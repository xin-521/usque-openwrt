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
			E('h2', {}, _('Registration & Account')),
			this.renderRegister(),
			this.renderAccount()
		]);
	},

	renderRegister: function() {
		var cfg = (this.stat && this.stat.config) || {};

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Registration')),
			usque.note(_('Registers a new WARP device and writes the configuration file. An existing configuration is backed up to .bak and replaced automatically. Internet access to api.cloudflareclient.com is required; this can take up to a minute.')),
			cfg.exists
				? E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, _('Configuration file')),
					E('div', { 'class': 'cbi-value-field' }, [
						E('code', {}, cfg.path || ''),
						' ',
						_('%s (%s)').format(_('present'), usque.fmtSize(cfg.size))
					])
				])
				: '',
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
				usque.button(_('Register'), ui.createHandlerFn(this, 'handleRegister'), 'cbi-button-apply')
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

		return usque.callRegister(name, jwt).then(L.bind(function(res) {
			if (out)
				out.textContent = (res && res.output) || '';

			if (res && res.ok) {
				ui.addNotification(null, E('p', {}, _('Registration succeeded.')), 'info');
				return usque.callStat().then(L.bind(function(stat) {
					if (stat && stat.ok)
						this.stat = stat;
				}, this));
			}

			ui.addNotification(null, E('p', {},
				_('Registration failed: %s').format(
					(res && res.error) ? usque.errorText(res.error) : ((res && res.output) || _('unknown error')))
			), 'danger');
		}, this));
	},

	renderAccount: function() {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Account')),
			usque.note(_('Requires network access and an existing configuration file.')),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('License key')),
				E('div', { 'class': 'cbi-value-field' }, [
					E('input', {
						'id': 'usque-license',
						'class': 'cbi-input-text',
						'placeholder': 'xxxxxxxx-xxxxxxxx-xxxxxxxx'
					}),
					usque.button(_('Set license'), ui.createHandlerFn(this, 'handleAccount', 'set'), 'cbi-button-action'),
					usque.button(_('Reset license'), ui.createHandlerFn(this, 'handleAccount', 'reset'), 'cbi-button-reset')
				])
			]),
			E('div', { 'class': 'cbi-page-actions', 'style': 'justify-content:flex-start;gap:8px' }, [
				usque.button(_('Account info'), ui.createHandlerFn(this, 'handleAccount', 'info'), 'cbi-button-neutral'),
				usque.button(_('Devices'), ui.createHandlerFn(this, 'handleAccount', 'devices'), 'cbi-button-neutral')
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

		return usque.callAccount(action, key).then(function(res) {
			if (!out)
				return;

			if (res && res.ok)
				out.textContent = res.output || _('Done.');
			else
				out.textContent = _('Failed: %s').format(
					(res && res.error) ? usque.errorText(res.error) : ((res && res.output) || _('unknown error')));
		});
	}
});