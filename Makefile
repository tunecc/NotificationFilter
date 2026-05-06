ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

THEOS_DEVICE_IP = localhost

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += NotificationFilterTweak NotificationFilterPrefs

include $(THEOS_MAKE_PATH)/aggregate.mk

.PHONY: build-packages package-rootful install-rootful package-debug-rootful install-debug-rootful package-rootless install-rootless package-debug-rootless install-debug-rootless package-roothide package-all

build-packages:
	bash scripts/build_packages.sh

package-rootful:
	bash scripts/build_packages.sh rootful

install-rootful:
	$(MAKE) FINALPACKAGE=1 clean all do

package-debug-rootful:
	$(MAKE) clean all package

install-debug-rootful:
	$(MAKE) clean all do

package-rootless:
	bash scripts/build_packages.sh rootless

install-rootless:
	$(MAKE) THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1 clean all do

package-debug-rootless:
	$(MAKE) THEOS_PACKAGE_SCHEME=rootless clean all package

install-debug-rootless:
	$(MAKE) THEOS_PACKAGE_SCHEME=rootless clean all do

package-roothide:
	bash scripts/build_packages.sh roothide

package-all: build-packages
