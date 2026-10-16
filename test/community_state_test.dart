import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:qiyou/app_state.dart';
import 'package:qiyou/data/community_client.dart';
import 'package:qiyou/data/device_bridge.dart';
import 'package:qiyou/data/miyoushe_client.dart';
import 'package:qiyou/domain/models.dart';

class MemoryStore extends DeviceBridge {
  String? saved;
  bool reject = false;
  @override
  bool get supportsAccounts => true;
  @override
  Future<String?> read() async => saved;
  @override
  Future<void> write(String value) async {
    if (reject) throw StateError('Synthetic storage failure');
    saved = value;
  }
}

class StubCommunity implements CommunityClient {
  StubCommunity(this.community, this.game);
  final Community community;
  final Game game;
  bool failNote = false;
  String? browserDevice;
  int reads = 0, signs = 0;
  @override
  Future<Account> connect(String input, {String? existingDeviceId}) async =>
      Account(
          id: '${community.name}:7',
          cookie: input,
          deviceId: browserDevice ?? existingDeviceId ?? 'new-device',
          recordHeaders: {if (browserDevice != null) 'devcode': browserDevice!},
          community: community,
          roles: [
            Role(
                game: game,
                uid: '7',
                region: 'server',
                nickname: 'Synthetic',
                serverName: 'Server')
          ]);
  @override
  Future<DailyNote> daily(Account account, Role role) async {
    expect(account.community, community);
    reads++;
    if (failNote) {
      throw const MiyousheException(
          ApiFailure.protocol, 'Synthetic daily failure');
    }
    return DailyNote(syncedAt: DateTime.now(), energy: 40, capacity: 200);
  }

  @override
  Future<SignStatus> signInfo(Account account, Role role) async =>
      SignStatus.pending;
  @override
  Future<SignStatus> sign(Account account, Role role) async {
    expect(account.community, community);
    signs++;
    return SignStatus.signed;
  }

  @override
  void close() {}
}

void main() {
  test(
      'Reconnecting Kuro installs the real login device and preserves other accounts',
      () async {
    final store = MemoryStore();
    final kuro = StubCommunity(Community.kuro, Game.wutheringWaves);
    final state = AppState(bridge: store, kuro: kuro);
    addTearDown(state.dispose);
    await state.initialize();
    await state.connect('synthetic-old', community: Community.kuro);
    expect(state.accounts.single.deviceId, 'new-device');
    kuro.browserDevice = 'real-browser-device';
    await state.connect('synthetic-new', community: Community.kuro);
    expect(state.accounts.single.deviceId, 'real-browser-device');
    expect(
        state.accounts.single.recordHeaders['devcode'], 'real-browser-device');
    expect(state.accounts, hasLength(1));
  });
  test(
      'Same numeric IDs coexist across communities, reload and route independently',
      () async {
    final store = MemoryStore();
    final kuro = StubCommunity(Community.kuro, Game.wutheringWaves);
    final tjd = StubCommunity(Community.taygedo, Game.nevernessToEverness);
    final state = AppState(bridge: store, kuro: kuro, taygedo: tjd);
    addTearDown(state.dispose);
    await state.initialize();
    await state.connect('synthetic-kuro', community: Community.kuro);
    await state.connect('synthetic-tjd', community: Community.taygedo);
    expect(state.accounts, hasLength(2));
    expect(state.entries, hasLength(2));
    expect(kuro.reads, 2);
    expect(tjd.reads, 1);
    await state.signAll();
    expect(kuro.signs, 1);
    expect(tjd.signs, 1);
    final reloaded = AppState(bridge: store, kuro: kuro, taygedo: tjd);
    addTearDown(reloaded.dispose);
    await reloaded.initialize();
    expect(reloaded.accounts.map((a) => a.community),
        [Community.kuro, Community.taygedo]);
    expect(reloaded.entries.every((e) => e.note?.energy == 40), isTrue);
    expect(object(jsonDecode(store.saved!))['accounts'], hasLength(2));
  });
  test('Failed secure save leaves previous accounts untouched', () async {
    final store = MemoryStore();
    final state = AppState(
        bridge: store,
        kuro: StubCommunity(Community.kuro, Game.wutheringWaves));
    addTearDown(state.dispose);
    await state.initialize();
    store.reject = true;
    await expectLater(state.connect('synthetic', community: Community.kuro),
        throwsStateError);
    expect(state.accounts, isEmpty);
    expect(state.demo, isTrue);
    expect(state.busy, isFalse);
  });
  test(
      'Daily failure does not block signing, reconnect keeps device and removal is scoped',
      () async {
    final store = MemoryStore();
    final kuro = StubCommunity(Community.kuro, Game.wutheringWaves)
      ..failNote = true;
    final tjd = StubCommunity(Community.taygedo, Game.nevernessToEverness);
    final state = AppState(bridge: store, kuro: kuro, taygedo: tjd);
    addTearDown(state.dispose);
    await state.initialize();
    await state.connect('synthetic', community: Community.kuro);
    final initialDevice = state.accounts.single.deviceId;
    await state.connect('synthetic-new', community: Community.kuro);
    expect(state.accounts.single.deviceId, initialDevice);
    expect(state.accounts, hasLength(1));
    await state.connect('synthetic', community: Community.taygedo);
    await state.signAll();
    expect(state.entries.first.noteError, isNotNull);
    expect(state.entries.first.signStatus, SignStatus.signed);
    await state.removeAccount(state.accounts.first);
    expect(state.accounts.single.community, Community.taygedo);
    expect(state.entries.single.role.game, Game.nevernessToEverness);
  });
}
