#!/bin/bash
# Safe-default helpers shared by install.sh and setup.sh (issue #49).
# Source this file; it defines functions only and runs nothing.
#
# Settings (environment or config.env):
#   OPENSEARCH_BIND             address OpenSearch listens on (default 127.0.0.1)
#   OPENSEARCH_ALLOWED_SOURCES  IPs/CIDRs allowed to reach 9200; required if the bind is not loopback
#   OPENSEARCH_DISABLE_SECURITY must be "true" to run a non-loopback bind (the installer does not
#                               provision the OpenSearch security plugin, so the API is unauthenticated)
#   LOGSTASH_ALLOWED_SOURCES    IPs/CIDRs allowed to send UDP 5140 (and 8086); required
#   GRAFANA_ALLOWED_SOURCES     IPs/CIDRs allowed to reach Grafana; required
#   INSECURE_OPEN_ACCESS        "true" restores the old behavior: 0.0.0.0, no source limits, default password

_lis_err() { echo "ERROR: $*" >&2; }

_lis_true() { [[ "${1:-}" == "true" ]]; }

# Print each IP/CIDR in a comma/space separated list, one per line.
# Fails on empty input, on anything that is not an IP or CIDR, and on a
# match-everything network (/0), which is the same as no restriction.
normalize_sources() {
    local list="${1:-}" item out=0
    list="${list//,/ }"
    for item in $list; do
        if ! [[ "$item" =~ ^[0-9A-Fa-f:.]+(/[0-9]{1,3})?$ ]] || [[ "$item" == */0 ]] ||
            [[ "$item" == "0.0.0.0" || "$item" == "::" ]]; then
            _lis_err "invalid or match-everything source '$item' (use an IP or CIDR such as 192.0.2.0/24)"
            return 1
        fi
        echo "$item"
        out=1
    done
    [[ $out -eq 1 ]]
}

is_loopback_addr() {
    [[ "$1" == "127.0.0.1" || "$1" == "::1" || "$1" == "localhost" || "$1" == 127.* ]]
}

# Resolve the OpenSearch bind address.
resolve_opensearch_bind() {
    local bind
    if _lis_true "${INSECURE_OPEN_ACCESS:-}"; then
        echo "0.0.0.0"
        return 0
    fi
    bind="${OPENSEARCH_BIND:-127.0.0.1}"
    if ! [[ "$bind" =~ ^[0-9A-Fa-f:.]+$ ]]; then
        _lis_err "OPENSEARCH_BIND '$bind' is not an IP address"
        return 1
    fi
    echo "$bind"
}

# Print opensearch.yml for the current settings.
render_opensearch_yml() {
    local bind security_line=""
    bind=$(resolve_opensearch_bind) || return 1
    if is_loopback_addr "$bind" || _lis_true "${INSECURE_OPEN_ACCESS:-}" ||
        _lis_true "${OPENSEARCH_DISABLE_SECURITY:-}"; then
        security_line="plugins.security.disabled: true"
    else
        _lis_err "OPENSEARCH_BIND=$bind is not loopback and the installer does not configure the OpenSearch security plugin."
        _lis_err "Set OPENSEARCH_DISABLE_SECURITY=true to accept an unauthenticated API on that address (source-limited by ufw), or keep the default 127.0.0.1."
        return 1
    fi
    cat <<EOF
cluster.name: pfsense-monitoring
node.name: siem-node-1
path.data: /opt/opensearch/data
path.logs: /opt/opensearch/logs
network.host: $bind
http.port: 9200
discovery.type: single-node
$security_line
EOF
}

# Print the ufw rules to add as SRC|PORT|PROTO|COMMENT (SRC "any" only with INSECURE_OPEN_ACCESS).
firewall_plan() {
    local bind src
    bind=$(resolve_opensearch_bind) || return 1
    if _lis_true "${INSECURE_OPEN_ACCESS:-}"; then
        echo "any|9200|tcp|OpenSearch HTTP (INSECURE_OPEN_ACCESS)"
        echo "any|5140|udp|Logstash Suricata input (INSECURE_OPEN_ACCESS)"
        if [[ "${MONITOR_MODE:-}" == "telegraf" || "${MONITOR_MODE:-}" == "both" ]]; then
            echo "any|8086|tcp|Logstash Telegraf input (INSECURE_OPEN_ACCESS)"
        fi
        echo "any|3000|tcp|Grafana Web UI (INSECURE_OPEN_ACCESS)"
        return 0
    fi

    local ls_src gf_src os_src=""
    if ! ls_src=$(normalize_sources "${LOGSTASH_ALLOWED_SOURCES:-}"); then
        _lis_err "LOGSTASH_ALLOWED_SOURCES is required: the pfSense address(es) that send events"
        return 1
    fi
    if ! gf_src=$(normalize_sources "${GRAFANA_ALLOWED_SOURCES:-}"); then
        _lis_err "GRAFANA_ALLOWED_SOURCES is required: the admin workstation address(es) or LAN CIDR"
        return 1
    fi
    if ! is_loopback_addr "$bind"; then
        if ! os_src=$(normalize_sources "${OPENSEARCH_ALLOWED_SOURCES:-}"); then
            _lis_err "OPENSEARCH_ALLOWED_SOURCES is required when OPENSEARCH_BIND is not loopback"
            return 1
        fi
        while IFS= read -r src; do echo "$src|9200|tcp|OpenSearch HTTP"; done <<<"$os_src"
    fi
    while IFS= read -r src; do
        echo "$src|5140|udp|Logstash Suricata input"
        if [[ "${MONITOR_MODE:-}" == "telegraf" || "${MONITOR_MODE:-}" == "both" ]]; then
            echo "$src|8086|tcp|Logstash Telegraf input"
        fi
    done <<<"$ls_src"
    while IFS= read -r src; do echo "$src|3000|tcp|Grafana Web UI"; done <<<"$gf_src"
}

# Succeeds if the password is acceptable for Grafana.
grafana_password_ok() {
    local pw="${1:-}"
    if [[ "${pw,,}" == "admin" || -z "$pw" ]]; then
        _lis_true "${INSECURE_OPEN_ACCESS:-}" && return 0
        _lis_err "the Grafana admin password must be set and must not be 'admin'"
        return 1
    fi
    if [[ ${#pw} -lt 8 ]]; then
        _lis_err "the Grafana admin password must be at least 8 characters"
        return 1
    fi
}

generate_password() {
    # 24 URL-safe characters from the kernel CSPRNG
    head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24
    echo
}

# Read KEY=VALUE for the listed keys from a config file WITHOUT executing it,
# exporting only those not already set in the environment.
load_safety_config() {
    local file="$1" key val
    [[ -f "$file" ]] || return 0
    for key in OPENSEARCH_BIND OPENSEARCH_ALLOWED_SOURCES OPENSEARCH_DISABLE_SECURITY \
        LOGSTASH_ALLOWED_SOURCES GRAFANA_ALLOWED_SOURCES INSECURE_OPEN_ACCESS; do
        [[ -n "${!key:-}" ]] && continue
        val=$(grep -E "^${key}=" "$file" | tail -1 | cut -d= -f2-)
        val="${val%\"}"
        val="${val#\"}"
        val="${val%\'}"
        val="${val#\'}"
        [[ -n "$val" ]] && export "${key}=${val}"
    done
    return 0
}
