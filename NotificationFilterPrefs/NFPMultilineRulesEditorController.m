#import "NFPMultilineRulesEditorController.h"
#import "NFPLocalization.h"
#import "../Shared/NFPreferences.h"

@interface NFPMultilineRulesEditorController ()

@property (nonatomic, copy) NSString *initialText;
@property (nonatomic, assign) NFPRuleEditorKind editorKind;
@property (nonatomic, copy) void (^saveHandler)(NSArray<NSString *> *rules);
@property (nonatomic, strong) UITextView *textView;

@end

@implementation NFPMultilineRulesEditorController

- (instancetype)initWithTitle:(NSString *)title
                  initialText:(NSString *)initialText
                   editorKind:(NFPRuleEditorKind)editorKind
                  saveHandler:(void (^)(NSArray<NSString *> *))saveHandler {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.title = title;
        _initialText = [initialText copy] ?: @"";
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
    self.navigationItem.prompt = self.editorKind == NFPRuleEditorKindRegex ? NFPLocalizedString(@"MULTILINE_EDITOR_PROMPT_REGEX") : NFPLocalizedString(@"MULTILINE_EDITOR_PROMPT_RULE");

    UITextView *textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    textView.alwaysBounceVertical = YES;
    textView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    textView.font = [UIFont monospacedSystemFontOfSize:15.0 weight:UIFontWeightRegular];
    textView.text = self.initialText;
    textView.textContainerInset = UIEdgeInsetsMake(16.0, 16.0, 16.0, 16.0);
    [self.view addSubview:textView];
    self.textView = textView;
}

- (void)saveTapped {
    NSArray<NSString *> *rules = [NFPreferences normalizedRuleLinesFromMultilineString:self.textView.text];
    if (self.editorKind == NFPRuleEditorKindRegex) {
        NSError *validationError = [self validateRegexRules:rules];
        if (validationError) {
            [self presentAlertWithTitle:NFPLocalizedString(@"REGEX_INVALID_TITLE") message:validationError.localizedDescription];
            return;
        }
    }

    if (self.saveHandler) {
        self.saveHandler(rules);
    }

    [self.navigationController popViewControllerAnimated:YES];
}

- (NSError *)validateRegexRules:(NSArray<NSString *> *)rules {
    for (NSString *rule in rules) {
        NSError *error = nil;
        [NSRegularExpression regularExpressionWithPattern:rule
                                                  options:NSRegularExpressionCaseInsensitive
                                                    error:&error];
        if (error) {
            return [NSError errorWithDomain:NFPreferencesIdentifier
                                       code:2
                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:NFPLocalizedString(@"REGEX_COMPILE_FAILED_FORMAT"),
                                                                          rule,
                                                                          error.localizedDescription ?: NFPLocalizedString(@"COMMON_UNKNOWN")]}];
        }
    }

    return nil;
}

- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
