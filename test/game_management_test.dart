import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qiyou/app_state.dart';
import 'package:qiyou/data/miyoushe_client.dart';
import 'package:qiyou/domain/models.dart';
import 'package:qiyou/ui/design.dart';
import 'package:qiyou/ui/pages.dart';
import 'package:qiyou/ui/dialogs.dart';
import 'community_state_test.dart' show MemoryStore, StubCommunity;
import 'community_clients_test.dart' show ww, pgr;

const genshin = Role(
    game: Game.genshin,
    uid: '100',
    region: 'cn_gf01',
    nickname: 'Synthetic',
    serverName: 'Server');
const rail = Role(
    game: Game.starRail,
    uid: '101',
    region: 'prod_gf_cn',
    nickname: 'Synthetic',
    serverName: 'Server');
const mys = Account(
    id: '7',
    cookie: 'ltuid=7; ltoken=synthetic',
    deviceId: 'synthetic-device',
    roles: [genshin, rail]);
const kuro = Account(
    id: 'kuro:7',
    cookie: 'synthetic-kuro',
    deviceId: 'synthetic-device',
    community: Community.kuro,
    roles: [ww, pgr]);

class GameMys extends MiyousheClient {
  final reads = <Game>[], signs = <Game>[];
  @override
  Future<DailyNote> daily(Account a, Role r) async {
    reads.add(r.game);
    return DailyNote(syncedAt: DateTime.now(), energy: 1, capacity: 240);
  }

  @override
  Future<SignStatus> signInfo(Account a, Role r) async => SignStatus.pending;
  @override
  Future<SignStatus> sign(Account a, Role r) async {
    signs.add(r.game);
    return SignStatus.signed;
  }
}

MemoryStore seeded(List<Account> accounts) => MemoryStore()
  ..saved = jsonEncode({
    'version': 1,
    'accounts': accounts.map((a) => a.toJson()).toList(),
    'tasks': [],
  });

void main() {
  testWidgets(
      'Game detail removal uses the parent route and keeps the other game',
      (tester) async {
    final state = AppState(bridge: seeded([mys]), client: GameMys());
    addTearDown(state.dispose);
    await state.initialize();
    await tester.pumpWidget(MaterialApp(
        theme: appTheme(),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showGameDetails(
                        context, state, state.entries.first, (_) {}),
                    child: const Text('Open details'))))));
    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除游戏'));
    await tester.pumpAndSettle();
    expect(find.text('移除原神？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '移除游戏'));
    await tester.pumpAndSettle();
    expect(state.entries.single.role.game, Game.starRail);
    expect(find.text('Open details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
      'Removing one game preserves other games, credentials and current cards; refresh/sign skip it',
      () async {
    final store = seeded([mys, kuro]);
    final client = GameMys();
    final kc = StubCommunity(Community.kuro, Game.wutheringWaves);
    final state = AppState(bridge: store, client: client, kuro: kc);
    addTearDown(state.dispose);
    await state.initialize();
    final railEntry =
        state.entries.firstWhere((e) => e.role.game == Game.starRail);
    await state.setGameHidden(state.accounts.first, Game.genshin, true);
    expect(state.accounts.first.cookie, mys.cookie);
    expect(state.accounts.first.roles, hasLength(2));
    expect(state.entries.first, same(railEntry));
    await state.setGameHidden(state.accounts.last, Game.wutheringWaves, true);
    expect(state.entries.map((e) => e.role.game),
        [Game.starRail, Game.punishingGrayRaven]);
    client.reads.clear();
    final before = kc.reads;
    await state.refresh();
    expect(client.reads, [Game.starRail]);
    expect(kc.reads - before, 1);
    await state.signAll();
    expect(client.signs, [Game.starRail]);
    expect(kc.signs, 1);
    final restored = AppState(bridge: store, client: client, kuro: kc);
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.entries.map((e) => e.role.game),
        [Game.starRail, Game.punishingGrayRaven]);
    expect(restored.accounts.first.hiddenGames, {Game.genshin});
  });

  test(
      'All games can be removed without deleting the community account, then restored without login',
      () async {
    final client = GameMys();
    final state = AppState(bridge: seeded([mys]), client: client);
    addTearDown(state.dispose);
    await state.initialize();
    final oldEntry = state.entries.first;
    await state.setGameHidden(state.accounts.single, Game.genshin, true);
    await state.setGameHidden(state.accounts.single, Game.starRail, true);
    expect(state.demo, isFalse);
    expect(state.entries, isEmpty);
    expect(state.accounts.single.cookie, mys.cookie);
    await state.signAll(only: oldEntry);
    expect(client.signs, isEmpty);
    await state.setGameHidden(state.accounts.single, Game.genshin, false);
    expect(state.entries.single.role.game, Game.genshin);
    expect(state.entries.single.note, isNull);
    await state.refresh();
    expect(state.entries.single.note?.energy, 1);
  });

  test(
      'Reconnect preserves game removal and failed writes leave visible games intact',
      () async {
    final store = MemoryStore();
    final state = AppState(
        bridge: store,
        kuro: StubCommunity(Community.kuro, Game.wutheringWaves));
    addTearDown(state.dispose);
    await state.initialize();
    await state.connect('synthetic-old', community: Community.kuro);
    await state.setGameHidden(state.accounts.single, Game.wutheringWaves, true);
    await state.connect('synthetic-new', community: Community.kuro);
    expect(state.entries, isEmpty);
    expect(state.accounts.single.cookie, 'synthetic-new');
    store.reject = true;
    await expectLater(
        state.setGameHidden(state.accounts.single, Game.wutheringWaves, false),
        throwsStateError);
    expect(state.entries, isEmpty);
    expect(state.accounts.single.hiddenGames, {Game.wutheringWaves});
    expect(state.busy, isFalse);
  });

  test('Cloud game visibility is applied while preserving local login session',
      () async {
    final client = GameMys();
    final state = AppState(bridge: seeded([mys]), client: client);
    addTearDown(state.dispose);
    await state.initialize();
    final remote = AppState(
        bridge: seeded([mys.copyWith(cookie: 'cloud-old')]), client: GameMys());
    addTearDown(remote.dispose);
    await remote.initialize();
    await remote.setGameHidden(remote.accounts.single, Game.genshin, true);
    await state.importSyncContents(remote.exportSyncContents(),
        expectedFingerprint: state.exportSyncContents().fingerprint);
    expect(state.accounts.single.cookie, mys.cookie);
    expect(state.entries.single.role.game, Game.starRail);
  });

  testWidgets('Account page removes and restores an individual game',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState(bridge: seeded([mys]), client: GameMys());
    addTearDown(state.dispose);
    await state.initialize();
    await tester.pumpWidget(AnimatedBuilder(
        animation: state,
        builder: (context, _) => MaterialApp(
            theme: appTheme(),
            home: Scaffold(
                body: SingleChildScrollView(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: AccountPage(
                            state: state,
                            connect: () {},
                            toast: (_) {},
                            goPage: (_) {})))))));
    await tester.tap(find.widgetWithText(TextButton, '移除').at(1));
    await tester.pumpAndSettle();
    expect(find.text('移除原神？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '移除游戏'));
    await tester.pumpAndSettle();
    expect(state.entries.single.role.game, Game.starRail);
    expect(find.text('已移除'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '恢复'));
    await tester.pumpAndSettle();
    expect(state.entries, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
