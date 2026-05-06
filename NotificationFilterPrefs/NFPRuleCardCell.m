#import "NFPRuleCardCell.h"
#import "NFPLocalization.h"
#import "../Shared/NFPreferences.h"

@interface NFPRuleCardCell ()

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UIButton *selectionButton;
@property (nonatomic, strong) NSLayoutConstraint *titleLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *subtitleLeadingConstraint;
@property (nonatomic, copy) void (^toggleHandler)(BOOL enabled);
@property (nonatomic, copy) void (^selectionHandler)(void);

@end

@implementation NFPRuleCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        UIView *cardView = [[UIView alloc] init];
        cardView.backgroundColor = [UIColor secondarySystemBackgroundColor];
        cardView.layer.cornerRadius = 14.0;
        cardView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:cardView];
        self.cardView = cardView;

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
        titleLabel.numberOfLines = 2;
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cardView addSubview:titleLabel];
        self.titleLabel = titleLabel;

        UILabel *subtitleLabel = [[UILabel alloc] init];
        subtitleLabel.font = [UIFont systemFontOfSize:13.0];
        subtitleLabel.textColor = [UIColor secondaryLabelColor];
        subtitleLabel.numberOfLines = 2;
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cardView addSubview:subtitleLabel];
        self.subtitleLabel = subtitleLabel;

        UILabel *statusLabel = [[UILabel alloc] init];
        statusLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
        statusLabel.textAlignment = NSTextAlignmentCenter;
        statusLabel.layer.cornerRadius = 9.0;
        statusLabel.layer.masksToBounds = YES;
        statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cardView addSubview:statusLabel];
        self.statusLabel = statusLabel;

        UIButton *selectionButton = [UIButton buttonWithType:UIButtonTypeSystem];
        selectionButton.translatesAutoresizingMaskIntoConstraints = NO;
        selectionButton.hidden = YES;
        [selectionButton addTarget:self action:@selector(selectionTapped) forControlEvents:UIControlEventTouchUpInside];
        [cardView addSubview:selectionButton];
        self.selectionButton = selectionButton;

        UISwitch *enabledSwitch = [[UISwitch alloc] init];
        enabledSwitch.translatesAutoresizingMaskIntoConstraints = NO;
        [enabledSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        [cardView addSubview:enabledSwitch];
        self.enabledSwitch = enabledSwitch;

        self.titleLeadingConstraint = [titleLabel.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor constant:14.0];
        self.subtitleLeadingConstraint = [subtitleLabel.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor constant:14.0];
        [NSLayoutConstraint activateConstraints:@[
            [cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],
            [cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],

            [titleLabel.topAnchor constraintEqualToAnchor:cardView.topAnchor constant:14.0],
            self.titleLeadingConstraint,
            [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:enabledSwitch.leadingAnchor constant:-12.0],

            [selectionButton.centerYAnchor constraintEqualToAnchor:cardView.centerYAnchor],
            [selectionButton.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor constant:14.0],
            [selectionButton.widthAnchor constraintEqualToConstant:28.0],
            [selectionButton.heightAnchor constraintEqualToConstant:28.0],

            [enabledSwitch.centerYAnchor constraintEqualToAnchor:cardView.centerYAnchor],
            [enabledSwitch.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor constant:-14.0],

            [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8.0],
            self.subtitleLeadingConstraint,
            [subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:statusLabel.leadingAnchor constant:-10.0],
            [subtitleLabel.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor constant:-14.0],

            [statusLabel.centerYAnchor constraintEqualToAnchor:subtitleLabel.centerYAnchor],
            [statusLabel.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor constant:-14.0],
            [statusLabel.heightAnchor constraintEqualToConstant:18.0],
            [statusLabel.widthAnchor constraintGreaterThanOrEqualToConstant:44.0]
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.toggleHandler = nil;
    self.selectionHandler = nil;
    self.statusLabel.hidden = YES;
    self.statusLabel.text = nil;
}

- (void)configureWithRuleEntry:(NSDictionary *)ruleEntry
                    editorKind:(NFPRuleEditorKind)editorKind
               validationState:(NFPRuleValidationState)validationState
                   editingMode:(BOOL)editingMode
                      selected:(BOOL)selected
                 toggleHandler:(void (^)(BOOL))toggleHandler
              selectionHandler:(void (^)(void))selectionHandler {
    self.toggleHandler = toggleHandler;
    self.selectionHandler = selectionHandler;

    NSString *ruleText = [NFPreferences ruleTextFromEntry:ruleEntry] ?: @"";
    BOOL enabled = [NFPreferences ruleEntryEnabled:ruleEntry];
    NSString *scope = [NFPreferences ruleScopeFromEntry:ruleEntry
                                           defaultScope:editorKind == NFPRuleEditorKindContains ? NFRuleScopeMessage : NFRuleScopeAll];

    self.titleLabel.text = ruleText;
    self.enabledSwitch.on = enabled;
    self.selectionButton.hidden = !editingMode;
    self.enabledSwitch.hidden = editingMode;
    self.selectionButton.tintColor = selected ? [UIColor systemBlueColor] : [UIColor tertiaryLabelColor];
    UIImage *selectionImage = [UIImage systemImageNamed:selected ? @"checkmark.circle.fill" : @"circle"];
    [self.selectionButton setImage:selectionImage forState:UIControlStateNormal];
    self.titleLeadingConstraint.constant = editingMode ? 50.0 : 14.0;
    self.subtitleLeadingConstraint.constant = editingMode ? 50.0 : 14.0;

    self.subtitleLabel.text = NFPLocalizedScopeName(scope);

    self.titleLabel.textColor = enabled ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    self.cardView.alpha = enabled ? 1.0 : 0.75;
    self.selectionStyle = editingMode ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;

    if (validationState == NFPRuleValidationStateNone) {
        self.statusLabel.hidden = YES;
    } else {
        self.statusLabel.hidden = NO;
        if (validationState == NFPRuleValidationStateValid) {
            self.statusLabel.text = NFPLocalizedString(@"RULE_CARD_VALID");
            self.statusLabel.textColor = [UIColor systemGreenColor];
            self.statusLabel.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.14];
        } else {
            self.statusLabel.text = NFPLocalizedString(@"RULE_CARD_INVALID");
            self.statusLabel.textColor = [UIColor systemRedColor];
            self.statusLabel.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.14];
        }
    }
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    self.enabledSwitch.enabled = !editing;
}

- (void)selectionTapped {
    if (self.selectionHandler) {
        self.selectionHandler();
    }
}

- (void)switchChanged:(UISwitch *)sender {
    if (self.toggleHandler) {
        self.toggleHandler(sender.on);
    }
}

@end
