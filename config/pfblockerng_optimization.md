# pfBlockerNG Recommended Configuration Guide
**Updated:** December 2025  
**Purpose:** Production-tested pfBlockerNG configuration for comprehensive threat blocking  
**Author:** ChiefGyk3D

> **⚠️ Important:** This configuration is aggressive and may require whitelist adjustments for your specific environment. Test in stages and monitor logs for false positives. Always maintain a whitelist for critical services (CDNs, video conferencing, cloud services, etc.).

---

## 📋 Table of Contents
1. [Quick Start](#quick-start)
2. [IP Block Lists](#ip-block-lists)
3. [DNS Block Lists (DNSBL)](#dns-block-lists-dnsbl)
4. [Pre-Configured Feeds](#pre-configured-feeds-from-pfblockerng)
5. [Performance Tuning](#performance-tuning)
6. [Whitelisting Guide](#whitelisting-guide)
7. [Privacy & Security Considerations](#privacy--security-considerations)
8. [Common Issues](#common-issues)

---

## Quick Start

### Before You Begin:
1. **Backup your pfSense configuration**: `Diagnostics > Backup & Restore`
2. **Create permit lists first**: CDN, Zoom, Microsoft, Google services
3. **Start with conservative settings**: Enable lists gradually
4. **Monitor logs**: `Firewall > pfBlockerNG > Reports > Alerts`

### Installation Order:
1. Install pfBlockerNG package
2. Configure General Settings (enable CRON)
3. Create permit/whitelist groups first
4. Add IP block lists (start with PRI1 only)
5. Add DNSBL lists (start with 1-2 groups)
6. Test and monitor for 24-48 hours
7. Gradually enable additional lists

---

## IP Block Lists

### Recommended Group Structure:

#### **Critical Threats (High Priority)**
**Settings:**
- List Action: `Deny Both` (blocks inbound + outbound)
- Update Frequency: `Every hour`
- Interface: `WAN` (or all external interfaces)

**Feeds to Include:**

| Feed Name | URL | Source | Purpose |
|-----------|-----|--------|---------|
| **Abuse.ch SSL Blacklist** | `https://sslbl.abuse.ch/blacklist/sslipblacklist.txt` | Abuse.ch | Malicious SSL certificates |
| **Abuse.ch Feodo Tracker** | Pre-configured in pfBlockerNG | Abuse.ch | Banking trojans (Feodo/Emotet) |
| **AlienVault Reputation** | Pre-configured in pfBlockerNG | AlienVault | IP reputation database |
| **CINS Army** | Pre-configured in pfBlockerNG | CINS | Command & Control servers |
| **Emerging Threats Block** | Pre-configured in pfBlockerNG | Proofpoint ET | Known malicious IPs |
| **Emerging Threats Compromised** | Pre-configured (ET_Comp) | Proofpoint ET | Compromised hosts |
| **ISC Block List** | Pre-configured in pfBlockerNG | SANS ISC | Top attacking IPs |
| **Spamhaus DROP** | Pre-configured in pfBlockerNG | Spamhaus | Known bad actors |
| **Pulsedive Threat Intel** | Pre-configured in pfBlockerNG | Pulsedive | Community threat intelligence |
| **FireHOL ThreatCrowd** | `https://iplists.firehol.org/files/threatcrowd.ipset` | FireHOL | Aggregated threat intel |

---

#### **Inbound Threats (Medium Priority)**
**Settings:**
- List Action: `Deny Inbound`
- Update Frequency: `Every 4 hours` (or hourly if CPU allows)
- Interface: `WAN`

**Feeds to Include:**

| Feed Name | URL | Source | Purpose |
|-----------|-----|--------|---------|
| **BlockList.de All** | `https://lists.blocklist.de/lists/all.txt` | BlockList.de | SSH/Mail/FTP brute force |
| **GreenSnow** | Pre-configured in pfBlockerNG | GreenSnow | SSH brute force attackers |
| **Bambenek C2 Tracker** | Pre-configured (BBC_C2) | Bambenek | C&C servers |
| **Stop Forum Spam Toxic** | Pre-configured (SFS_Toxic) | StopForumSpam | Toxic IP addresses |
| **FireHOL Level 1** | `https://iplists.firehol.org/files/firehol_level1.netset` | FireHOL | Aggregated attack sources |

---

#### **Additional Protection (Lower Priority)**
**Settings:**
- List Action: `Deny Inbound`
- Update Frequency: `Every 4 hours`
- Interface: `WAN`

**Feeds to Include:**

| Feed Name | URL | Source | Purpose |
|-----------|-----|--------|---------|
| **Binary Defense** | Pre-configured (BDS_Ban) | Binary Defense | Malicious IPs |
| **Botvrij** | Pre-configured (Botvrij_IP) | Botvrij.eu | Dutch CERT feed |
| **Cyber Crime Tracker** | Pre-configured (CCT_IP) | Cybercrime WHQ | Active C&C servers |
| **Darklist.de** | Pre-configured (Darklist) | Darklist.de | German security feed |
| **ISC Suspicious** | Pre-configured (ISC_Miner) | SANS ISC | Cryptomining IPs |
| **Stamparm ipsum L3** | `https://raw.githubusercontent.com/stamparm/ipsum/master/levels/3.txt` | Stamparm | Statistical threats (med) |
| **Stamparm ipsum L4** | `https://raw.githubusercontent.com/stamparm/ipsum/master/levels/4.txt` | Stamparm | Statistical threats (high) |

---

#### **Scanner Detection**
**Settings:**
- List Action: `Deny Inbound`
- Update Frequency: `Every day`
- Interface: `WAN`

**Feeds to Include:**

| Feed Name | URL | Source | Purpose |
|-----------|-----|--------|---------|
| **Maltrail Scanners** | Pre-configured (Maltrail_Scanners_All) | Maltrail | Port scanners |
| **ISC Shadowserver** | Pre-configured (ISC_Shadowserver) | SANS ISC | Shadowserver scanners |
| **ISC Shodan** | Pre-configured (ISC_Shodan) | SANS ISC | Shodan scanners |

---

#### **Cryptominer Blocking**
**Settings:**
- List Action: `Deny Both`
- Update Frequency: `Every day`
- Interface: `WAN`

**Feeds to Include:**

| Feed Name | URL | Source | Purpose |
|-----------|-----|--------|---------|
| **Monero Mining** | `https://gui.xmr.pm/files/block.txt` | XMR.pm | Malicious Monero mining nodes |
| **FireHOL CoinBlocker** | `https://iplists.firehol.org/files/coinbl_ips.ipset` | FireHOL | Cryptomining IPs |

---

### ⚠️ **Feeds to AVOID (Known Issues)**

| Feed Name | Issue | Recommendation |
|-----------|-------|----------------|
| **Talos/Cisco Blacklist** | Returns 404 | Remove/Skip |
| **DangerRulez** | 301 redirect (moved) | Remove/Skip |
| **NVT BlackList** | 301 redirect (moved) | Remove/Skip |
| **MyIP.ms** | SSL certificate errors | Skip (use FireHOL instead) |
| **Individual BlockList.de categories** | Redundant | Use "All" feed instead |

---

## DNS Block Lists (DNSBL)

### General DNSBL Settings:
- **List Action:** `Unbound`
- **Update Frequency:** `Every day`
- **TLD Exclusion:** Enable (prevents breaking entire TLDs)
- **CNAME Validation:** Enable (blocks CNAME cloaking)

---

### **Top-Tier DNSBL Lists (2025)**

#### **Comprehensive All-in-One (Pick ONE)**

| List Name | URL | Coverage | False Positive Risk |
|-----------|-----|----------|---------------------|
| **OISD** ⭐ RECOMMENDED | Pre-configured in pfBlockerNG | Ads + Trackers + Malware | Low |
| **Hagezi Pro** | `https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/domains/pro.txt` | Aggressive blocking | Medium |
| **1Hosts Pro** | `https://o0.pages.dev/Pro/domains.txt` | Comprehensive | Medium-High |

> **Note:** OISD is recommended for most users - excellent balance of coverage and low false positives.

---

#### **Malware & Phishing Protection**

**Group Name:** `Malicious_Domains`  
**Action:** `Unbound` | **Update:** `Every day`

| Feed Name | URL/Location | Source | Purpose |
|-----------|--------------|--------|---------|
| **URLhaus** | Pre-configured (Abuse_urlhaus) | Abuse.ch | Malware distribution URLs |
| **OpenPhish** | Pre-configured in pfBlockerNG | OpenPhish | Phishing domains |
| **PhishTank** | Pre-configured in pfBlockerNG | PhishTank | Community phishing |
| **Malc0de** | Pre-configured (Malc0de) | Malc0de | Malware domains |
| **VXVault** | Pre-configured (VXVault) | VXVault | Malware repository |
| **Joewein Base** | Pre-configured (Joewein_base) | Joewein | Spam/malware |
| **yHosts** | Pre-configured (yHosts) | yHosts | Adware/malware |

---

#### **Threat Intelligence Feeds**

**Group Name:** `Threat_Intel`  
**Action:** `Unbound` | **Update:** `Every day`

| Feed Name | URL/Location | Source | Purpose |
|-----------|--------------|--------|---------|
| **Hagezi TIF** | `https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/domains/tif.txt` | Hagezi | Threat intelligence |
| **Bambenek DGA** | Pre-configured (BBC_DGA) | Bambenek | Domain generation algorithms |
| **Pulsedive** | Pre-configured (Pulsedive_BD) | Pulsedive | Community threat intel |

---

#### **Advertising & Tracking (Firebog Collection)**

**Group Name:** `Firebog_Advertising`  
**Action:** `Unbound` | **Update:** `Every day`

| Feed Name | Pre-configured As | Purpose |
|-----------|-------------------|---------|
| **AdGuard DNS** | Adguard_DNS | Ads and trackers |
| **Admiral Anti-Adblock** | LanikSJ | Anti-adblock detection |
| **Anudeep Blacklist** | Anudeep_BL | Comprehensive ads |
| **EasyList** | Easylist_FB | Classic ad blocking |
| **Peter Lowe Adservers** | PL_Adservers | Ad servers |
| **Ad-Wars** | Ad_Wars | Aggressive ad blocking |

**Group Name:** `Firebog_Trackers`  
**Action:** `Unbound` | **Update:** `Every day`

| Feed Name | Pre-configured As | Purpose |
|-----------|-------------------|---------|
| **EasyPrivacy** | Easyprivacy | Privacy protection |
| **Lightswitch05** | Lightswitch05 | Ads & tracking |
| **Perflyst Android** | Perflyst_Android | Android trackers |
| **Perflyst SmartTV** | Perflyst_TV | SmartTV telemetry |

---

#### **Cryptojacking Protection**

**Group Name:** `Cryptojackers`  
**Action:** `Unbound` | **Update:** `Every day`

| Feed Name | Pre-configured As | Purpose |
|-----------|-------------------|---------|
| **NoCoin** | NoCoin | Cryptojacking scripts |
| **Monero Miner** | MoneroMiner | Monero mining sites |

---

### **Optional DNSBL Groups**

#### **EasyList (Language-Specific)**
Only enable if you need language-specific ad blocking:
- EasyList_German, EasyList_French, EasyList_Spanish, etc.

#### **Social Media Blocking** (Optional)
- Anudeep_Facebook - Blocks Facebook domains

#### **DoH/VPN Bypass Prevention** (Advanced)
- TheGreatWall_DoH - Blocks DNS-over-HTTPS resolvers
- Dibdot_DoH - Additional DoH blocking

> **⚠️ Warning:** Blocking DoH may break some modern browsers and apps that rely on encrypted DNS.

---

## Pre-Configured Feeds from pfBlockerNG

pfBlockerNG includes many pre-configured feeds accessible via `Firewall > pfBlockerNG > Feeds`. Click the **"+"** icon to add them instantly.

### **Highly Recommended Pre-Configured Feeds:**

#### **IPv4 - Critical Threats:**
- ✅ **ET_Comp** (Emerging Threats Compromised)
- ✅ **Pulsedive** (Community threat intelligence)

#### **IPv4 - Inbound Protection:**
- ✅ **BBC_C2** (Bambenek C&C tracker)
- ✅ **SFS_Toxic** (Stop Forum Spam - toxic IPs)

#### **IPv4 - Scanners:**
- ✅ **ISC_Shadowserver**
- ✅ **ISC_Shodan**

#### **DNSBL - All-in-One:**
- ⭐ **OISD** (Compilation category) - **START HERE!**

#### **DNSBL - Phishing:**
- ✅ **OpenPhish**
- ✅ **Abuse_urlhaus**

#### **DNSBL - Cryptojacking:**
- ✅ **NoCoin**

---

## Performance Tuning

### **Update Frequency Recommendations:**

| Group Type | Recommended Frequency | Reasoning |
|------------|----------------------|-----------|
| **Critical Threats** | Every hour | Fast-changing threat landscape |
| **Inbound Protection** | Every 4 hours | Balance between freshness and load |
| **Scanners** | Every day | Scanner IPs change slowly |
| **DNSBL** | Every day | Domain lists are relatively stable |
| **Cryptominers** | Every day | Mining pools don't change often |

### **Hardware Considerations:**

**Low-End Hardware** (2GB RAM, 2 cores):
- Limit to 5-10 IP lists
- Use OISD instead of multiple DNSBL groups
- Update frequency: 4-6 hours minimum

**Mid-Range Hardware** (4GB RAM, 4 cores):
- 10-20 IP lists comfortable
- Multiple DNSBL groups fine
- Update frequency: 1-4 hours

**High-End Hardware** (8GB+ RAM, 8+ cores):
- 30+ lists no problem
- Hourly updates fine
- Full Firebog collection supported

### **Monitoring Performance:**

Check these if pfSense feels slow:
```bash
# CPU during updates
top -P | grep php

# Memory usage
top -o res | head -20

# Firewall table sizes
pfctl -vvss | grep "table-entries"
```

**Red flags:**
- CPU pegged at 100% for >5 minutes during updates
- Memory usage >80%
- pfBlockerNG logs showing timeouts

**Solutions:**
- Reduce update frequency
- Consolidate redundant feeds
- Remove low-value feeds
- Increase hardware resources

---

## Whitelisting Guide

### **Comprehensive Whitelist File**

We provide a comprehensive, curated whitelist file that you can import directly into pfBlockerNG:

📁 **File Location:** [`config/dnsbl_whitelist.txt`](dnsbl_whitelist.txt)

**Format:** The file uses standard pfBlockerNG whitelist format:
- One domain per line
- Comments start with `#` (ignored by pfBlockerNG)
- Section headers use `##` for organization
- Wildcard subdomains use `.domain.com` syntax

**To Import:**
1. Navigate to `Firewall > pfBlockerNG > DNSBL > DNSBL Groups`
2. Create a new group with **List Action: Whitelist**
3. Copy/paste the contents of `dnsbl_whitelist.txt` into the custom list
4. Or use a URL if hosting the file (e.g., raw GitHub URL)
5. Save and force update

### **Whitelist Categories (62 Sections)**

The whitelist is organized into logical categories:

#### **Core Infrastructure**
| Category | Purpose |
|----------|---------|
| Identity / Login / Certificates | SSO, OAuth, OCSP, certificate validation |
| Apple Services | iCloud, iTunes, App Store, developer tools |
| Google Core | Search, APIs, authentication |

#### **Streaming & Media**
| Category | Purpose |
|----------|---------|
| Streaming Platforms — Live & Video | YouTube, Twitch, Kick |
| TikTok (multiple sections) | Core app, livestream, CDN, APIs |
| Media Streaming / Music / TV | Spotify, Netflix, Prime Video, etc. |
| Plex / Jellyfin / Emby | Personal media server connectivity |

#### **Gaming**
| Category | Purpose |
|----------|---------|
| Gaming / Consoles | Xbox, PlayStation, Nintendo, Steam |
| PC Gaming Platforms | Epic, GOG, EA, Ubisoft launchers |
| Anti-Cheat / Multiplayer | EasyAntiCheat, BattlEye, Riot Vanguard |
| Gaming Social | Discord, Guilded |

#### **Social Media & Messaging**
| Category | Purpose |
|----------|---------|
| LinkedIn, Reddit, X/Twitter | Professional and general social |
| Facebook/Meta, Instagram, Threads | Meta platforms (core only, no tracking) |
| Bluesky, Mastodon | Decentralized/federated social |
| Snapchat, Pinterest, Tumblr | Visual social platforms |
| WhatsApp, Telegram | Messaging apps |

#### **Creator & Content Platforms**
| Category | Purpose |
|----------|---------|
| Patreon, Ko-fi | Creator monetization |
| Substack, Medium, Quora | Publishing and knowledge |
| DeviantArt, Behance, Dribbble | Art and design communities |
| Letterboxd, Goodreads, Last.fm | Entertainment social |

#### **Productivity & Work**
| Category | Purpose |
|----------|---------|
| Productivity / Work Essentials | Notion, Slack, Zoom, Figma, Trello |
| Cloud Storage | Dropbox, Google Drive, OneDrive, iCloud |
| Developer Platforms | GitHub, GitLab, npm, Docker Hub |
| AI / LLM Tools | OpenAI, Claude, Gemini, Copilot |

#### **Utilities**
| Category | Purpose |
|----------|---------|
| CDN / Static Assets | Cloudflare, Akamai, Fastly, jsDelivr |
| Privacy & Secure Communications | Signal, ProtonMail, Bitwarden, Mullvad |
| Search Engines (Privacy-Focused) | DuckDuckGo, Startpage, Brave Search |
| E-commerce / Shopping | Amazon, eBay, Etsy, PayPal |
| News & Publications | Major news outlets |
| Weather, Maps, Smart Home | Utility services |

#### **Adult Content (18+ Only)**
| Category | Purpose |
|----------|---------|
| Adult Content | Major adult entertainment sites (Pornhub, XVideos, OnlyFans, Fansly, etc.) |

> **⚠️ Warning:** The Adult Content section is included for users who choose to allow such content. It includes privacy warnings about tracking. **Remove this section entirely** from your whitelist if you want adult content to remain blocked (default behavior with most DNSBL lists like OISD).

### **Critical Services to Whitelist:**

#### **CDN & Cloud Services** (Create "CDN" Permit group):
```
# CloudFlare
cloudflare.com
cloudflare.net
cf-ns.com

# Akamai
akamai.com
akamai.net
akamaitechnologies.com

# AWS CloudFront
cloudfront.net
amazonaws.com

# Fastly
fastly.com
fastly.net

# Bunny CDN (if using)
bunny.net
bunnycdn.com
```

#### **Video Conferencing** (Create "Meetings" Permit group):
```
# Zoom (CRITICAL)
zoom.us
zoomgov.com

# Microsoft Teams
teams.microsoft.com
skype.com

# Google Meet
meet.google.com
hangouts.google.com
```

#### **Streaming Services** (if used):
```
netflix.com
hulu.com
disneyplus.com
primevideo.com
youtube.com
```

#### **Microsoft Services**:
```
microsoft.com
msftncsi.com  # Network Connectivity Status Indicator
office.com
office365.com
windows.net
live.com
```

#### **Apple Services**:
```
apple.com
icloud.com
mzstatic.com
```

#### **Google Services**:
```
google.com
googleapis.com
gstatic.com
googleusercontent.com
```

### **How to Create Permit Lists:**

1. **For IP Lists**: `Firewall > pfBlockerNG > IP`
   - Create new group (e.g., "CDN_Permit")
   - List Action: `Permit Outbound` or `Permit Both`
   - Add feed URLs or manual IPs
   - **Important:** Permit lists must be processed BEFORE deny lists

2. **For DNSBL**: `Firewall > pfBlockerNG > DNSBL`
   - Create new group with List Action: `Whitelist`
   - Add domains (one per line)
   - Save and update

### **Testing for False Positives:**

1. Check pfBlockerNG alerts: `Firewall > pfBlockerNG > Reports > Alerts`
2. Look for repeated blocks of same domain/IP
3. Check DNSBL logs: `Firewall > pfBlockerNG > DNSBL > DNSBL Logs`
4. Temporarily disable groups to identify culprit
5. Add exceptions as needed

### **Common False Positives:**

- **Smart TVs**: May trigger on tracking domains (Perflyst lists)
- **Gaming Consoles**: Microsoft/Sony telemetry
- **IoT Devices**: Cloud connectivity checks
- **Banking Apps**: Ad network SDKs embedded in apps
- **News Sites**: Heavy ad/tracker usage

---

## Privacy & Security Considerations

The comprehensive whitelist includes many services that have known privacy or security concerns. These are included because users may legitimately need them, but you should understand the risks.

> **⚠️ Important:** Review the whitelist and remove any services you don't use. The more you whitelist, the larger your attack surface.

### **Services with Privacy Concerns**

The whitelist file includes `# PRIVACY NOTICE` comments for services with significant concerns. Here's a summary:

#### **Chinese-Owned Services**

| Service | Owner | Concerns |
|---------|-------|----------|
| **TikTok** | ByteDance (China) | Potential government data access under Chinese national security laws; extensive data collection (device info, location, browsing, biometrics); algorithm manipulation concerns; banned on government devices in multiple countries; pending US legislation for ban/sale |

**Recommendation:** Only whitelist if actively used and you accept the risks. Consider blocking on work/sensitive networks.

#### **Meta Platforms (Facebook, Instagram, WhatsApp, Threads)**

| Concern | Details |
|---------|---------|
| Cross-platform tracking | Unified tracking across all Meta properties |
| Privacy violations | $5B FTC fine (2019), Cambridge Analytica scandal |
| Behavioral profiling | Extensive data harvesting for targeted advertising |
| WhatsApp metadata | Even with E2E encryption, metadata is collected and shared |

**Recommendation:** Core domains are whitelisted; tracking domains remain blocked. Consider Signal for private messaging.

#### **Messaging Apps — Encryption Concerns**

| Service | E2E Encrypted? | Concerns |
|---------|----------------|----------|
| **WhatsApp** | Yes (messages) | Metadata collected by Meta |
| **Telegram** | ❌ Not by default | Only "Secret Chats" are E2E; regular chats stored on servers |
| **Discord** | ❌ No | All messages readable by Discord; provided to law enforcement |
| **Zoom** | Partial | Improved since 2020 controversy; still not fully E2E |

**Recommendation:** Use Signal for sensitive communications. Discord/Telegram are fine for non-sensitive use.

#### **VPNs with Questionable Ownership**

The whitelist **comments out** (blocks) these VPNs with warnings:

| VPN | Owner | Concerns | Reference |
|-----|-------|----------|-----------|
| **ExpressVPN** | Kape Technologies | Former Crossrider (adware platform); CIO involved in UAE surveillance ops | [CyberInsider](https://cyberinsider.com/kape-technologies-owns-expressvpn-cyberghost-pia-zenmate-vpn-review-sites/) |
| **CyberGhost** | Kape Technologies | Same ownership as ExpressVPN | |
| **Private Internet Access** | Kape Technologies | Acquired 2019; same concerns | |
| **Zenmate** | Kape Technologies | Part of Kape portfolio | |
| **NordVPN** | Nord Security | 2019 breach not disclosed for 1+ year; Tesonet data mining ties | |

**Recommended VPNs (whitelisted):** Mullvad, ProtonVPN, IVPN

#### **Password Managers**

| Service | Status | Concerns |
|---------|--------|----------|
| **LastPass** | ⚠️ Commented out | Multiple breaches (2022-2023); encrypted vaults stolen |
| **Bitwarden** | ✅ Whitelisted | Open source, audited, recommended |
| **1Password** | ✅ Whitelisted | Strong track record |
| **KeePassXC** | ✅ Whitelisted | Local/offline, open source |

#### **AI/LLM Services**

| Concern | Details |
|---------|---------|
| Data retention | Conversations may be logged for 30+ days |
| Training data | Some providers use conversations for model training |
| Confidentiality | Don't share sensitive/proprietary information |

**Recommendation:** Check each provider's data retention policy. Opt out of training data where possible.

#### **Smart Home / IoT**

| Service | Concerns |
|---------|----------|
| Amazon Ring | Partners with law enforcement; shares footage |
| Google Nest | Data collection for advertising profiles |
| Smart TVs | Viewing habit collection; built-in microphones |
| Voice assistants | Voice data recorded and analyzed |

**Recommendation:** Home Assistant and Homebridge are privacy-focused local alternatives (whitelisted).

#### **Other Considerations**

| Service | Concern |
|---------|---------|
| **LinkedIn** | Extensive tracking; data scraping for AI training; multiple breaches |
| **Snapchat** | Location tracking via Snap Map |
| **Pinterest** | Extensive tracking and profiling |

#### **Adult Content**

The whitelist includes an optional Adult Content section with major adult entertainment sites. 

| Concern | Details |
|---------|---------|
| **Tracking** | Adult sites often have extensive third-party tracking |
| **Privacy** | ISPs may log DNS queries; use encrypted DNS (DoH/DoT) |
| **Malvertising** | Higher risk of malicious ads on adult sites |

**Recommendations:**
- Remove the Adult Content section entirely if you want content blocked
- Use a privacy-focused browser with strict tracking protection
- Consider using Firefox containers or a separate browser profile
- Ensure encrypted DNS is enabled to prevent ISP logging

### **Your Threat Model**

Before importing the whitelist, consider:

1. **What do you actually use?** Remove services you don't need
2. **Is this a work network?** Consider stricter policies
3. **Do you have children?** Consider blocking social media entirely
4. **Are you in a high-risk profession?** Journalists, activists should use minimal whitelisting

### **Recommended Whitelist Strategy**

1. **Start with infrastructure only**: Identity, CDN, certificates
2. **Add work tools**: Productivity, cloud storage, video conferencing
3. **Add personal services selectively**: Only what you actively use
4. **Review monthly**: Remove services you've stopped using
5. **Keep tracking blocked**: The whitelist excludes tracking domains intentionally

---

## Common Issues

### **Issue: pfBlockerNG Updates Failing**

**Symptoms:** Feeds showing "Download FAIL" in logs

**Solutions:**
1. Check feed URL with curl: `curl -I <feed_url>`
2. If 404/301/SSL error, remove or replace feed
3. Known broken feeds: Talos, DangerRulez, NVT_BL, MyIP (SSL)

### **Issue: Internet Breaks After Enabling Lists**

**Symptoms:** Can't access websites, apps fail to connect

**Solutions:**
1. Check `Firewall > pfBlockerNG > Reports > Alerts` for recent blocks
2. Whitelist critical services (see Whitelisting Guide above)
3. Temporarily disable suspect list group
4. Test gradually: enable one group at a time

### **Issue: High CPU Usage During Updates**

**Symptoms:** pfSense sluggish hourly, PHP processes at 100%

**Solutions:**
1. Reduce update frequency (4 hours instead of 1 hour)
2. Remove redundant feeds
3. Stagger update times for different groups
4. Upgrade hardware if needed

### **Issue: Firewall Tables Full**

**Symptoms:** Error "table-entries limit of X exceeded"

**Solutions:**
1. Reduce number of IP lists
2. Consolidate to aggregated feeds (FireHOL instead of individual)
3. Increase table limits: `System > Advanced > Firewall/NAT`
4. Use DNSBL instead of IP lists where possible

### **Issue: DNSBL Not Blocking**

**Symptoms:** Ads still showing, malware domains resolving

**Solutions:**
1. Verify Unbound is enabled: `Services > DNS Resolver`
2. Check DNSBL is set to "Unbound" mode
3. Force update: `Firewall > pfBlockerNG > Update > Reload`
4. Test with: `nslookup doubleclick.net` (should return 0.0.0.0 or block page)

---

## Integration with Suricata IPS

If running Suricata alongside pfBlockerNG:

### **Recommended Division of Labor:**

**pfBlockerNG handles:**
- IP reputation (bad actors, scanners, botnet C&C)
- DNS blocking (ads, trackers, malware domains)

**Suricata handles:**
- Exploit detection (buffer overflows, SQL injection, etc.)
- Protocol-specific attacks
- Signature-based malware detection

### **Avoid Duplication:**

1. Disable Suricata IP reputation rules if using pfBlockerNG IP lists
2. Keep Suricata classtype-based blocking (exploit-kit, trojan-activity, etc.)
3. Let pfBlockerNG handle domain-based blocking (faster, less CPU)

### **Benefits of Both:**

- **Defense in depth**: pfBlockerNG blocks known-bad, Suricata catches unknown attacks
- **Reduced Suricata load**: pfBlockerNG filters traffic before Suricata sees it
- **Comprehensive logging**: Different tools, different perspectives

---

## Quick Reference: Feed Sources

### **Trusted IP Feed Sources (2025):**
- **Abuse.ch** - https://abuse.ch/ - Malware tracking (SSL, Feodo, URLhaus)
- **FireHOL** - https://iplists.firehol.org/ - Aggregator of 400+ feeds (recommended)
- **CINS Army** - https://cinsscore.com/ - C&C server tracking
- **Emerging Threats** - https://rules.emergingthreats.net/ - Proofpoint threat intel
- **Spamhaus** - https://www.spamhaus.org/drop/ - Known bad actors
- **Stamparm** - https://github.com/stamparm/ - Maltrail, ipsum statistical blocking

### **Trusted DNSBL Sources (2025):**
- **OISD** - https://oisd.nl/ - All-in-one, low false positives (⭐ recommended)
- **Hagezi** - https://github.com/hagezi/dns-blocklists - Top-tier, regularly updated
- **1Hosts** - https://o0.pages.dev/ - Comprehensive, aggressive
- **Firebog** - https://firebog.net/ - Curated collection
- **AdGuard** - https://adguard.com/en/filters.html - Well-maintained

---

## Implementation Checklist

### **Phase 1: Preparation** (Before enabling any feeds)
- [ ] Backup pfSense configuration
- [ ] Create CDN permit list
- [ ] Create video conferencing permit list
- [ ] Document current network usage patterns
- [ ] Identify critical services that must stay online

### **Phase 2: Initial Deployment** (Week 1)
- [ ] Enable Critical Threats IP group only
- [ ] Enable OISD DNSBL only
- [ ] Force update and monitor for 48 hours
- [ ] Check logs for false positives
- [ ] Add whitelists as needed

### **Phase 3: Expansion** (Week 2)
- [ ] Enable Inbound Protection IP group
- [ ] Add Malicious Domains DNSBL group
- [ ] Monitor for 48 hours
- [ ] Adjust whitelists

### **Phase 4: Full Deployment** (Week 3+)
- [ ] Enable remaining IP groups (scanners, additional)
- [ ] Add Firebog DNSBL groups
- [ ] Add cryptojacking protection
- [ ] Fine-tune update frequencies
- [ ] Document any custom whitelists for your environment

### **Ongoing Maintenance:**
- [ ] Monthly: Review pfBlockerNG logs for patterns
- [ ] Monthly: Check for deprecated feeds
- [ ] Quarterly: Review firewall rules for optimizations
- [ ] Yearly: Full configuration review and cleanup

---

## Support & Community

**Official pfBlockerNG Documentation:**
- Package documentation in pfSense
- Forum: https://forum.netgate.com/

**Feed Maintainer Communities:**
- Firebog: https://firebog.net/
- Hagezi: https://github.com/hagezi/dns-blocklists
- OISD: https://oisd.nl/

**Testing Tools:**
- **DNSBL Testing**: `nslookup <domain>` should return 0.0.0.0 for blocked domains
- **IP Block Testing**: Check `Firewall > pfBlockerNG > Reports > Alerts`
- **Whitelist Testing**: `pfctl -t pfB_<group>_v4 -T test <IP>`

---

**Version:** 1.1  
**Last Updated:** December 2025  
**Tested On:** pfSense 2.8.x with pfBlockerNG-devel 3.x  
**License:** Mozilla Public License 2.0

---

> **Disclaimer:** This configuration is provided as-is based on production testing. Your mileage may vary depending on your specific environment, hardware, and usage patterns. Always test changes in stages and maintain proper backups. The author is not responsible for any network disruptions or false positives. Privacy/security assessments are based on publicly available information and should be independently verified for your threat model.
