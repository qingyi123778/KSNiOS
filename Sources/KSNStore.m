#import "KSNStore.h"

static NSString *KSNKey(NSString *s) { return [@"ksn_" stringByAppendingString:s]; }

@implementation KSNStore {
    NSUserDefaults *_d;
}

+ (instancetype)shared {
    static KSNStore *o;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ o = [KSNStore new]; });
    return o;
}

- (instancetype)init {
    if ((self = [super init])) {
        _d = [NSUserDefaults standardUserDefaults];
    }
    return self;
}

- (void)flush { [_d synchronize]; }

#pragma mark - 标量配置

- (BOOL)autoSign { return [_d boolForKey:KSNKey(@"autoSign")]; }
- (void)setAutoSign:(BOOL)v { [_d setBool:v forKey:KSNKey(@"autoSign")]; [self flush]; }

- (BOOL)mockLocation { return [_d boolForKey:KSNKey(@"mockLocation")]; }
- (void)setMockLocation:(BOOL)v { [_d setBool:v forKey:KSNKey(@"mockLocation")]; [self flush]; }

- (BOOL)gestureSign { return [_d boolForKey:KSNKey(@"gestureSign")]; }
- (void)setGestureSign:(BOOL)v { [_d setBool:v forKey:KSNKey(@"gestureSign")]; [self flush]; }

- (BOOL)faceSign { return [_d boolForKey:KSNKey(@"faceSign")]; }
- (void)setFaceSign:(BOOL)v { [_d setBool:v forKey:KSNKey(@"faceSign")]; [self flush]; }

- (BOOL)idleKeepAwake { return [_d boolForKey:KSNKey(@"idleKeepAwake")]; }
- (void)setIdleKeepAwake:(BOOL)v { [_d setBool:v forKey:KSNKey(@"idleKeepAwake")]; [self flush]; }

- (BOOL)signNow { return [_d boolForKey:KSNKey(@"signNow")]; }
- (void)setSignNow:(BOOL)v { [_d setBool:v forKey:KSNKey(@"signNow")]; [self flush]; }

#pragma mark - 字符串配置

- (NSString *)locationRaw { return [_d stringForKey:KSNKey(@"locationRaw")] ?: @""; }
- (void)setLocationRaw:(NSString *)v { [_d setObject:(v ?: @"") forKey:KSNKey(@"locationRaw")]; [self flush]; }

- (NSString *)cachedSignCode { return [_d stringForKey:KSNKey(@"cachedSignCode")] ?: @""; }
- (void)setCachedSignCode:(NSString *)v { [_d setObject:(v ?: @"") forKey:KSNKey(@"cachedSignCode")]; [self flush]; }

- (NSString *)cachedGesture { return [_d stringForKey:KSNKey(@"cachedGesture")] ?: @""; }
- (void)setCachedGesture:(NSString *)v { [_d setObject:(v ?: @"") forKey:KSNKey(@"cachedGesture")]; [self flush]; }

#pragma mark - 人脸图

- (NSString *)facePath {
    NSString *lib = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [lib stringByAppendingPathComponent:@"KSN"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return [dir stringByAppendingPathComponent:@"face.b64"];
}

- (NSString *)faceBase64 {
    return [NSString stringWithContentsOfFile:[self facePath] encoding:NSUTF8StringEncoding error:NULL];
}

- (void)setFaceBase64:(NSString *)b64 {
    if (!b64.length) {
        [[NSFileManager defaultManager] removeItemAtPath:[self facePath] error:NULL];
        return;
    }
    [b64 writeToFile:[self facePath] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

#pragma mark - 桥用快照

- (NSDictionary *)snapshot {
    return @{
        @"autoSign":         @(self.autoSign),
        @"mockLocation":     @(self.mockLocation),
        @"locationRaw":      self.locationRaw,
        @"gestureSign":      @(self.gestureSign),
        @"faceSign":         @(self.faceSign),
        @"idleKeepAwake":    @(self.idleKeepAwake),
        @"signNow":          @(self.signNow),
        @"signCode":         self.cachedSignCode,
        @"hasFace":          @([[self faceBase64] length] > 1000),
        @"hasGesture":       @(self.cachedGesture.length > 0),
    };
}

- (void)applyFromBridge:(NSDictionary *)d {
    if (![d isKindOfClass:NSDictionary.class]) return;
    id v;
    if ((v = d[@"autoSign"]))         self.autoSign = [v boolValue];
    if ((v = d[@"mockLocation"]))     self.mockLocation = [v boolValue];
    if ((v = d[@"gestureSign"]))      self.gestureSign = [v boolValue];
    if ((v = d[@"faceSign"]))         self.faceSign = [v boolValue];
    if ((v = d[@"idleKeepAwake"]))    self.idleKeepAwake = [v boolValue];
    if ((v = d[@"signNow"]))          self.signNow = [v boolValue];
    if ([d[@"locationRaw"] isKindOfClass:NSString.class]) self.locationRaw = d[@"locationRaw"];
}

@end
