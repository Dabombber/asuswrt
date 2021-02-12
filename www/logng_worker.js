/*
 *  Bastardised from GlossyParser(Copyright Squeeks <privacymyass@gmail.com>)
 *
 *  Parses syslog-ng messages in the format:
 *    <${PRI}>${DATE|FULLDATE|ISODATE} ${HOST} ${PROGRAM}[${PID}]: ${MESSAGE}
 *
 *  PRI, HOST and PID are optional
 */

/*
 *  These values replace the integers in message that define the facility.
 *    ntp, security, console and solaris-cron used internally
 */
const FacilityIndex = [
	"kern",
	"user",
	"mail",
	"daemon",
	"auth",
	"syslog",
	"lpr",
	"news",
	"uucp",
	"cron",
	"authpriv",
	"ftp",
	"ntp",
	"security",
	"console",
	"solaris-cron",
	"local0",
	"local1",
	"local2",
	"local3",
	"local4",
	"local5",
	"local6",
	"local7"
];
const FacilityMap = {
	// syslog-ng
	"kern": 0,
	"user": 1,
	"mail": 2,
	"daemon": 3,
	"auth": 4,
	"syslog": 5,
	"lpr": 6,
	"news": 7,
	"uucp": 8,
	"cron": 9,
	"authpriv": 10,
	"ftp": 11,
	"ntp": 12,
	"security": 13,
	"console": 14,
	"solaris-cron": 15,
	"local0": 16,
	"local1": 17,
	"local2": 18,
	"local3": 19,
	"local4": 20,
	"local5": 21,
	"local6": 22,
	"local7": 23,

	// rsyslog
	"logaudit": 13,
	"logalert": 14,
	"clock": 15
};

/*
 *  These values replace the integers in message that define the severity.
 */
const SeverityIndex = [
	"emerg",
	"alert",
	"crit",
	"err",
	"warning",
	"notice",
	"info",
	"debug"
];
const SeverityMap = {
	"emerg": 0,
	"alert": 1,
	"crit": 2,
	"err": 3,
	"warning": 4,
	"notice": 5,
	"info": 6,
	"debug": 7,

	// deprecated
	"panic": 0,
	"error": 3,
	"warn": 4
};

/*
 *  Defines the range matching BSD style months to integers.
 */
const BSDDateMap = {
	"Jan": 0,
	"Feb": 1,
	"Mar": 2,
	"Apr": 3,
	"May": 4,
	"Jun": 5,
	"Jul": 6,
	"Aug": 7,
	"Sep": 8,
	"Oct": 9,
	"Nov": 10,
	"Dec": 11
};

const LoggyParser = function() {};

/*
 *  Parse the raw message received.
 *
 *  @param {String/Buffer} rawMessage Raw message received from socket
 *  @param {Function} callback Callback to run after parse is complete
 *  @return {Object} map containing all successfully parsed data:
 *    originalMessage
 *    facilityID
 *    severityID
 *    facility
 *    severity
 *    time
 *    host
 *    program
 *    pid
 *    header
 *    message
 */
LoggyParser.prototype.parse = function(rawMessage, callback) {
	if(typeof rawMessage != "string") {
		return rawMessage;
	}

	// Always return the original message
	let parsedMessage = {
		originalMessage: rawMessage
	};

	// The bit of the message that isn't the other bits of the message
	let rightMessage = rawMessage;

	// Priority/Facility
	let segment = rightMessage.match(/^<(\d+)>\s*/);
	if(segment) {
		parsedMessage.facilityID = segment[1] >>> 3;
		parsedMessage.severityID = segment[1] & 0b111;

		if(parsedMessage.facilityID < 24 && parsedMessage.severityID < 8) {
			parsedMessage.facility = FacilityIndex[parsedMessage.facilityID];
			parsedMessage.severity = SeverityIndex[parsedMessage.severityID];
		}
		rightMessage = rightMessage.substring(segment[0].length);
	}

	// Date
	segment = rightMessage.match(/^(\d{4}\s+)?(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+/);
	if(segment) {
		parsedMessage.time = new Date(segment[1] || (new Date()).getUTCFullYear(), BSDDateMap[segment[2]], segment[3], segment[4], segment[5], segment[6]);
		rightMessage = rightMessage.substring(segment[0].length);
	} else {
		segment = rightMessage.match(/^([^\s]+)\s+/);
		if(segment) {
			parsedMessage.time = this.parse8601(segment[1]) || this.parseRfc3339(segment[1]);
			if(parsedMessage.time) {
				rightMessage = rightMessage.substring(segment[0].length);
			}
		}
	}

	// Hostname facility.level Program[Pid]:
	segment = rightMessage.match(/^(?:([^\s]*(?:[^\s:]|::))\s+(?:(kern|user|mail|daemon|auth|security|syslog|lpr|news|uucp|cron|authpriv|ftp|ntp|security|logaudit|console|logalert|solaris-cron|clock|local[0-7])\.(emerg|panic|alert|crit|err|error|warn|warning|notice|info|debug)\s+)?)?([^\s]+):\s+/);
	if(segment) {
		parsedMessage.host = segment[1];
		parsedMessage.program = segment[4];

		if(segment[2] && segment[3]) {
			parsedMessage.facilityID = FacilityMap[segment[2]];
			parsedMessage.severityID = SeverityMap[segment[3]];

			parsedMessage.facility = FacilityIndex[parsedMessage.facilityID];
			parsedMessage.severity = SeverityIndex[parsedMessage.severityID];
		}

		rightMessage = rightMessage.substring(segment[0].length);

		segment = parsedMessage.program.match(/\[(\d+)\]$/);
		if(segment) {
			parsedMessage.pid = segment[1];
			parsedMessage.program = parsedMessage.program.slice(0, -segment[0].length);
		}
	}

	// Header shortcut
	if(parsedMessage.pid) {
		parsedMessage.header = parsedMessage.program + "[" + parsedMessage.pid + "]: ";
	} else if(parsedMessage.program){
		parsedMessage.header = parsedMessage.program + ": ";
	} else {
		parsedMessage.header = "";
	}

	// Whatever is left
	parsedMessage.message = rightMessage;

	if(callback) {
		callback(parsedMessage);
	} else {
		return parsedMessage;
	}
};

/*
 *  Parse RFC3339 style timestamps
 *  @param {String} timeStamp
 *  @return {Date/false} Timestamp, if parsed correctly
 *  @see http://blog.toppingdesign.com/2009/08/13/fast-rfc-3339-date-processing-in-javascript/
 */
LoggyParser.prototype.parseRfc3339 = function(timeStamp){
	let
		utcOffset,
		offsetSplitChar,
		offsetString,
		offsetMultiplier = 1,
		dateTime = timeStamp.split("T");

	if(dateTime.length < 2) return false;

	let
		date = dateTime[0].split("-"),
		time = dateTime[1].split(":"),
		offsetField = time[time.length - 1];

	offsetFieldIdentifier = offsetField.charAt(offsetField.length - 1);
	if (offsetFieldIdentifier === "Z") {
		utcOffset = 0;
		time[time.length - 1] = offsetField.substr(0, offsetField.length - 2);
	} else {
		if (offsetField[offsetField.length - 1].indexOf("+") != -1) {
			offsetSplitChar = "+";
			offsetMultiplier = 1;
		} else {
			offsetSplitChar = "-";
			offsetMultiplier = -1;
		}

		offsetString = offsetField.split(offsetSplitChar);
		if(offsetString.length < 2) return false;

		time[(time.length - 1)] = offsetString[0];
		offsetString = offsetString[1].split(":");
		utcOffset = (offsetString[0] * 60) + offsetString[1];
		utcOffset = utcOffset * 60 * 1000;
	}
	return new Date(Date.UTC(date[0], date[1] - 1, date[2], time[0], time[1], time[2]) + (utcOffset * offsetMultiplier));
};

/*
 *  Parse ISO 8601 timestamps
 *  @param {String} timeStamp
 *  @return {Object/false} Timestamp, if successfully parsed
 */
LoggyParser.prototype.parse8601 = function(timeStamp) {
	let parsedTime = new Date(Date.parse(timeStamp));
	if(parsedTime instanceof Date && !isNaN(parsedTime)) return parsedTime;
	return false;
};


const syslogParser = new LoggyParser();
onmessage = function(e) {
	syslogParser.parse(e.data.msg, (msg) => {
		msg.idx = e.data.idx;
		postMessage(msg);
	});
};
