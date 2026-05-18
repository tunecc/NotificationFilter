#import "NFPNotificationRuleScannerController.h"
#import "../Shared/NFPreferences.h"
#import "NFPAppInfoProvider.h"
#import "NFPNotificationHistoryClient.h"
#import "NFPLocalization.h"
#import "NFPNotificationRuleTokenPickerController.h"

@interface NFPNotificationRuleScannerController ()

@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, assign) NFPRuleEditorKind initialRuleKind;
@property (nonatomic, weak, nullable) UIViewController *returnViewController;
@property (nonatomic, copy) NFPNotificationRuleScannerCommitHandler commitHandler;
@property (nonatomic, copy) NSArray<NSDictionary *> *entries;
@property (nonatomic, copy, nullable) NSString *historySource;

@end

@implementation NFPNotificationRuleScannerController

static NSString *NFPScannerPreviewText(NSDictionary *entry) {
    NSArray<NSString *> *candidates = @[
        [entry[NFLogMessageKey] isKindOfClass:[NSString class]] ? entry[NFLogMessageKey] : @"",
        [entry[NFLogBodyKey] isKindOfClass:[NSString class]] ? entry[NFLogBodyKey] : @"",
        [entry[NFLogTitleKey] isKindOfClass:[NSString class]] ? entry[NFLogTitleKey] : @"",
        [entry[NFLogSubtitleKey] isKindOfClass:[NSString class]] ? entry[NFLogSubtitleKey] : @"",
        [entry[NFLogHeaderKey] isKindOfClass:[NSString class]] ? entry[NFLogHeaderKey] : @"",
        [entry[NFLogJoinedTextKey] isKindOfClass:[NSString class]] ? entry[NFLogJoinedTextKey] : @""
    ];

    for (NSString *candidate in candidates) {
        NSString *trimmed = [candidate stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            continue;
        }

        NSMutableString *preview = [[trimmed stringByReplacingOccurrencesOfString:@"\n" withString:@"  "] mutableCopy];
        if (preview.length > 100) {
            return [[preview substringToIndex:100] stringByAppendingString:@"…"];
        }
        return preview;
    }

    return @"";
}

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
                             displayName:(NSString *)displayName
                         initialRuleKind:(NFPRuleEditorKind)initialRuleKind
                    returnViewController:(UIViewController *)returnViewController
                           commitHandler:(NFPNotificationRuleScannerCommitHandler)commitHandler {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _bundleIdentifier = [bundleIdentifier copy] ?: @"";
        _displayName = [displayName copy] ?: _bundleIdentifier;
        _initialRuleKind = initialRuleKind;
        _returnViewController = returnViewController;
        _commitHandler = [commitHandler copy];
        _entries = @[];
        self.title = NFPLocalizedString(@"RULE_SCAN_TITLE");
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.prompt = self.displayName;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 76.0;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadEntries];
}

- (void)reloadEntries {
    NSError *error = nil;
    NSString *source = nil;
    NSArray<NSDictionary *> *loadedEntries = [NFPNotificationHistoryClient fetchEntriesForBundleIdentifier:self.bundleIdentifier
                                                                                                     error:&error
                                                                                                    source:&source];
    self.historySource = source;
    if (error && loadedEntries.count == 0) {
        self.tableView.backgroundView = [self errorStateView:error.localizedDescription];
        self.entries = @[];
        [self.tableView reloadData];
        return;
    }

    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry, NSDictionary *bindings) {
        return [self hasScannableContentForEntry:entry];
    }];

    self.entries = [[loadedEntries filteredArrayUsingPredicate:predicate] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        NSTimeInterval lhsTimestamp = [lhs[NFLogTimestampKey] respondsToSelector:@selector(doubleValue)] ? [lhs[NFLogTimestampKey] doubleValue] : 0;
        NSTimeInterval rhsTimestamp = [rhs[NFLogTimestampKey] respondsToSelector:@selector(doubleValue)] ? [rhs[NFLogTimestampKey] doubleValue] : 0;
        if (lhsTimestamp > rhsTimestamp) {
            return NSOrderedAscending;
        }
        if (lhsTimestamp < rhsTimestamp) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    self.tableView.backgroundView = self.entries.count == 0 ? [self emptyStateView] : nil;
    [self.tableView reloadData];
}

- (BOOL)hasScannableContentForEntry:(NSDictionary *)entry {
    NSArray<NSString *> *fields = @[
        [entry[NFLogTitleKey] isKindOfClass:[NSString class]] ? entry[NFLogTitleKey] : @"",
        [entry[NFLogSubtitleKey] isKindOfClass:[NSString class]] ? entry[NFLogSubtitleKey] : @"",
        [entry[NFLogHeaderKey] isKindOfClass:[NSString class]] ? entry[NFLogHeaderKey] : @"",
        [entry[NFLogBodyKey] isKindOfClass:[NSString class]] ? entry[NFLogBodyKey] : @"",
        [entry[NFLogMessageKey] isKindOfClass:[NSString class]] ? entry[NFLogMessageKey] : @""
    ];
    for (NSString *field in fields) {
        if ([[field stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0) {
            return YES;
        }
    }
    return NO;
}

- (UIView *)emptyStateView {
    UILabel *label = [[UILabel alloc] initWithFrame:self.tableView.bounds];
    label.text = NFPLocalizedString(@"RULE_SCAN_EMPTY");
    label.textColor = [UIColor secondaryLabelColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    return label;
}

- (UIView *)errorStateView:(NSString *)message {
    UILabel *label = [[UILabel alloc] initWithFrame:self.tableView.bounds];
    NSString *resolvedMessage = message;
    if ([resolvedMessage isEqualToString:@"RULE_SCAN_SOURCE_NO_REPLY"] ||
        [resolvedMessage isEqualToString:@"RULE_SCAN_SOURCE_FAILED"]) {
        resolvedMessage = NFPLocalizedString(resolvedMessage);
    }
    label.text = resolvedMessage.length > 0 ? resolvedMessage : NFPLocalizedString(@"RULE_SCAN_SOURCE_FAILED");
    label.textColor = [UIColor secondaryLabelColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    return label;
}

- (NSDateFormatter *)dateFormatter {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterShortStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
    });
    return formatter;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"scan"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"scan"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.numberOfLines = 2;
        cell.detailTextLabel.numberOfLines = 2;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }

    NSDictionary *entry = self.entries[indexPath.row];
    NSTimeInterval timestamp = [entry[NFLogTimestampKey] respondsToSelector:@selector(doubleValue)] ? [entry[NFLogTimestampKey] doubleValue] : 0;
    NSString *preview = NFPScannerPreviewText(entry);
    cell.textLabel.text = preview;
    cell.detailTextLabel.text = [[self dateFormatter] stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
    cell.imageView.image = [[NFPAppInfoProvider sharedProvider] iconForBundleIdentifier:self.bundleIdentifier];
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if ([self.historySource isEqualToString:@"mirror"]) {
        return NFPLocalizedString(@"RULE_SCAN_FOOTER_MIRROR");
    }
    return NFPLocalizedString(@"RULE_SCAN_FOOTER");
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= self.entries.count) {
        return;
    }

    NSDictionary *entry = self.entries[indexPath.row];
    NFPNotificationRuleTokenPickerController *controller = [[NFPNotificationRuleTokenPickerController alloc] initWithNotificationEntry:entry
                                                                                                                           appDisplayName:self.displayName
                                                                                                                           initialRuleKind:self.initialRuleKind
                                                                                                                      returnViewController:self.returnViewController
                                                                                                                             commitHandler:self.commitHandler];
    [self.navigationController pushViewController:controller animated:YES];
}

@end
