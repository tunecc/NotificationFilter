#import "NFPPerAppRulesController.h"
#import "../Shared/NFPreferences.h"
#import "NFPLocalization.h"
#import "NFPRulesListEditorController.h"

typedef NS_ENUM(NSInteger, NFPPerAppRulesRow) {
    NFPPerAppRulesRowContains = 0,
    NFPPerAppRulesRowExclude,
    NFPPerAppRulesRowRegex
};

@interface NFPPerAppRulesController ()

@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSDictionary *rules;

@end

@implementation NFPPerAppRulesController

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
        return 1;
    }
    if (section == 1) {
        return 3;
    }
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return NFPLocalizedString(@"PER_APP_RULES_ENABLED_FOOTER");
    }
    if (section == 1) {
        return NFPLocalizedString(@"PER_APP_RULES_LIST_FOOTER");
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
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
    switch (indexPath.row) {
        case NFPPerAppRulesRowContains:
            cell.textLabel.text = NFPLocalizedRuleEditorTitle(NFPRuleEditorKindContains);
            values = self.rules[NFRulesContainsKey];
            break;
        case NFPPerAppRulesRowExclude:
            cell.textLabel.text = NFPLocalizedRuleEditorTitle(NFPRuleEditorKindExclude);
            values = self.rules[NFRulesExcludeKey];
            break;
        default:
            cell.textLabel.text = NFPLocalizedRuleEditorTitle(NFPRuleEditorKindRegex);
            values = self.rules[NFRulesRegexKey];
            break;
    }

    cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)values.count];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 1) {
        NSString *title = nil;
        NSArray<NSString *> *rules = nil;
        NFPRuleEditorKind editorKind = NFPRuleEditorKindContains;

        switch (indexPath.row) {
            case NFPPerAppRulesRowContains:
                title = NFPLocalizedRuleEditorTitle(NFPRuleEditorKindContains);
                rules = self.rules[NFRulesContainsKey];
                editorKind = NFPRuleEditorKindContains;
                break;
            case NFPPerAppRulesRowExclude:
                title = NFPLocalizedRuleEditorTitle(NFPRuleEditorKindExclude);
                rules = self.rules[NFRulesExcludeKey];
                editorKind = NFPRuleEditorKindExclude;
                break;
            default:
                title = NFPLocalizedRuleEditorTitle(NFPRuleEditorKindRegex);
                rules = self.rules[NFRulesRegexKey];
                editorKind = NFPRuleEditorKindRegex;
                break;
        }

        __weak typeof(self) weakSelf = self;
        NFPRulesListEditorController *controller = [[NFPRulesListEditorController alloc] initWithTitle:title
                                                                                             editorKind:editorKind
                                                                                                  rules:rules ?: @[]
                                                                                            saveHandler:^(NSArray<NSString *> *rules) {
            [weakSelf updateRules:rules forRow:indexPath.row];
        }];
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

- (void)toggleChanged:(UISwitch *)sender {
    NSMutableDictionary *mutableRules = [self.rules mutableCopy];
    mutableRules[NFRulesEnabledKey] = @(sender.on);
    [self persistRules:mutableRules];
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

- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
