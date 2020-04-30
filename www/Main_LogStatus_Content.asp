<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
	<meta http-equiv="X-UA-Compatible" content="IE=Edge">
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
	<meta HTTP-EQUIV="Pragma" CONTENT="no-cache">
	<meta HTTP-EQUIV="Expires" CONTENT="-1">
	<link rel="shortcut icon" href="images/favicon.png">
	<link rel="icon" href="images/favicon.png">
	<title><#736#> - <#329#></title>
	<link rel="stylesheet" type="text/css" href="index_style.css">
	<link rel="stylesheet" type="text/css" href="form_style.css">
	<link rel="stylesheet" type="text/css" href="/user/logng_style.css">
	<script language="JavaScript" type="text/javascript" src="/user/logng.js"></script>
	<script language="JavaScript" type="text/javascript" src="/state.js"></script>
	<script language="JavaScript" type="text/javascript" src="/general.js"></script>
	<script language="JavaScript" type="text/javascript" src="/popup.js"></script>
	<script language="JavaScript" type="text/javascript" src="/help.js"></script>
	<script type="text/javascript" language="JavaScript" src="/validator.js"></script>
	<script language="JavaScript" type="text/javascript" src="/js/jquery.js"></script>
	<script>
		function showclock(){
			JS_timeObj.setTime(systime_millsec);
			systime_millsec += 1000;
			JS_timeObj2 = JS_timeObj.toString();
			JS_timeObj2 = JS_timeObj2.substring(0,3) + ", " +
			JS_timeObj2.substring(4,10) + " " +
			checkTime(JS_timeObj.getHours()) + ":" +
			checkTime(JS_timeObj.getMinutes()) + ":" +
			checkTime(JS_timeObj.getSeconds()) + " " +
			/*JS_timeObj.getFullYear() + " GMT" +
			timezone;*/ // Viz remove GMT timezone 2011.08
			JS_timeObj.getFullYear();
			document.getElementById("system_time").value = JS_timeObj2;
			setTimeout("showclock()", 1000);
			if(navigator.appName.indexOf("Microsoft") >= 0)
			document.getElementById("syslogContainer").style.width = "99%";
		}
		function showbootTime(){
			Days = Math.floor(boottime / (60*60*24));
			Hours = Math.floor((boottime / 3600) % 24);
			Minutes = Math.floor(boottime % 3600 / 60);
			Seconds = Math.floor(boottime % 60);
			document.getElementById("boot_days").innerHTML = Days;
			document.getElementById("boot_hours").innerHTML = Hours;
			document.getElementById("boot_minutes").innerHTML = Minutes;
			document.getElementById("boot_seconds").innerHTML = Seconds;
			boottime += 1;
			setTimeout("showbootTime()", 1000);
		}
		function clearLog(){
			document.form1.target = "hidden_frame";
			document.form1.action_mode.value = " Clear ";
			document.form1.submit();
			location.href = location.href;
		}
		function showDST(){
			var system_timezone_dut = "<% nvram_get("time_zone"); %>";
			if(system_timezone_dut.search("DST") >= 0 && "<% nvram_get("time_zone_dst"); %>" == "1"){
				document.getElementById('dstzone').style.display = "";
				document.getElementById('dstzone').innerHTML = "<#211#>";
			}
		}
		function initial(){
			show_menu();
			showclock();
			showbootTime();
			showDST();
			setTimeout("get_log_data();", 0);
		}
		function applySettings(){
			document.config_form.submit();
		}
		var autoscroll = true;
		function get_log_data(){
			$.ajax({
				url: '/ajax_log_data.asp',
				dataType: 'text',
				error: function(xhr){
					setTimeout("get_log_data();", 1000);
				},
				success: function(response){
					if((document.getElementById("auto_refresh").checked)){
						let el = document.getElementById("syslogContainer");
						if(el.scrollHeight - el.scrollTop - el.clientHeight <= 1) {
							autoscroll = true;
						}
						if(processLogFile(response.slice(30,-30)) > 0 && autoscroll) {
							$(el).animate({ scrollTop: el.scrollHeight - el.clientHeight }, "slow");
						}
						autoscroll = false;
					}
					setTimeout("get_log_data();", 5000);
				}
			});
		}
	</script>
</head>
<body onload="initial();" onunLoad="return unload_body();" class="bg">
	<div id="TopBanner"></div>
	<div id="Loading" class="popup_bg"></div>
	<iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>
	<form method="post" name="form" action="apply.cgi" target="hidden_frame">
		<input type="hidden" name="current_page" value="Main_LogStatus_Content.asp">
		<input type="hidden" name="next_page" value="Main_LogStatus_Content.asp">
		<input type="hidden" name="group_id" value="">
		<input type="hidden" name="modified" value="0">
		<input type="hidden" name="action_mode" value="">
		<input type="hidden" name="action_wait" value="">
		<input type="hidden" name="first_time" value="">
		<input type="hidden" name="action_script" value="">
		<input type="hidden" name="preferred_lang" id="preferred_lang" value="<% nvram_get("preferred_lang"); %>">
		<input type="hidden" name="firmver" value="<% nvram_get("firmver"); %>">
	</form>
	<table class="content" align="center" cellpadding="0" cellspacing="0">
		<tr>
			<td width="17">&nbsp;</td>
			<td valign="top" width="202">
				<div id="mainMenu"></div>
				<div id="subMenu"></div>
			</td>
			<td valign="top">
				<div id="tabMenu" class="submenuBlock"></div>
				<table width="98%" border="0" align="left" cellpadding="0" cellspacing="0">
					<tr>
						<td align="left" valign="top">
							<table width="760px" border="0" cellpadding="5" cellspacing="0" bordercolor="#6b8fa3" class="FormTitle" id="FormTitle">
								<tr>
									<td bgcolor="#4D595D" colspan="3" valign="top">
										<div>&nbsp;</div>
										<div class="formfonttitle"><#648#> - <#329#></div>
										<div style="margin:10px 0 10px 5px;" class="splitLine"></div>
										<div class="formfontdesc"><#1838#></div>
										<form method="post" name="config_form" action="start_apply.htm" target="hidden_frame">
											<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable">
												<tr>
													<th width="20%"><#212#></th>
													<td>
														<input type="text" id="system_time" name="system_time" size="40" class="devicepin" value="" readonly="1" style="font-size:12px;" autocorrect="off" autocapitalize="off">
														<br><span id="dstzone" style="display:none;margin-left:5px;color:#FFFFFF;"></span>
													</td>
												</tr>
												<tr>
													<th><#1837#></a></th>
													<td><span id="boot_days"></span> <#1389#> <span id="boot_hours"></span> <#1866#> <span id="boot_minutes"></span> <#2163#> <span id="boot_seconds"></span> <#2524#></td>
												</tr>
												<tr>
													<th><a class="hintstyle" href="javascript:void(0);" onClick="openHint(11,1)"><#2091#></a></th>
													<td>
														<input type="hidden" name="current_page" value="Main_LogStatus_Content.asp">
														<input type="hidden" name="next_page" value="Main_LogStatus_Content.asp">
														<input type="hidden" name="action_mode" value="apply">
														<input type="hidden" name="action_script" value="restart_logger">
														<input type="hidden" name="action_wait" value="5">
														<input type="text" maxlength="15" class="input_15_table" name="log_ipaddr" value="<% nvram_get("log_ipaddr"); %>" onKeyPress="return validator.isIPAddr(this, event)" autocorrect="off" autocapitalize="off">
														<label style="padding-left:15px;">Port:</label><input type="text" class="input_6_table" maxlength="5" name="log_port" onKeyPress="return validator.isNumber(this,event);" onblur="validator.numberRange(this, 0, 65535);" value='<% nvram_get("log_port"); %>' autocorrect="off" autocapitalize="off">
													</td>
												</tr>
												<tr>
													<th><a class="hintstyle" href="javascript:void(0);" onClick="openHint(50,11);">Default message log level</a></th>
													<td>
														<select name="message_loglevel" class="input_option">
															<option value="0" <% nvram_match("message_loglevel", "0", "selected"); %>>emergency</option>
															<option value="1" <% nvram_match("message_loglevel", "1", "selected"); %>>alert</option>
															<option value="2" <% nvram_match("message_loglevel", "2", "selected"); %>>critical</option>
															<option value="3" <% nvram_match("message_loglevel", "3", "selected"); %>>error</option>
															<option value="4" <% nvram_match("message_loglevel", "4", "selected"); %>>warning</option>
															<option value="5" <% nvram_match("message_loglevel", "5", "selected"); %>>notice</option>
															<option value="6" <% nvram_match("message_loglevel", "6", "selected"); %>>info</option>
															<option value="7" <% nvram_match("message_loglevel", "7", "selected"); %>>debug</option>
														</select>
													</td>
												</tr>
												<tr>
													<th><a class="hintstyle" href="javascript:void(0);" onClick="openHint(50,12);">Log only messages more urgent than</a></th>
													<td>
														<select name="log_level" class="input_option">
															<option value="1" <% nvram_match("log_level", "1", "selected"); %>>alert</option>
															<option value="2" <% nvram_match("log_level", "2", "selected"); %>>critical</option>
															<option value="3" <% nvram_match("log_level", "3", "selected"); %>>error</option>
															<option value="4" <% nvram_match("log_level", "4", "selected"); %>>warning</option>
															<option value="5" <% nvram_match("log_level", "5", "selected"); %>>notice</option>
															<option value="6" <% nvram_match("log_level", "6", "selected"); %>>info</option>
															<option value="7" <% nvram_match("log_level", "7", "selected"); %>>debug</option>
															<option value="8" <% nvram_match("log_level", "8", "selected"); %>>all</option>
														</select>
													</td>
												</tr>
											</table>
											<div class="apply_gen" valign="top"><input class="button_gen" onclick="applySettings();" type="button" value="<#164#>" /></div>
										</form>
										<div id="syslogControls">
											<div><input type="checkbox" checked id="auto_refresh"><label for="auto_refresh">Auto refresh</label></div>
											<div><input type="checkbox" id="facility" onchange="toggleColumn(this.id, this.checked);"><label for="facility">Facility</label></div>
											<div><input type="checkbox" id="hostname" onchange="toggleColumn(this.id, this.checked);"><label for="hostname">Hostname</label></div>
											<div id="severityContainer">
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
										<div>
											<table class="apply_gen">
												<tr class="apply_gen" valign="top">
													<td width="50%" align="right">
														<form method="post" name="form1" action="apply.cgi">
															<input type="hidden" name="current_page" value="Main_LogStatus_Content.asp">
															<input type="hidden" name="action_mode" value=" Clear ">
															<input type="submit" onClick="onSubmitCtrl(this, ' Clear ')" value="<#1346#>" class="button_gen">
														</form>
													</td>
													<td width="50%" align="left">
														<form method="post" name="form2" action="syslog.txt">
															<input type="submit" onClick="onSubmitCtrl(this, ' Save ');" value="<#1365#>" class="button_gen">
														</form>
													</td>
												</tr>
											</table>
										</div>
									</td>
								</tr>
							</table>
						</td>
					</tr>
				</table>
			</td>
			<td width="10" align="center" valign="top"></td>
		</tr>
	</table>
	<div id="footer"></div>
</body>
</html>
