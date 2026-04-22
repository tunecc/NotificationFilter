#import <Foundation/Foundation.h>
#import "NFPMultilineRulesEditorController.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSBundle *NFPPrefsBundle(void);
FOUNDATION_EXPORT NSString *NFPLocalizedString(NSString *key);
FOUNDATION_EXPORT NSString *NFPLocalizedRuleEditorTitle(NFPRuleEditorKind editorKind);
FOUNDATION_EXPORT NSString *NFPLocalizedScopeName(NSString *scope);
FOUNDATION_EXPORT NSString *NFPLocalizedMatchModeName(NSString *mode);
FOUNDATION_EXPORT NSString *NFPLocalizedDeleteStatusName(NSString *status);
FOUNDATION_EXPORT NSString *NFPLocalizedDeleteMethodSummary(NSString *methods);

NS_ASSUME_NONNULL_END
