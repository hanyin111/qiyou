// Native smoke check with GeeTest's public demo challenge, no user account.
// It only loads the widget and checks the bridge; it never solves a CAPTCHA.
// flutter build windows --release -t test/native_captcha_probe.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:qiyou/data/record_verification.dart';
import 'package:qiyou/domain/models.dart';
import 'package:qiyou/ui/note_verification.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _CaptchaProbe()));
}

class _CaptchaProbe extends StatefulWidget {
  const _CaptchaProbe();
  @override
  State<_CaptchaProbe> createState() => _CaptchaProbeState();
}

class _CaptchaProbeState extends State<_CaptchaProbe> {
  RecordVerification? verification;
  bool finished = false;
  int consoleErrors = 0;
  late final Timer timeout;

  @override
  void initState() {
    super.initState();
    timeout =
        Timer(const Duration(seconds: 40), () => finish(false, 'timeout'));
    initialize();
  }

  Future<void> initialize() async {
    try {
      final result = await http
          .get(Uri.https('www.geetest.com', '/demo/gt/register-slide'))
          .timeout(const Duration(seconds: 15));
      final data = object(jsonDecode(result.body));
      if (result.statusCode != 200 ||
          !RecordVerification.validToken(data['gt']) ||
          !RecordVerification.validToken(data['challenge'])) {
        return finish(false, 'demo_unavailable');
      }
      setState(() => verification = RecordVerification(
          gt: data['gt'],
          challenge: data['challenge'],
          accountId: 'demo',
          deviceId: 'demo',
          roleKey: 'demo',
          issuedAt: DateTime.now()));
    } catch (_) {
      await finish(false, 'demo_unavailable');
    }
  }

  Future<void> finish(bool passed, String status) async {
    if (finished) return;
    finished = true;
    timeout.cancel();
    final target = Platform.environment['QIYOU_CAPTCHA_REPORT'];
    if (target != null) {
      await File(target).writeAsString(jsonEncode({
        'passed': passed,
        'status': status,
        'console_errors': consoleErrors,
        'uses_user_account': false,
        'captcha_solved': false
      }));
    }
    exit(passed ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: verification == null
          ? const Center(child: CircularProgressIndicator())
          : InAppWebView(
              initialData: InAppWebViewInitialData(
                  data: noteVerificationHtml(verification!, 'native-probe')),
              initialSettings: InAppWebViewSettings(
                  incognito: true,
                  isInspectable: false,
                  allowFileAccess: false,
                  allowContentAccess: false,
                  saveFormData: false,
                  useShouldOverrideUrlLoading: true),
              shouldOverrideUrlLoading: (_, action) async =>
                  action.isForMainFrame &&
                          action.request.url?.toString() != 'about:blank'
                      ? NavigationActionPolicy.CANCEL
                      : NavigationActionPolicy.ALLOW,
              onConsoleMessage: (_, message) {
                if (message.messageLevel == ConsoleMessageLevel.ERROR) {
                  consoleErrors++;
                }
              },
              onWebViewCreated: (controller) {
                controller.addJavaScriptHandler(
                    handlerName: 'qiyouCaptcha',
                    callback: (args) async {
                      final data = args.isEmpty
                          ? <String, dynamic>{}
                          : object(args.first);
                      if (data['nonce'] != 'native-probe') return;
                      if (data['phase'] == 'ready') {
                        await finish(true, 'widget_ready_and_bridge_received');
                      }
                      if (data['phase'] == 'error') {
                        await finish(false, 'widget_error');
                      }
                    });
              }));
}
