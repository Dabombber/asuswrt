#!/bin/sh
# shellcheck shell=ash

str_contains() {
	[ ${#2} -eq 0 ] || [ "$1" != "${1#*"$2"}" ]
}

nvram_isset() {
	[ "$(nvram get "$1" | wc -c)" -gt 0 ]
	return $?
}

print_option() {
	local WIDTH=25 INDENT=4
	if [ -z "$2" ]; then
		printf "%$((INDENT))s%-$((WIDTH))s\n" "" "$1"
	elif [ ${#1} -ge $WIDTH ]; then
		printf "%$((INDENT))s%s\n%$((WIDTH+INDENT+1))s%s\n" "" "$1" "" "$2"
	else
		printf "%$((INDENT))s%-$((WIDTH))s %s\n" "" "$1" "$2"
	fi
}

SUPPORT="$(nvram get rc_support)"
is_supported() {
	[ -z "${SUPPORT##*"$1"*}" ]
}

printf '\nActions:\n	start, stop, restart\n\nScripts:\n'
print_option 'upgrade' 'Upgrade the router firmware'
print_option 'allnet' 'Apply action to all network services and interfaces'
print_option 'net' 'Apply action to all network services'
print_option 'net_and_phy' 'Apply action to all network services, servers and interfaces'
print_option 'wireless' 'Apply action to Wifi'
print_option 'wan' 'Apply action to WAN'
print_option 'ddns' 'Apply action to DDNS'
print_option 'httpd' 'Apply action to the WebUI'
print_option 'telnetd' 'Apply action to the telnet daemon'
print_option 'dns (start only)' 'Reload dnsmasq settings'
print_option 'dnsmasq' 'Apply action to dnsmasq'
print_option 'upnp' 'Apply action to UPnP'
print_option 'qos' 'Apply action to QoS'
print_option 'traffic_analyzer (stop only)' 'Saves traffic analyzer database'
print_option 'logger' 'Apply action to the system logger'
print_option 'firewall (start only)' 'Starts the firewall on the primary WAN'
print_option 'pppoe_relay' 'Apply action to the PPPoE relay'
print_option 'ntpc' 'Apply action to the Network Time Protocol client'
print_option 'time' 'Apply action to time and remote access services'
print_option 'wps_method'
print_option 'wps'
print_option 'autodet'
print_option 'snmpd' 'Apply action to the SNMP daemon'
print_option 'rstats' 'Apply action to the bandwidth logger'
print_option 'lltd' 'Apply action to the Link Layer Topology Discovery daemon'
print_option 'apps_update (start only)'
print_option 'apps_stop (start only)'
print_option 'apps_upgrade (start only)'
print_option 'apps_install (start only)'
print_option 'apps_remove (start only)'
print_option 'apps_enable (start only)'
print_option 'apps_switch (start only)'
print_option 'apps_cancel (start only)'
print_option 'webs_[script] (start only)'
print_option 'gobi_[script] (start only)'
if is_supported 'dsl'; then
	print_option 'dsl_setting (restart only)'
fi
if nvram_isset 'dsllog_sysvid'; then
	print_option 'dsl_autodet'
	print_option 'dsl_diag'
fi
if is_supported 'fanctrl'; then
	print_option 'fanctrl (restart only)' 'Restart the temperature sensing fan controller'
fi
if is_supported 'dblog' && is_supported 'email'; then
	print_option 'dblog' 'Apply action to system diagnostic support'
fi
if [ -x '/sbin/setup_dnsmq' ] ; then
	print_option 'nas' 'Apply action to NAS'
fi
if is_supported 'usb'; then
	print_option 'nasapps' 'Apply action to network apps'
fi
if grep -q '^nas:' '/etc/passwd' && [ -x '/usr/sbin/vsftpd' ]; then
	print_option 'ftpsamba' 'Apply action to the FTP and samba daemons'
fi
if is_supported 'permission_management'; then
	print_option 'pms_account' 'Apply action samba and ftp daemons'
	print_option 'pms_device' 'Apply action to Qos and parental controls'
fi
if [ -x '/usr/sbin/vsftpd' ]; then
	print_option 'ftpd' 'Apply action to the FTP daemon'
	print_option 'ftpd_force' 'Apply action to the FTP daemon (force mode)'
fi
if [ -x '/usr/sbin/in.tftpd' ]; then
	print_option 'tftpd' 'Apply action to the TFTP daemon'
fi
if grep -q '^nas:' '/etc/passwd'; then
	print_option 'samba' 'Apply action to the samba daemon'
	print_option 'samba_force' 'Apply action to the samba daemon (force mode)'
fi
if is_supported 'captivePortal'; then
	print_option 'chilli'
	print_option 'CP'
	print_option 'uam_srv'
fi
if is_supported 'webdav'; then
	print_option 'webdav'
fi
if [ "$(nvram get aae_support)" -eq 1 ]; then
	print_option 'aae, mastiff' 'Apply action to mastiff tunnel'
fi
if is_supported 'cloudsync'; then
	print_option 'cloudsync'
fi
if is_supported 'wtfast'; then
	print_option 'wtfast' 'Apply action to WTFast'
fi
if is_supported 'usb' && is_supported 'printer'; then
	print_option 'lpd' 'Apply action to the LPD printer service'
	print_option 'u2ec' 'Apply action to EZ Printer Sharing'
fi
if is_supported 'media'; then
	print_option 'media' 'Apply action to minidlna and AirPlay'
	print_option 'dms' 'Apply action to minidlna'
	print_option 'mt_daapd' 'Apply action to AirPlay'
fi
if is_supported 'diskutility'; then
	print_option 'diskmon' 'Apply action to the disk monitor'
	print_option 'diskscan (start only)' 'Start a disk scan'
	print_option 'diskformat (start only)' 'Format a disk'
fi
if [ -x '/sbin/start_bluetooth_service' ]; then
	print_option 'dbus_daemon' 'Apply action to the D-Bus daemon'
	print_option 'bluetooth_service' 'Apply action to the bluetooth service'
fi
if is_supported 'letsencrypt'; then
	print_option 'ddns_le' 'Apply action to DDNS and letsencrypt'
	print_option 'letsencrypt' 'Apply action to letsencrypt'
fi
if is_supported 'ssh'; then
	print_option 'sshd' 'Apply action to the SSH daemon'
fi
if is_supported 'ipv6'; then
	print_option 'ipv6' 'Apply action to IPv6'
	print_option 'dhcp6c' 'Apply action to the IPv6 DHCP client'
	print_option 'wan6' 'Apply action to WAN IPv6'
fi
if is_supported 'bwdpi'; then
	print_option 'wrs' 'Apply action to the Deep Packet Inspection engine'
	print_option 'wrs_force (stop only)' 'Force stop the Deep Packet Inspection engine'
	print_option 'sig_check (start only)' 'Update the Deep Packet Inspection engine profiles'
fi
if [ -x '/usr/bin/crontab' ]; then
	print_option 'crond' 'Apply action to the cron daemon'
fi
if is_supported 'repeater'; then
	print_option 'wlcconnect'
fi
if is_supported 'openvpnd'; then
	print_option 'vpnclient[N]'
	print_option 'vpnserver[N]'
	print_option 'vpnrouting[N] (start only)'
	print_option 'openvpnd'
fi
if is_supported 'pptpd'; then
	print_option 'vpnd'
	print_option 'pptpd'
fi
if is_supported 'yadns'; then
	print_option 'yadns'
fi
if is_supported 'dnsfilter'; then
	print_option 'dnsfilter (start only)'
fi
if is_supported 'timemachine'; then
	print_option 'timemachine'
	print_option 'afpd'
	print_option 'cnid_metad'
fi
if is_supported 'vpnc' && is_supported 'vpn_fusion'; then
	print_option 'vpnc'
fi
if is_supported 'vpnc'; then
	print_option 'vpncall'
fi
if is_supported 'tr069'; then
	print_option 'tr'
fi
if [ ! -x '/sbin/hnd-write' ]; then
	print_option 'cstats'
fi
if is_supported 'appnet' || is_supported 'appbase'; then
	print_option 'app (stop only)'
fi
if is_supported 'usericon'; then
	print_option 'lltdc (start only)'
fi
if [ -x '/usr/sbin/miniupnpc' ]; then
	print_option 'miniupnpc'
fi
if is_supported 'tor'; then
	print_option 'tor'
fi
if is_supported 'cloudcheck'; then
	print_option 'cloudcheck'
fi
if is_supported 'realip'; then
	print_option 'getrealip'
fi
if is_supported 'fbwifi'; then
	print_option 'fbwifi'
fi
if is_supported 'cfg_sync'; then
	print_option 'cfgsync'
fi
if is_supported 'amas'; then
	print_option 'amas_bhctrl'
	print_option 'amas_wlcconnect'
	print_option 'amas_lanctrl'
	print_option 'amas_lldpd'
	print_option 'obd'
fi
if is_supported 'amas' && is_supported 'user_low_rssi'; then
	print_option 'roamast'
fi
if nvram_isset 'usb_idle_enable'; then
	print_option 'usb_idle'
fi
if nvram_isset 'radius_serv_enable'; then
	print_option 'radiusd' 'Apply action to the Radius server'
fi
if [ -x '/sbin/hive_cap' ]; then
	print_option 'hyfi_process (start only)'
	print_option 'hyfi_sync (start only)'
	print_option 'chg_swmode (start only)'
	print_option 'spcmd (start only)'
fi
if [ -x '/sbin/dpdt_ant' ] && [ -x '/sbin/hive_cap' ]; then
	print_option 'bhblock (start only)'
fi
if [ -x '/sbin/autodet_plc' ]; then
	print_option 'plcdet' 'Apply action to the power line toolkit autodetection'
fi
if [ -x '/sbin/wlcscan' ]; then
	print_option 'wlcscan'
fi
if [ -x '/usr/sbin/avahi-daemon' ]; then
	print_option 'mdns'
fi
if nvram_isset 'quagga_enable'; then
	print_option 'quagga'
fi
if is_supported 'disable_nwmd'; then
	print_option 'networkmap'
fi
if [ -x '/sbin/obd_monitor' ]; then
	print_option 'obd_monitor'
fi
if nvram_isset 'bsd_role' || is_supported 'bandstr'; then
	print_option 'bsd'
fi


printf '\nActionless Scripts:\n'
print_option 'reboot' 'Reboot the router'
print_option 'resetdefault_erase' 'Perform a factory reset and remove system settings from /jffs/.sys/'
print_option 'resetdefault' 'Perform a factory reset'
print_option 'all' 'Restart all system services'
print_option 'mfgmode'
print_option 'wltest'
print_option 'ethtest'
print_option 'subnet'
print_option 'enable_webdav'
print_option 'aidisk_asusddns_register'
print_option 'adm_asusddns_register'
print_option 'asusddns_unregister'
print_option 'reset_wps'
print_option 'chpass'
print_option 'wan_disconnect'
print_option 'wan_connect'
print_option 'conntrack'
print_option 'leds'
print_option 'updateresolv'
print_option 'eco_guard'
print_option 'clean_web_history'
print_option 'clean_traffic_analyzer'
if is_supported 'dualwan'; then
	print_option 'multipath'
fi
if is_supported 'pwrsave'; then
	print_option 'pwrsave'
fi
if ! is_supported 'webdav'; then
	print_option 'webdav'
	print_option 'setting_webdav'
fi
if ! is_supported 'cloudsync'; then
	print_option 'cloudsync'
fi
if is_supported 'wtfast'; then
	print_option 'wtfast_rule' 'Reload WTFast settings'
fi
if is_supported 'jffs2' || grep -Fq 'ubifs' '/proc/filesystems'; then
	print_option 'datacount'
	print_option 'resetcount'
	print_option 'sim_del'
	print_option 'set_dataset'
fi
if is_supported 'gobi'; then
	print_option 'simdetect'
	print_option 'getband'
	print_option 'setband'
fi
if is_supported 'bwdpi'; then
	print_option 'dpi_disable' 'Disable the Deep Packet Inspection engine'
	print_option 'reset_cc_db' 'Reset the AiProtection CC database'
	print_option 'reset_mals_db' 'Reset the AiProtection malware database'
	print_option 'reset_vp_db' 'Reset the AiProtection vulnerability database'
fi
if is_supported 'traffic_limiter'; then
	print_option 'reset_traffic_limiter' 'Reset the traffic limiter'
	print_option 'reset_traffic_limiter_force' 'Reset the traffic limiter (force)'
	print_option 'reset_tl_count' 'Reset the traffic limit count'
fi
if is_supported 'nt_center'; then
	print_option 'send_confirm_mail'
	print_option 'email_conf'
	print_option 'email_info'
	print_option 'update_nc_setting_conf'
	print_option 'oauth_google_gen_token_email'
fi
if is_supported 'openvpnd'; then
	print_option 'clearvpnserver'
	print_option 'clearvpnclient'
fi
if is_supported 'email'; then
	print_option 'sendmail'
fi
if is_supported 'vpnc' || is_supported 'vpn_fusion'; then
	print_option 'default_wan'
	print_option 'vpnc_dev_policy'
fi
if is_supported 'keyGuard'; then
	print_option 'key_guard'
fi
if is_supported 'ipsec'; then
	print_option 'ipsec_set'
	print_option 'ipsec_start'
	print_option 'ipsec_stop'
	print_option 'ipsec_set_cli'
	print_option 'ipsec_start_cli'
	print_option 'ipsec_stop_cli'
	print_option 'generate_ca'
fi
if is_supported 'captivePortal'; then
	print_option 'set_captive_portal_wl'
	print_option 'set_captive_portal_adv_wl'
	print_option 'overwrite_captive_portal_ssid'
	print_option 'overwrite_captive_portal_adv_ssid'
fi
if is_supported 'fbwifi'; then
	print_option 'set_fbwifi_profile'
	print_option 'overwrite_fbwifi_ssid'
fi
if is_supported 'cfg_sync'; then
	print_option 'release_note'
fi
if [ "$(nvram get productid)" = 'BLUECAVE' ]; then
	print_option 'reset_led'
fi
if is_supported 'dhcp_override'; then
	print_option 'dhcpd'
fi
if str_contains 'RT-AC56U RT-AC68U RT-AC87U RT-AC86U RT-AC3200 RT-AC88U RT-AC3100 RT-AC5300' "$(uname -n)" && [ -x '/sbin/setup_dnsmq' ]; then
	print_option 'clkfreq'
fi
if [ -x '/sbin/setup_dnsmq' ] ; then
	print_option 'set_wltxpower'
fi
if [ -x '/sbin/setup_dnsmq' ] && is_supported 'amas'; then
	print_option 'wps_enr'
fi
if [ -x '/sbin/speedtest' ]; then
	print_option 'speedtest'
fi
if nvram_isset 'dsllog_opmode'; then
	print_option 'DSLsenddiagmail'
fi
if nvram_isset 'usbreset_active'; then
	print_option 'usbreset'
fi
if [ -x '/sbin/autodet_plc' ]; then
	print_option 'plc_upgrade'
fi


printf '\nArgumented Scripts:\n'
print_option 'upgrade_ate'
print_option 'iptrestore (start only)'
print_option 'rebootandrestore'
print_option 'restore'
print_option 'sh'
print_option 'wan_if'
print_option 'wan_line'
if is_supported 'dsl'; then
	print_option 'dslwan_if'
	print_option 'dsl_wireless'
fi
if is_supported 'modem'; then
	print_option 'simauth'
	print_option 'simpin'
	print_option 'simpuk'
	print_option 'lockpin'
	print_option 'pwdpin'
	print_option 'modemscan'
	print_option 'modemsta'
	print_option 'sendSMS'
fi
if is_supported 'usbsms'; then
	print_option 'savesms'
	print_option 'sendsmsbyindex'
	print_option 'sendsmsnow'
	print_option 'delsms'
	print_option 'modsmsdraft'
	print_option 'savephonenum'
	print_option 'delphonenum'
	print_option 'modphonenum'
fi
if is_supported 'repeater'; then
	print_option 'wlcmode'
fi
if is_supported 'ispmeter'; then
	print_option 'isp_meter'
fi
if is_supported 'email' && is_supported 'dblog'; then
	print_option 'senddblog'
fi
if nvram_isset 'xhci_ports'; then
	print_option 'xhcimode'
fi
