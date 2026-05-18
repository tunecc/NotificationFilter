#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NFLogStore : NSObject

+ (NSArray<NSDictionary *> *)loadEntries;
+ (void)appendBlockedEntry:(NSDictionary *)entry;
+ (void)clearEntries;
+ (void)clearEntriesForBundleIdentifier:(NSString *)bundleIdentifier;
+ (void)trimEntriesToCurrentLimit;

@end

NS_ASSUME_NONNULL_END
