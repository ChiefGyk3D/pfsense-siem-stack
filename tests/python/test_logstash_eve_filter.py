"""Checks for the Logstash Eve pipeline (issue #49, threat t_spoof).

The pipeline must not let a UDP sender write to pipeline-owned fields. The
Logstash binary is not required: the config structure is checked by text, and
the inline ruby filters are extracted and run under plain ruby against a small
Event stub. Tests skip nothing; they fail if ruby is missing.

Run with:  python3 -m pytest tests/python/ -v
"""
import json
import os
import re
import shutil
import subprocess

import pytest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CONF = os.path.join(REPO_ROOT, "config", "logstash-suricata.conf")

HARNESS = r'''
require "json"
require "time"
class Time; def time; self; end; end
class Event
  def initialize(h); @d = h; end
  def path(f); f.gsub(/\A\[|\]\z/, "").split("]["); end
  def get(f)
    cur = @d
    path(f).each { |p| return nil unless cur.is_a?(Hash); cur = cur[p] }
    cur
  end
  def set(f, v)
    ks = path(f); cur = @d
    ks[0..-2].each { |p| cur[p] = {} unless cur[p].is_a?(Hash); cur = cur[p] }
    cur[ks[-1]] = v
  end
  def remove(f)
    ks = path(f); cur = @d
    ks[0..-2].each { |p| return nil unless cur[p].is_a?(Hash); cur = cur[p] }
    cur.delete(ks[-1])
  end
  def to_hash; @d.reject { |k, _| k == "@metadata" }; end
  def to_h; @d; end
end
inp = JSON.parse(STDIN.read)
steps = inp["steps"]
ev = Event.new(inp["event"])
steps.each do |s|
  eval(s["init"]) if s["init"]
  eval("lambda { |event| #{s["code"]} }").call(ev)
end
puts JSON.generate(ev.to_h)
'''


def _conf():
    with open(CONF, encoding="utf-8") as fh:
        return fh.read()


def _ruby_blocks(text):
    """Return [{init, code}] for each ruby filter, in file order."""
    blocks = []
    for m in re.finditer(r"ruby\s*\{(.*?)\n\s*\}\s*\n", text, re.S):
        body = m.group(1)
        code = re.search(r"code\s*=>\s*'(.*?)'\s*(?:\n|$)", body, re.S)
        init = re.search(r"init\s*=>\s*'(.*?)'\s*\n", body, re.S)
        assert code, "ruby block without a single-quoted code string"
        blocks.append({"init": init.group(1) if init else None, "code": code.group(1)})
    return blocks


def _run(steps, event):
    assert shutil.which("ruby"), "ruby is required to run the filter tests"
    res = subprocess.run(
        ["ruby", "-e", HARNESS],
        input=json.dumps({"steps": steps, "event": event}),
        capture_output=True, text=True, check=False,
    )
    assert res.returncode == 0, res.stderr
    return json.loads(res.stdout)


def _validate(eve, steps=None):
    """Run the validate/copy ruby step on an event whose parsed JSON is `eve`."""
    blocks = _ruby_blocks(_conf())
    assert blocks, "no ruby filter found in the pipeline"
    ev = {"message": "raw", "tags": [], "@timestamp": "RECEIVE",
          "@metadata": {"eve": eve}}
    return _run(steps or blocks[:1], ev)


GOOD = {
    "timestamp": "2025-11-27T12:00:00.000000-0500",
    "flow_id": 123456789,
    "in_iface": "igc0",
    "event_type": "alert",
    "src_ip": "203.0.113.5", "src_port": 4444,
    "dest_ip": "192.0.2.10", "dest_port": 443,
    "proto": "TCP", "app_proto": "tls",
    "alert": {"action": "blocked", "gid": 1, "signature_id": 2100498, "rev": 7,
              "signature": "GPL ATTACK_RESPONSE id check returned root",
              "category": "Potentially Bad Traffic", "severity": 2,
              "metadata": {"tag": ["x"], "created_at": ["2010_09_23"]}},
    "geoip_src": {"country_code": "US", "location": [-97.8, 37.7]},
    "flow": {"pkts_toserver": 3, "bytes_toserver": 200},
    "dns": {"rrname": "example.test", "rrtype": "A"},
    "http": {"hostname": "example.test", "status": 200, "length": 12},
}


def _quarantined(out):
    return bool(out["@metadata"].get("quarantine_reason"))


# ---- structure --------------------------------------------------------------

def test_json_filter_never_parses_to_event_root():
    text = _conf()
    blocks = re.findall(r"\bjson\s*\{(.*?)\}", text, re.S)
    assert blocks, "expected at least one json filter"
    for b in blocks:
        assert re.search(r'target\s*=>\s*"\[@metadata\]\[eve\]"', b), b


def test_quarantine_output_is_separate_and_outside_suricata_pattern():
    text = _conf()
    idx = re.findall(r'index\s*=>\s*"([^"]+)"', text)
    assert len(idx) == 2, idx
    quarantine = [i for i in idx if "quarantine" in i]
    main = [i for i in idx if "quarantine" not in i]
    assert len(quarantine) == 1 and len(main) == 1
    # dashboards and the retention script read suricata-*; quarantine must not match
    assert not quarantine[0].startswith("suricata-")
    assert main[0].startswith("suricata-")
    assert re.search(r"if\s+\[@metadata\]\[quarantine_reason\]", text)


def test_reserved_names_are_not_in_the_allow_list():
    text = _conf()
    m = re.search(r"allowed\s*=\s*%w\[(.*?)\]", text, re.S)
    assert m, "allow-list not found"
    allowed = set(m.group(1).split())
    assert {"event_type", "src_ip", "dest_ip", "alert", "in_iface"} <= allowed
    for reserved in ("@timestamp", "@version", "@metadata", "tags", "host",
                     "message", "event", "log", "agent", "ecs", "input", "data_stream"):
        assert reserved not in allowed


# ---- behavior ---------------------------------------------------------------

def test_valid_event_passes_with_dashboard_fields_at_root():
    out = _validate(GOOD)
    assert not _quarantined(out)
    for k in ("event_type", "src_ip", "dest_ip", "src_port", "dest_port", "proto",
              "in_iface", "alert", "geoip_src", "flow", "dns", "http", "timestamp"):
        assert out[k] == GOOD[k], k
    assert out["alert"]["severity"] == 2


def test_sender_cannot_overwrite_pipeline_owned_fields():
    evil = dict(GOOD)
    evil.update({"@timestamp": "1999-01-01T00:00:00Z", "@version": "9",
                 "tags": ["trusted"], "host": {"ip": "10.9.9.9"},
                 "message": "x", "event": {"original": "y"},
                 "@metadata": {"index_date": "../../evil", "quarantine_reason": None},
                 "log": {"file": "z"}, "unlisted": 1})
    out = _validate(evil)
    assert not _quarantined(out)
    assert out["@timestamp"] == "RECEIVE"
    assert out["tags"] == []
    assert out["message"] == "raw"
    for k in ("@version", "host", "event", "log", "unlisted"):
        assert k not in out, k
    assert "index_date" not in out["@metadata"]


@pytest.mark.parametrize("patch", [
    {"event_type": "ALERT; drop"},
    {"event_type": 7},
    {"event_type": None},
    {"src_ip": "not-an-ip"},
    {"dest_ip": "192.0.2.0/24"},
    {"src_ip": ["1.2.3.4"]},
    {"src_port": 70000},
    {"dest_port": "443"},
    {"in_iface": "../x"},
    {"in_iface": "a" * 200},
    {"proto": {"a": 1}},
    {"timestamp": "yesterday"},
    {"alert": "string"},
    {"alert": dict(GOOD["alert"], severity="high")},
    {"alert": dict(GOOD["alert"], action="whatever")},
    {"alert": dict(GOOD["alert"], signature="s" * 5000)},
    {"geoip_src": {"location": "here"}},
    {"flow": {"pkts_toserver": "many"}},
    {"http": {"status": "200"}},
    {"dns": {"bad key!": "x"}},
])
def test_malformed_events_are_quarantined(patch):
    evil = dict(GOOD)
    evil.update(patch)
    out = _validate(evil)
    assert _quarantined(out), patch
    assert "event_type" not in out or out.get("event_type") is None
    assert "alert" not in out


def test_non_object_json_and_missing_event_type_are_quarantined():
    assert _quarantined(_validate([1, 2, 3]))
    assert _quarantined(_validate("str"))
    no_type = {k: v for k, v in GOOD.items() if k != "event_type"}
    assert _quarantined(_validate(no_type))


def test_deep_or_wide_payloads_are_quarantined():
    deep = {"x": 1}
    for _ in range(20):
        deep = {"n": deep}
    assert _quarantined(_validate(dict(GOOD, dns=deep)))
    assert _quarantined(_validate(dict(GOOD, dns={"l": list(range(1000))})))


def test_timestamp_range_check_quarantines_forged_times():
    blocks = _ruby_blocks(_conf())
    assert len(blocks) >= 3, "expected validate, time-range and quarantine steps"
    # _run's Event stub keeps @timestamp as a Time for the range step
    for ts, bad in (("2001-01-01T00:00:00Z", True), ("2999-01-01T00:00:00Z", True),
                    (None, False)):
        ev = {"message": "raw", "tags": [], "@metadata": {"eve": GOOD}}
        steps = blocks[:1] + [{"init": None, "code":
            'event.set("@timestamp", %s)' % ("Time.now" if ts is None
                                              else 'Time.parse("%s")' % ts)}] + blocks[1:2]
        out = _run(steps, ev)
        assert _quarantined(out) == bad, ts


def test_quarantine_event_keeps_only_truncated_raw_and_reason():
    blocks = _ruby_blocks(_conf())
    ev = {"message": "A" * 9000, "tags": ["_jsonparsefailure"], "src_ip": "1.1.1.1",
          "@metadata": {"quarantine_reason": "bad_event_type"}}
    out = _run(blocks[-1:], ev)
    assert len(out["message"]) <= 2048
    assert out["eve_quarantine_reason"] == "bad_event_type"
    assert "src_ip" not in out


def test_guard_bites_on_a_naive_root_parse():
    """Negative case: the checks above must fail for a pipeline that copies keys to root."""
    naive = [{"init": None, "code":
              'event.get("[@metadata][eve]").each { |k, v| event.set(k, v) }'}]
    out = _validate(dict(GOOD, tags=["trusted"], **{"@timestamp": "forged"}), naive)
    assert out["tags"] == ["trusted"] and out["@timestamp"] == "forged"
