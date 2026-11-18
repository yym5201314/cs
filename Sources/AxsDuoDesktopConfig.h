#pragma once

#import <Foundation/Foundation.h>

@interface AxsDuoDesktopConfig : NSObject
+ (instancetype)axs_duodesktop_shared;
- (BOOL)axs_duodesktop_isEnabled;
- (BOOL)axs_duodesktop_debugLogging;
- (id)axs_duodesktop_valueForKey:(NSString *)key defaultValue:(id)defaultValue;
- (BOOL)axs_duodesktop_boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue;
- (double)axs_duodesktop_doubleForKey:(NSString *)key defaultValue:(double)defaultValue;
- (NSInteger)axs_duodesktop_integerForKey:(NSString *)key defaultValue:(NSInteger)defaultValue;
- (void)axs_duodesktop_reload;
@end

// Read-only accessors for call sites that need a single value.
#ifdef __cplusplus
extern "C" {
#endif

BOOL axs_duodesktop_flag(NSString *key, BOOL fallback);
double axs_duodesktop_number(NSString *key, double fallback);
NSInteger axs_duodesktop_count(NSString *key, NSInteger fallback);
id axs_duodesktop_setting(NSString *key, id fallback);
#ifdef __cplusplus
}
#endif
