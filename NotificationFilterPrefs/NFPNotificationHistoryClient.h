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

@end

NS_ASSUME_NONNULL_END
