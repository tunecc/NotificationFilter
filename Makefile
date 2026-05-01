ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

THEOS_DEVICE_IP = localhost

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += NotificationFilterTweak NotificationFilterPrefs

include $(THEOS_MAKE_PATH)/aggregate.mk

.PHONY: package-rootful install-rootful package-debug-rootful install-debug-rootful package-rootless install-rootless package-debug-rootless install-debug-rootless package-all

package-rootful:
	$(MAKE) FINALPACKAGE=1 clean all package

install-rootful:
	$(MAKE) FINALPACKAGE=1 clean all do

package-debug-rootful:
	$(MAKE) clean all package

install-debug-rootful:
	$(MAKE) clean all do

package-rootless:
	$(MAKE) THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1 clean all package

install-rootless:
	$(MAKE) THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1 clean all do

package-debug-rootless:
	$(MAKE) THEOS_PACKAGE_SCHEME=rootless clean all package

install-debug-rootless:
	$(MAKE) THEOS_PACKAGE_SCHEME=rootless clean all do

package-all:
	$(MAKE) package-rootful
	$(MAKE) package-rootless
