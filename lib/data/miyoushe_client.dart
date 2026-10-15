import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../domain/models.dart';

enum ApiFailure { credentials, expired, verification, network, protocol }

class MiyousheException implements Exception {
  const MiyousheException(this.kind, this.message);
  final ApiFailure kind;
  final String message;
  @override
  String toString() => message;
}

class MiyousheProtocol {
  // Protocol metadata, not account secrets. Keep version and salts paired.
  static const appVersion = '2.109.0';
  static const webSalt = 'd9200c846b10886e8c874fc33c8f308b';
  static const recordSalt = 'xV8v4Qu54lUKrEYFZkJhB8cuOh9Asafs';
  static String signature(
      {required int timestamp,
      required String nonce,
      String? query,
      String body = ''}) {
    final input = query == null
        ? 'salt=$webSalt&t=$timestamp&r=$nonce'
        : 'salt=$recordSalt&t=$timestamp&r=$nonce&b=$body&q=$query';
    return '$timestamp,$nonce,${md5.convert(utf8.encode(input))}';
  }
}

class MiyousheClient {
  MiyousheClient({http.Client? transport, DateTime Function()? clock})
      : _http = transport ?? http.Client(),
        _clock = clock ?? DateTime.now;
  final http.Client _http;
  final DateTime Function() _clock;
  final Random _random = Random.secure();
  static const hosts = {
    'api-takumi.mihoyo.com',
    'api-takumi-record.mihoyo.com',
    'act-nap-api.mihoyo.com'
  };

  static Map<String, String> parseCookie(String input) {
    final trimmed = input
        .trim()
        .replaceFirst(RegExp(r'^cookie:\s*', caseSensitive: false), '');
    if (trimmed.isEmpty ||
        trimmed.length > 24000 ||
        RegExp(r'[\r\n\x00]').hasMatch(trimmed)) {
      throw const MiyousheException(
          ApiFailure.credentials, '登录凭证格式不正确，请重新粘贴完整 Cookie。');
    }
    final values = <String, String>{};
    for (final item in trimmed.split(';')) {
      final separator = item.indexOf('=');
      if (separator <= 0) continue;
      final key = item.substring(0, separator).trim();
      final value = item.substring(separator + 1).trim();
      if (RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(key) && value.isNotEmpty) {
        values[key] = value;
      }
    }
    final identity = values['account_id_v2'] ??
        values['account_id'] ??
        values['ltuid_v2'] ??
        values['ltuid'];
    final token = values['cookie_token_v2'] ??
        values['cookie_token'] ??
        values['ltoken_v2'] ??
        values['ltoken'];
    if (identity == null || token == null) {
      throw const MiyousheException(
          ApiFailure.credentials, '凭证中缺少账号或登录令牌，请使用完整的米游社 Cookie。');
    }
    return values;
  }

  String deviceId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<Account> connect(String input, {String? existingDeviceId}) async {
    final values = parseCookie(input);
    final cookie =
        values.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
    final id = values['account_id_v2'] ??
        values['account_id'] ??
        values['ltuid_v2'] ??
        values['ltuid']!;
    final device = existingDeviceId ?? deviceId();
    final temporary =
        Account(id: id, cookie: cookie, deviceId: device, roles: const []);
    final data = await _request(temporary, 'api-takumi.mihoyo.com',
        '/binding/api/getUserGameRolesByCookie');
    final roles = <Role>[];
    final seen = <String>{};
    for (final raw in data['list'] is List ? data['list'] as List : const []) {
      final item = object(raw);
      final matching =
          Game.values.where((game) => game.biz == item['game_biz']);
      if (matching.isEmpty ||
          item['game_uid'] == null ||
          item['region'] == null) {
        continue;
      }
      final role = Role(
          game: matching.first,
          uid: '${item['game_uid']}',
          region: '${item['region']}',
          nickname: '${item['nickname'] ?? '旅行者'}',
          serverName: '${item['region_name'] ?? '国服'}',
          level: number(item['level']));
      if (seen.add(role.key)) roles.add(role);
    }
    if (roles.isEmpty) {
      throw const MiyousheException(
          ApiFailure.protocol, '未发现已绑定的原神、星穹铁道或绝区零国服角色。请先在米游社绑定角色。');
    }
    return Account(id: id, cookie: cookie, deviceId: device, roles: roles);
  }

  Future<DailyNote> daily(Account account, Role role) async {
    final path = switch (role.game) {
      Game.genshin => '/game_record/app/genshin/api/dailyNote',
      Game.starRail => '/game_record/app/hkrpg/api/note',
      Game.zenless => '/game_record/app/zzz/api/note',
    };
    final data = await _request(account, 'api-takumi-record.mihoyo.com', path,
        params: {'role_id': role.uid, 'server': role.region}, record: true);
    return DailyNote.parse(role.game, data, _clock());
  }

  Future<SignStatus> signInfo(Account account, Role role) async {
    final data =
        await _request(account, _signHost(role), '${_signPath(role)}/info',
            params: {
              'act_id': role.game.activityId,
              'lang': 'zh-cn',
              'region': role.region,
              'uid': role.uid
            },
            game: role.game);
    if (data['is_sign'] is! bool) {
      throw const MiyousheException(
          ApiFailure.protocol, '签到状态格式有变化，暂时不能确认今日是否已签。');
    }
    return data['is_sign'] == true
        ? SignStatus.alreadySigned
        : SignStatus.pending;
  }

  Future<SignStatus> sign(Account account, Role role) async {
    // Query before every write. Never automatically retry an uncertain POST.
    if ((await signInfo(account, role)).isDone) return SignStatus.alreadySigned;
    try {
      await _request(account, _signHost(role), '${_signPath(role)}/sign',
          body: {
            'act_id': role.game.activityId,
            'region': role.region,
            'uid': role.uid
          },
          game: role.game);
      return SignStatus.signed;
    } on _AlreadySigned {
      return SignStatus.alreadySigned;
    }
  }

  String _signHost(Role role) => role.game == Game.zenless
      ? 'act-nap-api.mihoyo.com'
      : 'api-takumi.mihoyo.com';
  String _signPath(Role role) =>
      role.game == Game.zenless ? '/event/luna/zzz' : '/event/luna';

  Future<Map<String, dynamic>> _request(
      Account account, String host, String path,
      {Map<String, String> params = const {},
      Map<String, dynamic>? body,
      bool record = false,
      Game? game}) async {
    if (!hosts.contains(host)) throw StateError('Unsupported API host');
    final keys = params.keys.toList()..sort();
    final uri =
        Uri.https(host, path, {for (final key in keys) key: params[key]!});
    final timestamp = _clock().millisecondsSinceEpoch ~/ 1000;
    final nonce = record
        ? '${100000 + _random.nextInt(100001)}'
        : List.generate(
                6,
                (_) =>
                    'abcdefghijklmnopqrstuvwxyz0123456789'[_random.nextInt(36)])
            .join();
    final request = http.Request(body == null ? 'GET' : 'POST', uri)
      ..followRedirects = false
      ..headers.addAll({
        'Accept': 'application/json',
        'Cookie': account.cookie,
        'x-rpc-app_version': MiyousheProtocol.appVersion,
        'x-rpc-client_type': '5',
        'x-rpc-device_id': account.deviceId,
        'x-rpc-channel': 'miyousheluodi',
        'Referer': 'https://act.mihoyo.com/',
        'Origin': 'https://act.mihoyo.com',
        'User-Agent': 'Mozilla/5.0 miHoYoBBS/${MiyousheProtocol.appVersion}',
        if (game != null) 'x-rpc-signgame': game.signGame,
        'DS': MiyousheProtocol.signature(
            timestamp: timestamp,
            nonce: nonce,
            query: record ? uri.query : null)
      });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final response = await (() async {
        final stream = await _http.send(request);
        if (stream.statusCode != 200) {
          throw const MiyousheException(ApiFailure.network, '米游社暂时没有响应，请稍后重试。');
        }
        final bytes = <int>[];
        await for (final chunk in stream.stream) {
          bytes.addAll(chunk);
          if (bytes.length > 2000000) {
            throw const MiyousheException(ApiFailure.protocol, '返回数据异常，已停止处理。');
          }
        }
        return jsonDecode(utf8.decode(bytes));
      })()
          .timeout(const Duration(seconds: 18));
      final json = object(response);
      final code = number(json['retcode']);
      final data = object(json['data']);
      if (code == -5003 && body != null) throw _AlreadySigned();
      if ({-100, 10001, 10002, 10101}.contains(code)) {
        throw const MiyousheException(ApiFailure.expired, '登录已过期，请重新连接米游社账号。');
      }
      final risk = number(data['risk_code']);
      if ({1034, 5003, -999}.contains(code) ||
          (risk != null && risk != 0) ||
          (data['gt']?.toString().isNotEmpty ?? false) ||
          (data['challenge']?.toString().isNotEmpty ?? false)) {
        throw const MiyousheException(
            ApiFailure.verification, '需要在米游社完成安全验证。完成后再回到栖游重试。');
      }
      if (code != 0) {
        throw const MiyousheException(
            ApiFailure.protocol, '米游社暂时无法提供这项数据，请检查登录状态或稍后重试。');
      }
      return data;
    } on MiyousheException {
      rethrow;
    } on _AlreadySigned {
      rethrow;
    } on TimeoutException {
      throw const MiyousheException(ApiFailure.network, '连接超时，请检查网络后重试。');
    } catch (_) {
      throw const MiyousheException(ApiFailure.network, '连接未完成，请检查网络后重试。');
    }
  }

  void close() => _http.close();
}

class _AlreadySigned implements Exception {}
