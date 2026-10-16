// Anonymous official-browser session probe. Never reads the account store.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:qiyou/data/record_browser_session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _SessionProbe()));
}

class _SessionProbe extends StatefulWidget {
  const _SessionProbe();
  @override
  State<_SessionProbe> createState() => _SessionProbeState();
}

class _SessionProbeState extends State<_SessionProbe> {
  bool finished = false, checking = false;
  late Timer deadline;

  @override
  void initState() {
    super.initState();
    deadline =
        Timer(const Duration(seconds: 40), () => finish(false, false, false));
  }

  Future<void> finish(bool fp, bool id, bool ua) async {
    if (finished) return;
    finished = true;
    deadline.cancel();
    final path = Platform.environment['QIYOU_RECORD_SESSION_REPORT'];
    if (path != null) {
      await File(path).writeAsString(jsonEncode({
        'passed': fp && id && ua,
        'official_fp_received': fp,
        'official_device_id_received': id,
        'browser_user_agent_received': ua,
        'uses_user_account': false
      }));
    }
    exit(fp && id && ua ? 0 : 1);
  }

  Future<void> inspect(InAppWebViewController controller) async {
    if (checking || finished) return;
    checking = true;
    try {
      final session = await initializeRecordBrowserSession(controller, {},
          isActive: () => !finished);
      await finish(session.fingerprint.isNotEmpty, session.deviceId.isNotEmpty,
          session.userAgent.contains('Windows'));
    } catch (_) {
      await finish(false, false, false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
          body: InAppWebView(
        initialData: InAppWebViewInitialData(data: '<html></html>'),
        initialSettings: InAppWebViewSettings(
            incognito: true,
            isInspectable: false,
            allowFileAccess: false,
            allowContentAccess: false),
        onWebViewCreated: inspect,
      ));
}
