MODULE_CACHE_DIR = $(THEOS_OBJ_DIR)/ModuleCache.noindex

include $(THEOS_MAKE_PATH)/common.mk

TWEAK_NAME = NotificationFilter

NotificationFilter_FILES = \
	Tweak.xm \
	NFNotificationRecord.m \
	NFRuleEngine.m \
	../Shared/NFPreferences.m \
	../Shared/NFLogStore.m

NotificationFilter_CFLAGS = -fobjc-arc -fmodules-cache-path=$(MODULE_CACHE_DIR)
NotificationFilter_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
