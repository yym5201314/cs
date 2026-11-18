#import "AxsDuoDesktopRuntime.h"
#import "AxsDuoDesktopConfig.h"
#import "AxsDuoDesktopPreferences.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <string.h>

typedef void (*AxsDuoDesktopHookMessageFn)(Class, SEL, IMP, IMP *);

// Copy of a method type encoding with ARC qualifiers removed. Objects, blocks,
// pointers and scalars stay distinct so a mismatch is still detected.
static NSString *axs_duodesktop_normalizedType(const char *type) {
    if (!type) return @"";
    while (*type && strchr("rnNoORV", *type)) type++;
    if (*type == '@' && type[1] == '"') return @"@";
    return [NSString stringWithUTF8String:type] ?: @"";
}

BOOL axs_duodesktop_typesMatch(Class cls, SEL sel, const char *types) {
    if (!cls || !sel || !types) return NO;
    Method method = class_getInstanceMethod(cls, sel);
    const char *actual = method ? method_getTypeEncoding(method) : NULL;
    if (!actual) return NO;
    @try {
        NSMethodSignature *found = [NSMethodSignature signatureWithObjCTypes:actual];
        NSMethodSignature *wanted = [NSMethodSignature signatureWithObjCTypes:types];
        if (found.numberOfArguments != wanted.numberOfArguments) return NO;
        if (![axs_duodesktop_normalizedType(found.methodReturnType)
                isEqual:axs_duodesktop_normalizedType(wanted.methodReturnType)]) return NO;
        for (NSUInteger index = 0; index < found.numberOfArguments; index++) {
            if (![axs_duodesktop_normalizedType([found getArgumentTypeAtIndex:index])
                    isEqual:axs_duodesktop_normalizedType([wanted getArgumentTypeAtIndex:index])]) return NO;
        }
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

// Substrate is loaded by the jailbreak before tweaks; ellekit ships a
// compatible shim. Resolve lazily so a missing engine never crashes a process.
static AxsDuoDesktopHookMessageFn axs_duodesktop_hookEngine(void) {
    AxsDuoDesktopHookMessageFn hook =
        (AxsDuoDesktopHookMessageFn)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    if (hook) return hook;
    static void *engine;
    if (!engine) {
        Dl_info info = {0};
        if (dladdr((const void *)&axs_duodesktop_hookEngine, &info) && info.dli_fname) {
            NSString *directory = [[NSString stringWithUTF8String:info.dli_fname]
                stringByDeletingLastPathComponent];
            NSString *local = [directory stringByAppendingPathComponent:
                @".jbroot/usr/lib/libsubstrate.dylib"];
            engine = dlopen(local.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
        }
        const char *fallbacks[] = {
            "/var/jb/usr/lib/libsubstrate.dylib",
            "/usr/lib/libsubstrate.dylib",
            "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate"
        };
        for (NSUInteger index = 0; !engine && index < sizeof(fallbacks) / sizeof(fallbacks[0]); index++) {
            engine = dlopen(fallbacks[index], RTLD_NOW | RTLD_GLOBAL);
        }
    }
    return (AxsDuoDesktopHookMessageFn)dlsym(engine ?: RTLD_DEFAULT, "MSHookMessageEx");
}

BOOL axs_duodesktop_isSpringBoard(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"];
}

Class axs_duodesktop_class(NSString *name) {
    return name.length ? NSClassFromString(name) : Nil;
}

SEL axs_duodesktop_selector(NSString *name) {
    return name.length ? NSSelectorFromString(name) : NULL;
}

BOOL axs_duodesktop_installHook(NSString *key, Class cls, SEL sel, const char *types,
                                IMP replacement, IMP *original) {
    if (!cls || !sel || !replacement) return NO;
    if (!class_getInstanceMethod(cls, sel)) return NO;
    if (types && !axs_duodesktop_typesMatch(cls, sel, types)) {
        axs_duodesktop_log(@"hook %@ skipped: encoding mismatch", key);
        return NO;
    }
    AxsDuoDesktopHookMessageFn hook = axs_duodesktop_hookEngine();
    if (!hook) {
        axs_duodesktop_log(@"hook %@ skipped: no substrate engine", key);
        return NO;
    }
    static NSMutableDictionary<NSString *, NSValue *> *installed;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ installed = [NSMutableDictionary dictionary]; });
    @synchronized (installed) {
        NSString *slot = [NSString stringWithFormat:@"%p:%@", cls, NSStringFromSelector(sel)];
        NSValue *existing = installed[slot];
        if (existing) return existing.pointerValue == (const void *)replacement;
        if (class_getMethodImplementation(cls, sel) == replacement) return NO;
        hook(cls, sel, replacement, original);
        installed[slot] = [NSValue valueWithPointer:(const void *)replacement];
        axs_duodesktop_log(@"hook %@ installed on %@", key, NSStringFromClass(cls));
    }
    return YES;
}

void axs_duodesktop_observeReload(void (^handler)(void)) {
    if (!handler) return;
    [[NSNotificationCenter defaultCenter] addObserverForName:AxsDuoDesktopPreferencesChanged
        object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
            handler();
        }];
}

void axs_duodesktop_log(NSString *format, ...) {
    if (![AxsDuoDesktopConfig axs_duodesktop_shared].axs_duodesktop_debugLogging) return;
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    NSLog(@"[DuoDesktop] %@", message);
}

NSArray<UIWindow *> *axs_duodesktop_windows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
    }
    if (!windows.count) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        // SpringBoard exposes the home window here before a scene is connected.
        [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
    }
    return windows;
}

void *axs_duodesktop_framework(const char *path) {
    if (!path) return NULL;
    static NSMutableDictionary<NSString *, NSValue *> *handles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ handles = [NSMutableDictionary dictionary]; });
    NSString *key = [NSString stringWithUTF8String:path] ?: @"";
    @synchronized (handles) {
        NSValue *existing = handles[key];
        if (existing) return existing.pointerValue;
        void *handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
        if (!handle) return NULL;
        handles[key] = [NSValue valueWithPointer:handle];
        return handle;
    }
}
