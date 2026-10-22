'use strict';
'require view';
'require poll';
'require rpc';
'require ui';

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

function errorText(err) {
	var map = {
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

	return (err && map[err]) || err || _('unknown error');
}

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(callStat(), {}),
			L.resolveDefault(callLogs(200), { lines: '' })
		]);
	},

	render: function(data) {
		this.stat = data[0] || {};
		this.logs = data[1] || { lines: '' };

		poll.add(L.bind(function() {
			return L.resolveDefault(callStat(), null).then(L.bind(function(res) {
				if (res && res.ok) {
					this.stat = res;
					this.refreshStat();
				}
			}, this));
		}, this), 10);

		return E('div', {}, [
			E('h2', {}, _('Usque WARP')),
			this.renderStatus(),
			this.renderActions(),
			this.renderEgress(),
			this.renderRegister(),
			this.renderAccount(),
			this.renderLogs()
		]);
	},

	renderStatus: function() {
		var stat = this.stat || {},
		    svc = stat.service || {},
		    bin = stat.binary || {},
		    cfg = stat.config || {},
		    tun = stat.tunnel || {},
		    rt = stat.routes || {},
		    uci = stat.uci || {};

		var ifaceLine = E('span', {}, [
			E('code', {}, tun.iface || uci.iface || 'warp0'),
			' ',
			statusBadge(!!tun.present, _('Present'), _('Missing')),
			tun.present ? E('span', {}, [ ' / ', statusBadge(!!tun.up, _('Up'), _('Down')) ]) : ''
		]);

		var configLine;
		if (cfg.exists) {
			configLine = E('span', {}, [
				E('code', {}, cfg.path || ''),
				' ',
				_('%s (%s)').format(_('present'), fmtSize(cfg.size))
			]);
		}
		else {
			configLine = E('span', { 'style': 'color:#c62828' }, [
				E('code', {}, cfg.path || _('unknown')),
				' — ',
				_('missing, register first')
			]);
		}

		var selftest = rt.selftest4 || '';
		var selfOk = tun.iface && selftest.indexOf('dev ' + tun.iface) >= 0;

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Status')),
			E('div', { 'id': 'usque-status' }, [
				E('table', { 'class': 'table' }, [
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td', 'width': '32%' }, _('Service')),
						E('td', { 'class': 'td' }, [
							statusBadge(!!svc.running, _('Running'), _('Stopped')),
							svc.running && svc.pid ? E('span', {}, ' · ' + _('PID') + ' ' + svc.pid) : '',
							svc.running ? E('span', {}, ' · ' + _('Uptime') + ' ' + fmtUptime(svc.uptime)) : ''
						])
					]),
					row(_('Start on boot'), statusBadge(!!svc.autostart, _('Enabled'), _('Disabled'))),
					row(_('Version'), bin.exists ? (bin.version || _('unknown')) : statusBadge(false, '', _('usque binary not found'))),
					row(_('Configuration file'), configLine),
					row(_('Interface'), ifaceLine),
					row(_('MTU'), tun.mtu ? String(tun.mtu) : '-'),
					row(_('Tunnel address'),
						(tun.ipv4 && tun.ipv4.length) || (tun.ipv6 && tun.ipv6.length)
							? E('span', {}, [
								(tun.ipv4 && tun.ipv4.length) ? E('code', {}, tun.ipv4.join(', ')) : '',
								(tun.ipv4 && tun.ipv4.length && tun.ipv6 && tun.ipv6.length) ? ' / ' : '',
								(tun.ipv6 && tun.ipv6.length) ? E('code', {}, tun.ipv6.join(', ')) : ''
							])
							: '-'),
					row(_('IPv4 default route'), rt.default4 ? E('pre', { 'style': 'margin:0;white-space:pre-wrap' }, rt.default4) : _('none')),
					row(_('IPv6 default route'), rt.default6 ? E('pre', { 'style': 'margin:0;white-space:pre-wrap' }, rt.default6) : _('none')),
					row(_('Physical (WAN) default route'), rt.wan4 ? E('pre', { 'style': 'margin:0;white-space:pre-wrap' }, rt.wan4) : _('none')),
					row(_('Egress self-test'),
						selftest
							? E('span', {}, [
								statusBadge(selfOk, _('through tunnel'), _('not through tunnel')),
								E('pre', { 'style': 'margin:4px 0 0;white-space:pre-wrap' }, selftest)
							])
							: '-')
				])
			])
		]);
	},

	refreshStat: function() {
		var node = document.getElementById('usque-status');
		if (!node)
			return;

		while (node.firstChild)
			node.removeChild(node.firstChild);

		var fresh = this.renderStatus().querySelector('#usque-status');
		if (fresh) {
			while (fresh.firstChild)
				node.appendChild(fresh.firstChild);
		}
	},

	renderActions: function() {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Service control')),
			E('div', { 'class': 'cbi-page-actions', 'style': 'justify-content:flex-start;gap:8px' }, [
				button(_('Start'), ui.createHandlerFn(this, 'handleControl', 'start'), 'cbi-button-apply'),
				button(_('Stop'), ui.createHandlerFn(this, 'handleControl', 'stop'), 'cbi-button-reset'),
				button(_('Restart'), ui.createHandlerFn(this, 'handleControl', 'restart'), 'cbi-button-action'),
				button(_('Enable on boot'), ui.createHandlerFn(this, 'handleControl', 'enable'), 'cbi-button-neutral'),
				button(_('Disable on boot'), ui.createHandlerFn(this, 'handleControl', 'disable'), 'cbi-button-neutral')
			]),
			note(_('Stopping the service removes the tunnel route; the WAN fallback route takes over.'))
		]);
	},

	handleControl: function(action) {
		if (action == 'stop' && !confirm(_('Stop usque? The tunnel route will be removed and traffic may fall back to the WAN.')))
			return Promise.resolve();

		return callControl(action).then(L.bind(function(res) {
			if (res && res.stat)
				this.stat = res.stat;

			this.refreshStat();

			ui.addNotification(null, E('p', {},
				res && res.ok
					? _('Command "%s" executed.').format(action)
					: _('Command failed: %s').format((res && (res.output || res.error)) || _('unknown error'))
			), res && res.ok ? 'info' : 'danger');
		}, this));
	},

	renderEgress: function() {
		var uci = (this.stat && this.stat.uci) || {};
		var iface = (this.stat && this.stat.tunnel && this.stat.tunnel.iface) || uci.iface || 'warp0';

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Egress check')),
			note(_('Fetches https://www.cloudflare.com/cdn-cgi/trace and shows the public IP and WARP state. Requires curl or uclient-fetch.')),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Interface')),
				E('div', { 'class': 'cbi-value-field' }, [
					E('input', { 'id': 'usque-egress-iface', 'class': 'cbi-input-text', 'value': iface }),
					button(_('Check egress'), ui.createHandlerFn(this, 'handleEgress'), 'cbi-button-action')
				])
			]),
			E('pre', { 'id': 'usque-egress-out', 'style': 'white-space:pre-wrap;margin:0' }, '')
		]);
	},

	handleEgress: function() {
		var out = document.getElementById('usque-egress-out');
		var input = document.getElementById('usque-egress-iface');
		var iface = input ? input.value.trim() : '';

		if (out)
			out.textContent = _('Checking…');

		return callEgress(iface).then(function(res) {
			if (!out)
				return;

			if (!res || !res.ok) {
				out.textContent = _('Check failed: %s').format(
					(res && (res.error ? errorText(res.error) : res.output)) || _('unknown error'));
				return;
			}

			out.textContent = [
				'ip=' + (res.ip || '?'),
				'warp=' + (res.warp || '?'),
				'loc=' + (res.loc || '?'),
				'colo=' + (res.colo || '?')
			].join('\n');
		});
	},

	renderRegister: function() {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Registration')),
			note(_('Registers a new WARP device and writes the configuration file. An existing configuration is backed up to .bak and replaced automatically. Internet access to api.cloudflareclient.com is required; this can take up to a minute.')),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Device name')),
				E('div', { 'class': 'cbi-value-field' },
					E('input', { 'id': 'usque-reg-name', 'class': 'cbi-input-text', 'value': 'openwrt-router' }))
			]),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Team token (JWT or login link, optional)')),
				E('div', { 'class': 'cbi-value-field' }, [
					E('input', {
						'id': 'usque-reg-jwt',
						'class': 'cbi-input-text',
						'style': 'width:100%',
						'placeholder': _('Bare token, login link or <meta> snippet')
					}),
					E('div', { 'class': 'cbi-value-description' },
						_('Paste the bare token, the whole login link, or the <meta ...> snippet; the token is extracted automatically.'))
				])
			]),
			E('div', { 'class': 'cbi-page-actions', 'style': 'justify-content:flex-start' }, [
				button(_('Register'), ui.createHandlerFn(this, 'handleRegister'), 'cbi-button-apply')
			]),
			E('pre', { 'id': 'usque-reg-out', 'style': 'white-space:pre-wrap;margin:0' }, '')
		]);
	},

	handleRegister: function() {
		var nameNode = document.getElementById('usque-reg-name');
		var jwtNode = document.getElementById('usque-reg-jwt');
		var out = document.getElementById('usque-reg-out');

		var name = nameNode ? nameNode.value.trim() : '';
		var jwt = jwtNode ? jwtNode.value.trim() : '';

		if (out)
			out.textContent = _('Registering, please wait…');

		return callRegister(name, jwt).then(L.bind(function(res) {
			if (out)
				out.textContent = (res && res.output) || '';

			if (res && res.ok) {
				ui.addNotification(null, E('p', {}, _('Registration succeeded.')), 'info');
				return callStat().then(L.bind(function(stat) {
					if (stat && stat.ok) {
						this.stat = stat;
						this.refreshStat();
					}
				}, this));
			}

			ui.addNotification(null, E('p', {},
				_('Registration failed: %s').format(
					(res && (res.error ? errorText(res.error) : res.output)) || _('unknown error'))
			), 'danger');
		}, this));
	},

	renderAccount: function() {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Account')),
			note(_('Requires network access and an existing configuration file.')),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('License key')),
				E('div', { 'class': 'cbi-value-field' }, [
					E('input', {
						'id': 'usque-license',
						'class': 'cbi-input-text',
						'placeholder': 'xxxxxxxx-xxxxxxxx-xxxxxxxx'
					}),
					button(_('Set license'), ui.createHandlerFn(this, 'handleAccount', 'set'), 'cbi-button-action'),
					button(_('Reset license'), ui.createHandlerFn(this, 'handleAccount', 'reset'), 'cbi-button-reset')
				])
			]),
			E('div', { 'class': 'cbi-page-actions', 'style': 'justify-content:flex-start;gap:8px' }, [
				button(_('Account info'), ui.createHandlerFn(this, 'handleAccount', 'info'), 'cbi-button-neutral'),
				button(_('Devices'), ui.createHandlerFn(this, 'handleAccount', 'devices'), 'cbi-button-neutral')
			]),
			E('pre', { 'id': 'usque-account-out', 'style': 'white-space:pre-wrap;margin:0' }, '')
		]);
	},

	handleAccount: function(action) {
		if (action == 'reset' && !confirm(_('Reset the license key?')))
			return Promise.resolve();

		var licNode = document.getElementById('usque-license');
		var out = document.getElementById('usque-account-out');
		var key = licNode ? licNode.value.trim() : '';

		if (out)
			out.textContent = _('Working…');

		return callAccount(action, key).then(function(res) {
			if (!out)
				return;

			if (res && res.ok)
				out.textContent = res.output || _('Done.');
			else
				out.textContent = _('Failed: %s').format(
					(res && (res.error ? errorText(res.error) : res.output)) || _('unknown error'));
		});
	},

	renderLogs: function() {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Logs')),
			E('div', { 'class': 'cbi-page-actions', 'style': 'justify-content:flex-start' }, [
				button(_('Refresh'), ui.createHandlerFn(this, 'handleLogs'), 'cbi-button-neutral')
			]),
			E('pre', { 'id': 'usque-logs', 'style': 'white-space:pre-wrap;margin:0;max-height:420px;overflow:auto' },
				(this.logs && this.logs.lines) || _('No log entries.'))
		]);
	},

	handleLogs: function() {
		var out = document.getElementById('usque-logs');
		return callLogs(200).then(function(res) {
			if (out)
				out.textContent = (res && res.lines) || _('No log entries.');
		});
	}
});
