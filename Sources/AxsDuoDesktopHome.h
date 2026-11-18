#pragma once

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

// All entry points normalize to the main thread themselves.
FOUNDATION_EXPORT void axs_duodesktop_installHomeHooks(void);
FOUNDATION_EXPORT void axs_duodesktop_refreshHome(void);
FOUNDATION_EXPORT void axs_duodesktop_setSuppressed(NSString *reason, BOOL suppressed);
FOUNDATION_EXPORT BOOL axs_duodesktop_isSuppressed(void);
#ifdef __cplusplus
}
#endif
