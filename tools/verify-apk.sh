#!/bin/sh
# ???? APK ????????????verify-apk.sh <usque|luci> <apk>
set -eu
KIND=$1
APK=$2
APK_STATIC=${APK_STATIC:-$(cd "$(dirname "$0")" && pwd)/apk.static}
[ -f "$APK" ] || { echo "missing $APK" >&2; exit 1; }
[ -x "$APK_STATIC" ] || { echo "missing apk.static" >&2; exit 1; }

python3 - "$APK" <<'PY'
import sys
d = open(sys.argv[1], "rb").read(4)
assert d == b"ADBd", "not an apk v3 (ADB) package: %r" % d
PY

D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
if [ "$KIND" = luci ]; then
	ARCH=$("$APK_STATIC" adbdump "$APK" | sed -n 's/^  arch: //p')
	[ "$ARCH" = noarch ] || { echo "BAD arch: $ARCH (want noarch)" >&2; exit 1; }
fi

"$APK_STATIC" extract --allow-untrusted --destination "$D" "$APK" >/dev/null

need=""
[ "$KIND" = usque ] && need="usr/bin/usque etc/init.d/usque etc/config/usque etc/usque/up.sh etc/usque/down.sh etc/usque/options.sh etc/sysctl.d/90-usque.conf usr/libexec/usque-routing"
[ "$KIND" = luci ] && need="usr/share/rpcd/ucode/luci.usque usr/share/luci/menu.d/luci-app-usque.json usr/share/rpcd/acl.d/luci-app-usque.json etc/uci-defaults/95-luci-app-usque www/luci-static/resources/view/usque/overview.js www/luci-static/resources/view/usque/settings.js usr/lib/lua/luci/i18n/usque.zh-cn.lmo"
[ -n "$need" ] || { echo "unknown kind $KIND" >&2; exit 1; }

for f in $need; do
	[ -f "$D/$f" ] || { echo "MISSING /$f" >&2; exit 1; }
done
for f in usr/bin/usque etc/init.d/usque etc/usque/up.sh etc/usque/down.sh usr/libexec/usque-routing; do
	[ -x "$D/$f" ] || { [ "$KIND" = usque ] && { echo "NOT EXEC /$f" >&2; exit 1; }; }
done
for f in usr/share/rpcd/ucode/luci.usque etc/uci-defaults/95-luci-app-usque; do
	[ -x "$D/$f" ] || { [ "$KIND" = luci ] && { echo "NOT EXEC /$f" >&2; exit 1; }; }
done

echo "APK OK: $(basename "$APK") ($(wc -c < "$APK") bytes, $(find "$D" -type f | wc -l) files)"
