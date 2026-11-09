"""Required-secrets checks (issue #51).

One placeholder rule (scripts/lib-install-safety.sh: is_placeholder_secret) is used by every
script that reads a secret. These tests never run install.sh or setup.sh and never touch a host.

Run with:  python3 -m pytest tests/python/ -v
"""
import glob
import os
import re
import subprocess
import sys

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LIB = os.path.join(REPO_ROOT, "scripts", "lib-install-safety.sh")
DEPLOY = os.path.join(REPO_ROOT, "scripts", "deploy-wazuh-dashboards.py")

PLACEHOLDERS = [
    "", "   ", "admin", "ADMIN", "changeme", "ChangeMe123", "CHANGEME_NOW", "your_password",
    "YOUR_PASSWORD", "Your-Password-Here", "<password>", "<your grafana password>", "example",
    "Example", "placeholder", "PLACEHOLDER", "xxx", "XXXXXXXX", "dp.st.your_token", "password",
]
REAL = ["correct-horse-battery", "k3Y!x9Qw7zLm2Rt", "exampleish-but-long-and-real"]


def _read(name):
    with open(os.path.join(REPO_ROOT, name), encoding="utf-8") as fh:
        return fh.read()


def _sh(snippet, *args, env=None):
    full_env = {"PATH": os.environ["PATH"]}
    full_env.update(env or {})
    return subprocess.run(
        ["bash", "-c", 'source "$1"; shift; ' + snippet, "bash", LIB, *args],
        env=full_env, capture_output=True, text=True, check=False,
    )


def test_placeholders_rejected():
    for bad in PLACEHOLDERS:
        assert _sh('is_placeholder_secret "$1"', bad).returncode == 0, repr(bad)
        assert _sh('require_secret MY_VAR "$1"', bad).returncode != 0, repr(bad)


def test_real_looking_values_accepted():
    for good in REAL:
        assert _sh('is_placeholder_secret "$1"', good).returncode != 0, good
        assert _sh('require_secret MY_VAR "$1"', good).returncode == 0, good


def test_unset_rejected():
    assert _sh("require_secret MY_VAR").returncode != 0


def test_error_names_variable_and_never_prints_value():
    for bad in ("changeme-SENTINEL-123", "YOUR_SENTINEL_TOKEN", "<SENTINEL>"):
        res = _sh('require_secret MY_VAR "$1"', bad)
        assert res.returncode != 0
        assert "MY_VAR" in res.stderr
        assert "SENTINEL" not in res.stdout + res.stderr
    # grafana_password_ok must not echo what it rejected either
    res = _sh('grafana_password_ok "$1"', "changeme-SENTINEL-123")
    assert res.returncode != 0
    assert "SENTINEL" not in res.stdout + res.stderr


def test_grafana_password_uses_the_one_rule():
    for bad in PLACEHOLDERS:
        assert _sh('grafana_password_ok "$1"', bad).returncode != 0, repr(bad)
    for good in REAL:
        assert _sh('grafana_password_ok "$1"', good).returncode == 0, good
    res = _sh('grafana_password_ok "$1"', "changeme", env={"INSECURE_OPEN_ACCESS": "true"})
    assert res.returncode == 0  # the single explicit opt-out


def test_grafana_error_names_the_config_variable():
    res = _sh('grafana_password_ok "$1" GRAFANA_ADMIN_PASS', "")
    assert res.returncode != 0 and "GRAFANA_ADMIN_PASS" in res.stderr


# ---- every script that reads a secret refuses the default ------------------

def test_no_script_defaults_a_grafana_password_to_admin():
    offenders = []
    for path in (glob.glob(os.path.join(REPO_ROOT, "*.sh")) + glob.glob(os.path.join(REPO_ROOT, "scripts", "*"))
                 + glob.glob(os.path.join(REPO_ROOT, "tests", "*.sh")) + [os.path.join(REPO_ROOT, "pfsense-siem")]):
        if os.path.isdir(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as fh:
            for n, line in enumerate(fh, 1):
                if re.search(r"(PASS|PASSWORD)[A-Z_]*:-admin", line):
                    offenders.append(f"{os.path.relpath(path, REPO_ROOT)}:{n}")
    assert offenders == []


def test_scripts_that_log_in_to_grafana_use_the_check():
    checked = 0
    for name in ("scripts/diagnose-and-repair.sh", "tests/test-panel-compatibility.sh"):
        src = _read(name)
        assert "lib-install-safety.sh" in src, name
        assert "grafana_password_ok" in src, name
        checked += 1
    assert checked == 2


def _run_deploy(env_extra, *args):
    env = {"PATH": os.environ["PATH"]}
    env.update(env_extra)
    return subprocess.run([sys.executable, "-I", DEPLOY, *args], env=env, capture_output=True,
                          text=True, check=False)


def test_deploy_wazuh_rejects_placeholder_and_empty_secrets():
    for bad in ("", "admin", "changeme", "YOUR_PASSWORD", "<pw>"):
        res = _run_deploy({"GRAFANA_PASS": bad, "WAZUH_INDEXER_PASS": "real-long-secret-1"})
        assert res.returncode != 0, repr(bad)
        assert "GRAFANA_PASS" in res.stderr
        res = _run_deploy({"GRAFANA_PASS": "real-long-secret-1", "WAZUH_INDEXER_PASS": bad})
        assert res.returncode != 0, repr(bad)
        assert "WAZUH_INDEXER_PASS" in res.stderr


def test_deploy_wazuh_error_never_prints_the_value():
    res = _run_deploy({"GRAFANA_PASS": "changeme-SENTINEL-123", "WAZUH_INDEXER_PASS": "x1y2z3-real-secret"})
    assert res.returncode != 0
    assert "SENTINEL" not in res.stdout + res.stderr


def test_deploy_wazuh_accepts_real_values_past_the_secret_check():
    # --help exits 0 before secrets matter; a real pair must get PAST the secret check, so the
    # failure (no Grafana at this address) is not a secret error.
    res = _run_deploy({"GRAFANA_PASS": "real-long-secret-1", "WAZUH_INDEXER_PASS": "real-long-secret-2"},
                      "--grafana", "http://127.0.0.1:9", "--verify-only")
    assert "password not set" not in res.stderr and "placeholder" not in res.stderr


# ---- the example file and docs -------------------------------------------

def test_example_config_carries_no_placeholder_secret():
    cfg = _read("config.env.example")
    for m in re.finditer(r"^#?\s*([A-Z_]*(?:PASS|PASSWORD|SECRET|TOKEN|KEY)[A-Z_]*)=(.*)$", cfg, re.M):
        value = m.group(2).strip()
        assert value == "" or value.startswith("<"), (m.group(1), "must be empty or an invalid marker")
    assert not re.search(r"=\s*changeme", cfg, re.I)  # no placeholder value (the rule may be named in a comment)
    assert "INFLUXDB_PASS" in cfg and re.search(r"Required|REQUIRED|required", cfg)


def test_docs_do_not_advertise_default_credentials():
    bad = re.compile(r"admin\s*/\s*admin|admin:admin|Password:\s*admin\b|SecretPassword|changeme(?![*`_])"
                     r"|Default credentials|`GRAFANA_ADMIN_PASS`\s*\|\s*`admin`", re.I)
    hits = []
    for path in glob.glob(os.path.join(REPO_ROOT, "**", "*.md"), recursive=True):
        rel = os.path.relpath(path, REPO_ROOT)
        if rel.startswith((".git", "build/")) or rel == "CHANGELOG.md":  # build/ is generated from these
            continue
        with open(path, encoding="utf-8") as fh:
            for n, line in enumerate(fh, 1):
                if bad.search(line) and "refuse" not in line.lower():
                    hits.append(f"{rel}:{n}")
    assert hits == []


def test_logstash_sample_password_is_not_admin():
    for name in ("config/logstash-suricata.conf", "config/README.md"):
        assert not re.search(r'password\s*=>\s*"admin"', _read(name)), name


def test_required_secrets_section_covers_every_secret():
    readme = _read("README.md")
    assert "## Required secrets" in readme
    section = readme.split("## Required secrets", 1)[1].split("\n## ", 1)[0]
    for name in ("GRAFANA_ADMIN_PASS", "INFLUXDB_PASS", "GRAFANA_PASS", "WAZUH_INDEXER_PASS",
                 "OpenSearch", "SSH"):
        assert name in section, name
    assert "INSECURE_OPEN_ACCESS" in section
    assert "## Required secrets" in _read("docs/reference/CONFIGURATION.md") or \
        "## Required secrets" in _read("docs/install/INSTALL_SIEM_STACK.md")


def test_bash_and_python_placeholder_rules_agree():
    sys.path.insert(0, os.path.join(REPO_ROOT, "scripts"))
    import importlib.util
    spec = importlib.util.spec_from_file_location("deploy_wazuh", DEPLOY)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    samples = PLACEHOLDERS + REAL + ["Changeme", "your_", "xx", "<>", "<a", "a>", " admin "]
    assert samples
    for v in samples:
        bash = _sh('is_placeholder_secret "$1"', v).returncode == 0
        assert bash == mod.is_placeholder_secret(v), repr(v)
