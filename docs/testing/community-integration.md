# 库街区与塔吉多适配记录

核对日期：2026-10-16。版本：0.1.7（保留 0.1.6 验证记录）。此记录只含公开协议，不包含账号凭证。

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

`refreshTimeStamp` 的具体恢复语义尚未确认，本版不据此猜测回满时间。接口缺字段显示暂未提供，不填默认满体力。遇到额外风控则停止，并引导本人在官方页面处理后重新连接。

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
