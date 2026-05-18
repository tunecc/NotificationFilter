#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NFPNotificationHistoryClient : NSObject

+ (NSArray<NSDictionary *> *)fetchEntriesForBundleIdentifier:(NSString *)bundleIdentifier
                                                       error:(NSError * _Nullable * _Nullable)error
                                                      source:(NSString * _Nullable * _Nullable)source;

@end

NS_ASSUME_NONNULL_END
