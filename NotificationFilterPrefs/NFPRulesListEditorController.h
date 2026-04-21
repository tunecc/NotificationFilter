#import <UIKit/UIKit.h>
#import "NFPMultilineRulesEditorController.h"

NS_ASSUME_NONNULL_BEGIN

@interface NFPRulesListEditorController : UITableViewController

- (instancetype)initWithTitle:(NSString *)title
                   editorKind:(NFPRuleEditorKind)editorKind
                        rules:(NSArray *)rules
                  saveHandler:(void (^)(NSArray *rules))saveHandler;

@end

NS_ASSUME_NONNULL_END
