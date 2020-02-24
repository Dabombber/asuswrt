#!/bin/sh
# shellcheck shell=ash
# shellcheck disable=SC2169

###
### Default values
###

# What to call ourselves
DEFAULT_NAME='adblock'

# Data location, defaults to somewhere out of the way in entware but can be anywhere with enough space
DEFAULT_DIR="/opt/share/$DEFAULT_NAME"

# Optional file containing urls to hostlists
DEFAULT_HOSTS_CONF="$DEFAULT_DIR/$DEFAULT_NAME.conf"

# Directory to store downloaded hostlists
DEFAULT_HOSTS_DIR="$DEFAULT_DIR/download"

# Extension for hostlist names generated from URL
DEFAULT_HOSTS_EXT='.list'

# Default hostlist, file names and descriptions optional
DEFAULT_HOSTS_LIST='## https://pgl.yoyo.org/adservers/
yoyo-adservers.list http://pgl.yoyo.org/adservers/serverlist.php?hostformat=nohtml&mimetype=plaintext Includes hostnames and domains used for serving ad content, tracking users, spyware servers, and occasionally malware and other nasty purposes.

## https://adaway.org/
#adaway-hosts.list https://adaway.org/hosts.txt Blocking mobile ad providers and some analytics providers

## https://someonewhocares.org/hosts/
#someonewhocares-hosts.list https://someonewhocares.org/hosts/zero/hosts How to make the internet not suck (as much).

## https://github.com/StevenBlack/hosts
#stevenblack-unified.list https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts Extending and consolidating hosts files from several well-curated sources like adaway.org, mvps.org, malwaredomainlist.com, someonewhocares.org, and potentially others.
#stevenblack-fakenews.list https://raw.githubusercontent.com/StevenBlack/hosts/master/extensions/fakenews/hosts For fake news sites.
#stevenblack-porn.list https://raw.githubusercontent.com/StevenBlack/hosts/master/extensions/porn/hosts For porn sites.
#stevenblack-social.list https://raw.githubusercontent.com/StevenBlack/hosts/master/extensions/social/hosts For common social media sites.
#stevenblack-gambling.list https://raw.githubusercontent.com/StevenBlack/hosts/master/extensions/gambling/hosts For common online betting sites.

## https://hosts-file.net
#hphosts-ad_servers.list https://hosts-file.net/ad_servers.txt This file contains ad/tracking servers listed in the hpHosts database.
#hphosts-emd.list https://hosts-file.net/emd.txt This file contains malware sites listed in the hpHosts database.
#hphosts-exp.list https://hosts-file.net/exp.txt This file contains exploit sites listed in the hpHosts database.
#hphosts-fsa.list https://hosts-file.net/fsa.txt This file contains fraud sites listed in the hpHosts database.
#hphosts-grm.list https://hosts-file.net/grm.txt This file contains sites involved in spam (that do not otherwise meet any other classification criteria) listed in the hpHosts database.
#hphosts-hfs.list https://hosts-file.net/hfs.txt This file contains sites spamming the hpHosts forums (and not meeting any other classification criteria) listed in the hpHosts database.
#hphosts-hjk.list https://hosts-file.net/hjk.txt This file contains hijack sites listed in the hpHosts database.
#hphosts-mmt.list https://hosts-file.net/mmt.txt This file contains sites involved in misleading marketing (e.g. fake Flash update adverts) listed in the hpHosts database.
#hphosts-pha.list https://hosts-file.net/pha.txt This file contains illegal pharmacy sites listed in the hpHosts database.
#hphosts-psh.list https://hosts-file.net/psh.txt This file contains phishing sites listed in the hpHosts database.
#hphosts-pup.list https://hosts-file.net/pup.txt This file contains PUP sites listed in the hpHosts database.
#hphosts-wrz.list https://hosts-file.net/wrz.txt This file contains warez/piracy sites listed in the hpHosts database.
#hphosts-partial.list https://hosts-file.net/hphosts-partial.txt This file contains a list of sites that have been added AFTER the last full release of hpHosts.'

# Optional file containing domains to exclude
DEFAULT_WHITE_FILE="$DEFAULT_DIR/white.list"

# Some host files add common LAN entries, since we ignore the IP these should be filtered
# Full list, most excluded by fqdn regex:
#	local
#	localhost
#	localhost.localdomain
#	localhost4
#	localhost4.localdomain4
#	localhost6
#	localhost6.localdomain6
#	broadcasthost
#	ip6-localhost
#	ip6-loopback
#	ip6-localnet
#	ip6-mcastprefix
#	ip6-allnodes
#	ip6-allrouters
#	ip6-allhosts
#	0.0.0.0
#	127.0.0.1
#	::
#	::1
DEFAULT_WHITE_LIST='localhost.localdomain'

# IPs to use for blocked domains
DEFAULT_IP4='0.0.0.0'
DEFAULT_IP6='::'

# Domains per line for hosts files, slightly smaller host files generated but no difference to dnsmasq memory usage
DEFAULT_DPL=10

# Time to update hosts [HOUR|#[:MINUTE|#] [am|pm]] [daily|weekly|WEEKDAY]
DEFAULT_CRON='3:##am'

# Verbosity of messages printed to console users
DEFAULT_LOGLEVEL='info'


trap '{ rm -f "/tmp/.script$$"; exit; }' EXIT INT TERM
cat > "/tmp/.script$$" <<'#ENDSCRIPT' && . "/tmp/.script$$"
###
### Load config settings
###

# Use either preset values or defaults
readonly ADBLOCK_NAME="${ADBLOCK_NAME-"$DEFAULT_NAME"}"
readonly ADBLOCK_DIR="${ADBLOCK_DIR-"$DEFAULT_DIR"}"
readonly ADBLOCK_HOSTS_CONF="${ADBLOCK_HOSTS_CONF-"$DEFAULT_HOSTS_CONF"}"
readonly ADBLOCK_HOSTS_DIR="${ADBLOCK_HOSTS_DIR-"$DEFAULT_HOSTS_DIR"}"
readonly ADBLOCK_HOSTS_EXT="${ADBLOCK_HOSTS_EXT-"$DEFAULT_HOSTS_EXT"}"
readonly ADBLOCK_HOSTS_LIST="${ADBLOCK_HOSTS_LIST-"$DEFAULT_HOSTS_LIST"}"
readonly ADBLOCK_WHITE_FILE="${ADBLOCK_WHITE_FILE-"$DEFAULT_WHITE_FILE"}"
readonly ADBLOCK_WHITE_LIST="${ADBLOCK_WHITE_LIST-"$DEFAULT_WHITE_LIST"}"
readonly ADBLOCK_IP4="${ADBLOCK_IP4-"$DEFAULT_IP4"}"
readonly ADBLOCK_IP6="${ADBLOCK_IP6-"$DEFAULT_IP6"}"
readonly ADBLOCK_DPL="${ADBLOCK_DPL-"$DEFAULT_DPL"}"
readonly ADBLOCK_CRON="${ADBLOCK_CRON-"$DEFAULT_CRON"}"
readonly ADBLOCK_LOGLEVEL="${ADBLOCK_LOGLEVEL-"$DEFAULT_LOGLEVEL"}"

# Don't need these any more
unset DEFAULT_NAME
unset DEFAULT_DIR
unset DEFAULT_HOSTS_CONF
unset DEFAULT_HOSTS_DIR
unset DEFAULT_HOSTS_EXT
unset DEFAULT_HOSTS_LIST
unset DEFAULT_WHITE_FILE
unset DEFAULT_WHITE_LIST
unset DEFAULT_IP4
unset DEFAULT_IP6
unset DEFAULT_DPL
unset DEFAULT_CRON
unset DEFAULT_LOGLEVEL


###
### Utility functions
###

# https://gist.github.com/syzdek/6086792
readonly IPV4_REGEX='^((25[0-5]|(2[0-4]|1?[0-9])?[0-9])\.){3}(25[0-5]|(2[0-4]|1?[0-9])?[0-9])$'
readonly IPV6_REGEX='^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]+|::(ffff(:0{1,4})?:)?((25[0-5]|(2[0-4]|1?[0-9])?[0-9])\.){3}(25[0-5]|(2[0-4]|1?[0-9])?[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1?[0-9])?[0-9])\.){3}(25[0-5]|(2[0-4]|1?[0-9])?[0-9]))$'
# Should match any valid fqdn, and some invalid ones (labels starting or ending with a hyphen)
# https://stackoverflow.com/a/3523068
# https://stackoverflow.com/q/11809631
readonly FQDN_REGEX='^([a-zA-Z0-9_\-]{1,63}\.)+((xn--[a-z0-9]+)|([a-zA-Z]{2,}))\.?$'

# Test if a string is a valid ip address
# Usage: is_ipv4 [STRING]
is_ipv4() {
	if [ $# -gt 0 ]; then
		printf '%s\n' "$1" | grep -qE "$IPV4_REGEX"
	else
		grep -qE "$IPV4_REGEX"
	fi
}

# Test if a string is a valid ipv6 address
# Usage: is_ipv6 [STRING]
is_ipv6() {
	if [ $# -gt 0 ]; then
		printf '%s\n' "$1" | grep -qE "$IPV6_REGEX"
	else
		grep -qE "$IPV6_REGEX"
	fi
}

# Quote strings suitable for use with sed
# Usage sed_quote STRING
sed_quote() {
	printf '%s\n' "$1" | sed 's/[]\/$*.^&[]/\\&/g';
}

# Test if a string is a valid fqdn
# Usage: is_domain [STRING]
is_domain() {
	if [ $# -gt 0 ]; then
		[ "${#1}" -ge 1 ] && [ "${#1}" -le 254 ] && printf '%s\n' "$1" | grep -qE "$FQDN_REGEX"
	else
		grep -E '^.{1,254}$' | grep -qE "$FQDN_REGEX"
	fi
}

# Test if arguments are valid numbers and are in order
# Usage: is_number_between NUMBER [NUMBER]...
is_number_ordered() {
	[ $# -ne 0 ] || return $?
	local NUM PREV
	for NUM in "$@"; do
		[ -n "${NUM##*[!0-9]*}" ] || return $?
		[ -z "$PREV" ] || [ "$PREV" -le "$NUM" ] || return $?
		PREV="$NUM"
	done
	true; return $?
}

# True if called from cron, may fail if a parent in the tree has died
# Usage: is_cron_child
is_cron_child() {
	local PROCESS="$PPID" CRON_PID
	CRON_PID="$(pidof crond)"
	while [ "$PROCESS" -ne 1 ] && [ -d "/proc/$PROCESS" ]; do
		if [ "$CRON_PID" -eq "$PROCESS" ]; then
			true; return $?
		fi
		read -r _ _ _ PROCESS _ < "/proc/$PROCESS/stat"
	done
	false; return $?
}

# Return the last modifed time (epoch) of a url
# Usage: get_url_modified URL
get_url_modified() {
	local DATE
	if [ -z "${1##*"raw.githubusercontent.com"*}" ]; then
		# Github doesn't send Last-Modified headers, use the api instead
		local OWNER REPO BRANCH REPOPATH
		IFS="/" read -r _ OWNER REPO BRANCH REPOPATH <<- EOF
			${1#*://}
		EOF

		DATE="$(curl -sf "https://api.github.com/repos/$OWNER/$REPO/commits?path=$REPOPATH&sha=$BRANCH&per_page=1" | awk -F': ' '/^[[:space:]]*"date"[[:space:]]*:/{gsub(/["[:space:]]/,"",$2);d=$2};END{print d}')"
		if [ -n "$DATE" ]; then
			date -D '%Y-%m-%dT%H:%M:%SZ' -d "$DATE" '+%s'
		fi
	else
		DATE="$(curl -sfIL "$1" | awk -F': ' 'NF==0{p=1};p&&NF>0{d="";p=0};/^Last-Modified:/{d=$2};END{print d}')"
		if [ -n "$DATE" ]; then
			date -u -D '%a, %d %b %Y %H:%M:%S GMT' -d "$DATE" '+%s'
		fi
	fi
}

# Return a file name based on the domain and last couple of parts of a URL
# Usage: generate_filename URL
generate_filename() {
	# scheme://[userinfo@]host.tld[:port]path[?query][#fragment]
	local URL DOMAIN BASENAME

	# Cut out any unneeded junk
	URL="${1%%#*}"
	URL="${URL%%\?*}"
	URL="${URL#*://}"
	URL="${URL#*@}"

	DOMAIN="${URL%[/:]"${URL#*[/:]}"}"
	URL="${URL#"$DOMAIN"}"
	if [ "$URL" != "${URL#:}" ]; then
		URL="${URL#:}"
		URL="${URL#"${URL%?"${URL#*[!0-9]}"}"}"
	fi
	if [ "$DOMAIN" = 'raw.githubusercontent.com' ]; then
		# Change to something meaningful for github hosted files
		URL="${URL#/}"
		DOMAIN="${URL%/"${URL#*/}"}"
		URL="${URL#"$DOMAIN"}"
	else
		# Remove subdomains
		DOMAIN="${DOMAIN#"${DOMAIN%\.*\.*}."}"
	fi

	BASENAME="${URL#"${URL%/*/*}/"}"
	if [ -n "$BASENAME" ] && [ "$BASENAME" != "$URL" ]; then
		BASENAME="${BASENAME//"/"/-}"
		printf '%s\n' "$DOMAIN-${BASENAME%\.???}"
	else
		BASENAME="${URL##*/}"
		if [ -n "$BASENAME" ] && [ "$BASENAME" != "$URL" ]; then
			printf '%s\n' "$DOMAIN-${BASENAME%\.???}"
		else
			printf '%s\n' "$DOMAIN"
		fi
	fi
}

# Get the index of a short or long weekday name
# Usage: weekday_to_num WEEKDAY
weekday_to_num() {
	local DATE NUM=0
	while [ $NUM -lt 7 ]; do
		DATE="$(date -d "000${NUM}0000" '+%a %A %w')"
		if printf '%s\n' "${DATE% ?}" | grep -qwiF "$1"; then
			echo "${DATE#"${DATE%?}"}"
			return
		fi
		NUM=$((NUM+1))
	done
}

# Find the location of the current script
# Usage: script_path [NAME]
script_path() {
	[ -z "$1" ] && set -- '*.sh'
	local FILE
	# Included in a script
	for FILE in $(find "/proc/$$/fd" -name "1[0-9]" | sort -r); do
		FILE="$(readlink -f -- "$FILE")"
		case "${FILE##*/}" in
			$1)
				printf '%s\n' "$FILE"
				return
			;;
		esac
	done

	# Run directly
	FILE="$(readlink -f -- "$0")"
	case "${FILE##*/}" in
		$1)
			printf '%s\n' "$FILE";
			return
		;;
	esac

	# Last resort, check current directory
	FILE="$(find '.' -name "$1")"
	if [ "$(printf '%s\n' "$FILE" | wc -l)" -eq 1 ]; then
		readlink -f -- "$FILE"
	fi
}

# Read the last x lines of a file and try to determine the blocklist format
# Usage: get_host_format FILE [LINES] [TOLERANCE]
get_host_format() {
	if [ ! -f "$1" ]; then
		echo 'invalid'
		return
	fi
	local FIRST SECOND COUNT_IP=0 COUNT_HOST=0 COUNT_INVALID=0
	while read -r FIRST SECOND _; do
		[ -z "$FIRST" ] && continue
		if [ -n "$SECOND" ]; then
			if is_ipv4 "$FIRST" || is_ipv6 "$FIRST"; then
				if is_domain "$SECOND"; then
					COUNT_IP=$((COUNT_IP + 1))
				else
					COUNT_INVALID=$((COUNT_INVALID + 1))
				fi
			elif is_domain "$FIRST"; then
				COUNT_HOST=$((COUNT_HOST + 1))
			else
				COUNT_INVALID=$((COUNT_INVALID + 1))
			fi
		elif is_domain "$FIRST"; then
			COUNT_HOST=$((COUNT_HOST + 1))
		else
			COUNT_INVALID=$((COUNT_INVALID + 1))
		fi
	done <<- EOF
		$(tail -n "${2:-20}" "$1" | sed "s/#.*$//")
	EOF

	if [ $((100 * COUNT_IP / (COUNT_HOST + COUNT_IP + COUNT_INVALID))) -ge "${3:-90}" ]; then
		echo 'hosts'
	elif [ $((100 * COUNT_HOST / (COUNT_HOST + COUNT_IP + COUNT_INVALID))) -ge "${3:-90}" ]; then
		echo 'domains'
	else
		echo 'invalid'
	fi
}

# Get the integer value of a log priority level
# Usage: log_priority_value LEVEL
log_priority_value() {
	case "$1" in
		'emerg'|'panic') echo 0;;
		'alert') echo 1;;
		'crit') echo 2;;
		'err'|'error') echo 3;;
		'warning'|'warn') echo 4;;
		'notice') echo 5;;
		'info') echo 6;;
		'debug') echo 7;;
	esac
}


###
### Adblock functions
###

# Send message to syslog or terminal if called by a user
# Usage: adblock_log [PRIORITY] MESSAGE
# 	Priorities: debug, info, notice, warning, err, crit, alert, emerg
# Check for user in main script to allow log messages from subshells
[ -t 0 ] && { _CONSOLE_TTY="$(tty)" || unset _CONSOLE_TTY; }
is_cron_child && _FACILITY='cron' || _FACILITY='user'
adblock_log() {
	[ $# -lt 2 ] && set -- 'notice' "$@"
	[ -n "$_CONSOLE_TTY" ] && [ "$(log_priority_value "$1")" -le "$(log_priority_value "$ADBLOCK_LOGLEVEL")" ] && printf '%s\n' "$2" >"$_CONSOLE_TTY"
	logger -t "${ADBLOCK_NAME}[$$]" -p "$_FACILITY.$1" "$2"
}

# Download hostlist files to the download directory if newer
# Usage: adblock_download
adblock_download() {
	adblock_log 'debug' 'Downloading host lists'

	if [ ! -d "$ADBLOCK_HOSTS_DIR" ] && ! mkdir -p "$ADBLOCK_HOSTS_DIR"; then
		adblock_log 'warning' "Unable to create directory ($ADBLOCK_HOSTS_DIR)"
		false; return $?
	fi

	if [ -f "$ADBLOCK_HOSTS_CONF" ]; then
		exec 3<&0 0<"$ADBLOCK_HOSTS_CONF"
	else
		adblock_log 'info' 'Hostlist file missing using defaults'
		exec 3<&0 0<<-EOF
			$ADBLOCK_HOSTS_LIST
		EOF
	fi

	local FILENAME URL DESCR COUNT=0
	while read -r FILENAME URL DESCR; do
		# Comment or blank line
		[ -z "${FILENAME##"#"*}" ] && continue

		if [ -z "${FILENAME##*/*}" ]; then
			adblock_log 'debug' 'No filename listed, generating from URL'
			[ -n "$URL" ] && DESCR="$URL $DESCR"
			URL="$FILENAME"
			FILENAME="$(generate_filename "$URL")$ADBLOCK_HOSTS_EXT"
		fi

		if [ -f "$ADBLOCK_HOSTS_DIR/$FILENAME" ]; then
			adblock_log 'debug' "Checking local file against URL ($URL)"
			local DATE
			DATE="$(get_url_modified "$URL")"
			if [ -z "$DATE" ]; then
				adblock_log 'debug' "Date check failed, checking md5 ($URL)"
				curl -sfL "$URL" -o "$ADBLOCK_HOSTS_DIR/$FILENAME.tmp"
				dos2unix "$ADBLOCK_HOSTS_DIR/$FILENAME.tmp"
				if [ "$(md5sum "$ADBLOCK_HOSTS_DIR/$FILENAME").tmp" = "$(md5sum "$ADBLOCK_HOSTS_DIR/$FILENAME.tmp")" ]; then
					adblock_log 'debug' "MD5 match, file is up to date ($URL)"
					rm -f "$ADBLOCK_HOSTS_DIR/$FILENAME.tmp"
					continue
				else
					adblock_log 'info' "MD5 mismatch, using new version ($URL)"
					mv -f "$ADBLOCK_HOSTS_DIR/$FILENAME.tmp" "$ADBLOCK_HOSTS_DIR/$FILENAME"
				fi
			elif [ "$DATE" -le "$(date -r "$ADBLOCK_HOSTS_DIR/$FILENAME" '+%s')" ]; then
				adblock_log 'debug' "File is up to date ($URL)"
				continue
			else
				adblock_log 'info' "File is outdated, downloading new version ($URL)"
				rm -f "$ADBLOCK_HOSTS_DIR/$FILENAME"
				curl -sfL "$URL" -o "$ADBLOCK_HOSTS_DIR/$FILENAME"
				dos2unix "$ADBLOCK_HOSTS_DIR/$FILENAME"
			fi
		else
			adblock_log 'info' "Downloading new file ($URL)"
			curl -sfL "$URL" -o "$ADBLOCK_HOSTS_DIR/$FILENAME"
			dos2unix "$ADBLOCK_HOSTS_DIR/$FILENAME"
		fi

		COUNT=$((COUNT + 1))
	done
	exec 0<&3 3<&-

	adblock_log 'debug' "Downloading host lists complete ($COUNT updated)"
	[ $COUNT -gt 0 ]; return $?
}

# Reads files from ADBLOCK_HOSTS_DIR and combines them
# Usage: adblock_process
#
# Input files:
#	[IP HOST] [HOST]... [#COMMENT]
adblock_process() {
	adblock_log 'debug' 'Processing hosts files'
	if [ ! -d "$ADBLOCK_DIR" ] && ! mkdir -p "$ADBLOCK_DIR"; then
		adblock_log 'warning' "Unable to create directory ($ADBLOCK_DIR)"
		false; return $?
	fi
	if [ ! -d "$ADBLOCK_HOSTS_DIR" ] || [ -z "$(ls -A "$ADBLOCK_HOSTS_DIR")" ]; then
		adblock_log 'warning' 'No host files to process'
		false; return $?
	fi
	# shellcheck disable=SC2012
	#    only fields before the first filename are used
	if [ -f "$ADBLOCK_DIR/hosts" ] && [ -f "$ADBLOCK_DIR/hosts6" ] && [ "$(date -D '%b %e %H:%M:%S %Y' -d "$(ls -lte "$ADBLOCK_HOSTS_DIR" | awk '{print $7" "$8" "$9" "$10; exit}')" '+%s')" -lt "$(date -r "$ADBLOCK_DIR/hosts" '+%s')" ]; then
		adblock_log 'info' "Host list is up to date"
		false; return $?
	fi

	[ -f "$ADBLOCK_DIR/list.tmp" ] && rm -f "$ADBLOCK_DIR/list.tmp"

	local FILE WHITELIST
	if [ -f "$ADBLOCK_WHITE_FILE" ]; then
		adblock_log 'debug' "Using whitelist ($ADBLOCK_WHITE_FILE)"
		WHITELIST="$ADBLOCK_WHITE_LIST$(echo; sed -nE 's/^[[:space:]]*([^[:space:]#]+)[[:space:]]*(#.*)?$/\1/p' "$ADBLOCK_WHITE_FILE")"
	else
		WHITELIST="$ADBLOCK_WHITE_LIST"
	fi

	for FILE in "$ADBLOCK_HOSTS_DIR"/*; do
		if [ -f "$FILE" ]; then
			adblock_log 'debug' "Determining list format ($FILE)"
			local FIELD_START
			case "$(get_host_format "$FILE")" in
				'domains')
					adblock_log 'info' "Adding entries from domains file ($FILE)"
					FIELD_START=1
				;;
				'hosts')
					adblock_log 'info' "Adding entries from hosts file ($FILE)"
					FIELD_START=2
				;;
				*)
					adblock_log 'info' "Unknown format, skipping file ($FILE)"
					continue
				;;
			esac
			awk -v w="$WHITELIST" '
				BEGIN {
					split(w, t, "\n")
					for(i in t) {
						a[t[i]]
					}
				}
				{
					sub(/#.*$/, "")
					for(i=s; i<=NF; i++) {
						sub(/\.$/, "", $i)
						if(!($i in a) && length($i)<=254 && $i~/'"$FQDN_REGEX"'/) {
							print $i
						}
					}
				}' s=$FIELD_START "$FILE" >> "$ADBLOCK_DIR/list.tmp"
		fi
	done

	if [ ! -s "$ADBLOCK_DIR/list.tmp" ]; then
		adblock_log 'info' 'No hosts found'
	else
		adblock_log 'info' 'Removing duplicates and generating host files'
		sort -u "$ADBLOCK_DIR/list.tmp" | awk '
			{
				if(NR%dpl==0) {
					a=a " " $0
					print ip4 a > hosts
					print ip4 a "\n" ip6 a > hosts6
					a=""
				} else {
					a=a " " $0
				}
			}
			END {
				if(a) {
					print ip4 a > hosts
					print ip4 a "\n" ip6 a > hosts6
				}
			}' dpl="$ADBLOCK_DPL" ip4="$ADBLOCK_IP4" ip6="$ADBLOCK_IP6" hosts="$ADBLOCK_DIR/hosts" hosts6="$ADBLOCK_DIR/hosts6"
	fi

	adblock_log 'debug' 'Removing temp file'
	rm -f "$ADBLOCK_DIR/list.tmp"
	true; return $?
}

# Add user-script entries, and directories
# Usage: adblock_scripts [TOGGLE]
adblock_scripts() {
	if [ "$1" = 'disable' ]; then
		local SCRIPT
		for SCRIPT in post-mount unmount services-start dnsmasq.postconf; do
			if [ -f "/jffs/scripts/$SCRIPT" ]; then
				adblock_log 'debug' "Cleaning up script (/jffs/scripts/$SCRIPT)"
				sed -i "/## $ADBLOCK_NAME ##/d" "/jffs/scripts/$SCRIPT"
				if [ "$(grep -cvE '^[[:space:]]*(#|$)' "/jffs/scripts/$SCRIPT")" -eq 0 ]; then
					rm -f "/jffs/scripts/$SCRIPT"
				fi
			fi
		done
		rm -f "/jffs/scripts/.$ADBLOCK_NAME.event.sh"
	elif [ "$1" = 'enable' ]; then
		if [ ! -d "$ADBLOCK_DIR" ] && ! mkdir -p "$ADBLOCK_DIR"; then
			adblock_log 'warning' "Unable to create directory ($ADBLOCK_DIR)"
			return
		fi
		if [ "$(nvram get jffs2_scripts)" != "1" ] ; then
			nvram set jffs2_scripts=1
			nvram commit
		fi

		adblock_log 'debug' "Generating event script (/jffs/scripts/.$ADBLOCK_NAME.event.sh)"
		local ADBLOCK_ABSDIR ADBLOCK_MOUNT SCRIPT ADBLOCK_ESCNAME
		ADBLOCK_ABSDIR="$(readlink -f -- "$ADBLOCK_DIR")"
		ADBLOCK_MOUNT="$(df -T "$ADBLOCK_DIR" | awk 'NR==2 {print $7}')"
		[ -f "/jffs/scripts/.$ADBLOCK_NAME.event.sh" ] && SCRIPT="$(grep -o '{ crontab.*$' "/jffs/scripts/.$ADBLOCK_NAME.event.sh")"
		[ -z "$SCRIPT" ] && SCRIPT='## cron placeholder ##'
		# There will be written into single quotes so escape them
		ADBLOCK_ABSDIR="${ADBLOCK_ABSDIR//'/'\\''}"
		ADBLOCK_MOUNT="${ADBLOCK_MOUNT//'/'\\''}"
		ADBLOCK_ESCNAME="${ADBLOCK_NAME//'/'\\''}"
		cat > "/jffs/scripts/.$ADBLOCK_NAME.event.sh" << EOF
#!/bin/sh

SCRIPT="\$1"
shift
case "\$SCRIPT" in
	'services-start')
		touch '/tmp/$ADBLOCK_ESCNAME.hosts'
		$SCRIPT
	;;
	'post-mount')
		if [ "\$1" = '$ADBLOCK_MOUNT' ]; then
			HOST_LINK=""
			if [ "\$(nvram get ipv6_service)" != 'disabled' ] && [ -f '$ADBLOCK_ABSDIR/hosts6' ]; then
				HOST_LINK='$ADBLOCK_ABSDIR/hosts6'
			elif [ -f '$ADBLOCK_ABSDIR/hosts' ]; then
				HOST_LINK='$ADBLOCK_ABSDIR/hosts'
			fi
			if [ -n "\$HOST_LINK" ]; then
				read -r UPTIME _ < /proc/uptime
				if [ "\${UPTIME%.*}" -lt 300 ]; then
					(
						sleep 2m
						if [ -f "\$HOST_LINK" ]; then
							logger -t '$ADBLOCK_ESCNAME'"[\$\$]" -p 'user.info' 'Linking hosts and reloading dnsmasq (delayed)'
							rm -f '/tmp/$ADBLOCK_ESCNAME.hosts'
							ln -sf "\$HOST_LINK" '/tmp/$ADBLOCK_ESCNAME.hosts'
							killall -HUP dnsmasq
						fi

					) &
				else
					logger -t '$ADBLOCK_ESCNAME'"[\$\$]" -p 'user.info' 'Linking hosts and reloading dnsmasq'
					rm -f '/tmp/$ADBLOCK_ESCNAME.hosts'
					ln -sf "\$HOST_LINK" '/tmp/$ADBLOCK_ESCNAME.hosts'
					killall -HUP dnsmasq
				fi
			fi
		fi
	;;
	'unmount')
		if [ "\$1" = '$ADBLOCK_MOUNT' ] && [ -L '/tmp/$ADBLOCK_ESCNAME.hosts' ]; then
			logger -t '$ADBLOCK_ESCNAME'"[\$\$]" -p 'user.info' 'Unlinking hosts and reloading dnsmasq'
			rm -f '/tmp/$ADBLOCK_ESCNAME.hosts'
			touch '/tmp/$ADBLOCK_ESCNAME.hosts'
			killall -HUP dnsmasq
		fi
	;;
	'dnsmasq.postconf')
		printf 'ptr-record=0.0.0.0.in-addr.arpa,0.0.0.0\nptr-record=0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa,::\naddn-hosts=/tmp/$ADBLOCK_NAME.hosts\n' >> "\$1"
	;;
	'cron')
		if [ -x '$ADBLOCK_ABSDIR/$ADBLOCK_ESCNAME.sh' ]; then
			'$ADBLOCK_ABSDIR/$ADBLOCK_ESCNAME.sh' update
		fi
	;;
esac
EOF
		chmod +x "/jffs/scripts/.$ADBLOCK_NAME.event.sh"

		for SCRIPT in post-mount unmount services-start dnsmasq.postconf; do
			adblock_log 'debug' "Adding event trigger to script (/jffs/scripts/$SCRIPT)"
			if [ ! -f "/jffs/scripts/$SCRIPT" ]; then
				printf '#!/bin/sh\n\n. '\''/jffs/scripts/.%s.event.sh'\'' %s "$@" ## %s ##\n' "$ADBLOCK_ESCNAME" "$SCRIPT" "$ADBLOCK_NAME" > "/jffs/scripts/$SCRIPT"
				chmod +x "/jffs/scripts/$SCRIPT"
			elif ! grep -Fq "## $ADBLOCK_NAME ##" "/jffs/scripts/$SCRIPT"; then
				printf '. '\''/jffs/scripts/.%s.event.sh'\'' %s "$@" ## %s ##\n' "$ADBLOCK_ESCNAME" "$SCRIPT" "$ADBLOCK_NAME" >> "/jffs/scripts/$SCRIPT"
			fi
		done
	elif [ "$1" = 'cron' ] && [ ! -f "/jffs/scripts/.$ADBLOCK_NAME.event.sh" ]; then
		local ADBLOCK_ABSDIR ADBLOCK_ESCNAME
		ADBLOCK_ABSDIR="$(readlink -f -- "$ADBLOCK_DIR")"
		# There will be written into single quotes so escape them
		ADBLOCK_ABSDIR="${ADBLOCK_ABSDIR//'/'\\''}"
		ADBLOCK_ESCNAME="${ADBLOCK_NAME//'/'\\''}"
		cat > "/jffs/scripts/.$ADBLOCK_NAME.event.sh" << EOF
#!/bin/sh

SCRIPT="\$1"
shift
case "\$SCRIPT" in
	'services-start')
		## cron placeholder ##
	;;
	'cron')
		if [ -x '$ADBLOCK_ABSDIR/$ADBLOCK_ESCNAME.sh' ]; then
			'$ADBLOCK_ABSDIR/$ADBLOCK_ESCNAME.sh' update
		fi
	;;
esac
EOF
		chmod +x "/jffs/scripts/.$ADBLOCK_NAME.event.sh"

		adblock_log 'debug' "Adding event trigger to script (/jffs/scripts/services-start)"
		if [ ! -f '/jffs/scripts/services-start' ]; then
			printf '#!/bin/sh\n\n. '\''/jffs/scripts/.%s.event.sh'\'' services-start "$@" ## %s ##\n' "$ADBLOCK_ESCNAME" "$ADBLOCK_NAME" > '/jffs/scripts/services-start'
			chmod +x '/jffs/scripts/services-start'
		elif ! grep -Fq "## $ADBLOCK_NAME ##" '/jffs/scripts/services-start'; then
			printf '. '\''/jffs/scripts/.%s.event.sh'\'' services-start "$@" ## %s ##\n' "$ADBLOCK_ESCNAME" "$ADBLOCK_NAME" >> '/jffs/scripts/services-start'
		fi
	fi
}

# Enable/disable automatic host updating
# Usage: adblock_cron disable|[[HOUR|#[:MINUTE|#] [am|pm]] [daily|weekly|WEEKDAY]]
adblock_cron() {
	if [ $# -eq 0 ] || [ -z "${*// /}" ]; then
		return
	fi

	if [ "$1" = 'disable' ]; then
		adblock_log 'debug' 'Disabling adblock cron job'
		if [ -f "/jffs/scripts/.$ADBLOCK_NAME.event.sh" ]; then
			sed -i 's/{ crontab.*$/## cron placeholder ##/' "/jffs/scripts/.$ADBLOCK_NAME.event.sh"
		fi
		crontab -l | grep -v "#$ADBLOCK_NAME update#$" | crontab -
		return
	fi

	# Try to figure out what time to do this
	local NOGLOB ARG AMPM MINUTE='#' HOUR=0 DAY='*'
	if [ -z "$-" ] || [ -n "${-##*f*}" ]; then
		NOGLOB='yes'
		set -f
	fi
	# shellcheck disable=SC2048
	for ARG in $*; do
		case "$ARG" in
			[0-9]*)
				if [ "$ARG" != "${ARG%[aApP][mM]}" ]; then
					if [ "$ARG" != "${ARG%[pP]?}" ]; then
						AMPM=12
					else
						AMPM=0
					fi
					ARG="${ARG%??}"
				fi
				if [ -z "${ARG##*:*}" ]; then
					HOUR="$(printf '%s\n' "${ARG%:*}" | sed 's/^0*\([0-9]\)/\1/')"
					MINUTE="$(printf '%s\n' "${ARG#*:}" | sed 's/^0*\([0-9]\)/\1/')"
				else
					HOUR="$(printf '%s\n' "$ARG" | sed 's/^0*\([0-9]\)/\1/')"
					MINUTE=0
				fi
			;;
			[aA][mM]) AMPM=0;;
			[pP][mM]) AMPM=12;;
			'daily') DAY='*';;
			'weekly') DAY="$(awk -v min=0 -v max=6 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')";;
			*) DAY="$(weekday_to_num "$ARG")";;
		esac
	done
	[ "$NOGLOB" = 'yes' ] && set +f

	# Check for randomness
	if [ "$MINUTE" = '##' ] || [ "$MINUTE" = '#' ]; then
		MINUTE="$(awk -v min=0 -v max=59 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')"
	elif [ "$MINUTE" = "${MINUTE%?}#" ]; then
		if [ "${MINUTE%?}" = '0' ]; then
			MINUTE="$(awk -v min=0 -v max=9 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')"
		else
			MINUTE="${MINUTE%?}$(awk -v min=0 -v max=9 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')"
		fi
	fi
	if [ "$HOUR" = '##' ] || [ "$HOUR" = '#' ]; then
		if [ -n "$AMPM" ]; then
			HOUR="$(awk -v min=0 -v max=11 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')"
		else
			HOUR="$(awk -v min=0 -v max=23 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')"
		fi
	fi

	# 12pm is 0am the next day
	if [ "$AMPM" = '12' ]; then
		HOUR=$((HOUR+AMPM))
		if [ $HOUR -eq 24 ]; then
			HOUR=0
			if [ -n "$DAY" ] && [ "$DAY" != '*' ]; then
				DAY=$((DAY+1))
				[ "$DAY" -eq 7 ] && DAY=0
			fi
		fi
	fi

	# Check valid settings
	if ! is_number_ordered 0 "$HOUR" 23 || ! is_number_ordered 0 "$MINUTE" 59 || [ -z "$DAY" ]; then
		adblock_log 'warning' 'Invalid cron settings'
		return
	fi

	# copy ourselves to the adblock dir
	if [ ! -f "$ADBLOCK_DIR/$ADBLOCK_NAME.sh" ]; then
		local MYSCRIPT AWKSCRIPT
		if [ -f "/tmp/.script$$" ] && [ "$(awk 'NR==2{print; exit}' "/tmp/.script$$")" = '### Load config settings' ]; then
			MYSCRIPT="/tmp/.script$$"
			AWKSCRIPT='1'
		else
			MYSCRIPT="$(script_path "$ADBLOCK_NAME.sh")"
			# shellcheck disable=SC2016
			AWKSCRIPT='{if(!f&&/^### Load config settings$/){print p;f=1}else{p=$0}}f'
		fi
		if [ -z "$MYSCRIPT" ] || ! mkdir -p "$ADBLOCK_DIR" || ! { cat; awk "$AWKSCRIPT" "$MYSCRIPT"; } >"$ADBLOCK_DIR/$ADBLOCK_NAME.sh"; then
			adblock_log 'warning' "Unable to copy $ADBLOCK_NAME.sh to $ADBLOCK_DIR"
			return
		fi <<- EOF
			#!/bin/sh

			###
			### Default values
			###

			DEFAULT_NAME='$(printf '%s\n' "$ADBLOCK_NAME" | sed "s/'/'\\\\''/g")'
			DEFAULT_DIR='$(printf '%s\n' "$ADBLOCK_DIR" | sed "s/'/'\\\\''/g")'
			DEFAULT_HOSTS_CONF='$(printf '%s\n' "$ADBLOCK_HOSTS_CONF" | sed "s/'/'\\\\''/g")'
			DEFAULT_HOSTS_DIR='$(printf '%s\n' "$ADBLOCK_HOSTS_DIR" | sed "s/'/'\\\\''/g")'
			DEFAULT_HOSTS_EXT='$(printf '%s\n' "$ADBLOCK_HOSTS_EXT" | sed "s/'/'\\\\''/g")'
			DEFAULT_HOSTS_LIST='$(printf '%s\n' "$ADBLOCK_HOSTS_LIST" | sed "s/'/'\\\\''/g")'
			DEFAULT_WHITE_FILE='$(printf '%s\n' "$ADBLOCK_WHITE_FILE" | sed "s/'/'\\\\''/g")'
			DEFAULT_WHITE_LIST='$(printf '%s\n' "$ADBLOCK_WHITE_LIST" | sed "s/'/'\\\\''/g")'
			DEFAULT_IP4='$(printf '%s\n' "$ADBLOCK_IP4" | sed "s/'/'\\\\''/g")'
			DEFAULT_IP6='$(printf '%s\n' "$ADBLOCK_IP6" | sed "s/'/'\\\\''/g")'
			DEFAULT_DPL='$(printf '%s\n' "$ADBLOCK_DPL" | sed "s/'/'\\\\''/g")'
			DEFAULT_CRON='$(printf '%s\n' "$ADBLOCK_CRON" | sed "s/'/'\\\\''/g")'
			DEFAULT_LOGLEVEL='$(printf '%s\n' "$ADBLOCK_LOGLEVEL" | sed "s/'/'\\\\''/g")'


		EOF
		chmod +x "$ADBLOCK_DIR/$ADBLOCK_NAME.sh"
	fi

	adblock_log 'info' 'Adding cron job'
	local LINE
	LINE="$MINUTE $HOUR * * $DAY '/jffs/scripts/.${ADBLOCK_NAME//'/'\\''}.event.sh' cron"
	if [ ! -f "/jffs/scripts/.$ADBLOCK_NAME.event.sh" ]; then
		adblock_scripts 'cron'
	fi

	sed -i "s/## cron placeholder ##\|{ crontab.*$/$(sed_quote "{ crontab -l | grep -v '#${ADBLOCK_NAME//'/'\\''} update#$' ; echo '${LINE//'/'\\''} #${ADBLOCK_NAME//'/'\\''} update#'; } | crontab -")/" "/jffs/scripts/.$ADBLOCK_NAME.event.sh"
	{ crontab -l | grep -v "#$ADBLOCK_NAME update#$" ; echo "$LINE #$ADBLOCK_NAME update#"; } | crontab -
}

# Toggle the use of the hosts file in dnsmasq
# Usage: adblock_toggle [ACTION]
adblock_toggle() {
	if [ "$1" = 'disable' ]; then
		adblock_log 'debug' 'Disabling adblocking'
		if [ -L "/tmp/$ADBLOCK_NAME.hosts" ]; then
			rm -f "/tmp/$ADBLOCK_NAME.hosts"
			touch "/tmp/$ADBLOCK_NAME.hosts"
			if grep -Fq "addn-hosts=/tmp/$ADBLOCK_NAME.hosts" '/etc/dnsmasq.conf'; then
				adblock_log 'info' 'Reloading dnsmasq'
				killall -HUP dnsmasq
			fi
		fi
	elif [ "$1" = 'enable' ]; then
		adblock_log 'debug' 'Enabling adblocking'
		local HOST_LINK
		if [ "$(nvram get ipv6_service)" != 'disabled' ] && [ -f "$ADBLOCK_DIR/hosts6" ]; then
			HOST_LINK="$(readlink -f -- "$ADBLOCK_DIR/hosts6")"
		elif [ -f "$ADBLOCK_DIR/hosts" ]; then
			HOST_LINK="$(readlink -f -- "$ADBLOCK_DIR/hosts")"
		fi

		if [ -f "$HOST_LINK" ] && { [ ! -L "/tmp/$ADBLOCK_NAME.hosts" ] || [ "$(readlink -f -- "/tmp/$ADBLOCK_NAME.hosts")" != "$HOST_LINK" ]; }; then
			adblock_log 'debug' "Linking to host file ($HOST_LINK)"
			rm -f "/tmp/$ADBLOCK_NAME.hosts"
			ln -sf "$HOST_LINK" "/tmp/$ADBLOCK_NAME.hosts"

			if ! grep -Fq "addn-hosts=/tmp/$ADBLOCK_NAME.hosts" '/etc/dnsmasq.conf'; then
				adblock_log 'info' 'Restarting dnsmasq'
				service restart_dnsmasq >/dev/null
			else
				adblock_log 'info' 'Reloading dnsmasq'
				killall -HUP dnsmasq
			fi
		fi
	elif [ "$1" = 'reload' ]; then
		if grep -Fq "addn-hosts=/tmp/$ADBLOCK_NAME.hosts" '/etc/dnsmasq.conf' && [ -L "/tmp/$ADBLOCK_NAME.hosts" ]; then
			adblock_log 'info' 'Reloading dnsmasq'
			killall -HUP dnsmasq
		fi
	fi
}


###
### Adblock program
###

case "$1" in
	'install')
		adblock_log 'Installing dnsmasq adblocking'
		adblock_download
		adblock_process
		adblock_scripts 'enable'
		adblock_toggle 'enable'
		adblock_cron "$ADBLOCK_CRON"
	;;
	'uninstall')
		adblock_log 'Uninstalling dnsmasq adblocking'
		adblock_scripts 'disable'
		adblock_toggle 'disable'
		adblock_cron 'disable'
	;;
	'enable')
		adblock_log 'Enabling dnsmasq adblocking'
		adblock_toggle 'enable'
	;;
	'disable')
		adblock_log 'Disabling dnsmasq adblocking'
		adblock_toggle 'disable'
	;;
	'update')
		adblock_log 'Updating dnsmasq adblocking'
		adblock_download
		if adblock_process; then
			adblock_toggle 'reload'
		fi
	;;
esac

#ENDSCRIPT
