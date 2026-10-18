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

参考：[Apple 私有网站数据存储](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/websitedatastore)、[InAppWebView CookieManager](https://inappwebview.dev/docs/cookie-manager/)。
