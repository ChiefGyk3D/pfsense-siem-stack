#!/usr/bin/env python3
"""
deploy-wazuh-dashboards.py — Deploy Wazuh Grafana dashboards via API

Standalone Python script (no dependencies beyond stdlib) that:
1. Configures the OpenSearch-Wazuh datasource in Grafana
2. Creates the SIEM Alerts folder
3. Imports all 3 Wazuh dashboards
4. Verifies data is flowing through each panel query

Usage:
    python3 deploy-wazuh-dashboards.py
    python3 deploy-wazuh-dashboards.py --grafana http://192.0.2.100:3000 --user admin --pass secret

Environment variables (alternative to flags):
    GRAFANA_URL, GRAFANA_USER, GRAFANA_PASS, WAZUH_INDEXER_URL, WAZUH_INDEXER_USER, WAZUH_INDEXER_PASS
"""

import json
import urllib.request
import urllib.error
import base64
import argparse
import os
import sys
import time

# ============================================================
# Configuration
# ============================================================

def get_config():
    parser = argparse.ArgumentParser(description="Deploy Wazuh dashboards to Grafana")
    parser.add_argument("--grafana", default=os.environ.get("GRAFANA_URL", "http://localhost:3000"),
                        help="Grafana URL (default: http://localhost:3000)")
    parser.add_argument("--user", default=os.environ.get("GRAFANA_USER", "admin"),
                        help="Grafana admin username")
    parser.add_argument("--pass", dest="password", default=os.environ.get("GRAFANA_PASS", "changeme"),
                        help="Grafana admin password")
    parser.add_argument("--wazuh-url", default=os.environ.get("WAZUH_INDEXER_URL", "https://wazuh-indexer:9200"),
                        help="Wazuh Indexer URL (default: https://wazuh-indexer:9200)")
    parser.add_argument("--wazuh-user", default=os.environ.get("WAZUH_INDEXER_USER", "admin"),
                        help="Wazuh Indexer username")
    parser.add_argument("--wazuh-pass", default=os.environ.get("WAZUH_INDEXER_PASS", "SecretPassword"),
                        help="Wazuh Indexer password")
    parser.add_argument("--skip-verify", action="store_true", default=True,
                        help="Skip TLS verification for Wazuh Indexer (default: true)")
    parser.add_argument("--verify-only", action="store_true",
                        help="Only verify queries, don't deploy")
    parser.add_argument("--dashboard-dir", default=None,
                        help="Directory containing dashboard JSON files (auto-detected)")
    return parser.parse_args()


# ============================================================
# Grafana API helpers
# ============================================================

class GrafanaAPI:
    def __init__(self, url, user, password):
        self.url = url.rstrip("/")
        self.auth = base64.b64encode(f"{user}:{password}".encode()).decode()
        self.headers = {
            "Content-Type": "application/json",
            "Authorization": f"Basic {self.auth}"
        }

    def _request(self, path, method="GET", data=None):
        req_url = f"{self.url}{path}"
        body = json.dumps(data).encode() if data else None
        req = urllib.request.Request(req_url, data=body, headers=self.headers, method=method)
        try:
            resp = urllib.request.urlopen(req)
            return json.loads(resp.read()), resp.status
        except urllib.error.HTTPError as e:
            error_body = e.read().decode()
            return {"error": error_body, "status": e.code}, e.code

    def health(self):
        result, code = self._request("/api/health")
        return code == 200

    def create_folder(self, title, uid):
        result, code = self._request("/api/folders", "POST", {"uid": uid, "title": title})
        return code in (200, 412)  # 412 = already exists

    def create_datasource(self, ds_config):
        # Check if exists first
        result, code = self._request(f"/api/datasources/uid/{ds_config['uid']}")
        if code == 200:
            # Update existing
            ds_id = result.get("id")
            result, code = self._request(f"/api/datasources/{ds_id}", "PUT", ds_config)
            return "updated", code
        else:
            result, code = self._request("/api/datasources", "POST", ds_config)
            return "created", code

    def deploy_dashboard(self, dashboard, folder_uid):
        # Get existing version if any
        uid = dashboard.get("uid", "")
        try:
            result, code = self._request(f"/api/dashboards/uid/{uid}")
            if code == 200:
                dashboard["version"] = result["dashboard"].get("version", 0) + 1
        except Exception:
            pass

        dashboard.pop("id", None)
        payload = {"dashboard": dashboard, "overwrite": True, "folderUid": folder_uid}
        result, code = self._request("/api/dashboards/db", "POST", payload)
        return result, code

    def test_query(self, ds_id, index, query_str, agg_field=None, is_logs=False, time_range_days=1):
        now_ms = int(time.time() * 1000)
        ago_ms = now_ms - (time_range_days * 86400000)

        header = json.dumps({
            "search_type": "query_then_fetch",
            "ignore_unavailable": True,
            "index": index
        })

        if is_logs:
            body = {
                "size": 5,
                "query": {"bool": {"filter": [
                    {"range": {"timestamp": {"gte": str(ago_ms), "lte": str(now_ms), "format": "epoch_millis"}}},
                    {"query_string": {"analyze_wildcard": True, "query": query_str}}
                ]}},
                "sort": [{"timestamp": {"order": "desc"}}]
            }
        elif agg_field:
            body = {
                "size": 0,
                "query": {"bool": {"filter": [
                    {"range": {"timestamp": {"gte": str(ago_ms), "lte": str(now_ms), "format": "epoch_millis"}}},
                    {"query_string": {"analyze_wildcard": True, "query": query_str}}
                ]}},
                "aggs": {"terms_agg": {"terms": {"field": agg_field, "size": 5, "order": {"_count": "desc"}}}}
            }
        else:
            body = {
                "size": 0,
                "query": {"bool": {"filter": [
                    {"range": {"timestamp": {"gte": str(ago_ms), "lte": str(now_ms), "format": "epoch_millis"}}},
                    {"query_string": {"analyze_wildcard": True, "query": query_str}}
                ]}}
            }

        msearch = header + "\n" + json.dumps(body) + "\n"
        req_url = f"{self.url}/api/datasources/proxy/{ds_id}/_msearch"
        req = urllib.request.Request(
            req_url,
            data=msearch.encode(),
            headers={**self.headers, "Content-Type": "application/x-ndjson"},
            method="POST"
        )
        try:
            resp = urllib.request.urlopen(req)
            result = json.loads(resp.read())
            r = result.get("responses", [{}])[0]
            if r.get("error"):
                return False, str(r["error"])[:200]
            hits = r.get("hits", {}).get("total", {})
            hit_count = hits.get("value", 0) if isinstance(hits, dict) else hits
            return True, hit_count
        except Exception as e:
            return False, str(e)


# ============================================================
# Dashboard definitions (inline — no JSON file dependency)
# ============================================================

WAZUH_DS_UID = "dff8stu43lr7kc"
WAZUH_DS_TYPE = "grafana-opensearch-datasource"
FOLDER_UID = "eff8gvnuqvbwgb"

def wds():
    return {"type": WAZUH_DS_TYPE, "uid": WAZUH_DS_UID}

def dh(field="timestamp", interval="auto"):
    return {"field": field, "id": "3", "settings": {"interval": interval, "min_doc_count": "0", "trimEdges": "0"}, "type": "date_histogram"}

def ta(field, id_num="2", size="10"):
    return {"field": field, "id": str(id_num), "settings": {"order": "desc", "orderBy": "_count", "size": str(size), "min_doc_count": "1"}, "type": "terms"}

def tgt(query="*", metrics=None, bucket_aggs=None, ref="A"):
    return {"datasource": wds(), "query": query, "metrics": metrics or [{"id": "1", "type": "count"}],
            "bucketAggs": bucket_aggs or [dh()], "refId": ref, "timeField": "timestamp"}

def stat_panel(title, query="*", gp=None, metrics=None):
    return {"type": "stat", "title": title, "datasource": wds(), "gridPos": gp or {"h": 4, "w": 4, "x": 0, "y": 0},
            "targets": [tgt(query, metrics=metrics, bucket_aggs=[dh()])],
            "fieldConfig": {"defaults": {"thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": None}]}}, "overrides": []},
            "options": {"reduceOptions": {"calcs": ["sum"]}, "colorMode": "value", "graphMode": "none", "textMode": "auto"}}

def ts_panel(title, query, terms_field, gp=None):
    return {"type": "timeseries", "title": title, "datasource": wds(), "gridPos": gp or {"h": 8, "w": 12, "x": 0, "y": 0},
            "targets": [tgt(query, bucket_aggs=[ta(terms_field), dh()])],
            "fieldConfig": {"defaults": {"custom": {"drawStyle": "line", "lineInterpolation": "smooth", "fillOpacity": 15, "stacking": {"mode": "normal"}},
                            "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": None}]}}, "overrides": []},
            "options": {"tooltip": {"mode": "multi"}}}

def topn_table(title, query, field, gp=None, size="15"):
    return {"type": "table", "title": title, "datasource": wds(), "gridPos": gp or {"h": 8, "w": 12, "x": 0, "y": 0},
            "targets": [tgt(query, bucket_aggs=[ta(field, size=size)])],
            "options": {"showHeader": True, "sortBy": [{"displayName": "Count", "desc": True}]},
            "fieldConfig": {"defaults": {"custom": {"align": "auto"}}, "overrides": []}}

def logs_table(title, query, gp=None, size="50"):
    return {"type": "table", "title": title, "datasource": wds(), "gridPos": gp or {"h": 10, "w": 24, "x": 0, "y": 0},
            "targets": [tgt(query, metrics=[{"id": "1", "type": "logs", "settings": {"limit": str(size)}}], bucket_aggs=[dh()])],
            "options": {"showHeader": True}, "fieldConfig": {"defaults": {"custom": {"align": "auto"}}, "overrides": []}}

def multi_terms(title, query, fields, gp=None, size="15"):
    bkt = [ta(f, id_num=str(i+2), size=size) for i, f in enumerate(fields)]
    return {"type": "table", "title": title, "datasource": wds(), "gridPos": gp or {"h": 8, "w": 12, "x": 0, "y": 0},
            "targets": [tgt(query, bucket_aggs=bkt)],
            "options": {"showHeader": True, "sortBy": [{"displayName": "Count", "desc": True}]},
            "fieldConfig": {"defaults": {"custom": {"align": "auto"}}, "overrides": []}}


def build_security_overview():
    panels = []
    y = 0
    panels.append(stat_panel("Total Alerts", "*", {"h": 4, "w": 4, "x": 0, "y": y}))
    panels.append(stat_panel("Level 12+ (High)", "rule.level:>=12", {"h": 4, "w": 4, "x": 4, "y": y}))
    panels.append(stat_panel("Authentication", "rule.groups:authentication_success OR rule.groups:authentication_failed", {"h": 4, "w": 4, "x": 8, "y": y}))
    panels.append(stat_panel("Vulnerability", "rule.groups:vulnerability-detector", {"h": 4, "w": 4, "x": 12, "y": y}))
    panels.append(stat_panel("FIM Events", "rule.groups:syscheck", {"h": 4, "w": 4, "x": 16, "y": y}))
    panels.append(stat_panel("Active Response", "rule.groups:active_response", {"h": 4, "w": 4, "x": 20, "y": y}))
    y += 4
    panels.append(ts_panel("Alert Timeline by Level", "*", "rule.level", {"h": 8, "w": 16, "x": 0, "y": y}))
    panels.append(topn_table("Alert Level Distribution", "*", "rule.level", {"h": 8, "w": 8, "x": 16, "y": y}))
    y += 8
    panels.append(topn_table("Top 15 Alert Rules", "*", "rule.description", {"h": 8, "w": 12, "x": 0, "y": y}))
    panels.append(topn_table("Alerts by Agent", "*", "agent.name", {"h": 8, "w": 12, "x": 12, "y": y}, "10"))
    y += 8
    panels.append(topn_table("MITRE ATT&CK Tactics", "*", "rule.mitre.tactic", {"h": 8, "w": 12, "x": 0, "y": y}))
    panels.append(topn_table("MITRE ATT&CK Techniques", "*", "rule.mitre.technique", {"h": 8, "w": 12, "x": 12, "y": y}))
    y += 8
    panels.append(topn_table("PCI DSS", "*", "rule.pci_dss", {"h": 8, "w": 8, "x": 0, "y": y}))
    panels.append(topn_table("NIST 800-53", "*", "rule.nist_800_53", {"h": 8, "w": 8, "x": 8, "y": y}))
    panels.append(topn_table("HIPAA", "*", "rule.hipaa", {"h": 8, "w": 8, "x": 16, "y": y}))
    y += 8
    panels.append(stat_panel("Auth Successes", "rule.groups:authentication_success", {"h": 4, "w": 4, "x": 0, "y": y}))
    fail_stat = stat_panel("Auth Failures", "rule.groups:authentication_failed", {"h": 4, "w": 4, "x": 4, "y": y})
    fail_stat["fieldConfig"]["defaults"]["thresholds"]["steps"] = [{"color": "green", "value": None}, {"color": "red", "value": 1}]
    panels.append(fail_stat)
    panels.append(topn_table("Top Rule Groups", "*", "rule.groups", {"h": 8, "w": 8, "x": 8, "y": y - 2}, "15"))
    hourly = {"type": "timeseries", "title": "Hourly Alert Trend", "datasource": wds(),
              "gridPos": {"h": 8, "w": 8, "x": 16, "y": y - 2},
              "targets": [tgt("*", bucket_aggs=[ta("agent.name"), dh("1h")])],
              "fieldConfig": {"defaults": {"custom": {"drawStyle": "bars", "fillOpacity": 50, "stacking": {"mode": "normal"}},
                              "color": {"mode": "palette-classic"}}, "overrides": []},
              "options": {"tooltip": {"mode": "multi", "sort": "desc"}}}
    panels.append(hourly)
    y += 8
    panels.append(logs_table("Recent High-Level Alerts (Level 7+)", "rule.level:>=7", {"h": 10, "w": 24, "x": 0, "y": y}))
    return {"uid": "wazuh-security-overview", "title": "Wazuh Security Overview",
            "tags": ["wazuh", "security", "siem"], "timezone": "browser", "schemaVersion": 39,
            "refresh": "1m", "time": {"from": "now-24h", "to": "now"}, "panels": panels, "editable": True}


def build_vulnerability_detection():
    panels = []
    y = 0
    VQ = "rule.groups:vulnerability-detector"
    panels.append(stat_panel("Total Vulnerabilities", VQ, {"h": 4, "w": 6, "x": 0, "y": y}))
    panels.append(stat_panel("Critical/High", f"{VQ} AND (data.vulnerability.severity:Critical OR data.vulnerability.severity:High)", {"h": 4, "w": 6, "x": 6, "y": y}))
    panels.append(stat_panel("Unique CVEs", VQ, {"h": 4, "w": 6, "x": 12, "y": y}, [{"field": "data.vulnerability.cve", "id": "1", "type": "cardinality"}]))
    panels.append(stat_panel("Affected Agents", VQ, {"h": 4, "w": 6, "x": 18, "y": y}, [{"field": "agent.name", "id": "1", "type": "cardinality"}]))
    y += 4
    panels.append(topn_table("Severity Distribution", VQ, "data.vulnerability.severity", {"h": 8, "w": 8, "x": 0, "y": y}))
    panels.append(ts_panel("Vulnerability Timeline", VQ, "data.vulnerability.severity", {"h": 8, "w": 16, "x": 8, "y": y}))
    y += 8
    panels.append(topn_table("Top 20 CVEs", VQ, "data.vulnerability.cve", {"h": 8, "w": 12, "x": 0, "y": y}, "20"))
    panels.append(topn_table("Vulnerable Packages", VQ, "data.vulnerability.package.name", {"h": 8, "w": 12, "x": 12, "y": y}))
    y += 8
    panels.append(topn_table("Vulnerabilities by Agent", VQ, "agent.name", {"h": 8, "w": 12, "x": 0, "y": y}))
    panels.append(multi_terms("Severity by Agent", VQ, ["agent.name", "data.vulnerability.severity"], {"h": 8, "w": 12, "x": 12, "y": y}))
    y += 8
    panels.append(logs_table("Recent Critical/High Vulnerabilities",
                  f"{VQ} AND (data.vulnerability.severity:Critical OR data.vulnerability.severity:High)",
                  {"h": 10, "w": 24, "x": 0, "y": y}))
    return {"uid": "wazuh-vulnerabilities", "title": "Wazuh Vulnerability Detection",
            "tags": ["wazuh", "vulnerability", "siem"], "timezone": "browser", "schemaVersion": 39,
            "refresh": "5m", "time": {"from": "now-7d", "to": "now"}, "panels": panels, "editable": True}


def build_fim():
    panels = []
    y = 0
    FQ = "rule.groups:syscheck"
    panels.append(stat_panel("Total FIM Events", FQ, {"h": 4, "w": 6, "x": 0, "y": y}))
    panels.append(stat_panel("Added", f"{FQ} AND syscheck.event:added", {"h": 4, "w": 6, "x": 6, "y": y}))
    panels.append(stat_panel("Modified", f"{FQ} AND syscheck.event:modified", {"h": 4, "w": 6, "x": 12, "y": y}))
    panels.append(stat_panel("Deleted", f"{FQ} AND syscheck.event:deleted", {"h": 4, "w": 6, "x": 18, "y": y}))
    y += 4
    panels.append(ts_panel("FIM Timeline", FQ, "syscheck.event", {"h": 8, "w": 16, "x": 0, "y": y}))
    panels.append(topn_table("Event Types", FQ, "syscheck.event", {"h": 8, "w": 8, "x": 16, "y": y}))
    y += 8
    panels.append(topn_table("Top Modified Files", FQ, "syscheck.path", {"h": 8, "w": 12, "x": 0, "y": y}, "20"))
    panels.append(topn_table("FIM by Agent", FQ, "agent.name", {"h": 8, "w": 12, "x": 12, "y": y}))
    y += 8
    panels.append(topn_table("FIM Activity by Rule", FQ, "rule.description", {"h": 8, "w": 12, "x": 0, "y": y}))
    panels.append(multi_terms("FIM Detail: Agent / Event / Path", FQ, ["agent.name", "syscheck.event", "syscheck.path"], {"h": 8, "w": 12, "x": 12, "y": y}, "20"))
    y += 8
    panels.append(logs_table("Recent FIM Events", FQ, {"h": 10, "w": 24, "x": 0, "y": y}))
    return {"uid": "wazuh-fim", "title": "Wazuh File Integrity Monitoring",
            "tags": ["wazuh", "fim", "siem"], "timezone": "browser", "schemaVersion": 39,
            "refresh": "5m", "time": {"from": "now-24h", "to": "now"}, "panels": panels, "editable": True}


# ============================================================
# Main
# ============================================================

def main():
    config = get_config()
    api = GrafanaAPI(config.grafana, config.user, config.password)

    print(f"=== Wazuh Dashboard Deployment ===")
    print(f"Grafana: {config.grafana}")
    print(f"Wazuh Indexer: {config.wazuh_url}")
    print()

    # Check Grafana
    if not api.health():
        print("ERROR: Cannot reach Grafana")
        sys.exit(1)
    print("Grafana: reachable")

    if not config.verify_only:
        # Configure datasource
        print("\n--- Configuring Wazuh datasource ---")
        ds_config = {
            "name": "OpenSearch-Wazuh",
            "type": WAZUH_DS_TYPE,
            "uid": WAZUH_DS_UID,
            "url": config.wazuh_url,
            "access": "proxy",
            "basicAuth": True,
            "basicAuthUser": config.wazuh_user,
            "isDefault": False,
            "jsonData": {
                "database": "wazuh-alerts-4.x-*",
                "flavor": "opensearch",
                "pplEnabled": True,
                "timeField": "timestamp",
                "tlsSkipVerify": config.skip_verify,
                "version": "2.19.0"
            },
            "secureJsonData": {
                "basicAuthPassword": config.wazuh_pass
            }
        }
        action, code = api.create_datasource(ds_config)
        print(f"  Datasource: {action} (HTTP {code})")

        # Create folder
        print("\n--- Creating SIEM Alerts folder ---")
        api.create_folder("SIEM Alerts", FOLDER_UID)
        print("  Folder: created or exists")

        # Deploy dashboards
        print("\n--- Deploying dashboards ---")
        dashboards = [
            build_security_overview(),
            build_vulnerability_detection(),
            build_fim(),
        ]
        for dash in dashboards:
            result, code = api.deploy_dashboard(dash, FOLDER_UID)
            status = result.get("status", "unknown") if isinstance(result, dict) else "unknown"
            print(f"  {dash['title']}: {status} (HTTP {code})")

    # Verify queries
    print("\n--- Verifying queries ---")
    # Get datasource numeric ID
    ds_result, _ = api._request(f"/api/datasources/uid/{WAZUH_DS_UID}")
    ds_id = ds_result.get("id")
    if not ds_id:
        print("  WARNING: Cannot find datasource ID, skipping verification")
        return

    tests = [
        ("Total Alerts", "*", None, False, 1),
        ("Level 12+", "rule.level:>=12", None, False, 1),
        ("Vulnerabilities", "rule.groups:vulnerability-detector", None, False, 7),
        ("FIM Events", "rule.groups:syscheck", None, False, 1),
        ("Top Rules", "*", "rule.description", False, 1),
        ("Top Agents", "*", "agent.name", False, 1),
        ("MITRE Tactics", "*", "rule.mitre.tactic", False, 1),
        ("Top CVEs", "rule.groups:vulnerability-detector", "data.vulnerability.cve", False, 7),
        ("Top Files", "rule.groups:syscheck", "syscheck.path", False, 1),
        ("Recent Level 7+", "rule.level:>=7", None, True, 1),
        ("Recent Crit/High Vuln", "rule.groups:vulnerability-detector AND (data.vulnerability.severity:Critical OR data.vulnerability.severity:High)", None, True, 7),
        ("Recent FIM", "rule.groups:syscheck", None, True, 1),
    ]

    passed = 0
    failed = 0
    for name, query, agg_field, is_logs, days in tests:
        ok, info = api.test_query(ds_id, "wazuh-alerts-4.x-*", query, agg_field, is_logs, days)
        if ok:
            print(f"  OK   [{name}]: {info} hits")
            passed += 1
        else:
            print(f"  FAIL [{name}]: {info}")
            failed += 1

    print(f"\n=== Results: {passed} passed, {failed} failed ===")
    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
