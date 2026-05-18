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

FOUNDATION_EXPORT NSString *NFNotificationHistorySnapshotFilePath(void);
FOUNDATION_EXPORT NSString *NFNotificationHistoryRefreshRequestFilePath(void);
FOUNDATION_EXPORT NSString *NFNotificationHistoryRefreshStatusFilePath(void);

NS_ASSUME_NONNULL_END
