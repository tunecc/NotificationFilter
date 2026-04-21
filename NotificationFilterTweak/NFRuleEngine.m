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

    NSMutableArray<NSDictionary *> *scopes = [NSMutableArray array];
    NSDictionary *globalRules = [NFPreferences globalRulesFromPreferences:preferences];
    if ([globalRules[NFRulesEnabledKey] boolValue]) {
        [scopes addObject:@{
            @"name": NFMatchScopeGlobal,
            @"rules": globalRules
        }];
    }

    if (record.bundleIdentifier.length > 0) {
        NSDictionary *appRules = [NFPreferences rulesForBundleIdentifier:record.bundleIdentifier
                                                         fromPreferences:preferences];
        if ([appRules[NFRulesEnabledKey] boolValue]) {
            [scopes addObject:@{
                @"name": [self _scopeNameForBundleIdentifier:record.bundleIdentifier],
                @"rules": appRules
            }];
        }
    }

    for (NSDictionary *scope in scopes) {
        NSDictionary *rules = scope[@"rules"];
        for (NSDictionary *ruleEntry in [NFPreferences activeRuleEntriesFromArray:rules[NFRulesExcludeKey]
                                                                     defaultScope:NFRuleScopeAll]) {
            NSString *ruleText = [NFPreferences ruleTextFromEntry:ruleEntry];
            NSString *matchText = [self _textForScope:[NFPreferences ruleScopeFromEntry:ruleEntry defaultScope:NFRuleScopeAll]
                                               record:record
                                         defaultScope:NFRuleScopeAll];
            NSString *matchedRule = [self _firstMatchingContainsRuleInRules:ruleText.length > 0 ? @[ruleText] : @[]
                                                                       text:matchText];
            if (matchedRule.length > 0) {
                NFMatchResult *result = [[NFMatchResult alloc] init];
                result.shouldBlock = NO;
                result.matchedScope = scope[@"name"];
                result.matchedMode = NFMatchModeExclude;
                result.matchedPattern = matchedRule;
                return result;
            }
        }
    }

    for (NSDictionary *scope in scopes) {
        NSDictionary *rules = scope[@"rules"];
        for (NSDictionary *ruleEntry in [NFPreferences activeRuleEntriesFromArray:rules[NFRulesContainsKey]
                                                                     defaultScope:NFRuleScopeMessage]) {
            NSString *ruleText = [NFPreferences ruleTextFromEntry:ruleEntry];
            NSString *matchText = [self _textForScope:[NFPreferences ruleScopeFromEntry:ruleEntry defaultScope:NFRuleScopeMessage]
                                               record:record
                                         defaultScope:NFRuleScopeMessage];
            NSString *matchedContainsRule = [self _firstMatchingContainsRuleInRules:ruleText.length > 0 ? @[ruleText] : @[]
                                                                                text:matchText];
            if (matchedContainsRule.length > 0) {
                NFMatchResult *result = [[NFMatchResult alloc] init];
                result.shouldBlock = YES;
                result.matchedScope = scope[@"name"];
                result.matchedMode = NFMatchModeContains;
                result.matchedPattern = matchedContainsRule;
                return result;
            }
        }

        for (NSDictionary *ruleEntry in [NFPreferences activeRuleEntriesFromArray:rules[NFRulesRegexKey]
                                                                     defaultScope:NFRuleScopeAll]) {
            NSString *ruleText = [NFPreferences ruleTextFromEntry:ruleEntry];
            NSString *matchText = [self _textForScope:[NFPreferences ruleScopeFromEntry:ruleEntry defaultScope:NFRuleScopeAll]
                                               record:record
                                         defaultScope:NFRuleScopeAll];
            NSString *matchedRegexRule = [self _firstMatchingRegexRuleInRules:ruleText.length > 0 ? @[ruleText] : @[]
                                                                         text:matchText];
            if (matchedRegexRule.length > 0) {
                NFMatchResult *result = [[NFMatchResult alloc] init];
                result.shouldBlock = YES;
                result.matchedScope = scope[@"name"];
                result.matchedMode = NFMatchModeRegex;
                result.matchedPattern = matchedRegexRule;
                return result;
            }
        }
    }

    return [self _allowResult];
}

@end
