#import <UIKit/UIKit.h>
#import "AxsDuoDesktopConfig.h"
#import "AxsDuoDesktopHome.h"
#import "AxsDuoDesktopPrivate.h"
#import "AxsDuoDesktopRail.h"
#import "AxsDuoDesktopRuntime.h"

// The injection filter is com.apple.springboard only; the guard below keeps the
// entry point harmless if someone reuses the dylib in another process.
%ctor {
    @autoreleasepool {
        if (!axs_duodesktop_isSpringBoard()) return;
        // Readers load a snapshot; they never write default preferences.
        [AxsDuoDesktopConfig axs_duodesktop_shared];
        dispatch_async(dispatch_get_main_queue(), ^{
            axs_duodesktop_installHomeHooks();
            axs_duodesktop_installRailHooks();
            axs_duodesktop_refreshHome();
            axs_duodesktop_refreshRails();
            axs_duodesktop_observeReload(^{
                axs_duodesktop_refreshHome();
                axs_duodesktop_refreshRails();
            });
        });
    }
}
