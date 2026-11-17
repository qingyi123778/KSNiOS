#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/* 把桥和用户脚本塞进 WKWebViewConfiguration。
   必须在 initWithFrame:configuration: 之前调用 —— 配置定稿后再加就是无效操作。 */
void KSNPrepareConfiguration(WKWebViewConfiguration *cfg);

/* 已经建好的 webview 走这条，evaluateJavaScript 补一次，页面导航后失效。 */
void KSNInjectIntoWebView(WKWebView *wv);

/* 内嵌的 ksn.js 源码，由 scripts/embed_js.py 生成。 */
NSString *KSNJavaScriptSource(void);

NS_ASSUME_NONNULL_END
