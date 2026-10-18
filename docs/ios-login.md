# iOS 官方网页登录

## 0.1.15 修复

用户在 iPhone 的 0.1.14 中反馈：米哈游官方页已登录，应用却读不到登录状态；库街区展示移动端下载入口，无法进入网页短信登录。本次只修复这两个流程，没有更改塔吉多登录。

米游社的明确原因是会话存储不一致：项目锁定的 `flutter_inappwebview_ios 1.1.2` 使用 `WKWebsiteDataStore.default().httpCookieStore` 实现全局 CookieManager，即使调用时传入 WebViewController，也不会切换到登录页的无痕会话。该会话的 HttpOnly 登录 Cookie 也无法通过 `document.cookie` 读取。

现在通过当前控制器在页面写入一次性随机标记，原生桥接仅选择具有相同标记的官方 HTTPS WKWebView，读取其 `configuration.websiteDataStore.httpCookieStore`。读取后清理标记；多个匹配、找不到匹配、非官方地址和超时均失败，不退回全局存储或其他登录页。Cookie 按目标域名、路径、有效期和 HTTPS 筛选，不记录凭据、不读取表单，也不导出浏览器会话到小组件。

库街区的官方公开 [pre-route.js](https://web-static.kurobbs.com/resource/prod/static/pre-route.js) 按 `navigator.userAgent` 判断手机并切换移动路由。iOS 官方登录页现使用桌面 Safari UA，并设置 `UserPreferredContentMode.DESKTOP`，在页面初次加载前生效。仍使用原有官方短信表单与库街区游戏会话桥接。Android、Windows 沿用原有浏览器身份。

这次需要编译新版 iOS 程序，因为新增了读取私有会话的原生代码；不能仅靠修改 IPA 的 plist 修复。0.1.14 的 ASCII 默认名称和中文本地化保留。Actions 直接输出含 `Payload/Runner.app` 和小组件扩展的未签名 IPA，安装仍需个人签名。

## 验证范围

Dart 测试覆盖当前 WebView 随机标记绑定、结束清理、读取失败不回退，以及 iOS 桌面模式和其他平台配置。原生 `BrowserCookieTests` 在独立测试宿主内创建两个真实的 WKWebView 无痕数据存储，并设置默认存储中的干扰 Cookie，验证只读取绑定页面的 HttpOnly Cookie；同时覆盖域名、路径、HTTPS、非官方地址与未匹配标记。这些测试仅使用本地合成 HTML 和虚构 Cookie，不执行登录、发短信或签到。

模拟器测试能验证底层会话隔离及原生编译，不能替代 iPhone 上的真实账号登录。签名后的登录检测、库街区网页表单可用性及登录后的查询和签到，仍需用户真机验收。

2026-10-18，[0.1.15 构建验证通过](https://github.com/hanyin111/qiyou/actions/runs/39127890095)（代码提交 `519caa2`）：Dart 全量检查与回归通过，Swift 数据测试 6 项、模拟器原生测试 4 项通过。其中 `testPrivateHttpOnlyCookiesComeFromBoundWebView` 在两个独立无痕 WKWebView 和默认存储间验证隔离；域名/路径测试通过。iOS 真机与模拟器编译通过，Android、Windows、Web 构建也通过，鸿蒙未运行。本次只触发一轮构建。

发布文件 `qiyou-ios-0.1.15-unsigned.ipa` 为 build 16，39,790,317 字节，SHA-256：`7110ea797f9b7d82252967c8641811efdc8ea9d157d5a028c67090322f7fb9fb`。本地检查 ZIP 完整性、主应用/扩展版本与默认 ASCII 名称、两端中英文名称资源、可执行权限以及测试宿主未嵌入发布包。它仍是未签名 IPA，真实登录结果待用户确认。

参考：[Apple 私有网站数据存储](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/websitedatastore)、[InAppWebView CookieManager](https://inappwebview.dev/docs/cookie-manager/)。
