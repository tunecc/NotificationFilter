#import <Foundation/Foundation.h>
#import "../NotificationFilterPrefs/NFPImportExportPayload.h"
#import "../Shared/NFPreferences.h"

static void NFAssert(BOOL condition, NSString *message) {
    if (!condition) {
        @throw [NSException exceptionWithName:@"NFImportExportPayloadTestFailure" reason:message userInfo:nil];
    }
}

static NSMutableDictionary *basePreferencesWithApp(NSString *bundleID, NSArray *contains) {
    NSDictionary *rules = [NFPreferences normalizedRulesDictionaryFromEnabled:YES
                                                                    contains:contains
                                                                     exclude:@[]
                                                                       regex:@[]];
    return [@{
        NFEnabledKey: @YES,
        NFGlobalRulesEnabledKey: @YES,
        NFGlobalContainsKey: @[],
        NFGlobalExcludeKey: @[],
        NFGlobalRegexKey: @[],
        NFAppRulesKey: @{ bundleID: rules },
        NFLoggingEnabledKey: @YES,
        NFLoggingDisabledBundleIdentifiersKey: @[],
        NFLogEntryLimitKey: @500,
        NFPrefOnlyConfiguredAppsKey: @NO,
        NFPrefShowSystemAppsKey: @YES,
        NFPrefShowTrollAppsKey: @YES,
        NFDeleteFilteredNotificationsKey: @NO
    } mutableCopy];
}

static NSDictionary *entry(NSString *text, NSString *scope) {
    return [NFPreferences ruleEntryWithText:text enabled:YES identifier:nil scope:scope];
}

static NSDictionary *rulesDict(NSString *mode, NSArray *contains) {
    NSDictionary *raw = @{
        NFRulesEnabledKey: @YES,
        NFRulesModeKey: mode,
        NFRulesContainsKey: contains,
        NFRulesExcludeKey: @[],
        NFRulesRegexKey: @[]
    };
    return [NFPreferences normalizedRulesDictionaryFromRawDictionary:raw];
}

int main(void) {
    @autoreleasepool {
        // A2 / A36: 导出 app-rules 载荷结构正确
        NSDictionary *rules = rulesDict(NFRulesModeBlacklist, @[ entry(@"Payment", NFRuleScopeMessage) ]);
        NSDictionary *appRulesPayload = [NFPImportExportPayload appRulesPayloadForBundleIdentifier:@"com.example.app" rules:rules];
        NFAssert([appRulesPayload[NFPPayloadTypeKey] isEqualToString:NFPPayloadTypeAppRules], @"app-rules payload type");
        NFAssert([appRulesPayload[NFPPayloadBundleIDKey] isEqualToString:@"com.example.app"], @"app-rules bundleID");
        NFAssert([appRulesPayload[NFPPayloadRulesKey] isKindOfClass:[NSDictionary class]], @"app-rules rules dict");

        // A2 / A3: app-rules-bundle 载荷结构正确，单应用也归入 bundle
        NSDictionary *bundlePayload = [NFPImportExportPayload appRulesBundlePayloadForApps:@{
            @"com.example.appA": rules
        }];
        NFAssert([bundlePayload[NFPPayloadTypeKey] isEqualToString:NFPPayloadTypeAppRulesBundle], @"bundle payload type");
        NFAssert([bundlePayload[NFPPayloadAppsKey] isKindOfClass:[NSDictionary class]], @"bundle apps dict");
        NFAssert([bundlePayload[NFPPayloadAppsKey][@"com.example.appA"] isKindOfClass:[NSDictionary class]], @"bundle keeps appA");

        // A13: full-config 外壳
        NSDictionary *fullPayload = [NFPImportExportPayload fullConfigPayloadFromPreferences:@{ NFEnabledKey: @YES, NFAppRulesKey: @{} }];
        NFAssert([fullPayload[NFPPayloadTypeKey] isEqualToString:NFPPayloadTypeFullConfig], @"full-config payload type");
        NFAssert([fullPayload[NFPPayloadPreferencesKey] isKindOfClass:[NSDictionary class]], @"full-config preferences dict");

        // A25 / A26 / A35: 单应用合并整体替换该应用，其他应用与全局规则不变
        NSMutableDictionary *prefs = basePreferencesWithApp(@"com.existing", @[ entry(@"Old", NFRuleScopeMessage) ]);
        prefs[NFLoggingDisabledBundleIdentifiersKey] = @[ @"com.existing" ];
        NSDictionary *singlePayload = [NFPImportExportPayload appRulesPayloadForBundleIdentifier:@"com.imported"
                                                                                          rules:rulesDict(NFRulesModeWhitelist, @[ entry(@"New", NFRuleScopeAll) ])];
        NFPImportExportPayloadResult *r1 = [NFPImportExportPayload applyPayload:singlePayload toMutablePreferences:prefs];
        NFAssert(r1.kind == NFPPayloadKindAppRules, @"single kind");
        NFAssert(r1.appCount == 1, @"single appCount 1");
        NFAssert([prefs[NFAppRulesKey][@"com.imported"][NFRulesModeKey] isEqualToString:NFRulesModeWhitelist], @"imported app replaced with whitelist mode");
        NFAssert([prefs[NFAppRulesKey][@"com.existing"][NFRulesContainsKey] count] == 1, @"existing app untouched");
        NFAssert([prefs[NFGlobalRulesEnabledKey] boolValue] == YES, @"global rules untouched");
        NFAssert([prefs[NFLoggingDisabledBundleIdentifiersKey] containsObject:@"com.existing"], @"logging disabled list untouched");
        NFAssert([prefs[NFLogEntryLimitKey] integerValue] == 500, @"log entry limit untouched");

        // 整体替换：同 bundleID 旧规则被新规则替换
        NSMutableDictionary *prefs2 = basePreferencesWithApp(@"com.app", @[ entry(@"OldA", NFRuleScopeMessage), entry(@"OldB", NFRuleScopeMessage) ]);
        NSDictionary *replacePayload = [NFPImportExportPayload appRulesPayloadForBundleIdentifier:@"com.app"
                                                                                           rules:rulesDict(NFRulesModeBlacklist, @[ entry(@"NewOnly", NFRuleScopeAll) ])];
        NFPImportExportPayloadResult *r2 = [NFPImportExportPayload applyPayload:replacePayload toMutablePreferences:prefs2];
        NSArray *containsAfter = prefs2[NFAppRulesKey][@"com.app"][NFRulesContainsKey];
        NFAssert(containsAfter.count == 1, @"same bundleID replaced (count 1)");
        NFAssert([[NFPreferences ruleTextFromEntry:containsAfter[0]] isEqualToString:@"NewOnly"], @"same bundleID replaced (NewOnly)");

        // A19 / A26 / A28 / A31: 多应用合并，空 bundleID 跳过，计数只算有效应用
        NSMutableDictionary *prefs3 = basePreferencesWithApp(@"com.keep", @[ entry(@"Keep", NFRuleScopeMessage) ]);
        NSDictionary *multiPayload = [NFPImportExportPayload appRulesBundlePayloadForApps:@{
            @"com.app1": rulesDict(NFRulesModeBlacklist, @[ entry(@"A1", NFRuleScopeMessage) ]),
            @"com.app2": rulesDict(NFRulesModeBlacklist, @[ entry(@"A2", NFRuleScopeMessage) ]),
            @"": rulesDict(NFRulesModeBlacklist, @[ entry(@"Skipped", NFRuleScopeMessage) ])
        }];
        NFPImportExportPayloadResult *r3 = [NFPImportExportPayload applyPayload:multiPayload toMutablePreferences:prefs3];
        NFAssert(r3.kind == NFPPayloadKindAppRulesBundle, @"bundle kind");
        NFAssert(r3.appCount == 2, @"bundle appCount 2 (empty bundleID skipped)");
        NFAssert([prefs3[NFAppRulesKey][@"com.app1"][NFRulesContainsKey] count] == 1, @"app1 imported");
        NFAssert([prefs3[NFAppRulesKey][@"com.app2"][NFRulesContainsKey] count] == 1, @"app2 imported");
        NFAssert([prefs3[NFAppRulesKey][@"com.keep"][NFRulesContainsKey] count] == 1, @"com.keep untouched");
        NFAssert([prefs3[NFAppRulesKey] objectForKey:@""] == nil, @"empty bundleID not added");

        // A20 / A29: full-config 覆盖整份
        NSMutableDictionary *prefs4 = basePreferencesWithApp(@"com.old", @[ entry(@"Old", NFRuleScopeMessage) ]);
        NSDictionary *fullConfigPayload = [NFPImportExportPayload fullConfigPayloadFromPreferences:@{
            NFEnabledKey: @NO,
            NFAppRulesKey: @{ @"com.new": rulesDict(NFRulesModeBlacklist, @[ entry(@"Fresh", NFRuleScopeMessage) ]) },
            NFGlobalContainsKey: @[ entry(@"Global", NFRuleScopeMessage) ]
        }];
        NFPImportExportPayloadResult *r4 = [NFPImportExportPayload applyPayload:fullConfigPayload toMutablePreferences:prefs4];
        NFAssert(r4.kind == NFPPayloadKindFullConfig, @"full-config kind");
        NFAssert([prefs4[NFEnabledKey] boolValue] == NO, @"full-config overwrote Enabled");
        NFAssert([prefs4[NFAppRulesKey][@"com.new"][NFRulesContainsKey] count] == 1, @"full-config imported com.new");
        NFAssert([prefs4[NFAppRulesKey] objectForKey:@"com.old"] == nil, @"full-config dropped com.old");
        NFAssert([prefs4[NFGlobalContainsKey] count] == 1, @"full-config imported global contains");

        // A21 / A37: 无 type 的旧版 flat 识别为完整配置，覆盖整份
        NSMutableDictionary *prefs5 = basePreferencesWithApp(@"com.old", @[ entry(@"Old", NFRuleScopeMessage) ]);
        NSDictionary *legacyFlat = @{
            NFEnabledKey: @YES,
            NFGlobalRulesEnabledKey: @NO,
            NFGlobalContainsKey: @[],
            NFGlobalExcludeKey: @[],
            NFGlobalRegexKey: @[],
            NFAppRulesKey: @{ @"com.legacy": @{ NFRulesEnabledKey: @YES, NFRulesModeKey: NFRulesModeWhitelist, NFRulesContainsKey: @[ entry(@"Legacy", NFRuleScopeMessage) ], NFRulesExcludeKey: @[], NFRulesRegexKey: @[] } }
        };
        NFAssert([NFPImportExportPayload kindOfPayload:legacyFlat] == NFPPayloadKindFullConfig, @"legacy flat recognized as full-config");
        NFPImportExportPayloadResult *r5 = [NFPImportExportPayload applyPayload:legacyFlat toMutablePreferences:prefs5];
        NFAssert(r5.kind == NFPPayloadKindFullConfig, @"legacy flat kind full-config");
        NFAssert([prefs5[NFAppRulesKey][@"com.legacy"][NFRulesModeKey] isEqualToString:NFRulesModeWhitelist], @"legacy flat imported com.legacy");
        NFAssert([prefs5[NFAppRulesKey] objectForKey:@"com.old"] == nil, @"legacy flat dropped com.old");

        // A16: 非 JSON / 非 dict 报错
        NSError *err = nil;
        NSDictionary *badPayload = [NFPImportExportPayload payloadFromJSONString:@"not json" error:&err];
        NFAssert(badPayload == nil, @"non-JSON returns nil");
        NFAssert(err != nil, @"non-JSON sets error");

        err = nil;
        NSDictionary *arrayPayload = [NFPImportExportPayload payloadFromJSONString:@"[1,2,3]" error:&err];
        NFAssert(arrayPayload == nil, @"non-object root returns nil");

        // A22: 未知 type 报错，不修改配置
        NSMutableDictionary *prefs6 = basePreferencesWithApp(@"com.keep", @[ entry(@"Keep", NFRuleScopeMessage) ]);
        NSDictionary *unknownPayload = @{ NFPPayloadTypeKey: @"something-unknown", @"data": @{} };
        NFPImportExportPayloadResult *r6 = [NFPImportExportPayload applyPayload:unknownPayload toMutablePreferences:prefs6];
        NFAssert(r6.kind == NFPPayloadKindUnknown, @"unknown kind");
        NFAssert(r6.error != nil, @"unknown sets error");
        NFAssert([prefs6[NFAppRulesKey][@"com.keep"][NFRulesContainsKey] count] == 1, @"unknown did not modify preferences");

        // A28: 单应用载荷 bundleID 为空报错
        NSMutableDictionary *prefs7 = basePreferencesWithApp(@"com.keep", @[ entry(@"Keep", NFRuleScopeMessage) ]);
        NSDictionary *emptyBundlePayload = [NFPImportExportPayload appRulesPayloadForBundleIdentifier:@""
                                                                                               rules:[NFPreferences normalizedRulesDictionaryFromRawDictionary:nil]];
        NFPImportExportPayloadResult *r7 = [NFPImportExportPayload applyPayload:emptyBundlePayload toMutablePreferences:prefs7];
        NFAssert(r7.error != nil, @"empty bundleID sets error");
        NFAssert([prefs7[NFAppRulesKey][@"com.keep"][NFRulesContainsKey] count] == 1, @"empty bundleID did not modify preferences");

        // A36: 导出载荷规则条目结构与偏好一致（id/text/enabled/scope）
        NSDictionary *ruleEntry = appRulesPayload[NFPPayloadRulesKey][NFRulesContainsKey][0];
        NFAssert([ruleEntry[NFRuleEntryTextKey] isEqualToString:@"Payment"], @"exported entry text");
        NFAssert([ruleEntry[NFRuleEntryEnabledKey] boolValue] == YES, @"exported entry enabled");
        NFAssert([ruleEntry[NFRuleEntryScopeKey] isEqualToString:NFRuleScopeMessage], @"exported entry scope");
        NFAssert([ruleEntry[NFRuleEntryIdentifierKey] isKindOfClass:[NSString class]], @"exported entry id");

        NSLog(@"All NFPImportExportPayload tests passed.");
    }
    return 0;
}
