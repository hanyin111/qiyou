import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_state.dart';
import '../data/community_sms_login.dart';
import '../data/miyoushe_client.dart';
import '../domain/models.dart';
import 'design.dart';
import 'login_captcha.dart';
import 'official_login.dart';

class CommunitySmsLoginPage extends StatefulWidget {
  const CommunitySmsLoginPage(this.state, {super.key, required this.community});
  final AppState state;
  final Community community;
  @override
  State<CommunitySmsLoginPage> createState() => _CommunitySmsLoginPageState();
}

class _CommunitySmsLoginPageState extends State<CommunitySmsLoginPage> {
  final phone = TextEditingController(), code = TextEditingController();
  late final client = CommunitySmsLoginClient(widget.community);
  String? error, sentPhone, pendingCredential;
  bool busy = false;
  int remaining = 0;
  Timer? countdown;
  @override
  void dispose() {
    countdown?.cancel();
    client.close();
    pendingCredential = null;
    phone.clear();
    code.clear();
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  Future<Map<String, String>?> solve(LoginChallenge challenge) async {
    if (!mounted) return null;
    FocusScope.of(context).unfocus();
    return Navigator.push<Map<String, String>>(context,
        MaterialPageRoute(builder: (_) => LoginCaptchaPage(challenge)));
  }

  String message(Object failure) => failure is MiyousheException
      ? failure.message
      : '官方登录请求未完成，请检查网络后重试；也可使用下方官方网页登录。';

  Future<void> send() async {
    if (busy || remaining > 0) return;
    final number = phone.text.trim();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await client.sendCode(number, solve: solve);
      if (!mounted) return;
      setState(() {
        sentPhone = number;
        remaining = 60;
      });
      countdown?.cancel();
      countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => remaining--);
        if (remaining <= 0) timer.cancel();
      });
    } catch (failure) {
      if (mounted) setState(() => error = message(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> connect() async {
    if (busy) return;
    if (pendingCredential == null && phone.text.trim() != sentPhone) {
      setState(() => error = '请先为此手机号获取短信验证码。');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      pendingCredential ??=
          await client.login(phone.text.trim(), code.text.trim(), solve: solve);
      code.clear();
      await widget.state
          .connect(pendingCredential!, community: widget.community);
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) {
        setState(() => error = pendingCredential == null
            ? message(failure)
            : '${message(failure)} 登录会话已保留，可直接重试连接。');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: Text('${widget.community.title}登录')),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('手机号登录',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Text(
                        '短信与登录请求直接发送到${widget.community.title}官方服务器。需要人机验证时会单独显示，请手动完成。',
                        style: TextStyle(color: context.palette.secondary)),
                    const SizedBox(height: 28),
                    TextField(
                        controller: phone,
                        enabled: !busy,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11)
                        ],
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                            labelText: '手机号', prefixText: '+86 '),
                        onChanged: (_) => setState(() {
                              sentPhone = null;
                              pendingCredential = null;
                              code.clear();
                            })),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              controller: code,
                              enabled: !busy && pendingCredential == null,
                              keyboardType: TextInputType.number,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6)
                              ],
                              decoration:
                                  const InputDecoration(labelText: '短信验证码'))),
                      const SizedBox(width: 12),
                      TextButton(
                          onPressed: busy || remaining > 0 ? null : send,
                          child: Text(
                              remaining > 0 ? '${remaining}s 后重发' : '获取验证码'))
                    ]),
                    if (error != null) ...[
                      const SizedBox(height: 18),
                      Text(error!,
                          style: TextStyle(color: context.palette.error))
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                        onPressed: busy ? null : connect,
                        child: Text(busy
                            ? '正在处理…'
                            : pendingCredential == null
                                ? '登录并连接'
                                : '重试连接')),
                    const SizedBox(height: 18),
                    Text('成功后自动加密保存社区凭据。手机号和短信验证码不会保存。',
                        style: TextStyle(
                            fontSize: 12, color: context.palette.secondary)),
                    const SizedBox(height: 20),
                    TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                final connected = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => OfficialLoginPage(
                                            widget.state,
                                            community: widget.community)));
                                if (connected == true && context.mounted) {
                                  Navigator.pop(context, true);
                                }
                              },
                        child: const Text('使用官方网页登录')),
                  ])),
        ))),
      ));
}
