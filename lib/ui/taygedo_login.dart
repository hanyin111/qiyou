import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../data/taygedo_login_client.dart';
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
  late final login = TaygedoLoginClient(platform: defaultTargetPlatform.name);
  Timer? timer;
  bool busy = false;
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
    super.dispose();
  }

  Future<void> send() async {
    if (busy || remaining > 0) return;
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
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final credential = await login.login(phone.text.trim(), code.text.trim());
      code.clear();
      await widget.state.connect(credential, community: Community.taygedo);
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) {
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
                    const Text('连接游戏账号',
                        style: TextStyle(
                            fontSize: 25, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Text('使用完美通行证手机号登录，读取已绑定的异环、幻塔角色。',
                        style: TextStyle(color: context.palette.secondary)),
                    const SizedBox(height: 30),
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
                                  remaining > 0 ||
                                  phone.text.trim().length != 11
                              ? null
                              : send,
                          child:
                              Text(remaining > 0 ? '$remaining 秒后重发' : '发送验证码'))
                    ]),
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
                                    sentPhone != phone.text.trim() ||
                                    code.text.trim().length != 6
                                ? null
                                : connect,
                            child: Text(busy ? '正在处理…' : '登录并连接'))),
                    const SizedBox(height: 18),
                    Text('手机号与验证码仅发送至完美世界官方服务器，不保存到本机。连接成功后，只加密保存登录会话。',
                        style: TextStyle(
                            fontSize: 12, color: context.palette.secondary)),
                  ])),
        )),
      ));
}
