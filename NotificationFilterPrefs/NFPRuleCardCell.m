#import "NFPRuleCardCell.h"
#import "../Shared/NFPreferences.h"

@interface NFPRuleCardCell ()

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, copy) void (^toggleHandler)(BOOL enabled);

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

        UISwitch *enabledSwitch = [[UISwitch alloc] init];
        enabledSwitch.translatesAutoresizingMaskIntoConstraints = NO;
        [enabledSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        [cardView addSubview:enabledSwitch];
        self.enabledSwitch = enabledSwitch;

        [NSLayoutConstraint activateConstraints:@[
            [cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],
            [cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],

            [titleLabel.topAnchor constraintEqualToAnchor:cardView.topAnchor constant:14.0],
            [titleLabel.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor constant:14.0],
            [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:enabledSwitch.leadingAnchor constant:-12.0],

            [enabledSwitch.topAnchor constraintEqualToAnchor:cardView.topAnchor constant:12.0],
            [enabledSwitch.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor constant:-14.0],

            [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8.0],
            [subtitleLabel.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor constant:14.0],
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
    self.statusLabel.hidden = YES;
    self.statusLabel.text = nil;
}

- (void)configureWithRuleEntry:(NSDictionary *)ruleEntry
                    editorKind:(NFPRuleEditorKind)editorKind
               validationState:(NFPRuleValidationState)validationState
                 toggleHandler:(void (^)(BOOL))toggleHandler {
    self.toggleHandler = toggleHandler;

    NSString *ruleText = [NFPreferences ruleTextFromEntry:ruleEntry] ?: @"";
    BOOL enabled = [NFPreferences ruleEntryEnabled:ruleEntry];

    self.titleLabel.text = ruleText;
    self.enabledSwitch.on = enabled;

    switch (editorKind) {
        case NFPRuleEditorKindContains:
            self.subtitleLabel.text = @"命中消息内容时过滤";
            break;
        case NFPRuleEditorKindExclude:
            self.subtitleLabel.text = @"命中时优先放行";
            break;
        default:
            self.subtitleLabel.text = @"正则表达式";
            break;
    }

    self.titleLabel.textColor = enabled ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    self.cardView.alpha = enabled ? 1.0 : 0.75;

    if (validationState == NFPRuleValidationStateNone) {
        self.statusLabel.hidden = YES;
    } else {
        self.statusLabel.hidden = NO;
        if (validationState == NFPRuleValidationStateValid) {
            self.statusLabel.text = @"有效";
            self.statusLabel.textColor = [UIColor systemGreenColor];
            self.statusLabel.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.14];
        } else {
            self.statusLabel.text = @"无效";
            self.statusLabel.textColor = [UIColor systemRedColor];
            self.statusLabel.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.14];
        }
    }
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    self.enabledSwitch.enabled = !editing;
}

- (void)switchChanged:(UISwitch *)sender {
    if (self.toggleHandler) {
        self.toggleHandler(sender.on);
    }
}

@end
