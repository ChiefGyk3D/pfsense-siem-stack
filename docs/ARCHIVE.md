# Archived Material

Superseded documentation, scripts, dashboards, and plugins are no longer kept in the
working tree — they live in **git history**. This keeps the repository focused on the
current, supported deployment while preserving everything for anyone who wants to dig
into how the stack evolved.

## Where to find it

The last commit that contains all archived material is:

```
6529c5bc6b1883c46d87b6ee2bbb4239bb4e2ce5
```

To browse or recover anything from the archives:

```bash
# List everything that existed at that commit
git ls-tree -r --name-only 6529c5bc6b1883c46d87b6ee2bbb4239bb4e2ce5

# View a single archived file
git show 6529c5bc6b1883c46d87b6ee2bbb4239bb4e2ce5:docs/archive/GRAYLOG_SURICATA_SETUP.md

# Check out the whole tree at that point in time
git checkout 6529c5bc6b1883c46d87b6ee2bbb4239bb4e2ce5 -- docs/archive scripts/archive
```

## What was removed

| Path | Contents |
|------|----------|
| `docs/archive/` | Old Graylog setup guides, superseded troubleshooting checklists, dashboard improvement plans, pre-rebrand README/QUICK_START versions, and reorganization session logs |
| `scripts/archive/` | ~40 one-off fix/debug scripts from the original Logstash/Grafana bring-up (dashboard field fixes, Logstash 8.x migration helpers, old forwarder variants) |
| `dashboards/archive/` | Historical Grafana dashboard JSON exports superseded by the current `dashboards/*.json` |
| `plugins/Old/` | Legacy Python 2 / PHP Telegraf gateway plugins and a compiled Go binary (`telegraf_netifinfo_plugin`) |
| `docs/DOCUMENTATION_UPDATE_SUMMARY.md`, `docs/OVERHAUL_SUMMARY.md`, `docs/SESSION_SUMMARY.md` | Historical work-session summaries describing past documentation passes |

## Notes

- The abandoned **Graylog** exploration is summarized in
  [siem/graylog/README.md](siem/graylog/README.md); the original guides
  (`GRAYLOG_INDEX.md`, `GRAYLOG_SURICATA_SETUP.md`) are only in git history at the
  commit above.
- Nothing in the archives is needed for a current deployment. Start from the
  [Documentation Index](DOCUMENTATION_INDEX.md) instead.
