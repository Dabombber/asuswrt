#!/bin/sh
# shellcheck shell=ash
# shellcheck disable=SC2169
#	busybox ash supports ${VAR//find/replace}

# Allowed filesystems for swap file
ALLOWED_FILESYSTEMS='ext2|ext3|ext4|tfat|exfat'

# Defaults
DEFAULT_SWAP_SIZE="$(sed -n 's/^MemTotal:[ ]*\([^ ]*\) kB$/\1/p' /proc/meminfo)"
DEFAULT_SWAP_PATH="$(mount | sed -n "s/^[^ ]* on \(\/tmp\/mnt\/[^ ]*\) type \(${ALLOWED_FILESYSTEMS//|/\\|}\) .*[(,]rw[,)].*\$/\1/p;T;q")"
DEFAULT_SWAP_FILE='.swapfile.swp'


# Installs the event script for swap files
# Usage: swap_scripts enable|disable
swap_scripts() {
	if [ "$1" = 'disable' ]; then
		local SCRIPT
		for SCRIPT in post-mount unmount; do
			if [ -f "/jffs/scripts/$SCRIPT" ]; then
				# Remove swap line
				sed -i "/## swap files ##/d" "/jffs/scripts/$SCRIPT"
				# Remove scripts which do nothing
				[ "$(grep -csvE '^[[:space:]]*(#|$)' "/jffs/scripts/$SCRIPT")" = '0' ] && rm -f "/jffs/scripts/$SCRIPT"
			fi
		done
		# Remove event script
		rm -f /jffs/scripts/.swap.event.sh
	elif [ "$1" = 'enable' ]; then
		# Check userscripts are enabled
		if [ "$(nvram get jffs2_scripts)" != "1" ] ; then
			nvram set jffs2_scripts=1
			nvram commit
		fi

		# Create event script
		[ ! -x '/jffs/scripts/.swap.event.sh' ] && cat >/jffs/scripts/.swap.event.sh <<'EOF'
#!/bin/sh

SCRIPT="$1"
SWAPPATH="$2"

set --

update_script() {
	printf '#!/bin/sh\n\nSCRIPT="$1"\nSWAPPATH="$2"\n\n%s\n\n%s\n' "$1" "$(tail -n51 /jffs/scripts/.swap.event.sh)" >/tmp/.swap.event.sh
	mv -f /tmp/.swap.event.sh /jffs/scripts/.swap.event.sh
	chmod +x /jffs/scripts/.swap.event.sh
}

case "$SCRIPT" in
	'post-mount')
		for SWAPFILE in "$@"; do
			if [ -n "$SWAPFILE" ] && [ "${SWAPFILE#"$SWAPPATH/"}" != "$SWAPFILE" ] && [ -f "$SWAPFILE" ]; then
				swapon "$SWAPFILE"
			fi
		done
	;;
	'unmount')
		for SWAPFILE in "$@"; do
			if [ -n "$SWAPFILE" ] && [ "${SWAPFILE#"$SWAPPATH/"}" != "$SWAPFILE" ] && tail -n+2 /proc/swaps | grep -q "^$(printf '%s\n' "$SWAPFILE" | sed 's/[]\/$*.^&[]/\\&/g') "; then
				swapoff "$SWAPFILE" || swapoff -a;
			fi
		done
	;;
	'add')
		SWAPS='set --'
		UPDATE='true'
		for SWAPFILE in "$@"; do
			if [ "$SWAPFILE" = "$SWAPPATH" ]; then
				UPDATE='false'
				break
			fi
			SWAPS="$SWAPS '${SWAPFILE//'/'\\''}'"
		done

		if [ "$UPDATE" = 'true' ]; then
			SWAPS="$SWAPS '${SWAPPATH//'/'\\''}'"
			update_script "$SWAPS"
		else
			false
		fi
	;;
	'remove')
		SWAPS='set --'
		UPDATE='false'
		for SWAPFILE in "$@"; do
			if [ "$SWAPFILE" = "$SWAPPATH" ]; then
				UPDATE='true'
			else
				SWAPS="$SWAPS '${SWAPFILE//'/'\\''}'"
			fi
		done

		if [ "$UPDATE" = 'true' ]; then
			update_script "$SWAPS"
		else
			false
		fi
	;;
esac
EOF
		chmod +x /jffs/scripts/.swap.event.sh

		# Add event triggers
		local SCRIPT
		for SCRIPT in post-mount unmount; do
			if [ ! -f "/jffs/scripts/$SCRIPT" ]; then
				printf '#!/bin/sh\n\n. /jffs/scripts/.swap.event.sh %s "$@" ## swap files ##\n' "$SCRIPT" > "/jffs/scripts/$SCRIPT"
				chmod +x "/jffs/scripts/$SCRIPT"
			elif ! grep -qF '## swap files ##' "/jffs/scripts/$SCRIPT"; then
				printf '. /jffs/scripts/.swap.event.sh %s "$@" ## swap files ##\n' "$SCRIPT" >> "/jffs/scripts/$SCRIPT"
			fi
		done
	fi
}


# Creates and mounts a swap file
# Usage: swap_create [SIZE] [DIRECTORY] [FILENAME]
#
# All arguments optional
#	SIZE	- Swap size. defaults to kiB, or MB/KB/GB/KiB/MiB/GiB can be specified
#	DIRECTORY	- Where to create the swap file
#	FILENAME	- What to name the swap file
swap_create() {
	# Check for any existing swap files
	if [ "$(wc -l < /proc/swaps)" -gt 1 ]; then
		echo 'Swap file already exists' >&2
		return
	fi

	if [ $? -lt 3 ]; then
		# First arg isn't a size, shift them along
		if [ -n "$1" ] && ! printf '%s\n' "$1" | grep -qiE '^[0-9]*[ ]*(MB|KB|GB|KiB|MiB|GiB|)$'; then
			set -- "" "$@"
		fi
		# Still less than 3 args and the second isn't a directory
		if [ $? -eq 2 ] && [ -n "${2##*/*}" ]; then
			set -- "$1" "" "$2"
		fi
	fi

	local SWAP_SIZE="${1:-"$DEFAULT_SWAP_SIZE"}"
	local SWAP_PATH="${2:-"$DEFAULT_SWAP_PATH"}"
	local SWAP_FILE="${3:-"$DEFAULT_SWAP_FILE"}"

	# Remove leading 0s to avoid being interpreted as octal based
	SWAP_SIZE="$(printf '%s\n' "$SWAP_SIZE" | sed 's/^0*\([0-9]\)/\1/')"

	# Get the nearest 2^x memory size, within 32Mb-2Gb. Working in KiB (bs=1024)
	case "$SWAP_SIZE" in
		# Assume noone has any idea what MB/KB/GB/KiB/MiB/GiB mean
		*[kK][bB]) SWAP_SIZE=${SWAP_SIZE%??};;
		*[kK][iI][bB]) SWAP_SIZE=${SWAP_SIZE%???};;
		*[mM][bB]) SWAP_SIZE=$((${SWAP_SIZE%??} * 1000));;
		*[mM][iI][bB]) SWAP_SIZE=$((${SWAP_SIZE%???} * 1000));;
		*[gG][bB]) SWAP_SIZE=$((${SWAP_SIZE%??} * 1000 * 1000));;
		*[gG][iI][bB]) SWAP_SIZE=$((${SWAP_SIZE%???} * 1000 * 1000));;
	esac
	local SWAP_SIZE_MIN=$((32 * 1024))
	local SWAP_SIZE_MAX=$((2048 * 1024))

	local SIZE=$SWAP_SIZE_MIN
	while :; do
		if [ "$SWAP_SIZE" -le $SIZE ]; then
			SWAP_SIZE=$SIZE
			break
		fi
		SIZE=$((SIZE * 2))
		if [ $SIZE -gt $SWAP_SIZE_MAX ]; then
			echo "Invalid swap file size ($SWAP_SIZE)" >&2
			return
		fi
	done

	# Check the file path is suitable
	if [ ! -d "$SWAP_PATH" ]; then
		echo "Invalid path ($SWAP_PATH)" >&2
		return
	fi
	# Get the real path
	SWAP_PATH="$(readlink -f -- "$SWAP_PATH")"
	local FILE_SYSTEM FILE_CAPACITY
	read -r _ FILE_SYSTEM _ _ FILE_CAPACITY _ <<- EOF
		$(df -T "$SWAP_PATH" | tail -n1)
	EOF
	if ! printf '%s\n' "$FILE_SYSTEM" | grep -qE "$ALLOWED_FILESYSTEMS"; then
		echo "Invalid filesystem for path ($FILE_SYSTEM)" >&2
		return
	fi
	if [ "$FILE_CAPACITY" -le "$SWAP_SIZE" ]; then
		echo "Insufficient space (avaliable: $FILE_CAPACITY, required: $SWAP_SIZE)" >&2
		return
	fi
	if [ -f "$SWAP_PATH/$SWAP_FILE" ]; then
		echo "File already exists ($SWAP_PATH/$SWAP_FILE)" >&2
		return
	fi

	# Create the file and make it swappy
	if ! dd if=/dev/zero of="$SWAP_PATH/$SWAP_FILE" bs=1024 count="$SWAP_SIZE"; then
		echo "File creation failed ($SWAP_PATH/$SWAP_FILE)" >&2
		return
	fi
	if ! mkswap "$SWAP_PATH/$SWAP_FILE"; then
		echo "Swap area creation failed ($SWAP_PATH/$SWAP_FILE)" >&2
		return
	fi
	if ! swapon "$SWAP_PATH/$SWAP_FILE"; then
		echo "Swap mount failed ($SWAP_PATH/$SWAP_FILE)" >&2
		return
	fi

	echo "Swap file created ($SWAP_PATH/$SWAP_FILE)"

	# Add to list of automounted swap files
	swap_script install
	/jffs/scripts/.swap.event.sh add "$SWAP_PATH/$SWAP_FILE"
}

# Unmounts,deletes and/or removes from autostart the specified swap file
# Usage: swap_delete FILEPATH
swap_delete() {
	[ -z "$1" ] && return

	local SWAP_TYPE
	SWAP_TYPE="$(awk -v s="$1" 'NR>1&&index($0,s" ")==1{print $(NF-3)}' /proc/swaps)"

	# Unmount
	if [ -n "$SWAP_TYPE" ]; then
		if [ "$SWAP_TYPE" != 'file' ]; then
			echo "Swap is a $SWAP_TYPE, not a file ($1)" >&2
			return
		fi

		if ! swapoff "$1"; then
			echo "Swap unmount failed ($1)" >&2
			return
		fi
		echo "Swap file unmounted ($1)" >&2
	fi

	# Remove file
	if [ -f "$1" ]; then
		if ! rm -f "$1"; then
			echo "Swap deletion failed ($1)" >&2
			return
		fi
		echo "Swap file deleted ($1)"
	fi

	# Remove from list of automounted swap files
	if [ -x '/jffs/scripts/.swap.event.sh' ] && /jffs/scripts/.swap.event.sh remove "$1"; then
		echo "Swap file automount removed ($1)"
	fi
}

case "$1" in
	'create')
		shift
		swap_create "$@"
	;;
	'delete')
		shift
		swap_delete "$@"
	;;
esac
