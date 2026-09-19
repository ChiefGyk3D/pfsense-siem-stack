# Project Roadmap

> **pfSense SIEM Stack** — pfSense telemetry (Suricata, pfBlockerNG, Telegraf) into an OpenSearch/Grafana SIEM.

This is the single roadmap for the project. The changelog ([CHANGELOG.md](CHANGELOG.md)) records what shipped; this document records what's next and why. It was last reworked after a full stack review on 2026-08-29.

---

## 🧭 Where this project fits

This repo is one of three related projects:

| Repo | Role |
|------|------|
| [pfsense-siem-stack](https://github.com/ChiefGyk3D/pfsense-siem-stack) (this repo) | pfSense-side integration: Suricata forwarder, Telegraf plugins, SID tuning, dashboards, plus a standalone bare-metal SIEM installer |
| [siem-docker-stack](https://github.com/ChiefGyk3D/siem-docker-stack) | Dockerized SIEM/SOAR backend: OpenSearch hot/warm, Logstash, Grafana, Wazuh, syslog-ng, n8n SOAR |
| [jumpcloud-wazuh-bridge](https://github.com/ChiefGyk3D/jumpcloud-wazuh-bridge) | JumpCloud IdP events into Wazuh |

**Strategic direction (decision needed):** this repo's `install.sh` builds a bare-metal OpenSearch/Logstash/Grafana stack that duplicates what siem-docker-stack now does better (hot/warm tiers, ISM lifecycle, Wazuh). The recommended path is to make **siem-docker-stack the canonical backend** and focus this repo on what only it does: the pfSense-side forwarder, Telegraf plugins, Suricata tuning content, and dashboards. `install.sh` would remain as a documented standalone alternative, not the flagship. The cross-stack game plan lives in [siem-docker-stack/docs/game-plan.md](https://github.com/ChiefGyk3D/siem-docker-stack/blob/master/docs/game-plan.md).

---

## ✅ What works today

- **Multi-interface Suricata monitoring** — 15 instances (2 WAN inline IPS + 13 VLAN IDS)
- **Log forwarder** (`scripts/forward-suricata-eve.py`) — inode-aware rotation handling, GeoIP enrichment, multi-threaded, watchdog + rc.d service
- **OpenSearch/Logstash pipeline** — **flat** root-level EVE fields (not nested under `suricata.eve.*`), index templates (geo_point, pfBlockerNG keywords), ISM retention
- **Dashboards** — Suricata WAN + per-interface, pfSense/pfBlockerNG, Prometheus, Docker, Windows Exporter, and **3 Wazuh dashboards** (security overview, vulnerability detection, FIM) with a deploy script (`scripts/deploy-wazuh-dashboards.py`)
- **SID management** — curated disable/drop/suppress lists (`config/sid/`)
- **Automation** — `install.sh` (server), `setup.sh` (deployment), `pfsense-siem` menu console, 17 operational scripts

> Note: Wazuh dashboards **ship today** — earlier docs describing Wazuh as "planned" were stale. Graylog support was explored and abandoned (superseded guides live in git history — see [docs/ARCHIVE.md](docs/ARCHIVE.md)).

---

## 🔥 Phase A — Hardening & correctness (now)

Fixing what the 2026-08 review found. Items marked ✅ landed with the review PR.

- [x] `install.sh`: allow SSH before `ufw enable` (remote lockout risk)
- [x] `setup.sh`: fix `set -e` + `((ERRORS++))` interaction that aborted deployment on the first recoverable warning
- [x] `install.sh`: stop masking failures (exit code passthrough), protect the temp credentials file
- [x] `deploy-wazuh-dashboards.py`: TLS verification was impossible to enable (`--skip-verify` defaulted true); credentials via env instead of CLI
- [x] Stop using `GRAFANA_ADMIN_USER` as the SSH login in `diagnose-and-repair.sh`
- [x] Fix broken references to renamed/archived scripts across `install.sh`, docs, and tests
- [x] Docs: correct the nested-vs-flat Logstash contradiction (pipeline is flat)
- [x] CI: shell syntax, JSON, and Python compile checks on every push
- [x] Docs audited against the code and reorganised into a pfSense knowledge base + SIEM stack docs (2026-09); pfSense 2.9.0 upgrade guide added
- [x] `setup.sh`: rc.d unit renamed to `suricata_forwarder.sh` so pfSense actually starts it at boot; interpreter detected instead of hardcoded `python3.11`; `stop` works (supervisor + child PIDs)
- [ ] **pfSense 2.9.0 validation**: run `preflight.sh → setup.sh → status.sh` on a 2.9.0 box, confirm the Python path, `maxminddb` import, Telegraf workaround (Redmine #16674) and dashboards; record results in the upgrade guide
- [ ] Retire the legacy pfSense-side scripts (`setup_forwarder_monitoring.sh`, `suricata-restart-hook.sh`, `suricata-restart-with-forwarder.sh`, `unified-monitoring-watchdog.sh`, `suricata-eve-forwarder.sh`): they hardcode `python3.11` and use `killall python3.11`
- [ ] Install the watchdog cron through the pfSense Cron package (config.xml-backed) instead of root's crontab, so it is in backups and survives a restore
- [ ] `plugins/telegraf_pfifgw.php`: replace the legacy `$config` global with `config_get_path()`; guard undefined variables under PHP 8.5
- [ ] `apply-suricata-drop-rules.sh` / `enable-selective-blocking.sh`: stop hardcoding instance names and writing into pfSense-managed rules files; drive drops through SID Mgmt
- [ ] `status.sh`: probe Logstash's UDP port with `nc -u` (the TCP probe can never succeed); drop the `lsof` dependency (not in pfSense base)
- [ ] Suricata 8 readiness: detect the package version and warn about the DNS EVE v3 change; update DNS panels
- [ ] **OpenSearch security**: enable the security plugin (auth + TLS), bind to a management interface, restrict ufw 9200 by source — today the index is unauthenticated and reachable
- [ ] Verify OpenSearch tarball checksum during install
- [ ] Single shared config loader (`lib/config.sh`) so every script agrees on `PFSENSE_USER`, `SIEM_SSH_USER`, `OPENSEARCH_HOST` — no more personal-network defaults
- [ ] Consolidate the three entry points (`pfsense-siem` menu → `install.sh` → `setup.sh`) so they stop reimplementing each other (service restarts, python detection)

## 📣 Phase B — From dashboards to detection (next)

A SIEM you have to look at is a dashboard. Biggest capability gap:

- [ ] **Grafana alert rules as provisioned code** (alert on Suricata severity-1, pfBlockerNG surge, forwarder silence) + contact points (Discord/Matrix to match siem-docker-stack's n8n SOAR)
- [ ] **Pipeline health alerting**: index-rate-zero per source, Logstash backpressure, OpenSearch disk/heap — the pipeline must page someone when it silently stops
- [ ] **Reliable transport**: today Suricata events ride plain UDP 5140 (spoofable, silently lossy). Move to TLS + queued transport (Filebeat/Vector) or add sequencing/gap metrics to the forwarder
- [ ] Snapshot tier for OpenSearch (hot → snapshot → delete) instead of delete-only ISM
- [ ] Real tests: assertions + exit codes in `tests/`, dry-run mode for `setup.sh`/`install.sh` runnable in CI

## 📦 Phase B½ — One-command distribution (install from GitHub)

Today a user must clone the repo, copy `config.env.example`, then run three scripts on
two hosts. Goal: a single command per host, plus a download-and-run path for people who
will not pipe the internet into a shell.

- [ ] **`bootstrap.sh` at the repo root** (workstation or SIEM server, bash):
  `curl -fsSL https://raw.githubusercontent.com/ChiefGyk3D/pfsense-siem-stack/<tag>/bootstrap.sh | bash`
  — checks for `git`/`curl`/`jq`/`ssh`, clones (or downloads the release tarball for) a
  pinned tag into `~/pfsense-siem-stack`, creates `config.env` interactively
  (`SIEM_HOST`, `PFSENSE_HOST`, `PFSENSE_USER`), runs `scripts/preflight.sh`, then hands
  off to `./pfsense-siem`. Flags: `--version vX.Y.Z`, `--dir`, `--non-interactive` with
  env vars, `--siem-only` (runs `install.sh`), `--deploy-only` (runs `setup.sh`).
- [ ] **pfSense-side standalone installer** (`bootstrap-pfsense.sh`, POSIX `/bin/sh`,
  no bash on pfSense): for users who only want the forwarder and have no workstation
  in the loop — `fetch -o - https://.../bootstrap-pfsense.sh | sh -s -- --siem <SIEM_IP>`
  installs `forward-suricata-eve.py`, `suricata_forwarder.sh` and the watchdog exactly
  as `setup.sh` does, using the detected Python. Shares the rc.d/watchdog templates with
  `setup.sh` (move them to `lib/` so the two cannot drift).
- [ ] **GitHub Releases** as the distribution unit: tag `vX.Y.Z`, CI builds a tarball
  (`pfsense-siem-stack-vX.Y.Z.tar.gz`) plus `SHA256SUMS`, and the release notes are the
  CHANGELOG section. The manual path becomes "download the release, verify the checksum,
  unpack, run `./pfsense-siem`" — no git required. Sign tags (`git tag -s`) once a key is
  published.
- [ ] **Safety for the `curl | bash` path**: bootstrap fetches only from a pinned tag
  (never `main`), verifies the tarball against `SHA256SUMS` before running anything,
  prints what it is about to do and pauses unless `--yes`, and the README shows the
  two-step form first (`curl -o bootstrap.sh … && less bootstrap.sh && bash bootstrap.sh`).
- [ ] **`pfsense-siem update`** menu item: `git fetch` + checkout of the latest release
  tag (or tarball re-download), show the CHANGELOG diff, re-run `setup.sh` so the
  forwarder/rc.d/watchdog on pfSense match the new version. This is also the
  post-pfSense-upgrade recovery command.
- [ ] **Container image for the SIEM side** is out of scope here — that is
  [siem-docker-stack](https://github.com/ChiefGyk3D/siem-docker-stack); bootstrap should
  offer "point at an existing OpenSearch/Grafana" as the default and `install.sh` as the
  bare-metal fallback.
- [ ] Later: Ansible role wrapping the same steps for people who already manage pfSense
  and the SIEM host with Ansible (moves the Phase C item here).

Prerequisite decisions: adopt semantic version tags (the CHANGELOG already uses them but
nothing is tagged since 1.2.0), and decide whether `install.sh` stays supported enough
to be one `bootstrap` mode or becomes "advanced, read the doc".

## 📦 Phase C — Content & reach (later)

- [ ] LAN/east-west dashboard, lateral movement detection
- [ ] Filterlog dashboard (firewall rule analysis), Unbound DNS analytics, VPN monitoring, DHCP lease tracking
- [ ] Multi-firewall support (central monitoring of several pfSense boxes)
- [ ] Threat intel feeds (MISP, abuse.ch, OTX) — coordinate with siem-docker-stack's MISP plans ([siem-docker-stack#5](https://github.com/ChiefGyk3D/siem-docker-stack/issues/5))
- [ ] Ansible playbooks / repeatable deployment (see Phase B½ — one-command distribution)
- [ ] Snort integration, OPNsense support

## 🌅 Long-term ideas (no timeline)

ML anomaly detection, hardware sizing guide, configuration marketplace, web UI, multi-vendor firewall support, cloud deployment. Community-driven — open a Discussion if one of these matters to you.

---

## 🧹 Repo hygiene decisions (2026-08 review)

- `RENAME_CLEANUP_PLAN.md` and `MIGRATION_CHECKLIST.md` **deleted** — they tracked the `pfsense_grafana` → `pfsense-siem-stack` rename, which is complete; the checklist claimed the opposite.
- `REORGANIZATION_SUMMARY.md` — historical session log of the 2025 rebrand, now in git history (see [docs/ARCHIVE.md](docs/ARCHIVE.md)).
- The duplicate roadmap that lived at the bottom of `CHANGELOG.md` is merged into this file; CHANGELOG now only records changes.
- ~~A third of the tree is archived material (43 scripts, 12 docs, 7 dashboards).~~ Done: the archives were deleted and the last commit containing them is recorded in [docs/ARCHIVE.md](docs/ARCHIVE.md) — git history keeps them.

---

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Highest-value contributions right now: OpenSearch security enablement, alert rule library, reliable transport, multi-firewall testing.

---

**Last Updated**: September 19, 2026
**Maintainer**: [ChiefGyk3D](https://github.com/ChiefGyk3D)
**Issues**: [GitHub Issues](https://github.com/ChiefGyk3D/pfsense-siem-stack/issues)
**License**: MPL 2.0
