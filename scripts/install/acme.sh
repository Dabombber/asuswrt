#!/bin/sh
# shellcheck shell=ash
# shellcheck disable=SC2169

ACME_DIRECTORY='/opt/share/acme'
ACME_LOG='/opt/var/log/acme.log'


# Add user-script entries
# Usage: acme_scripts [TOGGLE]
acme_scripts() {
	local SCRIPT
	if [ "$1" = 'disable' ]; then
		for SCRIPT in 'configs/profile.add' 'scripts/services-start'; do
			if [ -f "/jffs/$SCRIPT" ]; then
				# Remove acme line
				sed -i '/## acme ##/d' "/jffs/$SCRIPT"
				# Remove scripts which do nothing
				if [ "$(grep -cvE '^[[:space:]]*(#|$)' "/jffs/$SCRIPT")" -eq 0 ]; then
					rm -f "/jffs/$SCRIPT"
				fi
			fi
		done
		# Remove cron job
		crontab -l 2>/dev/null | grep -v '#acme update#$' | crontab -
		# Remove event script
		rm -f '/jffs/scripts/.acme.event.sh'
	elif [ "$1" = 'enable' ]; then
		# Check userscripts are enabled
		if [ "$(nvram get jffs2_scripts)" != "1" ] ; then
			nvram set jffs2_scripts=1
			nvram commit
		fi

		# Create event script
		local ACME_ESCDIR ACME_MINUTE
		ACME_ESCDIR="${ACME_DIRECTORY//'/'\\''}"
		ACME_MINUTE="$(awk -v min=0 -v max=59 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')"
		cat > '/jffs/scripts/.acme.event.sh' << EOF
#!/bin/sh

SCRIPT="\$1"
shift
case "\$SCRIPT" in
	'services-start')
		{ crontab -l 2>/dev/null | grep -v '#acme update#$' ; echo '$ACME_MINUTE 0 * * * /jffs/scripts/.acme.event.sh cron #acme update#'; } | crontab -
	;;
	'alias')
		if [ -x '$ACME_ESCDIR/acme.sh' ]; then
			for ARG in "\$@"; do
				case "\$ARG" in
					'--install-cert'|'--issue') ACME_ISSUE='yes';;
					'--reloadcmd') ACME_CMD='yes';;
					'--key-file') ACME_KEY='yes';;
					'--fullchain-file') ACME_CRT='yes';;
				esac
			done
			if [ "\$ACME_ISSUE" = 'yes' ]; then
				[ "\$ACME_CRT" != 'yes' ] && set -- "\$@" '--fullchain-file' '/jffs/.cert/cert.pem'
				[ "\$ACME_KEY" != 'yes' ] && set -- "\$@" '--key-file' '/jffs/.cert/key.pem'
				[ "\$ACME_CMD" != 'yes' ] && set -- "\$@" '--reloadcmd' '/jffs/scripts/.acme.event.sh reload'
			fi
			'$ACME_ESCDIR/acme.sh' --home '$ACME_ESCDIR' --config-home '$ACME_ESCDIR/data' --cert-home '$ACME_ESCDIR/data/cert' "\$@"
		else
			echo "\$0: acme: not found" >&2
			return 1
		fi
	;;
	'reload')
		if [ -x '/jffs/scripts/acme-reload' ]; then
			/jffs/scripts/acme-reload
		else
			service reload_httpd
		fi
	;;
	'cron')
		if [ -x '$ACME_ESCDIR/acme.sh' ]; then
			'$ACME_ESCDIR/acme.sh' --cron --home '$ACME_ESCDIR' --config-home '$ACME_ESCDIR/data' --cert-home '$ACME_ESCDIR/data/cert' > /dev/null
		fi
	;;
esac
EOF
		chmod +x '/jffs/scripts/.acme.event.sh'

		# Add event triggers
		if [ ! -f '/jffs/scripts/services-start' ]; then
			printf '#!/bin/sh\n\n. /jffs/scripts/.acme.event.sh services-start "$@" ## acme ##\n' > '/jffs/scripts/services-start'
			chmod +x '/jffs/scripts/services-start'
		elif ! grep -Fq '## acme ##' '/jffs/scripts/services-start'; then
			printf '. /jffs/scripts/.acme.event.sh services-start "$@" ## acme ##\n' >> '/jffs/scripts/services-start'
		fi
		# Add acme command
		if [ ! -f '/jffs/configs/profile.add' ] || ! grep -qF '## acme ##' '/jffs/configs/profile.add'; then
			echo 'acme() { /jffs/scripts/.acme.event.sh alias "$@"; } ## acme ##' >> '/jffs/configs/profile.add'
		fi
		# Add cron job
		{ crontab -l 2>/dev/null | grep -v '#acme update#$' ; echo "$ACME_MINUTE 0 * * * /jffs/scripts/.acme.event.sh cron #acme update#"; } | crontab -
	fi
}

acme_install() {

	curl -sL 'https://github.com/acmesh-official/acme.sh/archive/master.tar.gz' | tar xzf -
	(
		cd acme.sh-master || { false; return $?; }
		chmod +x acme.sh
		mkdir -p "$ACME_DIRECTORY"
		sh acme.sh --install --noprofile --nocron --home "$ACME_DIRECTORY" --config-home "$ACME_DIRECTORY/data" --cert-home "$ACME_DIRECTORY/data/cert" --log "$ACME_LOG"
	)
	rm -rf acme.sh-master
	cat > "$ACME_DIRECTORY/dnsapi/dns_asus.sh" <<'EOF'
#!/bin/sh

dns_asus_add() {
	HOSTNAME="${1#_acme-challenge.}"
	TXTDATA="$2"

	# Reuse the current IP address
	IP="$(nslookup "$HOSTNAME" 'ns1.asuscomm.com' | awk 'NR>2&&/^Address/{print $(NF==2?2:3);exit}')"

	# Router MAC address location is hardware dependent
	for LAN_MAC_NAME in et0macaddr et1macaddr et2macaddr; do
		MAC_ADDR="$(nvram get "$LAN_MAC_NAME")"
		if [ -n "$MAC_ADDR" ] && [ "$MAC_ADDR" != '00:00:00:00:00:00' ]; then break; fi
	done

	# Use openssl to generate the password
	PASSWORD="$(printf '%s' "${MAC_ADDR//:/}${IP//./}" | openssl md5 -hmac "$(nvram get secret_code)" 2>/dev/null | awk '{print toupper($2)}')"

	HTTP_RESULT="$(curl -fs -w '%{http_code}' -o /dev/null -u "${MAC_ADDR//:/}:$PASSWORD" "http://ns1.asuscomm.com/ddns/update.jsp?hostname=$HOSTNAME&acme_challenge=1&txtdata=$TXTDATA&myip=$IP")"
	case "$HTTP_RESULT" in
		200|220|230) return 0;;
	esac
	return 1
}

dns_asus_rm() {
	# txt record is auto-removed by asus on next ddns update
	return 0
}
EOF
	true; return $?;
}

case "$1" in
	'install')
		acme_install && acme_scripts 'enable'
	;;
	'uninstall')
		acme_scripts 'disable'
	;;
esac
