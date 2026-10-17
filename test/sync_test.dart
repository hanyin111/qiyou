import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qiyou/app_state.dart';
import 'package:qiyou/data/sync_crypto.dart';
import 'package:qiyou/data/sync_models.dart';
import 'package:qiyou/data/webdav_sync.dart';
import 'package:qiyou/domain/models.dart';
import 'package:qiyou/ui/design.dart';
import 'package:qiyou/ui/sync_page.dart';
import 'community_state_test.dart' show MemoryStore, StubCommunity;

const password = 'Synthetic sync password';
// Python hashlib.scrypt + cryptography AESGCM; independent of PointyCastle.
const independentFixture =
    '''{"format":"qiyou-encrypted-vault","version":1,"kdf":"scrypt","n":32768,"r":8,"p":1,"cipher":"AES-256-GCM","salt":"AAECAwQFBgcICQoLDA0ODw==","nonce":"AAECAwQFBgcICQoL","ciphertext":"SQk8Rt/AZQ9DDbt3d30Si0gYlezBc6Lok16LEbh7Qg4U+zU5LeaWVr1vQVv387HJVzgkRndZjN5x+i5y/9Nj86I5hvFUHMBdXCP0EqIPqJddngr1VygB0sf57fvd5GvD4oUhoUyXFppRLM17bO9Lb35sBYg58PSLph9U3hXALEso42fjOPLXuEGAkxUrHaLgPq2PwIl2vY65PCvmZmiNvOHGw52PICdvu4SUmlIrK+lMvj7UpgzJlRUApTQDFqL0b3VjtDGrM81m1Q=="}''';

SyncContents contents(
        {List<Account> accounts = const [],
        List<RoutineTask> tasks = const [],
        String? day,
        bool dark = false}) =>
    SyncContents(
        accounts: accounts,
        tasks: tasks,
        taskDay: day ?? chinaDay(),
        dark: dark,
        hideUid: true);

// UI navigation only; real encryption is tested separately below.
class UiCrypto extends SyncCrypto {
  SyncSnapshot? last;
  @override
  Future<String> encrypt(SyncSnapshot snapshot, String password) async {
    last = snapshot;
    return 'synthetic-ui-ciphertext';
  }

  @override
  Future<SyncSnapshot> decrypt(String file, String password) async => last!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const crypto = SyncCrypto();
  final connection = SyncConnection('https://dav.example.test/my%20folder/',
      'synthetic-user', 'synthetic-dav-secret');

  test('Decrypts independent scrypt AES-GCM fixture', () async {
    final snapshot = await crypto.decrypt(independentFixture, password);
    expect(snapshot.revision, '0123456789abcdef0123456789abcdef');
    expect(snapshot.contents.taskDay, '2026-10-17');
    expect(snapshot.contents.accounts, isEmpty);
  });

  test('Sync password cannot equal server authentication password', () async {
    var requests = 0;
    final client =
        WebDavSyncClient(connection, transport: MockClient((r) async {
      requests++;
      return http.Response('', 404);
    }));
    addTearDown(client.close);
    await expectLater(
        client.download(connection.password), throwsA(isA<SyncException>()));
    await expectLater(
        client.upload(SyncSnapshot.create(contents()), connection.password,
            previous: null),
        throwsA(isA<SyncException>()));
    expect(requests, 0);
  });

  testWidgets(
      'Upload requires preview and matching confirmation, then download merges without signing',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState(bridge: MemoryStore());
    addTearDown(state.dispose);
    await state.initialize();
    String? file;
    var puts = 0;
    final uiCrypto = UiCrypto();
    WebDavSyncClient factory(SyncConnection config) =>
        WebDavSyncClient(config, crypto: uiCrypto,
            transport: MockClient((r) async {
          if (r.method == 'PUT') {
            puts++;
            file = r.body;
            return http.Response('', 201);
          }
          return file == null
              ? http.Response('', 404)
              : http.Response(file!, 200, headers: {'etag': '"v1"'});
        }));
    await tester.pumpWidget(MaterialApp(
        theme: appTheme(),
        home: SyncPage(state: state, clientFactory: factory)));
    await tester.enterText(
        find.byType(TextField).at(0), connection.folder.toString());
    await tester.enterText(find.byType(TextField).at(1), connection.username);
    await tester.enterText(find.byType(TextField).at(2), connection.password);
    await tester.ensureVisible(find.byType(TextField).at(3));
    await tester.enterText(find.byType(TextField).at(3), password);
    await tester.ensureVisible(find.text('上传到云端'));
    await tester.tap(find.text('上传到云端'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('创建加密备份'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认上传'))
            .onPressed,
        isNull);
    await tester.enterText(find.byType(TextField).last, 'wrong');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认上传'))
            .onPressed,
        isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(puts, 0);
    await tester.tap(find.text('上传到云端'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byType(TextField).last, password);
    await tester.pump();
    await tester.tap(find.text('确认上传'));
    await tester.pumpAndSettle();
    expect(puts, 1);
    expect(find.textContaining('加密备份已上传并确认'), findsWidgets);
    await tester.tap(find.text('从云端下载'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('合并云端备份'), findsOneWidget);
    await tester.tap(find.text('合并到本机'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已合并并加密保存到本机'), findsWidgets);
    expect(state.activities.single.text, contains('已合并云端账号'));
    expect(tester.takeException(), isNull);
  });

  test(
      'Randomized authenticated backups hide credentials and reject wrong keys and tampering',
      () async {
    final account = await StubCommunity(Community.kuro, Game.wutheringWaves)
        .connect('synthetic-community-token');
    final snapshot = SyncSnapshot.create(contents(accounts: [account]));
    final one = await crypto.encrypt(snapshot, password);
    final two = await crypto.encrypt(snapshot, password);
    expect(one, isNot(two));
    expect(one, isNot(contains(account.cookie)));
    expect(one, isNot(contains(account.deviceId)));
    expect(one, isNot(contains(password)));
    final opened = await crypto.decrypt(one, password);
    expect(opened.contents.accounts.single.cookie, account.cookie);
    await expectLater(crypto.decrypt(one, 'Wrong sync password'),
        throwsA(isA<SyncException>()));
    final tampered = jsonDecode(one) as Map<String, dynamic>;
    final bytes = base64Decode(tampered['ciphertext'] as String)..[0] ^= 1;
    tampered['ciphertext'] = base64Encode(bytes);
    await expectLater(crypto.decrypt(jsonEncode(tampered), password),
        throwsA(isA<SyncException>()));
  });

  test('Rejects hostile KDF parameters, oversize files and weak sync passwords',
      () async {
    final hostile = jsonDecode(independentFixture) as Map<String, dynamic>;
    hostile['n'] = 1073741824;
    await expectLater(crypto.decrypt(jsonEncode(hostile), password),
        throwsA(isA<SyncException>()));
    await expectLater(crypto.decrypt('x' * (maxSyncFile + 1), password),
        throwsA(isA<SyncException>()));
    expect(() => validateSyncPassword('short'), throwsA(isA<SyncException>()));
  });

  test(
      'WebDAV folder validation requires HTTPS without embedded credentials or query',
      () {
    for (final url in [
      'http://dav.example.test/',
      'https://u:p@dav.example.test/',
      'https://dav.example.test/?token=x',
      'https://dav.example.test/#fragment'
    ]) {
      expect(
          () => SyncConnection(url, 'u', 'p'), throwsA(isA<SyncException>()));
    }
    expect(connection.file.toString(),
        'https://dav.example.test/my%20folder/qiyou-vault-v1.json');
    expect(connection.toString(), isNot(contains(connection.password)));
  });

  test(
      'Two devices upload, download and preserve matching credentials via conditional WebDAV',
      () async {
    String? file;
    var etag = '"v1"';
    final requests = <http.Request>[];
    final transport = MockClient((r) async {
      requests.add(r);
      expect(r.followRedirects, isFalse);
      expect(r.url.host, 'dav.example.test');
      expect(r.headers['authorization'],
          'Basic ${base64Encode(utf8.encode('synthetic-user:synthetic-dav-secret'))}');
      expect(r.body, isNot(contains(password)));
      if (r.method == 'PUT') {
        if (file == null) {
          expect(r.headers['if-none-match'], '*');
        } else {
          expect(r.headers['if-match'], etag);
          etag = '"v2"';
        }
        file = r.body;
        return http.Response('', 201);
      }
      if (r.method == 'PROPFIND') {
        expect(r.headers['depth'], '0');
        return http.Response('<d:multistatus xmlns:d="DAV:"/>', 207);
      }
      return file == null
          ? http.Response('', 404)
          : http.Response(file!, 200, headers: {'etag': etag});
    });
    final client = WebDavSyncClient(connection, transport: transport);
    addTearDown(client.close);
    await client.testConnection();
    expect(await client.download(password), isNull);
    final kuro = StubCommunity(Community.kuro, Game.wutheringWaves);
    final source = AppState(bridge: MemoryStore(), kuro: kuro);
    final destinationStore = MemoryStore();
    final destination = AppState(bridge: destinationStore, kuro: kuro);
    addTearDown(source.dispose);
    addTearDown(destination.dispose);
    await source.initialize();
    await destination.initialize();
    await source.connect('synthetic-account-secret', community: Community.kuro);
    final snapshot = SyncSnapshot.create(source.exportSyncContents());
    await client.upload(snapshot, password, previous: null);
    final downloaded = (await client.download(password))!;
    await destination.importSyncContents(downloaded.snapshot.contents,
        expectedFingerprint: destination.exportSyncContents().fingerprint);
    expect(destination.accounts.single.cookie, 'synthetic-account-secret');
    expect(
        destination.accounts.single.deviceId, source.accounts.single.deviceId);
    expect(destination.entries.single.signStatus, SignStatus.unknown);
    expect(requests.where((r) => r.method == 'POST'), isEmpty);
    expect(file, isNot(contains('synthetic-account-secret')));
    await client.upload(
        SyncSnapshot.create(source.exportSyncContents()), password,
        previous: downloaded);
    final restored = AppState(bridge: destinationStore, kuro: kuro);
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.accounts.single.cookie, destination.accounts.single.cookie);
  });

  test('412 stops after one PUT and missing strong ETag never overwrites',
      () async {
    var puts = 0;
    final client =
        WebDavSyncClient(connection, transport: MockClient((r) async {
      puts++;
      return http.Response('private server text must not be shown', 412);
    }));
    addTearDown(client.close);
    final snapshot = SyncSnapshot.create(contents());
    await expectLater(
        client.upload(snapshot, password,
            previous: RemoteVault(snapshot, '"old"')),
        throwsA(isA<SyncException>().having((e) => e.message, 'message',
            isNot(contains('private server text')))));
    expect(puts, 1);
    for (final tag in [null, 'W/"weak"', 'unquoted']) {
      await expectLater(
          client.upload(snapshot, password,
              previous: RemoteVault(snapshot, tag)),
          throwsA(isA<SyncException>()));
    }
    expect(puts, 1);
  });

  test(
      'Redirects, authentication failures and unsupported folder responses are sanitized',
      () async {
    for (final code in [307, 401, 403, 404]) {
      var count = 0;
      final client =
          WebDavSyncClient(connection, transport: MockClient((r) async {
        count++;
        expect(r.followRedirects, isFalse);
        return http.Response('synthetic-sensitive-response', code,
            headers: {'location': 'https://other.example.test/stolen'});
      }));
      await expectLater(
          client.testConnection(),
          throwsA(isA<SyncException>().having((e) => e.message, 'message',
              isNot(contains('synthetic-sensitive-response')))));
      expect(count, 1);
      client.close();
    }
  });

  test(
      'Merge keeps newer local sessions by default and persists local-only DAV config',
      () async {
    final store = MemoryStore();
    final kuro = StubCommunity(Community.kuro, Game.wutheringWaves);
    final tjd = StubCommunity(Community.taygedo, Game.nevernessToEverness);
    final state = AppState(bridge: store, kuro: kuro, taygedo: tjd);
    addTearDown(state.dispose);
    await state.initialize();
    await state.connect('local-new', community: Community.kuro);
    await state.saveSyncConnection(connection);
    final remote = contents(accounts: [
      await kuro.connect('remote-old'),
      await tjd.connect('remote-new')
    ], tasks: [
      RoutineTask(
          id: 'task-1', game: Game.genshin, title: 'Old task', done: true)
    ], day: '2020-01-01', dark: true);
    await state.importSyncContents(remote,
        expectedFingerprint: state.exportSyncContents().fingerprint);
    expect(state.accounts, hasLength(2));
    expect(state.accounts.first.cookie, 'local-new');
    expect(state.tasks.single.done, isFalse);
    expect(state.dark, isTrue);
    expect(jsonEncode(state.exportSyncContents().toJson()),
        isNot(contains(connection.password)));
    final restored = AppState(bridge: store, kuro: kuro, taygedo: tjd);
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.syncConnection?.password, connection.password);
    await state.importSyncContents(remote,
        expectedFingerprint: state.exportSyncContents().fingerprint,
        preferRemoteSessions: true);
    expect(state.accounts.first.cookie, 'remote-old');
    await state.saveSyncConnection(null);
    expect(jsonDecode(store.saved!)['syncConnection'], isNull);
    expect(state.accounts, hasLength(2));
  });

  test('Failed imports and stale previews leave all current accounts unchanged',
      () async {
    final store = MemoryStore();
    final kuro = StubCommunity(Community.kuro, Game.wutheringWaves);
    final state = AppState(bridge: store, kuro: kuro);
    addTearDown(state.dispose);
    await state.initialize();
    await state.connect('local', community: Community.kuro);
    final old = state.exportSyncContents().fingerprint;
    await state.setDark(true);
    await expectLater(
        state.importSyncContents(contents(), expectedFingerprint: old),
        throwsA(isA<SyncException>()));
    store.reject = true;
    final remote = contents(accounts: [await kuro.connect('remote')]);
    await expectLater(
        state.importSyncContents(remote,
            expectedFingerprint: state.exportSyncContents().fingerprint,
            preferRemoteSessions: true),
        throwsStateError);
    expect(state.accounts.single.cookie, 'local');
    expect(state.busy, isFalse);
    expect(state.dark, isTrue);
  });

  test('Invalid optional DAV settings never hide saved accounts', () async {
    final store = MemoryStore();
    final kuro = StubCommunity(Community.kuro, Game.wutheringWaves);
    final state = AppState(bridge: store, kuro: kuro);
    addTearDown(state.dispose);
    await state.initialize();
    await state.connect('local', community: Community.kuro);
    final saved = jsonDecode(store.saved!) as Map<String, dynamic>;
    saved['syncConnection'] = {'folder': 'http://bad.test/'};
    store.saved = jsonEncode(saved);
    final restored = AppState(bridge: store, kuro: kuro);
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.accounts, hasLength(1));
    expect(restored.storageReady, isTrue);
    expect(restored.syncConnection, isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'Sync form stays usable on narrow ${dark ? 'dark' : 'light'} screen without network on open',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState(bridge: MemoryStore());
      addTearDown(state.dispose);
      await state.initialize();
      await tester.pumpWidget(MaterialApp(
          theme: appTheme(dark: dark), home: SyncPage(state: state)));
      expect(find.text('账号同步'), findsOneWidget);
      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();
      expect(find.textContaining('请填写 HTTPS'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
