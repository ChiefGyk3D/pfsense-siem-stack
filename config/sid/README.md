# Suricata SID Management on pfSense

Rule tuning lists for the pfSense Suricata package, plus the procedure for building your own and applying them so they survive rule updates and pfSense upgrades.

This is generic pfSense/Suricata material. The only part that depends on the SIEM stack is the OpenSearch query used to find your noisiest signatures; if you do not run the stack, use the **Alerts** tab in the Suricata GUI instead.

```
config/sid/
├── README.md                       # this file
├── disable/disablesid.conf         # 218 SIDs never loaded (maintainer's list, annotated)
├── drop/dropsid-minimal-safe.conf  # 6 high-confidence classtypes to convert alert → drop
├── drop/dropsid-comprehensive.conf # tiered classtype drop list for aggressive inline IPS
└── suppress/suppress.conf          # 2 example IP-specific suppressions (replace with yours)
```

---

## 1. Disable, drop and suppress — what each one does

The pfSense Suricata package exposes three mechanisms for changing how a rule behaves. They are not interchangeable.

| Mechanism | pfSense file / tab | Effect | Cost | Use when |
|-----------|--------------------|--------|------|----------|
| **Disable** | `disablesid.conf` (SID Mgmt) | Rule is **not loaded** into the engine at all | None — the rule consumes no CPU or memory | The rule is always noise in your environment, regardless of source or destination |
| **Drop** | `dropsid.conf` (SID Mgmt) | Rule's action is rewritten from `alert` to `drop`; in **inline IPS mode** matching packets are blocked | Same as an alert rule | You run inline IPS and want a class of high-confidence rules to block, not just alert |
| **Suppress** | Suppress list (Suppress tab → assigned per interface) | Rule still runs; alerts are hidden when the entry's conditions match (`track by_src`/`by_dst` + IP/CIDR) | Full — the rule still inspects every packet | The rule is a false positive **only** for specific hosts and you still want it for everyone else |

Two consequences follow:

- A suppress entry without an IP condition (`suppress gen_id 1, sig_id 12345`) is strictly worse than disabling: same silence, but the rule still burns CPU. Move those to `disablesid.conf`.
- `dropsid.conf` does nothing in IDS mode. It only matters on interfaces running inline IPS (see [SURICATA_OPTIMIZATION_GUIDE.md](../../docs/pfsense/SURICATA_OPTIMIZATION_GUIDE.md#ids-vs-ips-mode)).

### File syntax

`disablesid.conf` / `dropsid.conf` (SID Mgmt format):

```
1:2029322                 # gid:sid — one per line, or comma-separated
2029322                   # bare sid (gid 1 assumed)
pcre:classtype:trojan-activity   # regex matched against the rule text
```

Both `pcre:` and `re:` prefixes are accepted for regular expressions; the two drop lists in this directory use one each and both work.

Suppress list (Suricata `threshold.config` format):

```
suppress gen_id 1, sig_id 2221034, track by_dst, ip 192.0.2.10
suppress gen_id 1, sig_id 2038669, track by_src, ip 198.51.100.0/24
```

---

## 2. What is in the shipped lists and how they were derived

The lists came from roughly a month of alert volume on the maintainer's deployment (15 Suricata instances: 2 WAN inline IPS, 13 VLAN IDS). They are a reasonable starting point for a home or small-office network behind pfSense, but they encode one network's traffic; review before adopting.

### `disable/disablesid.conf` — 218 SIDs

Each line carries a comment describing the rule. Grouped by section:

- **Suricata engine/protocol-anomaly events** (`SURICATA STREAM ...`, `SURICATA Applayer ...`, TLS/QUIC/HTTP anomaly events in the 22xxxxx range). These fire constantly on asymmetric routing, WAN retransmissions and encrypted traffic, and almost never indicate an attack.
- **Chat, IM and social apps** (Telegram, Skype, IRC, Facebook and similar `ET CHAT`/`ET POLICY` informational rules).
- **P2P/BitTorrent** peer-sync rules, if you allow torrents.
- **Informational** `ET INFO` rules (Java version checks, user-agent notices, external IP lookups).
- **Old Snort preprocessor events** with non-1 generator IDs (`119:*`, `120:*`, `137:*`, `138:*`, `140:*`, `141:*`, `3:*`) — 20 entries that were previously suppressed globally and are now disabled.

### `suppress/suppress.conf` — 2 conditional suppressions

```
suppress gen_id 1, sig_id 2221034, track by_dst, ip <Microsoft Azure IP>
suppress gen_id 1, sig_id 2038669, track by_src, ip <AWS EC2 IP>
```

These are **examples from the maintainer's deployment**, not universal values. One silences an HTTP "unrecognized authorization method" event toward a specific Microsoft endpoint; the other silences a Realtek exploit signature that a particular AWS host trips on legitimate traffic. The addresses in the file are the maintainer's; **replace them with the hosts that generate false positives on your network**, or delete both lines and start empty.

### `drop/` — two alert→drop lists

- **`dropsid-minimal-safe.conf`**: six classtypes with near-zero false-positive risk (`exploit-kit`, `trojan-activity`, `command-and-control`, `domain-c2`, `successful-admin`, `successful-user`). Start here.
- **`dropsid-comprehensive.conf`**: the same idea in six tiers, from ultra-safe through broad coverage. The file's comments say which tiers to enable first and which to back out if legitimate traffic breaks. `misc-activity` is deliberately commented out — it includes hunting/monitoring rules that would block Telegram, Discord and similar.

### Before / after

The original lists had ~151 disabled SIDs and 67 suppress entries, 65 of them unconditional (rules loaded and inspecting traffic only to have every alert hidden). Moving the unconditional ones to the disable list gives the current state:

| | Disabled (not loaded) | Suppressed (loaded, alerts hidden) |
|---|---|---|
| Before | ~151 | 67 (65 unconditional + 2 IP-specific) |
| After | **218** | **2** (IP-specific only) |

Same silence in the dashboards, 65 fewer rules in every instance's detection engine.

---

## 3. Building your own list

Do not paste someone else's disable list blindly. Run in IDS mode for one to two weeks, then look at what is actually noisy.

### 3.1 Find your top signatures

**With the SIEM stack** — aggregate over the `suricata-*` indices (fields are flat; `alert.signature_id` is an integer, `alert.signature` has a `.keyword` sub-field):

```bash
curl -s "http://<SIEM_IP>:9200/suricata-*/_search" -H 'Content-Type: application/json' -d '{
  "size": 0,
  "query": {"bool": {"filter": [
    {"term": {"event_type": "alert"}},
    {"range": {"@timestamp": {"gte": "now-7d"}}}
  ]}},
  "aggs": {
    "top_sids": {
      "terms": {"field": "alert.signature_id", "size": 50},
      "aggs": {
        "name":  {"terms": {"field": "alert.signature.keyword", "size": 1}},
        "src":   {"terms": {"field": "src_ip",  "size": 3}},
        "dst":   {"terms": {"field": "dest_ip", "size": 3}},
        "iface": {"terms": {"field": "in_iface", "size": 5}}
      }
    }
  }
}' | jq '.aggregations.top_sids.buckets[] | {sid: .key, count: .doc_count, name: .name.buckets[0].key, src: [.src.buckets[].key], dst: [.dst.buckets[].key]}'
```

The `src`/`dst` sub-aggregations are what tell you whether a signature is noisy everywhere or only for one or two hosts.

**Without the stack** — **Services → Suricata → Alerts**, pick the interface, sort by count; or on the box:

```bash
ssh admin@<PFSENSE_IP> "cat /var/log/suricata/suricata_*/eve.json | jq -r 'select(.event_type==\"alert\") | \"\(.alert.signature_id) \(.alert.signature)\"' | sort | uniq -c | sort -rn | head -50"
```

### 3.2 Decide, per signature

```
Is the traffic legitimate?
├── No  → leave the rule alone (and consider adding its classtype to dropsid.conf if you run inline IPS)
└── Yes → Is it noisy for every host, or only a few?
    ├── Every host / protocol anomaly / informational → disablesid.conf
    └── One or a few specific IPs or subnets       → suppress list with track by_src/by_dst + ip
```

Rules of thumb:

- Anything starting with `SURICATA STREAM`, `SURICATA Applayer`, `SURICATA TLS`, `SURICATA HTTP` or `SURICATA QUIC` is an engine event, not a threat signature. Disable unless you are debugging the engine.
- `ET INFO` and most `ET POLICY` rules are informational. Disable the ones you do not care about rather than suppressing them.
- Keep the suppress list short. If it grows past a dozen entries, some of them probably belong in the disable list.
- When a *legitimate* application breaks in inline IPS mode, the fix is usually a suppress entry for that host or removing a tier from `dropsid.conf`, not disabling the rule globally.

Copy `disablesid.conf` and `suppress.conf`, edit them, and keep them in version control alongside your pfSense backups.

---

## 4. Applying the lists in pfSense

Everything below is stored in `config.xml`, which means it is included in **Diagnostics → Backup & Restore**, survives rule updates, and survives pfSense and package upgrades. Editing the generated `suricata.yaml`, `threshold.config` or `*.rules` files under `/usr/local/etc/suricata/suricata_*/` by hand does **not** persist — the package regenerates them on every rule update and every save.

### 4.1 Disable and drop lists — SID Mgmt

1. **Services → Suricata → SID Mgmt** (a global tab, not per interface).
2. Check **Enable Automatic SID State Management** and Save.
3. Under **SID Management Configuration Files**, click **+ Add** (or upload): name it `disablesid.conf`, paste the contents of [`disable/disablesid.conf`](disable/disablesid.conf), Save. Repeat for `dropsid.conf` if you run inline IPS (paste `drop/dropsid-minimal-safe.conf` to start).
4. In the **Interface SID Management List Assignments** table, pick `disablesid.conf` in the *Disable SID File* column for each interface, and `dropsid.conf` in the *Drop SID File* column for the inline-IPS interfaces only.
5. Optionally check **Rebuild** for each interface so the rules are regenerated immediately, then Save.

### 4.2 Suppress list — Suppress tab

1. **Services → Suricata → Suppress** → **+ Add**. Name it (e.g. `suppress_wan`), paste the entries, Save.
2. **Services → Suricata → Interfaces → edit interface → Alert Suppression and Filtering → Alert Suppression List**: select the list, Save.
3. Repeat for each interface that should use it (suppress lists can differ per interface, which is useful when a false positive only exists on one segment).

### 4.3 Reload the rules

**Services → Suricata → Updates → Update Rules** (or **Force**). This regenerates each instance's rule set with the disable/drop transforms applied and, if **Live Rule Swap on Update** is enabled in Global Settings, reloads without dropping the instance.

If you prefer a hard restart of all instances:

- GUI: **Services → Suricata → Interfaces** → stop/start icon per interface, or
- Shell: `ssh admin@<PFSENSE_IP> "/usr/local/etc/rc.d/suricata.sh restart"`

The GUI tracks the running state of each instance. Restarting from the shell works, but if the Interfaces page then shows a stale state, refresh it or restart once from the GUI to resynchronise.

`scripts/apply-suricata-drop-rules.sh` in this repository is a shell-side alternative that runs `suricata-update` with a drop list directly against the instance directories. It is a workaround for environments where the GUI SID Mgmt tab misbehaves; the GUI path above is the supported one.

---

## 5. Verifying

**Disabled SIDs are commented out in the generated rules:**

```bash
ssh admin@<PFSENSE_IP> "grep -l '^# .*sid:2029322;' /usr/local/etc/suricata/suricata_*/rules/*.rules"
```

A disabled rule appears with a leading `#` in every instance's rules directory; a still-active one appears without it.

**Drop rules were rewritten (inline IPS interfaces):**

```bash
ssh admin@<PFSENSE_IP> "grep -c '^drop ' /usr/local/etc/suricata/suricata_*/rules/suricata.rules"
```

**Alerts for the disabled SIDs stop arriving** (SIEM stack):

```bash
curl -s "http://<SIEM_IP>:9200/suricata-*/_count" -H 'Content-Type: application/json' -d '{
  "query": {"bool": {"filter": [
    {"range": {"@timestamp": {"gte": "now-1h"}}},
    {"terms": {"alert.signature_id": [2029322, 2231002, 2033077, 2033078]}}
  ]}}
}' | jq '.count'
```

Anything non-zero after a reload is either an old event or a SID that did not make it into the list.

**Overall alert volume** should drop visibly in the Suricata dashboard within an hour.

---

## 6. Troubleshooting

**Changes not applied**

- Check **Services → Suricata → Logs View → suricata.log** for the interface; SID Mgmt syntax errors are reported there.
- Confirm the list is actually *assigned* to the interface in the SID Mgmt assignment table. Creating the file is not enough.
- Run **Update Rules** again; the transforms only apply during a rule build.

**Still seeing alerts from a disabled SID**

- Check the alert timestamp: is it from before the reload?
- Was the SID written with the correct `gid:sid`? Preprocessor events use gids other than 1 (`119:31`, not `1:31`).
- Is the rule coming from a **custom.rules** entry or a category that SID Mgmt is not managing? Custom rules are not transformed.

**Suppress entry has no effect**

- Suppress lists are assigned per interface; make sure the interface that saw the alert has the list selected.
- `track by_src` matches the alert's source IP, `by_dst` the destination. Check which side the offending host is on in the alert.

---

## Related

- [SURICATA_OPTIMIZATION_GUIDE.md](../../docs/pfsense/SURICATA_OPTIMIZATION_GUIDE.md) — rule sources, IDS vs IPS, when to start dropping
- [SURICATA_CONFIGURATION.md](../../docs/pfsense/SURICATA_CONFIGURATION.md) — interface strategy and what survives an upgrade
- [PFSENSE_UPGRADE_GUIDE.md](../../docs/pfsense/PFSENSE_UPGRADE_GUIDE.md) — full upgrade checklist
- `scripts/check_custom_sids.sh` — checks whether specific SIDs still exist in the installed rule sets
