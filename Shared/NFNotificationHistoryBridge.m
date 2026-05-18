#import "NFNotificationHistoryBridge.h"

NSString * const NFNotificationHistoryMessagingCenterName = @"com.tune.notificationfilter.history";
NSString * const NFNotificationHistoryFetchMessageName = @"fetch-history";
NSString * const NFNotificationHistoryBundleIdentifierKey = @"bundleIdentifier";
NSString * const NFNotificationHistoryLimitKey = @"limit";
NSString * const NFNotificationHistoryEntriesKey = @"entries";
NSString * const NFNotificationHistoryErrorKey = @"error";
NSString * const NFNotificationHistorySourceKey = @"source";

NSString * const NFNotificationHistorySourceLive = @"live";
NSString * const NFNotificationHistorySourceMirror = @"mirror";

NSString *NFNotificationHistorySnapshotFilePath(void) {
    return @"/var/mobile/Library/Preferences/com.tune.notificationfilter.history.plist";
}
