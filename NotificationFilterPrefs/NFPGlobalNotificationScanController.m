#import "NFPGlobalNotificationScanController.h"
#import "../Shared/NFPreferences.h"
#import "../Shared/NFNotificationHistoryBridge.h"
#import "NFPLocalization.h"
#import "NFPAppInfoProvider.h"
#import "NFPNotificationHistoryClient.h"
#import "NFPNotificationRuleTokenPickerController.h"

// 与单应用扫描一致的超时：1.5s 内未收到完成通知则回退当前快照。
static NSTimeInterval const NFPGlobalScanRefreshTimeout = 1.5;
static NSUInteger const NFPGlobalScanRequestLimit = 500;
static NSString * const NFPGlobalScanEntryCellReuseIdentifier = @"global-scan-entry";
static NSString * const NFPGlobalScanBundleIdentifierKey = @"bundleIdentifier";
static NSString * const NFPGlobalScanDisplayNameKey = @"displayName";
static NSString * const NFPGlobalScanEntriesKey = @"entries";
static NSString * const NFPGlobalScanLatestTimestampKey = @"latestTimestamp";
static NSString * const NFPGlobalScanHasContentKey = @"hasContent";

static NSString *NFPGlobalScanPreviewText(NSDictionary *entry) {
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

// 独立于 self 的规则提交器：避免 token picker 回调链持有全局扫描页。
// 语义沿用 NFPPerAppRulesController 的 appendScannedRuleEntries:toEditorKind:error:。
static BOOL NFPGlobalScanAppendRuleEntries(NSString *bundleIdentifier,
                                          NFPRuleEditorKind editorKind,
                                          NSArray<NSDictionary *> *entries,
                                          NSError **error) {
    if (entries.count == 0 || bundleIdentifier.length == 0) {
        return YES;
    }

    NSString *rulesKey = nil;
    NSString *defaultScope = NFRuleScopeAll;
    switch (editorKind) {
        case NFPRuleEditorKindContains:
            rulesKey = NFRulesContainsKey;
            defaultScope = NFRuleScopeMessage;
            break;
        case NFPRuleEditorKindExclude:
            rulesKey = NFRulesExcludeKey;
            defaultScope = NFRuleScopeAll;
            break;
        default:
            return NO;
    }

    NSDictionary *rules = [NFPreferences rulesForBundleIdentifier:bundleIdentifier
                                                    fromPreferences:[NFPreferences loadPreferences]];
    NSMutableDictionary *mutableRules = [rules mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableArray *combinedEntries = [NSMutableArray arrayWithArray:mutableRules[rulesKey] ?: @[]];
    [combinedEntries addObjectsFromArray:entries];
    mutableRules[rulesKey] = [NFPreferences normalizedRuleEntriesFromArray:combinedEntries
                                                              defaultScope:defaultScope];

    NSMutableDictionary *preferences = [NFPreferences loadMutablePreferences];
    NSMutableDictionary *appRules = [preferences[NFAppRulesKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    appRules[bundleIdentifier] = [NFPreferences normalizedRulesDictionaryFromRawDictionary:mutableRules];
    preferences[NFAppRulesKey] = appRules;

    BOOL saved = [NFPreferences savePreferences:preferences error:error];
    if (!saved) {
        return NO;
    }

    [NFPreferences postPreferencesChangedNotification];
    return YES;
}

@interface NFPGlobalNotificationScanController ()

@property (nonatomic, copy) NSArray<NSDictionary *> *appGroups;
@property (nonatomic, copy, nullable) NSString *historySource;
@property (nonatomic, copy, nullable) NSString *refreshRequestIdentifier;
@property (nonatomic, strong, nullable) NSTimer *refreshTimeoutTimer;
@property (nonatomic, assign) BOOL waitingForRefresh;
@property (nonatomic, assign) BOOL hasLoadedOnce;

@end

@implementation NFPGlobalNotificationScanController

static void NFPGlobalScanRefreshCompletedCallback(CFNotificationCenterRef center,
                                                  void *observer,
                                                  CFStringRef name,
                                                  const void *object,
                                                  CFDictionaryRef userInfo) {
    NFPGlobalNotificationScanController *controller = (__bridge NFPGlobalNotificationScanController *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [controller handleRefreshCompletedNotification];
    });
}

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _appGroups = @[];
        self.title = NFPLocalizedString(@"GLOBAL_SCAN_TITLE");
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 76.0;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    (__bridge const void *)(self),
                                    NFPGlobalScanRefreshCompletedCallback,
                                    (CFStringRef)NFNotificationHistoryRefreshCompletedNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 从 token picker 返回时只重新读取快照（规则可能已变化），不再发起跨进程刷新请求。
    if (self.hasLoadedOnce) {
        [self reloadEntries];
        return;
    }
    self.hasLoadedOnce = YES;
    [self requestRefreshAndReloadEntries];
}

- (void)dealloc {
    [self.refreshTimeoutTimer invalidate];
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                       (__bridge const void *)(self),
                                       (CFStringRef)NFNotificationHistoryRefreshCompletedNotification,
                                       NULL);
}

#pragma mark - Refresh

- (void)requestRefreshAndReloadEntries {
    [self.refreshTimeoutTimer invalidate];
    self.refreshTimeoutTimer = nil;
    self.waitingForRefresh = NO;
    self.refreshRequestIdentifier = nil;

    NSError *error = nil;
    NSString *requestIdentifier = [NFPNotificationHistoryClient requestRefreshForBundleIdentifier:NFNotificationHistoryAllAppsIdentifier
                                                                                            limit:NFPGlobalScanRequestLimit
                                                                                            error:&error];
    if (requestIdentifier.length == 0) {
        [self reloadEntries];
        return;
    }

    self.refreshRequestIdentifier = requestIdentifier;
    self.waitingForRefresh = YES;
    self.appGroups = @[];
    self.historySource = nil;
    self.tableView.backgroundView = [self loadingStateView];
    [self.tableView reloadData];
    self.refreshTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:NFPGlobalScanRefreshTimeout
                                                                target:self
                                                              selector:@selector(refreshRequestDidTimeout:)
                                                              userInfo:requestIdentifier
                                                               repeats:NO];
    [self handleRefreshCompletedNotification];
}

- (void)handleRefreshCompletedNotification {
    if (!self.waitingForRefresh || self.refreshRequestIdentifier.length == 0) {
        return;
    }

    NSDictionary *status = [NFPNotificationHistoryClient refreshStatusForRequestIdentifier:self.refreshRequestIdentifier
                                                                          bundleIdentifier:NFNotificationHistoryAllAppsIdentifier];
    if (!status) {
        return;
    }

    [self.refreshTimeoutTimer invalidate];
    self.refreshTimeoutTimer = nil;
    self.waitingForRefresh = NO;
    NSString *source = [status[NFNotificationHistorySourceKey] isKindOfClass:[NSString class]] ? status[NFNotificationHistorySourceKey] : nil;
    [self reloadEntriesWithPreferredSource:source];
}

- (void)refreshRequestDidTimeout:(NSTimer *)timer {
    NSString *requestIdentifier = [timer.userInfo isKindOfClass:[NSString class]] ? timer.userInfo : nil;
    if (requestIdentifier.length > 0 && ![requestIdentifier isEqualToString:self.refreshRequestIdentifier]) {
        return;
    }

    self.refreshTimeoutTimer = nil;
    self.waitingForRefresh = NO;
    [self reloadEntries];
}

- (void)reloadEntries {
    [self reloadEntriesWithPreferredSource:nil];
}

- (void)reloadEntriesWithPreferredSource:(NSString *)preferredSource {
    NSError *error = nil;
    NSString *source = nil;
    NSArray<NSDictionary *> *loadedEntries = [NFPNotificationHistoryClient fetchAllAppsEntriesWithError:&error source:&source];
    self.historySource = preferredSource ?: source;
    if (error && loadedEntries.count == 0) {
        self.tableView.backgroundView = [self errorStateView:error.localizedDescription];
        self.appGroups = @[];
        [self.tableView reloadData];
        return;
    }

    self.appGroups = [self appGroupsWithEntries:loadedEntries];
    self.tableView.backgroundView = self.appGroups.count == 0 ? [self emptyStateView] : nil;
    [self.tableView reloadData];
}

#pragma mark - Grouping

- (BOOL)entryHasScannableContent:(NSDictionary *)entry {
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

- (NSTimeInterval)timestampForEntry:(NSDictionary *)entry {
    return [entry[NFLogTimestampKey] respondsToSelector:@selector(doubleValue)] ? [entry[NFLogTimestampKey] doubleValue] : 0;
}

- (NSArray<NSDictionary *> *)sortedEntriesDescending:(NSArray<NSDictionary *> *)entries {
    return [entries sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        NSTimeInterval lhsTimestamp = [self timestampForEntry:lhs];
        NSTimeInterval rhsTimestamp = [self timestampForEntry:rhs];
        if (lhsTimestamp > rhsTimestamp) {
            return NSOrderedAscending;
        }
        if (lhsTimestamp < rhsTimestamp) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
}

// 条目按应用分组；组内按时间倒序，组按最近通知时间排序（与 NFPLogsListController 一致）。
- (NSArray<NSDictionary *> *)appGroupsWithEntries:(NSArray<NSDictionary *> *)entries {
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *entriesByBundleIdentifier = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *orderedBundleIdentifiers = [NSMutableArray array];

    for (NSDictionary *entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]] || ![self entryHasScannableContent:entry]) {
            continue;
        }

        NSString *bundleIdentifier = [entry[NFLogBundleIdentifierKey] isKindOfClass:[NSString class]] ? entry[NFLogBundleIdentifierKey] : @"";
        if (bundleIdentifier.length == 0) {
            continue;
        }

        NSMutableArray *grouped = entriesByBundleIdentifier[bundleIdentifier];
        if (!grouped) {
            grouped = [NSMutableArray array];
            entriesByBundleIdentifier[bundleIdentifier] = grouped;
            [orderedBundleIdentifiers addObject:bundleIdentifier];
        }
        [grouped addObject:entry];
    }

    NSMutableArray<NSDictionary *> *groups = [NSMutableArray array];
    for (NSString *bundleIdentifier in orderedBundleIdentifiers) {
        NSArray<NSDictionary *> *sortedEntries = [self sortedEntriesDescending:entriesByBundleIdentifier[bundleIdentifier]];
        NSMutableDictionary *group = [@{
            NFPGlobalScanBundleIdentifierKey: bundleIdentifier,
            NFPGlobalScanDisplayNameKey: [[NFPAppInfoProvider sharedProvider] displayNameForBundleIdentifier:bundleIdentifier] ?: bundleIdentifier,
            NFPGlobalScanEntriesKey: sortedEntries,
            NFPGlobalScanLatestTimestampKey: @([self timestampForEntry:sortedEntries.firstObject]),
            NFPGlobalScanHasContentKey: @YES
        } mutableCopy];
        [groups addObject:[group copy]];
    }

    return [groups sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        NSTimeInterval lhsTimestamp = [lhs[NFPGlobalScanLatestTimestampKey] doubleValue];
        NSTimeInterval rhsTimestamp = [rhs[NFPGlobalScanLatestTimestampKey] doubleValue];
        if (lhsTimestamp > rhsTimestamp) {
            return NSOrderedAscending;
        }
        if (lhsTimestamp < rhsTimestamp) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
}

- (NSArray<NSDictionary *> *)entriesForSection:(NSInteger)section {
    if (section < 0 || section >= self.appGroups.count) {
        return @[];
    }
    NSDictionary *group = self.appGroups[section];
    return [group[NFPGlobalScanEntriesKey] isKindOfClass:[NSArray class]] ? group[NFPGlobalScanEntriesKey] : @[];
}

- (NSString *)bundleIdentifierForSection:(NSInteger)section {
    if (section < 0 || section >= self.appGroups.count) {
        return @"";
    }
    return [self.appGroups[section][NFPGlobalScanBundleIdentifierKey] isKindOfClass:[NSString class]] ?
        self.appGroups[section][NFPGlobalScanBundleIdentifierKey] :
        @"";
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

#pragma mark - State views

- (UIView *)loadingStateView {
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    indicator.frame = self.tableView.bounds;
    indicator.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [indicator startAnimating];
    return indicator;
}

- (UIView *)emptyStateView {
    UILabel *label = [[UILabel alloc] initWithFrame:self.tableView.bounds];
    label.text = NFPLocalizedString(@"GLOBAL_SCAN_EMPTY");
    label.textColor = [UIColor secondaryLabelColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    return label;
}

- (UIView *)errorStateView:(NSString *)message {
    UILabel *label = [[UILabel alloc] initWithFrame:self.tableView.bounds];
    NSString *resolvedMessage = message;
    if ([resolvedMessage isEqualToString:@"RULE_SCAN_SOURCE_FAILED"]) {
        resolvedMessage = NFPLocalizedString(resolvedMessage);
    }
    label.text = resolvedMessage.length > 0 ? resolvedMessage : NFPLocalizedString(@"RULE_SCAN_SOURCE_FAILED");
    label.textColor = [UIColor secondaryLabelColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    return label;
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.appGroups.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self entriesForSection:section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section < 0 || section >= self.appGroups.count) {
        return nil;
    }

    NSDictionary *group = self.appGroups[section];
    NSString *displayName = [group[NFPGlobalScanDisplayNameKey] isKindOfClass:[NSString class]] ? group[NFPGlobalScanDisplayNameKey] : @"";
    NSUInteger count = [self entriesForSection:section].count;
    if (displayName.length == 0) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@  (%lu)", displayName, (unsigned long)count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 0) {
        return nil;
    }

    if ([self.historySource isEqualToString:NFNotificationHistorySourceLive]) {
        return NFPLocalizedString(@"GLOBAL_SCAN_FOOTER_LIVE");
    }
    if ([self.historySource isEqualToString:NFNotificationHistorySourceMirror]) {
        return NFPLocalizedString(@"GLOBAL_SCAN_FOOTER_MIRROR");
    }
    return NFPLocalizedString(@"GLOBAL_SCAN_FOOTER");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:NFPGlobalScanEntryCellReuseIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:NFPGlobalScanEntryCellReuseIdentifier];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.numberOfLines = 2;
        cell.detailTextLabel.numberOfLines = 2;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }

    NSDictionary *entry = [self entriesForSection:indexPath.section][indexPath.row];
    NSString *bundleIdentifier = [self bundleIdentifierForSection:indexPath.section];
    NSTimeInterval timestamp = [self timestampForEntry:entry];
    cell.textLabel.text = NFPGlobalScanPreviewText(entry);
    cell.detailTextLabel.text = [[self dateFormatter] stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
    cell.imageView.image = [[NFPAppInfoProvider sharedProvider] iconForBundleIdentifier:bundleIdentifier];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray<NSDictionary *> *entries = [self entriesForSection:indexPath.section];
    if (indexPath.row >= entries.count) {
        return;
    }

    NSDictionary *entry = entries[indexPath.row];
    NSString *bundleIdentifier = [self bundleIdentifierForSection:indexPath.section];
    if (bundleIdentifier.length == 0) {
        return;
    }

    NSString *displayName = [[NFPAppInfoProvider sharedProvider] displayNameForBundleIdentifier:bundleIdentifier] ?: bundleIdentifier;
    NSDictionary *rules = [NFPreferences rulesForBundleIdentifier:bundleIdentifier
                                                    fromPreferences:[NFPreferences loadPreferences]];
    NSString *ruleMode = [NFPreferences normalizedRulesMode:rules[NFRulesModeKey]];

    __weak typeof(self) weakSelf = self;
    NFPNotificationRuleTokenPickerController *controller = [[NFPNotificationRuleTokenPickerController alloc] initWithNotificationEntry:entry
                                                                                                                       appDisplayName:displayName
                                                                                                                       initialRuleKind:NFPRuleEditorKindContains
                                                                                                                              ruleMode:ruleMode
                                                                                                                  returnViewController:self
                                                                                                                            returnMode:NFPNotificationRuleTokenReturnModeTargetViewController
                                                                                                                         commitHandler:^BOOL(NFPRuleEditorKind targetKind, NSArray<NSDictionary *> *ruleEntries, NSError **error) {
        BOOL result = NFPGlobalScanAppendRuleEntries(bundleIdentifier, targetKind, ruleEntries, error);
        if (result) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf reloadEntries];
            });
        }
        return result;
    }];
    [self.navigationController pushViewController:controller animated:YES];
}

@end
