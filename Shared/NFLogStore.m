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

+ (NSUInteger)_currentEntryLimit {
    NSDictionary *preferences = [NFPreferences loadPreferences];
    return (NSUInteger)[NFPreferences normalizedLogEntryLimit:preferences[NFLogEntryLimitKey]];
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

+ (NSString *)_clearStatePath {
    return [[NFPreferences logsFilePath] stringByAppendingString:@".cleared.plist"];
}

+ (NSMutableDictionary *)_loadClearState {
    NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:[self _clearStatePath]];
    if (![state isKindOfClass:[NSDictionary class]]) {
        return [NSMutableDictionary dictionary];
    }
    return [state mutableCopy];
}

+ (void)_saveClearState:(NSDictionary *)state {
    NSString *statePath = [self _clearStatePath];
    NSString *directoryPath = [statePath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [state writeToFile:statePath atomically:YES];
}

+ (NSString *)_clearSignatureForEntry:(NSDictionary *)entry {
    NSString *bundleIdentifier = NFNormalizedLogString(entry[NFLogBundleIdentifierKey]);
    if (bundleIdentifier.length == 0) {
        return nil;
    }

    NSString *sectionID = NFNormalizedLogString(entry[NFLogSectionIDKey]);
    NSString *bulletinID = NFNormalizedLogString(entry[NFLogBulletinIDKey]);
    NSString *recordID = NFNormalizedLogString(entry[NFLogRecordIDKey]);
    NSString *publisherBulletinID = NFNormalizedLogString(entry[NFLogPublisherBulletinIDKey]);
    if (bulletinID.length > 0 || recordID.length > 0 || publisherBulletinID.length > 0) {
        return [NSString stringWithFormat:@"id|%@|%@|%@|%@|%@",
                                          bundleIdentifier,
                                          sectionID ?: @"",
                                          bulletinID ?: @"",
                                          recordID ?: @"",
                                          publisherBulletinID ?: @""];
    }

    return nil;
}

+ (void)_markEntriesClearedForBundleIdentifier:(NSString *)bundleIdentifier
                                       entries:(NSArray<NSDictionary *> *)entries
                                     clearTime:(NSTimeInterval)clearTime
                                         state:(NSMutableDictionary *)state {
    NSString *normalizedBundleIdentifier = NFNormalizedLogString(bundleIdentifier);
    if (normalizedBundleIdentifier.length == 0) {
        return;
    }

    NSMutableSet<NSString *> *signatures = [NSMutableSet set];
    NSDictionary *existingBundleState = [state[normalizedBundleIdentifier] isKindOfClass:[NSDictionary class]] ?
        state[normalizedBundleIdentifier] :
        nil;
    NSArray *existingSignatures = [existingBundleState[@"signatures"] isKindOfClass:[NSArray class]] ?
        existingBundleState[@"signatures"] :
        @[];
    for (id signature in existingSignatures) {
        if ([signature isKindOfClass:[NSString class]] && [signature length] > 0) {
            [signatures addObject:signature];
        }
    }

    for (NSDictionary *entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        NSString *entryBundleIdentifier = NFNormalizedLogString(entry[NFLogBundleIdentifierKey]);
        if (![entryBundleIdentifier isEqualToString:normalizedBundleIdentifier]) {
            continue;
        }

        NSString *signature = [self _clearSignatureForEntry:entry];
        if (signature.length > 0) {
            [signatures addObject:signature];
        }
    }

    NSTimeInterval existingClearTime = [existingBundleState[@"clearedAt"] respondsToSelector:@selector(doubleValue)] ?
        [existingBundleState[@"clearedAt"] doubleValue] :
        0;
    state[normalizedBundleIdentifier] = @{
        @"clearedAt": @(MAX(existingClearTime, clearTime)),
        @"signatures": [signatures.allObjects sortedArrayUsingSelector:@selector(compare:)]
    };
}

+ (BOOL)_entryMatchesClearState:(NSDictionary *)entry clearState:(NSDictionary *)state {
    NSString *bundleIdentifier = NFNormalizedLogString(entry[NFLogBundleIdentifierKey]);
    if (bundleIdentifier.length == 0) {
        return NO;
    }

    NSDictionary *bundleState = [state[bundleIdentifier] isKindOfClass:[NSDictionary class]] ?
        state[bundleIdentifier] :
        nil;
    if (!bundleState) {
        return NO;
    }

    NSTimeInterval clearedAt = [bundleState[@"clearedAt"] respondsToSelector:@selector(doubleValue)] ?
        [bundleState[@"clearedAt"] doubleValue] :
        0;
    NSTimeInterval entryTimestamp = [entry[NFLogTimestampKey] respondsToSelector:@selector(doubleValue)] ?
        [entry[NFLogTimestampKey] doubleValue] :
        0;
    if (clearedAt > 0 && entryTimestamp > 0 && entryTimestamp <= clearedAt) {
        return YES;
    }

    NSString *signature = [self _clearSignatureForEntry:entry];
    NSArray *signatures = [bundleState[@"signatures"] isKindOfClass:[NSArray class]] ?
        bundleState[@"signatures"] :
        @[];
    return signature.length > 0 && [signatures containsObject:signature];
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

        if ([self _entryMatchesClearState:mutableEntry clearState:[self _loadClearState]]) {
            return;
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
        NSUInteger entryLimit = [self _currentEntryLimit];
        if (entries.count > entryLimit) {
            [entries removeObjectsInRange:NSMakeRange(entryLimit, entries.count - entryLimit)];
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
        NSArray *existingEntries = [NSArray arrayWithContentsOfFile:logPath];
        if ([existingEntries isKindOfClass:[NSArray class]] && existingEntries.count > 0) {
            NSMutableDictionary *clearState = [self _loadClearState];
            NSMutableSet<NSString *> *bundleIdentifiers = [NSMutableSet set];
            for (id entry in existingEntries) {
                if (![entry isKindOfClass:[NSDictionary class]]) {
                    continue;
                }
                NSString *bundleIdentifier = NFNormalizedLogString(((NSDictionary *)entry)[NFLogBundleIdentifierKey]);
                if (bundleIdentifier.length > 0) {
                    [bundleIdentifiers addObject:bundleIdentifier];
                }
            }

            NSTimeInterval clearTime = [[NSDate date] timeIntervalSince1970];
            for (NSString *bundleIdentifier in bundleIdentifiers) {
                [self _markEntriesClearedForBundleIdentifier:bundleIdentifier
                                                     entries:(NSArray<NSDictionary *> *)existingEntries
                                                   clearTime:clearTime
                                                       state:clearState];
            }
            [self _saveClearState:clearState];
        }
        [[NSFileManager defaultManager] removeItemAtPath:logPath error:nil];
    });
}

+ (void)clearEntriesForBundleIdentifier:(NSString *)bundleIdentifier {
    NSString *normalizedBundleIdentifier = NFNormalizedLogString(bundleIdentifier);
    if (normalizedBundleIdentifier.length == 0) {
        return;
    }

    dispatch_sync([self _logQueue], ^{
        NSString *logPath = [NFPreferences logsFilePath];
        NSArray *existingEntries = [NSArray arrayWithContentsOfFile:logPath];
        NSMutableDictionary *clearState = [self _loadClearState];
        [self _markEntriesClearedForBundleIdentifier:normalizedBundleIdentifier
                                             entries:[existingEntries isKindOfClass:[NSArray class]] ? (NSArray<NSDictionary *> *)existingEntries : @[]
                                           clearTime:[[NSDate date] timeIntervalSince1970]
                                               state:clearState];
        [self _saveClearState:clearState];

        if (![existingEntries isKindOfClass:[NSArray class]] || existingEntries.count == 0) {
            return;
        }

        NSMutableArray<NSDictionary *> *remainingEntries = [NSMutableArray arrayWithCapacity:existingEntries.count];
        for (id entry in existingEntries) {
            if (![entry isKindOfClass:[NSDictionary class]]) {
                continue;
            }

            NSString *entryBundleIdentifier = NFNormalizedLogString(((NSDictionary *)entry)[NFLogBundleIdentifierKey]);
            if ([entryBundleIdentifier isEqualToString:normalizedBundleIdentifier]) {
                continue;
            }
            [remainingEntries addObject:entry];
        }

        if (remainingEntries.count == existingEntries.count) {
            return;
        }

        if (remainingEntries.count == 0) {
            [[NSFileManager defaultManager] removeItemAtPath:logPath error:nil];
            return;
        }

        [remainingEntries writeToFile:logPath atomically:YES];
    });
}

+ (void)trimEntriesToCurrentLimit {
    dispatch_sync([self _logQueue], ^{
        NSUInteger entryLimit = [self _currentEntryLimit];
        NSString *logPath = [NFPreferences logsFilePath];
        NSArray *existingEntries = [NSArray arrayWithContentsOfFile:logPath];
        if (![existingEntries isKindOfClass:[NSArray class]] || existingEntries.count <= entryLimit) {
            return;
        }

        NSArray *trimmedEntries = [existingEntries subarrayWithRange:NSMakeRange(0, entryLimit)];
        [trimmedEntries writeToFile:logPath atomically:YES];
    });
}

@end
