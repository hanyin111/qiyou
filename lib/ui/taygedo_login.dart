import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../data/taygedo_login_client.dart';
import '../data/taygedo_client.dart';
import '../data/miyoushe_client.dart';
import '../domain/models.dart';
import 'design.dart';

class TaygedoLoginPage extends StatefulWidget {
  const TaygedoLoginPage(this.state, {super.key});
  final AppState state;
  @override
  State<TaygedoLoginPage> createState() => _TaygedoLoginPageState();
}

class _TaygedoLoginPageState extends State<TaygedoLoginPage> {
  final phone = TextEditingController(), code = TextEditingController();
  final refreshToken = TextEditingController(),
      uid = TextEditingController(),
      device = TextEditingController();
  late final login = TaygedoLoginClient(platform: defaultTargetPlatform.name);
  Timer? timer;
  bool busy = false;
  bool importSession = false, acceptSms = false;
  int remaining = 0;
  String? sentPhone, error;
  @override
  void dispose() {
    timer?.cancel();
    login.close();
    phone.clear();
    code.clear();
    phone.dispose();
    code.dispose();
    for (final field in [refreshToken, uid, device]) {
      field.clear();
      field.dispose();
    }
    super.dispose();
  }

  Future<void> send() async {
    if (busy || remaining > 0 || importSession || !acceptSms) return;
    setState(() {
      busy = true;
      error = null;
    });
    final number = phone.text.trim();
    try {
      await login.sendCode(number);
      if (!mounted) return;
      setState(() {
        sentPhone = number;
        remaining = 60;
      });
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => remaining--);
        if (remaining <= 0) t.cancel();
      });
    } catch (failure) {
      if (mounted) {
        setState(() => error =
            failure is MiyousheException ? failure.message : '短信发送未完成，请稍后重试。');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> connect() async {
    if (busy) return;
    if (!importSession && !acceptSms) return;
    setState(() {
      busy = true;
      error = null;
    });
    var smsSessionIssued = false;
    try {
      final credential = importSession
          ? jsonEncode({
              'refreshToken': refreshToken.text.trim(),
              'uid': uid.text.trim(),
              'did': device.text.trim()
            })
          : await login.login(phone.text.trim(), code.text.trim());
      if (!importSession) {
        final values = object(jsonDecode(credential));
        refreshToken.text = values['refreshToken'] as String;
        uid.text = values['uid'] as String;
        device.text = values['did'] as String;
        smsSessionIssued = true;
      }
      code.clear();
      await widget.state.connect(credential, community: Community.taygedo);
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) {
        if (failure is TaygedoConnectFailure) {
          refreshToken.text = failure.session.refreshToken!;
          uid.text = failure.session.id.replaceFirst('taygedo:', '');
          device.text = failure.session.deviceId;
        }
        if (smsSessionIssued) {
          importSession = true;
          acceptSms = false;
        }
        setState(() => error =
            failure is MiyousheException ? failure.message : '连接未完成，请稍后重试。');
      }
    } finally {
      if (mounted) {
        code.clear();
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar:
            AppBar(title: const Text('塔吉多登录', style: TextStyle(fontSize: 16))),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('连接塔吉多',
                        style: TextStyle(
                            fontSize: 25, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Text('读取已绑定的异环、幻塔角色。已有社区会话可直接导入。',
                        style: TextStyle(color: context.palette.secondary)),
                    const SizedBox(height: 22),
                    SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('短信登录')),
                          ButtonSegment(value: true, label: Text('高级导入')),
                        ],
                        selected: {
                          importSession
                        },
                        onSelectionChanged: busy
                            ? null
                            : (value) => setState(() {
                                  importSession = value.single;
                                  error = null;
                                  acceptSms = false;
                                  code.clear();
                                  refreshToken.clear();
                                })),
                    const SizedBox(height: 22),
                    if (importSession) ...[
                      Text(
                          '使用本人已有塔吉多社区的 refreshToken、UID 和原登录设备 ID。不会重新登录完美通行证。',
                          style: TextStyle(color: context.palette.secondary)),
                      const SizedBox(height: 16),
                      for (final field in [
                        (refreshToken, '社区刷新令牌（refreshToken）', true),
                        (uid, '塔吉多 UID', false),
                        (device, '原登录设备 ID（deviceId）', false),
                      ]) ...[
                        TextField(
                            controller: field.$1,
                            enabled: !busy,
                            obscureText: field.$3,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: const [],
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(labelText: field.$2)),
                        const SizedBox(height: 16),
                      ],
                      Text('续期会轮换令牌。同一会话请选一个程序维护；不要和 GsCore 同时续期同一份令牌。',
                          style: TextStyle(
                              fontSize: 12, color: context.palette.secondary)),
                    ] else ...[
                      Text('验证码登录成功后，访问令牌和 refreshToken 会自动获取并加密保存，无需手动填写。',
                          style: TextStyle(color: context.palette.secondary)),
                      const SizedBox(height: 12),
                      Text('短信登录会重新建立完美通行证会话，可能导致同通行证的游戏下线。查询与签到不会自动执行此登录。',
                          style: TextStyle(color: context.palette.error)),
                      CheckboxListTile(
                          value: acceptSms,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: busy
                              ? null
                              : (v) => setState(() => acceptSms = v == true),
                          title: const Text('我了解影响，仍使用短信登录')),
                      TextField(
                          controller: phone,
                          enabled: !busy,
                          keyboardType: TextInputType.phone,
                          maxLength: 11,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [],
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                              labelText: '手机号',
                              prefixText: '+86 ',
                              counterText: '')),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                            child: TextField(
                                controller: code,
                                enabled: !busy,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                obscureText: true,
                                autocorrect: false,
                                enableSuggestions: false,
                                autofillHints: const [],
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                    labelText: '短信验证码', counterText: ''))),
                        const SizedBox(width: 12),
                        TextButton(
                            onPressed: busy ||
                                    !acceptSms ||
                                    remaining > 0 ||
                                    phone.text.trim().length != 11
                                ? null
                                : send,
                            child: Text(
                                remaining > 0 ? '$remaining 秒后重发' : '发送验证码'))
                      ]),
                    ],
                    const SizedBox(height: 22),
                    if (error != null) ...[
                      Text(error!,
                          style: TextStyle(color: context.palette.error)),
                      const SizedBox(height: 18)
                    ],
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                            onPressed: busy ||
                                    (importSession
                                        ? refreshToken.text.trim().isEmpty ||
                                            uid.text.trim().isEmpty ||
                                            device.text.trim().isEmpty
                                        : !acceptSms ||
                                            sentPhone != phone.text.trim() ||
                                            code.text.trim().length != 6)
                                ? null
                                : connect,
                            child: Text(busy
                                ? '正在处理…'
                                : importSession
                                    ? '导入并连接'
                                    : '登录并连接'))),
                    const SizedBox(height: 18),
                    Text(
                        '社区访问令牌与刷新令牌加密保存在本机。手机号、验证码与 SDK 中间令牌不保存。请勿把凭据发到聊天或反馈中。',
                        style: TextStyle(
                            fontSize: 12, color: context.palette.secondary)),
                  ])),
        )),
      ));
}
