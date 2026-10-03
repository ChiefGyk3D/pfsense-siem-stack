# FAQ

Short answers to the questions that come up most often, each pointing at the page with
the full story.

## About the project

**Do I need the SIEM stack to use the pfSense guides?**
No. Everything under "pfSense knowledge base" on [Home](Home.md) applies to any pfSense
box. Sections that depend on the SIEM are marked as such inside each guide.

**Which pfSense versions does this cover?**
pfSense CE 2.7.2 or later. 2.8.1 is what the reference deployment ran for most of this
material; 2.9.0 works with caveats that are spelled out in
[Upgrading pfSense](../docs/pfsense/PFSENSE_UPGRADE_GUIDE.md). pfSense Plus is not tested
but the Suricata, pfBlockerNG and Telegraf material is the same.

**Does it work with OPNsense?**
Not today. OPNsense support is a long-term roadmap item, and the shell pieces that run on
the firewall assume pfSense's package layout. The Suricata rule-tuning advice is largely
engine-level and transfers.

**Where do the numbers come from?**
One deployment: an 8-core Intel Atom C3758 with 16 GB RAM running 15 Suricata instances
(2 WAN inline IPS, 13 VLAN IDS), feeding a 4-core, 32 GB SIEM server. Details in
[Hardware Requirements](../docs/install/HARDWARE_REQUIREMENTS.md).

**Can I edit this wiki?**
Not directly. It is regenerated from the repository on every push, so edits made in the
wiki are overwritten. Edit the source file named at the bottom of the page and open a pull
request; see [Contributing](../CONTRIBUTING.md).

## Suricata

**Suricata or Snort?**
Suricata. It is multithreaded, actively developed, writes EVE JSON natively, and can use
Snort's rules. [Why Suricata Over Snort](../docs/pfsense/SURICATA_CONFIGURATION.md#-why-suricata-over-snort).

**I enabled inline IPS mode and nothing is being blocked. Why?**
Inline mode is a *capture* method. Suricata only drops traffic for rules whose action is
`drop`, and every rule ships as `alert`. Add a `dropsid.conf` through SID Mgmt or use a
Snort IPS policy. [IDS vs IPS Mode](../docs/pfsense/SURICATA_OPTIMIZATION_GUIDE.md#ids-vs-ips-mode).

**Should I run IPS on my LAN or VLANs?**
No. Keep internal interfaces in IDS mode. A false positive there breaks something
internal that you cannot easily diagnose from outside. IDS still catches lateral
movement and scanning. [Interface Strategy](../docs/pfsense/SURICATA_CONFIGURATION.md#️-interface-strategy).

**Why does CPU hit 100% for a few minutes every day?**
Rule reload. Every instance recompiles its detection engine after a rule update. Schedule
updates for a quiet hour and enable Live Rule Swap. It is normal.

**I get hundreds of alerts a day. Which ones matter?**
Probably twenty signatures account for most of them: `SURICATA STREAM` and other engine
anomaly events, `ET INFO`, chat and P2P policy rules. Disable them with `disablesid.conf`
and the real alerts become visible. [SID Management](../config/sid/README.md).

**Disable, suppress or drop. Which one?**
Disable when a rule is noise everywhere (the rule is not loaded, zero cost). Suppress
when it is a false positive only for specific hosts (the rule still runs). Drop only on
inline interfaces, for high-confidence classtypes. [What each one does](../config/sid/README.md#1-disable-drop-and-suppress--what-each-one-does).

**Where do I put custom rules?**
In the interface's **custom.rules** box in the GUI. Files you copy into the instance
directory are overwritten on the next rule update.

**An instance died with a memory error, or the memcap counters keep climbing.**
Raise the stream memcap in steps toward 1 GB for that interface, and budget RAM for it
across all instances. [Stream Memory](../docs/pfsense/SURICATA_CONFIGURATION.md#-stream-memory).

**How do I test that Suricata is actually alerting?**
`testmyids.com` redirected to HTTPS, so use
`curl -A "BlackSun" http://testmynids.org/uid/index.html` from a client behind the
firewall. [Testing and Validation](../docs/pfsense/SURICATA_OPTIMIZATION_GUIDE.md#testing-and-validation).

## pfBlockerNG

**Which feeds should I start with?**
Feodo Tracker, SSL Blacklist and URLhaus (Deny Both, hourly); Spamhaus DROP and ET
Compromised (Deny Inbound, every 4 hours); one DNSBL, OISD, daily. Expand after a week.
[Quick Setup](../docs/pfsense/PFBLOCKERNG_OPTIMIZATION.md#quick-setup).

**Should Suricata and pfBlockerNG both do IP reputation?**
No. Let pfBlockerNG own reputation feeds and disable Suricata's `emerging-drop`,
`emerging-dshield` and `emerging-ciarmy` categories. Keeping both doubles the work.

**A legitimate site is blocked.**
Find the list under **Reports → Alerts**, whitelist the address or domain, reload. The
[Whitelisting Guide](../docs/pfsense/PFBLOCKERNG_FEED_REFERENCE.md#whitelisting-guide)
lists the CDNs and conferencing services that break most often.

**DNSBL does nothing for some devices.**
They are not using the firewall for DNS: a hard-coded `8.8.8.8` or DNS-over-HTTPS bypasses
DNSBL entirely.

## Telegraf and metrics

**My change to `telegraf.conf` disappeared.**
The pfSense package regenerates that file from `config.xml` on every save, reinstall and
upgrade. Put your additions in the **Additional Configuration** box on **Services →
Telegraf**. [Where the configuration really lives](../docs/pfsense/TELEGRAF_ON_PFSENSE.md#2-configure-via-services--telegraf).

**Why does Telegraf run as root? Is that a bug?**
It is deliberate. `pfctl -s info` only returns real statistics to root, so the `pf` input
and the PF Information panel need it. [Telegraf runs as root by design](../docs/pfsense/TELEGRAF_ON_PFSENSE.md#6-telegraf-runs-as-root-by-design).

**How do I restart Telegraf?**
From the GUI (**Status → Services**, or Save on the Telegraf page), or
`/usr/local/etc/rc.d/telegraf.sh restart`. Not `service telegraf restart`, which targets
the wrong script. [Restarting Telegraf correctly](../docs/pfsense/TELEGRAF_ON_PFSENSE.md#5-restarting-telegraf-correctly).

**Telegraf will not start after upgrading to pfSense 2.9.0.**
The package writes two deprecated option names that the newer Telegraf rejects. The
workaround and the Redmine issue are in
[pfSense 2.9.0: Telegraf refuses to start](../docs/pfsense/TELEGRAF_ON_PFSENSE.md#pfsense-290-telegraf-refuses-to-start-with-ssl_ca--fielddrop-errors).

## pfSense platform

**Firewall or pfBlockerNG logs stopped but rules still work.**
The filterlog rotation bug. One `php -r` line restores logging now; a Cron-package job
keeps it from recurring. [Filterlog Stops After Rotation](../docs/troubleshooting/PFSENSE_FILTERLOG_ROTATION_FIX.md).

**What survives a pfSense upgrade?**
Anything set through the GUI (it is in `config.xml`). Not: hand edits to generated
files, scripts you copied to `/usr/local/bin`, lines in `/etc/crontab`, packages installed
from the shell. [What this stack puts on pfSense, and what survives](../docs/pfsense/PFSENSE_UPGRADE_GUIDE.md#part-2--what-this-stack-puts-on-pfsense-and-what-survives).

**Can I use an SD card or USB stick for the firewall or the SIEM?**
Not for anything that logs. Suricata alone writes tens to hundreds of times a second.
[Hardware Requirements](../docs/install/HARDWARE_REQUIREMENTS.md#-critical-warnings).

**Do I need a MaxMind account for GeoIP?**
Only the package that *downloads* GeoLite2 does (pfBlockerNG or ntopng), and the account
is free. The forwarder just reads the database that is already on the box.
[GeoIP Setup](../docs/install/GEOIP_SETUP.md).

## SIEM stack

**Do I have to run `install.sh`?**
No. `setup.sh` works against any reachable OpenSearch 2.x and Grafana 12.x; the
recommended server side is [siem-docker-stack](https://github.com/ChiefGyk3D/siem-docker-stack).
`install.sh` is the single-box bare-metal alternative. [Quick Start](../QUICK_START.md).

**The dashboards show "No Data".**
First confirm documents exist and are recent; if so, it is the datasource, index pattern
or field mapping. [Dashboard Shows "No Data"](../docs/troubleshooting/DASHBOARD_NO_DATA_FIX.md)
is the single triage page. `./scripts/diagnose-and-repair.sh` does most of it for you.

**Data stops at exactly midnight UTC.**
`action.auto_create_index` does not allow the new daily index.
[Data Stops at Midnight UTC](../docs/troubleshooting/OPENSEARCH_AUTO_CREATE.md).

**One interface vanished from the per-interface dashboard.**
Either the forwarder is holding a rotated file (restart the service) or the interface was
added after the forwarder started (restart the service; it discovers files at startup).
[Forwarder and Log Rotation](../docs/troubleshooting/LOG_ROTATION_FIX.md).

**Why are the fields flat instead of nested under `suricata.eve.*`?**
Grafana's OpenSearch datasource aggregates far better on flat keyword fields. The nested
layout existed early on and was dropped; anything still using it is stale.
[Field Reference](../docs/reference/FIELD_REFERENCE.md).

**What do I do after upgrading pfSense?**
`./scripts/preflight.sh`, then `./setup.sh` (it re-detects Python and redeploys the
forwarder, service and watchdog), then `./scripts/status.sh`.
[Post-upgrade procedure](../docs/pfsense/PFSENSE_UPGRADE_GUIDE.md#post-upgrade-procedure-for-the-siem-pieces).

**Is this secure out of the box?**
Not yet. `install.sh` leaves OpenSearch unauthenticated on port 9200, events travel as
plain UDP, and Grafana ships with `admin`/`admin`. Restrict the ports, change the
password, and read [Security considerations](../README.md#security-considerations) and the
[Roadmap](../ROADMAP.md).

**Can I also feed Wazuh?**
Yes. Set pfSense remote logging to RFC 5424 with RFC 3339 timestamps, or Wazuh's `pf`
decoder never matches. [Wazuh Integration](../docs/siem/wazuh/README.md).
