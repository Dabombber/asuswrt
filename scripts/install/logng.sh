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
	if [ ! -f /tmp/.time-init ] || [ ! -f /tmp/.time-sync ]; then
		return
	fi
	local INIT_UPTIME INIT_EPOCH CURRENT_UPTIME CURRENT_EPOCH SYNC_EPOCH OFFSET
	read -r INIT_UPTIME INIT_EPOCH < /tmp/.time-init
	read -r _ SYNC_EPOCH < /tmp/.time-sync
	rm /tmp/.time-init

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
	local LINE LINE_EPOCH STAGE='searching'
	while read -r LINE; do
		[ -z "$LINE" ] && continue
		if [ "$STAGE" = 'searching' ]; then
			# Make sure it's this boot, 5s is pretty generous (ntp-sync log message ± service-event)
			if [ "${LINE:16}" = 'ntpd: Initial clock set' ] && LINE_EPOCH=$((SYNC_EPOCH - $(date -D '%b %e %T' -d "${LINE:0:15}" '+%s'))) 2>/dev/null && [ ${LINE_EPOCH#-} -le 5 ]; then
				STAGE='processing'
			fi
		elif [ "$STAGE" = 'processing' ]; then
			if [ "${LINE:16:30}" = 'kernel: klogd started: BusyBox' ]; then
				STAGE='processed'
			elif [ "${LINE:16}" = 'ntpd: Initial clock set' ]; then
				# Went past klogd start somehow
				STAGE='error'
				break
			fi
			if LINE_EPOCH="$(date -D '%b %e %T' -d "${LINE:0:15}" '+%s')"; then
				LINE="$(date -d "@$((LINE_EPOCH + OFFSET))" '+%b %e %H:%M:%S')${LINE:15}"
			else
				STAGE='error'
				break
			fi
		fi
		printf '%s\n' "$LINE" >> /tmp/fixlog.tmp
	done < /tmp/revlog.tmp

	# Only apply changes if processed properly
	if [ "$STAGE" = 'processed' ]; then
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
	elif mount | grep -Fq '/www/Main_LogStatus_Content.asp'; then
		umount '/www/Main_LogStatus_Content.asp'
	fi

	# Make new file
	if [ -n "$TIMESTAMP" ]; then
		mkdir -p "$(dirname "$SYSLOG_WWW")"
		cp '/www/Main_LogStatus_Content.asp' "$SYSLOG_WWW"

		escape() { printf '%s\n' "$1" | sed '/^[[:space:]]*$/d' | sed -e 's/[]\/$*.^&[]/\\&/g' -e '$!s/$/\\n/' | tr -d '\t\n'; }
		local REPLACEMENT

		# Include our files
		REPLACEMENT="$(escape '
			<link rel="stylesheet" type="text/css" href="/user/logng_style.css">
			<script language="JavaScript" type="text/javascript" src="/user/logng.js"></script>
		')"
		sed -i -e '/form_style\.css/a\' -e "$REPLACEMENT" "$SYSLOG_WWW"

		# # Peform an update on page load
		REPLACEMENT="$(escape 'setTimeout("get_log_data();", 0);')"
		sed -i -e '/scrollTop = 9999999/{N;c\' -e "$REPLACEMENT" -e '}' "$SYSLOG_WWW"

		# Read syslog as text instead of script
		sed -i -e '/dataType:/c\' -e "dataType: 'text'," "$SYSLOG_WWW"

		# Some IE thing which most likely doesn't even work
		sed -i 's/getElementById("textarea")\.style/getElementById("syslogContainer")\.style/' "$SYSLOG_WWW"

		# Replace success function
		sed -i '/var h = 0;/d' "$SYSLOG_WWW"
		sed -i 's/var height = 0;/var autoscroll = true;/' "$SYSLOG_WWW"
		REPLACEMENT="$(escape '
			if(document.getElementById("auto_refresh").checked) {
				let el = document.getElementById("syslogContainer");
				if(el.scrollHeight - el.scrollTop - el.clientHeight <= 1) {
					autoscroll = true;
				}
				if(processLogFile(response.slice(30,-30)) > 0 && autoscroll) {
					$(el).animate({ scrollTop: el.scrollHeight - el.clientHeight }, "slow");
				}
				autoscroll = false;
			}
		')"
		sed -i -e'/function(response){/{n;N;N;N;N;N;c\' -e "$REPLACEMENT" -e '}' "$SYSLOG_WWW"

		# Add checkboxes for togglable columns and severity selector
		REPLACEMENT="$(escape '
			<div id="syslogControls">
				<div><input type="checkbox" checked id="auto_refresh"><label for="auto_refresh">Auto refresh</label></div>
				<div><input type="checkbox" id="facility" onchange="toggleColumn(this.id, this.checked);"><label for="facility">Facility</label></div>
				<div><input type="checkbox" id="hostname" onchange="toggleColumn(this.id, this.checked);"><label for="hostname">Hostname</label></div>
				<div>
				<select id="severity" class="input_option" onchange="applyFilter(this.value)">
					<option value="emerg" <% nvram_match("log_level", "1", "selected"); %>>emergency</option>
					<option value="alert" <% nvram_match("log_level", "2", "selected"); %>>alert</option>
					<option value="crit" <% nvram_match("log_level", "3", "selected"); %>>critical</option>
					<option value="err" <% nvram_match("log_level", "4", "selected"); %>>error</option>
					<option value="warning" <% nvram_match("log_level", "5", "selected"); %>>warning</option>
					<option value="notice" <% nvram_match("log_level", "6", "selected"); %>>notice</option>
					<option value="info" <% nvram_match("log_level", "7", "selected"); %>>info</option>
					<option value="debug" <% nvram_match("log_level", "8", "selected"); %>>debug</option>
				</select><label for="severity">or more urgent</label>
				</div>
			</div>
		')"
		sed -i -e '/Auto refresh/c\' -e "$REPLACEMENT" "$SYSLOG_WWW"

		# Use table instead of textarea
		REPLACEMENT="$(escape '
			<div id="syslogContainer">
				<table id="syslogTable">
					<colgroup>
						<col>
					</colgroup>
					<thead>
						<tr>
							<th colspan="5">Raw</th>
							<th>Facility</th>
							<th>Time</th>
							<th>Hostname</th>
							<th>Source</th>
							<th>Message</th>
						</tr>
					</thead>
					<tbody>
					</tbody>
				</table>
			</div>
		')"
		sed -i -e '/margin-top:8px/{N;N;c\' -e "$REPLACEMENT" -e '}' "$SYSLOG_WWW"

		# Add source file timestamp
		printf '%s\n' "<!-- Source timestamp: $TIMESTAMP -->" >> "$SYSLOG_WWW"
	fi

	# Mount over stock file
	if ! mount | grep -Fq '/www/Main_LogStatus_Content.asp'; then
		mount -o bind "$SYSLOG_WWW" '/www/Main_LogStatus_Content.asp'
	fi

	# Link to our files
	local FILE
	for FILE in logng.js logng_worker.js logng_style.css; do
		[ ! -L "/www/user/$FILE" ] && ln -s "/jffs/www/$FILE" "/www/user/$FILE"
	done
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
	# Do nothing if it's not enabled
	if [ "$ENABLED" != 'yes' ]; then
		false; return $?
	fi

	# Don't run until time is set
	if [ "$(nvram get ntp_ready)" != '1' ]; then
		touch /tmp/.ntpwait-syslogng
		false; return $?
	fi

	# kill any/all running klogd and/or syslogd
	pidof klogd &>/dev/null && killall klogd
	pidof syslogd &>/dev/null && killall syslogd

	# While nothing is logging lets see if we can fix the timestamps
	fixtime

	# Append stock logs
	if [ ! -L /tmp/syslog.log ]; then
		if [ -s /tmp/syslog.log-1 ] && ! printf '%s\n' "$SYSLOG_HEADER" | cmp -s /tmp/syslog.log-1; then
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

	true; return $?
}

# Start the stock syslog after terminating syslog-ng
# Usage: post_syslog
post_syslog() {
	# Remove symlinks and blocking folders
	[ -L /tmp/syslog.log ] && rm -f /tmp/syslog.log
	printf '%s\n' "$SYSLOG_HEADER" | cmp -s /tmp/syslog.log-1 && rm -f /tmp/syslog.log-1
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
		printf '%s %s\n' "$(awk -F. '{print $1}' < /proc/uptime)" "$(date '+%s')" > /tmp/.time-init
		web_mount
		[ -x '/jffs/scripts/.logmonitor.sh' ] && /jffs/scripts/.logmonitor.sh start
	;;
	'service-event')
		if [ "$1_$2" = 'restart_diskmon' ]; then
			if [ "$(nvram get ntp_ready)" = '1' ] && [ ! -f /tmp/.time-sync ]; then
				# Initial ntp sync
				printf '%s %s\n' "$(awk -F. '{print $1}' < /proc/uptime)" "$(date '+%s')" > /tmp/.time-sync
				if [ -f /tmp/.ntpwait-syslogng ]; then
					rm /tmp/.ntpwait-syslogng
					[ -x /opt/etc/init.d/S01syslog-ng ] && /opt/etc/init.d/S01syslog-ng start
				fi
			fi
		elif [ "$1" != 'stop' ] && { [ "$2" = 'logger' ] || [ "$2" = 'time' ]; } && pidof syslog-ng &>/dev/null; then
			(
				waitkill 'klogd' &
				waitkill 'syslogd' &

				wait
				[ -x /opt/etc/init.d/S01syslog-ng ] && /opt/etc/init.d/S01syslog-ng restart
			) &
		fi
	;;
	'rc.func')
		# Unset procs to include rc.func without doing anything
		PROCS=""
		. /opt/etc/init.d/rc.func
		PROC='syslog-ng'

		case "$1" in
			'start')
				[ -x '/jffs/scripts/.logmonitor.sh' ] && /jffs/scripts/.logmonitor.sh stop && LOGMONITOR='true'
				pre_syslog && start
				[ LOGMONITOR = 'true' ] && /jffs/scripts/.logmonitor.sh start
			;;
			'stop'|'kill')
				[ -x '/jffs/scripts/.logmonitor.sh' ] && /jffs/scripts/.logmonitor.sh stop && LOGMONITOR='true'
				check && stop && post_syslog
				[ LOGMONITOR = 'true' ] && /jffs/scripts/.logmonitor.sh start
			;;
			'restart')
				[ -x '/jffs/scripts/.logmonitor.sh' ] && /jffs/scripts/.logmonitor.sh stop && LOGMONITOR='true'
				if check >/dev/null; then
					stop
					start
				else
					pre_syslog && start
				fi
				[ LOGMONITOR = 'true' ] && /jffs/scripts/.logmonitor.sh start
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
		cat > /jffs/scripts/.logmonitor.sh <<'EOF'
#!/bin/sh

PID_FILE='/tmp/.logmonitor.pid'

start_monitor() {
	if [ -f "$PID_FILE" ]; then
		read -r PROCESS < "$PID_FILE"
		if [ -f "/proc/$PROCESS/status" ]; then
			return
		fi
	fi
	tail -n0 -F '/tmp/syslog.log' | while read -r LINE; do
		# Monitor skipped events
		if [ -z "${LINE##*"rc_service: skip the event:"*}" ] && [ -x '/jffs/scripts/service-event-skip' ]; then
			EVENT="${LINE#*"event: "}"
			EVENT="${EVENT%.}"
			if [ -z "${EVENT##*_*}" ]; then
				logger -t 'custom_script' "Running /jffs/scripts/service-event-skip (args: ${EVENT%%_*} ${EVENT#*_})"
				/jffs/scripts/service-event-skip "${EVENT%%_*}" "${EVENT#*_}" &
			else
				logger -t 'custom_script' "Running /jffs/scripts/service-event-skip (arg: $EVENT)"
				/jffs/scripts/service-event-skip "" "$EVENT" &
			fi
		fi
	done &
	# Find the tail we just started (other option is $! with named pipes)
	for TAILPID in $(pidof tail); do
		read -r PROCESS _ _ PARENT _ < "/proc/$TAILPID/stat"
		if [ "$PARENT" = $$ ]; then
			printf '%s\n' "$PROCESS"> "$PID_FILE"
		fi
	done
}

stop_monitor() {
	if [ -f "$PID_FILE" ]; then
		read -r PROCESS < "$PID_FILE"
		rm "$PID_FILE"
		if [ -f "/proc/$PROCESS/status" ]; then
			kill "$PROCESS" 2>/dev/null
			true; return $?
		fi
	fi
	false; return $?
}

case "$1" in
	'start')
		start_monitor
	;;
	'stop')
		stop_monitor
	;;
esac
EOF

		chmod +x /jffs/scripts/.logng.event.sh
		chmod +x /jffs/scripts/.logmonitor.sh

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
			cat > /jffs/www/logng.js <<'EOF'
Date.prototype.to8601String=function(){return this.getFullYear()+"-"+(this.getMonth()+1).toString().padStart(2,"0")+"-"+this.getDate().toString().padStart(2,"0")+" "+this.getHours().toString().padStart(2,"0")+":"+this.getMinutes().toString().padStart(2,"0")+":"+this.getSeconds().toString().padStart(2,"0")},String.prototype.lastIndexEnd=function(e){if(!e)return-1;const t=this.lastIndexOf(e);return-1===t?-1:t+e.length};let lastLine="";const syslogWorker=new Worker("/user/logng_worker.js");function processLogFile(e){const t=document.getElementById("syslogTable").getElementsByTagName("tbody")[0],l=[];let n=0;for(e.substring(e.lastIndexEnd(lastLine)).split("\n").forEach(e=>{if(e){lastLine="\n"+e+"\n";const o=t.insertRow(-1),s=o.insertCell(-1);s.innerText=e,s.colSpan=5,l.push({idx:o.rowIndex,msg:e}),n++}});l.length;)syslogWorker.postMessage(l.pop());return n}syslogWorker.onmessage=function(e){if(!e.data.idx)return;const t=document.getElementById("syslogTable").rows[e.data.idx];let l=t.insertCell(-1);e.data.facility&&(l.innerText=e.data.facility,e.data.severity&&l.setAttribute("title",e.data.severity)),l=t.insertCell(-1),e.data.time&&(l.innerText=e.data.time.to8601String(),l.setAttribute("title",e.data.time.toString())),l=t.insertCell(-1),e.data.host&&(l.innerText=e.data.host),l=t.insertCell(-1),e.data.program&&(l.innerText=e.data.program,e.data.pid&&l.setAttribute("title",`${e.data.program}[${e.data.pid}]`)),l=t.insertCell(-1),e.data.message&&(l.innerText=e.data.message),e.data.time&&e.data.program&&e.data.message&&t.classList.add("lvl_"+(e.data.severity||"unknown"))};const filterList=["emerg","alert","crit","err","warning","notice","info"];function applyFilter(e){const t=document.getElementById("syslogContainer"),l=t.scrollHeight-t.scrollTop-t.clientHeight<=1||lowestVisableRow(),n=document.getElementById("syslogTable");"undefined"!=typeof Storage&&(localStorage.selectSeverity=e);for(const t of filterList)n.classList.toggle("filter_"+t,e===t);!0===l?t.scrollTop=t.scrollHeight:l&&t.scrollTop+t.clientHeight<l.offsetTop+l.clientHeight&&(t.scrollTop=l.offsetTop+l.clientHeight-t.clientHeight)}function toggleColumn(e,t){document.getElementById("syslogTable").classList.toggle(e,t),"undefined"!=typeof Storage&&(localStorage["check"+e]=t?"true":"false")}function lowestVisableRow(){const e=document.getElementById("syslogTable"),t=document.getElementById("syslogContainer");let l;for(let n,o=0;n=e.rows[o];o++)if(n.offsetParent){if(!(t.scrollTop+t.clientHeight>=n.offsetTop+n.clientHeight))break;l=n}return l}document.addEventListener("DOMContentLoaded",function(){if("undefined"!=typeof Storage&&localStorage.selectSeverity?(-1!==filterList.indexOf(localStorage.selectSeverity)&&document.getElementById("syslogTable").classList.add("filter_"+localStorage.selectSeverity),document.getElementById("severity").value=localStorage.selectSeverity):0< <% nvram_get("log_level"); %> && <% nvram_get("log_level"); %> <8&&document.getElementById("syslogTable").classList.add("filter_"+filterList[ <% nvram_get("log_level"); %> -1]),"undefined"!=typeof Storage){const e=document.querySelectorAll("input[type=checkbox]");for(let t=0;t<e.length;t++)if(localStorage["check"+e[t].id]){const l="true"===localStorage["check"+e[t].id];document.getElementById("syslogTable").classList.toggle(e[t].id,l),document.getElementById(e[t].id).checked=l}}document.getElementById("severity").addEventListener("wheel",function(e){if(!this.hasFocus&&e.deltaY){if(e.preventDefault(),e.deltaY<0){if(this.selectedIndex<=0)return;this.selectedIndex=this.selectedIndex-1}if(e.deltaY>0){if(this.selectedIndex>=this.length-1)return;this.selectedIndex=this.selectedIndex+1}applyFilter(this.value)}})});
EOF
			cat > /jffs/www/logng_worker.js <<'EOF'
const FacilityIndex=["kern","user","mail","daemon","auth","syslog","lpr","news","uucp","cron","authpriv","ftp","ntp","security","console","solaris-cron","local0","local1","local2","local3","local4","local5","local6","local7"],FacilityMap={kern:0,user:1,mail:2,daemon:3,auth:4,syslog:5,lpr:6,news:7,uucp:8,cron:9,authpriv:10,ftp:11,ntp:12,security:13,console:14,"solaris-cron":15,local0:16,local1:17,local2:18,local3:19,local4:20,local5:21,local6:22,local7:23,logaudit:13,logalert:14,clock:15},SeverityIndex=["emerg","alert","crit","err","warning","notice","info","debug"],SeverityMap={emerg:0,alert:1,crit:2,err:3,warning:4,notice:5,info:6,debug:7,panic:0,error:3,warn:4},BSDDateMap={Jan:0,Feb:1,Mar:2,Apr:3,May:4,Jun:5,Jul:6,Aug:7,Sep:8,Oct:9,Nov:10,Dec:11},LoggyParser=function(){};LoggyParser.prototype.parse=function(e,r){if("string"!=typeof e)return e;let t={originalMessage:e},a=e,i=a.match(/^<(\d+)>\s*/);if(i&&(t.facilityID=i[1]>>>3,t.severityID=7&i[1],t.facilityID<24&&t.severityID<8&&(t.facility=FacilityIndex[t.facilityID],t.severity=SeverityIndex[t.severityID]),a=a.substring(i[0].length)),(i=a.match(/^(\d{4}\s+)?(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+/))?(t.time=new Date(i[1]||(new Date).getUTCFullYear(),BSDDateMap[i[2]],i[3],i[4],i[5],i[6]),a=a.substring(i[0].length)):(i=a.match(/^([^\s]+)\s+/))&&(t.time=this.parse8601(i[1])||this.parseRfc3339(i[1]),t.time&&(a=a.substring(i[0].length))),(i=a.match(/^(?:([^\s]*(?:[^\s:]|::))\s+(?:(kern|user|mail|daemon|auth|security|syslog|lpr|news|uucp|cron|authpriv|ftp|ntp|security|logaudit|console|logalert|solaris-cron|clock|local[0-7])\.(emerg|panic|alert|crit|err|error|warn|warning|notice|info|debug)\s+)?)?([^\s]+):\s+/))&&(t.host=i[1],t.program=i[4],i[2]&&i[3]&&(t.facilityID=FacilityMap[i[2]],t.severityID=SeverityMap[i[3]],t.facility=FacilityIndex[t.facilityID],t.severity=SeverityIndex[t.severityID]),a=a.substring(i[0].length),(i=t.program.match(/\[(\d+)\]$/))&&(t.pid=i[1],t.program=t.program.slice(0,-i[0].length))),t.pid?t.header=t.program+"["+t.pid+"]: ":t.program?t.header=t.program+": ":t.header="",t.message=a,!r)return t;r(t)},LoggyParser.prototype.parseRfc3339=function(e){let r,t,a,i=1,l=e.split("T");if(l.length<2)return!1;let s=l[0].split("-"),n=l[1].split(":"),o=n[n.length-1];if(offsetFieldIdentifier=o.charAt(o.length-1),"Z"===offsetFieldIdentifier)r=0,n[n.length-1]=o.substr(0,o.length-2);else{if(-1!=o[o.length-1].indexOf("+")?(t="+",i=1):(t="-",i=-1),(a=o.split(t)).length<2)return!1;n[n.length-1]=a[0],r=60*(r=60*(a=a[1].split(":"))[0]+a[1])*1e3}return new Date(Date.UTC(s[0],s[1]-1,s[2],n[0],n[1],n[2])+r*i)},LoggyParser.prototype.parse8601=function(e){let r=new Date(Date.parse(e));return r instanceof Date&&!isNaN(r)&&r};const syslogParser=new LoggyParser;onmessage=function(e){syslogParser.parse(e.data.msg,r=>{r.idx=e.data.idx,postMessage(r)})};
EOF
			cat > /jffs/www/logng_style.css <<'EOF'
#syslogContainer{all:initial;display:inline-block;margin-top:8px;width:745px;height:500px;resize:both;overflow:auto;font-family:'Courier New',Courier,mono;font-size:11px;color:#fff}#syslogTable{table-layout:fixed;border-collapse:collapse}#syslogTable th{margin:0;position:sticky;top:0;background:#2F3A3E;text-align:left;padding-left:5px}#syslogTable tbody{line-height:normal;height:11px}#syslogTable td{padding-left:2px;padding-right:2px;padding-top:1px;padding-bottom:0;margin:0;border-bottom:1px dotted gray;overflow:hidden;white-space:nowrap}#syslogTable col:first-of-type{border-left:2px solid #2F3A3E}#syslogTable td:last-of-type,#syslogTable th:last-of-type,#syslogTable td:first-of-type{border-right:2px solid #2F3A3E}#syslogTable tr:last-of-type{border-bottom:2px solid #2F3A3E}#syslogTable th:first-of-type,#syslogTable tr.lvl_unknown td:first-of-type,#syslogTable tr.lvl_emerg td:first-of-type,#syslogTable tr.lvl_alert td:first-of-type,#syslogTable tr.lvl_crit td:first-of-type,#syslogTable tr.lvl_err td:first-of-type,#syslogTable tr.lvl_warning td:first-of-type,#syslogTable tr.lvl_notice td:first-of-type,#syslogTable tr.lvl_info td:first-of-type,#syslogTable tr.lvl_debug td:first-of-type,#syslogTable tr:not(.lvl_unknown):not(.lvl_emerg):not(.lvl_alert):not(.lvl_crit):not(.lvl_err):not(.lvl_warning):not(.lvl_notice):not(.lvl_info):not(.lvl_debug) td:not(:first-of-type){display:none}#syslogTable th,#syslogTable td{width:0}#syslogTable td:first-of-type,#syslogTable th:last-of-type,#syslogTable td:last-of-type{width:auto;overflow:scroll}#syslogTable:not(.facility) th:nth-of-type(2),#syslogTable:not(.facility) td:nth-of-type(2){display:none}#syslogTable:not(.hostname) th:nth-of-type(4),#syslogTable:not(.hostname) td:nth-of-type(4){display:none}#syslogTable tr.lvl_emerg{background-color:#000}#syslogTable tr.lvl_alert{background-color:#DB78C6}#syslogTable tr.lvl_crit{background-color:#CF1819}#syslogTable tr.lvl_err{background-color:#C4731F}#syslogTable tr.lvl_warning{background-color:#B8BD25}#syslogTable tr.lvl_notice{background-color:#2496B3}#syslogTable tr.lvl_info{background-color:#6F7374}#syslogTable tr.lvl_debug{background-color:#449E74}#syslogTable.filter_emerg tr.lvl_alert,#syslogTable.filter_emerg tr.lvl_crit,#syslogTable.filter_emerg tr.lvl_err,#syslogTable.filter_emerg tr.lvl_warning,#syslogTable.filter_emerg tr.lvl_notice,#syslogTable.filter_emerg tr.lvl_info,#syslogTable.filter_emerg tr.lvl_debug{display:none}#syslogTable.filter_alert tr.lvl_crit,#syslogTable.filter_alert tr.lvl_err,#syslogTable.filter_alert tr.lvl_warning,#syslogTable.filter_alert tr.lvl_notice,#syslogTable.filter_alert tr.lvl_info,#syslogTable.filter_alert tr.lvl_debug{display:none}#syslogTable.filter_crit tr.lvl_err,#syslogTable.filter_crit tr.lvl_warning,#syslogTable.filter_crit tr.lvl_notice,#syslogTable.filter_crit tr.lvl_info,#syslogTable.filter_crit tr.lvl_debug{display:none}#syslogTable.filter_err tr.lvl_warning,#syslogTable.filter_err tr.lvl_notice,#syslogTable.filter_err tr.lvl_info,#syslogTable.filter_err tr.lvl_debug{display:none}#syslogTable.filter_warning tr.lvl_notice,#syslogTable.filter_warning tr.lvl_info,#syslogTable.filter_warning tr.lvl_debug{display:none}#syslogTable.filter_notice tr.lvl_info,#syslogTable.filter_notice tr.lvl_debug{display:none}#syslogTable.filter_info tr.lvl_debug{display:none}#syslogControls{color:#FC0;padding-top:10px}#syslogControls div{padding-left:10px;display:inline-block}label[for="severity"]{padding-left:5px}
EOF
			mount | grep -Fq '/www/Main_LogStatus_Content.asp' && umount '/www/Main_LogStatus_Content.asp'
			rm -f '/jffs/www/Main_LogStatus_Content.asp'
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
		rm -f '/jffs/www/Main_LogStatus_Content.asp'
		for FILE in logng.js logng_worker.js logng_style.css; do
			rm -f "/jffs/www/$FILE" "/www/user/$FILE"
		done
	;;
esac
