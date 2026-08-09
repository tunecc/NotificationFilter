#import "NFPPerAppRulesController.h"
#import "../Shared/NFPreferences.h"
#import "NFPLocalization.h"
#import "NFPNotificationRuleScannerController.h"
#import "NFPRulesListEditorController.h"

typedef NS_ENUM(NSInteger, NFPPerAppRulesRow) {
    NFPPerAppRulesRowContains = 0,
    NFPPerAppRulesRowExclude,
    NFPPerAppRulesRowRegex
};

typedef NS_ENUM(NSInteger, NFPPerAppRulesConfigRow) {
    NFPPerAppRulesConfigRowEnabled = 0,
    NFPPerAppRulesConfigRowLogging,
    NFPPerAppRulesConfigRowMode
};

@interface NFPPerAppRulesController ()

@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSDictionary *rules;

@end

@implementation NFPPerAppRulesController

- (NSArray<NSDictionary *> *)rulesForEditorKind:(NFPRuleEditorKind)editorKind fromRules:(NSDictionary *)rules {
    switch (editorKind) {
        case NFPRuleEditorKindContains:
            return rules[NFRulesContainsKey] ?: @[];
        case NFPRuleEditorKindExclude:
            return rules[NFRulesExcludeKey] ?: @[];
        default:
            return rules[NFRulesRegexKey] ?: @[];
    }
}

- (NSString *)currentRuleMode {
    return [NFPreferences normalizedRulesMode:self.rules[NFRulesModeKey]];
}

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier displayName:(NSString *)displayName {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _bundleIdentifier = [bundleIdentifier copy];
        _displayName = [displayName copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.displayName;
    self.navigationItem.prompt = self.bundleIdentifier;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NFPLocalizedString(@"COMMON_SCAN")
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(scanButtonTapped:)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.rules = [NFPreferences rulesForBundleIdentifier:self.bundleIdentifier
                                         fromPreferences:[NFPreferences loadPreferences]];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return 3;
    }
    if (section == 1) {
        return 3;
    }
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        NSString *mode = [self currentRuleMode];
        NSString *footer = [mode isEqualToString:NFRulesModeWhitelist] ? NFPLocalizedString(@"PER_APP_RULES_ENABLED_FOOTER_WHITELIST") : NFPLocalizedString(@"PER_APP_RULES_ENABLED_FOOTER_BLACKLIST");
        if (![NFPreferences loggingEnabledForPreferences:[NFPreferences loadPreferences]]) {
            footer = [NSString stringWithFormat:@"%@\n%@",
                                            footer,
                                            NFPLocalizedString(@"LOGS_APP_LOG_GLOBAL_OFF_FOOTER")];
        }
        return footer;
    }
    if (section == 1) {
        return NFPLocalizedString(@"PER_APP_RULES_LIST_FOOTER");
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        if (indexPath.row == NFPPerAppRulesConfigRowLogging) {
            UITableViewCell *loggingCell = [tableView dequeueReusableCellWithIdentifier:@"logging-toggle"];
            if (!loggingCell) {
                loggingCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"logging-toggle"];
                UISwitch *loggingSwitch = [[UISwitch alloc] init];
                [loggingSwitch addTarget:self action:@selector(loggingToggleChanged:) forControlEvents:UIControlEventValueChanged];
                loggingCell.accessoryView = loggingSwitch;
                loggingCell.selectionStyle = UITableViewCellSelectionStyleNone;
            }

            loggingCell.textLabel.text = NFPLocalizedString(@"PER_APP_RULES_LOG_ENABLED");
            NSDictionary *preferences = [NFPreferences loadPreferences];
            BOOL disabled = [NFPreferences isLoggingDisabledForBundleIdentifier:self.bundleIdentifier
                                                                    preferences:preferences];
            ((UISwitch *)loggingCell.accessoryView).on = !disabled;
            return loggingCell;
        }
        if (indexPath.row == NFPPerAppRulesConfigRowMode) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"mode"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"mode"];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }

            NSString *mode = [self currentRuleMode];
            cell.textLabel.text = NFPLocalizedString(@"PER_APP_RULES_MODE");
            cell.detailTextLabel.text = [mode isEqualToString:NFRulesModeWhitelist] ? NFPLocalizedString(@"PER_APP_RULES_MODE_WHITELIST") : NFPLocalizedString(@"PER_APP_RULES_MODE_BLACKLIST");
            return cell;
        }

        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"toggle"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"toggle"];
            UISwitch *toggle = [[UISwitch alloc] init];
            [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }

        cell.textLabel.text = NFPLocalizedString(@"PER_APP_RULES_ENABLE");
        ((UISwitch *)cell.accessoryView).on = [self.rules[NFRulesEnabledKey] boolValue];
        return cell;
    }

    if (indexPath.section == 2) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"delete"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"delete"];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.textColor = [UIColor systemRedColor];
        }

        cell.textLabel.text = NFPLocalizedString(@"PER_APP_RULES_DELETE");
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"rule"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"rule"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    NSArray *values = nil;
    NSString *mode = [self currentRuleMode];
    switch (indexPath.row) {
        case NFPPerAppRulesRowContains:
            cell.textLabel.text = NFPLocalizedRuleEditorTitleForMode(NFPRuleEditorKindContains, mode);
            values = self.rules[NFRulesContainsKey];
            break;
        case NFPPerAppRulesRowExclude:
            cell.textLabel.text = NFPLocalizedRuleEditorTitleForMode(NFPRuleEditorKindExclude, mode);
            values = self.rules[NFRulesExcludeKey];
            break;
        default:
            cell.textLabel.text = NFPLocalizedRuleEditorTitleForMode(NFPRuleEditorKindRegex, mode);
            values = self.rules[NFRulesRegexKey];
            break;
    }

    cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)values.count];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0 && indexPath.row == NFPPerAppRulesConfigRowLogging) {
        return;
    }

    if (indexPath.section == 0 && indexPath.row == NFPPerAppRulesConfigRowMode) {
        [self presentRuleModePickerFromIndexPath:indexPath];
        return;
    }

    if (indexPath.section == 1) {
        NSString *title = nil;
        NSArray<NSString *> *rules = nil;
        NFPRuleEditorKind editorKind = NFPRuleEditorKindContains;

        NSString *mode = [self currentRuleMode];
        switch (indexPath.row) {
            case NFPPerAppRulesRowContains:
                title = NFPLocalizedRuleEditorTitleForMode(NFPRuleEditorKindContains, mode);
                rules = self.rules[NFRulesContainsKey];
                editorKind = NFPRuleEditorKindContains;
                break;
            case NFPPerAppRulesRowExclude:
                title = NFPLocalizedRuleEditorTitleForMode(NFPRuleEditorKindExclude, mode);
                rules = self.rules[NFRulesExcludeKey];
                editorKind = NFPRuleEditorKindExclude;
                break;
            default:
                title = NFPLocalizedRuleEditorTitleForMode(NFPRuleEditorKindRegex, mode);
                rules = self.rules[NFRulesRegexKey];
                editorKind = NFPRuleEditorKindRegex;
                break;
        }

        __weak typeof(self) weakSelf = self;
        NFPScannedRuleMergeHandler mergeHandler = nil;
        NFPRulesReloadHandler reloadHandler = nil;
        if (editorKind != NFPRuleEditorKindRegex) {
            mergeHandler = ^BOOL(NFPRuleEditorKind targetKind, NSArray<NSDictionary *> *entries, NSError **error) {
                return [weakSelf appendScannedRuleEntries:entries toEditorKind:targetKind error:error];
            };
            reloadHandler = ^NSArray<NSDictionary *> * (NFPRuleEditorKind targetKind) {
                NSDictionary *latestRules = [NFPreferences rulesForBundleIdentifier:weakSelf.bundleIdentifier
                                                                     fromPreferences:[NFPreferences loadPreferences]];
                return [weakSelf rulesForEditorKind:targetKind fromRules:latestRules];
            };
        }

        NFPRulesListEditorController *controller = [[NFPRulesListEditorController alloc] initWithTitle:title
                                                                                             editorKind:editorKind
                                                                                                  rules:rules ?: @[]
                                                                                       bundleIdentifier:self.bundleIdentifier
                                                                                            displayName:self.displayName
                                                                                               ruleMode:mode
                                                                                            saveHandler:^(NSArray<NSString *> *rules) {
            [weakSelf updateRules:rules forRow:indexPath.row];
        }
                                                                                 scannedRuleMergeHandler:mergeHandler
                                                                                       rulesReloadHandler:reloadHandler];
        [self.navigationController pushViewController:controller animated:YES];
        return;
    }

    if (indexPath.section == 2) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFPLocalizedString(@"PER_APP_RULES_DELETE_TITLE")
                                                                       message:NFPLocalizedString(@"PER_APP_RULES_DELETE_MESSAGE")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_CANCEL") style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_DELETE")
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *action) {
            [self deleteCurrentRules];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)presentRuleModePickerFromIndexPath:(NSIndexPath *)indexPath {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFPLocalizedString(@"PER_APP_RULES_MODE")
                                                                   message:NFPLocalizedString(@"PER_APP_RULES_MODE_MESSAGE")
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"PER_APP_RULES_MODE_BLACKLIST")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self updateRuleMode:NFRulesModeBlacklist];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"PER_APP_RULES_MODE_WHITELIST")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self updateRuleMode:NFRulesModeWhitelist];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_CANCEL") style:UIAlertActionStyleCancel handler:nil]];

    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    alert.popoverPresentationController.sourceView = cell ?: self.tableView;
    alert.popoverPresentationController.sourceRect = cell ? cell.bounds : self.tableView.bounds;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateRuleMode:(NSString *)mode {
    NSMutableDictionary *mutableRules = [self.rules mutableCopy];
    mutableRules[NFRulesModeKey] = [NFPreferences normalizedRulesMode:mode];
    [self persistRules:mutableRules];
}

- (void)toggleChanged:(UISwitch *)sender {
    NSMutableDictionary *mutableRules = [self.rules mutableCopy];
    mutableRules[NFRulesEnabledKey] = @(sender.on);
    [self persistRules:mutableRules];
}

- (void)loggingToggleChanged:(UISwitch *)sender {
    [NFPreferences setLoggingDisabled:!sender.on
                    forBundleIdentifier:self.bundleIdentifier];
    [self.tableView reloadData];
}

- (void)scanButtonTapped:(UIBarButtonItem *)sender {
    __weak typeof(self) weakSelf = self;
    NFPNotificationRuleScannerController *controller = [[NFPNotificationRuleScannerController alloc] initWithBundleIdentifier:self.bundleIdentifier
                                                                                                                  displayName:self.displayName
                                                                                                              initialRuleKind:NFPRuleEditorKindContains
                                                                                                                      ruleMode:[self currentRuleMode]
                                                                                                         returnViewController:self
                                                                                                                   returnMode:NFPNotificationRuleTokenReturnModeTargetViewController
                                                                                                                commitHandler:^BOOL(NFPRuleEditorKind targetKind, NSArray<NSDictionary *> *entries, NSError **error) {
        return [weakSelf appendScannedRuleEntries:entries toEditorKind:targetKind error:error];
    }];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)updateRules:(NSArray<NSString *> *)rules forRow:(NSInteger)row {
    NSMutableDictionary *mutableRules = [self.rules mutableCopy];
    switch (row) {
        case NFPPerAppRulesRowContains:
            mutableRules[NFRulesContainsKey] = rules;
            break;
        case NFPPerAppRulesRowExclude:
            mutableRules[NFRulesExcludeKey] = rules;
            break;
        default:
            mutableRules[NFRulesRegexKey] = rules;
            break;
    }

    [self persistRules:mutableRules];
}

- (void)deleteCurrentRules {
    NSMutableDictionary *preferences = [NFPreferences loadMutablePreferences];
    NSMutableDictionary *appRules = [preferences[NFAppRulesKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    [appRules removeObjectForKey:self.bundleIdentifier];
    preferences[NFAppRulesKey] = appRules;

    NSError *error = nil;
    if (![NFPreferences savePreferences:preferences error:&error]) {
        [self presentAlertWithTitle:NFPLocalizedString(@"COMMON_DELETE_FAILED")
                            message:error.localizedDescription ?: NFPLocalizedString(@"PER_APP_RULES_DELETE_FAILED_MESSAGE")];
        return;
    }

    [NFPreferences postPreferencesChangedNotification];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)persistRules:(NSDictionary *)rules {
    NSMutableDictionary *preferences = [NFPreferences loadMutablePreferences];
    NSMutableDictionary *appRules = [preferences[NFAppRulesKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    appRules[self.bundleIdentifier] = [NFPreferences normalizedRulesDictionaryFromRawDictionary:rules];
    preferences[NFAppRulesKey] = appRules;

    NSError *error = nil;
    if (![NFPreferences savePreferences:preferences error:&error]) {
        [self presentAlertWithTitle:NFPLocalizedString(@"COMMON_SAVE_FAILED")
                            message:error.localizedDescription ?: NFPLocalizedString(@"PER_APP_RULES_SAVE_FAILED_MESSAGE")];
        return;
    }

    [NFPreferences postPreferencesChangedNotification];
    self.rules = [NFPreferences rulesForBundleIdentifier:self.bundleIdentifier
                                         fromPreferences:[NFPreferences loadPreferences]];
    [self.tableView reloadData];
}

- (BOOL)appendScannedRuleEntries:(NSArray<NSDictionary *> *)entries
                    toEditorKind:(NFPRuleEditorKind)editorKind
                           error:(NSError **)error {
    if (entries.count == 0) {
        return YES;
    }

    NSMutableDictionary *mutableRules = [self.rules mutableCopy];
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

    NSMutableArray *combinedEntries = [NSMutableArray arrayWithArray:mutableRules[rulesKey] ?: @[]];
    [combinedEntries addObjectsFromArray:entries];
    mutableRules[rulesKey] = [NFPreferences normalizedRuleEntriesFromArray:combinedEntries
                                                              defaultScope:defaultScope];

    NSMutableDictionary *preferences = [NFPreferences loadMutablePreferences];
    NSMutableDictionary *appRules = [preferences[NFAppRulesKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    appRules[self.bundleIdentifier] = [NFPreferences normalizedRulesDictionaryFromRawDictionary:mutableRules];
    preferences[NFAppRulesKey] = appRules;

    BOOL saved = [NFPreferences savePreferences:preferences error:error];
    if (!saved) {
        return NO;
    }

    [NFPreferences postPreferencesChangedNotification];
    self.rules = [NFPreferences rulesForBundleIdentifier:self.bundleIdentifier
                                         fromPreferences:[NFPreferences loadPreferences]];
    return YES;
}

- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
