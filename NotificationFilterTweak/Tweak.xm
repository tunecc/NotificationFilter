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
typedef void (*NFWithdrawByRecordIDFunction)(id dataProvider, NSString *recordID);
typedef void (*NFWithdrawByPublisherBulletinIDFunction)(id dataProvider, NSString *publisherBulletinID);

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

static NFMatchResult *NFEvaluateRecord(NFNotificationRecord *record) {
    return [NFRuleEngine evaluateRecord:record preferences:NFCopyPreferencesSnapshot()];
}

static id NFCallObject(id obj, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!obj || !selector || ![obj respondsToSelector:selector]) {
        return nil;
    }

    return ((id (*)(id, SEL))objc_msgSend)(obj, selector);
}

static dispatch_queue_t NFBBServerQueue(void) {
    static dispatch_queue_t cachedQueue = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __unsafe_unretained dispatch_queue_t *queuePointer = (__unsafe_unretained dispatch_queue_t *)dlsym(RTLD_DEFAULT, "__BBServerQueue");
        if (queuePointer) {
            cachedQueue = *queuePointer;
        }
    });
    return cachedQueue;
}

static void NFDispatchAsyncOnBBServerQueue(dispatch_block_t block) {
    dispatch_queue_t queue = NFBBServerQueue();
    if (!queue) {
        block();
        return;
    }

    dispatch_async(queue, block);
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

    if (!server || !bulletin) {
        baseLogEntry[NFLogDeleteStatusKey] = @"skipped";
        baseLogEntry[NFLogDeleteMethodKey] = @"invalid-input";
        [NFLogStore appendBlockedEntry:baseLogEntry];
        return;
    }

    NFDispatchAsyncOnBBServerQueue(^{
        BOOL clearedFromNotificationCenter = NO;
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
            clearedFromNotificationCenter = YES;
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
                [methods addObject:@"withdrawPublisher"];
            } else if (recordID.length > 0 && withdrawByRecordID) {
                withdrawByRecordID(dataProvider, recordID);
                [methods addObject:@"withdrawRecord"];
            }
        }

        if (!clearedFromNotificationCenter) {
            SEL removeSelector = NSSelectorFromString(@"_removeBulletin:shouldSync:");
            if ([server respondsToSelector:removeSelector]) {
                ((void (*)(id, SEL, id, BOOL))objc_msgSend)(server, removeSelector, bulletin, YES);
                clearedFromNotificationCenter = YES;
                [methods addObject:@"removeBulletin"];
            } else {
                SEL removeRescheduleSelector = NSSelectorFromString(@"_removeBulletin:rescheduleTimerIfAffected:shouldSync:");
                if ([server respondsToSelector:removeRescheduleSelector]) {
                    ((void (*)(id, SEL, id, BOOL, BOOL))objc_msgSend)(server,
                                                                     removeRescheduleSelector,
                                                                     bulletin,
                                                                     YES,
                                                                     YES);
                    clearedFromNotificationCenter = YES;
                    [methods addObject:@"removeBulletinReschedule"];
                }
            }
        }

        NSMutableDictionary *completedLogEntry = [baseLogEntry mutableCopy];
        completedLogEntry[NFLogDeleteStatusKey] = clearedFromNotificationCenter ? @"success" : @"failed";
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
        // Deletion mode must allow the bulletin to flow into BBServer so the
        // server path can persist it first and then withdraw it.
        %orig;
        return;
    }

    NFAppendBlockedLog(record, result);
}

%end

%end

%group NFBulletinHooks

%hook BBServer

- (void)publishBulletin:(id)bulletin destinations:(unsigned long long)destinations {
    NFNotificationRecord *record = [NFNotificationRecord recordFromBulletin:bulletin];
    NFMatchResult *result = NFEvaluateRecord(record);
    if (!result.shouldBlock) {
        %orig;
        return;
    }

    if (NFShouldDeleteFilteredNotifications()) {
        %orig;
        NFAttemptDeleteFilteredBulletin(self, bulletin, record, result);
        return;
    }

    NFAppendBlockedLog(record, result);
}

- (void)publishBulletin:(id)bulletin destinations:(unsigned long long)destinations alwaysToLockScreen:(BOOL)alwaysToLockScreen {
    NFNotificationRecord *record = [NFNotificationRecord recordFromBulletin:bulletin];
    NFMatchResult *result = NFEvaluateRecord(record);
    if (!result.shouldBlock) {
        %orig;
        return;
    }

    if (NFShouldDeleteFilteredNotifications()) {
        %orig;
        NFAttemptDeleteFilteredBulletin(self, bulletin, record, result);
        return;
    }

    NFAppendBlockedLog(record, result);
}

%end

%end

%ctor {
    @autoreleasepool {
        NFPreferencesQueue = dispatch_queue_create("com.tune.notificationfilter.preferences", DISPATCH_QUEUE_SERIAL);
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
    }
}
