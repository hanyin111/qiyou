import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qiyou/app_state.dart';
import 'package:qiyou/domain/models.dart';
import 'package:qiyou/ui/community_sms_login.dart';
import 'package:qiyou/ui/taygedo_login.dart';

void main() {
  for (final dark in [false, true]) {
    for (final community in [Community.miyoushe, Community.kuro]) {
      testWidgets(
          '${community.name} native SMS buttons remain reachable with a phone keyboard: $dark',
          (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final state = AppState();
        addTearDown(state.dispose);
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            home: CommunitySmsLoginPage(state, community: community)));
        await tester.tap(find.text('获取验证码'));
        await tester.pump();
        expect(find.text('请输入正确的中国大陆手机号。'), findsOneWidget);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pump();
        final button = find.text('登录并连接');
        await tester.ensureVisible(button);
        expect(tester.getRect(button).bottom, lessThan(512));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
    testWidgets(
        'Taygedo defaults to SMS and explains automatic refreshToken capture: $dark',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState();
      addTearDown(state.dispose);
      await tester.pumpWidget(MaterialApp(
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: TaygedoLoginPage(state)));
      expect(find.textContaining('refreshToken 会自动获取'), findsOneWidget);
      expect(find.text('原登录设备 ID（deviceId）'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
