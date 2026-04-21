#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NFPPerAppRulesController : UITableViewController

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier displayName:(NSString *)displayName;

@end

NS_ASSUME_NONNULL_END
