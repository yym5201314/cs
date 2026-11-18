#import "AxsDuoDesktopConfig.h"
#import "AxsDuoDesktopPreferences.h"

@interface AxsDuoDesktopConfig ()
@property (atomic, copy) NSDictionary *snapshot;
@property (nonatomic, strong) dispatch_queue_t reloadQueue;
@end

static void axs_duodesktop_preferencesDidChange(CFNotificationCenterRef center, void *observer,
                                                CFStringRef name, const void *object,
                                                CFDictionaryRef info) {
    AxsDuoDesktopConfig *config = (__bridge AxsDuoDesktopConfig *)observer;
    dispatch_async(config.reloadQueue, ^{
        [config axs_duodesktop_reload];
    });
}

@implementation AxsDuoDesktopConfig

+ (instancetype)axs_duodesktop_shared {
    static AxsDuoDesktopConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _reloadQueue = dispatch_queue_create("com.axs.duodesktop.preferences",
                                             DISPATCH_QUEUE_SERIAL);
        [self axs_duodesktop_reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self, axs_duodesktop_preferencesDidChange,
            (__bridge CFStringRef)AxsDuoDesktopPreferencesChanged, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Close the window between the first read and observer registration.
        dispatch_async(_reloadQueue, ^{ [self axs_duodesktop_reload]; });
    }
    return self;
}

- (void)axs_duodesktop_reload {
    NSDictionary *next = axs_duodesktop_readPreferences();
    if (![next isKindOfClass:[NSDictionary class]]) next = @{};
    NSDictionary *previous = self.snapshot;
    if (previous && [previous isEqualToDictionary:next]) return;
    self.snapshot = [next copy];
    // Subscribers may call +shared from their own once token; never notify inline.
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:AxsDuoDesktopPreferencesChanged
                                                            object:self];
    });
}

- (id)axs_duodesktop_valueForKey:(NSString *)key defaultValue:(id)defaultValue {
    if (!key.length) return defaultValue;
    id value = self.snapshot[key];
    return value ?: defaultValue;
}

- (BOOL)axs_duodesktop_boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    id value = [self axs_duodesktop_valueForKey:key defaultValue:nil];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : defaultValue;
}

- (double)axs_duodesktop_doubleForKey:(NSString *)key defaultValue:(double)defaultValue {
    id value = [self axs_duodesktop_valueForKey:key defaultValue:nil];
    return [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : defaultValue;
}

- (NSInteger)axs_duodesktop_integerForKey:(NSString *)key defaultValue:(NSInteger)defaultValue {
    id value = [self axs_duodesktop_valueForKey:key defaultValue:nil];
    return [value isKindOfClass:[NSNumber class]] ? [value integerValue] : defaultValue;
}

- (BOOL)axs_duodesktop_isEnabled {
    return [self axs_duodesktop_boolForKey:@"enabled" defaultValue:NO];
}

- (BOOL)axs_duodesktop_debugLogging {
    return [self axs_duodesktop_boolForKey:@"debugLogging" defaultValue:NO];
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
}

@end

BOOL axs_duodesktop_flag(NSString *key, BOOL fallback) {
    return [[AxsDuoDesktopConfig axs_duodesktop_shared]
        axs_duodesktop_boolForKey:key defaultValue:fallback];
}

double axs_duodesktop_number(NSString *key, double fallback) {
    return [[AxsDuoDesktopConfig axs_duodesktop_shared]
        axs_duodesktop_doubleForKey:key defaultValue:fallback];
}

NSInteger axs_duodesktop_count(NSString *key, NSInteger fallback) {
    return [[AxsDuoDesktopConfig axs_duodesktop_shared]
        axs_duodesktop_integerForKey:key defaultValue:fallback];
}

id axs_duodesktop_setting(NSString *key, id fallback) {
    return [[AxsDuoDesktopConfig axs_duodesktop_shared]
        axs_duodesktop_valueForKey:key defaultValue:fallback];
}
