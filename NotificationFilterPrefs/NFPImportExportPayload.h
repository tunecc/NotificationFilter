#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const NFPPayloadErrorDomain;

extern NSString * const NFPPayloadTypeKey;
extern NSString * const NFPPayloadTypeAppRules;
extern NSString * const NFPPayloadTypeAppRulesBundle;
extern NSString * const NFPPayloadTypeFullConfig;

extern NSString * const NFPPayloadBundleIDKey;
extern NSString * const NFPPayloadRulesKey;
extern NSString * const NFPPayloadAppsKey;
extern NSString * const NFPPayloadPreferencesKey;

typedef NS_ENUM(NSInteger, NFPPayloadKind) {
    NFPPayloadKindUnknown = 0,
    NFPPayloadKindAppRules,
    NFPPayloadKindAppRulesBundle,
    NFPPayloadKindFullConfig
};

@interface NFPImportExportPayloadResult : NSObject

@property (nonatomic, assign) NFPPayloadKind kind;
@property (nonatomic, copy, nullable) NSString *bundleIdentifier;
@property (nonatomic, assign) NSInteger appCount;
@property (nonatomic, strong, nullable) NSError *error;

@end

@interface NFPImportExportPayload : NSObject

+ (NSDictionary *)appRulesPayloadForBundleIdentifier:(NSString *)bundleIdentifier
                                               rules:(NSDictionary * _Nullable)rules;
+ (NSDictionary *)appRulesBundlePayloadForApps:(NSDictionary<NSString *, NSDictionary *> *)apps;
+ (NSDictionary *)fullConfigPayloadFromPreferences:(NSDictionary *)preferences;

+ (nullable NSData *)jsonDataFromPayload:(NSDictionary *)payload error:(NSError **)error;
+ (nullable NSString *)jsonStringFromPayload:(NSDictionary *)payload error:(NSError **)error;

+ (nullable NSDictionary *)payloadFromJSONString:(NSString *)jsonString error:(NSError **)error;
+ (NFPPayloadKind)kindOfPayload:(nullable NSDictionary *)payload;

+ (NFPImportExportPayloadResult *)applyPayload:(NSDictionary *)payload
                          toMutablePreferences:(NSMutableDictionary *)preferences;

@end

NS_ASSUME_NONNULL_END
