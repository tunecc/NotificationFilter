#import <Foundation/Foundation.h>

#import "../Shared/NFLogStore.h"

NSString * const NFLogEntryLimitKey = @"LogEntryLimit";
NSString * const NFLogIdentifierKey = @"id";
NSString * const NFLogTimestampKey = @"timestamp";
NSString * const NFLogBundleIdentifierKey = @"bundleID";
NSString * const NFLogSectionIDKey = @"sectionID";
NSString * const NFLogBulletinIDKey = @"bulletinID";
NSString * const NFLogRecordIDKey = @"recordID";
NSString * const NFLogPublisherBulletinIDKey = @"publisherBulletinID";
NSString * const NFLogMatchedScopeKey = @"matchedScope";
NSString * const NFLogMatchedPatternKey = @"matchedPattern";

@interface NFPreferences : NSObject

+ (NSDictionary *)loadPreferences;
+ (NSInteger)normalizedLogEntryLimit:(id)value;
+ (NSString *)logsFilePath;

@end

@implementation NFPreferences

+ (NSDictionary *)loadPreferences {
    return @{ NFLogEntryLimitKey: @500 };
}

+ (NSInteger)normalizedLogEntryLimit:(id)value {
    if (![value respondsToSelector:@selector(integerValue)]) {
        return 500;
    }

    NSInteger limit = [value integerValue];
    return limit > 0 ? limit : 500;
}

+ (NSString *)logsFilePath {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"nf-logstore-regression.plist"];
}

@end

@interface NFLogStore (Testing)

+ (dispatch_queue_t)_logQueue;
+ (void)_flushLockedForTesting;

@end

static NSDictionary *NFMakeEntry(NSString *identifierSuffix) {
    return @{
        NFLogIdentifierKey: [NSString stringWithFormat:@"entry-%@", identifierSuffix],
        NFLogTimestampKey: @1000.0,
        NFLogBundleIdentifierKey: @"com.example.messages",
        NFLogSectionIDKey: @"com.example.messages",
        NFLogRecordIDKey: [NSString stringWithFormat:@"record-%@", identifierSuffix],
        NFLogPublisherBulletinIDKey: [NSString stringWithFormat:@"record-%@", identifierSuffix],
        NFLogMatchedScopeKey: @"app:com.example.messages",
        NFLogMatchedPatternKey: @"match-pattern"
    };
}

static void NFFlushLogQueue(void) {
    // 排空 _logQueue 上的 async 任务并强制把内存缓存落盘，
    // 否则写合并后 loadEntries 读磁盘可能拿不到最新条目。
    [NFLogStore _flushLockedForTesting];
}

static void NFCleanupLogFiles(void) {
    NSString *logPath = [NFPreferences logsFilePath];
    [[NSFileManager defaultManager] removeItemAtPath:logPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[logPath stringByAppendingString:@".cleared.plist"] error:nil];
}

int main(void) {
    @autoreleasepool {
        NFCleanupLogFiles();

        NSDictionary *targetEntry = NFMakeEntry(@"target");
        [NFLogStore appendBlockedEntry:targetEntry];
        NFFlushLogQueue();

        for (NSInteger index = 0; index < 20; index++) {
            NSString *suffix = [NSString stringWithFormat:@"filler-%ld", (long)index];
            [NFLogStore appendBlockedEntry:NFMakeEntry(suffix)];
        }
        NFFlushLogQueue();

        [NFLogStore appendBlockedEntry:targetEntry];
        NFFlushLogQueue();

        NSArray<NSDictionary *> *entries = [NFLogStore loadEntries];
        NSUInteger duplicateCount = 0;
        for (NSDictionary *entry in entries) {
            NSString *recordID = entry[NFLogRecordIDKey];
            if ([recordID isEqualToString:@"record-target"]) {
                duplicateCount += 1;
            }
        }

        if (entries.count != 21 || duplicateCount != 1) {
            fprintf(stderr,
                    "FAIL entries=%lu duplicateCount=%lu\n",
                    (unsigned long)entries.count,
                    (unsigned long)duplicateCount);
            NFCleanupLogFiles();
            return 1;
        }

        printf("PASS entries=%lu duplicateCount=%lu\n",
               (unsigned long)entries.count,
               (unsigned long)duplicateCount);
        NFCleanupLogFiles();
        return 0;
    }
}
