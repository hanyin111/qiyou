import 'package:flutter/material.dart';
import '../app_state.dart';
import '../domain/models.dart';
import 'design.dart';

class IosCompanionPage extends StatefulWidget {
  const IosCompanionPage(this.state, {super.key});
  final AppState state;
  @override
  State<IosCompanionPage> createState() => _IosCompanionPageState();
}

class _IosCompanionPageState extends State<IosCompanionPage> {
  bool saving = false;
  String? message;
  @override
  void initState() {
    super.initState();
    widget.state.checkCompanionPermission();
  }

  Future<void> change(Future<void> Function() action) async {
    setState(() {
      saving = true;
      message = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) message = '更改未完成，请检查通知权限和本机存储后重试。';
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final state = widget.state;
        final enabled = !saving && !state.busy && state.storageReady;
        return Scaffold(
            appBar: AppBar(title: const Text('小组件与体力提醒')),
            body: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child:
                        ListView(padding: const EdgeInsets.all(24), children: [
                      const Text('一眼查看游戏状态',
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Text('在主屏幕添加“栖游”小组件。支持小号、中号和大号，显示官方图标、最近同步的体力与当天签到状态。',
                          style: TextStyle(color: context.palette.secondary)),
                      const SizedBox(height: 20),
                      Surface(
                          child: Material(
                              type: MaterialType.transparency,
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('显示的游戏',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 8),
                                    for (final game in Game.values)
                                      CheckboxListTile(
                                          contentPadding: EdgeInsets.zero,
                                          secondary: GameMark(game, size: 28),
                                          title: Text(game.shortTitle,
                                              style: const TextStyle(
                                                  fontSize: 14)),
                                          value:
                                              state.widgetGames.contains(game),
                                          onChanged: enabled
                                              ? (v) => change(() =>
                                                  state.setWidgetGame(
                                                      game, v == true))
                                              : null),
                                    Text(
                                        '只显示已连接且未移除的游戏。同一游戏的多个角色合并体力，签到全部完成才显示对勾。此选择不影响游戏页和体力通知。',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: context.palette.secondary)),
                                  ]))),
                      const SizedBox(height: 20),
                      Surface(
                          child: Material(
                              type: MaterialType.transparency,
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SwitchListTile.adaptive(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text('体力回满提醒'),
                                        subtitle:
                                            const Text('按最近查询的官方回满时间安排本机通知'),
                                        value: state.fullEnergyReminders,
                                        onChanged: enabled
                                            ? (v) => change(() =>
                                                state.setFullEnergyReminders(v))
                                            : null),
                                    if (state.notificationPermission ==
                                        'denied') ...[
                                      const Text('系统通知未允许，请在 iOS 设置中开启。'),
                                      TextButton(
                                          onPressed: () =>
                                              state.companion.openSettings(),
                                          child: const Text('打开系统设置')),
                                    ],
                                    Text(
                                        '游戏中消耗体力后，请回到栖游刷新，更新通知时间。没有回满时间、查询失败或数据过旧时不安排提醒；已回满不会重复通知。关闭开关或移除游戏会撤销未发出的提醒。',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: context.palette.secondary)),
                                  ]))),
                      const SizedBox(height: 18),
                      Text(
                          'iOS 决定小组件刷新时机。小组件展示同步值，不会在后台自动签到；超过 6 小时的数据标为待刷新。通知可能受系统专注模式与通知设置影响。',
                          style: TextStyle(
                              fontSize: 12, color: context.palette.secondary)),
                      if (message ?? state.companionError
                          case final String error) ...[
                        const SizedBox(height: 14),
                        Text(error,
                            style: TextStyle(color: context.palette.error)),
                      ],
                    ]))));
      });
}
