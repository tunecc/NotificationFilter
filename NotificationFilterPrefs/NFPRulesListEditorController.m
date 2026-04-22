#import "NFPRulesListEditorController.h"
#import "../Shared/NFPreferences.h"
#import "NFPLocalization.h"
#import "NFPRuleTextEditorController.h"
#import "NFPRuleCardCell.h"

@interface NFPRulesListEditorController ()

@property (nonatomic, assign) NFPRuleEditorKind editorKind;
@property (nonatomic, copy) void (^saveHandler)(NSArray *rules);
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *rules;
@property (nonatomic, assign) BOOL editingRules;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedRuleIdentifiers;
@property (nonatomic, strong) UIBarButtonItem *editRulesButton;
@property (nonatomic, strong) UIBarButtonItem *pasteButton;
@property (nonatomic, strong) UIBarButtonItem *addButton;
@property (nonatomic, strong) UIBarButtonItem *deleteButton;

@end

@implementation NFPRulesListEditorController

static NSString *NFPRuleDefaultScopeForEditorKind(NFPRuleEditorKind editorKind) {
    return editorKind == NFPRuleEditorKindContains ? NFRuleScopeMessage : NFRuleScopeAll;
}

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
        _selectedRuleIdentifiers = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.estimatedRowHeight = 88.0;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.navigationItem.leftItemsSupplementBackButton = YES;

    self.editRulesButton = [[UIBarButtonItem alloc] initWithTitle:NFPLocalizedString(@"COMMON_EDIT")
                                                            style:UIBarButtonItemStylePlain
                                                           target:self
                                                           action:@selector(toggleEditingRules)];
    self.navigationItem.leftBarButtonItem = self.editRulesButton;

    self.pasteButton = [[UIBarButtonItem alloc] initWithTitle:NFPLocalizedString(@"COMMON_PASTE")
                                                        style:UIBarButtonItemStylePlain
                                                       target:self
                                                       action:@selector(importFromPasteboardButtonTapped:)];
    self.addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                    target:self
                                                                    action:@selector(addButtonTapped:)];
    self.deleteButton = [[UIBarButtonItem alloc] initWithTitle:NFPLocalizedString(@"COMMON_DELETE")
                                                         style:UIBarButtonItemStylePlain
                                                        target:self
                                                        action:@selector(deleteSelectedRules)];
    [self updateNavigationItems];
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
            return NFPLocalizedString(@"RULES_LIST_CONTAINS_FOOTER");
        case NFPRuleEditorKindExclude:
            return NFPLocalizedString(@"RULES_LIST_EXCLUDE_FOOTER");
        default:
            return NFPLocalizedString(@"RULES_LIST_REGEX_FOOTER");
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
        cell.textLabel.text = NFPLocalizedString(@"RULES_LIST_EMPTY_TITLE");
        cell.detailTextLabel.text = NFPLocalizedString(@"RULES_LIST_EMPTY_DETAIL");
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
                    editingMode:self.editingRules
                       selected:[self.selectedRuleIdentifiers containsObject:ruleEntry[NFRuleEntryIdentifierKey]]
                  toggleHandler:^(BOOL enabled) {
        [weakSelf setEnabled:enabled forRuleAtIndex:indexPath.row];
    } selectionHandler:^{
        [weakSelf toggleSelectionForRuleAtIndex:indexPath.row];
    }];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.rules.count == 0) {
        return;
    }

    if (self.editingRules) {
        [self toggleSelectionForRuleAtIndex:indexPath.row];
        return;
    }

    NSDictionary *ruleEntry = self.rules[indexPath.row];
    [self pushEditorForRuleEntry:ruleEntry atIndex:indexPath.row];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.rules.count > 0 && !self.editingRules;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.rules.count == 0 || self.isEditing) {
        return nil;
    }

    __weak typeof(self) weakSelf = self;
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:NFPLocalizedString(@"COMMON_DELETE")
                                                                             handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [weakSelf.rules removeObjectAtIndex:indexPath.row];
        [weakSelf persistRules];
        [weakSelf.tableView reloadData];
        completionHandler(YES);
    }];

    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

- (void)addButtonTapped:(UIBarButtonItem *)sender {
    [self pushEditorForRuleEntry:nil atIndex:NSNotFound];
}

- (void)importFromPasteboardButtonTapped:(UIBarButtonItem *)sender {
    [self importRulesFromPasteboard];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
}

- (void)pushEditorForRuleEntry:(NSDictionary *)ruleEntry atIndex:(NSUInteger)index {
    NSString *placeholder = nil;
    switch (self.editorKind) {
        case NFPRuleEditorKindContains:
            placeholder = NFPLocalizedString(@"RULES_LIST_CONTAINS_PLACEHOLDER");
            break;
        case NFPRuleEditorKindExclude:
            placeholder = NFPLocalizedString(@"RULES_LIST_EXCLUDE_PLACEHOLDER");
            break;
        default:
            placeholder = NFPLocalizedString(@"RULES_LIST_REGEX_PLACEHOLDER");
            break;
    }

    __weak typeof(self) weakSelf = self;
    NFPRuleTextEditorController *controller = [[NFPRuleTextEditorController alloc] initWithTitle:self.title
                                                                                      placeholder:placeholder
                                                                                      initialRule:[NFPreferences ruleTextFromEntry:ruleEntry]
                                                                                     initialScope:[NFPreferences ruleScopeFromEntry:ruleEntry
                                                                                                                    defaultScope:NFPRuleDefaultScopeForEditorKind(self.editorKind)]
                                                                                       editorKind:self.editorKind
                                                                                      saveHandler:^(NSString *newRule, NSString *scope) {
        [weakSelf saveRule:newRule scope:scope atIndex:index];
    }];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)saveRule:(NSString *)rule scope:(NSString *)scope atIndex:(NSUInteger)index {
    NSMutableArray<NSDictionary *> *updatedRules = [self.rules mutableCopy];
    if (index == NSNotFound || index >= updatedRules.count) {
        [updatedRules addObject:[NFPreferences ruleEntryWithText:rule
                                                         enabled:YES
                                                       identifier:nil
                                                            scope:scope]];
    } else {
        NSDictionary *existingEntry = updatedRules[index];
        updatedRules[index] = [NFPreferences ruleEntryWithText:rule
                                                       enabled:[NFPreferences ruleEntryEnabled:existingEntry]
                                                     identifier:existingEntry[NFRuleEntryIdentifierKey]
                                                          scope:scope];
    }

    self.rules = [[NFPreferences normalizedRuleEntriesFromArray:updatedRules
                                                   defaultScope:NFPRuleDefaultScopeForEditorKind(self.editorKind)] mutableCopy];
    [self persistRules];
    [self.tableView reloadData];
}

- (void)importRulesFromPasteboard {
    NSString *clipboardText = [UIPasteboard generalPasteboard].string;
    if (clipboardText.length == 0) {
        [self presentAlertWithTitle:NFPLocalizedString(@"COMMON_IMPORT_FAILED")
                            message:NFPLocalizedString(@"RULES_LIST_IMPORT_EMPTY_PASTEBOARD_MESSAGE")];
        return;
    }

    NSMutableArray<NSDictionary *> *combinedRules = [self.rules mutableCopy];
    for (NSString *ruleText in [NFPreferences normalizedRuleLinesFromMultilineString:clipboardText]) {
        [combinedRules addObject:[NFPreferences ruleEntryWithText:ruleText
                                                         enabled:YES
                                                       identifier:nil
                                                            scope:NFPRuleDefaultScopeForEditorKind(self.editorKind)]];
    }

    NSArray<NSDictionary *> *normalizedRules = [NFPreferences normalizedRuleEntriesFromArray:combinedRules
                                                                                 defaultScope:NFPRuleDefaultScopeForEditorKind(self.editorKind)];
    if (self.editorKind == NFPRuleEditorKindRegex) {
        NSError *error = [self validateRegexRules:normalizedRules];
        if (error) {
            [self presentAlertWithTitle:NFPLocalizedString(@"COMMON_IMPORT_FAILED") message:error.localizedDescription];
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
                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:NFPLocalizedString(@"REGEX_COMPILE_FAILED_FORMAT"),
                                                                          rule,
                                                                          error.localizedDescription ?: NFPLocalizedString(@"COMMON_UNKNOWN")]}];
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
                                               identifier:ruleEntry[NFRuleEntryIdentifierKey]
                                                    scope:[NFPreferences ruleScopeFromEntry:ruleEntry
                                                                               defaultScope:NFPRuleDefaultScopeForEditorKind(self.editorKind)]];
    [self persistRules];
}

- (void)toggleEditingRules {
    self.editingRules = !self.editingRules;
    if (!self.editingRules) {
        [self.selectedRuleIdentifiers removeAllObjects];
    }
    [self updateNavigationItems];
    [self.tableView reloadData];
}

- (void)toggleSelectionForRuleAtIndex:(NSUInteger)index {
    if (index >= self.rules.count) {
        return;
    }

    NSString *identifier = self.rules[index][NFRuleEntryIdentifierKey];
    if (identifier.length == 0) {
        return;
    }

    if ([self.selectedRuleIdentifiers containsObject:identifier]) {
        [self.selectedRuleIdentifiers removeObject:identifier];
    } else {
        [self.selectedRuleIdentifiers addObject:identifier];
    }

    [self updateNavigationItems];
    [self.tableView reloadData];
}

- (void)deleteSelectedRules {
    if (self.selectedRuleIdentifiers.count == 0) {
        return;
    }

    NSUInteger count = self.selectedRuleIdentifiers.count;
    NSString *message = [NSString stringWithFormat:NFPLocalizedString(@"RULES_LIST_DELETE_CONFIRM_MESSAGE_FORMAT"), (unsigned long)count];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFPLocalizedString(@"COMMON_CONFIRM_DELETE")
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_CANCEL") style:UIAlertActionStyleCancel handler:nil]];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_DELETE")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        NSIndexSet *indexesToDelete = [weakSelf.rules indexesOfObjectsPassingTest:^BOOL(NSDictionary *ruleEntry, NSUInteger idx, BOOL *stop) {
            return [weakSelf.selectedRuleIdentifiers containsObject:ruleEntry[NFRuleEntryIdentifierKey]];
        }];
        if (indexesToDelete.count == 0) {
            return;
        }

        [weakSelf.rules removeObjectsAtIndexes:indexesToDelete];
        [weakSelf.selectedRuleIdentifiers removeAllObjects];
        [weakSelf persistRules];
        [weakSelf toggleEditingRules];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateNavigationItems {
    self.editRulesButton.title = self.editingRules ? NFPLocalizedString(@"COMMON_DONE") : NFPLocalizedString(@"COMMON_EDIT");
    if (self.editingRules) {
        NSUInteger count = self.selectedRuleIdentifiers.count;
        self.title = [NSString stringWithFormat:NFPLocalizedString(@"RULES_LIST_SELECTED_COUNT_TITLE_FORMAT"), (unsigned long)count];
        self.deleteButton.title = count > 0 ? [NSString stringWithFormat:NFPLocalizedString(@"RULES_LIST_DELETE_COUNT_BUTTON_FORMAT"), (unsigned long)count] : NFPLocalizedString(@"COMMON_DELETE");
        self.deleteButton.enabled = count > 0;
        self.navigationItem.rightBarButtonItems = @[self.deleteButton];
    } else {
        self.title = NFPLocalizedRuleEditorTitle(self.editorKind);
        self.navigationItem.rightBarButtonItems = @[self.addButton, self.pasteButton];
    }
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
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
