#!/bin/sh
# shellcheck shell=ash

# Add user-script entries
# Usage: entware_scripts [TOGGLE]
entware_scripts() {
	local SCRIPT
	if [ "$1" = 'disable' ]; then
		for SCRIPT in services-start services-stop post-mount unmount; do
			if [ -f "/jffs/scripts/$SCRIPT" ]; then
				# Remove entware line
				sed -i '/## entware ##/d' "/jffs/scripts/$SCRIPT"
				# Remove scripts which do nothing
				[ "$(grep -cvE '^[[:space:]]*(#|$)' "/jffs/scripts/$SCRIPT")" -eq 0 ] && rm -f "/jffs/scripts/$SCRIPT"
			fi
		done
		# Remove event script
		rm -f '/jffs/scripts/.entware.event.sh'
	elif [ "$1" = 'enable' ]; then
		# Create event script
		cat > '/jffs/scripts/.entware.event.sh' << EOF
#!/bin/sh

SCRIPT="\$1"
shift
case "\$SCRIPT" in
	'services-start')
		if [ -d '/tmp/opt' ]; then
			logger -t "entware[\$\$]" -p 'user.info' 'Starting entware services'
			/opt/etc/init.d/rc.unslung start "\$0"
		fi
		touch '/tmp/.entware.services-start'
	;;
	'services-stop')
		if [ -f '/tmp/.entware.services-start' ]; then
			rm -f '/tmp/.entware.services-start'
			if [ -d '/tmp/opt' ]; then
				logger -t "entware[\$\$]" -p 'user.info' 'Stopping entware services'
				/opt/etc/init.d/rc.unslung stop "\$0"
			fi
		fi
	;;
	'post-mount')
		if [ ! -d '/tmp/opt' ] && [ -d "\$1/entware" ]; then
			ln -nsf "\$1/entware" '/tmp/opt'
			if [ -f '/tmp/.entware.services-start' ]; then
				logger -t "entware[\$\$]" -p 'user.info' 'Starting entware services'
				/opt/etc/init.d/rc.unslung start "\$0"
			fi
		fi
	;;
	'unmount')
		if [ "\$(readlink -f -- '/tmp/opt')" = "\$1/entware" ]; then
			if [ -f '/tmp/.entware.services-start' ]; then
				logger -t "entware[\$\$]" -p 'user.info' 'Stopping entware services'
				/opt/etc/init.d/rc.unslung stop "\$0"
			fi
			rm -f '/tmp/opt'
		fi
	;;
esac
EOF
		chmod +x '/jffs/scripts/.entware.event.sh'

		# Add event triggers
		for SCRIPT in services-start services-stop post-mount unmount; do
			if [ ! -f "/jffs/scripts/$SCRIPT" ]; then
				printf '#!/bin/sh\n\n. /jffs/scripts/.entware.event.sh %s "$@" ## entware ##\n' "$SCRIPT" > "/jffs/scripts/$SCRIPT"
				chmod +x "/jffs/scripts/$SCRIPT"
			elif ! grep -Fq '## entware ##' "/jffs/scripts/$SCRIPT"; then
				printf '. /jffs/scripts/.entware.event.sh %s "$@" ## entware ##\n' "$SCRIPT" >> "/jffs/scripts/$SCRIPT"
			fi
		done
	fi
}

# Remove entware-setup.sh additions
# Usage: entware_clean
entware_clean() {
	# Quote strings suitable for use with sed
	# Usage sed_quote STRING
	sed_quote() { printf '%s\n' "$1" | sed 's/[]\/$*.^&[]/\\&/g'; }

	#RC='/opt/etc/init.d/rc.unslung'
	#
	#i=30
	#until [ -x "$RC" ] ; do
	#  i=$(($i-1))
	#  if [ "$i" -lt 1 ] ; then
	#    logger "Could not start Entware"
	#    exit
	#  fi
	#  sleep 1
	#done
	#$RC start
	if [ -f '/jffs/scripts/services-start' ]; then
		sed -i "/^$(sed_quote "RC='/opt/etc/init.d/rc.unslung'")$/,/^$(sed_quote '$RC start')$/d" '/jffs/scripts/services-start'
	fi

	#/opt/etc/init.d/rc.unslung stop
	if [ -f '/jffs/scripts/services-stop' ]; then
		sed -i "/^$(sed_quote '/opt/etc/init.d/rc.unslung stop')$/d" '/jffs/scripts/services-stop'
	fi

	#if [ -d "$1/entware" ] ; then
	#  ln -nsf $1/entware /tmp/opt
	#fi
	if [ -f '/jffs/scripts/post-mount' ]; then
		sed -i "/^$(sed_quote "if [ -d \"\$1/entware\" ] ; then")$/,+2d" '/jffs/scripts/post-mount'
	fi

	# Remove scripts which do nothing
	local SCRIPT
	for SCRIPT in services-start services-stop post-mount; do
		[ "$(grep -csvE '^[[:space:]]*(#|$)' "/jffs/scripts/$SCRIPT")" = '0' ] && rm -f "/jffs/scripts/$SCRIPT"
	done
}

case "$1" in
	'enable')
		entware_clean
		entware_scripts 'enable'
	;;
	'disable')
		entware_scripts 'disable'
	;;
esac
