import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qiyou/app_state.dart';
import 'package:qiyou/data/ios_companion.dart';
import 'package:qiyou/domain/models.dart';
import 'package:qiyou/ui/design.dart';
import 'package:qiyou/ui/ios_companion_page.dart';
import 'community_state_test.dart' show MemoryStore, StubCommunity;

class FakeCompanion extends IosCompanionBridge {
  final payloads = <Map<String, dynamic>>[];
  String authorization = 'authorized';
  bool shared = true, reject = false;
  int prompts = 0;
  @override
  bool get supported => true;
  @override
  Future<String> permission({bool request = false}) async {
    if (request) prompts++;
    return authorization;
  }

  @override
  Future<bool> publish(Map<String, dynamic> payload) async {
    if (reject) throw StateError('synthetic bridge failure');
    payloads.add(jsonDecode(jsonEncode(payload)) as Map<String, dynamic>);
    return shared;
  }
}

final now = DateTime.utc(2026, 10, 18);
GameEntry entry(Game game,
        {String uid = 'private-role-uid',
        DailyNote? note,
        SignStatus sign = SignStatus.pending}) =>
    GameEntry(
        accountId: 'private-account-id',
        role: Role(
            game: game,
            uid: uid,
            region: 'private-region',
            nickname: 'private-nickname',
            serverName: 'private-server'),
        note: note ??
            DailyNote(
                syncedAt: now,
                energy: 80,
                capacity: 240,
                recoverySeconds: 3600),
        signStatus: sign);
Map<String, dynamic> payload(List<GameEntry> entries,
        {Set<Game>? selected,
        bool connected = true,
        bool enabled = true,
        String? day}) =>
    companionPayload(
        entries: entries,
        selected: selected ?? Game.values.toSet(),
        signDay: day ?? chinaDay(now),
        connected: connected,
        remindersEnabled: enabled,
        now: now);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'All seven games fit one snapshot; no account identity or secrets are exported',
      () {
    final rows = Game.values.map((g) => entry(g)).toList();
    final value = payload(rows);
    expect((value['snapshot'] as Map)['games'], hasLength(7));
    expect(value['reminders'], hasLength(7));
    final encoded = jsonEncode(value);
    for (final private in [
      'private-account-id',
      'private-role-uid',
      'private-nickname',
      'private-region',
      'private-server',
      'cookie',
      'token',
      'deviceId',
      'password'
    ]) {
      expect(encoded, isNot(contains(private)));
    }
    final id = (value['reminders'] as List).first['id'];
    expect(id, matches(r'^qiyou\.energy\.[a-f0-9]{24}$'));
    expect(id, (payload(rows)['reminders'] as List).first['id']);
  });
  test(
      'Game selection affects only widget; notifications still cover active games',
      () {
    final value = payload(Game.values.map((g) => entry(g)).toList(),
        selected: {Game.genshin});
    expect((value['snapshot'] as Map)['games'], hasLength(1));
    expect(value['reminders'], hasLength(7));
    expect(
        (payload([entry(Game.genshin)], selected: {})['snapshot']
            as Map)['games'],
        isEmpty);
  });
  test('Multiple roles aggregate stamina and cannot claim a complete sign', () {
    final rows = [
      entry(Game.genshin, sign: SignStatus.signed),
      entry(Game.genshin, uid: 'second')
    ];
    final game = ((payload(rows)['snapshot'] as Map)['games'] as List).single;
    expect(game['energy'], 160);
    expect(game['capacity'], 480);
    expect(game['sign'], 'partial');
    expect(game['signedRoles'], 1);
    rows.last.noteError = 'synthetic query failure';
    final failed = payload(rows);
    expect(
        (((failed['snapshot'] as Map)['games'] as List).single
            as Map)['energy'],
        isNull);
    expect(failed['reminders'], hasLength(1));
    final yesterday =
        ((payload(rows, day: '2026-10-17')['snapshot'] as Map)['games'] as List)
            .single;
    expect(yesterday['signedRoles'], 0);
    expect(yesterday['sign'], 'unknown');
  });
  test('Only known fresh future recovery deadlines produce notifications', () {
    final rows = [
      entry(Game.genshin,
          uid: 'unknown',
          note: DailyNote(syncedAt: now, energy: 10, capacity: 200)),
      entry(Game.genshin,
          uid: 'full',
          note: DailyNote(
              syncedAt: now, energy: 200, capacity: 200, recoverySeconds: 0)),
      entry(Game.genshin,
          uid: 'past',
          note: DailyNote(
              syncedAt: now.subtract(const Duration(hours: 1)),
              energy: 10,
              capacity: 200,
              recoverySeconds: 1)),
      entry(Game.genshin,
          uid: 'stale',
          note: DailyNote(
              syncedAt: now.subtract(const Duration(hours: 7)),
              energy: 10,
              capacity: 200,
              recoverySeconds: 86400)),
      entry(Game.genshin,
          uid: 'invalid',
          note: DailyNote(
              syncedAt: now, energy: -1, capacity: 200, recoverySeconds: 3600)),
    ];
    expect(payload(rows)['reminders'], isEmpty);
    final good = payload([entry(Game.genshin)]);
    expect((good['reminders'] as List).single['fullAt'],
        now.add(const Duration(hours: 1)).millisecondsSinceEpoch);
    expect(
        payload([entry(Game.genshin)], enabled: false)['reminders'], isEmpty);
    final demo = payload([entry(Game.genshin)], connected: false);
    expect((demo['snapshot'] as Map)['games'], isEmpty);
    expect(demo['reminders'], isEmpty);
  });
  test('Notification budget keeps earliest sixty unique roles', () {
    final rows = List.generate(
        80,
        (i) => entry(Game.genshin,
            uid: '$i',
            note: DailyNote(
                syncedAt: now,
                energy: 1,
                capacity: 200,
                recoverySeconds: 80 - i)));
    final reminders = payload(rows)['reminders'] as List;
    expect(reminders, hasLength(60));
    expect(reminders.first['fullAt'],
        now.add(const Duration(seconds: 1)).millisecondsSinceEpoch);
    expect(reminders.last['fullAt'],
        now.add(const Duration(seconds: 60)).millisecondsSinceEpoch);
  });
  test('Permission is requested only on enable; preferences survive restart',
      () async {
    final store = MemoryStore(), companion = FakeCompanion();
    final state = AppState(
        bridge: store,
        companion: companion,
        kuro: StubCommunity(Community.kuro, Game.wutheringWaves));
    addTearDown(state.dispose);
    await state.initialize();
    expect(companion.prompts, 0);
    await state.setWidgetGame(Game.genshin, false);
    await state.setFullEnergyReminders(true);
    expect(companion.prompts, 1);
    expect(state.fullEnergyReminders, isTrue);
    await state.setFullEnergyReminders(false);
    expect(companion.prompts, 1);
    expect(companion.payloads.last['remindersEnabled'], isFalse);
    final again = AppState(bridge: store, companion: companion);
    addTearDown(again.dispose);
    await again.initialize();
    expect(again.widgetGames.contains(Game.genshin), isFalse);
    expect(again.fullEnergyReminders, isFalse);
  });
  test('Denied permission and failed save leave reminder settings unchanged',
      () async {
    final store = MemoryStore(),
        companion = FakeCompanion()..authorization = 'denied';
    final state = AppState(bridge: store, companion: companion);
    addTearDown(state.dispose);
    await state.initialize();
    await expectLater(state.setFullEnergyReminders(true), throwsStateError);
    expect(state.fullEnergyReminders, isFalse);
    companion.authorization = 'authorized';
    store.reject = true;
    await expectLater(state.setFullEnergyReminders(true), throwsStateError);
    expect(state.fullEnergyReminders, isFalse);
    await expectLater(
        state.setWidgetGame(Game.genshin, false), throwsStateError);
    expect(state.widgetGames.contains(Game.genshin), isTrue);
  });
  test(
      'Refresh, sign and game removal publish all active games regardless of filters',
      () async {
    final companion = FakeCompanion();
    final state = AppState(
        bridge: MemoryStore(),
        companion: companion,
        kuro: StubCommunity(Community.kuro, Game.wutheringWaves),
        taygedo: StubCommunity(Community.taygedo, Game.nevernessToEverness));
    addTearDown(state.dispose);
    await state.initialize();
    await state.connect('synthetic-token', community: Community.kuro);
    await state.connect('synthetic-token', community: Community.taygedo);
    state.setFilter(Game.wutheringWaves);
    await state.refresh();
    expect((companion.payloads.last['snapshot'] as Map)['games'], hasLength(2));
    await state.signAll();
    final games = (companion.payloads.last['snapshot'] as Map)['games'] as List;
    expect(games.firstWhere((g) => g['game'] == 'wutheringWaves')['sign'],
        'signed');
    await state.setGameHidden(state.accounts.first, Game.wutheringWaves, true);
    expect(
        ((companion.payloads.last['snapshot'] as Map)['games'] as List)
            .single['game'],
        'nevernessToEverness');
    await state.removeAccount(state.accounts.last);
    expect((companion.payloads.last['snapshot'] as Map)['games'], isEmpty);
    companion.reject = true;
    await state.updateCompanion();
    expect(state.companionError, isNotNull);
    companion.reject = false;
    await state.updateCompanion();
    expect(state.companionError, isNull);
  });
  for (final dark in [false, true]) {
    testWidgets(
        'iOS settings fit a narrow screen and do not request permission on open: dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final companion = FakeCompanion();
      final state = AppState(bridge: MemoryStore(), companion: companion);
      addTearDown(state.dispose);
      await state.initialize();
      await tester.pumpWidget(MaterialApp(
          theme: appTheme(dark: dark), home: IosCompanionPage(state)));
      await tester.pumpAndSettle();
      expect(companion.prompts, 0);
      expect(find.byType(CheckboxListTile), findsNWidgets(7));
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(state.widgetGames.contains(Game.genshin), isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
