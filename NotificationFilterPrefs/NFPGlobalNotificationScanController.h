#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 全局扫描页：读取通知中心全部应用的通知，按应用分组展示，
// 点条目直接进入既有 token picker 生成规则并写入对应应用。
@interface NFPGlobalNotificationScanController : UITableViewController

@end

NS_ASSUME_NONNULL_END
