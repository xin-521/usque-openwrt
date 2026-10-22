#!/bin/sh
# =============================================================================
#  build-luci-apk.sh —— 在没有 buildroot/SDK 的 Linux 上手工打包 LuCI 应用
#
#  需要 apk-tools 的静态二进制（apk.static）：
#    https://gitlab.alpinelinux.org/api/v4/projects/5/packages/generic/apk-tools/<ver>/<arch>/apk.static
#
#  用法（在 Linux / WSL 中运行；Windows 原生 Git Bash 无法保证文件模式）：
#    APK_STATIC=/path/to/apk.static sh tools/build-luci-apk.sh          # arch=all
#    APK_STATIC=/path/to/apk.static sh tools/build-luci-apk.sh x86_64   # 指定架构
#
#  可选：安装 po2lmo 后会把 po/zh_Hans/usque.po 编译成 lmo 一起打包。
#
#  产物：dist/luci-app-usque-<ver>-r<rel>.<arch>.apk
# =============================================================================
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
SRC="$ROOT/luci-app-usque"

NAME=luci-app-usque
VER=1.1.3
REL=1
# apk v3 uses "noarch" for architecture-independent packages; "all" is not
# a valid apk arch and makes the package uninstallable.
ARCH=${1:-noarch}
[ "$ARCH" = all ] && ARCH=noarch

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

[ -d "$SRC/root" ] || { echo "找不到 $SRC/root" >&2; exit 1; }

STAGE="$ROOT/temp/luci-apk-stage"
PKG="$STAGE/pkgroot"
OUT="$ROOT/dist/${NAME}-${VER}-r${REL}.${ARCH}.apk"

rm -rf "$STAGE"
mkdir -p "$PKG" "$ROOT/dist"

# 1) root/ 即设备根目录
cp -R "$SRC/root/." "$PKG/"

# 2) htdocs/ → /www/luci-static/...
mkdir -p "$PKG/www"
cp -R "$SRC/htdocs/." "$PKG/www/"

# 3) 可选：翻译
if command -v po2lmo >/dev/null 2>&1; then
	mkdir -p "$PKG/usr/lib/lua/luci/i18n"
	po2lmo "$SRC/po/zh_Hans/usque.po" "$PKG/usr/lib/lua/luci/i18n/usque.zh-cn.lmo"
	echo "已编译 zh_Hans 翻译"
else
	echo "[!] 未找到 po2lmo，跳过中文翻译（界面回退英文）" >&2
fi

# 4) 文件权限（源码里的可执行位在 Windows 上不可靠，这里显式设置）
chmod 755 "$PKG/usr/share/rpcd/ucode/luci.usque"
chmod 755 "$PKG/etc/uci-defaults/95-luci-app-usque"
chmod 644 "$PKG"/usr/share/luci/menu.d/*.json "$PKG"/usr/share/rpcd/acl.d/*.json

# 4b) post-install：rpcd 只在启动时加载 /usr/share/rpcd/ucode/*，
#     不重启的话 luci.usque 这个 ubus 对象根本不存在，界面会报
#     「未找到 usque 可执行文件」（实际是 ubus 调用 Not found）。
mkdir -p "$STAGE/scripts"
cat > "$STAGE/scripts/post-install" <<'EOS'
#!/bin/sh
[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd restart >/dev/null 2>&1
exit 0
EOS
chmod 755 "$STAGE/scripts/post-install"

MODEBAD=0
for f in usr/share/rpcd/ucode/luci.usque etc/uci-defaults/95-luci-app-usque; do
	[ -x "$PKG/$f" ] || { echo "[!] 缺少可执行位：/$f" >&2; MODEBAD=1; }
done
if [ "$MODEBAD" = 1 ]; then
	echo "ERROR: 当前文件系统未保留可执行位（常见于 Windows/Git Bash）。" >&2
	echo "       请在 Linux/WSL 或路由器上运行本脚本。" >&2
	[ "${ALLOW_BAD_MODES:-0}" = 1 ] || exit 1
	echo "[!] ALLOW_BAD_MODES=1：继续打包，安装后必须手动 chmod 755 相关文件。" >&2
fi

# 5) 打包（apk-tools 3.x：依赖用 --info depends:，文件用 --files）
RM_OUT=0
[ -f "$OUT" ] && RM_OUT=1
[ "$RM_OUT" = 1 ] && rm -f "$OUT"

"$APK_STATIC" mkpkg \
	--info "name:${NAME}" \
	--info "version:${VER}-r${REL}" \
	--info "arch:${ARCH}" \
	--info "license:Apache-2.0" \
	--info "description:LuCI support for usque (Cloudflare WARP / MASQUE)" \
	--info "depends:luci-base" \
	--info "depends:rpcd-mod-ucode" \
	--info "depends:ucode-mod-fs" \
	--info "depends:usque" \
	--script "post-install:$STAGE/scripts/post-install" \
	--files "$PKG" \
	--output "$OUT"

echo
echo "已生成 $OUT"
echo "文件清单（$PKG）："
(cd "$PKG" && ls -1R)
echo
echo "安装前建议解包核对权限："
echo "  mkdir -p /tmp/chk && cd /tmp/chk && apk extract --allow-untrusted '$OUT' && ls -laR"
