MODULE_CACHE_DIR = $(THEOS_OBJ_DIR)/ModuleCache.noindex

include $(THEOS_MAKE_PATH)/common.mk

BUNDLE_NAME = NotificationFilterPrefs

NotificationFilterPrefs_FILES = \
	NFPRootListController.m \
	NFPAppInfoProvider.m \
	NFPGlobalRulesController.m \
	NFPAppRulesListController.m \
	NFPPerAppRulesController.m \
	NFPMultilineRulesEditorController.m \
	NFPRuleCardCell.m \
	NFPRuleTextEditorController.m \
	NFPRulesListEditorController.m \
	NFPJSONImportController.m \
	NFPImportExportController.m \
	NFPLogsListController.m \
	NFPLogDetailController.m \
	../Shared/NFPreferences.m \
	../Shared/NFLogStore.m

NotificationFilterPrefs_FRAMEWORKS = UIKit Foundation MobileCoreServices
NotificationFilterPrefs_INSTALL_PATH = /Library/PreferenceBundles
NotificationFilterPrefs_CFLAGS = -fobjc-arc -fmodules-cache-path=$(MODULE_CACHE_DIR) -Wno-error=deprecated-declarations
NotificationFilterPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk
