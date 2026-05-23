#import <Foundation/Foundation.h>
#import "../NotificationFilterPrefs/NFPNotificationRuleTokenBuilder.h"

NSString * const NFRuleEntryIdentifierKey = @"id";
NSString * const NFRuleEntryTextKey = @"text";
NSString * const NFRuleEntryEnabledKey = @"enabled";
NSString * const NFRuleEntryScopeKey = @"scope";
NSString * const NFRuleScopeMessage = @"message";
NSString * const NFRuleScopeTitle = @"title";
NSString * const NFRuleScopeSubtitle = @"subtitle";
NSString * const NFRuleScopeAll = @"all";
NSString * const NFLogTitleKey = @"title";
NSString * const NFLogSubtitleKey = @"subtitle";
NSString * const NFLogBodyKey = @"body";
NSString * const NFLogHeaderKey = @"header";
NSString * const NFLogMessageKey = @"message";

@interface NFPreferences : NSObject
+ (NSDictionary *)ruleEntryWithText:(NSString *)text
                            enabled:(BOOL)enabled
                          identifier:(NSString *)identifier
                               scope:(NSString *)scope;
@end

@implementation NFPreferences

+ (NSDictionary *)ruleEntryWithText:(NSString *)text
                            enabled:(BOOL)enabled
                          identifier:(NSString *)identifier
                               scope:(NSString *)scope {
    return @{
        NFRuleEntryIdentifierKey: identifier.length > 0 ? identifier : @"test-id",
        NFRuleEntryTextKey: text ?: @"",
        NFRuleEntryEnabledKey: @(enabled),
        NFRuleEntryScopeKey: scope ?: NFRuleScopeAll
    };
}

@end

static void NFAssert(BOOL condition, NSString *message) {
    if (!condition) {
        @throw [NSException exceptionWithName:@"NFPNotificationRuleTokenBuilderTestFailure" reason:message userInfo:nil];
    }
}

static void NFAssertArrayEquals(NSArray *actual, NSArray *expected, NSString *message) {
    NFAssert([actual isEqualToArray:expected], [NSString stringWithFormat:@"%@ actual=%@ expected=%@", message, actual, expected]);
}

int main(void) {
    @autoreleasepool {
        NSArray<NSString *> *mixedTokens = [NFPNotificationRuleTokenBuilder tokensFromText:@"限时sale 2026已到"];
        NFAssertArrayEquals(mixedTokens, (@[@"限", @"时", @"sale", @"2026", @"已", @"到"]), @"mixed Chinese and English tokens should keep every Chinese character and every English word");

        NSArray<NSString *> *duplicateTokens = [NFPNotificationRuleTokenBuilder tokensFromText:@"哈哈OK OK"];
        NFAssertArrayEquals(duplicateTokens, (@[@"哈", @"哈", @"OK", @"OK"]), @"duplicate characters and words should remain selectable");

        NSDictionary *entry = @{
            NFLogTitleKey: @"限时sale",
            NFLogBodyKey: @"马上到"
        };
        NSArray<NSDictionary *> *sections = [NFPNotificationRuleTokenBuilder tokenSectionsFromNotificationEntry:entry];
        NFAssert(sections.count == 2, @"title and message sections should both be built");

        NSString *titleScope = sections[0][NFPNotificationRuleTokenSectionScopeKey];
        NSArray<NSString *> *titleTokens = sections[0][NFPNotificationRuleTokenSectionTokensKey];
        NSString *messageScope = sections[1][NFPNotificationRuleTokenSectionScopeKey];
        NSArray<NSString *> *messageTokens = sections[1][NFPNotificationRuleTokenSectionTokensKey];
        NFAssertArrayEquals(titleTokens, (@[@"限", @"时", @"sale"]), @"title tokens should stay in source order");
        NFAssertArrayEquals(messageTokens, (@[@"马", @"上", @"到"]), @"message tokens should stay in source order");

        NSSet<NSString *> *sameScopeSelection = [NSSet setWithObjects:
            [NFPNotificationRuleTokenBuilder selectionKeyForScope:messageScope tokenIndex:0 token:messageTokens[0]],
            [NFPNotificationRuleTokenBuilder selectionKeyForScope:messageScope tokenIndex:2 token:messageTokens[2]],
            nil];
        NSArray<NSDictionary *> *sameScopeEntries = [NFPNotificationRuleTokenBuilder ruleEntriesFromTokenSections:sections
                                                                                                  selectedTokenKeys:sameScopeSelection
                                                                                                      defaultScope:NFRuleScopeMessage];
        NFAssert(sameScopeEntries.count == 1, @"one scan save should create exactly one rule for same-scope selection");
        NFAssert([sameScopeEntries[0][NFRuleEntryTextKey] isEqualToString:@"马到"], @"non-contiguous characters should be connected inside one rule");
        NFAssert([sameScopeEntries[0][NFRuleEntryScopeKey] isEqualToString:NFRuleScopeMessage], @"same-scope selection should keep that scope");

        NSSet<NSString *> *mixedScopeSelection = [NSSet setWithObjects:
            [NFPNotificationRuleTokenBuilder selectionKeyForScope:titleScope tokenIndex:2 token:titleTokens[2]],
            [NFPNotificationRuleTokenBuilder selectionKeyForScope:messageScope tokenIndex:2 token:messageTokens[2]],
            nil];
        NSArray<NSDictionary *> *mixedScopeEntries = [NFPNotificationRuleTokenBuilder ruleEntriesFromTokenSections:sections
                                                                                                 selectedTokenKeys:mixedScopeSelection
                                                                                                      defaultScope:NFRuleScopeMessage];
        NFAssert(mixedScopeEntries.count == 1, @"one scan save should create exactly one rule across scopes");
        NFAssert([mixedScopeEntries[0][NFRuleEntryTextKey] isEqualToString:@"sale到"], @"mixed selected pieces should be connected in section order");
        NFAssert([mixedScopeEntries[0][NFRuleEntryScopeKey] isEqualToString:NFRuleScopeAll], @"cross-scope selection should fall back to all-text matching");
    }
    return 0;
}
