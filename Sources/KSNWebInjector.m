#import "KSNWebInjector.h"
#import "KSNBridge.h"
#import <objc/runtime.h>

#if __has_include("KSNJSData.h")
#  import "KSNJSData.h"
#else
static const char kKSNJSSource[] = "console.log('[KSN] ksn.js not embedded, run scripts/embed_js.py');";
#endif

static void *kKSNCfgPrepared = &kKSNCfgPrepared;

NSString *KSNJavaScriptSource(void) {
    static NSString *src;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        src = [NSString stringWithUTF8String:kKSNJSSource] ?: @"";
    });
    return src;
}

void KSNPrepareConfiguration(WKWebViewConfiguration *cfg) {
    if (!cfg) return;
    if (objc_getAssociatedObject(cfg, kKSNCfgPrepared)) return;
    objc_setAssociatedObject(cfg, kKSNCfgPrepared, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    WKUserContentController *ucc = cfg.userContentController;
    if (!ucc) {
        ucc = [WKUserContentController new];
        cfg.userContentController = ucc;
    }

    [KSNBridge.shared attachTo:ucc];

    NSString *js = KSNJavaScriptSource();
    if (js.length) {
        WKUserScript *script = [[WKUserScript alloc] initWithSource:js
                                                      injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                   forMainFrameOnly:NO];
        [ucc addUserScript:script];
    }
}

void KSNInjectIntoWebView(WKWebView *wv) {
    if (!wv) return;
    NSString *js = KSNJavaScriptSource();
    if (!js.length) return;
    [wv evaluateJavaScript:js completionHandler:^(id result, NSError *err) {
        if (err) NSLog(@"[KSN] 补注入失败: %@", err.localizedDescription);
    }];
}
