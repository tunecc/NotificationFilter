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

NSString * const NFRulesEnabledKey = @"enabled";
NSString * const NFRulesContainsKey = @"contains";
NSString * const NFRulesExcludeKey = @"exclude";
NSString * const NFRulesRegexKey = @"regex";
NSString * const NFRuleEntryIdentifierKey = @"id";
NSString * const NFRuleEntryTextKey = @"text";
NSString * const NFRuleEntryEnabledKey = @"enabled";

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
        NFAppRulesKey
    ];
}

+ (NSDictionary *)defaultPreferences {
    return @{
        NFEnabledKey: @YES,
        NFGlobalRulesEnabledKey: @NO,
        NFGlobalContainsKey: @[],
        NFGlobalExcludeKey: @[],
        NFGlobalRegexKey: @[],
        NFAppRulesKey: @{}
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
        NFRulesContainsKey: [self normalizedRuleEntriesFromArray:contains],
        NFRulesExcludeKey: [self normalizedRuleEntriesFromArray:exclude],
        NFRulesRegexKey: [self normalizedRuleEntriesFromArray:regex]
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
    if (![rawRules isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (id rawRule in rawRules) {
        NSString *identifier = nil;
        NSString *text = nil;
        BOOL enabled = YES;

        if ([rawRule isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dictionary = rawRule;
            id textValue = dictionary[NFRuleEntryTextKey] ?: dictionary[@"value"];
            if ([dictionary[NFRuleEntryEnabledKey] respondsToSelector:@selector(boolValue)]) {
                enabled = [dictionary[NFRuleEntryEnabledKey] boolValue];
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
                                         identifier:identifier]];
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

+ (NSDictionary *)ruleEntryWithText:(NSString *)text
                            enabled:(BOOL)enabled
                          identifier:(NSString *)identifier {
    NSString *normalizedText = [self _normalizedRuleText:text];
    NSString *resolvedIdentifier = identifier.length > 0 ? identifier : [NSUUID UUID].UUIDString;
    return @{
        NFRuleEntryIdentifierKey: resolvedIdentifier,
        NFRuleEntryTextKey: normalizedText ?: @"",
        NFRuleEntryEnabledKey: @(enabled)
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

    normalizedPreferences[NFGlobalContainsKey] = [self normalizedRuleEntriesFromArray:rawPreferences[NFGlobalContainsKey]];
    normalizedPreferences[NFGlobalExcludeKey] = [self normalizedRuleEntriesFromArray:rawPreferences[NFGlobalExcludeKey]];
    normalizedPreferences[NFGlobalRegexKey] = [self normalizedRuleEntriesFromArray:rawPreferences[NFGlobalRegexKey]];

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

@end
