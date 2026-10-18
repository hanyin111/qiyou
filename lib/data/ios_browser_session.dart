import 'package:flutter/services.dart';
import 'community_http.dart' show newCommunityDeviceId;

const _channel = MethodChannel('app.qiyou/browser-session');

// Bind the native cookie read to this exact WebView. The plugin's global iOS
// CookieManager reads WKWebsiteDataStore.default(), not its incognito store.
Future<Map<String, String>> readIosBrowserCookies({
  required Future<dynamic> Function(String source) evaluate,
  required List<String> urls,
}) async {
  final nonce = newCommunityDeviceId();
  final bound = await evaluate('''(() => {
    if (location.protocol !== 'https:') return false;
    Object.defineProperty(window, '__qiyouSessionReadNonce',
      {value: '$nonce', configurable: true});
    return true;
  })()''');
  if (bound != true) throw StateError('Official browser session unavailable');
  try {
    final result = await _channel.invokeMapMethod<String, String>(
        'readCookies', {'nonce': nonce, 'urls': urls}).timeout(
      const Duration(seconds: 8),
    );
    if (result == null) {
      throw StateError('Official browser session unavailable');
    }
    return Map<String, String>.from(result);
  } finally {
    try {
      await evaluate('''(() => {
        if (window.__qiyouSessionReadNonce === '$nonce')
          delete window.__qiyouSessionReadNonce;
      })()''');
    } catch (_) {
      // A navigation or closed page must not mask the original result.
    }
  }
}
