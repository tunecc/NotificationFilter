#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NFPRuleEditorKind) {
    NFPRuleEditorKindContains = 0,
    NFPRuleEditorKindExclude,
    NFPRuleEditorKindRegex
};

@interface NFPMultilineRulesEditorController : UIViewController

- (instancetype)initWithTitle:(NSString *)title
                  initialText:(NSString *)initialText
                   editorKind:(NFPRuleEditorKind)editorKind
                  saveHandler:(void (^)(NSArray<NSString *> *rules))saveHandler;

@end

NS_ASSUME_NONNULL_END
