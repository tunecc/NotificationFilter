#import "NFNotificationHistoryBridge.h"

#ifdef __has_include
  #if __has_include(<roothide.h>)
    #include <roothide.h>
  #endif
#endif
#ifndef jbroot
  #define jbroot(path) path
#endif

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

static NSString *NFLegacyPreferencesFilePath(NSString *filename) {
    return [@"/var/mobile/Library/Preferences" stringByAppendingPathComponent:filename];
}

static NSString *NFPreferencesScopedFilePath(NSString *filename) {
    NSString *legacyPath = NFLegacyPreferencesFilePath(filename);
    NSString *scopedPath = jbroot(legacyPath);

    if ([scopedPath isEqualToString:legacyPath]) {
        return scopedPath;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:scopedPath] &&
        [fileManager fileExistsAtPath:legacyPath]) {
        NSString *parentPath = [scopedPath stringByDeletingLastPathComponent];
        [fileManager createDirectoryAtPath:parentPath
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:nil];

        NSError *moveError = nil;
        if (![fileManager moveItemAtPath:legacyPath toPath:scopedPath error:&moveError]) {
            [fileManager copyItemAtPath:legacyPath toPath:scopedPath error:nil];
        }
    }

    return scopedPath;
}

NSString *NFNotificationHistorySnapshotFilePath(void) {
    return NFPreferencesScopedFilePath(@"com.tune.notificationfilter.history.plist");
}

NSString *NFNotificationHistoryRefreshRequestFilePath(void) {
    return NFPreferencesScopedFilePath(@"com.tune.notificationfilter.history-request.plist");
}

NSString *NFNotificationHistoryRefreshStatusFilePath(void) {
    return NFPreferencesScopedFilePath(@"com.tune.notificationfilter.history-status.plist");
}
