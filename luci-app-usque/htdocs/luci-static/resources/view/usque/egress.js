'use strict';
'require view';
'require ui';
'require usque.common as usque';

return view.extend({
	load: function() {
		return L.resolveDefault(usque.callStat(), {});
	},

	render: function(stat) {
		stat = stat || {};

		var uci = stat.uci || {},
		    tun = stat.tunnel || {},
		    iface = tun.iface || uci.iface || 'warp0';

		return E('div', {}, [
			E('h2', {}, _('Egress check')),
			E('div', { 'class': 'cbi-section' }, [
				usque.note(_('Fetches https://www.cloudflare.com/cdn-cgi/trace and shows the public IP and WARP state. Requires curl or uclient-fetch.')),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, _('Interface')),
					E('div', { 'class': 'cbi-value-field' }, [
						E('input', { 'id': 'usque-egress-iface', 'class': 'cbi-input-text', 'value': iface }),
						usque.button(_('Check egress'), ui.createHandlerFn(this, 'handleEgress'), 'cbi-button-action')
					])
				]),
				E('pre', { 'id': 'usque-egress-out', 'style': 'white-space:pre-wrap;margin:0' }, '')
			])
		]);
	},

	handleEgress: function() {
		var out = document.getElementById('usque-egress-out');
		var input = document.getElementById('usque-egress-iface');
		var iface = input ? input.value.trim() : '';

		if (out)
			out.textContent = _('Checking…');

		return usque.callEgress(iface).then(function(res) {
			if (!out)
				return;

			if (!res || !res.ok) {
				out.textContent = _('Check failed: %s').format(
					(res && res.error) ? usque.errorText(res.error) : ((res && res.output) || _('unknown error')));
				return;
			}

			out.textContent = [
				'ip=' + (res.ip || '?'),
				'warp=' + (res.warp || '?'),
				'loc=' + (res.loc || '?'),
				'colo=' + (res.colo || '?')
			].join('\n');
		});
	}
});