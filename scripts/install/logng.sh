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

		sed -i -f - "$SYSLOG_WWW" <<-'EOSCRIPT'
			#!/bin/sed -f

			# Include our files
			/form_style\.css/a\
			<link rel="stylesheet" type="text\/css" href="\/user\/logng_style\.css">\n<script language="JavaScript" type="text\/javascript" src="\/user\/logng\.js"><\/script>

			# Peform an update on page load
			/scrollTop = 9999999/{N;s/.*/setTimeout("get_log_data();", 0);/}

			# Read syslog as text instead of script
			s/dataType: 'script'/dataType: 'text'/

			# Some IE thing which most likely doesn't even work
			s/getElementById("textarea").style/getElementById("syslogContainer").style/

			# Replace success function
			/var h = 0;/d
			s/var height = 0;/var autoscroll = true;/
			/function(response){/{n;N;N;N;N;s/.*/if((document\.getElementById("auto_refresh")\.checked)){\nlet el = document\.getElementById("syslogContainer");\nif(el\.scrollHeight - el\.scrollTop - el\.clientHeight <= 1) autoscroll = true;\nif(processLogFile(response\.slice(31,-30)) > 0 \&\& autoscroll) \$(el)\.animate({ scrollTop: el.scrollHeight - el.clientHeight }, "slow");\nautoscroll = false;/}

			# Add checkboxes for togglable columns and severity selector
			s/style="color:#FFCC00;/&padding-top:10px;/
			s/Auto refresh<\/div>/<label for="auto_refresh">Auto refresh<\/label>\n<input type="checkbox" id="facility" onchange="document\.getElementById('syslogTable')\.classList\.toggle(this\.id, this\.checked);"><label for="facility">Facility<\/label>\n<input type="checkbox" id="hostname" onchange="document\.getElementById('syslogTable')\.classList\.toggle(this\.id, this\.checked);"><label for="hostname">Hostname<\/label>\n<div id="severityContainer">\n<select id="severity" class="input_option" onchange="filterSeverity(this)">\n<option value="emerg" <% nvram_match("log_level", "1", "selected"); %>>emergency<\/option>\n<option value="alert" <% nvram_match("log_level", "2", "selected"); %>>alert<\/option>\n<option value="crit" <% nvram_match("log_level", "3", "selected"); %>>critical<\/option>\n<option value="err" <% nvram_match("log_level", "4", "selected"); %>>error<\/option>\n<option value="warning" <% nvram_match("log_level", "5", "selected"); %>>warning<\/option>\n<option value="notice" <% nvram_match("log_level", "6", "selected"); %>>notice<\/option>\n<option value="info" <% nvram_match("log_level", "7", "selected"); %>>info<\/option>\n<option value="debug" <% nvram_match("log_level", "8", "selected"); %>>debug<\/option>\n<\/select>\n<label for="severity">or more urgent<\/label>\n<\/div>\n<\/div>/
			/showDST();/a\
			initSeverity();

			# Use table instead of textarea
			/id="textarea"/c\
			<div id="syslogContainer">\n<table id="syslogTable">\n<colgroup>\n<col>\n<\/colgroup>\n<thead>\n<tr>\n<th colspan="5">Raw<\/th>\n<th>Facility<\/th>\n<th>Time<\/th>\n<th>Hostname<\/th>\n<th>Source<\/th>\n<th>Message<\/th>\n<\/tr>\n<\/thead>\n<tbody>\n<\/tbody>\n<\/table>\n<\/div>
		EOSCRIPT

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
			waitkill 'klogd' &
			waitkill 'syslogd' &
		fi
	;;
	'rc.func')
		# Unset procs to include rc.func without doing anything
		PROCS=""
		. /opt/etc/init.d/rc.func
		PROC='syslog-ng'

		case "$1" in
			'start')
				pre_syslog && start
			;;
			'stop'|'kill')
				check && stop && post_syslog
			;;
			'restart')
				if check >/dev/null; then
					stop
					start
				else
					pre_syslog && start
				fi
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
			cat > /jffs/www/logng.js <<'EOF'
Date.prototype.to8601String=function(){return this.getFullYear()+'-'+(this.getMonth()+1).toString().padStart(2,'0')+'-'+this.getDate().toString().padStart(2,'0')+' '+this.getHours().toString().padStart(2,'0')+':'+this.getMinutes().toString().padStart(2,'0')+':'+this.getSeconds().toString().padStart(2,'0')};String.prototype.lastIndexEnd=function(string){if(!string)return-1;var io=this.lastIndexOf(string)
return io==-1?-1:io+string.length};var lastLine="";var syslogWorker=new Worker("/user/logng_worker.js");syslogWorker.onmessage=function(e){if(!e.data.idx)return;var row=document.getElementById("syslogTable").rows[e.data.idx];var cell=row.insertCell(-1);if(e.data.facility){cell.innerText=e.data.facility;if(e.data.severity)cell.setAttribute("title",e.data.severity)}
cell=row.insertCell(-1);if(e.data.time){cell.innerText=e.data.time.to8601String();cell.setAttribute("title",e.data.time.toString())}
cell=row.insertCell(-1);if(e.data.host)cell.innerText=e.data.host;cell=row.insertCell(-1);if(e.data.program){cell.innerText=e.data.program;if(e.data.pid)cell.setAttribute("title",`${e.data.program}[${e.data.pid}]`)}
cell=row.insertCell(-1);if(e.data.message)cell.innerText=e.data.message;if(e.data.time&&e.data.program&&e.data.message)row.classList.add("lvl_"+(e.data.severity||"unknown"))}
function processLogFile(file){var tbody=document.getElementById("syslogTable").getElementsByTagName("tbody")[0];var added=0;file.substring(file.lastIndexEnd(lastLine)).split("\n").forEach(line=>{if(line){lastLine="\n"+line+"\n";var row=tbody.insertRow(-1);var cell=row.insertCell(-1);cell.innerText=line;cell.colSpan=5;syslogWorker.postMessage({idx:row.rowIndex,msg:line});added++}});return added}
var filterList=['emerg','alert','crit','err','warning','notice','info'];function filterSeverity(selectObject){var container=document.getElementById("syslogContainer");var rescroll=(container.scrollHeight-container.scrollTop-container.clientHeight<=1);var table=document.getElementById("syslogTable");for(const severity of filterList){table.classList.toggle("filter_"+severity,selectObject.value==severity)}
if(rescroll&&!(container.scrollHeight-container.scrollTop-container.clientHeight<=1))$(container).animate({scrollTop:container.scrollHeight-container.clientHeight},"slow")}
function initSeverity(){if(0<<%nvram_get("log_level");%>&&<%nvram_get("log_level");%><8){document.getElementById("syslogTable").classList.add("filter_"+filterList[<%nvram_get("log_level");%>-1])}}
EOF
			cat > /jffs/www/logng_worker.js <<'EOF'
var FacilityIndex=['kern','user','mail','daemon','auth','syslog','lpr','news','uucp','cron','authpriv','ftp','ntp','security','console','solaris-cron','local0','local1','local2','local3','local4','local5','local6','local7'];var SeverityIndex=['emerg','alert','crit','err','warning','notice','info','debug'];var BSDDateIndex={'Jan':0,'Feb':1,'Mar':2,'Apr':3,'May':4,'Jun':5,'Jul':6,'Aug':7,'Sep':8,'Oct':9,'Nov':10,'Dec':11};var LoggyParser=function(){};LoggyParser.prototype.parse=function(rawMessage,callback){if(typeof rawMessage!='string'){return rawMessage}
var parsedMessage={originalMessage:rawMessage};var rightMessage=rawMessage;var segment=rightMessage.match(/^<(\d+)>\s*/);if(segment){parsedMessage.facilityID=segment[1]>>>3;parsedMessage.severityID=segment[1]&0b111;if(parsedMessage.facilityID<24&&parsedMessage.severityID<8){parsedMessage.facility=FacilityIndex[parsedMessage.facilityID];parsedMessage.severity=SeverityIndex[parsedMessage.severityID]}
rightMessage=rightMessage.substring(segment[0].length)}
segment=rightMessage.match(/^(\d{4}\s+)?(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+/);if(segment){parsedMessage.time=new Date(segment[1]||(new Date()).getUTCFullYear(),BSDDateIndex[segment[2]],segment[3],segment[4],segment[5],segment[6]);rightMessage=rightMessage.substring(segment[0].length)}else{segment=rightMessage.match(/^([^\s]+)\s+/);if(segment){parsedMessage.time=this.parse8601(segment[1])||this.parseRfc3339(segment[1]);if(parsedMessage.time){rightMessage=rightMessage.substring(segment[0].length)}}}
segment=rightMessage.match(/^(?:([^\s]+(?:[^\s:]|::))\s+)?([^\s]+):\s+/);if(segment){parsedMessage.host=segment[1];parsedMessage.program=segment[2];rightMessage=rightMessage.substring(segment[0].length);segment=parsedMessage.program.match(/\[(\d+)\]$/);if(segment){parsedMessage.pid=segment[1];parsedMessage.program=parsedMessage.program.slice(0,-segment[0].length)}}
if(parsedMessage.pid){parsedMessage.header=parsedMessage.program+"["+parsedMessage.pid+"]: "}else if(parsedMessage.program){parsedMessage.header=parsedMessage.program+": "}else{parsedMessage.header=""}
parsedMessage.message=rightMessage;if(callback){callback(parsedMessage)}else{return parsedMessage}};LoggyParser.prototype.parseRfc3339=function(timeStamp){var utcOffset,offsetSplitChar,offsetString,offsetMultiplier=1,dateTime=timeStamp.split("T");if(dateTime.length<2)return!1;var date=dateTime[0].split("-"),time=dateTime[1].split(":"),offsetField=time[time.length-1];offsetFieldIdentifier=offsetField.charAt(offsetField.length-1);if(offsetFieldIdentifier==="Z"){utcOffset=0;time[time.length-1]=offsetField.substr(0,offsetField.length-2)}else{if(offsetField[offsetField.length-1].indexOf("+")!=-1){offsetSplitChar="+";offsetMultiplier=1}else{offsetSplitChar="-";offsetMultiplier=-1}
offsetString=offsetField.split(offsetSplitChar);if(offsetString.length<2)return!1;time[(time.length-1)]=offsetString[0];offsetString=offsetString[1].split(":");utcOffset=(offsetString[0]*60)+offsetString[1];utcOffset=utcOffset*60*1000}
var parsedTime=new Date(Date.UTC(date[0],date[1]-1,date[2],time[0],time[1],time[2])+(utcOffset*offsetMultiplier));return parsedTime};LoggyParser.prototype.parse8601=function(timeStamp){var parsedTime=new Date(Date.parse(timeStamp));if(parsedTime instanceof Date&&!isNaN(parsedTime))return parsedTime;return!1};var syslogParser=new LoggyParser();onmessage=function(e){syslogParser.parse(e.data.msg,(msg)=>{msg.idx=e.data.idx;postMessage(msg)})}
EOF
			cat > /jffs/www/logng_style.css <<'EOF'
#syslogContainer{width:68em;height:45em;resize:both;overflow:auto;font-family:'Courier New',Courier,mono;font-size:11px}#syslogTable{table-layout:fixed;min-height:300px;border-collapse:collapse}#syslogTable th{margin:0;position:sticky;top:0;background:#2F3A3E;text-align:left;padding-left:5px}#syslogTable td{padding-left:2px;padding-right:2px;padding-top:0;padding-bottom:0;margin:0;border:1px solid gray;overflow:hidden;white-space:nowrap}#syslogTable col:first-of-type{border-left:2px solid #2F3A3E}#syslogTable td:last-of-type,#syslogTable th:last-of-type,#syslogTable td:first-of-type{border-right:2px solid #2F3A3E}#syslogTable tr:last-of-type{border-bottom:2px solid #2F3A3E}#syslogTable th:first-of-type,#syslogTable tr.lvl_unknown td:first-of-type,#syslogTable tr.lvl_emerg td:first-of-type,#syslogTable tr.lvl_alert td:first-of-type,#syslogTable tr.lvl_crit td:first-of-type,#syslogTable tr.lvl_err td:first-of-type,#syslogTable tr.lvl_warning td:first-of-type,#syslogTable tr.lvl_notice td:first-of-type,#syslogTable tr.lvl_info td:first-of-type,#syslogTable tr.lvl_debug td:first-of-type,#syslogTable tr:not(.lvl_unknown):not(.lvl_emerg):not(.lvl_alert):not(.lvl_crit):not(.lvl_err):not(.lvl_warning):not(.lvl_notice):not(.lvl_info):not(.lvl_debug) td:not(:first-of-type){display:none}#syslogTable th,#syslogTable td{width:0}#syslogTable td:first-of-type,#syslogTable th:last-of-type,#syslogTable td:last-of-type{width:auto;overflow:scroll}#syslogTable:not(.facility) th:nth-of-type(2),#syslogTable:not(.facility) td:nth-of-type(2){display:none}#syslogTable:not(.hostname) th:nth-of-type(4),#syslogTable:not(.hostname) td:nth-of-type(4){display:none}#syslogTable tr.lvl_emerg{background-color:#000}#syslogTable tr.lvl_alert{background-color:#DB78C6}#syslogTable tr.lvl_crit{background-color:#CF1819}#syslogTable tr.lvl_err{background-color:#C4731F}#syslogTable tr.lvl_warning{background-color:#B8BD25}#syslogTable tr.lvl_notice{background-color:#2496B3}#syslogTable tr.lvl_info{background-color:#6F7374}#syslogTable tr.lvl_debug{background-color:#449E74}#syslogTable.filter_emerg tr.lvl_alert,#syslogTable.filter_emerg tr.lvl_crit,#syslogTable.filter_emerg tr.lvl_err,#syslogTable.filter_emerg tr.lvl_warning,#syslogTable.filter_emerg tr.lvl_notice,#syslogTable.filter_emerg tr.lvl_info,#syslogTable.filter_emerg tr.lvl_debug{display:none}#syslogTable.filter_alert tr.lvl_crit,#syslogTable.filter_alert tr.lvl_err,#syslogTable.filter_alert tr.lvl_warning,#syslogTable.filter_alert tr.lvl_notice,#syslogTable.filter_alert tr.lvl_info,#syslogTable.filter_alert tr.lvl_debug{display:none}#syslogTable.filter_crit tr.lvl_err,#syslogTable.filter_crit tr.lvl_warning,#syslogTable.filter_crit tr.lvl_notice,#syslogTable.filter_crit tr.lvl_info,#syslogTable.filter_crit tr.lvl_debug{display:none}#syslogTable.filter_err tr.lvl_warning,#syslogTable.filter_err tr.lvl_notice,#syslogTable.filter_err tr.lvl_info,#syslogTable.filter_err tr.lvl_debug{display:none}#syslogTable.filter_warning tr.lvl_notice,#syslogTable.filter_warning tr.lvl_info,#syslogTable.filter_warning tr.lvl_debug{display:none}#syslogTable.filter_notice tr.lvl_info,#syslogTable.filter_notice tr.lvl_debug{display:none}#syslogTable.filter_info tr.lvl_debug{display:none}#severityContainer{display:inline-block;padding-left:10px}label[for="severity"]{padding-left:5px}
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
		rm -f '/jffs/www/Main_LogStatus_Content.asp'
		for FILE in logng.js logng_worker.js logng_style.css; do
			rm -f "/jffs/www/$FILE" "/www/user/$FILE"
		done
	;;
esac
