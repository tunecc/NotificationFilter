#import <XCTest/XCTest.h>
#import "../NotificationFilterTweak/NFNotificationRecord.h"
#import "../NotificationFilterTweak/NFRuleEngine.h"
#import "../Shared/NFPreferences.h"

// Test helper to simulate NFBlockedActionRecordKey logic
static NSString *NFNormalizedStringValueTest(id value) {
    if (!value) {
        return nil;
    }

    NSString *stringValue = nil;
    if ([value isKindOfClass:[NSString class]]) {
        stringValue = value;
    } else if ([value respondsToSelector:@selector(stringValue)]) {
        id response = ((id (*)(id, SEL))objc_msgSend)(value, @selector(stringValue));
        if ([response isKindOfClass:[NSString class]]) {
            stringValue = response;
        }
    }

    return [stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *NFBlockedActionRecordKeyTest(NFNotificationRecord *record, NFMatchResult *result) {
    if (!record || !result.shouldBlock) {
        return nil;
    }

    NSString *bulletinID = NFNormalizedStringValueTest(record.bulletinID);
    NSString *recordID = NFNormalizedStringValueTest(record.recordID);
    NSString *publisherBulletinID = NFNormalizedStringValueTest(record.publisherBulletinID);
    if (bulletinID.length == 0 && recordID.length == 0 && publisherBulletinID.length == 0) {
        return nil;
    }

    NSString *matchedPattern = NFNormalizedStringValueTest(result.matchedPattern);
    NSString *matchedMode = NFNormalizedStringValueTest(result.matchedMode);

    // For whitelist default block mode with no pattern, include content hash to distinguish different notifications
    if (matchedPattern.length == 0 && [matchedMode isEqualToString:NFMatchModeWhitelistDefault]) {
        NSString *contentForHash = [NSString stringWithFormat:@"%@|%@|%@",
                                    NFNormalizedStringValueTest(record.title) ?: @"",
                                    NFNormalizedStringValueTest(record.subtitle) ?: @"",
                                    NFNormalizedStringValueTest(record.messageText) ?: @""];
        matchedPattern = [NSString stringWithFormat:@"content:%lu", (unsigned long)[contentForHash hash]];
    }

    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@|%@",
                                      NFNormalizedStringValueTest(record.bundleIdentifier) ?: @"",
                                      NFNormalizedStringValueTest(record.sectionID) ?: @"",
                                      bulletinID ?: @"",
                                      recordID ?: @"",
                                      publisherBulletinID ?: @"",
                                      NFNormalizedStringValueTest(result.matchedScope) ?: @"",
                                      matchedPattern ?: @""];
}

@interface NFWhitelistDedupeTests : XCTestCase
@end

@implementation NFWhitelistDedupeTests

- (void)testWhitelistDefaultBlockGeneratesDifferentKeysForDifferentNotifications {
    // Setup: Create two notifications with different content
    NFNotificationRecord *record1 = [[NFNotificationRecord alloc] init];
    record1.bundleIdentifier = @"com.example.app";
    record1.sectionID = @"com.example.app";
    record1.bulletinID = @"bulletin-001";
    record1.title = @"First Notification";
    record1.subtitle = @"First subtitle";
    record1.messageText = @"First message";

    NFNotificationRecord *record2 = [[NFNotificationRecord alloc] init];
    record2.bundleIdentifier = @"com.example.app";
    record2.sectionID = @"com.example.app";
    record2.bulletinID = @"bulletin-002";
    record2.title = @"Second Notification";
    record2.subtitle = @"Second subtitle";
    record2.messageText = @"Second message";

    // Create whitelist default block result (no pattern)
    NFMatchResult *result1 = [[NFMatchResult alloc] init];
    result1.shouldBlock = YES;
    result1.matchedScope = @"app:com.example.app";
    result1.matchedMode = NFMatchModeWhitelistDefault;
    result1.matchedPattern = nil;

    NFMatchResult *result2 = [[NFMatchResult alloc] init];
    result2.shouldBlock = YES;
    result2.matchedScope = @"app:com.example.app";
    result2.matchedMode = NFMatchModeWhitelistDefault;
    result2.matchedPattern = nil;

    // Generate keys
    NSString *key1 = NFBlockedActionRecordKeyTest(record1, result1);
    NSString *key2 = NFBlockedActionRecordKeyTest(record2, result2);

    // Assert: Keys should be different because content is different
    XCTAssertNotNil(key1, @"Key 1 should not be nil");
    XCTAssertNotNil(key2, @"Key 2 should not be nil");
    XCTAssertNotEqualObjects(key1, key2, @"Different notifications should generate different keys in whitelist default mode");
}

- (void)testWhitelistDefaultBlockGeneratesSameKeyForSameNotification {
    // Setup: Create two identical notifications
    NFNotificationRecord *record1 = [[NFNotificationRecord alloc] init];
    record1.bundleIdentifier = @"com.example.app";
    record1.sectionID = @"com.example.app";
    record1.bulletinID = @"bulletin-001";
    record1.title = @"Same Notification";
    record1.subtitle = @"Same subtitle";
    record1.messageText = @"Same message";

    NFNotificationRecord *record2 = [[NFNotificationRecord alloc] init];
    record2.bundleIdentifier = @"com.example.app";
    record2.sectionID = @"com.example.app";
    record2.bulletinID = @"bulletin-001";
    record2.title = @"Same Notification";
    record2.subtitle = @"Same subtitle";
    record2.messageText = @"Same message";

    // Create whitelist default block result
    NFMatchResult *result1 = [[NFMatchResult alloc] init];
    result1.shouldBlock = YES;
    result1.matchedScope = @"app:com.example.app";
    result1.matchedMode = NFMatchModeWhitelistDefault;
    result1.matchedPattern = nil;

    NFMatchResult *result2 = [[NFMatchResult alloc] init];
    result2.shouldBlock = YES;
    result2.matchedScope = @"app:com.example.app";
    result2.matchedMode = NFMatchModeWhitelistDefault;
    result2.matchedPattern = nil;

    // Generate keys
    NSString *key1 = NFBlockedActionRecordKeyTest(record1, result1);
    NSString *key2 = NFBlockedActionRecordKeyTest(record2, result2);

    // Assert: Keys should be the same for identical content
    XCTAssertNotNil(key1, @"Key 1 should not be nil");
    XCTAssertNotNil(key2, @"Key 2 should not be nil");
    XCTAssertEqualObjects(key1, key2, @"Identical notifications should generate the same key for deduplication");
}

- (void)testBlacklistModeStillUsesPattern {
    // Setup: Create notification with blacklist mode (has pattern)
    NFNotificationRecord *record1 = [[NFNotificationRecord alloc] init];
    record1.bundleIdentifier = @"com.example.app";
    record1.sectionID = @"com.example.app";
    record1.bulletinID = @"bulletin-001";
    record1.title = @"First Notification";
    record1.messageText = @"First message";

    NFNotificationRecord *record2 = [[NFNotificationRecord alloc] init];
    record2.bundleIdentifier = @"com.example.app";
    record2.sectionID = @"com.example.app";
    record2.bulletinID = @"bulletin-002";
    record2.title = @"Second Notification";
    record2.messageText = @"Second message";

    // Create blacklist mode result with pattern
    NFMatchResult *result1 = [[NFMatchResult alloc] init];
    result1.shouldBlock = YES;
    result1.matchedScope = @"app:com.example.app";
    result1.matchedMode = NFMatchModeContains;
    result1.matchedPattern = @"spam";

    NFMatchResult *result2 = [[NFMatchResult alloc] init];
    result2.shouldBlock = YES;
    result2.matchedScope = @"app:com.example.app";
    result2.matchedMode = NFMatchModeContains;
    result2.matchedPattern = @"spam";

    // Generate keys
    NSString *key1 = NFBlockedActionRecordKeyTest(record1, result1);
    NSString *key2 = NFBlockedActionRecordKeyTest(record2, result2);

    // Assert: Keys should use the pattern, not content hash
    XCTAssertNotNil(key1, @"Key 1 should not be nil");
    XCTAssertNotNil(key2, @"Key 2 should not be nil");
    XCTAssertTrue([key1 containsString:@"spam"], @"Blacklist mode should include pattern in key");
    XCTAssertTrue([key2 containsString:@"spam"], @"Blacklist mode should include pattern in key");
    XCTAssertFalse([key1 containsString:@"content:"], @"Blacklist mode should not use content hash");
    XCTAssertFalse([key2 containsString:@"content:"], @"Blacklist mode should not use content hash");
}

- (void)testWhitelistExcludeModeUsesPattern {
    // Setup: Create notification with whitelist exclude mode (has pattern)
    NFNotificationRecord *record = [[NFNotificationRecord alloc] init];
    record.bundleIdentifier = @"com.example.app";
    record.sectionID = @"com.example.app";
    record.bulletinID = @"bulletin-001";
    record.title = @"Important Notification";
    record.messageText = @"Important message";

    // Create whitelist exclude result with pattern (allowed)
    NFMatchResult *result = [[NFMatchResult alloc] init];
    result.shouldBlock = YES;  // In whitelist mode, exclude rules set shouldBlock to YES (inverted logic)
    result.matchedScope = @"app:com.example.app";
    result.matchedMode = NFMatchModeExclude;
    result.matchedPattern = @"important";

    // Generate key
    NSString *key = NFBlockedActionRecordKeyTest(record, result);

    // Assert: Should use the pattern, not content hash
    XCTAssertNotNil(key, @"Key should not be nil");
    XCTAssertTrue([key containsString:@"important"], @"Whitelist exclude mode should include pattern in key");
    XCTAssertFalse([key containsString:@"content:"], @"Whitelist exclude mode should not use content hash");
}

@end
