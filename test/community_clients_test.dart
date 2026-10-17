import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qiyou/data/community_http.dart';
import 'package:qiyou/data/community_login_session.dart';
import 'package:qiyou/data/kuro_client.dart';
import 'package:qiyou/data/taygedo_client.dart';
import 'package:qiyou/data/miyoushe_client.dart';
import 'package:qiyou/domain/models.dart';
import 'package:qiyou/ui/official_login.dart';

http.Response reply(Object? data, {int code = 0}) =>
    http.Response(jsonEncode({'code': code, 'data': data}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
const ww = Role(
    game: Game.wutheringWaves,
    uid: '1001',
    region: 'actual-server',
    nickname: '漂泊者',
    serverName: '国服');
const pgr = Role(
    game: Game.punishingGrayRaven,
    uid: '1002',
    region: '1000',
    nickname: '指挥官',
    serverName: '国服');
const nte = Role(
    game: Game.nevernessToEverness,
    uid: '2001',
    region: '1',
    nickname: '鉴定师',
    serverName: '国服');
const tof = Role(
    game: Game.towerOfFantasy,
    uid: '2002',
    region: '2',
    nickname: '拓荒者',
    serverName: '国服');
const kuroAccount = Account(
    id: 'kuro:7',
    cookie: 'synthetic-kuro',
    deviceId: 'test-device',
    community: Community.kuro,
    roles: [ww, pgr]);
const tjdAccount = Account(
    id: 'taygedo:7',
    cookie: 'synthetic-tjd',
    deviceId: 'test-device',
    community: Community.taygedo,
    roles: [nte, tof]);

void main() {
  test('Taygedo accepts private API Cookie login without localStorage token',
      () async {
    final input = communityLoginCredential(Community.taygedo, {
      'token': null,
      'user-agent': 'synthetic-browser'
    }, apiCookies: {
      'tjd_session': 'synthetic-session',
      'bad\r\nname': 'discard'
    });
    final values = communityCredential(input, allowCookie: true);
    expect(values['cookie'], 'tjd_session=synthetic-session');
    expect(values.containsKey('token'), isFalse);
    final requests = <http.Request>[];
    final client = TaygedoClient(transport: MockClient((request) async {
      requests.add(request);
      if (request.url.path.contains('getUserFullInfo')) {
        return reply({
          'user': {'uid': '7'}
        });
      }
      if (request.url.path.contains('getGameRecordCard')) {
        return reply([
          {
            'gameId': 1289,
            'bindRoleInfo': {'roleId': 2001}
          }
        ]);
      }
      return reply({'todaySign': true});
    }));
    addTearDown(client.close);
    final account = await client.connect(input);
    final restored = Account.fromJson(account.toJson());
    expect(await client.signInfo(restored, restored.roles.single),
        SignStatus.alreadySigned);
    for (final request in requests) {
      expect(request.headers['cookie'], 'tjd_session=synthetic-session');
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(request.headers['origin'], 'https://www.tajiduo.com');
    }
    // The same JSON envelope must never turn a Kuro token into Cookie auth.
    expect(() => communityCredential(input), throwsA(isA<MiyousheException>()));
  });
  test('Kuro uses the browser login device instead of an unrelated saved ID',
      () async {
    final client = KuroClient(transport: MockClient((request) async {
      expect(request.headers['devcode'], 'official-browser-dc');
      expect(request.headers['did'], 'official-browser-dc');
      if (request.url.path.endsWith('/list')) {
        return reply([
          {'userId': '7', 'roleId': '1001', 'serverId': 'real-server'}
        ]);
      }
      return reply({'accessToken': 'synthetic-data-token'});
    }));
    addTearDown(client.close);
    final account = await client.connect(
        jsonEncode({
          'token': 'synthetic-kuro',
          'did': 'official-browser-dc',
          'devcode': 'official-browser-dc'
        }),
        existingDeviceId: 'unrelated-old-device');
    expect(account.deviceId, 'official-browser-dc');
    expect(communitySessionScript(Community.kuro), contains("getItem('dc')"));
  });
  test('Kuro 10901 identifies failing step and redacts credentials', () async {
    final client = KuroClient(
        transport: MockClient((request) async => http.Response(
            jsonEncode({'code': 10901, 'msg': '设备 synthetic-kuro test-device'}),
            200,
            headers: {'content-type': 'application/json'})));
    addTearDown(client.close);
    await expectLater(
        client.daily(kuroAccount, ww),
        throwsA(isA<MiyousheException>()
            .having((e) => e.message, 'operation', contains('获取鸣潮数据令牌'))
            .having((e) => e.message.contains('synthetic-kuro'),
                'token redacted', isFalse)
            .having((e) => e.message.contains('test-device'), 'device redacted',
                isFalse)));
  });
  test('Old encrypted account schema migrates to MiYouShe', () {
    final old = {
      'id': '7',
      'cookie': 'synthetic',
      'deviceId': 'device',
      'roles': <Object>[]
    };
    expect(Account.fromJson(old).community, Community.miyoushe);
    for (final a in [kuroAccount, tjdAccount]) {
      final restored = Account.fromJson(a.toJson());
      expect(restored.community, a.community);
      expect(restored.roles.map((r) => r.key), a.roles.map((r) => r.key));
      expect(restored.toString(), isNot(contains(a.cookie)));
    }
  });
  test('Official login navigation and session reads are provider scoped', () {
    expect(
        isOfficialLoginUrl(Uri.parse('https://www.kurobbs.com/mc/'),
            community: Community.kuro),
        isTrue);
    expect(
        isOfficialLoginUrl(Uri.parse('https://id.wanmei.com/'),
            community: Community.taygedo),
        isTrue);
    for (final value in [
      'https://kurobbs.com.evil.example/',
      'http://www.kurobbs.com/',
      'https://www.tajiduo.com/'
    ]) {
      expect(isOfficialLoginUrl(Uri.parse(value), community: Community.kuro),
          isFalse);
    }
    expect(communitySessionScript(Community.kuro),
        contains("getItem('auth_token')"));
    expect(communitySessionScript(Community.taygedo),
        contains("getItem('token')"));
    expect(
        () => communityLoginCredential(Community.kuro, {'token': 'synthetic'}),
        throwsA(isA<MiyousheException>()));
    final session = communityCredential(jsonEncode({
      'token': 'synthetic',
      'Cookie': 'must-discard',
      'authorization': 'discard',
      'url': 'https://evil.example',
      'user-agent': 'test-browser'
    }));
    expect(session.keys, unorderedEquals(['token', 'user-agent']));
    expect(() => communityCredential('bad\r\nAuthorization: value'),
        throwsA(isA<MiyousheException>()));
  });
  test('Kuro discovers both bound games and requires real server and owner',
      () async {
    final client = KuroClient(transport: MockClient((request) async {
      expect(request.url.host, 'api.kurobbs.com');
      expect(request.headers['token'], 'synthetic-kuro');
      expect(request.followRedirects, isFalse);
      final game = request.bodyFields['gameId'];
      return reply([
        {
          'roleId': game == '3' ? '1001' : '1002',
          'serverId': 'returned-server',
          'userId': '7',
          'roleName': '角色',
          'gameLevel': '35'
        }
      ], code: 200);
    }));
    addTearDown(client.close);
    final account = await client.connect('synthetic-kuro');
    expect(account.id, 'kuro:7');
    expect(account.roles.map((r) => r.game),
        [Game.wutheringWaves, Game.punishingGrayRaven]);
    expect(account.roles.first.region, 'returned-server');
    expect(account.roles.first.level, 35);
  });
  test(
      'Kuro obtains role-scoped data token and decodes JSON-string widget data',
      () async {
    final paths = <String>[];
    final client = KuroClient(transport: MockClient((request) async {
      paths.add(request.url.path);
      expect(request.bodyFields['serverId'], ww.region);
      if (request.url.path.endsWith('requestToken')) {
        return reply({'accessToken': 'synthetic-data-token'});
      }
      expect(request.headers['b-at'], 'synthetic-data-token');
      expect(request.bodyFields['gameId'], '3');
      if (request.url.path.endsWith('refreshData')) {
        expect(request.headers.containsKey('token'), isFalse);
        expect(request.headers['origin'], 'https://web-static.kurobbs.com');
        return reply(true);
      }
      return reply(jsonEncode({
        'energyData': {'cur': 120, 'total': 240},
        'livenessData': {'cur': 100, 'total': 100}
      }));
    }));
    addTearDown(client.close);
    final note = await client.daily(kuroAccount, ww);
    expect(paths, [
      '/aki/roleBox/requestToken',
      '/aki/roleBox/akiBox/refreshData',
      '/gamer/widget/game3/getData'
    ]);
    expect(note.energy, 120);
    expect(note.metrics.first.complete, isTrue);
    expect(note.recoverySeconds, isNull);
  });
  test(
      'Wuthering Waves refreshes stale 52 energy to current 1 before reading recovery deadline',
      () async {
    final now = DateTime.utc(2026, 10, 17, 7);
    final paths = <String>[];
    var refreshed = false;
    final client = KuroClient(
        clock: () => now,
        transport: MockClient((r) async {
          paths.add(r.url.path);
          if (r.url.path.endsWith('requestToken')) {
            return reply({'accessToken': 'synthetic-data-token'});
          }
          expect(r.headers['b-at'], 'synthetic-data-token');
          expect(r.bodyFields['roleId'], ww.uid);
          expect(r.bodyFields['serverId'], ww.region);
          if (r.url.path.endsWith('refreshData')) {
            expect(r.bodyFields,
                {'gameId': '3', 'serverId': ww.region, 'roleId': ww.uid});
            refreshed = true;
            expect(r.headers.containsKey('token'), isFalse);
            return reply(true);
          }
          return reply({
            'roleId': ww.uid,
            'serverId': ww.region,
            'energyData': {
              'cur': refreshed ? 1 : 52,
              'total': 240,
              'refreshTimeStamp': now
                      .add(const Duration(hours: 23, minutes: 54))
                      .millisecondsSinceEpoch ~/
                  1000
            }
          });
        }));
    addTearDown(client.close);
    final note = await client.daily(kuroAccount, ww);
    expect(note.energy, 1);
    expect(note.recoverySeconds, 86040);
    expect(note.remainingAt(now.add(const Duration(minutes: 10)))?.inSeconds,
        85440);
    expect(paths, [
      '/aki/roleBox/requestToken',
      '/aki/roleBox/akiBox/refreshData',
      '/gamer/widget/game3/getData'
    ]);
  });
  test(
      'Failed Wuthering Waves refresh never falls back to reading stale widget data',
      () async {
    final paths = <String>[];
    final client = KuroClient(transport: MockClient((r) async {
      paths.add(r.url.path);
      if (r.url.path.endsWith('requestToken')) {
        return reply({'accessToken': 'synthetic-data-token'});
      }
      return reply(null, code: 500);
    }));
    addTearDown(client.close);
    await expectLater(
        client.daily(kuroAccount, ww), throwsA(isA<MiyousheException>()));
    expect(paths,
        ['/aki/roleBox/requestToken', '/aki/roleBox/akiBox/refreshData']);
  });
  test(
      'Wuthering Waves recovery handles seconds, milliseconds, zero energy and full capacity',
      () {
    final now = DateTime.utc(2026, 10, 17, 7);
    DailyNote parse(int cur, Object? deadline) => DailyNote.parse(
        Game.wutheringWaves,
        {
          'energyData': {'cur': cur, 'total': 240, 'refreshTimeStamp': deadline}
        },
        now);
    final end = now.add(const Duration(hours: 24));
    expect(parse(0, end.millisecondsSinceEpoch ~/ 1000).recoverySeconds, 86400);
    expect(parse(0, end.millisecondsSinceEpoch).recoverySeconds, 86400);
    expect(parse(240, null).recoverySeconds, 0);
    for (final value in [
      null,
      0,
      3600,
      (now.millisecondsSinceEpoch ~/ 1000) - 1
    ]) {
      expect(parse(1, value).recoverySeconds, isNull);
    }
  });
  test('Wuthering Waves does not display another returned role', () async {
    final client = KuroClient(transport: MockClient((r) async {
      if (r.url.path.endsWith('requestToken')) {
        return reply({'accessToken': 'synthetic-data-token'});
      }
      if (r.url.path.endsWith('refreshData')) {
        return reply(true);
      }
      return reply({
        'roleId': 'other-role',
        'energyData': {'cur': 52, 'total': 240}
      });
    }));
    addTearDown(client.close);
    await expectLater(
        client.daily(kuroAccount, ww), throwsA(isA<MiyousheException>()));
  });
  test('Refresh uses only data auth while widget and sign keep community auth',
      () async {
    var refreshed = false;
    final account = kuroAccount.copyWith(recordHeaders: {
      'user-agent': 'actual-browser-UA',
      'devcode': 'actual-device'
    });
    final client = KuroClient(transport: MockClient((r) async {
      if (r.url.path.endsWith('requestToken')) {
        expect(r.headers['token'], account.cookie);
        return reply({'accessToken': 'synthetic-data-token'});
      }
      expect(r.headers['did'], account.deviceId);
      expect(r.headers['user-agent'], 'actual-browser-UA');
      if (r.url.path.endsWith('refreshData')) {
        // Reproduce the server behaviour that the old test doubles omitted.
        if (r.headers.containsKey('token')) return reply(null, code: 10000);
        expect(r.headers['b-at'], 'synthetic-data-token');
        expect(r.headers['origin'], 'https://web-static.kurobbs.com');
        expect(r.headers['x-requested-with'], 'com.kurogame.kjq');
        expect(r.bodyFields.keys.toList(), ['gameId', 'roleId', 'serverId']);
        refreshed = true;
        return reply(true, code: 200);
      }
      expect(r.headers['token'], account.cookie);
      if (r.url.path.endsWith('initSignInV2')) {
        expect(r.headers.containsKey('b-at'), isFalse);
        return reply({'isSigIn': true});
      }
      expect(refreshed, isTrue);
      return reply({
        'energyData': {'cur': 1, 'total': 240}
      });
    }));
    addTearDown(client.close);
    expect((await client.daily(account, ww)).energy, 1);
    expect(await client.signInfo(account, ww), SignStatus.alreadySigned);
  });
  for (final refreshResult in [false, null]) {
    test('Unconfirmed refresh ($refreshResult) never reads stale widget',
        () async {
      final paths = <String>[];
      final client = KuroClient(transport: MockClient((r) async {
        paths.add(r.url.path);
        if (r.url.path.endsWith('requestToken')) {
          return reply({'accessToken': 'synthetic-data-token'});
        }
        return reply(refreshResult, code: 200);
      }));
      addTearDown(client.close);
      await expectLater(
          client.daily(kuroAccount, ww),
          throwsA(isA<MiyousheException>()
              .having((e) => e.message, 'message', contains('未确认鸣潮数据刷新'))));
      expect(paths,
          ['/aki/roleBox/requestToken', '/aki/roleBox/akiBox/refreshData']);
    });
  }
  test('10000 identifies refresh stage and redacts official error text',
      () async {
    final api = CommunityHttp(Community.kuro, 'api.kurobbs.com',
        transport: MockClient((r) async => http.Response(
            jsonEncode({
              'code': 10000,
              'msg': '参数错误 synthetic-secret-data-token 123456789'
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'})));
    addTearDown(api.close);
    await expectLater(
        api.request('/aki/roleBox/akiBox/refreshData',
            {'b-at': 'synthetic-secret-data-token'},
            form: {'roleId': '123456789'}),
        throwsA(isA<MiyousheException>()
            .having((e) => e.message, 'stage', contains('刷新鸣潮数据失败'))
            .having((e) => e.message, 'code', contains('10000'))
            .having((e) => e.message, 'token',
                isNot(contains('synthetic-secret-data-token')))
            .having((e) => e.message, 'role', isNot(contains('123456789')))));
  });
  test('PGR uses serum and activity data without a Wuthering Waves data token',
      () async {
    final client = KuroClient(transport: MockClient((request) async {
      expect(request.url.path, '/haru/roleBox/dailyData');
      expect(request.bodyFields['gameId'], '2');
      expect(request.headers.containsKey('b-at'), isFalse);
      return reply({
        'actionData': {'cur': 80, 'total': 240},
        'activeData': {'cur': 20, 'total': 100}
      });
    }));
    addTearDown(client.close);
    final note = await client.daily(kuroAccount, pgr);
    expect(note.energy, 80);
    expect(note.metrics.first.value, '20 / 100');
  });
  test('Kuro sign submits exact role and China month then confirms state',
      () async {
    var signed = false;
    var posts = 0;
    final client = KuroClient(
        clock: () => DateTime.utc(2026, 9, 30, 18),
        transport: MockClient((request) async {
          if (request.url.path.endsWith('/v2')) {
            posts++;
            expect(request.bodyFields, {
              'gameId': '3',
              'serverId': ww.region,
              'roleId': ww.uid,
              'userId': '7',
              'reqMonth': '10'
            });
            signed = true;
            return reply({});
          }
          return reply({'isSigIn': signed});
        }));
    addTearDown(client.close);
    expect(await client.sign(kuroAccount, ww), SignStatus.signed);
    expect(await client.sign(kuroAccount, ww), SignStatus.alreadySigned);
    expect(posts, 1);
  });
  test('Taygedo validates its own profile and reads only bound record cards',
      () async {
    final client = TaygedoClient(transport: MockClient((request) async {
      expect(request.url.host, 'bbs-api.tajiduo.com');
      expect(request.headers['authorization'], 'synthetic-tjd');
      if (request.url.path.contains('getUserFullInfo')) {
        return reply({
          'user': {'uid': '7'}
        });
      }
      expect(request.url.queryParameters['uid'], '7');
      expect(request.headers['uid'], '7');
      expect(request.headers['ds'], isNotEmpty);
      return reply([
        {
          'gameId': 1289,
          'bindRoleInfo': {
            'roleId': 2001,
            'serverId': 1,
            'roleName': '鉴定师',
            'lev': 30
          }
        },
        {
          'gameId': 1256,
          'bindRoleInfo': {'roleId': 2002, 'serverId': 2}
        },
        {
          'gameId': 9999,
          'bindRoleInfo': {'roleId': 9000}
        },
      ]);
    }));
    addTearDown(client.close);
    final account = await client.connect('synthetic-tjd');
    expect(account.id, 'taygedo:7');
    expect(account.roles, hasLength(2));
    expect(account.roles.first.level, 30);
    expect(account.community, Community.taygedo);
  });
  test('NTE daily maps pixel stamina and city stamina without inventing fields',
      () async {
    final client = TaygedoClient(transport: MockClient((request) async {
      expect(request.url.path, '/apihub/awapi/yh/roleHome');
      expect(request.url.queryParameters['roleId'], nte.uid);
      return reply({
        'staminaValue': '80',
        'staminaMaxValue': 240,
        'citystaminaValue': 25,
        'citystaminaMaxValue': 60
      });
    }));
    addTearDown(client.close);
    final note = await client.daily(tjdAccount, nte);
    expect(note.energy, 80);
    expect(note.metrics.first.value, '25 / 60');
    expect(note.metrics.last.value, '暂未提供');
    final ht = await client.daily(tjdAccount, tof);
    expect(ht.energy, isNull);
    expect(ht.metrics.single.value, '此版本暂不支持');
  });
  for (final accepted in [true, false]) {
    test('Taygedo confirms sign after write: confirmed=$accepted', () async {
      var wrote = false;
      var writes = 0;
      final client = TaygedoClient(transport: MockClient((request) async {
        if (request.url.path.endsWith('/sign')) {
          expect(request.bodyFields, {'roleId': nte.uid, 'gameId': '1289'});
          wrote = true;
          writes++;
          return reply({});
        }
        return reply({'todaySign': wrote && accepted});
      }));
      addTearDown(client.close);
      if (accepted) {
        expect(await client.sign(tjdAccount, nte), SignStatus.signed);
        expect(await client.sign(tjdAccount, nte), SignStatus.alreadySigned);
      } else {
        await expectLater(
            client.sign(tjdAccount, nte), throwsA(isA<MiyousheException>()));
      }
      expect(writes, 1);
    });
  }
  test('Missing sign state never triggers a blind sign write', () async {
    var count = 0;
    final client = TaygedoClient(transport: MockClient((request) async {
      count++;
      return reply({'days': 2});
    }));
    addTearDown(client.close);
    await expectLater(
        client.sign(tjdAccount, nte), throwsA(isA<MiyousheException>()));
    expect(count, 1);
  });
  test(
      'Community errors never expose upstream payload or cross-route credentials',
      () async {
    var count = 0;
    final client = KuroClient(transport: MockClient((request) async {
      count++;
      return http.Response(
          jsonEncode({'code': 270, 'msg': 'synthetic-secret'}), 200);
    }));
    addTearDown(client.close);
    await expectLater(
        client.daily(tjdAccount, nte), throwsA(isA<MiyousheException>()));
    expect(count, 0);
    await expectLater(
        client.signInfo(kuroAccount, ww),
        throwsA(isA<MiyousheException>()
            .having((e) => e.kind, 'kind', ApiFailure.verification)
            .having((e) => e.message.contains('synthetic-secret'), 'redacted',
                isFalse)));
  });
  test('Uncertain sign write is never automatically retried', () async {
    var writes = 0;
    final client = KuroClient(transport: MockClient((request) async {
      if (request.url.path.endsWith('/v2')) {
        writes++;
        throw http.ClientException('synthetic-token');
      }
      return reply({'isSigIn': false});
    }));
    addTearDown(client.close);
    await expectLater(
        client.sign(kuroAccount, ww),
        throwsA(isA<MiyousheException>().having(
            (e) => e.message.contains('synthetic-token'),
            'redacted',
            isFalse)));
    expect(writes, 1);
  });
}
