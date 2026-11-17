#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* 离屏签到器。
   学习通首页是原生 TabBar，没有 WKWebView 时 ksn.js 根本没有执行环境，
   自动签到就成了摆设。这里自己拉一个离屏 webview 加载 mobilelearn 域，
   cookie 与主 webview 共享同一个 WKWebsiteDataStore，登录态直接复用。

   代价：多一个 webview 实例。跑完就丢，不留常驻。 */
void KSNStartBackgroundSign(void);

/* 定时器开关，跟 autoSign 配置联动。 */
void KSNSetBackgroundSignEnabled(BOOL enabled);

NS_ASSUME_NONNULL_END
