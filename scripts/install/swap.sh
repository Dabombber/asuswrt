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

# Installs the event script for swap files
# Usage: swap_scripts enable|disable
swap_scripts() {
	if [ "$1" = 'disable' ]; then
		rm -f '/jffs/scripts/mount.d/S10swaps' '/jffs/scripts/mount.d/K90swaps'
	elif [ "$1" = 'enable' ]; then
		# Check userscripts are enabled
		if [ "$(nvram get jffs2_scripts)" != '1' ] ; then
			nvram set jffs2_scripts=1
			nvram commit
		fi

		# Add mount directory script
		directory_scripts 'mount' 'post-mount' 'unmount'

		[ ! -x '/jffs/scripts/mount.d/S10swaps' ] && cat > '/jffs/scripts/mount.d/S10swaps' <<'EOF'
#!/bin/sh

[ -f /jffs/configs/swaps ] && xargs -r0 sh -c '#!/bin/sh
SWAPPATH="$1"
shift
for SWAPFILE in "$@"; do
	if [ -n "$SWAPFILE" ] && [ "${SWAPFILE#"$SWAPPATH/"}" != "$SWAPFILE" ] && [ -f "$SWAPFILE" ]; then
		swapon "$SWAPFILE"
	fi
done
' _ "$1" < /jffs/configs/swaps
EOF
		[ ! -x '/jffs/scripts/mount.d/K90swaps' ] && cat > '/jffs/scripts/mount.d/K90swaps' <<'EOF'
#!/bin/sh

[ -f /jffs/configs/swaps ] && xargs -r0 sh -c '#!/bin/sh
SWAPPATH="$1"
shift
for SWAPFILE in "$@"; do
	if [ -n "$SWAPFILE" ] && [ "${SWAPFILE#"$SWAPPATH/"}" != "$SWAPFILE" ] && tail -n+2 /proc/swaps | grep -q "^$(printf "%s\n" "$SWAPFILE" | sed '\''s/[]\/$*.^&[]/\\&/g'\'') "; then
		swapoff "$SWAPFILE" || swapoff -a;
	fi
done
' _ "$1" < /jffs/configs/swaps
EOF
		chmod +x '/jffs/scripts/mount.d/S10swaps' '/jffs/scripts/mount.d/K90swaps'
	fi
}

# Add or remove a file from the swaps config (automatic loading)
# Usage: swap_config add|remove FILEPATH
swap_config() {
	if [ -z "$2" ]; then
		false; return $?
	fi
	if [ "$1" = 'add' ]; then
		if [ ! -s /jffs/configs/swaps ]; then
			printf '%s\0' "$2" > /jffs/configs/swaps
			true; return $?
		else
			xargs -0 sh -c '#!/bin/sh
SWAPFILE="$1"
shift
for FILE in "$@"; do
	if [ "$FILE" = "$SWAPFILE" ]; then
		exit 1
	fi
done
printf '\''%s\0'\'' "$SWAPFILE" >> /jffs/configs/swaps' _ "$2" < /jffs/configs/swaps
			return $?
		fi
	elif [ "$1" = 'remove' ]; then
		if [ ! -f /jffs/configs/swaps ]; then
			false; return $?
		else
			xargs -r0 sh -c '#!/bin/sh
SWAPFILE="$1"
shift
FLAG="false"
for FILE in "$@"; do
	if [ "$FILE" = "$SWAPFILE" ]; then
		FLAG="true"
	else
		set -- "$@" "$FILE"
	fi
	shift
done
[ "$FLAG" != "true" ] && exit 1
printf '\''%s\0'\'' "$@" > /jffs/configs/swaps' _ "$2" < /jffs/configs/swaps
			return $?
		fi
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
	read -r _ FILE_SYSTEM _ _ FILE_CAPACITY _ <<-EOF
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
	swap_scripts enable
	if swap_config add "$SWAP_PATH/$SWAP_FILE"; then
		echo "Swap file automount created ($1)"
	fi
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
	if [ -f '/jffs/configs/swaps' ] && swap_config remove "$1"; then
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
	'add')
		shift
		swap_scripts enable
		swap_config add "$@"
	;;
	'remove')
		shift
		swap_config remove "$@"
	;;
	'list')
		[ -f /jffs/configs/swaps ] && xargs -r0 printf '%s\n' < /jffs/configs/swaps
	;;
esac
