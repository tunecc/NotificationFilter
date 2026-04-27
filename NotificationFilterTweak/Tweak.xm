#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <string.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "NFNotificationRecord.h"
#import "NFRuleEngine.h"
#import "../Shared/NFPreferences.h"
#import "../Shared/NFLogStore.h"

static NSDictionary *NFCurrentPreferences = nil;
static dispatch_queue_t NFPreferencesQueue = nil;
static void *NFBBServerQueueSpecificKey = &NFBBServerQueueSpecificKey;
static dispatch_queue_t NFBlockedActionQueue = nil;
static NSMutableDictionary<NSString *, NSNumber *> *NFBlockedActionTimestamps = nil;
static dispatch_queue_t NFBlockedIdentityQueue = nil;
static NSMutableDictionary<NSString *, NSDictionary *> *NFBlockedIdentityCache = nil;
typedef void (*NFWithdrawByRecordIDFunction)(id dataProvider, NSString *recordID);
typedef void (*NFWithdrawByPublisherBulletinIDFunction)(id dataProvider, NSString *publisherBulletinID);
typedef void (^NFBooleanCompletionBlock)(BOOL value);
typedef void (^NFBooleanErrorCompletionBlock)(BOOL value, NSError *error);
static void NFAttemptDeleteFilteredBulletin(id server,
                                            id bulletin,
                                            NFNotificationRecord *record,
                                            NFMatchResult *result);
static void NFClearTransientBlockedCaches(void);

static NSDictionary *NFCopyPreferencesSnapshot(void) {
    __block NSDictionary *snapshot = nil;
    dispatch_sync(NFPreferencesQueue, ^{
        snapshot = NFCurrentPreferences ?: [NFPreferences defaultPreferences];
    });
    return snapshot;
}

static BOOL NFShouldDeleteFilteredNotifications(void) {
    return [NFCopyPreferencesSnapshot()[NFDeleteFilteredNotificationsKey] boolValue];
}

static void NFUpdatePreferencesSnapshot(NSDictionary *preferences) {
    dispatch_sync(NFPreferencesQueue, ^{
        NFCurrentPreferences = [preferences copy];
    });
}

static void NFReloadPreferences(void) {
    NFUpdatePreferencesSnapshot([NFPreferences loadPreferences]);
    NFClearTransientBlockedCaches();
}

static void NFPreferencesChangedCallback(CFNotificationCenterRef center,
                                         void *observer,
                                         CFStringRef name,
                                         const void *object,
                                         CFDictionaryRef userInfo) {
    NFReloadPreferences();
}

static NSMutableDictionary *NFBuildBlockedLogEntry(NFNotificationRecord *record, NFMatchResult *result) {
    if (!result.shouldBlock) {
        return nil;
    }

    NSMutableDictionary *logEntry = [[record dictionaryRepresentation] mutableCopy];
    if (result.matchedScope.length > 0) {
        logEntry[NFLogMatchedScopeKey] = result.matchedScope;
    }
    if (result.matchedMode.length > 0) {
        logEntry[NFLogMatchedModeKey] = result.matchedMode;
    }
    if (result.matchedPattern.length > 0) {
        logEntry[NFLogMatchedPatternKey] = result.matchedPattern;
    }

    return logEntry;
}

static void NFAppendBlockedLog(NFNotificationRecord *record, NFMatchResult *result) {
    if (!result.shouldBlock) {
        return;
    }

    NSMutableDictionary *logEntry = NFBuildBlockedLogEntry(record, result);
    [NFLogStore appendBlockedEntry:logEntry];
}

static id NFCallObject(id obj, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!obj || !selector || ![obj respondsToSelector:selector]) {
        return nil;
    }

    return ((id (*)(id, SEL))objc_msgSend)(obj, selector);
}

static NSString *NFNormalizedStringValue(id value) {
    if (!value) {
        return nil;
    }

    NSString *stringValue = nil;
    if ([value isKindOfClass:[NSString class]]) {
        stringValue = value;
    } else if ([value respondsToSelector:@selector(stringValue)]) {
        id response = ((id (*)(id, SEL))objc_msgSend)(value, @selector(stringValue));
        if ([response isKindOfClass:[NSString class]]) {
            stringValue = response;
        }
    }

    return [stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSTimeInterval NFBlockedActionDedupeWindow(void) {
    return 2.0;
}

static NSTimeInterval NFBlockedIdentityTTL(void) {
    return 900.0;
}

static NSString *NFBlockedActionRecordKey(NFNotificationRecord *record, NFMatchResult *result) {
    if (!record || !result.shouldBlock) {
        return nil;
    }

    NSString *bulletinID = NFNormalizedStringValue(record.bulletinID);
    NSString *recordID = NFNormalizedStringValue(record.recordID);
    NSString *publisherBulletinID = NFNormalizedStringValue(record.publisherBulletinID);
    if (bulletinID.length == 0 && recordID.length == 0 && publisherBulletinID.length == 0) {
        return nil;
    }

    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@|%@",
                                      NFNormalizedStringValue(record.bundleIdentifier) ?: @"",
                                      NFNormalizedStringValue(record.sectionID) ?: @"",
                                      bulletinID ?: @"",
                                      recordID ?: @"",
                                      publisherBulletinID ?: @"",
                                      NFNormalizedStringValue(result.matchedScope) ?: @"",
                                      NFNormalizedStringValue(result.matchedPattern) ?: @""];
}

static NSArray<NSString *> *NFBlockedIdentityKeysForRecord(NFNotificationRecord *record) {
    NSMutableArray<NSString *> *keys = [NSMutableArray array];

    NSString *bulletinID = NFNormalizedStringValue(record.bulletinID);
    if (bulletinID.length > 0) {
        [keys addObject:[NSString stringWithFormat:@"bulletin:%@", bulletinID]];
    }

    NSString *recordID = NFNormalizedStringValue(record.recordID);
    if (recordID.length > 0) {
        [keys addObject:[NSString stringWithFormat:@"record:%@", recordID]];
    }

    NSString *publisherBulletinID = NFNormalizedStringValue(record.publisherBulletinID);
    if (publisherBulletinID.length > 0) {
        [keys addObject:[NSString stringWithFormat:@"publisher:%@", publisherBulletinID]];
    }

    return keys;
}

static void NFPurgeExpiredBlockedIdentityEntriesLocked(NSTimeInterval now) {
    NSTimeInterval ttl = NFBlockedIdentityTTL();
    NSMutableArray<NSString *> *expiredKeys = [NSMutableArray array];

    [NFBlockedIdentityCache enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *entry, BOOL *stop) {
        NSNumber *timestamp = [entry[@"timestamp"] respondsToSelector:@selector(doubleValue)] ? entry[@"timestamp"] : nil;
        if (!timestamp || (now - timestamp.doubleValue) > ttl) {
            [expiredKeys addObject:key];
        }
    }];

    if (expiredKeys.count > 0) {
        [NFBlockedIdentityCache removeObjectsForKeys:expiredKeys];
    }
}

static BOOL NFIsExplicitAllowResult(NFMatchResult *result) {
    return !result.shouldBlock && [result.matchedMode isEqualToString:NFMatchModeExclude];
}

static void NFRememberBlockedIdentityForRecord(NFNotificationRecord *record, NFMatchResult *result) {
    if (!record || !result.shouldBlock) {
        return;
    }

    NSArray<NSString *> *identityKeys = NFBlockedIdentityKeysForRecord(record);
    if (identityKeys.count == 0) {
        return;
    }

    NSDictionary *entry = @{
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
        @"matchedScope": result.matchedScope ?: @"",
        @"matchedMode": result.matchedMode ?: @"",
        @"matchedPattern": result.matchedPattern ?: @""
    };

    dispatch_sync(NFBlockedIdentityQueue, ^{
        NFPurgeExpiredBlockedIdentityEntriesLocked([entry[@"timestamp"] doubleValue]);
        for (NSString *key in identityKeys) {
            NFBlockedIdentityCache[key] = entry;
        }
    });
}

static NSDictionary *NFCachedBlockedIdentityEntryForRecord(NFNotificationRecord *record) {
    NSArray<NSString *> *identityKeys = NFBlockedIdentityKeysForRecord(record);
    if (identityKeys.count == 0) {
        return nil;
    }

    __block NSDictionary *matchedEntry = nil;
    dispatch_sync(NFBlockedIdentityQueue, ^{
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NFPurgeExpiredBlockedIdentityEntriesLocked(now);
        for (NSString *key in identityKeys) {
            NSDictionary *entry = NFBlockedIdentityCache[key];
            if (entry) {
                matchedEntry = entry;
                break;
            }
        }
    });

    return matchedEntry;
}

static NFMatchResult *NFCachedBlockedIdentityResultForRecord(NFNotificationRecord *record) {
    NSDictionary *entry = NFCachedBlockedIdentityEntryForRecord(record);
    if (!entry) {
        return nil;
    }

    NFMatchResult *result = [[NFMatchResult alloc] init];
    result.shouldBlock = YES;
    result.matchedScope = [entry[@"matchedScope"] isKindOfClass:[NSString class]] ? entry[@"matchedScope"] : nil;
    result.matchedMode = [entry[@"matchedMode"] isKindOfClass:[NSString class]] ? entry[@"matchedMode"] : nil;
    result.matchedPattern = [entry[@"matchedPattern"] isKindOfClass:[NSString class]] ? entry[@"matchedPattern"] : nil;
    return result;
}

static void NFClearTransientBlockedCaches(void) {
    if (NFBlockedActionQueue) {
        dispatch_sync(NFBlockedActionQueue, ^{
            [NFBlockedActionTimestamps removeAllObjects];
        });
    }

    if (NFBlockedIdentityQueue) {
        dispatch_sync(NFBlockedIdentityQueue, ^{
            [NFBlockedIdentityCache removeAllObjects];
        });
    }
}

static NFMatchResult *NFEvaluateRecord(NFNotificationRecord *record) {
    NSDictionary *preferences = NFCopyPreferencesSnapshot();
    NFMatchResult *result = [NFRuleEngine evaluateRecord:record preferences:preferences];
    if (![preferences[NFEnabledKey] boolValue]) {
        return result;
    }

    if (result.shouldBlock) {
        NFRememberBlockedIdentityForRecord(record, result);
        return result;
    }

    if (NFIsExplicitAllowResult(result)) {
        return result;
    }

    NFMatchResult *cachedBlockedResult = NFCachedBlockedIdentityResultForRecord(record);
    if (cachedBlockedResult.shouldBlock) {
        return cachedBlockedResult;
    }

    return result;
}

static BOOL NFShouldPerformBlockedAction(NSString *actionName,
                                         NFNotificationRecord *record,
                                         NFMatchResult *result) {
    NSString *recordKey = NFBlockedActionRecordKey(record, result);
    if (recordKey.length == 0 || actionName.length == 0) {
        return YES;
    }

    NSString *actionKey = [NSString stringWithFormat:@"%@|%@", actionName, recordKey];
    __block BOOL shouldPerform = YES;
    dispatch_sync(NFBlockedActionQueue, ^{
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSTimeInterval dedupeWindow = NFBlockedActionDedupeWindow();
        NSMutableArray<NSString *> *expiredKeys = [NSMutableArray array];

        [NFBlockedActionTimestamps enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *timestamp, BOOL *stop) {
            if (now - timestamp.doubleValue <= dedupeWindow) {
                return;
            }

            [expiredKeys addObject:key];
        }];
        if (expiredKeys.count > 0) {
            [NFBlockedActionTimestamps removeObjectsForKeys:expiredKeys];
        }

        NSNumber *lastTimestamp = NFBlockedActionTimestamps[actionKey];
        if (lastTimestamp && (now - lastTimestamp.doubleValue) <= dedupeWindow) {
            shouldPerform = NO;
            return;
        }

        NFBlockedActionTimestamps[actionKey] = @(now);
    });

    return shouldPerform;
}

static id NFSectionIdentifierCandidate(id obj) {
    id sectionIdentifier = NFCallObject(obj, @"sectionIdentifier");
    if (sectionIdentifier) {
        return sectionIdentifier;
    }

    sectionIdentifier = NFCallObject(obj, @"sectionID");
    if (sectionIdentifier) {
        return sectionIdentifier;
    }

    return NFCallObject(obj, @"section");
}

static void NFBackfillRecordSectionIdentifier(NFNotificationRecord *record, id sectionIdentifier) {
    NSString *resolvedSectionIdentifier = NFNormalizedStringValue(sectionIdentifier);
    if (resolvedSectionIdentifier.length == 0) {
        return;
    }

    if (record.bundleIdentifier.length == 0) {
        record.bundleIdentifier = resolvedSectionIdentifier;
    }
    if (record.sectionID.length == 0) {
        record.sectionID = resolvedSectionIdentifier;
    }
}

static BOOL NFCanDeleteFilteredNotificationWithServer(id server) {
    if (!server) {
        return NO;
    }

    return [server respondsToSelector:NSSelectorFromString(@"dataProviderForSectionID:")] ||
           [server respondsToSelector:NSSelectorFromString(@"_clearBulletinIDs:forSectionID:shouldSync:")];
}

static NSUInteger NFNotificationRecordSignalScore(NFNotificationRecord *record) {
    if (!record) {
        return 0;
    }

    NSUInteger score = 0;
    if (record.bundleIdentifier.length > 0) {
        score += 1;
    }
    if (record.sectionID.length > 0) {
        score += 1;
    }
    if (record.bulletinID.length > 0) {
        score += 1;
    }
    if (record.recordID.length > 0) {
        score += 1;
    }
    if (record.publisherBulletinID.length > 0) {
        score += 1;
    }
    if (record.title.length > 0) {
        score += 2;
    }
    if (record.subtitle.length > 0) {
        score += 1;
    }
    if (record.header.length > 0) {
        score += 1;
    }
    if (record.body.length > 0) {
        score += 2;
    }
    if (record.message.length > 0) {
        score += 2;
    }
    if (record.joinedText.length > 0) {
        score += 3;
    }

    return score;
}

static NFNotificationRecord *NFBestRecordFromNotificationObject(id notificationObject,
                                                                id fallbackSectionIdentifier) {
    NFNotificationRecord *requestRecord = [NFNotificationRecord recordFromNotificationRequest:notificationObject];
    NFBackfillRecordSectionIdentifier(requestRecord, fallbackSectionIdentifier);

    NFNotificationRecord *bulletinRecord = [NFNotificationRecord recordFromBulletin:notificationObject];
    NFBackfillRecordSectionIdentifier(bulletinRecord, fallbackSectionIdentifier);

    if (NFNotificationRecordSignalScore(bulletinRecord) > NFNotificationRecordSignalScore(requestRecord)) {
        return bulletinRecord;
    }

    return requestRecord;
}

static id NFExtractNotificationObjectFromUpdate(id updateOrTransaction) {
    if (!updateOrTransaction) {
        return nil;
    }

    NSArray<NSString *> *selectorNames = @[
        @"bulletin",
        @"bulletinUpdate",
        @"bulletinRequest",
        @"request",
        @"notificationRequest",
        @"update",
        @"modifiedBulletin",
        @"newBulletin"
    ];
    NSMutableArray *pendingObjects = [NSMutableArray arrayWithObject:updateOrTransaction];
    NSMutableSet<NSString *> *visitedObjects = [NSMutableSet set];
    id bestObject = nil;
    NSUInteger bestScore = 0;

    while (pendingObjects.count > 0) {
        id candidate = pendingObjects.firstObject;
        [pendingObjects removeObjectAtIndex:0];

        NSString *candidateKey = [NSString stringWithFormat:@"%p", candidate];
        if ([visitedObjects containsObject:candidateKey]) {
            continue;
        }
        [visitedObjects addObject:candidateKey];

        NSUInteger candidateScore = NFNotificationRecordSignalScore(NFBestRecordFromNotificationObject(candidate, nil));
        if (candidateScore > bestScore) {
            bestScore = candidateScore;
            bestObject = candidate;
        }

        for (NSString *selectorName in selectorNames) {
            id nestedObject = NFCallObject(candidate, selectorName);
            if (nestedObject) {
                [pendingObjects addObject:nestedObject];
            }
        }
    }

    return bestObject ?: updateOrTransaction;
}

static void NFHandleBlockedNotificationObject(id server,
                                              id notificationObject,
                                              NFNotificationRecord *record,
                                              NFMatchResult *result) {
    if (!result.shouldBlock) {
        return;
    }

    if (NFShouldDeleteFilteredNotifications() && NFCanDeleteFilteredNotificationWithServer(server)) {
        if (!NFShouldPerformBlockedAction(@"delete", record, result)) {
            return;
        }
        NFAttemptDeleteFilteredBulletin(server, notificationObject, record, result);
        return;
    }

    if (!NFShouldPerformBlockedAction(@"log", record, result)) {
        return;
    }
    NFAppendBlockedLog(record, result);
}

static BOOL NFShouldBlockNotificationObject(id server,
                                            id notificationObject,
                                            id fallbackSectionIdentifier) {
    if (!notificationObject) {
        return NO;
    }

    NFNotificationRecord *record = NFBestRecordFromNotificationObject(notificationObject,
                                                                      fallbackSectionIdentifier);
    NFMatchResult *result = NFEvaluateRecord(record);
    if (!result.shouldBlock) {
        return NO;
    }

    NFHandleBlockedNotificationObject(server, notificationObject, record, result);
    return YES;
}

static BOOL NFShouldBlockUpdateLikeObject(id server,
                                          id updateOrTransaction,
                                          id fallbackSectionIdentifier) {
    id notificationObject = NFExtractNotificationObjectFromUpdate(updateOrTransaction);
    id resolvedSectionIdentifier = fallbackSectionIdentifier ?: NFSectionIdentifierCandidate(updateOrTransaction);
    return NFShouldBlockNotificationObject(server, notificationObject, resolvedSectionIdentifier);
}

static void NFInvokeBooleanCompletion(id completion) {
    if (!completion) {
        return;
    }

    ((NFBooleanCompletionBlock)completion)(NO);
}

static void NFInvokeBooleanErrorCompletion(id completion) {
    if (!completion) {
        return;
    }

    ((NFBooleanErrorCompletionBlock)completion)(NO, nil);
}

static id NFFilterBulletinRequests(id server,
                                   id sectionIdentifier,
                                   id bulletinRequests,
                                   BOOL *didFilterAnyRequests) {
    NSArray *requestArray = nil;
    BOOL returnsSet = NO;

    if ([bulletinRequests isKindOfClass:[NSArray class]]) {
        requestArray = bulletinRequests;
    } else if ([bulletinRequests isKindOfClass:[NSSet class]]) {
        requestArray = [(NSSet *)bulletinRequests allObjects];
        returnsSet = YES;
    } else {
        if (didFilterAnyRequests) {
            *didFilterAnyRequests = NO;
        }
        return bulletinRequests;
    }

    NSMutableArray *allowedRequests = [NSMutableArray arrayWithCapacity:requestArray.count];
    BOOL didFilter = NO;

    for (id request in requestArray) {
        NFNotificationRecord *record = [NFNotificationRecord recordFromNotificationRequest:request];
        NFBackfillRecordSectionIdentifier(record, sectionIdentifier);

        NFMatchResult *result = NFEvaluateRecord(record);
        if (!result.shouldBlock) {
            [allowedRequests addObject:request];
            continue;
        }

        didFilter = YES;
        NFHandleBlockedNotificationObject(server, request, record, result);
    }

    if (didFilterAnyRequests) {
        *didFilterAnyRequests = didFilter;
    }
    if (!didFilter) {
        return bulletinRequests;
    }

    if (returnsSet) {
        return [NSSet setWithArray:allowedRequests];
    }

    return [allowedRequests copy];
}

static dispatch_queue_t NFBBServerQueue(void) {
    static dispatch_queue_t cachedQueue = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __unsafe_unretained dispatch_queue_t *queuePointer = (__unsafe_unretained dispatch_queue_t *)dlsym(RTLD_DEFAULT, "__BBServerQueue");
        if (queuePointer) {
            cachedQueue = *queuePointer;
            dispatch_queue_set_specific(cachedQueue,
                                        NFBBServerQueueSpecificKey,
                                        NFBBServerQueueSpecificKey,
                                        NULL);
        }
    });
    return cachedQueue;
}

static void NFPerformSyncOrInlineOnBBServerQueue(dispatch_block_t block) {
    dispatch_queue_t queue = NFBBServerQueue();
    if (!queue) {
        block();
        return;
    }

    if (dispatch_get_specific(NFBBServerQueueSpecificKey) == NFBBServerQueueSpecificKey) {
        block();
        return;
    }

    dispatch_sync(queue, block);
}

static void NFAttemptDeleteFilteredBulletin(id server,
                                            id bulletin,
                                            NFNotificationRecord *record,
                                            NFMatchResult *result) {
    NSMutableDictionary *baseLogEntry = NFBuildBlockedLogEntry(record, result);
    if (!baseLogEntry) {
        return;
    }

    baseLogEntry[NFLogDeleteRequestedKey] = @YES;

    NSString *sectionID = record.sectionID.length > 0 ? record.sectionID : NFCallObject(bulletin, @"sectionID");
    if (sectionID.length == 0) {
        sectionID = NFCallObject(bulletin, @"section");
    }
    NSString *bulletinID = record.bulletinID.length > 0 ? record.bulletinID : NFCallObject(bulletin, @"bulletinID");
    NSString *recordID = record.recordID.length > 0 ? record.recordID : NFCallObject(bulletin, @"recordID");
    NSString *publisherBulletinID = record.publisherBulletinID.length > 0 ? record.publisherBulletinID : NFCallObject(bulletin, @"publisherBulletinID");

    if (sectionID.length > 0) {
        baseLogEntry[NFLogSectionIDKey] = sectionID;
    }
    if (bulletinID.length > 0) {
        baseLogEntry[NFLogBulletinIDKey] = bulletinID;
    }
    if (recordID.length > 0) {
        baseLogEntry[NFLogRecordIDKey] = recordID;
    }
    if (publisherBulletinID.length > 0) {
        baseLogEntry[NFLogPublisherBulletinIDKey] = publisherBulletinID;
    }

    if (!server) {
        baseLogEntry[NFLogDeleteStatusKey] = @"skipped";
        baseLogEntry[NFLogDeleteMethodKey] = @"invalid-input";
        [NFLogStore appendBlockedEntry:baseLogEntry];
        return;
    }

    NFPerformSyncOrInlineOnBBServerQueue(^{
        BOOL clearedExistingEntries = NO;
        NSMutableArray<NSString *> *methods = [NSMutableArray array];

        SEL clearSelector = NSSelectorFromString(@"_clearBulletinIDs:forSectionID:shouldSync:");
        if (sectionID.length > 0 &&
            bulletinID.length > 0 &&
            [server respondsToSelector:clearSelector]) {
            ((void (*)(id, SEL, id, id, BOOL))objc_msgSend)(server,
                                                            clearSelector,
                                                            @[bulletinID],
                                                            sectionID,
                                                            YES);
            clearedExistingEntries = YES;
            [methods addObject:@"clearBulletinIDs"];
        }

        id dataProvider = nil;
        SEL dataProviderSelector = NSSelectorFromString(@"dataProviderForSectionID:");
        if (sectionID.length > 0 && [server respondsToSelector:dataProviderSelector]) {
            dataProvider = ((id (*)(id, SEL, id))objc_msgSend)(server, dataProviderSelector, sectionID);
        }

        if (dataProvider) {
            static NFWithdrawByPublisherBulletinIDFunction withdrawByPublisherBulletinID = NULL;
            static NFWithdrawByRecordIDFunction withdrawByRecordID = NULL;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                withdrawByPublisherBulletinID = (NFWithdrawByPublisherBulletinIDFunction)dlsym(RTLD_DEFAULT, "BBDataProviderWithdrawBulletinWithPublisherBulletinID");
                withdrawByRecordID = (NFWithdrawByRecordIDFunction)dlsym(RTLD_DEFAULT, "BBDataProviderWithdrawBulletinsWithRecordID");
            });

            if (publisherBulletinID.length > 0 && withdrawByPublisherBulletinID) {
                withdrawByPublisherBulletinID(dataProvider, publisherBulletinID);
                clearedExistingEntries = YES;
                [methods addObject:@"withdrawPublisher"];
            }
            if (recordID.length > 0 && withdrawByRecordID) {
                withdrawByRecordID(dataProvider, recordID);
                clearedExistingEntries = YES;
                [methods addObject:@"withdrawRecord"];
            }
        }

        NSMutableDictionary *completedLogEntry = [baseLogEntry mutableCopy];
        completedLogEntry[NFLogDeleteStatusKey] = clearedExistingEntries ? @"success" : @"failed";
        completedLogEntry[NFLogDeleteMethodKey] = methods.count > 0 ? [methods componentsJoinedByString:@","] : @"none";
        [NFLogStore appendBlockedEntry:completedLogEntry];
    });
}

%group NFDispatcherHooks

%hook NCNotificationDispatcher

- (void)postNotificationWithRequest:(id)request {
    NFNotificationRecord *record = [NFNotificationRecord recordFromNotificationRequest:request];
    NFMatchResult *result = NFEvaluateRecord(record);
    if (!result.shouldBlock) {
        %orig;
        return;
    }

    if (NFShouldDeleteFilteredNotifications()) {
        // Deletion mode lets the request reach BBServer so we can block at the
        // bulletin layer while still clearing prior Notification Center entries by ID.
        %orig;
        return;
    }

    NFAppendBlockedLog(record, result);
}

%end

%end

%group NFBulletinHooks

%hook BBServer

- (void)publishBulletinRequest:(id)request destinations:(unsigned long long)destinations {
    NFNotificationRecord *record = [NFNotificationRecord recordFromNotificationRequest:request];
    NFMatchResult *result = NFEvaluateRecord(record);
    if (!result.shouldBlock) {
        %orig;
        return;
    }

    NFHandleBlockedNotificationObject(self, request, record, result);
}

- (void)_publishBulletinRequest:(id)request forSectionID:(id)sectionIdentifier forDestinations:(unsigned long long)destinations {
    if (!NFShouldBlockNotificationObject(self, request, sectionIdentifier)) {
        %orig;
    }
}

- (void)updateSection:(id)sectionIdentifier inFeed:(unsigned long long)feed withBulletinRequests:(id)bulletinRequests {
    BOOL didFilterRequests = NO;
    id allowedRequests = NFFilterBulletinRequests(self,
                                                  sectionIdentifier,
                                                  bulletinRequests,
                                                  &didFilterRequests);
    if (!didFilterRequests) {
        %orig;
        return;
    }

    if ([allowedRequests respondsToSelector:@selector(count)] &&
        ((NSUInteger)[allowedRequests count]) > 0) {
        %orig(sectionIdentifier, feed, allowedRequests);
    }
}

- (void)publishBulletin:(id)bulletin destinations:(unsigned long long)destinations {
    NFNotificationRecord *record = [NFNotificationRecord recordFromBulletin:bulletin];
    NFMatchResult *result = NFEvaluateRecord(record);
    if (!result.shouldBlock) {
        %orig;
        return;
    }

    NFHandleBlockedNotificationObject(self, bulletin, record, result);
}

- (void)_modifyBulletin:(id)bulletin {
    if (!NFShouldBlockNotificationObject(self, bulletin, nil)) {
        %orig;
    }
}

- (void)_addBulletin:(id)bulletin {
    if (!NFShouldBlockNotificationObject(self, bulletin, nil)) {
        %orig;
    }
}

- (void)_sendAddBulletin:(id)bulletin toFeeds:(unsigned long long)feeds {
    if (!NFShouldBlockNotificationObject(self, bulletin, nil)) {
        %orig;
    }
}

- (void)_sendModifyBulletin:(id)bulletin toFeeds:(unsigned long long)feeds {
    if (!NFShouldBlockNotificationObject(self, bulletin, nil)) {
        %orig;
    }
}

- (void)_sendBulletinUpdate:(id)update {
    if (!NFShouldBlockUpdateLikeObject(self, update, nil)) {
        %orig;
    }
}

- (void)publishBulletin:(id)bulletin destinations:(unsigned long long)destinations alwaysToLockScreen:(BOOL)alwaysToLockScreen {
    NFNotificationRecord *record = [NFNotificationRecord recordFromBulletin:bulletin];
    NFMatchResult *result = NFEvaluateRecord(record);
    if (!result.shouldBlock) {
        %orig;
        return;
    }

    NFHandleBlockedNotificationObject(self, bulletin, record, result);
}

%end

%end

%group NFObserverHooks

%hook BBObserver

- (void)updateBulletin:(id)updateTransaction withReply:(id)reply {
    if (NFShouldBlockUpdateLikeObject(nil, updateTransaction, nil)) {
        NFInvokeBooleanCompletion(reply);
        return;
    }

    %orig;
}

- (void)_queue_updateAddBulletin:(id)update withReply:(id)reply {
    if (NFShouldBlockUpdateLikeObject(nil, update, nil)) {
        NFInvokeBooleanCompletion(reply);
        return;
    }

    %orig;
}

- (void)_queue_updateModifyBulletin:(id)update withReply:(id)reply {
    if (NFShouldBlockUpdateLikeObject(nil, update, nil)) {
        NFInvokeBooleanCompletion(reply);
        return;
    }

    %orig;
}

%end

%end

%group NFObserverServerProxyHooks

%hook BBObserverServerProxy

- (void)updateBulletin:(id)updateTransaction withHandler:(id)handler {
    if (NFShouldBlockUpdateLikeObject(nil, updateTransaction, nil)) {
        NFInvokeBooleanCompletion(handler);
        return;
    }

    %orig;
}

%end

%end

%group NFObserverClientProxyHooks

%hook BBObserverClientProxy

- (void)updateBulletin:(id)updateTransaction withHandler:(id)handler {
    if (NFShouldBlockUpdateLikeObject(nil, updateTransaction, nil)) {
        NFInvokeBooleanErrorCompletion(handler);
        return;
    }

    %orig;
}

%end

%end

%group NFDataProviderProxyHooks

%hook BBDataProviderProxy

- (void)addBulletin:(id)bulletin forDestinations:(unsigned long long)destinations {
    if (!NFShouldBlockNotificationObject(nil, bulletin, nil)) {
        %orig;
    }
}

- (void)modifyBulletin:(id)bulletin {
    if (!NFShouldBlockNotificationObject(nil, bulletin, nil)) {
        %orig;
    }
}

%end

%end

%group NFRemoteDataProviderHooks

%hook BBRemoteDataProvider

- (void)addBulletin:(id)bulletin forDestinations:(unsigned long long)destinations {
    if (!NFShouldBlockNotificationObject(nil, bulletin, nil)) {
        %orig;
    }
}

- (void)modifyBulletin:(id)bulletin {
    if (!NFShouldBlockNotificationObject(nil, bulletin, nil)) {
        %orig;
    }
}

%end

%end

%ctor {
    @autoreleasepool {
        NFPreferencesQueue = dispatch_queue_create("com.tune.notificationfilter.preferences", DISPATCH_QUEUE_SERIAL);
        NFBlockedActionQueue = dispatch_queue_create("com.tune.notificationfilter.blocked-actions", DISPATCH_QUEUE_SERIAL);
        NFBlockedActionTimestamps = [NSMutableDictionary dictionary];
        NFBlockedIdentityQueue = dispatch_queue_create("com.tune.notificationfilter.blocked-identities", DISPATCH_QUEUE_SERIAL);
        NFBlockedIdentityCache = [NSMutableDictionary dictionary];
        NFReloadPreferences();

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        NFPreferencesChangedCallback,
                                        (CFStringRef)NFPreferencesChangedDarwinNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        if (objc_getClass("NCNotificationDispatcher")) {
            %init(NFDispatcherHooks);
        }

        if (objc_getClass("BBServer")) {
            %init(NFBulletinHooks);
        }
        if (objc_getClass("BBObserver")) {
            %init(NFObserverHooks);
        }
        if (objc_getClass("BBObserverServerProxy")) {
            %init(NFObserverServerProxyHooks);
        }
        if (objc_getClass("BBObserverClientProxy")) {
            %init(NFObserverClientProxyHooks);
        }
        if (objc_getClass("BBDataProviderProxy")) {
            %init(NFDataProviderProxyHooks);
        }
        if (objc_getClass("BBRemoteDataProvider")) {
            %init(NFRemoteDataProviderHooks);
        }
    }
}
