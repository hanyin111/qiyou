import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';
import '../domain/models.dart';
import 'community_http.dart';
import 'miyoushe_client.dart';
import 'taygedo_client.dart';

// Public SDK protocol constants. User phone/OTP and SDK intermediate credentials
// are never stored; only the final official community session is returned.
class TaygedoLoginClient {
  TaygedoLoginClient(
      {http.Client? transport,
      DateTime Function()? clock,
      String? deviceId,
      this.platform = 'windows'})
      : _http = transport ?? http.Client(),
        _clock = clock ?? DateTime.now,
        deviceId = deviceId ?? newCommunityDeviceId();
  final http.Client _http;
  final DateTime Function() _clock;
  final String deviceId, platform;
  static const sdkSecret = '89155cc4e8634ec5b1b6364013b23e3e';
  static String signature(Map<String, String> data) {
    final keys = data.keys.toList()..sort();
    return md5
        .convert(utf8.encode('${keys.map((k) => data[k]).join()}$sdkSecret'))
        .toString();
  }

  static String encryptField(String value) {
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(AESEngine()));
    cipher.init(
        true,
        PaddedBlockCipherParameters<KeyParameter, Null>(
            KeyParameter(Uint8List.fromList(
                utf8.encode(sdkSecret.substring(sdkSecret.length - 16)))),
            null));
    return base64Encode(cipher.process(Uint8List.fromList(utf8.encode(value))));
  }

  static String _token(Object? value, String message) {
    if (value is! String ||
        value.isEmpty ||
        value.length > 12000 ||
        RegExp(r'[\r\n\x00]').hasMatch(value)) {
      throw MiyousheException(ApiFailure.credentials, message);
    }
    return value;
  }

  Map<String, String> _base({bool login = false}) => {
        'adm': '',
        'appId': '10550',
        'bid': 'com.pwrd.htassistant',
        'channelId': '1',
        'deviceId': deviceId,
        'deviceModel': 'Qiyou $platform',
        'deviceName': 'Qiyou $platform',
        'deviceSys': platform,
        'deviceType': platform,
        'idfa': '',
        'sdkVersion': '4.327.0',
        't':
            '${login ? _clock().millisecondsSinceEpoch : _clock().millisecondsSinceEpoch ~/ 1000}',
        if (login) 'mac': '' else 'imei': '',
        if (login) 'version': '17' else 'versionCode': '17',
      };
  static void _phone(String phone) {
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)) {
      throw const MiyousheException(ApiFailure.credentials, '请输入有效的中国大陆手机号。');
    }
  }

  Future<Map<String, dynamic>> _post(
      String host, String path, Map<String, String> form, String stage,
      {Map<String, String> headers = const {}}) async {
    try {
      return await (() async {
        final request = http.Request('POST', Uri.https(host, path))
          ..followRedirects = false
          ..headers.addAll({'accept': 'application/json', ...headers})
          ..bodyFields = form;
        final response = await _http.send(request);
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 1024 * 1024) {
            throw const FormatException();
          }
          bytes.addAll(chunk);
        }
        if (response.statusCode != 200) {
          throw MiyousheException(ApiFailure.protocol,
              '$stage未完成（HTTP ${response.statusCode}），请稍后重试。');
        }
        return object(jsonDecode(utf8.decode(bytes)));
      })()
          .timeout(const Duration(seconds: 18));
    } on MiyousheException {
      rethrow;
    } catch (_) {
      throw MiyousheException(ApiFailure.network, '$stage连接失败，请检查网络后重试。');
    }
  }

  Future<Map<String, dynamic>> _sdk(
      String path, Map<String, String> data, String stage,
      {bool login = false, bool sending = false}) async {
    final form = {...data, 'sign': signature(data)};
    if (!login) form.removeWhere((_, v) => v.isEmpty);
    final response = await _post('user.laohu.com', path, form, stage,
        headers: {'user-agent': 'LaohuSDK/4.327.0 (Qiyou/$platform)'});
    final code = number(response['code']);
    final message = response['message'] ?? response['msg'];
    if (code != 0 &&
        !(sending &&
            code == 1 &&
            message is String &&
            message.contains('短信正在发送'))) {
      throw MiyousheException(ApiFailure.credentials,
          '$stage未完成（错误码 ${code ?? '未知'}）。请检查验证码；若官方要求安全验证，请在官方客户端处理后重试。',
          code: code);
    }
    return response;
  }

  Future<void> sendCode(String phone) async {
    _phone(phone);
    await _sdk(
        '/m/newApi/sendPhoneCaptchaWithOutLogin',
        {
          ..._base(),
          'areaCodeId': '1',
          'cellphone': phone,
          'type': '16',
        },
        '发送短信',
        sending: true);
  }

  Future<String> login(String phone, String code) async {
    _phone(phone);
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const MiyousheException(ApiFailure.credentials, '请输入六位短信验证码。');
    }
    await _sdk(
        '/m/newApi/checkPhoneCaptchaWithOutLogin',
        {
          ..._base(),
          'cellphone': phone,
          'captcha': code,
        },
        '校验短信');
    final sdk = await _sdk(
        '/openApi/sms/new/login',
        {
          ..._base(login: true),
          'areaCodeId': '1',
          'cellphone': encryptField(phone),
          'captcha': encryptField(code),
          'type': '16',
        },
        '完美通行证登录',
        login: true);
    final result = object(sdk['result']);
    final token = _token(result['token'], '官方未返回通行证会话，请重新登录。');
    final identity = requiredText(result['userId'], '官方未返回账号编号，请重新登录。');
    final community = await _post(
        'bbs-api.tajiduo.com',
        '/usercenter/api/login',
        {
          'token': token,
          'userIdentity': identity,
          'appId': '10551',
        },
        '连接塔吉多游戏服务',
        headers: {
          'authorization': '',
          'appversion': TaygedoClient.appVersion,
          'platform': 'android',
          'uid': '0',
          'deviceid': deviceId,
          'ds': TaygedoClient.signature(_clock().millisecondsSinceEpoch ~/ 1000,
              newCommunityDeviceId().substring(0, 8)),
        });
    if (number(community['code']) != 0) {
      throw MiyousheException(ApiFailure.credentials,
          '塔吉多游戏服务未接受登录（错误码 ${number(community['code']) ?? '未知'}），请稍后重试。',
          code: number(community['code']));
    }
    final data = object(community['data']);
    return jsonEncode({
      'token': _token(data['accessToken'], '塔吉多未返回游戏访问令牌。'),
      'uid': requiredText(data['uid'], '塔吉多未返回账号编号。'),
      'did': deviceId
    });
  }

  void close() => _http.close();
}
