#pragma once

#import <UIKit/UIKit.h>

// DuoDesktop talks to SpringBoard through NSClassFromString + NSInvocation, so
// no private header is needed at build time. These are the selectors confirmed
// on iOS 15-16, each guarded by an encoding check before it is installed or
// invoked:
//
//   SBRootFolderView              layoutSubviews, didMoveToWindow
//   SBDockView                    layoutSubviews
//   SBDockIconListView            layoutSubviews, didMoveToWindow
//   SBHomeScreenController        searchPresenterWillPresentSearch:animated:
//                                 searchPresenterWillDismissSearch:animated:
//   SBHIconManager                setEditing:
//   SBCoverSheetPresentationManager
//                                 coverSheetSlidingViewControllerDidEndTransition:toPresented:
//   SBRootFolderController        rootFolderView:willPresentPageManagementWithLayoutManager:
//                                 animator:context:
//                                 rootFolderView:didDismissPageManagementWithLayoutManager:context:
