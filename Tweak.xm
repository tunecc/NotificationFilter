#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static id STBCallObject(id obj, SEL selector) {
    if (!obj || !selector || ![obj respondsToSelector:selector]) {
        return nil;
    }

    return ((id (*)(id, SEL))objc_msgSend)(obj, selector);
}

static NSString *STBNormalizedString(NSString *value) {
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *STBStringValue(id value) {
    if (!value) {
        return nil;
    }

    if ([value isKindOfClass:[NSString class]]) {
        return STBNormalizedString(value);
    }

    if ([value respondsToSelector:@selector(stringValue)]) {
        id stringValue = ((id (*)(id, SEL))objc_msgSend)(value, @selector(stringValue));
        if ([stringValue isKindOfClass:[NSString class]]) {
            return STBNormalizedString(stringValue);
        }
    }

    return nil;
}

static NSArray<NSString *> *STBCollectStrings(id obj, NSArray<NSString *> *selectorNames) {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    for (NSString *selectorName in selectorNames) {
        NSString *value = STBStringValue(STBCallObject(obj, NSSelectorFromString(selectorName)));
        if (value.length > 0 && ![seen containsObject:value]) {
            [seen addObject:value];
            [values addObject:value];
        }
    }

    return values;
}

static NSString *STBSectionIdentifier(id obj) {
    NSArray<NSString *> *sections = STBCollectStrings(obj, @[@"sectionIdentifier", @"sectionID"]);
    return sections.firstObject;
}

static NSArray<NSString *> *STBNotificationTexts(id obj) {
    return STBCollectStrings(obj, @[@"title", @"header", @"body", @"message", @"subtitle"]);
}

static BOOL STBShouldBlockTexts(NSArray<NSString *> *texts) {
    for (NSString *text in texts) {
        if ([text caseInsensitiveCompare:@"Automation failed"] == NSOrderedSame) {
            return YES;
        }
    }

    return NO;
}

static BOOL STBShouldBlockRequest(id request) {
    if (![[STBSectionIdentifier(request) lowercaseString] isEqualToString:@"com.apple.shortcuts"]) {
        return NO;
    }

    NSMutableArray<NSString *> *texts = [NSMutableArray array];

    id content = STBCallObject(request, @selector(content));
    if (content) {
        [texts addObjectsFromArray:STBNotificationTexts(content)];
    }

    [texts addObjectsFromArray:STBNotificationTexts(request)];

    return STBShouldBlockTexts(texts);
}

static BOOL STBShouldBlockBulletin(id bulletin) {
    if (![[STBSectionIdentifier(bulletin) lowercaseString] isEqualToString:@"com.apple.shortcuts"]) {
        return NO;
    }

    return STBShouldBlockTexts(STBNotificationTexts(bulletin));
}

%group STBDispatcherHooks

%hook NCNotificationDispatcher

- (void)postNotificationWithRequest:(id)request {
    if (STBShouldBlockRequest(request)) {
        return;
    }

    %orig;
}

%end

%end

%group STBBulletinHooks

%hook BBServer

- (void)publishBulletin:(id)bulletin destinations:(unsigned long long)destinations {
    if (STBShouldBlockBulletin(bulletin)) {
        return;
    }

    %orig;
}

- (void)publishBulletin:(id)bulletin destinations:(unsigned long long)destinations alwaysToLockScreen:(BOOL)alwaysToLockScreen {
    if (STBShouldBlockBulletin(bulletin)) {
        return;
    }

    %orig;
}

%end

%end

%ctor {
    if (objc_getClass("NCNotificationDispatcher")) {
        %init(STBDispatcherHooks);
    }

    if (objc_getClass("BBServer")) {
        %init(STBBulletinHooks);
    }
}
