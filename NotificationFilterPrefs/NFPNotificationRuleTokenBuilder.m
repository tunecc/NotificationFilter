#import "NFPNotificationRuleTokenBuilder.h"
#import "../Shared/NFPreferences.h"

NSString * const NFPNotificationRuleTokenSectionScopeKey = @"scope";
NSString * const NFPNotificationRuleTokenSectionTokensKey = @"tokens";

static NSString * const NFPNotificationRuleTokenSelectionSeparator = @"\n";

@implementation NFPNotificationRuleTokenBuilder

+ (NSArray<NSDictionary *> *)tokenSectionsFromNotificationEntry:(NSDictionary *)entry {
    NSMutableArray<NSDictionary *> *sections = [NSMutableArray array];

    [self appendSectionWithScope:NFRuleScopeTitle
                        rawTexts:@[entry[NFLogTitleKey] ?: @""]
                      toSections:sections];
    [self appendSectionWithScope:NFRuleScopeSubtitle
                        rawTexts:@[entry[NFLogSubtitleKey] ?: @""]
                      toSections:sections];
    [self appendSectionWithScope:NFRuleScopeMessage
                        rawTexts:@[entry[NFLogHeaderKey] ?: @"", entry[NFLogBodyKey] ?: @"", entry[NFLogMessageKey] ?: @""]
                      toSections:sections];

    return sections;
}

+ (void)appendSectionWithScope:(NSString *)scope
                      rawTexts:(NSArray *)rawTexts
                    toSections:(NSMutableArray<NSDictionary *> *)sections {
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];

    for (id rawText in rawTexts) {
        [tokens addObjectsFromArray:[self tokensFromText:rawText]];
    }

    if (tokens.count == 0) {
        return;
    }

    [sections addObject:@{
        NFPNotificationRuleTokenSectionScopeKey: scope,
        NFPNotificationRuleTokenSectionTokensKey: tokens
    }];
}

+ (NSArray<NSString *> *)tokensFromText:(id)rawText {
    if (![rawText isKindOfClass:[NSString class]]) {
        return @[];
    }

    NSString *text = [(NSString *)rawText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) {
        return @[];
    }

    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    NSMutableString *currentWord = [NSMutableString string];
    NSCharacterSet *lettersAndDigits = [NSCharacterSet alphanumericCharacterSet];
    NSCharacterSet *whitespaceAndNewlines = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSCharacterSet *punctuation = [NSCharacterSet punctuationCharacterSet];

    void (^flushCurrentWord)(void) = ^{
        if (currentWord.length > 0) {
            [tokens addObject:[currentWord copy]];
            [currentWord setString:@""];
        }
    };

    [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        if (substring.length == 0) {
            return;
        }

        unichar character = [substring characterAtIndex:0];
        if ([whitespaceAndNewlines characterIsMember:character]) {
            flushCurrentWord();
            return;
        }

        if ([punctuation characterIsMember:character]) {
            flushCurrentWord();
            return;
        }

        if ([self characterIsCJK:character]) {
            flushCurrentWord();
            [tokens addObject:substring];
            return;
        }

        if ([lettersAndDigits characterIsMember:character]) {
            [currentWord appendString:substring];
            return;
        }

        flushCurrentWord();
        [tokens addObject:substring];
    }];

    flushCurrentWord();
    return tokens;
}

+ (BOOL)characterIsCJK:(unichar)character {
    return (character >= 0x3400 && character <= 0x4DBF) ||
           (character >= 0x4E00 && character <= 0x9FFF) ||
           (character >= 0xF900 && character <= 0xFAFF);
}

+ (NSString *)selectionKeyForScope:(NSString *)scope
                        tokenIndex:(NSUInteger)tokenIndex
                             token:(NSString *)token {
    return [NSString stringWithFormat:@"%@%@%lu%@%@", scope ?: @"", NFPNotificationRuleTokenSelectionSeparator, (unsigned long)tokenIndex, NFPNotificationRuleTokenSelectionSeparator, token ?: @""];
}

+ (NSArray<NSDictionary *> *)ruleEntriesFromTokenSections:(NSArray<NSDictionary *> *)tokenSections
                                         selectedTokenKeys:(NSSet<NSString *> *)selectedTokenKeys
                                             defaultScope:(NSString *)defaultScope {
    if (selectedTokenKeys.count == 0) {
        return @[];
    }

    NSMutableArray<NSString *> *selectedTokens = [NSMutableArray array];
    NSString *resolvedScope = nil;
    BOOL mixedScopes = NO;

    for (NSDictionary *section in tokenSections) {
        NSString *scope = [section[NFPNotificationRuleTokenSectionScopeKey] isKindOfClass:[NSString class]] ? section[NFPNotificationRuleTokenSectionScopeKey] : defaultScope;
        NSArray<NSString *> *tokens = [section[NFPNotificationRuleTokenSectionTokensKey] isKindOfClass:[NSArray class]] ? section[NFPNotificationRuleTokenSectionTokensKey] : @[];
        for (NSUInteger tokenIndex = 0; tokenIndex < tokens.count; tokenIndex++) {
            NSString *token = tokens[tokenIndex];
            NSString *selectionKey = [self selectionKeyForScope:scope tokenIndex:tokenIndex token:token];
            if (![selectedTokenKeys containsObject:selectionKey]) {
                continue;
            }

            [selectedTokens addObject:token];
            if (!resolvedScope) {
                resolvedScope = scope;
            } else if (![resolvedScope isEqualToString:scope]) {
                mixedScopes = YES;
            }
        }
    }

    NSString *ruleText = [selectedTokens componentsJoinedByString:@""];
    if (ruleText.length == 0) {
        return @[];
    }

    NSString *entryScope = mixedScopes ? NFRuleScopeAll : (resolvedScope ?: defaultScope);
    return @[
        [NFPreferences ruleEntryWithText:ruleText
                                 enabled:YES
                               identifier:nil
                                    scope:entryScope ?: NFRuleScopeMessage]
    ];
}

@end
