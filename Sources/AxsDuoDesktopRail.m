#import "AxsDuoDesktopRail.h"
#import "AxsDuoDesktopActionEditor.h"
#import "AxsDuoDesktopActions.h"
#import "AxsDuoDesktopConfig.h"
#import "AxsDuoDesktopRuntime.h"
#import "AxsDuoDesktopTile.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static char AxsDuoDesktopRailKey;
static void (*axs_duodesktop_originalDockIconMove)(id, SEL);
static void (*axs_duodesktop_originalDockIconLayout)(id, SEL);

@interface AxsDuoDesktopActionRail : UIView
@property (nonatomic, strong) UIButton *handle;
@property (nonatomic, strong) UIVisualEffectView *panel;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic) BOOL expanded;
- (void)axs_duodesktop_refresh;
@end

@implementation AxsDuoDesktopActionRail

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _handle = [UIButton buttonWithType:UIButtonTypeSystem];
        [_handle setImage:[UIImage systemImageNamed:@"sidebar.left"] forState:UIControlStateNormal];
        _handle.tintColor = UIColor.labelColor;
        _handle.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.94];
        _handle.layer.cornerRadius = 17;
        _handle.accessibilityLabel = @"DuoDesktop 快捷侧栏";
        _handle.accessibilityHint = @"轻点展开快捷动作，长按编辑";
        [_handle addTarget:self action:@selector(axs_duodesktop_toggle)
          forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *press =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                          action:@selector(axs_duodesktop_edit:)];
        [_handle addGestureRecognizer:press];
        [self addSubview:_handle];

        _panel = [[UIVisualEffectView alloc]
            initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
        _panel.layer.cornerRadius = 20;
        _panel.layer.cornerCurve = kCACornerCurveContinuous;
        _panel.clipsToBounds = YES;
        _panel.hidden = YES;
        [self addSubview:_panel];

        _stack = [[UIStackView alloc] initWithFrame:CGRectZero];
        _stack.axis = UILayoutConstraintAxisVertical;
        _stack.spacing = 2;
        _stack.distribution = UIStackViewDistributionFillEqually;
        [self.panel.contentView addSubview:_stack];
    }
    return self;
}

- (void)axs_duodesktop_toggle {
    self.expanded = !self.expanded;
    // Widen before refreshing: touches outside the view bounds are not delivered.
    CGRect frame = self.frame;
    frame.size.width = self.expanded ? 140 : 34;
    self.frame = frame;
    [self axs_duodesktop_refresh];
}

- (void)axs_duodesktop_edit:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    axs_duodesktop_presentActionEditor(axs_duodesktop_presenter());
}

- (void)axs_duodesktop_tileTapped:(AxsDuoDesktopActionTile *)tile {
    NSDictionary *record = [tile axs_duodesktop_record];
    if (record) axs_duodesktop_performAction(record);
}

- (void)axs_duodesktop_refresh {
    BOOL visible = axs_duodesktop_flag(@"enabled", NO)
        && axs_duodesktop_flag(@"railEnabled", YES)
        && !axs_duodesktop_flag(@"railHidden", NO);
    self.hidden = !visible;
    self.panel.hidden = !self.expanded;
    if (!visible) return;

    for (UIView *view in self.stack.arrangedSubviews.copy) {
        [self.stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    NSUInteger count = 0;
    for (NSDictionary *record in axs_duodesktop_records(nil)) {
        if (![record[@"enabled"] boolValue]) continue;
        if (count >= 6) break;
        AxsDuoDesktopActionTile *tile = [[AxsDuoDesktopActionTile alloc] initWithFrame:CGRectZero];
        tile.vertical = YES;
        [tile axs_duodesktop_setRecord:record];
        [tile addTarget:self action:@selector(axs_duodesktop_tileTapped:)
            forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *press =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                          action:@selector(axs_duodesktop_edit:)];
        press.minimumPressDuration = 0.6;
        [tile addGestureRecognizer:press];
        [self.stack addArrangedSubview:tile];
        count++;
    }
    self.panel.hidden = !self.expanded || count == 0;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = CGRectGetHeight(self.bounds);
    self.handle.frame = CGRectMake(0, (height - 52) / 2, 34, 52);
    CGFloat panelHeight = MIN(height, MAX(0, self.stack.arrangedSubviews.count * 46 + 12));
    self.panel.frame = CGRectMake(40, (height - panelHeight) / 2, 96, panelHeight);
    self.stack.frame = CGRectMake(4, 6, 88, MAX(0, panelHeight - 12));
}

@end

static void axs_duodesktop_attach(UIView *host) {
    if (![host isKindOfClass:[UIView class]]) return;
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ axs_duodesktop_attach(host); });
        return;
    }
    AxsDuoDesktopActionRail *rail = objc_getAssociatedObject(host, &AxsDuoDesktopRailKey);
    BOOL created = rail == nil;
    if (!rail) {
        rail = [[AxsDuoDesktopActionRail alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(host, &AxsDuoDesktopRailKey, rail, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [host addSubview:rail];
    }
    BOOL visible = axs_duodesktop_flag(@"enabled", NO)
        && axs_duodesktop_flag(@"railEnabled", YES)
        && !axs_duodesktop_flag(@"railHidden", NO);
    CGFloat height = MAX(120, MIN(320, CGRectGetHeight(host.bounds) - 220));
    CGFloat width = rail.expanded ? 140 : 34;
    rail.frame = CGRectMake(MAX(2, host.safeAreaInsets.left + 2),
                            (CGRectGetHeight(host.bounds) - height) / 2, width, height);
    rail.hidden = !visible;
    // Dock layout runs often; only rebuild the action list on creation or reload.
    if (created) [rail axs_duodesktop_refresh];
}

void axs_duodesktop_attachRail(UIView *host) {
    if (!axs_duodesktop_isSpringBoard()) return;
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ axs_duodesktop_attachRail(host); });
        return;
    }
    Class rootClass = NSClassFromString(@"SBRootFolderView");
    UIView *root = host;
    while (root && rootClass && ![root isKindOfClass:rootClass]) root = root.superview;
    if (root) axs_duodesktop_attach(root);
}

void axs_duodesktop_refreshRails(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ axs_duodesktop_refreshRails(); });
        return;
    }
    for (UIWindow *window in axs_duodesktop_windows()) {
        Class rootClass = NSClassFromString(@"SBRootFolderView");
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
        while (queue.count) {
            UIView *view = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if (rootClass && [view isKindOfClass:rootClass]) {
                axs_duodesktop_attach(view);
                AxsDuoDesktopActionRail *rail =
                    objc_getAssociatedObject(view, &AxsDuoDesktopRailKey);
                [rail axs_duodesktop_refresh];
                break;
            }
            [queue addObjectsFromArray:view.subviews];
        }
    }
}

static void axs_duodesktop_dockIconMove(id self, SEL cmd) {
    if (axs_duodesktop_originalDockIconMove) axs_duodesktop_originalDockIconMove(self, cmd);
    axs_duodesktop_attachRail(self);
}

static void axs_duodesktop_dockIconLayout(id self, SEL cmd) {
    if (axs_duodesktop_originalDockIconLayout) axs_duodesktop_originalDockIconLayout(self, cmd);
    axs_duodesktop_attachRail(self);
}

void axs_duodesktop_installRailHooks(void) {
    if (!axs_duodesktop_isSpringBoard()) return;
    Class dock = NSClassFromString(@"SBDockIconListView");
    axs_duodesktop_installHook(@"rail.dock.move", dock, NSSelectorFromString(@"didMoveToWindow"), "v@:",
                               (IMP)axs_duodesktop_dockIconMove, (IMP *)&axs_duodesktop_originalDockIconMove);
    axs_duodesktop_installHook(@"rail.dock.layout", dock, @selector(layoutSubviews), "v@:",
                               (IMP)axs_duodesktop_dockIconLayout, (IMP *)&axs_duodesktop_originalDockIconLayout);
    axs_duodesktop_refreshRails();
}
