#import "NFPImportExportPayload.h"
#import "../Shared/NFPreferences.h"

NSString * const NFPPayloadErrorDomain = @"com.tune.notificationfilter.import";

NSString * const NFPPayloadTypeKey = @"type";
NSString * const NFPPayloadTypeAppRules = @"app-rules";
NSString * const NFPPayloadTypeAppRulesBundle = @"app-rules-bundle";
NSString * const NFPPayloadTypeFullConfig = @"full-config";

NSString * const NFPPayloadBundleIDKey = @"bundleID";
NSString * const NFPPayloadRulesKey = @"rules";
NSString * const NFPPayloadAppsKey = @"apps";
NSString * const NFPPayloadPreferencesKey = @"preferences";

@implementation NFPImportExportPayloadResult
@end

@implementation NFPImportExportPayload

+ (NSDictionary *)appRulesPayloadForBundleIdentifier:(NSString *)bundleIdentifier
                                               rules:(NSDictionary * _Nullable)rules {
    return @{
        NFPPayloadTypeKey: NFPPayloadTypeAppRules,
        NFPPayloadBundleIDKey: bundleIdentifier ?: @"",
        NFPPayloadRulesKey: rules ?: [NFPreferences normalizedRulesDictionaryFromRawDictionary:nil]
    };
}

+ (NSDictionary *)appRulesBundlePayloadForApps:(NSDictionary<NSString *, NSDictionary *> *)apps {
    NSMutableDictionary<NSString *, NSDictionary *> *normalizedApps = [NSMutableDictionary dictionary];
    [apps enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (![key isKindOfClass:[NSString class]] || [((NSString *)key) length] == 0) {
            return;
        }
        normalizedApps[key] = [NFPreferences normalizedRulesDictionaryFromRawDictionary:obj];
    }];

    return @{
        NFPPayloadTypeKey: NFPPayloadTypeAppRulesBundle,
        NFPPayloadAppsKey: normalizedApps
    };
}

+ (NSDictionary *)fullConfigPayloadFromPreferences:(NSDictionary *)preferences {
    return @{
        NFPPayloadTypeKey: NFPPayloadTypeFullConfig,
        NFPPayloadPreferencesKey: [NFPreferences normalizedPreferencesFromDictionary:preferences]
    };
}

+ (NSData *)jsonDataFromPayload:(NSDictionary *)payload error:(NSError **)error {
    if (![NSJSONSerialization isValidJSONObject:payload]) {
        if (error) {
            *error = [NSError errorWithDomain:NFPPayloadErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Payload is not a valid JSON object."}];
        }
        return nil;
    }
    return [NSJSONSerialization dataWithJSONObject:payload
                                           options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                             error:error];
}

+ (NSString *)jsonStringFromPayload:(NSDictionary *)payload error:(NSError **)error {
    NSData *jsonData = [self jsonDataFromPayload:payload error:error];
    if (!jsonData) {
        return nil;
    }
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

+ (NSDictionary *)payloadFromJSONString:(NSString *)jsonString error:(NSError **)error {
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    if (!jsonData) {
        if (error) {
            *error = [NSError errorWithDomain:NFPPayloadErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"The JSON text could not be encoded as UTF-8."}];
        }
        return nil;
    }

    id object = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:error];
    if (![object isKindOfClass:[NSDictionary class]]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:NFPPayloadErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"The JSON root must be an object."}];
        }
        return nil;
    }

    return object;
}

+ (NFPPayloadKind)kindOfPayload:(NSDictionary *)payload {
    if (![payload isKindOfClass:[NSDictionary class]]) {
        return NFPPayloadKindUnknown;
    }

    NSString *type = payload[NFPPayloadTypeKey];
    if (![type isKindOfClass:[NSString class]]) {
        return NFPPayloadKindFullConfig;
    }

    if ([type isEqualToString:NFPPayloadTypeAppRules]) {
        return NFPPayloadKindAppRules;
    }
    if ([type isEqualToString:NFPPayloadTypeAppRulesBundle]) {
        return NFPPayloadKindAppRulesBundle;
    }
    if ([type isEqualToString:NFPPayloadTypeFullConfig]) {
        return NFPPayloadKindFullConfig;
    }

    return NFPPayloadKindUnknown;
}

+ (NFPImportExportPayloadResult *)applyPayload:(NSDictionary *)payload
                          toMutablePreferences:(NSMutableDictionary *)preferences {
    NFPImportExportPayloadResult *result = [[NFPImportExportPayloadResult alloc] init];
    result.kind = [self kindOfPayload:payload];

    switch (result.kind) {
        case NFPPayloadKindFullConfig: {
            NSDictionary *preferencesToMerge = payload[NFPPayloadPreferencesKey];
            if (![preferencesToMerge isKindOfClass:[NSDictionary class]]) {
                preferencesToMerge = payload;
            }

            NSDictionary *normalized = [NFPreferences normalizedPreferencesFromDictionary:preferencesToMerge];
            for (NSString *key in normalized) {
                preferences[key] = normalized[key];
            }
            result.appCount = 0;
            return result;
        }
        case NFPPayloadKindAppRules: {
            NSString *bundleIdentifier = payload[NFPPayloadBundleIDKey];
            NSDictionary *rules = payload[NFPPayloadRulesKey];

            if (![bundleIdentifier isKindOfClass:[NSString class]] || [bundleIdentifier length] == 0) {
                result.error = [NSError errorWithDomain:NFPPayloadErrorDomain
                                                   code:3
                                               userInfo:@{NSLocalizedDescriptionKey: @"Missing bundle identifier in app-rules payload."}];
                return result;
            }

            NSMutableDictionary *appRules = [preferences[NFAppRulesKey] mutableCopy] ?: [NSMutableDictionary dictionary];
            appRules[bundleIdentifier] = [NFPreferences normalizedRulesDictionaryFromRawDictionary:rules];
            preferences[NFAppRulesKey] = appRules;

            result.bundleIdentifier = [bundleIdentifier copy];
            result.appCount = 1;
            return result;
        }
        case NFPPayloadKindAppRulesBundle: {
            NSDictionary *apps = payload[NFPPayloadAppsKey];
            if (![apps isKindOfClass:[NSDictionary class]]) {
                result.error = [NSError errorWithDomain:NFPPayloadErrorDomain
                                                   code:4
                                               userInfo:@{NSLocalizedDescriptionKey: @"Missing apps map in app-rules-bundle payload."}];
                return result;
            }

            NSMutableDictionary *appRules = [preferences[NFAppRulesKey] mutableCopy] ?: [NSMutableDictionary dictionary];
            __block NSInteger appliedCount = 0;
            [apps enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                if (![key isKindOfClass:[NSString class]] || [((NSString *)key) length] == 0) {
                    return;
                }
                appRules[key] = [NFPreferences normalizedRulesDictionaryFromRawDictionary:obj];
                appliedCount += 1;
            }];
            preferences[NFAppRulesKey] = appRules;

            result.appCount = appliedCount;
            return result;
        }
        case NFPPayloadKindUnknown:
        default: {
            result.error = [NSError errorWithDomain:NFPPayloadErrorDomain
                                               code:5
                                           userInfo:@{NSLocalizedDescriptionKey: @"Unrecognized payload type."}];
            return result;
        }
    }
}

@end
