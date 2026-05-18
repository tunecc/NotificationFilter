#import "NFPNotificationRuleTokenPickerController.h"
#import "../Shared/NFPreferences.h"
#import "NFPLocalization.h"

static NSString * const NFPTokenTextKey = @"text";
static NSString * const NFPTokenScopesKey = @"scopes";

@interface NFPNotificationRuleTokenPickerController ()

@property (nonatomic, copy) NSDictionary *entry;
@property (nonatomic, copy) NSString *appDisplayName;
@property (nonatomic, assign) NFPRuleEditorKind initialRuleKind;
@property (nonatomic, assign) NFPRuleEditorKind selectedRuleKind;
@property (nonatomic, weak, nullable) UIViewController *returnViewController;
@property (nonatomic, copy) NFPNotificationRuleTokenCommitHandler commitHandler;
@property (nonatomic, copy) NSArray<NSDictionary *> *tokens;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedTokens;
@property (nonatomic, copy) NSString *selectedScope;
@property (nonatomic, strong) UISegmentedControl *ruleKindControl;
@property (nonatomic, strong) UISegmentedControl *scopeControl;
@property (nonatomic, strong) UITextView *summaryTextView;
@property (nonatomic, strong) UIStackView *tokenStackView;

@end

@implementation NFPNotificationRuleTokenPickerController

- (instancetype)initWithNotificationEntry:(NSDictionary *)entry
                          appDisplayName:(NSString *)appDisplayName
                          initialRuleKind:(NFPRuleEditorKind)initialRuleKind
                     returnViewController:(UIViewController *)returnViewController
                            commitHandler:(NFPNotificationRuleTokenCommitHandler)commitHandler {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _entry = [entry copy] ?: @{};
        _appDisplayName = [appDisplayName copy] ?: @"";
        _initialRuleKind = initialRuleKind == NFPRuleEditorKindExclude ? NFPRuleEditorKindExclude : NFPRuleEditorKindContains;
        _selectedRuleKind = initialRuleKind == NFPRuleEditorKindExclude ? NFPRuleEditorKindExclude : NFPRuleEditorKindContains;
        _returnViewController = returnViewController;
        _commitHandler = [commitHandler copy];
        _selectedTokens = [NSMutableSet set];
        _tokens = [self buildTokensFromEntry:_entry];
        _selectedScope = NFRuleScopeAll;
        self.title = NFPLocalizedString(@"RULE_SCAN_PICKER_TITLE");
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NFPLocalizedString(@"COMMON_SAVE")
                                                                               style:UIBarButtonItemStyleDone
                                                                              target:self
                                                                              action:@selector(saveTapped)];

    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scrollView];

    UIStackView *contentStack = [[UIStackView alloc] init];
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.spacing = 16.0;
    [scrollView addSubview:contentStack];

    UILabel *summaryLabel = [[UILabel alloc] init];
    summaryLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    summaryLabel.textColor = [UIColor secondaryLabelColor];
    summaryLabel.text = NFPLocalizedString(@"RULE_SCAN_NOTIFICATION_LABEL");
    [contentStack addArrangedSubview:summaryLabel];

    UITextView *summaryTextView = [[UITextView alloc] init];
    summaryTextView.translatesAutoresizingMaskIntoConstraints = NO;
    summaryTextView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    summaryTextView.textContainerInset = UIEdgeInsetsMake(12.0, 12.0, 12.0, 12.0);
    summaryTextView.layer.cornerRadius = 14.0;
    summaryTextView.editable = NO;
    summaryTextView.scrollEnabled = NO;
    summaryTextView.font = [UIFont systemFontOfSize:15.0];
    summaryTextView.text = [self notificationSummaryText];
    [contentStack addArrangedSubview:summaryTextView];
    self.summaryTextView = summaryTextView;

    UILabel *ruleTypeLabel = [[UILabel alloc] init];
    ruleTypeLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    ruleTypeLabel.textColor = [UIColor secondaryLabelColor];
    ruleTypeLabel.text = NFPLocalizedString(@"RULE_SCAN_RULE_TYPE_LABEL");
    [contentStack addArrangedSubview:ruleTypeLabel];

    UISegmentedControl *ruleKindControl = [[UISegmentedControl alloc] initWithItems:@[
        NFPLocalizedRuleEditorTitle(NFPRuleEditorKindContains),
        NFPLocalizedRuleEditorTitle(NFPRuleEditorKindExclude)
    ]];
    ruleKindControl.selectedSegmentIndex = self.selectedRuleKind == NFPRuleEditorKindExclude ? 1 : 0;
    [ruleKindControl addTarget:self action:@selector(ruleKindChanged:) forControlEvents:UIControlEventValueChanged];
    [contentStack addArrangedSubview:ruleKindControl];
    self.ruleKindControl = ruleKindControl;

    UILabel *scopeLabel = [[UILabel alloc] init];
    scopeLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    scopeLabel.textColor = [UIColor secondaryLabelColor];
    scopeLabel.text = NFPLocalizedString(@"RULE_TEXT_SCOPE_LABEL");
    [contentStack addArrangedSubview:scopeLabel];

    UISegmentedControl *scopeControl = [[UISegmentedControl alloc] initWithItems:@[
        NFPLocalizedScopeName(NFRuleScopeMessage),
        NFPLocalizedScopeName(NFRuleScopeTitle),
        NFPLocalizedScopeName(NFRuleScopeSubtitle),
        NFPLocalizedScopeName(NFRuleScopeAll)
    ]];
    [scopeControl addTarget:self action:@selector(scopeChanged:) forControlEvents:UIControlEventValueChanged];
    [contentStack addArrangedSubview:scopeControl];
    self.scopeControl = scopeControl;

    UILabel *tokenLabel = [[UILabel alloc] init];
    tokenLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    tokenLabel.textColor = [UIColor secondaryLabelColor];
    tokenLabel.text = NFPLocalizedString(@"RULE_SCAN_TOKENS_LABEL");
    [contentStack addArrangedSubview:tokenLabel];

    UIView *tokenContainer = [[UIView alloc] init];
    tokenContainer.translatesAutoresizingMaskIntoConstraints = NO;
    tokenContainer.backgroundColor = [UIColor secondarySystemBackgroundColor];
    tokenContainer.layer.cornerRadius = 14.0;
    [contentStack addArrangedSubview:tokenContainer];

    UIStackView *tokenStackView = [[UIStackView alloc] init];
    tokenStackView.translatesAutoresizingMaskIntoConstraints = NO;
    tokenStackView.axis = UILayoutConstraintAxisVertical;
    tokenStackView.spacing = 10.0;
    [tokenContainer addSubview:tokenStackView];
    self.tokenStackView = tokenStackView;

    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [contentStack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor constant:16.0],
        [contentStack.leadingAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.leadingAnchor constant:16.0],
        [contentStack.trailingAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.trailingAnchor constant:-16.0],
        [contentStack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor constant:-24.0],

        [summaryTextView.heightAnchor constraintGreaterThanOrEqualToConstant:120.0],
        [tokenStackView.topAnchor constraintEqualToAnchor:tokenContainer.topAnchor constant:12.0],
        [tokenStackView.leadingAnchor constraintEqualToAnchor:tokenContainer.leadingAnchor constant:12.0],
        [tokenStackView.trailingAnchor constraintEqualToAnchor:tokenContainer.trailingAnchor constant:-12.0],
        [tokenStackView.bottomAnchor constraintEqualToAnchor:tokenContainer.bottomAnchor constant:-12.0]
    ]];

    [self rebuildTokenButtons];
    [self updateSelectedScopeFromTokens];
    [self updateScopeControl];
}

- (NSArray<NSDictionary *> *)buildTokensFromEntry:(NSDictionary *)entry {
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *tokenScopes = [NSMutableDictionary dictionary];
    [self collectTokensFromText:entry[NFLogTitleKey] scope:NFRuleScopeTitle intoMap:tokenScopes];
    [self collectTokensFromText:entry[NFLogSubtitleKey] scope:NFRuleScopeSubtitle intoMap:tokenScopes];
    [self collectTokensFromText:entry[NFLogHeaderKey] scope:NFRuleScopeMessage intoMap:tokenScopes];
    [self collectTokensFromText:entry[NFLogBodyKey] scope:NFRuleScopeMessage intoMap:tokenScopes];
    [self collectTokensFromText:entry[NFLogMessageKey] scope:NFRuleScopeMessage intoMap:tokenScopes];

    NSMutableArray<NSDictionary *> *tokens = [NSMutableArray arrayWithCapacity:tokenScopes.count];
    [tokenScopes enumerateKeysAndObjectsUsingBlock:^(NSString *token, NSMutableSet<NSString *> *scopes, BOOL *stop) {
        [tokens addObject:@{
            NFPTokenTextKey: token,
            NFPTokenScopesKey: [[scopes allObjects] sortedArrayUsingSelector:@selector(compare:)]
        }];
    }];

    [tokens sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        NSString *lhsText = lhs[NFPTokenTextKey];
        NSString *rhsText = rhs[NFPTokenTextKey];
        if (lhsText.length > rhsText.length) {
            return NSOrderedAscending;
        }
        if (lhsText.length < rhsText.length) {
            return NSOrderedDescending;
        }
        return [lhsText localizedCaseInsensitiveCompare:rhsText];
    }];
    return tokens;
}

- (void)collectTokensFromText:(id)rawText scope:(NSString *)scope intoMap:(NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *)tokenScopes {
    if (![rawText isKindOfClass:[NSString class]]) {
        return;
    }

    NSString *text = [(NSString *)rawText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) {
        return;
    }

    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    if (@available(iOS 5.0, *)) {
        [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                                 options:NSStringEnumerationByWords | NSStringEnumerationLocalized
                              usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
            NSString *normalized = [self normalizedTokenFromSubstring:substring];
            if (normalized.length > 0) {
                [tokens addObject:normalized];
            }
        }];
    }

    if (tokens.count == 0) {
        [tokens addObjectsFromArray:[self fallbackTokensFromText:text]];
    }

    for (NSString *token in tokens) {
        NSMutableSet<NSString *> *scopes = tokenScopes[token];
        if (!scopes) {
            scopes = [NSMutableSet set];
            tokenScopes[token] = scopes;
        }
        [scopes addObject:scope];
    }
}

- (NSArray<NSString *> *)fallbackTokensFromText:(NSString *)text {
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    NSMutableString *currentLatin = [NSMutableString string];
    NSCharacterSet *alphanumeric = [NSCharacterSet alphanumericCharacterSet];

    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        NSString *unit = [text substringWithRange:NSMakeRange(index, 1)];
        if ([alphanumeric characterIsMember:character]) {
            [currentLatin appendString:unit];
            continue;
        }

        if (currentLatin.length > 0) {
            [tokens addObject:[currentLatin copy]];
            [currentLatin setString:@""];
        }

        NSString *normalized = [self normalizedTokenFromSubstring:unit];
        if (normalized.length > 0) {
            [tokens addObject:normalized];
        }
    }

    if (currentLatin.length > 0) {
        [tokens addObject:[currentLatin copy]];
    }

    return tokens;
}

- (NSString *)normalizedTokenFromSubstring:(NSString *)substring {
    NSString *trimmed = [substring stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return nil;
    }

    NSCharacterSet *punctuation = [NSCharacterSet punctuationCharacterSet];
    BOOL allPunctuation = YES;
    for (NSUInteger index = 0; index < trimmed.length; index++) {
        unichar character = [trimmed characterAtIndex:index];
        if (![punctuation characterIsMember:character]) {
            allPunctuation = NO;
            break;
        }
    }
    if (allPunctuation) {
        return nil;
    }

    return trimmed;
}

- (NSString *)notificationSummaryText {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:NFPLocalizedString(@"LOG_DETAIL_APP_FORMAT"), self.appDisplayName.length > 0 ? self.appDisplayName : NFPLocalizedString(@"APP_UNKNOWN")]];

    void (^appendField)(NSString *, NSString *) = ^(NSString *labelFormat, NSString *value) {
        NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) {
            [lines addObject:[NSString stringWithFormat:labelFormat, trimmed]];
        }
    };

    appendField(NFPLocalizedString(@"LOG_DETAIL_NOTIFICATION_TITLE_FORMAT"), [self.entry[NFLogTitleKey] isKindOfClass:[NSString class]] ? self.entry[NFLogTitleKey] : @"");
    appendField(NFPLocalizedString(@"LOG_DETAIL_NOTIFICATION_SUBTITLE_FORMAT"), [self.entry[NFLogSubtitleKey] isKindOfClass:[NSString class]] ? self.entry[NFLogSubtitleKey] : @"");
    appendField(NFPLocalizedString(@"LOG_DETAIL_NOTIFICATION_HEADER_FORMAT"), [self.entry[NFLogHeaderKey] isKindOfClass:[NSString class]] ? self.entry[NFLogHeaderKey] : @"");
    appendField(NFPLocalizedString(@"LOG_DETAIL_NOTIFICATION_BODY_FORMAT"), [self.entry[NFLogBodyKey] isKindOfClass:[NSString class]] ? self.entry[NFLogBodyKey] : @"");
    appendField(NFPLocalizedString(@"LOG_DETAIL_NOTIFICATION_MESSAGE_FORMAT"), [self.entry[NFLogMessageKey] isKindOfClass:[NSString class]] ? self.entry[NFLogMessageKey] : @"");
    return [lines componentsJoinedByString:@"\n"];
}

- (void)rebuildTokenButtons {
    for (UIView *subview in self.tokenStackView.arrangedSubviews) {
        [self.tokenStackView removeArrangedSubview:subview];
        [subview removeFromSuperview];
    }

    if (self.tokens.count == 0) {
        UILabel *emptyLabel = [[UILabel alloc] init];
        emptyLabel.text = NFPLocalizedString(@"RULE_SCAN_NO_TOKENS");
        emptyLabel.textColor = [UIColor secondaryLabelColor];
        emptyLabel.numberOfLines = 0;
        [self.tokenStackView addArrangedSubview:emptyLabel];
        return;
    }

    UIStackView *currentRow = nil;
    NSUInteger itemsInRow = 0;
    for (NSUInteger index = 0; index < self.tokens.count; index++) {
        if (!currentRow || itemsInRow >= 3) {
            currentRow = [[UIStackView alloc] init];
            currentRow.axis = UILayoutConstraintAxisHorizontal;
            currentRow.spacing = 8.0;
            currentRow.distribution = UIStackViewDistributionFillEqually;
            [self.tokenStackView addArrangedSubview:currentRow];
            itemsInRow = 0;
        }

        NSDictionary *tokenInfo = self.tokens[index];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = index;
        button.layer.cornerRadius = 12.0;
        button.layer.borderWidth = 1.0;
        button.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
        button.titleLabel.numberOfLines = 2;
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        button.titleLabel.minimumScaleFactor = 0.72;
        [button setTitle:tokenInfo[NFPTokenTextKey] forState:UIControlStateNormal];
        [button addTarget:self action:@selector(tokenTapped:) forControlEvents:UIControlEventTouchUpInside];
        [button.heightAnchor constraintGreaterThanOrEqualToConstant:44.0].active = YES;
        [self updateAppearanceForTokenButton:button selected:NO];
        [currentRow addArrangedSubview:button];
        itemsInRow += 1;
    }
}

- (void)tokenTapped:(UIButton *)sender {
    if (sender.tag >= self.tokens.count) {
        return;
    }

    NSString *tokenText = self.tokens[sender.tag][NFPTokenTextKey];
    if (tokenText.length == 0) {
        return;
    }

    BOOL selected = ![self.selectedTokens containsObject:tokenText];
    if (selected) {
        [self.selectedTokens addObject:tokenText];
    } else {
        [self.selectedTokens removeObject:tokenText];
    }

    [self updateAppearanceForTokenButton:sender selected:selected];
    [self updateSelectedScopeFromTokens];
    [self updateScopeControl];
}

- (void)updateAppearanceForTokenButton:(UIButton *)button selected:(BOOL)selected {
    button.backgroundColor = selected ? [UIColor systemBlueColor] : [UIColor tertiarySystemBackgroundColor];
    button.layer.borderColor = (selected ? [UIColor systemBlueColor] : [UIColor separatorColor]).CGColor;
    [button setTitleColor:(selected ? [UIColor whiteColor] : [UIColor labelColor]) forState:UIControlStateNormal];
}

- (void)updateSelectedScopeFromTokens {
    if (self.selectedTokens.count == 0) {
        self.selectedScope = self.selectedRuleKind == NFPRuleEditorKindContains ? NFRuleScopeMessage : NFRuleScopeAll;
        return;
    }

    NSMutableSet<NSString *> *scopes = [NSMutableSet set];
    for (NSDictionary *tokenInfo in self.tokens) {
        NSString *tokenText = tokenInfo[NFPTokenTextKey];
        if (![self.selectedTokens containsObject:tokenText]) {
            continue;
        }

        NSArray<NSString *> *tokenScopes = tokenInfo[NFPTokenScopesKey];
        for (NSString *scope in tokenScopes) {
            if (scope.length > 0) {
                [scopes addObject:scope];
            }
        }
    }

    if (scopes.count == 1) {
        NSString *scope = scopes.anyObject;
        if ([scope isEqualToString:NFRuleScopeTitle]) {
            self.selectedScope = NFRuleScopeTitle;
            return;
        }
        if ([scope isEqualToString:NFRuleScopeSubtitle]) {
            self.selectedScope = NFRuleScopeSubtitle;
            return;
        }
        self.selectedScope = NFRuleScopeMessage;
        return;
    }

    self.selectedScope = NFRuleScopeAll;
}

- (void)updateScopeControl {
    NSArray<NSString *> *scopes = @[NFRuleScopeMessage, NFRuleScopeTitle, NFRuleScopeSubtitle, NFRuleScopeAll];
    NSUInteger index = [scopes indexOfObject:self.selectedScope ?: NFRuleScopeAll];
    self.scopeControl.selectedSegmentIndex = index == NSNotFound ? 3 : index;
}

- (void)ruleKindChanged:(UISegmentedControl *)sender {
    self.selectedRuleKind = sender.selectedSegmentIndex == 1 ? NFPRuleEditorKindExclude : NFPRuleEditorKindContains;
}

- (void)scopeChanged:(UISegmentedControl *)sender {
    switch (sender.selectedSegmentIndex) {
        case 1:
            self.selectedScope = NFRuleScopeTitle;
            break;
        case 2:
            self.selectedScope = NFRuleScopeSubtitle;
            break;
        case 3:
            self.selectedScope = NFRuleScopeAll;
            break;
        default:
            self.selectedScope = NFRuleScopeMessage;
            break;
    }
}

- (void)saveTapped {
    if (self.selectedTokens.count == 0) {
        [self presentAlertWithTitle:NFPLocalizedString(@"RULE_SCAN_EMPTY_SELECTION_TITLE")
                            message:NFPLocalizedString(@"RULE_SCAN_EMPTY_SELECTION_MESSAGE")];
        return;
    }

    NSMutableArray<NSDictionary *> *entries = [NSMutableArray arrayWithCapacity:self.selectedTokens.count];
    NSArray<NSString *> *sortedSelections = [[self.selectedTokens allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *token in sortedSelections) {
        [entries addObject:[NFPreferences ruleEntryWithText:token
                                                    enabled:YES
                                                  identifier:nil
                                                       scope:self.selectedScope ?: NFRuleScopeAll]];
    }

    NSError *error = nil;
    if (!self.commitHandler || !self.commitHandler(self.selectedRuleKind, entries, &error)) {
        [self presentAlertWithTitle:NFPLocalizedString(@"COMMON_SAVE_FAILED")
                            message:error.localizedDescription ?: NFPLocalizedString(@"PER_APP_RULES_SAVE_FAILED_MESSAGE")];
        return;
    }

    NSArray<UIViewController *> *controllers = self.navigationController.viewControllers ?: @[];
    if (self.returnViewController) {
        if (self.selectedRuleKind == self.initialRuleKind) {
            [self.navigationController popToViewController:self.returnViewController animated:YES];
            return;
        }

        NSUInteger returnIndex = [controllers indexOfObject:self.returnViewController];
        if (returnIndex != NSNotFound && returnIndex > 0) {
            [self.navigationController popToViewController:controllers[returnIndex - 1] animated:YES];
            return;
        }

        [self.navigationController popToViewController:self.returnViewController animated:YES];
        return;
    }

    [self.navigationController popViewControllerAnimated:YES];
}

- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_OK")
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
