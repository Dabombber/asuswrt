#!/bin/sh
# shellcheck shell=ash
# shellcheck disable=2169

ESC="$(printf '\e')"
SS3="${ESC}O"
CSI="${ESC}["

CURSOR_HIDE="${ESC}[?25l"
CURSOR_SHOW="${ESC}[?25h"

#TEXT_CLEARLINE="${CSI}2K"
TEXT_INVERT="${CSI}7m"
TEXT_INVERT_OFF="${CSI}27m"

#MOUSE_X11="${CSI}?1000h"
#MOUSE_X11_OFF="${CSI}?1000l"
#MOUSE_SGR="${CSI}?1006h"
#MOUSE_SGR_OFF="${CSI}?1006l"
#MOUSE_XY="${CSI}?1000h"
#MOUSE_XY_OFF="${CSI}?1000h"

_TEMPFILE="/tmp/.$(tr -dc 'A-F0-9' < /dev/urandom | dd bs=1c count=8c 2>/dev/null)"
trap '{ rm -f "$_TEMPFILE"; exit; }' EXIT INT TERM

# Read a single key from user input
read_key() {
    local KEY
    IFS= read -rs -n 1 KEY
    if [ "$KEY" = "$ESC" ]; then
        local _K STDIN
        STDIN="/proc/$$/fd/0"
        :> "$_TEMPFILE"
        ( IFS= read -rs -n 1 _KEY <"$STDIN"; printf '%s\n' "$_KEY" > "$_TEMPFILE" ) &
        local PID_R=$!
        ( usleep 10000; kill $PID_R 2>/dev/null ) &
		wait $PID_R
        IFS= read -r _K <"$_TEMPFILE"
        KEY="$KEY$_K"
		# Need to check for \e\e[X as an alternative to \e[1;3X
        if [ "$_K" = "?" ] || [ "$_K" = "O" ] || [ "$_K" = "[" ] || [ "$_K" = "<" ]; then
            while IFS= read -rs -n 1 -t 1 _K; do
                if [ "$KEY" = "${CSI}M" ]; then
                    IFS= read -rs -n 3 -t 1 _K
                    KEY="$KEY$_K"
                    break;
                fi
                KEY="$KEY$_K"
                case "$_K" in [^0-9\;]) break;; esac
            done
        fi
    fi
    printf '%s' "$KEY"
}


# Return a key name from an escape sequence
# Usage: key_name [-mc] [KEY]
#	m	Show keypress modifiers
#	c	Show mouse XY coordinates
# shellcheck disable=SC2120
key_name() {
	local SHOW_MODS SHOW_COORD KEY ARG
	for ARG in "$@"; do
		if [ "${#ARG}" -ge 2 ] && [ "${ARG#"-"}" != "$ARG" ]; then
			[ -z "${ARG##*m*}" ] && SHOW_MODS="yes"
			[ -z "${ARG##*c*}" ] && SHOW_COORD="yes"
		else
			KEY="$ARG"
		fi
	done
	KEY="${KEY:-"$(test -t 0 || cat)"}"

	# Extract modifiers
	local MOUSE_X MOUSE_Y MOD
	if [ "$KEY" = "${CSI}Z" ]; then
		# Special case: shift+tab
		KEY="	"
		MOD=2
	elif [ "${KEY#"$ESC$CSI"}" != "$KEY" ]; then
		# Special case: alt+arrow
		KEY="${KEY/$ESC$CSI/$CSI}"
		MOD=3
	elif [ "${#KEY}" -eq 1 ]; then
		# ^key
		if [ "$(printf '%d' "'$KEY")" -ge 128 ]; then
			MOD=9
			KEY="$(printf '%c' $((KEY - 128)))"
		fi
	elif [ "${#KEY}" -eq 2 ]; then
		# ESC key
		KEY="${KEY#?}"
		if [ "$(printf '%d' "'$KEY")" -ge 128 ]; then
			MOD=11
			KEY="$(printf '%c' $((KEY - 128)))"
		else
			MOD=3
		fi
	elif [ "${KEY#"${CSI}<"}" != "$KEY" ]; then
		# SGR mouse
		# CSI < Cb ; Cx ; Cy M
		local UPDOWN="${KEY#"${KEY%?}"}" VAL="${KEY#"${CSI}<"}"
		MOUSE_Y="${VAL##*";"}"
		MOUSE_Y="${VAL%"$UPDOWN"}"
		MOUSE_X="${VAL#*";"}"
		MOUSE_X="${VAL%";"*}"
		VAL="${VAL%%";"*}"

		case $(((VAL&28)>>2)) in
			1) MOD=1;;
			2) MOD=9;;
			3) MOD=10;;
			4) MOD=5;;
			5) MOD=6;;
			6) MOD=13;;
			7) MOD=14;;
		esac
		VAL=$(((VAL&192)>>4 + (VAL&3)))
		if [ "$VAL" -lt 4 ]; then
			KEY="Mouse$((VAL+1))"
		else
			KEY="Mouse$VAL"
		fi
		if [ "$UPDOWN" = "m" ]; then
			KEY="$KEY Release"
		fi
	elif [ "${KEY#"${CSI}M"}" != "$KEY" ]; then
		# X10/11 mouse
		# CSI M Cb Cx Cy
		local BXY VAL
		BXY="${KEY#"${CSI}M"}"
		MOUSE_X="${BXY#?}"
		MOUSE_Y=$(("${BXY#??}" - 32))
		MOUSE_X=$(("${MOUSE_X%?}" - 32))
		VAL=$(("$(printf '%d' "'${BXY%??}")" - 32))
		# 0b bb1mmmbb button x2, +32(0b100000) to be printable, modifiers x3, button x2
		case $(((VAL&28)>>2)) in
			1) MOD=1;;
			2) MOD=9;;
			3) MOD=10;;
			4) MOD=5;;
			5) MOD=6;;
			6) MOD=13;;
			7) MOD=14;;
		esac
		VAL=$(((VAL&192)>>4 + (VAL&3)))
		if [ "$VAL" -eq 4 ]; then
			KEY="Mouse Release"
		elif [ "$VAL" -lt 4 ]; then
			KEY="Mouse$((VAL+1))"
		else
			KEY="Mouse$VAL"
		fi
	elif [ "$KEY" != "${KEY#*";"}" ]; then
		END="${KEY#"${KEY%?}"}"
		if [ "$END" = "~" ]; then
			# {CSI}/{SS3} key ; modifier ~
			MOD="${KEY#*;}"
			MOD="${MOD%"~"}"
			KEY="${KEY%";$MOD~"}~"
		elif [ "$END" != ";" ]; then
			# {CSI}/{SS3} 1 ; modifier key
			MOD="${KEY#*1;}"
			MOD="${MOD%"$END"}"
			KEY="${KEY%"1;$MOD$END"}$END"
		fi
	fi

	local MODIFIER=""
	if [ "$SHOW_MODS" = "yes" ]; then
		case "$MOD" in
			2) MODIFIER="Shift";;
			3) MODIFIER="Alt";;
			4) MODIFIER="Shift Alt";;
			5) MODIFIER="Ctrl";;
			6) MODIFIER="Shift Ctrl";;
			7) MODIFIER="Alt Ctrl";;
			8) MODIFIER="Shift Alt Ctrl";;
			9) MODIFIER="Meta";;
			10) MODIFIER="Meta Shift";;
			11) MODIFIER="Meta Alt";;
			12) MODIFIER="Meta Alt Shift";;
			13) MODIFIER="Meta Ctrl";;
			14) MODIFIER="Meta Ctrl Shift";;
			15) MODIFIER="Meta Ctrl Alt";;
			16) MODIFIER="Meta Ctrl Alt Shift";;
		esac
		MODIFIER="$MODIFIER "
	fi
	if [ "$SHOW_COORD" = "yes" ] && [ -n "$MOUSE_X" ] && [ -n "$MOUSE_Y" ]; then
		MODIFIER="[$MOUSE_X:MOUSE_Y] $MODIFIER"
	fi

	case "$KEY" in
		# Mouse
		"Mouse Release") echo "${MODIFIER}Mouse Release" && return;;
		"Mouse"*) echo "${MODIFIER}Mouse$KEY" && return;;

		# Arrow keys
		"${CSI}A"|"${SS3}A") echo "${MODIFIER}Up";;
		"${CSI}B"|"${SS3}B") echo "${MODIFIER}Down";;
		"${CSI}C"|"${SS3}C") echo "${MODIFIER}Right";;
		"${CSI}D"|"${SS3}D") echo "${MODIFIER}Left";;

		# Page navigation
		"${CSI}1~"|"${CSI}H"|"${SS3}H") echo "${MODIFIER}Home";;
		"${CSI}4~"|"${CSI}F"|"${SS3}F") echo "${MODIFIER}End";;
		"${CSI}2~") echo "${MODIFIER}Insert";;
		"${CSI}3~") echo "${MODIFIER}Delete";;
		"${CSI}5~") echo "${MODIFIER}PageUp";;
		"${CSI}6~") echo "${MODIFIER}PageDown";;

		# Whitespace
		"${SS3} "|" ") echo "${MODIFIER}Space";;
		"${SS3}I"|"	") echo "${MODIFIER}Tab";;
		"${SS3}M"|"") echo "${MODIFIER}Enter";;
		"$(printf '\x7F')") echo "${MODIFIER}Backspace" && return;;

		# Numpad
		"${SS3}j") echo "${MODIFIER}*";;
		"${SS3}k") echo "${MODIFIER}+";;
		"${SS3}l") echo "${MODIFIER},";;
		"${SS3}m") echo "${MODIFIER}-";;
		"${SS3}n") echo "${MODIFIER}.";;
		"${SS3}o") echo "${MODIFIER}/";;
		"${SS3}p") echo "${MODIFIER}0";;
		"${SS3}q") echo "${MODIFIER}1";;
		"${SS3}r") echo "${MODIFIER}2";;
		"${SS3}s") echo "${MODIFIER}3";;
		"${SS3}t") echo "${MODIFIER}4";;
		"${SS3}u"|"${CSI}E") echo "${MODIFIER}5";;	# CSI E, "Begin" key, doesn't seem to be handled specially
		"${SS3}v") echo "${MODIFIER}6";;
		"${SS3}w") echo "${MODIFIER}7";;
		"${SS3}x") echo "${MODIFIER}8";;
		"${SS3}y") echo "${MODIFIER}9";;
		"${SS3}X") echo "${MODIFIER}=";;

		# F1-20
		"${CSI}11~"|"${SS3}P") echo "${MODIFIER}F1";;
		"${CSI}12~"|"${SS3}Q") echo "${MODIFIER}F2";;
		"${CSI}13~"|"${SS3}R") echo "${MODIFIER}F3";;
		"${CSI}14~"|"${SS3}S") echo "${MODIFIER}F4";;
		"${CSI}15~") echo "${MODIFIER}F5";;
		"${CSI}17~") echo "${MODIFIER}F6";;
		"${CSI}18~") echo "${MODIFIER}F7";;
		"${CSI}19~") echo "${MODIFIER}F8";;
		"${CSI}20~") echo "${MODIFIER}F9";;
		"${CSI}21~") echo "${MODIFIER}F10";;
		"${CSI}23~") echo "${MODIFIER}F11";;
		"${CSI}24~") echo "${MODIFIER}F12";;
		"${CSI}25~") echo "${MODIFIER}F13";;
		"${CSI}26~") echo "${MODIFIER}F14";;
		"${CSI}28~") echo "${MODIFIER}F15";;
		"${CSI}29~") echo "${MODIFIER}F16";;
		"${CSI}31~") echo "${MODIFIER}F17";;
		"${CSI}32~") echo "${MODIFIER}F18";;
		"${CSI}33~") echo "${MODIFIER}F19";;
		"${CSI}34~") echo "${MODIFIER}F20";;

		*) echo "${MODIFIER}$KEY";;
	esac
}


key_code() {
	local KEY="${1:-"$(test -t 0 || cat)"}"
	KEY="${KEY//$ESC/\\e}"
	local END="${KEY#"${KEY%?}"}" VAL
	VAL="$(printf '%d' "'$END")"
	if [ "$VAL" -ge 128 ]; then
		KEY="${KEY%"$END"}^$(printf '%c' $((VAL - 128)))"
	fi
	printf '%s' "$KEY"
}


select_option() {
	local SELECT=1 PREFIX="$CURSOR_HIDE$1 "
	shift
	while :; do
		local IDX=1 LINE="$PREFIX" OPTION
		for OPTION in "$@"; do
			if [ "$IDX" -eq "$SELECT" ]; then
				LINE="$LINE $TEXT_INVERT$OPTION$TEXT_INVERT_OFF"
			else
				LINE="$LINE $OPTION"
			fi
			IDX=$((IDX+1))
		done
		printf '\r%s' "$LINE" >"$(tty)"
		# shellcheck disable=SC2119
		case "$(read_key | key_name)" in
			"Enter") break;;
			"Left")
				SELECT=$((SELECT-1))
				[ "$SELECT" -lt 1 ] && SELECT=$#
					;;
			"Right")
				SELECT=$((SELECT+1))
				[ "$SELECT" -gt $# ] && SELECT=1
				;;
		esac
	done

	printf '%s\n' "$CURSOR_SHOW" >"$(tty)"
	while [ "$SELECT" -ne 1 ]; do shift; SELECT=$((SELECT-1)); done
	echo "$1"
}


#select_option 'Number:' 'one' 'two' 'three'


#while :; do
#	printf '%s\n' "$(read_key | key_name -m)"
#done
