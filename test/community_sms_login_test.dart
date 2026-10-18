import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qiyou/data/community_sms_login.dart';
import 'package:qiyou/data/miyoushe_client.dart';
import 'package:qiyou/domain/models.dart';
import 'package:qiyou/ui/login_captcha.dart';

http.Response response(Map<String, dynamic> data,
        {Map<String, String> headers = const {}}) =>
    http.Response(jsonEncode(data), 200,
        headers: {'content-type': 'application/json', ...headers});

void main() {
  const v4 = {
    'lot_number': 'synthetic-lot',
    'captcha_output': 'synthetic-output',
    'pass_token': 'synthetic-pass',
    'gen_time': '1792320000'
  };
  test(
      'Kuro SMS challenge is completed by the user, then native login keeps the same device',
      () async {
    final requests = <http.Request>[];
    var solves = 0;
    final client = CommunitySmsLoginClient(Community.kuro,
        deviceId: 'fixed-device', transport: MockClient((r) async {
      requests.add(r);
      expect(r.url.host, 'api.kurobbs.com');
      expect(r.followRedirects, isFalse);
      expect(r.headers['devcode'], 'fixed-device');
      if (r.url.path == '/user/getSmsCode') {
        return response({
          'code': 200,
          'data': {'geeTest': requests.length == 1}
        });
      }
      expect(r.url.path, '/user/sdkLogin');
      expect(r.bodyFields['devCode'], 'fixed-device');
      return response({
        'code': 200,
        'data': {'token': 'community-session'}
      });
    }));
    addTearDown(client.close);
    Future<Map<String, String>?> solve(LoginChallenge c) async {
      solves++;
      return v4;
    }

    await client.sendCode('13800000000', solve: solve);
    final credential =
        await client.login('13800000000', '123456', solve: solve);
    expect(solves, 1);
    expect(jsonDecode(requests[1].bodyFields['geeTestData']!)['captcha_id'],
        'ec4aa4174277d822d73f2442a165a2cd');
    expect(jsonDecode(credential), {
      'token': 'community-session',
      'did': 'fixed-device',
      'devcode': 'fixed-device',
      'user-agent': 'okhttp/4.12.0'
    });
    expect(credential, isNot(contains('13800000000')));
    expect(credential, isNot(contains('123456')));
  });
  test('Cancelling Kuro CAPTCHA stops before another SMS request', () async {
    var calls = 0;
    final client = CommunitySmsLoginClient(Community.kuro,
        transport: MockClient((r) async {
      calls++;
      return response({
        'code': 200,
        'data': {'geeTest': true}
      });
    }));
    addTearDown(client.close);
    await expectLater(client.sendCode('13800000000', solve: (_) async => null),
        throwsA(isA<MiyousheException>()));
    expect(calls, 1);
  });
  test(
      'Miyoushe encrypts phone, binds Aigis proof, and exchanges a temporary token for cookies',
      () async {
    final requests = <http.Request>[];
    final client = CommunitySmsLoginClient(Community.miyoushe,
        deviceId: 'fixed-device', transport: MockClient((r) async {
      requests.add(r);
      expect(r.url.host, 'passport-api.mihoyo.com');
      expect(r.followRedirects, isFalse);
      expect(r.headers['x-rpc-device_id'], 'fixed-device');
      if (requests.length == 1) {
        return response({
          'retcode': -3101
        }, headers: {
          'x-rpc-aigis': jsonEncode({
            'session_id': 'synthetic-session',
            'data': jsonEncode({'gt': 'test-gt', 'challenge': 'test-challenge'})
          })
        });
      }
      if (r.url.path.endsWith('createLoginCaptcha')) {
        final body = jsonDecode(r.body);
        expect(base64Decode(body['mobile']).length, 128);
        expect(r.body, isNot(contains('13800000000')));
        expect(r.headers['x-rpc-aigis'], startsWith('synthetic-session;'));
        return response({
          'retcode': 0,
          'data': {'action_type': 'login'}
        });
      }
      if (r.url.path.endsWith('loginByMobileCaptcha')) {
        expect(jsonDecode(r.body)['action_type'], 'login');
        return response({
          'retcode': 0,
          'data': {
            'token': {'token': 'temporary-stoken'},
            'user_info': {'aid': '7', 'mid': 'synthetic-mid'}
          }
        });
      }
      expect(r.url.path, '/account/auth/api/getCookieAccountInfoBySToken');
      expect(r.url.queryParameters['stoken'], 'temporary-stoken');
      return response({
        'retcode': 0,
        'data': {'cookie_token': 'official-cookie'}
      });
    }));
    addTearDown(client.close);
    Future<Map<String, String>?> solve(LoginChallenge c) async => {
          'geetest_challenge': c.challenge,
          'geetest_validate': 'test-validation',
          'geetest_seccode': 'test-validation|jordan'
        };
    await client.sendCode('13800000000', solve: solve);
    final credential =
        await client.login('13800000000', '123456', solve: solve);
    expect(MiyousheClient.parseCookie(credential)['account_id_v2'], '7');
    for (final sensitive in ['temporary-stoken', '13800000000', '123456']) {
      expect(credential, isNot(contains(sensitive)));
    }
    expect(requests.length, 4);
  });
  test(
      'Login validation and HTTP failure do not retry or expose response messages',
      () async {
    var calls = 0;
    final client = CommunitySmsLoginClient(Community.kuro,
        transport: MockClient((r) async {
      calls++;
      return http.Response('private server detail 13800000000', 302,
          headers: {'location': 'https://evil.example/'});
    }));
    addTearDown(client.close);
    await expectLater(client.sendCode('invalid', solve: (_) async => null),
        throwsA(isA<MiyousheException>()));
    expect(calls, 0);
    await expectLater(
        client.sendCode('13800000000', solve: (_) async => null),
        throwsA(isA<MiyousheException>().having(
            (e) => e.message, 'redacted', isNot(contains('13800000000')))));
    expect(calls, 1);
  });
  test(
      'CAPTCHA page contains only public challenge data and validates task binding',
      () {
    const c = LoginChallenge(id: 'test-gt', challenge: 'test-challenge');
    final html = loginCaptchaHtml(c, 'synthetic-nonce');
    expect(html, contains('https://static.geetest.com/static/tools/gt.js'));
    for (final forbidden in [
      'cookie_token',
      'stoken',
      'mobile_captcha',
      'document.cookie'
    ]) {
      expect(html, isNot(contains(forbidden)));
    }
    expect(
        () => c.validate({
              'geetest_challenge': 'wrong',
              'geetest_validate': 'proof',
              'geetest_seccode': 'proof|jordan'
            }),
        throwsA(isA<MiyousheException>()));
    expect(
        () => loginCaptchaHtml(const LoginChallenge(id: '</script>'), 'nonce'),
        throwsFormatException);
    expect(CommunitySmsLoginClient.encryptPhone('13800000000'),
        isNot(CommunitySmsLoginClient.encryptPhone('13800000000')));
  });
  test('Miyoushe accepts an Aigis v4 login task without a v3 challenge',
      () async {
    var calls = 0;
    final client = CommunitySmsLoginClient(Community.miyoushe,
        transport: MockClient((r) async {
      calls++;
      if (calls == 1) {
        return http.Response(jsonEncode({'retcode': -3101}), 200, headers: {
          'x-rpc-aigis': jsonEncode({
            'session_id': 'synthetic-session',
            'data': jsonEncode({'gt': 'synthetic-v4-id'})
          })
        });
      }
      final aigis = r.headers['x-rpc-aigis']!.split(';');
      expect(aigis.first, 'synthetic-session');
      final proof = jsonDecode(utf8.decode(base64Decode(aigis.last)));
      expect(proof['captcha_id'], 'synthetic-v4-id');
      expect(proof['pass_token'], 'synthetic-pass');
      return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {'action_type': 'login'}
          }),
          200);
    }));
    addTearDown(client.close);
    await client.sendCode('13800000000', solve: (challenge) async {
      expect(challenge.isV4, isTrue);
      return {
        'lot_number': 'synthetic-lot',
        'captcha_output': 'synthetic-output',
        'pass_token': 'synthetic-pass',
        'gen_time': '123'
      };
    });
    expect(calls, 2);
  });
}
