#import "NFPLogDetailController.h"
#import "NFPLocalization.h"
#import "../Shared/NFPreferences.h"

@interface NFPLogDetailController ()

@property (nonatomic, copy) NSDictionary *entry;
@property (nonatomic, copy) NSString *displayName;

@end

@implementation NFPLogDetailController

- (instancetype)initWithEntry:(NSDictionary *)entry displayName:(NSString *)displayName {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _entry = [entry copy];
        _displayName = [displayName copy];
        self.title = NFPLocalizedString(@"LOG_DETAIL_TITLE");
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    UITextView *textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    textView.editable = NO;
    textView.alwaysBounceVertical = YES;
    textView.font = [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightRegular];
    textView.textContainerInset = UIEdgeInsetsMake(16.0, 16.0, 16.0, 16.0);
    textView.text = [self formattedText];
    [self.view addSubview:textView];
}

- (NSString *)formattedText {
    NSString *unknown = NFPLocalizedString(@"COMMON_UNKNOWN");
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[self.entry[NFLogTimestampKey] doubleValue]];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterMediumStyle;

    NSString *bundleIdentifier = [self.entry[NFLogBundleIdentifierKey] isKindOfClass:[NSString class]] ? self.entry[NFLogBundleIdentifierKey] : nil;
    NSString *matchedScope = [self.entry[NFLogMatchedScopeKey] isKindOfClass:[NSString class]] ? self.entry[NFLogMatchedScopeKey] : nil;
    NSString *matchedMode = [self.entry[NFLogMatchedModeKey] isKindOfClass:[NSString class]] ? self.entry[NFLogMatchedModeKey] : nil;
    NSString *matchedPattern = [self.entry[NFLogMatchedPatternKey] isKindOfClass:[NSString class]] ? self.entry[NFLogMatchedPatternKey] : nil;
    NSString *deleteStatus = [self.entry[NFLogDeleteStatusKey] isKindOfClass:[NSString class]] ? self.entry[NFLogDeleteStatusKey] : nil;
    NSString *deleteMethod = [self.entry[NFLogDeleteMethodKey] isKindOfClass:[NSString class]] ? self.entry[NFLogDeleteMethodKey] : nil;

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:NFPLocalizedString(@"LOG_DETAIL_APP_FORMAT"), self.displayName ?: unknown]];
    [lines addObject:[NSString stringWithFormat:NFPLocalizedString(@"LOG_DETAIL_BUNDLE_ID_FORMAT"), bundleIdentifier ?: unknown]];
    [lines addObject:[NSString stringWithFormat:NFPLocalizedString(@"LOG_DETAIL_TIME_FORMAT"), [formatter stringFromDate:date]]];
    [lines addObject:[NSString stringWithFormat:NFPLocalizedString(@"LOG_DETAIL_SCOPE_FORMAT"), matchedScope.length > 0 ? NFPLocalizedScopeName(matchedScope) : unknown]];
    [lines addObject:[NSString stringWithFormat:NFPLocalizedString(@"LOG_DETAIL_MODE_FORMAT"), matchedMode.length > 0 ? NFPLocalizedMatchModeName(matchedMode) : unknown]];
    [lines addObject:[NSString stringWithFormat:NFPLocalizedString(@"LOG_DETAIL_PATTERN_FORMAT"), matchedPattern ?: unknown]];
    if ([self.entry[NFLogDeleteRequestedKey] boolValue]) {
        [lines addObject:[NSString stringWithFormat:NFPLocalizedString(@"LOG_DETAIL_DELETE_STATUS_FORMAT"), deleteStatus.length > 0 ? NFPLocalizedDeleteStatusName(deleteStatus) : unknown]];
        [lines addObject:[NSString stringWithFormat:NFPLocalizedString(@"LOG_DETAIL_DELETE_METHOD_FORMAT"), deleteMethod.length > 0 ? NFPLocalizedDeleteMethodSummary(deleteMethod) : unknown]];
    }
    if ([self.entry[NFLogSectionIDKey] length] > 0) {
        [lines addObject:[NSString stringWithFormat:NFPLocalizedString(@"LOG_DETAIL_SECTION_ID_FORMAT"), self.entry[NFLogSectionIDKey]]];
    }
    if ([self.entry[NFLogBulletinIDKey] length] > 0) {
        [lines addObject:[NSString stringWithFormat:NFPLocalizedString(@"LOG_DETAIL_BULLETIN_ID_FORMAT"), self.entry[NFLogBulletinIDKey]]];
    }
    if ([self.entry[NFLogRecordIDKey] length] > 0) {
        [lines addObject:[NSString stringWithFormat:NFPLocalizedString(@"LOG_DETAIL_RECORD_ID_FORMAT"), self.entry[NFLogRecordIDKey]]];
    }
    if ([self.entry[NFLogPublisherBulletinIDKey] length] > 0) {
        [lines addObject:[NSString stringWithFormat:NFPLocalizedString(@"LOG_DETAIL_PUBLISHER_BULLETIN_ID_FORMAT"), self.entry[NFLogPublisherBulletinIDKey]]];
    }
    [lines addObject:@""];
    [lines addObject:[NSString stringWithFormat:NFPLocalizedString(@"LOG_DETAIL_NOTIFICATION_TITLE_FORMAT"), self.entry[NFLogTitleKey] ?: @""]];
    [lines addObject:[NSString stringWithFormat:NFPLocalizedString(@"LOG_DETAIL_NOTIFICATION_SUBTITLE_FORMAT"), self.entry[NFLogSubtitleKey] ?: @""]];
    [lines addObject:[NSString stringWithFormat:NFPLocalizedString(@"LOG_DETAIL_NOTIFICATION_HEADER_FORMAT"), self.entry[NFLogHeaderKey] ?: @""]];
    [lines addObject:[NSString stringWithFormat:NFPLocalizedString(@"LOG_DETAIL_NOTIFICATION_BODY_FORMAT"), self.entry[NFLogBodyKey] ?: @""]];
    [lines addObject:[NSString stringWithFormat:NFPLocalizedString(@"LOG_DETAIL_NOTIFICATION_MESSAGE_FORMAT"), self.entry[NFLogMessageKey] ?: @""]];
    [lines addObject:@""];
    [lines addObject:NFPLocalizedString(@"LOG_DETAIL_JOINED_TEXT_TITLE")];
    [lines addObject:self.entry[NFLogJoinedTextKey] ?: @""];

    return [lines componentsJoinedByString:@"\n"];
}

@end
