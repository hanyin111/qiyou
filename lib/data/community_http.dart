import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import 'miyoushe_client.dart';
import 'verification_diagnostics.dart'
    show safeVerificationReason, writeVerificationDiagnostic;

// One fixed official host per client. Never follow a credential-bearing redirect.
class CommunityHttp {
  CommunityHttp(this.community, this.host, {http.Client? transport})
      : transport = transport ?? http.Client();
  final Community community;
  final String host;
  final http.Client transport;
  Future<dynamic> request(String path, Map<String, String> headers,
      {Map<String, String>? form,
      Map<String, String>? query,
      Set<int> acceptedCodes = const {0}}) async {
    try {
      return await (() async {
        final request = http.Request(
            form == null ? 'GET' : 'POST', Uri.https(host, path, query))
          ..followRedirects = false
          ..headers.addAll({'accept': 'application/json', ...headers});
        if (form != null) request.bodyFields = form;
        final response = await transport.send(request);
        if (community == Community.taygedo && response.statusCode == 402) {
          throw const MiyousheException(
              ApiFailure.expired, '塔吉多会话已失效（HTTP 402），请检查社区续期凭据或导入有效会话。',
              code: 402);
        }
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw MiyousheException(
              ApiFailure.expired, '${community.title}登录失效，请重新连接。');
        }
        if (response.statusCode != 200) {
          throw MiyousheException(ApiFailure.network,
              '${community.title}暂时无法响应（HTTP ${response.statusCode}），请稍后重试。');
        }
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 2 * 1024 * 1024) {
            throw const FormatException();
          }
          bytes.addAll(chunk);
        }
        final json = object(jsonDecode(utf8.decode(bytes)));
        final code = number(json['code']);
        if (community == Community.kuro &&
            const {
              '/aki/roleBox/requestToken',
              '/aki/roleBox/akiBox/refreshData',
              '/gamer/widget/game3/getData',
            }.contains(path)) {
          // Explicit developer opt-in only. No header values, role IDs, raw
          // responses or credentials enter the local diagnostic.
          await writeVerificationDiagnostic({
            'version': '0.1.16',
            'community': 'kuro',
            'stage': path,
            'code': code,
            'has_community_token': headers.containsKey('token'),
            'has_data_token': headers.containsKey('b-at'),
            if (path.endsWith('/refreshData'))
              'refresh_confirmed': json['data'] == true,
          }, environmentKey: 'QIYOU_KURO_REPORT');
        }
        if (!acceptedCodes.contains(code)) {
          final operation = switch (path) {
            '/aki/roleBox/requestToken' => '获取鸣潮数据令牌',
            '/aki/roleBox/akiBox/refreshData' => '刷新鸣潮数据',
            '/gamer/widget/game3/getData' => '读取鸣潮体力',
            _ => '查询',
          };
          final reason = community == Community.kuro
              ? safeVerificationReason(json['msg'], [
                  ...headers.values,
                  ...?form?.values,
                  ...?query?.values,
                ])
              : '';
          if (community == Community.kuro && code == 10901) {
            throw MiyousheException(ApiFailure.protocol,
                '库街区$operation失败（10901）。请重新连接并完成官方短信登录，获取游戏数据会话。${reason.isEmpty ? '' : '\n官方提示：$reason'}',
                code: code);
          }
          final expired = community == Community.kuro
              ? const {220, 221, 222, 230}.contains(code)
              : const {401, 403, 10001, 10002}.contains(code);
          final risk = community == Community.kuro &&
              const {130, 132, 270}.contains(code);
          throw MiyousheException(
              expired
                  ? ApiFailure.expired
                  : risk
                      ? ApiFailure.verification
                      : ApiFailure.protocol,
              expired
                  ? '${community.title}登录已过期，请重新连接。'
                  : risk
                      ? '${community.title}要求人工安全验证，请在官方页面处理后重新连接。'
                      : community == Community.kuro
                          ? '库街区$operation失败（错误码 ${code ?? '未知'}）。${reason.isEmpty ? '请稍后重试。' : '\n官方提示：$reason'}'
                          : '${community.title}未完成请求（错误码 ${code ?? '未知'}），请稍后重试。',
              code: code);
        }
        dynamic data = json['data'];
        if (data is String && (data.startsWith('{') || data.startsWith('['))) {
          data = jsonDecode(data);
        }
        if (object(data)['geeTest'] == true) {
          throw MiyousheException(ApiFailure.verification,
              '${community.title}要求人工安全验证，请在官方页面处理后重新连接。');
        }
        return data;
      })()
          .timeout(const Duration(seconds: 20));
    } on MiyousheException {
      rethrow;
    } on TimeoutException {
      throw MiyousheException(
          ApiFailure.network, '${community.title}请求超时，请稍后重试；签到请先刷新状态再操作。');
    } on FormatException {
      throw MiyousheException(
          ApiFailure.protocol, '${community.title}返回格式发生变化，暂时无法读取。');
    } catch (_) {
      throw MiyousheException(
          ApiFailure.network, '${community.title}连接失败，请检查网络后重试。');
    }
  }

  void close() => transport.close();
}

String newCommunityDeviceId() =>
    List.generate(16, (_) => Random.secure().nextInt(256))
        .map((n) => n.toRadixString(16).padLeft(2, '0'))
        .join();

// Credentials are opaque strings or a minimal JSON envelope from the official
// WebView. Whitelist metadata; never accept arbitrary request headers or hosts.
Map<String, String> communityCredential(String input,
    {bool allowCookie = false}) {
  final clean = input.trim();
  if (clean.isEmpty ||
      clean.length > 24000 ||
      RegExp(r'[\r\n\x00]').hasMatch(clean)) {
    throw const MiyousheException(
        ApiFailure.credentials, '未检测到登录凭证，请先在官方页面完成登录。');
  }
  final values = <String, String>{};
  if (clean.startsWith('{')) {
    try {
      final json = object(jsonDecode(clean));
      for (final key in [
        'token',
        'uid',
        'devcode',
        'did',
        'user-agent',
        if (allowCookie) 'cookie',
        if (allowCookie) 'refreshToken'
      ]) {
        final value = json[key];
        if (value is String &&
            value.isNotEmpty &&
            value.length <= 12000 &&
            !RegExp(r'[\r\n\x00]').hasMatch(value)) {
          values[key] = value;
        }
      }
    } catch (_) {
      throw const MiyousheException(ApiFailure.credentials, '登录凭证格式不正确。');
    }
  } else {
    values['token'] = clean;
  }
  if (values['token'] == null &&
      (!allowCookie ||
          (values['cookie'] == null && values['refreshToken'] == null))) {
    throw const MiyousheException(
        ApiFailure.credentials, '未检测到登录令牌，请在官方页面重新登录。');
  }
  return values;
}

String requiredText(Object? value, String message) {
  final text = value?.toString() ?? '';
  if (text.isEmpty ||
      text == '0' ||
      text.length > 160 ||
      RegExp(r'[\r\n\x00]').hasMatch(text)) {
    throw MiyousheException(ApiFailure.protocol, message);
  }
  return text;
}

SignStatus strictSignState(Object? value, Community community) {
  if (value is! bool) {
    throw MiyousheException(
        ApiFailure.protocol, '${community.title}未返回明确签到状态，暂时无法确认。');
  }
  return value ? SignStatus.alreadySigned : SignStatus.pending;
}
