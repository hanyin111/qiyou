import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../domain/models.dart';
import 'community_http.dart';
import 'miyoushe_client.dart';

// Read only the documented community session key, after the user explicitly
// presses Connect. Never inspect login forms, SMS codes, or password requests.
String communitySessionScript(Community community) {
  final (host, key) = switch (community) {
    Community.kuro => ('www.kurobbs.com', 'auth_token'),
    Community.taygedo => ('www.tajiduo.com', 'token'),
    _ => throw ArgumentError('Use the MiYouShe Cookie session reader'),
  };
  return '''(() => {
    if (location.protocol !== 'https:' || location.hostname !== '$host') return null;
    return {token: localStorage.getItem('$key'), 'user-agent': navigator.userAgent};
  })()''';
}

Future<String> readCommunityLogin(
    InAppWebViewController controller, Community community) async {
  final current = await controller.getUrl();
  final expected =
      community == Community.kuro ? 'www.kurobbs.com' : 'www.tajiduo.com';
  if (current?.scheme != 'https' || current?.host != expected) {
    throw MiyousheException(
        ApiFailure.credentials, '请完成官方登录并返回${community.title}社区页面，再点击连接。');
  }
  final result = await controller.evaluateJavascript(
      source: communitySessionScript(community));
  final data = object(result);
  final token = data['token'];
  if (token is! String || token.isEmpty) {
    throw MiyousheException(
        ApiFailure.credentials, '尚未检测到${community.title}登录状态，请在页面右上角完成登录后重试。');
  }
  return jsonEncode(communityCredential(jsonEncode(data)));
}
