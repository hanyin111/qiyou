# 0.1.16：手机登录与小组件侧载兼容

米游社、库街区新增独立的 Flutter 手机号与短信验证码表单，避免在 iPhone 上操作桌面网页。入口仍保留“使用官方网页登录”。请求只发送到对应官方固定域名，不跟随重定向，不保存手机号、短信验证码或米哈游中间 stoken。人机验证通过独立页面让用户手动完成，不自动解题；取消验证时不会继续发短信。短信成功后才启动重发倒计时。登录成功但角色连接失败时，在当前页面内保留已取得的会话，可重试连接而不重复登录。

米游社使用当前 Passport `createLoginCaptcha` / `loginByMobileCaptcha` / `getCookieAccountInfoBySToken` 流程，以官方 RSA 公钥加密手机号，处理 Aigis 人机验证后取得社区 Cookie。匿名检查发现旧 `create_mmt` 路径返回拒绝，因此没有采用旧网页短信接口。参数参考 [TeyvatGuide 的 Passport 实现](https://github.com/BTMuli/TeyvatGuide/blob/main/src/request/passportReq.ts)，独立实现请求与界面。

库街区使用官方 `/user/getSmsCode` 和 `/user/sdkLogin`；需要极验 v4 时单独显示验证页面，完成后携带官方证明继续。短信与登录共用同一设备标识，返回的社区 token、设备标识用于现有角色和体力接口。参考[库街区公开前端](https://web-static.kurobbs.com/resource/prod/assets/index-CWPdzgN0.js)的极验配置及[库街区接口记录](https://github.com/TomyJan/Kuro-API-Collection/blob/master/API/user/sdkLogin.md)。

塔吉多改为默认“短信登录”，清楚说明成功后自动取得并加密保存 accessToken、refreshToken 和登录设备 ID；用户无需手动提取。原有手动导入放在“高级导入”，适合已有社区会话。保留短信登录可能影响同通行证游戏会话的提示；日常续期仍不重做 SDK 短信登录。

米游社便笺验证初始化改为直接载入官方页面，等首次加载完成后再写入允许的设备 Cookie。iOS 的设备 Cookie 写入当前私有网页，不再写到默认存储。移除完全透明的初始化 WebView；iOS 请求桌面页面，其他平台保留原来的 UA。增加 40 秒总超时与主页面加载失败提示，避免无限停留在初始化。账号 Cookie 仍不会提供给验证码页面。

## 侧载共享空间

原来固定使用 `group.app.qiyou.qiyou`；[SideStore 重签名](https://github.com/SideStore/SideStore/blob/develop/SideStore/Core/Operations/PipelineOperations/FetchProvisioningProfilesOperation.swift)会附加团队后缀。主应用和小组件现读取各自已安装授权描述文件里的共享组，从本项目的组名范围内选择实际可用容器；不访问其他应用组。兼容旧签名工具提供的 `ALTAppGroups` 字段，原始组名作为正式开发者签名的后备。

Actions 的 `--no-codesign` 编译不会提供可供侧载工具提取的完整共享权限，因此打包前对主应用和扩展写入带共享组声明的本地 ad-hoc 签名。这个签名不能直接用于 iPhone 安装，仍需 SideStore 等工具使用用户自己的开发者身份重新签名。安装时需保留小组件扩展和共享权限；如果签名服务不授权 App Groups，程序不能绕过系统限制，会明确提示未取得共享空间。

## 验证与边界

接口回归只使用虚构手机号、验证码、Cookie 与模拟 HTTP 响应，验证 RSA 加密、Aigis 绑定、手动验证取消、设备一致性、重定向停止及敏感信息不进入保存凭据。窄屏界面覆盖 375×812、键盘弹出和亮暗两种模式；塔吉多默认入口也有界面回归。Swift 测试覆盖 CMS 包裹的授权 plist 解析、团队后缀、无关组过滤和后备顺序。

为了减少无关编译，本版编译 iOS 真机应用，并在独立模拟器宿主中测试共享的原生实现和小组件界面，不重复编译完整 Flutter 模拟器应用。签名后的真实共享区访问、真实短信发送/登录、米游社安全验证码和查询结果仍需 iPhone 验收。这些通过的模拟测试不等于真实账号验证。
