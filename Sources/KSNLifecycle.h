#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* 生命周期钩子。装一次，全局生效。
   注意：这里做的是「延长」不是「保活」—— iOS 没有前台服务，App 被挂起就是挂起。 */
void KSNInstallLifecycle(void);

/* 配置变更后调用，同步 idleTimerDisabled。 */
void KSNApplyKeepAlive(void);

NS_ASSUME_NONNULL_END
