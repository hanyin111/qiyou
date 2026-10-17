import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../domain/models.dart';

class SyncException implements Exception {
  const SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SyncConnection {
  SyncConnection(String folder, this.username, this.password)
      : folder = _folder(folder) {
    if (username.isEmpty ||
        username.length > 512 ||
        username.contains(':') ||
        password.isEmpty ||
        password.length > 4096 ||
        RegExp(r'[\r\n\x00]').hasMatch('$username$password')) {
      throw const SyncException('请填写有效的 WebDAV 用户名和应用密码。');
    }
  }
  final Uri folder;
  final String username, password;
  Uri get file => folder.resolve('qiyou-vault-v1.json');
  static Uri _folder(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        input.length > 2048) {
      throw const SyncException('请填写 HTTPS WebDAV 文件夹地址，不含用户名、查询参数或片段。');
    }
    return uri.path.endsWith('/') ? uri : Uri.parse('${uri.toString()}/');
  }

  Map<String, dynamic> toJson() => {
        'folder': folder.toString(),
        'username': username,
        'password': password,
      };
  factory SyncConnection.fromJson(Map<String, dynamic> json) => SyncConnection(
      json['folder'] as String,
      json['username'] as String,
      json['password'] as String);
  @override
  String toString() => 'SyncConnection(redacted)';
}

String syncAccountKey(Account account) =>
    '${account.community.name}:${account.id}';

// Only portable application data. No WebDAV credentials, live game responses,
// CAPTCHA state, browser profiles, or activity logs enter a snapshot.
class SyncContents {
  SyncContents(
      {required this.accounts,
      required this.tasks,
      required this.taskDay,
      required this.dark,
      required this.hideUid});
  final List<Account> accounts;
  final List<RoutineTask> tasks;
  final String taskDay;
  final bool dark, hideUid;
  Map<String, dynamic> toJson() => {
        'accounts': accounts.map((a) => a.toJson()).toList(),
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'taskDay': taskDay,
        'dark': dark,
        'hideUid': hideUid,
      };
  String get fingerprint =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();
  factory SyncContents.fromJson(Map<String, dynamic> json) {
    try {
      final rawAccounts = json['accounts'] as List;
      final rawTasks = json['tasks'] as List;
      final day = json['taskDay'] as String;
      if (rawAccounts.length > 100 ||
          rawTasks.length > 1000 ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day) ||
          json['dark'] is! bool ||
          json['hideUid'] is! bool) {
        throw const FormatException();
      }
      final accounts = rawAccounts
          .map((a) => Account.fromJson(Map<String, dynamic>.from(a as Map)))
          .toList();
      final tasks = rawTasks
          .map((t) => RoutineTask.fromJson(Map<String, dynamic>.from(t as Map)))
          .toList();
      final ids = <String>{};
      for (final a in accounts) {
        if (!ids.add(syncAccountKey(a)) ||
            a.roles.isEmpty ||
            a.roles.length > 100 ||
            a.id.isEmpty ||
            a.id.length > 256 ||
            a.deviceId.isEmpty ||
            a.deviceId.length > 2048 ||
            a.cookie.isEmpty ||
            a.cookie.length > 64000 ||
            a.recordHeaders.length > 30 ||
            a.roles.any((r) => r.game.community != a.community) ||
            [
              a.id,
              a.deviceId,
              a.cookie,
              ...a.recordHeaders.keys,
              ...a.recordHeaders.values
            ].any(
                (s) => s.length > 64000 || RegExp(r'[\r\n\x00]').hasMatch(s))) {
          throw const FormatException();
        }
      }
      final taskIds = <String>{};
      for (final t in tasks) {
        if (!taskIds.add(t.id) ||
            t.id.isEmpty ||
            t.id.length > 256 ||
            t.title.trim().isEmpty ||
            t.title.length > 60) {
          throw const FormatException();
        }
      }
      return SyncContents(
          accounts: accounts,
          tasks: tasks,
          taskDay: day,
          dark: json['dark'] as bool,
          hideUid: json['hideUid'] as bool);
    } catch (_) {
      throw const SyncException('云端数据格式不受支持，未更改本机账号。');
    }
  }
  @override
  String toString() =>
      'SyncContents(accounts: ${accounts.length}, tasks: ${tasks.length})';
}

class SyncSnapshot {
  SyncSnapshot(
      {required this.contents,
      required this.createdAt,
      required this.revision});
  factory SyncSnapshot.create(SyncContents contents) => SyncSnapshot(
      contents: contents,
      createdAt: DateTime.now().toUtc(),
      revision: List.generate(16, (_) => Random.secure().nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join());
  final SyncContents contents;
  final DateTime createdAt;
  final String revision;
  Map<String, dynamic> toJson() => {
        'schema': 1,
        'createdAt': createdAt.toIso8601String(),
        'revision': revision,
        'contents': contents.toJson()
      };
  factory SyncSnapshot.fromJson(Map<String, dynamic> json) {
    try {
      if (json['schema'] != 1 ||
          json['revision'] is! String ||
          !RegExp(r'^[0-9a-f]{32}$').hasMatch(json['revision'] as String)) {
        throw const FormatException();
      }
      return SyncSnapshot(
          contents: SyncContents.fromJson(
              Map<String, dynamic>.from(json['contents'] as Map)),
          createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
          revision: json['revision'] as String);
    } catch (_) {
      throw const SyncException('云端备份格式不受支持，请使用兼容版本。');
    }
  }
  @override
  String toString() => 'SyncSnapshot(redacted)';
}
