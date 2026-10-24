'use strict';
'require view';
'require poll';
'require ui';
'require usque.common as usque';

var LINE_CHOICES = [ 100, 200, 500, 1000 ];
var DEFAULT_LINES = 200;

return view.extend({
	load: function() {
		return L.resolveDefault(usque.callLogs(DEFAULT_LINES), null);
	},

	render: function(data) {
		this.lines = DEFAULT_LINES;

		var select = E('select', {
			'id': 'usque-log-lines',
			'class': 'cbi-input-select',
			'change': ui.createHandlerFn(this, 'handleLogs')
		}, LINE_CHOICES.map(function(n) {
			return E('option', { 'value': String(n) }, String(n));
		}));
		select.value = String(DEFAULT_LINES);

		var initial = this.logText(data);

		poll.add(L.bind(function() {
			return this.fetchLogs(false);
		}, this), 10);

		return E('div', {}, [
			E('h2', {}, _('Logs')),
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, _('Lines')),
					E('div', { 'class': 'cbi-value-field' }, [
						select,
						usque.button(_('Refresh'), ui.createHandlerFn(this, 'handleLogs'), 'cbi-button-neutral')
					])
				]),
				usque.note(_('Shows the last syslog entries that mention usque, including procd and the connect/disconnect hooks. The list refreshes every 10 seconds and can be paged back with Lines.')),
				E('pre', { 'id': 'usque-logs', 'style': 'white-space:pre-wrap;margin:0;max-height:420px;overflow:auto' },
					initial)
			])
		]);
	},

	logText: function(res) {
		if (res && res.error)
			return _('Failed: %s').format(usque.errorText(res.error));

		return (res && res.lines) || _('No log entries.');
	},

	currentLines: function() {
		var sel = document.getElementById('usque-log-lines');
		var n = sel ? parseInt(sel.value, 10) : NaN;

		return (n > 0) ? n : DEFAULT_LINES;
	},

	fetchLogs: function(showProgress) {
		var out = document.getElementById('usque-logs');

		if (showProgress && out)
			out.textContent = _('Loading…');

		return usque.callLogs(this.currentLines()).then(L.bind(function(res) {
			this.logs = res;

			if (out)
				out.textContent = this.logText(res);
		}, this), L.bind(function(err) {
			if (out)
				out.textContent = _('Failed: %s').format(usque.errorText(err && err.message));
		}, this));
	},

	handleLogs: function() {
		return this.fetchLogs(true);
	}
});