#import <UIKit/UIKit.h>
#import "NFPMultilineRulesEditorController.h"

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^NFPNotificationRuleScannerCommitHandler)(NFPRuleEditorKind targetKind, NSArray<NSDictionary *> *entries, NSError **error);

@interface NFPNotificationRuleScannerController : UITableViewController

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
                             displayName:(NSString *)displayName
                         initialRuleKind:(NFPRuleEditorKind)initialRuleKind
                    returnViewController:(UIViewController * _Nullable)returnViewController
                           commitHandler:(NFPNotificationRuleScannerCommitHandler)commitHandler;

@end

NS_ASSUME_NONNULL_END
