#import "NFPRulesListEditorController.h"
#import "../Shared/NFPreferences.h"
#import "NFPRuleTextEditorController.h"
#import "NFPRuleCardCell.h"

@interface NFPRulesListEditorController ()

@property (nonatomic, assign) NFPRuleEditorKind editorKind;
@property (nonatomic, copy) void (^saveHandler)(NSArray *rules);
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *rules;

@end

@implementation NFPRulesListEditorController

- (instancetype)initWithTitle:(NSString *)title
                   editorKind:(NFPRuleEditorKind)editorKind
                        rules:(NSArray *)rules
                  saveHandler:(void (^)(NSArray *))saveHandler {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = title;
        _editorKind = editorKind;
        _rules = [[NFPreferences normalizedRuleEntriesFromArray:rules] mutableCopy];
        _saveHandler = [saveHandler copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.estimatedRowHeight = 88.0;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.allowsSelectionDuringEditing = YES;

    self.navigationItem.leftBarButtonItem = self.editButtonItem;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                            target:self
                                                                                            action:@selector(addTapped:)];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.rules.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (self.editorKind) {
        case NFPRuleEditorKindContains:
            return @"成熟的软件通常把规则作为单独条目维护，而不是让用户在一个大文本框里手工排版。这里支持逐条编辑和从剪贴板批量导入。";
        case NFPRuleEditorKindExclude:
            return @"排除规则建议尽量精确，避免误放行。支持逐条维护和批量导入。";
        default:
            return @"正则适合复杂匹配；保存前会校验语法。需要大量导入时可直接从剪贴板批量导入。";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.rules.count == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"empty"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"empty"];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.detailTextLabel.numberOfLines = 0;
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        }
        cell.textLabel.text = @"暂无规则";
        cell.detailTextLabel.text = @"点右上角 + 新增，或从剪贴板批量导入。";
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    NFPRuleCardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"rule"];
    if (!cell) {
        cell = [[NFPRuleCardCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"rule"];
    }

    NSDictionary *ruleEntry = self.rules[indexPath.row];
    __weak typeof(self) weakSelf = self;
    [cell configureWithRuleEntry:ruleEntry
                      editorKind:self.editorKind
                 validationState:[self validationStateForRuleEntry:ruleEntry]
                   toggleHandler:^(BOOL enabled) {
        [weakSelf setEnabled:enabled forRuleAtIndex:indexPath.row];
    }];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.rules.count == 0) {
        return;
    }

    NSDictionary *ruleEntry = self.rules[indexPath.row];
    [self pushEditorForRuleEntry:ruleEntry atIndex:indexPath.row];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.rules.count > 0;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.rules.count > 0;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (sourceIndexPath.row == destinationIndexPath.row || self.rules.count == 0) {
        return;
    }

    NSDictionary *ruleEntry = self.rules[sourceIndexPath.row];
    [self.rules removeObjectAtIndex:sourceIndexPath.row];
    [self.rules insertObject:ruleEntry atIndex:destinationIndexPath.row];
    [self persistRules];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.rules.count == 0 || self.isEditing) {
        return nil;
    }

    __weak typeof(self) weakSelf = self;
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"删除"
                                                                             handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [weakSelf.rules removeObjectAtIndex:indexPath.row];
        [weakSelf persistRules];
        [weakSelf.tableView reloadData];
        completionHandler(YES);
    }];

    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

- (void)addTapped:(UIBarButtonItem *)sender {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"新增一条"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self pushEditorForRuleEntry:nil atIndex:NSNotFound];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"从剪贴板批量导入"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self importRulesFromPasteboard];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    popover.barButtonItem = sender;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    [self.tableView setEditing:editing animated:animated];
    [self.tableView reloadData];
}

- (void)pushEditorForRuleEntry:(NSDictionary *)ruleEntry atIndex:(NSUInteger)index {
    NSString *placeholder = nil;
    switch (self.editorKind) {
        case NFPRuleEditorKindContains:
            placeholder = @"输入一条需要匹配的消息内容，例如：支付成功";
            break;
        case NFPRuleEditorKindExclude:
            placeholder = @"输入一条需要放行的消息内容，例如：验证码";
            break;
        default:
            placeholder = @"输入一条正则表达式，例如：验证码\\d{4,6}";
            break;
    }

    __weak typeof(self) weakSelf = self;
    NFPRuleTextEditorController *controller = [[NFPRuleTextEditorController alloc] initWithTitle:self.title
                                                                                      placeholder:placeholder
                                                                                      initialRule:[NFPreferences ruleTextFromEntry:ruleEntry]
                                                                                       editorKind:self.editorKind
                                                                                      saveHandler:^(NSString *newRule) {
        [weakSelf saveRule:newRule atIndex:index];
    }];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)saveRule:(NSString *)rule atIndex:(NSUInteger)index {
    NSMutableArray<NSDictionary *> *updatedRules = [self.rules mutableCopy];
    if (index == NSNotFound || index >= updatedRules.count) {
        [updatedRules addObject:[NFPreferences ruleEntryWithText:rule enabled:YES identifier:nil]];
    } else {
        NSDictionary *existingEntry = updatedRules[index];
        updatedRules[index] = [NFPreferences ruleEntryWithText:rule
                                                       enabled:[NFPreferences ruleEntryEnabled:existingEntry]
                                                     identifier:existingEntry[NFRuleEntryIdentifierKey]];
    }

    self.rules = [[NFPreferences normalizedRuleEntriesFromArray:updatedRules] mutableCopy];
    [self persistRules];
    [self.tableView reloadData];
}

- (void)importRulesFromPasteboard {
    NSString *clipboardText = [UIPasteboard generalPasteboard].string;
    if (clipboardText.length == 0) {
        [self presentAlertWithTitle:@"导入失败" message:@"剪贴板里没有可用内容。"];
        return;
    }

    NSMutableArray<NSDictionary *> *combinedRules = [self.rules mutableCopy];
    for (NSString *ruleText in [NFPreferences normalizedRuleLinesFromMultilineString:clipboardText]) {
        [combinedRules addObject:[NFPreferences ruleEntryWithText:ruleText enabled:YES identifier:nil]];
    }

    NSArray<NSDictionary *> *normalizedRules = [NFPreferences normalizedRuleEntriesFromArray:combinedRules];
    if (self.editorKind == NFPRuleEditorKindRegex) {
        NSError *error = [self validateRegexRules:normalizedRules];
        if (error) {
            [self presentAlertWithTitle:@"导入失败" message:error.localizedDescription];
            return;
        }
    }

    self.rules = [normalizedRules mutableCopy];
    [self persistRules];
    [self.tableView reloadData];
}

- (NSError *)validateRegexRules:(NSArray *)rules {
    for (NSDictionary *ruleEntry in [NFPreferences normalizedRuleEntriesFromArray:rules]) {
        NSString *rule = [NFPreferences ruleTextFromEntry:ruleEntry];
        NSError *error = nil;
        [NSRegularExpression regularExpressionWithPattern:rule
                                                  options:NSRegularExpressionCaseInsensitive
                                                    error:&error];
        if (error) {
            return [NSError errorWithDomain:NFPreferencesIdentifier
                                       code:4
                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"正则“%@”无法编译：%@", rule, error.localizedDescription ?: @"未知错误"]}];
        }
    }
    return nil;
}

- (NFPRuleValidationState)validationStateForRuleEntry:(NSDictionary *)ruleEntry {
    if (self.editorKind != NFPRuleEditorKindRegex) {
        return NFPRuleValidationStateNone;
    }

    NSString *rule = [NFPreferences ruleTextFromEntry:ruleEntry];
    NSError *error = nil;
    [NSRegularExpression regularExpressionWithPattern:rule
                                              options:NSRegularExpressionCaseInsensitive
                                                error:&error];
    return error ? NFPRuleValidationStateInvalid : NFPRuleValidationStateValid;
}

- (void)setEnabled:(BOOL)enabled forRuleAtIndex:(NSUInteger)index {
    if (index >= self.rules.count) {
        return;
    }

    NSDictionary *ruleEntry = self.rules[index];
    self.rules[index] = [NFPreferences ruleEntryWithText:[NFPreferences ruleTextFromEntry:ruleEntry]
                                                 enabled:enabled
                                               identifier:ruleEntry[NFRuleEntryIdentifierKey]];
    [self persistRules];
}

- (void)persistRules {
    if (self.saveHandler) {
        self.saveHandler([self.rules copy]);
    }
}

- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
