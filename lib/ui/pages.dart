import 'package:flutter/material.dart';
import '../app_state.dart';
import '../domain/models.dart';
import 'design.dart';
import 'dashboard.dart';
import 'sync_page.dart';

class InfoBanner extends StatelessWidget {
  const InfoBanner(this.text, {super.key, this.icon = Icons.shield_outlined});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: context.palette.selected,
          borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 19, color: context.palette.accent),
        SizedBox(width: 12),
        Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12,
                    height: 1.8,
                    color: context.palette.secondary)))
      ]));
}

class RoutinePage extends StatelessWidget {
  const RoutinePage({super.key, required this.state, required this.toast});
  final AppState state;
  final ValueChanged<String> toast;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('清单', subtitle: '手动记录 · 每日按北京时间重置'),
        SizedBox(height: 25),
        GameFilters(state),
        SizedBox(height: 22),
        TaskPanel(state: state),
      ]);
}

class AccountPage extends StatelessWidget {
  const AccountPage(
      {super.key,
      required this.state,
      required this.connect,
      required this.toast,
      required this.goPage});
  final AppState state;
  final VoidCallback connect;
  final ValueChanged<String> toast;
  final ValueChanged<int> goPage;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('账号',
            subtitle: '米游社 · 库街区 · 塔吉多',
            trailing: IconButton(
                tooltip: '连接游戏社区',
                onPressed: state.busy ? null : connect,
                icon: Icon(Icons.person_add_alt_1_outlined,
                    color: context.palette.accent))),
        SizedBox(height: 25),
        if (state.accounts.isEmpty)
          Surface(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Container(
                      width: 55,
                      height: 55,
                      decoration: BoxDecoration(
                          color: context.palette.selected,
                          borderRadius: BorderRadius.circular(17)),
                      child: Icon(Icons.link_rounded,
                          color: context.palette.accent, size: 27)),
                  SizedBox(width: 17),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('连接游戏社区',
                            style: TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w700)),
                        SizedBox(height: 5),
                        Text('支持米游社、库街区和塔吉多国服角色',
                            style: TextStyle(
                                fontSize: 12,
                                color: context.palette.secondary)),
                      ]))
                ]),
                SizedBox(height: 22),
                Text('在官方页面登录后，已绑定的游戏角色会出现在游戏页。',
                    style: TextStyle(
                        fontSize: 13, color: context.palette.secondary)),
                SizedBox(height: 23),
                FilledButton.icon(
                    onPressed: state.busy ? null : connect,
                    icon: Icon(Icons.add_rounded, size: 18),
                    label: Text('连接我的账号')),
              ])),
        for (final account in state.accounts)
          Padding(
              padding: EdgeInsets.only(bottom: 18),
              child: Surface(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      CircleAvatar(
                          backgroundColor: context.palette.selected,
                          child: Icon(Icons.person_outline,
                              color: context.palette.accent)),
                      SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(account.title,
                                style: TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w700)),
                            Text(
                                '${account.community.title} · ${account.roles.length} 个角色',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: context.palette.secondary)),
                          ])),
                      TextButton(
                          onPressed: state.busy
                              ? null
                              : () => _remove(context, account),
                          child: Text('移除',
                              style: TextStyle(
                                  color: context.palette.error, fontSize: 12)))
                    ]),
                    SizedBox(height: 18),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      for (final role in account.roles)
                        Pill('${role.game.shortTitle} · ${role.nickname}',
                            color: context.palette.accent)
                    ]),
                  ]))),
        SizedBox(height: 22),
        InfoBanner(
            '账号凭证在设备本地加密保存。主动开启账号同步后，备份会加密上传到你选择的 WebDAV 服务。游戏请求仍发送到对应官方社区。'),
        SizedBox(height: 22),
        Surface(
            color: context.palette.selected,
            child: Row(children: [
              GameMark(Game.genshin, size: 43),
              SizedBox(width: 15),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(state.demo ? '演示空间' : '体验演示',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text('示例数据，与真实账号互相独立',
                        style: TextStyle(
                            fontSize: 11, color: context.palette.secondary))
                  ])),
              TextButton(
                  onPressed: state.busy
                      ? null
                      : () async {
                          if (state.demo && state.accounts.isNotEmpty) {
                            await state.enterLive();
                          } else {
                            await state.enterDemo();
                          }
                          goPage(0);
                        },
                  child: Text(state.demo && state.accounts.isNotEmpty
                      ? '返回账号'
                      : '进入演示')),
            ])),
      ]);
  Future<void> _remove(BuildContext context, Account account) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('移除此账号？'),
              content: Text('此账号的本机登录凭证和游戏卡片会被移除。之后可以重新连接。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('保留')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text('移除账号'))
              ],
            ));
    if (confirmed == true) {
      try {
        await state.removeAccount(account);
        toast('账号已从本机移除');
      } catch (_) {
        toast('暂时无法移除，请稍后重试');
      }
    }
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('设置'),
        SizedBox(height: 25),
        Surface(
            child: Column(children: [
          SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text('暗色模式', style: TextStyle(fontSize: 14)),
              value: state.dark,
              onChanged: state.setDark),
          Divider(height: 28),
          SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text('隐藏游戏 UID', style: TextStyle(fontSize: 14)),
              subtitle: Text('展示时遮住中间数字，方便分享界面',
                  style: TextStyle(
                      fontSize: 11, color: context.palette.secondary)),
              value: state.hideUid,
              onChanged: state.setHideUid),
          Divider(height: 28),
          _row(
              context,
              Icons.storage_outlined,
              '账号存储',
              state.bridge.supportsAccounts
                  ? state.storageReady
                      ? '本机加密存储'
                      : '安全存储暂不可用'
                  : '浏览器演示不接收登录凭证'),
          Divider(height: 28),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.cloud_sync_outlined,
                  color: context.palette.accent),
              title: Text('账号同步', style: TextStyle(fontSize: 14)),
              subtitle: Text('自选 WebDAV · 端到端加密 · 手动同步',
                  style: TextStyle(
                      fontSize: 11, color: context.palette.secondary)),
              trailing: Icon(Icons.chevron_right_rounded),
              enabled: state.storageReady && !state.busy,
              onTap: state.storageReady && !state.busy
                  ? () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => SyncPage(state: state)))
                  : null),
          Divider(height: 28),
          _row(context, Icons.schedule_rounded, '后台自动签到',
              '首版暂不支持；打开 App 后可一键签到'),
          Divider(height: 28),
          _row(context, Icons.notifications_none_rounded, '体力提醒',
              '首版展示回满倒计时，系统通知尚未接入'),
          Divider(height: 28),
          _row(context, Icons.public_rounded, '支持范围', '米游社、库街区、塔吉多 · 国服'),
          Divider(height: 28),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.text_fields_rounded,
                  color: context.palette.accent),
              title:
                  Text('鸿蒙黑体 HarmonyOS Sans', style: TextStyle(fontSize: 13)),
              subtitle: Text('内置原始字体 · 查看字体和开源许可',
                  style: TextStyle(
                      fontSize: 11, color: context.palette.secondary)),
              onTap: () =>
                  showLicensePage(context: context, applicationName: '栖游')),
        ])),
        SizedBox(height: 22),
        Surface(
            child: Row(children: [
          Brand(compact: true),
          Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('0.1.9',
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    color: context.palette.secondary)),
            SizedBox(height: 5),
            Text('多社区预览版',
                style:
                    TextStyle(fontSize: 11, color: context.palette.secondary)),
          ])
        ])),
      ]);
  Widget _row(
          BuildContext context, IconData icon, String title, String detail) =>
      Row(children: [
        Icon(icon, color: context.palette.accent, size: 21),
        SizedBox(width: 15),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 13)),
          SizedBox(height: 5),
          Text(detail,
              style: TextStyle(fontSize: 11, color: context.palette.secondary))
        ])),
      ]);
}
