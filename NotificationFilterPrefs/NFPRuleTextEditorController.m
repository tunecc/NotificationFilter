#import "NFPRuleTextEditorController.h"
#import "NFPLocalization.h"
#import "../Shared/NFPreferences.h"

@interface NFPRuleTextEditorController () <UITextViewDelegate>

@property (nonatomic, copy) NSString *placeholder;
@property (nonatomic, copy) NSString *initialRule;
@property (nonatomic, copy) NSString *initialScope;
@property (nonatomic, assign) NFPRuleEditorKind editorKind;
@property (nonatomic, copy) void (^saveHandler)(NSString *rule, NSString *scope);
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, copy) NSString *selectedScopeValue;
@property (nonatomic, strong) NSArray<UIButton *> *scopeButtons;
@property (nonatomic, strong) UIView *hintCardView;
@property (nonatomic, strong) UILabel *hintTitleLabel;
@property (nonatomic, strong) UILabel *hintDetailLabel;

@end

@implementation NFPRuleTextEditorController

- (instancetype)initWithTitle:(NSString *)title
                  placeholder:(NSString *)placeholder
                  initialRule:(NSString *)initialRule
                 initialScope:(NSString *)initialScope
                   editorKind:(NFPRuleEditorKind)editorKind
                  saveHandler:(void (^)(NSString *, NSString *))saveHandler {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.title = title;
        _placeholder = [placeholder copy] ?: @"";
        _initialRule = [initialRule copy] ?: @"";
        _initialScope = [initialScope copy] ?: NFRuleScopeAll;
        _selectedScopeValue = _initialScope;
        _editorKind = editorKind;
        _saveHandler = [saveHandler copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                                            target:self
                                                                                            action:@selector(saveTapped)];

    UIView *scopeContainer = [[UIView alloc] init];
    scopeContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scopeContainer];

    UILabel *scopeLabel = [[UILabel alloc] init];
    scopeLabel.text = NFPLocalizedString(@"RULE_TEXT_SCOPE_LABEL");
    scopeLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    scopeLabel.textColor = [UIColor secondaryLabelColor];
    scopeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [scopeContainer addSubview:scopeLabel];

    UIStackView *scopeRow = [[UIStackView alloc] init];
    scopeRow.axis = UILayoutConstraintAxisHorizontal;
    scopeRow.alignment = UIStackViewAlignmentFill;
    scopeRow.distribution = UIStackViewDistributionFillEqually;
    scopeRow.spacing = 8.0;
    scopeRow.translatesAutoresizingMaskIntoConstraints = NO;
    [scopeContainer addSubview:scopeRow];

    NSArray<NSDictionary *> *scopeItems = @[
        @{@"title": NFPLocalizedScopeName(NFRuleScopeMessage), @"scope": NFRuleScopeMessage},
        @{@"title": NFPLocalizedScopeName(NFRuleScopeTitle), @"scope": NFRuleScopeTitle},
        @{@"title": NFPLocalizedScopeName(NFRuleScopeSubtitle), @"scope": NFRuleScopeSubtitle},
        @{@"title": NFPLocalizedScopeName(NFRuleScopeAll), @"scope": NFRuleScopeAll}
    ];
    NSMutableArray<UIButton *> *buttons = [NSMutableArray arrayWithCapacity:scopeItems.count];
    for (NSUInteger index = 0; index < scopeItems.count; index++) {
        NSDictionary *item = scopeItems[index];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.tag = index;
        UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
        configuration.contentInsets = NSDirectionalEdgeInsetsMake(6.0, 6.0, 6.0, 6.0);
        configuration.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey,id> * _Nonnull(NSDictionary<NSAttributedStringKey,id> * _Nonnull incoming) {
            NSMutableDictionary<NSAttributedStringKey, id> *attributes = [incoming mutableCopy];
            attributes[NSFontAttributeName] = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
            return attributes;
        };
        button.configuration = configuration;
        button.layer.cornerRadius = 12.0;
        button.layer.borderWidth = 1.0;
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        button.titleLabel.minimumScaleFactor = 0.72;
        button.titleLabel.lineBreakMode = NSLineBreakByClipping;
        [button setTitle:item[@"title"] forState:UIControlStateNormal];
        [button addTarget:self action:@selector(scopeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [button.heightAnchor constraintEqualToConstant:38.0].active = YES;
        [scopeRow addArrangedSubview:button];
        [buttons addObject:button];
    }
    self.scopeButtons = buttons;

    UITextView *textView = [[UITextView alloc] init];
    textView.alwaysBounceVertical = YES;
    textView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    textView.font = [UIFont systemFontOfSize:17.0];
    textView.delegate = self;
    textView.textContainerInset = UIEdgeInsetsMake(16.0, 16.0, 16.0, 16.0);
    textView.text = self.initialRule;
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:textView];
    self.textView = textView;

    UIView *hintCardView = [[UIView alloc] init];
    hintCardView.translatesAutoresizingMaskIntoConstraints = NO;
    hintCardView.backgroundColor = [UIColor tertiarySystemBackgroundColor];
    hintCardView.layer.cornerRadius = 14.0;
    [self.view addSubview:hintCardView];
    self.hintCardView = hintCardView;

    UILabel *hintTitleLabel = [[UILabel alloc] init];
    hintTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    hintTitleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    hintTitleLabel.textColor = [UIColor labelColor];
    [hintCardView addSubview:hintTitleLabel];
    self.hintTitleLabel = hintTitleLabel;

    UILabel *hintDetailLabel = [[UILabel alloc] init];
    hintDetailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    hintDetailLabel.font = [UIFont systemFontOfSize:12.0];
    hintDetailLabel.textColor = [UIColor secondaryLabelColor];
    hintDetailLabel.numberOfLines = 0;
    [hintCardView addSubview:hintDetailLabel];
    self.hintDetailLabel = hintDetailLabel;

    UILabel *placeholderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    placeholderLabel.text = self.placeholder;
    placeholderLabel.textColor = [UIColor placeholderTextColor];
    placeholderLabel.numberOfLines = 0;
    placeholderLabel.font = textView.font;
    placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [textView addSubview:placeholderLabel];
    self.placeholderLabel = placeholderLabel;

    [NSLayoutConstraint activateConstraints:@[
        [scopeContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12.0],
        [scopeContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [scopeContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],

        [scopeLabel.topAnchor constraintEqualToAnchor:scopeContainer.topAnchor],
        [scopeLabel.leadingAnchor constraintEqualToAnchor:scopeContainer.leadingAnchor],
        [scopeLabel.trailingAnchor constraintEqualToAnchor:scopeContainer.trailingAnchor],

        [scopeRow.topAnchor constraintEqualToAnchor:scopeLabel.bottomAnchor constant:8.0],
        [scopeRow.leadingAnchor constraintEqualToAnchor:scopeContainer.leadingAnchor],
        [scopeRow.trailingAnchor constraintEqualToAnchor:scopeContainer.trailingAnchor],
        [scopeRow.bottomAnchor constraintEqualToAnchor:scopeContainer.bottomAnchor],

        [hintCardView.topAnchor constraintEqualToAnchor:scopeContainer.bottomAnchor constant:12.0],
        [hintCardView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [hintCardView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],

        [textView.topAnchor constraintEqualToAnchor:hintCardView.bottomAnchor constant:12.0],
        [textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [hintTitleLabel.topAnchor constraintEqualToAnchor:hintCardView.topAnchor constant:12.0],
        [hintTitleLabel.leadingAnchor constraintEqualToAnchor:hintCardView.leadingAnchor constant:12.0],
        [hintTitleLabel.trailingAnchor constraintEqualToAnchor:hintCardView.trailingAnchor constant:-12.0],

        [hintDetailLabel.topAnchor constraintEqualToAnchor:hintTitleLabel.bottomAnchor constant:6.0],
        [hintDetailLabel.leadingAnchor constraintEqualToAnchor:hintCardView.leadingAnchor constant:12.0],
        [hintDetailLabel.trailingAnchor constraintEqualToAnchor:hintCardView.trailingAnchor constant:-12.0],
        [hintDetailLabel.bottomAnchor constraintEqualToAnchor:hintCardView.bottomAnchor constant:-12.0],

        [placeholderLabel.topAnchor constraintEqualToAnchor:textView.topAnchor constant:24.0],
        [placeholderLabel.leadingAnchor constraintEqualToAnchor:textView.leadingAnchor constant:21.0],
        [placeholderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:textView.trailingAnchor constant:-21.0]
    ]];

    [self updatePlaceholderVisibility];
    [self updateScopeButtons];
    [self updateScopeHint];
}

- (void)textViewDidChange:(UITextView *)textView {
    [self updatePlaceholderVisibility];
}

- (void)updatePlaceholderVisibility {
    self.placeholderLabel.hidden = self.textView.text.length > 0;
}

- (void)saveTapped {
    NSString *normalizedRule = [self normalizedRuleFromText:self.textView.text];
    if (normalizedRule.length == 0) {
        [self presentAlertWithTitle:NFPLocalizedString(@"RULE_TEXT_EMPTY_TITLE")
                            message:NFPLocalizedString(@"RULE_TEXT_EMPTY_MESSAGE")];
        return;
    }

    NSError *validationError = [self validateRule:normalizedRule];
    if (validationError) {
        [self presentAlertWithTitle:NFPLocalizedString(@"RULE_TEXT_INVALID_TITLE") message:validationError.localizedDescription];
        return;
    }

    if (self.saveHandler) {
        self.saveHandler(normalizedRule, [self selectedScope]);
    }

    [self.navigationController popViewControllerAnimated:YES];
}

- (void)scopeButtonTapped:(UIButton *)sender {
    NSString *scope = [self scopeValueForButtonIndex:sender.tag];
    if ([scope isEqualToString:self.selectedScopeValue]) {
        return;
    }

    self.selectedScopeValue = scope;
    [self updateScopeButtons];
    [self updateScopeHint];
}

- (NSString *)normalizedRuleFromText:(NSString *)text {
    NSArray<NSString *> *components = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSString *singleLine = [[components componentsJoinedByString:@" "] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return singleLine;
}

- (NSError *)validateRule:(NSString *)rule {
    if (self.editorKind != NFPRuleEditorKindRegex) {
        return nil;
    }

    NSError *error = nil;
    [NSRegularExpression regularExpressionWithPattern:rule
                                              options:NSRegularExpressionCaseInsensitive
                                                error:&error];
    if (error) {
        return [NSError errorWithDomain:NFPreferencesIdentifier
                                   code:3
                               userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:NFPLocalizedString(@"REGEX_COMPILE_FAILED_FORMAT"),
                                                                      rule,
                                                                      error.localizedDescription ?: NFPLocalizedString(@"COMMON_UNKNOWN")]}];
    }

    return nil;
}

- (NSString *)selectedScope {
    return self.selectedScopeValue ?: NFRuleScopeMessage;
}

- (NSString *)scopeValueForButtonIndex:(NSInteger)index {
    switch (index) {
        case 1:
            return NFRuleScopeTitle;
        case 2:
            return NFRuleScopeSubtitle;
        case 3:
            return NFRuleScopeAll;
        default:
            return NFRuleScopeMessage;
    }
}

- (void)updateScopeButtons {
    for (UIButton *button in self.scopeButtons) {
        NSString *scope = [self scopeValueForButtonIndex:button.tag];
        BOOL selected = [scope isEqualToString:self.selectedScopeValue];
        button.backgroundColor = selected ? [UIColor systemBlueColor] : [UIColor secondarySystemBackgroundColor];
        button.layer.borderColor = (selected ? [UIColor systemBlueColor] : [UIColor separatorColor]).CGColor;
        [button setTitleColor:(selected ? [UIColor whiteColor] : [UIColor labelColor]) forState:UIControlStateNormal];
    }
}

- (void)updateScopeHint {
    NSString *scope = [self selectedScope];
    if ([scope isEqualToString:NFRuleScopeTitle]) {
        self.hintTitleLabel.text = NFPLocalizedString(@"RULE_TEXT_HINT_TITLE_TITLE");
        self.hintDetailLabel.text = NFPLocalizedString(@"RULE_TEXT_HINT_TITLE_DETAIL");
        return;
    }
    if ([scope isEqualToString:NFRuleScopeSubtitle]) {
        self.hintTitleLabel.text = NFPLocalizedString(@"RULE_TEXT_HINT_SUBTITLE_TITLE");
        self.hintDetailLabel.text = NFPLocalizedString(@"RULE_TEXT_HINT_SUBTITLE_DETAIL");
        return;
    }
    if ([scope isEqualToString:NFRuleScopeAll]) {
        self.hintTitleLabel.text = NFPLocalizedString(@"RULE_TEXT_HINT_ALL_TITLE");
        self.hintDetailLabel.text = NFPLocalizedString(@"RULE_TEXT_HINT_ALL_DETAIL");
        return;
    }

    self.hintTitleLabel.text = NFPLocalizedString(@"RULE_TEXT_HINT_MESSAGE_TITLE");
    self.hintDetailLabel.text = NFPLocalizedString(@"RULE_TEXT_HINT_MESSAGE_DETAIL");
}

- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
