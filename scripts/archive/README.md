# Archived Scripts

This directory contains experimental and development scripts that were used during the initial setup and troubleshooting phases. These are kept for historical reference and learning purposes.

## Why These Scripts Were Archived

### Shell Script Forwarding Attempts (FAILED)
- `forward-suricata-eve-v2.sh` - Added timeout and logging (corrupted data)
- `forward-suricata-eve-direct-pipe.sh` - Attempted direct pipe without while loop (corrupted data)
- `forward-suricata-eve-socat.sh` - Tried using socat instead of nc (corrupted data)

**Lesson Learned**: Shell scripts with `tail | while read | nc` are fundamentally broken on pfSense. Python solution is the only reliable method.

### Logstash Configuration Experiments
- `fix-logstash-8x-opensearch.sh` - Attempted various Logstash 8.x configurations
- `fix-logstash-opensearch.sh` - Output plugin troubleshooting
- `fix-logstash-bulk-api.sh` - Bulk API configuration attempts
- `fix-logstash-http-output.sh` - HTTP output attempts before opensearch plugin
- `fix-logstash-permissions.sh` - Permission issues during installation
- `update-logstash-yml.sh` - Various logstash.yml configurations
- `upgrade-logstash-8x.sh` - Upgrade from 7.x to 8.x

**Lesson Learned**: Use `logstash-output-opensearch` plugin and parse from `[event][original]` field for UDP input.

### JSON Parsing Fixes
- `fix-json-parsing.sh` - Attempted to fix parsing failures
- `fix-suricata-field-structure.sh` - Field nesting experiments
- `fix-udp-buffer-size.sh` - UDP buffer tuning

**Lesson Learned**: UDP `codec => plain` populates `event.original`, not `message`. Parse from correct field.

### Dashboard Creation Attempts
- `create-suricata-dashboard.sh` - Early dashboard creation
- `create-final-dashboard.sh` - Later iteration
- `setup-grafana-dashboard-14893.sh` - Specific dashboard import
- `setup-grafana-manual.sh` - Manual setup scripts
- `setup-grafana-simple.sh` - Simplified approach
- `import-suricata-dashboard.sh` - Various import methods
- `import-suricata-dashboard-fixed.sh` - Fixed version
- `fix-dashboard-fields.sh` - Field mapping fixes
- `fix-dashboard-panels.sh` - Panel configuration fixes
- `fix-dashboard-variables.sh` - Variable setup attempts

**Lesson Learned**: Use grafana-opensearch-datasource plugin. Stat/pie charts don't work; use tables and timeseries.

### Index Management
- `create-suricata-index.sh` - Index template creation
- `setup-opensearch-dashboard.sh` - OpenSearch Dashboards (not needed)

### Graylog Attempts (ABANDONED)
- `setup-graylog-geoip.sh` - Graylog setup before switching to OpenSearch

**Lesson Learned**: Graylog was too complex for this use case. OpenSearch + Logstash + Grafana is simpler and works better.

### Debugging Scripts
- `debug-suricata-data.sh` - Data flow debugging
- `test-logstash-parsing.sh` - Parsing tests
- `verify-and-disable-debug.sh` - Debug mode cleanup

### Cleanup Scripts
- `cleanup-local-workspace.sh` - Clean development environment
- `cleanup-old-stack.sh` - Remove old components
- `cleanup-pfsense.sh` - Clean pfSense test scripts

### Installation Helpers
- `install-logstash-suricata.sh` - Early Logstash installation
- `install-reliable-forwarder.sh` - Attempt at reliable shell forwarder (failed)

## What Actually Worked

See the parent `scripts/` directory for the working scripts:
- `check-system-health.sh` - Comprehensive health check ✓
- `check-forwarder-status.sh` - pfSense forwarder status ✓
- `verify-suricata-data.sh` - End-to-end data verification ✓
- `restart-services.sh` - Service restart utility ✓
- `forward-suricata-eve-python.py` - **Python forwarder (THE SOLUTION)** ✓
- `suricata-forwarder-watchdog.sh` - Monitoring script ✓

## Key Takeaways

1. **Python > Shell Scripts** on pfSense for complex operations
2. **UDP codec behavior** requires parsing from `event.original`
3. **Grafana plugin compatibility** matters - use native datasource plugins
4. **Incremental testing** saves time - test each component separately
5. **Documentation** prevents repeating failed experiments

## Using These Scripts

**DO NOT USE** these scripts in production. They are here for reference only to show:
- What didn't work and why
- Evolution of the solution
- Common pitfalls to avoid

If you need functionality from these scripts, check if it's been incorporated into the working scripts in the parent directory.

## Script Count

- Total archived: 34 scripts
- Working scripts: 6 scripts + 3 pfSense scripts
- Success rate: ~18% (typical for experimental development)

---
Last Updated: 2025-11-24  
Status: Archived for historical reference
