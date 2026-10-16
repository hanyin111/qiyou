// Anonymous browser protocol test. No account store, phone, OTP or real login.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:qiyou/data/kuro_login_session.dart';
import 'package:qiyou/domain/models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Probe()));
}

class Probe extends StatefulWidget {
  const Probe({super.key});
  @override
  State<Probe> createState() => ProbeState();
}

class ProbeState extends State<Probe> {
  bool checking = false, finished = false;
  late Timer deadline;
  final received = Completer<bool>();
  @override
  void initState() {
    super.initState();
    deadline = Timer(const Duration(seconds: 35), () => finish(false));
  }

  Future<void> finish(bool passed) async {
    if (finished) return;
    finished = true;
    deadline.cancel();
    final path = Platform.environment['QIYOU_KURO_LOGIN_REPORT'];
    if (path != null) {
      await File(path).writeAsString(jsonEncode({
        'passed': passed,
        'uses_user_account': false,
        'performs_login': false,
        'performs_sign_in': false,
        'synthetic_app_channel_and_session_bridge': passed,
      }));
    }
    exit(passed ? 0 : 1);
  }

  Future<void> inspect(InAppWebViewController c) async {
    if (checking) return;
    checking = true;
    try {
      // Only the synthetic XHR constructor is patched. No login request is sent.
      final flags = object(await c.evaluateJavascript(source: '''(() => {
        const original = window.XMLHttpRequest;
        let flags = {};
        class SyntheticXHR extends EventTarget {
          constructor() { super(); this.headers={}; this.status=200; this.responseType='';
            this.responseText=JSON.stringify({code:200,data:{token:'synthetic-app-token'}}); }
          open(method,url) { this.url=url; }
          setRequestHeader(k,v) { this.headers[k.toLowerCase()]=v; }
          send(body) { flags={native_path:this.url==='https://api.kurobbs.com/user/sdkLogin',
            native_source:this.headers.source==='android', device_field:body.includes('&devCode=')};
            this.dispatchEvent(new Event('load')); }
        }
        window.XMLHttpRequest=SyntheticXHR;
        ${kuroAppLoginScript('synthetic-nonce')}
        const xhr=new XMLHttpRequest(); xhr.open('POST','https://api.kurobbs.com/user/sdkLoginForH5');
        xhr.setRequestHeader('source','h5'); xhr.send('placeholder=synthetic');
        window.XMLHttpRequest=original;
        return flags;
      })()'''));
      final bridged = await received.future.timeout(const Duration(seconds: 8));
      await finish(bridged &&
          flags['native_path'] == true &&
          flags['native_source'] == true &&
          flags['device_field'] == true);
    } catch (_) {
      await finish(false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
          body: InAppWebView(
        initialUrlRequest:
            URLRequest(url: WebUri('https://www.kurobbs.com/mc/')),
        initialSettings: InAppWebViewSettings(
            incognito: true,
            isInspectable: false,
            allowFileAccess: false,
            allowContentAccess: false),
        onWebViewCreated: (c) => c.addJavaScriptHandler(
            handlerName: 'qiyouKuroAppSession',
            callback: (args) {
              if (args.length == 1 && !received.isCompleted) {
                final raw =
                    kuroAppLoginCredential(args.single, 'synthetic-nonce');
                received.complete(raw != null &&
                    object(jsonDecode(raw))['token'] == 'synthetic-app-token');
              }
            }),
        onLoadStop: (c, _) => inspect(c),
      ));
}
