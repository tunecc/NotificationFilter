#import <Foundation/Foundation.h>
#import "../NotificationFilterTweak/NFRuleEngine.h"
#import "../NotificationFilterTweak/NFNotificationRecord.h"
#import "../Shared/NFPreferences.h"

static NSDictionary *NFRule(NSString *text, NSString *scope) {
    return [NFPreferences ruleEntryWithText:text enabled:YES identifier:nil scope:scope];
}

static NFNotificationRecord *NFRecord(NSString *body) {
    NFNotificationRecord *record = [[NFNotificationRecord alloc] init];
    record.bundleIdentifier = @"com.example.chat";
    record.body = body;
    record.messageText = body ?: @"";
    record.joinedText = body ?: @"";
    record.timestamp = [NSDate date];
    return record;
}

static NSDictionary *NFPreferencesWithAppRules(NSDictionary *appRules) {
    return [NFPreferences normalizedPreferencesFromDictionary:@{
        NFEnabledKey: @YES,
        NFGlobalRulesEnabledKey: @NO,
        NFAppRulesKey: @{ @"com.example.chat": appRules }
    }];
}

static void NFAssert(BOOL condition, NSString *message) {
    if (!condition) {
        @throw [NSException exceptionWithName:@"NFRuleEngineModeTestFailure" reason:message userInfo:nil];
    }
}

static void NFAssertMode(NFMatchResult *result, BOOL shouldBlock, NSString *mode, NSString *message) {
    NFAssert(result.shouldBlock == shouldBlock, [message stringByAppendingFormat:@" shouldBlock=%d", result.shouldBlock]);
    if (mode.length > 0) {
        NFAssert([result.matchedMode isEqualToString:mode], [message stringByAppendingFormat:@" mode=%@ expected=%@", result.matchedMode, mode]);
    }
}

int main(void) {
    @autoreleasepool {
        NSDictionary *blacklistRules = [NFPreferences normalizedRulesDictionaryFromRawDictionary:@{
            NFRulesEnabledKey: @YES,
            NFRulesModeKey: NFRulesModeBlacklist,
            NFRulesContainsKey: @[ NFRule(@"promo", NFRuleScopeMessage) ],
            NFRulesExcludeKey: @[ NFRule(@"otp", NFRuleScopeAll) ],
            NFRulesRegexKey: @[ NFRule(@"sale[0-9]+", NFRuleScopeAll) ]
        }];
        NFAssertMode([NFRuleEngine evaluateRecord:NFRecord(@"promo today") preferences:NFPreferencesWithAppRules(blacklistRules)], YES, NFMatchModeContains, @"blacklist contains should block");
        NFAssertMode([NFRuleEngine evaluateRecord:NFRecord(@"otp promo") preferences:NFPreferencesWithAppRules(blacklistRules)], NO, NFMatchModeExclude, @"blacklist exclude should allow before contains");
        NFAssertMode([NFRuleEngine evaluateRecord:NFRecord(@"sale2026") preferences:NFPreferencesWithAppRules(blacklistRules)], YES, NFMatchModeRegex, @"blacklist regex should block");
        NFAssertMode([NFRuleEngine evaluateRecord:NFRecord(@"plain message") preferences:NFPreferencesWithAppRules(blacklistRules)], NO, nil, @"blacklist no match should allow");

        NSDictionary *whitelistRules = [NFPreferences normalizedRulesDictionaryFromRawDictionary:@{
            NFRulesEnabledKey: @YES,
            NFRulesModeKey: NFRulesModeWhitelist,
            NFRulesContainsKey: @[ NFRule(@"otp", NFRuleScopeMessage) ],
            NFRulesExcludeKey: @[ NFRule(@"ad", NFRuleScopeAll) ],
            NFRulesRegexKey: @[ NFRule(@"code[0-9]+", NFRuleScopeAll) ]
        }];
        NFAssertMode([NFRuleEngine evaluateRecord:NFRecord(@"otp 123") preferences:NFPreferencesWithAppRules(whitelistRules)], NO, NFMatchModeContains, @"whitelist contains should allow");
        NFAssertMode([NFRuleEngine evaluateRecord:NFRecord(@"code2026") preferences:NFPreferencesWithAppRules(whitelistRules)], NO, NFMatchModeRegex, @"whitelist regex should allow");
        NFAssertMode([NFRuleEngine evaluateRecord:NFRecord(@"ad otp") preferences:NFPreferencesWithAppRules(whitelistRules)], YES, NFMatchModeExclude, @"whitelist exclude should block before contains");
        NFAssertMode([NFRuleEngine evaluateRecord:NFRecord(@"plain message") preferences:NFPreferencesWithAppRules(whitelistRules)], YES, NFMatchModeWhitelistDefault, @"whitelist no match should block by default");

        NSDictionary *globalFirstPreferences = [NFPreferences normalizedPreferencesFromDictionary:@{
            NFEnabledKey: @YES,
            NFGlobalRulesEnabledKey: @YES,
            NFGlobalContainsKey: @[ NFRule(@"global-block", NFRuleScopeAll) ],
            NFAppRulesKey: @{ @"com.example.chat": whitelistRules }
        }];
        NFAssertMode([NFRuleEngine evaluateRecord:NFRecord(@"global-block otp") preferences:globalFirstPreferences], YES, NFMatchModeContains, @"global block should run before app whitelist allow");

        NSDictionary *disabledWhitelist = [NFPreferences normalizedRulesDictionaryFromRawDictionary:@{
            NFRulesEnabledKey: @NO,
            NFRulesModeKey: NFRulesModeWhitelist
        }];
        NFAssertMode([NFRuleEngine evaluateRecord:NFRecord(@"plain message") preferences:NFPreferencesWithAppRules(disabledWhitelist)], NO, nil, @"disabled app whitelist should not block");
    }
    return 0;
}
