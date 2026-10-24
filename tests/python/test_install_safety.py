"""Safe-default checks for the installer (issue #49).

These never run install.sh or setup.sh. They exercise the pure helpers in
scripts/lib-install-safety.sh through bash, and assert (grep-style) that the
installer scripts no longer carry the old open defaults.

Run with:  python3 -m pytest tests/python/ -v
"""
import os
import re
import subprocess

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LIB = os.path.join(REPO_ROOT, "scripts", "lib-install-safety.sh")


def _read(name):
    with open(os.path.join(REPO_ROOT, name), encoding="utf-8") as fh:
        return fh.read()


def _sh(snippet, env=None):
    """Source the helper library in a clean bash and run a snippet."""
    full_env = {"PATH": os.environ["PATH"]}
    full_env.update(env or {})
    return subprocess.run(
        ["bash", "-c", 'source "$1"; ' + snippet, "bash", LIB],
        env=full_env, capture_output=True, text=True, check=False,
    )


def _plan(env):
    res = _sh("firewall_plan", env)
    assert res.returncode == 0, res.stderr
    return [line.split("|") for line in res.stdout.splitlines() if line]


BASE = {
    "MONITOR_MODE": "both",
    "LOGSTASH_ALLOWED_SOURCES": "192.0.2.1",
    "GRAFANA_ALLOWED_SOURCES": "192.0.2.0/24, 198.51.100.7",
}


# ---- firewall plan ---------------------------------------------------------

def test_default_plan_has_no_open_rule_and_no_9200():
    rules = _plan(BASE)
    assert rules, "plan must not be empty"
    assert all(src != "any" for src, *_ in rules)
    assert all(port != "9200" for _, port, *_ in rules)
    ports = {(port, src) for src, port, *_ in rules}
    assert ("5140", "192.0.2.1") in ports
    assert ("8086", "192.0.2.1") in ports
    assert ("3000", "192.0.2.0/24") in ports
    assert ("3000", "198.51.100.7") in ports


def test_remote_opensearch_needs_named_sources():
    env = dict(BASE, OPENSEARCH_BIND="192.0.2.10", OPENSEARCH_DISABLE_SECURITY="true")
    res = _sh("firewall_plan", env)
    assert res.returncode != 0
    assert "OPENSEARCH_ALLOWED_SOURCES" in res.stderr

    env["OPENSEARCH_ALLOWED_SOURCES"] = "192.0.2.50"
    rules = _plan(env)
    assert ["192.0.2.50", "9200", "tcp"] == [r for r in rules if r[1] == "9200"][0][:3]


def test_grafana_sources_are_required():
    env = {k: v for k, v in BASE.items() if k != "GRAFANA_ALLOWED_SOURCES"}
    res = _sh("firewall_plan", env)
    assert res.returncode != 0
    assert "GRAFANA_ALLOWED_SOURCES" in res.stderr


def test_logstash_sources_are_required():
    env = {k: v for k, v in BASE.items() if k != "LOGSTASH_ALLOWED_SOURCES"}
    res = _sh("firewall_plan", env)
    assert res.returncode != 0
    assert "LOGSTASH_ALLOWED_SOURCES" in res.stderr


def test_invalid_source_is_rejected():
    # /1 to /7 cover at least 1/128 of the address space: as open as /0 in practice
    for bad in ("any", "0.0.0.0/0", "::/0", "128.0.0.0/1", "0.0.0.0/4", "2000::/3", "1.2.3.4; rm -rf /", "host name"):
        env = dict(BASE, GRAFANA_ALLOWED_SOURCES=bad)
        assert _sh("firewall_plan", env).returncode != 0, bad


def test_ordinary_lan_ranges_are_still_accepted():
    for good in ("192.0.2.0/24", "10.0.0.0/8", "198.51.100.7", "2001:db8::/32"):
        env = dict(BASE, GRAFANA_ALLOWED_SOURCES=good)
        assert _sh("firewall_plan", env).returncode == 0, good


def test_insecure_open_access_is_explicit_opt_in():
    rules = _plan(dict(BASE, INSECURE_OPEN_ACCESS="true"))
    assert any(src == "any" and port == "9200" for src, port, *_ in rules)
    assert any(src == "any" and port == "3000" for src, port, *_ in rules)


# ---- opensearch.yml --------------------------------------------------------

def test_default_opensearch_binds_loopback():
    res = _sh("render_opensearch_yml")
    assert res.returncode == 0, res.stderr
    assert "network.host: 127.0.0.1" in res.stdout
    assert "0.0.0.0" not in res.stdout


def test_remote_bind_without_security_optin_is_refused():
    res = _sh("render_opensearch_yml", {"OPENSEARCH_BIND": "192.0.2.10"})
    assert res.returncode != 0
    assert "OPENSEARCH_DISABLE_SECURITY" in res.stderr


def test_remote_bind_with_optin_is_rendered():
    res = _sh("render_opensearch_yml",
              {"OPENSEARCH_BIND": "192.0.2.10", "OPENSEARCH_DISABLE_SECURITY": "true"})
    assert res.returncode == 0, res.stderr
    assert "network.host: 192.0.2.10" in res.stdout
    assert "plugins.security.disabled: true" in res.stdout


def test_insecure_open_access_restores_old_yaml():
    res = _sh("render_opensearch_yml", {"INSECURE_OPEN_ACCESS": "true"})
    assert "network.host: 0.0.0.0" in res.stdout
    assert "plugins.security.disabled: true" in res.stdout


def test_bad_bind_value_rejected():
    assert _sh("render_opensearch_yml", {"OPENSEARCH_BIND": "x\nnetwork.host: 0.0.0.0"}).returncode != 0


# ---- Grafana password ------------------------------------------------------

def test_grafana_default_password_rejected():
    for bad in ("admin", "", "Admin", "ADMIN"):
        assert _sh('grafana_password_ok "$1"'.replace('"$1"', f"'{bad}'")).returncode != 0, bad
    assert _sh("grafana_password_ok 'correct-horse-battery'").returncode == 0
    assert _sh("grafana_password_ok 'short'").returncode != 0


def test_default_password_allowed_only_with_optin():
    res = _sh("grafana_password_ok admin", {"INSECURE_OPEN_ACCESS": "true"})
    assert res.returncode == 0


def test_generated_password_passes_check():
    res = _sh('p=$(generate_password) && grafana_password_ok "$p" && echo "$p"')
    assert res.returncode == 0, res.stderr
    assert len(res.stdout.strip()) >= 20


# ---- installer scripts must not carry the old defaults ---------------------

def test_install_sh_has_no_open_defaults():
    src = _read("install.sh")
    assert not re.search(r"^\s*network\.host:\s*0\.0\.0\.0", src, re.M)
    assert "plugins.security.disabled: true" not in src
    assert not re.search(r"ufw allow (9200|5140|3000|8086)", src)
    assert "leave empty for 'admin'" not in src
    assert not re.search(r"GRAFANA_PASSWORD:-admin", src)
    assert "lib-install-safety.sh" in src


def test_setup_sh_does_not_default_grafana_password():
    src = _read("setup.sh")
    assert not re.search(r"GRAFANA_ADMIN_PASS:-admin", src)
    assert "grafana_password_ok" in src


def test_example_config_has_no_admin_password_and_documents_optins():
    cfg = _read("config.env.example")
    assert not re.search(r"^GRAFANA_ADMIN_PASS=admin\s*$", cfg, re.M)
    for var in ("OPENSEARCH_BIND", "OPENSEARCH_ALLOWED_SOURCES",
                "LOGSTASH_ALLOWED_SOURCES", "GRAFANA_ALLOWED_SOURCES",
                "INSECURE_OPEN_ACCESS"):
        assert var in cfg, var
    assert re.search(r"^#?\s*INSECURE_OPEN_ACCESS=false", cfg, re.M)
