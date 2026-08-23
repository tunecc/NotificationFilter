#import "NFPImportExportController.h"
#import "../Shared/NFPreferences.h"
#import "NFPLocalization.h"
#import "NFPJSONImportController.h"
#import "NFPImportExportPayload.h"
#import "NFPAppRulesExportPickerController.h"
#import "NFPAppInfoProvider.h"

typedef NS_ENUM(NSInteger, NFPImportExportSection) {
    NFPImportExportSectionExport = 0,
    NFPImportExportSectionImport
};

@implementation NFPImportExportController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NFPLocalizedString(@"IMPORT_EXPORT_TITLE");
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == NFPImportExportSectionExport ? 3 : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == NFPImportExportSectionExport ? NFPLocalizedString(@"IMPORT_EXPORT_SECTION_EXPORT") : NFPLocalizedString(@"IMPORT_EXPORT_SECTION_IMPORT");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == NFPImportExportSectionExport) {
        return NFPLocalizedString(@"IMPORT_EXPORT_FOOTER_EXPORT");
    }
    return NFPLocalizedString(@"IMPORT_EXPORT_FOOTER_IMPORT");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"action"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    if (indexPath.section == NFPImportExportSectionExport) {
        switch (indexPath.row) {
            case 0:
                cell.textLabel.text = NFPLocalizedString(@"IMPORT_EXPORT_EXPORT_JSON");
                cell.detailTextLabel.text = NFPLocalizedString(@"IMPORT_EXPORT_EXPORT_JSON_DETAIL");
                break;
            case 1:
                cell.textLabel.text = NFPLocalizedString(@"IMPORT_EXPORT_COPY_JSON");
                cell.detailTextLabel.text = NFPLocalizedString(@"IMPORT_EXPORT_COPY_JSON_DETAIL");
                break;
            default:
                cell.textLabel.text = NFPLocalizedString(@"IMPORT_EXPORT_EXPORT_APP_RULES");
                cell.detailTextLabel.text = NFPLocalizedString(@"IMPORT_EXPORT_EXPORT_APP_RULES_DETAIL");
                break;
        }
    } else {
        if (indexPath.row == 0) {
            cell.textLabel.text = NFPLocalizedString(@"IMPORT_EXPORT_IMPORT_PASTEBOARD");
            cell.detailTextLabel.text = NFPLocalizedString(@"IMPORT_EXPORT_IMPORT_PASTEBOARD_DETAIL");
        } else {
            cell.textLabel.text = NFPLocalizedString(@"IMPORT_EXPORT_IMPORT_MANUAL");
            cell.detailTextLabel.text = NFPLocalizedString(@"IMPORT_EXPORT_IMPORT_MANUAL_DETAIL");
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == NFPImportExportSectionExport) {
        switch (indexPath.row) {
            case 0:
                [self exportFullConfigToShareSheet];
                break;
            case 1:
                [self copyFullConfigJSONToPasteboard];
                break;
            default:
                [self openAppRulesExportPicker];
                break;
        }
        return;
    }

    if (indexPath.row == 0) {
        [self importFromPasteboard];
    } else {
        __weak typeof(self) weakSelf = self;
        NFPJSONImportController *controller = [[NFPJSONImportController alloc] initWithInitialText:@""
                                                                                        importHandler:^(NSDictionary *payload, NSError *error) {
            if (error) {
                [weakSelf presentAlertWithTitle:NFPLocalizedString(@"COMMON_IMPORT_FAILED")
                                        message:error.localizedDescription ?: NFPLocalizedString(@"JSON_PARSE_FAILED_MESSAGE")];
                return;
            }

            [weakSelf applyImportedPayload:payload];
        }];
        [self.navigationController pushViewController:controller animated:YES];
    }
}

#pragma mark - Full config export

- (NSDictionary *)fullConfigPayload {
    return [NFPImportExportPayload fullConfigPayloadFromPreferences:[NFPreferences loadPreferences]];
}

- (void)exportFullConfigToShareSheet {
    NSError *error = nil;
    NSString *jsonString = [NFPImportExportPayload jsonStringFromPayload:[self fullConfigPayload] error:&error];
    if (!jsonString) {
        [self presentAlertWithTitle:NFPLocalizedString(@"COMMON_EXPORT_FAILED")
                            message:error.localizedDescription ?: NFPLocalizedString(@"JSON_GENERATE_FAILED_MESSAGE")];
        return;
    }

    UIActivityViewController *activityController = [[UIActivityViewController alloc] initWithActivityItems:@[jsonString ?: @""]
                                                                                     applicationActivities:nil];
    [self presentViewController:activityController animated:YES completion:nil];
}

- (void)copyFullConfigJSONToPasteboard {
    NSError *error = nil;
    NSString *jsonString = [NFPImportExportPayload jsonStringFromPayload:[self fullConfigPayload] error:&error];
    if (!jsonString) {
        [self presentAlertWithTitle:NFPLocalizedString(@"IMPORT_EXPORT_COPY_FAILED")
                            message:error.localizedDescription ?: NFPLocalizedString(@"JSON_GENERATE_FAILED_MESSAGE")];
        return;
    }

    [UIPasteboard generalPasteboard].string = jsonString;
    [self presentAlertWithTitle:NFPLocalizedString(@"IMPORT_EXPORT_COPIED")
                        message:NFPLocalizedString(@"IMPORT_EXPORT_COPIED_MESSAGE")];
}

#pragma mark - App rules export picker

- (void)openAppRulesExportPicker {
    __weak typeof(self) weakSelf = self;
    NFPAppRulesExportPickerController *controller = [[NFPAppRulesExportPickerController alloc] initWithSelectedBundleIdentifiers:@[]
                                                                                                                 selectionHandler:^(NSArray<NSString *> *selectedBundleIdentifiers) {
        [weakSelf presentAppRulesExportActionsForBundleIdentifiers:selectedBundleIdentifiers];
    }];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)presentAppRulesExportActionsForBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers {
    if (bundleIdentifiers.count == 0) {
        [self presentAlertWithTitle:NFPLocalizedString(@"IMPORT_EXPORT_EXPORT_APP_RULES")
                            message:NFPLocalizedString(@"IMPORT_EXPORT_EXPORT_APP_RULES_NONE_MESSAGE")];
        return;
    }

    NSDictionary<NSString *, NSDictionary *> *apps = [self appsPayloadDictionaryForBundleIdentifiers:bundleIdentifiers];
    NSDictionary *payload = [NFPImportExportPayload appRulesBundlePayloadForApps:apps];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFPLocalizedString(@"IMPORT_EXPORT_EXPORT_APP_RULES")
                                                                   message:NFPLocalizedString(@"IMPORT_EXPORT_EXPORT_APP_RULES_ACTIONS_MESSAGE")
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"IMPORT_EXPORT_COPY_TO_PASTEBOARD")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf copyAppRulesPayloadToPasteboard:payload];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"IMPORT_EXPORT_SHARE")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf shareAppRulesPayload:payload];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_CANCEL")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.0, 1.0);
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSDictionary<NSString *, NSDictionary *> *)appsPayloadDictionaryForBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers {
    NSDictionary *preferences = [NFPreferences loadPreferences];
    NSMutableDictionary<NSString *, NSDictionary *> *apps = [NSMutableDictionary dictionary];
    for (NSString *bundleIdentifier in bundleIdentifiers) {
        if (![bundleIdentifier isKindOfClass:[NSString class]] || [bundleIdentifier length] == 0) {
            continue;
        }
        NSDictionary *rules = [NFPreferences rulesForBundleIdentifier:bundleIdentifier
                                                     fromPreferences:preferences];
        apps[bundleIdentifier] = rules;
    }
    return apps;
}

- (void)copyAppRulesPayloadToPasteboard:(NSDictionary *)payload {
    NSError *error = nil;
    NSString *jsonString = [NFPImportExportPayload jsonStringFromPayload:payload error:&error];
    if (!jsonString) {
        [self presentAlertWithTitle:NFPLocalizedString(@"IMPORT_EXPORT_COPY_FAILED")
                            message:error.localizedDescription ?: NFPLocalizedString(@"JSON_GENERATE_FAILED_MESSAGE")];
        return;
    }

    [UIPasteboard generalPasteboard].string = jsonString;
    [self presentAlertWithTitle:NFPLocalizedString(@"IMPORT_EXPORT_COPIED")
                        message:NFPLocalizedString(@"IMPORT_EXPORT_COPIED_MESSAGE")];
}

- (void)shareAppRulesPayload:(NSDictionary *)payload {
    NSError *error = nil;
    NSString *jsonString = [NFPImportExportPayload jsonStringFromPayload:payload error:&error];
    if (!jsonString) {
        [self presentAlertWithTitle:NFPLocalizedString(@"COMMON_EXPORT_FAILED")
                            message:error.localizedDescription ?: NFPLocalizedString(@"JSON_GENERATE_FAILED_MESSAGE")];
        return;
    }

    UIActivityViewController *activityController = [[UIActivityViewController alloc] initWithActivityItems:@[jsonString ?: @""]
                                                                                     applicationActivities:nil];
    [self presentViewController:activityController animated:YES completion:nil];
}

#pragma mark - Import

- (void)importFromPasteboard {
    NSString *clipboardText = [UIPasteboard generalPasteboard].string;
    if (clipboardText.length == 0) {
        [self presentAlertWithTitle:NFPLocalizedString(@"COMMON_IMPORT_FAILED")
                            message:NFPLocalizedString(@"IMPORT_EXPORT_EMPTY_PASTEBOARD_MESSAGE")];
        return;
    }

    NSError *error = nil;
    NSDictionary *payload = [NFPImportExportPayload payloadFromJSONString:clipboardText error:&error];
    if (!payload) {
        [self presentAlertWithTitle:NFPLocalizedString(@"COMMON_IMPORT_FAILED")
                            message:error.localizedDescription ?: NFPLocalizedString(@"JSON_PARSE_FAILED_MESSAGE")];
        return;
    }

    [self applyImportedPayload:payload];
}

- (void)applyImportedPayload:(NSDictionary *)payload {
    NSMutableDictionary *preferences = [NFPreferences loadMutablePreferences];
    NFPImportExportPayloadResult *result = [NFPImportExportPayload applyPayload:payload toMutablePreferences:preferences];

    if (result.error) {
        [self presentAlertWithTitle:NFPLocalizedString(@"COMMON_IMPORT_FAILED")
                            message:result.error.localizedDescription ?: NFPLocalizedString(@"JSON_PARSE_FAILED_MESSAGE")];
        return;
    }

    NSError *error = nil;
    if (![NFPreferences savePreferences:preferences error:&error]) {
        [self presentAlertWithTitle:NFPLocalizedString(@"COMMON_IMPORT_FAILED")
                            message:error.localizedDescription ?: NFPLocalizedString(@"IMPORT_EXPORT_SAVE_FAILED_MESSAGE")];
        return;
    }

    [NFPreferences postPreferencesChangedNotification];
    [self presentAlertWithTitle:NFPLocalizedString(@"COMMON_IMPORT_SUCCEEDED")
                        message:[self importSuccessMessageForResult:result]];
}

- (NSString *)importSuccessMessageForResult:(NFPImportExportPayloadResult *)result {
    switch (result.kind) {
        case NFPPayloadKindAppRules: {
            NSString *displayName = [[NFPAppInfoProvider sharedProvider] displayNameForBundleIdentifier:result.bundleIdentifier];
            return [NSString stringWithFormat:NFPLocalizedString(@"IMPORT_EXPORT_IMPORT_APP_RULES_SUCCEEDED_MESSAGE"), displayName ?: result.bundleIdentifier];
        }
        case NFPPayloadKindAppRulesBundle:
            return [NSString stringWithFormat:NFPLocalizedString(@"IMPORT_EXPORT_IMPORT_APP_RULES_BUNDLE_SUCCEEDED_MESSAGE"), (long)result.appCount];
        case NFPPayloadKindFullConfig:
            return NFPLocalizedString(@"IMPORT_EXPORT_IMPORT_SUCCEEDED_MESSAGE");
        case NFPPayloadKindUnknown:
        default:
            return NFPLocalizedString(@"IMPORT_EXPORT_IMPORT_SUCCEEDED_MESSAGE");
    }
}

- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
