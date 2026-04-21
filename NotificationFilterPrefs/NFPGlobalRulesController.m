#import "NFPGlobalRulesController.h"
#import "../Shared/NFPreferences.h"
#import "NFPRulesListEditorController.h"

typedef NS_ENUM(NSInteger, NFPGlobalRulesRow) {
    NFPGlobalRulesRowContains = 0,
    NFPGlobalRulesRowExclude,
    NFPGlobalRulesRowRegex
};

@interface NFPGlobalRulesController ()

@property (nonatomic, copy) NSDictionary *rules;

@end

@implementation NFPGlobalRulesController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"全局规则";
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.rules = [NFPreferences globalRulesFromPreferences:[NFPreferences loadPreferences]];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"关闭后，全局规则不会参与匹配。";
    }
    return @"包含和正则命中会拦截通知；排除规则命中会优先放行。";
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

        cell.textLabel.text = @"启用全局规则";
        ((UISwitch *)cell.accessoryView).on = [self.rules[NFRulesEnabledKey] boolValue];
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"rule"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"rule"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    NSArray *values = nil;
    switch (indexPath.row) {
        case NFPGlobalRulesRowContains:
            cell.textLabel.text = @"包含规则";
            values = self.rules[NFRulesContainsKey];
            break;
        case NFPGlobalRulesRowExclude:
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
    if (indexPath.section != 1) {
        return;
    }

    NSString *title = nil;
    NSArray<NSString *> *rules = nil;
    NFPRuleEditorKind editorKind = NFPRuleEditorKindContains;

    switch (indexPath.row) {
        case NFPGlobalRulesRowContains:
            title = @"包含规则";
            rules = self.rules[NFRulesContainsKey];
            editorKind = NFPRuleEditorKindContains;
            break;
        case NFPGlobalRulesRowExclude:
            title = @"排除规则";
            rules = self.rules[NFRulesExcludeKey];
            editorKind = NFPRuleEditorKindExclude;
            break;
        default:
            title = @"正则规则";
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
}

- (void)toggleChanged:(UISwitch *)sender {
    NSMutableDictionary *preferences = [NFPreferences loadMutablePreferences];
    preferences[NFGlobalRulesEnabledKey] = @(sender.on);
    [self persistPreferences:preferences];
}

- (void)updateRules:(NSArray<NSString *> *)rules forRow:(NSInteger)row {
    NSMutableDictionary *preferences = [NFPreferences loadMutablePreferences];
    switch (row) {
        case NFPGlobalRulesRowContains:
            preferences[NFGlobalContainsKey] = rules;
            break;
        case NFPGlobalRulesRowExclude:
            preferences[NFGlobalExcludeKey] = rules;
            break;
        default:
            preferences[NFGlobalRegexKey] = rules;
            break;
    }

    [self persistPreferences:preferences];
}

- (void)persistPreferences:(NSMutableDictionary *)preferences {
    NSError *error = nil;
    if (![NFPreferences savePreferences:preferences error:&error]) {
        [self presentAlertWithTitle:@"保存失败" message:error.localizedDescription ?: @"无法更新全局规则。"];
        return;
    }

    [NFPreferences postPreferencesChangedNotification];
    self.rules = [NFPreferences globalRulesFromPreferences:[NFPreferences loadPreferences]];
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
