import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';
import '../domain/models.dart';
import 'community_http.dart' show newCommunityDeviceId;
import 'miyoushe_client.dart';

class LoginChallenge {
  const LoginChallenge(
      {required this.id, this.challenge = '', this.session = ''});
  final String id, challenge, session;
  bool get isV4 => challenge.isEmpty;
  Map<String, String> validate(Object? raw) {
    final data = object(raw);
    final keys = isV4
        ? ['lot_number', 'captcha_output', 'pass_token', 'gen_time']
        : ['geetest_challenge', 'geetest_validate', 'geetest_seccode'];
    final result = <String, String>{};
    for (final key in keys) {
      final value = data[key];
      if (value is! String ||
          value.isEmpty ||
          value.length > 4096 ||
          RegExp(r'[\r\n\x00]').hasMatch(value)) {
        throw const MiyousheException(
            ApiFailure.verification, '人机验证结果不完整，请重新验证。');
      }
      result[key] = value;
    }
    if (!isV4 && result['geetest_challenge'] != challenge) {
      throw const MiyousheException(ApiFailure.verification, '验证任务已变化，请重新验证。');
    }
    if (isV4) {
      if (data['captcha_id'] != null && data['captcha_id'] != id) {
        throw const MiyousheException(
            ApiFailure.verification, '验证任务已变化，请重新验证。');
      }
      result['captcha_id'] = id;
    }
    return result;
  }
}

typedef SolveLoginChallenge = Future<Map<String, String>?> Function(
    LoginChallenge);

// Native forms call only fixed official hosts. No password login, automatic
// CAPTCHA solving, request retries, redirect following or credential logging.
class CommunitySmsLoginClient {
  CommunitySmsLoginClient(this.community,
      {http.Client? transport, String? deviceId})
      : transport = transport ?? http.Client(),
        deviceId = deviceId ?? newCommunityDeviceId() {
    if (community == Community.taygedo) {
      throw ArgumentError('Use TaygedoLoginClient');
    }
  }
  final Community community;
  final http.Client transport;
  final String deviceId;
  String? _actionType;
  void close() => transport.close();

  static String encryptPhone(String value) {
    // Official passport RSA public key; protocol metadata, not an account secret.
    final modulus = BigInt.parse(
        'c3bde91d3cc1cddc06219bfbe4b494fe609afb708e4372c34aa9db31e43657d200ee585b888f377006eb6b2183cd9912751bcc9b0c817ba035b6784a66e6c31b2fdcecf44c5709dbeaae7e75a842dbaa3d17c6d3132296821c5488e743df3e94c557d5edfe19b2570a24a0e5c59401200a7f900a01ace766c5a1832dca2fb111',
        radix: 16);
    final random = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(
          List.generate(32, (_) => Random.secure().nextInt(256)))));
    final rsa = PKCS1Encoding(RSAEngine())
      ..init(
          true,
          ParametersWithRandom(
              PublicKeyParameter<RSAPublicKey>(
                  RSAPublicKey(modulus, BigInt.from(65537))),
              random));
    return base64Encode(rsa.process(Uint8List.fromList(utf8.encode(value))));
  }

  Map<String, String> get _headers => community == Community.kuro
      ? {
          'source': 'android',
          'version': '3.1.3',
          'devcode': deviceId,
          'lang': 'zh-Hans',
          'user-agent': 'okhttp/4.12.0'
        }
      : {
          'x-rpc-app_id': 'bll8iq97cem8',
          'x-rpc-app_version': MiyousheProtocol.appVersion,
          'x-rpc-client_type': '2',
          'x-rpc-device_id': deviceId,
          'user-agent': 'Mozilla/5.0 miHoYoBBS/${MiyousheProtocol.appVersion}',
          'referer': 'https://user.miyoushe.com/'
        };

  Future<Map<String, dynamic>> _request(String host, String path,
      {Map<String, String>? form,
      Map<String, dynamic>? json,
      Map<String, String>? query,
      Map<String, String> headers = const {},
      required SolveLoginChallenge solve}) async {
    var aigis = '';
    for (var attempt = 0; attempt < 2; attempt++) {
      final request = http.Request(
          form != null || json != null ? 'POST' : 'GET',
          Uri.https(host, path, query))
        ..followRedirects = false
        ..headers.addAll({
          ..._headers,
          ...headers,
          if (aigis.isNotEmpty) 'x-rpc-aigis': aigis
        });
      if (form != null) request.bodyFields = form;
      if (json != null) {
        request.headers['content-type'] = 'application/json';
        request.body = jsonEncode(json);
      }
      final response = await (() async {
        final stream = await transport.send(request);
        if (stream.statusCode != 200) {
          throw MiyousheException(ApiFailure.network,
              '${community.title}登录请求未完成（HTTP ${stream.statusCode}）。');
        }
        final bytes = <int>[];
        await for (final chunk in stream.stream) {
          if (bytes.length + chunk.length > 512000) {
            throw const FormatException();
          }
          bytes.addAll(chunk);
        }
        return (
          data: object(jsonDecode(utf8.decode(bytes))),
          headers: stream.headers
        );
      })()
          .timeout(const Duration(seconds: 18));
      final rawAigis = response.headers['x-rpc-aigis'];
      if (rawAigis != null && rawAigis.isNotEmpty && attempt == 0) {
        final envelope = object(jsonDecode(rawAigis));
        final raw = envelope['data'];
        final config = object(raw is String ? jsonDecode(raw) : raw);
        final session = envelope['session_id'];
        final id = config['gt'] ?? config['captcha_id'];
        if (session is! String || id is! String) throw const FormatException();
        final challenge = LoginChallenge(
            id: id,
            challenge: '${config['challenge'] ?? ''}',
            session: session);
        final proof = await solve(challenge);
        if (proof == null) {
          throw const MiyousheException(
              ApiFailure.verification, '已取消人机验证，未继续登录。');
        }
        aigis =
            '$session;${base64Encode(utf8.encode(jsonEncode(challenge.validate(proof))))}';
        continue;
      }
      final result = response.data;
      final code = result['retcode'] ?? result['code'];
      if (code is! int) throw const FormatException();
      if (code != 0 && code != 200) {
        throw MiyousheException(ApiFailure.credentials,
            '${community.title}未完成登录请求（错误码 $code），请检查验证码或稍后重试。');
      }
      return object(result['data']);
    }
    throw const MiyousheException(ApiFailure.verification, '官方尚未接受人机验证，请重新尝试。');
  }

  static void _phone(String phone) {
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      throw const MiyousheException(ApiFailure.credentials, '请输入正确的中国大陆手机号。');
    }
  }

  Future<void> sendCode(String phone,
      {required SolveLoginChallenge solve}) async {
    _phone(phone);
    if (community == Community.miyoushe) {
      final data = await _request('passport-api.mihoyo.com',
          '/account/ma-cn-verifier/verifier/createLoginCaptcha',
          json: {
            'area_code': encryptPhone('+86'),
            'mobile': encryptPhone(phone)
          },
          solve: solve);
      final action = data['action_type'];
      if (action == null || action.toString().isEmpty) {
        throw const FormatException();
      }
      _actionType = action.toString();
      return;
    }
    var proof = <String, String>{};
    for (var attempt = 0; attempt < 2; attempt++) {
      final data = await _request('api.kurobbs.com', '/user/getSmsCode',
          form: {
            'mobile': phone,
            'geeTestData': proof.isEmpty ? '' : jsonEncode(proof)
          },
          solve: solve);
      if (data['geeTest'] != true) return;
      if (attempt != 0) break;
      const challenge = LoginChallenge(id: 'ec4aa4174277d822d73f2442a165a2cd');
      final result = await solve(challenge);
      if (result == null) {
        throw const MiyousheException(
            ApiFailure.verification, '已取消人机验证，未发送短信。');
      }
      proof = challenge.validate(result);
    }
    throw const MiyousheException(
        ApiFailure.verification, '官方尚未接受人机验证，未继续发送短信。');
  }

  Future<String> login(String phone, String code,
      {required SolveLoginChallenge solve}) async {
    _phone(phone);
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const MiyousheException(ApiFailure.credentials, '请输入六位短信验证码。');
    }
    if (community == Community.kuro) {
      final data = await _request('api.kurobbs.com', '/user/sdkLogin',
          form: {
            'mobile': phone,
            'code': code,
            'devCode': deviceId,
            'gameList': ''
          },
          solve: solve);
      final token = data['token'];
      if (token is! String || token.isEmpty) throw const FormatException();
      return jsonEncode({
        'token': token,
        'did': deviceId,
        'devcode': deviceId,
        'user-agent': _headers['user-agent']
      });
    }
    if (_actionType == null) {
      throw const MiyousheException(ApiFailure.credentials, '请先在此页面获取短信验证码。');
    }
    final data = await _request('passport-api.mihoyo.com',
        '/account/ma-cn-passport/app/loginByMobileCaptcha',
        json: {
          'area_code': encryptPhone('+86'),
          'mobile': encryptPhone(phone),
          'captcha': code,
          'action_type': _actionType
        },
        solve: solve);
    final user = object(data['user_info']);
    final token = object(data['token'])['token'];
    final uid = '${user['aid'] ?? ''}', mid = '${user['mid'] ?? ''}';
    if (token is! String || token.isEmpty || uid.isEmpty || mid.isEmpty) {
      throw const FormatException();
    }
    final cookie = await _request('passport-api.mihoyo.com',
        '/account/auth/api/getCookieAccountInfoBySToken',
        query: {'stoken': token},
        headers: {
          'cookie': 'stuid=$uid; stoken=$token; mid=$mid',
          'x-rpc-aigis': ''
        },
        solve: solve);
    final cookieToken = cookie['cookie_token'];
    if (cookieToken is! String || cookieToken.isEmpty) {
      throw const FormatException();
    }
    final credential =
        'account_id_v2=$uid; account_mid_v2=$mid; cookie_token_v2=$cookieToken';
    MiyousheClient.parseCookie(credential);
    return credential;
  }
}
