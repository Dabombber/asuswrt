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

# Add directory user-script entries
# Usage: directory_scripts DIRECTORY START-SCRIPT KILL-SCRIPT
directory_scripts() {
	mkdir -p "/jffs/scripts/$1.d"

	[ ! -x "/jffs/scripts/$2" ] && printf '#!/bin/sh\n\n' > "/jffs/scripts/$2" && chmod +x "/jffs/scripts/$2"
	[ ! -x "/jffs/scripts/$3" ] && printf '#!/bin/sh\n\n' > "/jffs/scripts/$3" && chmod +x "/jffs/scripts/$3"

	if ! grep -qF "[ -d '/jffs/scripts/$1.d' ]" "/jffs/scripts/$2"; then
		echo "[ -d '/jffs/scripts/$1.d' ] && for FILENAME in '/jffs/scripts/$1.d/S'[0-9][0-9]*; do [ -x \"\$FILENAME\" ] && . \"\$FILENAME\" \"\$@\"; done" >> "/jffs/scripts/$2"
	fi
	if ! grep -qF "[ -d '/jffs/scripts/$1.d' ]" "/jffs/scripts/$3"; then
		echo "[ -d '/jffs/scripts/$1.d' ] && for FILENAME in '/jffs/scripts/$1.d/K'[0-9][0-9]*; do [ -x \"\$FILENAME\" ] && . \"\$FILENAME\" \"\$@\"; done" >> "/jffs/scripts/$3"
	fi
}

# Add user-script entries
# Usage: entware_scripts [TOGGLE]
entware_scripts() {
	if [ "$1" = 'disable' ]; then
		rm -f '/jffs/scripts/services.d/S20entware' '/jffs/scripts/services.d/K80entware' '/jffs/scripts/mount.d/S20entware' '/jffs/scripts/mount.d/K80entware'
	elif [ "$1" = 'enable' ]; then
		# Check userscripts are enabled
		if [ "$(nvram get jffs2_scripts)" != "1" ] ; then
			nvram set jffs2_scripts=1
			nvram commit
		fi

		# Add services/mount directory scripts
		directory_scripts 'services' 'services-start' 'services-stop'
		directory_scripts 'mount' 'post-mount' 'unmount'

		# Create start/stop scripts
		cat > '/jffs/scripts/services.d/S20entware' <<'EOF'
#!/bin/sh

if [ -d '/tmp/opt' ]; then
	logger -t "entware[$$]" -p 'user.info' 'Starting entware services'
	/opt/etc/init.d/rc.unslung start "$0"
fi
touch '/tmp/.entware.services-start'
EOF
		cat > '/jffs/scripts/services.d/K80entware' <<'EOF'
#!/bin/sh

if [ -f '/tmp/.entware.services-start' ]; then
	rm -f '/tmp/.entware.services-start'
	if [ -d '/tmp/opt' ]; then
		logger -t "entware[$$]" -p 'user.info' 'Stopping entware services'
		/opt/etc/init.d/rc.unslung stop "$0"
	fi
fi
EOF
		cat > '/jffs/scripts/mount.d/S20entware' <<'EOF'
#!/bin/sh

if [ ! -d '/tmp/opt' ] && [ -d "$1/entware" ]; then
	ln -nsf "$1/entware" '/tmp/opt'
	if [ -f '/tmp/.entware.services-start' ]; then
		logger -t "entware[$$]" -p 'user.info' 'Starting entware services'
		/opt/etc/init.d/rc.unslung start "$0"
	fi
fi
EOF
		cat > '/jffs/scripts/mount.d/K80entware' <<'EOF'
#!/bin/sh

		if [ "$(readlink -f -- '/tmp/opt')" = "$1/entware" ]; then
			if [ -f '/tmp/.entware.services-start' ]; then
				logger -t "entware[$$]" -p 'user.info' 'Stopping entware services'
				/opt/etc/init.d/rc.unslung stop "$0"
			fi
			rm -f '/tmp/opt'
		fi
EOF
		chmod +x '/jffs/scripts/services.d/S20entware' '/jffs/scripts/services.d/K80entware' '/jffs/scripts/mount.d/S20entware' '/jffs/scripts/mount.d/K80entware'
	fi
}

case "$1" in
	'install')
		shift
		entware_prepare "$@" && entware_install "$@" && entware_scripts 'enable'
	;;
	'enable')
		entware_scripts 'enable'
	;;
	'disable')
		entware_scripts 'disable'
	;;
esac
