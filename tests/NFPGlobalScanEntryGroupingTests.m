#import <Foundation/Foundation.h>
#import "../NotificationFilterPrefs/NFPNotificationHistoryClient.h"
#import "../Shared/NFPreferences.h"
#import "../Shared/NFNotificationHistoryBridge.h"

//
// 全局扫描分组回归测试：覆盖全部应用镜像读取（空快照、跨 bundle 保留、损坏文件）。
// 直接编译真实 Shared/Prefs 源码，不重复定义生产常量，避免符号冲突。
//
@interface NFPNotificationHistoryClient (Testing)
+ (NSArray<NSDictionary *> *)fetchAllAppsEntriesWithError:(NSError **)error source:(NSString **)source;
@end

static void NFAssert(BOOL condition, NSString *message) {
    if (!condition) {
        @throw [NSException exceptionWithName:@"NFPGlobalScanTestFailure" reason:message userInfo:nil];
    }
}

int main(void) {
    @autoreleasepool {
        NSString *snapshotDirectory = NSTemporaryDirectory();
        setenv("NF_NOTIFICATION_HISTORY_DIRECTORY_OVERRIDE", snapshotDirectory.UTF8String, 1);

        // 空快照：返回空数组，不崩溃。
        NSError *error = nil;
        NSString *source = nil;
        NSArray<NSDictionary *> *empty = [NFPNotificationHistoryClient fetchAllAppsEntriesWithError:&error source:&source];
        NFAssert(empty.count == 0, @"empty snapshot should return no entries");
        NFAssert(error == nil, @"empty snapshot should not report an error");

        // 全部应用条目：不按 bundleIdentifier 过滤，保留所有有效条目。
        NSArray<NSDictionary *> *snapshot = @[
            @{
                NFLogBundleIdentifierKey: @"com.app.a",
                NFLogTitleKey: @"验证码",
                NFLogBodyKey: @"你的验证码是 1234",
                NFLogTimestampKey: @1000.0
            },
            @{
                NFLogBundleIdentifierKey: @"com.app.b",
                NFLogTitleKey: @"推广",
                NFLogBodyKey: @"限时优惠",
                NFLogTimestampKey: @2000.0
            },
            @{
                // 无 bundleIdentifier 的条目应被跳过。
                NFLogTitleKey: @"无来源",
                NFLogBodyKey: @"内容"
            }
        ];
        [snapshot writeToFile:[snapshotDirectory stringByAppendingPathComponent:@"com.tune.notificationfilter.history.plist"] atomically:YES];

        source = nil;
        error = nil;
        NSArray<NSDictionary *> *all = [NFPNotificationHistoryClient fetchAllAppsEntriesWithError:&error source:&source];
        NFAssert(all.count == 2, @"all-apps fetch should keep entries from every bundle and drop bundleless entries");
        NFAssert([source isEqualToString:NFNotificationHistorySourceMirror], @"all-apps fetch should report the mirror source");
        NFAssert(error == nil, @"all-apps fetch should not report an error on a valid snapshot");

        // 非数组快照（损坏文件）：返回空，不崩溃。
        [@{ @"unexpected": @"shape" } writeToFile:[snapshotDirectory stringByAppendingPathComponent:@"com.tune.notificationfilter.history.plist"] atomically:YES];
        error = nil;
        source = nil;
        NSArray<NSDictionary *> *corrupt = [NFPNotificationHistoryClient fetchAllAppsEntriesWithError:&error source:&source];
        NFAssert(corrupt.count == 0, @"corrupt snapshot should yield no entries without crashing");
        NFAssert(source == nil, @"corrupt snapshot should not report a source");
    }
    return 0;
}
