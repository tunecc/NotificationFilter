#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static id NFCallObject(id obj, SEL selector) {
    if (!obj || !selector || ![obj respondsToSelector:selector]) {
        return nil;
    }

    return ((id (*)(id, SEL))objc_msgSend)(obj, selector);
}

static NSString *NFNormalizedString(NSString *value) {
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *NFStringValue(id value) {
    if (!value) {
        return nil;
    }

    if ([value isKindOfClass:[NSString class]]) {
        return NFNormalizedString(value);
    }

    if ([value respondsToSelector:@selector(stringValue)]) {
        id stringValue = ((id (*)(id, SEL))objc_msgSend)(value, @selector(stringValue));
        if ([stringValue isKindOfClass:[NSString class]]) {
            return NFNormalizedString(stringValue);
        }
    }

    return nil;
}

static NSArray<NSString *> *NFCollectStrings(id obj, NSArray<NSString *> *selectorNames) {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    for (NSString *selectorName in selectorNames) {
        NSString *value = NFStringValue(NFCallObject(obj, NSSelectorFromString(selectorName)));
        if (value.length > 0 && ![seen containsObject:value]) {
            [seen addObject:value];
            [values addObject:value];
        }
    }

    return values;
}

static NSString *NFSectionIdentifier(id obj) {
    NSArray<NSString *> *sections = NFCollectStrings(obj, @[@"sectionIdentifier", @"sectionID"]);
    return sections.firstObject;
}

static NSArray<NSString *> *NFNotificationTexts(id obj) {
    return NFCollectStrings(obj, @[@"title", @"header", @"body", @"message", @"subtitle"]);
}

static BOOL NFShouldBlockTexts(NSArray<NSString *> *texts) {
    for (NSString *text in texts) {
        if ([text caseInsensitiveCompare:@"Automation failed"] == NSOrderedSame) {
            return YES;
        }
    }

    return NO;
}

static BOOL NFShouldBlockRequest(id request) {
    if (![[NFSectionIdentifier(request) lowercaseString] isEqualToString:@"com.apple.shortcuts"]) {
        return NO;
    }

    NSMutableArray<NSString *> *texts = [NSMutableArray array];

    id content = NFCallObject(request, @selector(content));
    if (content) {
        [texts addObjectsFromArray:NFNotificationTexts(content)];
    }

    [texts addObjectsFromArray:NFNotificationTexts(request)];

    return NFShouldBlockTexts(texts);
}

static BOOL NFShouldBlockBulletin(id bulletin) {
    if (![[NFSectionIdentifier(bulletin) lowercaseString] isEqualToString:@"com.apple.shortcuts"]) {
        return NO;
    }

    return NFShouldBlockTexts(NFNotificationTexts(bulletin));
}

%group NFDispatcherHooks

%hook NCNotificationDispatcher

- (void)postNotificationWithRequest:(id)request {
    if (NFShouldBlockRequest(request)) {
        return;
    }

    %orig;
}

%end

%end

%group NFBulletinHooks

%hook BBServer

- (void)publishBulletin:(id)bulletin destinations:(unsigned long long)destinations {
    if (NFShouldBlockBulletin(bulletin)) {
        return;
    }

    %orig;
}

- (void)publishBulletin:(id)bulletin destinations:(unsigned long long)destinations alwaysToLockScreen:(BOOL)alwaysToLockScreen {
    if (NFShouldBlockBulletin(bulletin)) {
        return;
    }

    %orig;
}

%end

%end

%ctor {
    if (objc_getClass("NCNotificationDispatcher")) {
        %init(NFDispatcherHooks);
    }

    if (objc_getClass("BBServer")) {
        %init(NFBulletinHooks);
    }
}
