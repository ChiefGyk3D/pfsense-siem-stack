#!/bin/bash
# =============================================================================
# Preflight checks for the pfSense SIEM Stack
# =============================================================================
#
# Run this BEFORE install.sh / setup.sh to catch configuration and connectivity
# problems early. Safe to run repeatedly; makes no changes to any host.
#
# Checks:
#   1. config.env exists and defines the required variables
#   2. SSH reachability to pfSense (key-based, BatchMode)
#   3. SSH reachability to the SIEM server (warning only — setup.sh can fall
#      back to manual Logstash deployment)
#   4. python3 present on pfSense (needed by the forwarder)
#   5. OpenSearch port reachable (warning only — it won't exist before install.sh)
#   6. GeoIP database present on pfSense (warning only — enrichment is optional)
#
# Exit status: 0 = all hard checks passed, 1 = at least one hard failure.
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${REPO_DIR}/config.env"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

PASS=0
WARNINGS=0
FAILURES=0

ok()   { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS+1)); }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; WARNINGS=$((WARNINGS+1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; FAILURES=$((FAILURES+1)); }

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)

echo ""
echo -e "${BLUE}── pfSense SIEM Stack Preflight ──${NC}"
echo ""

# ── 1. Configuration ─────────────────────────────────────────────────────────
if [[ ! -f "$CONFIG_FILE" ]]; then
    fail "config.env not found at ${CONFIG_FILE}"
    echo "      Create it first:  cp config.env.example config.env && nano config.env"
    echo ""
    echo -e "  ${RED}Preflight failed${NC} (cannot continue without config.env)"
    exit 1
fi
ok "config.env found"

# shellcheck source=/dev/null
source "$CONFIG_FILE"

if [[ -n "${SIEM_HOST:-}" ]]; then
    ok "SIEM_HOST set (${SIEM_HOST})"
else
    fail "SIEM_HOST not set in config.env"
fi

if [[ -n "${PFSENSE_HOST:-}" ]]; then
    ok "PFSENSE_HOST set (${PFSENSE_HOST})"
else
    fail "PFSENSE_HOST not set in config.env"
fi

if [[ -n "${PFSENSE_USER:-}" ]]; then
    ok "PFSENSE_USER set (${PFSENSE_USER})"
else
    PFSENSE_USER="admin"
    warn "PFSENSE_USER not set — defaulting to 'admin' (pfSense's default admin account)"
fi

if [[ -n "${SIEM_SSH_USER:-}" ]]; then
    ok "SIEM_SSH_USER set (${SIEM_SSH_USER})"
else
    SIEM_SSH_USER="$(whoami)"
    warn "SIEM_SSH_USER not set — defaulting to current user '${SIEM_SSH_USER}'"
fi

if [[ "$FAILURES" -gt 0 ]]; then
    echo ""
    echo -e "  ${RED}Preflight failed${NC} — fix config.env before continuing"
    exit 1
fi

OPENSEARCH_PORT="${OPENSEARCH_PORT:-9200}"

# ── 2. SSH to pfSense ────────────────────────────────────────────────────────
echo ""
PFSENSE_SSH_OK=false
if ssh "${SSH_OPTS[@]}" "${PFSENSE_USER}@${PFSENSE_HOST}" 'echo ok' &>/dev/null; then
    ok "SSH to pfSense OK (${PFSENSE_USER}@${PFSENSE_HOST})"
    PFSENSE_SSH_OK=true
else
    fail "Cannot SSH to ${PFSENSE_USER}@${PFSENSE_HOST} (key-based auth required)"
    echo "      Enable SSH: pfSense → System → Advanced → Secure Shell"
    echo "      Install your key:  ssh-copy-id ${PFSENSE_USER}@${PFSENSE_HOST}"
fi

# ── 3. SSH to SIEM server ────────────────────────────────────────────────────
if ssh "${SSH_OPTS[@]}" "${SIEM_SSH_USER}@${SIEM_HOST}" 'echo ok' &>/dev/null; then
    ok "SSH to SIEM server OK (${SIEM_SSH_USER}@${SIEM_HOST})"
else
    warn "Cannot SSH to ${SIEM_SSH_USER}@${SIEM_HOST} — setup.sh will skip automatic Logstash deployment"
    echo "      (Fine if you run setup.sh directly ON the SIEM server, or deploy Logstash config manually)"
fi

# ── 4. Python on pfSense ─────────────────────────────────────────────────────
if [[ "$PFSENSE_SSH_OK" == true ]]; then
    PFSENSE_PYTHON=$(ssh "${SSH_OPTS[@]}" "${PFSENSE_USER}@${PFSENSE_HOST}" \
        'for p in /usr/local/bin/python3.11 /usr/local/bin/python3 /usr/bin/python3; do [ -x "$p" ] && echo "$p" && break; done' 2>/dev/null)
    if [[ -n "$PFSENSE_PYTHON" ]]; then
        ok "python3 on pfSense (${PFSENSE_PYTHON})"
    else
        fail "python3 not found on pfSense (required by the forwarder)"
        echo "      Install:  ssh ${PFSENSE_USER}@${PFSENSE_HOST} 'pkg install python311'"
    fi
else
    fail "python3 check on pfSense skipped (no SSH access)"
fi

# ── 5. OpenSearch reachability ───────────────────────────────────────────────
if curl -sf --max-time 5 "http://${SIEM_HOST}:${OPENSEARCH_PORT}" &>/dev/null; then
    ok "OpenSearch reachable at http://${SIEM_HOST}:${OPENSEARCH_PORT}"
else
    warn "OpenSearch not reachable at http://${SIEM_HOST}:${OPENSEARCH_PORT}"
    echo "      Expected if you have not run install.sh yet; required before setup.sh"
fi

# ── 6. GeoIP database on pfSense (optional) ──────────────────────────────────
if [[ "$PFSENSE_SSH_OK" == true ]]; then
    GEOIP_FOUND=$(ssh "${SSH_OPTS[@]}" "${PFSENSE_USER}@${PFSENSE_HOST}" '
        for db in /usr/local/share/ntopng/GeoLite2-City.mmdb \
                  /usr/local/share/suricata/GeoLite2/GeoLite2-City.mmdb \
                  /usr/local/share/suricata/GeoLite2/GeoLite2-Country.mmdb \
                  /usr/local/share/GeoIP/GeoLite2-City.mmdb \
                  /usr/local/share/GeoIP/GeoLite2-Country.mmdb \
                  /var/db/GeoIP/GeoLite2-City.mmdb; do
            [ -f "$db" ] && echo "$db" && break
        done' 2>/dev/null)
    if [[ -n "$GEOIP_FOUND" ]]; then
        ok "GeoIP database on pfSense (${GEOIP_FOUND})"
    else
        warn "No GeoIP database found on pfSense — events will not be geo-enriched"
        echo "      See docs/install/GEOIP_SETUP.md (optional, needed for the attack map)"
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
if [[ "$FAILURES" -gt 0 ]]; then
    echo -e "  ${RED}Preflight failed:${NC} ${FAILURES} hard failure(s), ${WARNINGS} warning(s), ${PASS} passed"
    exit 1
fi
if [[ "$WARNINGS" -gt 0 ]]; then
    echo -e "  ${YELLOW}Preflight passed with ${WARNINGS} warning(s)${NC} (${PASS} checks passed)"
else
    echo -e "  ${GREEN}Preflight passed${NC} (${PASS} checks passed)"
fi
exit 0
