import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../app_state.dart';
import '../data/miyoushe_client.dart';
import '../data/login_session.dart';
import '../domain/models.dart';
import '../data/community_login_session.dart';
import '../data/kuro_login_session.dart';
import '../data/community_http.dart' show newCommunityDeviceId;
import 'design.dart';

bool get supportsOfficialLogin =>
    !kIsWeb &&
    const {TargetPlatform.windows, TargetPlatform.android, TargetPlatform.iOS}
        .contains(defaultTargetPlatform);

const officialDesktopUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';

InAppWebViewSettings officialLoginSettings({TargetPlatform? platform}) {
  final desktopOnIos =
      (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;
  return InAppWebViewSettings(
    incognito: true,
    userAgent: desktopOnIos ? officialDesktopUserAgent : null,
    preferredContentMode: desktopOnIos
        ? UserPreferredContentMode.DESKTOP
        : UserPreferredContentMode.RECOMMENDED,
    javaScriptEnabled: true,
    useShouldOverrideUrlLoading: true,
    isInspectable: false,
    allowFileAccess: false,
    allowContentAccess: false,
    saveFormData: false,
    supportMultipleWindows: false,
  );
}

bool isOfficialLoginUrl(Uri? url, {Community community = Community.miyoushe}) =>
    url != null &&
    url.scheme == 'https' &&
    (switch (community) {
      Community.miyoushe => const ['mihoyo.com', 'miyoushe.com'],
      Community.kuro => const ['kurobbs.com', 'kurogame.com'],
      Community.taygedo => const ['tajiduo.com', 'wanmei.com', 'laohu.com'],
    })
        .any((domain) => url.host == domain || url.host.endsWith('.$domain'));

class OfficialLoginPage extends StatefulWidget {
  const OfficialLoginPage(this.state,
      {super.key, this.community = Community.miyoushe});
  final AppState state;
  final Community community;
  @override
  State<OfficialLoginPage> createState() => _OfficialLoginPageState();
}

class _OfficialLoginPageState extends State<OfficialLoginPage> {
  InAppWebViewController? controller;
  final String loginNonce = newCommunityDeviceId();
  String? kuroCredential;
  late String host = Uri.parse(startUrl).host;
  String get startUrl => switch (widget.community) {
        Community.miyoushe => 'https://user.mihoyo.com/',
        Community.kuro => 'https://www.kurobbs.com/mc/',
        Community.taygedo => 'https://www.tajiduo.com/bbs/index.html#/home',
      };
  String? error;
  bool saving = false;
  double progress = 0;
  @override
  void dispose() {
    kuroCredential = null;
    super.dispose();
  }

  Future<void> connect() async {
    if (controller == null || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (widget.community != Community.miyoushe) {
        final String credential;
        if (widget.community == Community.kuro) {
          if (kuroCredential == null) {
            throw const MiyousheException(ApiFailure.credentials,
                '请在下方官方页面重新完成短信登录，以取得游戏数据会话；仅网页登录状态不能连接体力接口。');
          }
          credential = kuroCredential!;
        } else {
          credential = await readCommunityLogin(controller!, widget.community);
        }
        await widget.state.connect(credential, community: widget.community);
        if (mounted) Navigator.pop(context, true);
        return;
      }
      final session = await readSessionCookies(controller!);
      const allowed = {
        'account_id',
        'account_id_v2',
        'account_mid_v2',
        'cookie_token',
        'cookie_token_v2',
        'ltuid',
        'ltuid_v2',
        'ltoken',
        'ltoken_v2',
        'ltmid_v2',
        'mi18nLang'
      };
      final values = Map<String, String>.fromEntries(
          session.entries.where((entry) => allowed.contains(entry.key)));
      final cookie =
          values.entries.map((e) => '${e.key}=${e.value}').join('; ');
      if (values.isEmpty) {
        throw const MiyousheException(
            ApiFailure.credentials, '尚未检测到登录状态，请先在官方页面完成登录。');
      }
      await widget.state.connect(cookie);
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = failure is MiyousheException
              ? failure.message
              : '连接未完成，请检查网络和本机安全存储后重试。';
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                '${widget.community == Community.miyoushe ? '米哈游' : widget.community.title}官方登录',
                style: const TextStyle(fontSize: 16)),
            Text(host,
                style:
                    TextStyle(fontSize: 11, color: context.palette.secondary))
          ]),
          actions: [
            TextButton(
                onPressed: saving ? null : connect,
                child: Text(saving ? '正在连接…' : '完成登录并连接')),
            const SizedBox(width: 16),
          ],
        ),
        body: Column(children: [
          if (progress < 1) LinearProgressIndicator(value: progress),
          Container(
            width: double.infinity,
            color: context.palette.surface,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text(
                error ??
                    (widget.community == Community.kuro
                        ? kuroCredential == null
                            ? '请使用下方官方短信登录。完成后点击右上角连接；手机号和验证码由官方页面处理。'
                            : '已取得库街区游戏登录会话，请点击右上角连接。'
                        : '在下方官方页面登录，完成后点击右上角连接。密码由官方页面处理。'),
                style: TextStyle(
                    fontSize: 12,
                    color: error == null
                        ? context.palette.secondary
                        : context.palette.error)),
          ),
          Expanded(
              child: InAppWebView(
            initialUserScripts: widget.community == Community.kuro
                ? UnmodifiableListView([
                    UserScript(
                        source: kuroAppLoginScript(loginNonce),
                        injectionTime:
                            UserScriptInjectionTime.AT_DOCUMENT_START,
                        forMainFrameOnly: true)
                  ])
                : null,
            initialUrlRequest: URLRequest(url: WebUri(startUrl)),
            initialSettings: officialLoginSettings(),
            onWebViewCreated: (value) {
              controller = value;
              if (widget.community == Community.kuro) {
                value.addJavaScriptHandler(
                    handlerName: 'qiyouKuroAppSession',
                    callback: (args) async {
                      if (!mounted || args.length != 1) return;
                      final current = await value.getUrl();
                      if (current?.scheme != 'https' ||
                          current?.host != 'www.kurobbs.com') {
                        return;
                      }
                      try {
                        final credential =
                            kuroAppLoginCredential(args.single, loginNonce);
                        if (mounted && credential != null) {
                          setState(() {
                            kuroCredential = credential;
                            error = null;
                          });
                        }
                      } on MiyousheException catch (failure) {
                        if (mounted) setState(() => error = failure.message);
                      }
                    });
              }
            },
            onProgressChanged: (_, value) {
              if (mounted) setState(() => progress = value / 100);
            },
            onLoadStart: (_, url) {
              if (mounted &&
                  isOfficialLoginUrl(url, community: widget.community)) {
                setState(() => host = url!.host);
              }
            },
            shouldOverrideUrlLoading: (_, action) async =>
                action.isForMainFrame &&
                        !isOfficialLoginUrl(action.request.url,
                            community: widget.community)
                    ? NavigationActionPolicy.CANCEL
                    : NavigationActionPolicy.ALLOW,
            onReceivedError: (_, request, failure) {
              if (request.isForMainFrame == true && mounted) {
                setState(() => error = '官方登录页面加载失败，请检查网络后重新进入。');
              }
            },
          )),
        ]),
      ));
}
