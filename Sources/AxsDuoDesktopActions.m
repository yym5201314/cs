#import "AxsDuoDesktopActions.h"
#import "AxsDuoDesktopConfig.h"
#import "AxsDuoDesktopPreferences.h"
#import "AxsDuoDesktopRuntime.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <notify.h>
#import <math.h>
#import <string.h>

NSString * const AxsDuoDesktopActionsChanged = @"com.axs.duodesktop.actions-changed";

static NSString * const AxsDuoDesktopRecordKey = @"shortcutActions";

#pragma mark - Invocation

static const char *axs_duodesktop_unqualified(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type ?: "";
}

static BOOL axs_duodesktop_isKind(const char *raw, NSString *kind) {
    const char *type = axs_duodesktop_unqualified(raw);
    if ([kind isEqualToString:@"object"]) return type[0] == '@' && type[1] != '?';
    if ([kind isEqualToString:@"block"]) return !strcmp(type, "@?");
    if ([kind isEqualToString:@"void"]) return !strcmp(type, "v");
    if ([kind isEqualToString:@"number"]) return strlen(type) == 1 && strchr("BcCsSiIlLqQfd", *type);
    if ([kind isEqualToString:@"bool"]) return !strcmp(type, "B") || !strcmp(type, "c");
    return NO;
}

static NSError *axs_duodesktop_error(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"com.axs.duodesktop.actions" code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"操作不可用"}];
}

// Arity, return kind and every argument kind are verified before arguments are
// written, then scalars are marshalled with their exact width.
static id axs_duodesktop_invoke(id target, NSString *name, NSString *returnKind,
                                NSArray<NSString *> *kinds, NSArray *arguments, BOOL *accepted) {
    if (accepted) *accepted = NO;
    if (!target || arguments.count != kinds.count) return nil;
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(object_getClass(target), selector);
    if (!method) return nil;
    NSMethodSignature *signature =
        [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (!signature || signature.numberOfArguments != arguments.count + 2) return nil;
    if (!axs_duodesktop_isKind(signature.methodReturnType, returnKind)) return nil;
    for (NSUInteger index = 0; index < arguments.count; index++) {
        if (!axs_duodesktop_isKind([signature getArgumentTypeAtIndex:index + 2], kinds[index])) return nil;
    }
    @try {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = target;
        invocation.selector = selector;
        for (NSUInteger index = 0; index < arguments.count; index++) {
            id argument = arguments[index] == NSNull.null ? nil : arguments[index];
            const char *type = axs_duodesktop_unqualified([signature getArgumentTypeAtIndex:index + 2]);
            if (*type == '@') {
                __unsafe_unretained id object = argument;
                [invocation setArgument:&object atIndex:(NSInteger)index + 2];
                continue;
            }
            if (![argument isKindOfClass:[NSNumber class]]) return nil;
#define AXS_DD_ARG(C, T, M) case C: { T value = [argument M]; [invocation setArgument:&value atIndex:(NSInteger)index + 2]; break; }
            switch (*type) {
                AXS_DD_ARG('B', BOOL, boolValue) AXS_DD_ARG('c', char, charValue)
                AXS_DD_ARG('C', unsigned char, unsignedCharValue) AXS_DD_ARG('s', short, shortValue)
                AXS_DD_ARG('S', unsigned short, unsignedShortValue) AXS_DD_ARG('i', int, intValue)
                AXS_DD_ARG('I', unsigned int, unsignedIntValue) AXS_DD_ARG('l', long, longValue)
                AXS_DD_ARG('L', unsigned long, unsignedLongValue) AXS_DD_ARG('q', long long, longLongValue)
                AXS_DD_ARG('Q', unsigned long long, unsignedLongLongValue)
                AXS_DD_ARG('f', float, floatValue) AXS_DD_ARG('d', double, doubleValue)
                default: return nil;
            }
#undef AXS_DD_ARG
        }
        [invocation retainArguments];
        [invocation invoke];
        if (accepted) *accepted = YES;
        const char *type = axs_duodesktop_unqualified(signature.methodReturnType);
        if (*type == 'v') return nil;
        if (*type == '@') {
            __unsafe_unretained id value = nil;
            [invocation getReturnValue:&value];
            return value;
        }
#define AXS_DD_RET(C, T) case C: { T value = 0; [invocation getReturnValue:&value]; return @(value); }
        switch (*type) {
            AXS_DD_RET('B', BOOL) AXS_DD_RET('c', char) AXS_DD_RET('C', unsigned char)
            AXS_DD_RET('s', short) AXS_DD_RET('S', unsigned short) AXS_DD_RET('i', int)
            AXS_DD_RET('I', unsigned int) AXS_DD_RET('l', long) AXS_DD_RET('L', unsigned long)
            AXS_DD_RET('q', long long) AXS_DD_RET('Q', unsigned long long)
            AXS_DD_RET('f', float) AXS_DD_RET('d', double)
        }
#undef AXS_DD_RET
    } @catch (NSException *exception) {
        axs_duodesktop_log(@"action %@ rejected: %@", name, exception.reason);
        if (accepted) *accepted = NO;
    }
    return nil;
}

static id axs_duodesktop_object(id target, NSString *selector) {
    return axs_duodesktop_invoke(target, selector, @"object", @[], @[], NULL);
}

static NSNumber *axs_duodesktop_numberValue(id target, NSString *selector) {
    return axs_duodesktop_invoke(target, selector, @"number", @[], @[], NULL);
}

static BOOL axs_duodesktop_command(id target, NSString *selector) {
    BOOL sent = NO;
    axs_duodesktop_invoke(target, selector, @"void", @[], @[], &sent);
    if (sent) return YES;
    NSNumber *result = axs_duodesktop_invoke(target, selector, @"bool", @[], @[], &sent);
    return sent && result.boolValue;
}

static BOOL axs_duodesktop_setNumber(id target, NSString *selector, NSNumber *value) {
    BOOL sent = NO;
    axs_duodesktop_invoke(target, selector, @"void", @[@"number"], @[value], &sent);
    if (sent) return YES;
    NSNumber *result = axs_duodesktop_invoke(target, selector, @"bool", @[@"number"], @[value], &sent);
    return sent && result.boolValue;
}

static BOOL axs_duodesktop_arguments(id target, NSString *selector,
                                     NSArray<NSString *> *kinds, NSArray *arguments) {
    BOOL sent = NO;
    axs_duodesktop_invoke(target, selector, @"void", kinds, arguments, &sent);
    if (sent) return YES;
    NSNumber *result = axs_duodesktop_invoke(target, selector, @"bool", kinds, arguments, &sent);
    return sent && result.boolValue;
}

static id axs_duodesktop_shared(NSString *className) {
    Class cls = axs_duodesktop_class(className);
    for (NSString *name in @[@"sharedInstance", @"sharedInstanceIfExists", @"sharedManager",
                             @"sharedController", @"defaultWorkspace"]) {
        id instance = axs_duodesktop_object(cls, name);
        if (instance) return instance;
    }
    return nil;
}

#pragma mark - Catalog

static NSDictionary *axs_duodesktop_tool(NSString *value, NSString *title, NSString *icon,
                                         NSDictionary *extra) {
    NSMutableDictionary *entry = [@{
        @"type": @"tool",
        @"value": value,
        @"title": title,
        @"icon": icon,
        @"id": [@"tool:" stringByAppendingString:value],
        @"enabled": @YES
    } mutableCopy];
    if (extra) [entry addEntriesFromDictionary:extra];
    return entry;
}

NSArray<NSDictionary *> *axs_duodesktop_catalog(void) {
    static NSArray<NSDictionary *> *catalog;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
        // System actions implemented directly against SpringBoard services.
        [items addObject:axs_duodesktop_tool(@"home", @"回到桌面", @"house", nil)];
        [items addObject:axs_duodesktop_tool(@"switcher", @"多任务切换", @"rectangle.on.rectangle", nil)];
        [items addObject:axs_duodesktop_tool(@"control-center", @"控制中心", @"switch.2", nil)];
        [items addObject:axs_duodesktop_tool(@"notification-center", @"通知中心", @"bell.badge", nil)];
        [items addObject:axs_duodesktop_tool(@"lock-screen", @"锁定屏幕", @"lock", nil)];
        [items addObject:axs_duodesktop_tool(@"system-screenshot", @"系统截图", @"camera", nil)];
        [items addObject:axs_duodesktop_tool(@"screenshot-copy", @"截图并复制", @"doc.on.clipboard", nil)];
        [items addObject:axs_duodesktop_tool(@"screenshot-edit", @"截图并编辑", @"camera.viewfinder", nil)];
        [items addObject:axs_duodesktop_tool(@"screen-record", @"录屏开关", @"record.circle", nil)];
        [items addObject:axs_duodesktop_tool(@"screen-record-mic", @"开麦录屏开关", @"record.circle.fill", nil)];
        [items addObject:axs_duodesktop_tool(@"rotation-lock", @"旋转锁定", @"lock.rotation", nil)];
        [items addObject:axs_duodesktop_tool(@"flashlight", @"手电筒", @"flashlight.on.fill", nil)];
        [items addObject:axs_duodesktop_tool(@"wifi", @"Wi-Fi", @"wifi", nil)];
        [items addObject:axs_duodesktop_tool(@"bluetooth", @"蓝牙", @"antenna.radiowaves.left.and.right", nil)];
        [items addObject:axs_duodesktop_tool(@"airplane-mode", @"飞行模式", @"airplane", nil)];
        [items addObject:axs_duodesktop_tool(@"low-power-mode", @"低电量模式", @"battery.25", nil)];
        [items addObject:axs_duodesktop_tool(@"silent-mode", @"静音模式", @"bell.slash", nil)];
        [items addObject:axs_duodesktop_tool(@"dark-mode", @"深色模式", @"circle.lefthalf.filled", nil)];
        [items addObject:axs_duodesktop_tool(@"brightness-up", @"提高亮度", @"sun.max", nil)];
        [items addObject:axs_duodesktop_tool(@"brightness-down", @"降低亮度", @"sun.min", nil)];
        [items addObject:axs_duodesktop_tool(@"volume-up", @"增大音量", @"speaker.plus", nil)];
        [items addObject:axs_duodesktop_tool(@"volume-down", @"减小音量", @"speaker.minus", nil)];
        // Settings deep links. Opening them hands the tap to the system.
        [items addObject:axs_duodesktop_tool(@"settings", @"系统设置", @"gearshape", @{@"url": @"App-prefs:"})];
        [items addObject:axs_duodesktop_tool(@"vpn", @"VPN 设置", @"network", @{@"url": @"App-prefs:root=General&path=VPN"})];
        [items addObject:axs_duodesktop_tool(@"cellular-data", @"蜂窝网络设置", @"chart.bar.fill", @{@"url": @"App-prefs:root=MOBILE_DATA_SETTINGS_ID"})];
        [items addObject:axs_duodesktop_tool(@"do-not-disturb", @"专注模式设置", @"moon", @{@"url": @"App-prefs:root=DO_NOT_DISTURB"})];
        [items addObject:axs_duodesktop_tool(@"location-services", @"定位服务设置", @"location", @{@"url": @"App-prefs:root=Privacy&path=LOCATION"})];
        [items addObject:axs_duodesktop_tool(@"shortcuts", @"快捷指令", @"square.stack.3d.up", @{@"url": @"shortcuts://"})];
        // Accessibility system actions use AXPISystemActionHelper when present.
        [items addObject:axs_duodesktop_tool(@"siri", @"呼出 Siri", @"sparkles", @{@"systemSelector": @"activateSiri"})];
        [items addObject:axs_duodesktop_tool(@"spotlight", @"Spotlight 搜索", @"magnifyingglass", @{@"systemSelector": @"revealSpotlight"})];
        [items addObject:axs_duodesktop_tool(@"app-library", @"App 资源库", @"square.grid.2x2", @{@"systemSelector": @"toggleAppLibrary"})];
        [items addObject:axs_duodesktop_tool(@"shake", @"摇一摇", @"hand.raised", @{@"systemSelector": @"shake"})];
        [items addObject:axs_duodesktop_tool(@"voice-control", @"语音控制", @"mic.circle", @{@"systemSelector": @"toggleCommandAndControl"})];
        [items addObject:axs_duodesktop_tool(@"live-speech", @"实时语音", @"waveform.circle", @{@"systemSelector": @"toggleLiveSpeech"})];
        [items addObject:axs_duodesktop_tool(@"smart-invert", @"智能反色", @"circle.lefthalf.filled", @{@"systemSelector": @"_toggleSmartInvert"})];
        [items addObject:axs_duodesktop_tool(@"nearby-device-control", @"附近设备控制", @"antenna.radiowaves.left.and.right", @{@"systemSelector": @"toggleNearbyDeviceControlPicker"})];
        [items addObject:axs_duodesktop_tool(@"ipad-dock", @"iPad Dock", @"dock.rectangle", @{@"systemSelector": @"toggleDock", @"ipadOnly": @YES})];
        [items addObject:axs_duodesktop_tool(@"ipad-quick-note", @"快速备忘录", @"square.and.pencil", @{@"systemSelector": @"toggleQuickNote", @"ipadOnly": @YES})];
        catalog = [items copy];
    });
    return catalog;
}

static NSDictionary *axs_duodesktop_catalogEntry(NSString *value) {
    for (NSDictionary *entry in axs_duodesktop_catalog()) {
        if ([entry[@"value"] isEqual:value]) return entry;
    }
    return nil;
}

#pragma mark - Records

static NSString *axs_duodesktop_text(id value) {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

NSDictionary *axs_duodesktop_normalizeRecord(id input) {
    if (![input isKindOfClass:[NSDictionary class]]) return nil;
    NSString *type = axs_duodesktop_text(input[@"type"]);
    NSString *value = axs_duodesktop_text(input[@"value"]);
    if (!value.length) return nil;
    if ([value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return nil;
    if (![@[@"tool", @"app", @"url", @"shortcut"] containsObject:type]) return nil;
    if ([type isEqual:@"tool"] && !axs_duodesktop_catalogEntry(value)) return nil;
    if ([type isEqual:@"url"] && ![NSURLComponents componentsWithString:value].scheme.length) return nil;
    NSMutableDictionary *record = [@{@"type": type, @"value": value} mutableCopy];
    NSString *title = axs_duodesktop_text(input[@"title"]);
    record[@"title"] = title.length ? title : (axs_duodesktop_catalogEntry(value)[@"title"] ?: value);
    NSString *identifier = axs_duodesktop_text(input[@"id"]);
    record[@"id"] = identifier.length ? identifier : [NSString stringWithFormat:@"%@:%@", type, value];
    record[@"enabled"] = [input[@"enabled"] isKindOfClass:[NSNumber class]]
        ? @([input[@"enabled"] boolValue]) : @YES;
    return record;
}

NSArray<NSDictionary *> *axs_duodesktop_records(NSString *key) {
    NSString *slot = key.length ? key : AxsDuoDesktopRecordKey;
    id stored = axs_duodesktop_setting(slot, nil);
    NSMutableArray<NSDictionary *> *records = [NSMutableArray array];
    if ([stored isKindOfClass:[NSArray class]]) {
        for (id item in stored) {
            NSDictionary *record = axs_duodesktop_normalizeRecord(item);
            if (record) [records addObject:record];
        }
        return records;
    }
    if (![slot isEqual:AxsDuoDesktopRecordKey]) return @[];
    for (NSString *value in @[@"wifi", @"bluetooth", @"rotation-lock",
                              @"dark-mode", @"screenshot-copy", @"low-power-mode"]) {
        NSDictionary *entry = axs_duodesktop_catalogEntry(value);
        if (entry) [records addObject:entry];
    }
    return records;
}

BOOL axs_duodesktop_saveRecords(NSString *key, NSArray<NSDictionary *> *records, NSError **error) {
    if (![records isKindOfClass:[NSArray class]]) {
        if (error) *error = axs_duodesktop_error(1, @"动作列表无效");
        return NO;
    }
    NSMutableArray *clean = [NSMutableArray array];
    NSMutableSet<NSString *> *identifiers = [NSMutableSet set];
    for (id input in records) {
        NSMutableDictionary *record = [axs_duodesktop_normalizeRecord(input) mutableCopy];
        if (!record) {
            if (error) *error = axs_duodesktop_error(2, @"动作配置无效，请重新选择");
            return NO;
        }
        if ([identifiers containsObject:record[@"id"]]) record[@"id"] = NSUUID.UUID.UUIDString;
        [identifiers addObject:record[@"id"]];
        [clean addObject:record];
    }
    BOOL written = axs_duodesktop_writePreference(key.length ? key : AxsDuoDesktopRecordKey, clean, error);
    if (written) {
        [[NSNotificationCenter defaultCenter] postNotificationName:AxsDuoDesktopActionsChanged object:nil];
    }
    return written;
}

#pragma mark - State, icons and applications

static NSNumber *axs_duodesktop_firstNumber(id target, NSArray<NSString *> *selectors) {
    for (NSString *selector in selectors) {
        NSNumber *value = axs_duodesktop_numberValue(target, selector);
        if (value) return value;
    }
    return nil;
}

static void axs_duodesktop_loadFramework(NSString *name) {
    NSString *path = [NSString stringWithFormat:
        @"/System/Library/PrivateFrameworks/%@.framework/%@", name, name];
    axs_duodesktop_framework(path.UTF8String);
}

NSNumber *axs_duodesktop_actionState(NSDictionary *record) {
    if (!axs_duodesktop_isSpringBoard()) return nil;
    if (![record[@"type"] isEqual:@"tool"]) return nil;
    NSString *value = axs_duodesktop_text(record[@"value"]);
    if ([value isEqual:@"wifi"]) {
        return axs_duodesktop_firstNumber(axs_duodesktop_shared(@"SBWiFiManager"),
            @[@"isWiFiEnabled", @"wiFiEnabled", @"wifiEnabled"]);
    }
    if ([value isEqual:@"bluetooth"]) {
        axs_duodesktop_loadFramework(@"BluetoothManager");
        return axs_duodesktop_firstNumber(axs_duodesktop_shared(@"BluetoothManager"),
            @[@"enabled", @"powered"]);
    }
    if ([value isEqual:@"rotation-lock"]) {
        return axs_duodesktop_firstNumber(axs_duodesktop_shared(@"SBOrientationLockManager"),
            @[@"isUserLocked", @"isLocked"]);
    }
    if ([value isEqual:@"flashlight"]) {
        NSNumber *level = axs_duodesktop_numberValue(axs_duodesktop_shared(@"SBUIFlashlightController"),
                                                     @"level");
        return level ? @(level.doubleValue > 0) : nil;
    }
    if ([value isEqual:@"low-power-mode"]) return @(NSProcessInfo.processInfo.lowPowerModeEnabled);
    if ([value isEqual:@"dark-mode"]) {
        return @(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    }
    if ([value isEqual:@"silent-mode"]) {
        id agent = axs_duodesktop_object(axs_duodesktop_shared(@"SBControlCenterController"),
                                         @"systemAgent");
        return axs_duodesktop_numberValue(agent, @"isRingerMuted");
    }
    return nil;
}

NSArray<NSDictionary *> *axs_duodesktop_applicationRecords(void) {
    id workspace = axs_duodesktop_shared(@"LSApplicationWorkspace");
    id applications = axs_duodesktop_object(workspace, @"allInstalledApplications")
        ?: axs_duodesktop_object(workspace, @"allApplications");
    if (![applications isKindOfClass:[NSArray class]]) {
        applications = axs_duodesktop_object(axs_duodesktop_shared(@"SBApplicationController"),
                                             @"allApplications");
    }
    if (![applications isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray<NSDictionary *> *records = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id application in applications) {
        id bundle = axs_duodesktop_object(application, @"applicationIdentifier")
            ?: axs_duodesktop_object(application, @"bundleIdentifier");
        if (![bundle isKindOfClass:[NSString class]] || ![(NSString *)bundle length]) continue;
        if ([seen containsObject:bundle]) continue;
        [seen addObject:bundle];
        id name = axs_duodesktop_object(application, @"localizedName")
            ?: axs_duodesktop_object(application, @"displayName");
        NSString *title = [name isKindOfClass:[NSString class]] ? name : bundle;
        [records addObject:@{@"type": @"app", @"value": bundle, @"title": title,
                             @"id": [@"app:" stringByAppendingString:bundle], @"enabled": @YES}];
    }
    [records sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"title"] localizedStandardCompare:right[@"title"]];
    }];
    return records;
}

UIImage *axs_duodesktop_actionImage(NSDictionary *record) {
    if (![record isKindOfClass:[NSDictionary class]]) return nil;
    if ([record[@"type"] isEqual:@"app"]) {
        NSString *bundle = axs_duodesktop_text(record[@"value"]);
        if (bundle.length) {
            id image = axs_duodesktop_invoke(UIImage.class,
                @"_applicationIconImageForBundleIdentifier:format:scale:", @"object",
                @[@"object", @"number", @"number"],
                @[bundle, @0, @(UIScreen.mainScreen.scale)], NULL);
            if ([image isKindOfClass:[UIImage class]]) return image;
        }
        return [UIImage systemImageNamed:@"app"];
    }
    NSString *symbol = axs_duodesktop_catalogEntry(axs_duodesktop_text(record[@"value"]))[@"icon"];
    if (!symbol.length) symbol = [record[@"type"] isEqual:@"url"] ? @"link" : @"square.stack.3d.up";
    return [UIImage systemImageNamed:symbol];
}

#pragma mark - Execution

static BOOL axs_duodesktop_isUnlocked(NSError **error) {
    if (!axs_duodesktop_isSpringBoard()) {
        if (error) *error = axs_duodesktop_error(10, @"系统动作需要在 SpringBoard 中执行");
        return NO;
    }
    id manager = axs_duodesktop_shared(@"SBLockScreenManager");
    NSNumber *locked = axs_duodesktop_numberValue(manager, @"isUILocked");
    if (!locked) {
        int token = -1;
        uint64_t state = 0;
        if (notify_register_check("com.apple.springboard.lockstate", &token) == NOTIFY_STATUS_OK) {
            if (notify_get_state(token, &state) == NOTIFY_STATUS_OK) locked = @(state != 0);
            notify_cancel(token);
        }
    }
    if (!locked) {
        if (error) *error = axs_duodesktop_error(11, @"无法确认锁屏状态，动作未执行");
        return NO;
    }
    if (locked.boolValue) {
        if (error) *error = axs_duodesktop_error(12, @"请先解锁再执行快捷操作");
        return NO;
    }
    return YES;
}

UIViewController *axs_duodesktop_presenter(void) {
    for (UIWindow *window in axs_duodesktop_windows().reverseObjectEnumerator) {
        if (window.hidden || !window.rootViewController || window.alpha <= 0) continue;
        UIViewController *controller = window.rootViewController;
        while (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) {
            controller = controller.presentedViewController;
        }
        return controller;
    }
    return nil;
}

void axs_duodesktop_showMessage(NSString *message) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ axs_duodesktop_showMessage(message); });
        return;
    }
    UIViewController *host = axs_duodesktop_presenter();
    if (!host || [host isKindOfClass:[UIAlertController class]]) {
        axs_duodesktop_log(@"%@", message);
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"DuoDesktop"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:alert animated:YES completion:nil];
}

static BOOL axs_duodesktop_openURL(NSString *text, NSError **error) {
    NSURL *url = [NSURL URLWithString:text];
    if (!url.scheme.length) {
        if (error) *error = axs_duodesktop_error(30, @"URL 格式无效");
        return NO;
    }
    UIApplication *application = UIApplication.sharedApplication;
    if (axs_duodesktop_arguments(application, @"applicationOpenURL:", @[@"object"], @[url])) return YES;
    if (axs_duodesktop_arguments(application, @"applicationOpenURL:publicURLsOnly:",
                                 @[@"object", @"bool"], @[url, @NO])) return YES;
    if (![application canOpenURL:url]) {
        if (error) *error = axs_duodesktop_error(31, @"没有可处理此链接的应用，或系统拒绝打开");
        return NO;
    }
    [application openURL:url options:@{} completionHandler:^(BOOL success) {
        if (!success) axs_duodesktop_showMessage(@"系统未接受打开链接的请求");
    }];
    return YES;
}

static BOOL axs_duodesktop_toggle(id target, NSArray<NSString *> *getters,
                                  NSArray<NSString *> *setters) {
    NSNumber *current = axs_duodesktop_firstNumber(target, getters);
    if (!current) return NO;
    for (NSString *setter in setters) {
        if (axs_duodesktop_setNumber(target, setter, @(!current.boolValue))) return YES;
    }
    return NO;
}

static id axs_duodesktop_radios(void) {
    static id radios;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        axs_duodesktop_loadFramework(@"AppSupport");
        radios = [axs_duodesktop_class(@"RadiosPreferences") new];
    });
    return radios;
}

static BOOL axs_duodesktop_recordScreen(BOOL microphone, NSError **error) {
    axs_duodesktop_framework("/System/Library/Frameworks/ReplayKit.framework/ReplayKit");
    id recorder = axs_duodesktop_object(axs_duodesktop_class(@"RPScreenRecorder"), @"sharedRecorder");
    NSNumber *recording = axs_duodesktop_firstNumber(recorder, @[@"isRecording", @"systemRecording"]);
    if (!recording) {
        if (error) *error = axs_duodesktop_error(36, @"系统录屏服务不可用");
        return NO;
    }
    void (^handler)(NSError *) = ^(NSError *failure) {
        if (failure) axs_duodesktop_showMessage(failure.localizedDescription);
    };
    if (recording.boolValue) {
        return axs_duodesktop_arguments(recorder, @"stopSystemRecording:", @[@"block"], @[handler]);
    }
    return axs_duodesktop_arguments(recorder, @"startSystemRecordingWithMicrophoneEnabled:handler:",
                                    @[@"bool", @"block"], @[@(microphone), handler]);
}

static BOOL axs_duodesktop_copyScreenshot(NSError **error) {
    typedef UIImage *(*AxsDuoDesktopCapture)(BOOL);
    AxsDuoDesktopCapture capture =
        (AxsDuoDesktopCapture)dlsym(RTLD_DEFAULT, "_UICreateScreenUIImageWithRotation");
    if (!capture) {
        if (error) *error = axs_duodesktop_error(37, @"系统截图接口不可用");
        return NO;
    }
    UIImage *image = capture(YES);
    if (![image isKindOfClass:[UIImage class]] || !image.CGImage) {
        if (error) *error = axs_duodesktop_error(38, @"系统未返回有效截图");
        return NO;
    }
    UIPasteboard.generalPasteboard.image = image;
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"截图已复制");
    return YES;
}

static BOOL axs_duodesktop_systemTool(NSDictionary *tool, NSError **error) {
    NSString *value = tool[@"value"];
    UIApplication *application = UIApplication.sharedApplication;
    if ([value isEqual:@"home"]) return axs_duodesktop_command(application, @"_simulateHomeButtonPress");
    if ([value isEqual:@"switcher"]) {
        return axs_duodesktop_command(axs_duodesktop_shared(@"SBUIController"),
                                      @"handleHomeButtonDoublePressDown");
    }
    if ([value isEqual:@"control-center"]) {
        id controller = axs_duodesktop_shared(@"SBControlCenterController");
        return axs_duodesktop_setNumber(controller, @"presentAnimated:", @YES)
            || axs_duodesktop_arguments(controller, @"presentAnimated:completion:",
                                        @[@"bool", @"block"], @[@YES, NSNull.null]);
    }
    if ([value isEqual:@"notification-center"]) {
        id manager = axs_duodesktop_shared(@"SBCoverSheetPresentationManager");
        if (axs_duodesktop_arguments(manager, @"setCoverSheetPresented:animated:withCompletion:",
                                     @[@"bool", @"bool", @"block"], @[@YES, @YES, NSNull.null])) return YES;
        return axs_duodesktop_setNumber(axs_duodesktop_shared(@"SBNotificationCenterController"),
                                        @"presentAnimated:", @YES);
    }
    if ([value isEqual:@"lock-screen"]) {
        return axs_duodesktop_command(application, @"_simulateLockButtonPress")
            || axs_duodesktop_arguments(axs_duodesktop_shared(@"SBLockScreenManager"),
                                        @"lockUIFromSource:withOptions:",
                                        @[@"number", @"object"], @[@1, @{}]);
    }
    if ([value isEqual:@"system-screenshot"] || [value isEqual:@"screenshot-edit"]) {
        return axs_duodesktop_setNumber(application, @"_takeScreenshotAndEdit:",
                                        @([value isEqual:@"screenshot-edit"]))
            || axs_duodesktop_command(application, @"takeScreenshot");
    }
    if ([value isEqual:@"rotation-lock"]) {
        id manager = axs_duodesktop_shared(@"SBOrientationLockManager");
        if (axs_duodesktop_toggle(manager, @[@"isUserLocked", @"isLocked"], @[@"setUserLocked:"])) return YES;
        NSNumber *state = axs_duodesktop_firstNumber(manager, @[@"isUserLocked", @"isLocked"]);
        return state ? axs_duodesktop_command(manager, state.boolValue ? @"unlock" : @"lock") : NO;
    }
    if ([value isEqual:@"wifi"]) {
        return axs_duodesktop_toggle(axs_duodesktop_shared(@"SBWiFiManager"),
            @[@"isWiFiEnabled", @"wiFiEnabled", @"wifiEnabled"],
            @[@"setWiFiEnabled:", @"setWiFiEnabledAndPowered:"]);
    }
    if ([value isEqual:@"bluetooth"]) {
        axs_duodesktop_loadFramework(@"BluetoothManager");
        return axs_duodesktop_toggle(axs_duodesktop_shared(@"BluetoothManager"),
            @[@"enabled", @"powered"], @[@"setEnabled:", @"setPowered:"]);
    }
    if ([value isEqual:@"flashlight"]) {
        id controller = axs_duodesktop_shared(@"SBUIFlashlightController");
        NSNumber *level = axs_duodesktop_numberValue(controller, @"level");
        return level ? axs_duodesktop_setNumber(controller, @"setLevel:",
                                                @(level.doubleValue > 0 ? 0.0 : 1.0)) : NO;
    }
    if ([value isEqual:@"airplane-mode"]) {
        id radios = axs_duodesktop_radios();
        axs_duodesktop_command(radios, @"refresh");
        return axs_duodesktop_toggle(radios, @[@"airplaneMode"], @[@"setAirplaneMode:"]);
    }
    if ([value isEqual:@"low-power-mode"]) {
        axs_duodesktop_loadFramework(@"LowPowerMode");
        id controller = axs_duodesktop_shared(@"_PMLowPowerMode");
        NSNumber *state = axs_duodesktop_numberValue(controller, @"getPowerMode");
        return state && axs_duodesktop_arguments(controller, @"setPowerMode:fromSource:",
                                                 @[@"number", @"object"],
                                                 @[@(!state.boolValue), @"SpringBoard"]);
    }
    if ([value isEqual:@"silent-mode"]) {
        id agent = axs_duodesktop_object(axs_duodesktop_shared(@"SBControlCenterController"),
                                         @"systemAgent");
        NSNumber *state = axs_duodesktop_numberValue(agent, @"isRingerMuted");
        if (state && axs_duodesktop_arguments(agent, @"setRingerMuted:reason:",
                                              @[@"bool", @"object"],
                                              @[@(!state.boolValue), @"DuoDesktop"])) return YES;
        return axs_duodesktop_toggle(axs_duodesktop_object(application, @"ringerControl"),
                                     @[@"isRingerMuted"], @[@"setRingerMuted:"]);
    }
    if ([value isEqual:@"dark-mode"]) {
        axs_duodesktop_loadFramework(@"UIKitServices");
        id current = axs_duodesktop_object(axs_duodesktop_shared(@"UIUserInterfaceStyleArbiter"),
                                           @"currentStyle");
        NSNumber *state = axs_duodesktop_numberValue(current, @"modeValue");
        id mode = [axs_duodesktop_class(@"UISUserInterfaceStyleMode") new];
        NSInteger currentMode = state ? state.integerValue
            : (UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 2 : 1);
        return axs_duodesktop_setNumber(mode, @"setModeValue:", @(currentMode == 2 ? 1 : 2));
    }
    if ([value hasPrefix:@"brightness-"]) {
        CGFloat delta = [value hasSuffix:@"up"] ? 0.0625 : -0.0625;
        UIScreen.mainScreen.brightness = MIN(1, MAX(0, UIScreen.mainScreen.brightness + delta));
        return YES;
    }
    if ([value hasPrefix:@"volume-"]) {
        return axs_duodesktop_command(axs_duodesktop_shared(@"SBVolumeControl"),
            [value hasSuffix:@"up"] ? @"increaseVolume" : @"decreaseVolume");
    }
    if ([value isEqual:@"screenshot-copy"]) return axs_duodesktop_copyScreenshot(error);
    if ([value isEqual:@"screen-record"] || [value isEqual:@"screen-record-mic"]) {
        return axs_duodesktop_recordScreen([value isEqual:@"screen-record-mic"], error);
    }
    NSString *systemSelector = tool[@"systemSelector"];
    if (systemSelector.length) {
        if ([tool[@"ipadOnly"] boolValue] &&
            UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) return NO;
        axs_duodesktop_loadFramework(@"AccessibilityPhysicalInteraction");
        return axs_duodesktop_command(axs_duodesktop_shared(@"AXPISystemActionHelper"), systemSelector);
    }
    if (error) *error = axs_duodesktop_error(32, @"当前系统缺少该动作的兼容接口");
    return NO;
}

BOOL axs_duodesktop_launchApplication(NSString *bundleID, NSError **error) {
    if (!NSThread.isMainThread) {
        __block BOOL result = NO;
        __block NSError *failure = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = axs_duodesktop_launchApplication(bundleID, &failure);
        });
        if (error) *error = failure;
        return result;
    }
    if (!bundleID.length) {
        if (error) *error = axs_duodesktop_error(50, @"未配置应用标识");
        return NO;
    }
    if (!axs_duodesktop_isUnlocked(error)) return NO;
    BOOL accepted = NO;
    NSNumber *result = axs_duodesktop_invoke(UIApplication.sharedApplication,
        @"launchApplicationWithIdentifier:suspended:", @"bool",
        @[@"object", @"bool"], @[bundleID, @NO], &accepted);
    if (accepted && result.boolValue) return YES;
    void *services = axs_duodesktop_framework(
        "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices");
    typedef int (*AxsDuoDesktopLaunch)(CFStringRef, BOOL);
    AxsDuoDesktopLaunch launch =
        services ? (AxsDuoDesktopLaunch)dlsym(services, "SBSLaunchApplicationWithIdentifier") : NULL;
    if (launch && launch((__bridge CFStringRef)bundleID, NO) == 0) return YES;
    if (error) *error = axs_duodesktop_error(51, @"系统未接受启动请求，或该应用不可用");
    return NO;
}

NSString *axs_duodesktop_unavailableReason(NSDictionary *record) {
    NSDictionary *normalized = axs_duodesktop_normalizeRecord(record);
    if (!normalized) return @"动作配置无效，请重新选择";
    NSString *type = normalized[@"type"];
    if ([type isEqual:@"tool"]) {
        NSDictionary *tool = axs_duodesktop_catalogEntry(normalized[@"value"]);
        if (!tool) return @"当前版本没有这个系统动作";
        if ([tool[@"ipadOnly"] boolValue] &&
            UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) {
            return @"此动作仅适用于 iPad";
        }
    }
    return nil;
}

BOOL axs_duodesktop_performActionWithError(NSDictionary *record, NSError **error) {
    if (error) *error = nil;
    if (!NSThread.isMainThread) {
        __block BOOL success = NO;
        __block NSError *failure = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            success = axs_duodesktop_performActionWithError(record, &failure);
        });
        if (error) *error = failure;
        return success;
    }
    NSDictionary *normalized = axs_duodesktop_normalizeRecord(record);
    if (!normalized) {
        if (error) *error = axs_duodesktop_error(40, @"动作配置无效，请重新选择");
        return NO;
    }
    NSString *reason = axs_duodesktop_unavailableReason(normalized);
    if (reason) {
        if (error) *error = axs_duodesktop_error(41, reason);
        return NO;
    }
    if (!axs_duodesktop_isUnlocked(error)) return NO;
    NSString *type = normalized[@"type"];
    NSString *value = normalized[@"value"];
    BOOL success = NO;
    if ([type isEqual:@"app"]) {
        success = axs_duodesktop_launchApplication(value, error);
    } else if ([type isEqual:@"url"]) {
        success = axs_duodesktop_openURL(value, error);
    } else if ([type isEqual:@"shortcut"]) {
        NSURLComponents *components = [NSURLComponents componentsWithString:@"shortcuts://run-shortcut"];
        components.queryItems = @[[NSURLQueryItem queryItemWithName:@"name" value:value]];
        success = axs_duodesktop_openURL(components.URL.absoluteString, error);
    } else if ([type isEqual:@"tool"]) {
        NSDictionary *tool = axs_duodesktop_catalogEntry(value);
        if ([tool[@"url"] length]) success = axs_duodesktop_openURL(tool[@"url"], error);
        else success = axs_duodesktop_systemTool(tool, error);
    }
    if (!success && error && !*error) {
        *error = axs_duodesktop_error(42, @"当前系统未接受该动作");
    }
    if (success) {
        [[NSNotificationCenter defaultCenter] postNotificationName:AxsDuoDesktopActionsChanged
                                                            object:nil];
    }
    return success;
}

BOOL axs_duodesktop_performAction(NSDictionary *record) {
    NSError *error = nil;
    BOOL success = axs_duodesktop_performActionWithError(record, &error);
    if (!success) axs_duodesktop_showMessage(error.localizedDescription ?: @"动作未执行");
    return success;
}
