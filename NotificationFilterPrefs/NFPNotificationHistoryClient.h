#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NFPNotificationHistoryClient : NSObject

+ (NSString * _Nullable)requestRefreshForBundleIdentifier:(NSString *)bundleIdentifier
                                                    limit:(NSUInteger)limit
                                                    error:(NSError * _Nullable * _Nullable)error;

+ (NSDictionary * _Nullable)refreshStatusForRequestIdentifier:(NSString *)requestIdentifier
                                             bundleIdentifier:(NSString *)bundleIdentifier;

+ (NSArray<NSDictionary *> *)fetchEntriesForBundleIdentifier:(NSString *)bundleIdentifier
                                                       error:(NSError * _Nullable * _Nullable)error
                                                      source:(NSString * _Nullable * _Nullable)source;

// 读取全部应用的镜像条目（不做 bundleIdentifier 过滤），供全局扫描使用。
+ (NSArray<NSDictionary *> *)fetchAllAppsEntriesWithError:(NSError * _Nullable * _Nullable)error
                                                   source:(NSString * _Nullable * _Nullable)source;

@end

NS_ASSUME_NONNULL_END
