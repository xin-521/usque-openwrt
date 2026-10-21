include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for usque (Cloudflare WARP / MASQUE)
LUCI_DESCRIPTION:=Web UI, UCI configuration and ubus API for the usque nativetun daemon
LUCI_DEPENDS:=+luci-base +rpcd-mod-ucode +ucode-mod-fs +usque
LUCI_PKGARCH:=all
LUCI_LANG.zh_Hans:=简体中文

PKG_VERSION:=1.1.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=usque-openwrt contributors

include ../../luci.mk

# call BuildPackage - OpenWrt buildroot signature
