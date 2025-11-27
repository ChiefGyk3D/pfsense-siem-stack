#!/usr/local/bin/php-cgi -f
<?php
// SPDX-FileCopyrightText: 2025 ChiefGyk3D
// SPDX-License-Identifier: MPL-2.0

/**
 * Telegraf ARP Table with MAC Vendor Lookup
 * 
 * Collects ARP table entries and enriches them with MAC vendor information
 * from the nmap MAC prefixes database.
 * 
 * Output Format: InfluxDB Line Protocol
 * Measurement: arp_table
 * Tags: mac_address, vendor, interface, ip_address
 * Fields: expires_in (seconds), permanent (boolean)
 */

$host = gethostname();

// Load MAC vendor database
function load_mac_vendors() {
    $vendors = [];
    $db_paths = [
        '/usr/local/share/nmap/nmap-mac-prefixes',  // If nmap installed
        '/usr/local/share/oui.txt',                  // Custom OUI database
        '/var/db/oui.txt'                           // Alternative location
    ];
    
    foreach ($db_paths as $path) {
        if (file_exists($path)) {
            $lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            foreach ($lines as $line) {
                // nmap format: 000C29 VMware
                if (preg_match('/^([0-9A-Fa-f]{6})\s+(.+)$/', $line, $matches)) {
                    $vendors[strtoupper($matches[1])] = trim($matches[2]);
                }
                // IEEE OUI format: 00-0C-29   (hex)    VMware, Inc.
                elseif (preg_match('/^([0-9A-Fa-f]{2})-([0-9A-Fa-f]{2})-([0-9A-Fa-f]{2})\s+\(hex\)\s+(.+)$/', $line, $matches)) {
                    $prefix = strtoupper($matches[1] . $matches[2] . $matches[3]);
                    $vendors[$prefix] = trim($matches[4]);
                }
            }
            break;  // Use first found database
        }
    }
    
    return $vendors;
}

// Lookup vendor from MAC address
function get_mac_vendor($mac, $vendors) {
    // Extract first 6 hex digits (OUI prefix)
    $mac = str_replace([':', '-', '.'], '', strtoupper($mac));
    $prefix = substr($mac, 0, 6);
    
    return isset($vendors[$prefix]) ? $vendors[$prefix] : 'Unknown';
}

// Parse ARP table
function get_arp_table() {
    $arp_output = shell_exec('arp -an');
    $entries = [];
    
    if (!$arp_output) {
        return $entries;
    }
    
    $lines = explode("\n", trim($arp_output));
    foreach ($lines as $line) {
        // Format: ? (192.168.1.10) at 18:e8:29:4f:90:b9 on lagg1 expires in 630 seconds [ethernet]
        if (preg_match('/\?\s+\(([^\)]+)\)\s+at\s+([0-9a-f:]{17})\s+on\s+(\S+)(?:\s+expires in\s+(\d+)\s+seconds)?(?:\s+(permanent))?/', $line, $matches)) {
            $ip = $matches[1];
            $mac = $matches[2];
            $interface = $matches[3];
            $expires = isset($matches[4]) ? intval($matches[4]) : 0;
            $permanent = isset($matches[5]) ? 1 : 0;
            
            $entries[] = [
                'ip' => $ip,
                'mac' => $mac,
                'interface' => $interface,
                'expires' => $expires,
                'permanent' => $permanent
            ];
        }
    }
    
    return $entries;
}

// Escape special characters for InfluxDB line protocol
function influx_escape($str) {
    return str_replace([',', ' ', '='], ['\,', '\ ', '\='], $str);
}

// Main execution
$vendors = load_mac_vendors();
$arp_entries = get_arp_table();

if (empty($vendors)) {
    // Output warning to stderr (Telegraf will log it)
    fwrite(STDERR, "Warning: MAC vendor database not found. Install nmap package or download OUI database.\n");
    fwrite(STDERR, "Run: pkg install pfSense-pkg-nmap\n");
}

foreach ($arp_entries as $entry) {
    $vendor = get_mac_vendor($entry['mac'], $vendors);
    
    // Sanitize values for InfluxDB
    $mac_escaped = influx_escape($entry['mac']);
    $vendor_escaped = influx_escape($vendor);
    $interface_escaped = influx_escape($entry['interface']);
    $ip_escaped = influx_escape($entry['ip']);
    
    // Output InfluxDB line protocol
    // Format: measurement,tag=value field=value timestamp
    printf("arp_table,host=%s,mac=%s,vendor=%s,interface=%s,ip=%s expires=%d,permanent=%d\n",
        $host,
        $mac_escaped,
        $vendor_escaped,
        $interface_escaped,
        $ip_escaped,
        $entry['expires'],
        $entry['permanent']
    );
}
?>
