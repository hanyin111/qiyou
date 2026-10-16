import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'data/device_bridge.dart';
import 'data/miyoushe_client.dart';
import 'domain/models.dart';

class AppState extends ChangeNotifier {
  AppState({MiyousheClient? client, DeviceBridge? bridge})
      : client = client ?? MiyousheClient(),
        bridge = bridge ?? DeviceBridge() {
    _makeDemo();
  }
  final MiyousheClient client;
  final DeviceBridge bridge;
  bool demo = true,
      busy = false,
      hideUid = true,
      storageReady = false,
      dark = false;
  String? notice;
  Game? filter;
  String? accountFilter;
  List<Account> accounts = [];
  List<GameEntry> entries = [];
  List<RoutineTask> tasks = [];
  List<RoutineTask> _savedTasks = [];
  final List<Activity> activities = [];
  String taskDay = chinaDay();
  String signDay = chinaDay();
  DateTime? lastRefresh;

  List<GameEntry> get visibleEntries => entries
      .where((entry) =>
          (filter == null || entry.role.game == filter) &&
          (accountFilter == null || demo || entry.accountId == accountFilter))
      .toList();
  List<RoutineTask> get visibleTasks =>
      tasks.where((task) => filter == null || task.game == filter).toList();
  int get signedCount =>
      entries.where((entry) => entry.signStatus.isDone).length;
  int get nearFullCount =>
      entries.where((entry) => entry.note?.nearFull == true).length;
  int get doneTasks => tasks.where((task) => task.done).length;

  Future<void> initialize() async {
    if (!bridge.supportsAccounts) return;
    try {
      final saved = await bridge.read();
      storageReady = true;
      if (saved != null) {
        final json = object(jsonDecode(saved));
        accounts = (json['accounts'] as List? ?? [])
            .map((item) => Account.fromJson(object(item)))
            .toList();
        hideUid = json['hideUid'] != false;
        dark = json['dark'] == true;
        taskDay = json['taskDay'] as String? ?? chinaDay();
        _savedTasks = (json['tasks'] as List? ?? [])
            .map((item) => RoutineTask.fromJson(object(item)))
            .toList();
        if (taskDay != chinaDay()) {
          for (final task in _savedTasks) {
            task.done = false;
          }
          taskDay = chinaDay();
        }
        if (accounts.isNotEmpty) {
          _makeLive();
          await refresh();
        }
      }
    } catch (_) {
      storageReady = false;
      notice = '本机安全存储暂不可用，当前可以体验演示空间。';
    }
    notifyListeners();
  }

  void setFilter(Game? value) {
    filter = value;
    notifyListeners();
  }

  void setAccountFilter(String? value) {
    accountFilter = value;
    notifyListeners();
  }

  void _makeDemo() {
    demo = true;
    filter = null;
    accountFilter = null;
    final now = DateTime.now();
    entries = [
      GameEntry(
          accountId: 'demo',
          role: const Role(
              game: Game.genshin,
              uid: '100082106',
              region: 'cn_gf01',
              nickname: '旅行者',
              serverName: '天空岛',
              level: 60),
          signStatus: SignStatus.pending,
          note: DailyNote(
              syncedAt: now,
              energy: 168,
              capacity: 200,
              recoverySeconds: 15360,
              metrics: const [
                Metric('每日委托', '2 / 4'),
                Metric('探索派遣', '5 项已完成', complete: true)
              ])),
      GameEntry(
          accountId: 'demo',
          role: const Role(
              game: Game.starRail,
              uid: '100762082',
              region: 'prod_gf_cn',
              nickname: '开拓者',
              serverName: '星穹列车',
              level: 70),
          signStatus: SignStatus.pending,
          note: DailyNote(
              syncedAt: now,
              energy: 224,
              capacity: 300,
              recoverySeconds: 27360,
              metrics: const [
                Metric('每日实训', '500 / 500', complete: true),
                Metric('历战余响', '1 / 3')
              ])),
      GameEntry(
          accountId: 'demo',
          role: const Role(
              game: Game.zenless,
              uid: '100296103',
              region: 'prod_gf_cn',
              nickname: '绳匠',
              serverName: '新艾利都',
              level: 60),
          signStatus: SignStatus.pending,
          note: DailyNote(
              syncedAt: now,
              energy: 198,
              capacity: 240,
              recoverySeconds: 15120,
              metrics: const [
                Metric('今日活跃', '200 / 400'),
                Metric('录像店经营', '正在营业', complete: true)
              ])),
    ];
    tasks = [
      RoutineTask(id: 'd1', game: Game.genshin, title: '完成今天的每日委托'),
      RoutineTask(id: 'd2', game: Game.starRail, title: '领取每日实训奖励', done: true),
      RoutineTask(id: 'd3', game: Game.zenless, title: '去咖啡店喝一杯'),
      RoutineTask(id: 'd4', game: Game.genshin, title: '收取探索派遣奖励'),
    ];
    lastRefresh = now;
  }

  void _makeLive() {
    demo = false;
    filter = null;
    accountFilter = null;
    entries = [
      for (final account in accounts)
        for (final role in account.roles)
          GameEntry(role: role, accountId: account.id)
    ];
    tasks = _savedTasks;
    lastRefresh = null;
    notice = null;
  }

  Future<void> enterDemo() async {
    if (busy) return;
    if (!demo) _savedTasks = tasks;
    _makeDemo();
    activities.clear();
    notifyListeners();
  }

  Future<void> enterLive() async {
    if (busy || accounts.isEmpty) return;
    _makeLive();
    activities.clear();
    notifyListeners();
    await refresh();
  }

  Future<void> connect(String cookie) async {
    if (busy) return;
    if (!bridge.supportsAccounts || !storageReady) {
      throw StateError('真实账号需要在支持安全存储的手机端连接。');
    }
    busy = true;
    notifyListeners();
    try {
      final values = MiyousheClient.parseCookie(cookie);
      final id = values['account_id_v2'] ??
          values['account_id'] ??
          values['ltuid_v2'] ??
          values['ltuid'];
      final existing =
          accounts.where((account) => account.id == id).firstOrNull;
      final account =
          await client.connect(cookie, existingDeviceId: existing?.deviceId);
      final updated = [
        ...accounts.where((item) => item.id != account.id),
        account
      ];
      await _persist(accountOverride: updated);
      accounts = updated;
      _makeLive();
      activities.clear();
      _record('已连接米游社 · 发现 ${account.roles.length} 个游戏角色');
    } finally {
      busy = false;
      notifyListeners();
    }
    await refresh();
  }

  void checkDay() {
    final today = chinaDay();
    if (signDay != today) {
      signDay = today;
      for (final entry in entries) {
        entry.signStatus = demo ? SignStatus.pending : SignStatus.unknown;
      }
    }
    if (taskDay != today) {
      taskDay = today;
      for (final task in tasks) {
        task.done = false;
      }
    }
  }

  Future<void> refresh() async {
    if (busy) return;
    checkDay();
    busy = true;
    notice = null;
    notifyListeners();
    try {
      if (demo) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
        _record('演示数据已刷新');
        // Keep the original stamina timestamp: refresh must not invent regenerated data.
      } else {
        for (final entry in visibleEntries) {
          final account =
              accounts.firstWhere((account) => account.id == entry.accountId);
          entry.noteError = null;
          entry.signError = null;
          entry.noteNeedsVerification = false;
          try {
            entry.note = await client.daily(account, entry.role);
          } on MiyousheException catch (error) {
            entry.noteError = error.message;
            entry.noteNeedsVerification = error.kind == ApiFailure.verification;
          }
          try {
            entry.signStatus = await client.signInfo(account, entry.role);
          } on MiyousheException catch (error) {
            entry.signStatus = _status(error);
            entry.signError = error.message;
          }
          notifyListeners();
        }
        final failures =
            visibleEntries.where((entry) => entry.error != null).length;
        _record(failures == 0 ? '游戏状态已同步' : '$failures 个角色的部分数据未同步',
            success: failures == 0);
      }
      lastRefresh = DateTime.now();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String> signAll({GameEntry? only}) async {
    if (busy) return '正在处理，请稍候';
    checkDay();
    final selected = only == null ? visibleEntries : [only];
    final pending =
        selected.where((entry) => !entry.signStatus.isDone).toList();
    if (pending.isEmpty) return '这些角色今天已经签过啦';
    busy = true;
    notifyListeners();
    var done = 0;
    try {
      for (final entry in pending) {
        if (demo) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          entry.signStatus = SignStatus.signed;
          entry.signError = null;
        } else {
          try {
            final account =
                accounts.firstWhere((account) => account.id == entry.accountId);
            entry.signStatus = await client.sign(account, entry.role);
            entry.signError = null;
          } on MiyousheException catch (error) {
            entry.signStatus = _status(error);
            entry.signError = error.message;
          }
        }
        if (entry.signStatus.isDone) done++;
        _record('${entry.role.game.shortTitle} · ${entry.signStatus.label}',
            success: entry.signStatus.isDone);
        notifyListeners();
      }
    } finally {
      busy = false;
      notifyListeners();
    }
    return demo ? '演示签到完成 · 未发送真实请求' : '已完成 $done / ${pending.length} 个角色的签到';
  }

  Future<void> acceptOfficialNote(GameEntry entry, Map<String, dynamic> data,
      Map<String, String> headers) async {
    if (demo || busy || !entries.contains(entry)) return;
    final note = DailyNote.parse(entry.role.game, data, DateTime.now());
    if (note.energy == null || note.capacity == null || note.capacity! <= 0) {
      throw const MiyousheException(ApiFailure.protocol, '官方便笺返回的数据不完整。');
    }
    final index =
        accounts.indexWhere((account) => account.id == entry.accountId);
    if (index < 0) return;
    final previous = accounts[index];
    final updated = [...accounts];
    updated[index] = Account(
        id: previous.id,
        cookie: previous.cookie,
        deviceId: previous.deviceId,
        roles: previous.roles,
        recordHeaders: {
          ...previous.recordHeaders,
          ...MiyousheClient.safeRecordHeaders(headers)
        });
    await _persist(accountOverride: updated);
    accounts = updated;
    entry.note = note;
    entry.noteError = null;
    entry.noteNeedsVerification = false;
    lastRefresh = DateTime.now();
    _record('${entry.role.game.shortTitle} · 已从官方工具同步便笺');
    notifyListeners();
  }

  SignStatus _status(MiyousheException error) => switch (error.kind) {
        ApiFailure.expired => SignStatus.expired,
        ApiFailure.verification => SignStatus.verification,
        _ => SignStatus.failed,
      };

  Future<void> toggleTask(RoutineTask task) async {
    if (busy) return;
    checkDay();
    task.done = !task.done;
    notifyListeners();
    if (!demo) await _savePreferences();
  }

  Future<void> addTask(String title, Game game) async {
    if (busy) return;
    final clean = title.trim();
    if (clean.isEmpty || clean.length > 60) return;
    tasks.add(RoutineTask(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        game: game,
        title: clean));
    notifyListeners();
    if (!demo) await _savePreferences();
  }

  Future<void> setHideUid(bool value) async {
    if (busy) return;
    hideUid = value;
    notifyListeners();
    if (storageReady) await _savePreferences();
  }

  Future<void> setDark(bool value) async {
    dark = value;
    notifyListeners();
    if (storageReady && !busy) await _savePreferences();
  }

  Future<void> removeAccount(Account account) async {
    if (busy) return;
    final updated = accounts.where((item) => item.id != account.id).toList();
    await _persist(accountOverride: updated);
    accounts = updated;
    if (accounts.isEmpty) {
      _makeDemo();
    } else {
      _makeLive();
    }
    activities.clear();
    notifyListeners();
    if (!demo) await refresh();
  }

  Future<void> _savePreferences() async {
    try {
      await _persist();
    } catch (_) {
      notice = '更改暂未保存到本机，请稍后重试。';
      notifyListeners();
    }
  }

  Future<void> _persist({List<Account>? accountOverride}) =>
      bridge.write(jsonEncode({
        'version': 1,
        'accounts': (accountOverride ?? accounts)
            .map((account) => account.toJson())
            .toList(),
        'hideUid': hideUid,
        'dark': dark,
        'taskDay': taskDay,
        'tasks':
            (demo ? _savedTasks : tasks).map((task) => task.toJson()).toList(),
      }));

  void _record(String text, {bool success = true}) {
    activities.insert(0, Activity(text, demo: demo, success: success));
    if (activities.length > 30) activities.removeLast();
  }

  @override
  void dispose() {
    client.close();
    super.dispose();
  }
}
