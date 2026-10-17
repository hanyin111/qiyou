# 栖游 Qiyou

轻量的二游体力、日常与社区签到管理。Flutter 开发，提供黑白灰亮色、暗色两种主题。

支持米游社、库街区、塔吉多国服账号。Windows 0.1.8 的库街区与塔吉多登录、体力及签到状态读取已获用户确认；塔吉多签到实际生效也已确认。0.1.9 增加自选 WebDAV 的端到端加密手动同步。

| 社区 | 游戏 | 当前适配 |
| --- | --- | --- |
| 米游社 | 原神、星穹铁道、绝区零 | 登录、角色、签到、体力与日常、人工安全验证 |
| 库街区 | 鸣潮、战双帕弥什 | 官方网页登录、绑定角色、签到、体力与活跃度 |
| 塔吉多 | 异环 | 官方短信登录、绑定角色、签到、本性像素、都市活力、今日活跃 |
| 塔吉多 | 幻塔 | 官方短信登录、绑定角色、签到；体力与日常尚未适配 |

## 当前功能

- 游戏总览：体力、上限、预计回满时间和社区可提供的日常进度。
- 多社区、多账号导入，自动发现官方社区已绑定的游戏角色。
- 按账号单独移除或恢复游戏，其他游戏与社区登录保留；移除后不再查询和签到，状态可随加密备份同步。
- 一键社区签到，分别显示已签、过期、需要验证、失败等状态。
- 每日手动清单，按北京时间重置；与游戏接口中的完成度独立。
- 亮色 / 暗色切换，UID 展示脱敏。
- 官方游戏图标，来源记录于 [assets/games/sources.json](assets/games/sources.json)。
- 全界面内置鸿蒙黑体 HarmonyOS Sans SC，包含常规、中等和粗体原始字体。
- Windows 桌面测试版，支持官方网页连接账号和 DPAPI 本机加密存储。
- 自选 HTTPS WebDAV：手动上传、下载预览与合并；scrypt + AES-256-GCM 端到端加密，条件写入防止覆盖其他设备更新。

**浏览器预览默认使用示例数据，不接受真实 Cookie，也不会发送真实签到请求。**
Windows 米游社登录、签到及 0.1.5 人工验证码完成后读取体力，已由用户实测确认。库街区与塔吉多的实测范围见上文及适配记录，不代表每个游戏均已真机验收。Android / iOS / 鸿蒙尚未完成真机验证。接口不是官方对第三方保证稳定的开放 API，版本、签名参数和接口字段可能变化。官方网页登录后获取会话不等于官方 OAuth 授权。

首版暂不包含扫码登录、后台自动签到和系统体力通知。体力显示最近同步值；回满倒计时依赖该次同步估算。

0.1.10 修正鸣潮直接读取组件旧缓存的问题：查询前先请求官方刷新角色数据，再读取体力；从 `energyData.refreshTimeStamp` 的回满时间戳计算倒计时，缺失或不一致时不假定已满。可在游戏详情中移除单个游戏，在账号页恢复；按社区账号隔离，不改动官方绑定。移除全部游戏也保留本机社区会话，重新连接不会自动恢复已移除游戏。

## 本地预览

```sh
flutter pub get
flutter run -d chrome
```

Windows 测试：`flutter run -d windows`；发布构建：`flutter build windows --release`。
分发时包含 EXE、运行库 DLL 和 `data/`，不能只复制 EXE。不要打包使用后生成的 `qiyou.exe.WebView2/` 浏览器配置目录或本机账号数据。
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

Windows / Android / iOS 在“账号”页连接时选择社区。米游社使用原有官方网页 Cookie 登录。库街区在官方网页完成短信与人工验证码，通过 App 登录通道获取游戏数据会话，完成后点击右上角连接；只读取服务端返回的 Token 和 `dc` 设备键，不把手机号或验证码字段传到 Dart。塔吉多改为本人输入手机号和短信验证码，通过完美世界官方 SDK 接口验证后换取塔吉多 App 会话；手机号、验证码、中间 SDK 凭证和未使用的 refreshToken 均不保存。可在本机导入已有 App Token，单纯网页 Token 或 Cookie 不能用于游戏接口。鸿蒙当前仅支持凭证导入。连接前主动同意凭证处理，先请求已绑定角色，校验成功后才保存。

- Android：Android Keystore 的 AES-GCM 密钥，密文写入 `noBackupFilesDir`，关闭应用备份。
- iOS：Keychain，`AfterFirstUnlockThisDeviceOnly`。
- Windows：当前 Windows 用户的 DPAPI，密文位于本机用户的 LocalAppData/Qiyou。
- 鸿蒙：Asset Store；按每条 SECRET 的字节上限分块，使用最后提交的索引切换完整数据版本。
- 不记录登录凭证。游戏账号请求只发送到各社区客户端内固定的官方 HTTPS 域名。可选同步只向用户自选的 HTTPS WebDAV 上传加密备份；同步密码不保存、不发送。两类请求均禁止自动跟随重定向。账号按社区隔离并在同一本机安全存储中加密保存。
- 遇到验证时停止该角色的签到，由用户回官方社区处理；不会尝试自动破解验证码。
- 签到写请求失败后不自动重试，避免结果不明确时重复提交。
- 签到提交成功后再次读取官方状态，未确认时不会标记成功。
- 体力同步与签到的错误独立显示。便笺出现 1034 / 10035 / 10041 时可点击“完成安全验证”，由本人操作极验验证码；向米游社确认通过后重新查询当前角色。验证码组件不接收 Cookie、账号 ID 或游戏 UID；极验会处理验证所需的设备与网络信息。验证参数只在内存中保留至多 5 分钟，不使用打码服务。验证码通过但数据仍被限制时，继续显示失败。
- 人工验证采用 `createVerification → 极验人工交互 → verifyVerification → 便笺查询`。0.1.4 按官方前端补齐失败请求地址与追踪标识、`is_high=true`，使用确认接口返回的新凭据单次重试，不能把极验原始 challenge 当作米游社返回凭据。错误分别标明获取、确认或查询阶段。接口测试通过不代表已通过真实账号验证，仍需本人测试。
- 0.1.5 在验证前通过匿名的米游社官方网页获取本机浏览器设备指纹、设备 ID 与浏览器标识；不伪造手机硬件参数，不向这个初始化页面提供账号 Cookie。设备信息加密保存后先重试便笺，仍要求验证时才显示验证码。记录接口的短期基础设施 Cookie 按账号、设备和域名隔离，仅在内存保留。
- 开发者从本机启动时可设置 `QIYOU_VERIFICATION_REPORT` 输出单份脱敏诊断，仅含版本、阶段、游戏、错误码、脱敏后的官方说明，以及设备指纹和临时会话是否存在；不输出 Cookie、UID、指纹值、验证码内容或原始响应。不设置该变量时不写诊断文件，也不上传诊断。

上架边界与自托管方案见 [华为应用市场上架评估](docs/appgallery-assessment.md)。当前版本为开发测试版，尚未完成接口及素材授权、正式隐私政策和上架资质准备。

## 跨平台账号同步

在“设置 → 账号同步”填写一个已建立的 HTTPS WebDAV 文件夹地址、用户名和应用密码，可测试连接并主动保存到本机安全存储。另设至少 12 个字符的同步密码，与 WebDAV 应用密码分开；所有设备需使用相同的同步密码，关闭页面后需重新输入，忘记无法恢复。

已有账号设备点击“上传到云端”，首次需再次确认同步密码；另一设备点击“从云端下载”，预览后合并账号、清单并应用亮暗与 UID 设置。同一账号默认保留本机登录态，可主动选择云端会话；同一清单保留本机进度。下载不删除本机独有数据，也不执行登录或签到。返回游戏页手动刷新以验证官方是否接受该会话。

上传是完整备份替换，预览会提示云端独有内容可能被移除；有其他设备内容时先下载合并再上传。文件固定为 `qiyou-vault-v1.json`。已有备份需强 ETag 才能安全更新，冲突返回后必须重新预览，不自动覆盖。浏览器演示禁用真实同步。

同步能传递现有会话，不能解除官方的单会话限制、设备绑定或人工验证要求。首版尚无自动同步、主设备代理签到或同步密码更换。加密协议、兼容性及测试边界见 [同步说明](docs/sync.md)。

## 目录

```text
lib/domain/            角色、体力、日常和签到状态
lib/data/              三个社区的官方请求、登录会话与系统存储通道
lib/ui/                简洁界面与亮暗主题
platform/ohos/         鸿蒙原生存储插件
scripts/               鸿蒙工程配置、图标和字体工具
test/                  模拟接口、错误处理和响应式界面测试
.github/workflows/     检查与各平台构建
```

游戏接口地址和协议字段参考米游社客户端接口及 [GsCore](https://github.com/Genshin-bots/gsuid_core) 等项目的公开资料；本项目没有嵌入或运行其插件代码。

库街区与塔吉多的接口、官方前端来源及测试边界记录于 [多社区适配记录](docs/testing/community-integration.md)。只借鉴公开协议字段，使用独立 Dart 实现；没有接入上游的代理服务、自动验证码或社区刷任务功能。

人工验证的接口字段参考 [GsCore 验证请求](https://github.com/Genshin-bots/gsuid_core/blob/master/gsuid_core/utils/api/mys/pass_request.py)，完整上下文与重试流程按[米游社官方前端](https://webstatic.mihoyo.com/app/community-game-records/)核对（见 [0.1.4 核对记录](docs/testing/record-verification-protocol.md)），验证码交互使用[极验官方 Web SDK](https://docs.geetest.com/captcha/apirefer/api/web)。未集成上游的自动验证服务；只由用户操作验证码，并由米游社服务端确认。

原创源码采用 MIT。游戏图标版权归米哈游等各自权利人所有，不属于 MIT 授权内容。HarmonyOS Sans 字体遵循[华为原始字体许可](assets/fonts/LICENSE.txt)，未修改、未子集化；来源与校验值见 [sources.json](assets/fonts/sources.json)。字体随应用分发，不作为独立字体商品。本项目为独立工具，与米哈游无隶属关系。
