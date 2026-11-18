#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#ifdef __cplusplus
extern "C" {
#endif

// Runtime helpers shared by the hooks and the UI. Every entry stays in this
// process: nothing is written back to the target application.

BOOL axs_duodesktop_isSpringBoard(void);
Class axs_duodesktop_class(NSString *name);
SEL axs_duodesktop_selector(NSString *name);
BOOL axs_duodesktop_typesMatch(Class cls, SEL sel, const char *types);
BOOL axs_duodesktop_installHook(NSString *key, Class cls, SEL sel, const char *types,
                                IMP replacement, IMP *original);
void axs_duodesktop_observeReload(void (^handler)(void));
void axs_duodesktop_log(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
void *axs_duodesktop_framework(const char *path);
NSArray<UIWindow *> *axs_duodesktop_windows(void);
#ifdef __cplusplus
}
#endif
