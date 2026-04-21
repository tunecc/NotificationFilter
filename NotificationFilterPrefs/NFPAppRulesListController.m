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
    self.title = @"应用规则";

    UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    searchController.obscuresBackgroundDuringPresentation = NO;
    searchController.searchResultsUpdater = self;
    searchController.searchBar.placeholder = @"搜索应用名或 Bundle ID";
    self.navigationItem.searchController = searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.searchController = searchController;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadApplications];
}

- (void)reloadApplications {
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
    self.applications = [[NFPAppInfoProvider sharedProvider] sortedApplicationsWithConfiguredBundleIdentifiers:configuredBundleIdentifiers];
    [self applySearchText:self.searchController.searchBar.text];
    [self.tableView reloadData];
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
    return @"已有规则的应用会固定排在顶部。";
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

@end
