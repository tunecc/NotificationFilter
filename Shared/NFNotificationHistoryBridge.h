#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const NFNotificationHistoryRefreshRequestNotification;
extern NSString * const NFNotificationHistoryRefreshCompletedNotification;
extern NSString * const NFNotificationHistoryRequestIdentifierKey;
extern NSString * const NFNotificationHistoryBundleIdentifierKey;
extern NSString * const NFNotificationHistoryLimitKey;
extern NSString * const NFNotificationHistoryErrorKey;
extern NSString * const NFNotificationHistorySourceKey;
extern NSString * const NFNotificationHistoryUpdatedAtKey;

extern NSString * const NFNotificationHistorySourceLive;
extern NSString * const NFNotificationHistorySourceMirror;

// 全局扫描请求专用标识：写入 request 的 bundleIdentifier 时表示「请求全部应用」。
// 与单应用请求（非空 bundleIdentifier）互斥；空字符串仍视为非法请求。
extern NSString * const NFNotificationHistoryAllAppsIdentifier;

FOUNDATION_EXPORT NSString *NFNotificationHistorySnapshotFilePath(void);
FOUNDATION_EXPORT NSString *NFNotificationHistoryRefreshRequestFilePath(void);
FOUNDATION_EXPORT NSString *NFNotificationHistoryRefreshStatusFilePath(void);

NS_ASSUME_NONNULL_END
