import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import 'community_client.dart';
import 'record_verification.dart';
import 'record_session_cookies.dart';
import 'verification_diagnostics.dart';

enum ApiFailure { credentials, expired, verification, network, protocol }

enum ApiStage {
  note('便笺查询'),
  verificationCreate('获取验证码'),
  verificationConfirm('确认验证码');

  const ApiStage(this.label);
  final String label;
}

class MiyousheException implements Exception {
  const MiyousheException(this.kind, this.message, {this.code, this.stage});
  final ApiFailure kind;
  final String message;
  final int? code;
  final ApiStage? stage;
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

class MiyousheClient implements CommunityClient {
  MiyousheClient({http.Client? transport, DateTime Function()? clock})
      : _http = transport ?? http.Client(),
        _clock = clock ?? DateTime.now;
  final http.Client _http;
  final DateTime Function() _clock;
  final Random _random = Random.secure();
  final _recordPasses = <String, ({String challenge, DateTime expires})>{};
  final _recordTraces = <String, ({String value, DateTime receivedAt})>{};
  final _recordCookies = RecordSessionCookies();
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

  @override
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
      final matching = Game.values.where((game) =>
          game.community == Community.miyoushe && game.biz == item['game_biz']);
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

  @override
  Future<DailyNote> daily(Account account, Role role) async {
    final path = _notePath(role.game);
    final key = _passKey(account, role);
    // The official retry credential is consumed by the next read only.
    final pass = _recordPasses.remove(key);
    _recordTraces.remove(key);
    try {
      final data = await _request(account, 'api-takumi-record.mihoyo.com', path,
          params: {'role_id': role.uid, 'server': role.region},
          record: true,
          recordGame: role.game,
          stage: ApiStage.note, onResponseHeaders: (headers) {
        final trace = headers['x-trace-id'];
        if (RecordVerification.validTrace(trace)) {
          _recordTraces[key] = (value: trace!, receivedAt: _clock());
        }
      },
          verifiedChallenge: pass != null && _clock().isBefore(pass.expires)
              ? pass.challenge
              : null);
      return DailyNote.parse(role.game, data, _clock());
    } on MiyousheException {
      rethrow;
    }
  }

  static String _notePath(Game game) => switch (game) {
        Game.genshin => '/game_record/app/genshin/api/dailyNote',
        Game.starRail => '/game_record/app/hkrpg/api/note',
        Game.zenless => '/event/game_record_zzz/api/zzz/note',
        _ => throw ArgumentError('Unsupported MiYouShe game'),
      };

  String _passKey(Account account, Role role) =>
      '${account.id}:${account.deviceId}:${role.key}';

  Future<RecordVerification> createNoteVerification(
      Account account, Role role) async {
    _recordPasses.remove(_passKey(account, role));
    final trace = _recordTraces[_passKey(account, role)];
    final traceId = trace != null &&
            _clock().difference(trace.receivedAt) < const Duration(minutes: 5)
        ? trace.value
        : '';
    final requestPath =
        Uri.https('api-takumi-record.mihoyo.com', _notePath(role.game))
            .toString();
    final data = await _request(account, 'api-takumi-record.mihoyo.com',
        '/game_record/app/card/wapi/createVerification',
        params: {'is_high': 'true'},
        record: true,
        recordGame: role.game,
        stage: ApiStage.verificationCreate,
        challengePath: requestPath,
        challengeTrace: traceId,
        expectChallenge: true);
    if (!RecordVerification.validToken(data['gt']) ||
        !RecordVerification.validToken(data['challenge'])) {
      throw const MiyousheException(
          ApiFailure.protocol, '获取验证码：米游社没有返回可用的验证码，请稍后重试。',
          stage: ApiStage.verificationCreate);
    }
    if (data['success'] != true && number(data['success']) != 1) {
      throw const MiyousheException(
          ApiFailure.verification, '获取验证码：极验服务暂不可用，请稍后重试。',
          stage: ApiStage.verificationCreate);
    }
    return RecordVerification(
        gt: data['gt'] as String,
        challenge: data['challenge'] as String,
        newCaptcha: data['new_captcha'] != false,
        accountId: account.id,
        deviceId: account.deviceId,
        roleKey: role.key,
        requestPath: requestPath,
        traceId: traceId,
        issuedAt: _clock());
  }

  Future<void> verifyNote(Account account, Role role,
      RecordVerification verification, RecordVerificationProof proof) async {
    if (!verification.matches(account, role, _clock()) ||
        RecordVerificationProof.fromData(proof.toJson()) == null) {
      throw const MiyousheException(
          ApiFailure.verification, '本次验证已失效，请重新获取验证码。');
    }
    final expectedPath =
        Uri.https('api-takumi-record.mihoyo.com', _notePath(role.game))
            .toString();
    if (verification.requestPath != expectedPath) {
      throw const MiyousheException(
          ApiFailure.verification, '确认验证码：验证对应的游戏请求已变化，请重新加载。',
          stage: ApiStage.verificationConfirm);
    }
    final data = await _request(account, 'api-takumi-record.mihoyo.com',
        '/game_record/app/card/wapi/verifyVerification',
        body: proof.toJson(),
        record: true,
        recordGame: role.game,
        stage: ApiStage.verificationConfirm,
        challengePath: verification.requestPath,
        challengeTrace: verification.traceId,
        expectChallenge: true);
    final accepted = data['challenge'];
    if (!RecordVerification.validPass(accepted)) {
      throw const MiyousheException(
          ApiFailure.protocol, '确认验证码：米游社未返回重试凭据，暂时无法确认验证成功。',
          stage: ApiStage.verificationConfirm);
    }
    // Only an official successful response permits a retry with this challenge.
    // This is MiYouShe's returned credential, not the raw GeeTest challenge.
    // Keep it in memory until the next read or expiry; never persist it.
    _recordPasses[_passKey(account, role)] = (
      challenge: accepted as String,
      expires: verification.issuedAt.add(const Duration(minutes: 5))
    );
  }

  static Map<String, String> recordMetadata(Game game) => switch (game) {
        Game.genshin => {
            'x-rpc-challenge_game': '2',
            'x-rpc-page': 'v4.1.5-ys_#ys',
            'x-rpc-tool-verison': 'v4.1.5-ys'
          },
        Game.starRail => {
            'x-rpc-challenge_game': '6',
            'x-rpc-page': 'v1.4.1-rpg_#/rpg',
            'x-rpc-tool-verison': 'v1.4.1-rpg'
          },
        Game.zenless => {
            'x-rpc-challenge_game': '8',
            'x-rpc-page': 'v1.0.14_#/zzz',
            'x-rpc-tool-verison': 'v1.0.14-zzz'
          },
        _ => throw ArgumentError('Unsupported MiYouShe game'),
      };

  @override
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

  @override
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
      if ((await signInfo(account, role)).isDone) return SignStatus.signed;
      throw const MiyousheException(
          ApiFailure.protocol, '签到请求已提交，但官方状态尚未确认。请刷新查看，暂勿重复签到。');
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
      Game? recordGame,
      ApiStage? stage,
      void Function(Map<String, String>)? onResponseHeaders,
      String? challengePath,
      String? challengeTrace,
      String? verifiedChallenge,
      bool expectChallenge = false,
      Game? game}) async {
    if (!hosts.contains(host)) throw StateError('Unsupported API host');
    final keys = params.keys.toList()..sort();
    final uri =
        Uri.https(host, path, {for (final key in keys) key: params[key]!});
    final timestamp = _clock().millisecondsSinceEpoch ~/ 1000;
    final encodedBody = body == null ? '' : jsonEncode(body);
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
        'Cookie': record
            ? _recordCookies.header(
                account.cookie, account.id, account.deviceId, host, _clock())
            : account.cookie,
        'x-rpc-app_version': MiyousheProtocol.appVersion,
        'x-rpc-client_type': '5',
        'x-rpc-device_id': account.deviceId,
        'x-rpc-channel': 'miyousheluodi',
        'Referer': record && recordGame != Game.zenless
            ? 'https://webstatic.mihoyo.com/'
            : 'https://act.mihoyo.com/',
        'Origin': record && recordGame != Game.zenless
            ? 'https://webstatic.mihoyo.com'
            : 'https://act.mihoyo.com',
        'User-Agent': 'Mozilla/5.0 miHoYoBBS/${MiyousheProtocol.appVersion}',
        if (game != null) 'x-rpc-signgame': game.signGame,
        'DS': MiyousheProtocol.signature(
            timestamp: timestamp,
            nonce: nonce,
            query: record ? uri.query : null,
            body: encodedBody)
      });
    if (record) {
      request.headers.addAll(safeRecordHeaders(account.recordHeaders));
      if (recordGame != null) {
        request.headers.addAll(recordMetadata(recordGame));
      }
      if (challengePath != null) {
        request.headers['x-rpc-challenge_path'] = challengePath;
      }
      if (RecordVerification.validTrace(challengeTrace)) {
        request.headers['x-rpc-challenge_trace'] = challengeTrace!;
      }
      if (verifiedChallenge != null) {
        request.headers['x-rpc-challenge'] = verifiedChallenge;
      }
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = encodedBody;
    }
    try {
      final response = await (() async {
        final stream = await _http.send(request);
        if (record) {
          _recordCookies.remember(account.id, account.deviceId, host,
              stream.headers['set-cookie'], _clock());
        }
        onResponseHeaders?.call(stream.headers);
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
      var officialReason = '';
      if (stage == ApiStage.verificationConfirm ||
          stage == ApiStage.verificationCreate) {
        officialReason = safeVerificationReason(json['message'], [
          account.cookie,
          account.id,
          account.deviceId,
          ...account.cookie.split(';').map((c) =>
              c.contains('=') ? c.substring(c.indexOf('=') + 1).trim() : ''),
          ...account.recordHeaders.values,
          ...params.values,
          ...?body?.values.whereType<String>()
        ]);
        await writeVerificationDiagnostic({
          'version': '0.1.13',
          'stage': stage!.name,
          'game': recordGame?.name,
          'retcode': code,
          'official_reason': officialReason,
          'has_device_fp':
              request.headers['x-rpc-device_fp']?.isNotEmpty == true,
          'has_trace':
              request.headers['x-rpc-challenge_trace']?.isNotEmpty == true,
          'has_temporary_session':
              request.headers['Cookie']?.contains('acw_tc=') == true,
          'proof_fields': body?.keys.toList(),
        });
      }
      if (code == -5003 &&
          body != null &&
          game != null &&
          path.endsWith('/sign')) {
        throw _AlreadySigned();
      }
      if ({-100, 10001, 10002, 10101}.contains(code)) {
        throw MiyousheException(ApiFailure.expired, '登录已过期，请重新连接米游社账号。',
            code: code);
      }
      final risk = number(data['risk_code']);
      if ({1034, 10306, 5003, 10035, 10041, -999}.contains(code) ||
          (risk != null && risk != 0) ||
          (!expectChallenge &&
              ((data['gt']?.toString().isNotEmpty ?? false) ||
                  (data['challenge']?.toString().isNotEmpty ?? false)))) {
        throw MiyousheException(
            ApiFailure.verification,
            stage == ApiStage.verificationConfirm
                ? '米游社未接受本次验证码（错误码 $code），请重新加载后手动验证。${officialReason.isEmpty ? '' : '\n官方提示：$officialReason'}'
                : '米游社要求安全验证（$code）。请点击“完成安全验证”后重试。',
            code: code);
      }
      if (code != 0) {
        throw MiyousheException(ApiFailure.protocol,
            '米游社暂时无法提供这项数据（错误码 ${code ?? '未知'}），请检查登录状态或稍后重试。',
            code: code);
      }
      return data;
    } on MiyousheException catch (error) {
      if (stage == null || error.stage != null) rethrow;
      throw MiyousheException(error.kind, '${stage.label}：${error.message}',
          code: error.code, stage: stage);
    } on _AlreadySigned {
      rethrow;
    } on TimeoutException {
      throw MiyousheException(ApiFailure.network,
          '${stage == null ? '' : '${stage.label}：'}连接超时，请检查网络后重试。',
          stage: stage);
    } catch (_) {
      throw MiyousheException(ApiFailure.network,
          '${stage == null ? '' : '${stage.label}：'}连接未完成，请检查网络后重试。',
          stage: stage);
    }
  }

  static Map<String, String> safeRecordHeaders(Map<String, String> headers) {
    const allowed = {
      'x-rpc-device_id',
      'x-rpc-device_fp',
      'x-rpc-client_type',
      'x-rpc-app_version',
      'x-rpc-page',
      'x-rpc-tool-verison',
      'x-rpc-challenge_game',
      'user-agent',
      'referer',
      'origin'
    };
    return {
      for (final entry in headers.entries)
        if (allowed.contains(entry.key.toLowerCase()) &&
            entry.value.length <= 2048 &&
            !RegExp(r'[\r\n\x00]').hasMatch(entry.value))
          entry.key.toLowerCase(): entry.value
    };
  }

  @override
  void close() => _http.close();
}

class _AlreadySigned implements Exception {}
