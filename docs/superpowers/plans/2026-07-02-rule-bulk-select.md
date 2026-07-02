# Rule Bulk Select Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add bulk selection to rule editing and section-level select-all to notification token picking, while saving cross-section token selections as separate scoped rules.

**Architecture:** Keep the change inside the existing PreferenceBundle controllers and token builder. `NFPNotificationRuleTokenBuilder` owns save semantics, `NFPRulesListEditorController` owns rule-list selection state, and `NFPNotificationRuleTokenPickerController` owns token-section selection UI.

**Tech Stack:** Objective-C, UIKit, Foundation, Theos PreferenceBundle, existing assert-based Objective-C tests.

## Global Constraints

- Keep the existing rule storage format and `scope` values compatible.
- Do not change the tweak rule engine or notification matching behavior.
- Do not introduce new dependencies or a new toolbar/editing architecture.
- Localize new visible strings in both `NotificationFilterPrefs/Resources/en.lproj/Localizable.strings` and `NotificationFilterPrefs/Resources/zh-Hans.lproj/Localizable.strings`.
- Preserve existing single-tap token selection, drag token selection, and save failure behavior.

---

## File Structure

- Modify `NotificationFilterPrefs/NFPNotificationRuleTokenBuilder.m`: change `ruleEntriesFromTokenSections:selectedTokenKeys:defaultScope:` so each selected section returns its own rule entry.
- Modify `tests/NFPNotificationRuleTokenBuilderTests.m`: replace the old mixed-scope assertion and add coverage for title+message returning two scoped entries.
- Modify `NotificationFilterPrefs/NFPRulesListEditorController.m`: add one `selectAllRulesButton`, toggle all selectable rule IDs, and update nav button state.
- Modify `NotificationFilterPrefs/NFPNotificationRuleTokenPickerController.m`: render each token section with a title row plus select-all button, and add helpers for section-level token selection.
- Modify `NotificationFilterPrefs/Resources/en.lproj/Localizable.strings`: add `COMMON_SELECT_ALL` and `COMMON_DESELECT_ALL`.
- Modify `NotificationFilterPrefs/Resources/zh-Hans.lproj/Localizable.strings`: add `COMMON_SELECT_ALL` and `COMMON_DESELECT_ALL`.

---

### Task 1: Token Builder Saves One Rule Per Selected Section

**Files:**
- Modify: `tests/NFPNotificationRuleTokenBuilderTests.m`
- Modify: `NotificationFilterPrefs/NFPNotificationRuleTokenBuilder.m`

**Interfaces:**
- Consumes: existing `+selectionKeyForScope:tokenIndex:token:` and `+ruleEntryWithText:enabled:identifier:scope:`.
- Produces: `+ruleEntriesFromTokenSections:selectedTokenKeys:defaultScope:` now returns `NSArray<NSDictionary *> *` with one rule entry per selected section, preserving section order.

- [ ] **Step 1: Write the failing mixed-section test**

In `tests/NFPNotificationRuleTokenBuilderTests.m`, replace the current `mixedScopeSelection` assertion block with this block:

```objc
        NSSet<NSString *> *mixedScopeSelection = [NSSet setWithObjects:
            [NFPNotificationRuleTokenBuilder selectionKeyForScope:titleScope tokenIndex:0 token:titleTokens[0]],
            [NFPNotificationRuleTokenBuilder selectionKeyForScope:titleScope tokenIndex:1 token:titleTokens[1]],
            [NFPNotificationRuleTokenBuilder selectionKeyForScope:messageScope tokenIndex:2 token:messageTokens[2]],
            nil];
        NSArray<NSDictionary *> *mixedScopeEntries = [NFPNotificationRuleTokenBuilder ruleEntriesFromTokenSections:sections
                                                                                                 selectedTokenKeys:mixedScopeSelection
                                                                                                      defaultScope:NFRuleScopeMessage];
        NFAssert(mixedScopeEntries.count == 2, @"cross-scope selection should create one rule per selected section");
        NFAssert([mixedScopeEntries[0][NFRuleEntryTextKey] isEqualToString:@"限时"], @"title selected pieces should be connected inside the title rule");
        NFAssert([mixedScopeEntries[0][NFRuleEntryScopeKey] isEqualToString:NFRuleScopeTitle], @"title selection should keep title scope");
        NFAssert([mixedScopeEntries[1][NFRuleEntryTextKey] isEqualToString:@"到"], @"message selected pieces should be connected inside the message rule");
        NFAssert([mixedScopeEntries[1][NFRuleEntryScopeKey] isEqualToString:NFRuleScopeMessage], @"message selection should keep message scope");
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
clang -fobjc-arc -fmodules -framework Foundation tests/NFPNotificationRuleTokenBuilderTests.m NotificationFilterPrefs/NFPNotificationRuleTokenBuilder.m -o /tmp/NFPNotificationRuleTokenBuilderTests && /tmp/NFPNotificationRuleTokenBuilderTests
```

Expected: process exits with an exception containing `cross-scope selection should create one rule per selected section`.

- [ ] **Step 3: Implement per-section rule entry generation**

In `NotificationFilterPrefs/NFPNotificationRuleTokenBuilder.m`, replace `+ruleEntriesFromTokenSections:selectedTokenKeys:defaultScope:` with:

```objc
+ (NSArray<NSDictionary *> *)ruleEntriesFromTokenSections:(NSArray<NSDictionary *> *)tokenSections
                                         selectedTokenKeys:(NSSet<NSString *> *)selectedTokenKeys
                                             defaultScope:(NSString *)defaultScope {
    if (selectedTokenKeys.count == 0) {
        return @[];
    }

    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];

    for (NSDictionary *section in tokenSections) {
        NSString *scope = [section[NFPNotificationRuleTokenSectionScopeKey] isKindOfClass:[NSString class]] ? section[NFPNotificationRuleTokenSectionScopeKey] : defaultScope;
        NSArray<NSString *> *tokens = [section[NFPNotificationRuleTokenSectionTokensKey] isKindOfClass:[NSArray class]] ? section[NFPNotificationRuleTokenSectionTokensKey] : @[];
        NSMutableArray<NSString *> *selectedTokens = [NSMutableArray array];

        for (NSUInteger tokenIndex = 0; tokenIndex < tokens.count; tokenIndex++) {
            NSString *token = tokens[tokenIndex];
            NSString *selectionKey = [self selectionKeyForScope:scope tokenIndex:tokenIndex token:token];
            if ([selectedTokenKeys containsObject:selectionKey]) {
                [selectedTokens addObject:token];
            }
        }

        NSString *ruleText = [selectedTokens componentsJoinedByString:@""];
        if (ruleText.length == 0) {
            continue;
        }

        [entries addObject:[NFPreferences ruleEntryWithText:ruleText
                                                    enabled:YES
                                                  identifier:nil
                                                       scope:scope ?: defaultScope ?: NFRuleScopeMessage]];
    }

    return entries;
}
```

- [ ] **Step 4: Run the token builder test and verify it passes**

Run:

```bash
clang -fobjc-arc -fmodules -framework Foundation tests/NFPNotificationRuleTokenBuilderTests.m NotificationFilterPrefs/NFPNotificationRuleTokenBuilder.m -o /tmp/NFPNotificationRuleTokenBuilderTests && /tmp/NFPNotificationRuleTokenBuilderTests
```

Expected: command exits `0` with no output.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
git add tests/NFPNotificationRuleTokenBuilderTests.m NotificationFilterPrefs/NFPNotificationRuleTokenBuilder.m
git commit -m "fix: save scanned tokens by scope"
```

---

### Task 2: Rule List Select All and Deselect All

**Files:**
- Modify: `NotificationFilterPrefs/NFPRulesListEditorController.m`
- Modify: `NotificationFilterPrefs/Resources/en.lproj/Localizable.strings`
- Modify: `NotificationFilterPrefs/Resources/zh-Hans.lproj/Localizable.strings`

**Interfaces:**
- Consumes: existing `editingRules`, `selectedRuleIdentifiers`, `updateNavigationItems`, `toggleEditingRules`, and `deleteSelectedRules`.
- Produces: `-toggleSelectAllRules`, `-allSelectableRulesSelected`, and `-selectableRuleIdentifiers` used only inside `NFPRulesListEditorController`.
- Navigation behavior: in edit mode the left custom item is select-all/deselect-all; the supplemented back button remains available, and successful deletion exits edit mode through the existing `toggleEditingRules` path.

- [ ] **Step 1: Add localized select-all strings**

In `NotificationFilterPrefs/Resources/en.lproj/Localizable.strings`, add after `"COMMON_DELETE" = "Delete";`:

```text
"COMMON_SELECT_ALL" = "Select All";
"COMMON_DESELECT_ALL" = "Deselect All";
```

In `NotificationFilterPrefs/Resources/zh-Hans.lproj/Localizable.strings`, add after `"COMMON_DELETE" = "删除";`:

```text
"COMMON_SELECT_ALL" = "全选";
"COMMON_DESELECT_ALL" = "取消全选";
```

- [ ] **Step 2: Add the select-all button property**

In `NotificationFilterPrefs/NFPRulesListEditorController.m`, add this property next to `editRulesButton`:

```objc
@property (nonatomic, strong) UIBarButtonItem *selectAllRulesButton;
```

- [ ] **Step 3: Create the button in `viewDidLoad`**

After `self.editRulesButton = ...`, add:

```objc
    self.selectAllRulesButton = [[UIBarButtonItem alloc] initWithTitle:NFPLocalizedString(@"COMMON_SELECT_ALL")
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(toggleSelectAllRules)];
```

- [ ] **Step 4: Add selectable rule helpers**

Add these methods before `-toggleEditingRules`:

```objc
- (NSArray<NSString *> *)selectableRuleIdentifiers {
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
    for (NSDictionary *ruleEntry in self.rules) {
        NSString *identifier = ruleEntry[NFRuleEntryIdentifierKey];
        if (identifier.length > 0) {
            [identifiers addObject:identifier];
        }
    }
    return identifiers;
}

- (BOOL)allSelectableRulesSelected {
    NSArray<NSString *> *identifiers = [self selectableRuleIdentifiers];
    if (identifiers.count == 0) {
        return NO;
    }

    for (NSString *identifier in identifiers) {
        if (![self.selectedRuleIdentifiers containsObject:identifier]) {
            return NO;
        }
    }
    return YES;
}

- (void)toggleSelectAllRules {
    NSArray<NSString *> *identifiers = [self selectableRuleIdentifiers];
    if (identifiers.count == 0) {
        return;
    }

    if ([self allSelectableRulesSelected]) {
        [self.selectedRuleIdentifiers removeAllObjects];
    } else {
        [self.selectedRuleIdentifiers unionSet:[NSSet setWithArray:identifiers]];
    }

    [self updateNavigationItems];
    [self.tableView reloadData];
}
```

- [ ] **Step 5: Update editing navigation state**

In `-updateNavigationItems`, replace the `if (self.editingRules) { ... }` branch with:

```objc
    if (self.editingRules) {
        NSUInteger count = self.selectedRuleIdentifiers.count;
        BOOL allSelected = [self allSelectableRulesSelected];
        self.title = [NSString stringWithFormat:NFPLocalizedString(@"RULES_LIST_SELECTED_COUNT_TITLE_FORMAT"), (unsigned long)count];
        self.selectAllRulesButton.title = allSelected ? NFPLocalizedString(@"COMMON_DESELECT_ALL") : NFPLocalizedString(@"COMMON_SELECT_ALL");
        self.selectAllRulesButton.enabled = [self selectableRuleIdentifiers].count > 0;
        self.deleteButton.title = count > 0 ? [NSString stringWithFormat:NFPLocalizedString(@"RULES_LIST_DELETE_COUNT_BUTTON_FORMAT"), (unsigned long)count] : NFPLocalizedString(@"COMMON_DELETE");
        self.deleteButton.enabled = count > 0;
        self.navigationItem.leftBarButtonItem = self.selectAllRulesButton;
        self.navigationItem.rightBarButtonItems = @[self.deleteButton];
    } else {
        self.title = NFPLocalizedRuleEditorTitleForMode(self.editorKind, self.ruleMode);
        self.navigationItem.leftBarButtonItem = self.editRulesButton;
        if (self.scanButton) {
            self.navigationItem.rightBarButtonItems = @[self.addButton, self.scanButton];
        } else {
            self.navigationItem.rightBarButtonItems = @[self.addButton];
        }
    }
```

- [ ] **Step 6: Build the PreferenceBundle**

Run:

```bash
make package-debug-rootless
```

Expected: Theos completes and creates a debug rootless package.

- [ ] **Step 7: Commit Task 2**

Run:

```bash
git add NotificationFilterPrefs/NFPRulesListEditorController.m NotificationFilterPrefs/Resources/en.lproj/Localizable.strings NotificationFilterPrefs/Resources/zh-Hans.lproj/Localizable.strings
git commit -m "feat: add rule list select all"
```

---

### Task 3: Token Picker Section Select All

**Files:**
- Modify: `NotificationFilterPrefs/NFPNotificationRuleTokenPickerController.m`

**Interfaces:**
- Consumes: existing `tokenSections`, `selectedTokenKeys`, `rebuildTokenButtons`, `enumerateTokenButtonsUsingBlock:`, and `updateAppearanceForTokenButton:selected:`.
- Produces: section select buttons keyed by token section scope, plus helpers to toggle and refresh each section.

- [ ] **Step 1: Add section button storage**

In `NFPNotificationRuleTokenPickerController`'s private interface, add:

```objc
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIButton *> *sectionSelectButtons;
```

In the initializer, after `_dragToggledTokenKeys = [NSMutableSet set];`, add:

```objc
        _sectionSelectButtons = [NSMutableDictionary dictionary];
```

- [ ] **Step 2: Reset section buttons during rebuild**

At the start of `-rebuildTokenButtons`, after removing arranged subviews, add:

```objc
    [self.sectionSelectButtons removeAllObjects];
```

- [ ] **Step 3: Replace section label creation with a header row**

In `-rebuildTokenButtons`, replace the `UILabel *sectionLabel = ... [self.tokenStackView addArrangedSubview:sectionLabel];` block with:

```objc
        UIStackView *sectionHeader = [[UIStackView alloc] init];
        sectionHeader.axis = UILayoutConstraintAxisHorizontal;
        sectionHeader.alignment = UIStackViewAlignmentCenter;
        sectionHeader.spacing = 8.0;

        UILabel *sectionLabel = [[UILabel alloc] init];
        sectionLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
        sectionLabel.textColor = [UIColor secondaryLabelColor];
        sectionLabel.text = NFPLocalizedScopeName(scope);
        [sectionHeader addArrangedSubview:sectionLabel];

        UIView *spacer = [[UIView alloc] init];
        [sectionHeader addArrangedSubview:spacer];

        UIButton *selectButton = [UIButton buttonWithType:UIButtonTypeSystem];
        selectButton.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
        selectButton.accessibilityIdentifier = scope;
        [selectButton addTarget:self action:@selector(sectionSelectButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [sectionHeader addArrangedSubview:selectButton];

        self.sectionSelectButtons[scope ?: @""] = selectButton;
        [self.tokenStackView addArrangedSubview:sectionHeader];
```

- [ ] **Step 4: Add section selection helpers**

Add these methods before `-tokenTapped:`:

```objc
- (NSArray<NSString *> *)selectionKeysForSectionScope:(NSString *)scope {
    NSMutableArray<NSString *> *selectionKeys = [NSMutableArray array];
    for (NSDictionary *section in self.tokenSections) {
        NSString *sectionScope = [section[NFPNotificationRuleTokenSectionScopeKey] isKindOfClass:[NSString class]] ? section[NFPNotificationRuleTokenSectionScopeKey] : @"";
        if (![sectionScope isEqualToString:scope ?: @""]) {
            continue;
        }

        NSArray<NSString *> *tokens = [section[NFPNotificationRuleTokenSectionTokensKey] isKindOfClass:[NSArray class]] ? section[NFPNotificationRuleTokenSectionTokensKey] : @[];
        for (NSUInteger tokenIndex = 0; tokenIndex < tokens.count; tokenIndex++) {
            [selectionKeys addObject:[NFPNotificationRuleTokenBuilder selectionKeyForScope:sectionScope tokenIndex:tokenIndex token:tokens[tokenIndex]]];
        }
    }
    return selectionKeys;
}

- (BOOL)sectionScopeIsFullySelected:(NSString *)scope {
    NSArray<NSString *> *selectionKeys = [self selectionKeysForSectionScope:scope];
    if (selectionKeys.count == 0) {
        return NO;
    }

    for (NSString *selectionKey in selectionKeys) {
        if (![self.selectedTokenKeys containsObject:selectionKey]) {
            return NO;
        }
    }
    return YES;
}

- (void)sectionSelectButtonTapped:(UIButton *)sender {
    NSString *scope = sender.accessibilityIdentifier ?: @"";
    NSArray<NSString *> *selectionKeys = [self selectionKeysForSectionScope:scope];
    if (selectionKeys.count == 0) {
        return;
    }

    if ([self sectionScopeIsFullySelected:scope]) {
        [self.selectedTokenKeys minusSet:[NSSet setWithArray:selectionKeys]];
    } else {
        [self.selectedTokenKeys unionSet:[NSSet setWithArray:selectionKeys]];
    }

    [self emitTokenSelectionFeedback];
    [self updateAllTokenButtonAppearances];
    [self updateSectionSelectButtons];
}

- (void)updateAllTokenButtonAppearances {
    [self enumerateTokenButtonsUsingBlock:^(NFPTokenButton *button, BOOL *stop) {
        [self updateAppearanceForTokenButton:button selected:[self.selectedTokenKeys containsObject:button.accessibilityIdentifier]];
    }];
}

- (void)updateSectionSelectButtons {
    [self.sectionSelectButtons enumerateKeysAndObjectsUsingBlock:^(NSString *scope, UIButton *button, BOOL *stop) {
        BOOL selected = [self sectionScopeIsFullySelected:scope];
        [button setTitle:NFPLocalizedString(selected ? @"COMMON_DESELECT_ALL" : @"COMMON_SELECT_ALL") forState:UIControlStateNormal];
    }];
}
```

- [ ] **Step 5: Refresh section buttons after rebuilding and token changes**

At the end of `-rebuildTokenButtons`, add:

```objc
    [self updateSectionSelectButtons];
```

At the end of `-toggleTokenButton:trackingCurrentDrag:`, after `updateAppearanceForTokenButton:selected:`, add:

```objc
    [self updateSectionSelectButtons];
```

- [ ] **Step 6: Run token builder test and build**

Run:

```bash
clang -fobjc-arc -fmodules -framework Foundation tests/NFPNotificationRuleTokenBuilderTests.m NotificationFilterPrefs/NFPNotificationRuleTokenBuilder.m -o /tmp/NFPNotificationRuleTokenBuilderTests && /tmp/NFPNotificationRuleTokenBuilderTests
make package-debug-rootless
```

Expected: token builder test exits `0`; Theos build completes.

- [ ] **Step 7: Commit Task 3**

Run:

```bash
git add NotificationFilterPrefs/NFPNotificationRuleTokenPickerController.m
git commit -m "feat: add token section select all"
```

---

### Task 4: Final Verification and Manual Smoke Notes

**Files:**
- Inspect only: no required file edits.

**Interfaces:**
- Consumes: all changes from Tasks 1-3.
- Produces: verification evidence for final handoff.

- [ ] **Step 1: Run focused regression test**

Run:

```bash
clang -fobjc-arc -fmodules -framework Foundation tests/NFPNotificationRuleTokenBuilderTests.m NotificationFilterPrefs/NFPNotificationRuleTokenBuilder.m -o /tmp/NFPNotificationRuleTokenBuilderTests && /tmp/NFPNotificationRuleTokenBuilderTests
```

Expected: exits `0` with no output.

- [ ] **Step 2: Build debug rootless package**

Run:

```bash
make package-debug-rootless
```

Expected: Theos completes and emits a package artifact.

- [ ] **Step 3: Inspect final diff**

Run:

```bash
git status --short
git diff --stat HEAD
```

Expected: no unstaged or uncommitted changes after Task 3 commits; diff stat is empty.

- [ ] **Step 4: Manual smoke checklist on device or simulator-equivalent Settings UI**

Verify these behaviors:

```text
1. Open an app rule list with multiple keyword rules.
2. Tap Edit; left button shows Select All / 全选 and right button shows disabled Delete.
3. Tap Select All; every selectable rule is selected, title count matches rule count, right button shows Delete(n).
4. Tap Deselect All / 取消全选; selection count returns to 0 and Delete is disabled.
5. Select all again, tap Delete(n), confirm; rules are removed and the editor exits edit mode.
6. Open Scan History, choose a notification with title and body tokens.
7. Tap title section Select All and body section Select All.
8. Save; the app rule list receives separate title-scoped and message-scoped rules.
9. Single token tap and drag selection still update the section button state correctly.
```

- [ ] **Step 5: Leave the worktree clean**

Run:

```bash
git status --short
```

Expected: no output. This final task is verification-only and should not create another commit.
