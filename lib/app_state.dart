import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'data/device_bridge.dart';
import 'data/miyoushe_client.dart';
import 'data/community_client.dart';
import 'data/kuro_client.dart';
import 'data/taygedo_client.dart';
import 'data/record_verification.dart';
import 'data/record_browser_session.dart';
import 'data/sync_models.dart';
import 'data/ios_companion.dart';
import 'domain/models.dart';

class AppState extends ChangeNotifier {
  AppState(
      {MiyousheClient? client,
      CommunityClient? kuro,
      CommunityClient? taygedo,
      DeviceBridge? bridge,
      IosCompanionBridge? companion})
      : client = client ?? MiyousheClient(),
        kuro = kuro ?? KuroClient(),
        taygedo = taygedo ?? TaygedoClient(),
        bridge = bridge ?? DeviceBridge(),
        companion = companion ?? IosCompanionBridge() {
    _makeDemo();
  }
  final MiyousheClient client;
  final CommunityClient kuro, taygedo;
  CommunityClient _clientFor(Community community) => switch (community) {
        Community.miyoushe => client,
        Community.kuro => kuro,
        Community.taygedo => taygedo,
      };
  final DeviceBridge bridge;
  final IosCompanionBridge companion;
  Set<Game> widgetGames = Game.values.toSet();
  bool fullEnergyReminders = false;
  String notificationPermission = 'unknown';
  String? companionError;
  bool _disposed = false;
  Future<void> _companionQueue = Future<void>.value();

  Future<void> updateCompanion() async {
    if (!companion.supported || !storageReady) return;
    final payload = companionPayload(
        entries: demo ? [] : entries,
        selected: widgetGames,
        signDay: signDay,
        connected: !demo && accounts.isNotEmpty,
        remindersEnabled: fullEnergyReminders && !demo,
        now: DateTime.now());
    final operation = _companionQueue.then((_) async {
      try {
        final available = await companion.publish(payload);
        companionError =
            available ? null : '当前签名未提供可用的小组件共享空间。请使用保留小组件与共享组权限的新版重新签名安装。';
      } catch (_) {
        companionError = '小组件或体力提醒暂未更新，请稍后刷新重试。';
      }
    });
    _companionQueue = operation;
    await operation;
    if (!_disposed) notifyListeners();
  }

  Future<void> checkCompanionPermission() async {
    if (!companion.supported) return;
    try {
      notificationPermission = await companion.permission();
    } catch (_) {
      notificationPermission = 'unknown';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setWidgetGame(Game game, bool selected) async {
    if (busy || !storageReady) throw StateError('请稍后重试');
    final previous = widgetGames;
    widgetGames = {...previous};
    selected ? widgetGames.add(game) : widgetGames.remove(game);
    busy = true;
    try {
      await _persist();
    } catch (_) {
      widgetGames = previous;
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
    await updateCompanion();
  }

  Future<void> setFullEnergyReminders(bool value) async {
    if (!companion.supported || busy || !storageReady) {
      throw StateError('请稍后重试');
    }
    busy = true;
    final previous = fullEnergyReminders;
    try {
      notificationPermission = await companion.permission(request: value);
      if (value &&
          !const {'authorized', 'provisional', 'ephemeral'}
              .contains(notificationPermission)) {
        throw StateError('未获得系统通知权限');
      }
      fullEnergyReminders = value;
      await _persist();
    } catch (_) {
      fullEnergyReminders = previous;
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
    await updateCompanion();
  }

  SyncConnection? syncConnection;
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
  bool _pendingCredentialSave = false;

  Future<void> _saveRotatedSession() async {
    try {
      await _persist();
    } catch (_) {
      throw const MiyousheException(
          ApiFailure.protocol, '会话已续期但未能加密保存，请保留窗口后重试；未执行后续请求。');
    }
  }

  // Only read operations may be retried. In particular, never replay a sign POST
  // when its response or subsequent confirmation is lost.
  Future<T> _readCommunity<T>(
      String accountId,
      Future<T> Function(CommunityClient, Account) read,
      Set<String> renewed) async {
    if (_pendingCredentialSave) await _saveRotatedSession();
    Account current() => accounts.firstWhere((a) => a.id == accountId);
    final account = current();
    final communityClient = _clientFor(account.community);
    try {
      return await read(communityClient, account);
    } on MiyousheException catch (error) {
      if (error.kind != ApiFailure.expired ||
          account.community != Community.taygedo ||
          communityClient is! RenewableCommunityClient) {
        rethrow;
      }
      if (account.refreshToken == null || account.refreshToken!.isEmpty) {
        throw const MiyousheException(
            ApiFailure.expired, '此旧会话未保存社区续期凭据，请在账号页导入已有塔吉多会话。不会自动执行短信登录。');
      }
      if (!renewed.add(accountId)) rethrow;
      final next = await communityClient.renew(current());
      if (next.id != account.id ||
          next.community != account.community ||
          next.deviceId != account.deviceId) {
        throw const MiyousheException(
            ApiFailure.protocol, '社区续期返回的账号或设备不一致，已停止。');
      }
      // The server may have already invalidated the old rotating refresh token.
      // Retain the new session in memory even if the OS vault write fails.
      accounts[accounts.indexWhere((a) => a.id == accountId)] = next;
      _pendingCredentialSave = true;
      await _saveRotatedSession();
      return read(communityClient, current());
    }
  }

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
        fullEnergyReminders = json['fullEnergyReminders'] == true;
        if (json['widgetGames'] is List) {
          widgetGames = Game.values
              .where((g) => (json['widgetGames'] as List).contains(g.name))
              .toSet();
        }
        taskDay = json['taskDay'] as String? ?? chinaDay();
        _savedTasks = (json['tasks'] as List? ?? [])
            .map((item) => RoutineTask.fromJson(object(item)))
            .toList();
        // An invalid optional sync configuration must not hide saved accounts.
        try {
          if (json['syncConnection'] is Map) {
            syncConnection =
                SyncConnection.fromJson(object(json['syncConnection']));
          }
        } catch (_) {
          syncConnection = null;
        }
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
    await updateCompanion();
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
        for (final role in account.activeRoles)
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
    await updateCompanion();
    notifyListeners();
  }

  Future<void> enterLive() async {
    if (busy || accounts.isEmpty) return;
    _makeLive();
    activities.clear();
    notifyListeners();
    await refresh();
  }

  Future<void> connect(String cookie,
      {Community community = Community.miyoushe}) async {
    if (busy) return;
    if (!bridge.supportsAccounts || !storageReady) {
      throw StateError('真实账号需要在支持安全存储的手机端连接。');
    }
    busy = true;
    notifyListeners();
    try {
      final values = community == Community.miyoushe
          ? MiyousheClient.parseCookie(cookie)
          : <String, String>{};
      final id = values['account_id_v2'] ??
          values['account_id'] ??
          values['ltuid_v2'] ??
          values['ltuid'];
      final existing = accounts
          .where(
              (account) => account.community == community && account.id == id)
          .firstOrNull;
      var account = await _clientFor(community)
          .connect(cookie, existingDeviceId: existing?.deviceId);
      if (account.community != community ||
          account.roles.any((r) => r.game.community != community)) {
        throw const MiyousheException(ApiFailure.protocol, '社区账号信息不一致，请重新连接。');
      }
      final previous = accounts
          .where((a) => a.id == account.id && a.community == community)
          .firstOrNull;
      if (community != Community.miyoushe &&
          previous != null &&
          account.recordHeaders['session-device'] != account.deviceId &&
          !(community == Community.kuro &&
              account.recordHeaders['devcode'] != null)) {
        account = Account(
            id: account.id,
            cookie: account.cookie,
            refreshToken: account.refreshToken,
            deviceId: previous.deviceId,
            roles: account.roles,
            community: community,
            recordHeaders: account.recordHeaders);
      }
      account =
          account.copyWith(hiddenGames: previous?.hiddenGames ?? const {});
      final updated = [
        ...accounts.where((item) => item.id != account.id),
        account
      ];
      await _persist(accountOverride: updated);
      accounts = updated;
      _makeLive();
      activities.clear();
      _record('已连接${community.title} · 发现 ${account.roles.length} 个游戏角色');
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
        final renewed = <String>{};
        for (final entry in visibleEntries) {
          entry.noteError = null;
          entry.signError = null;
          entry.noteNeedsVerification = false;
          try {
            entry.note = await _readCommunity(
                entry.accountId,
                (client, account) => client.daily(account, entry.role),
                renewed);
          } on MiyousheException catch (error) {
            entry.noteError = error.message;
            entry.noteNeedsVerification = error.kind == ApiFailure.verification;
          }
          try {
            entry.signStatus = await _readCommunity(
                entry.accountId,
                (client, account) => client.signInfo(account, entry.role),
                renewed);
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
      await updateCompanion();
      busy = false;
      notifyListeners();
    }
  }

  Future<String> signAll({GameEntry? only}) async {
    if (busy) return '正在处理，请稍候';
    checkDay();
    final selected = only == null
        ? visibleEntries
        : entries.where((e) => identical(e, only)).toList();
    if (selected.isEmpty) return '当前没有可签到角色，请先在账号页恢复游戏';
    final pending =
        selected.where((entry) => !entry.signStatus.isDone).toList();
    if (pending.isEmpty) return '这些角色今天已经签过啦';
    busy = true;
    notifyListeners();
    var done = 0;
    final renewed = <String>{};
    try {
      for (final entry in pending) {
        if (demo) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          entry.signStatus = SignStatus.signed;
          entry.signError = null;
        } else {
          try {
            if (_pendingCredentialSave) await _saveRotatedSession();
            var account =
                accounts.firstWhere((account) => account.id == entry.accountId);
            final preflight = account.community == Community.taygedo
                ? await _readCommunity(
                    entry.accountId,
                    (client, current) => client.signInfo(current, entry.role),
                    renewed)
                : SignStatus.pending;
            account = accounts.firstWhere((a) => a.id == entry.accountId);
            entry.signStatus = preflight.isDone
                ? preflight
                : await _clientFor(account.community).sign(account, entry.role);
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
    await updateCompanion();
    return demo ? '演示签到完成 · 未发送真实请求' : '已完成 $done / ${pending.length} 个角色的签到';
  }

  Account _noteAccount(GameEntry entry) {
    if (demo || busy || !entries.contains(entry)) {
      throw const MiyousheException(ApiFailure.protocol, '当前无法查询，请返回游戏页重试。');
    }
    return accounts.firstWhere((account) => account.id == entry.accountId);
  }

  Future<RecordVerification> createNoteVerification(GameEntry entry) async {
    final account = _noteAccount(entry);
    if (account.community != Community.miyoushe) throw StateError('此验证仅适用于米游社');
    busy = true;
    notifyListeners();
    try {
      return await client.createNoteVerification(account, entry.role);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> installRecordBrowserSession(
      GameEntry entry, RecordBrowserSession session) async {
    final previous = _noteAccount(entry);
    if (previous.community != Community.miyoushe) {
      throw StateError('此设备会话仅适用于米游社');
    }
    final cookies = MiyousheClient.parseCookie(previous.cookie)
      ..addAll(session.cookies);
    final updated = [...accounts];
    final index = updated.indexWhere((a) => a.id == previous.id);
    updated[index] = Account(
        id: previous.id,
        cookie: cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
        deviceId: session.deviceId,
        roles: previous.roles,
        recordHeaders: {
          ...previous.recordHeaders,
          'x-rpc-device_id': session.deviceId,
          'x-rpc-device_fp': session.fingerprint,
          'user-agent': session.userAgent
        },
        hiddenGames: previous.hiddenGames);
    busy = true;
    notifyListeners();
    try {
      await _persist(accountOverride: updated);
      accounts = updated;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> refreshNote(GameEntry entry,
      {RecordVerification? verification,
      RecordVerificationProof? proof}) async {
    final account = _noteAccount(entry);
    if ((verification != null || proof != null) &&
        account.community != Community.miyoushe) {
      throw StateError('此验证仅适用于米游社');
    }
    busy = true;
    notifyListeners();
    var verified = false;
    try {
      if (verification != null && proof != null) {
        await client.verifyNote(account, entry.role, verification, proof);
        verified = true;
      }
      final note = await _readCommunity(entry.accountId,
          (client, current) => client.daily(current, entry.role), <String>{});
      if (note.energy == null || note.capacity == null || note.capacity! <= 0) {
        throw const MiyousheException(
            ApiFailure.protocol, '社区未返回完整体力数据，暂时无法同步。');
      }
      entry.note = note;
      entry.noteError = null;
      entry.noteNeedsVerification = false;
      lastRefresh = DateTime.now();
      _record('${entry.role.game.shortTitle} · 便笺已同步');
    } on MiyousheException catch (error) {
      final failure = verified && error.kind == ApiFailure.verification
          ? MiyousheException(ApiFailure.verification,
              '米游社已确认验证码，但便笺查询仍受限制（错误码 ${error.code ?? '未知'}）。请稍后重试；若持续出现，可能还需要在米游社 App 处理账号验证。',
              code: error.code, stage: error.stage)
          : error;
      entry.noteError = failure.message;
      entry.noteNeedsVerification = failure.kind == ApiFailure.verification ||
          (verification != null &&
              !verified &&
              failure.kind != ApiFailure.expired);
      throw failure;
    } finally {
      await updateCompanion();
      busy = false;
      notifyListeners();
    }
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
    await updateCompanion();
    notifyListeners();
    if (!demo) await refresh();
  }

  Future<void> setGameHidden(Account account, Game game, bool hidden) async {
    if (busy || !storageReady) throw StateError('正在处理其他操作，请稍后重试。');
    final index = accounts.indexWhere(
        (a) => a.id == account.id && a.community == account.community);
    if (index < 0 || !accounts[index].roles.any((r) => r.game == game)) {
      throw StateError('未找到此账号的游戏。');
    }
    final games = {...accounts[index].hiddenGames};
    hidden ? games.add(game) : games.remove(game);
    final updated = [...accounts];
    updated[index] = accounts[index].copyWith(hiddenGames: games);
    busy = true;
    notifyListeners();
    try {
      await _persist(accountOverride: updated);
      accounts = updated;
      if (!demo) {
        final previous = {for (final e in entries) e.key: e};
        entries = [
          for (final a in accounts)
            for (final r in a.activeRoles)
              previous['${a.id}:${r.key}'] ??
                  GameEntry(role: r, accountId: a.id)
        ];
        if (filter != null && !entries.any((e) => e.role.game == filter)) {
          filter = null;
        }
      }
      _record('${game.shortTitle}已${hidden ? '移除' : '恢复'}', success: true);
      await updateCompanion();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _savePreferences() async {
    try {
      await _persist();
    } catch (_) {
      notice = '更改暂未保存到本机，请稍后重试。';
      notifyListeners();
    }
  }

  void _requireSyncStorage() {
    if (!bridge.supportsAccounts || !storageReady) {
      throw const SyncException('账号同步需要可用的本机安全存储，浏览器演示不接收凭据。');
    }
  }

  SyncContents exportSyncContents() {
    _requireSyncStorage();
    // Round trip creates an independent snapshot while an upload is in flight.
    return SyncContents.fromJson({
      'accounts': accounts.map((a) => a.toJson()).toList(),
      'tasks': (demo ? _savedTasks : tasks).map((t) => t.toJson()).toList(),
      'taskDay': taskDay,
      'dark': dark,
      'hideUid': hideUid,
    });
  }

  Future<T> runSync<T>(Future<T> Function() operation) async {
    _requireSyncStorage();
    if (busy) throw const SyncException('正在处理其他操作，请稍后重试。');
    busy = true;
    notifyListeners();
    try {
      if (_pendingCredentialSave) await _saveRotatedSession();
      return await operation();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> saveSyncConnection(SyncConnection? connection) async {
    await runSync(() async {
      await _persist(syncOverride: connection, clearSync: connection == null);
      syncConnection = connection;
    });
  }

  Future<void> importSyncContents(SyncContents remote,
      {required String expectedFingerprint,
      bool preferRemoteSessions = false}) async {
    await runSync(() async {
      final local = exportSyncContents();
      if (local.fingerprint != expectedFingerprint) {
        throw const SyncException('本机数据在预览后发生变化，请重新下载并预览。');
      }
      final mergedAccounts = {
        for (final a in local.accounts) syncAccountKey(a): a
      };
      for (final a in remote.accounts) {
        if (preferRemoteSessions) {
          mergedAccounts[syncAccountKey(a)] = a;
        } else {
          final current = mergedAccounts[syncAccountKey(a)];
          mergedAccounts[syncAccountKey(a)] = current == null
              ? a
              : current.copyWith(hiddenGames: a.hiddenGames);
        }
      }
      final today = chinaDay();
      RoutineTask normalize(RoutineTask t, String day) => RoutineTask(
          id: t.id, game: t.game, title: t.title, done: day == today && t.done);
      final mergedTasks = {
        for (final t in remote.tasks) t.id: normalize(t, remote.taskDay),
        for (final t in local.tasks) t.id: normalize(t, local.taskDay)
      };
      final merged = SyncContents(
          accounts: mergedAccounts.values.toList(),
          tasks: mergedTasks.values.toList(),
          taskDay: today,
          dark: remote.dark,
          hideUid: remote.hideUid);
      SyncContents.fromJson(merged.toJson());
      // Commit to the OS vault before changing the visible state. Failed saves
      // leave all current accounts and sessions intact.
      await _persist(contentsOverride: merged);
      accounts = merged.accounts;
      _savedTasks = merged.tasks;
      taskDay = today;
      dark = merged.dark;
      hideUid = merged.hideUid;
      if (accounts.isEmpty) {
        _makeDemo();
      } else {
        _makeLive();
      }
      activities.clear();
      _record('已合并云端账号；刷新后读取最新游戏状态');
      await updateCompanion();
    });
  }

  Future<void> _persist(
      {List<Account>? accountOverride,
      SyncContents? contentsOverride,
      SyncConnection? syncOverride,
      bool clearSync = false}) async {
    await bridge.write(jsonEncode({
      'version': 1,
      'accounts': (contentsOverride?.accounts ?? accountOverride ?? accounts)
          .map((account) => account.toJson())
          .toList(),
      'hideUid': contentsOverride?.hideUid ?? hideUid,
      'dark': contentsOverride?.dark ?? dark,
      'widgetGames': widgetGames.map((g) => g.name).toList(),
      'fullEnergyReminders': fullEnergyReminders,
      'taskDay': contentsOverride?.taskDay ?? taskDay,
      'tasks': (contentsOverride?.tasks ?? (demo ? _savedTasks : tasks))
          .map((task) => task.toJson())
          .toList(),
      if (!clearSync && (syncOverride ?? syncConnection) != null)
        'syncConnection': (syncOverride ?? syncConnection)!.toJson(),
    }));
    _pendingCredentialSave = false;
  }

  void _record(String text, {bool success = true}) {
    activities.insert(0, Activity(text, demo: demo, success: success));
    if (activities.length > 30) activities.removeLast();
  }

  @override
  void dispose() {
    _disposed = true;
    client.close();
    kuro.close();
    taygedo.close();
    super.dispose();
  }
}
