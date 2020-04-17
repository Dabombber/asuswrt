#!/bin/sh

logng_scripts() {
	if [ "$1" = 'disable' ]; then
		local SCRIPT
		for SCRIPT in init-start service-event; do
			if [ -f "/jffs/scripts/$SCRIPT" ]; then
				# Remove logng line
				sed -i "/## logng ##/d" "/jffs/scripts/$SCRIPT"
				# Remove scripts which do nothing
				[ "$(grep -csvE '^[[:space:]]*(#|$)' "/jffs/scripts/$SCRIPT")" = '0' ] && rm -f "/jffs/scripts/$SCRIPT"
			fi
		done
		# Remove event script
		rm -f /jffs/scripts/.logng.event.sh
	elif [ "$1" = 'enable' ]; then
		# Check userscripts are enabled
		if [ "$(nvram get jffs2_scripts)" != "1" ] ; then
			nvram set jffs2_scripts=1
			nvram commit
		fi

		cat > /jffs/scripts/.logng.event.sh <<'EOF'
#!/bin/sh

# Placeholder text for stock syslog rotation
readonly SYSLOG_HEADER='### Top of Log File ###'

# Fix syslog timestamps from boot until ntp sync
# Usage: fixtime
fixtime() {
	# Run once
	[ ! -f /tmp/.fixtime ] && return
	local INIT_UPTIME INIT_EPOCH CURRENT_UPTIME CURRENT_EPOCH OFFSET
	read -r INIT_UPTIME INIT_EPOCH < /tmp/.fixtime
	rm /tmp/.fixtime

	# Already been processed by syslog-ng, this shouldn't happen
	if [ -L /tmp/syslog.log ] || [ ! -f /tmp/syslog.log ]; then
		return
	fi

	# Time offset in seconds for pre-ntp'ed log entries = current_epoch - (init_epoch + (current_uptime - init_uptime))
	CURRENT_UPTIME="$(awk -F. '{print $1}' < /proc/uptime)"
	CURRENT_EPOCH="$(date '+%s')"
	OFFSET=$((CURRENT_EPOCH - INIT_EPOCH - CURRENT_UPTIME + INIT_UPTIME))

	# Chopshop busybox
	if ! type tac &>/dev/null; then
		tac() {
			awk '{print NR" "$0}' -- "$@" | sort -k1 -n -r | sed 's/^[^ ]* //g'
		}
	fi

	# Reverse the file so we only apply changes to the latest boot
	if [ -f /tmp/syslog.log-1 ]; then
		tac /tmp/syslog.log-1 /tmp/syslog.log > /tmp/revlog.tmp
	else
		tac /tmp/syslog.log > /tmp/revlog.tmp
	fi

	# Process lines between ntpd-sync and klogd-start
	local LINE LINE_EPOCH STAGE='start'
	while read -r LINE; do
		[ -z "$LINE" ] && continue
		if [ "$STAGE" = 'start' ]; then
			if [ -z "${LINE##*"ntpd: Initial clock set"}" ]; then
				STAGE='middle'
			fi
		elif [ "$STAGE" = 'middle' ]; then
			if [ -z "${LINE##*"klogd started: BusyBox"*}" ]; then
				STAGE='end'
			fi
			LINE_EPOCH="$(date -D '%b %e %T' -d "${LINE:0:15}" '+%s')"
			LINE="$(date -d "@$((LINE_EPOCH + OFFSET))" '+%b %e %H:%M:%S')${LINE:15}"
		fi
		printf '%s\n' "$LINE" >> /tmp/fixlog.tmp
	done < /tmp/revlog.tmp

	# Only append changes if processed properly
	if [ "$STAGE" = 'end' ]; then
		tac /tmp/fixlog.tmp > /tmp/syslog.log
		rm -f /tmp/syslog.log-1
	fi
	rm -f /tmp/revlog.tmp /tmp/fixlog.tmp
}

web_mount() {
	# Modified weblog file location
	readonly SYSLOG_WWW='/jffs/www/Main_LogStatus_Content.asp'

	# Remove any stale file
	local TIMESTAMP
	TIMESTAMP="$(date -r '/www/require/')" # Use a folder date since asp will be modified
	if [ -f "$SYSLOG_WWW" ]; then
		if ! grep -Fq "$TIMESTAMP" "$SYSLOG_WWW"; then
			mount | grep -Fq '/www/Main_LogStatus_Content.asp' && umount '/www/Main_LogStatus_Content.asp'
			rm "$SYSLOG_WWW"
		else
			# Up to date, nothing to do here
			unset TIMESTAMP
		fi
	fi

	# Make new file
	if [ -n "$TIMESTAMP" ]; then
		mkdir -p "$(dirname "$SYSLOG_WWW")"
		cp '/www/Main_LogStatus_Content.asp' "$SYSLOG_WWW"

		# Include our js file
		sed -i -e '/src="\/js\/jquery\.js"/a\' -e '<script language="JavaScript" type="text\/javascript" src="\/user\/loggyparser\.js"><\/script>' "$SYSLOG_WWW"

		# Peform an update on page load
		sed -i '/\/\/make Scroll_y bottom/{n;s/5000/0/}' "$SYSLOG_WWW"

		# read syslog in /www/user/
		sed -i "s/url: '\/ajax_log_data\.asp'/url: '\/user\/syslog\.html'/" "$SYSLOG_WWW"
		sed -i "s/dataType: 'script'/dataType: 'text'/" "$SYSLOG_WWW"

		# Process log
		sed -i -e '/innerHTML = logString/c\' -e 'append_to_log(response, "<% nvram_get("log_level"); %>");' "$SYSLOG_WWW"

		# Remove initial nvram dump
		sed -i 's/<% nvram_dump("syslog.log",""); %>//' "$SYSLOG_WWW"

		# Add source file timestamp
		printf "%s\n" "<!-- Source timestamp: $TIMESTAMP -->" >> "$SYSLOG_WWW"
	fi

	# Mount over stock file
	if ! mount | grep -Fq '/www/Main_LogStatus_Content.asp'; then
		mount -o bind "$SYSLOG_WWW" '/www/Main_LogStatus_Content.asp'
	fi

	# Make the logs readable from www
	[ ! -L /www/user/syslog.html ] && ln -s /tmp/syslog.log /www/user/syslog.html
	# Link to our javascript
	[ ! -L /www/user/loggyparser.js ] && ln -s /jffs/www/loggyparser.js /www/user/loggyparser.js
}

# Wait for a process to spawn then kill it
# Usage: waitkill PROCESSNAME
waitkill() {
	local COUNT=20
	while [ $COUNT -gt 0 ]; do
		sleep 1
		if pidof "$1" &>/dev/null; then
			killall "$1"
			true; return $?
		fi
		COUNT=$((COUNT-1))
	done
	false; return $?
}

# Kill the stock syslog in preperation for syslog-ng
# Usage: pre_syslog
pre_syslog() {
	# Do nothing if it's not going to be started
	[ "$ENABLED" != 'yes' ] && return

	# kill any/all running klogd and/or syslogd
	pidof klogd &>/dev/null && killall klogd
	pidof syslogd &>/dev/null && killall syslogd

	# While nothing is logging lets see if we can fix the timestamps
	[ "$(nvram get ntp_ready)" = '1' ] && fixtime

	# Append stock logs
	if [ ! -L /tmp/syslog.log ]; then
		if [ -s /tmp/syslog.log-1 ] && ! printf '%s\n' "$SYSLOG_HEADER" | cmp -s /tmp/syslog_log-1; then
			cat /tmp/syslog.log-1 /tmp/syslog.log >> /opt/var/log/messages
		else
			cat /tmp/syslog.log >> /opt/var/log/messages
		fi
		rm -f /tmp/syslog.log
		ln -s /opt/var/log/messages /tmp/syslog.log
		printf '%s\n' "$SYSLOG_HEADER" > /tmp/syslog.log-1
	fi

	# make /jffs/syslog.log and log-1 directories if not already
	# prevents system log saver from writing to jffs
	[ ! -d '/jffs/syslog.log' ] && rm -f '/jffs/syslog.log' && mkdir '/jffs/syslog.log'
	[ ! -d '/jffs/syslog.log-1' ] && rm -f '/jffs/syslog.log-1' && mkdir '/jffs/syslog.log-1'

	# set logrotate to... rotate
	{ crontab -l 2>/dev/null | grep -v '#logrotate#$'; echo '5 0 * * * /opt/sbin/logrotate /opt/etc/logrotate.conf >> /opt/tmp/logrotate.daily 2>&1 #logrotate#'; } | crontab -
}

# Start the stock syslog after terminating syslog-ng
# Usage: post_syslog
post_syslog() {
	# Remove symlinks and blocking folders
	[ -L /tmp/syslog.log ] && rm -f /tmp/syslog.log
	printf '%s\n' "$SYSLOG_HEADER" | cmp -s /tmp/syslog_log-1 && rm -f /tmp/syslog_log-1
	[ -d /jffs/syslog.log ] && rm -rf /jffs/syslog.log
	[ -d /jffs/syslog.log-1 ] && rm -rf /jffs/syslog.log-1

	# remove logrotate cronjob
	crontab -l 2>/dev/null | grep -v "#logrotate#$" | crontab -

	# Start the built in logger
	/sbin/service start_logger
}


EVENT="$1"
shift
case "$EVENT" in
	'init-start')
		printf '%s %s\n' "$(awk -F. '{print $1}' < /proc/uptime)" "$(date '+%s')" > /tmp/.fixtime
		web_mount
	;;
	'service-event')
		if [ "$1_$2" = 'restart_diskmon' ]; then
			if [ "$(nvram get ntp_ready)" = '1' ] && [ -f /tmp/.ntpwait-syslogng ]; then
				rm /tmp/.ntpwait-syslogng
				[ -x /opt/etc/init.d/S01syslog-ng ] && /opt/etc/init.d/S01syslog-ng start
			fi
		elif [ "$1" != 'stop' ] && { [ "$2" = 'logger' ] || [ "$2" = 'time' ]; } && pidof syslog-ng &>/dev/null; then
			waitkill 'klogd' &
			waitkill 'syslogd' &
		fi
	;;
	'rc.func')
		# Unset procs to include rc.func without doing anything
		PROCS=""
		. /opt/etc/init.d/rc.func
		PROC='syslog-ng'

		# Don't run until time is set
		if [ "$(nvram get ntp_ready)" != '1' ]; then
			touch /tmp/.ntpwait-syslogng
			ENABLED='no'
		fi

		case "$1" in
			'start')
				pre_syslog
				start
			;;
			'stop'|'kill')
				check && stop && post_syslog
			;;
			'restart')
				if check >/dev/null; then
					stop
				else
					pre_syslog
				fi
				start
			;;
			'check')
				check
			;;
			'reconfigure')
				reconfigure
			;;
			*)
				printf '\033[1;37m Usage: %s (start|stop|restart|check|kill|reconfigure)\033[m\n' "$0" >&2
			;;
		esac
	;;
esac
EOF

		chmod +x /jffs/scripts/.logng.event.sh

		# Add event triggers
		local SCRIPT
		for SCRIPT in init-start service-event; do
			if [ ! -f "/jffs/scripts/$SCRIPT" ]; then
				printf '#!/bin/sh\n\n. /jffs/scripts/.logng.event.sh %s "$@" ## logng ##\n' "$SCRIPT" > "/jffs/scripts/$SCRIPT"
				chmod +x "/jffs/scripts/$SCRIPT"
			elif ! grep -qF '## logng ##' "/jffs/scripts/$SCRIPT"; then
				printf '. /jffs/scripts/.logng.event.sh %s "$@" ## logng ##\n' "$SCRIPT" >> "/jffs/scripts/$SCRIPT"
			fi
		done
	fi
}

case "$1" in
	'install')
		if [ -x /opt/bin/opkg ]; then
			# Install syslog-ng if needed
			if [ ! -x /opt/sbin/syslog-ng ]; then
				/opt/bin/opkg install syslog-ng
			fi
			# Use custom syslog-ng rc.init
			sed -i 's/^\. \/opt\/etc\/init.d\/rc\.func$/\. \/jffs\/scripts\/\.logng\.event\.sh rc\.func "\$@" ## logng ##/' /opt/etc/init.d/S01syslog-ng

			# Add userscript additions
			logng_scripts 'enable'

			# Customise webUI log page
			mkdir -p /jffs/www/
			cat > /jffs/www/loggyparser.js <<-'EOF'
var FacilityIndex=['kern','user','mail','daemon','auth','syslog','lpr','news','uucp','cron','authpriv','ftp','ntp','security','console','solaris-cron','local0','local1','local2','local3','local4','local5','local6','local7'];var SeverityIndex=['emerg','alert','crit','err','warning','notice','info','debug'];var BSDDateIndex={'Jan':0,'Feb':1,'Mar':2,'Apr':3,'May':4,'Jun':5,'Jul':6,'Aug':7,'Sep':8,'Oct':9,'Nov':10,'Dec':11};var LoggyParser=function(){};LoggyParser.prototype.parse=function(rawMessage,callback){if(typeof rawMessage!='string'){return rawMessage}
var parsedMessage={originalMessage:rawMessage};var rightMessage=rawMessage;var segment=rightMessage.match(/^<(\d+)>\s*/);if(segment){parsedMessage.facilityID=segment[1]>>>3;parsedMessage.severityID=segment[1]&0b111;if(parsedMessage.facilityID<24&&parsedMessage.severityID<8){parsedMessage.facility=FacilityIndex[parsedMessage.facilityID];parsedMessage.severity=SeverityIndex[parsedMessage.severityID]}
rightMessage=rightMessage.substring(segment[0].length)}
segment=rightMessage.match(/^(\d{4}\s+)?(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+/);if(segment){parsedMessage.time=new Date(segment[1]||(new Date()).getUTCFullYear(),BSDDateIndex[segment[2]],segment[3],segment[4],segment[5],segment[6]);rightMessage=rightMessage.substring(segment[0].length)}else{segment=rightMessage.match(/^([^\s]+)\s+/);if(segment){parsedMessage.time=this.parse8601(segment[1])||this.parseRfc3339(segment[1]);if(parsedMessage.time){rightMessage=rightMessage.substring(segment[0].length)}}}
segment=rightMessage.match(/^(?:([^\s]+(?:[^\s:]|::))\s+)?([^\s]+)(?:\[(\d+)\])?:\s+/);if(segment){parsedMessage.host=segment[1];parsedMessage.program=segment[2];parsedMessage.pid=segment[3];rightMessage=rightMessage.substring(segment[0].length)}
if(parsedMessage.pid){parsedMessage.header=parsedMessage.program+"["+parsedMessage.pid+"]: "}else if(parsedMessage.program){parsedMessage.header=parsedMessage.program+": "}else{parsedMessage.header=""}
parsedMessage.message=rightMessage;if(callback){callback(parsedMessage)}else{return parsedMessage}};LoggyParser.prototype.parseRfc3339=function(timeStamp){var utcOffset,offsetSplitChar,offsetString,offsetMultiplier=1,dateTime=timeStamp.split("T");if(dateTime.length<2)return!1;var date=dateTime[0].split("-"),time=dateTime[1].split(":"),offsetField=time[time.length-1];offsetFieldIdentifier=offsetField.charAt(offsetField.length-1);if(offsetFieldIdentifier==="Z"){utcOffset=0;time[time.length-1]=offsetField.substr(0,offsetField.length-2)}else{if(offsetField[offsetField.length-1].indexOf("+")!=-1){offsetSplitChar="+";offsetMultiplier=1}else{offsetSplitChar="-";offsetMultiplier=-1}
offsetString=offsetField.split(offsetSplitChar);if(offsetString.length<2)return!1;time[(time.length-1)]=offsetString[0];offsetString=offsetString[1].split(":");utcOffset=(offsetString[0]*60)+offsetString[1];utcOffset=utcOffset*60*1000}
var parsedTime=new Date(Date.UTC(date[0],date[1]-1,date[2],time[0],time[1],time[2])+(utcOffset*offsetMultiplier));return parsedTime};LoggyParser.prototype.parse8601=function(timeStamp){var parsedTime=new Date(Date.parse(timeStamp));if(parsedTime instanceof Date&&!isNaN(parsedTime))return parsedTime;return!1};Date.prototype.to8601String=function(){return this.getFullYear()+'-'+(this.getMonth()+1).toString().padStart(2,'0')+'-'+this.getDate().toString().padStart(2,'0')+' '+this.getHours().toString().padStart(2,'0')+':'+this.getMinutes().toString().padStart(2,'0')+':'+this.getSeconds().toString().padStart(2,'0')};String.prototype.lastIndexEnd=function(string){var io=this.lastIndexOf(string)
return(string.length==0||io==-1)?-1:io+string.length};var lastLine="";var syslogParser=new LoggyParser();function append_to_log(lines,log_level){lines.substring(lines.lastIndexEnd(lastLine)).split("\n").filter(i=>i).forEach(line=>syslogParser.parse(line,(msg)=>{lastLine="\n"+msg.originalMessage+"\n";if(msg.severityID==null||msg.severityID<log_level){document.getElementById("textarea").innerHTML+=msg.time.to8601String()+" "+msg.header+msg.message+"\n"}}))}
EOF
			(. /jffs/scripts/.logng.event.sh; web_mount)
		else
			echo 'Entware needs to be installed' >&2
		fi
	;;
	'uninstall')
		# Restore syslog-ng
		if [ -x /opt/etc/init.d/S01syslog-ng ]; then
			pidof syslog-ng &>/dev/null && /opt/etc/init.d/S01syslog-ng stop
			sed -i 's/## logng ##$/\. \/opt\/etc\/init.d\/rc\.func/' /opt/etc/init.d/S01syslog-ng
		fi

		# Disable userscript additions
		logng_scripts 'disable'

		# Remove webUI changes
		mount | grep -Fq '/www/Main_LogStatus_Content.asp' && umount '/www/Main_LogStatus_Content.asp'
		rm -f '/jffs/www/loggyparser.js' '/www/loggyparser.js' '/jffs/www/Main_LogStatus_Content.asp'
	;;
esac