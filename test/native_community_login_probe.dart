// Anonymous Windows WebView smoke test. Does not read secure account storage.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:qiyou/data/community_login_session.dart';
import 'package:qiyou/domain/models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: CommunityLoginProbe()));
}

class CommunityLoginProbe extends StatefulWidget {
  const CommunityLoginProbe({super.key});
  @override
  State<CommunityLoginProbe> createState() => _CommunityLoginProbeState();
}

class _CommunityLoginProbeState extends State<CommunityLoginProbe> {
  final result = <String, bool>{};
  InAppWebViewController? controller;
  Timer? deadline;
  bool checking = false, finished = false;
  Community community = Community.kuro;
  String get url => community == Community.kuro
      ? 'https://www.kurobbs.com/mc/'
      : 'https://www.tajiduo.com/bbs/index.html#/home';

  @override
  void initState() {
    super.initState();
    deadline = Timer(const Duration(seconds: 55), finish);
  }

  Future<void> finish() async {
    if (finished) return;
    finished = true;
    deadline?.cancel();
    final passed = result['kuro'] == true &&
        result['taygedo'] == true &&
        result['private_httponly_cookie'] == true;
    final path = Platform.environment['QIYOU_COMMUNITY_LOGIN_REPORT'];
    if (path != null) {
      await File(path).writeAsString(jsonEncode({
        'version': '0.1.7',
        'passed': passed,
        'official_page_and_session_reader': result,
        'uses_user_account': false,
        'performs_sign_in': false,
      }));
    }
    exit(passed ? 0 : 1);
  }

  Future<void> inspect(InAppWebViewController c) async {
    if (checking || finished) return;
    checking = true;
    try {
      final data = object(await c.evaluateJavascript(
          source: communitySessionScript(community)));
      // Only check browser execution and the known session-key result type.
      // Never output or store its value, even in this fresh private profile.
      result[community.name] =
          data['user-agent'] is String && data.containsKey('token');
      if (community == Community.kuro) {
        result['kuro'] = result['kuro'] == true &&
            data['did'] is String &&
            (data['did'] as String).isNotEmpty &&
            data['did'] == data['devcode'];
      } else {
        // Synthetic HttpOnly Cookie on the API origin, in this actual private
        // WebView. This reproduces a cookie-only login without using an account.
        await c.callDevToolsProtocolMethod(
            methodName: 'Network.setCookie',
            parameters: {
              'url': 'https://bbs-api.tajiduo.com/',
              'name': 'qiyou_probe',
              'value': 'synthetic-private-session',
              'httpOnly': true,
              'secure': true,
              'path': '/',
            });
        final credential =
            object(jsonDecode(await readCommunityLogin(c, Community.taygedo)));
        result['private_httponly_cookie'] = '${credential['cookie']}'
            .contains('qiyou_probe=synthetic-private-session');
        await c.callDevToolsProtocolMethod(
            methodName: 'Network.deleteCookies',
            parameters: {
              'url': 'https://bbs-api.tajiduo.com/',
              'name': 'qiyou_probe',
            });
      }
    } catch (_) {
      result[community.name] = false;
    }
    if (community == Community.kuro) {
      community = Community.taygedo;
      await c.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      checking = false;
    } else {
      await finish();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
          body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
            incognito: true,
            isInspectable: false,
            allowFileAccess: false,
            allowContentAccess: false,
            saveFormData: false),
        onWebViewCreated: (c) => controller = c,
        onLoadStop: (c, _) => inspect(c),
      ));
}
