#import "NFPRuleTextEditorController.h"
#import "../Shared/NFPreferences.h"

@interface NFPRuleTextEditorController () <UITextViewDelegate>

@property (nonatomic, copy) NSString *placeholder;
@property (nonatomic, copy) NSString *initialRule;
@property (nonatomic, assign) NFPRuleEditorKind editorKind;
@property (nonatomic, copy) void (^saveHandler)(NSString *rule);
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *placeholderLabel;

@end

@implementation NFPRuleTextEditorController

- (instancetype)initWithTitle:(NSString *)title
                  placeholder:(NSString *)placeholder
                  initialRule:(NSString *)initialRule
                   editorKind:(NFPRuleEditorKind)editorKind
                  saveHandler:(void (^)(NSString *))saveHandler {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.title = title;
        _placeholder = [placeholder copy] ?: @"";
        _initialRule = [initialRule copy] ?: @"";
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

    UITextView *textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    textView.alwaysBounceVertical = YES;
    textView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    textView.font = [UIFont systemFontOfSize:17.0];
    textView.delegate = self;
    textView.textContainerInset = UIEdgeInsetsMake(16.0, 16.0, 16.0, 16.0);
    textView.text = self.initialRule;
    [self.view addSubview:textView];
    self.textView = textView;

    UILabel *placeholderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    placeholderLabel.text = self.placeholder;
    placeholderLabel.textColor = [UIColor placeholderTextColor];
    placeholderLabel.numberOfLines = 0;
    placeholderLabel.font = textView.font;
    placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [textView addSubview:placeholderLabel];
    self.placeholderLabel = placeholderLabel;

    [NSLayoutConstraint activateConstraints:@[
        [placeholderLabel.topAnchor constraintEqualToAnchor:textView.topAnchor constant:24.0],
        [placeholderLabel.leadingAnchor constraintEqualToAnchor:textView.leadingAnchor constant:21.0],
        [placeholderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:textView.trailingAnchor constant:-21.0]
    ]];

    [self updatePlaceholderVisibility];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.textView becomeFirstResponder];
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
        [self presentAlertWithTitle:@"规则为空" message:@"请输入一条规则。"];
        return;
    }

    NSError *validationError = [self validateRule:normalizedRule];
    if (validationError) {
        [self presentAlertWithTitle:@"规则无效" message:validationError.localizedDescription];
        return;
    }

    if (self.saveHandler) {
        self.saveHandler(normalizedRule);
    }

    [self.navigationController popViewControllerAnimated:YES];
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
                               userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"正则“%@”无法编译：%@", rule, error.localizedDescription ?: @"未知错误"]}];
    }

    return nil;
}

- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
