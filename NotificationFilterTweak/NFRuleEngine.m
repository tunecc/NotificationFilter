#import "NFRuleEngine.h"
#import "NFNotificationRecord.h"
#import "../Shared/NFPreferences.h"

@implementation NFMatchResult
@end

@implementation NFRuleEngine

+ (NFMatchResult *)_allowResult {
    NFMatchResult *result = [[NFMatchResult alloc] init];
    result.shouldBlock = NO;
    return result;
}

+ (NFMatchResult *)_resultWithShouldBlock:(BOOL)shouldBlock
                                    scope:(NSString *)scope
                                     mode:(NSString *)mode
                                  pattern:(NSString *)pattern {
    NFMatchResult *result = [[NFMatchResult alloc] init];
    result.shouldBlock = shouldBlock;
    result.matchedScope = scope;
    result.matchedMode = mode;
    result.matchedPattern = pattern;
    return result;
}

+ (NSString *)_scopeNameForBundleIdentifier:(NSString *)bundleIdentifier {
    return [NSString stringWithFormat:@"app:%@", bundleIdentifier];
}

+ (NSString * _Nullable)_firstMatchingContainsRuleInRules:(NSArray<NSString *> *)rules text:(NSString *)text {
    for (NSString *rule in rules) {
        if ([text rangeOfString:rule options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return rule;
        }
    }
    return nil;
}

+ (NSString * _Nullable)_firstMatchingRegexRuleInRules:(NSArray<NSString *> *)rules text:(NSString *)text {
    for (NSString *rule in rules) {
        NSError *error = nil;
        NSRegularExpression *regularExpression = [NSRegularExpression regularExpressionWithPattern:rule
                                                                                           options:NSRegularExpressionCaseInsensitive
                                                                                             error:&error];
        if (error || !regularExpression) {
            continue;
        }

        if ([regularExpression firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) {
            return rule;
        }
    }
    return nil;
}

+ (NSString *)_textForScope:(NSString *)scope record:(NFNotificationRecord *)record defaultScope:(NSString *)defaultScope {
    NSString *resolvedScope = [NFPreferences ruleScopeFromEntry:@{ NFRuleEntryScopeKey: scope ?: @"" }
                                                  defaultScope:defaultScope];
    if ([resolvedScope isEqualToString:NFRuleScopeTitle]) {
        return record.title ?: @"";
    }
    if ([resolvedScope isEqualToString:NFRuleScopeSubtitle]) {
        return record.subtitle ?: @"";
    }
    if ([resolvedScope isEqualToString:NFRuleScopeMessage]) {
        return record.messageText ?: @"";
    }
    return record.joinedText ?: @"";
}

+ (NSString * _Nullable)_firstMatchingRuleEntryInRules:(NSArray *)rawRules
                                           defaultScope:(NSString *)defaultScope
                                                  regex:(BOOL)regex
                                                 record:(NFNotificationRecord *)record {
    for (NSDictionary *ruleEntry in [NFPreferences activeRuleEntriesFromArray:rawRules defaultScope:defaultScope]) {
        NSString *ruleText = [NFPreferences ruleTextFromEntry:ruleEntry];
        NSString *matchText = [self _textForScope:[NFPreferences ruleScopeFromEntry:ruleEntry defaultScope:defaultScope]
                                           record:record
                                     defaultScope:defaultScope];
        NSArray *singleRule = ruleText.length > 0 ? @[ruleText] : @[];
        NSString *matchedRule = regex ? [self _firstMatchingRegexRuleInRules:singleRule text:matchText] : [self _firstMatchingContainsRuleInRules:singleRule text:matchText];
        if (matchedRule.length > 0) {
            return matchedRule;
        }
    }
    return nil;
}

+ (NFMatchResult * _Nullable)_evaluateBlacklistRules:(NSDictionary *)rules
                                           scopeName:(NSString *)scopeName
                                              record:(NFNotificationRecord *)record {
    NSString *matchedExclude = [self _firstMatchingRuleEntryInRules:rules[NFRulesExcludeKey]
                                                       defaultScope:NFRuleScopeAll
                                                              regex:NO
                                                             record:record];
    if (matchedExclude.length > 0) {
        return [self _resultWithShouldBlock:NO
                                      scope:scopeName
                                       mode:NFMatchModeExclude
                                    pattern:matchedExclude];
    }

    NSString *matchedContains = [self _firstMatchingRuleEntryInRules:rules[NFRulesContainsKey]
                                                        defaultScope:NFRuleScopeMessage
                                                               regex:NO
                                                              record:record];
    if (matchedContains.length > 0) {
        return [self _resultWithShouldBlock:YES
                                      scope:scopeName
                                       mode:NFMatchModeContains
                                    pattern:matchedContains];
    }

    NSString *matchedRegex = [self _firstMatchingRuleEntryInRules:rules[NFRulesRegexKey]
                                                     defaultScope:NFRuleScopeAll
                                                            regex:YES
                                                           record:record];
    if (matchedRegex.length > 0) {
        return [self _resultWithShouldBlock:YES
                                      scope:scopeName
                                       mode:NFMatchModeRegex
                                    pattern:matchedRegex];
    }

    return nil;
}

+ (NFMatchResult * _Nullable)_evaluateAppRules:(NSDictionary *)rules
                                     scopeName:(NSString *)scopeName
                                        record:(NFNotificationRecord *)record {
    NSString *mode = [NFPreferences normalizedRulesMode:rules[NFRulesModeKey]];
    BOOL whitelist = [mode isEqualToString:NFRulesModeWhitelist];

    NSString *matchedExclude = [self _firstMatchingRuleEntryInRules:rules[NFRulesExcludeKey]
                                                       defaultScope:NFRuleScopeAll
                                                              regex:NO
                                                             record:record];
    if (matchedExclude.length > 0) {
        return [self _resultWithShouldBlock:whitelist
                                      scope:scopeName
                                       mode:NFMatchModeExclude
                                    pattern:matchedExclude];
    }

    NSString *matchedContains = [self _firstMatchingRuleEntryInRules:rules[NFRulesContainsKey]
                                                        defaultScope:NFRuleScopeMessage
                                                               regex:NO
                                                              record:record];
    if (matchedContains.length > 0) {
        return [self _resultWithShouldBlock:!whitelist
                                      scope:scopeName
                                       mode:NFMatchModeContains
                                    pattern:matchedContains];
    }

    NSString *matchedRegex = [self _firstMatchingRuleEntryInRules:rules[NFRulesRegexKey]
                                                     defaultScope:NFRuleScopeAll
                                                            regex:YES
                                                           record:record];
    if (matchedRegex.length > 0) {
        return [self _resultWithShouldBlock:!whitelist
                                      scope:scopeName
                                       mode:NFMatchModeRegex
                                    pattern:matchedRegex];
    }

    if (whitelist) {
        return [self _resultWithShouldBlock:YES
                                      scope:scopeName
                                       mode:NFMatchModeWhitelistDefault
                                    pattern:nil];
    }

    return nil;
}

+ (NFMatchResult *)evaluateRecord:(NFNotificationRecord *)record
                      preferences:(NSDictionary *)preferences {
    if (![preferences[NFEnabledKey] boolValue]) {
        return [self _allowResult];
    }

    NSString *joinedText = record.joinedText ?: @"";
    NSString *messageText = record.messageText ?: @"";
    if (joinedText.length == 0 && messageText.length == 0) {
        return [self _allowResult];
    }

    NSDictionary *globalRules = [NFPreferences globalRulesFromPreferences:preferences];
    if ([globalRules[NFRulesEnabledKey] boolValue]) {
        NFMatchResult *globalResult = [self _evaluateBlacklistRules:globalRules
                                                          scopeName:NFMatchScopeGlobal
                                                             record:record];
        if (globalResult) {
            return globalResult;
        }
    }

    if (record.bundleIdentifier.length > 0) {
        NSDictionary *appRules = [NFPreferences rulesForBundleIdentifier:record.bundleIdentifier
                                                         fromPreferences:preferences];
        if ([appRules[NFRulesEnabledKey] boolValue]) {
            NFMatchResult *appResult = [self _evaluateAppRules:appRules
                                                     scopeName:[self _scopeNameForBundleIdentifier:record.bundleIdentifier]
                                                        record:record];
            if (appResult) {
                return appResult;
            }
        }
    }

    return [self _allowResult];
}

@end
