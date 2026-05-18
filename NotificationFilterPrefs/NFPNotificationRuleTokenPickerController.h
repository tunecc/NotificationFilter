#import <UIKit/UIKit.h>
#import "NFPMultilineRulesEditorController.h"

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^NFPNotificationRuleTokenCommitHandler)(NFPRuleEditorKind targetKind, NSArray<NSDictionary *> *entries, NSError **error);

typedef NS_ENUM(NSInteger, NFPNotificationRuleTokenReturnMode) {
    NFPNotificationRuleTokenReturnModeRulesList = 0,
    NFPNotificationRuleTokenReturnModeTargetViewController
};

@interface NFPNotificationRuleTokenPickerController : UIViewController

- (instancetype)initWithNotificationEntry:(NSDictionary *)entry
                          appDisplayName:(NSString *)appDisplayName
                          initialRuleKind:(NFPRuleEditorKind)initialRuleKind
                     returnViewController:(UIViewController * _Nullable)returnViewController
                            commitHandler:(NFPNotificationRuleTokenCommitHandler)commitHandler;

- (instancetype)initWithNotificationEntry:(NSDictionary *)entry
                          appDisplayName:(NSString *)appDisplayName
                          initialRuleKind:(NFPRuleEditorKind)initialRuleKind
                     returnViewController:(UIViewController * _Nullable)returnViewController
                               returnMode:(NFPNotificationRuleTokenReturnMode)returnMode
                            commitHandler:(NFPNotificationRuleTokenCommitHandler)commitHandler;

@end

NS_ASSUME_NONNULL_END
