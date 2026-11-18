#import "AxsDuoDesktopHome.h"
#import "AxsDuoDesktopActions.h"
#import "AxsDuoDesktopActionEditor.h"
#import "AxsDuoDesktopConfig.h"
#import "AxsDuoDesktopTile.h"
#import "AxsDuoDesktopRuntime.h"
#import <EventKit/EventKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <math.h>

static char AxsDuoDesktopEventDateKey;

@class AxsDuoDesktopHomeController;

// Declared once here so the UIKit classes below can be ordered for readability.
static NSMutableSet<NSString *> *axs_duodesktop_suppression(void);
static AxsDuoDesktopHomeController *axs_duodesktop_controller(void);
static UIView *axs_duodesktop_findView(UIView *view, NSString *name, NSUInteger depth);
static NSString *axs_duodesktop_string(id value);
static BOOL axs_duodesktop_calendarAllowed(void);
static void *axs_duodesktop_mediaHandle;
static NSString *axs_duodesktop_mediaKey(const char *symbol);
static void (*axs_duodesktop_mediaInfo(void))(dispatch_queue_t, void (^)(CFDictionaryRef));
static void (*axs_duodesktop_mediaPlaying(void))(dispatch_queue_t, void (^)(BOOL));
static BOOL (*axs_duodesktop_mediaCommand(void))(uint32_t, CFDictionaryRef);
static void (*axs_duodesktop_mediaSeek(void))(double);

#pragma mark - Clock face

@interface AxsDuoDesktopClockFace : UIView
@property (nonatomic) BOOL axs_duodesktop_showsSeconds;
- (void)axs_duodesktop_updateWithDate:(NSDate *)date;
@end

@implementation AxsDuoDesktopClockFace {
    NSMutableArray<CALayer *> *_ticks;
    CALayer *_hourHand;
    CALayer *_minuteHand;
    CALayer *_secondHand;
    NSDate *_date;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        _ticks = [NSMutableArray array];
        for (NSInteger index = 0; index < 12; index++) {
            CALayer *tick = [CALayer layer];
            tick.backgroundColor = UIColor.labelColor.CGColor;
            tick.cornerRadius = 1;
            [self.layer addSublayer:tick];
            [_ticks addObject:tick];
        }
        _hourHand = [self axs_duodesktop_makeHandWithWidth:4 color:UIColor.labelColor];
        _minuteHand = [self axs_duodesktop_makeHandWithWidth:3 color:UIColor.labelColor];
        _secondHand = [self axs_duodesktop_makeHandWithWidth:1.5 color:UIColor.systemOrangeColor];
        _date = NSDate.date;
    }
    return self;
}

- (CALayer *)axs_duodesktop_makeHandWithWidth:(CGFloat)width color:(UIColor *)color {
    CALayer *hand = [CALayer layer];
    hand.backgroundColor = color.CGColor;
    hand.cornerRadius = width / 2;
    hand.anchorPoint = CGPointMake(0.5, 1.0);
    [self.layer addSublayer:hand];
    return hand;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
    CGFloat radius = MAX(10, side / 2 - 3);
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    for (NSUInteger index = 0; index < _ticks.count; index++) {
        CALayer *tick = _ticks[index];
        CGFloat angle = index * M_PI / 6;
        CGFloat length = (index % 3 == 0) ? 9 : 5;
        tick.bounds = CGRectMake(0, 0, (index % 3 == 0) ? 2.5 : 1.5, length);
        tick.position = CGPointMake(center.x + sin(angle) * (radius - length / 2),
                                    center.y - cos(angle) * (radius - length / 2));
        tick.transform = CATransform3DMakeRotation(angle, 0, 0, 1);
    }
    _hourHand.bounds = CGRectMake(0, 0, 4, radius * 0.50);
    _minuteHand.bounds = CGRectMake(0, 0, 3, radius * 0.72);
    _secondHand.bounds = CGRectMake(0, 0, 1.5, radius * 0.86);
    _hourHand.position = center;
    _minuteHand.position = center;
    _secondHand.position = center;
    [self axs_duodesktop_updateWithDate:_date];
}

- (void)axs_duodesktop_updateWithDate:(NSDate *)date {
    _date = date ?: NSDate.date;
    NSDateComponents *parts = [NSCalendar.currentCalendar components:
        (NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond) fromDate:_date];
    CGFloat hour = (parts.hour % 12) + parts.minute / 60.0;
    CGFloat minute = parts.minute + parts.second / 60.0;
    _hourHand.transform = CATransform3DMakeRotation(hour * M_PI / 6, 0, 0, 1);
    _minuteHand.transform = CATransform3DMakeRotation(minute * M_PI / 30, 0, 0, 1);
    _secondHand.hidden = !self.axs_duodesktop_showsSeconds;
    _secondHand.transform = CATransform3DMakeRotation(parts.second * M_PI / 30, 0, 0, 1);
}

@end

#pragma mark - Controller

@interface AxsDuoDesktopHomeController : NSObject
@property (nonatomic, weak) UIView *root;
@property (nonatomic, strong) UIView *surface;
@property (nonatomic, strong) UIVisualEffectView *material;
@property (nonatomic, strong) UIScrollView *pager;
@property (nonatomic, strong) UIPageControl *dots;
@property (nonatomic, strong) UIButton *expandButton;
@property (nonatomic, strong) UIButton *editButton;
@property (nonatomic, strong) UILabel *heading;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIView *> *panes;
@property (nonatomic, copy) NSArray<NSString *> *kinds;
@property (nonatomic, strong) NSMapTable<UIView *, NSValue *> *nativeFrames;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSMutableArray *observers;
@property (nonatomic) BOOL expanded;
@property (nonatomic) BOOL applyingLayout;
@property (nonatomic) BOOL rebuilding;
@property (nonatomic) NSInteger selected;
@property (nonatomic) NSUInteger ticks;

@property (nonatomic, strong) UILabel *clockTime;
@property (nonatomic, strong) UIButton *clockDate;
@property (nonatomic, strong) AxsDuoDesktopClockFace *clockFace;

@property (nonatomic, strong) UIImageView *artwork;
@property (nonatomic, strong) UILabel *mediaTitle;
@property (nonatomic, strong) UILabel *mediaArtist;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UISlider *scrubber;
@property (nonatomic, strong) UILabel *mediaTime;
@property (nonatomic, strong) NSDictionary *mediaInfo;
@property (nonatomic) NSTimeInterval mediaSample;
@property (nonatomic) BOOL mediaPending;
@property (nonatomic) BOOL mediaPlaying;

@property (nonatomic, strong) UIView *calendarRows;
@property (nonatomic, strong) UILabel *calendarStatus;
@property (nonatomic, strong) UIButton *calendarButton;
@property (nonatomic, strong) EKEventStore *eventStore;
@property (nonatomic, strong) NSArray<EKEvent *> *events;
@property (nonatomic, strong) dispatch_queue_t calendarQueue;
@property (nonatomic) NSUInteger calendarGeneration;
@property (nonatomic) BOOL calendarPending;

@property (nonatomic, strong) UIView *shortcutGrid;
@end

@implementation AxsDuoDesktopHomeController

- (instancetype)init {
    self = [super init];
    if (self) {
        _panes = [NSMutableDictionary dictionary];
        _nativeFrames = [NSMapTable weakToStrongObjectsMapTable];
        _observers = [NSMutableArray array];
        _calendarQueue = dispatch_queue_create("com.axs.duodesktop.calendar", DISPATCH_QUEUE_SERIAL);
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        __weak typeof(self) weakSelf = self;
        for (NSString *name in @[NSSystemTimeZoneDidChangeNotification,
                                 NSCurrentLocaleDidChangeNotification,
                                 UIApplicationSignificantTimeChangeNotification,
                                 UIApplicationDidBecomeActiveNotification]) {
            id token = [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                       usingBlock:^(__unused NSNotification *note) {
                [weakSelf axs_duodesktop_tick];
                [weakSelf axs_duodesktop_reloadCalendar];
                [weakSelf axs_duodesktop_refresh];
            }];
            [_observers addObject:token];
        }
        [_observers addObject:[center addObserverForName:EKEventStoreChangedNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                [weakSelf axs_duodesktop_reloadCalendar];
            }]];
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
    for (id token in _observers) [NSNotificationCenter.defaultCenter removeObserver:token];
}

- (void)axs_duodesktop_observeRoot:(UIView *)root {
    if (![root isKindOfClass:[UIView class]] || !root.window) return;
    if (CGRectGetWidth(root.bounds) < 100 || CGRectGetHeight(root.bounds) < 200) return;
    if (self.root != root) {
        [self axs_duodesktop_restoreNativeFrames];
        [self.surface removeFromSuperview];
        self.root = root;
        if (self.surface) [root addSubview:self.surface];
    }
    if (!self.surface) [self axs_duodesktop_rebuild];
    [self axs_duodesktop_applyLayout];
}

- (void)axs_duodesktop_refresh {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self axs_duodesktop_refresh]; });
        return;
    }
    if (!self.root) return;
    [self axs_duodesktop_restoreNativeFrames];
    [self axs_duodesktop_rebuild];
    [self axs_duodesktop_applyLayout];
    [self axs_duodesktop_tick];
    [self axs_duodesktop_requestMedia];
    [self axs_duodesktop_reloadCalendar];
    [self.root setNeedsLayout];
}

- (void)axs_duodesktop_restoreNativeFrames {
    if (self.applyingLayout) return;
    self.applyingLayout = YES;
    for (UIView *view in self.nativeFrames.keyEnumerator.allObjects) {
        NSValue *value = [self.nativeFrames objectForKey:view];
        if (view.superview && value && !CGRectEqualToRect(view.frame, value.CGRectValue)) {
            view.frame = value.CGRectValue;
        }
    }
    [self.nativeFrames removeAllObjects];
    self.applyingLayout = NO;
}

- (UILabel *)axs_duodesktop_labelIn:(UIView *)parent size:(CGFloat)size weight:(UIFontWeight)weight {
    UILabel *label = [UILabel new];
    label.textColor = UIColor.labelColor;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.65;
    [parent addSubview:label];
    return label;
}

- (UIButton *)axs_duodesktop_buttonIn:(UIView *)parent title:(NSString *)title
                               symbol:(NSString *)symbol selector:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    if (symbol.length) [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.tintColor = UIColor.labelColor;
    button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    button.layer.cornerRadius = 12;
    if (selector) [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    [parent addSubview:button];
    return button;
}

- (void)axs_duodesktop_rebuild {
    if (self.rebuilding) return;
    self.rebuilding = YES;
    [self.timer invalidate];
    self.timer = nil;
    [self.surface removeFromSuperview];
    [self.panes removeAllObjects];
    self.clockTime = nil;
    self.clockDate = nil;
    self.clockFace = nil;
    self.artwork = nil;
    self.mediaTitle = nil;
    self.mediaArtist = nil;
    self.playButton = nil;
    self.scrubber = nil;
    self.mediaTime = nil;
    self.calendarRows = nil;
    self.calendarStatus = nil;
    self.calendarButton = nil;
    self.shortcutGrid = nil;

    NSMutableArray<NSString *> *kinds = [NSMutableArray array];
    if (axs_duodesktop_flag(@"showClock", YES)) [kinds addObject:@"clock"];
    if (axs_duodesktop_flag(@"showMedia", YES)) [kinds addObject:@"media"];
    if (axs_duodesktop_flag(@"showCalendar", YES)) [kinds addObject:@"calendar"];
    if (axs_duodesktop_flag(@"showShortcuts", YES)) [kinds addObject:@"shortcuts"];
    self.kinds = kinds;
    self.selected = 0;

    UIView *surface = [[UIView alloc] initWithFrame:CGRectZero];
    surface.accessibilityIdentifier = @"DuoDesktop.Home.Surface";
    self.surface = surface;
    self.material = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    self.material.layer.cornerRadius = 28;
    self.material.layer.cornerCurve = kCACornerCurveContinuous;
    self.material.clipsToBounds = YES;
    self.material.userInteractionEnabled = NO;
    [surface addSubview:self.material];

    self.heading = [self axs_duodesktop_labelIn:surface size:12 weight:UIFontWeightSemibold];
    self.heading.text = @"DUODESKTOP";
    self.heading.textColor = UIColor.secondaryLabelColor;

    self.editButton = [self axs_duodesktop_buttonIn:surface title:@"" symbol:@"ellipsis.circle"
                                           selector:@selector(axs_duodesktop_editShortcuts:)];
    self.editButton.accessibilityLabel = @"管理快捷动作";
    self.expandButton = [self axs_duodesktop_buttonIn:surface title:@""
        symbol:self.expanded ? @"chevron.down" : @"chevron.up"
        selector:@selector(axs_duodesktop_toggleExpanded:)];
    self.expandButton.accessibilityLabel = @"展开或收起 DuoDesktop";

    self.pager = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.pager.pagingEnabled = YES;
    self.pager.showsHorizontalScrollIndicator = NO;
    self.pager.showsVerticalScrollIndicator = NO;
    self.pager.directionalLockEnabled = YES;
    self.pager.accessibilityIdentifier = @"DuoDesktop.Home.Carousel";
    [surface addSubview:self.pager];

    self.dots = [UIPageControl new];
    self.dots.numberOfPages = MAX(1, kinds.count);
    self.dots.pageIndicatorTintColor = [UIColor.secondaryLabelColor colorWithAlphaComponent:0.3];
    self.dots.currentPageIndicatorTintColor = UIColor.labelColor;
    [self.dots addTarget:self action:@selector(axs_duodesktop_pageChanged:)
        forControlEvents:UIControlEventValueChanged];
    [surface addSubview:self.dots];

    for (NSString *kind in kinds) {
        UIView *pane = [self axs_duodesktop_buildPane:kind];
        if (!pane) continue;
        self.panes[kind] = pane;
        [self.pager addSubview:pane];
    }
    if (self.root) [self.root addSubview:surface];
    self.rebuilding = NO;
}

- (UIView *)axs_duodesktop_buildPane:(NSString *)kind {
    UIView *pane = [[UIView alloc] initWithFrame:CGRectZero];
    pane.accessibilityIdentifier = [@"DuoDesktop.Home." stringByAppendingString:kind];
    BOOL enabled = axs_duodesktop_flag(@"enabled", NO);
    if (!enabled) return pane;

    if ([kind isEqualToString:@"clock"]) {
        self.clockTime = [self axs_duodesktop_labelIn:pane size:62 weight:UIFontWeightLight];
        self.clockTime.font = [UIFont monospacedDigitSystemFontOfSize:62 weight:UIFontWeightLight];
        self.clockTime.userInteractionEnabled = YES;
        [self.clockTime addGestureRecognizer:[[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(axs_duodesktop_openClock:)]];
        self.clockTime.accessibilityTraits = UIAccessibilityTraitButton;
        self.clockTime.accessibilityLabel = @"打开时钟";
        self.clockFace = [[AxsDuoDesktopClockFace alloc] initWithFrame:CGRectZero];
        [pane addSubview:self.clockFace];
        self.clockDate = [self axs_duodesktop_buttonIn:pane title:@"" symbol:nil
            selector:@selector(axs_duodesktop_openCalendar:)];
        self.clockDate.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    } else if ([kind isEqualToString:@"media"]) {
        self.artwork = [[UIImageView alloc] initWithFrame:CGRectZero];
        self.artwork.layer.cornerRadius = 14;
        self.artwork.clipsToBounds = YES;
        self.artwork.contentMode = UIViewContentModeScaleAspectFill;
        self.artwork.backgroundColor = [UIColor.secondaryLabelColor colorWithAlphaComponent:0.15];
        self.artwork.userInteractionEnabled = YES;
        [self.artwork addGestureRecognizer:[[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(axs_duodesktop_openMusic:)]];
        [pane addSubview:self.artwork];
        self.mediaTitle = [self axs_duodesktop_labelIn:pane size:18 weight:UIFontWeightSemibold];
        self.mediaTitle.text = @"暂无正在播放";
        self.mediaArtist = [self axs_duodesktop_labelIn:pane size:13 weight:UIFontWeightRegular];
        self.mediaArtist.textColor = UIColor.secondaryLabelColor;
        self.playButton = [self axs_duodesktop_buttonIn:pane title:@"" symbol:@"play.fill"
            selector:@selector(axs_duodesktop_playPause:)];
        self.playButton.accessibilityLabel = @"播放或暂停";
        UIButton *previous = [self axs_duodesktop_buttonIn:pane title:@"" symbol:@"backward.fill"
            selector:@selector(axs_duodesktop_previous:)];
        previous.tag = 310;
        UIButton *next = [self axs_duodesktop_buttonIn:pane title:@"" symbol:@"forward.fill"
            selector:@selector(axs_duodesktop_next:)];
        next.tag = 311;
        self.scrubber = [UISlider new];
        [self.scrubber addTarget:self action:@selector(axs_duodesktop_seek:)
            forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        self.scrubber.accessibilityLabel = @"播放进度";
        [pane addSubview:self.scrubber];
        self.mediaTime = [self axs_duodesktop_labelIn:pane size:11 weight:UIFontWeightRegular];
        self.mediaTime.textColor = UIColor.secondaryLabelColor;
    } else if ([kind isEqualToString:@"calendar"]) {
        UIButton *header = [self axs_duodesktop_buttonIn:pane title:@"日历" symbol:@"calendar"
            selector:@selector(axs_duodesktop_openCalendar:)];
        header.tag = 320;
        header.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        self.calendarStatus = [self axs_duodesktop_labelIn:pane size:14 weight:UIFontWeightRegular];
        self.calendarStatus.numberOfLines = 3;
        self.calendarRows = [UIView new];
        [pane addSubview:self.calendarRows];
        self.calendarButton = [self axs_duodesktop_buttonIn:pane title:@"打开日历设置"
            symbol:nil selector:@selector(axs_duodesktop_calendarSettings:)];
        self.calendarButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [self axs_duodesktop_renderCalendar];
    } else if ([kind isEqualToString:@"shortcuts"]) {
        self.shortcutGrid = [UIView new];
        [pane addSubview:self.shortcutGrid];
        [self axs_duodesktop_reloadShortcuts];
    }
    return pane;
}

- (void)axs_duodesktop_reloadShortcuts {
    if (!self.shortcutGrid) return;
    for (UIView *view in self.shortcutGrid.subviews.copy) [view removeFromSuperview];
    NSArray<NSDictionary *> *records = axs_duodesktop_records(nil);
    NSUInteger limit = self.expanded ? 9 : 8;
    NSUInteger count = 0;
    for (NSDictionary *record in records) {
        if (![record[@"enabled"] boolValue]) continue;
        if (count >= limit) break;
        AxsDuoDesktopActionTile *tile = [[AxsDuoDesktopActionTile alloc] initWithFrame:CGRectZero];
        [tile axs_duodesktop_setRecord:record];
        [tile addTarget:self action:@selector(axs_duodesktop_shortcutTapped:)
            forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(axs_duodesktop_editShortcuts:)];
        press.minimumPressDuration = 0.6;
        [tile addGestureRecognizer:press];
        [self.shortcutGrid addSubview:tile];
        count++;
    }
    if (count == 0) {
        UILabel *empty = [self axs_duodesktop_labelIn:self.shortcutGrid size:14 weight:UIFontWeightRegular];
        empty.tag = 331;
        empty.text = @"还没有快捷动作\n点右上角管理，或长按此处添加";
        empty.numberOfLines = 2;
        empty.textAlignment = NSTextAlignmentCenter;
        empty.textColor = UIColor.secondaryLabelColor;
    }
    [self.shortcutGrid setNeedsLayout];
    [self axs_duodesktop_layoutPanes];
}

- (void)axs_duodesktop_applyLayout {
    if (self.applyingLayout || self.rebuilding || !self.root) return;
    BOOL visible = axs_duodesktop_flag(@"enabled", NO) && self.kinds.count > 0
        && axs_duodesktop_suppression().count == 0 && self.root.window;
    self.surface.hidden = !visible;
    if (!visible) {
        [self.timer invalidate];
        self.timer = nil;
        [self axs_duodesktop_restoreNativeFrames];
        return;
    }
    self.applyingLayout = YES;
    UIView *root = self.root;
    CGFloat width = CGRectGetWidth(root.bounds);
    CGFloat total = CGRectGetHeight(root.bounds);
    CGFloat top = MAX(root.safeAreaInsets.top, 36) + 8;
    CGFloat height = self.expanded ? MIN(370, total * 0.46) : 226;
    if (width > total) height = self.expanded ? 210 : 170;
    height = MIN(height, MAX(100, total - top - 200));
    CGRect frame = CGRectMake(16, top, width - 32, height);
    if (!CGRectEqualToRect(self.surface.frame, frame)) self.surface.frame = frame;
    self.material.frame = self.surface.bounds;
    self.heading.frame = CGRectMake(18, 8, 140, 24);
    self.editButton.frame = CGRectMake(width - 138, 2, 42, 38);
    self.expandButton.frame = CGRectMake(width - 92, 2, 42, 38);
    self.pager.frame = CGRectMake(0, 38, width - 32, MAX(1, height - 62));
    self.dots.frame = CGRectMake(40, height - 26, width - 112, 24);
    self.dots.hidden = self.kinds.count < 2;
    [self axs_duodesktop_layoutPanes];

    UIView *scroll = axs_duodesktop_findView(root, @"SBIconScrollView", 0);
    if (scroll && scroll.superview) {
        NSValue *saved = [self.nativeFrames objectForKey:scroll];
        CGRect original = saved ? saved.CGRectValue : scroll.frame;
        if (!saved) [self.nativeFrames setObject:[NSValue valueWithCGRect:original] forKey:scroll];
        CGRect converted = [scroll.superview convertRect:original toView:root];
        CGFloat bottom = CGRectGetMaxY(converted);
        CGFloat desired = MAX(CGRectGetMinY(converted), CGRectGetMaxY(self.surface.frame) + 8);
        if (bottom - desired >= 100) {
            converted.origin.y = desired;
            converted.size.height = bottom - desired;
            CGRect target = [root convertRect:converted toView:scroll.superview];
            if (!CGRectEqualToRect(scroll.frame, target)) scroll.frame = target;
        }
    }
    [root bringSubviewToFront:self.surface];
    self.applyingLayout = NO;
    if (!self.timer) {
        __weak typeof(self) weakSelf = self;
        self.timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *timer) {
            [weakSelf axs_duodesktop_tick];
        }];
        [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
        [self axs_duodesktop_requestMedia];
        [self axs_duodesktop_reloadCalendar];
    }
}

- (void)axs_duodesktop_layoutPanes {
    CGFloat width = self.pager.bounds.size.width;
    CGFloat height = self.pager.bounds.size.height;
    if (width <= 0) return;
    self.pager.contentSize = CGSizeMake(width * self.kinds.count, height);
    for (NSUInteger index = 0; index < self.kinds.count; index++) {
        self.panes[self.kinds[index]].frame = CGRectMake(width * index, 0, width, height);
    }
    if (!self.pager.dragging && !self.pager.decelerating) {
        self.pager.contentOffset = CGPointMake(width * self.selected, 0);
    }
    BOOL analog = axs_duodesktop_flag(@"clockAnalog", NO);
    self.clockFace.hidden = !analog;
    self.clockFace.axs_duodesktop_showsSeconds = axs_duodesktop_flag(@"clockSeconds", YES);
    self.clockTime.hidden = analog;
    CGFloat face = MIN(140, height - 26);
    self.clockFace.frame = CGRectMake((width - face) / 2, 0, face, face);
    self.clockTime.frame = CGRectMake(20, MAX(0, (height - 104) / 2 - 10), width - 40, 80);
    self.clockTime.textAlignment = axs_duodesktop_flag(@"clockCentered", NO)
        ? NSTextAlignmentCenter : NSTextAlignmentLeft;
    self.clockDate.frame = CGRectMake(14, height - 36, width - 28, 32);

    CGFloat art = self.expanded ? MIN(124, height - 94) : 64;
    self.artwork.frame = CGRectMake(18, 5, art, art);
    self.mediaTitle.frame = CGRectMake(art + 30, 6, MAX(30, width - art - 46), 26);
    self.mediaArtist.frame = CGRectMake(art + 30, 34, MAX(30, width - art - 46), 35);
    self.mediaArtist.numberOfLines = 2;
    CGFloat controls = self.expanded ? MAX(art + 9, height - 93) : 72;
    UIView *media = self.panes[@"media"];
    [media viewWithTag:310].frame = CGRectMake(width / 2 - 90, controls, 54, 38);
    self.playButton.frame = CGRectMake(width / 2 - 27, controls, 54, 38);
    [media viewWithTag:311].frame = CGRectMake(width / 2 + 36, controls, 54, 38);
    self.scrubber.frame = CGRectMake(18, height - 42, width - 36, 26);
    self.mediaTime.frame = CGRectMake(23, height - 18, width - 46, 16);

    UIView *calendar = self.panes[@"calendar"];
    [calendar viewWithTag:320].frame = CGRectMake(14, 0, width - 28, 30);
    self.calendarStatus.frame = CGRectMake(20, 36, width - 40, 54);
    self.calendarRows.frame = CGRectMake(16, 90, width - 32, MAX(0, height - 134));
    self.calendarButton.frame = CGRectMake(20, height - 44, width - 40, 36);

    self.shortcutGrid.frame = CGRectMake(10, 4, width - 20, height - 8);
    CGFloat gridWidth = self.shortcutGrid.bounds.size.width;
    CGFloat gridHeight = self.shortcutGrid.bounds.size.height;
    NSUInteger count = self.shortcutGrid.subviews.count;
    NSUInteger columns = self.expanded ? 3 : 4;
    NSUInteger rows = MAX(1, (count + columns - 1) / columns);
    CGFloat cellWidth = gridWidth / columns;
    CGFloat cellHeight = MAX(40, gridHeight / rows);
    for (NSUInteger index = 0; index < count; index++) {
        UIView *tile = self.shortcutGrid.subviews[index];
        if (tile.tag == 331) {
            tile.frame = CGRectMake(10, 12, gridWidth - 20, MAX(40, gridHeight - 24));
        } else {
            tile.frame = CGRectMake((index % columns) * cellWidth,
                                    (index / columns) * cellHeight, cellWidth, cellHeight);
        }
    }
    [self axs_duodesktop_renderCalendar];
}

- (void)axs_duodesktop_updateSelection {
    CGFloat width = self.pager.bounds.size.width;
    if (width <= 0 || !self.kinds.count) return;
    NSInteger selected = (NSInteger)llround(self.pager.contentOffset.x / width);
    selected = MAX(0, MIN((NSInteger)self.kinds.count - 1, selected));
    if (selected == self.selected) return;
    self.selected = selected;
    self.dots.currentPage = selected;
}

- (void)axs_duodesktop_tick {
    if (!self.root.window || self.surface.hidden) {
        [self.timer invalidate];
        self.timer = nil;
        return;
    }
    NSDate *now = NSDate.date;
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.timeStyle = NSDateFormatterShortStyle;
    self.clockTime.text = [formatter stringFromDate:now];
    [self.clockFace axs_duodesktop_updateWithDate:now];
    formatter.timeStyle = NSDateFormatterNoStyle;
    formatter.dateStyle = NSDateFormatterFullStyle;
    [self.clockDate setTitle:[formatter stringFromDate:now] forState:UIControlStateNormal];

    NSTimeInterval duration = [self.mediaInfo[axs_duodesktop_mediaKey("kMRMediaRemoteNowPlayingInfoDuration") ?: @"Duration"] doubleValue];
    NSTimeInterval elapsed = [self.mediaInfo[axs_duodesktop_mediaKey("kMRMediaRemoteNowPlayingInfoElapsedTime") ?: @"ElapsedTime"] doubleValue];
    if (self.mediaPlaying) elapsed += MAX(0, CACurrentMediaTime() - self.mediaSample);
    elapsed = MIN(MAX(0, elapsed), MAX(0, duration));
    if (!self.scrubber.tracking) self.scrubber.value = duration > 0 ? elapsed / duration : 0;
    self.scrubber.enabled = axs_duodesktop_mediaSeek() != NULL && duration > 0;
    self.mediaTime.text = duration > 0
        ? [NSString stringWithFormat:@"%ld:%02ld / %ld:%02ld", (long)elapsed / 60,
           (long)elapsed % 60, (long)duration / 60, (long)duration % 60]
        : @"";
    [self axs_duodesktop_updateSelection];
    if (++self.ticks % 10 == 0) [self axs_duodesktop_requestMedia];
    if (self.ticks % 60 == 0) [self axs_duodesktop_reloadCalendar];
}

- (void)axs_duodesktop_toggleExpanded:(id)sender {
    self.expanded = !self.expanded;
    [self.expandButton setImage:[UIImage systemImageNamed:
        self.expanded ? @"chevron.down" : @"chevron.up"] forState:UIControlStateNormal];
    [self axs_duodesktop_restoreNativeFrames];
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0
        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
        animations:^{ [self axs_duodesktop_applyLayout]; } completion:nil];
    [self axs_duodesktop_reloadShortcuts];
}

- (void)axs_duodesktop_pageChanged:(UIPageControl *)control {
    if (!self.kinds.count) return;
    self.selected = MAX(0, MIN((NSInteger)self.kinds.count - 1, control.currentPage));
    [self.pager setContentOffset:CGPointMake(self.selected * self.pager.bounds.size.width, 0)
                        animated:YES];
}

- (void)axs_duodesktop_openClock:(id)sender {
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"clock-alarm:"] options:@{} completionHandler:nil];
}

- (void)axs_duodesktop_openCalendar:(id)sender {
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"calshow:"] options:@{} completionHandler:nil];
}

- (void)axs_duodesktop_calendarSettings:(id)sender {
    NSURL *url = [NSURL URLWithString:@"App-prefs:Privacy&path=CALENDARS"];
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (void)axs_duodesktop_openMusic:(id)sender {
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"music:"] options:@{} completionHandler:nil];
}

- (void)axs_duodesktop_shortcutTapped:(AxsDuoDesktopActionTile *)tile {
    NSDictionary *record = [tile axs_duodesktop_record];
    if (record) axs_duodesktop_performAction(record);
}

- (void)axs_duodesktop_editShortcuts:(id)sender {
    if ([sender isKindOfClass:[UIGestureRecognizer class]] &&
        [(UIGestureRecognizer *)sender state] != UIGestureRecognizerStateBegan) return;
    axs_duodesktop_presentActionEditor(axs_duodesktop_presenter());
}

- (void)axs_duodesktop_playPause:(id)sender {
    if (axs_duodesktop_mediaCommand()) {
        axs_duodesktop_mediaCommand()(2, NULL);
        [self axs_duodesktop_requestMedia];
    }
}

- (void)axs_duodesktop_previous:(id)sender {
    if (axs_duodesktop_mediaCommand()) {
        axs_duodesktop_mediaCommand()(5, NULL);
        [self axs_duodesktop_requestMedia];
    }
}

- (void)axs_duodesktop_next:(id)sender {
    if (axs_duodesktop_mediaCommand()) {
        axs_duodesktop_mediaCommand()(4, NULL);
        [self axs_duodesktop_requestMedia];
    }
}

- (void)axs_duodesktop_seek:(UISlider *)slider {
    NSTimeInterval duration = [self.mediaInfo[axs_duodesktop_mediaKey("kMRMediaRemoteNowPlayingInfoDuration") ?: @"Duration"] doubleValue];
    if (axs_duodesktop_mediaSeek() && duration > 0 && isfinite(duration)) {
        axs_duodesktop_mediaSeek()(slider.value * duration);
        [self axs_duodesktop_requestMedia];
    }
}

- (void)axs_duodesktop_requestMedia {
    if (self.mediaPending || self.surface.hidden || !self.mediaTitle) return;
    if (!axs_duodesktop_mediaInfo()) {
        self.mediaArtist.text = @"系统媒体接口不可用";
        self.playButton.enabled = NO;
        return;
    }
    self.mediaPending = YES;
    __weak typeof(self) weakSelf = self;
    axs_duodesktop_mediaInfo()(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
        AxsDuoDesktopHomeController *controller = weakSelf;
        if (!controller) return;
        controller.mediaPending = NO;
        controller.mediaInfo = info ? [(__bridge NSDictionary *)info copy] : @{};
        controller.mediaSample = CACurrentMediaTime();
        NSString *title = axs_duodesktop_string(controller.mediaInfo[axs_duodesktop_mediaKey("kMRMediaRemoteNowPlayingInfoTitle") ?: @"Title"]);
        NSString *artist = axs_duodesktop_string(controller.mediaInfo[axs_duodesktop_mediaKey("kMRMediaRemoteNowPlayingInfoArtist") ?: @"Artist"]);
        controller.mediaTitle.text = title.length ? title : @"暂无正在播放";
        controller.mediaArtist.text = artist.length ? artist : @"打开音乐开始播放";
        id data = controller.mediaInfo[axs_duodesktop_mediaKey("kMRMediaRemoteNowPlayingInfoArtworkData") ?: @"ArtworkData"];
        controller.artwork.image = [data isKindOfClass:[NSData class]]
            ? [UIImage imageWithData:data] : [UIImage systemImageNamed:@"music.note"];
        NSNumber *rate = controller.mediaInfo[axs_duodesktop_mediaKey("kMRMediaRemoteNowPlayingInfoPlaybackRate") ?: @"PlaybackRate"];
        if ([rate isKindOfClass:[NSNumber class]]) controller.mediaPlaying = rate.doubleValue > 0;
        [controller.playButton setImage:[UIImage systemImageNamed:
            controller.mediaPlaying ? @"pause.fill" : @"play.fill"] forState:UIControlStateNormal];
        [controller axs_duodesktop_tick];
    });
    if (axs_duodesktop_mediaPlaying()) {
        axs_duodesktop_mediaPlaying()(dispatch_get_main_queue(), ^(BOOL playing) {
            AxsDuoDesktopHomeController *controller = weakSelf;
            if (!controller) return;
            controller.mediaPlaying = playing;
            [controller.playButton setImage:[UIImage systemImageNamed:
                playing ? @"pause.fill" : @"play.fill"] forState:UIControlStateNormal];
        });
    }
    self.playButton.enabled = axs_duodesktop_mediaCommand() != NULL;
}

- (void)axs_duodesktop_reloadCalendar {
    if (!self.calendarRows || self.calendarPending || self.surface.hidden) return;
    if (!axs_duodesktop_calendarAllowed()) {
        self.events = @[];
        self.calendarStatus.hidden = NO;
        self.calendarRows.hidden = YES;
        self.calendarButton.hidden = NO;
        self.calendarStatus.text = @"SpringBoard 未获得日历权限。iOS 只会向应用授予读取权限，此页在越狱环境中通常不可用；可点日历图标查看系统日历。";
        [self axs_duodesktop_renderCalendar];
        return;
    }
    self.calendarPending = YES;
    NSUInteger generation = ++self.calendarGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.calendarQueue, ^{
        AxsDuoDesktopHomeController *controller = weakSelf;
        if (!controller) return;
        if (!controller.eventStore) controller.eventStore = [EKEventStore new];
        NSArray<EKEvent *> *events = @[];
        NSString *failure = nil;
        @try {
            NSDate *start = [NSCalendar.currentCalendar startOfDayForDate:NSDate.date];
            NSDate *end = [NSCalendar.currentCalendar dateByAddingUnit:NSCalendarUnitDay value:2
                                                               toDate:start options:0];
            NSPredicate *predicate = [controller.eventStore predicateForEventsWithStartDate:start
                                                    endDate:end calendars:nil];
            NSMutableArray<EKEvent *> *found = [NSMutableArray array];
            for (EKEvent *event in [controller.eventStore eventsMatchingPredicate:predicate]) {
                if ([event.endDate compare:NSDate.date] == NSOrderedAscending) continue;
                [found addObject:event];
            }
            events = [found sortedArrayUsingComparator:^NSComparisonResult(EKEvent *left, EKEvent *right) {
                return [left.startDate compare:right.startDate];
            }];
        } @catch (NSException *exception) {
            failure = @"无法读取日历，请检查系统日历权限。";
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            AxsDuoDesktopHomeController *current = weakSelf;
            if (!current || generation != current.calendarGeneration) return;
            current.calendarPending = NO;
            current.events = events;
            if (failure.length) {
                current.calendarStatus.text = failure;
                current.calendarStatus.hidden = NO;
            }
            [current axs_duodesktop_renderCalendar];
        });
    });
}

- (void)axs_duodesktop_renderCalendar {
    if (!self.calendarRows) return;
    for (UIView *view in self.calendarRows.subviews.copy) [view removeFromSuperview];
    BOOL allowed = axs_duodesktop_calendarAllowed();
    self.calendarRows.hidden = !allowed;
    self.calendarButton.hidden = allowed;
    if (!allowed) return;
    if (!self.events.count) {
        self.calendarStatus.hidden = NO;
        self.calendarStatus.text = @"今天没有更多日程";
        return;
    }
    self.calendarStatus.hidden = YES;
    CGFloat height = self.calendarRows.bounds.size.height;
    CGFloat width = self.calendarRows.bounds.size.width;
    CGFloat rowHeight = 42;
    NSUInteger count = MIN(self.events.count, (NSUInteger)MAX(1, floor(height / rowHeight)));
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.timeStyle = NSDateFormatterShortStyle;
    for (NSUInteger index = 0; index < count; index++) {
        EKEvent *event = self.events[index];
        NSString *time = event.allDay ? @"全天" : [formatter stringFromDate:event.startDate];
        if (![NSCalendar.currentCalendar isDateInToday:event.startDate]) {
            time = [@"明天 " stringByAppendingString:time];
        }
        UIButton *row = [self axs_duodesktop_buttonIn:self.calendarRows
            title:[NSString stringWithFormat:@"%@  %@", time, event.title ?: @"未命名日程"]
            symbol:nil selector:@selector(axs_duodesktop_openCalendarEvent:)];
        row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        row.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        row.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        row.frame = CGRectMake(4, index * rowHeight, MAX(0, width - 8), rowHeight - 2);
        objc_setAssociatedObject(row, &AxsDuoDesktopEventDateKey, event.startDate,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIView *stripe = [[UIView alloc] initWithFrame:CGRectMake(0, 7, 3, rowHeight - 14)];
        stripe.backgroundColor = event.calendar.CGColor
            ? [UIColor colorWithCGColor:event.calendar.CGColor] : UIColor.systemBlueColor;
        stripe.layer.cornerRadius = 1.5;
        [row addSubview:stripe];
    }
}

- (void)axs_duodesktop_openCalendarEvent:(UIButton *)sender {
    id date = objc_getAssociatedObject(sender, &AxsDuoDesktopEventDateKey);
    NSTimeInterval stamp = [date isKindOfClass:[NSDate class]]
        ? [date timeIntervalSinceReferenceDate] : NSDate.date.timeIntervalSinceReferenceDate;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"calshow:%.0f", stamp]];
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (UIViewController *)axs_duodesktop_presenter {
    UIResponder *responder = self.root;
    while (responder && ![responder isKindOfClass:[UIViewController class]]) {
        responder = responder.nextResponder;
    }
    UIViewController *controller = [responder isKindOfClass:[UIViewController class]]
        ? (UIViewController *)responder : self.root.window.rootViewController;
    while (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) {
        controller = controller.presentedViewController;
    }
    return controller;
}

@end

#pragma mark - Shared controller

static AxsDuoDesktopHomeController *axs_duodesktop_controller(void) {
    static AxsDuoDesktopHomeController *controller;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ controller = [AxsDuoDesktopHomeController new]; });
    return controller;
}

static NSMutableSet<NSString *> *axs_duodesktop_suppression(void) {
    static NSMutableSet<NSString *> *reasons;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ reasons = [NSMutableSet set]; });
    return reasons;
}

void axs_duodesktop_refreshHome(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ axs_duodesktop_refreshHome(); });
        return;
    }
    AxsDuoDesktopHomeController *controller = axs_duodesktop_controller();
    if (!controller.root || !controller.root.window) {
        for (UIWindow *window in axs_duodesktop_windows()) {
            UIView *root = axs_duodesktop_findView(window, @"SBRootFolderView", 0);
            if (root.window) {
                [controller axs_duodesktop_observeRoot:root];
                break;
            }
        }
    }
    [controller axs_duodesktop_refresh];
}

void axs_duodesktop_setSuppressed(NSString *reason, BOOL suppressed) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ axs_duodesktop_setSuppressed(reason, suppressed); });
        return;
    }
    if (!reason.length) return;
    NSMutableSet<NSString *> *reasons = axs_duodesktop_suppression();
    if (suppressed) [reasons addObject:reason];
    else [reasons removeObject:reason];
    [axs_duodesktop_controller() axs_duodesktop_applyLayout];
}

BOOL axs_duodesktop_isSuppressed(void) {
    return axs_duodesktop_suppression().count > 0;
}

#pragma mark - Helpers

static UIView *axs_duodesktop_findView(UIView *view, NSString *name, NSUInteger depth) {
    if (!view || depth > 12) return nil;
    Class cls = NSClassFromString(name);
    if (cls && [view isKindOfClass:cls]) return view;
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:[AxsDuoDesktopActionTile class]]) continue;
        UIView *found = axs_duodesktop_findView(child, name, depth + 1);
        if (found) return found;
    }
    return nil;
}

static NSString *axs_duodesktop_string(id value) {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static BOOL axs_duodesktop_calendarAllowed(void) {
    // Authorized and the iOS 17 full-access case share the raw value 3.
    return [EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent] == 3;
}

#pragma mark - MediaRemote

static void (*axs_duodesktop_mediaInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
static void (*axs_duodesktop_mediaPlayingFn)(dispatch_queue_t, void (^)(BOOL));
static BOOL (*axs_duodesktop_mediaCommandFn)(uint32_t, CFDictionaryRef);
static void (*axs_duodesktop_mediaSeekFn)(double);
static BOOL axs_duodesktop_mediaLoaded;

static void axs_duodesktop_loadMedia(void) {
    if (axs_duodesktop_mediaLoaded) return;
    axs_duodesktop_mediaLoaded = YES;
    axs_duodesktop_mediaHandle = axs_duodesktop_framework(
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote");
    if (!axs_duodesktop_mediaHandle) return;
    axs_duodesktop_mediaInfoFn = dlsym(axs_duodesktop_mediaHandle, "MRMediaRemoteGetNowPlayingInfo");
    axs_duodesktop_mediaPlayingFn = dlsym(axs_duodesktop_mediaHandle,
                                          "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    axs_duodesktop_mediaCommandFn = dlsym(axs_duodesktop_mediaHandle, "MRMediaRemoteSendCommand");
    axs_duodesktop_mediaSeekFn = dlsym(axs_duodesktop_mediaHandle, "MRMediaRemoteSetElapsedTime");
    void (*registerNotifications)(dispatch_queue_t) =
        dlsym(axs_duodesktop_mediaHandle, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (registerNotifications) registerNotifications(dispatch_get_main_queue());
}

static void (*axs_duodesktop_mediaInfo(void))(dispatch_queue_t, void (^)(CFDictionaryRef)) {
    axs_duodesktop_loadMedia();
    return axs_duodesktop_mediaInfoFn;
}

static void (*axs_duodesktop_mediaPlaying(void))(dispatch_queue_t, void (^)(BOOL)) {
    axs_duodesktop_loadMedia();
    return axs_duodesktop_mediaPlayingFn;
}

static BOOL (*axs_duodesktop_mediaCommand(void))(uint32_t, CFDictionaryRef) {
    axs_duodesktop_loadMedia();
    return axs_duodesktop_mediaCommandFn;
}

static void (*axs_duodesktop_mediaSeek(void))(double) {
    axs_duodesktop_loadMedia();
    return axs_duodesktop_mediaSeekFn;
}

static NSString *axs_duodesktop_mediaKey(const char *symbol) {
    if (!axs_duodesktop_mediaHandle) return nil;
    CFStringRef *value = dlsym(axs_duodesktop_mediaHandle, symbol);
    return (value && *value) ? (__bridge NSString *)*value : nil;
}

#pragma mark - Hooks

static void (*axs_duodesktop_originalRootLayout)(id, SEL);
static void (*axs_duodesktop_originalRootMove)(id, SEL);
static void (*axs_duodesktop_originalDockLayout)(id, SEL);
static void (*axs_duodesktop_originalSearchPresent)(id, SEL, id, BOOL);
static void (*axs_duodesktop_originalSearchDismiss)(id, SEL, id, BOOL);
static void (*axs_duodesktop_originalSetEditing)(id, SEL, BOOL);
static void (*axs_duodesktop_originalCoverEnd)(id, SEL, id, BOOL);
static void (*axs_duodesktop_originalPageBegin)(id, SEL, id, id, id, id);
static void (*axs_duodesktop_originalPageEnd)(id, SEL, id, id, id);

static void axs_duodesktop_rootLayout(id self, SEL cmd) {
    if (axs_duodesktop_originalRootLayout) axs_duodesktop_originalRootLayout(self, cmd);
    [axs_duodesktop_controller() axs_duodesktop_observeRoot:self];
}

static void axs_duodesktop_rootMove(id self, SEL cmd) {
    if (axs_duodesktop_originalRootMove) axs_duodesktop_originalRootMove(self, cmd);
    [axs_duodesktop_controller() axs_duodesktop_observeRoot:self];
}

static void axs_duodesktop_dockLayout(id self, SEL cmd) {
    if (axs_duodesktop_originalDockLayout) axs_duodesktop_originalDockLayout(self, cmd);
    Class rootClass = NSClassFromString(@"SBRootFolderView");
    UIView *view = self;
    while (view && rootClass && ![view isKindOfClass:rootClass]) view = view.superview;
    if (view) [axs_duodesktop_controller() axs_duodesktop_observeRoot:view];
}

static void axs_duodesktop_searchPresent(id self, SEL cmd, id presenter, BOOL animated) {
    axs_duodesktop_setSuppressed(@"search", YES);
    if (axs_duodesktop_originalSearchPresent) {
        axs_duodesktop_originalSearchPresent(self, cmd, presenter, animated);
    }
}

static void axs_duodesktop_searchDismiss(id self, SEL cmd, id presenter, BOOL animated) {
    if (axs_duodesktop_originalSearchDismiss) {
        axs_duodesktop_originalSearchDismiss(self, cmd, presenter, animated);
    }
    axs_duodesktop_setSuppressed(@"search", NO);
}

static void axs_duodesktop_setEditing(id self, SEL cmd, BOOL editing) {
    if (axs_duodesktop_originalSetEditing) axs_duodesktop_originalSetEditing(self, cmd, editing);
    axs_duodesktop_setSuppressed(@"editing", editing);
}

static void axs_duodesktop_coverEnd(id self, SEL cmd, id controller, BOOL presented) {
    if (axs_duodesktop_originalCoverEnd) {
        axs_duodesktop_originalCoverEnd(self, cmd, controller, presented);
    }
    axs_duodesktop_setSuppressed(@"coverSheet", presented);
    if (!presented) axs_duodesktop_refreshHome();
}

static void axs_duodesktop_pageBegin(id self, SEL cmd, id root, id manager, id animator, id context) {
    axs_duodesktop_setSuppressed(@"pageManagement", YES);
    if (axs_duodesktop_originalPageBegin) {
        axs_duodesktop_originalPageBegin(self, cmd, root, manager, animator, context);
    }
}

static void axs_duodesktop_pageEnd(id self, SEL cmd, id root, id manager, id context) {
    if (axs_duodesktop_originalPageEnd) {
        axs_duodesktop_originalPageEnd(self, cmd, root, manager, context);
    }
    axs_duodesktop_setSuppressed(@"pageManagement", NO);
}

static Class axs_duodesktop_classRespondingTo(NSArray<NSString *> *names, NSString *selector) {
    for (NSString *name in names) {
        Class cls = axs_duodesktop_class(name);
        if (cls && [cls instancesRespondToSelector:NSSelectorFromString(selector)]) return cls;
    }
    return Nil;
}

void axs_duodesktop_installHomeHooks(void) {
    if (!axs_duodesktop_isSpringBoard()) return;
    static BOOL started;
    if (!started) {
        started = YES;
        axs_duodesktop_observeReload(^{ axs_duodesktop_refreshHome(); });
    }
    Class root = axs_duodesktop_class(@"SBRootFolderView");
    axs_duodesktop_installHook(@"home.root.layout", root, @selector(layoutSubviews), "v@:",
                               (IMP)axs_duodesktop_rootLayout, (IMP *)&axs_duodesktop_originalRootLayout);
    axs_duodesktop_installHook(@"home.root.move", root, NSSelectorFromString(@"didMoveToWindow"), "v@:",
                               (IMP)axs_duodesktop_rootMove, (IMP *)&axs_duodesktop_originalRootMove);
    axs_duodesktop_installHook(@"home.dock.layout", axs_duodesktop_class(@"SBDockView"),
                               @selector(layoutSubviews), "v@:",
                               (IMP)axs_duodesktop_dockLayout, (IMP *)&axs_duodesktop_originalDockLayout);
    Class search = axs_duodesktop_classRespondingTo(
        @[@"SBIconController", @"SBHomeScreenController", @"SBHIconManager"],
        @"searchPresenterWillPresentSearch:animated:");
    axs_duodesktop_installHook(@"home.search.present", search,
        NSSelectorFromString(@"searchPresenterWillPresentSearch:animated:"), "v@:@B",
        (IMP)axs_duodesktop_searchPresent, (IMP *)&axs_duodesktop_originalSearchPresent);
    axs_duodesktop_installHook(@"home.search.dismiss", search,
        NSSelectorFromString(@"searchPresenterWillDismissSearch:animated:"), "v@:@B",
        (IMP)axs_duodesktop_searchDismiss, (IMP *)&axs_duodesktop_originalSearchDismiss);
    axs_duodesktop_installHook(@"home.editing", axs_duodesktop_class(@"SBHIconManager"),
        NSSelectorFromString(@"setEditing:"), "v@:B",
        (IMP)axs_duodesktop_setEditing, (IMP *)&axs_duodesktop_originalSetEditing);
    axs_duodesktop_installHook(@"home.cover.end", axs_duodesktop_class(@"SBCoverSheetPresentationManager"),
        NSSelectorFromString(@"coverSheetSlidingViewControllerDidEndTransition:toPresented:"), "v@:@B",
        (IMP)axs_duodesktop_coverEnd, (IMP *)&axs_duodesktop_originalCoverEnd);
    Class folder = axs_duodesktop_class(@"SBRootFolderController");
    axs_duodesktop_installHook(@"home.page.begin", folder,
        NSSelectorFromString(@"rootFolderView:willPresentPageManagementWithLayoutManager:animator:context:"),
        "v@:@@@@", (IMP)axs_duodesktop_pageBegin, (IMP *)&axs_duodesktop_originalPageBegin);
    axs_duodesktop_installHook(@"home.page.end", folder,
        NSSelectorFromString(@"rootFolderView:didDismissPageManagementWithLayoutManager:context:"),
        "v@:@@@", (IMP)axs_duodesktop_pageEnd, (IMP *)&axs_duodesktop_originalPageEnd);
    axs_duodesktop_refreshHome();
}
