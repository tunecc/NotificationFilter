#import <Foundation/Foundation.h>
#import "../Shared/NFLogStore.h"

@interface NFPreferences : NSObject
+ (NSDictionary *)loadPreferences;
+ (NSInteger)normalizedLogEntryLimit:(id)value;
+ (NSString *)logsFilePath;
@end

NSString * const NFLogIdentifierKey = @"id";
NSString * const NFLogTimestampKey = @"timestamp";
NSString * const NFLogBundleIdentifierKey = @"bundleID";
NSString * const NFLogSectionIDKey = @"sectionID";
NSString * const NFLogBulletinIDKey = @"bulletinID";
NSString * const NFLogRecordIDKey = @"recordID";
NSString * const NFLogPublisherBulletinIDKey = @"publisherBulletinID";
NSString * const NFLogMatchedScopeKey = @"matchedScope";
NSString * const NFLogMatchedPatternKey = @"matchedPattern";
NSString * const NFLogEntryLimitKey = @"LogEntryLimit";

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
    return path.length > 0 ? path : [NSTemporaryDirectory() stringByAppendingPathComponent:@"nf-logstore-test.plist"];
}

@end

static void NFAssert(BOOL condition, NSString *message) {
    if (!condition) {
        @throw [NSException exceptionWithName:@"NFLogStoreTestFailure" reason:message userInfo:nil];
    }
}

static NSDictionary *NFEntry(NSString *bundleIdentifier, NSTimeInterval timestamp, NSString *bulletinID) {
    return @{
        NFLogBundleIdentifierKey: bundleIdentifier,
        NFLogTimestampKey: @(timestamp),
        NFLogBulletinIDKey: bulletinID,
        NFLogMatchedScopeKey: @"app:test",
        NFLogMatchedPatternKey: @"old"
    };
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

        NSString *bundleIdentifier = @"com.example.demo";
        NSTimeInterval oldTimestamp = [[NSDate date] timeIntervalSince1970] - 120.0;
        [NFLogStore clearEntries];
        [NFLogStore appendBlockedEntry:NFEntry(bundleIdentifier, oldTimestamp, @"old-1")];
        [NFLogStore clearEntriesForBundleIdentifier:bundleIdentifier];
        [NFLogStore appendBlockedEntry:NFEntry(bundleIdentifier, oldTimestamp, @"old-1")];
        [NFLogStore trimEntriesToCurrentLimit];

        NSArray *entriesAfterOldReplay = [NFLogStore loadEntries];
        NFAssert(entriesAfterOldReplay.count == 0, @"old replayed entry should stay cleared");

        [NFLogStore appendBlockedEntry:NFEntry(bundleIdentifier, [[NSDate date] timeIntervalSince1970] + 1.0, @"new-1")];
        [NFLogStore trimEntriesToCurrentLimit];
        NSArray *entriesAfterNewNotification = [NFLogStore loadEntries];
        NFAssert(entriesAfterNewNotification.count == 1, @"new entry after clear should be logged");

        [[NSFileManager defaultManager] removeItemAtPath:testDirectory error:nil];
    }
    return 0;
}
