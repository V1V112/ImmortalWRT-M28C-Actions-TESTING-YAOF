#
# 使用 PikuZheng/smartdns 的预编译 SmartDNS 后端。
#
# OpenWrt/ImmortalWrt 25.12 仍会把这里的内容重新打包成目标固件使用的
# 软件包格式。这里继续使用 IPK 作为稳定的 tar 容器，因为上游 APK v3
# 软件包需要 apk-tools 才能解包。
#

include $(TOPDIR)/rules.mk

PKG_NAME:=smartdns-prebuilt
PKG_VERSION:=1.2026.48.1.5
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=PikuZheng
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)-$(PKG_RELEASE)

SMARTDNS_UPSTREAM_VERSION:=1.2026.v48.1.5
SMARTDNS_RELEASE_TAG:=1.2026.v48.1.5_with_ui
SMARTDNS_RELEASE_URL:=https://github.com/PikuZheng/smartdns/releases/download/$(SMARTDNS_RELEASE_TAG)

SMARTDNS_PREBUILT_FILE:=smartdns_with_ui.$(SMARTDNS_UPSTREAM_VERSION).aarch64.ipk
SMARTDNS_PREBUILT_HASH:=ca88de7d3c7f356ddbdbbcc33c22a911174e558f58fca97f5b1e96e43eb320a2

# PikuZheng 的 with_ui IPK 会把 SmartDNS 后端和内置面板都打进 smartdns 包。
# LuCI 包源保持独立，确保现有 profile 中的 luci-app-smartdns 包名仍能解析。
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
  TITLE:=预编译 SmartDNS 服务端
  URL:=https://github.com/PikuZheng/smartdns
  DEPENDS:=@(aarch64) +libc +libopenssl +libpthread +zlib
endef

define Package/smartdns/description
来自 PikuZheng/smartdns 的 aarch64 OpenWrt SmartDNS 预编译包。
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
  TITLE:=SmartDNS 的 LuCI 管理界面
  URL:=https://github.com/pymumu/smartdns
  DEPENDS:=+luci-base +smartdns
endef

define Package/luci-app-smartdns/description
来自 pymumu/smartdns 的 SmartDNS 预编译 LuCI 应用。
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
