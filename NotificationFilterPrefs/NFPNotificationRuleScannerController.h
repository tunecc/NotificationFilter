#import <UIKit/UIKit.h>
#import "NFPMultilineRulesEditorController.h"
#import "NFPNotificationRuleTokenPickerController.h"

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^NFPNotificationRuleScannerCommitHandler)(NFPRuleEditorKind targetKind, NSArray<NSDictionary *> *entries, NSError **error);

@interface NFPNotificationRuleScannerController : UITableViewController

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
                             displayName:(NSString *)displayName
                         initialRuleKind:(NFPRuleEditorKind)initialRuleKind
                                 ruleMode:(NSString * _Nullable)ruleMode
                    returnViewController:(UIViewController * _Nullable)returnViewController
                           commitHandler:(NFPNotificationRuleScannerCommitHandler)commitHandler;

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
                             displayName:(NSString *)displayName
                         initialRuleKind:(NFPRuleEditorKind)initialRuleKind
                                 ruleMode:(NSString * _Nullable)ruleMode
                    returnViewController:(UIViewController * _Nullable)returnViewController
                              returnMode:(NFPNotificationRuleTokenReturnMode)returnMode
                           commitHandler:(NFPNotificationRuleScannerCommitHandler)commitHandler;

@end

NS_ASSUME_NONNULL_END
