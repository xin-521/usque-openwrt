'use strict';
'require view';
'require poll';
'require usque.common as usque';

return view.extend({
	load: function() {
		return L.resolveDefault(usque.callStat(), {});
	},

	render: function(stat) {
		this.stat = stat || {};

		poll.add(L.bind(function() {
			return L.resolveDefault(usque.callStat(), null).then(L.bind(function(res) {
				if (res && res.ok) {
					this.stat = res;
					this.refreshStat();
				}
			}, this));
		}, this), 10);

		return E('div', {}, [
			E('h2', {}, _('Status')),
			this.renderStatus()
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
			usque.statusBadge(!!tun.present, _('Present'), _('Missing')),
			tun.present ? E('span', {}, [ ' / ', usque.statusBadge(!!tun.up, _('Up'), _('Down')) ]) : ''
		]);

		var configLine;
		if (cfg.exists) {
			configLine = E('span', {}, [
				E('code', {}, cfg.path || ''),
				' ',
				_('%s (%s)').format(_('present'), usque.fmtSize(cfg.size))
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
			E('div', { 'id': 'usque-status' }, [
				E('table', { 'class': 'table' }, [
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td', 'width': '32%' }, _('Service')),
						E('td', { 'class': 'td' }, [
							usque.statusBadge(!!svc.running, _('Running'), _('Stopped')),
							svc.running && svc.pid ? E('span', {}, ' · ' + _('PID') + ' ' + svc.pid) : '',
							svc.running ? E('span', {}, ' · ' + _('Uptime') + ' ' + usque.fmtUptime(svc.uptime)) : ''
						])
					]),
					usque.row(_('Start on boot'), usque.statusBadge(!!svc.autostart, _('Enabled'), _('Disabled'))),
					usque.row(_('Version'), bin.exists ? (bin.version || _('unknown')) : usque.statusBadge(false, '', _('usque binary not found'))),
					usque.row(_('Configuration file'), configLine),
					usque.row(_('Interface'), ifaceLine),
					usque.row(_('MTU'), tun.mtu ? String(tun.mtu) : '-'),
					usque.row(_('Tunnel address'),
						(tun.ipv4 && tun.ipv4.length) || (tun.ipv6 && tun.ipv6.length)
							? E('span', {}, [
								(tun.ipv4 && tun.ipv4.length) ? E('code', {}, tun.ipv4.join(', ')) : '',
								(tun.ipv4 && tun.ipv4.length && tun.ipv6 && tun.ipv6.length) ? ' / ' : '',
								(tun.ipv6 && tun.ipv6.length) ? E('code', {}, tun.ipv6.join(', ')) : ''
							])
							: '-'),
					usque.row(_('IPv4 default route'), rt.default4 ? E('pre', { 'style': 'margin:0;white-space:pre-wrap' }, rt.default4) : _('none')),
					usque.row(_('IPv6 default route'), rt.default6 ? E('pre', { 'style': 'margin:0;white-space:pre-wrap' }, rt.default6) : _('none')),
					usque.row(_('Physical (WAN) default route'), rt.wan4 ? E('pre', { 'style': 'margin:0;white-space:pre-wrap' }, rt.wan4) : _('none')),
					usque.row(_('Egress self-test'),
						selftest
							? E('span', {}, [
								usque.statusBadge(selfOk, _('through tunnel'), _('not through tunnel')),
								E('pre', { 'style': 'margin:4px 0 0;white-space:pre-wrap' }, selftest)
							])
							: '-')
				])
			]),
			usque.note(_('The table refreshes every 10 seconds while this page is open.'))
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
	}
});