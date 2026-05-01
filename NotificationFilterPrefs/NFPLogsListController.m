#import "NFPLogsListController.h"
#import "NFPLocalization.h"
#import "../Shared/NFLogStore.h"
#import "../Shared/NFPreferences.h"
#import "NFPAppInfoProvider.h"
#import "NFPLogDetailController.h"

@interface NFPLogsListController ()

@property (nonatomic, copy) NSArray<NSDictionary *> *entries;
@property (nonatomic, copy) NSArray<NSDictionary *> *filteredEntries;
@property (nonatomic, copy) NSArray<NSDictionary *> *appGroups;
@property (nonatomic, copy) NSArray<NSDictionary *> *filteredAppGroups;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy, nullable) NSString *bundleIdentifierFilter;
@property (nonatomic, copy, nullable) NSString *displayNameFilter;
@property (nonatomic, assign) BOOL showsAppEntries;

@end

@implementation NFPLogsListController

static NSString * const NFPLogsGroupBundleIdentifierKey = @"bundleIdentifier";
static NSString * const NFPLogsGroupDisplayNameKey = @"displayName";
static NSString * const NFPLogsGroupLatestEntryKey = @"latestEntry";
static NSString * const NFPLogsGroupLatestTimestampKey = @"latestTimestamp";
static NSString * const NFPLogsGroupEntriesKey = @"entries";

static NSString *NFPLogPreviewText(NSDictionary *entry) {
    NSString *joinedText = entry[NFLogJoinedTextKey];
    if (![joinedText isKindOfClass:[NSString class]] || joinedText.length == 0) {
        NSString *matchedPattern = entry[NFLogMatchedPatternKey];
        if ([matchedPattern isKindOfClass:[NSString class]] && matchedPattern.length > 0) {
            return matchedPattern;
        }
        return NFPLocalizedString(@"LOGS_EMPTY_PREVIEW");
    }

    NSMutableString *preview = [[joinedText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] mutableCopy];
    [preview replaceOccurrencesOfString:@"\n"
                             withString:@"  "
                                options:0
                                  range:NSMakeRange(0, preview.length)];
    if (preview.length > 90) {
        return [[preview substringToIndex:90] stringByAppendingString:@"…"];
    }
    return preview;
}

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier displayName:(NSString *)displayName {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _bundleIdentifierFilter = [bundleIdentifier copy];
        _displayNameFilter = [displayName copy];
        _showsAppEntries = YES;
    }
    return self;
}

- (BOOL)isShowingAppEntries {
    return self.showsAppEntries;
}

- (BOOL)isShowingGlobalSearchResults {
    if ([self isShowingAppEntries]) {
        return NO;
    }
    NSString *searchText = [self.searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return searchText.length > 0;
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

- (NSTimeInterval)timestampForEntry:(NSDictionary *)entry {
    if ([entry[NFLogTimestampKey] respondsToSelector:@selector(doubleValue)]) {
        return [entry[NFLogTimestampKey] doubleValue];
    }
    return 0;
}

- (NSString *)displayNameForBundleIdentifier:(NSString *)bundleIdentifier {
    return [[NFPAppInfoProvider sharedProvider] displayNameForBundleIdentifier:bundleIdentifier];
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

- (NSArray<NSDictionary *> *)appGroupsFromEntries:(NSArray<NSDictionary *> *)entries {
    NSMutableDictionary<NSString *, NSMutableDictionary *> *groupsByBundleIdentifier = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *orderedBundleIdentifiers = [NSMutableArray array];

    for (NSDictionary *entry in [self sortedEntriesDescending:entries]) {
        NSString *bundleIdentifier = [entry[NFLogBundleIdentifierKey] isKindOfClass:[NSString class]] ?
            entry[NFLogBundleIdentifierKey] :
            @"";
        NSMutableDictionary *group = groupsByBundleIdentifier[bundleIdentifier];
        if (!group) {
            group = [@{
                NFPLogsGroupBundleIdentifierKey: bundleIdentifier,
                NFPLogsGroupDisplayNameKey: [self displayNameForBundleIdentifier:bundleIdentifier] ?: bundleIdentifier,
                NFPLogsGroupLatestEntryKey: entry,
                NFPLogsGroupLatestTimestampKey: @([self timestampForEntry:entry]),
                NFPLogsGroupEntriesKey: [NSMutableArray array]
            } mutableCopy];
            groupsByBundleIdentifier[bundleIdentifier] = group;
            [orderedBundleIdentifiers addObject:bundleIdentifier];
        }
        [group[NFPLogsGroupEntriesKey] addObject:entry];
    }

    NSMutableArray<NSDictionary *> *groups = [NSMutableArray arrayWithCapacity:orderedBundleIdentifiers.count];
    for (NSString *bundleIdentifier in orderedBundleIdentifiers) {
        NSMutableDictionary *group = [groupsByBundleIdentifier[bundleIdentifier] mutableCopy];
        group[NFPLogsGroupEntriesKey] = [[self sortedEntriesDescending:group[NFPLogsGroupEntriesKey]] copy];
        [groups addObject:[group copy]];
    }
    return groups;
}

- (BOOL)entry:(NSDictionary *)entry matchesSearchText:(NSString *)normalizedSearchText {
    NSString *bundleIdentifier = [entry[NFLogBundleIdentifierKey] lowercaseString] ?: @"";
    NSString *displayName = [[self displayNameForBundleIdentifier:entry[NFLogBundleIdentifierKey]] lowercaseString] ?: @"";
    if ([bundleIdentifier containsString:normalizedSearchText] || [displayName containsString:normalizedSearchText]) {
        return YES;
    }

    NSArray<NSString *> *searchableValues = @[
        [entry[NFLogMatchedPatternKey] lowercaseString] ?: @"",
        [entry[NFLogJoinedTextKey] lowercaseString] ?: @"",
        [entry[NFLogTitleKey] lowercaseString] ?: @"",
        [entry[NFLogSubtitleKey] lowercaseString] ?: @"",
        [entry[NFLogHeaderKey] lowercaseString] ?: @"",
        [entry[NFLogBodyKey] lowercaseString] ?: @"",
        [entry[NFLogMessageKey] lowercaseString] ?: @""
    ];

    for (NSString *value in searchableValues) {
        if ([value containsString:normalizedSearchText]) {
            return YES;
        }
    }
    return NO;
}

- (NSString *)detailTextForSearchResultEntry:(NSDictionary *)entry {
    NSString *matchedPattern = [entry[NFLogMatchedPatternKey] isKindOfClass:[NSString class]] ? entry[NFLogMatchedPatternKey] : nil;
    NSString *previewText = NFPLogPreviewText(entry);
    if (matchedPattern.length == 0) {
        return previewText;
    }

    return [NSString stringWithFormat:NFPLocalizedString(@"LOGS_SEARCH_RESULT_DETAIL_FORMAT"),
                                      matchedPattern,
                                      previewText];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self isShowingAppEntries] ? (self.displayNameFilter ?: NFPLocalizedString(@"LOGS_TITLE")) : NFPLocalizedString(@"LOGS_TITLE");
    if (![self isShowingAppEntries]) {
        UIBarButtonItem *clearButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
                                                                                     target:self
                                                                                     action:@selector(clearTapped)];
        UIBarButtonItem *limitButton = [[UIBarButtonItem alloc] initWithTitle:NFPLocalizedString(@"LOGS_LIMIT_BUTTON")
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(limitTapped)];
        self.navigationItem.rightBarButtonItems = @[clearButton, limitButton];
    }

    UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    searchController.obscuresBackgroundDuringPresentation = NO;
    searchController.searchResultsUpdater = self;
    searchController.searchBar.placeholder = NFPLocalizedString(@"LOGS_SEARCH_PLACEHOLDER");
    self.navigationItem.searchController = searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.searchController = searchController;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadEntries];
}

- (void)reloadEntries {
    NSArray<NSDictionary *> *loadedEntries = [self sortedEntriesDescending:[NFLogStore loadEntries]];
    if ([self isShowingAppEntries]) {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry, NSDictionary *bindings) {
            NSString *bundleIdentifier = [entry[NFLogBundleIdentifierKey] isKindOfClass:[NSString class]] ? entry[NFLogBundleIdentifierKey] : @"";
            return [bundleIdentifier isEqualToString:self.bundleIdentifierFilter ?: @""];
        }];
        self.entries = [loadedEntries filteredArrayUsingPredicate:predicate];
        self.appGroups = @[];
    } else {
        self.entries = loadedEntries;
        self.appGroups = [self appGroupsFromEntries:loadedEntries];
    }
    [self applySearchText:self.searchController.searchBar.text];
    self.tableView.backgroundView = [self currentRowCount] == 0 ? [self emptyStateView] : nil;
    [self.tableView reloadData];
}

- (UIView *)emptyStateView {
    UILabel *label = [[UILabel alloc] initWithFrame:self.tableView.bounds];
    label.text = NFPLocalizedString(@"LOGS_EMPTY");
    label.textColor = [UIColor secondaryLabelColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    return label;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self currentRowCount];
}

- (NSInteger)currentRowCount {
    if ([self isShowingAppEntries] || [self isShowingGlobalSearchResults]) {
        return self.filteredEntries.count;
    }
    return self.filteredAppGroups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"log"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"log"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.detailTextLabel.numberOfLines = 2;
    }

    if ([self isShowingAppEntries] || [self isShowingGlobalSearchResults]) {
        NSDictionary *entry = self.filteredEntries[indexPath.row];
        NSString *bundleIdentifier = entry[NFLogBundleIdentifierKey];
        NSString *displayName = [self displayNameForBundleIdentifier:bundleIdentifier];
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[self timestampForEntry:entry]];

        cell.textLabel.text = [NSString stringWithFormat:@"%@ · %@",
                               displayName,
                               [[self dateFormatter] stringFromDate:date]];
        cell.detailTextLabel.text = [self isShowingGlobalSearchResults] ? [self detailTextForSearchResultEntry:entry] : NFPLogPreviewText(entry);
        cell.imageView.image = [[NFPAppInfoProvider sharedProvider] iconForBundleIdentifier:bundleIdentifier];
    } else {
        NSDictionary *group = self.filteredAppGroups[indexPath.row];
        NSDictionary *latestEntry = group[NFPLogsGroupLatestEntryKey];
        NSString *bundleIdentifier = group[NFPLogsGroupBundleIdentifierKey];
        NSString *displayName = group[NFPLogsGroupDisplayNameKey];
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[group[NFPLogsGroupLatestTimestampKey] doubleValue]];
        NSUInteger count = [group[NFPLogsGroupEntriesKey] count];

        cell.textLabel.text = [NSString stringWithFormat:@"%@ · %@",
                               displayName,
                               [[self dateFormatter] stringFromDate:date]];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  (%lu)",
                                     NFPLogPreviewText(latestEntry),
                                     (unsigned long)count];
        cell.imageView.image = [[NFPAppInfoProvider sharedProvider] iconForBundleIdentifier:bundleIdentifier];
    }
    [cell setNeedsLayout];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if ([self isShowingAppEntries] || [self isShowingGlobalSearchResults]) {
        NSDictionary *entry = self.filteredEntries[indexPath.row];
        NSString *bundleIdentifier = entry[NFLogBundleIdentifierKey];
        NSString *displayName = [self displayNameForBundleIdentifier:bundleIdentifier];
        NFPLogDetailController *controller = [[NFPLogDetailController alloc] initWithEntry:entry displayName:displayName];
        [self.navigationController pushViewController:controller animated:YES];
        return;
    }

    NSDictionary *group = self.filteredAppGroups[indexPath.row];
    NFPLogsListController *controller = [[NFPLogsListController alloc] initWithBundleIdentifier:group[NFPLogsGroupBundleIdentifierKey]
                                                                                     displayName:group[NFPLogsGroupDisplayNameKey]];
    [self.navigationController pushViewController:controller animated:YES];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if ([self isShowingAppEntries] || [self isShowingGlobalSearchResults]) {
        return nil;
    }
    return [NSString stringWithFormat:NFPLocalizedString(@"LOGS_FOOTER_FORMAT"),
                                      (long)[self currentLogEntryLimit]];
}

- (void)clearTapped {
    if (self.entries.count == 0) {
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFPLocalizedString(@"LOGS_CLEAR_TITLE")
                                                                   message:NFPLocalizedString(@"LOGS_CLEAR_MESSAGE")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_CLEAR")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [NFLogStore clearEntries];
        [self reloadEntries];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)currentLogEntryLimit {
    NSDictionary *preferences = [NFPreferences loadPreferences];
    return [NFPreferences normalizedLogEntryLimit:preferences[NFLogEntryLimitKey]];
}

- (void)limitTapped {
    NSInteger currentLimit = [self currentLogEntryLimit];
    NSString *message = [NSString stringWithFormat:NFPLocalizedString(@"LOGS_LIMIT_MESSAGE_FORMAT"),
                         (long)[NFPreferences defaultLogEntryLimit]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFPLocalizedString(@"LOGS_LIMIT_TITLE")
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.placeholder = [NSString stringWithFormat:@"%ld", (long)[NFPreferences defaultLogEntryLimit]];
        textField.text = [NSString stringWithFormat:@"%ld", (long)currentLimit];
        if (@available(iOS 10.0, *)) {
            textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        }
    }];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_CANCEL")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_SAVE")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        NSString *rawValue = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (rawValue.length > 0) {
            NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
            if ([rawValue rangeOfCharacterFromSet:nonDigits].location != NSNotFound || rawValue.integerValue <= 0) {
                [self presentLogLimitSaveError];
                return;
            }
        }

        NSInteger limit = rawValue.length > 0 ?
            [NFPreferences normalizedLogEntryLimit:@(rawValue.integerValue)] :
            [NFPreferences defaultLogEntryLimit];
        if (limit <= 0) {
            [self presentLogLimitSaveError];
            return;
        }
        [self saveLogEntryLimit:limit];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveLogEntryLimit:(NSInteger)limit {
    NSMutableDictionary *preferences = [NFPreferences loadMutablePreferences];
    preferences[NFLogEntryLimitKey] = @(limit);

    NSError *error = nil;
    if (![NFPreferences savePreferences:preferences error:&error]) {
        [self presentError:error fallbackMessageKey:@"LOGS_LIMIT_SAVE_FAILED"];
        return;
    }

    [NFPreferences postPreferencesChangedNotification];
    [NFLogStore trimEntriesToCurrentLimit];
    [self reloadEntries];
}

- (void)presentLogLimitSaveError {
    [self presentError:nil fallbackMessageKey:@"LOGS_LIMIT_INVALID_MESSAGE"];
}

- (void)presentError:(NSError *)error fallbackMessageKey:(NSString *)fallbackMessageKey {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFPLocalizedString(@"COMMON_SAVE_FAILED")
                                                                   message:error.localizedDescription ?: NFPLocalizedString(fallbackMessageKey)
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self applySearchText:searchController.searchBar.text];
    self.tableView.backgroundView = [self currentRowCount] == 0 ? [self emptyStateView] : nil;
    [self.tableView reloadData];
}

- (void)applySearchText:(NSString *)searchText {
    NSString *normalizedSearchText = [[searchText ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (normalizedSearchText.length == 0) {
        if ([self isShowingAppEntries]) {
            self.filteredEntries = self.entries ?: @[];
        } else {
            self.filteredEntries = @[];
            self.filteredAppGroups = self.appGroups ?: @[];
        }
        return;
    }

    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry, NSDictionary *bindings) {
        return [self entry:entry matchesSearchText:normalizedSearchText];
    }];
    self.filteredEntries = [self.entries filteredArrayUsingPredicate:predicate];
    self.filteredAppGroups = @[];
}

@end
