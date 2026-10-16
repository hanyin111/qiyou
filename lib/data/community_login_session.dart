import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../domain/models.dart';
import 'community_http.dart';
import 'miyoushe_client.dart';
import 'login_session.dart';

// Read only the official community session keys, after the user explicitly
// presses Connect. Never inspect login forms, SMS codes, or password requests.
String communitySessionScript(Community community) {
  final (host, key) = switch (community) {
    Community.kuro => ('www.kurobbs.com', 'auth_token'),
    Community.taygedo => ('www.tajiduo.com', 'token'),
    _ => throw ArgumentError('Use the MiYouShe Cookie session reader'),
  };
  return '''(() => {
    if (location.protocol !== 'https:' || location.hostname !== '$host') return null;
    return {token: localStorage.getItem('$key'), 'user-agent': navigator.userAgent
      ${community == Community.kuro ? ", devcode: localStorage.getItem('dc'), did: localStorage.getItem('dc')" : ''}};
  })()''';
}

String communityLoginCredential(Community community, Map<String, dynamic> data,
    {Map<String, String> apiCookies = const {}}) {
  final values = {...data};
  if (community == Community.kuro &&
      (data['did'] is! String || (data['did'] as String).isEmpty)) {
    throw const MiyousheException(
        ApiFailure.credentials, '库街区官方登录设备尚未就绪，请等待页面加载完成后重试。');
  }
  if (community == Community.taygedo && apiCookies.isNotEmpty) {
    // Cookies come only from the current private browser and only for the
    // official API origin. Never forward identity-provider cookies.
    values['cookie'] = apiCookies.entries
        .where((entry) =>
            RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(entry.key) &&
            entry.value.isNotEmpty &&
            !RegExp(r'[;\r\n\x00]').hasMatch(entry.value))
        .map((e) => '${e.key}=${e.value}')
        .join('; ');
  }
  return jsonEncode(communityCredential(jsonEncode(values),
      allowCookie: community == Community.taygedo));
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
  final apiCookies = community == Community.taygedo
      ? await readSessionCookies(controller, urls: const [
          'https://bbs-api.tajiduo.com/usercenter/wapi/getUserFullInfo'
        ])
      : <String, String>{};
  if ((data['token'] is! String || (data['token'] as String).isEmpty) &&
      apiCookies.isEmpty) {
    throw MiyousheException(
        ApiFailure.credentials, '尚未检测到${community.title}登录状态，请在页面右上角完成登录后重试。');
  }
  return communityLoginCredential(community, data, apiCookies: apiCookies);
}
