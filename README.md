# Asuswrt-Merlin Scripts and configs

Most scripts which trigger off Asuswrt-Merlin events use a single line in the `/jffs/scripts/<event-script>` file (to make addition/removal easier), in the form `. /jffs/scripts/.<script>.event.sh <event-script> "$@" ## script ##`.
The exception to this is `services-start`/`services-stop` and `post-mount`/`unmount`, where a line is added to run scripts from the `/jffs/scripts/services.d` and `/jffs/scripts/mount.d` folders respectively. Scripts in these folders prefixed with `S##` (where # is a number) will be run on the start/mount event, and those prefixed with `K##` will be run on the stop/unmount event, allowing better run order control.

## configs

### nanorc

Pretty up nano a bit and get multi-line pastes working from putty.

### profile.add

Clean up ssh environment and add some aliases.

## scripts

### acme-renew

A renew script for acme.sh.

### alias.sh

Functions to extend the `service` command to `/opt`, and colour `opkg` output.

### ddns-start

A poor attempt at getting IPv4 and IPv6 ddns to update concurrently.

### dnsmasq.postconf

Use ISP DNS for NTP if DNS privacy is enabled.

### init-start

Add a warning to the webUI if access from WAN is enabled, remove the warning when anonymous samba access is enabled. Adds an event when service-events are skipped.

### service-event-skip

Starts services if they were skipped.

## scripts/include

### input.sh

Played around a bit with ssh UIs. Seems to be more trouble than it's worth.

### servicelist.sh

A list of services from [services.c](https://github.com/RMerl/asuswrt-merlin.ng/blob/master/release/src/router/rc/services.c) made for the aliased service command. Most likely incomplete, outdated and inaccurate.

### string.sh

Various string functions because I can never remember how sed works.

### text.sh

Some escape sequence constants.

## scripts/install

### acme.sh

A wrapper for installing [acme.sh](https://github.com/acmesh-official/acme.sh). Adds cron job to check for renewals at a random time between 12pm-1am, and an `acme` command.

### adblock.sh

A dnsmasq based adblocker. Uses a set of hosts/domains lists which are updated (defaults to some time between 3-4am daily) and consolidated into a hosts file for dnsmasq.

### entware.sh

Installer for entware.

### logng.sh

Adds scripts to help run syslog-ng. syslog-ng startup is delayed if ntp isn't synced, and when switching from syslogd/klogd to syslog-ng, timestamps from before ntp sync are corrected. The `/www/Main_LogStatus_Content.asp` file is mounted over, and changed to show logs in a table instead of a textarea.

The layout of the table is below. The colgroup is just added to make styling the first column easier since it could be either Raw, Facility or Time depending on view settings.
```html
<div id="syslogContainer">
	<table id="syslogTable">
		<colgroup>
			<col>
		</colgroup>
		<thead>
			<tr>
				<th colspan="5">Raw</th>
				<th>Facility</th>
				<th>Time</th>
				<th>Hostname</th>
				<th>Source</th>
				<th>Message</th>
			</tr>
		</thead>
		<tbody>
		</tbody>
	</table>
</div>
```

The originals of the three [minified](https://www.minifier.org/) js/css files are in the `www` folder.

### nansy.sh

Adds nano syntax files specific to the installed nano version, modifies the sh entry to use highlighting with `/jffs/configs/profile.add`.

### swap.sh

Creates and installs swap files. Stores the list of controlled swaps files in a null separated file `/jffs/configs/swaps` and automounts/unmounts.
