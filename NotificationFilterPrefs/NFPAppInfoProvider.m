#import "NFPAppInfoProvider.h"
#import <MobileCoreServices/LSApplicationWorkspace.h>
#import <MobileCoreServices/LSApplicationProxy.h>
#import <UIKit/UIImage+Private.h>
#import <objc/message.h>

static NSString * const NFPBundleIdentifierKey = @"bundleID";
static NSString * const NFPDisplayNameKey = @"displayName";
static NSString * const NFPIsUserApplicationKey = @"isUserApplication";
static NSString * const NFPIsSystemApplicationKey = @"isSystemApplication";
static NSString * const NFPIsTrollApplicationKey = @"isTrollApplication";

@interface NFPAppInfoProvider ()

@property (nonatomic, strong) dispatch_queue_t fetchQueue;
@property (nonatomic, copy) NSArray<NSDictionary *> *cachedApplications;
@property (nonatomic, copy) NSDictionary<NSString *, NSDictionary *> *applicationsByBundleIdentifier;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *iconCache;

@end

@implementation NFPAppInfoProvider

+ (instancetype)sharedProvider {
    static NFPAppInfoProvider *sharedProvider = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedProvider = [[self alloc] init];
    });
    return sharedProvider;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _fetchQueue = dispatch_queue_create("com.tune.notificationfilter.applist", DISPATCH_QUEUE_SERIAL);
        _cachedApplications = @[];
        _applicationsByBundleIdentifier = @{};
        _iconCache = [[NSCache alloc] init];
        _iconCache.countLimit = 256;
    }
    return self;
}

- (BOOL)hasCachedApplications {
    @synchronized (self) {
        return self.cachedApplications.count > 0;
    }
}

- (void)refreshApplicationsWithCompletion:(void (^)(NSArray<NSDictionary *> *))completion {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.fetchQueue, ^{
        NSArray<NSDictionary *> *applications = [weakSelf fetchedApplicationsSnapshot];
        NSMutableDictionary<NSString *, NSDictionary *> *applicationsByBundleIdentifier = [NSMutableDictionary dictionaryWithCapacity:applications.count];
        for (NSDictionary *application in applications) {
            NSString *bundleIdentifier = application[NFPBundleIdentifierKey];
            if (bundleIdentifier.length > 0) {
                applicationsByBundleIdentifier[bundleIdentifier] = application;
            }
        }

        @synchronized (weakSelf) {
            weakSelf.cachedApplications = applications;
            weakSelf.applicationsByBundleIdentifier = applicationsByBundleIdentifier;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(applications);
            }
        });
    });
}

- (NSArray<NSDictionary *> *)sortedApplicationsWithConfiguredBundleIdentifiers:(NSSet<NSString *> *)configuredBundleIdentifiers
                                                          onlyConfiguredApps:(BOOL)onlyConfiguredApps
                                                                showSystemApps:(BOOL)showSystemApps
                                                                 showTrollApps:(BOOL)showTrollApps {
    NSArray<NSDictionary *> *applications = nil;
    @synchronized (self) {
        applications = self.cachedApplications ?: @[];
    }
    NSMutableArray<NSDictionary *> *configuredApps = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *regularApps = [NSMutableArray array];
    NSMutableSet<NSString *> *seenBundleIdentifiers = [NSMutableSet set];

    for (NSDictionary *application in applications) {
        NSString *bundleIdentifier = application[NFPBundleIdentifierKey];
        NSDictionary *info = application;
        BOOL isConfigured = [configuredBundleIdentifiers containsObject:bundleIdentifier];
        BOOL isUserApplication = [application[NFPIsUserApplicationKey] boolValue];
        BOOL isSystemApplication = [application[NFPIsSystemApplicationKey] boolValue];
        BOOL isTrollApplication = [application[NFPIsTrollApplicationKey] boolValue];

        if (onlyConfiguredApps && !isConfigured) {
            continue;
        }

        BOOL shouldInclude = isUserApplication;
        if (isSystemApplication && showSystemApps) {
            shouldInclude = YES;
        }
        if (isTrollApplication && showTrollApps) {
            shouldInclude = YES;
        }
        if (!shouldInclude) {
            continue;
        }

        [seenBundleIdentifiers addObject:bundleIdentifier];
        if (isConfigured) {
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

    @synchronized (self) {
        NSString *cachedDisplayName = self.applicationsByBundleIdentifier[bundleIdentifier][NFPDisplayNameKey];
        if (cachedDisplayName.length > 0) {
            return cachedDisplayName;
        }
    }

    return bundleIdentifier;
}

- (UIImage *)iconForBundleIdentifier:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) {
        return nil;
    }

    UIImage *cachedIcon = [self.iconCache objectForKey:bundleIdentifier];
    if (cachedIcon) {
        return cachedIcon;
    }

    UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:bundleIdentifier
                                                               format:MIIconVariantSmall
                                                                scale:[UIScreen mainScreen].scale];
    if (icon) {
        [self.iconCache setObject:icon forKey:bundleIdentifier];
    }
    return icon;
}

- (NSArray<NSDictionary *> *)fetchedApplicationsSnapshot {
    LSApplicationWorkspace *workspace = [LSApplicationWorkspace defaultWorkspace];
    SEL allApplicationsSelector = NSSelectorFromString(@"allApplications");
    NSArray<LSApplicationProxy *> *applications = nil;
    if ([workspace respondsToSelector:allApplicationsSelector]) {
        applications = ((id (*)(id, SEL))objc_msgSend)(workspace, allApplicationsSelector);
    } else {
        applications = [workspace allInstalledApplications];
    }
    if (![applications isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<NSDictionary *> *fetchedApplications = [NSMutableArray array];
    for (LSApplicationProxy *application in applications) {
        if (![application isKindOfClass:[LSApplicationProxy class]]) {
            continue;
        }

        NSString *bundleIdentifier = application.bundleIdentifier;
        if (bundleIdentifier.length == 0) {
            continue;
        }

        if ([application respondsToSelector:@selector(isPlaceholder)] && [application isPlaceholder]) {
            continue;
        }

        if ([application respondsToSelector:@selector(isInstalled)] && ![application isInstalled]) {
            continue;
        }

        NSString *displayName = nil;
        NSString *applicationType = nil;
        SEL localizedNameSelector = NSSelectorFromString(@"localizedName");
        SEL applicationTypeSelector = NSSelectorFromString(@"applicationType");
        if ([application respondsToSelector:localizedNameSelector]) {
            displayName = ((id (*)(id, SEL))objc_msgSend)(application, localizedNameSelector);
        }
        if ([application respondsToSelector:applicationTypeSelector]) {
            applicationType = ((id (*)(id, SEL))objc_msgSend)(application, applicationTypeSelector);
        }
        if (displayName.length == 0 && [application.localizedShortName isKindOfClass:[NSString class]]) {
            displayName = application.localizedShortName;
        }
        if (displayName.length == 0 && [application.itemName isKindOfClass:[NSString class]]) {
            displayName = application.itemName;
        }
        if (displayName.length == 0) {
            displayName = bundleIdentifier;
        }

        NSURL *bundleURL = nil;
        if ([application respondsToSelector:@selector(bundleURL)]) {
            bundleURL = [application bundleURL];
        }
        BOOL isUserApplication = [applicationType isEqualToString:@"User"];
        if (applicationType.length == 0) {
            NSString *bundlePath = bundleURL.path ?: @"";
            isUserApplication = [bundlePath containsString:@"/var/containers/Bundle/Application/"];
        }
        BOOL isSystemApplication = !isUserApplication && [bundleIdentifier hasPrefix:@"com.apple."];
        BOOL isTrollApplication = !isUserApplication && !isSystemApplication;

        [fetchedApplications addObject:@{
            NFPBundleIdentifierKey: bundleIdentifier,
            NFPDisplayNameKey: displayName,
            NFPIsUserApplicationKey: @(isUserApplication),
            NFPIsSystemApplicationKey: @(isSystemApplication),
            NFPIsTrollApplicationKey: @(isTrollApplication)
        }];
    }

    [fetchedApplications sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        return [lhs[NFPDisplayNameKey] localizedCaseInsensitiveCompare:rhs[NFPDisplayNameKey]];
    }];

    return fetchedApplications;
}

@end
