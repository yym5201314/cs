#pragma once

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

// Presents the record editor from whichever controller is on screen. Passing
// nil resolves the frontmost controller itself.
FOUNDATION_EXPORT void axs_duodesktop_presentActionEditor(UIViewController * _Nullable presenter);
#ifdef __cplusplus
}
#endif
