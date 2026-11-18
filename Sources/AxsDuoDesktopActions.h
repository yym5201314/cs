#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Posted after an action record set changes so visible grids can reload.
FOUNDATION_EXPORT NSString * const AxsDuoDesktopActionsChanged;

// Record schema: type (tool/app/url/shortcut), value, title, id, enabled.
NSArray<NSDictionary *> *axs_duodesktop_catalog(void);
NSDictionary * _Nullable axs_duodesktop_normalizeRecord(id _Nullable input);
NSArray<NSDictionary *> *axs_duodesktop_records(NSString * _Nullable key);
BOOL axs_duodesktop_saveRecords(NSString * _Nullable key, NSArray<NSDictionary *> *records,
                                NSError * _Nullable * _Nullable error);
NSArray<NSDictionary *> *axs_duodesktop_applicationRecords(void);

BOOL axs_duodesktop_performAction(NSDictionary *record);
BOOL axs_duodesktop_performActionWithError(NSDictionary *record, NSError * _Nullable * _Nullable error);
NSString * _Nullable axs_duodesktop_unavailableReason(NSDictionary * _Nullable record);
NSNumber * _Nullable axs_duodesktop_actionState(NSDictionary * _Nullable record);
UIImage * _Nullable axs_duodesktop_actionImage(NSDictionary * _Nullable record);
BOOL axs_duodesktop_launchApplication(NSString *bundleID, NSError * _Nullable * _Nullable error);

UIViewController * _Nullable axs_duodesktop_presenter(void);
void axs_duodesktop_showMessage(NSString *message);

NS_ASSUME_NONNULL_END
