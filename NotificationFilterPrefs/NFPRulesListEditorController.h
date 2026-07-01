#import <UIKit/UIKit.h>
#import "NFPMultilineRulesEditorController.h"

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^NFPScannedRuleMergeHandler)(NFPRuleEditorKind targetKind, NSArray<NSDictionary *> *entries, NSError **error);
typedef NSArray<NSDictionary *> * _Nonnull (^NFPRulesReloadHandler)(NFPRuleEditorKind editorKind);

@interface NFPRulesListEditorController : UITableViewController

- (instancetype)initWithTitle:(NSString *)title
                   editorKind:(NFPRuleEditorKind)editorKind
                        rules:(NSArray *)rules
                  saveHandler:(void (^)(NSArray *rules))saveHandler;

- (instancetype)initWithTitle:(NSString *)title
                   editorKind:(NFPRuleEditorKind)editorKind
                        rules:(NSArray *)rules
             bundleIdentifier:(NSString * _Nullable)bundleIdentifier
                  displayName:(NSString * _Nullable)displayName
                      ruleMode:(NSString * _Nullable)ruleMode
                  saveHandler:(void (^)(NSArray *rules))saveHandler
       scannedRuleMergeHandler:(NFPScannedRuleMergeHandler _Nullable)scannedRuleMergeHandler
             rulesReloadHandler:(NFPRulesReloadHandler _Nullable)rulesReloadHandler;

@end

NS_ASSUME_NONNULL_END
