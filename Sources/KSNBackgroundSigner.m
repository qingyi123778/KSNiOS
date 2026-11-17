#import "KSNBackgroundSigner.h"
#import "KSNWebInjector.h"
#import "KSNStore.h"
#import "KSNBridge.h"
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

static UIWindow *KSNHostWindow(void) {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) {
            if (w.isKeyWindow) return w;
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

@interface KSNBackgroundSigner : NSObject <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *web;
@property (nonatomic, strong) NSTimer *watchdog;
@property (nonatomic, strong) NSTimer *loop;
@property (nonatomic, assign) BOOL busy;
@end

@implementation KSNBackgroundSigner

+ (instancetype)shared {
    static KSNBackgroundSigner *o;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ o = [KSNBackgroundSigner new]; });
    return o;
}

- (void)start {
    if (self.busy) return;
    KSNStore *st = KSNStore.shared;
    if (!st.autoSign && !st.signNow) return;

    UIWindow *host = KSNHostWindow();
    if (!host) { KSNBridge.shared.lastStatus = @"后台签到：没有可用窗口"; return; }

    self.busy = YES;
    KSNBridge.shared.lastStatus = @"后台签到：加载 mobilelearn…";

    WKWebViewConfiguration *cfg = [WKWebViewConfiguration new];
    /* 关键：和主 webview 共用同一个 dataStore，登录 cookie 直接复用，不需要重新登录 */
    cfg.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    KSNPrepareConfiguration(cfg);

    WKWebView *wv = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 1, 1) configuration:cfg];
    wv.navigationDelegate = self;
    wv.alpha = 0.01;
    wv.userInteractionEnabled = NO;
    [host addSubview:wv];
    self.web = wv;

    [wv loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://mobilelearn.chaoxing.com/"]]];

    __weak typeof(self) weakSelf = self;
    self.watchdog = [NSTimer scheduledTimerWithTimeInterval:45 repeats:NO block:^(NSTimer *t) {
        [weakSelf finish:@"45 秒无结果，放弃本轮"];
    }];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    /* ksn.js 已经在 AtDocumentStart 注入，但它自己的 tick 要等 15 秒，这里直接催一次 */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [webView evaluateJavaScript:@"(window.__ksnSignNow && window.__ksnSignNow(), 'ok')"
                 completionHandler:^(id result, NSError *err) {
            if (err) NSLog(@"[KSN] 后台签到触发失败: %@", err.localizedDescription);
        }];
    });
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self finish:[NSString stringWithFormat:@"加载失败 %@", error.localizedDescription]];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self finish:[NSString stringWithFormat:@"连接失败 %@", error.localizedDescription]];
}

- (void)finish:(NSString *)reason {
    [self.watchdog invalidate];
    self.watchdog = nil;
    [self.web stopLoading];
    [self.web removeFromSuperview];
    self.web = nil;
    self.busy = NO;
    if (reason.length) KSNBridge.shared.lastStatus = [@"后台签到：" stringByAppendingString:reason];
    NSLog(@"[KSN] 后台签到结束 — %@", reason);
}

- (void)setEnabled:(BOOL)on {
    [self.loop invalidate];
    self.loop = nil;
    if (!on) return;

    __weak typeof(self) weakSelf = self;
    /* 30 秒一轮。注意这个定时器只在 App 活着的时候跑，锁屏挂起后一样停。 */
    self.loop = [NSTimer scheduledTimerWithTimeInterval:30 repeats:YES block:^(NSTimer *t) {
        [weakSelf start];
    }];
    [self start];
}

@end

void KSNStartBackgroundSign(void) {
    [KSNBackgroundSigner.shared start];
}

void KSNSetBackgroundSignEnabled(BOOL enabled) {
    [KSNBackgroundSigner.shared setEnabled:enabled];
}
