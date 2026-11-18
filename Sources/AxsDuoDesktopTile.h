#pragma once

#import <UIKit/UIKit.h>

// Small self-contained action button used by the carousel grid and the rail.
@interface AxsDuoDesktopActionTile : UIControl
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic) BOOL vertical;
- (void)axs_duodesktop_setRecord:(NSDictionary *)record;
- (NSDictionary *)axs_duodesktop_record;
@end
