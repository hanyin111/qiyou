import 'package:flutter/material.dart';
import '../app_state.dart';
import '../data/sync_crypto.dart';
import '../data/sync_models.dart';
import '../data/webdav_sync.dart';
import '../domain/models.dart';
import 'design.dart';

class SyncPage extends StatefulWidget {
  const SyncPage({super.key, required this.state, this.clientFactory});
  final AppState state;
  final WebDavSyncClient Function(SyncConnection)? clientFactory;
  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final _folder = TextEditingController(),
      _user = TextEditingController(),
      _password = TextEditingController(),
      _secret = TextEditingController();
  bool _working = false;
  String? _message;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    final config = widget.state.syncConnection;
    if (config != null) {
      _folder.text = config.folder.toString();
      _user.text = config.username;
      _password.text = config.password;
    }
  }

  @override
  void dispose() {
    for (final c in [_folder, _user, _password, _secret]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  SyncConnection _connection() =>
      SyncConnection(_folder.text, _user.text.trim(), _password.text);

  WebDavSyncClient _client() =>
      widget.clientFactory?.call(_connection()) ??
      WebDavSyncClient(_connection());

  void _result(String message, {bool failed = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _failed = failed;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _perform(Future<String?> Function() action) async {
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final message = await action();
      if (mounted && message != null) {
        _result(message);
      }
    } on SyncException catch (e) {
      _result(e.message, failed: true);
    } catch (_) {
      _result('操作未完成，本机账号未被替换；请检查网络或安全存储。', failed: true);
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _test() => _perform(() async {
        final client = _client();
        try {
          await widget.state.runSync(client.testConnection);
          return 'WebDAV 已响应，上传和下载权限将在操作时确认。';
        } finally {
          client.close();
        }
      });

  Future<void> _save() => _perform(() async {
        await widget.state.saveSyncConnection(_connection());
        return '连接已保存到本机安全存储。同步密码不会保存。';
      });

  Future<void> _clear() => _perform(() async {
        await widget.state.saveSyncConnection(null);
        _folder.clear();
        _user.clear();
        _password.clear();
        _secret.clear();
        return '已清除本机同步连接，游戏账号和云端备份仍保留。';
      });

  String _summary(SyncContents data) {
    final communities = Community.values
        .map((c) {
          final count = data.accounts.where((a) => a.community == c).length;
          return count == 0 ? null : '${c.title} $count 个账号';
        })
        .whereType<String>()
        .join('、');
    return '${data.accounts.length} 个账号 · ${data.tasks.length} 项清单'
        '${communities.isEmpty ? '' : '\n$communities'}';
  }

  Future<void> _upload() => _perform(() async {
        final password = _secret.text;
        validateSyncPassword(password);
        final client = _client();
        try {
          final local = SyncSnapshot.create(widget.state.exportSyncContents());
          final previous =
              await widget.state.runSync(() => client.download(password));
          if (!mounted) return null;
          if (previous != null && !previous.canOverwrite) {
            throw const SyncException('服务未提供强 ETag，无法安全覆盖已有备份；仍可下载。');
          }
          final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => _UploadDialog(
                  local: _summary(local.contents),
                  remote: previous == null
                      ? null
                      : _summary(previous.snapshot.contents),
                  password: password));
          if (confirmed != true) return null;
          if (widget.state.exportSyncContents().fingerprint !=
              local.contents.fingerprint) {
            throw const SyncException('本机数据在预览后发生变化，请重新上传并预览。');
          }
          await widget.state.runSync(
              () => client.upload(local, password, previous: previous));
          return '加密备份已上传并确认。其他设备可使用相同地址和同步密码下载。';
        } finally {
          client.close();
        }
      });

  Future<void> _download() => _perform(() async {
        final password = _secret.text;
        validateSyncPassword(password);
        final client = _client();
        try {
          final remote =
              await widget.state.runSync(() => client.download(password));
          if (remote == null) throw const SyncException('云端尚无备份，请先在已有账号的设备上传。');
          if (!mounted) return null;
          final local = widget.state.exportSyncContents();
          var preferRemote = false;
          final localIds = local.accounts.map(syncAccountKey).toSet();
          final overlaps = remote.snapshot.contents.accounts
              .where((a) => localIds.contains(syncAccountKey(a)))
              .length;
          final time = remote.snapshot.createdAt.toLocal();
          final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => StatefulBuilder(
                  builder: (context, update) => AlertDialog(
                        title: const Text('合并云端备份'),
                        content: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(_summary(remote.snapshot.contents)),
                              const SizedBox(height: 12),
                              Text(
                                  '备份时间：${time.year}/${time.month}/${time.day} ${clockText(time)}'),
                              const SizedBox(height: 12),
                              const Text(
                                  '添加云端账号和清单，保留本机独有内容，并应用云端亮暗模式、UID 设置和游戏移除状态。同一清单保留本机进度；旧日期的完成状态会重置。'),
                              if (overlaps > 0) ...[
                                const SizedBox(height: 12),
                                CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    value: preferRemote,
                                    onChanged: (value) => update(() {
                                          preferRemote = value == true;
                                        }),
                                    title: const Text('同一账号使用云端登录态'),
                                    subtitle: Text(
                                        '$overlaps 个重复账号；默认保留本机登录态，避免旧凭据覆盖新登录。')),
                              ],
                              const SizedBox(height: 12),
                              const Text('合并不会执行登录或签到。返回游戏页刷新后确认会话是否可用。'),
                            ])),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消')),
                          FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('合并到本机'))
                        ],
                      )));
          if (confirmed != true) return null;
          await widget.state.importSyncContents(remote.snapshot.contents,
              expectedFingerprint: local.fingerprint,
              preferRemoteSessions: preferRemote);
          return '已合并并加密保存到本机。请返回游戏页刷新状态。';
        } finally {
          client.close();
        }
      });

  Widget _field(TextEditingController controller, String label,
          {bool secret = false, String? hint}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextField(
              controller: controller,
              enabled: !_working,
              obscureText: secret,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType:
                  secret ? TextInputType.visiblePassword : TextInputType.text,
              decoration: InputDecoration(labelText: label, hintText: hint)));

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_working,
      child: Scaffold(
          appBar: AppBar(
              title: const Text('账号同步'), automaticallyImplyLeading: !_working),
          body: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ListView(padding: const EdgeInsets.all(24), children: [
                    Surface(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('自己的云端备份',
                              style: TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          const Text(
                              '使用已建立的 HTTPS WebDAV 文件夹。账号、设置和清单先在设备上加密，再上传到你选择的服务。'),
                          const SizedBox(height: 22),
                          _field(_folder, 'WebDAV 文件夹地址',
                              hint: 'https://example.com/dav/qiyou/'),
                          _field(_user, 'WebDAV 用户名'),
                          _field(_password, 'WebDAV 应用密码', secret: true),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            OutlinedButton(
                                onPressed: _working ? null : _test,
                                child: const Text('测试连接')),
                            TextButton(
                                onPressed: _working ? null : _save,
                                child: const Text('保存连接')),
                            if (widget.state.syncConnection != null)
                              TextButton(
                                  onPressed: _working ? null : _clear,
                                  child: const Text('清除本机连接')),
                          ]),
                        ])),
                    const SizedBox(height: 20),
                    Surface(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('同步密码',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          const Text(
                              '在所有设备输入同一个密码，至少 12 个字符。与 WebDAV 应用密码分开设置；不会保存或发送此密码。忘记后无法解密备份。'),
                          const SizedBox(height: 18),
                          _field(_secret, '用于加密和解锁的同步密码', secret: true),
                          Wrap(spacing: 12, runSpacing: 12, children: [
                            FilledButton.icon(
                                onPressed: _working ? null : _upload,
                                icon: const Icon(Icons.cloud_upload_outlined),
                                label: const Text('上传到云端')),
                            OutlinedButton.icon(
                                onPressed: _working ? null : _download,
                                icon: const Icon(Icons.cloud_download_outlined),
                                label: const Text('从云端下载')),
                          ]),
                        ])),
                    if (_working)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: LinearProgressIndicator()),
                    if (_message != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Text(_message!,
                              style: TextStyle(
                                  color: _failed
                                      ? context.palette.error
                                      : context.palette.text))),
                    const SizedBox(height: 20),
                    Text(
                        '手动同步，不执行后台签到。体力和签到状态以官方最新查询为准。共享已有会话不会申请新登录，但各社区仍可能要求重新验证，无法保证多设备会话一直有效。',
                        style: TextStyle(
                            fontSize: 12, color: context.palette.secondary)),
                  ])))));
}

class _UploadDialog extends StatefulWidget {
  const _UploadDialog(
      {required this.local, required this.remote, required this.password});
  final String local, password;
  final String? remote;
  @override
  State<_UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends State<_UploadDialog> {
  final _confirm = TextEditingController();
  @override
  void dispose() {
    _confirm.clear();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.remote == null ? '创建加密备份' : '更新云端备份'),
          content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('本机：${widget.local}'),
                const SizedBox(height: 12),
                Text(widget.remote == null
                    ? '云端尚无备份。请再次输入同步密码确认。'
                    : '云端：${widget.remote}\n\n将以本机完整内容替换云端备份。云端独有内容会被移除；如需保留，请取消后先下载合并。'),
                if (widget.remote == null) ...[
                  const SizedBox(height: 16),
                  TextField(
                      controller: _confirm,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(labelText: '再次输入同步密码'),
                      onChanged: (_) => setState(() {})),
                ],
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed:
                    widget.remote == null && _confirm.text != widget.password
                        ? null
                        : () => Navigator.pop(context, true),
                child: const Text('确认上传'))
          ]);
}
