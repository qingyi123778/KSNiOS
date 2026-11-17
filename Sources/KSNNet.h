#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* 原生 HTTP 通道。
   存在的理由：WKWebView 里的 fetch 会自带一些不可控的东西（存储策略、CSP、UA 拼接），
   而且拿不到全部 cookie。签到接口在 WebView 里一律 500，需要直连才能确认是服务端问题还是通道问题。

   cookie 直接从 WKWebsiteDataStore.defaultDataStore.httpCookieStore 取，
   和主 webview 共用同一份登录态，不需要手动搬运。

   spec:  { url, method, body, headers }
   result:{ ok, status, body, err, ncookie } */
void KSNNetRequest(NSDictionary *spec, void (^done)(NSDictionary *result));

NS_ASSUME_NONNULL_END
