#!/bin/bash
# =============================================================================
# SIEM freshness check — exits non-zero when the newest Suricata event in
# OpenSearch is older than a threshold. Catches a silently dead forwarder,
# Logstash or OpenSearch (one went unnoticed for 2.5 months).
#
# Usage: scripts/check-siem-freshness.sh [--max-age MINUTES] [--via-pfsense]
#   --max-age N      Alert threshold in minutes (default 15)
#   --via-pfsense    Query OpenSearch from the pfSense box over SSH (use when
#                    this machine cannot reach OpenSearch directly)
#
# Reads config.env (SIEM_HOST, OPENSEARCH_PORT, INDEX_PREFIX, PFSENSE_HOST,
# PFSENSE_USER) from the repo root, or the environment.
# Exit codes: 0 fresh, 1 stale or no events, 2 could not query.
# Cron example (on the SIEM host):
#   */10 * * * * /opt/pfsense-siem-stack/scripts/check-siem-freshness.sh || logger -t siem-fresh "Suricata events stale"
# =============================================================================
set -euo pipefail

MAX_AGE=15
VIA_PFSENSE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-age) MAX_AGE="${2:?--max-age needs minutes}"; shift 2 ;;
        --via-pfsense) VIA_PFSENSE=true; shift ;;
        -h | --help) sed -n '2,19p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done
[[ "$MAX_AGE" =~ ^[0-9]+$ ]] || { echo "--max-age must be a whole number of minutes" >&2; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
[[ -f "$ROOT/config.env" ]] && source "$ROOT/config.env"
SIEM_HOST="${SIEM_HOST:?Set SIEM_HOST in config.env}"
OPENSEARCH_PORT="${OPENSEARCH_PORT:-9200}"
INDEX_PREFIX="${INDEX_PREFIX:-suricata}"
URL="http://${SIEM_HOST}:${OPENSEARCH_PORT}/${INDEX_PREFIX}-*/_search?size=1&sort=@timestamp:desc&_source=@timestamp"

if [[ "$VIA_PFSENSE" == true ]]; then
    PFSENSE_HOST="${PFSENSE_HOST:?Set PFSENSE_HOST in config.env}"
    RESP=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "${PFSENSE_USER:-admin}@${PFSENSE_HOST}" "curl -s -m 10 '${URL}'" 2>/dev/null) || RESP=""
else
    RESP=$(curl -s -m 10 "$URL") || RESP=""
fi
[[ -n "$RESP" ]] || { echo "UNKNOWN: no response from OpenSearch at ${SIEM_HOST}:${OPENSEARCH_PORT}" >&2; exit 2; }

python3 -I -c '
import json, sys, datetime
max_age = int(sys.argv[1])
try:
    hits = json.loads(sys.stdin.read())["hits"]["hits"]
except Exception as e:
    print(f"UNKNOWN: unreadable OpenSearch response ({e})"); sys.exit(2)
if not hits:
    print("STALE: no Suricata events found at all"); sys.exit(1)
ts = hits[0]["_source"]["@timestamp"].replace("Z", "+00:00")
age = (datetime.datetime.now(datetime.timezone.utc) - datetime.datetime.fromisoformat(ts)).total_seconds() / 60
if age > max_age:
    print(f"STALE: newest Suricata event is {age:.0f} min old (limit {max_age})"); sys.exit(1)
print(f"OK: newest Suricata event is {age:.1f} min old (limit {max_age})")
' "$MAX_AGE" <<<"$RESP"
