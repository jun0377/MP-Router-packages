#
# Copyright (C) 2016 Shuanglei Tao <tsl0922@gmail.com>
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=serialnumber
PKG_RELEASE:=1.0


PKG_MAINTAINER:=jun <525697019@qq.com>
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/serialnumber
	SECTION:=utils
	CATEGORY:=Utilities
	TITLE:=Serial number management over the web
	DEPENDS:=
endef

define Package/serialnumber/description
serialnumber is a Serial number management over the web
endef

define Package/serialnumber/conffiles
/etc/config/serialnumber
endef

define Build/Prepare
	$(call Build/Prepare/Default)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
  $(TARGET_CC) $(TARGET_CFLAGS) \
                -o $(PKG_BUILD_DIR)/serialnumber $(PKG_BUILD_DIR)/serialnumber.c
endef

define Package/serialnumber/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/serialnumber $(1)/usr/bin/
endef

$(eval $(call BuildPackage,serialnumber))