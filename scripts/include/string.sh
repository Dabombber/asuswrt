#!/bin/sh
# shellcheck shell=ash
# shellcheck disable=2169

# Variable containing a new line as "$()" strips it
readonly _NL='
'

# Escape a string for use in quotes or a regular expression
# Usage string_escape [s|single|d|double|e|extended|b|basic]
string_escape() {
	case "$1" in
		# Single quoted string: '
		's'|'single')
			sed "s/'/'\\\\''/g"
			#sed "s/'/'\"'\"'/g"
		;;
		# Double quoted string: "\$`
		'd'|'double')
			sed 's/["\$`]/\\&/g'
		;;
		# Extended regular expression: ])}|\/$*+?.^&{([
		'e'|'extended')
			sed 's/[])}|\/$*+?.^&{([]/\\&/g'
		;;
		# Basic regular expression: ]\/$*.^&[
		'b'|'basic'|*)
			sed 's/[]\/$*.^&[]/\\&/g'
		;;
	esac
}

# Quote strings suitable for use with sed
# Usage _quote [STRING]
_quote() {
	if [ $# -gt 0 ]; then
		awk -v s="$*" 'BEGIN{gsub(/[]\/$*.^&[]/,"\\\\&",s);gsub(/\n+$/,"",s);gsub(/\n/,"\\n",s);print s}'
	else
		awk '{gsub(/[]\/$*.^&[]/,"\\\\&");printf (FNR>1)?"\\n%s":"%s",$0}END{print ""}'
	fi
}

# This function looks for a substring in a string
# Usage: str_contains STRING SEARCH
str_contains() {
        [ ${#2} -eq 0 ] || [ "$1" != "${1#*"$2"}" ]
}

# A random hex string
# Usage: randhex [LENGTH]
str_randhex() {
	tr -dc 'A-F0-9' < /dev/urandom | dd bs=1c count="${1:-8}c" 2>/dev/null
}

# Split a string ($1, or stdin if empty) by a delimiter ($2, default ;) and applies a seperator ($3, default \n) preserving quoted strings
# Usage: str_token [-d DELIMITER] [-s SEPERATOR] [STRING]
#	Will most likely break using ' or " as a delimiter
#	Whitespace is not trimmed
str_token() {
	local STRING QUOTES='no' DELIMITER=';' SEPERATOR="$_NL" SUB
	SUB="$(printf '\x1A')"

	while [ $# -gt 0 ]; do
		case "$1" in
			'-q')
				QUOTES='yes'
			;;
			'-d'*)
				DELIMITER="${1#-d}"
				if [ -z "$DELIMITER" ]; then
					DELIMITER="$2"
					shift
				fi
			;;
			'-s'*)
				SEPERATOR="${1#-s}"
				if [ -z "$SEPERATOR" ]; then
					SEPERATOR="$2"
					shift
				fi
			;;
			'--')
				STRING="$2"
				break
			;;
			*)
				STRING="$1"
			;;
		esac
		shift
	done
	STRING="${STRING-"$(test -t 0 || cat)"}"
	STRING="${STRING//\\\\/$SUB}"

	local STRING_QQ STRING_Q STRING_RIGHT
	while [ -n "$STRING" ]; do
		STRING_RIGHT="$STRING"
		while :; do
			STRING_QQ="${STRING_RIGHT%%"\""*}"
			STRING_RIGHT="${STRING_RIGHT#"$STRING_QQ"}"
			if [ -z "$STRING_RIGHT" ] || [ "${STRING_QQ%"\\"}" = "$STRING_QQ" ]; then break; fi
			STRING_RIGHT="${STRING_RIGHT#"\""}"
		done
		STRING_QQ="${STRING%"$STRING_RIGHT"}"

		STRING_Q="${STRING%%"'"*}"

		if [ "$STRING_QQ" != "$STRING" ] && [ ${#STRING_QQ} -lt ${#STRING_Q} ]; then
			STRING_RIGHT="${STRING_QQ//"$DELIMITER"/"$SEPERATOR"}"
			printf '%s' "${STRING_RIGHT//$SUB/\\\\}"

			STRING="${STRING#"$STRING_QQ\""}"

			STRING_RIGHT="$STRING"
			while :; do
				STRING_QQ="${STRING_RIGHT%%"\""*}"
				STRING_RIGHT="${STRING_RIGHT#"$STRING_QQ"}"
				if [ -z "$STRING_RIGHT" ] || [ "${STRING_QQ%"\\"}" = "$STRING_QQ" ]; then break; fi
				STRING_RIGHT="${STRING_RIGHT#"\""}"
			done
			STRING_QQ="${STRING%"$STRING_RIGHT"}"

			[ "$STRING_QQ" = "$STRING" ] && echo "Error: Unmatched quote ($0)" >&2 && return 1
			if [ "$QUOTES" = 'yes' ]; then
				printf '"%s"' "${STRING_QQ//$SUB/\\\\}"
			else
				printf '%s' "${STRING_QQ//$SUB/\\\\}"
			fi

			STRING="${STRING#"$STRING_QQ\""}"
		elif [ "$STRING_Q" != "$STRING" ]; then
			STRING_RIGHT="${STRING_Q//"$DELIMITER"/"$SEPERATOR"}"
			printf '%s' "${STRING_RIGHT//$SUB/\\\\}"

			STRING="${STRING#"$STRING_Q'"}"
			STRING_Q="${STRING%%"'"*}"
			[ "$STRING_Q" = "$STRING" ] && echo "Error: Unmatched quote ($0)" >&2 && return 1
			if [ "$QUOTES" = 'yes' ]; then
				printf "'%s'" "${STRING_Q//$SUB/\\\\}"
			else
				printf '%s' "${STRING_Q//$SUB/\\\\}"
			fi

			STRING="${STRING#"$STRING_Q'"}"
		else
			STRING_RIGHT="${STRING//"$DELIMITER"/"$SEPERATOR"}"
			printf '%s' "${STRING_RIGHT//$SUB/\\\\}"
			STRING=''
		fi
	done
	printf '\n'
}

# This function looks for a string and replaces it with a different string, from stdin or in a specified file
# Usage: str_replace SEARCH REPLACE [FILE]
str_replace() {
	PATTERN="$(_quote "$1")"
	CONTENT="$(_quote "$2")"
	sed ${3+-i} "s/$PATTERN/$CONTENT/" ${3+"$3"}
}

# This function looks for a string and inserts a string before it, from stdin or in a specified file
# Usage: str_prepend SEARCH INSERT [FILE]
str_prepend() {
	PATTERN="$(_quote "$1")"
	CONTENT="$(_quote "$2")"
	sed ${3+-i} "s/$PATTERN/$CONTENT&/" ${3+"$3"}
}

# This function looks for a string and inserts a string after it, from stdin or in a specified file
# Usage: str_append SEARCH INSERT [FILE]
str_append() {
	PATTERN="$(_quote "$1")"
	CONTENT="$(_quote "$2")"
	sed ${3+-i} "s/$PATTERN/&$CONTENT/" ${3+"$3"}
}

# This function will delete a given string, from stdin or in a specified file
# Usage: str_delete SEARCH [FILE]
str_delete() {
	PATTERN="$(_quote "$1")"
	sed ${2+-i} "s/$PATTERN//" ${2+"$2"}
}

# This function looks for a line and replaces it with a specified line, from stdin or in a specified file
# Usage: line_replace SEARCH REPLACE [FILE]
line_replace() {
	PATTERN="$(_quote "$1")"
	CONTENT="$(_quote "$2")"
	sed ${3+-i} -e "/$PATTERN/c\\" -e "$CONTENT" ${3+"$3"}
}

# This function looks for a line and replaces it if found or appends if not, from stdin or in a specified file
# Usage: line_replace SEARCH REPLACE [FILE]
line_applace() {
	PATTERN="$(_quote "$1")"
	CONTENT="$(_quote "$2")"
	sed ${3+-i} "/$PATTERN/{h;s/.*/$CONTENT/};\${x;/^\$/{s//$CONTENT/;H};x}" ${3+"$3"}
}

# This function looks for a line and inserts a specified line before it, from stdin or in a specified file
# Usage: line_prepend SEARCH INSERT [FILE]
line_prepend() {
	PATTERN="$(_quote "$1")"
	CONTENT="$(_quote "$2")"
	sed ${3+-i} -e "/$PATTERN/i\\" -e "$CONTENT" ${3+"$3"}
}

# This function looks for a line and inserts a specified line after it, from stdin or in a specified file
# Usage: line_append SEARCH INSERT [FILE]
line_append() {
	PATTERN="$(_quote "$1")"
	CONTENT="$(_quote "$2")"
	sed ${3+-i} -e "/$PATTERN/a\\" -e "$CONTENT" ${3+"$3"}
}

# This function will delete a line containing a given string, from stdin or in a specified file
# Usage: line_delete STRING [FILE]
line_delete() {
	PATTERN="$(_quote "$1")"
	sed ${2+-i} "/$PATTERN/d" ${2+"$2"}
}

# This function will insert a given string at the beginning of a given file
# Usage: file_prepend INSERT [FILE]
file_prepend() {
	CONTENT="$(_quote "$1")"
	sed ${2+-i} "1s/^/$CONTENT\n/" ${2+"$2"}
}

# This function will append a given string at the end of a given file
# Usage: file_append INSERT FILE
file_append() {
	printf "%s\n" "$1" >> "$2"
}
