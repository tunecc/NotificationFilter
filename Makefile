ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

THEOS_DEVICE_IP = localhost

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += NotificationFilterTweak NotificationFilterPrefs

include $(THEOS_MAKE_PATH)/aggregate.mk

.PHONY: package-roothide install-roothide package-debug-roothide install-debug-roothide package-rootless install-rootless

package-roothide:
	$(MAKE) clean package THEOS_PACKAGE_SCHEME=roothide FINALPACKAGE=1

install-roothide:
	$(MAKE) clean do THEOS_PACKAGE_SCHEME=roothide FINALPACKAGE=1

package-debug-roothide:
	$(MAKE) clean package THEOS_PACKAGE_SCHEME=roothide

install-debug-roothide:
	$(MAKE) clean do THEOS_PACKAGE_SCHEME=roothide

package-rootless:
	$(MAKE) clean package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1

install-rootless:
	$(MAKE) clean do THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1
