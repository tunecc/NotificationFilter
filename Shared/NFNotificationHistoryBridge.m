#import "NFNotificationHistoryBridge.h"

#ifdef __has_include
  #if __has_include(<rootless.h>)
    #import <rootless.h>
  #elif __has_include(<roothide.h>)
    #include <roothide.h>
  #endif
#endif
#ifndef jbroot
  #ifdef ROOT_PATH_NS
    #define jbroot(path) ROOT_PATH_NS(path)
  #else
    #define jbroot(path) path
  #endif
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

// 与 NFPreferences / NFLogStore 保持同一模式：直接返回 jbroot() 解析后的路径，
// 历史文件写入隐藏的 .jbroot（roothide）/ jb 根（rootless）/ 原样（rootful）。
// 不做跨容器迁移，也不删除可见路径的旧文件——1.3.7 的迁移/删除正是
// roothide iOS 15 上触发 SpringBoard 安全模式的根因；旧版本留在可见路径的
// 历史文件保留在磁盘上不再读取，需要时可手动恢复。
static NSString *NFPreferencesScopedFilePath(NSString *filename) {
    return jbroot(NFLegacyPreferencesFilePath(filename));
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
