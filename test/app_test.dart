import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qiyou/app_state.dart';
import 'package:qiyou/data/device_bridge.dart';
import 'package:qiyou/data/miyoushe_client.dart';
import 'package:qiyou/domain/models.dart';
import 'package:qiyou/main.dart';

class DemoBridge extends DeviceBridge {
  @override
  bool get supportsAccounts => false;
}

class NoNetworkClient extends MiyousheClient {
  @override
  Future<SignStatus> sign(Account account, Role role) =>
      throw StateError('Demo must never use the network');
}

class SuccessfulSignClient extends MiyousheClient {
  @override
  Future<SignStatus> sign(Account account, Role role) async =>
      SignStatus.signed;
}

void main() {
  test('Signing preserves an unrelated daily-note verification error',
      () async {
    final state =
        AppState(client: SuccessfulSignClient(), bridge: DemoBridge());
    addTearDown(state.dispose);
    final entry = state.entries.first;
    state.demo = false;
    state.accounts.add(Account(
        id: entry.accountId,
        cookie: 'test',
        deviceId: 'test',
        roles: [entry.role]));
    entry.noteError = 'Daily note needs verification';
    entry.noteNeedsVerification = true;
    await state.signAll(only: entry);
    expect(entry.signStatus, SignStatus.signed);
    expect(entry.error, 'Daily note needs verification');
    expect(entry.noteNeedsVerification, isTrue);
  });
  test('Demo sign never touches real client and does not sign twice', () async {
    final state = AppState(client: NoNetworkClient(), bridge: DemoBridge());
    addTearDown(state.dispose);
    expect(await state.signAll(), contains('未发送真实请求'));
    expect(state.signedCount, 3);
    expect(await state.signAll(), contains('已经签过'));
    expect(state.activities, hasLength(3));
  });
  for (final width in [360.0, 390.0, 768.0, 1440.0]) {
    testWidgets('Dashboard fits width $width and game filters work',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState(bridge: DemoBridge());
      addTearDown(state.dispose);
      await tester.pumpWidget(QiyouApp(state: state));
      await tester.pumpAndSettle();
      expect(find.text('168'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('清单').last);
      await tester.pumpAndSettle();
      final chip = find.widgetWithText(ChoiceChip, '原神');
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(state.visibleEntries, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
      'Preview connection explains limits and never requests credentials',
      (tester) async {
    final state = AppState(bridge: DemoBridge());
    addTearDown(state.dispose);
    await tester.pumpWidget(QiyouApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('账号管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接我的账号'));
    await tester.pumpAndSettle();
    expect(find.text('先在演示空间逛逛'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('继续体验'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Light and dark themes switch without losing dashboard state',
      (tester) async {
    final state = AppState(bridge: DemoBridge());
    addTearDown(state.dispose);
    await tester.pumpWidget(QiyouApp(state: state));
    await tester.pumpAndSettle();
    final roleKeys = state.entries.map((entry) => entry.key).toList();
    await state.setDark(true);
    await tester.pumpAndSettle();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark);
    expect(
        Theme.of(tester.element(find.text('168'))).brightness, Brightness.dark);
    expect(state.entries.map((entry) => entry.key).toList(), roleKeys);
    await state.setDark(false);
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('168'))).brightness,
        Brightness.light);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
