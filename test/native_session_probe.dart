// Run as a separate native app, never against a user's actual browser cookies.
// flutter build windows --release -t test/native_session_probe.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:qiyou/data/device_bridge.dart';
import 'package:qiyou/data/login_session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _NativeProbe()));
}

class _NativeProbe extends StatefulWidget {
  const _NativeProbe();
  @override
  State<_NativeProbe> createState() => _NativeProbeState();
}

class _NativeProbeState extends State<_NativeProbe> {
  bool finished = false;
  late final Timer timeout;
  @override
  void initState() {
    super.initState();
    timeout = Timer(const Duration(seconds: 40),
        () => finish({'passed': false, 'error': 'timeout'}, 1));
  }

  Future<void> finish(Map<String, dynamic> report, int code) async {
    if (finished) return;
    finished = true;
    timeout.cancel();
    final target = Platform.environment['QIYOU_SMOKE_REPORT'];
    if (target != null) await File(target).writeAsString(jsonEncode(report));
    exit(code);
  }

  Future<void> probe(InAppWebViewController controller) async {
    try {
      const url = 'https://qiyou.invalid/';
      await controller.callDevToolsProtocolMethod(
          methodName: 'Network.setCookie',
          parameters: {
            'name': 'qiyou_native_probe',
            'value': 'synthetic-test-value',
            'url': url,
            'secure': true,
            'httpOnly': true,
          });
      final actual = await readSessionCookies(controller, urls: [url]);
      final global = await CookieManager.instance()
          .getCookies(url: WebUri(url), webViewController: controller);
      final privateSession =
          actual['qiyou_native_probe'] == 'synthetic-test-value';
      await controller.callDevToolsProtocolMethod(
          methodName: 'Network.deleteCookies',
          parameters: {'name': 'qiyou_native_probe', 'url': url});
      final cleared =
          (await readSessionCookies(controller, urls: [url])).isEmpty;
      final bridge = DeviceBridge();
      final original = await bridge.read();
      var storageRoundTrip = false;
      // Never overwrite or export existing user data, even temporarily.
      if (original == null) {
        try {
          await bridge.write('{"native_probe":true}');
          storageRoundTrip = await bridge.read() == '{"native_probe":true}';
        } finally {
          await bridge.delete();
        }
      }
      await finish({
        'passed':
            privateSession && cleared && (storageRoundTrip || original != null),
        'private_http_only_cookie_read': privateSession,
        'cookie_removed': cleared,
        'global_manager_missed_private_session': global.isEmpty,
        'secure_store_read': true,
        'secure_store_roundtrip': storageRoundTrip,
        'existing_store_untouched': original != null,
      }, privateSession && cleared ? 0 : 1);
    } catch (error) {
      await finish({'passed': false, 'error': error.runtimeType.toString()}, 1);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: InAppWebView(
          initialData: InAppWebViewInitialData(
              data: '<html><body>Native session test</body></html>'),
          initialSettings:
              InAppWebViewSettings(incognito: true, isInspectable: false),
          onWebViewCreated: probe));
}
