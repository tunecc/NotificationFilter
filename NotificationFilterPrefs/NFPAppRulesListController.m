#import "NFPAppRulesListController.h"
#import "../Shared/NFPreferences.h"
#import "NFPAppInfoProvider.h"
#import "NFPPerAppRulesController.h"

static NSString * const NFPAppRulesBundleIdentifierKey = @"bundleID";
static NSString * const NFPAppRulesDisplayNameKey = @"displayName";

@interface NFPAppRulesListController ()

@property (nonatomic, copy) NSArray<NSDictionary *> *applications;
@property (nonatomic, copy) NSArray<NSDictionary *> *filteredApplications;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *ruleCountsByBundleIdentifier;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL hasLoadedOnce;
@property (nonatomic, assign) BOOL onlyConfiguredApps;
@property (nonatomic, assign) BOOL showSystemApps;
@property (nonatomic, assign) BOOL showTrollApps;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;

@end

@implementation NFPAppRulesListController

static NSUInteger NFPRuleCountForRulesDictionary(NSDictionary *rules) {
    if (![rules isKindOfClass:[NSDictionary class]]) {
        return 0;
    }

    return [rules[NFRulesContainsKey] count] +
           [rules[NFRulesExcludeKey] count] +
           [rules[NFRulesRegexKey] count];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSDictionary *preferences = [NFPreferences loadPreferences];
    self.onlyConfiguredApps = [preferences[NFPrefOnlyConfiguredAppsKey] boolValue];
    self.showSystemApps = [preferences[NFPrefShowSystemAppsKey] boolValue];
    self.showTrollApps = [preferences[NFPrefShowTrollAppsKey] boolValue];
    [self configureTitleView];

    UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    searchController.obscuresBackgroundDuringPresentation = NO;
    searchController.searchResultsUpdater = self;
    searchController.searchBar.placeholder = @"搜索应用名或 Bundle ID";
    self.navigationItem.searchController = searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.searchController = searchController;

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refreshTriggered) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refreshControl;
    [self updateFilterButton];

    if ([[NFPAppInfoProvider sharedProvider] hasCachedApplications]) {
        [self reloadApplicationsFromCache];
    } else {
        [self beginInitialLoad];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.hasLoadedOnce) {
        [self reloadApplicationsFromCache];
    }
}

- (void)reloadApplicationsFromCache {
    NSDictionary *preferences = [NFPreferences loadPreferences];
    NSDictionary *appRules = preferences[NFAppRulesKey];
    NSMutableSet<NSString *> *configuredBundleIdentifiers = [NSMutableSet set];
    NSMutableDictionary<NSString *, NSNumber *> *ruleCountsByBundleIdentifier = [NSMutableDictionary dictionary];

    [appRules enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (![key isKindOfClass:[NSString class]]) {
            return;
        }

        if ([NFPreferences rulesDictionaryHasConfiguredValues:obj]) {
            [configuredBundleIdentifiers addObject:key];
            ruleCountsByBundleIdentifier[key] = @(NFPRuleCountForRulesDictionary(obj));
        }
    }];

    self.ruleCountsByBundleIdentifier = ruleCountsByBundleIdentifier;
    self.applications = [[NFPAppInfoProvider sharedProvider] sortedApplicationsWithConfiguredBundleIdentifiers:configuredBundleIdentifiers
                                                                                         onlyConfiguredApps:self.onlyConfiguredApps
                                                                                               showSystemApps:self.showSystemApps
                                                                                                showTrollApps:self.showTrollApps];
    [self applySearchText:self.searchController.searchBar.text];
    self.hasLoadedOnce = YES;
    [self updateTitleSubtitle];
    [self.tableView reloadData];
}

- (void)beginInitialLoad {
    UILabel *loadingLabel = [[UILabel alloc] initWithFrame:self.tableView.bounds];
    loadingLabel.text = @"正在加载应用列表…";
    loadingLabel.textColor = [UIColor secondaryLabelColor];
    loadingLabel.textAlignment = NSTextAlignmentCenter;
    self.tableView.backgroundView = loadingLabel;
    [self refreshApplications:NO];
}

- (void)refreshTriggered {
    [self refreshApplications:YES];
}

- (void)refreshApplications:(BOOL)showRefreshControl {
    if (showRefreshControl && !self.refreshControl.isRefreshing) {
        [self.refreshControl beginRefreshing];
    }

    __weak typeof(self) weakSelf = self;
    [[NFPAppInfoProvider sharedProvider] refreshApplicationsWithCompletion:^(__unused NSArray<NSDictionary *> *applications) {
        [weakSelf.refreshControl endRefreshing];
        weakSelf.tableView.backgroundView = nil;
        [weakSelf reloadApplicationsFromCache];
    }];
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
    NSString *bundleIdentifier = application[NFPAppRulesBundleIdentifierKey];
    cell.textLabel.text = application[NFPAppRulesDisplayNameKey];
    cell.detailTextLabel.text = bundleIdentifier;
    cell.imageView.image = [[NFPAppInfoProvider sharedProvider] iconForBundleIdentifier:bundleIdentifier];
    cell.accessoryView = [self accessoryViewForBundleIdentifier:bundleIdentifier];
    [cell setNeedsLayout];
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"已有规则的应用会固定排在顶部；下拉可刷新应用列表。";
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *application = self.filteredApplications[indexPath.row];
    NFPPerAppRulesController *controller = [[NFPPerAppRulesController alloc] initWithBundleIdentifier:application[NFPAppRulesBundleIdentifierKey]
                                                                                            displayName:application[NFPAppRulesDisplayNameKey]];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self applySearchText:searchController.searchBar.text];
    [self.tableView reloadData];
}

- (void)applySearchText:(NSString *)searchText {
    NSString *normalizedSearchText = [[searchText ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (normalizedSearchText.length == 0) {
        self.filteredApplications = self.applications ?: @[];
        return;
    }

    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *application, NSDictionary *bindings) {
        NSString *displayName = [application[NFPAppRulesDisplayNameKey] lowercaseString] ?: @"";
        NSString *bundleIdentifier = [application[NFPAppRulesBundleIdentifierKey] lowercaseString] ?: @"";
        return [displayName containsString:normalizedSearchText] || [bundleIdentifier containsString:normalizedSearchText];
    }];
    self.filteredApplications = [self.applications filteredArrayUsingPredicate:predicate];
}

- (UIView *)accessoryViewForBundleIdentifier:(NSString *)bundleIdentifier {
    NSUInteger ruleCount = [self.ruleCountsByBundleIdentifier[bundleIdentifier] unsignedIntegerValue];
    if (ruleCount == 0) {
        return nil;
    }

    UILabel *countLabel = [[UILabel alloc] init];
    countLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    countLabel.textColor = [UIColor secondaryLabelColor];
    countLabel.text = [NSString stringWithFormat:@"%lu条", (unsigned long)ruleCount];
    [countLabel sizeToFit];
    return countLabel;
}

- (void)updateFilterButton {
    BOOL isUsingNonDefaultFilter = self.onlyConfiguredApps || self.showSystemApps || self.showTrollApps;
    NSString *imageName = isUsingNonDefaultFilter ? @"line.3.horizontal.decrease.circle.fill" : @"line.3.horizontal.decrease.circle";
    UIImage *image = [UIImage systemImageNamed:imageName];
    UIBarButtonItem *filterButton = [[UIBarButtonItem alloc] initWithImage:image
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:nil
                                                                    action:nil];

    __weak typeof(self) weakSelf = self;
    UIAction *toggleOnlyConfiguredApps = [UIAction actionWithTitle:@"只看已配置规则的应用"
                                                             image:[UIImage systemImageNamed:@"checklist"]
                                                        identifier:nil
                                                           handler:^(__kindof UIAction *action) {
        weakSelf.onlyConfiguredApps = !weakSelf.onlyConfiguredApps;
        [weakSelf persistFilterStateAndReload];
    }];
    toggleOnlyConfiguredApps.state = self.onlyConfiguredApps ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIAction *toggleSystemApps = [UIAction actionWithTitle:@"显示系统项"
                                                     image:[UIImage systemImageNamed:@"apple.logo"]
                                                identifier:nil
                                                   handler:^(__kindof UIAction *action) {
        weakSelf.showSystemApps = !weakSelf.showSystemApps;
        [weakSelf persistFilterStateAndReload];
    }];
    toggleSystemApps.state = self.showSystemApps ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIAction *toggleTrollApps = [UIAction actionWithTitle:@"显示 Troll 应用"
                                                    image:[UIImage systemImageNamed:@"shippingbox"]
                                               identifier:nil
                                                  handler:^(__kindof UIAction *action) {
        weakSelf.showTrollApps = !weakSelf.showTrollApps;
        [weakSelf persistFilterStateAndReload];
    }];
    toggleTrollApps.state = self.showTrollApps ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIAction *resetDefaults = [UIAction actionWithTitle:@"恢复默认"
                                                  image:[UIImage systemImageNamed:@"arrow.counterclockwise"]
                                             identifier:nil
                                                handler:^(__kindof UIAction *action) {
        weakSelf.onlyConfiguredApps = NO;
        weakSelf.showSystemApps = YES;
        weakSelf.showTrollApps = YES;
        [weakSelf persistFilterStateAndReload];
    }];

    filterButton.menu = [UIMenu menuWithTitle:@"" children:@[
        toggleOnlyConfiguredApps,
        toggleSystemApps,
        toggleTrollApps,
        resetDefaults
    ]];
    self.navigationItem.rightBarButtonItem = filterButton;
}

- (void)configureTitleView {
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.text = @"应用规则";
    self.titleLabel = titleLabel;

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
    subtitleLabel.textColor = [UIColor secondaryLabelColor];
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel = subtitleLabel;

    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, subtitleLabel]];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.alignment = UIStackViewAlignmentCenter;
    stackView.spacing = 1.0;
    self.navigationItem.titleView = stackView;
    [self updateTitleSubtitle];
}

- (void)updateTitleSubtitle {
    NSMutableArray<NSString *> *components = [NSMutableArray array];
    if (self.onlyConfiguredApps) {
        [components addObject:@"仅已配置"];
    }

    if (self.showSystemApps && self.showTrollApps) {
        [components addObject:@"显示所有"];
    } else if (!self.showSystemApps && self.showTrollApps) {
        [components addObject:@"仅隐藏系统项"];
    } else if (!self.showSystemApps && !self.showTrollApps) {
        [components addObject:@"仅显示普通应用"];
    } else {
        if (self.showSystemApps) {
            [components addObject:@"显示系统项"];
        }
        if (self.showTrollApps) {
            [components addObject:@"显示 Troll 应用"];
        }
    }

    self.subtitleLabel.text = [components componentsJoinedByString:@" · "];
}

- (void)persistFilterStateAndReload {
    NSMutableDictionary *preferences = [NFPreferences loadMutablePreferences];
    preferences[NFPrefOnlyConfiguredAppsKey] = @(self.onlyConfiguredApps);
    preferences[NFPrefShowSystemAppsKey] = @(self.showSystemApps);
    preferences[NFPrefShowTrollAppsKey] = @(self.showTrollApps);

    NSError *error = nil;
    if (![NFPreferences savePreferences:preferences error:&error]) {
        return;
    }

    [self updateFilterButton];
    [self reloadApplicationsFromCache];
}

@end
