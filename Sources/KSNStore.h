#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* 配置持久化。宿主是学习通进程，所以用 standardUserDefaults，
   数据落在学习通自己的容器里，卸载 App 会一并清掉。
   键统一加 ksn_ 前缀，避免污染宿主已有的键。 */
@interface KSNStore : NSObject

+ (instancetype)shared;

@property (nonatomic, assign) BOOL autoSign;          // 定时扫描可签到活动并补签
@property (nonatomic, assign) BOOL mockLocation;      // 覆盖 navigator.geolocation
@property (nonatomic, copy)   NSString *locationRaw;  // "lat,lng,地址"
@property (nonatomic, assign) BOOL gestureSign;       // 手势学习 / 重放
@property (nonatomic, assign) BOOL faceSign;          // 人脸签到（上传已存照片，可靠性低）
@property (nonatomic, assign) BOOL idleKeepAwake;     // 屏幕常亮，替代后台保活
@property (nonatomic, assign) BOOL signNow;           // 一次性触发，跑完自清
@property (nonatomic, copy)   NSString *cachedSignCode;
@property (nonatomic, copy)   NSString *cachedGesture; // 手势点集 JSON

- (NSDictionary *)snapshot;                 // 给 JS 的完整配置
- (void)applyFromBridge:(NSDictionary *)d;  // 从 JS 回写
- (nullable NSString *)faceBase64;          // 人脸图（大对象单独落盘）
- (void)setFaceBase64:(nullable NSString *)b64;

/* 页面里嗅探到的请求，一行一条 JSON 追加到 Library/KSN/spy.log。
   超过 512KB 自动清空，避免长期开着把沙盒撑爆。 */
- (void)appendSpy:(NSDictionary *)d;
- (NSString *)spyPath;

- (void)flush;

@end

NS_ASSUME_NONNULL_END
