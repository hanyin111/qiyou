import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../app_state.dart';
import '../data/miyoushe_client.dart';
import '../data/login_session.dart';
import 'design.dart';

bool get supportsOfficialLogin =>
    !kIsWeb &&
    const {TargetPlatform.windows, TargetPlatform.android, TargetPlatform.iOS}
        .contains(defaultTargetPlatform);

bool isOfficialLoginUrl(Uri? url) =>
    url != null &&
    url.scheme == 'https' &&
    const ['mihoyo.com', 'miyoushe.com']
        .any((domain) => url.host == domain || url.host.endsWith('.$domain'));

class OfficialLoginPage extends StatefulWidget {
  const OfficialLoginPage(this.state, {super.key});
  final AppState state;
  @override
  State<OfficialLoginPage> createState() => _OfficialLoginPageState();
}

class _OfficialLoginPageState extends State<OfficialLoginPage> {
  InAppWebViewController? controller;
  String host = 'user.mihoyo.com';
  String? error;
  bool saving = false;
  double progress = 0;

  Future<void> connect() async {
    if (controller == null || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
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
            const Text('米哈游官方登录', style: TextStyle(fontSize: 16)),
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
            child: Text(error ?? '在下方官方页面登录，完成后点击右上角连接。密码由官方页面处理。',
                style: TextStyle(
                    fontSize: 12,
                    color: error == null
                        ? context.palette.secondary
                        : context.palette.error)),
          ),
          Expanded(
              child: InAppWebView(
            initialUrlRequest:
                URLRequest(url: WebUri('https://user.mihoyo.com/')),
            initialSettings: InAppWebViewSettings(
              incognito: true,
              javaScriptEnabled: true,
              useShouldOverrideUrlLoading: true,
              isInspectable: false,
              allowFileAccess: false,
              allowContentAccess: false,
              saveFormData: false,
              supportMultipleWindows: false,
            ),
            onWebViewCreated: (value) => controller = value,
            onProgressChanged: (_, value) {
              if (mounted) setState(() => progress = value / 100);
            },
            onLoadStart: (_, url) {
              if (mounted && isOfficialLoginUrl(url)) {
                setState(() => host = url!.host);
              }
            },
            shouldOverrideUrlLoading: (_, action) async =>
                action.isForMainFrame && !isOfficialLoginUrl(action.request.url)
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
