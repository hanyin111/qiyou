# 库街区与塔吉多适配记录

核对日期：2026-10-17。版本：0.1.11（保留早期验证记录）。此记录只含公开协议，不包含账号凭证。

2026-10-17 本人反馈：库街区和塔吉多均能正常连接、读取体力及签到状态；塔吉多签到实际生效已确认。此结论不扩展到未测试的其他游戏或移动平台。下面保留各版本当时的验证边界。

## 0.1.11：刷新请求的认证分离

用户重新连接后，0.1.10 仍返回 10000。核对 [McKuro 数据客户端](https://github.com/ZPC5560/McKuro/blob/465954bcd0a7010c2887b4d6eb583b665b11a964/src/McKuro.Core/Services/Roles/KujiequApiClient.cs) 的 RefreshDataAsync 与 BuildWebHeader：角色数据中心刷新不能额外携带社区 token，否则返回参数错误。0.1.10 复用了带社区 token 的组件请求头，先前模拟测试没有模拟这种拒绝条件。

0.1.11 对刷新复制并分离请求头，保留实际绑定的 did 与 b-at，移除社区 token，使用 `https://web-static.kurobbs.com` 的官方工具 origin 及 `X-Requested-With: com.kurogame.kjq` H5 协议标记；保留真实 UA 和登录设备，不复制上游的虚构手机硬件参数。请求体仅 gameId、roleId、serverId 三字段。刷新响应必须明确为 true 才读取组件；false/null 不视为成功。社区角色、签到与原有组件请求继续使用各自认证。错误会显示失败步骤及脱敏后的官方说明，不自动重试风控。

本机静态检查及 92 项回归通过。新增模拟服务会在刷新请求带社区 token 时返回 10000，验证修正后能刷新并读取体力，且不会破坏社区签到认证；也覆盖刷新响应 false/null、错误阶段及敏感值脱敏。

本机诊断再次在数据令牌阶段返回 220（会话过期），尚未对有效会话完成刷新实测。正式入口支持可选 `QIYOU_KURO_REPORT`，只在开发者明确指定本机路径时记录最近一次查询阶段、错误码、两类认证字段是否存在及刷新是否确认，不含凭据、UID 或原始响应，不上传；便于在用户本人重新连接的同一窗口定位，避免依赖另一个进程的旧会话。真实账号体力对照仍待本人确认。

## 0.1.10：鸣潮缓存刷新与回满时间

用户随后反馈鸣潮显示的体力与游戏内不符，且未显示回满时间。0.1.8/0.1.9 直接读取 `/gamer/widget/game3/getData` 的缓存，没有触发角色数据更新，也没有解析能量回满时间字段。

按 [XutheringWavesUID 请求实现](https://github.com/Loping151/XutheringWavesUID/blob/4c1727580c613ef3034a391dc3156a1570cd5260/XutheringWavesUID/utils/api/requests.py) 核对：先取得角色访问令牌，再 `POST /aki/roleBox/akiBox/refreshData`，携带实际绑定的 gameId、serverId、roleId 和同一登录设备及数据访问令牌；成功后读取组件。刷新失败时停止，不把缓存重新标成最新值。若响应显式包含其他角色或服务器，拒绝显示。

[体力展示实现](https://github.com/Loping151/XutheringWavesUID/blob/4c1727580c613ef3034a391dc3156a1570cd5260/XutheringWavesUID/wutheringwaves_stamina/draw_waves_stamina.py) 将 `energyData.refreshTimeStamp` 作为绝对 Unix 回满时间。0.1.10 转换为从本次查询时刻起的剩余秒数，支持秒和毫秒输入；已满显示 0，零体力仍可正常计算。缺失、零或与非满体力矛盾的过期时间不显示“已满”。不猜恢复速率。

游戏移除是按社区账号保存的 `hiddenGames` 设置：保留原绑定角色与会话，停止被移除游戏的查询和签到；账号页可恢复。重新连接保留此设置。WebDAV 合并应用云端游戏移除状态，同账号仍默认保留本机登录凭据；旧存档缺该字段时默认全部显示，旧版客户端不识别此设置，跨设备应升级后使用。

`test/native_kuro_stamina_probe.dart` 为显式本地诊断入口，通过应用原生通道读本机存储，对比刷新前后体力及恢复时间；不写存档、不登录、不签到，报告只写到开发者指定的本机文件，不公开真实账号数据。

本机原生核对在取得数据令牌时返回 220（会话过期），未完成真实账号体力对照；需要本人在新版重新连接库街区后复测。模拟检查不替代此项实测。

本机静态检查及 88 项完整回归通过，新增覆盖刷新旧缓存、回满时间、角色一致性、按账号移除/恢复游戏、重连保留移除设置、停止已移除游戏的查询与签到、存储失败回滚、云端状态合并及两个界面入口。

## 0.1.8：区分网页与游戏会话

0.1.7 用户反馈：鸣潮获取数据令牌返回 10901“禁止访问”；塔吉多可以读到异环角色，但体力及签到状态返回 HTTP 402。

本机只读诊断复现：原库街区网页登录 Token 在 `source=h5` 时被数据令牌接口拒绝；同一个 Token 改为原生通道后返回 220，无有效 App 登录态。塔吉多 Cookie、增加 DS 签名、把 `tjd_token` 当作 Authorization 均不能读取游戏接口；`/usercenter/wapi/login` 返回重定向，没有下发 App 会话。不能靠更换设备标识、请求头或重复刷新解决。诊断不执行签到，不修改账号存储，输出仅含状态码及字段存在性。

库街区作者的[接口记录](https://github.com/TomyJan/Kuro-API-Collection/blob/main/API/user/sdkLoginForH5.md)明确区分 Web 与 App Token。官方当前前端短信登录调用 `/user/sdkLogin`，只传 mobile 和 code；0.1.8 仍由官方表单负责手机号、短信及人工验证码，在当前私密网页中把该次登录选择为 `source=android` 的 App 通道，并追加同一浏览器 `dc` 作为 devCode。不提取手机号和验证码字段，只将服务端成功响应中的社区 Token 及设备信息交给原生端。消息带随机 nonce 并验证当前官方 origin，Token 由官方角色接口再次校验后才保存。旧网页 Token 不再作为连接游戏接口的成功依据。

塔吉多[官方异环工具](https://webstatic.tajiduo.com/bbs/yh-game-record/)从 App 桥接 `getUserData` 取得 accessToken，并将 HTTP 402 提示为需要重新登录。0.1.8 改用本人操作的手机号短信登录：`user.laohu.com/m/newApi/sendPhoneCaptchaWithOutLogin` → 校验短信 → `/openApi/sms/new/login` → `bbs-api.tajiduo.com/usercenter/api/login`。协议按 [NTEUID](https://github.com/tyql688/NTEUID) 与 [taygedo-auto-attendance](https://github.com/zzstar101/taygedo-auto-attendance) 的直接官方请求核对，独立 Dart 实现，未使用代理；未借用官方工具内的演示令牌。签名与 AES-ECB/PKCS7 属于公开客户端协议；设备型号字段标识 Qiyou 与实际平台，不伪造手机硬件。若官方要求额外验证则停止，不自动解题或重试验证码。

手机号、验证码、SDK 中间令牌不保存。本人点击发送才请求短信，界面设 60 秒重发倒计时。只将最终塔吉多访问令牌、服务端账号编号与本次登录设备送入安全存储；旧账号重新连接时替换为实际登录设备。访问令牌过期时需要重新登录，本版不保存尚未使用的刷新令牌。HTTP 402 现在明确提示重新连接游戏服务。

64 项测试通过，含独立 AES 测试向量、签名、三步身份交换、实际登录设备替换、错误脱敏和原有米游社回归。Windows 匿名桥接检查通过，见 [windows-kuro-login-0.1.8.json](windows-kuro-login-0.1.8.json)；空表单请求也确认 App 通道响应允许当前官方网页 origin。模拟协议与匿名桥接检查不能代替本人短信登录后的真实查询和签到实测。

## 0.1.7：真实反馈后的会话修正

0.1.6 用户反馈：塔吉多网页已显示头像或昵称，点击连接仍提示未检测登录；库街区可以连接并读到角色，鸣潮卡片刷新报 10901。此前匿名检查仅证明页面与脚本可运行，不能证明完整账号登录和查询成功。

- 塔吉多官方 PC 前端的请求客户端设置 `withCredentials: true`，`localStorage.token` 只是可选 Authorization 补充；官方登录重定向后可以仅持有 Cookie。0.1.7 从实际隐私 WebView 读取 `bbs-api.tajiduo.com` 的 Cookie，支持不含本地 Token 的会话，先由官方个人信息接口校验后再保存。令牌登录继续兼容，Cookie 会话加密保存并在后续查询中恢复；不读取或转发 `id.wanmei.com`、`user.laohu.com` 的 Cookie。
- 库街区官方 `index-DCU6Kl-8.js` 从 `localStorage.dc` 初始化 `DEV_CODE`，`useConfig-DLqk4N_9.js` 把它作为 `devCode` 请求头。旧版只读取 Token，另生成设备 ID。0.1.7 一并读取真实 `dc`，将其传递到数据令牌请求的 `did`，重新连接时允许实际浏览器设备替换旧随机 ID。10901 的服务端具体含义仍以实际响应为准；失败提示会区分获取令牌与读取体力，并显示脱敏后的官方说明。

新增模拟测试覆盖 Cookie-only 登录、会话保存恢复、浏览器设备优先级、重新连接替换旧设备和 10901 的步骤及脱敏。Windows 匿名检查改为验证实际 `dc` 读取及当前隐私窗口跨子域的虚构 HttpOnly Cookie；不使用真实账号。真实账号的体力与签到仍须用户复测。

0.1.7 本机静态检查及 57 项测试通过。原生匿名检查也通过了真实 `dc` 与当前隐私窗口 HttpOnly Cookie 的生产读取函数，报告见 [windows-community-login-0.1.7.json](windows-community-login-0.1.7.json)。

## 范围与登录

| 社区 | 官方登录入口 | 会话读取 |
| --- | --- | --- |
| 库街区 | https://www.kurobbs.com/mc/ | 本人完成官方网页登录后，点击连接，读取官方社区 origin 下的 `localStorage.auth_token` 和 `dc` |
| 塔吉多 | https://www.tajiduo.com/bbs/index.html#/home | 本人完成官方 SSO 登录并返回社区后，点击连接，读取官方 API origin 的 Cookie 和可选 `localStorage.token` |

隐私 WebView 不读取密码输入、短信验证码或登录表单请求。仅允许 HTTPS 官方页面导航，SSO 包括 `id.wanmei.com`。会话获取后读取官方绑定角色，成功后才提交系统安全存储。原有无 `community` 字段的账号按米游社迁移，新社区账号 ID 分别加 `kuro:` 与 `taygedo:` 前缀，防止相同数字 ID 覆盖。

## 库街区

固定官方 API 域名：`api.kurobbs.com`。`gameId=3` 鸣潮，`gameId=2` 战双帕弥什。

- `POST /gamer/role/list`：按游戏查询绑定角色，使用返回的 `userId`、`roleId`、`serverId`，不猜默认服务器。
- `POST /aki/roleBox/requestToken`：鸣潮角色数据访问令牌，仅在内存短期缓存，按账号、设备、角色隔离。
- `POST /gamer/widget/game3/getData`：鸣潮结晶波片与活跃度，支持响应 `data` 是 JSON 字符串的情况。
- `POST /haru/roleBox/dailyData`：战双血清与活跃度。
- `POST /encourage/signIn/initSignInV2`：严格读取布尔字段 `isSigIn`。
- `POST /encourage/signIn/v2`：携带实际绑定角色与北京时间月份 `reqMonth`，提交后重新读取签到状态。

公开协议参考 [XutheringWavesUID](https://github.com/Loping151/XutheringWavesUID)、[PGRUID](https://github.com/Loping151/PGRUID)、[McKuro](https://github.com/ZPC5560/McKuro)，登录键与图标按库街区官方前端核对。未嵌入任何插件源码或打码服务。没有使用上游示例中的伪造手机硬件参数。

早期版本未使用 `refreshTimeStamp`；0.1.10 的字段核对与实现见上文。接口缺字段显示暂未提供，不填默认满体力。遇到额外风控则停止，并引导本人在官方页面处理后重新连接。

## 塔吉多

固定官方 API 域名：`bbs-api.tajiduo.com`。`gameId=1289` 异环，`gameId=1256` 幻塔。

- `GET /usercenter/wapi/getUserFullInfo`：校验官方会话，获取当前账号 UID。
- `GET /apihub/api/getGameRecordCard`：读取此账号已绑定角色；不自动更改社区主绑定角色。
- `GET /apihub/awapi/yh/roleHome`：异环本性像素、都市活力与今日活跃；缺失数据不视为零。
- `GET /apihub/awapi/signin/state`：严格读取布尔字段 `todaySign`。
- `POST /apihub/awapi/sign`：提交绑定角色的游戏签到，再查询今日状态确认。

公开协议参考 [NTEUID](https://github.com/tyql688/NTEUID)、[taygedo-auto-attendance](https://github.com/zzstar101/taygedo-auto-attendance)，登录键、社区游戏 ID 和图标按官方社区前端及 `GET /apihub/wapi/getAllCommunity` 核对。原生查询的 DS 为公开客户端协议字段，独立 Dart 实现。账号令牌只发往官方域名，不接入第三方代理。

幻塔官方社区的游戏记录工具位于 `https://webstatic.tajiduo.com/bbs/game-records/`，其 `GET /apihub/awapi/ht/getRoleGameRecord` 主要展示战绩与收集。本次尚未确认可稳定读取当前活力的字段，因此幻塔先提供角色与签到，体力和日常明确显示尚未适配。

## 验证边界

模拟接口测试覆盖旧账号迁移、多社区同数字账号共存、真实服务器字段传递、角色数据令牌、日常解析、签到前后状态确认、状态缺失不盲签、写入失败不重试、错误脱敏、保存失败回滚和移除账号的隔离。

原有米游社流程纳入回归。米游社 0.1.5 已获用户确认“验证码完成后已显示体力”。新社区的模拟测试与匿名网页登录检查不能替代真实账号验证，库街区与塔吉多仍需用户在本机完成登录、刷新和签到实测。

本机结果：53 项测试通过，静态检查通过；Windows 匿名 WebView 检查同时通过两个官方 origin 与生产会话读取脚本，报告见 [windows-community-login.json](windows-community-login.json)。独立入口 `test/native_community_login_probe.dart` 不读取本机安全存储，不执行签到。
