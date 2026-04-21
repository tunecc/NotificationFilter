#import "NFPRootListController.h"
#import <Preferences/PSSpecifier.h>
#import "../Shared/NFPreferences.h"
#import "NFPGlobalRulesController.h"
#import "NFPAppRulesListController.h"
#import "NFPImportExportController.h"
#import "NFPLogsListController.h"

@implementation NFPRootListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"通知过滤";
}

- (NSArray *)specifiers {
    if (_specifiers) {
        return _specifiers;
    }

    NSMutableArray *specifiers = [NSMutableArray array];

    PSSpecifier *toggleGroup = [PSSpecifier emptyGroupSpecifier];
    [toggleGroup setProperty:@"关闭主开关后，所有通知都会直接放行。" forKey:PSFooterTextGroupKey];
    [specifiers addObject:toggleGroup];

    PSSpecifier *enabledSpecifier = [PSSpecifier preferenceSpecifierNamed:@"启用过滤"
                                                                   target:self
                                                                      set:@selector(setPreferenceValue:specifier:)
                                                                      get:@selector(readPreferenceValue:)
                                                                   detail:nil
                                                                     cell:PSSwitchCell
                                                                     edit:nil];
    [enabledSpecifier setProperty:NFEnabledKey forKey:PSKeyNameKey];
    [enabledSpecifier setProperty:@YES forKey:PSDefaultValueKey];
    [specifiers addObject:enabledSpecifier];

    PSSpecifier *pagesGroup = [PSSpecifier emptyGroupSpecifier];
    [pagesGroup setProperty:@"全局规则和单应用规则叠加生效；命中排除规则优先放行。" forKey:PSFooterTextGroupKey];
    [specifiers addObject:pagesGroup];

    [specifiers addObject:[self linkSpecifierWithName:@"全局规则" action:@selector(openGlobalRules:)]];
    [specifiers addObject:[self linkSpecifierWithName:@"应用规则" action:@selector(openAppRules:)]];
    [specifiers addObject:[self linkSpecifierWithName:@"规则导入导出" action:@selector(openImportExport:)]];
    [specifiers addObject:[self linkSpecifierWithName:@"已过滤通知" action:@selector(openLogs:)]];

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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存失败"
                                                                   message:error.localizedDescription ?: @"无法写入配置。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
