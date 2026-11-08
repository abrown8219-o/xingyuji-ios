# 星语机 iOS 版（WKWebView 壳）

把「星语星愿」网页包成一个 iOS App，功能和安卓 APK 对等：
WKWebView 加载站点 + Capacitor 垫片注入 + Basic Auth + 调试面板 + 日志上传 + 悬浮返回键 + 无痕模式 + 更新检查 + JS 桥。

> ⚠️ **重要前提**：iOS 不能像安卓那样直接安装 apk。你必须有一台 Mac + Xcode，
> 用 Apple ID（免费个人签名，7 天有效）或 Apple Developer（$99/年）签名后才能装到 iPhone。
> 没有 Mac 就把这个文件夹发给有 Mac 的人帮忙编译。

---

## 一、编译步骤（Xcode 15 或更新版本）

1. 打开 Xcode → **File → New → Project** → 选 **iOS → App**。
2. 名字填 `Xingyuji`，Interface 选 **SwiftUI**，Language 选 **Swift**，然后保存。
3. 把本目录下这 5 个 `.swift` 文件拖进 Xcode 左侧的项目导航（勾选 Copy items if needed）：
   - `XingyujiApp.swift`
   - `Store.swift`
   - `MainScreen.swift`
   - `WebScreen.swift`
   - `Services.swift`
   - 删除模板自动生成的 `ContentView.swift`（用不到了）。
4. 选目标 `Xingyuji` → **Signing & Capabilities** 标签：
   - 勾选 **Automatically manage signing**
   - **Team** 选你自己的 Apple ID（没有就点 Add Account 登录一个免费 Apple ID）
   - **Bundle Identifier** 改成唯一值，例如 `com.yourname.xingyuji`
5. 设置部署目标 **Deployment Target ≥ iOS 17.0**。
6. 接上 iPhone，顶部设备选你的手机，点 ▶ 运行。首次会提示去「设置 → 通用 → VPN与设备管理」信任你的开发者证书。

---

## 二、Info.plist 里需要加的键（重要）

工程里点开 `Info.plist`，添加下面这些（否则 http 站点/语音输入会失败）：

| Key | 类型 | 值 |
|---|---|---|
| `NSAppTransportSecurity` | Dictionary | 里面加 `NSAllowsArbitraryLoads` = YES（允许 http / 自签证书，等同安卓放行自签） |
| `NSMicrophoneUsageDescription` | String | `用于语音输入` |
| `NSCameraUsageDescription` | String | `用于拍照上传` |

> 只访问 https 站点可省略 ATS 那项，但建议都加上，方便连局域网 SillyTavern。

---

## 三、和安卓版的差异（iOS 平台限制）

| 安卓功能 | iOS 版 |
|---|---|
| 直接下载 apk 安装 | ❌ 不行，必须 Xcode 签名 |
| 后台保活 / 悬浮球 / 开机自启 / 电池白名单 | ❌ iOS 系统不允许，已移除 |
| 应用内检查更新自动装 | ⚠️ 只能提示新版本并打开网页，iOS 壳自身更新走 TestFlight / App Store |
| 无痕模式 | ✅ 用 `WKWebsiteDataStore.nonPersistent()`，退出即清，真隔离 |
| 选择外部浏览器 | ⚠️ iOS 只有 Safari，改为「在 Safari 打开」 |
| 网页语音输入（麦克风） | ✅ 已处理权限回调，需上面的 plist 键 |
| 文件上传 | ✅ iOS 原生支持，无需额外代码 |

---

## 四、代码结构

- `XingyujiApp.swift` — App 入口，注入全局状态
- `Store.swift` — 站点列表 + 设置 + Basic Auth 凭证 + 日志环（UserDefaults 持久化）
- `MainScreen.swift` — 主界面：站点列表、添加/编辑/删除、设置开关、检查更新、上传日志
- `WebScreen.swift` — 网页视图：WKWebView + Capacitor 垫片 + JS 桥 + 调试面板 + 悬浮返回键 + 错误页
- `Services.swift` — 日志上传（PUT 到服务器）+ 更新检查（读 version.json）

> 网页地址、日志服务器、上传密钥都集中在 `Services.swift` 顶部和 `Store.swift` 的默认站点里，换域名改这两处即可。
