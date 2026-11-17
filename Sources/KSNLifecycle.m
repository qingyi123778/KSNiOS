#import "KSNLifecycle.h"
#import "KSNStore.h"
#import "KSNNotifier.h"
#import <UIKit/UIKit.h>

static UIBackgroundTaskIdentifier kKSNBGTask = UIBackgroundTaskInvalid;

static void KSNBeginBGTask(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (!app) return;
    if (kKSNBGTask != UIBackgroundTaskInvalid) return;

    kKSNBGTask = [app beginBackgroundTaskWithName:@"KSN.sign" expirationHandler:^{
        NSLog(@"[KSN] 后台额度耗尽，进程即将挂起");
        if (kKSNBGTask != UIBackgroundTaskInvalid) {
            [app endBackgroundTask:kKSNBGTask];
            kKSNBGTask = UIBackgroundTaskInvalid;
        }
    }];
    NSLog(@"[KSN] 后台任务开启 id=%lu", (unsigned long)kKSNBGTask);
}

static void KSNEndBGTask(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (kKSNBGTask != UIBackgroundTaskInvalid && app) {
        [app endBackgroundTask:kKSNBGTask];
        kKSNBGTask = UIBackgroundTaskInvalid;
    }
}

void KSNApplyKeepAlive(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (!app) return;
    BOOL want = KSNStore.shared.idleKeepAwake;
    if (app.idleTimerDisabled != want) {
        app.idleTimerDisabled = want;
        NSLog(@"[KSN] 屏幕常亮 %@", want ? @"开" : @"关");
    }
}

void KSNInstallLifecycle(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

        [nc addObserverForName:UIApplicationDidEnterBackgroundNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            KSNBeginBGTask();
        }];

        [nc addObserverForName:UIApplicationWillEnterForegroundNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            KSNEndBGTask();
            KSNApplyKeepAlive();
        }];

        [nc addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            KSNApplyKeepAlive();
        }];

        [KSNNotifier requestAuthorization];
        KSNApplyKeepAlive();
    });
}
