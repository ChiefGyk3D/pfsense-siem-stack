# New to pfSense? Start Here

This project started as one person's monitoring stack and turned into a reference that
people new to pfSense use to learn how to run it well. This page is the on-ramp: what
the moving parts are, which guides to read in which order, and the handful of things
that bite nearly every newcomer. You do not need the SIEM half of this project to use
any of the pfSense guides.

If a term is unfamiliar, the [Glossary](Glossary.md) has one-line definitions, and the
[FAQ](FAQ.md) answers the questions that come up most often.

## The pieces, in one paragraph each

**pfSense** is a FreeBSD-based firewall and router distribution. Everything you configure
through its web GUI is stored in one file, `config.xml`, which is what Backup & Restore
saves and what survives an upgrade. Anything you change *outside* the GUI (editing a file
over SSH, `pkg install` from the shell, a hand-written crontab line) is not in that file
and is best-effort at most. Most of the hard-won advice in this wiki comes back to that
one fact.

**Suricata** is the intrusion detection and prevention engine (IDS/IPS) installed as a
pfSense package. It inspects traffic on the interfaces you enable it on, compares it with
tens of thousands of signature rules, and writes alerts and other events as JSON lines
to `eve.json`. In **IDS** mode it only alerts; in **IPS** (inline) mode it can also drop
traffic, but only for rules whose action you have changed to `drop`.

**pfBlockerNG** blocks traffic by reputation rather than by signature: IP blocklists
(botnet command servers, scanners, hijacked networks) enforced as firewall rules, and
DNS blocklists (DNSBL) answered by the firewall's own resolver. Used in front of
Suricata it removes known-bad traffic before Suricata spends CPU inspecting it.

**Telegraf** is a metrics agent. On pfSense it collects CPU, memory, interface and
gateway statistics for Grafana, and can tail pfBlockerNG's logs. Its configuration is
written by the pfSense GUI; the only persistent place for your own additions is the
*Additional Configuration* box.

**The SIEM stack** (optional) is the other half of this repository: a small Python
forwarder on pfSense ships Suricata's events to a server running Logstash, OpenSearch
and Grafana, where you get searchable history and dashboards. Everything about it lives
under "SIEM stack" on the [Home](Home.md) page.

## A reading order

Work through these in order. Each one is written to stand alone, so skip what you
already know.

1. **[Hardware Requirements](../docs/install/HARDWARE_REQUIREMENTS.md)** — before buying
   or repurposing anything. Quad-core and 8 GB for Suricata on a couple of interfaces, a
   real SSD, and never an SD card for anything that logs.
2. **[Suricata Optimization Guide](../docs/pfsense/SURICATA_OPTIMIZATION_GUIDE.md)** —
   the complete walk-through: install, pick interfaces, choose rule sources, run in IDS
   mode, tune, and only then consider blocking.
3. **[Suricata Configuration and Design](../docs/pfsense/SURICATA_CONFIGURATION.md)** —
   the *why* behind the previous guide: interface strategy, memcaps, the SID tuning
   philosophy, what survives an upgrade.
4. **[Suricata SID Management](../config/sid/README.md)** — after a week or two of
   alerts. Disable the rules that are always noise, suppress the ones that are false
   positives for one host, and do it through the GUI so it persists.
5. **[pfBlockerNG Optimization](../docs/pfsense/PFBLOCKERNG_OPTIMIZATION.md)** — a
   short list of high-value feeds, how often to update them, and how pfBlockerNG and
   Suricata divide the work. The [Feed Reference](../docs/pfsense/PFBLOCKERNG_FEED_REFERENCE.md)
   is the long catalog for later.
6. **[Telegraf on pfSense](../docs/pfsense/TELEGRAF_ON_PFSENSE.md)** — if you want
   metrics. Read section 2 ("where the configuration really lives") even if you read
   nothing else.
7. **[Filterlog Stops After Rotation](../docs/troubleshooting/PFSENSE_FILTERLOG_ROTATION_FIX.md)**
   — a pfSense bug that silently stops firewall logging. Install the Cron-package job on
   every box.
8. **[Upgrading pfSense](../docs/pfsense/PFSENSE_UPGRADE_GUIDE.md)** — read it *before*
   your first upgrade, not after.

Then, when you want more: [LAN and East-West Monitoring](../docs/pfsense/LAN_MONITORING.md)
for IDS on your VLANs, [Traffic Shaping Guide](../docs/pfsense/TRAFFIC_SHAPING_GUIDE.md)
for QoS, and [Quick Start](../QUICK_START.md) when you are ready for dashboards.

## Your first month with Suricata

The guides go into detail; this is the shape of it.

- **Week 1.** Install Suricata on **WAN only**, in **IDS mode**, inline capture. Enable
  Emerging Threats Open plus the Snort registered rules if you have a free Oinkcode.
  Turn on automatic log management. Set rule updates to run daily at a quiet hour.
- **Weeks 2 to 3.** Look at the Alerts tab. The same twenty signatures will account for
  most of the volume: stream and TCP anomaly events, `ET INFO` notices, chat and P2P
  policy rules. Decide for each whether it is a real problem or noise on *your* network.
- **Week 4.** Put the noise into a `disablesid.conf` and apply it through
  **Services → Suricata → SID Mgmt**. Alert volume should fall visibly. Now you can see
  the alerts that matter.
- **After that.** If you want blocking, add a `dropsid.conf` with the six high-confidence
  classtypes from the shipped minimal list to the WAN interface only, and watch the
  Blocks tab for a week before widening it. Keep internal interfaces in IDS mode.

## Things that bite newcomers

Each of these has cost someone hours. They are all explained in depth elsewhere; this
is the short list.

- **Hand edits to generated files vanish.** `suricata.yaml`, `threshold.config`,
  `telegraf.conf` and the rules files are regenerated by their packages on every save or
  update. Find the GUI setting instead. ([Telegraf on pfSense](../docs/pfsense/TELEGRAF_ON_PFSENSE.md#8-persistence-cheat-sheet),
  [Suricata Configuration](../docs/pfsense/SURICATA_CONFIGURATION.md#-after-a-pfsense-or-suricata-package-upgrade))
- **Only `config.xml` is backed up.** Files you copy to `/usr/local/bin`, lines you add
  with `crontab -e`, packages installed with `pkg install` from the shell: none of it is in
  a pfSense backup. Use the Cron and Filer packages when you need something durable.
  ([Upgrading pfSense](../docs/pfsense/PFSENSE_UPGRADE_GUIDE.md#part-2--what-this-stack-puts-on-pfsense-and-what-survives))
- **Never edit `/etc/crontab`.** pfSense regenerates it. Use the Cron package (stored in
  `config.xml`) or, for this project's watchdog, root's own crontab.
- **Inline mode does not block anything by itself.** Suricata only drops traffic for
  rules whose action is `drop`. Enabling IPS mode and then wondering why nothing is
  blocked is a rite of passage. ([IDS vs IPS Mode](../docs/pfsense/SURICATA_OPTIMIZATION_GUIDE.md#ids-vs-ips-mode))
- **Run IDS first, for weeks, before any blocking.** A noisy rule set in IPS mode breaks
  real traffic in ways users notice immediately. Internal VLANs should stay IDS.
- **Every Suricata interface is a full extra process** with its own copy of the rules.
  Thirteen VLAN instances roughly doubled the CPU of the reference box compared with two
  WAN instances. Add internal interfaces deliberately. ([LAN Monitoring](../docs/pfsense/LAN_MONITORING.md))
- **100% CPU for a few minutes after a rule update is normal.** Every instance recompiles
  its detection engine. Schedule updates for a quiet hour.
- **Firewall logs stop after rotation.** The `filterlog` daemon loses its file handle
  when `newsyslog` rotates `filter.log`; rules still work, logging does not. Install the
  Cron job in [Filterlog Stops After Rotation](../docs/troubleshooting/PFSENSE_FILTERLOG_ROTATION_FIX.md).
- **`service telegraf restart` is the wrong command on pfSense.** The package's script is
  `/usr/local/etc/rc.d/telegraf.sh`; the other name can start a second, unprivileged
  Telegraf that breaks the `pf` input. ([Restarting Telegraf correctly](../docs/pfsense/TELEGRAF_ON_PFSENSE.md#5-restarting-telegraf-correctly))
- **Telegraf runs as root on pfSense on purpose.** `pfctl` only reports real statistics to
  root. Do not "fix" it. ([Telegraf runs as root by design](../docs/pfsense/TELEGRAF_ON_PFSENSE.md#6-telegraf-runs-as-root-by-design))
- **GeoIP needs a free MaxMind key, entered in pfBlockerNG or ntopng**, not in Suricata.
  This project's forwarder only reads a database another package downloaded.
  ([GeoIP Setup](../docs/install/GEOIP_SETUP.md))
- **pfSense 2.9.0 breaks the Telegraf package at release**, and tightens SSH algorithms.
  Read the [upgrade guide](../docs/pfsense/PFSENSE_UPGRADE_GUIDE.md) first and use an
  ed25519 SSH key.
- **SD cards die under logging in weeks.** Not months. ([Hardware Requirements](../docs/install/HARDWARE_REQUIREMENTS.md#-critical-warnings))

## Conventions in these guides

- `admin@<PFSENSE_IP>` is your pfSense SSH login (`admin` on pfSense CE 2.7+; older
  releases used `root`). `<SIEM_IP>` is the server running OpenSearch and Grafana.
- Interface names such as `igc0` or `igc1.20` and VLAN numbers are examples from one
  deployment. Substitute your own.
- Example public addresses use the RFC 5737 documentation ranges (`203.0.113.x`,
  `198.51.100.x`).
- Menu paths are written as **Services → Suricata → Global Settings**.
- All numbers (CPU, RAM, alert counts) come from one reference deployment: an 8-core
  Intel Atom C3758 with 16 GB RAM running 15 Suricata instances. Your mileage will differ.

## Where to ask

- [GitHub Discussions](https://github.com/ChiefGyk3D/pfsense-siem-stack/discussions) for
  questions and "how do you handle X" threads.
- [GitHub Issues](https://github.com/ChiefGyk3D/pfsense-siem-stack/issues) for mistakes in
  these guides or bugs in the scripts.
- Official references: the [pfSense documentation](https://docs.netgate.com/pfsense/en/latest/),
  the [Suricata documentation](https://docs.suricata.io/) and the
  [Netgate forum](https://forum.netgate.com/).
