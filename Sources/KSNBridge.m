#import "KSNBridge.h"
#import "KSNStore.h"
#import "KSNNotifier.h"
#import "KSNNet.h"
#import <objc/runtime.h>

static NSString *const kKSNBridgeName = @"ksnmsg";
static void *kKSNBridgeAttached = &kKSNBridgeAttached;

@interface KSNBridge ()
@property (nonatomic, copy, readwrite) NSString *lastStatus;
@end

@implementation KSNBridge

+ (instancetype)shared {
    static KSNBridge *o;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        o = [KSNBridge new];
        o.lastStatus = @"待机";
    });
    return o;
}

- (void)attachTo:(WKUserContentController *)ucc {
    if (!ucc) return;
    if (objc_getAssociatedObject(ucc, kKSNBridgeAttached)) return;
    objc_setAssociatedObject(ucc, kKSNBridgeAttached, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        [ucc addScriptMessageHandlerWithReply:self
                                 contentWorld:WKContentWorld.pageWorld
                                         name:kKSNBridgeName];
    } @catch (NSException *e) {
        NSLog(@"[KSN] 桥注册失败: %@", e);
    }
}

- (void)setStatus:(NSString *)text {
    self.lastStatus = text ?: @"";
}

#pragma mark - WKScriptMessageHandlerWithReply

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message
                 replyHandler:(void (^)(id _Nullable, NSString *_Nullable))replyHandler
{
    NSDictionary *body = [message.body isKindOfClass:NSDictionary.class] ? message.body : @{};
    NSString *cmd = [body[@"cmd"] isKindOfClass:NSString.class] ? body[@"cmd"] : @"";

    /* 网络请求走异步：replyHandler 由 NSURLSession 回调里触发，
       这里直接接管整条回复路径，不能先 return 再调。 */
    if ([cmd isEqualToString:@"net"]) {
        NSDictionary *a = [body[@"args"] isKindOfClass:NSDictionary.class] ? body[@"args"] : @{};
        KSNNetRequest(a, ^(NSDictionary *r) { replyHandler(r, nil); });
        return;
    }

    id out = nil;
    @try {
        out = [self dispatch:message];
    } @catch (NSException *e) {
        NSLog(@"[KSN] 分发异常: %@", e);
    }
    replyHandler(out, nil);
}

- (id)dispatch:(WKScriptMessage *)message {
    NSDictionary *body = [message.body isKindOfClass:NSDictionary.class] ? message.body : @{};
    NSString *cmd = [body[@"cmd"] isKindOfClass:NSString.class] ? body[@"cmd"] : @"";
    NSDictionary *a = [body[@"args"] isKindOfClass:NSDictionary.class] ? body[@"args"] : @{};
    KSNStore *s = KSNStore.shared;

    if ([cmd isEqualToString:@"cfg"]) {
        return [s snapshot];
    }
    if ([cmd isEqualToString:@"savecfg"]) {
        [s applyFromBridge:a];
        return [s snapshot];
    }
    if ([cmd isEqualToString:@"notify"]) {
        [KSNNotifier postTitle:a[@"title"] body:a[@"body"]];
        return @YES;
    }
    if ([cmd isEqualToString:@"face"]) {
        return [s faceBase64] ?: @"";
    }
    if ([cmd isEqualToString:@"getgesture"]) {
        return [s cachedGesture] ?: @"";
    }
    if ([cmd isEqualToString:@"savegesture"]) {
        s.cachedGesture = [a[@"g"] isKindOfClass:NSString.class] ? a[@"g"] : @"";
        return @YES;
    }
    if ([cmd isEqualToString:@"signcode"]) {
        NSString *c = [a[@"c"] isKindOfClass:NSString.class] ? a[@"c"] : nil;
        if (c.length) { s.cachedSignCode = c; return c; }
        return s.cachedSignCode ?: @"";
    }
    if ([cmd isEqualToString:@"state"]) {
        NSString *m = [a[@"m"] isKindOfClass:NSString.class] ? a[@"m"] : @"";
        if (m.length) self.lastStatus = m;
        return @YES;
    }
    if ([cmd isEqualToString:@"log"]) {
        NSLog(@"[KSN/js] %@", a[@"m"]);
        return @YES;
    }
    return nil;
}

@end
