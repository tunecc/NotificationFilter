#import "NFNotificationHistoryBridge.h"

NSString * const NFNotificationHistoryRefreshRequestNotification = @"com.tune.notificationfilter.history/refresh-request";
NSString * const NFNotificationHistoryRefreshCompletedNotification = @"com.tune.notificationfilter.history/refresh-completed";
NSString * const NFNotificationHistoryRequestIdentifierKey = @"requestID";
NSString * const NFNotificationHistoryBundleIdentifierKey = @"bundleIdentifier";
NSString * const NFNotificationHistoryLimitKey = @"limit";
NSString * const NFNotificationHistoryErrorKey = @"error";
NSString * const NFNotificationHistorySourceKey = @"source";
NSString * const NFNotificationHistoryUpdatedAtKey = @"updatedAt";

NSString * const NFNotificationHistorySourceLive = @"live";
NSString * const NFNotificationHistorySourceMirror = @"mirror";

NSString *NFNotificationHistorySnapshotFilePath(void) {
    return @"/var/mobile/Library/Preferences/com.tune.notificationfilter.history.plist";
}

NSString *NFNotificationHistoryRefreshRequestFilePath(void) {
    return @"/var/mobile/Library/Preferences/com.tune.notificationfilter.history-request.plist";
}

NSString *NFNotificationHistoryRefreshStatusFilePath(void) {
    return @"/var/mobile/Library/Preferences/com.tune.notificationfilter.history-status.plist";
}
