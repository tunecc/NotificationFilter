#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "NFNotificationRecord.h"
#import "NFRuleEngine.h"
#import "../Shared/NFPreferences.h"
#import "../Shared/NFLogStore.h"

static NSDictionary *NFCurrentPreferences = nil;
static dispatch_queue_t NFPreferencesQueue = nil;

static NSDictionary *NFCopyPreferencesSnapshot(void) {
    __block NSDictionary *snapshot = nil;
    dispatch_sync(NFPreferencesQueue, ^{
        snapshot = NFCurrentPreferences ?: [NFPreferences defaultPreferences];
    });
    return snapshot;
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

static void NFAppendBlockedLog(NFNotificationRecord *record, NFMatchResult *result) {
    if (!result.shouldBlock) {
        return;
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

    [NFLogStore appendBlockedEntry:logEntry];
}

static BOOL NFShouldBlockRecord(NFNotificationRecord *record) {
    NFMatchResult *result = [NFRuleEngine evaluateRecord:record preferences:NFCopyPreferencesSnapshot()];
    if (result.shouldBlock) {
        NFAppendBlockedLog(record, result);
        return YES;
    }

    return NO;
}

%group NFDispatcherHooks

%hook NCNotificationDispatcher

- (void)postNotificationWithRequest:(id)request {
    NFNotificationRecord *record = [NFNotificationRecord recordFromNotificationRequest:request];
    if (NFShouldBlockRecord(record)) {
        return;
    }

    %orig;
}

%end

%end

%group NFBulletinHooks

%hook BBServer

- (void)publishBulletin:(id)bulletin destinations:(unsigned long long)destinations {
    NFNotificationRecord *record = [NFNotificationRecord recordFromBulletin:bulletin];
    if (NFShouldBlockRecord(record)) {
        return;
    }

    %orig;
}

- (void)publishBulletin:(id)bulletin destinations:(unsigned long long)destinations alwaysToLockScreen:(BOOL)alwaysToLockScreen {
    NFNotificationRecord *record = [NFNotificationRecord recordFromBulletin:bulletin];
    if (NFShouldBlockRecord(record)) {
        return;
    }

    %orig;
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
