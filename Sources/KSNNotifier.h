#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* 本地通知。用的是学习通自己的通知权限位，
   首次发通知会弹授权框，拒绝之后就只能靠面板里的状态行看结果。 */
@interface KSNNotifier : NSObject
+ (void)requestAuthorization;
+ (void)postTitle:(nullable NSString *)title body:(nullable NSString *)body;
@end

NS_ASSUME_NONNULL_END
