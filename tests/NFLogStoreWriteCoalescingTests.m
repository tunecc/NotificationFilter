#import <Foundation/Foundation.h>
#import "../Shared/NFLogStore.h"

@interface NFPreferences : NSObject
+ (NSDictionary *)loadPreferences;
+ (NSInteger)normalizedLogEntryLimit:(id)value;
+ (NSString *)logsFilePath;
@end

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

@implementation NFPreferences

+ (NSDictionary *)loadPreferences {
    return @{ NFLogEntryLimitKey: @500 };
}

+ (NSInteger)normalizedLogEntryLimit:(id)value {
    if (![value respondsToSelector:@selector(integerValue)] || [value integerValue] <= 0) {
        return 500;
    }
    return [value integerValue];
}

+ (NSString *)logsFilePath {
    NSString *path = NSProcessInfo.processInfo.environment[@"NF_LOG_STORE_TEST_PATH"];
    return path.length > 0 ? path : [NSTemporaryDirectory() stringByAppendingPathComponent:@"nf-logstore-coalescing-test.plist"];
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

// 带当前时间戳的条目。clear-state 机制会把「同 bundle 且 timestamp <= clearedAt」的条目视为已清理，
// 因此验证 clear 之后新通知能否落盘时，必须用当前/未来时间戳，避免被 clear-state 过滤（与
// NFLogStoreClearTests.m 一致）。
static NSDictionary *NFMakeFreshEntry(NSString *identifierSuffix) {
    NSMutableDictionary *entry = [NFMakeEntry(identifierSuffix) mutableCopy];
    entry[NFLogTimestampKey] = @([[NSDate date] timeIntervalSince1970] + 1.0);
    return [entry copy];
}

static void NFFlushLogQueue(void) {
    dispatch_sync([NFLogStore _logQueue], ^{
    });
}

static void NFCleanupLogFiles(NSString *logPath) {
    [[NSFileManager defaultManager] removeItemAtPath:logPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[logPath stringByAppendingString:@".cleared.plist"] error:nil];
}

int main(void) {
    @autoreleasepool {
        NSString *testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [[NSFileManager defaultManager] createDirectoryAtPath:testDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        NSString *logPath = [testDirectory stringByAppendingPathComponent:@"logs.plist"];
        setenv("NF_LOG_STORE_TEST_PATH", logPath.UTF8String, 1);

        int failures = 0;

        // Case A: append does not flush immediately; disk should not yet contain the entry.
        NFCleanupLogFiles(logPath);
        [NFLogStore appendBlockedEntry:NFMakeEntry(@"a")];
        NFFlushLogQueue(); // drain the append async block, but no forced flush.
        {
            NSArray *diskEntries = [NSArray arrayWithContentsOfFile:logPath];
            NSUInteger diskCount = [diskEntries isKindOfClass:[NSArray class]] ? diskEntries.count : 0;
            if (diskCount != 0) {
                fprintf(stderr, "FAIL Case A: disk should be empty before flush, got %lu\n", (unsigned long)diskCount);
                failures++;
            } else {
                printf("PASS Case A: disk empty before forced flush\n");
            }
        }

        // Case B: after forced flush, loadEntries sees the entry (deduped).
        [NFLogStore _flushLockedForTesting];
        {
            NSArray<NSDictionary *> *entries = [NFLogStore loadEntries];
            NSUInteger matchCount = 0;
            for (NSDictionary *entry in entries) {
                if ([[entry objectForKey:NFLogRecordIDKey] isEqualToString:@"record-a"]) {
                    matchCount++;
                }
            }
            if (entries.count != 1 || matchCount != 1) {
                fprintf(stderr, "FAIL Case B: expected 1 entry after flush, got entries=%lu matchCount=%lu\n",
                        (unsigned long)entries.count, (unsigned long)matchCount);
                failures++;
            } else {
                printf("PASS Case B: disk has 1 deduped entry after flush\n");
            }
        }

        // Case C: append (no flush) -> clearEntries -> append new -> flush -> old entry must not revive.
        // 用未来时间戳的新条目，避免被 clear-state 过滤（与 NFLogStoreClearTests.m 一致）。
        [NFLogStore appendBlockedEntry:NFMakeFreshEntry(@"old")];
        NFFlushLogQueue(); // drain append; old not yet flushed to disk.
        [NFLogStore clearEntries];
        [NFLogStore appendBlockedEntry:NFMakeFreshEntry(@"new")];
        NFFlushLogQueue();
        [NFLogStore _flushLockedForTesting];
        {
            NSArray<NSDictionary *> *entries = [NFLogStore loadEntries];
            BOOL hasOld = NO, hasNew = NO;
            for (NSDictionary *entry in entries) {
                NSString *recordID = [entry objectForKey:NFLogRecordIDKey];
                if ([recordID isEqualToString:@"record-old"]) hasOld = YES;
                if ([recordID isEqualToString:@"record-new"]) hasNew = YES;
            }
            if (hasOld || !hasNew) {
                fprintf(stderr, "FAIL Case C: old revived=%d new present=%d\n", hasOld, hasNew);
                failures++;
            } else {
                printf("PASS Case C: old entry cleared, new entry present, no revival\n");
            }
        }

        NFCleanupLogFiles(logPath);
        [[NSFileManager defaultManager] removeItemAtPath:testDirectory error:nil];

        if (failures > 0) {
            fprintf(stderr, "RESULT: %d FAILURE(S)\n", failures);
            return 1;
        }
        printf("RESULT: ALL PASS\n");
        return 0;
    }
}
