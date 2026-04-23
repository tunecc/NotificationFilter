#import "NFPRootListController.h"
#import <Preferences/PSSpecifier.h>
#import "../Shared/NFPreferences.h"
#import "NFPLocalization.h"
#import "NFPGlobalRulesController.h"
#import "NFPAppRulesListController.h"
#import "NFPImportExportController.h"
#import "NFPLogsListController.h"

@implementation NFPRootListController

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

    PSSpecifier *pagesGroup = [PSSpecifier emptyGroupSpecifier];
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

- (void)presentError:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFPLocalizedString(@"COMMON_SAVE_FAILED")
                                                                   message:error.localizedDescription ?: NFPLocalizedString(@"ROOT_SAVE_FAILED_MESSAGE")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
