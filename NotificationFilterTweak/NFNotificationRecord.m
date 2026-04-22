#import "NFNotificationRecord.h"
#import "../Shared/NFPreferences.h"
#import <objc/message.h>

static id NFCallObject(id obj, SEL selector) {
    if (!obj || !selector || ![obj respondsToSelector:selector]) {
        return nil;
    }

    return ((id (*)(id, SEL))objc_msgSend)(obj, selector);
}

static NSString *NFNormalizedString(id value) {
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

static NSString *NFValueForSelectorName(id primaryObject, id fallbackObject, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    NSString *value = NFNormalizedString(NFCallObject(primaryObject, selector));
    if (value.length > 0) {
        return value;
    }

    return NFNormalizedString(NFCallObject(fallbackObject, selector));
}

static NSString *NFSectionIdentifier(id obj) {
    NSString *sectionIdentifier = NFValueForSelectorName(obj, nil, @"sectionIdentifier");
    if (sectionIdentifier.length > 0) {
        return sectionIdentifier;
    }

    return NFValueForSelectorName(obj, nil, @"sectionID");
}

static NSString *NFJoinedText(NSArray<NSString *> *values) {
    NSMutableArray<NSString *> *components = [NSMutableArray array];
    NSMutableSet<NSString *> *seenValues = [NSMutableSet set];

    for (NSString *value in values) {
        if (value.length == 0 || [seenValues containsObject:value]) {
            continue;
        }

        [seenValues addObject:value];
        [components addObject:value];
    }

    return [components componentsJoinedByString:@"\n"];
}

@implementation NFNotificationRecord

+ (instancetype)recordFromNotificationRequest:(id)request {
    id content = NFCallObject(request, @selector(content));

    NFNotificationRecord *record = [[self alloc] init];
    record.bundleIdentifier = NFSectionIdentifier(request);
    record.title = NFValueForSelectorName(content, request, @"title");
    record.subtitle = NFValueForSelectorName(content, request, @"subtitle");
    record.header = NFValueForSelectorName(content, request, @"header");
    record.body = NFValueForSelectorName(content, request, @"body");
    record.message = NFValueForSelectorName(content, request, @"message");
    record.messageText = NFJoinedText(@[
        record.body ?: @"",
        record.message ?: @""
    ]);
    record.joinedText = NFJoinedText(@[
        record.title ?: @"",
        record.subtitle ?: @"",
        record.header ?: @"",
        record.body ?: @"",
        record.message ?: @""
    ]);
    record.timestamp = [NSDate date];
    return record;
}

+ (instancetype)recordFromBulletin:(id)bulletin {
    NFNotificationRecord *record = [[self alloc] init];
    record.bundleIdentifier = NFSectionIdentifier(bulletin);
    record.sectionID = NFValueForSelectorName(bulletin, nil, @"sectionID");
    if (record.sectionID.length == 0) {
        record.sectionID = NFValueForSelectorName(bulletin, nil, @"section");
    }
    record.bulletinID = NFValueForSelectorName(bulletin, nil, @"bulletinID");
    record.recordID = NFValueForSelectorName(bulletin, nil, @"recordID");
    record.publisherBulletinID = NFValueForSelectorName(bulletin, nil, @"publisherBulletinID");
    record.title = NFValueForSelectorName(bulletin, nil, @"title");
    record.subtitle = NFValueForSelectorName(bulletin, nil, @"subtitle");
    record.header = NFValueForSelectorName(bulletin, nil, @"header");
    record.body = NFValueForSelectorName(bulletin, nil, @"body");
    record.message = NFValueForSelectorName(bulletin, nil, @"message");
    record.messageText = NFJoinedText(@[
        record.body ?: @"",
        record.message ?: @""
    ]);
    record.joinedText = NFJoinedText(@[
        record.title ?: @"",
        record.subtitle ?: @"",
        record.header ?: @"",
        record.body ?: @"",
        record.message ?: @""
    ]);
    record.timestamp = [NSDate date];
    return record;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    dictionary[NFLogTimestampKey] = @([self.timestamp timeIntervalSince1970]);
    dictionary[NFLogJoinedTextKey] = self.joinedText ?: @"";

    if (self.bundleIdentifier.length > 0) {
        dictionary[NFLogBundleIdentifierKey] = self.bundleIdentifier;
    }
    if (self.title.length > 0) {
        dictionary[NFLogTitleKey] = self.title;
    }
    if (self.subtitle.length > 0) {
        dictionary[NFLogSubtitleKey] = self.subtitle;
    }
    if (self.body.length > 0) {
        dictionary[NFLogBodyKey] = self.body;
    }
    if (self.header.length > 0) {
        dictionary[NFLogHeaderKey] = self.header;
    }
    if (self.message.length > 0) {
        dictionary[NFLogMessageKey] = self.message;
    }
    if (self.sectionID.length > 0) {
        dictionary[NFLogSectionIDKey] = self.sectionID;
    }
    if (self.bulletinID.length > 0) {
        dictionary[NFLogBulletinIDKey] = self.bulletinID;
    }
    if (self.recordID.length > 0) {
        dictionary[NFLogRecordIDKey] = self.recordID;
    }
    if (self.publisherBulletinID.length > 0) {
        dictionary[NFLogPublisherBulletinIDKey] = self.publisherBulletinID;
    }

    return dictionary;
}

@end
