#import "AxsDuoDesktopActionEditor.h"
#import "AxsDuoDesktopActions.h"
#import "AxsDuoDesktopConfig.h"
#import "AxsDuoDesktopPreferences.h"
#import "AxsDuoDesktopRuntime.h"

@interface AxsDuoDesktopActionPicker : UITableViewController
@property (nonatomic, copy) NSArray<NSDictionary *> *records;
@property (nonatomic, copy) void (^choose)(NSDictionary *record);
- (instancetype)initWithRecords:(NSArray<NSDictionary *> *)records
                          title:(NSString *)title
                         choose:(void (^)(NSDictionary *record))choose;
@end

@implementation AxsDuoDesktopActionPicker

- (instancetype)initWithRecords:(NSArray<NSDictionary *> *)records
                          title:(NSString *)title
                         choose:(void (^)(NSDictionary *record))choose {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _records = [records copy];
        _choose = [choose copy];
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 54;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.records.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"picker"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"picker"];
        cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
        cell.imageView.bounds = CGRectMake(0, 0, 30, 30);
    }
    if (indexPath.row >= (NSInteger)self.records.count) return cell;
    NSDictionary *record = self.records[(NSUInteger)indexPath.row];
    cell.textLabel.text = record[@"title"];
    cell.detailTextLabel.text = axs_duodesktop_unavailableReason(record) ?: record[@"value"];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.imageView.image = axs_duodesktop_actionImage(record);
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)self.records.count) return;
    NSDictionary *record = self.records[(NSUInteger)indexPath.row];
    if (self.choose) self.choose(record);
}

@end

@interface AxsDuoDesktopActionEditor : UITableViewController
@property (nonatomic, copy) NSString *preferenceKey;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *records;
@end

@implementation AxsDuoDesktopActionEditor

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _preferenceKey = @"shortcutActions";
        _records = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"快捷动作";
    self.records = [axs_duodesktop_records(self.preferenceKey) mutableCopy];
    self.tableView.rowHeight = 62;
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(axs_duodesktop_close)];
    [self axs_duodesktop_updateNavigation];
}

- (void)axs_duodesktop_updateNavigation {
    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                        target:self
                                                                        action:@selector(axs_duodesktop_add)];
    UIBarButtonItem *edit = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:(self.editing ? UIBarButtonSystemItemDone : UIBarButtonSystemItemEdit)
                             target:self
                             action:@selector(axs_duodesktop_toggleEditing)];
    self.navigationItem.rightBarButtonItems = @[add, edit];
}

- (void)axs_duodesktop_toggleEditing {
    [self setEditing:!self.editing animated:YES];
    [self axs_duodesktop_updateNavigation];
}

- (void)axs_duodesktop_close {
    [self axs_duodesktop_save];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)axs_duodesktop_save {
    NSError *error = nil;
    if (!axs_duodesktop_saveRecords(self.preferenceKey, self.records, &error)) {
        axs_duodesktop_showMessage(error.localizedDescription ?: @"动作列表保存失败");
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.records.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"轻点项目可改名，编辑状态可拖动排序或删除；开关控制是否显示在桌面。修改立即保存。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"record"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"record"];
        cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
        cell.imageView.bounds = CGRectMake(0, 0, 30, 30);
    }
    if (indexPath.row >= (NSInteger)self.records.count) return cell;
    NSDictionary *record = self.records[(NSUInteger)indexPath.row];
    cell.textLabel.text = record[@"title"];
    cell.detailTextLabel.text = axs_duodesktop_unavailableReason(record) ?: record[@"value"];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.imageView.image = axs_duodesktop_actionImage(record);
    UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
    toggle.on = [record[@"enabled"] boolValue];
    toggle.tag = indexPath.row;
    [toggle addTarget:self action:@selector(axs_duodesktop_enabledChanged:)
     forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    return cell;
}

- (void)axs_duodesktop_enabledChanged:(UISwitch *)sender {
    NSInteger row = sender.tag;
    if (row < 0 || row >= (NSInteger)self.records.count) return;
    NSMutableDictionary *record = [self.records[(NSUInteger)row] mutableCopy];
    record[@"enabled"] = @(sender.on);
    self.records[(NSUInteger)row] = record;
    [self axs_duodesktop_save];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source
      toIndexPath:(NSIndexPath *)destination {
    if (source.row >= (NSInteger)self.records.count) return;
    if (destination.row >= (NSInteger)self.records.count) return;
    id record = self.records[(NSUInteger)source.row];
    [self.records removeObjectAtIndex:(NSUInteger)source.row];
    [self.records insertObject:record atIndex:(NSUInteger)destination.row];
    [self axs_duodesktop_save];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style
    forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style != UITableViewCellEditingStyleDelete) return;
    if (indexPath.row >= (NSInteger)self.records.count) return;
    [self.records removeObjectAtIndex:(NSUInteger)indexPath.row];
    [self axs_duodesktop_save];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)axs_duodesktop_addRecord:(NSDictionary *)record {
    NSMutableDictionary *normalized = [axs_duodesktop_normalizeRecord(record) mutableCopy];
    if (!normalized) return;
    normalized[@"id"] = NSUUID.UUID.UUIDString;
    [self.records addObject:normalized];
    [self axs_duodesktop_save];
    [self.tableView reloadData];
}

- (void)axs_duodesktop_pickRecords:(NSArray<NSDictionary *> *)records title:(NSString *)title {
    AxsDuoDesktopActionPicker *picker =
        [[AxsDuoDesktopActionPicker alloc] initWithRecords:records title:title choose:nil];
    __weak typeof(self) weakSelf = self;
    picker.choose = ^(NSDictionary *record) {
        AxsDuoDesktopActionEditor *editor = weakSelf;
        if (!editor) return;
        [editor axs_duodesktop_addRecord:record];
        [editor.navigationController popViewControllerAnimated:YES];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)axs_duodesktop_addTextWithType:(NSString *)type record:(NSDictionary *)record {
    BOOL isURL = [type isEqual:@"url"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:
        (isURL ? @"网址" : @"快捷指令")
        message:(isURL ? @"输入完整 URL，例如 https://example.com" : @"输入快捷指令 App 中的准确名称")
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"显示名称";
        field.text = record[@"title"];
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = isURL ? @"https://" : @"快捷指令名称";
        field.text = record[@"value"];
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
        AxsDuoDesktopActionEditor *editor = weakSelf;
        if (!editor) return;
        NSDictionary *candidate = @{@"type": type,
                                    @"title": alert.textFields[0].text ?: @"",
                                    @"value": alert.textFields[1].text ?: @"",
                                    @"enabled": @YES};
        NSDictionary *normalized = axs_duodesktop_normalizeRecord(candidate);
        if (!normalized) {
            axs_duodesktop_showMessage(isURL ? @"URL 无效，需要包含 scheme" : @"请输入快捷指令名称");
            return;
        }
        [editor.records addObject:normalized];
        [editor axs_duodesktop_save];
        [editor.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)axs_duodesktop_add {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"添加快捷动作"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"系统工具" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
        AxsDuoDesktopActionEditor *editor = weakSelf;
        [editor axs_duodesktop_pickRecords:axs_duodesktop_catalog() title:@"系统工具"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"应用" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
        AxsDuoDesktopActionEditor *editor = weakSelf;
        if (!editor) return;
        NSArray *applications = axs_duodesktop_applicationRecords();
        if (!applications.count) {
            axs_duodesktop_showMessage(@"当前进程无法读取已安装应用列表");
            return;
        }
        [editor axs_duodesktop_pickRecords:applications title:@"应用"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"网址" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
        [weakSelf axs_duodesktop_addTextWithType:@"url" record:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"快捷指令" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
        [weakSelf axs_duodesktop_addTextWithType:@"shortcut" record:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)self.records.count) return;
    NSDictionary *record = self.records[(NSUInteger)indexPath.row];
    if ([record[@"type"] isEqual:@"url"] || [record[@"type"] isEqual:@"shortcut"]) {
        [self axs_duodesktop_addTextWithType:record[@"type"] record:record];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:record[@"title"]
        message:axs_duodesktop_unavailableReason(record) ?: record[@"value"]
        preferredStyle:UIAlertControllerStyleAlert];
    NSUInteger row = (NSUInteger)indexPath.row;
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"修改名称" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
        UIAlertController *rename = [UIAlertController alertControllerWithTitle:@"显示名称"
            message:nil preferredStyle:UIAlertControllerStyleAlert];
        [rename addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.text = record[@"title"];
        }];
        [rename addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *confirm) {
            AxsDuoDesktopActionEditor *editor = weakSelf;
            if (!editor || row >= editor.records.count) return;
            NSMutableDictionary *updated = [editor.records[row] mutableCopy];
            NSString *title = rename.textFields.firstObject.text;
            if (title.length) updated[@"title"] = title;
            editor.records[row] = updated;
            [editor axs_duodesktop_save];
            [editor.tableView reloadData];
        }]];
        [rename addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [weakSelf presentViewController:rename animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

void axs_duodesktop_presentActionEditor(UIViewController *presenter) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            axs_duodesktop_presentActionEditor(presenter);
        });
        return;
    }
    UIViewController *host = presenter ?: axs_duodesktop_presenter();
    if (!host || host.presentedViewController) return;
    AxsDuoDesktopActionEditor *editor = [AxsDuoDesktopActionEditor new];
    UINavigationController *navigation =
        [[UINavigationController alloc] initWithRootViewController:editor];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    [host presentViewController:navigation animated:YES completion:nil];
}
