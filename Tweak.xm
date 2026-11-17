#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <unistd.h>

#import "KSNWebInjector.h"
#import "KSNPanel.h"
#import "KSNLifecycle.h"
#import "KSNStore.h"
#import "KSNBackgroundSigner.h"

/* 唯一的 hook 点。
   WKWebView 的 configuration 在 initWithFrame:configuration: 之后就定稿，
   过了这个点再加 userScript / messageHandler 都是无效操作，所以必须在 %orig 之前动手。 */
%hook WKWebView

- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    KSNPrepareConfiguration(configuration);
    return %orig;
}

%end

%ctor {
    @autoreleasepool {
        NSLog(@"[KSN] tweak 已加载 pid=%d", getpid());
        KSNInstallLifecycle();
        KSNInstallPanel();
        /* 首页是原生页面时没有 webview，靠离屏签到器兜底 */
        KSNSetBackgroundSignEnabled(KSNStore.shared.autoSign);
    }
}
