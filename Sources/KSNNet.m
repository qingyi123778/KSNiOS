#import "KSNNet.h"
#import <WebKit/WebKit.h>
#import <UIKit/UIKit.h>

static NSString *KSNUserAgent(void) {
    static NSString *ua;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        /* 拼一个 iOS 学习通风格 UA。服务端按 UA 分流的情况很常见。 */
        ua = @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_2 like Mac OS X) "
             @"AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 "
             @"ChaoXingStudy/7.0.2";
    });
    return ua;
}

static BOOL KSNCookieBelongs(NSHTTPCookie *c) {
    NSString *d = c.domain.lowercaseString ?: @"";
    return [d containsString:@"chaoxing.com"] || [d containsString:@"ssreader"];
}

void KSNNetRequest(NSDictionary *spec, void (^done)(NSDictionary *)) {
    NSString *urlStr = [spec[@"url"] isKindOfClass:NSString.class] ? spec[@"url"] : nil;
    if (!urlStr.length) {
        done(@{@"ok": @NO, @"status": @0, @"body": @"", @"err": @"no url", @"ncookie": @0});
        return;
    }

    NSString *method = [spec[@"method"] isKindOfClass:NSString.class] ? spec[@"method"] : @"GET";
    NSString *bodyStr = [spec[@"body"] isKindOfClass:NSString.class] ? spec[@"body"] : @"";
    NSDictionary *extra = [spec[@"headers"] isKindOfClass:NSDictionary.class] ? spec[@"headers"] : @{};

    WKHTTPCookieStore *store = [WKWebsiteDataStore defaultDataStore].httpCookieStore;
    [store getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        NSMutableURLRequest *req =
            [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
        req.HTTPMethod = method.uppercaseString;
        req.timeoutInterval = 20;
        req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;

        NSMutableArray<NSString *> *pairs = [NSMutableArray array];
        for (NSHTTPCookie *c in cookies) {
            if (KSNCookieBelongs(c)) {
                [pairs addObject:[NSString stringWithFormat:@"%@=%@", c.name, c.value]];
            }
        }
        if (pairs.count) {
            [req setValue:[pairs componentsJoinedByString:@"; "] forHTTPHeaderField:@"Cookie"];
        }

        [req setValue:KSNUserAgent() forHTTPHeaderField:@"User-Agent"];
        [req setValue:@"https://mobilelearn.chaoxing.com/" forHTTPHeaderField:@"Referer"];
        [req setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
        [req setValue:@"zh-CN,zh;q=0.9" forHTTPHeaderField:@"Accept-Language"];
        [req setValue:@"*/*" forHTTPHeaderField:@"Accept"];

        for (NSString *k in extra) {
            if ([extra[k] isKindOfClass:NSString.class]) {
                [req setValue:extra[k] forHTTPHeaderField:k];
            }
        }

        if (bodyStr.length && ![method.uppercaseString isEqualToString:@"GET"]) {
            req.HTTPBody = [bodyStr dataUsingEncoding:NSUTF8StringEncoding];
            if (!extra[@"Content-Type"]) {
                [req setValue:@"application/x-www-form-urlencoded"
                    forHTTPHeaderField:@"Content-Type"];
            }
        }

        NSURLSessionDataTask *task =
            [NSURLSession.sharedSession dataTaskWithRequest:req
                                        completionHandler:^(NSData *data,
                                                            NSURLResponse *resp,
                                                            NSError *err) {
            NSInteger code = [resp isKindOfClass:NSHTTPURLResponse.class]
                             ? ((NSHTTPURLResponse *)resp).statusCode : 0;
            NSString *text = data ? ([[NSString alloc] initWithData:data
                                                           encoding:NSUTF8StringEncoding] ?: @"") : @"";
            NSDictionary *out = @{
                @"ok":      @(code >= 200 && code < 300),
                @"status":  @(code),
                @"body":    text.length > 4000 ? [text substringToIndex:4000] : text,
                @"err":     err.localizedDescription ?: @"",
                @"ncookie": @(pairs.count),
                @"url":     urlStr,
            };
            dispatch_async(dispatch_get_main_queue(), ^{ done(out); });
        }];
        [task resume];
    }];
}
