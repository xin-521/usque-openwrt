'use strict';
'require rpc';

// =============================================================================
//  Shared ubus wrappers and small helpers for every usque view.
//
//  NOTE about the rpcd ucode argument types: the backend declares method
//  arguments as `name: <type hint>` where the *value* selects the ubus type
//  (integer -> BLOBMSG_TYPE_INT32, boolean -> INT8, array -> ARRAY,
//  object -> TABLE, anything else -> STRING).  A string such as 'int' is
//  therefore a String argument, and the browser's numeric {"lines":200}
//  would be rejected with "Invalid argument" before the call is dispatched.
//  Keep `lines` numeric here and in the backend.
// =============================================================================

var callStat = rpc.declare({
	object: 'luci.usque',
	method: 'stat',
	expect: {}
});

var callControl = rpc.declare({
	object: 'luci.usque',
	method: 'control',
	params: [ 'action' ],
	expect: {}
});

var callLogs = rpc.declare({
	object: 'luci.usque',
	method: 'logs',
	params: [ 'lines' ],
	expect: {}
});

var callEgress = rpc.declare({
	object: 'luci.usque',
	method: 'check_egress',
	params: [ 'iface' ],
	expect: {}
});

var callRegister = rpc.declare({
	object: 'luci.usque',
	method: 'register',
	params: [ 'name', 'jwt' ],
	expect: {}
});

var callAccount = rpc.declare({
	object: 'luci.usque',
	method: 'account',
	params: [ 'action', 'key' ],
	expect: {}
});

var ERROR_TEXT = {
	'invalid-name': _('Device name may only contain letters, digits, dot, dash and underscore.'),
	'invalid-jwt': _('No valid team token was found in the pasted text.'),
	'invalid-license': _('The license key format is invalid.'),
	'invalid-config-path': _('The configuration path is invalid.'),
	'invalid-iface': _('The interface name is invalid.'),
	'no-config': _('No configuration file found. Register first.'),
	'binary-missing': _('The usque binary is not installed.'),
	'init-missing': _('The usque init script is not installed.'),
	'service-disabled': _('The service is disabled in Settings. Enable it there first.'),
	'routing-helper-missing': _('The routing helper /usr/libexec/usque-routing is missing.'),
	'no-http-client': _('Neither curl nor uclient-fetch is installed.'),
	'backup-failed': _('Could not move the existing configuration aside.'),
	'bad-action': _('Unsupported action.'),
	'unknown error': _('unknown error')
};

function errorText(err) {
	return (err && ERROR_TEXT[err]) || err || _('unknown error');
}

function fmtUptime(sec) {
	sec = +sec || 0;
	if (sec <= 0)
		return '-';

	var d = Math.floor(sec / 86400),
	    h = Math.floor((sec % 86400) / 3600),
	    m = Math.floor((sec % 3600) / 60),
	    s = sec % 60;

	if (d > 0)
		return '%dd %dh %dm'.format(d, h, m);
	if (h > 0)
		return '%dh %dm'.format(h, m);
	if (m > 0)
		return '%dm %ds'.format(m, s);
	return '%ds'.format(s);
}

function fmtSize(bytes) {
	bytes = +bytes || 0;
	if (bytes >= 1048576)
		return (bytes / 1048576).toFixed(1) + ' MB';
	if (bytes >= 1024)
		return (bytes / 1024).toFixed(1) + ' KB';
	return '%d B'.format(bytes);
}

function statusBadge(ok, goodText, badText) {
	return E('span', {
		'style': ok ? 'color:#2e7d32;font-weight:bold' : 'color:#c62828;font-weight:bold'
	}, ok ? goodText : badText);
}

function row(label, value) {
	return E('tr', { 'class': 'tr' }, [
		E('td', { 'class': 'td', 'width': '32%' }, label),
		E('td', { 'class': 'td' }, value)
	]);
}

function button(label, handler, style) {
	return E('button', {
		'class': 'btn cbi-button ' + (style || 'cbi-button-neutral'),
		'click': handler
	}, label);
}

function note(text) {
	return E('p', { 'class': 'cbi-section-descr' }, text);
}

return L.Class.extend({
	callStat: callStat,
	callControl: callControl,
	callLogs: callLogs,
	callEgress: callEgress,
	callRegister: callRegister,
	callAccount: callAccount,
	errorText: errorText,
	fmtUptime: fmtUptime,
	fmtSize: fmtSize,
	statusBadge: statusBadge,
	row: row,
	button: button,
	note: note
});