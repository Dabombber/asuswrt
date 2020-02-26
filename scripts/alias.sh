#!/bin/sh
# shellcheck shell=ash

# Extend the service command to /opt
alias_service() {
	if [ $# -lt 1 ] || [ "$1" = '-h' ] || [ "$1" = '--help' ]; then
		echo 'Usage: service [ACTION_]SCRIPT [ARGUMENTS][; ...]'
		[ -x '/jffs/scripts/include/servicelist.sh' ] && . /jffs/scripts/include/servicelist.sh
		return
	fi

	local LINE
	if [ -x '/opt/bin/find' ]; then
		local CMDLIST PASS=""
		if ! CMDLIST="$(. /jffs/scripts/include/string.sh; str_token "$*")"; then return 1; fi
		while read -r LINE
		do
			if [ "$LINE" = 'reload_dnsmasq' ] || [ "$LINE" = 'reconfigure_dnsmasq' ]; then
				echo 'Sending SIGHUP to dnsmasq...'
				killall -HUP dnsmasq
				continue
			fi

			local SCRIPT="${LINE%% *}"
			local ARGS="${LINE#* }"
			local ACTION="${SCRIPT%%_*}"

			[ "$SCRIPT" = "$ARGS" ] && ARGS=""
			SCRIPT="${SCRIPT#*_}"
			[ "$ACTION" = "$SCRIPT" ] && ACTION=""

			if [ -z "$ACTION" ] || [ -z "$(/opt/bin/find /opt/etc/init.d/ -perm '-u+x' -name "S[0-9][0-9]$SCRIPT" -printf '.' -execdir sh -c "
				if [ \"\$2\" = 'enable' ] || [ \"\$2\" = 'disable' ]; then
					[ \"\$2\" = 'enable' ] && VAL='yes' || VAL='no'
					case \"\$(grep -F 'ENABLED=' \"\$1\")\" in
						*\"ENABLED=\$VAL\"*)
							echo \"\${1#./S??} is already \${2}d\" > /proc/$$/fd/2
						;;
						*'ENABLED='*)
							sed -i \"s/ENABLED=[:alnum:]*/ENABLED=\$VAL/\" \"\$1\"
							echo \"\${1#./S??} has been \${2}d\" > /proc/$$/fd/1
						;;
						*)
							echo \"Unable to \$2 \${1#./S??}, incompatible init.d file\" > /proc/$$/fd/2
						;;
					esac
				elif grep -Fq 'ENABLED=no' \"\$1\"; then
					echo \"\${1#./S??} is disabled, unable to \$2\" > /proc/$$/fd/2;
				else
					\"\$1\" \"\$2\" > /proc/$$/fd/1;
				fi
			" _ "{}" "$ACTION" \;)" ]; then
				PASS="$PASS;$LINE"
			fi
		done <<- EOF
			$CMDLIST
		EOF
		[ -z "$PASS" ] && return
		set -- "${PASS#;}"
	fi

	# Make sure no temp files stick around
	trap '{ rm -f "/tmp/.service$$.log" "/tmp/.service$$.fifo"; exit; }' EXIT INT TERM

	# Prepare to grab errors, can't just tail|grep since we need the tail pid
	mknod "/tmp/.service$$.fifo" p
	tail -n0 -F /tmp/syslog.log >"/tmp/.service$$.fifo" &
	local PID=$!
	grep --line-buffered '^... .. ..:..:.. rc: received unrecognized event: ' <"/tmp/.service$$.fifo" >"/tmp/.service$$.log" &

	# Send command, usleep 500000 is too short for logs to show
	/sbin/service "$@" >/dev/null
	sleep 1

	# Cleanup, grep will kill itself
	kill $PID 2>/dev/null

	# Check for errors
	if [ -s "/tmp/.service$$.log" ]; then
		while read -r LINE; do
			echo "Unrecognized event: ${LINE:49}" >&2
		done <"/tmp/.service$$.log"
	else
		echo 'Done.'
	fi
}

# Enables an entware service
alias_enable() {
	if [ $# -lt 1 ] || [ "$1" = '-h' ] || [ "$1" = '--help' ]; then
		echo 'Usage: enable SERVICE [...]'
		return
	fi

	if [ -x '/opt/bin/find' ]; then
		local SERVICE
		for SERVICE in "$@"; do
			if [ -z "$(/opt/bin/find /opt/etc/init.d/ -perm '-u+x' -name "S[0-9][0-9]$SERVICE" -printf '.' -execdir sh -c "
				case \"\$(grep -F 'ENABLED=' \"\$1\")\" in
					*'ENABLED=yes'*)
						echo \"\${1#./S??} is already enabled\" > /proc/$$/fd/2
					;;
					*'ENABLED='*)
						sed -i 's/ENABLED=.*/ENABLED=yes/' \"\$1\"
						echo \"\${1#./S??} has been disabled\" > /proc/$$/fd/1
					;;
					*)
						echo \"Unable to enable \${1#./S??}, incompatible init.d file\" > /proc/$$/fd/2
					;;
				esac
			" _ "{}" \;)" ]; then
				echo "Unable to find service: $SERVICE" >&2
			fi
		done
	else
		echo 'Entware not detected' >&2
	fi
}

# Disables an entware service
alias_disable() {
	if [ $# -lt 1 ] || [ "$1" = '-h' ] || [ "$1" = '--help' ]; then
		echo 'Usage: disable SERVICE [...]'
		return
	fi

	if [ -x '/opt/bin/find' ]; then
		local SERVICE
		for SERVICE in "$@"; do
			if [ -z "$(/opt/bin/find /opt/etc/init.d/ -perm '-u+x' -name "S[0-9][0-9]$SERVICE" -printf '.' -execdir sh -c "
				case \"\$(grep -F 'ENABLED=' \"\$1\")\" in
					*'ENABLED=yes'*)
						sed -i 's/ENABLED=yes/ENABLED=no/' \"\$1\"
						echo \"\${1#./S??} has been disabled\" > /proc/$$/fd/1
					;;
					*'ENABLED='*)
						echo \"\${1#./S??} is already disabled\" > /proc/$$/fd/2
					;;
					*)
						echo \"Unable to disable \${1#./S??}, incompatible init.d file\" > /proc/$$/fd/2
					;;
				esac
			" _ "{}" \;)" ]; then
				echo "Unable to find service: $SERVICE" >&2
			fi
		done
	else
		echo 'Entware not detected' >&2
	fi
}

# service restart_SERVICE shortcut
alias_restart() {
	if [ $# -lt 1 ] || [ "$1" = '-h' ] || [ "$1" = '--help' ]; then
		echo 'Usage: restart SERVICE [...]'
		return
	fi

	local SERVICE SERVICE_LIST=""
	for SERVICE in "$@"; do
		SERVICE_LIST="$SERVICE_LIST;restart_$SERVICE"
	done
	alias_service "${SERVICE_LIST#;}"
}

# service start_SERVICE shortcut
alias_start() {
	if [ $# -lt 1 ] || [ "$1" = '-h' ] || [ "$1" = '--help' ]; then
		echo 'Usage: start SERVICE [...]'
		return
	fi

	local SERVICE SERVICE_LIST=""
	for SERVICE in "$@"; do
		SERVICE_LIST="$SERVICE_LIST;start_$SERVICE"
	done
	alias_service "${SERVICE_LIST#;}"
}

# service stop_SERVICE shortcut
alias_stop() {
	if [ $# -lt 1 ] || [ "$1" = '-h' ] || [ "$1" = '--help' ]; then
		echo 'Usage: stop SERVICE [...]'
		return
	fi

	local SERVICE SERVICE_LIST=""
	for SERVICE in "$@"; do
		SERVICE_LIST="$SERVICE_LIST;stop_$SERVICE"
	done
	alias_service "${SERVICE_LIST#;}"
}

# Colour opkg output
alias_opkg() {
	[ ! -x '/opt/bin/opkg' ] && echo "$0: opkg: not found" >&2 && return 1
	local CSI
	CSI="$(printf '\e[')"

	# Field colours
	local CLR_NAME="${CSI}m"
	local CLR_VERSION="${CSI}1;31m"
	local CLR_VUPDATE="${CSI}1;35m"
	local CLR_SIZE="${CSI}1;33m"
	local CLR_DESC="${CSI}1;30m"
	local CLR_RESET="${CSI}m"

	local ARG SIZE="" SUBCOMMAND=""
	for ARG in "$@"; do
		[ "$ARG" = '--size' ] && SIZE='yes'
		[ -n "${ARG##-*}" ] && [ -z "$SUBCOMMAND" ] && SUBCOMMAND="$ARG"
	done
	if [ "$SUBCOMMAND" = "list-upgradable" ]; then
		/opt/bin/opkg "$@" | sed "s/\([^ ]*\) - \([^ ]*\) - \(.*\)/${CLR_NAME}\1${CLR_RESET} - ${CLR_VERSION}\2${CLR_RESET} - ${CLR_VUPDATE}\3/"
	elif [ "$SUBCOMMAND" = 'list' ] || [ "$SUBCOMMAND" = 'find' ]; then
		if [ "$SIZE" = 'yes' ]; then
			/opt/bin/opkg "$@" | sed "s/\([^ ]*\) - \([^ ]*\) - \([^ ]*\) - \(.*\)/${CLR_NAME}\1${CLR_RESET} - ${CLR_VERSION}\2${CLR_RESET} - ${CLR_SIZE}\3${CLR_RESET} - ${CLR_DESC}\4/"
		else
			/opt/bin/opkg "$@" | sed "s/\([^ ]*\) - \([^ ]*\) - \(.*\)/${CLR_NAME}\1${CLR_RESET} - ${CLR_VERSION}\2${CLR_RESET} - ${CLR_DESC}\3/"
		fi
	elif [ "$SUBCOMMAND" = 'list-installed' ]; then
		if [ "$SIZE" = 'yes' ]; then
			/opt/bin/opkg "$@" | sed "s/\([^ ]*\) - \([^ ]*\) - \(.*\)/${CLR_NAME}\1${CLR_RESET} - ${CLR_VERSION}\2${CLR_RESET} - ${CLR_SIZE}\3${CLR_RESET}/"
		else
			/opt/bin/opkg "$@" | sed "s/\([^ ]*\) - \(.*\)/${CLR_NAME}\1${CLR_RESET} - ${CLR_VERSION}\2${CLR_RESET}/"
		fi
	else
		/opt/bin/opkg "$@"
	fi
}

case "$1" in
	'service') shift && alias_service "$@";;
	'enable') shift && alias_enable "$@";;
	'disable') shift && alias_disable "$@";;
	'restart') shift && alias_restart "$@";;
	'start') shift && alias_start "$@";;
	'stop') shift && alias_stop "$@";;
	'opkg') shift && alias_opkg "$@";;
esac
