#import <Foundation/Foundation.h>
#import "../Shared/NFPreferences.h"

static void NFAssert(BOOL condition, NSString *message) {
    if (!condition) {
        @throw [NSException exceptionWithName:@"NFPreferencesRuleModeTestFailure" reason:message userInfo:nil];
    }
}

static void NFAssertStringEquals(NSString *actual, NSString *expected, NSString *message) {
    NFAssert([actual isEqualToString:expected], [NSString stringWithFormat:@"%@ actual=%@ expected=%@", message, actual, expected]);
}

int main(void) {
    @autoreleasepool {
        NSDictionary *missingMode = [NFPreferences normalizedRulesDictionaryFromRawDictionary:@{
            NFRulesEnabledKey: @YES,
            NFRulesContainsKey: @[ @"promo" ]
        }];
        NFAssertStringEquals(missingMode[NFRulesModeKey], NFRulesModeBlacklist, @"missing mode should default to blacklist");
        NFAssert([missingMode[NFRulesEnabledKey] boolValue], @"enabled flag should be preserved");

        NSDictionary *whitelistMode = [NFPreferences normalizedRulesDictionaryFromRawDictionary:@{
            NFRulesEnabledKey: @YES,
            NFRulesModeKey: NFRulesModeWhitelist,
            NFRulesContainsKey: @[ @"otp" ],
            NFRulesExcludeKey: @[ @"ad" ],
            NFRulesRegexKey: @[ @"code\\d+" ]
        }];
        NFAssertStringEquals(whitelistMode[NFRulesModeKey], NFRulesModeWhitelist, @"valid whitelist mode should be preserved");
        NFAssert([whitelistMode[NFRulesContainsKey] count] == 1, @"contains entries should survive normalization");
        NFAssert([whitelistMode[NFRulesExcludeKey] count] == 1, @"exclude entries should survive normalization");
        NFAssert([whitelistMode[NFRulesRegexKey] count] == 1, @"regex entries should survive normalization");

        NSDictionary *invalidMode = [NFPreferences normalizedRulesDictionaryFromRawDictionary:@{
            NFRulesModeKey: @"allowlist"
        }];
        NFAssertStringEquals(invalidMode[NFRulesModeKey], NFRulesModeBlacklist, @"invalid string mode should normalize to blacklist");

        NSDictionary *nonStringMode = [NFPreferences normalizedRulesDictionaryFromRawDictionary:@{
            NFRulesModeKey: @42
        }];
        NFAssertStringEquals(nonStringMode[NFRulesModeKey], NFRulesModeBlacklist, @"non-string mode should normalize to blacklist");

        NSDictionary *defaultDictionary = [NFPreferences normalizedRulesDictionaryFromEnabled:YES contains:nil exclude:nil regex:nil];
        NFAssertStringEquals(defaultDictionary[NFRulesModeKey], NFRulesModeBlacklist, @"legacy constructor should create blacklist dictionaries");
    }
    return 0;
}
