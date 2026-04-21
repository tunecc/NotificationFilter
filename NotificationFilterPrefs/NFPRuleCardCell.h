#import <UIKit/UIKit.h>
#import "NFPMultilineRulesEditorController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NFPRuleValidationState) {
    NFPRuleValidationStateNone = 0,
    NFPRuleValidationStateValid,
    NFPRuleValidationStateInvalid
};

@interface NFPRuleCardCell : UITableViewCell

- (void)configureWithRuleEntry:(NSDictionary *)ruleEntry
                    editorKind:(NFPRuleEditorKind)editorKind
               validationState:(NFPRuleValidationState)validationState
                   editingMode:(BOOL)editingMode
                      selected:(BOOL)selected
                 toggleHandler:(void (^)(BOOL enabled))toggleHandler
              selectionHandler:(void (^)(void))selectionHandler;

@end

NS_ASSUME_NONNULL_END
