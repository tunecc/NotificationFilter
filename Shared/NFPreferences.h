#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const NFPreferencesIdentifier;
extern NSString * const NFPreferencesChangedDarwinNotification;

extern NSString * const NFEnabledKey;
extern NSString * const NFGlobalRulesEnabledKey;
extern NSString * const NFGlobalContainsKey;
extern NSString * const NFGlobalExcludeKey;
extern NSString * const NFGlobalRegexKey;
extern NSString * const NFAppRulesKey;

extern NSString * const NFRulesEnabledKey;
extern NSString * const NFRulesContainsKey;
extern NSString * const NFRulesExcludeKey;
extern NSString * const NFRulesRegexKey;
extern NSString * const NFRuleEntryIdentifierKey;
extern NSString * const NFRuleEntryTextKey;
extern NSString * const NFRuleEntryEnabledKey;

extern NSString * const NFLogIdentifierKey;
extern NSString * const NFLogTimestampKey;
extern NSString * const NFLogBundleIdentifierKey;
extern NSString * const NFLogTitleKey;
extern NSString * const NFLogSubtitleKey;
extern NSString * const NFLogBodyKey;
extern NSString * const NFLogHeaderKey;
extern NSString * const NFLogMessageKey;
extern NSString * const NFLogJoinedTextKey;
extern NSString * const NFLogMatchedScopeKey;
extern NSString * const NFLogMatchedModeKey;
extern NSString * const NFLogMatchedPatternKey;

extern NSString * const NFMatchScopeGlobal;
extern NSString * const NFMatchModeExclude;
extern NSString * const NFMatchModeContains;
extern NSString * const NFMatchModeRegex;

@interface NFPreferences : NSObject

+ (NSDictionary *)defaultPreferences;
+ (NSDictionary *)loadPreferences;
+ (NSMutableDictionary *)loadMutablePreferences;
+ (NSDictionary *)normalizedPreferencesFromDictionary:(NSDictionary * _Nullable)rawPreferences;
+ (BOOL)savePreferences:(NSDictionary *)preferences error:(NSError * _Nullable * _Nullable)error;
+ (void)postPreferencesChangedNotification;

+ (NSDictionary *)globalRulesFromPreferences:(NSDictionary *)preferences;
+ (NSDictionary * _Nullable)rulesForBundleIdentifier:(NSString *)bundleIdentifier
                                     fromPreferences:(NSDictionary *)preferences;
+ (NSDictionary *)normalizedRulesDictionaryFromRawDictionary:(NSDictionary * _Nullable)rawRules;
+ (NSDictionary *)normalizedRulesDictionaryFromEnabled:(BOOL)enabled
                                              contains:(NSArray * _Nullable)contains
                                               exclude:(NSArray * _Nullable)exclude
                                                 regex:(NSArray * _Nullable)regex;
+ (BOOL)rulesDictionaryHasConfiguredValues:(NSDictionary * _Nullable)rules;

+ (NSArray<NSDictionary *> *)normalizedRuleEntriesFromArray:(NSArray * _Nullable)rawRules;
+ (NSArray<NSString *> *)activeRuleTextsFromRuleEntries:(NSArray * _Nullable)rawRules;
+ (NSString *)ruleTextFromEntry:(NSDictionary * _Nullable)entry;
+ (BOOL)ruleEntryEnabled:(NSDictionary * _Nullable)entry;
+ (NSDictionary *)ruleEntryWithText:(NSString *)text
                            enabled:(BOOL)enabled
                          identifier:(NSString * _Nullable)identifier;

+ (NSArray<NSString *> *)normalizedRuleLinesFromArray:(NSArray * _Nullable)rawRules;
+ (NSArray<NSString *> *)normalizedRuleLinesFromMultilineString:(NSString * _Nullable)multilineString;
+ (NSString *)multilineStringFromRuleLines:(NSArray<NSString *> * _Nullable)rules;

+ (NSString *)logsFilePath;

@end

NS_ASSUME_NONNULL_END
