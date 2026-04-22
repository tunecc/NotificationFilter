#import "NFPLogsListController.h"
#import "NFPLocalization.h"
#import "../Shared/NFLogStore.h"
#import "../Shared/NFPreferences.h"
#import "NFPAppInfoProvider.h"
#import "NFPLogDetailController.h"

@interface NFPLogsListController ()

@property (nonatomic, copy) NSArray<NSDictionary *> *entries;
@property (nonatomic, copy) NSArray<NSDictionary *> *filteredEntries;
@property (nonatomic, strong) UISearchController *searchController;

@end

@implementation NFPLogsListController

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

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NFPLocalizedString(@"LOGS_TITLE");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
                                                                                            target:self
                                                                                            action:@selector(clearTapped)];

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
    self.entries = [NFLogStore loadEntries];
    [self applySearchText:self.searchController.searchBar.text];
    self.tableView.backgroundView = self.filteredEntries.count == 0 ? [self emptyStateView] : nil;
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
    return self.filteredEntries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"log"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"log"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.detailTextLabel.numberOfLines = 2;
    }

    NSDictionary *entry = self.filteredEntries[indexPath.row];
    NSString *bundleIdentifier = entry[NFLogBundleIdentifierKey];
    NSString *displayName = [[NFPAppInfoProvider sharedProvider] displayNameForBundleIdentifier:bundleIdentifier];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[entry[NFLogTimestampKey] doubleValue]];

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterShortStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;

    cell.textLabel.text = [NSString stringWithFormat:@"%@ · %@",
                           displayName,
                           [formatter stringFromDate:date]];
    cell.detailTextLabel.text = NFPLogPreviewText(entry);
    cell.imageView.image = [[NFPAppInfoProvider sharedProvider] iconForBundleIdentifier:bundleIdentifier];
    [cell setNeedsLayout];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *entry = self.filteredEntries[indexPath.row];
    NSString *bundleIdentifier = entry[NFLogBundleIdentifierKey];
    NSString *displayName = [[NFPAppInfoProvider sharedProvider] displayNameForBundleIdentifier:bundleIdentifier];
    NFPLogDetailController *controller = [[NFPLogDetailController alloc] initWithEntry:entry displayName:displayName];
    [self.navigationController pushViewController:controller animated:YES];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return NFPLocalizedString(@"LOGS_FOOTER");
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

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self applySearchText:searchController.searchBar.text];
    self.tableView.backgroundView = self.filteredEntries.count == 0 ? [self emptyStateView] : nil;
    [self.tableView reloadData];
}

- (void)applySearchText:(NSString *)searchText {
    NSString *normalizedSearchText = [[searchText ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (normalizedSearchText.length == 0) {
        self.filteredEntries = self.entries ?: @[];
        return;
    }

    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry, NSDictionary *bindings) {
        NSString *bundleIdentifier = [entry[NFLogBundleIdentifierKey] lowercaseString] ?: @"";
        NSString *displayName = [[[NFPAppInfoProvider sharedProvider] displayNameForBundleIdentifier:entry[NFLogBundleIdentifierKey]] lowercaseString] ?: @"";
        NSString *matchedPattern = [entry[NFLogMatchedPatternKey] lowercaseString] ?: @"";
        NSString *joinedText = [entry[NFLogJoinedTextKey] lowercaseString] ?: @"";
        return [bundleIdentifier containsString:normalizedSearchText] ||
               [displayName containsString:normalizedSearchText] ||
               [matchedPattern containsString:normalizedSearchText] ||
               [joinedText containsString:normalizedSearchText];
    }];
    self.filteredEntries = [self.entries filteredArrayUsingPredicate:predicate];
}

@end
