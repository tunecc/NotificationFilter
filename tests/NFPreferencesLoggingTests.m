#import <Foundation/Foundation.h>
#import "../Shared/NFPreferences.h"

static void NFAssert(BOOL condition, NSString *message) {
    if (!condition) {
        @throw [NSException exceptionWithName:@"NFPreferencesLoggingTestFailure" reason:message userInfo:nil];
    }
}

static NSDictionary *NFPrefs(BOOL enabled, NSArray *disabledBundleIdentifiers) {
    return @{
        NFLoggingEnabledKey: @(enabled),
        NFLoggingDisabledBundleIdentifiersKey: disabledBundleIdentifiers ?: @[]
    };
}

int main(void) {
    @autoreleasepool {
        // 归一化:LoggingEnabled 缺省 -> YES
        NFAssert([NFPreferences loggingEnabledForPreferences:@{}] == YES,
                 @"missing LoggingEnabled should default to YES");

        // 归一化:LoggingEnabled 非 BOOL -> YES
        NSDictionary *nonBoolPrefs = @{ NFLoggingEnabledKey: @"nonsense" };
        NSDictionary *normalizedNonBool = [NFPreferences normalizedPreferencesFromDictionary:nonBoolPrefs];
        NFAssert([normalizedNonBool[NFLoggingEnabledKey] boolValue] == YES,
                 @"non-bool LoggingEnabled should normalize to YES");

        // 归一化:禁用列表清洗
        NSDictionary *dirtyList = [NFPreferences normalizedPreferencesFromDictionary:@{
            NFLoggingDisabledBundleIdentifiersKey: @[ @"com.a", @"com.a", @"", @42, @"com.b" ]
        }];
        NSArray *normalizedList = dirtyList[NFLoggingDisabledBundleIdentifiersKey];
        NFAssert(normalizedList.count == 2, @"disabled list should dedupe, drop empty and non-string");
        NFAssert([normalizedList containsObject:@"com.a"] && [normalizedList containsObject:@"com.b"],
                 @"disabled list should keep valid strings");

        // 组合判定矩阵
        NFAssert([NFPreferences loggingEnabledForPreferences:NFPrefs(YES, nil)] == YES,
                 @"global on, no disabled -> log");
        NFAssert([NFPreferences loggingEnabledForPreferences:NFPrefs(NO, nil)] == NO,
                 @"global off -> no log");
        NFAssert([NFPreferences isLoggingDisabledForBundleIdentifier:@"com.a" preferences:NFPrefs(YES, @[ @"com.a" ])] == YES,
                 @"bundle id in disabled list -> disabled");
        NFAssert([NFPreferences isLoggingDisabledForBundleIdentifier:@"com.b" preferences:NFPrefs(YES, @[ @"com.a" ])] == NO,
                 @"bundle id not in disabled list -> not disabled");
        NFAssert([NFPreferences loggingEnabledForBundleIdentifier:@"com.a" preferences:NFPrefs(YES, @[ @"com.a" ])] == NO,
                 @"global on but app disabled -> no log");
        NFAssert([NFPreferences loggingEnabledForBundleIdentifier:@"com.b" preferences:NFPrefs(YES, @[ @"com.a" ])] == YES,
                 @"global on and app enabled -> log");
        NFAssert([NFPreferences loggingEnabledForBundleIdentifier:@"com.a" preferences:NFPrefs(NO, @[ @"com.a" ])] == NO,
                 @"global off wins even if app not disabled");
    }
    return 0;
}
