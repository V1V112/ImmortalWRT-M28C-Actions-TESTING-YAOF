#
# Prebuilt SmartDNS backend from PikuZheng/smartdns.
#
# OpenWrt/ImmortalWrt 25.12 still repackages this into the target package
# format for the final image. The IPK files are used only as stable tar
# containers here, because upstream APK v3 packages need apk-tools to extract.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=smartdns-prebuilt
PKG_VERSION:=1.2026.v48.1.5
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=PikuZheng
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)-$(PKG_RELEASE)

SMARTDNS_RELEASE_TAG:=1.2026.v48.1.5_with_ui
SMARTDNS_RELEASE_URL:=https://github.com/PikuZheng/smartdns/releases/download/$(SMARTDNS_RELEASE_TAG)

SMARTDNS_PREBUILT_FILE:=smartdns_with_ui.$(PKG_VERSION).aarch64.ipk
SMARTDNS_PREBUILT_HASH:=ca88de7d3c7f356ddbdbbcc33c22a911174e558f58fca97f5b1e96e43eb320a2

# PikuZheng's with_ui IPK ships the SmartDNS backend/dashboard as smartdns.
# Keep the LuCI package source separate so the existing profile package name
# luci-app-smartdns still resolves.
LUCI_SMARTDNS_RELEASE_TAG:=Release48.1
LUCI_SMARTDNS_RELEASE_URL:=https://github.com/pymumu/smartdns/releases/download/$(LUCI_SMARTDNS_RELEASE_TAG)
LUCI_SMARTDNS_PREBUILT_VERSION:=1.2026.06.07-1153
LUCI_SMARTDNS_PREBUILT_FILE:=luci-app-smartdns.$(LUCI_SMARTDNS_PREBUILT_VERSION).all-luci-all.ipk
LUCI_SMARTDNS_PREBUILT_HASH:=ad83db947bbefb1702ce15b1006266efc5d414e2f8645022671246a2c5faf80f

include $(INCLUDE_DIR)/package.mk

define Download/smartdns-prebuilt
  FILE:=$(SMARTDNS_PREBUILT_FILE)
  URL:=$(SMARTDNS_RELEASE_URL)
  HASH:=$(SMARTDNS_PREBUILT_HASH)
endef
$(eval $(call Download,smartdns-prebuilt))

define Download/luci-app-smartdns-prebuilt
  FILE:=$(LUCI_SMARTDNS_PREBUILT_FILE)
  URL:=$(LUCI_SMARTDNS_RELEASE_URL)
  HASH:=$(LUCI_SMARTDNS_PREBUILT_HASH)
endef
$(eval $(call Download,luci-app-smartdns-prebuilt))

define Package/smartdns
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=IP Addresses and Names
  TITLE:=prebuilt smartdns server
  URL:=https://github.com/PikuZheng/smartdns
  DEPENDS:=@(aarch64) +libc +libopenssl +libpthread +zlib
endef

define Package/smartdns/description
Prebuilt aarch64 OpenWrt SmartDNS package from PikuZheng/smartdns.
endef

define Package/smartdns/conffiles
/etc/config/smartdns
/etc/smartdns/address.conf
/etc/smartdns/blacklist-ip.conf
/etc/smartdns/custom.conf
/etc/smartdns/domain-block.list
/etc/smartdns/domain-forwarding.list
endef

define Package/luci-app-smartdns
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI for smartdns
  URL:=https://github.com/pymumu/smartdns
  DEPENDS:=+luci-base +smartdns
endef

define Package/luci-app-smartdns/description
Prebuilt LuCI app for SmartDNS from pymumu/smartdns.
endef

define Build/Prepare
	$(RM) -r $(PKG_BUILD_DIR)
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/smartdns-pkg $(PKG_BUILD_DIR)/smartdns-root
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/luci-pkg $(PKG_BUILD_DIR)/luci-root
	$(TAR) -xzf $(DL_DIR)/$(SMARTDNS_PREBUILT_FILE) -C $(PKG_BUILD_DIR)/smartdns-pkg ./data.tar.gz
	$(TAR) -xzf $(PKG_BUILD_DIR)/smartdns-pkg/data.tar.gz -C $(PKG_BUILD_DIR)/smartdns-root
	$(TAR) -xzf $(DL_DIR)/$(LUCI_SMARTDNS_PREBUILT_FILE) -C $(PKG_BUILD_DIR)/luci-pkg ./data.tar.gz
	$(TAR) -xzf $(PKG_BUILD_DIR)/luci-pkg/data.tar.gz -C $(PKG_BUILD_DIR)/luci-root
endef

define Build/Compile
endef

define Package/smartdns/install
	$(CP) $(PKG_BUILD_DIR)/smartdns-root/* $(1)/
endef

define Package/luci-app-smartdns/install
	$(CP) $(PKG_BUILD_DIR)/luci-root/* $(1)/
endef

$(eval $(call BuildPackage,smartdns))
$(eval $(call BuildPackage,luci-app-smartdns))
