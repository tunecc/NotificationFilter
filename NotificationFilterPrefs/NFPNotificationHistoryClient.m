#import "NFPNotificationHistoryClient.h"
#import "../Shared/NFPreferences.h"
#import "../Shared/NFNotificationHistoryBridge.h"

@implementation NFPNotificationHistoryClient

+ (NSString *)_normalizedBundleIdentifier:(NSString *)bundleIdentifier {
    return [bundleIdentifier stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

+ (BOOL)_ensureDirectoryForFilePath:(NSString *)filePath error:(NSError **)error {
    NSString *directoryPath = [filePath stringByDeletingLastPathComponent];
    return [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:error];
}

+ (NSString *)requestRefreshForBundleIdentifier:(NSString *)bundleIdentifier
                                          limit:(NSUInteger)limit
                                          error:(NSError **)error {
    NSString *normalizedBundleIdentifier = [self _normalizedBundleIdentifier:bundleIdentifier];
    if (normalizedBundleIdentifier.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tune.notificationfilter.history"
                                         code:10
                                     userInfo:@{NSLocalizedDescriptionKey: @"RULE_SCAN_SOURCE_FAILED"}];
        }
        return nil;
    }

    NSString *requestIdentifier = [[NSUUID UUID] UUIDString];
    NSDictionary *request = @{
        NFNotificationHistoryRequestIdentifierKey: requestIdentifier,
        NFNotificationHistoryBundleIdentifierKey: normalizedBundleIdentifier,
        NFNotificationHistoryLimitKey: @(limit > 0 ? limit : 200),
        NFLogTimestampKey: @([[NSDate date] timeIntervalSince1970])
    };

    NSString *requestPath = NFNotificationHistoryRefreshRequestFilePath();
    if (![self _ensureDirectoryForFilePath:requestPath error:error]) {
        return nil;
    }

    if (![request writeToFile:requestPath atomically:YES]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tune.notificationfilter.history"
                                         code:11
                                     userInfo:@{NSLocalizedDescriptionKey: @"RULE_SCAN_SOURCE_FAILED"}];
        }
        return nil;
    }

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)NFNotificationHistoryRefreshRequestNotification,
                                         NULL,
                                         NULL,
                                         YES);
    return requestIdentifier;
}

+ (NSDictionary *)refreshStatusForRequestIdentifier:(NSString *)requestIdentifier
                                   bundleIdentifier:(NSString *)bundleIdentifier {
    if (requestIdentifier.length == 0) {
        return nil;
    }

    NSDictionary *status = [NSDictionary dictionaryWithContentsOfFile:NFNotificationHistoryRefreshStatusFilePath()];
    if (![status isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSString *statusRequestIdentifier = [status[NFNotificationHistoryRequestIdentifierKey] isKindOfClass:[NSString class]] ?
        status[NFNotificationHistoryRequestIdentifierKey] :
        nil;
    if (![statusRequestIdentifier isEqualToString:requestIdentifier]) {
        return nil;
    }

    NSString *normalizedBundleIdentifier = [self _normalizedBundleIdentifier:bundleIdentifier];
    NSString *statusBundleIdentifier = [status[NFNotificationHistoryBundleIdentifierKey] isKindOfClass:[NSString class]] ?
        status[NFNotificationHistoryBundleIdentifierKey] :
        nil;
    if (normalizedBundleIdentifier.length > 0 && ![statusBundleIdentifier isEqualToString:normalizedBundleIdentifier]) {
        return nil;
    }

    return status;
}

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
    NSString *normalizedBundleIdentifier = [self _normalizedBundleIdentifier:bundleIdentifier];
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

    if (source) {
        *source = nil;
    }
    return @[];
}

@end
