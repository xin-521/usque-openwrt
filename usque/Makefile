include $(TOPDIR)/rules.mk

PKG_NAME:=usque
PKG_VERSION:=4.2.1
PKG_RELEASE:=7

PKG_LICENSE:=MIT
PKG_MAINTAINER:=usque-openwrt contributors

include $(INCLUDE_DIR)/package.mk

# Map the OpenWrt target architecture to the prebuilt Go binary name.
# Override with: make ... USQUE_GOARCH=armv6
USQUE_GOARCH?=
ifeq ($(strip $(USQUE_GOARCH)),)
  ifeq ($(ARCH),aarch64)
    USQUE_GOARCH:=arm64
  else ifeq ($(ARCH),arm)
    ifneq ($(filter cortex-a5% cortex-a7% cortex-a8% cortex-a9% cortex-a15%,$(CPU_TYPE)),)
      USQUE_GOARCH:=armv7
    else ifneq ($(filter arm1176% arm_1176%,$(CPU_TYPE)),)
      USQUE_GOARCH:=armv6
    else ifneq ($(filter arm926% fa526 xscale mpcore,$(CPU_TYPE)),)
      USQUE_GOARCH:=armv5
    else
      USQUE_GOARCH:=armv7
    endif
  else ifeq ($(ARCH),i386)
    ifneq ($(filter y,$(CONFIG_x86_64) $(CONFIG_TARGET_x86_64)),)
      USQUE_GOARCH:=amd64
    else ifneq ($(filter x86_64%,$(ARCH_PACKAGES)),)
      USQUE_GOARCH:=amd64
    else
      USQUE_GOARCH:=386
    endif
  else ifeq ($(ARCH),mipsel)
    ifeq ($(CONFIG_SOFT_FLOAT),y)
      USQUE_GOARCH:=mipsle-softfloat
    else
      USQUE_GOARCH:=mipsle
    endif
  else ifeq ($(ARCH),mips)
    ifeq ($(CONFIG_SOFT_FLOAT),y)
      USQUE_GOARCH:=mips-softfloat
    else
      USQUE_GOARCH:=mips
    endif
  else ifeq ($(ARCH),mips64el)
    USQUE_GOARCH:=mips64le
  else ifeq ($(ARCH),mips64)
    USQUE_GOARCH:=mips64
  else ifeq ($(ARCH),riscv64)
    USQUE_GOARCH:=riscv64
  else ifeq ($(ARCH),loongarch64)
    USQUE_GOARCH:=loong64
  endif
endif

# Prebuilt binary location. Stage dist/bin/usque-linux-* into usque/files/ or
# point USQUE_BIN at the file directly.
USQUE_BIN?=$(CURDIR)/files/usque-linux-$(USQUE_GOARCH)

define Package/usque
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Cloudflare WARP client using MASQUE (usque)
  URL:=https://github.com/Diniboy1123/usque
  DEPENDS:=+kmod-tun +ip-full +ca-bundle
endef

define Package/usque/description
  Unofficial Cloudflare WARP client that implements the MASQUE protocol and
  exposes the tunnel as a native TUN device. Includes the procd service, the
  on-connect/on-disconnect routing hooks and the UCI configuration used by
  luci-app-usque.
endef

define Package/usque/conffiles
/etc/config/usque
/etc/usque/options.sh
endef

define Build/Compile
endef

define Package/usque/install
	@if [ ! -f "$(USQUE_BIN)" ]; then \
		echo "ERROR: prebuilt binary not found: $(USQUE_BIN)"; \
		echo "  stage dist/bin/usque-linux-$(USQUE_GOARCH) into usque/files/"; \
		echo "  or run: make ... USQUE_BIN=/path/to/usque"; \
		exit 1; \
	fi
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(USQUE_BIN) $(1)/usr/bin/usque
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/usque $(1)/etc/init.d/usque
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/usque $(1)/etc/config/usque
	$(INSTALL_DIR) $(1)/etc/usque
	$(INSTALL_BIN) ./root/etc/usque/up.sh $(1)/etc/usque/up.sh
	$(INSTALL_BIN) ./root/etc/usque/down.sh $(1)/etc/usque/down.sh
	$(INSTALL_DATA) ./root/etc/usque/options.sh $(1)/etc/usque/options.sh
	$(INSTALL_DIR) $(1)/etc/sysctl.d
	$(INSTALL_DATA) ./root/etc/sysctl.d/90-usque.conf $(1)/etc/sysctl.d/90-usque.conf
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./root/usr/libexec/usque-routing $(1)/usr/libexec/usque-routing
endef

$(eval $(call BuildPackage,usque))
