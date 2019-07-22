#!/bin/sh
# shellcheck shell=ash
# shellcheck disable=SC2169
#	busybox ash supports ${VAR//find/replace}

# Allowed filesystems for swap file
ALLOWED_FILESYSTEMS='ext2|ext3|ext4|tfat|exfat'

# Defaults
DEFAULT_SWAP_SIZE="$(sed -n 's/^MemTotal:[ ]*\([^ ]*\) kB$/\1/p' /proc/meminfo)"
DEFAULT_SWAP_PATH="$(mount | sed -n "s/^\/dev\/sda. on \([^ ]*\) type \(${ALLOWED_FILESYSTEMS//|/\\|}\) .*\$/\1/p;T;q")"
DEFAULT_SWAP_FILE='.swapfile.swp'

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
	local FILE_SYSTEM FILE_CAPACITY FILE_MOUNT
	read -r _ FILE_SYSTEM _ _ FILE_CAPACITY _ FILE_MOUNT <<- EOF
		$(df -T "$SWAP_PATH" | tail -n1)
	EOF
	if ! printf '%s\n' "$FILE_SYSTEM" | grep -qE "$ALLOWED_FILESYSTEMS"; then
		echo "Invalid path filesystem ($FILE_SYSTEM)" >&2
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

	# Setup automatic (un)mounting
	if [ ! -f '/jffs/scripts/post-mount' ]; then
		printf '#!/bin/sh\n\n' > '/jffs/scripts/post-mount'
		chmod +x '/jffs/scripts/post-mount'
	fi
	if [ ! -f '/jffs/scripts/unmount' ]; then
		printf '#!/bin/sh\n\n' > '/jffs/scripts/unmount'
		chmod +x '/jffs/scripts/unmount'
	fi
	echo "[ \"\$1\" = '${FILE_MOUNT//'/'\\''}' ] && swapon '${SWAP_PATH//'/'\\''}/${SWAP_FILE//'/'\\''}' ## swap file ##" >> '/jffs/scripts/post-mount'
	echo "[ \"\$1\" = '${FILE_MOUNT//'/'\\''}' ] && swapoff '${SWAP_PATH//'/'\\''}/${SWAP_FILE//'/'\\''}' ## swap file ##" >> '/jffs/scripts/unmount'
}

# Deletes the specified or last found swap file
# Usage: swap_delete [FILEPATH|FILENAME]
swap_delete() {
	if [ "$(wc -l < /proc/swaps)" -le 1 ]; then
		echo 'No swap file currently enabled' >&2
		return
	fi
	local SWAP_FILEPATH SWAP_TYPE
	if [ -n "$1" ]; then
		read -r SWAP_FILEPATH SWAP_TYPE _ <<- EOF
			$(tail -n+2 /proc/swaps | grep -e "^${1//\\/\\\\} " -e "^[^ ]*/${1//\\/\\\\} ")
		EOF

		if [ -z "$SWAP_FILEPATH" ]; then
			echo "Swap file not found ($1)" >&2
			return
		fi
	else
		read -r SWAP_FILEPATH SWAP_TYPE _ <<- EOF
			$(tail -n1 /proc/swaps)
		EOF
	fi

	if [ "$SWAP_TYPE" != 'file' ]; then
		echo "Swap is a $SWAP_TYPE, not a file ($SWAP_FILEPATH)" >&2
		return
	fi

	# Remove file
	if ! swapoff "$SWAP_FILEPATH"; then
		echo "Swap unmount failed ($SWAP_FILEPATH)" >&2
		return
	fi
	if ! rm -f "$SWAP_FILEPATH"; then
		echo "Swap deletion failed ($SWAP_FILEPATH)" >&2
		return
	fi

	echo "Swap file deleted ($SWAP_FILEPATH)"

	# Escape single quotes and quote for use with sed
	SWAP_FILEPATH="$(printf '%s\n' "${1//'/'\\''}" | sed 's/[]\/$*.^&[]/\\&/g')"

	if [ -f '/jffs/scripts/post-mount' ]; then
		# Clean up mount scripts
		sed -i -e "/swapon '$SWAP_FILEPATH' ## swap file ##/d" -e "/swapon $SWAP_FILEPATH # Swap file created by Diversion/d" '/jffs/scripts/post-mount'
		# Remove scripts which do nothing
		[ "$(grep -csvE '^[[:space:]]*(#|$)' '/jffs/scripts/post-mount')" = '0' ] && rm -f '/jffs/scripts/post-mount'
	fi
	if [ -f '/jffs/scripts/unmount' ]; then
		# Clean up unmount scripts
		sed -i -e "/swapoff '$SWAP_FILEPATH' ## swap file ##/d" -e "/swapoff \$1\/${SWAP_FILEPATH##*/} # Added by Diversion/d" '/jffs/scripts/unmount'
		# Remove scripts which do nothing
		[ "$(grep -csvE '^[[:space:]]*(#|$)' '/jffs/scripts/unmount')" = '0' ] && rm -f '/jffs/scripts/unmount'
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
