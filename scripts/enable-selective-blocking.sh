#!/bin/bash
# Enable Selective IPS Blocking on pfSense Suricata
# Blocks only high-confidence threats while keeping everything else in alert mode

set -e

PFSENSE_HOST="${PFSENSE_HOST:-192.168.1.1}"
PFSENSE_USER="${PFSENSE_USER:-root}"

# High-confidence categories safe to block
HIGH_CONFIDENCE_RULES=(
    # Tier 1: Zero tolerance - definitely malicious
    "botcc"                 # Botnet C2
    "compromised"           # Known bad hosts
    "malware"               # Confirmed malware
    "exploit_kit"           # Exploit frameworks
    "worm"                  # Worm propagation
    "ciarmy"                # IP reputation
    "drop"                  # Spamhaus DROP
    "dshield"               # DShield attackers
    
    # Tier 2: Very safe - minimal false positives
    "trojan"                # Trojan detection
    "phishing"              # Phishing sites
    "shellcode"             # Shellcode patterns
    "adware_pup"            # Adware/PUPs
    "mobile_malware"        # Mobile threats
)

echo "=========================================="
echo "Selective IPS Blocking Configuration"
echo "=========================================="
echo ""
echo "This will enable DROP (blocking) for these categories:"
for rule in "${HIGH_CONFIDENCE_RULES[@]}"; do
    echo "  - emerging-${rule}.rules"
done
echo ""
echo "All other rules will remain in ALERT (detect-only) mode"
echo ""
read -p "Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "Creating dropsid.conf file..."

# Build the dropsid.conf content
DROPSID_CONTENT=""
for rule in "${HIGH_CONFIDENCE_RULES[@]}"; do
    DROPSID_CONTENT="${DROPSID_CONTENT}re:emerging-${rule}.*\n"
done

# Get list of active Suricata instances
echo "Detecting active Suricata instances..."
INSTANCES=$(ssh ${PFSENSE_USER}@${PFSENSE_HOST} "ls -d /usr/local/etc/suricata/suricata_*/ 2>/dev/null")

if [ -z "$INSTANCES" ]; then
    echo "ERROR: No Suricata instances found!"
    exit 1
fi

echo "Found instances:"
echo "$INSTANCES" | while read instance; do
    echo "  - $instance"
done

# Deploy dropsid.conf to each instance
echo ""
echo "Deploying dropsid.conf to each instance..."

echo "$INSTANCES" | while read instance; do
    instance_name=$(basename "$instance")
    echo "  Configuring $instance_name..."
    
    # Create dropsid.conf
    ssh ${PFSENSE_USER}@${PFSENSE_HOST} "cat > ${instance}dropsid.conf << 'EOF'
# Selective IPS Blocking Configuration
# Only these high-confidence categories will be blocked (DROP)
# All other rules remain in ALERT mode
# Generated: $(date)

# Tier 1: Zero tolerance threats
re:emerging-botcc.*
re:emerging-compromised.*
re:emerging-malware.*
re:emerging-exploit_kit.*
re:emerging-worm.*
re:emerging-ciarmy.*
re:emerging-drop.*
re:emerging-dshield.*

# Tier 2: Very safe to block
re:emerging-trojan.*
re:emerging-phishing.*
re:emerging-shellcode.*
re:emerging-adware_pup.*
re:emerging-mobile_malware.*
EOF
"
done

echo ""
echo "=========================================="
echo "Configuration Complete!"
echo "=========================================="
echo ""
echo "⚠️  IMPORTANT: You must now:"
echo "1. Log into pfSense WebGUI"
echo "2. Go to: Services > Suricata > Interface Settings"
echo "3. For EACH interface, click Edit"
echo "4. Go to: 'IPS Mode' section"
echo "5. Change mode to: 'Inline' (if not already)"
echo "6. Go to: 'SID MGMT' tab"
echo "7. Enable 'Auto-manage SID state lists'"
echo "8. Verify dropsid.conf is listed"
echo "9. Click 'Save'"
echo "10. Go to: Services > Suricata > Updates tab"
echo "11. Click 'Update Rules' to apply changes"
echo ""
echo "Verification:"
echo "  ssh root@${PFSENSE_HOST} 'grep -c \"^re:\" /usr/local/etc/suricata/suricata_*/dropsid.conf'"
echo ""
echo "Monitor blocks:"
echo "  ssh root@${PFSENSE_HOST} 'tail -f /var/log/suricata/suricata_*/eve.json | grep '\"action\":\"blocked\"''"
echo ""
