#pragma once

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

FOUNDATION_EXPORT void axs_duodesktop_installRailHooks(void);
FOUNDATION_EXPORT void axs_duodesktop_refreshRails(void);
FOUNDATION_EXPORT void axs_duodesktop_attachRail(UIView *host);
#ifdef __cplusplus
}
#endif
