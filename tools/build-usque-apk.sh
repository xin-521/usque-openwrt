#!/bin/sh
# =============================================================================
#  build-usque-apk.sh —— 把 dist/bin 里的预编译 usque 打成 OpenWrt 25.x .apk
#
#  用法（Linux / WSL）：
#    APK_STATIC=/path/to/apk.static sh tools/build-usque-apk.sh
#    APK_STATIC=/path/to/apk.static sh tools/build-usque-apk.sh arm64
#    APK_STATIC=/path/to/apk.static sh tools/build-usque-apk.sh arm64 aarch64_cortex-a53
#
#  参数 1：Go 架构（dist/bin/usque-linux-<arch>），默认 arm64
#  参数 2：APK 架构字符串，默认 all（不做过架构校验，便于本地安装；生产包请
#          填路由器 `apk info --print-arch` 的输出）
#
#  产物：dist/usque-<ver>-r<rel>.<apkarch>.apk
# =============================================================================
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
SRC="$ROOT/usque"
BIN="$ROOT/dist/bin/usque-linux-${1:-arm64}"

GOARCH=${1:-arm64}
APKARCH=${2:-all}
VER=${USQUE_VERSION:-4.2.1}
REL=${USQUE_RELEASE:-1}
OUT="$ROOT/dist/usque-${VER}-r${REL}.${APKARCH}.apk"

APK_STATIC=${APK_STATIC:-}
if [ -z "$APK_STATIC" ]; then
	for c in "$ROOT/tools/apk.static" "$HOME/.local/bin/apk.static"; do
		if [ -x "$c" ]; then APK_STATIC=$c; break; fi
	done
fi
if [ -z "$APK_STATIC" ]; then
	APK_STATIC=$(command -v apk.static 2>/dev/null || true)
fi
if [ -z "$APK_STATIC" ]; then
	echo "找不到 apk.static；请设置 APK_STATIC=/path/to/apk.static" >&2
	exit 1
fi

if [ ! -f "$BIN" ]; then
	echo "找不到 $BIN" >&2
	echo "可用目标：" >&2
	for f in "$ROOT"/dist/bin/usque-linux-*; do
		[ -f "$f" ] && echo "  ${f##*/usque-linux-}" >&2
	done
	exit 1
fi

STAGE="$ROOT/temp/usque-apk-stage"
PKG="$STAGE/pkgroot"

rm -rf "$STAGE"
mkdir -p "$PKG" "$ROOT/dist"

cp -R "$SRC/root/." "$PKG/"
mkdir -p "$PKG/usr/bin"
install -m 0755 "$BIN" "$PKG/usr/bin/usque"

# 权限（源码在 Windows/NTFS 上没有可执行位）
chmod 755 "$PKG/usr/bin/usque"
chmod 755 "$PKG/etc/init.d/usque"
chmod 755 "$PKG/etc/usque/up.sh"
chmod 755 "$PKG/etc/usque/down.sh"
chmod 755 "$PKG/usr/libexec/usque-routing"
chmod 644 "$PKG/etc/usque/options.sh"
chmod 644 "$PKG/etc/sysctl.d/90-usque.conf"
chmod 600 "$PKG/etc/config/usque"

# NTFS/Git Bash cannot represent the executable bit on an extensionless ELF;
# refuse to build a package whose service would fail with "Permission denied".
MODEBAD=0
for f in usr/bin/usque etc/init.d/usque etc/usque/up.sh etc/usque/down.sh usr/libexec/usque-routing; do
	[ -x "$PKG/$f" ] || { echo "[!] 缺少可执行位：/$f" >&2; MODEBAD=1; }
done
if [ "$MODEBAD" = 1 ]; then
	echo "ERROR: 当前文件系统未保留可执行位（常见于 Windows/Git Bash）。" >&2
	echo "       请在 Linux/WSL 或路由器上运行本脚本。" >&2
	[ "${ALLOW_BAD_MODES:-0}" = 1 ] || exit 1
	echo "[!] ALLOW_BAD_MODES=1：继续打包，安装后必须手动 chmod 755 /usr/bin/usque 等文件。" >&2
fi

# 与 MANIFEST/SHA256SUMS 核对，避免把旧二进制打进包
SUM=""
if command -v sha256sum >/dev/null 2>&1; then
	SUM=$(sha256sum "$BIN" | awk '{print $1}')
fi
if [ -n "$SUM" ] && [ -f "$ROOT/dist/MANIFEST.tsv" ]; then
	WANT=$(awk -F'\t' -v f="usque-linux-${GOARCH}" '$1 == f { print $5 }' "$ROOT/dist/MANIFEST.tsv")
	if [ -n "$WANT" ] && [ "$WANT" != "$SUM" ]; then
		echo "[!] 警告：$BIN 的 sha256 与 dist/MANIFEST.tsv 不一致" >&2
		echo "    manifest: $WANT" >&2
		echo "    actual  : $SUM" >&2
	fi
fi

[ -f "$OUT" ] && rm -f "$OUT"

"$APK_STATIC" mkpkg \
	--info "name:usque" \
	--info "version:${VER}-r${REL}" \
	--info "arch:${APKARCH}" \
	--info "license:MIT" \
	--info "description:Cloudflare WARP (MASQUE) client with procd service and routing hooks" \
	--info "depends:kmod-tun" \
	--info "depends:ip-full" \
	--info "depends:ca-bundle" \
	--files "$PKG" \
	--output "$OUT"

echo
echo "已生成 $OUT"
[ -n "$SUM" ] && echo "二进制 sha256: $SUM"
echo "文件清单（$PKG）："
(cd "$PKG" && ls -1R)
echo
echo "安装（与 LuCI 包一起，示例）："
echo "  apk add --allow-untrusted $OUT $ROOT/dist/luci-app-usque-1.1.0-r1.all.apk"
echo "  /etc/init.d/rpcd restart && rm -rf /tmp/luci-*"
