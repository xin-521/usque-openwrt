#!/bin/sh
# Regression test for the managed-DNS path in usque-routing.
#
# r7/r8 created a second dnsmasq instance. Both instances bound port 53, so
# warp_dns entered a procd crash loop. This test recreates that legacy state,
# runs apply with mocks, and verifies that only the main dnsmasq is used.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
ROUTING="$ROOT/usque/root/usr/libexec/usque-routing"
[ -f "$ROUTING" ] || { echo "missing $ROUTING" >&2; exit 1; }

WORK="$ROOT/temp/_test-routing-dns-$$"
case "$WORK" in
	"$ROOT"/temp/_test-routing-dns-*) ;;
	*) echo "unsafe temporary path: $WORK" >&2; exit 1 ;;
esac
trap 'rm -rf "$WORK"' EXIT INT TERM
mkdir -p "$WORK/bin" "$WORK/root/etc/init.d" "$WORK/root/lib/functions"

STATE="$WORK/uci.state"
CALLS="$WORK/calls.log"
TESTED="$WORK/usque-routing"
OUTPUT="$WORK/output.log"
: > "$CALLS"

cat > "$STATE" <<'EOF'
usque.main.iface=warp0
usque.main.strict=0
usque.main.manage_firewall=0
usque.main.manage_dns=1
usque.main.wan_metric=250
usque.main.dns=1.1.1.1
usque.main.http2=0
usque.main.ipv6=0
usque.main.config=/etc/usque/config.json
usque.routing_state=state
usque.routing_state.dhcp_instance_target=cfg01411c
usque.routing_state.dhcp_instances=lan wan
dhcp.warp_dns=dnsmasq
dhcp.warp_dns.server=1.1.1.1
dhcp.warp_dns.strictorder=0
dhcp.lan.instance=cfg01411c
dhcp.wan.instance=cfg01411c
network.wan=interface
network.wan.metric=250
EOF

# Minimal UCI key/value store implementing only the commands used by the
# routing helper.
cat > "$WORK/bin/uci" <<'EOF'
#!/bin/sh
set -eu
STATE="${UCI_STATE:?}"
[ "${1:-}" = "-q" ] && shift
[ "${1:-}" = "-X" ] && shift
cmd=${1:-}
shift || true

get_value() {
	awk -v key="$1" '
		index($0, key "=") == 1 {
			sub(/^[^=]*=/, "")
			print
			found = 1
			exit
		}
		END { exit !found }
	' "$STATE"
}

set_value() {
	key=$1
	value=$2
	next="$STATE.next"
	found=0
	: > "$next"
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			"$key="*)
				printf '%s=%s\n' "$key" "$value" >> "$next"
				found=1
				;;
			*) printf '%s\n' "$line" >> "$next" ;;
		esac
	done < "$STATE"
	[ "$found" = 1 ] || printf '%s=%s\n' "$key" "$value" >> "$next"
	mv "$next" "$STATE"
}

case "$cmd" in
	get)
		get_value "$1"
		;;
	set)
		arg=$1
		key=${arg%%=*}
		value=${arg#*=}
		set_value "$key" "$value"
		;;
	add_list)
		arg=$1
		key=${arg%%=*}
		value=${arg#*=}
		old=$(get_value "$key" 2>/dev/null || true)
		if [ -n "$old" ]; then value="$old $value"; fi
		set_value "$key" "$value"
		;;
	delete)
		key=$1
		next="$STATE.next"
		awk -v key="$key" '
			index($0, key "=") != 1 && index($0, key ".") != 1
		' "$STATE" > "$next"
		mv "$next" "$STATE"
		;;
	show)
		cat "$STATE"
		;;
	commit)
		;;
	*)
		echo "unsupported mock uci command: $cmd" >&2
		exit 1
		;;
esac
EOF

cat > "$WORK/bin/ip" <<'EOF'
#!/bin/sh
echo "ip $*" >> "$CALLS"
case "$*" in
	*"route show default"*)
		echo "default via 10.130.0.1 dev wan proto static metric 250"
		;;
	*"route get "*) echo "1.1.1.1 via 10.130.0.1 dev wan" ;;
esac
exit 0
EOF

cat > "$WORK/bin/logger" <<'EOF'
#!/bin/sh
exit 0
EOF

cat > "$WORK/bin/jsonfilter" <<'EOF'
#!/bin/sh
exit 1
EOF

for init in network firewall dnsmasq usque; do
	cat > "$WORK/root/etc/init.d/$init" <<EOF
#!/bin/sh
echo "$init \$*" >> "\$CALLS"
[ "$init" = usque ] && [ "\${1:-}" = status ] && exit 1
exit 0
EOF
	chmod +x "$WORK/root/etc/init.d/$init"
done
chmod +x "$WORK/bin/uci" "$WORK/bin/ip" "$WORK/bin/logger" "$WORK/bin/jsonfilter"

sed \
	-e "s#/etc/init.d/#$WORK/root/etc/init.d/#g" \
	-e "s#/lib/functions/network.sh#$WORK/root/lib/functions/network.sh#g" \
	"$ROUTING" > "$TESTED"

run_apply() {
	CALLS="$CALLS" UCI_STATE="$STATE" PATH="$WORK/bin:/usr/bin:/bin" \
		sh "$TESTED" apply >"$OUTPUT"
}

assert_absent() {
	if grep -Fq "$1" "$STATE"; then
		echo "FAIL: unexpected UCI entry containing '$1'" >&2
		exit 1
	fi
}

assert_value() {
	actual=$(awk -v key="$1" 'index($0, key "=") == 1 { sub(/^[^=]*=/, ""); print; exit }' "$STATE")
	if [ "$actual" != "$2" ]; then
		echo "FAIL: $1 expected '$2', got '$actual'" >&2
		exit 1
	fi
}

run_apply
assert_absent "dhcp.warp_dns"
assert_absent "dhcp.lan.instance"
assert_absent "dhcp.wan.instance"
assert_absent "usque.routing_state"
assert_value "network.wan.peerdns" "0"
assert_value "network.wan.dns" "1.1.1.1"
grep -Fq "dnsmasq reload" "$CALLS" || {
	echo "FAIL: dnsmasq was not reloaded" >&2
	exit 1
}

# Turning management off must also clean the legacy state and restore WAN DNS.
UCI_STATE="$STATE" "$WORK/bin/uci" -q set usque.main.manage_dns=0
UCI_STATE="$STATE" "$WORK/bin/uci" -q set dhcp.warp_dns=dnsmasq
UCI_STATE="$STATE" "$WORK/bin/uci" -q set dhcp.lan.instance=cfg01411c
UCI_STATE="$STATE" "$WORK/bin/uci" -q set usque.routing_state=state
UCI_STATE="$STATE" "$WORK/bin/uci" -q set usque.routing_state.dhcp_instance_target=cfg01411c
UCI_STATE="$STATE" "$WORK/bin/uci" -q set usque.routing_state.dhcp_instances=lan
run_apply
assert_absent "dhcp.warp_dns"
assert_absent "dhcp.lan.instance"
assert_absent "usque.routing_state"
assert_value "network.wan.peerdns" "1"
assert_absent "network.wan.dns"

echo "routing DNS regression test: PASS"
