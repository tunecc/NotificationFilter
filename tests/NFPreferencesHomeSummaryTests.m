#import <Foundation/Foundation.h>
#import "../Shared/NFPreferences.h"

static void NFAssert(BOOL condition, NSString *message) {
    if (!condition) {
        @throw [NSException exceptionWithName:@"NFPreferencesHomeSummaryTestFailure" reason:message userInfo:nil];
    }
}

int main(void) {
    @autoreleasepool {
        NFAssert([NFPreferences globalRuleEntryCountFromPreferences:@{}] == 0,
                 @"empty preferences should have zero global rules");
        NFAssert([NFPreferences enabledAppRulesCountFromPreferences:@{}] == 0,
                 @"empty preferences should have zero enabled apps");

        NSDictionary *disabledEntry = [NFPreferences ruleEntryWithText:@"ad"
                                                               enabled:NO
                                                            identifier:@"disabled-1"
                                                                 scope:NFRuleScopeAll];
        NSDictionary *globalPrefs = @{
            NFGlobalRulesEnabledKey: @YES,
            NFGlobalContainsKey: @[ @"promo" ],
            NFGlobalExcludeKey: @[ disabledEntry ],
            NFGlobalRegexKey: @[ @"code\\d+" ]
        };
        NFAssert([NFPreferences globalRuleEntryCountFromPreferences:globalPrefs] == 3,
                 @"global count should sum contains/exclude/regex including disabled entries");

        NSDictionary *closedGlobal = @{
            NFGlobalRulesEnabledKey: @NO,
            NFGlobalContainsKey: @[ @"promo", @"sale" ]
        };
        NFAssert([NFPreferences globalRuleEntryCountFromPreferences:closedGlobal] == 2,
                 @"global count is independent of the enabled switch");

        NSDictionary *appPrefs = @{
            NFAppRulesKey: @{
                @"com.a": @{
                    NFRulesEnabledKey: @YES
                },
                @"com.b": @{
                    NFRulesEnabledKey: @NO,
                    NFRulesContainsKey: @[ @"otp" ]
                },
                @"com.c": @{
                    NFRulesEnabledKey: @YES,
                    NFRulesContainsKey: @[ @"ad" ]
                }
            }
        };
        NFAssert([NFPreferences enabledAppRulesCountFromPreferences:appPrefs] == 2,
                 @"enabled app count should include apps whose switch is on, even without rules");
    }
    return 0;
}
