import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qiyou/data/taygedo_login_client.dart';
import 'package:qiyou/data/taygedo_client.dart';
import 'package:qiyou/data/kuro_login_session.dart';
import 'package:qiyou/data/miyoushe_client.dart';
import 'package:qiyou/domain/models.dart';

http.Response envelope(Map<String, dynamic> payload) =>
    http.Response(jsonEncode(payload), 200,
        headers: {'content-type': 'application/json'});

void main() {
  test('SDK encryption matches independent AES-ECB PKCS7 test vectors', () {
    expect(
        TaygedoLoginClient.encryptField('123456'), 'TyWSYItqCceQ7+iFvOTXbA==');
    expect(TaygedoLoginClient.encryptField('13800000000'),
        'IqfquRou563hM4IuwWbe4Q==');
  });
  test('Taygedo SMS goes only to official host and signs sorted actual fields',
      () async {
    final requests = <http.Request>[];
    final client = TaygedoLoginClient(
        deviceId: 'test-device',
        clock: () => DateTime.utc(2026, 10, 16),
        transport: MockClient((r) async {
          requests.add(r);
          return envelope({'code': 0});
        }));
    addTearDown(client.close);
    await client.sendCode('13800000000');
    final r = requests.single;
    expect(r.url.toString(),
        'https://user.laohu.com/m/newApi/sendPhoneCaptchaWithOutLogin');
    expect(r.followRedirects, isFalse);
    expect(r.bodyFields['cellphone'], '13800000000');
    expect(r.bodyFields['deviceModel'], 'Qiyou windows');
    expect(r.bodyFields['sign'],
        TaygedoLoginClient.signature(Map.from(r.bodyFields)..remove('sign')));
    expect(r.bodyFields.values.any((v) => v.isEmpty), isFalse);
  });
  test(
      'SMS login exchanges SDK identity for community access token without saving phone or OTP',
      () async {
    final requests = <http.Request>[];
    final client = TaygedoLoginClient(
        deviceId: 'login-device',
        transport: MockClient((r) async {
          requests.add(r);
          if (r.url.path.endsWith('checkPhoneCaptchaWithOutLogin')) {
            return envelope({'code': 0});
          }
          if (r.url.path.endsWith('/sms/new/login')) {
            return envelope({
              'code': 0,
              'result': {'token': 'sdk-token', 'userId': '123456789012345678'}
            });
          }
          return envelope({
            'code': 0,
            'data': {
              'accessToken': 'community-token',
              'refreshToken': 'not-persisted',
              'uid': '7'
            }
          });
        }));
    addTearDown(client.close);
    final credential = await client.login('13800000000', '123456');
    expect(requests.map((r) => r.url.host),
        ['user.laohu.com', 'user.laohu.com', 'bbs-api.tajiduo.com']);
    expect(requests[1].bodyFields['cellphone'], 'IqfquRou563hM4IuwWbe4Q==');
    expect(requests[1].bodyFields['captcha'], 'TyWSYItqCceQ7+iFvOTXbA==');
    expect(requests[2].bodyFields, {
      'token': 'sdk-token',
      'userIdentity': '123456789012345678',
      'appId': '10551'
    });
    expect(requests[2].headers['ds'], isNotEmpty);
    expect(jsonDecode(credential),
        {'token': 'community-token', 'uid': '7', 'did': 'login-device'});
    for (final sensitive in [
      '13800000000',
      '123456',
      'sdk-token',
      'not-persisted'
    ]) {
      expect(credential, isNot(contains(sensitive)));
    }
  });
  test('Incorrect SMS stops before login exchange and redacts official errors',
      () async {
    var calls = 0;
    final client = TaygedoLoginClient(transport: MockClient((r) async {
      calls++;
      return envelope({'code': 9, 'message': '13800000000 123456 secret'});
    }));
    addTearDown(client.close);
    await expectLater(
        client.login('13800000000', '123456'),
        throwsA(isA<MiyousheException>()
            .having((e) => e.message.contains('13800000000'), 'phone redacted',
                isFalse)
            .having(
                (e) => e.message.contains('123456'), 'OTP redacted', isFalse)));
    expect(calls, 1);
  });
  test(
      'Kuro native session bridge rejects unrelated messages and omits OTP fields',
      () {
    final input = {
      'nonce': 'expected',
      'token': 'app-token',
      'did': 'device',
      'devcode': 'device',
      'mobile': 'discard',
      'code': 'discard'
    };
    expect(kuroAppLoginCredential(input, 'wrong'), isNull);
    final credential =
        jsonDecode(kuroAppLoginCredential(input, 'expected')!) as Map;
    expect(credential.keys, unorderedEquals(['token', 'did', 'devcode']));
    expect(kuroAppLoginScript('test'),
        contains("target.pathname = '/user/sdkLogin'"));
    expect(kuroAppLoginScript('test'), isNot(contains('JSON.stringify(body)')));
  });
  test('Native Taygedo session validates its UID and carries its login device',
      () async {
    final client = TaygedoClient(transport: MockClient((r) async {
      expect(r.headers['authorization'], 'app-token');
      expect(r.headers['uid'], '7');
      expect(r.headers['deviceid'], 'login-device');
      if (r.url.path.endsWith('getUserFullInfo')) {
        expect(r.url.path, '/usercenter/api/getUserFullInfo');
        return envelope({
          'code': 0,
          'data': {
            'user': {'uid': '7'}
          }
        });
      }
      return envelope({
        'code': 0,
        'data': [
          {
            'gameId': 1289,
            'bindRoleInfo': {'roleId': '101'}
          }
        ]
      });
    }));
    addTearDown(client.close);
    final account = await client.connect(
        jsonEncode({'token': 'app-token', 'uid': '7', 'did': 'login-device'}),
        existingDeviceId: 'old-web-device');
    expect(account.deviceId, 'login-device');
    expect(account.recordHeaders['session-device'], 'login-device');
    expect(account.community, Community.taygedo);
  });
}
