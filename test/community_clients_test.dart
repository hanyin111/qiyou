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
      return reply(jsonEncode({
        'energyData': {'cur': 120, 'total': 240},
        'livenessData': {'cur': 100, 'total': 100}
      }));
    }));
    addTearDown(client.close);
    final note = await client.daily(kuroAccount, ww);
    expect(paths, ['/aki/roleBox/requestToken', '/gamer/widget/game3/getData']);
    expect(note.energy, 120);
    expect(note.metrics.first.complete, isTrue);
    expect(note.recoverySeconds, isNull);
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
