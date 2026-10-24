'use strict';
'require view';
'require form';
'require rpc';
'require uci';
'require ui';

var callRouting = rpc.declare({
	object: 'luci.usque',
	method: 'routing',
	params: [ 'action' ],
	expect: {}
});

function errorText(err) {
	if (err == 'routing-helper-missing')
		return _('The routing helper /usr/libexec/usque-routing is missing.');
	if (err == 'bad-action')
		return _('Unsupported action.');
	return err || _('unknown error');
}

return view.extend({
	load: function() {
		return uci.load('usque');
	},

	render: function() {
		var m, s, o;

		m = new form.Map('usque', _('Usque WARP'),
			_('Configuration of the usque nativetun daemon. Saving commits /etc/config/usque and reloads the service through procd.'));

		s = m.section(form.NamedSection, 'main', 'usque', _('Settings'));
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('Enable service'),
			_('Master switch. When disabled, procd will not start usque even if autostart is enabled.'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'iface', _('Interface name'),
			_('Name of the TUN interface. Keep warp0 unless it conflicts with another interface.'));
		o.default = 'warp0';
		o.rmempty = false;
		o.placeholder = 'warp0';

		o = s.option(form.Value, 'config', _('Configuration file'),
			_('Device credentials written by usque register. Contains private keys; keep it private.'));
		o.default = '/etc/usque/config.json';
		o.rmempty = false;

		o = s.option(form.Flag, 'always_reconnect', _('Always reconnect'),
			_('Pass --always-reconnect so the tunnel is re-established even when idle.'));
		o.default = '1';

		o = s.option(form.Flag, 'http2', _('Use HTTP/2 over TCP'),
			_('Pass --http2 to use TCP+TLS instead of QUIC when UDP/443 is blocked. If logs report "tls: access denied", Cloudflare rejected this account or endpoint for HTTP/2; try another endpoint.'));

		o = s.option(form.Value, 'endpoint_h2_v4', _('HTTP/2 IPv4 endpoint'),
			_('Optional override for endpoint_h2_v4. Leave empty to use the endpoint stored in config.json, or 162.159.198.2 when it is unset.'));
		o.datatype = 'ip4addr';
		o.placeholder = '162.159.198.2';

		o = s.option(form.Value, 'endpoint_h2_v6', _('HTTP/2 IPv6 endpoint'),
			_('Required when both HTTP/2 and IPv6 endpoint are enabled. The usque default is empty.'));
		o.datatype = 'ip6addr';
		o.placeholder = _('not set');

		o = s.option(form.Flag, 'ipv6', _('Use IPv6 endpoint'),
			_('Pass -6 to connect to the WARP endpoint over IPv6.'));

		o = s.option(form.Value, 'sni', _('TLS SNI'),
			_('Optional -s value. A harmless SNI such as www.bing.com can help against DPI.'));
		o.placeholder = _('default');

		o = s.option(form.Value, 'port', _('Connect port'),
			_('UDP/TCP port used for the MASQUE connection (443 by default).'));
		o.default = '443';
		o.datatype = 'port';
		o.rmempty = false;

		o = s.option(form.Value, 'keepalive', _('Keepalive period (seconds)'),
			_('Passed as --keepalive-period. Shorten it if NAT drops idle connections.'));
		o.default = '30';
		o.datatype = 'range(1,3600)';
		o.rmempty = false;

		o = s.option(form.Value, 'reconnect_delay', _('Reconnect delay (seconds)'),
			_('Passed as --reconnect-delay.'));
		o.default = '1';
		o.datatype = 'range(1,60)';
		o.rmempty = false;

		o = s.option(form.Value, 'mtu', _('MTU'),
			_('The tunnel MTU; 1280 is the only supported value.'));
		o.default = '1280';
		o.datatype = 'uinteger';
		o.rmempty = false;

		o = s.option(form.Flag, 'insecure', _('Disable certificate pinning'),
			_('Pass --insecure. Troubleshooting only: it removes protection against man-in-the-middle attacks.'));
		o.rmempty = false;

		o = s.option(form.Flag, 'no_tunnel_ipv4', _('Disable IPv4 inside the tunnel'),
			_('Pass --no-tunnel-ipv4.'));

		o = s.option(form.Flag, 'no_tunnel_ipv6', _('Disable IPv6 inside the tunnel'),
			_('Pass --no-tunnel-ipv6.'));

		o = s.option(form.Value, 'tun_metric', _('Tunnel route metric'),
			_('Metric of the default route installed by the connect hook. Must be lower than the WAN metric.'));
		o.default = '10';
		o.datatype = 'uinteger';
		o.rmempty = false;

		o = s.option(form.Value, 'wan_metric', _('WAN fallback metric'),
			_('Metric of the physical WAN default route. Higher means the tunnel wins while it is up.'));
		o.default = '250';
		o.datatype = 'uinteger';
		o.rmempty = false;

		o = s.option(form.Flag, 'strict', _('Strict mode'),
			_('Remove the WAN default route entirely, so traffic never falls back to the ISP when the tunnel is down.'));

		o = s.option(form.Flag, 'manage_firewall', _('Manage firewall'),
			_('Create the warp zone, LAN to warp forwarding and NAT rules when routing is applied.'));
		o.default = '1';

		o = s.option(form.Flag, 'manage_dns', _('Manage DNS'),
			_('Point the dnsmasq upstream at the tunnel to avoid DNS leaks when routing is applied.'));
		o.default = '1';

		o = s.option(form.Value, 'dns', _('DNS server'),
			_('Upstream server used when Manage DNS is enabled.'));
		o.default = '1.1.1.1';
		o.datatype = 'ipaddr';
		o.rmempty = false;

		o = s.option(form.Button, '_apply_routing', _('Apply routing'),
			_('Installs the warp interface, default route priority, firewall zone and DNS upstream from the saved settings.'));
		o.inputtitle = _('Apply routing');
		o.inputstyle = 'apply';
		o.onclick = ui.createHandlerFn(this, 'handleRouting', 'apply');

		o = s.option(form.Button, '_revert_routing', _('Revert routing'),
			_('Stops usque and removes the warp interface, firewall and DNS UCI entries created by Apply routing.'));
		o.inputtitle = _('Revert routing');
		o.inputstyle = 'remove';
		o.onclick = ui.createHandlerFn(this, 'handleRouting', 'revert');

		return m.render();
	},

	handleRouting: function(action) {
		if (action == 'revert' &&
		    !confirm(_('Revert routing? usque will be stopped and the warp interface, firewall and DNS entries will be removed.')))
			return Promise.resolve();

		return callRouting(action).then(function(res) {
			if (res && res.ok)
				ui.addNotification(null, E('p', {}, _('Routing action "%s" completed.').format(action)), 'info');
			else
				ui.addNotification(null, E('p', {},
					_('Routing action failed: %s').format(
						(res && (res.error ? errorText(res.error) : res.output)) || _('unknown error'))
				), 'danger');
		});
	}
});
