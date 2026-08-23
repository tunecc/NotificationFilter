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

// 进程内写合并缓存。所有字段仅在 _logQueue 上下文访问，由队列串行化保证线程安全。
// _pendingEntries 代表内存中认为的磁盘最终状态；append 操作它（去重合并 + 裁剪），_flushLocked 落盘。
static NSMutableArray<NSDictionary *> *NFLogStorePendingEntries = nil;
static BOOL NFLogStoreDirty = NO;
static BOOL NFLogStoreFlushPending = NO;

+ (NSTimeInterval)_flushInterval {
    return 2.0;
}

// 仅在 _logQueue 上下文调用。首次或缓存作废时从磁盘加载一次，后续直接复用。
+ (NSMutableArray<NSDictionary *> *)_pendingEntriesLocked {
    if (NFLogStorePendingEntries == nil) {
        NSMutableArray *loaded = [[self loadEntries] mutableCopy];
        NFLogStorePendingEntries = loaded ?: [NSMutableArray array];
    }
    return NFLogStorePendingEntries;
}

// 仅在 _logQueue 上下文调用。clear/trim 落盘后作废缓存，强制下次 append 从磁盘重新加载，
// 避免陈旧缓存回写复活已被其它路径（跨进程 clear/trim）处理掉的条目。
+ (void)_invalidateCacheLocked {
    NFLogStorePendingEntries = nil;
    NFLogStoreDirty = NO;
    NFLogStoreFlushPending = NO;
}

// 仅在 _logQueue 上下文调用。把缓存合并落盘：重读跨进程共享的 clear-state 过滤、重读 entryLimit 裁剪、原子写。
+ (void)_flushLocked {
    NFLogStoreFlushPending = NO;
    if (!NFLogStoreDirty) {
        return;
    }

    NSMutableArray<NSDictionary *> *entries = [self _pendingEntriesLocked];

    NSDictionary *clearState = [self _loadClearState];
    if (clearState.count > 0) {
        NSMutableIndexSet *indexesToRemove = [NSMutableIndexSet indexSet];
        [entries enumerateObjectsUsingBlock:^(NSDictionary *entry, NSUInteger idx, BOOL *stop) {
            if ([self _entryMatchesClearState:entry clearState:clearState]) {
                [indexesToRemove addIndex:idx];
            }
        }];
        [entries removeObjectsAtIndexes:indexesToRemove];
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
    if (entries.count > 0) {
        [entries writeToFile:logPath atomically:YES];
    } else {
        [[NSFileManager defaultManager] removeItemAtPath:logPath error:nil];
    }

    NFLogStoreDirty = NO;
}

// 仅在 _logQueue 上下文调用。Leading-edge 防抖：首个待写条目安排一次 2 秒后的 flush，
// 窗口内后续 append 不重排定时器，保证洪峰期最坏每 2 秒落盘一次且首条及时可见。
+ (void)_scheduleFlushLocked {
    if (NFLogStoreFlushPending) {
        return;
    }
    NFLogStoreFlushPending = YES;
    dispatch_queue_t queue = [self _logQueue];
    dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)([self _flushInterval] * NSEC_PER_SEC));
    dispatch_after(when, queue, ^{
        [self _flushLocked];
    });
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
    for (NSUInteger index = 0; index < entries.count; index++) {
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

        NSMutableArray<NSDictionary *> *entries = [self _pendingEntriesLocked];
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

        NFLogStoreDirty = YES;
        [self _scheduleFlushLocked];
    });
}

+ (void)clearEntries {
    dispatch_sync([self _logQueue], ^{
        // 先把未 flush 的缓存落盘，保证 clear 处理到最新状态；随后作废缓存避免回写复活。
        [self _flushLocked];
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
        [self _invalidateCacheLocked];
    });
}

+ (void)clearEntriesForBundleIdentifier:(NSString *)bundleIdentifier {
    NSString *normalizedBundleIdentifier = NFNormalizedLogString(bundleIdentifier);
    if (normalizedBundleIdentifier.length == 0) {
        return;
    }

    dispatch_sync([self _logQueue], ^{
        // 先 flush 未落盘缓存，再执行磁盘过滤，最后作废缓存，保证被清 bundle 的新条目不会因缓存回写复活。
        [self _flushLocked];
        NSString *logPath = [NFPreferences logsFilePath];
        NSArray *existingEntries = [NSArray arrayWithContentsOfFile:logPath];
        NSMutableDictionary *clearState = [self _loadClearState];
        [self _markEntriesClearedForBundleIdentifier:normalizedBundleIdentifier
                                             entries:[existingEntries isKindOfClass:[NSArray class]] ? (NSArray<NSDictionary *> *)existingEntries : @[]
                                           clearTime:[[NSDate date] timeIntervalSince1970]
                                               state:clearState];
        [self _saveClearState:clearState];

        if (![existingEntries isKindOfClass:[NSArray class]] || existingEntries.count == 0) {
            [self _invalidateCacheLocked];
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
            [self _invalidateCacheLocked];
            return;
        }

        if (remainingEntries.count == 0) {
            [[NSFileManager defaultManager] removeItemAtPath:logPath error:nil];
            [self _invalidateCacheLocked];
            return;
        }

        [remainingEntries writeToFile:logPath atomically:YES];
        [self _invalidateCacheLocked];
    });
}

+ (void)trimEntriesToCurrentLimit {
    dispatch_sync([self _logQueue], ^{
        // 先 flush 未落盘缓存，再按最新 limit 裁剪磁盘，最后作废缓存。
        [self _flushLocked];
        NSUInteger entryLimit = [self _currentEntryLimit];
        NSString *logPath = [NFPreferences logsFilePath];
        NSArray *existingEntries = [NSArray arrayWithContentsOfFile:logPath];
        if (![existingEntries isKindOfClass:[NSArray class]] || existingEntries.count <= entryLimit) {
            [self _invalidateCacheLocked];
            return;
        }

        NSArray *trimmedEntries = [existingEntries subarrayWithRange:NSMakeRange(0, entryLimit)];
        [trimmedEntries writeToFile:logPath atomically:YES];
        [self _invalidateCacheLocked];
    });
}

// 仅供测试：在 _logQueue 上下文强制 flush 落盘，验证写合并契约（未 flush 不落盘 / flush 后落盘）。
+ (void)_flushLockedForTesting {
    dispatch_sync([self _logQueue], ^{
        [self _flushLocked];
    });
}

@end
