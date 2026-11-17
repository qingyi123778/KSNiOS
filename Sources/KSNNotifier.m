#import "KSNNotifier.h"
#import <UserNotifications/UserNotifications.h>

@interface KSNNotifier () <UNUserNotificationCenterDelegate>
@end

@implementation KSNNotifier

+ (void)requestAuthorization {
    UNUserNotificationCenter *c = [UNUserNotificationCenter currentNotificationCenter];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        static KSNNotifier *delegate;
        delegate = [KSNNotifier new];
        c.delegate = delegate;
    });
    [c requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                    completionHandler:^(BOOL granted, NSError *err) {
        NSLog(@"[KSN] 通知授权: %d %@", granted, err);
    }];
}

+ (void)postTitle:(NSString *)title body:(NSString *)body {
    if (!title.length && !body.length) return;
    UNMutableNotificationContent *c = [UNMutableNotificationContent new];
    c.title = title.length ? title : @"KSN";
    c.body = body ?: @"";
    c.sound = [UNNotificationSound defaultSound];
    UNNotificationRequest *req = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString]
                                                                     content:c
                                                                     trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter]
        addNotificationRequest:req
         withCompletionHandler:^(NSError *err) {
        if (err) NSLog(@"[KSN] 通知失败: %@", err);
    }];
}

#pragma mark - 前台也弹横幅

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler
{
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound);
}

@end
