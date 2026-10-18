import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../data/community_sms_login.dart';
import '../data/login_captcha_document.dart';

import '../domain/models.dart';

export '../data/login_captcha_document.dart' show loginCaptchaHtml;

class LoginCaptchaPage extends StatefulWidget {
  const LoginCaptchaPage(this.challenge, {super.key});
  final LoginChallenge challenge;
  @override
  State<LoginCaptchaPage> createState() => _LoginCaptchaPageState();
}

class _LoginCaptchaPageState extends State<LoginCaptchaPage> {
  String nonce = List.generate(16, (_) => Random.secure().nextInt(256))
      .map((n) => n.toRadixString(16).padLeft(2, '0'))
      .join();
  Timer? timer;
  String? error;
  bool ready = false, finished = false;
  @override
  void initState() {
    super.initState();
    armTimeout();
  }

  void armTimeout() {
    timer?.cancel();
    timer = Timer(const Duration(seconds: 30), () {
      if (mounted && !ready && !finished) {
        setState(() => error = '验证码加载超时，请重新加载或返回重新获取。');
      }
    });
  }

  void retry() {
    setState(() {
      nonce = List.generate(16, (_) => Random.secure().nextInt(256))
          .map((n) => n.toRadixString(16).padLeft(2, '0'))
          .join();
      error = null;
      ready = false;
    });
    armTimeout();
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
            Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  Text(error!),
                  TextButton(onPressed: retry, child: const Text('重新加载')),
                ])),
          Expanded(
              child: InAppWebView(
            key: ValueKey(nonce),
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
            onWebViewCreated: (controller) async {
              final attempt = nonce;
              controller.addJavaScriptHandler(
                  handlerName: 'qiyouLoginCaptcha',
                  callback: (args) {
                    if (!mounted ||
                        finished ||
                        attempt != nonce ||
                        args.length != 1) {
                      return;
                    }
                    final data = object(args.single);
                    if (data['nonce'] != nonce || error != null) return;
                    if (data['phase'] == 'ready') {
                      timer?.cancel();
                      setState(() => ready = true);
                    }
                    if (data['phase'] == 'error') {
                      timer?.cancel();
                      final reason = switch (data['reason']) {
                        'timeout' => '验证码加载超时，请检查网络后重新加载。',
                        'resource' => '验证码资源未能加载，请检查网络后重试。',
                        'proof' => '验证结果不完整，请返回重新获取验证码。',
                        _ => '官方验证码未能初始化，请重新加载。'
                      };
                      setState(() => error = reason);
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
                  });
              // Install the callback before loading, as in notes verification.
              try {
                await controller.loadData(
                    data: loginCaptchaHtml(widget.challenge, attempt));
              } catch (_) {
                if (mounted && attempt == nonce) {
                  timer?.cancel();
                  setState(() => error = '验证页面未能打开，请重新加载。');
                }
              }
            },
            onReceivedError: (_, request, failure) {
              if (request.isForMainFrame == true && mounted && !finished) {
                timer?.cancel();
                setState(() => error = '验证页面加载失败，请重新加载。');
              }
            },
          )),
        ])),
      );
}
