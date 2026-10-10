<?php
/*
 * Adds the forwarder watchdog to the pfSense Cron package (config.xml), so the
 * entry survives pfSense upgrades. Idempotent. Run on pfSense:
 *   php /tmp/pfsense-add-watchdog-cron.php
 */
require_once("config.inc");
require_once("/usr/local/pkg/cron.inc");

$cmd = "/usr/local/bin/suricata-forwarder-watchdog.sh";
$items = config_get_path('cron/item', array());
foreach ($items as $item) {
	if (($item['command'] ?? '') === $cmd) {
		echo "present\n";
		exit(0);
	}
}
$items[] = array(
	'minute' => '*', 'hour' => '*', 'mday' => '*', 'month' => '*', 'wday' => '*',
	'who' => 'root', 'command' => $cmd,
);
config_set_path('cron/item', $items);
write_config("pfsense-siem-stack: forwarder watchdog cron entry");
cron_sync_package();
echo "added\n";
