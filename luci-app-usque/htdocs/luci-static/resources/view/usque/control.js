'use strict';
'require view';
'require ui';
'require usque.common as usque';

return view.extend({
	load: function() {
		return L.resolveDefault(usque.callStat(), {});
	},

	render: function(stat) {
		this.stat = stat || {};

		return E('div', {}, [
			E('h2', {}, _('Service control')),
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'id': 'usque-control-state' }, this.renderState()),
				E('div', { 'class': 'cbi-page-actions', 'style': 'justify-content:flex-start;gap:8px' }, [
					usque.button(_('Start'), ui.createHandlerFn(this, 'handleControl', 'start'), 'cbi-button-apply'),
					usque.button(_('Stop'), ui.createHandlerFn(this, 'handleControl', 'stop'), 'cbi-button-reset'),
					usque.button(_('Restart'), ui.createHandlerFn(this, 'handleControl', 'restart'), 'cbi-button-action')
				]),
				E('div', { 'class': 'cbi-page-actions', 'style': 'justify-content:flex-start;gap:8px' }, [
					usque.button(_('Enable on boot'), ui.createHandlerFn(this, 'handleControl', 'enable'), 'cbi-button-neutral'),
					usque.button(_('Disable on boot'), ui.createHandlerFn(this, 'handleControl', 'disable'), 'cbi-button-neutral')
				]),
				usque.note(_('Stopping the service removes the tunnel route; the WAN fallback route takes over.')),
				usque.note(_('Autostart is enabled once when the package is first installed. You can disable it here at any time.'))
			])
		]);
	},

	renderState: function() {
		var stat = this.stat || {},
		    svc = stat.service || {},
		    tun = stat.tunnel || {};

		return E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'width': '32%' }, _('Service')),
				E('td', { 'class': 'td' }, [
					usque.statusBadge(!!svc.running, _('Running'), _('Stopped')),
					svc.running && svc.pid ? E('span', {}, ' · ' + _('PID') + ' ' + svc.pid) : '',
					svc.running ? E('span', {}, ' · ' + _('Uptime') + ' ' + usque.fmtUptime(svc.uptime)) : ''
				])
			]),
			usque.row(_('Start on boot'), usque.statusBadge(!!svc.autostart, _('Enabled'), _('Disabled'))),
			usque.row(_('Interface'), E('span', {}, [
				E('code', {}, tun.iface || (stat.uci && stat.uci.iface) || 'warp0'),
				' ',
				usque.statusBadge(!!tun.present, _('Present'), _('Missing')),
				tun.present ? E('span', {}, [ ' / ', usque.statusBadge(!!tun.up, _('Up'), _('Down')) ]) : ''
			]))
		]);
	},

	refreshState: function() {
		var node = document.getElementById('usque-control-state');
		if (!node)
			return;

		while (node.firstChild)
			node.removeChild(node.firstChild);

		node.appendChild(this.renderState());
	},

	handleControl: function(action) {
		if (action == 'stop' && !confirm(_('Stop usque? The tunnel route will be removed and traffic may fall back to the WAN.')))
			return Promise.resolve();

		return usque.callControl(action).then(L.bind(function(res) {
			if (res && res.stat) {
				this.stat = res.stat;
				this.refreshState();
			}

			ui.addNotification(null, E('p', {},
				res && res.ok
					? _('Command "%s" executed.').format(action)
					: _('Command failed: %s').format((res && res.error)
						? usque.errorText(res.error) : ((res && res.output) || _('unknown error')))
			), res && res.ok ? 'info' : 'danger');
		}, this));
	}
});
