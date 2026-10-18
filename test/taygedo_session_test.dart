import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qiyou/app_state.dart';
import 'package:qiyou/data/miyoushe_client.dart';
import 'package:qiyou/data/sync_crypto.dart';
import 'package:qiyou/data/sync_models.dart';
import 'package:qiyou/data/taygedo_client.dart';
import 'package:qiyou/domain/models.dart';
import 'package:qiyou/ui/design.dart';
import 'package:qiyou/ui/taygedo_login.dart';
import 'community_state_test.dart' show MemoryStore;

const role = Role(
    game: Game.nevernessToEverness,
    uid: '101',
    region: '1',
    nickname: 'Synthetic',
    serverName: 'Test');
const secondRole = Role(
    game: Game.nevernessToEverness,
    uid: '102',
    region: '2',
    nickname: 'Synthetic 2',
    serverName: 'Test 2');
const session = Account(
    id: 'taygedo:7',
    cookie: 'old-access',
    refreshToken: 'old-refresh',
    deviceId: 'original-device',
    community: Community.taygedo,
    roles: [role, secondRole]);
http.Response reply(dynamic data) =>
    http.Response(jsonEncode({'code': 0, 'data': data}), 200,
        headers: {'content-type': 'application/json'});
http.Response rotated() =>
    reply({'accessToken': 'new-access', 'refreshToken': 'new-refresh'});
http.Response note() => reply({'staminaValue': 80, 'staminaMaxValue': 240});
MemoryStore stored(Account account) => MemoryStore()
  ..saved = jsonEncode({
    'accounts': [account.toJson()],
    'tasks': [],
    'taskDay': chinaDay()
  });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Renewal uses only the official community endpoint and original device',
      () async {
    final requests = <http.Request>[];
    final client = TaygedoClient(transport: MockClient((r) async {
      requests.add(r);
      expect(r.url.toString(),
          'https://bbs-api.tajiduo.com/usercenter/api/refreshToken');
      expect(r.method, 'POST');
      expect(r.followRedirects, isFalse);
      expect(r.headers['authorization'], 'old-refresh');
      expect(r.headers['deviceid'], session.deviceId);
      expect(r.headers['uid'], '7');
      expect(r.headers['ds'], isNotEmpty);
      expect(r.headers.containsKey('cookie'), isFalse);
      expect(r.body, isEmpty);
      return rotated();
    }));
    addTearDown(client.close);
    final next = await client.renew(session.copyWith(recordHeaders: {
      'auth-type': 'cookie',
      'authorization': 'stale-override'
    }));
    expect(requests, hasLength(1));
    expect(next.cookie, 'new-access');
    expect(next.refreshToken, 'new-refresh');
    expect(next.deviceId, session.deviceId);
    expect(next.roles, session.roles);
    expect(next.recordHeaders.containsKey('authorization'), isFalse);
    expect(next.recordHeaders.containsKey('auth-type'), isFalse);
  });

  for (final bad in [
    {'accessToken': 'new-access'},
    {'accessToken': 'new-access', 'refreshToken': ''},
    {'accessToken': 'new-access', 'refreshToken': 'new-refresh', 'uid': '8'},
    {'accessToken': 'new-access', 'refreshToken': 'bad\nvalue'},
  ]) {
    test('Incomplete or mismatched rotation is rejected: ${bad.keys}',
        () async {
      final client =
          TaygedoClient(transport: MockClient((r) async => reply(bad)));
      addTearDown(client.close);
      await expectLater(
          client.renew(session), throwsA(isA<MiyousheException>()));
    });
  }

  test(
      'Refresh-only import uses no SDK login and preserves rotated credentials',
      () async {
    final paths = <String>[];
    final client = TaygedoClient(transport: MockClient((r) async {
      expect(r.url.host, 'bbs-api.tajiduo.com');
      paths.add(r.url.path);
      if (r.url.path.endsWith('refreshToken')) return rotated();
      expect(r.headers['authorization'], 'new-access');
      if (r.url.path.endsWith('getUserFullInfo')) {
        return reply({
          'user': {'uid': '7'}
        });
      }
      return reply([
        {
          'gameId': 1289,
          'bindRoleInfo': {'roleId': '101'}
        }
      ]);
    }));
    addTearDown(client.close);
    final account = await client.connect(jsonEncode(
        {'refreshToken': 'old-refresh', 'uid': '7', 'did': 'original-device'}));
    expect(account.cookie, 'new-access');
    expect(account.refreshToken, 'new-refresh');
    expect(account.deviceId, 'original-device');
    expect(paths, [
      '/usercenter/api/refreshToken',
      '/usercenter/api/getUserFullInfo',
      '/apihub/api/getGameRecordCard'
    ]);
  });

  test('Import requires original UID and device before any request', () async {
    var calls = 0;
    final client = TaygedoClient(transport: MockClient((r) async {
      calls++;
      return rotated();
    }));
    addTearDown(client.close);
    for (final field in ['uid', 'did']) {
      final input = {
        'refreshToken': 'old-refresh',
        'uid': '7',
        'did': 'original-device'
      }..remove(field);
      await expectLater(
          client.connect(jsonEncode(input)), throwsA(isA<MiyousheException>()));
    }
    expect(calls, 0);
  });

  testWidgets(
      'Failed discovery preserves rotated credentials in the masked form',
      (tester) async {
    var renewals = 0;
    final state = AppState(
        bridge: MemoryStore(),
        taygedo: TaygedoClient(transport: MockClient((r) async {
          expect(r.url.host, 'bbs-api.tajiduo.com');
          if (r.url.path.endsWith('refreshToken')) {
            renewals++;
            return rotated();
          }
          return http.Response('', 503);
        })));
    addTearDown(state.dispose);
    await state.initialize();
    await tester.pumpWidget(
        MaterialApp(theme: appTheme(), home: TaygedoLoginPage(state)));
    await tester.enterText(find.byType(TextField).at(0), 'old-refresh');
    await tester.enterText(find.byType(TextField).at(1), '7');
    await tester.enterText(find.byType(TextField).at(2), 'original-device');
    await tester.pump();
    await tester.ensureVisible(find.text('导入并连接'));
    await tester.tap(find.text('导入并连接'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.obscureText, isTrue);
    expect(field.controller!.text, 'new-refresh');
    expect(renewals, 1);
    expect(find.textContaining('新会话已保留'), findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (w) => w is Text && (w.data?.contains('new-refresh') ?? false)),
        findsNothing);
    expect(state.accounts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('Expired reads rotate once, persist before retry and survive restart',
      () async {
    final store = stored(session.copyWith(hiddenGames: {Game.towerOfFantasy}));
    var renewals = 0, oldReads = 0, newReads = 0;
    final client = TaygedoClient(transport: MockClient((r) async {
      expect(r.url.host, 'bbs-api.tajiduo.com');
      if (r.url.path.endsWith('refreshToken')) {
        renewals++;
        return rotated();
      }
      if (r.headers['authorization'] == 'old-access') {
        oldReads++;
        return http.Response('', 402);
      }
      expect(r.headers['authorization'], 'new-access');
      expect(store.saved, contains('new-refresh'));
      newReads++;
      return r.url.path.endsWith('roleHome')
          ? note()
          : reply({'todaySign': true});
    }));
    final state = AppState(bridge: store, taygedo: client);
    addTearDown(state.dispose);
    await state.initialize();
    expect(renewals, 1);
    expect(oldReads, 1);
    expect(newReads, 4);
    expect(state.accounts.single.hiddenGames, {Game.towerOfFantasy});
    expect(state.entries.every((e) => e.note?.energy == 80 && e.error == null),
        isTrue);
    final again = AppState(bridge: store, taygedo: client);
    await again.initialize();
    expect(renewals, 1);
    expect(again.accounts.single.refreshToken, 'new-refresh');
    again.dispose();
  });

  test('Invalid refresh token stops without SMS or game login fallback',
      () async {
    var renewals = 0;
    final state = AppState(
        bridge: stored(session),
        taygedo: TaygedoClient(transport: MockClient((r) async {
          expect(r.url.host, 'bbs-api.tajiduo.com');
          expect(r.url.path, isNot(contains('/login')));
          if (r.url.path.endsWith('refreshToken')) renewals++;
          return http.Response('', 402);
        })));
    addTearDown(state.dispose);
    await state.initialize();
    expect(renewals, 1);
    expect(state.accounts.single.cookie, 'old-access');
    expect(state.accounts.single.refreshToken, 'old-refresh');
    expect(state.entries.first.signStatus, SignStatus.expired);
  });

  test('Legacy accounts remain saved and explain missing refresh credentials',
      () async {
    final old = session.toJson()..remove('refreshToken');
    final store = stored(Account.fromJson(old));
    final state = AppState(
        bridge: store,
        taygedo: TaygedoClient(transport: MockClient((r) async {
          expect(r.method, 'GET');
          return http.Response('', 402);
        })));
    addTearDown(state.dispose);
    await state.initialize();
    expect(state.accounts.single.refreshToken, isNull);
    expect(state.entries.first.noteError, contains('旧会话'));
    expect(state.entries.first.signError, contains('不会自动执行短信登录'));
    expect(store.saved, contains('old-access'));
  });

  test(
      'Failed vault save retains rotation in memory and blocks further requests',
      () async {
    final store = stored(session)..reject = true;
    var calls = 0, renewals = 0;
    final state = AppState(
        bridge: store,
        taygedo: TaygedoClient(transport: MockClient((r) async {
          calls++;
          if (r.url.path.endsWith('refreshToken')) {
            renewals++;
            return rotated();
          }
          if (r.headers['authorization'] == 'old-access') {
            return http.Response('', 402);
          }
          expect(store.saved, contains('new-refresh'));
          return r.url.path.endsWith('roleHome')
              ? note()
              : reply({'todaySign': true});
        })));
    addTearDown(state.dispose);
    await state.initialize();
    expect(calls, 2);
    expect(state.accounts.single.refreshToken, 'new-refresh');
    expect(state.entries.first.noteError, contains('保留窗口'));
    expect(store.saved, contains('old-refresh'));
    store.reject = false;
    await state.refresh();
    expect(renewals, 1);
    expect(state.entries.every((e) => e.error == null), isTrue);
    expect(store.saved, contains('new-refresh'));
  });

  for (final confirmationLost in [false, true]) {
    test(
        'Sign preflight renews, sign POST is never replayed: lost=$confirmationLost',
        () async {
      final store = stored(session);
      var expired = false, posts = 0, renewals = 0;
      final state = AppState(
          bridge: store,
          taygedo: TaygedoClient(transport: MockClient((r) async {
            if (r.url.path.endsWith('refreshToken')) {
              renewals++;
              return rotated();
            }
            if (expired && r.headers['authorization'] == 'old-access') {
              return http.Response('', 402);
            }
            if (r.url.path.endsWith('/sign')) {
              posts++;
              return confirmationLost ? reply({}) : http.Response('', 402);
            }
            if (posts > 0) return http.Response('', 402);
            return r.url.path.endsWith('roleHome')
                ? note()
                : reply({'todaySign': false});
          })));
      addTearDown(state.dispose);
      await state.initialize();
      expired = true;
      await state.signAll(only: state.entries.first);
      expect(renewals, 1);
      expect(posts, 1);
      expect(state.entries.first.signStatus, SignStatus.expired);
      expect(store.saved, contains('new-refresh'));
    });
  }

  test(
      'Community refresh tokens are encrypted in sync and old backups remain valid',
      () async {
    final contents = SyncContents(
        accounts: [session],
        tasks: [],
        taskDay: chinaDay(),
        dark: false,
        hideUid: true);
    const crypto = SyncCrypto();
    final encrypted = await crypto.encrypt(
        SyncSnapshot.create(contents), 'Synthetic long password');
    expect(encrypted, isNot(contains('old-refresh')));
    final decoded = await crypto.decrypt(encrypted, 'Synthetic long password');
    expect(decoded.contents.accounts.single.refreshToken, 'old-refresh');
    final legacy = contents.toJson();
    (legacy['accounts'] as List).single.remove('refreshToken');
    expect(SyncContents.fromJson(legacy).accounts.single.refreshToken, isNull);
    final invalid = contents.toJson();
    (invalid['accounts'] as List).single['refreshToken'] = 'bad\nvalue';
    expect(() => SyncContents.fromJson(invalid), throwsA(isA<SyncException>()));
  });

  for (final dark in [false, true]) {
    testWidgets(
        'Session import is default; SMS requires acknowledgment, dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(390, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState(bridge: MemoryStore());
      addTearDown(state.dispose);
      await tester.pumpWidget(MaterialApp(
          theme: appTheme(dark: dark), home: TaygedoLoginPage(state)));
      expect(find.text('社区刷新令牌（refreshToken）'), findsOneWidget);
      expect(find.text('发送验证码'), findsNothing);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '导入并连接'))
              .onPressed,
          isNull);
      await tester.tap(find.text('短信登录'));
      await tester.pumpAndSettle();
      expect(find.textContaining('可能导致同通行证'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '13800000000');
      await tester.pump();
      expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '发送验证码'))
              .onPressed,
          isNull);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '发送验证码'))
              .onPressed,
          isNotNull);
      expect(tester.takeException(), isNull);
    });
  }
}
