#import "AxsDuoDesktopTile.h"
#import "AxsDuoDesktopActions.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static char AxsDuoDesktopTileRecordKey;

@implementation AxsDuoDesktopActionTile

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.userInteractionEnabled = NO;
        [self addSubview:_iconView];
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.numberOfLines = 2;
        _titleLabel.userInteractionEnabled = NO;
        [self addSubview:_titleLabel];
        self.layer.cornerRadius = 14;
        self.layer.cornerCurve = kCACornerCurveContinuous;
    }
    return self;
}

- (void)axs_duodesktop_setRecord:(NSDictionary *)record {
    objc_setAssociatedObject(self, &AxsDuoDesktopTileRecordKey, record,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.titleLabel.text = record[@"title"];
    self.iconView.image = axs_duodesktop_actionImage(record) ?: [UIImage systemImageNamed:@"app"];
    self.iconView.tintColor = UIColor.labelColor;
    NSString *reason = axs_duodesktop_unavailableReason(record);
    self.alpha = reason ? 0.5 : 1.0;
    NSNumber *state = axs_duodesktop_actionState(record);
    self.backgroundColor = state.boolValue
        ? [UIColor.systemBlueColor colorWithAlphaComponent:0.22] : UIColor.clearColor;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = record[@"title"];
    self.accessibilityHint = reason ?: @"轻点执行，长按编辑";
    [self setNeedsLayout];
}

- (NSDictionary *)axs_duodesktop_record {
    return objc_getAssociatedObject(self, &AxsDuoDesktopTileRecordKey);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    if (self.vertical) {
        CGFloat icon = MIN(28, height - 12);
        self.iconView.frame = CGRectMake(10, (height - icon) / 2, icon, icon);
        self.titleLabel.textAlignment = NSTextAlignmentLeft;
        self.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        self.titleLabel.frame = CGRectMake(10 + icon + 10, 0, MAX(0, width - icon - 32), height);
    } else {
        CGFloat icon = MIN(34, MAX(18, height * 0.44));
        self.iconView.frame = CGRectMake((width - icon) / 2, 8, icon, icon);
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        self.titleLabel.frame = CGRectMake(4, icon + 11, width - 8, MAX(0, height - icon - 13));
    }
}

@end
