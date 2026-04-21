#import "NFPImportExportController.h"
#import "../Shared/NFPreferences.h"
#import "NFPJSONImportController.h"

typedef NS_ENUM(NSInteger, NFPImportExportSection) {
    NFPImportExportSectionExport = 0,
    NFPImportExportSectionImport
};

@implementation NFPImportExportController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"规则导入导出";
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == NFPImportExportSectionExport ? @"导出" : @"导入";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == NFPImportExportSectionExport) {
        return @"导出的 JSON 只包含过滤规则配置，不包含过滤日志。";
    }
    return @"导入会覆盖当前全部规则配置。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"action"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    if (indexPath.section == NFPImportExportSectionExport) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"导出为 JSON";
            cell.detailTextLabel.text = @"使用系统分享面板导出当前规则";
        } else {
            cell.textLabel.text = @"复制 JSON 到剪贴板";
            cell.detailTextLabel.text = @"便于手动备份或跨设备传递";
        }
    } else {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"从剪贴板导入";
            cell.detailTextLabel.text = @"读取剪贴板中的 JSON 并覆盖当前规则";
        } else {
            cell.textLabel.text = @"手动粘贴导入";
            cell.detailTextLabel.text = @"打开编辑器，粘贴 JSON 后导入";
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
                [weakSelf presentAlertWithTitle:@"导入失败" message:error.localizedDescription ?: @"JSON 无法解析。"];
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
        [self presentAlertWithTitle:@"导出失败" message:error.localizedDescription ?: @"无法生成 JSON。"];
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
        [self presentAlertWithTitle:@"复制失败" message:error.localizedDescription ?: @"无法生成 JSON。"];
        return;
    }

    [UIPasteboard generalPasteboard].string = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    [self presentAlertWithTitle:@"已复制" message:@"当前规则 JSON 已复制到剪贴板。"];
}

- (void)importFromPasteboard {
    NSString *clipboardText = [UIPasteboard generalPasteboard].string;
    if (clipboardText.length == 0) {
        [self presentAlertWithTitle:@"导入失败" message:@"剪贴板中没有可用的 JSON 文本。"];
        return;
    }

    NSError *error = nil;
    NSDictionary *payload = [NFPJSONImportController payloadFromJSONString:clipboardText error:&error];
    if (!payload) {
        [self presentAlertWithTitle:@"导入失败" message:error.localizedDescription ?: @"JSON 无法解析。"];
        return;
    }

    [self persistImportedPayload:payload];
}

- (void)persistImportedPayload:(NSDictionary *)payload {
    NSDictionary *normalizedPreferences = [NFPreferences normalizedPreferencesFromDictionary:payload];
    NSError *error = nil;
    if (![NFPreferences savePreferences:normalizedPreferences error:&error]) {
        [self presentAlertWithTitle:@"导入失败" message:error.localizedDescription ?: @"无法写入偏好配置。"];
        return;
    }

    [NFPreferences postPreferencesChangedNotification];
    [self presentAlertWithTitle:@"导入成功" message:@"过滤规则已覆盖为导入内容。"];
}

- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
