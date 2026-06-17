#
# Prebuilt SmartDNS payloads from pymumu/smartdns Release48.1.
#
# OpenWrt/ImmortalWrt 25.12 still repackages this into the target package
# format for the final image. The IPK files are used only as stable tar
# containers here, because upstream APK v3 packages need apk-tools to extract.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=smartdns-prebuilt
PKG_VERSION:=1.2026.06.07
PKG_RELEASE:=1153

PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=Nick Peng <pymumu@gmail.com>
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)-$(PKG_RELEASE)

SMARTDNS_RELEASE_TAG:=Release48.1
SMARTDNS_RELEASE_URL:=https://github.com/pymumu/smartdns/releases/download/$(SMARTDNS_RELEASE_TAG)
SMARTDNS_PREBUILT_VERSION:=$(PKG_VERSION)-$(PKG_RELEASE)

SMARTDNS_PREBUILT_FILE:=smartdns.$(SMARTDNS_PREBUILT_VERSION).aarch64-openwrt-all.ipk
SMARTDNS_PREBUILT_HASH:=f3e9787e4e1c8f35983d3df160789e9ef68fbdea76b71541c37c594716a2bfc9
LUCI_SMARTDNS_PREBUILT_FILE:=luci-app-smartdns.$(SMARTDNS_PREBUILT_VERSION).all-luci-all.ipk
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
  URL:=$(SMARTDNS_RELEASE_URL)
  HASH:=$(LUCI_SMARTDNS_PREBUILT_HASH)
endef
$(eval $(call Download,luci-app-smartdns-prebuilt))

define Package/smartdns
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=IP Addresses and Names
  TITLE:=prebuilt smartdns server
  URL:=https://github.com/pymumu/smartdns
  DEPENDS:=@(aarch64) +libc
endef

define Package/smartdns/description
Prebuilt aarch64 OpenWrt SmartDNS package from pymumu/smartdns.
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
