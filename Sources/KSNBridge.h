#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/* JS ↔ 原生 桥。
   用 WKScriptMessageHandlerWithReply，JS 侧 postMessage() 直接返回 Promise ——
   和 Android 版 addWebMessageListener 的调用形态一致，H5 那一层写法不用改。
   桥名固定 ksnmsg。 */
@interface KSNBridge : NSObject <WKScriptMessageHandlerWithReply>

+ (instancetype)shared;
- (void)attachTo:(WKUserContentController *)ucc;

/* 最近一次 JS 上报的状态行，面板直接读，不落盘。 */
@property (nonatomic, copy, readonly) NSString *lastStatus;

/* 外部写状态走这个方法 —— 属性本身对头文件是只读的。 */
- (void)setStatus:(nullable NSString *)text;

@end

NS_ASSUME_NONNULL_END
