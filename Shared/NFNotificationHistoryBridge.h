#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const NFNotificationHistoryMessagingCenterName;
extern NSString * const NFNotificationHistoryFetchMessageName;
extern NSString * const NFNotificationHistoryBundleIdentifierKey;
extern NSString * const NFNotificationHistoryLimitKey;
extern NSString * const NFNotificationHistoryEntriesKey;
extern NSString * const NFNotificationHistoryErrorKey;
extern NSString * const NFNotificationHistorySourceKey;

extern NSString * const NFNotificationHistorySourceLive;
extern NSString * const NFNotificationHistorySourceMirror;

FOUNDATION_EXPORT NSString *NFNotificationHistorySnapshotFilePath(void);

NS_ASSUME_NONNULL_END
