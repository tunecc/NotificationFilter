ARCHS = arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard

THEOS_DEVICE_IP = localhost
MODULE_CACHE_DIR = $(CURDIR)/.cache/clang/ModuleCache

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ShortcutsTimeoutBlocker

ShortcutsTimeoutBlocker_FILES = Tweak.xm
ShortcutsTimeoutBlocker_CFLAGS = -fobjc-arc -fmodules-cache-path=$(MODULE_CACHE_DIR)
ShortcutsTimeoutBlocker_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
