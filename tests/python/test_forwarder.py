"""Unit tests for scripts/forward-suricata-eve.py.

The forwarder is designed to run on pfSense, but its core logic — log tailing
with rotation detection, GeoIP enrichment, and UDP event formatting — is pure
Python and testable anywhere. maxminddb is intentionally NOT required: the
module degrades gracefully without it, and these tests stub the GeoIP reader
directly so CI needs no GeoIP database.

Run with:  python3 -m pytest tests/python/ -v
"""
import importlib.util
import json
import os
import threading
import time

import pytest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FORWARDER_PATH = os.path.join(REPO_ROOT, "scripts", "forward-suricata-eve.py")


def _load_forwarder():
    spec = importlib.util.spec_from_file_location("forward_suricata_eve", FORWARDER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def fwd():
    """Import the forwarder module once (import has no fatal side effects)."""
    return _load_forwarder()


class FakeSocket:
    """Captures UDP sendto() calls."""

    def __init__(self):
        self.sent = []
        self.event = threading.Event()

    def sendto(self, payload, addr):
        self.sent.append((payload, addr))
        self.event.set()

    def wait_for_messages(self, count, timeout=10.0):
        deadline = time.monotonic() + timeout
        while len(self.sent) < count and time.monotonic() < deadline:
            time.sleep(0.02)
        return len(self.sent) >= count


def _start_tail(fwd, path, sock, monkeypatch):
    """Run tail_log_file against a temp file in a daemon thread."""
    # Rotation checks normally happen after ~5s idle; make them near-instant.
    monkeypatch.setattr(fwd, "ROTATION_CHECK_CYCLES", 1)
    t = threading.Thread(target=fwd.tail_log_file, args=(str(path), sock), daemon=True)
    t.start()
    return t


def _append_event(path, event):
    with open(path, "a") as f:
        f.write(json.dumps(event) + "\n")
        f.flush()
        os.fsync(f.fileno())


# ── Event forwarding & formatting ────────────────────────────────────────────

class TestEventForwarding:
    def test_event_forwarded_as_json_udp_payload(self, fwd, tmp_path, monkeypatch):
        eve = tmp_path / "iface0" / "eve.json"
        eve.parent.mkdir()
        eve.write_text("")  # forwarder tails from EOF
        sock = FakeSocket()
        _start_tail(fwd, eve, sock, monkeypatch)
        time.sleep(0.5)  # let the tail thread open the file

        event = {"timestamp": "2026-08-29T00:00:00", "event_type": "alert",
                 "src_ip": "10.0.0.1", "dest_ip": "10.0.0.2"}
        _append_event(eve, event)

        assert sock.wait_for_messages(1), "event was not forwarded"
        payload, addr = sock.sent[0]
        assert isinstance(payload, bytes)
        assert json.loads(payload.decode("utf-8")) == event
        assert addr == (fwd.SIEM_HOST, fwd.LOGSTASH_PORT)

    def test_bad_json_lines_are_skipped(self, fwd, tmp_path, monkeypatch):
        eve = tmp_path / "iface0" / "eve.json"
        eve.parent.mkdir()
        eve.write_text("")
        sock = FakeSocket()
        _start_tail(fwd, eve, sock, monkeypatch)
        time.sleep(0.5)

        with open(eve, "a") as f:
            f.write("this is not json\n")
        _append_event(eve, {"event_type": "flow"})

        assert sock.wait_for_messages(1)
        # Only the valid event arrives; the garbage line is dropped, not fatal.
        assert json.loads(sock.sent[0][0]) == {"event_type": "flow"}
        assert len(sock.sent) == 1


# ── Log rotation handling ────────────────────────────────────────────────────

class TestLogRotation:
    def test_inode_change_reopens_and_keeps_forwarding(self, fwd, tmp_path, monkeypatch):
        """File replaced by rotation (new inode) → forwarder reopens it."""
        eve = tmp_path / "wan" / "eve.json"
        eve.parent.mkdir()
        eve.write_text("")
        sock = FakeSocket()
        _start_tail(fwd, eve, sock, monkeypatch)
        time.sleep(0.5)

        _append_event(eve, {"seq": 1})
        assert sock.wait_for_messages(1), "pre-rotation event not forwarded"

        # Simulate rotation: rename the old file away and create a fresh one.
        os.rename(eve, tmp_path / "wan" / "eve.json.2026_0829")
        eve.write_text("")

        # After reopen the forwarder tails from EOF of the NEW file. Keep
        # appending until one lands (covers the detect/reopen race).
        got_post_rotation = False
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            _append_event(eve, {"seq": 2})
            before = len(sock.sent)
            time.sleep(0.3)
            if len(sock.sent) > before:
                got_post_rotation = True
                break
        assert got_post_rotation, "no events forwarded after inode rotation"
        assert json.loads(sock.sent[-1][0])["seq"] == 2

    def test_truncation_reseeks_to_end(self, fwd, tmp_path, monkeypatch):
        """File truncated in place (same inode) → forwarder reseeks, no crash."""
        eve = tmp_path / "lan" / "eve.json"
        eve.parent.mkdir()
        eve.write_text("")
        sock = FakeSocket()
        _start_tail(fwd, eve, sock, monkeypatch)
        time.sleep(0.5)

        # Push the read position forward, then truncate below it.
        for i in range(20):
            _append_event(eve, {"seq": i, "pad": "x" * 200})
        assert sock.wait_for_messages(20), "pre-truncation events not forwarded"

        with open(eve, "w") as f:  # truncate to 0, same inode
            f.truncate(0)

        got_post_truncation = False
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            _append_event(eve, {"seq": "post-truncate"})
            before = len(sock.sent)
            time.sleep(0.3)
            if len(sock.sent) > before:
                got_post_truncation = True
                break
        assert got_post_truncation, "no events forwarded after truncation"
        assert json.loads(sock.sent[-1][0])["seq"] == "post-truncate"


# ── GeoIP enrichment ─────────────────────────────────────────────────────────

class FakeGeoReader:
    """Stand-in for maxminddb.Reader — no database file needed."""

    def __init__(self, record):
        self.record = record
        self.queries = []

    def get(self, ip):
        self.queries.append(ip)
        return self.record


CITY_RECORD = {
    "country": {"iso_code": "DE", "names": {"en": "Germany"}},
    "continent": {"code": "EU"},
    "city": {"names": {"en": "Berlin"}},
    "location": {"latitude": 52.52, "longitude": 13.405},
    "subdivisions": [{"names": {"en": "Berlin"}}],
}


class TestGeoIPEnrichment:
    def test_no_database_is_a_safe_noop(self, fwd, monkeypatch):
        """No GeoIP DB (the CI case) → events pass through unchanged, no crash."""
        monkeypatch.setattr(fwd, "geoip_reader", None)
        event = {"src_ip": "8.8.8.8", "dest_ip": "1.1.1.1", "event_type": "alert"}
        result = fwd.enrich_geoip(dict(event))
        assert result == event
        assert fwd._lookup_geoip("8.8.8.8") is None

    def test_public_ips_enriched_with_flat_geo_fields(self, fwd, monkeypatch):
        reader = FakeGeoReader(CITY_RECORD)
        monkeypatch.setattr(fwd, "geoip_reader", reader)
        event = fwd.enrich_geoip({"src_ip": "93.184.216.34", "dest_ip": "10.0.0.5"})

        geo = event["geoip_src"]
        assert geo["country_code"] == "DE"
        assert geo["country_name"] == "Germany"
        assert geo["continent_code"] == "EU"
        assert geo["city_name"] == "Berlin"
        assert geo["region_name"] == "Berlin"
        # GeoJSON order [lon, lat] for OpenSearch geo_point
        assert geo["location"] == [13.405, 52.52]
        # dest is RFC1918 → never looked up, never enriched
        assert "geoip_dest" not in event
        assert reader.queries == ["93.184.216.34"]

    def test_private_reserved_and_invalid_ips_skipped(self, fwd, monkeypatch):
        reader = FakeGeoReader(CITY_RECORD)
        monkeypatch.setattr(fwd, "geoip_reader", reader)
        for ip in ("192.168.1.1", "10.1.2.3", "127.0.0.1", "fe80::1", "not-an-ip", ""):
            assert fwd._lookup_geoip(ip) is None, ip
        assert reader.queries == []

    def test_reader_exception_does_not_crash(self, fwd, monkeypatch):
        class ExplodingReader:
            def get(self, ip):
                raise RuntimeError("corrupt database")

        monkeypatch.setattr(fwd, "geoip_reader", ExplodingReader())
        event = {"src_ip": "8.8.8.8"}
        result = fwd.enrich_geoip(dict(event))
        assert result == event  # lookup failure → no enrichment, no exception

    def test_empty_record_returns_none(self, fwd, monkeypatch):
        monkeypatch.setattr(fwd, "geoip_reader", FakeGeoReader({}))
        assert fwd._lookup_geoip("8.8.8.8") is None


# ── Helpers ──────────────────────────────────────────────────────────────────

class TestHelpers:
    def test_is_private_ip(self, fwd):
        assert fwd.is_private_ip("192.168.0.1")
        assert fwd.is_private_ip("172.16.5.5")
        assert fwd.is_private_ip("127.0.0.1")
        assert fwd.is_private_ip("garbage")  # invalid treated as private (skip)
        assert not fwd.is_private_ip("8.8.8.8")
        assert not fwd.is_private_ip("2001:4860:4860::8888")

    def test_get_inode(self, fwd, tmp_path):
        p = tmp_path / "f"
        p.write_text("x")
        assert fwd._get_inode(str(p)) == os.stat(p).st_ino
        assert fwd._get_inode(str(tmp_path / "missing")) is None
