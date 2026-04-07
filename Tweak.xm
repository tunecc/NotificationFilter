#import <Foundation/Foundation.h>
#import <objc/message.h>

static id STBCallObject(id obj, SEL selector) {
    if (!obj || !selector || ![obj respondsToSelector:selector]) {
        return nil;
    }

    return ((id (*)(id, SEL))objc_msgSend)(obj, selector);
}

static NSString *STBStringValue(id value) {
    if (!value) {
        return nil;
    }

    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }

    if ([value respondsToSelector:@selector(stringValue)]) {
        id stringValue = ((id (*)(id, SEL))objc_msgSend)(value, @selector(stringValue));
        if ([stringValue isKindOfClass:[NSString class]]) {
            return stringValue;
        }
    }

    return nil;
}

static NSString *STBFirstString(id obj, NSArray<NSString *> *selectorNames) {
    for (NSString *selectorName in selectorNames) {
        NSString *value = STBStringValue(STBCallObject(obj, NSSelectorFromString(selectorName)));
        if (value.length > 0) {
            return value;
        }
    }

    return nil;
}

static BOOL STBShouldBlockNotification(id request) {
    NSString *sectionIdentifier = STBStringValue(STBCallObject(request, @selector(sectionIdentifier)));
    if (![sectionIdentifier isEqualToString:@"com.apple.shortcuts"]) {
        return NO;
    }

    id content = STBCallObject(request, @selector(content));
    if (!content) {
        return NO;
    }

    // 标题和正文在不同系统版本里字段名可能不同，这里只做有限兼容。
    NSString *title = STBFirstString(content, @[@"title", @"header"]);
    if (title.length == 0) {
        NSString *messageAsTitle = STBFirstString(content, @[@"message"]);
        if ([messageAsTitle isEqualToString:@"Automation failed"]) {
            title = messageAsTitle;
        }
    }

    NSString *body = STBFirstString(content, @[@"body", @"message", @"subtitle"]);

    return [title isEqualToString:@"Automation failed"]
        && [body containsString:@"Remote execution timed out"];
}

%hook NCNotificationDispatcher

- (void)postNotificationWithRequest:(id)request {
    if (STBShouldBlockNotification(request)) {
        return;
    }

    %orig;
}

%end
