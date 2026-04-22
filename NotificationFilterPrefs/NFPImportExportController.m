#import "NFPImportExportController.h"
#import "../Shared/NFPreferences.h"
#import "NFPLocalization.h"
#import "NFPJSONImportController.h"

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
    return 2;
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
        if (indexPath.row == 0) {
            cell.textLabel.text = NFPLocalizedString(@"IMPORT_EXPORT_EXPORT_JSON");
            cell.detailTextLabel.text = NFPLocalizedString(@"IMPORT_EXPORT_EXPORT_JSON_DETAIL");
        } else {
            cell.textLabel.text = NFPLocalizedString(@"IMPORT_EXPORT_COPY_JSON");
            cell.detailTextLabel.text = NFPLocalizedString(@"IMPORT_EXPORT_COPY_JSON_DETAIL");
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
        if (indexPath.row == 0) {
            [self exportToShareSheet];
        } else {
            [self copyJSONToPasteboard];
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

            [weakSelf persistImportedPayload:payload];
        }];
        [self.navigationController pushViewController:controller animated:YES];
    }
}

- (NSDictionary *)exportPayload {
    return [NFPreferences normalizedPreferencesFromDictionary:[NFPreferences loadPreferences]];
}

- (NSData *)exportJSONData:(NSError **)error {
    return [NSJSONSerialization dataWithJSONObject:[self exportPayload]
                                           options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                             error:error];
}

- (void)exportToShareSheet {
    NSError *error = nil;
    NSData *jsonData = [self exportJSONData:&error];
    if (!jsonData) {
        [self presentAlertWithTitle:NFPLocalizedString(@"COMMON_EXPORT_FAILED")
                            message:error.localizedDescription ?: NFPLocalizedString(@"JSON_GENERATE_FAILED_MESSAGE")];
        return;
    }

    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    UIActivityViewController *activityController = [[UIActivityViewController alloc] initWithActivityItems:@[jsonString ?: @""]
                                                                                     applicationActivities:nil];
    [self presentViewController:activityController animated:YES completion:nil];
}

- (void)copyJSONToPasteboard {
    NSError *error = nil;
    NSData *jsonData = [self exportJSONData:&error];
    if (!jsonData) {
        [self presentAlertWithTitle:NFPLocalizedString(@"IMPORT_EXPORT_COPY_FAILED")
                            message:error.localizedDescription ?: NFPLocalizedString(@"JSON_GENERATE_FAILED_MESSAGE")];
        return;
    }

    [UIPasteboard generalPasteboard].string = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    [self presentAlertWithTitle:NFPLocalizedString(@"IMPORT_EXPORT_COPIED")
                        message:NFPLocalizedString(@"IMPORT_EXPORT_COPIED_MESSAGE")];
}

- (void)importFromPasteboard {
    NSString *clipboardText = [UIPasteboard generalPasteboard].string;
    if (clipboardText.length == 0) {
        [self presentAlertWithTitle:NFPLocalizedString(@"COMMON_IMPORT_FAILED")
                            message:NFPLocalizedString(@"IMPORT_EXPORT_EMPTY_PASTEBOARD_MESSAGE")];
        return;
    }

    NSError *error = nil;
    NSDictionary *payload = [NFPJSONImportController payloadFromJSONString:clipboardText error:&error];
    if (!payload) {
        [self presentAlertWithTitle:NFPLocalizedString(@"COMMON_IMPORT_FAILED")
                            message:error.localizedDescription ?: NFPLocalizedString(@"JSON_PARSE_FAILED_MESSAGE")];
        return;
    }

    [self persistImportedPayload:payload];
}

- (void)persistImportedPayload:(NSDictionary *)payload {
    NSDictionary *normalizedPreferences = [NFPreferences normalizedPreferencesFromDictionary:payload];
    NSError *error = nil;
    if (![NFPreferences savePreferences:normalizedPreferences error:&error]) {
        [self presentAlertWithTitle:NFPLocalizedString(@"COMMON_IMPORT_FAILED")
                            message:error.localizedDescription ?: NFPLocalizedString(@"IMPORT_EXPORT_SAVE_FAILED_MESSAGE")];
        return;
    }

    [NFPreferences postPreferencesChangedNotification];
    [self presentAlertWithTitle:NFPLocalizedString(@"COMMON_IMPORT_SUCCEEDED")
                        message:NFPLocalizedString(@"IMPORT_EXPORT_IMPORT_SUCCEEDED_MESSAGE")];
}

- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NFPLocalizedString(@"COMMON_OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
