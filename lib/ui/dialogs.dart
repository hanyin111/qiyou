import 'package:flutter/material.dart';
import '../app_state.dart';
import '../domain/models.dart';
import '../data/miyoushe_client.dart';
import 'design.dart';
import 'official_login.dart';

Future<void> showGameDetails(BuildContext context, AppState state,
    GameEntry entry, ValueChanged<String> toast) async {
  await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
            title: Row(children: [
              GameMark(entry.role.game),
              SizedBox(width: 14),
              Expanded(child: Text(entry.role.game.shortTitle))
            ]),
            content: SizedBox(
                width: 380,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${entry.role.nickname} · ${entry.role.serverName}'),
                      SizedBox(height: 10),
                      SelectableText(
                          'UID ${maskedUid(entry.role.uid, state.hideUid)}',
                          style: TextStyle(
                              fontSize: 12, color: context.palette.secondary)),
                      SizedBox(height: 18),
                      Text('签到状态：${entry.signStatus.label}'),
                      SizedBox(height: 10),
                      Text(remainingText(
                          entry.note?.remainingAt(DateTime.now()))),
                      SizedBox(height: 12),
                      Text('体力显示最近同步值，倒计时按该次同步估算。',
                          style: TextStyle(
                              fontSize: 11, color: context.palette.secondary)),
                      if (entry.error != null) ...[
                        SizedBox(height: 15),
                        Text(entry.error!,
                            style: TextStyle(
                                fontSize: 12, color: context.palette.error))
                      ],
                      if (state.demo) ...[
                        SizedBox(height: 15),
                        Text('演示数据，不会发送真实签到请求',
                            style: TextStyle(
                                fontSize: 11, color: context.palette.accent))
                      ],
                    ])),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context), child: Text('关闭')),
              FilledButton(
                  onPressed: state.busy
                      ? null
                      : () async {
                          Navigator.pop(context);
                          toast(await state.signAll(only: entry));
                        },
                  child: Text(entry.signStatus.isDone ? '今日已签' : '签到'))
            ],
          ));
}

Future<void> showAddTask(BuildContext context, AppState state) async {
  final controller = TextEditingController();
  Game selected = state.filter ?? Game.genshin;
  await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
                title: Text('记下一件小事'),
                content: SizedBox(
                    width: 360,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: controller,
                          autofocus: true,
                          maxLength: 60,
                          decoration: InputDecoration(hintText: '例如：领取本周奖励')),
                      SizedBox(height: 12),
                      DropdownButtonFormField<Game>(
                          initialValue: selected,
                          decoration: InputDecoration(labelText: '所属游戏'),
                          items: Game.values
                              .map((game) => DropdownMenuItem(
                                  value: game, child: Text(game.shortTitle)))
                              .toList(),
                          onChanged: (value) =>
                              update(() => selected = value!)),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('取消')),
                  FilledButton(
                      onPressed: () async {
                        if (controller.text.trim().isEmpty) return;
                        await state.addTask(controller.text, selected);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Text('添加到清单'))
                ],
              )));
  // Wait until the closing route has detached its text field.
  await Future<void>.delayed(Duration(milliseconds: 250));
  controller.dispose();
}

class ConnectDialog extends StatefulWidget {
  const ConnectDialog(this.state, {super.key});
  final AppState state;
  @override
  State<ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<ConnectDialog> {
  final input = TextEditingController();
  String? error;
  bool saving = false;
  bool consent = false;
  @override
  void dispose() {
    input.clear();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canConnect =
        widget.state.bridge.supportsAccounts && widget.state.storageReady;
    return PopScope(
        canPop: !saving,
        child: AlertDialog(
          title: Text('连接米游社',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          content: SizedBox(
              width: 430,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('登录后读取已绑定角色和游戏状态。',
                        style: TextStyle(
                            fontSize: 13, color: context.palette.secondary)),
                    SizedBox(height: 23),
                    if (canConnect) ...[
                      if (supportsOfficialLogin) ...[
                        SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                                onPressed: saving || !consent
                                    ? null
                                    : () async {
                                        final connected =
                                            await Navigator.of(context)
                                                .push<bool>(MaterialPageRoute(
                                                    builder: (_) =>
                                                        OfficialLoginPage(
                                                            widget.state)));
                                        if (connected == true &&
                                            context.mounted) {
                                          Navigator.pop(context, true);
                                        }
                                      },
                                icon: Icon(Icons.login, size: 18),
                                label: Text('打开官方页面登录'))),
                        SizedBox(height: 20),
                      ],
                      Text('或导入已有凭证（Cookie）',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      SizedBox(height: 9),
                      TextField(
                          controller: input,
                          obscureText: true,
                          maxLines: 1,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: [],
                          enabled: !saving,
                          decoration: InputDecoration(
                              hintText: '在本机粘贴完整的米游社 Cookie',
                              prefixIcon: Icon(Icons.key_outlined, size: 18))),
                      SizedBox(height: 15),
                      Text('校验成功后自动读取已绑定的国服角色。当前支持原神、星穹铁道、绝区零。',
                          style: TextStyle(
                              fontSize: 12,
                              color: context.palette.secondary,
                              height: 1.8)),
                      SizedBox(height: 14),
                      Text('不要在聊天、截图或公开日志中分享登录凭证。凭证只在本机加密保存。',
                          style: TextStyle(
                              fontSize: 11,
                              color: context.palette.secondary,
                              height: 1.8)),
                      SizedBox(height: 12),
                      Text('连接会读取账号、角色及游戏状态；点击签到时向米游社提交请求。可在账号页移除凭证和角色数据。',
                          style: TextStyle(
                              fontSize: 11, color: context.palette.secondary)),
                      CheckboxListTile(
                          value: consent,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text('我同意为上述目的处理并在本机保存登录凭证',
                              style: TextStyle(fontSize: 11)),
                          onChanged: saving
                              ? null
                              : (value) =>
                                  setState(() => consent = value ?? false)),
                    ] else
                      Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(20),
                          decoration: BoxDecoration(
                              color: context.palette.background,
                              borderRadius: BorderRadius.circular(16)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.devices_rounded,
                                    color: context.palette.accent, size: 28),
                                SizedBox(height: 15),
                                Text(
                                    widget.state.bridge.supportsAccounts
                                        ? '本机安全存储尚未就绪'
                                        : '先在演示空间逛逛',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700)),
                                SizedBox(height: 9),
                                Text(
                                    widget.state.bridge.supportsAccounts
                                        ? '当前设备的安全存储不可用，暂时不能接收登录凭证。你可以继续体验演示数据。'
                                        : '浏览器预览可体验总览、清单和签到流程。真实账号需要在手机端连接，预览不会接收你的登录凭证。',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: context.palette.secondary,
                                        height: 1.9)),
                              ])),
                    if (error != null) ...[
                      SizedBox(height: 17),
                      Text(error!,
                          style: TextStyle(
                              fontSize: 12, color: context.palette.error))
                    ],
                  ]))),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: Text('稍后再说')),
            FilledButton(
                onPressed: saving || (canConnect && !consent)
                    ? null
                    : canConnect
                        ? () async {
                            setState(() {
                              saving = true;
                              error = null;
                            });
                            try {
                              await widget.state.connect(input.text);
                              input.clear();
                              if (context.mounted) Navigator.pop(context, true);
                            } catch (failure) {
                              if (mounted) {
                                setState(() {
                                  error = failure is MiyousheException
                                      ? failure.message
                                      : '连接未完成，请检查本机存储和网络后重试。';
                                  saving = false;
                                });
                              }
                            }
                          }
                        : () => Navigator.pop(context),
                child: Text(saving
                    ? '正在连接…'
                    : canConnect
                        ? '验证并连接'
                        : '继续体验'))
          ],
        ));
  }
}
