#import "AxsDuoDesktopRootListController.h"
#import "AxsDuoDesktopPreferences.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>


@interface AxsDuoDesktopRootListController ()
@end

@implementation AxsDuoDesktopRootListController

- (instancetype)init {
    self = [super init];
    if (self) self.title = @"DuoDesktop";
    return self;
}

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        // Parse the resource ourselves. -loadSpecifiersFromPlistName: only
        // understands one root shape, and the format used by this project
        // ({"title", "items"}) is not the one it expects; parsing here accepts
        // both a bare specifier array and the title/items dictionary, so the
        // page can never end up empty because of a format mismatch.
        NSArray *loaded = [self axs_duodesktop_specifiersFromPlist:@"AxsDuoDesktopRoot"];
        NSMutableArray *items = loaded.count ? [loaded mutableCopy]
            : [[self axs_duodesktop_fallbackSpecifiers] mutableCopy];
        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"关于我们" target:self
                     set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [self axs_duodesktop_addButton:@"Sileo 越狱源" action:@selector(axs_duodesktop_openRepository:) to:items];
        [self axs_duodesktop_addButton:@"TG分享频道" action:@selector(axs_duodesktop_openTelegram:) to:items];
        [self axs_duodesktop_addButton:@"QQ交流群组" action:@selector(axs_duodesktop_openQQ:) to:items];
        _specifiers = items;
    }
    return _specifiers;
}

- (NSString *)axs_duodesktop_plistPath:(NSString *)name {
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSString *path = [bundle pathForResource:name ofType:@"plist"];
    if (path.length) return path;
    // Fall back to the path adjacent to the executable for odd bundle layouts.
    NSString *candidate = [bundle.bundlePath stringByAppendingPathComponent:
        [name stringByAppendingPathExtension:@"plist"]];
    return [NSFileManager.defaultManager fileExistsAtPath:candidate] ? candidate : nil;
}

- (PSCellType)axs_duodesktop_cellType:(NSString *)name item:(NSDictionary *)item {
    if ([name isEqualToString:@"PSGroupCell"]) return PSGroupCell;
    if ([name isEqualToString:@"PSButtonCell"]) return PSButtonCell;
    if ([name isEqualToString:@"PSLinkCell"]) return PSLinkCell;
    if ([name isEqualToString:@"PSStaticTextCell"]) return PSStaticTextCell;
    if ([name isEqualToString:@"PSSwitchCell"]) return PSSwitchCell;
    return item[@"key"] ? PSSwitchCell : PSStaticTextCell;
}

- (NSArray<PSSpecifier *> *)axs_duodesktop_specifiersFromPlist:(NSString *)name {
    NSString *path = [self axs_duodesktop_plistPath:name];
    if (!path.length) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    id root = data ? [NSPropertyListSerialization propertyListWithData:data options:0
                                                               format:NULL error:NULL] : nil;
    NSArray *entries = nil;
    if ([root isKindOfClass:[NSArray class]]) {
        entries = root;
    } else if ([root isKindOfClass:[NSDictionary class]]) {
        id title = ((NSDictionary *)root)[@"title"];
        if ([title isKindOfClass:[NSString class]] && [title length]) self.title = title;
        id items = ((NSDictionary *)root)[@"items"];
        if ([items isKindOfClass:[NSArray class]]) entries = items;
    }
    if (!entries.count) return nil;

    NSMutableArray<PSSpecifier *> *specifiers = [NSMutableArray arrayWithCapacity:entries.count];
    for (NSDictionary *entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *cell = [entry[@"cell"] isKindOfClass:[NSString class]] ? entry[@"cell"] : nil;
        PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:entry[@"label"] ?: @""
            target:self
            set:@selector(setPreferenceValue:specifier:)
            get:@selector(readPreferenceValue:)
            detail:nil
            cell:[self axs_duodesktop_cellType:cell item:entry]
            edit:nil];
        for (NSString *key in entry) {
            if ([key isEqualToString:@"cell"] || [key isEqualToString:@"label"]) continue;
            [specifier setProperty:entry[key] forKey:key];
        }
        [specifiers addObject:specifier];
    }
    return specifiers.count ? specifiers : nil;
}

- (void)axs_duodesktop_addButton:(NSString *)title action:(SEL)action to:(NSMutableArray *)items {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:title target:self
                          set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    item.buttonAction = action;
    [items addObject:item];
}

- (PSSpecifier *)axs_duodesktop_switch:(NSString *)title key:(NSString *)key
                              fallback:(BOOL)fallback {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:title target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:)
        detail:nil cell:PSSwitchCell edit:nil];
    [item setProperty:key forKey:@"key"];
    [item setProperty:AxsDuoDesktopPreferencesDomain forKey:@"defaults"];
    [item setProperty:@(fallback) forKey:@"default"];
    return item;
}

// Mirrors the shipped plist; only used when the resource cannot be loaded.
- (NSArray<PSSpecifier *> *)axs_duodesktop_fallbackSpecifiers {
    NSMutableArray<PSSpecifier *> *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier preferenceSpecifierNamed:@"基本设置" target:nil
        set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
    [group setProperty:@"关闭后桌面恢复原生布局，已保存的快捷动作不会被删除。" forKey:@"footerText"];
    [items addObject:group];
    [items addObject:[self axs_duodesktop_switch:@"启用插件" key:@"enabled" fallback:NO]];
    [items addObject:[self axs_duodesktop_switch:@"时钟页面" key:@"showClock" fallback:YES]];
    [items addObject:[self axs_duodesktop_switch:@"媒体页面" key:@"showMedia" fallback:YES]];
    [items addObject:[self axs_duodesktop_switch:@"日历页面" key:@"showCalendar" fallback:YES]];
    [items addObject:[self axs_duodesktop_switch:@"快捷动作页面" key:@"showShortcuts" fallback:YES]];
    [items addObject:[self axs_duodesktop_switch:@"启用侧栏" key:@"railEnabled" fallback:YES]];
    [items addObject:[self axs_duodesktop_switch:@"输出调试日志" key:@"debugLogging" fallback:NO]];
    return items;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return nil;
    return axs_duodesktop_readPreferences()[key] ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return;
    NSError *error = nil;
    if (!axs_duodesktop_writePreference(key, value, &error)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置未保存"
            message:error.localizedDescription ?: @"请检查配置文件路径和写入权限。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self reloadSpecifiers];
    }
}

- (void)axs_duodesktop_openURL:(NSURL *)url fallback:(NSURL *)fallback {
    if (!url) return;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        if (success) return;
        if (fallback) {
            [self axs_duodesktop_openURL:fallback fallback:nil];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法打开链接"
                message:@"请确认已安装对应应用。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }];
}

- (void)axs_duodesktop_openRepository:(id)sender {
    NSString *source = @"https://axs66.github.io/pro";
    NSString *encoded = [source stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSURL *primary = [NSURL URLWithString:[@"sileo://source/" stringByAppendingString:encoded ?: source]];
    [self axs_duodesktop_openURL:primary fallback:[NSURL URLWithString:source]];
}

- (void)axs_duodesktop_openTelegram:(id)sender {
    [self axs_duodesktop_openURL:[NSURL URLWithString:@"tg://resolve?domain=wxfx8"]
                   fallback:[NSURL URLWithString:@"https://t.me/wxfx8"]];
}

- (void)axs_duodesktop_openQQ:(id)sender {
    [self axs_duodesktop_openURL:[NSURL URLWithString:@"mqqapi://card/show_pslcard?src_type=internal&version=1&uin=678055716&card_type=group&source=qrcode"] fallback:nil];
}


@end
