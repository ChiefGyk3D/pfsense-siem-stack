# LAN Monitoring & East-West Detection

## Overview

**East-west traffic** is lateral movement inside your network: between VLANs, between hosts on the same subnet, or from an internal host toward internal servers. WAN-only IDS/IPS never sees it. Monitoring internal interfaces with Suricata catches:

- Compromised hosts spreading malware
- Insider threats
- Lateral movement after an initial breach
- Internal reconnaissance and scanning

This guide covers how to add Suricata IDS instances on internal VLANs, which rules to run there, and how to use the per-interface dashboard. It applies to any pfSense box; only the [forwarder](#integration-with-the-forwarder) and [Grafana](#grafana-dashboard-for-lan-monitoring) sections depend on this repository's SIEM stack.

**Cost first:** every monitored interface is a separate Suricata process with its own copy of the rule set. On the reference deployment (8-core Intel Atom C3758, 16 GB) 13 VLAN instances in IDS mode roughly double the steady-state CPU compared with the two WAN instances alone. Monitor the segments where the visibility is worth that — usually IoT and guest first, trusted last. [SURICATA_OPTIMIZATION_GUIDE.md](SURICATA_OPTIMIZATION_GUIDE.md#which-interfaces-to-monitor) has the sizing background.

---

## Example Topology

Everything below uses this **example topology**. Substitute your own interface names, VLAN IDs and subnets throughout.

| Interface | Role | Subnet | Suricata mode |
|-----------|------|--------|---------------|
| `igc0` | WAN | (public) | Inline IPS |
| `igc1.10` | **Trusted** VLAN (workstations) | `10.10.10.0/24` | IDS |
| `igc1.20` | **IoT** VLAN (TVs, cameras, smart devices) | `10.10.20.0/24` | IDS |
| `igc1.30` | **Guest** VLAN | `10.10.30.0/24` | IDS |

```
Internet → igc0 (WAN) [Inline IPS] → pfSense → igc1.10 Trusted  [IDS]
                                              → igc1.20 IoT      [IDS]
                                              → igc1.30 Guest    [IDS]
                                                       ↓
                                        detect 10.10.x.x → 10.10.y.y
```

**Key principle:** inline IPS on WAN (block), IDS on internal VLANs (alert only, never break internal traffic).

---

## Suricata Configuration for LAN Monitoring

### 1. Enable Suricata on Internal Interfaces

**Services → Suricata → Interfaces → Add**, once per VLAN:

| Setting | Value | Reason |
|---------|-------|--------|
| **Interface** | `igc1.20` (your VLAN) | Interface to monitor |
| **Description** | `IoT_IDS` | Clear naming; this becomes the instance name in logs |
| **Enable** | ✓ | |
| **IPS Mode** | Legacy or Inline, but **do not enable blocking** | Alert only on internal segments |
| **Promiscuous Mode** | Off unless needed | Needed only when Suricata must see traffic not addressed to the firewall's own MAC — some VLAN/bridge setups or a mirror-port feed. On a routed VLAN interface the firewall already sees all inter-VLAN traffic |
| **HOME_NET** | `10.10.0.0/16` (your internal ranges) | Defines "inside" for the rules |
| **EXTERNAL_NET** | `!$HOME_NET` | Everything else |

Note that on a routed VLAN Suricata only sees traffic that **crosses the firewall** — VLAN-to-VLAN, VLAN-to-WAN. Host-to-host traffic within the same VLAN stays on the switch and is invisible unless you feed a mirror port to a dedicated interface.

### 2. Rule Selection for LAN Monitoring

**Services → Suricata → {Interface} → Categories**

Enable these for internal monitoring:

| Ruleset | Purpose | Priority |
|---------|---------|----------|
| **emerging-malware** | C2 beaconing from internal hosts | High |
| **emerging-exploit** | Exploit attempts (lateral movement) | High |
| **emerging-scan** | Internal port scanning | High |
| **emerging-compromised** | Known compromised host signatures | High |
| **emerging-worm** | Worm propagation (WannaCry, NotPetya, ...) | High |
| **emerging-policy** | Policy violations (torrents, unauthorized protocols) | Medium |

Disable or tune:
- `emerging-info` (too noisy on internal networks)
- `emerging-dns` (unless you want to see internal DNS queries)
- Anything you already disabled globally — see [config/sid/README.md](../../config/sid/README.md)

**Custom rule example** (SMB brute force between internal hosts):

```
alert tcp $HOME_NET any -> $HOME_NET 445 (msg:"LOCAL SMB connection burst to internal host"; flow:to_server; threshold:type threshold, track by_src, count 10, seconds 60; sid:9000001; rev:2;)
```

Paste custom rules into **Services → Suricata → {Interface} → Rules → Category: custom.rules**. They are stored in `config.xml` and survive rule updates; files dropped into the instance directory are not.

### 3. Per-VLAN Tuning

**IoT VLAN (`igc1.20`)** — high suspicion:
- IDS mode; malware, exploit, scan, worm rules all on
- Firewall rules block IoT → Trusted at the pf level; Suricata alerts on any attempt that gets through or is even tried
- Expect the most alerts here; smart TVs and cameras are noisy

**Trusted VLAN (`igc1.10`)** — balanced:
- IDS mode; malware, exploit, compromised rules
- Allow normal business traffic (SMB, RDP within the VLAN)
- Alert on cross-VLAN access attempts toward IoT or servers

**Guest VLAN (`igc1.30`)** — light:
- IDS mode; exploit and compromised rules only
- Guests are isolated by firewall rules anyway; Suricata is here to spot an infected guest device scanning

---

## Grafana Dashboard for LAN Monitoring

*(SIEM stack)*

### Suricata Per-Interface Dashboard

**Dashboard**: `dashboards/Suricata_Per_Interface.json`

Dynamic per-interface monitoring: pick one, several or all interfaces, and the dashboard repeats a full row of panels for each.

#### Panels (per interface)

1. **Events & alerts counter** — totals with colour thresholds and a sparkline
2. **Top alert signatures** — pie chart of `alert.signature`
3. **Alerts timeline** — time series
4. **Top source IPs** — internal hosts generating the most alerts (`src_ip`)
5. **Top destination IPs** — most-targeted internal hosts (`dest_ip`)
6. **Alert log table** — time, category, signature, action, severity, protocol, IPs, ports, countries

#### How to Use

1. **Import**: Grafana → Dashboards → Import → upload `dashboards/Suricata_Per_Interface.json`
2. **Select interfaces**: the `interface` variable is populated from the `in_iface` field; pick `igc1.10`, `igc1.20`, ... or *All*
3. **Adjust thresholds**: WAN interfaces want higher thresholds (500/2000 alerts) than VLANs (50/200)

#### Example Use Cases

- **IoT only**: select `igc1.20` — spot a compromised device
- **Compare VLANs**: select `igc1.10`, `igc1.20`, `igc1.30` side by side
- **Full view**: *All*

![Per-Interface Dashboard](../../media/Suricata%20Per-Interface%20Dashboard.png)
*Each selected interface gets its own complete monitoring section*

---

## Detection Use Cases

### 1. Compromised IoT Device

**Scenario**: a smart TV on the IoT VLAN is compromised and scans the Trusted VLAN.

**Detection**: the `igc1.20` instance sees `ET SCAN Potential Port Scan`-class alerts from `10.10.20.45` toward `10.10.10.0/24`.

**Response**: isolate the device, investigate.

### 2. Lateral Movement After a Breach

**Scenario**: an attacker on a Trusted-VLAN workstation pivots toward a file server.

**Detection**: `ET EXPLOIT ... SMB Remote Code Execution` from `10.10.10.55` to `10.10.10.200`.

**Response**: quarantine the workstation, check the server.

### 3. Internal C2 Beaconing

**Scenario**: malware beacons to an attacker-controlled internal pivot.

**Detection**: periodic connections from `10.10.10.75` to `10.10.10.200` on an odd high port; `ET MALWARE` alerts if the beacon matches a signature.

**Response**: investigate both hosts.

---

## Integration with the Forwarder

*(SIEM stack)*

The forwarder discovers **every** Suricata instance automatically, including the VLAN ones — no configuration change is needed when you add an interface:

```
/var/log/suricata/suricata_igc0<id>/eve.json        # WAN
/var/log/suricata/suricata_igc1.10<id>/eve.json     # Trusted VLAN
/var/log/suricata/suricata_igc1.20<id>/eve.json     # IoT VLAN
/var/log/suricata/suricata_igc1.30<id>/eve.json     # Guest VLAN
```

(`<id>` is a numeric suffix the pfSense package assigns per instance.)

Verify:

```bash
ssh admin@<PFSENSE_IP> "ps aux | grep '[f]orward-suricata-eve.py' | awk '{print \$2}' | xargs -I{} lsof -p {} 2>/dev/null | grep eve.json"
```

You should see one `eve.json` per interface.

---

## Grafana Filtering for LAN vs WAN

All fields are flat root-level EVE fields (`in_iface`, `src_ip`, `dest_ip`, `event_type`, `alert.*`) — nothing is nested under a `suricata.eve.*` prefix.

**WAN only**
```
in_iface:igc0
```

**All VLANs**
```
in_iface:igc1.*
```

**Lateral movement (internal → internal alerts)**
```
event_type:alert AND src_ip:"10.0.0.0/8" AND dest_ip:"10.0.0.0/8"
```

`src_ip` and `dest_ip` are mapped as `ip`, so CIDR notation works directly in Lucene queries.

---

## Performance Considerations

Internal traffic volume is usually **much higher** than WAN traffic, and every VLAN instance is a full Suricata process.

1. **IDS, never inline blocking, on internal interfaces** — inline adds latency and a false positive breaks something internal
2. **Selective categories** — malware, exploit, scan, worm; skip INFO/DNS/policy noise
3. **Raise scan thresholds** — internal networks are chatty; 50 connections/min instead of 10
4. **Pass lists** — **Services → Suricata → Pass Lists** for trusted server-to-server flows (backups, replication)
5. **Watch CPU** — `ssh admin@<PFSENSE_IP> "top -P"`; each instance should sit well under 50% outside rule reloads. If not, drop categories or drop instances

---

## Alerting Strategy

### High priority (act now)

- Exploit attempts between VLANs
- C2 beaconing from internal hosts
- Brute force on RDP/SSH toward servers
- Worm propagation signatures

```
Query:      event_type:alert AND alert.severity:1 AND src_ip:"10.0.0.0/8"
Threshold:  count > 5 in 5 minutes
Notify:     chat webhook + email
```

### Medium priority (review daily)

- Port scans within a VLAN
- Policy violations
- Unusual internal DNS

```
Query:      alert.signature:*SCAN* AND src_ip:"10.0.0.0/8"
Threshold:  count > 20 in 1 hour
Notify:     daily email summary
```

### Low priority (review weekly)

INFO-level and generic policy alerts — dashboard review only, no notifications.

---

## Testing & Validation

### 1. Port scan detection

From a workstation on the Trusted VLAN:
```bash
nmap -sS 10.10.20.0/24
```
Expected: `ET SCAN`-class alerts on the `igc1.20` instance with `src_ip` = your workstation.

### 2. Exploit detection

On an **isolated** test VLAN with a deliberately vulnerable VM:
```bash
msfconsole
use exploit/windows/smb/ms17_010_eternalblue
set RHOST 10.10.30.50
exploit
```
Expected: `ET EXPLOIT ... MS17-010` alerts.

### 3. Beacon pattern

```bash
while true; do curl -s http://10.10.10.200:8080/beacon; sleep 60; done
```
Expected: the periodic connection is visible in the per-interface dashboard; a C2 alert only if the pattern matches a signature.

---

## Best Practices

1. **Segment** with VLANs (Trusted, IoT, Guest, Servers) before you monitor — monitoring a flat network tells you little
2. **IDS on the VLANs that matter**, not automatically on all of them
3. **Tune per VLAN** — heavy on untrusted segments, light on trusted ones
4. **Use the per-interface dashboard** to compare segments
5. **Alert only on high-priority signatures** to avoid alert fatigue
6. **Review weekly** and push noisy SIDs into your disable list
7. **Test detection** on isolated segments

---

## Further Reading

- [SURICATA_OPTIMIZATION_GUIDE.md](SURICATA_OPTIMIZATION_GUIDE.md) — full install and tuning guide
- [SURICATA_CONFIGURATION.md](SURICATA_CONFIGURATION.md) — interface strategy and design decisions
- [config/sid/README.md](../../config/sid/README.md) — disabling noisy rules
- [PFBLOCKERNG_OPTIMIZATION.md](PFBLOCKERNG_OPTIMIZATION.md) — reputation blocking upstream of Suricata
- [DASHBOARD_NO_DATA_FIX.md](../troubleshooting/DASHBOARD_NO_DATA_FIX.md) — when panels are empty

---

**Next steps:**
1. Add Suricata IDS instances on the VLANs you care about most
2. Import `Suricata_Per_Interface.json`
3. Run the scan test and confirm the alert reaches the dashboard
4. Tune thresholds and disable noisy SIDs per VLAN
