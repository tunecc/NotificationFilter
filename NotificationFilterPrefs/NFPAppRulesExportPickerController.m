#import "NFPAppRulesExportPickerController.h"
#import "../Shared/NFPreferences.h"
#import "NFPLocalization.h"
#import "NFPAppInfoProvider.h"

static NSString * const NFPExportPickerBundleIdentifierKey = @"bundleID";
static NSString * const NFPExportPickerDisplayNameKey = @"displayName";

@interface NFPAppRulesExportPickerController ()

@property (nonatomic, copy) NSArray<NSString *> *initiallySelectedBundleIdentifiers;
@property (nonatomic, copy) void (^selectionHandler)(NSArray<NSString *> *selectedBundleIdentifiers);
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedBundleIdentifiers;
@property (nonatomic, copy) NSArray<NSDictionary *> *applications;
@property (nonatomic, copy) NSArray<NSDictionary *> *filteredApplications;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIBarButtonItem *doneButton;

@end

@implementation NFPAppRulesExportPickerController

- (instancetype)initWithSelectedBundleIdentifiers:(NSArray<NSString *> *)selectedBundleIdentifiers
                                 selectionHandler:(void (^)(NSArray<NSString *> *))selectionHandler {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _initiallySelectedBundleIdentifiers = [selectedBundleIdentifiers copy] ?: @[];
        _selectionHandler = [selectionHandler copy];
        _selectedBundleIdentifiers = [NSMutableSet setWithArray:_initiallySelectedBundleIdentifiers];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NFPLocalizedString(@"APP_RULES_EXPORT_PICKER_TITLE");
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.allowsMultipleSelectionDuringEditing = YES;
    self.tableView.allowsMultipleSelection = YES;
    [self.tableView setEditing:YES animated:NO];

    UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    searchController.obscuresBackgroundDuringPresentation = NO;
    searchController.searchResultsUpdater = self;
    searchController.searchBar.placeholder = NFPLocalizedString(@"APP_RULES_SEARCH_PLACEHOLDER");
    self.navigationItem.searchController = searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.searchController = searchController;

    self.doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                     target:self
                                                                     action:@selector(doneTapped)];
    self.navigationItem.rightBarButtonItem = self.doneButton;

    [self reloadApplications];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadApplications];
}

- (void)reloadApplications {
    NSDictionary *preferences = [NFPreferences loadPreferences];
    NSDictionary *appRules = preferences[NFAppRulesKey];

    NSMutableSet<NSString *> *configuredBundleIdentifiers = [NSMutableSet set];
    [appRules enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (![key isKindOfClass:[NSString class]]) {
            return;
        }
        if ([NFPreferences rulesDictionaryHasConfiguredValues:obj]) {
            [configuredBundleIdentifiers addObject:key];
        }
    }];

    NSArray<NSDictionary *> *applications = [[NFPAppInfoProvider sharedProvider] sortedApplicationsWithConfiguredBundleIdentifiers:configuredBundleIdentifiers
                                                                                                                  onlyConfiguredApps:YES
                                                                                                                        showSystemApps:YES
                                                                                                                         showTrollApps:YES];
    self.applications = applications;
    [self applySearchText:self.searchController.searchBar.text];
    [self updateDoneButton];
    [self.tableView reloadData];
}

- (void)applySearchText:(NSString *)searchText {
    NSString *normalizedSearchText = [[searchText ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (normalizedSearchText.length == 0) {
        self.filteredApplications = self.applications ?: @[];
        return;
    }

    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *application, NSDictionary *bindings) {
        NSString *displayName = [application[NFPExportPickerDisplayNameKey] lowercaseString] ?: @"";
        NSString *bundleIdentifier = [application[NFPExportPickerBundleIdentifierKey] lowercaseString] ?: @"";
        return [displayName containsString:normalizedSearchText] || [bundleIdentifier containsString:normalizedSearchText];
    }];
    self.filteredApplications = [self.applications filteredArrayUsingPredicate:predicate];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self applySearchText:searchController.searchBar.text];
    [self.tableView reloadData];
}

- (void)updateDoneButton {
    NSUInteger count = self.selectedBundleIdentifiers.count;
    self.doneButton.title = count > 0 ? [NSString stringWithFormat:NFPLocalizedString(@"APP_RULES_EXPORT_DONE_COUNT_FORMAT"), (unsigned long)count]
                                     : NFPLocalizedString(@"COMMON_DONE");
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredApplications.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"app"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"app"];
    }

    NSDictionary *application = self.filteredApplications[indexPath.row];
    NSString *bundleIdentifier = application[NFPExportPickerBundleIdentifierKey];
    cell.textLabel.text = application[NFPExportPickerDisplayNameKey];
    cell.detailTextLabel.text = bundleIdentifier;
    cell.imageView.image = [[NFPAppInfoProvider sharedProvider] iconForBundleIdentifier:bundleIdentifier];
    [cell setNeedsLayout];

    if ([self.selectedBundleIdentifiers containsObject:bundleIdentifier]) {
        [tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
    }

    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return NFPLocalizedString(@"APP_RULES_EXPORT_PICKER_FOOTER");
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *application = self.filteredApplications[indexPath.row];
    NSString *bundleIdentifier = application[NFPExportPickerBundleIdentifierKey];
    if (bundleIdentifier.length > 0) {
        [self.selectedBundleIdentifiers addObject:bundleIdentifier];
    }
    [self updateDoneButton];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *application = self.filteredApplications[indexPath.row];
    NSString *bundleIdentifier = application[NFPExportPickerBundleIdentifierKey];
    [self.selectedBundleIdentifiers removeObject:bundleIdentifier];
    [self updateDoneButton];
}

- (void)doneTapped {
    NSArray<NSString *> *selected = [self.selectedBundleIdentifiers allObjects];
    if (self.selectionHandler) {
        self.selectionHandler(selected);
    }
    [self.navigationController popViewControllerAnimated:YES];
}

@end
