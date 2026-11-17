# KSNiOS

学习通 iOS 端签到增强。Theos tweak，rootless，注入学习通 App 进程。

**不是 KSNStudy 的移植。** 原项目是纯 Android（Java + dex + `addWebMessageListener`），
iOS 侧没有一行可复用的代码。这里只复用它的签到接口调用方式和 DOM 选择器思路，
原生层、桥、面板全部按 iOS 的技术栈重写。

**不含答题、交卷、考试脱控。** 那部分没有做。

---

## 能做的

| 能力 | 实现 |
|------|------|
| 自动签到 | 轮询 `activelist` 拿待签活动，逐个提交 `stuSignajax` |
| 离屏签到 | 首页没有 WebView 时自己拉一个隐藏 webview 承载签到，复用同一份登录 cookie |
| 签到码获取 | 签到前先打 `signDetail` 拿最新码，取不到回退缓存 |
| 定位伪造 | 覆盖 `navigator.geolocation`，返回标准 `GeolocationPosition` |
| 手势签到 | JS 层记录你在签到页的绘制轨迹，之后自动重放 |
| 人脸签到 | 上传已存照片换 `faceCode`（可靠性低，见下） |
| 通知 | 签到结果走系统通知 |
| 面板 | 原生 UIKit 悬浮球 + pageSheet 配置页 |

## 做不到的

这些是 iOS 平台本身不给，不是没写完。

**1. 熄屏后台保活 —— 做不到**

Android 版靠前台服务 + `WakeLock` 常驻。iOS 没有等价物。
`beginBackgroundTaskWithExpirationHandler:` 只给大约 30 秒，之后进程被挂起，
`WKWebView` 里的 `setInterval` 全部停摆。

唯一可靠方案是**屏幕常亮 + 插电 + App 保持前台**（面板里的「屏幕常亮」开关）。
把手机锁屏放兜里等它自动签到，不成立。

**2. App 内自更新 —— 做不到**

iOS 不允许 App 替换自己的二进制。更新只能重新打 deb，用 Sileo / Zebra 覆盖安装。

**3. 人脸签到 —— 基本签不上**

学习通的人脸签到带活体检测和比对。上传一张静态照片换 `faceCode` 这条路，
在需要真人核验的场景过不了。代码留了通道，但别指望它。

**4. 手势签到 —— 只认绘制型**

只对 canvas / PointerEvent 的手势签到页有效。改成图片点选、文字密码那类就失效。

**5. 签到码 —— 看教师设置**

`signDetail` 拿不到「签到码不公开」的活动。这种情况下只能靠二维码链接里的码，
或者上一次的缓存值。

## 风险

**跨域。** JS 在 `i.chaoxing.com` / `mooc1.chaoxing.com` 下 fetch `mobilelearn.chaoxing.com`
是跨域请求。学习通自己的 H5 域大概率放行，被拦的话需要原生 `NSURLSession` 兜底
—— 这部分**没有实现**，是下一步。

**越狱检测。** 学习通有基础检测，rootless 的 `/var/jb` 路径容易被 grep 到。

**没编译验证过。** 开发环境是 Windows，没有 iOS 工具链。代码只做了静态检查，
首次编译走 GitHub Actions，报错再修。

---

## 构建

推上 GitHub，`.github/workflows/build.yml` 会用 `macos-15` 拉 Theos + iPhoneOS16.5.sdk
编出 deb，产物在 Actions 的 `ksnios-deb` artifact 里。

本地有 Theos 的环境：

```bash
export THEOS=~/theos
make clean && make package FINALPACKAGE=1
```

改完 `Resources/ksn.js` 不用手动跑脚本，`make` 的 `before-all` 会自动重新生成
`Sources/KSNJSData.h`（JS 内嵌进二进制，运行时零文件依赖）。

## 安装

```bash
# 越狱设备上
dpkg -i com.ksn.ios_0.1.0_iphoneos-arm64.deb
killall -9 Study    # 或重启 App
```

或者把 deb 丢进 Sileo / Zebra 装。

## Bundle ID

已确认：**`com.ssreader.ChaoXingStudy`**（学习通 7.0.2，App Store 中国区，`minimumOsVersion` 15.6）。

不是 `com.chaoxing.study` —— 那个在 iTunes 库里查不到任何结果。`ssreader` 是超星早期的品牌标识。

设备上自查（越狱，SSH 或 Filza 里的终端）：

```bash
for d in /var/containers/Bundle/Application/*/*.app; do
  id=$(plutil -extract CFBundleIdentifier raw "$d/Info.plist" 2>/dev/null)
  echo "$id  $d"
done | grep -i -E "ssreader|chaoxing"
```

Filza 手动找：`/var/containers/Bundle/Application/` → 逐个 UUID 目录 → `xxx.app/Info.plist` → `CFBundleIdentifier`。

装完验证 tweak 有没有真的进去：

```bash
log stream --predicate 'eventMessage CONTAINS "[KSN]"'
```

出现 `[KSN] tweak 已加载 pid=...` 就是注入成功。没有就两类原因：Bundle ID 不对，或者 App 没重启。

## 用法

1. 装好打开学习通，右上角出现悬浮球
2. 点开面板配好定位坐标（`纬度,经度,地址`）和开关
3. 进到学习通任意页面，等 30 秒自动扫一次（离屏签到器不依赖你停在哪一页）
4. 要看结果就点「立即签到」，或看面板顶部的状态行

## 接口

```
GET  mobilelearn.chaoxing.com/v2/apis/active/student/activelist?fid=0&showNotStartedActive=0
POST mobilelearn.chaoxing.com/newsign/signDetail          activePrimaryId=&appType=15&msg=
POST mobilelearn.chaoxing.com/pptSign/stuSignajax         courseId&classId&activePrimaryId&uid&signCode&latitude&longitude&location...
POST mobilelearn.chaoxing.com/v2/apis/sign/collectionfilephotoEnc   (multipart, face.jpg)
```

签名、风控参数（`vpProbability` / `vpStrategy` / `mockData`）沿用原项目的传法。

## 结构

```
Tweak.xm                    %hook WKWebView initWithFrame:configuration: —— 唯一 hook 点
Sources/KSNWebInjector.m    注入 WKUserScript + 挂桥
Sources/KSNBridge.m         WKScriptMessageHandlerWithReply，JS 侧 postMessage 直接返 Promise
Sources/KSNStore.m          配置（NSUserDefaults，落在学习通容器里）
Sources/KSNLifecycle.m      后台任务额度 + 屏幕常亮
Sources/KSNBackgroundSigner.m  离屏 webview 签到器（脱离用户当前页面）
Sources/KSNPanel.m          悬浮球 + 配置面板
Resources/ksn.js            签到引擎
scripts/embed_js.py         JS → C 字符串头文件
```

## 许可

MIT。签到行为的后果自己承担，包括但不限于账号风控和学业处分。
