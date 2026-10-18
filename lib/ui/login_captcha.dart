import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../data/community_sms_login.dart';
import '../domain/models.dart';

String loginCaptchaHtml(LoginChallenge challenge, String nonce) {
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,1024}$').hasMatch(challenge.id) ||
      (!challenge.isV4 &&
          !RegExp(r'^[a-zA-Z0-9_-]{1,1024}$').hasMatch(challenge.challenge))) {
    throw const FormatException('Invalid official CAPTCHA configuration');
  }
  final config = challenge.isV4
      ? {'captchaId': challenge.id, 'product': 'popup', 'language': 'zho'}
      : {
          'gt': challenge.id,
          'challenge': challenge.challenge,
          'new_captcha': true,
          'offline': false,
          'https': true,
          'product': 'popup',
          'lang': 'zh-cn'
        };
  final script = challenge.isV4
      ? 'https://static.geetest.com/v4/gt4.js'
      : 'https://static.geetest.com/static/tools/gt.js';
  final initialize = challenge.isV4 ? 'initGeetest4' : 'initGeetest';
  return '''<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' https://*.geetest.com https://*.geevisit.com; connect-src https://*.geetest.com https://*.geevisit.com; img-src data: blob: https://*.geetest.com https://*.geevisit.com; style-src 'unsafe-inline' https://*.geetest.com https://*.geevisit.com; font-src https://*.geetest.com; frame-src https://*.geetest.com https://*.geevisit.com; worker-src blob: https://*.geetest.com; base-uri 'none'; form-action 'none'">
<style>html,body{margin:0;height:100%;background:#fff}body{display:flex;align-items:center;justify-content:center}#captcha{min-height:44px}</style></head>
<body><div id="captcha"></div><script>
function send(phase,result){const go=()=>window.flutter_inappwebview.callHandler('qiyouLoginCaptcha',{nonce:${jsonEncode(nonce)},phase:phase,result:result});
if(window.flutter_inappwebview&&window.flutter_inappwebview.callHandler)go();else window.addEventListener('flutterInAppWebViewPlatformReady',go,{once:true});}
const script=document.createElement('script');script.src=${jsonEncode(script)};
script.onerror=()=>send('error');script.onload=()=>{
  $initialize(${jsonEncode(config)},captcha=>{captcha.appendTo('#captcha');
    captcha.onReady(()=>send('ready'));captcha.onError(()=>send('error'));
    captcha.onSuccess(()=>send('success',captcha.getValidate()));
  });
};document.head.appendChild(script);
</script></body></html>''';
}

class LoginCaptchaPage extends StatefulWidget {
  const LoginCaptchaPage(this.challenge, {super.key});
  final LoginChallenge challenge;
  @override
  State<LoginCaptchaPage> createState() => _LoginCaptchaPageState();
}

class _LoginCaptchaPageState extends State<LoginCaptchaPage> {
  late final String nonce =
      List.generate(16, (_) => Random.secure().nextInt(256))
          .map((n) => n.toRadixString(16).padLeft(2, '0'))
          .join();
  Timer? timer;
  String? error;
  bool ready = false, finished = false;
  @override
  void initState() {
    super.initState();
    timer = Timer(const Duration(seconds: 30), () {
      if (mounted && !ready) setState(() => error = '验证码加载超时，请返回后重新获取。');
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('完成安全验证')),
        body: SafeArea(
            child: Column(children: [
          const Padding(
              padding: EdgeInsets.all(20),
              child: Text('请手动完成官方要求的人机验证，之后继续发送短信或登录。此页面不接收手机号、短信验证码或账号凭据。')),
          if (!ready && error == null) const LinearProgressIndicator(),
          if (error != null)
            Padding(padding: const EdgeInsets.all(20), child: Text(error!)),
          Expanded(
              child: InAppWebView(
            initialData: InAppWebViewInitialData(
                data: loginCaptchaHtml(widget.challenge, nonce)),
            initialSettings: InAppWebViewSettings(
                incognito: true,
                isInspectable: false,
                useShouldOverrideUrlLoading: true,
                allowFileAccess: false,
                allowContentAccess: false,
                supportMultipleWindows: false),
            shouldOverrideUrlLoading: (_, action) async =>
                action.isForMainFrame &&
                        action.request.url?.toString() != 'about:blank'
                    ? NavigationActionPolicy.CANCEL
                    : NavigationActionPolicy.ALLOW,
            onWebViewCreated: (controller) => controller.addJavaScriptHandler(
                handlerName: 'qiyouLoginCaptcha',
                callback: (args) {
                  if (!mounted || finished || args.length != 1) return;
                  final data = object(args.single);
                  if (data['nonce'] != nonce) return;
                  if (data['phase'] == 'ready') {
                    timer?.cancel();
                    setState(() => ready = true);
                  }
                  if (data['phase'] == 'error') {
                    timer?.cancel();
                    setState(() => error = '官方验证码未能加载，请返回后重试。');
                  }
                  if (data['phase'] == 'success') {
                    try {
                      final proof = widget.challenge.validate(data['result']);
                      finished = true;
                      Navigator.pop(context, proof);
                    } catch (_) {
                      setState(() => error = '验证结果无效，请返回重试。');
                    }
                  }
                }),
          )),
        ])),
      );
}
