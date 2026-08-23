#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NFPAppRulesExportPickerController : UITableViewController <UISearchResultsUpdating>

- (instancetype)initWithSelectedBundleIdentifiers:(NSArray<NSString *> *)selectedBundleIdentifiers
                                     selectionHandler:(void (^)(NSArray<NSString *> *selectedBundleIdentifiers))selectionHandler;

@end

NS_ASSUME_NONNULL_END
