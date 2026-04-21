#import "NFPreferences.h"
#import <CoreFoundation/CoreFoundation.h>
#import <roothide/stub.h>

NSString * const NFPreferencesIdentifier = @"com.tune.notificationfilter";
NSString * const NFPreferencesChangedDarwinNotification = @"com.tune.notificationfilter/preferences-changed";

NSString * const NFEnabledKey = @"Enabled";
NSString * const NFGlobalRulesEnabledKey = @"GlobalRulesEnabled";
NSString * const NFGlobalContainsKey = @"GlobalContains";
NSString * const NFGlobalExcludeKey = @"GlobalExclude";
NSString * const NFGlobalRegexKey = @"GlobalRegex";
NSString * const NFAppRulesKey = @"AppRules";
NSString * const NFPrefOnlyConfiguredAppsKey = @"PrefOnlyConfiguredApps";
NSString * const NFPrefShowSystemAppsKey = @"PrefShowSystemApps";
NSString * const NFPrefShowTrollAppsKey = @"PrefShowTrollApps";

NSString * const NFRulesEnabledKey = @"enabled";
NSString * const NFRulesContainsKey = @"contains";
NSString * const NFRulesExcludeKey = @"exclude";
NSString * const NFRulesRegexKey = @"regex";
NSString * const NFRuleEntryIdentifierKey = @"id";
NSString * const NFRuleEntryTextKey = @"text";
NSString * const NFRuleEntryEnabledKey = @"enabled";
NSString * const NFRuleEntryScopeKey = @"scope";
NSString * const NFRuleScopeMessage = @"message";
NSString * const NFRuleScopeTitle = @"title";
NSString * const NFRuleScopeSubtitle = @"subtitle";
NSString * const NFRuleScopeAll = @"all";

NSString * const NFLogIdentifierKey = @"id";
NSString * const NFLogTimestampKey = @"timestamp";
NSString * const NFLogBundleIdentifierKey = @"bundleID";
NSString * const NFLogTitleKey = @"title";
NSString * const NFLogSubtitleKey = @"subtitle";
NSString * const NFLogBodyKey = @"body";
NSString * const NFLogHeaderKey = @"header";
NSString * const NFLogMessageKey = @"message";
NSString * const NFLogJoinedTextKey = @"joinedText";
NSString * const NFLogMatchedScopeKey = @"matchedScope";
NSString * const NFLogMatchedModeKey = @"matchedMode";
NSString * const NFLogMatchedPatternKey = @"matchedPattern";

NSString * const NFMatchScopeGlobal = @"global";
NSString * const NFMatchModeExclude = @"exclude";
NSString * const NFMatchModeContains = @"contains";
NSString * const NFMatchModeRegex = @"regex";

@implementation NFPreferences

+ (NSArray<NSString *> *)_allPreferenceKeys {
    return @[
        NFEnabledKey,
        NFGlobalRulesEnabledKey,
        NFGlobalContainsKey,
        NFGlobalExcludeKey,
        NFGlobalRegexKey,
        NFAppRulesKey,
        NFPrefOnlyConfiguredAppsKey,
        NFPrefShowSystemAppsKey,
        NFPrefShowTrollAppsKey
    ];
}

+ (NSDictionary *)defaultPreferences {
    return @{
        NFEnabledKey: @YES,
        NFGlobalRulesEnabledKey: @NO,
        NFGlobalContainsKey: @[],
        NFGlobalExcludeKey: @[],
        NFGlobalRegexKey: @[],
        NFAppRulesKey: @{},
        NFPrefOnlyConfiguredAppsKey: @NO,
        NFPrefShowSystemAppsKey: @YES,
        NFPrefShowTrollAppsKey: @YES
    };
}

+ (NSDictionary *)loadPreferences {
    NSMutableDictionary *rawPreferences = [NSMutableDictionary dictionary];

    for (NSString *key in [self _allPreferenceKeys]) {
        CFPropertyListRef value = CFPreferencesCopyAppValue((CFStringRef)key, (CFStringRef)NFPreferencesIdentifier);
        if (value) {
            rawPreferences[key] = CFBridgingRelease(value);
        }
    }

    return [self normalizedPreferencesFromDictionary:rawPreferences];
}

+ (NSMutableDictionary *)loadMutablePreferences {
    return [[self loadPreferences] mutableCopy];
}

+ (BOOL)savePreferences:(NSDictionary *)preferences error:(NSError **)error {
    NSDictionary *normalizedPreferences = [self normalizedPreferencesFromDictionary:preferences];

    for (NSString *key in [self _allPreferenceKeys]) {
        id value = normalizedPreferences[key];
        CFPreferencesSetAppValue((CFStringRef)key,
                                 value ? (__bridge CFPropertyListRef)value : NULL,
                                 (CFStringRef)NFPreferencesIdentifier);
    }

    Boolean synchronized = CFPreferencesAppSynchronize((CFStringRef)NFPreferencesIdentifier);
    if (!synchronized && error) {
        *error = [NSError errorWithDomain:NFPreferencesIdentifier
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to synchronize preferences."}];
    }

    return synchronized;
}

+ (void)postPreferencesChangedNotification {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)NFPreferencesChangedDarwinNotification,
                                         NULL,
                                         NULL,
                                         YES);
}

+ (NSDictionary *)globalRulesFromPreferences:(NSDictionary *)preferences {
    NSDictionary *normalizedPreferences = [self normalizedPreferencesFromDictionary:preferences];
    return [self normalizedRulesDictionaryFromEnabled:[normalizedPreferences[NFGlobalRulesEnabledKey] boolValue]
                                             contains:normalizedPreferences[NFGlobalContainsKey]
                                              exclude:normalizedPreferences[NFGlobalExcludeKey]
                                                regex:normalizedPreferences[NFGlobalRegexKey]];
}

+ (NSDictionary *)rulesForBundleIdentifier:(NSString *)bundleIdentifier
                           fromPreferences:(NSDictionary *)preferences {
    if (bundleIdentifier.length == 0) {
        return nil;
    }

    NSDictionary *normalizedPreferences = [self normalizedPreferencesFromDictionary:preferences];
    NSDictionary *appRules = normalizedPreferences[NFAppRulesKey];
    return [self normalizedRulesDictionaryFromRawDictionary:appRules[bundleIdentifier]];
}

+ (NSDictionary *)normalizedRulesDictionaryFromRawDictionary:(NSDictionary *)rawRules {
    if (![rawRules isKindOfClass:[NSDictionary class]]) {
        return [self normalizedRulesDictionaryFromEnabled:NO contains:nil exclude:nil regex:nil];
    }

    BOOL enabled = [rawRules[NFRulesEnabledKey] respondsToSelector:@selector(boolValue)] ? [rawRules[NFRulesEnabledKey] boolValue] : NO;
    return [self normalizedRulesDictionaryFromEnabled:enabled
                                             contains:rawRules[NFRulesContainsKey]
                                              exclude:rawRules[NFRulesExcludeKey]
                                                regex:rawRules[NFRulesRegexKey]];
}

+ (NSDictionary *)normalizedRulesDictionaryFromEnabled:(BOOL)enabled
                                              contains:(NSArray *)contains
                                               exclude:(NSArray *)exclude
                                                 regex:(NSArray *)regex {
    return @{
        NFRulesEnabledKey: @(enabled),
        NFRulesContainsKey: [self normalizedRuleEntriesFromArray:contains defaultScope:NFRuleScopeMessage],
        NFRulesExcludeKey: [self normalizedRuleEntriesFromArray:exclude defaultScope:NFRuleScopeAll],
        NFRulesRegexKey: [self normalizedRuleEntriesFromArray:regex defaultScope:NFRuleScopeAll]
    };
}

+ (BOOL)rulesDictionaryHasConfiguredValues:(NSDictionary *)rules {
    if (![rules isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    if ([rules[NFRulesEnabledKey] boolValue]) {
        return YES;
    }

    return [rules[NFRulesContainsKey] count] > 0 ||
           [rules[NFRulesExcludeKey] count] > 0 ||
           [rules[NFRulesRegexKey] count] > 0;
}

+ (NSArray<NSDictionary *> *)normalizedRuleEntriesFromArray:(NSArray *)rawRules {
    return [self normalizedRuleEntriesFromArray:rawRules defaultScope:NFRuleScopeAll];
}

+ (NSArray<NSDictionary *> *)normalizedRuleEntriesFromArray:(NSArray *)rawRules
                                              defaultScope:(NSString *)defaultScope {
    if (![rawRules isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (id rawRule in rawRules) {
        NSString *identifier = nil;
        NSString *text = nil;
        BOOL enabled = YES;
        NSString *scope = defaultScope;

        if ([rawRule isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dictionary = rawRule;
            id textValue = dictionary[NFRuleEntryTextKey] ?: dictionary[@"value"];
            if ([dictionary[NFRuleEntryEnabledKey] respondsToSelector:@selector(boolValue)]) {
                enabled = [dictionary[NFRuleEntryEnabledKey] boolValue];
            }
            if ([dictionary[NFRuleEntryScopeKey] isKindOfClass:[NSString class]] &&
                [dictionary[NFRuleEntryScopeKey] length] > 0) {
                scope = dictionary[NFRuleEntryScopeKey];
            }
            if ([dictionary[NFRuleEntryIdentifierKey] isKindOfClass:[NSString class]] &&
                [dictionary[NFRuleEntryIdentifierKey] length] > 0) {
                identifier = dictionary[NFRuleEntryIdentifierKey];
            }
            text = [self _normalizedRuleText:textValue];
        } else {
            text = [self _normalizedRuleText:rawRule];
        }

        if (text.length == 0) {
            continue;
        }

        [entries addObject:[self ruleEntryWithText:text
                                           enabled:enabled
                                         identifier:identifier
                                              scope:[self _normalizedRuleScope:scope defaultScope:defaultScope]]];
    }

    return entries;
}

+ (NSArray<NSString *> *)activeRuleTextsFromRuleEntries:(NSArray *)rawRules {
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSDictionary *entry in [self normalizedRuleEntriesFromArray:rawRules]) {
        if (![self ruleEntryEnabled:entry]) {
            continue;
        }

        NSString *text = [self ruleTextFromEntry:entry];
        if (text.length > 0) {
            [texts addObject:text];
        }
    }

    return texts;
}

+ (NSArray<NSDictionary *> *)activeRuleEntriesFromArray:(NSArray *)rawRules
                                          defaultScope:(NSString *)defaultScope {
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (NSDictionary *entry in [self normalizedRuleEntriesFromArray:rawRules defaultScope:defaultScope]) {
        if ([self ruleEntryEnabled:entry]) {
            [entries addObject:entry];
        }
    }
    return entries;
}

+ (NSString *)ruleTextFromEntry:(NSDictionary *)entry {
    if (![entry isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    return [self _normalizedRuleText:entry[NFRuleEntryTextKey]];
}

+ (BOOL)ruleEntryEnabled:(NSDictionary *)entry {
    if (![entry isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    if ([entry[NFRuleEntryEnabledKey] respondsToSelector:@selector(boolValue)]) {
        return [entry[NFRuleEntryEnabledKey] boolValue];
    }

    return YES;
}

+ (NSString *)ruleScopeFromEntry:(NSDictionary *)entry
                    defaultScope:(NSString *)defaultScope {
    if (![entry isKindOfClass:[NSDictionary class]]) {
        return [self _normalizedRuleScope:nil defaultScope:defaultScope];
    }

    return [self _normalizedRuleScope:entry[NFRuleEntryScopeKey] defaultScope:defaultScope];
}

+ (NSDictionary *)ruleEntryWithText:(NSString *)text
                            enabled:(BOOL)enabled
                          identifier:(NSString *)identifier
                               scope:(NSString *)scope {
    NSString *normalizedText = [self _normalizedRuleText:text];
    NSString *resolvedIdentifier = identifier.length > 0 ? identifier : [NSUUID UUID].UUIDString;
    return @{
        NFRuleEntryIdentifierKey: resolvedIdentifier,
        NFRuleEntryTextKey: normalizedText ?: @"",
        NFRuleEntryEnabledKey: @(enabled),
        NFRuleEntryScopeKey: [self _normalizedRuleScope:scope defaultScope:NFRuleScopeAll]
    };
}

+ (NSArray<NSString *> *)normalizedRuleLinesFromArray:(NSArray *)rawRules {
    if (![rawRules isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<NSString *> *normalizedRules = [NSMutableArray array];
    NSMutableSet<NSString *> *seenRules = [NSMutableSet set];

    for (id rawValue in rawRules) {
        id value = rawValue;
        if (![value respondsToSelector:@selector(description)]) {
            continue;
        }

        if ([value isKindOfClass:[NSDictionary class]]) {
            value = [self ruleTextFromEntry:value];
        }

        NSString *rule = [[value description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (rule.length == 0 || [seenRules containsObject:rule]) {
            continue;
        }

        [seenRules addObject:rule];
        [normalizedRules addObject:rule];
    }

    return normalizedRules;
}

+ (NSArray<NSString *> *)normalizedRuleLinesFromMultilineString:(NSString *)multilineString {
    if (![multilineString isKindOfClass:[NSString class]] || multilineString.length == 0) {
        return @[];
    }

    NSArray<NSString *> *components = [multilineString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    return [self normalizedRuleLinesFromArray:components];
}

+ (NSString *)multilineStringFromRuleLines:(NSArray<NSString *> *)rules {
    return [[self normalizedRuleLinesFromArray:rules] componentsJoinedByString:@"\n"];
}

+ (NSString *)logsFilePath {
    return jbroot(@"/var/mobile/Library/Preferences/com.tune.notificationfilter.logs.plist");
}

+ (NSDictionary *)normalizedPreferencesFromDictionary:(NSDictionary *)rawPreferences {
    NSDictionary *defaultPreferences = [self defaultPreferences];
    NSMutableDictionary *normalizedPreferences = [defaultPreferences mutableCopy];

    if ([rawPreferences[NFEnabledKey] respondsToSelector:@selector(boolValue)]) {
        normalizedPreferences[NFEnabledKey] = @([rawPreferences[NFEnabledKey] boolValue]);
    }

    if ([rawPreferences[NFGlobalRulesEnabledKey] respondsToSelector:@selector(boolValue)]) {
        normalizedPreferences[NFGlobalRulesEnabledKey] = @([rawPreferences[NFGlobalRulesEnabledKey] boolValue]);
    }
    if ([rawPreferences[NFPrefOnlyConfiguredAppsKey] respondsToSelector:@selector(boolValue)]) {
        normalizedPreferences[NFPrefOnlyConfiguredAppsKey] = @([rawPreferences[NFPrefOnlyConfiguredAppsKey] boolValue]);
    }
    if ([rawPreferences[NFPrefShowSystemAppsKey] respondsToSelector:@selector(boolValue)]) {
        normalizedPreferences[NFPrefShowSystemAppsKey] = @([rawPreferences[NFPrefShowSystemAppsKey] boolValue]);
    }
    if ([rawPreferences[NFPrefShowTrollAppsKey] respondsToSelector:@selector(boolValue)]) {
        normalizedPreferences[NFPrefShowTrollAppsKey] = @([rawPreferences[NFPrefShowTrollAppsKey] boolValue]);
    }

    normalizedPreferences[NFGlobalContainsKey] = [self normalizedRuleEntriesFromArray:rawPreferences[NFGlobalContainsKey] defaultScope:NFRuleScopeMessage];
    normalizedPreferences[NFGlobalExcludeKey] = [self normalizedRuleEntriesFromArray:rawPreferences[NFGlobalExcludeKey] defaultScope:NFRuleScopeAll];
    normalizedPreferences[NFGlobalRegexKey] = [self normalizedRuleEntriesFromArray:rawPreferences[NFGlobalRegexKey] defaultScope:NFRuleScopeAll];

    NSMutableDictionary *normalizedAppRules = [NSMutableDictionary dictionary];
    NSDictionary *rawAppRules = rawPreferences[NFAppRulesKey];
    if ([rawAppRules isKindOfClass:[NSDictionary class]]) {
        [rawAppRules enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            if (![key isKindOfClass:[NSString class]] || [((NSString *)key) length] == 0) {
                return;
            }

            normalizedAppRules[key] = [self normalizedRulesDictionaryFromRawDictionary:obj];
        }];
    }

    normalizedPreferences[NFAppRulesKey] = normalizedAppRules;

    return normalizedPreferences;
}

+ (NSString *)_normalizedRuleText:(id)value {
    if (![value respondsToSelector:@selector(description)]) {
        return nil;
    }

    return [[[value description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
}

+ (NSString *)_normalizedRuleScope:(NSString *)scope defaultScope:(NSString *)defaultScope {
    NSString *resolvedScope = [scope isKindOfClass:[NSString class]] ? scope : defaultScope;
    NSSet<NSString *> *allowedScopes = [NSSet setWithObjects:
        NFRuleScopeMessage,
        NFRuleScopeTitle,
        NFRuleScopeSubtitle,
        NFRuleScopeAll,
        nil];
    if (![allowedScopes containsObject:resolvedScope]) {
        return defaultScope ?: NFRuleScopeAll;
    }
    return resolvedScope;
}

@end
