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
		crontab -l | grep -v '#acme update#$' | crontab -
		# Remove event script
		rm -f '/jffs/scripts/.acme.event.sh'
	elif [ "$1" = 'enable' ]; then
		# Check userscripts are enabled
		if [ "$(nvram get jffs2_scripts)" != "1" ] ; then
			nvram set jffs2_scripts=1
			nvram commit
		fi

		# Create event script
		local ACME_ABSDIR ACME_MINUTE
		ACME_ABSDIR="$(readlink -f -- "$ACME_DIRECTORY")"
		ACME_ABSDIR="${ACME_ABSDIR//'/'\\''}"
		ACME_MINUTE="$(awk -v min=0 -v max=59 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')"
		cat > '/jffs/scripts/.acme.event.sh' << EOF
#!/bin/sh

SCRIPT="\$1"
shift
case "\$SCRIPT" in
	'services-start')
		{ crontab -l | grep -v '#acme update#$' ; echo '$ACME_MINUTE 0 * * * /jffs/scripts/.acme.event.sh cron #acme update#'; } | crontab -
	;;
	'alias')
		if [ -x '$ACME_ABSDIR/acme.sh' ]; then
			for ARG in "\$@"; do
				case "\$ARG" in
					'--install-cert'|'--issue') ACME_ISSUE='yes';;
					'--renew-hook') ACME_CMD='yes';;
					'--key-file') ACME_KEY='yes';;
					'--fullchain-file') ACME_CRT='yes';;
				esac
			done
			if [ "\$ACME_ISSUE" = 'yes' ]; then
				[ "\$ACME_CRT" != 'yes' ] && set -- "\$@" '--fullchain-file' '/jffs/.cert/cert.pem'
				[ "\$ACME_KEY" != 'yes' ] && set -- "\$@" '--key-file' '/jffs/.cert/key.pem'
				[ "\$ACME_CMD" != 'yes' ] && set -- "\$@" '--renew-hook' '/jffs/scripts/.acme.event.sh renew'
			fi
			'$ACME_ABSDIR/acme.sh' --home '$ACME_ABSDIR' --config-home '$ACME_ABSDIR/data' --cert-home '$ACME_ABSDIR/data/cert' "\$@"
		else
			echo "\$0: acme: not found" >&2
			return 1
		fi
	;;
	'renew')
		if [ -x '/jffs/scripts/acme-renew' ]; then
			/jffs/scripts/acme-renew
		else
			service reload_httpd
		fi
	;;
	'cron')
		if [ -x '$ACME_ABSDIR/acme.sh' ]; then
			'$ACME_ABSDIR/acme.sh' --cron --home '$ACME_ABSDIR' --config-home '$ACME_ABSDIR/data' --cert-home '$ACME_ABSDIR/data/cert' > /dev/null
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
		{ crontab -l | grep -v '#acme update#$' ; echo "$ACME_MINUTE 0 * * * /jffs/scripts/.acme.event.sh cron #acme update#"; } | crontab -
	fi
}

acme_install() {

	curl -sL 'https://github.com/Neilpang/acme.sh/archive/master.tar.gz' | tar xzf -
	(
		cd acme.sh-master || return
		chmod +x acme.sh
		mkdir -p "$ACME_DIRECTORY"
		local ACME_ABSDIR
		ACME_ABSDIR="$(readlink -f -- "$ACME_DIRECTORY")"
		sh acme.sh --install --noprofile --nocron --home "$ACME_ABSDIR" --config-home "$ACME_ABSDIR/data" --cert-home "$ACME_ABSDIR/data/cert" --log "$(readlink -f -- "$ACME_LOG")"
	)
	rm -rf acme.sh-master
}

case "$1" in
	'install')
		acme_install
		acme_scripts 'enable'
	;;
	'uninstall')
		acme_scripts 'disable'
	;;
esac
