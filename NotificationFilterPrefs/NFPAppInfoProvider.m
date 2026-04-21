#import "NFPAppInfoProvider.h"
#import <MobileCoreServices/LSApplicationWorkspace.h>
#import <MobileCoreServices/LSApplicationProxy.h>
#import <UIKit/UIImage+Private.h>

static NSString * const NFPBundleIdentifierKey = @"bundleID";
static NSString * const NFPDisplayNameKey = @"displayName";

@implementation NFPAppInfoProvider

+ (instancetype)sharedProvider {
    static NFPAppInfoProvider *sharedProvider = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedProvider = [[self alloc] init];
    });
    return sharedProvider;
}

- (NSArray<LSApplicationProxy *> *)installedApplications {
    NSArray<LSApplicationProxy *> *applications = [[LSApplicationWorkspace defaultWorkspace] allInstalledApplications];
    if (![applications isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<LSApplicationProxy *> *filteredApplications = [NSMutableArray array];
    for (LSApplicationProxy *application in applications) {
        if (![application isKindOfClass:[LSApplicationProxy class]]) {
            continue;
        }

        if (![application isInstalled] || [application isPlaceholder]) {
            continue;
        }

        if (application.bundleIdentifier.length == 0) {
            continue;
        }

        [filteredApplications addObject:application];
    }

    return filteredApplications;
}

- (NSArray<NSDictionary *> *)sortedApplicationsWithConfiguredBundleIdentifiers:(NSSet<NSString *> *)configuredBundleIdentifiers {
    NSArray<LSApplicationProxy *> *applications = [[self installedApplications] sortedArrayUsingComparator:^NSComparisonResult(LSApplicationProxy *lhs, LSApplicationProxy *rhs) {
        NSString *leftName = [self displayNameForBundleIdentifier:lhs.bundleIdentifier];
        NSString *rightName = [self displayNameForBundleIdentifier:rhs.bundleIdentifier];
        return [leftName localizedCaseInsensitiveCompare:rightName];
    }];
    NSMutableArray<NSDictionary *> *configuredApps = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *regularApps = [NSMutableArray array];
    NSMutableSet<NSString *> *seenBundleIdentifiers = [NSMutableSet set];

    for (LSApplicationProxy *application in applications) {
        NSString *bundleIdentifier = application.bundleIdentifier;
        NSString *displayName = [self displayNameForBundleIdentifier:bundleIdentifier];
        NSDictionary *info = @{
            NFPBundleIdentifierKey: bundleIdentifier,
            NFPDisplayNameKey: displayName
        };
        [seenBundleIdentifiers addObject:bundleIdentifier];
        if ([configuredBundleIdentifiers containsObject:bundleIdentifier]) {
            [configuredApps addObject:info];
        } else {
            [regularApps addObject:info];
        }
    }

    for (NSString *bundleIdentifier in configuredBundleIdentifiers) {
        if (bundleIdentifier.length == 0 || [seenBundleIdentifiers containsObject:bundleIdentifier]) {
            continue;
        }

        [configuredApps addObject:@{
            NFPBundleIdentifierKey: bundleIdentifier,
            NFPDisplayNameKey: bundleIdentifier
        }];
    }

    NSMutableArray<NSDictionary *> *result = [NSMutableArray arrayWithArray:configuredApps];
    [result addObjectsFromArray:regularApps];
    return result;
}

- (NSString *)displayNameForBundleIdentifier:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) {
        return @"未知应用";
    }

    LSApplicationProxy *application = [LSApplicationProxy applicationProxyForIdentifier:bundleIdentifier];
    if ([application.localizedShortName isKindOfClass:[NSString class]] && application.localizedShortName.length > 0) {
        return application.localizedShortName;
    }
    if ([application.itemName isKindOfClass:[NSString class]] && application.itemName.length > 0) {
        return application.itemName;
    }

    return bundleIdentifier;
}

- (UIImage *)iconForBundleIdentifier:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) {
        return nil;
    }

    return [UIImage _applicationIconImageForBundleIdentifier:bundleIdentifier
                                                      format:MIIconVariantSmall
                                                       scale:[UIScreen mainScreen].scale];
}

@end
