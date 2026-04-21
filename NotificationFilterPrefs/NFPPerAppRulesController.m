#import "NFPPerAppRulesController.h"
#import "../Shared/NFPreferences.h"
#import "NFPMultilineRulesEditorController.h"

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
        return @"关闭后，该应用规则不会参与匹配。";
    }
    if (section == 1) {
        return @"只有该应用的通知会使用这里的规则，并与全局规则一起参与判断。";
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

        cell.textLabel.text = @"启用该应用规则";
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

        cell.textLabel.text = @"删除该应用规则";
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
            cell.textLabel.text = @"包含规则";
            values = self.rules[NFRulesContainsKey];
            break;
        case NFPPerAppRulesRowExclude:
            cell.textLabel.text = @"排除规则";
            values = self.rules[NFRulesExcludeKey];
            break;
        default:
            cell.textLabel.text = @"正则规则";
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
        NSString *multilineText = nil;
        NFPRuleEditorKind editorKind = NFPRuleEditorKindContains;

        switch (indexPath.row) {
            case NFPPerAppRulesRowContains:
                title = @"包含规则";
                multilineText = [NFPreferences multilineStringFromRuleLines:self.rules[NFRulesContainsKey]];
                editorKind = NFPRuleEditorKindContains;
                break;
            case NFPPerAppRulesRowExclude:
                title = @"排除规则";
                multilineText = [NFPreferences multilineStringFromRuleLines:self.rules[NFRulesExcludeKey]];
                editorKind = NFPRuleEditorKindExclude;
                break;
            default:
                title = @"正则规则";
                multilineText = [NFPreferences multilineStringFromRuleLines:self.rules[NFRulesRegexKey]];
                editorKind = NFPRuleEditorKindRegex;
                break;
        }

        __weak typeof(self) weakSelf = self;
        NFPMultilineRulesEditorController *controller = [[NFPMultilineRulesEditorController alloc] initWithTitle:title
                                                                                                       initialText:multilineText
                                                                                                        editorKind:editorKind
                                                                                                       saveHandler:^(NSArray<NSString *> *rules) {
            [weakSelf updateRules:rules forRow:indexPath.row];
        }];
        [self.navigationController pushViewController:controller animated:YES];
        return;
    }

    if (indexPath.section == 2) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除规则"
                                                                       message:@"会移除该应用的所有过滤设置。"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"删除"
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
        [self presentAlertWithTitle:@"删除失败" message:error.localizedDescription ?: @"无法删除该应用规则。"];
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
        [self presentAlertWithTitle:@"保存失败" message:error.localizedDescription ?: @"无法保存应用规则。"];
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
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
