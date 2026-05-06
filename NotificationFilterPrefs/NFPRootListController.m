#import "NFPRootListController.h"
#import <Preferences/PSSpecifier.h>
#import "../Shared/NFPreferences.h"
#import "NFPLocalization.h"
#import "NFPGlobalRulesController.h"
#import "NFPAppRulesListController.h"
#import "NFPImportExportController.h"
#import "NFPLogsListController.h"

@interface NFPRootListController () <UITextViewDelegate>
@end

@implementation NFPRootListController

static NSString * const NFPRulesGroupSpecifierID = @"ROOT_RULES_GROUP";
static NSString * const NFPProjectPageURLString = @"https://github.com/tunecc/NotificationFilter";

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NFPLocalizedString(@"ROOT_TITLE");
}

- (NSArray *)specifiers {
    if (_specifiers) {
        return _specifiers;
    }

    NSMutableArray *specifiers = [NSMutableArray array];

    PSSpecifier *toggleGroup = [PSSpecifier emptyGroupSpecifier];
    [toggleGroup setProperty:NFPLocalizedString(@"ROOT_TOGGLE_FOOTER") forKey:PSFooterTextGroupKey];
    [specifiers addObject:toggleGroup];

    PSSpecifier *enabledSpecifier = [PSSpecifier preferenceSpecifierNamed:NFPLocalizedString(@"ROOT_ENABLE_FILTER")
                                                                   target:self
                                                                      set:@selector(setPreferenceValue:specifier:)
                                                                      get:@selector(readPreferenceValue:)
                                                                   detail:nil
                                                                     cell:PSSwitchCell
                                                                     edit:nil];
    [enabledSpecifier setProperty:NFEnabledKey forKey:PSKeyNameKey];
    [enabledSpecifier setProperty:@YES forKey:PSDefaultValueKey];
    [specifiers addObject:enabledSpecifier];

    PSSpecifier *deleteGroup = [PSSpecifier emptyGroupSpecifier];
    [deleteGroup setProperty:NFPLocalizedString(@"ROOT_DELETE_FOOTER") forKey:PSFooterTextGroupKey];
    [specifiers addObject:deleteGroup];

    PSSpecifier *deleteSpecifier = [PSSpecifier preferenceSpecifierNamed:NFPLocalizedString(@"ROOT_DELETE_FILTERED")
                                                                  target:self
                                                                     set:@selector(setPreferenceValue:specifier:)
                                                                     get:@selector(readPreferenceValue:)
                                                                  detail:nil
                                                                    cell:PSSwitchCell
                                                                    edit:nil];
    [deleteSpecifier setProperty:NFDeleteFilteredNotificationsKey forKey:PSKeyNameKey];
    [deleteSpecifier setProperty:@NO forKey:PSDefaultValueKey];
    [specifiers addObject:deleteSpecifier];

    PSSpecifier *pagesGroup = [PSSpecifier groupSpecifierWithID:NFPRulesGroupSpecifierID];
    [pagesGroup setProperty:NFPLocalizedString(@"ROOT_RULES_FOOTER") forKey:PSFooterTextGroupKey];
    [specifiers addObject:pagesGroup];

    [specifiers addObject:[self linkSpecifierWithName:NFPLocalizedString(@"ROOT_GLOBAL_RULES") action:@selector(openGlobalRules:)]];
    [specifiers addObject:[self linkSpecifierWithName:NFPLocalizedString(@"ROOT_APP_RULES") action:@selector(openAppRules:)]];
    [specifiers addObject:[self linkSpecifierWithName:NFPLocalizedString(@"ROOT_IMPORT_EXPORT") action:@selector(openImportExport:)]];
    [specifiers addObject:[self linkSpecifierWithName:NFPLocalizedString(@"ROOT_FILTERED_LOGS") action:@selector(openLogs:)]];

    _specifiers = [specifiers copy];
    return _specifiers;
}

- (PSSpecifier *)linkSpecifierWithName:(NSString *)name action:(SEL)action {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
                                                            target:self
                                                               set:nil
                                                               get:nil
                                                            detail:nil
                                                              cell:PSLinkCell
                                                              edit:nil];
    specifier->action = action;
    [specifier setProperty:NSStringFromSelector(action) forKey:PSActionKey];
    return specifier;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *preferences = [NFPreferences loadPreferences];
    NSString *key = [specifier propertyForKey:PSKeyNameKey];
    id value = preferences[key];
    if (value) {
        return value;
    }
    return [specifier propertyForKey:PSDefaultValueKey];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSMutableDictionary *preferences = [NFPreferences loadMutablePreferences];
    NSString *key = [specifier propertyForKey:PSKeyNameKey];
    if (key.length == 0) {
        return;
    }

    preferences[key] = value ?: [specifier propertyForKey:PSDefaultValueKey] ?: @NO;

    NSError *error = nil;
    if (![NFPreferences savePreferences:preferences error:&error]) {
        [self presentError:error];
        return;
    }

    [NFPreferences postPreferencesChangedNotification];
}

- (void)openGlobalRules:(PSSpecifier *)specifier {
    NFPGlobalRulesController *controller = [[NFPGlobalRulesController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)openAppRules:(PSSpecifier *)specifier {
    NFPAppRulesListController *controller = [[NFPAppRulesListController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)openLogs:(PSSpecifier *)specifier {
    NFPLogsListController *controller = [[NFPLogsListController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)openImportExport:(PSSpecifier *)specifier {
    NFPImportExportController *controller = [[NFPImportExportController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    [self.navigationController pushViewController:controller animated:YES];
}

- (BOOL)openProjectPageURL {
    NSURL *projectURL = [NSURL URLWithString:NFPProjectPageURLString];
    if (projectURL == nil) {
        return NO;
    }

    UIApplication *application = [UIApplication sharedApplication];
    if (@available(iOS 10.0, *)) {
        [application openURL:projectURL options:@{} completionHandler:nil];
        return YES;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [application openURL:projectURL];
#pragma clang diagnostic pop
    return YES;
}

- (BOOL)isRulesFooterSection:(NSInteger)section {
    NSInteger group = NSNotFound;
    NSInteger row = NSNotFound;
    if (![self getGroup:&group row:&row ofSpecifierID:NFPRulesGroupSpecifierID]) {
        return NO;
    }
    return group == section;
}

- (NSAttributedString *)rulesFooterAttributedText {
    NSString *footerText = NFPLocalizedString(@"ROOT_RULES_FOOTER") ?: @"";
    NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithString:footerText
                                                                                        attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:13.0],
        NSForegroundColorAttributeName: [UIColor secondaryLabelColor]
    }];

    NSString *linkText = NFPLocalizedString(@"ROOT_PROJECT_LINK_TEXT");
    NSRange linkRange = [footerText rangeOfString:linkText];
    if (linkRange.location != NSNotFound) {
        [attributedText addAttribute:NSLinkAttributeName value:NFPProjectPageURLString range:linkRange];
    }

    return attributedText;
}

- (UITextView *)rulesFooterTextViewWithWidth:(CGFloat)width {
    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, 1.0)];
    textView.backgroundColor = [UIColor clearColor];
    textView.delegate = self;
    textView.editable = NO;
    textView.scrollEnabled = NO;
    textView.selectable = YES;
    textView.attributedText = [self rulesFooterAttributedText];
    textView.linkTextAttributes = @{
        NSForegroundColorAttributeName: self.footerHyperlinkColor ?: [UIColor linkColor],
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)
    };
    textView.textContainerInset = UIEdgeInsetsZero;
    textView.textContainer.lineFragmentPadding = 0.0;
    return textView;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (![self isRulesFooterSection:section]) {
        return nil;
    }

    UIView *containerView = [[UIView alloc] initWithFrame:CGRectZero];
    containerView.backgroundColor = [UIColor clearColor];

    UITextView *textView = [self rulesFooterTextViewWithWidth:CGRectGetWidth(tableView.bounds) - 32.0];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:textView];

    [NSLayoutConstraint activateConstraints:@[
        [textView.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:4.0],
        [textView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor constant:20.0],
        [textView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-20.0],
        [textView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor constant:-8.0]
    ]];

    return containerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (![self isRulesFooterSection:section]) {
        return UITableViewAutomaticDimension;
    }

    CGFloat availableWidth = MAX(CGRectGetWidth(tableView.bounds) - 40.0, 0.0);
    UITextView *textView = [self rulesFooterTextViewWithWidth:availableWidth];
    CGSize fittingSize = [textView sizeThatFits:CGSizeMake(availableWidth, CGFLOAT_MAX)];
    return ceil(fittingSize.height) + 12.0;
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForFooterInSection:(NSInteger)section {
    if (![self isRulesFooterSection:section]) {
        return UITableViewAutomaticDimension;
    }
    return 60.0;
}

- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange interaction:(UITextItemInteraction)interaction API_AVAILABLE(ios(10.0)) {
    [self openProjectPageURL];
    return NO;
}

- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange {
    [self openProjectPageURL];
    return NO;
}

- (void)presentError:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFPLocalizedString(@"COMMON_SAVE_FAILED")
                                                                   message:error.localizedDescription ?: NFPLocalizedString(@"ROOT_SAVE_FAILED_MESSAGE")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
