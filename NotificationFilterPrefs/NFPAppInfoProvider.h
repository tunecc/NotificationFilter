#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NFPAppInfoProvider : NSObject

+ (instancetype)sharedProvider;
- (NSArray<NSDictionary *> *)sortedApplicationsWithConfiguredBundleIdentifiers:(NSSet<NSString *> *)configuredBundleIdentifiers;
- (NSString *)displayNameForBundleIdentifier:(NSString *)bundleIdentifier;
- (UIImage * _Nullable)iconForBundleIdentifier:(NSString *)bundleIdentifier;

@end

NS_ASSUME_NONNULL_END
