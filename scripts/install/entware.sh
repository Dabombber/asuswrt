#!/bin/sh
# shellcheck shell=ash
# shellcheck disable=SC2169
#	busybox ash supports ${VAR//find/replace}

# Create /tmp/opt mount
# Usage: entware_prepare [PATH]
entware_prepare() {
	local ARG ENTWARE_TYPES ENTWARE_FOLDER ENTWARE_MOUNT=''

	# Check supported file system types
	case "$(uname -m)" in
		'armv7l'|'aarch64') ENTWARE_TYPES='ext2|ext3|ext4';;
		'mips') ENTWARE_TYPES='ext2|ext3';;
		*)
			echo 'Unsupported platform' >&2
			false; return $?
		;;
	esac

	for ARG in "$@"; do
		if [ "$ARG" = '-32' ] || [ "$ARG" = '-64' ]; then continue; fi
		ENTWARE_MOUNT="$ARG"
	done

	# Check the file system for the path is valid, or pick the first suitable mount if none is specified
	if [ -z "$ENTWARE_MOUNT" ]; then
		ENTWARE_MOUNT="$(mount | sed -n "s/^[^ ]* on \(\/tmp\/mnt\/[^ ]*\) type \(${ENTWARE_TYPES//|/\\|}\) .*[(,]rw[,)].*\$/\1/p;T;q")"
		if [ -z "$ENTWARE_MOUNT" ]; then
			echo 'No partitions available' >&2
			false; return $?
		fi
		echo "No partition specified, defaulting to $ENTWARE_MOUNT"
	else
		ARG="$(df -PT "$ENTWARE_MOUNT" 2>/dev/null | awk 'NR==2{print $2" "$7}')"
		if [ -z "$ARG" ]; then
			echo 'Invalid path specified' >&2
			false; return $?
		elif ! printf '%s' "${ARG%% }" | grep -qE "$ENTWARE_TYPES"; then
			echo 'Unsupported partition type' >&2
			false; return $?
		elif ! mount | grep -F " on ${ARG# } type ${ARG%% }" | grep -qE ' \(([^ ]*,)?rw(,[^ ]*)?\)$'; then
			echo 'Partition must be writable' >&2
			false; return $?
		elif [ "$ENTWARE_MOUNT" != "${ARG# }" ]; then
			echo "Using root of specified path (${ARG# })"
			ENTWARE_MOUNT="${ARG# }"
		fi
	fi

	# asusware stuff
	if [ -n "$(nvram get apps_mounted_path)" ]; then
		if [ -x '/opt/etc/init.d/S50downloadmaster' ]; then
			#app_remove.sh downloadmaster
			echo "Download Master must be uninstalled first" >&2
			false; return $?
		fi
		echo "Resetting asusware nvram settings"
		nvram set apps_mounted_path=
		nvram set apps_dev=
		nvram set apps_state_autorun=
		nvram set apps_state_enable=
		nvram set apps_state_install=
		nvram set apps_state_switch=
		nvram commit
	fi

	# Create folder/symlinks
	ENTWARE_FOLDER="$ENTWARE_MOUNT/entware"

	if [ -d "$ENTWARE_FOLDER" ]; then
		local DATE
		DATE="$(date +%F_%H-%M)"
		echo "Found previous installation, saving to entware-old_$DATE"
		mv "$ENTWARE_FOLDER" "$ENTWARE_FOLDER-old_$DATE"
	fi
	echo "Creating $ENTWARE_FOLDER folder"
	if ! mkdir "$ENTWARE_FOLDER"; then
		false; return $?
	fi

	if [ -d '/tmp/opt' ]; then
		echo 'Deleting old /tmp/opt symlink'
		rm '/tmp/opt'
	fi
	echo 'Creating /tmp/opt symlink'
	ln -s "$ENTWARE_FOLDER" '/tmp/opt'

	true; return $?
}

# Install entware to /opt
# Usage: entware_install [-32|-64]
entware_install() {
	local ARG PLATFORM INST_URL

	if [ ! -d '/tmp/opt' ]; then
		echo 'Cannot install, missing /tmp/opt symlink' >&2
		false; return $?
	fi

	PLATFORM="$(uname -m)"
	if [ "$PLATFORM" = 'aarch64' ]; then
		for ARG in "$@"; do
			if [ "$ARG" = '-32' ]; then
				PLATFORM='armv7l'
				break
			fi
		done
	fi

	case "$PLATFORM" in
		'armv7l')
			INST_URL='https://bin.entware.net/armv7sf-k2.6/installer/generic.sh'
		;;
		'mips')
			INST_URL='https://pkg.entware.net/binaries/mipsel/installer/installer.sh'
		;;
		'aarch64')
			INST_URL='https://bin.entware.net/aarch64-k3.10/installer/generic.sh'
		;;
		*)
			echo 'Unsupported platform' >&2
			false; return $?
		;;
	esac

	cd '/tmp' || { false; return $?; }

	# Suppress this warning since it's been intentionally created
	wget --timeout=10 --tries=3 --retry-connrefused -qO - "$INST_URL" | sh | grep --line-buffered -vxF 'Warning: Folder /opt exists!'

	[ -x '/opt/bin/opkg' ]; return $?
}

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
		# Check userscripts are enabled
		if [ "$(nvram get jffs2_scripts)" != "1" ] ; then
			echo "Enabling custom scripts and configs from /jffs..."
			nvram set jffs2_scripts=1
			nvram commit
		fi

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

# Remove entware-setup.sh/diversion/amtm additions
# Usage: entware_clean
entware_clean() {
	# Quote strings suitable for use with sed
	# Usage sed_quote STRING
	sed_quote() { printf '%s\n' "$1" | sed 's/[]\/$*.^&[]/\\&/g'; }

	if [ -f '/jffs/scripts/services-start' ]; then
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
		sed -i "/^$(sed_quote "RC='/opt/etc/init.d/rc.unslung'")$/bx;b;:x;N;/^$(sed_quote "\$RC start")$/d;bx" '/jffs/scripts/services-start'
	fi

	if [ -f '/jffs/scripts/services-stop' ]; then
		#/opt/etc/init.d/rc.unslung stop [# Added by XXX]
		sed -i "/^$(sed_quote '/opt/etc/init.d/rc.unslung stop')/d" '/jffs/scripts/services-stop'
	fi

	if [ -f '/jffs/scripts/post-mount' ]; then
		#if [ -d "$1/entware" ] ; then
		#  ln -nsf $1/entware /tmp/opt
		#fi
		sed -i -e '/\(post-mount\.div\|mount-entware\.div\)/d' -e "/^$(sed_quote "if [ -d \"\$1/entware\" ] ; then")$/,+2d" '/jffs/scripts/post-mount'
	fi

	# Remove scripts which do nothing
	local SCRIPT
	for SCRIPT in services-start services-stop post-mount; do
		[ "$(grep -csvE '^[[:space:]]*(#|$)' "/jffs/scripts/$SCRIPT")" = '0' ] && rm -f "/jffs/scripts/$SCRIPT"
	done
}

case "$1" in
	'install')
		shift
		entware_prepare "$@" && entware_install "$@" && { entware_clean; entware_scripts 'enable'; }
	;;
	'enable')
		entware_clean
		entware_scripts 'enable'
	;;
	'disable')
		entware_scripts 'disable'
	;;
esac
