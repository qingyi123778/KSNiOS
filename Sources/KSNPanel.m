#import "KSNPanel.h"
#import "KSNStore.h"
#import "KSNBridge.h"
#import "KSNLifecycle.h"
#import "KSNWebInjector.h"
#import "KSNBackgroundSigner.h"
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

static UIWindow *gKSNWindow;
static UIButton *gKSNBall;

/* 透明窗口默认会吃掉全屏触摸，学习通整个界面就点不动了。
   只放行真正命中的子视图，其余一律穿透。 */
@interface KSNPassthroughWindow : UIWindow
@end

@implementation KSNPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
@end

static UIWindowScene *KSNForegroundScene(void) {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene *)s;
        }
    }
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class]) return (UIWindowScene *)s;
    }
    return nil;
}

#pragma mark - 面板

@interface KSNPanelVC : UIViewController
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSTimer *ticker;
@end

@implementation KSNPanelVC

- (UIView *)rowTitle:(NSString *)title
            subtitle:(NSString *)subtitle
                isOn:(BOOL)isOn
              toggle:(void (^)(BOOL))toggle
{
    UIView *box = [UIView new];
    box.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *t = [UILabel new];
    t.text = title;
    t.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    t.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *s = [UILabel new];
    s.text = subtitle;
    s.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    s.textColor = UIColor.secondaryLabelColor;
    s.numberOfLines = 0;
    s.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[t, s]];
    texts.axis = UILayoutConstraintAxisVertical;
    texts.spacing = 2;
    texts.translatesAutoresizingMaskIntoConstraints = NO;

    UISwitch *sw = [UISwitch new];
    sw.on = isOn;
    sw.translatesAutoresizingMaskIntoConstraints = NO;
    [sw addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        UISwitch *ctrl = (UISwitch *)a.sender;
        if (toggle) toggle(ctrl.isOn);
    }] forControlEvents:UIControlEventValueChanged];

    [box addSubview:texts];
    [box addSubview:sw];

    [NSLayoutConstraint activateConstraints:@[
        [texts.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
        [texts.topAnchor constraintEqualToAnchor:box.topAnchor constant:2],
        [texts.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-2],
        [texts.trailingAnchor constraintEqualToAnchor:sw.leadingAnchor constant:-12],

        [sw.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
        [sw.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
        [sw.topAnchor constraintGreaterThanOrEqualToAnchor:box.topAnchor],
        [box.heightAnchor constraintGreaterThanOrEqualToConstant:56],
    ]];
    return box;
}

- (UILabel *)sectionTitle:(NSString *)text {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    l.textColor = UIColor.secondaryLabelColor;
    return l;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"KSN 签到";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(close)];

    KSNStore *st = KSNStore.shared;

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    self.statusLabel = [UILabel new];
    self.statusLabel.text = @"待机";
    self.statusLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.numberOfLines = 0;

    [stack addArrangedSubview:[self sectionTitle:@"状态"]];
    [stack addArrangedSubview:self.statusLabel];

    [stack addArrangedSubview:[self sectionTitle:@"签到"]];
    [stack addArrangedSubview:[self rowTitle:@"自动签到"
                                   subtitle:@"每 30 秒拉离屏 webview 扫一次，锁屏后停"
                                       isOn:st.autoSign
                                     toggle:^(BOOL on) {
        KSNStore.shared.autoSign = on;
        KSNSetBackgroundSignEnabled(on);
    }]];

    [stack addArrangedSubview:[self sectionTitle:@"定位"]];
    [stack addArrangedSubview:[self rowTitle:@"锁定坐标"
                                   subtitle:@"覆盖 navigator.geolocation"
                                       isOn:st.mockLocation
                                     toggle:^(BOOL on) { KSNStore.shared.mockLocation = on; }]];

    UITextField *field = [UITextField new];
    field.text = st.locationRaw;
    field.placeholder = @"39.92,116.39,北京市海淀区";
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field.heightAnchor constraintEqualToConstant:38].active = YES;
    [field addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        KSNStore.shared.locationRaw = ((UITextField *)a.sender).text ?: @"";
    }] forControlEvents:UIControlEventEditingDidEnd];
    [stack addArrangedSubview:field];

    [stack addArrangedSubview:[self sectionTitle:@"手势与人脸"]];
    [stack addArrangedSubview:[self rowTitle:@"手势签到"
                                   subtitle:@"在签到页手画一遍并记住，之后自动重放"
                                       isOn:st.gestureSign
                                     toggle:^(BOOL on) { KSNStore.shared.gestureSign = on; }]];
    [stack addArrangedSubview:[self rowTitle:@"人脸签到"
                                   subtitle:@"上传已存照片换 faceCode，活体检测过不了"
                                       isOn:st.faceSign
                                     toggle:^(BOOL on) { KSNStore.shared.faceSign = on; }]];

    [stack addArrangedSubview:[self sectionTitle:@"其他"]];
    [stack addArrangedSubview:[self rowTitle:@"屏幕常亮"
                                   subtitle:@"iOS 唯一可靠的保活手段，需插电"
                                       isOn:st.idleKeepAwake
                                     toggle:^(BOOL on) {
        KSNStore.shared.idleKeepAwake = on;
        KSNApplyKeepAlive();
    }]];

    UIButton *go = [UIButton buttonWithType:UIButtonTypeSystem];
    [go setTitle:@"立即签到" forState:UIControlStateNormal];
    go.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    go.backgroundColor = UIColor.systemBlueColor;
    [go setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    go.layer.cornerRadius = 10;
    go.translatesAutoresizingMaskIntoConstraints = NO;
    [go.heightAnchor constraintEqualToConstant:46].active = YES;
    [go addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        KSNStore.shared.signNow = YES;
        [KSNBridge.shared setStatus:[NSString stringWithFormat:@"%@ 已下发签到指令",
                                     [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                                   dateStyle:NSDateFormatterNoStyle
                                                                   timeStyle:NSDateFormatterMediumStyle]]];
    }] forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:go];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [self.view addSubview:scroll];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:g.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],

        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-30],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-20],
    ]];

    __weak typeof(self) weakSelf = self;
    self.ticker = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  repeats:YES
                                                    block:^(NSTimer *t) {
        KSNPanelVC *strongSelf = weakSelf;
        if (!strongSelf) { [t invalidate]; return; }
        NSString *s = KSNBridge.shared.lastStatus;
        if (![strongSelf.statusLabel.text isEqualToString:s]) strongSelf.statusLabel.text = s;
    }];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.ticker invalidate];
    self.ticker = nil;
}

- (void)close {
    [self.ticker invalidate];
    self.ticker = nil;
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - 悬浮球

@interface KSNPanel : NSObject
+ (instancetype)shared;
- (void)install;
@end

@implementation KSNPanel

+ (instancetype)shared {
    static KSNPanel *o;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ o = [KSNPanel new]; });
    return o;
}

- (void)install {
    if (gKSNWindow) return;

    UIWindowScene *scene = KSNForegroundScene();
    if (scene) {
        gKSNWindow = [[KSNPassthroughWindow alloc] initWithWindowScene:scene];
    } else {
        gKSNWindow = [[KSNPassthroughWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    }
    gKSNWindow.frame = UIScreen.mainScreen.bounds;
    gKSNWindow.windowLevel = UIWindowLevelAlert + 100;
    gKSNWindow.backgroundColor = UIColor.clearColor;
    gKSNWindow.rootViewController = [UIViewController new];
    gKSNWindow.hidden = NO;

    UIViewController *root = gKSNWindow.rootViewController;
    CGFloat size = 54;
    CGRect screen = UIScreen.mainScreen.bounds;
    CGRect frame = CGRectMake(CGRectGetWidth(screen) - size - 12,
                              CGRectGetHeight(screen) * 0.35, size, size);

    gKSNBall = [UIButton buttonWithType:UIButtonTypeCustom];
    gKSNBall.frame = frame;
    gKSNBall.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.55];
    gKSNBall.layer.cornerRadius = size / 2;
    gKSNBall.layer.borderWidth = 0.5;
    gKSNBall.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
    UIImage *icon = [UIImage systemImageNamed:@"checkmark.circle.fill"];
    [gKSNBall setImage:icon forState:UIControlStateNormal];
    gKSNBall.tintColor = UIColor.whiteColor;
    gKSNBall.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [gKSNBall addGestureRecognizer:pan];
    [gKSNBall addTarget:self action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];

    [root.view addSubview:gKSNBall];
    NSLog(@"[KSN] 面板已挂载");
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    CGPoint t = [g translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [g setTranslation:CGPointZero inView:v.superview];

    if (g.state == UIGestureRecognizerStateEnded) {
        CGRect bounds = v.superview.bounds;
        CGPoint c = v.center;
        CGFloat half = CGRectGetWidth(v.bounds) / 2;
        c.x = MAX(half + 6, MIN(CGRectGetWidth(bounds) - half - 6, c.x));
        c.y = MAX(half + 6, MIN(CGRectGetHeight(bounds) - half - 6, c.y));
        [UIView animateWithDuration:0.2 animations:^{ v.center = c; }];
    }
}

- (void)onTap {
    UIViewController *root = gKSNWindow.rootViewController;
    if (!root || root.presentedViewController) return;
    KSNPanelVC *vc = [KSNPanelVC new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [root presentViewController:nav animated:YES completion:nil];
}

@end

void KSNInstallPanel(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [KSNPanel.shared install];
    });
}
