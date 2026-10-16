import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../app_state.dart';
import '../data/miyoushe_client.dart';
import '../data/record_verification.dart';
import '../data/record_browser_session.dart';
import '../domain/models.dart';
import 'official_login.dart';

// A local host page for the official GeeTest widget. It contains no account
// cookies, UID, password, or API client bridge. Proofs are checked by MiYouShe.
String noteVerificationHtml(RecordVerification verification, String nonce) {
  final config = jsonEncode({
    'gt': verification.gt,
    'challenge': verification.challenge,
    'new_captcha': verification.newCaptcha,
    'offline': false,
    'https': true,
    'product': 'popup',
    'lang': 'zh-cn',
    'width': '300px',
    'timeout': 20000
  });
  return '''<!doctype html><html lang="zh-CN"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' https://*.geetest.com https://*.geevisit.com; connect-src https://*.geetest.com https://*.geevisit.com; img-src data: blob: https://*.geetest.com https://*.geevisit.com; style-src 'unsafe-inline' https://*.geetest.com https://*.geevisit.com; font-src https://*.geetest.com; frame-src https://*.geetest.com https://*.geevisit.com; base-uri 'none'; form-action 'none'">
<style>html,body{height:100%;margin:0;background:#fff}body{display:flex;align-items:center;justify-content:center}#captcha{min-height:44px}</style>
</head><body><div id="captcha"></div><script>
(function() {
  const nonce = ${jsonEncode(nonce)};
  function send(phase, result) {
    const deliver = function() {
      window.flutter_inappwebview.callHandler('qiyouCaptcha', {nonce:nonce,phase:phase,result:result});
    };
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) deliver();
    else window.addEventListener('flutterInAppWebViewPlatformReady', deliver, {once:true});
  }
  const script = document.createElement('script');
  script.src = 'https://static.geetest.com/static/tools/gt.js';
  script.onerror = function() { send('error'); };
  script.onload = function() {
    if (typeof initGeetest !== 'function') { send('error'); return; }
    initGeetest($config, function(captcha) {
      captcha.appendTo('#captcha');
      captcha.onReady(function() { send('ready'); });
      captcha.onSuccess(function() {
        const result = captcha.getValidate();
        if (result) send('success', result);
      });
      captcha.onError(function() { send('error'); });
    });
  };
  document.head.appendChild(script);
})();
</script></body></html>''';
}

Future<void> openNoteVerification(
    BuildContext context, AppState state, GameEntry entry) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NoteVerificationPage(state, entry)));
}

class NoteVerificationPage extends StatefulWidget {
  const NoteVerificationPage(this.state, this.entry, {super.key});
  final AppState state;
  final GameEntry entry;
  @override
  State<NoteVerificationPage> createState() => _NoteVerificationPageState();
}

class _NoteVerificationPageState extends State<NoteVerificationPage> {
  RecordVerification? verification;
  String? error;
  String nonce = '';
  bool loading = false,
      ready = false,
      submitting = false,
      complete = false,
      preparing = false;
  String progressMessage = '正在初始化官方设备会话…';
  Timer? timeout;

  Future<void> start() async {
    if (loading || submitting) return;
    timeout?.cancel();
    setState(() {
      loading = true;
      preparing = true;
      progressMessage = '正在初始化官方设备会话…';
      ready = false;
      error = null;
      verification = null;
      nonce = List.generate(16, (_) => Random.secure().nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
    });
  }

  Future<void> prepare(
      InAppWebViewController controller, String attempt) async {
    bool active() => mounted && nonce == attempt;
    try {
      final account = widget.state.accounts
          .firstWhere((a) => a.id == widget.entry.accountId);
      final session = await initializeRecordBrowserSession(
          controller, RecordBrowserSession.seedCookies(account.cookie),
          isActive: active);
      if (!active()) return;
      await widget.state.installRecordBrowserSession(widget.entry, session);
      if (!active()) return;
      setState(() => progressMessage = '正在使用官方设备会话查询便笺…');
      try {
        await widget.state.refreshNote(widget.entry);
        if (active()) setState(() => complete = true);
        return;
      } on MiyousheException catch (failure) {
        if (failure.kind != ApiFailure.verification) rethrow;
      }
      if (!active()) return;
      setState(() => progressMessage = '正在获取验证码…');
      final value = await widget.state.createNoteVerification(widget.entry);
      if (!active()) return;
      controller.addJavaScriptHandler(
          handlerName: 'qiyouCaptcha',
          callback: (args) => handleCaptcha(args, attempt));
      setState(() {
        verification = value;
        preparing = false;
      });
      await controller.loadData(data: noteVerificationHtml(value, nonce));
      timeout = Timer(const Duration(seconds: 35), () {
        if (mounted && !ready && !submitting && !complete) {
          setState(() => error = '验证码加载超时，请检查网络后重新加载。');
        }
      });
    } on MiyousheException catch (failure) {
      if (active()) setState(() => error = failure.message);
    } catch (_) {
      if (active()) setState(() => error = '未能初始化验证会话，请稍后重试。');
    } finally {
      if (active()) {
        setState(() {
          loading = false;
          preparing = false;
        });
      }
    }
  }

  Future<void> handleCaptcha(List<dynamic> args, String attempt) async {
    if (!mounted || attempt != nonce || args.length != 1 || complete) return;
    final data = object(args.single);
    if (data['nonce'] != nonce || submitting) return;
    switch (data['phase']) {
      case 'ready':
        timeout?.cancel();
        setState(() {
          ready = true;
          error = null;
        });
      case 'error':
        timeout?.cancel();
        setState(() => error = '极验组件未能加载，请检查网络后重新加载。');
      case 'success':
        final proof = RecordVerificationProof.fromData(data['result']);
        final active = verification;
        if (proof == null || active == null) return;
        timeout?.cancel();
        setState(() {
          submitting = true;
          error = null;
        });
        try {
          await widget.state
              .refreshNote(widget.entry, verification: active, proof: proof);
          if (mounted) setState(() => complete = true);
        } on MiyousheException {
          if (mounted) {
            setState(() => error = widget.entry.noteError ?? '验证未通过，请重新加载验证码。');
          }
        } catch (_) {
          if (mounted) setState(() => error = '查询未完成，请返回后重试。');
        } finally {
          if (mounted) setState(() => submitting = false);
        }
    }
  }

  @override
  void dispose() {
    timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !submitting,
      child: Scaffold(
          appBar: AppBar(
              title: Text('${widget.entry.role.game.shortTitle} · 安全验证')),
          body: SingleChildScrollView(
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(complete ? '体力已同步' : '完成本次查询的安全验证',
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 12),
                                Text(
                                    complete
                                        ? '已从米游社读取最新便笺，可以返回游戏页。'
                                        : '先由米游社官方网页初始化设备会话，必要时显示极验验证码。两者会处理设备与网络信息以识别人机行为；账号凭证不会提供给验证码页面。',
                                    textAlign: TextAlign.center),
                                if ((preparing || verification != null) &&
                                    !complete &&
                                    error == null)
                                  SizedBox(
                                      height: 440,
                                      child: IgnorePointer(
                                          ignoring: preparing,
                                          child: Opacity(
                                              opacity: preparing ? 0 : 1,
                                              child: InAppWebView(
                                                key: ValueKey(nonce),
                                                initialData:
                                                    InAppWebViewInitialData(
                                                        data: '<html></html>'),
                                                initialSettings:
                                                    InAppWebViewSettings(
                                                        incognito: true,
                                                        isInspectable: false,
                                                        useShouldOverrideUrlLoading:
                                                            true,
                                                        allowFileAccess: false,
                                                        allowContentAccess:
                                                            false,
                                                        saveFormData: false),
                                                onWebViewCreated:
                                                    (controller) => prepare(
                                                        controller, nonce),
                                                shouldOverrideUrlLoading: (_,
                                                        action) async =>
                                                    action.isForMainFrame &&
                                                            action.request.url
                                                                    ?.toString() !=
                                                                'about:blank' &&
                                                            !(preparing &&
                                                                isOfficialLoginUrl(
                                                                    action
                                                                        .request
                                                                        .url))
                                                        ? NavigationActionPolicy
                                                            .CANCEL
                                                        : NavigationActionPolicy
                                                            .ALLOW,
                                              )))),
                                if (loading ||
                                    (verification != null &&
                                        !ready &&
                                        error == null) ||
                                    submitting) ...[
                                  const SizedBox(height: 16),
                                  const LinearProgressIndicator(),
                                  const SizedBox(height: 12),
                                  Text(submitting
                                      ? '正在确认验证结果并查询体力…'
                                      : loading
                                          ? progressMessage
                                          : '正在加载验证码…'),
                                ],
                                if (error != null) ...[
                                  const SizedBox(height: 20),
                                  Text(error!,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error)),
                                ],
                                const SizedBox(height: 24),
                                if (complete)
                                  FilledButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('返回游戏页'))
                                else if (!loading &&
                                    !submitting &&
                                    (verification == null || error != null))
                                  FilledButton(
                                      onPressed: start,
                                      child: Text(
                                          error == null ? '开始验证' : '重新加载')),
                              ])))))));
}
