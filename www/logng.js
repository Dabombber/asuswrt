Date.prototype.to8601String = function() {
	return this.getFullYear() +
	"-" + (this.getMonth() + 1).toString().padStart(2, "0") +
	"-" + this.getDate().toString().padStart(2, "0") +
	" " + this.getHours().toString().padStart(2, "0") +
	":" + this.getMinutes().toString().padStart(2, "0") +
	":" + this.getSeconds().toString().padStart(2, "0");
};

String.prototype.lastIndexEnd = function(string) {
	if (!string) return -1;
	const io = this.lastIndexOf(string)
	return io === -1 ? -1 : io + string.length;
};

let lastLine = "";
const syslogWorker = new Worker("/user/logng_worker.js");

syslogWorker.onmessage = function(e) {
	if (!e.data.idx) return;
	const row = document.getElementById("syslogTable").rows[e.data.idx];

	let cell = row.insertCell(-1);
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
	const tbody = document.getElementById("syslogTable").getElementsByTagName("tbody")[0];
	const stack = [];
	let added = 0;
	file.substring(file.lastIndexEnd(lastLine)).split("\n").forEach(line => {
		if (line) {
			lastLine = "\n" + line + "\n";
			const row = tbody.insertRow(-1);
			const cell = row.insertCell(-1);
			cell.innerText = line;
			cell.colSpan = 5;
			//syslogWorker.postMessage({idx: row.rowIndex, msg: line});
			stack.push({idx: row.rowIndex, msg: line});
			added++;
		}
	});
	while(stack.length) syslogWorker.postMessage(stack.pop());
	return added;
}

// Debug means no filter, so no need to include
const filterList = ["emerg", "alert", "crit", "err", "warning", "notice", "info"];

document.addEventListener("DOMContentLoaded", function() {
	// Initialise filters
	if (typeof(Storage) !== "undefined" && localStorage.selectSeverity) {
		if(filterList.indexOf(localStorage.selectSeverity) !== -1) {
			document.getElementById("syslogTable").classList.add("filter_" + localStorage.selectSeverity)
		}
		document.getElementById("severity").value = localStorage.selectSeverity;
	} else {
		// Fallback to copying built in settings
		if (0 < <% nvram_get("log_level"); %> && <% nvram_get("log_level"); %> < 8) {
			document.getElementById("syslogTable").classList.add("filter_" + filterList[<% nvram_get("log_level"); %> - 1])
		}
	}

	// Initialise columns
	if (typeof(Storage) !== "undefined") {
		const inputs = document.querySelectorAll("input[type=checkbox]");
		for(let i = 0; i < inputs.length; i++) {
			if(localStorage["check" + inputs[i].id]) {
				const value = (localStorage["check" + inputs[i].id] === "true");
				document.getElementById("syslogTable").classList.toggle(inputs[i].id, value);
				document.getElementById(inputs[i].id).checked = value;
			}
		}
	}

	// Allow changing severity by scrolling over it
	document.getElementById("severity").addEventListener("wheel", function(e) {
		if(this.hasFocus || !e.deltaY) return;
		e.preventDefault();
		if(e.deltaY < 0) {
			if(this.selectedIndex <= 0) return;
			this.selectedIndex = this.selectedIndex - 1;
		}
		if(e.deltaY > 0) {
			if(this.selectedIndex >= this.length - 1) return;
			this.selectedIndex = this.selectedIndex + 1;
		}
		applyFilter(this.value);
	});
});

function applyFilter(newSeverity) {
	const container = document.getElementById("syslogContainer");
	const rescroll = (container.scrollHeight - container.scrollTop - container.clientHeight <= 1) ? true : lowestVisableRow();
	const table = document.getElementById("syslogTable");
	if (typeof(Storage) !== "undefined") {
		localStorage.selectSeverity = newSeverity;
	}
	for (const severity of filterList) {
		table.classList.toggle("filter_" + severity, newSeverity === severity);
	}
	if(rescroll === true) {
		container.scrollTop = container.scrollHeight
	} else if(rescroll && container.scrollTop + container.clientHeight < rescroll.offsetTop + rescroll.clientHeight) {
		container.scrollTop = rescroll.offsetTop + rescroll.clientHeight - container.clientHeight;
	}
}

function toggleColumn(column, toggle) {
	document.getElementById("syslogTable").classList.toggle(column, toggle);
	if (typeof(Storage) !== "undefined") {
		localStorage["check" + column] = toggle ? "true" : "false";
	}
}

function lowestVisableRow() {
	const table = document.getElementById("syslogTable");
	const container = document.getElementById("syslogContainer");
	let bottomRow;

	for (let i = 0, row; (row = table.rows[i]); i++) {
		// Skip hidden rows
		if(!row.offsetParent) continue;
		if(container.scrollTop + container.clientHeight >= row.offsetTop + row.clientHeight) {
			bottomRow = row;
		} else {
			break;
		}
	}
	return bottomRow;
}
