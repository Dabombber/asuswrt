Date.prototype.to8601String = function() {
	return this.getFullYear() +
	'-' + (this.getMonth() + 1).toString().padStart(2, '0') +
	'-' + this.getDate().toString().padStart(2, '0') +
	' ' + this.getHours().toString().padStart(2, '0') +
	':' + this.getMinutes().toString().padStart(2, '0') +
	':' + this.getSeconds().toString().padStart(2, '0');
};

String.prototype.lastIndexEnd = function(string) {
	if (!string) return -1;
	var io = this.lastIndexOf(string)
	return io == -1 ? -1 : io + string.length;
};

var lastLine = "";
var syslogWorker = new Worker("/user/logng_worker.js");

syslogWorker.onmessage = function(e) {
	if (!e.data.idx) return;
	var row = document.getElementById("syslogTable").rows[e.data.idx];

	var cell = row.insertCell(-1);
	if (e.data.facility) {
		cell.innerText = e.data.facility;
		if(e.data.severity) cell.setAttribute("title", e.data.severity);
	}

	cell = row.insertCell(-1);
	if (e.data.time) {
		cell.innerText = e.data.time.to8601String();
		cell.setAttribute("title", e.data.time.toString());
	}

	cell = row.insertCell(-1);
	if (e.data.host) cell.innerText = e.data.host;

	cell = row.insertCell(-1);
	if (e.data.program) {
		cell.innerText = e.data.program;
		if(e.data.pid) cell.setAttribute("title", `${e.data.program}[${e.data.pid}]`);
	}

	cell = row.insertCell(-1);
	if (e.data.message) cell.innerText = e.data.message;

	if(e.data.time && e.data.program && e.data.message) row.classList.add("lvl_" + (e.data.severity || "unknown"));
}

function processLogFile(file) {
	var tbody = document.getElementById("syslogTable").getElementsByTagName("tbody")[0];
	file.substring(file.lastIndexEnd(lastLine)).split("\n").forEach(line => {
		if (line) {
			lastLine = "\n" + line + "\n";
			var row = tbody.insertRow(-1);
			var cell = row.insertCell(-1);
			cell.innerText = line;
			cell.colSpan = 5;
			syslogWorker.postMessage({idx: row.rowIndex, msg: line});
		}
	});
}

// Debug means no filter, so no need to include
var filterList = ['emerg','alert','crit','err','warning','notice','info'];

function filterSeverity(selectObject) {
	var container = document.getElementById("syslogContainer");
	var rescroll = (container.scrollHeight - container.scrollTop - container.clientHeight <= 1);
	var table = document.getElementById("syslogTable");
	for (const severity of filterList) {
		table.classList.toggle("filter_" + severity, selectObject.value == severity);
	}
	if(rescroll && !(container.scrollHeight - container.scrollTop - container.clientHeight <= 1)) $(container).animate({ scrollTop: container.scrollHeight - container.clientHeight }, "slow");
}

function initSeverity() {
	if(0 < <% nvram_get("log_level"); %> && <% nvram_get("log_level"); %> < 8) {
		document.getElementById("syslogTable").classList.add("filter_" + filterList[<% nvram_get("log_level"); %> - 1])
	}
}
