# 栖游 Qiyou

轻量的二游体力、日常与社区签到管理。Flutter 开发，提供黑白灰亮色、暗色两种主题。

首版支持米游社国服：**原神、崩坏：星穹铁道、绝区零**。

## 当前功能

- 游戏总览：体力、上限、预计回满时间和社区可提供的日常进度。
- 多米游社账号导入，自动发现已绑定的游戏角色。
- 一键社区签到，分别显示已签、过期、需要验证、失败等状态。
- 每日手动清单，按北京时间重置；与游戏接口中的完成度独立。
- 亮色 / 暗色切换，UID 展示脱敏。
- 官方游戏图标，来源记录于 [assets/games/sources.json](assets/games/sources.json)。
- 全界面内置鸿蒙黑体 HarmonyOS Sans SC，包含常规、中等和粗体原始字体。
- Windows 桌面测试版，支持官方网页连接账号和 DPAPI 本机加密存储。

**浏览器预览默认使用示例数据，不接受真实 Cookie，也不会发送真实签到请求。**
Windows 端已由用户验证官方网页登录、角色读取及今日签到状态；实时便笺仍在进行人工安全验证与端到端测试。Android / iOS / 鸿蒙尚未完成真机验证。接口不是官方对第三方保证稳定的开放 API，版本、签名参数和接口字段可能变化。官方网页登录后获取会话不等于官方 OAuth 授权。

首版暂不包含扫码登录、后台自动签到和系统体力通知。体力显示最近同步值；回满倒计时依赖该次同步估算。

## 本地预览

```sh
flutter pub get
flutter run -d chrome
```

Windows 测试：`flutter run -d windows`；发布构建：`flutter build windows --release`。
将 `build/windows/x64/runner/Release/` 整个目录一起分发，不能只复制 EXE。
登录组件使用系统 WebView2 Runtime；本机构建还需 Microsoft NuGet 位于 PATH。

Windows 原生会话回归测试入口为 `test/native_session_probe.dart`。
该独立测试仅为 `qiyou.invalid` 设置虚构 HttpOnly Cookie，验证当前隐私窗口的读取、清除以及系统加密存储；不会登录真实账号或请求真实签到。0.1.1 修正了 Windows 通用 CookieManager 读取默认会话、漏掉隐私窗口会话的问题。

检查：

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release --no-wasm-dry-run
```

标准 Flutter 使用 **3.44.2**。网络与数据解析为纯 Dart；系统安全存储通过一个小型原生通道适配。

## GitHub Actions

推送到 `main`、提交 PR 或手动运行 `Build Qiyou` 后，先执行静态检查与测试，再并行构建：

| 产物 | 下载位置 | 安装说明 |
| --- | --- | --- |
| Android 调试 APK | `qiyou-android-debug` | 可直接安装测试；正式发行需配置自己的签名 |
| Windows 桌面版 | `qiyou-windows-x64` | 解压整个目录后运行 `qiyou.exe` |
| iOS 未签名 `.app` 压缩包 | `qiyou-ios-unsigned` | 用于验证编译，不能直接安装；IPA / TestFlight 需要 Apple 证书与描述文件 |
| 鸿蒙未签名 HAP（可选手动构建） | `qiyou-harmony-unsigned` | 用于验证编译，真机安装需要华为调试或发行签名 |
| 网页演示 | `qiyou-web-preview` | 静态文件，可本地启动 HTTP 服务预览 |

在仓库 **Actions → 对应运行 → Artifacts** 下载产物。CI 不需要游戏登录凭证；不要把 Cookie 放进 Actions Secrets、仓库或日志。

### 鸿蒙构建

鸿蒙 NEXT 使用 OpenHarmony 社区适配的 Flutter，不能使用标准 Flutter 的 Android APK 替代。

- 上游：`https://gitcode.com/openharmony-tpc/flutter_flutter.git`
- 官方发行标签：`3.35.7+ohos-1.0.5`
- 固定提交：`04d2008b35eae67162f0f11d2fd8e2453092c891`
- 命令行 SDK：`6.1.1.280`
- 最低兼容 API：17

鸿蒙优先本地编译，云端仅在手动运行时勾选 `build_harmony` 才执行。工作流核实官方标签提交后，在 SDK 内增加本地 `3.35.7` 版本别名，解决 Flutter 无法识别 `+ohos` 标签而报告 `0.0.0-unknown` 的问题；不修改 SDK 源码。

工作流先使用该版本生成 `ohos/` runner，再执行 `scripts/prepare_ohos.py` 注册原生安全存储，最后编译 HAP。生成过程不改动 `lib/`。新的鸿蒙构建配置仍需实际编译验证。

在已配置鸿蒙工具链的本机，也可以运行：

```sh
flutter create --platforms=ohos --project-name qiyou --org app.qiyou --no-pub .
python3 scripts/prepare_ohos.py <本机SDK的API版本数字>
flutter pub get
flutter build hap --release --target-platform ohos-arm64
```

## 登录与凭证

Windows / Android / iOS 在“账号”页可打开官方网页登录，完成后点击“完成登录并连接”；也可导入完整 Cookie。鸿蒙当前仅支持 Cookie 导入。连接前主动同意凭证处理，先请求已绑定角色，校验成功后才保存。WebView 使用隐私模式，不向栖游提供密码输入内容。

- Android：Android Keystore 的 AES-GCM 密钥，密文写入 `noBackupFilesDir`，关闭应用备份。
- iOS：Keychain，`AfterFirstUnlockThisDeviceOnly`。
- Windows：当前 Windows 用户的 DPAPI，密文位于本机用户的 LocalAppData/Qiyou。
- 鸿蒙：Asset Store；按每条 SECRET 的字节上限分块，使用最后提交的索引切换完整数据版本。
- 不记录 Cookie，不上传到自建服务器；网络请求只发送到代码内固定的米游社官方 HTTPS 域名，禁止自动跟随重定向。
- 遇到验证时停止该角色的签到，由用户回官方社区处理；不会尝试自动破解验证码。
- 签到写请求失败后不自动重试，避免结果不明确时重复提交。
- 签到提交成功后再次读取官方状态，未确认时不会标记成功。
- 体力同步与签到的错误独立显示。1034 / 10035 / 10041 会提示人工安全验证；可打开官方游戏工具。在 Windows 上，仅从当前所选角色的成功便笺响应同步数据和允许的设备会话元数据，并加密保存；不使用外部打码服务。

上架边界与自托管方案见 [华为应用市场上架评估](docs/appgallery-assessment.md)。当前版本为开发测试版，尚未完成接口及素材授权、正式隐私政策和上架资质准备。

## 目录

```text
lib/domain/            角色、体力、日常和签到状态
lib/data/              米游社请求与系统存储通道
lib/ui/                简洁界面与亮暗主题
platform/ohos/         鸿蒙原生存储插件
scripts/               鸿蒙工程配置、图标和字体工具
test/                  模拟接口、错误处理和响应式界面测试
.github/workflows/     检查与各平台构建
```

游戏接口地址和协议字段参考米游社客户端接口及 [GsCore](https://github.com/Genshin-bots/gsuid_core) 等项目的公开资料；本项目没有嵌入或运行其插件代码。

原创源码采用 MIT。游戏图标版权归米哈游等各自权利人所有，不属于 MIT 授权内容。HarmonyOS Sans 字体遵循[华为原始字体许可](assets/fonts/LICENSE.txt)，未修改、未子集化；来源与校验值见 [sources.json](assets/fonts/sources.json)。字体随应用分发，不作为独立字体商品。本项目为独立工具，与米哈游无隶属关系。
