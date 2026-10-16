import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'login_session.dart';
import 'miyoushe_client.dart';

class RecordBrowserSession {
  const RecordBrowserSession._(
      this.deviceId, this.fingerprint, this.userAgent, this.cookies);
  final String deviceId, fingerprint, userAgent;
  final Map<String, String> cookies;
  static const cookieNames = {
    'DEVICEFP',
    'DEVICEFP_SEED_ID',
    'DEVICEFP_SEED_TIME',
    '_MHYUUID'
  };

  static Map<String, String> seedCookies(String cookie) => {
        for (final entry in MiyousheClient.parseCookie(cookie).entries)
          if (cookieNames.contains(entry.key) &&
              RegExp(r'^[a-zA-Z0-9._-]{1,256}$').hasMatch(entry.value))
            entry.key: entry.value
      };

  static RecordBrowserSession? fromCookies(
      Map<String, String> values, Object? userAgent) {
    final fp = values['DEVICEFP'] ?? '';
    final id = values['_MHYUUID'] ?? '';
    if (!RegExp(r'^[a-zA-Z0-9_-]{6,128}$').hasMatch(fp) ||
        RegExp(r'^0+$').hasMatch(fp) ||
        !RegExp(r'^[a-zA-Z0-9_-]{8,128}$').hasMatch(id) ||
        userAgent is! String ||
        userAgent.isEmpty ||
        userAgent.length > 1024 ||
        RegExp(r'[\r\n\x00]').hasMatch(userAgent)) {
      return null;
    }
    return RecordBrowserSession._(
        id,
        fp,
        userAgent,
        Map.unmodifiable({
          for (final entry in values.entries)
            if (cookieNames.contains(entry.key) &&
                RegExp(r'^[a-zA-Z0-9._-]{1,256}$').hasMatch(entry.value))
              entry.key: entry.value
        }));
  }
}

// Bootstrap the public official page anonymously. Never seed auth cookies here.
Future<RecordBrowserSession> initializeRecordBrowserSession(
    InAppWebViewController controller, Map<String, String> seeds,
    {required bool Function() isActive}) async {
  const url = 'https://www.miyoushe.com/ys/';
  for (final cookie in seeds.entries) {
    if (!RecordBrowserSession.cookieNames.contains(cookie.key)) continue;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await controller.callDevToolsProtocolMethod(
          methodName: 'Network.setCookie',
          parameters: {
            'name': cookie.key,
            'value': cookie.value,
            'domain': '.miyoushe.com',
            'path': '/',
            'secure': true,
            'httpOnly': false
          });
    } else {
      await CookieManager.instance().setCookie(
          url: WebUri(url),
          name: cookie.key,
          value: cookie.value,
          domain: '.miyoushe.com',
          isSecure: true,
          isHttpOnly: false);
    }
  }
  await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  for (var i = 0; i < 55 && isActive(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!isActive()) break;
    try {
      final current = await controller.getUrl();
      if (current?.scheme != 'https' ||
          !(current!.host == 'www.miyoushe.com' ||
              current.host == 'm.miyoushe.com')) {
        continue;
      }
      final cookies = await readSessionCookies(controller,
          urls: [url, 'https://m.miyoushe.com/']);
      final ua =
          await controller.evaluateJavascript(source: 'navigator.userAgent');
      final session = RecordBrowserSession.fromCookies(cookies, ua);
      if (session != null) return session;
    } catch (_) {
      // The page may still be navigating. Retry only this local session read.
    }
  }
  throw const MiyousheException(ApiFailure.network, '官方设备会话未能初始化，请检查网络后重试。',
      stage: ApiStage.verificationCreate);
}
