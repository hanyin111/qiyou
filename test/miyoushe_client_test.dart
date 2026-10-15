import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qiyou/data/miyoushe_client.dart';
import 'package:qiyou/domain/models.dart';

const role = Role(
    game: Game.genshin,
    uid: '100000001',
    region: 'cn_gf01',
    nickname: 'Test',
    serverName: '天空岛');
const account = Account(
    id: '1',
    cookie: 'account_id=1; cookie_token=test-only',
    deviceId: 'device',
    roles: [role]);
http.Response response(Map<String, dynamic> data, {int retcode = 0}) =>
    http.Response(jsonEncode({'retcode': retcode, 'data': data}), 200);

void main() {
  test(
      'Cookie import accepts token values containing equals and masks debug output',
      () {
    final parsed = MiyousheClient.parseCookie(
        'Cookie: account_id_v2=1; cookie_token_v2=abc==;');
    expect(parsed['cookie_token_v2'], 'abc==');
    expect(account.toString(), isNot(contains('test-only')));
  });
  test('Malformed or injected credentials never appear in errors', () {
    for (final value in [
      'password=secret',
      'account_id=1; cookie_token=secret\r\nHost: evil.example'
    ]) {
      try {
        MiyousheClient.parseCookie(value);
        fail('must reject');
      } on MiyousheException catch (error) {
        expect(error.toString(), isNot(contains('secret')));
      }
    }
  });
  test('Discover only supported CN roles and deduplicate bindings', () async {
    final client = MiyousheClient(transport: MockClient((request) async {
      expect(request.url.scheme, 'https');
      expect(request.url.host, 'api-takumi.mihoyo.com');
      expect(request.followRedirects, isFalse);
      return response({
        'list': [
          {
            'game_biz': 'hk4e_cn',
            'game_uid': '100000001',
            'region': 'cn_gf01',
            'nickname': 'Traveler'
          },
          {
            'game_biz': 'hk4e_cn',
            'game_uid': '100000001',
            'region': 'cn_gf01',
            'nickname': 'Traveler'
          },
          {
            'game_biz': 'hk4e_global',
            'game_uid': '600000001',
            'region': 'os_usa'
          },
        ]
      });
    }));
    addTearDown(client.close);
    final result = await client.connect('account_id=1; cookie_token=test-only');
    expect(result.roles, hasLength(1));
    expect(result.roles.single.game, Game.genshin);
  });
  test('Already signed status never sends a write', () async {
    var requests = 0;
    final client = MiyousheClient(transport: MockClient((request) async {
      requests++;
      expect(request.method, 'GET');
      return response({'is_sign': true});
    }));
    addTearDown(client.close);
    expect(await client.sign(account, role), SignStatus.alreadySigned);
    expect(requests, 1);
  });
  test('Risk challenge in HTTP success must not count as a successful sign',
      () async {
    final client = MiyousheClient(
        transport: MockClient((request) async => request.method == 'GET'
            ? response({'is_sign': false})
            : response({'risk_code': 375, 'challenge': 'test-challenge'})));
    addTearDown(client.close);
    await expectLater(
        client.sign(account, role),
        throwsA(isA<MiyousheException>()
            .having((error) => error.kind, 'kind', ApiFailure.verification)));
  });
  test('Empty challenge with risk code zero is a valid successful sign',
      () async {
    var signed = false;
    final client = MiyousheClient(transport: MockClient((request) async {
      if (request.method == 'GET') return response({'is_sign': signed});
      signed = true;
      return response({'risk_code': 0, 'gt': '', 'challenge': ''});
    }));
    addTearDown(client.close);
    expect(await client.sign(account, role), SignStatus.signed);
  });
  test('Successful POST without confirmed official sign status is not success',
      () async {
    var writes = 0;
    final client = MiyousheClient(transport: MockClient((request) async {
      if (request.method == 'GET') return response({'is_sign': false});
      writes++;
      return response({'risk_code': 0});
    }));
    addTearDown(client.close);
    await expectLater(
        client.sign(account, role),
        throwsA(isA<MiyousheException>()
            .having((error) => error.message, 'message', contains('尚未确认'))));
    expect(writes, 1);
  });
  test('Expired login is surfaced without response body leakage', () async {
    final client = MiyousheClient(
        transport: MockClient((_) async =>
            response({'secret': 'do-not-display'}, retcode: -100)));
    addTearDown(client.close);
    await expectLater(
        client.daily(account, role),
        throwsA(isA<MiyousheException>()
            .having((error) => error.kind, 'kind', ApiFailure.expired)
            .having((error) => error.message, 'message',
                isNot(contains('do-not-display')))));
  });
  test('Uncertain POST failure is not retried automatically', () async {
    var writes = 0;
    final client = MiyousheClient(transport: MockClient((request) async {
      if (request.method == 'GET') return response({'is_sign': false});
      writes++;
      throw http.ClientException('request interrupted');
    }));
    addTearDown(client.close);
    await expectLater(
        client.sign(account, role), throwsA(isA<MiyousheException>()));
    expect(writes, 1);
  });
  test('Record signature uses the exact sorted transmitted query', () async {
    final at = DateTime.utc(2026, 10, 15);
    final client = MiyousheClient(
        clock: () => at,
        transport: MockClient((request) async {
          expect(request.url.query, 'role_id=100000001&server=cn_gf01');
          final ds = request.headers['DS'] ?? request.headers['ds']!;
          final parts = ds.split(',');
          expect(
              ds,
              MiyousheProtocol.signature(
                  timestamp: at.millisecondsSinceEpoch ~/ 1000,
                  nonce: parts[1],
                  query: request.url.query));
          return response({
            'current_resin': 100,
            'max_resin': 200,
            'resin_recovery_time': '48000'
          });
        }));
    addTearDown(client.close);
    expect((await client.daily(account, role)).energy, 100);
  });
  test(
      'Unknown daily fields stay unknown rather than inventing completed tasks',
      () {
    final note = DailyNote.parse(Game.zenless, {}, DateTime.utc(2026));
    expect(note.energy, isNull);
    expect(note.capacity, isNull);
    expect(note.metrics.first.complete, isFalse);
    expect(note.metrics.first.value, '暂未提供');
  });
  test('Recovery estimates clamp at zero and task reset day is Beijing time',
      () {
    final at = DateTime.utc(2026, 10, 14, 16);
    expect(chinaDay(at), '2026-10-15');
    final note = DailyNote(syncedAt: at, recoverySeconds: 10);
    expect(
        note.remainingAt(at.add(const Duration(seconds: 20))), Duration.zero);
  });
}
