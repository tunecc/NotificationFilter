#import "NFPNotificationRuleTokenPickerController.h"
#import "../Shared/NFPreferences.h"
#import "NFPLocalization.h"

static NSString * const NFPTokenSectionScopeKey = @"scope";
static NSString * const NFPTokenSectionTokensKey = @"tokens";
static NSString * const NFPTokenSelectionSeparator = @"\n";

@interface NFPNotificationRuleTokenPickerController ()

@property (nonatomic, copy) NSDictionary *entry;
@property (nonatomic, copy) NSString *appDisplayName;
@property (nonatomic, assign) NFPRuleEditorKind initialRuleKind;
@property (nonatomic, assign) NFPRuleEditorKind selectedRuleKind;
@property (nonatomic, weak, nullable) UIViewController *returnViewController;
@property (nonatomic, copy) NFPNotificationRuleTokenCommitHandler commitHandler;
@property (nonatomic, copy) NSArray<NSDictionary *> *tokenSections;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedTokenKeys;
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
        _selectedTokenKeys = [NSMutableSet set];
        _tokenSections = [self buildTokenSectionsFromEntry:_entry];
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
}

- (NSArray<NSDictionary *> *)buildTokenSectionsFromEntry:(NSDictionary *)entry {
    NSMutableArray<NSDictionary *> *sections = [NSMutableArray array];

    [self appendSectionWithScope:NFRuleScopeTitle
                        rawTexts:@[entry[NFLogTitleKey] ?: @""]
                       toSections:sections];
    [self appendSectionWithScope:NFRuleScopeSubtitle
                        rawTexts:@[entry[NFLogSubtitleKey] ?: @""]
                       toSections:sections];
    [self appendSectionWithScope:NFRuleScopeMessage
                        rawTexts:@[entry[NFLogHeaderKey] ?: @"", entry[NFLogBodyKey] ?: @"", entry[NFLogMessageKey] ?: @""]
                       toSections:sections];

    return sections;
}

- (void)appendSectionWithScope:(NSString *)scope
                      rawTexts:(NSArray *)rawTexts
                     toSections:(NSMutableArray<NSDictionary *> *)sections {
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    NSMutableSet<NSString *> *seenTokens = [NSMutableSet set];

    for (id rawText in rawTexts) {
        for (NSString *token in [self tokensFromText:rawText]) {
            if (token.length == 0 || [seenTokens containsObject:token]) {
                continue;
            }
            [seenTokens addObject:token];
            [tokens addObject:token];
        }
    }

    if (tokens.count == 0) {
        return;
    }

    [tokens sortUsingComparator:^NSComparisonResult(NSString *lhs, NSString *rhs) {
        if (lhs.length > rhs.length) {
            return NSOrderedAscending;
        }
        if (lhs.length < rhs.length) {
            return NSOrderedDescending;
        }
        return [lhs localizedCaseInsensitiveCompare:rhs];
    }];

    [sections addObject:@{
        NFPTokenSectionScopeKey: scope,
        NFPTokenSectionTokensKey: tokens
    }];
}

- (NSArray<NSString *> *)tokensFromText:(id)rawText {
    if (![rawText isKindOfClass:[NSString class]]) {
        return @[];
    }

    NSString *text = [(NSString *)rawText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) {
        return @[];
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

    return tokens;
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

    if (self.tokenSections.count == 0) {
        UILabel *emptyLabel = [[UILabel alloc] init];
        emptyLabel.text = NFPLocalizedString(@"RULE_SCAN_NO_TOKENS");
        emptyLabel.textColor = [UIColor secondaryLabelColor];
        emptyLabel.numberOfLines = 0;
        [self.tokenStackView addArrangedSubview:emptyLabel];
        return;
    }

    for (NSDictionary *section in self.tokenSections) {
        NSString *scope = section[NFPTokenSectionScopeKey];
        NSArray<NSString *> *tokens = [section[NFPTokenSectionTokensKey] isKindOfClass:[NSArray class]] ? section[NFPTokenSectionTokensKey] : @[];
        if (tokens.count == 0) {
            continue;
        }

        UILabel *sectionLabel = [[UILabel alloc] init];
        sectionLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
        sectionLabel.textColor = [UIColor secondaryLabelColor];
        sectionLabel.text = NFPLocalizedScopeName(scope);
        [self.tokenStackView addArrangedSubview:sectionLabel];

        UIStackView *currentRow = nil;
        NSUInteger itemsInRow = 0;
        for (NSString *token in tokens) {
            if (!currentRow || itemsInRow >= 3) {
                currentRow = [[UIStackView alloc] init];
                currentRow.axis = UILayoutConstraintAxisHorizontal;
                currentRow.spacing = 8.0;
                currentRow.distribution = UIStackViewDistributionFillEqually;
                [self.tokenStackView addArrangedSubview:currentRow];
                itemsInRow = 0;
            }

            NSString *selectionKey = [self selectionKeyForScope:scope token:token];
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.accessibilityIdentifier = selectionKey;
            button.layer.cornerRadius = 12.0;
            button.layer.borderWidth = 1.0;
            button.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
            button.titleLabel.numberOfLines = 2;
            button.titleLabel.adjustsFontSizeToFitWidth = YES;
            button.titleLabel.minimumScaleFactor = 0.72;
            [button setTitle:token forState:UIControlStateNormal];
            [button addTarget:self action:@selector(tokenTapped:) forControlEvents:UIControlEventTouchUpInside];
            [button.heightAnchor constraintGreaterThanOrEqualToConstant:44.0].active = YES;
            [self updateAppearanceForTokenButton:button selected:[self.selectedTokenKeys containsObject:selectionKey]];
            [currentRow addArrangedSubview:button];
            itemsInRow += 1;
        }
    }
}

- (void)tokenTapped:(UIButton *)sender {
    NSString *selectionKey = sender.accessibilityIdentifier;
    if (selectionKey.length == 0) {
        return;
    }

    BOOL selected = ![self.selectedTokenKeys containsObject:selectionKey];
    if (selected) {
        [self.selectedTokenKeys addObject:selectionKey];
    } else {
        [self.selectedTokenKeys removeObject:selectionKey];
    }

    [self updateAppearanceForTokenButton:sender selected:selected];
}

- (void)updateAppearanceForTokenButton:(UIButton *)button selected:(BOOL)selected {
    button.backgroundColor = selected ? [UIColor systemBlueColor] : [UIColor tertiarySystemBackgroundColor];
    button.layer.borderColor = (selected ? [UIColor systemBlueColor] : [UIColor separatorColor]).CGColor;
    [button setTitleColor:(selected ? [UIColor whiteColor] : [UIColor labelColor]) forState:UIControlStateNormal];
}

- (void)ruleKindChanged:(UISegmentedControl *)sender {
    self.selectedRuleKind = sender.selectedSegmentIndex == 1 ? NFPRuleEditorKindExclude : NFPRuleEditorKindContains;
}

- (void)saveTapped {
    if (self.selectedTokenKeys.count == 0) {
        [self presentAlertWithTitle:NFPLocalizedString(@"RULE_SCAN_EMPTY_SELECTION_TITLE")
                            message:NFPLocalizedString(@"RULE_SCAN_EMPTY_SELECTION_MESSAGE")];
        return;
    }

    NSMutableArray<NSDictionary *> *entries = [NSMutableArray arrayWithCapacity:self.selectedTokenKeys.count];
    for (NSDictionary *section in self.tokenSections) {
        NSString *scope = section[NFPTokenSectionScopeKey];
        NSArray<NSString *> *tokens = [section[NFPTokenSectionTokensKey] isKindOfClass:[NSArray class]] ? section[NFPTokenSectionTokensKey] : @[];
        for (NSString *token in tokens) {
            NSString *selectionKey = [self selectionKeyForScope:scope token:token];
            if (![self.selectedTokenKeys containsObject:selectionKey]) {
                continue;
            }

            [entries addObject:[NFPreferences ruleEntryWithText:token
                                                        enabled:YES
                                                      identifier:nil
                                                           scope:scope ?: NFRuleScopeMessage]];
        }
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

- (NSString *)selectionKeyForScope:(NSString *)scope token:(NSString *)token {
    return [NSString stringWithFormat:@"%@%@%@", scope ?: @"", NFPTokenSelectionSeparator, token ?: @""];
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
