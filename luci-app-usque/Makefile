include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for usque (Cloudflare WARP / MASQUE)
LUCI_DESCRIPTION:=Web UI, UCI configuration and ubus API for the usque nativetun daemon
LUCI_DEPENDS:=+luci-base +rpcd-mod-ucode +ucode-mod-fs +usque
LUCI_PKGARCH:=all
LUCI_LANG.zh_Hans:=简体中文

PKG_VERSION:=1.2.0
PKG_RELEASE:=4
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=usque-openwrt contributors

include ../../luci.mk

# The ubus object lives in /usr/share/rpcd/ucode/luci.usque and is only loaded
# when rpcd starts. Without this the UI reports "usque binary not found"
# because every luci.usque call returns "Not found" until rpcd is restarted.
# buildroot registers this postinst body as both post-install and post-upgrade
# (see include/package-pack.mk), so it runs on upgrades as well;
# tools/build-luci-apk.sh registers the same file under both script names.
define Package/luci-app-usque/postinst
#!/bin/sh
[ -x /etc/uci-defaults/95-luci-app-usque ] && {
	/etc/uci-defaults/95-luci-app-usque >/dev/null 2>&1
	rm -f /etc/uci-defaults/95-luci-app-usque
}
[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd restart >/dev/null 2>&1
exit 0
endef

# call BuildPackage - OpenWrt buildroot signature
