#import <UIKit/UIKit.h>
#import "NFPMultilineRulesEditorController.h"

NS_ASSUME_NONNULL_BEGIN

@interface NFPRuleTextEditorController : UIViewController

- (instancetype)initWithTitle:(NSString *)title
                  placeholder:(NSString *)placeholder
                  initialRule:(NSString * _Nullable)initialRule
                   editorKind:(NFPRuleEditorKind)editorKind
                  saveHandler:(void (^)(NSString *rule))saveHandler;

@end

NS_ASSUME_NONNULL_END
