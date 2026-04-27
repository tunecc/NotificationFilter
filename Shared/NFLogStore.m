#import "NFLogStore.h"
#import "NFPreferences.h"

static NSString *NFNormalizedLogString(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }

    NSString *stringValue = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return stringValue.length > 0 ? stringValue : nil;
}

@implementation NFLogStore

+ (dispatch_queue_t)_logQueue {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.tune.notificationfilter.logstore", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

+ (NSTimeInterval)_dedupeWindow {
    return 2.0;
}

+ (NSString *)_dedupeSignatureForEntry:(NSDictionary *)entry {
    NSString *bulletinID = NFNormalizedLogString(entry[NFLogBulletinIDKey]);
    NSString *recordID = NFNormalizedLogString(entry[NFLogRecordIDKey]);
    NSString *publisherBulletinID = NFNormalizedLogString(entry[NFLogPublisherBulletinIDKey]);
    if (bulletinID.length == 0 && recordID.length == 0 && publisherBulletinID.length == 0) {
        return nil;
    }

    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@|%@",
                                      NFNormalizedLogString(entry[NFLogBundleIdentifierKey]) ?: @"",
                                      NFNormalizedLogString(entry[NFLogSectionIDKey]) ?: @"",
                                      bulletinID ?: @"",
                                      recordID ?: @"",
                                      publisherBulletinID ?: @"",
                                      NFNormalizedLogString(entry[NFLogMatchedScopeKey]) ?: @"",
                                      NFNormalizedLogString(entry[NFLogMatchedPatternKey]) ?: @""];
}

+ (NSUInteger)_recentMatchingIndexForEntry:(NSDictionary *)entry
                                  inEntries:(NSArray<NSDictionary *> *)entries {
    NSString *signature = [self _dedupeSignatureForEntry:entry];
    if (signature.length == 0) {
        return NSNotFound;
    }

    NSTimeInterval timestamp = [entry[NFLogTimestampKey] respondsToSelector:@selector(doubleValue)] ?
        [entry[NFLogTimestampKey] doubleValue] :
        [[NSDate date] timeIntervalSince1970];
    NSUInteger maxScanCount = MIN(entries.count, (NSUInteger)20);
    for (NSUInteger index = 0; index < maxScanCount; index++) {
        NSDictionary *existingEntry = entries[index];
        NSString *existingSignature = [self _dedupeSignatureForEntry:existingEntry];
        if (existingSignature.length == 0 || ![existingSignature isEqualToString:signature]) {
            continue;
        }

        if (![existingEntry[NFLogTimestampKey] respondsToSelector:@selector(doubleValue)]) {
            continue;
        }

        NSTimeInterval existingTimestamp = [existingEntry[NFLogTimestampKey] doubleValue];
        if (fabs(existingTimestamp - timestamp) <= [self _dedupeWindow]) {
            return index;
        }
    }

    return NSNotFound;
}

+ (NSArray<NSDictionary *> *)loadEntries {
    NSString *logPath = [NFPreferences logsFilePath];
    NSArray *entries = [NSArray arrayWithContentsOfFile:logPath];
    if (![entries isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<NSDictionary *> *normalizedEntries = [NSMutableArray array];
    for (id entry in entries) {
        if ([entry isKindOfClass:[NSDictionary class]]) {
            [normalizedEntries addObject:entry];
        }
    }

    return normalizedEntries;
}

+ (void)appendBlockedEntry:(NSDictionary *)entry {
    if (![entry isKindOfClass:[NSDictionary class]]) {
        return;
    }

    dispatch_async([self _logQueue], ^{
        NSMutableDictionary *mutableEntry = [entry mutableCopy];
        if (![mutableEntry[NFLogIdentifierKey] isKindOfClass:[NSString class]]) {
            mutableEntry[NFLogIdentifierKey] = [NSUUID UUID].UUIDString;
        }
        if (![mutableEntry[NFLogTimestampKey] respondsToSelector:@selector(doubleValue)]) {
            mutableEntry[NFLogTimestampKey] = @([[NSDate date] timeIntervalSince1970]);
        }

        NSMutableArray<NSDictionary *> *entries = [[self loadEntries] mutableCopy];
        NSUInteger matchingIndex = [self _recentMatchingIndexForEntry:mutableEntry inEntries:entries];
        if (matchingIndex != NSNotFound) {
            NSMutableDictionary *mergedEntry = [entries[matchingIndex] mutableCopy];
            NSString *existingIdentifier = [mergedEntry[NFLogIdentifierKey] isKindOfClass:[NSString class]] ?
                mergedEntry[NFLogIdentifierKey] :
                nil;
            [mergedEntry addEntriesFromDictionary:mutableEntry];
            if (existingIdentifier.length > 0) {
                mergedEntry[NFLogIdentifierKey] = existingIdentifier;
            }

            [entries removeObjectAtIndex:matchingIndex];
            [entries insertObject:[mergedEntry copy] atIndex:0];
        } else {
            [entries insertObject:[mutableEntry copy] atIndex:0];
        }
        if (entries.count > 500) {
            [entries removeObjectsInRange:NSMakeRange(500, entries.count - 500)];
        }

        NSString *logPath = [NFPreferences logsFilePath];
        NSString *directoryPath = [logPath stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        [entries writeToFile:logPath atomically:YES];
    });
}

+ (void)clearEntries {
    dispatch_sync([self _logQueue], ^{
        NSString *logPath = [NFPreferences logsFilePath];
        [[NSFileManager defaultManager] removeItemAtPath:logPath error:nil];
    });
}

@end
