# CrowdSec Phase 1 for pfSense SIEM Stack

## Why

CrowdSec can aggregate repeated hostile behavior and produce ban decisions with TTL, reducing noisy one-off firewall events.

## pfSense Work Items

1. Install CrowdSec package/plugin in pfSense.
2. Configure log acquisition from firewall/auth logs.
3. Enable remediation component (bouncer) and log processor.
4. Use short ban TTL first (for example 1h) and review false positives.
5. Keep an emergency disable toggle documented.

## Installation (pfSense)

Reference: CrowdSec pfSense install doc

```bash
fetch https://raw.githubusercontent.com/crowdsecurity/pfSense-pkg-crowdsec/refs/heads/main/install-crowdsec.sh
sh install-crowdsec.sh
```

After install:

- Go to `Services/CrowdSec`
- Enable:
	- Remediation Component
	- Log Processor
	- Local API (recommended if hardware supports it)
- Save

Notes:

- Do not manually start services outside pfSense service controls unless troubleshooting.
- If using RAM disk for `/var`, disable Local API or ensure persistent storage for CrowdSec DB under `/var/db`.

## Integration Targets

- Forward CrowdSec alerts/decisions to central SIEM (`siem-docker-stack`).
- Add metadata fields required by Wazuh decoder/rules.
- Expose decision metrics to Grafana.

## Validation Checklist

- Decisions appear in CrowdSec local API.
- pfSense alias updates reflect active decisions.
- Wazuh receives parsed CrowdSec events.
- Grafana panel shows scenario and decision trends.

## Validation Commands

```bash
# Show active decisions with context
cscli decisions list -a

# Verify blocked tables
pfctl -T show -t crowdsec_blacklists
pfctl -T show -t crowdsec6_blacklists

# Controlled end-to-end test ban (from a non-critical source IP)
cscli decisions add -t ban -d 2m -i <YOUR_TEST_IP>
```

Expected result for test ban:

- Test client loses firewall access during the 2-minute window
- Decision appears in CrowdSec status page and CLI
- Event is visible in SIEM ingestion path

## Rollback

- Disable bouncer enforcement only (keep detect mode if desired).
- Revert alias update automation.
- Keep SIEM ingestion active for tuning.

Emergency rollback steps:

1. Disable remediation component in `Services/CrowdSec`.
2. Confirm block tables drain/stop updating.
3. Keep log processor enabled to continue collecting decision telemetry.
