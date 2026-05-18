#import "NFPNotificationHistoryClient.h"
#import "../Shared/NFPreferences.h"
#import "../Shared/NFNotificationHistoryBridge.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <rocketbootstrap/rocketbootstrap.h>

static void NFPEnsureAppSupportLoaded(void) {
    static BOOL attempted = NO;
    if (!attempted) {
        attempted = YES;
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_LAZY);
    }
}

@implementation NFPNotificationHistoryClient

+ (NSArray<NSDictionary *> * _Nullable)_entriesFromSnapshotFileForBundleIdentifier:(NSString *)bundleIdentifier
                                                                      filePresent:(BOOL *)filePresent {
    NSArray *entries = [NSArray arrayWithContentsOfFile:NFNotificationHistorySnapshotFilePath()];
    if (![entries isKindOfClass:[NSArray class]]) {
        if (filePresent) {
            *filePresent = [[NSFileManager defaultManager] fileExistsAtPath:NFNotificationHistorySnapshotFilePath()];
        }
        return @[];
    }
    if (filePresent) {
        *filePresent = YES;
    }

    NSMutableArray<NSDictionary *> *filteredEntries = [NSMutableArray array];
    for (id entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *entryBundleIdentifier = [entry[NFLogBundleIdentifierKey] isKindOfClass:[NSString class]] ? entry[NFLogBundleIdentifierKey] : nil;
        if (![entryBundleIdentifier isEqualToString:bundleIdentifier]) {
            continue;
        }
        [filteredEntries addObject:entry];
    }
    return filteredEntries;
}

+ (NSArray<NSDictionary *> *)fetchEntriesForBundleIdentifier:(NSString *)bundleIdentifier
                                                       error:(NSError **)error
                                                      source:(NSString **)source {
    NSString *normalizedBundleIdentifier = [bundleIdentifier stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (normalizedBundleIdentifier.length == 0) {
        if (source) {
            *source = nil;
        }
        return @[];
    }

    BOOL snapshotFilePresent = NO;
    NSArray<NSDictionary *> *snapshotEntries = [self _entriesFromSnapshotFileForBundleIdentifier:normalizedBundleIdentifier
                                                                                     filePresent:&snapshotFilePresent];
    if (snapshotFilePresent) {
        if (source) {
            *source = NFNotificationHistorySourceMirror;
        }
        return snapshotEntries;
    }

    NFPEnsureAppSupportLoaded();
    Class centerClass = NSClassFromString(@"CPDistributedMessagingCenter");
    if (!centerClass) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tune.notificationfilter.history"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"RULE_SCAN_SOURCE_FAILED"}];
        }
        if (source) {
            *source = nil;
        }
        return @[];
    }

    id center = ((id (*)(id, SEL, id))objc_msgSend)(centerClass,
                                                    @selector(centerNamed:),
                                                    NFNotificationHistoryMessagingCenterName);
    if (!center) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.tune.notificationfilter.history"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"RULE_SCAN_SOURCE_FAILED"}];
        }
        if (source) {
            *source = nil;
        }
        return @[];
    }
    rocketbootstrap_distributedmessagingcenter_apply(center);

    NSDictionary *requestUserInfo = @{
        NFNotificationHistoryBundleIdentifierKey: normalizedBundleIdentifier,
        NFNotificationHistoryLimitKey: @200
    };

    NSDictionary *reply = nil;
    SEL replyWithErrorSelector = @selector(sendMessageAndReceiveReplyName:userInfo:error:);
    SEL replySelector = @selector(sendMessageAndReceiveReplyName:userInfo:);
    if ([center respondsToSelector:replyWithErrorSelector]) {
        reply = ((id (*)(id, SEL, id, id, NSError **))objc_msgSend)(center,
                                                                     replyWithErrorSelector,
                                                                     NFNotificationHistoryFetchMessageName,
                                                                     requestUserInfo,
                                                                     error);
    } else if ([center respondsToSelector:replySelector]) {
        reply = ((id (*)(id, SEL, id, id))objc_msgSend)(center,
                                                        replySelector,
                                                        NFNotificationHistoryFetchMessageName,
                                                        requestUserInfo);
    }
    if (![reply isKindOfClass:[NSDictionary class]]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.tune.notificationfilter.history"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"RULE_SCAN_SOURCE_NO_REPLY"}];
        }
        if (source) {
            *source = nil;
        }
        return @[];
    }

    NSString *replySource = [reply[NFNotificationHistorySourceKey] isKindOfClass:[NSString class]] ? reply[NFNotificationHistorySourceKey] : nil;
    if (source) {
        *source = replySource;
    }

    NSString *errorMessage = [reply[NFNotificationHistoryErrorKey] isKindOfClass:[NSString class]] ? reply[NFNotificationHistoryErrorKey] : nil;
    if (errorMessage.length > 0 && error) {
        *error = [NSError errorWithDomain:@"com.tune.notificationfilter.history"
                                     code:2
                                 userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
    }

    NSArray *entries = [reply[NFNotificationHistoryEntriesKey] isKindOfClass:[NSArray class]] ? reply[NFNotificationHistoryEntriesKey] : @[];
    NSMutableArray<NSDictionary *> *normalizedEntries = [NSMutableArray arrayWithCapacity:entries.count];
    for (id entry in entries) {
        if ([entry isKindOfClass:[NSDictionary class]]) {
            [normalizedEntries addObject:entry];
        }
    }
    return normalizedEntries;
}

@end
