import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

const officialCookieOrigins = [
  'https://user.mihoyo.com/',
  'https://www.miyoushe.com/',
  'https://m.miyoushe.com/',
];

Future<Map<String, String>> readSessionCookies(
    InAppWebViewController controller,
    {List<String> urls = officialCookieOrigins}) async {
  final values = <String, String>{};
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    // Plugin 0.6's CookieManager ignores webViewController and uses a helper
    // WebView with the default profile. Read this actual private WebView instead.
    final response = await controller.callDevToolsProtocolMethod(
        methodName: 'Network.getCookies', parameters: {'urls': urls});
    if (response is! Map || response['cookies'] is! List) {
      throw StateError('Current browser session unavailable');
    }
    for (final cookie in response['cookies'] as List) {
      if (cookie is Map &&
          cookie['name'] is String &&
          cookie['value'] is String) {
        values[cookie['name'] as String] = cookie['value'] as String;
      }
    }
  } else {
    for (final url in urls) {
      final cookies = await CookieManager.instance()
          .getCookies(url: WebUri(url), webViewController: controller);
      for (final cookie in cookies) {
        values[cookie.name] = cookie.value;
      }
    }
  }
  return values;
}
