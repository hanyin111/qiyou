import 'dart:math';

enum Community { miyoushe, kuro, taygedo }

extension CommunityInfo on Community {
  String get title => switch (this) {
        Community.miyoushe => '米游社',
        Community.kuro => '库街区',
        Community.taygedo => '塔吉多',
      };
  String get games => Game.values
      .where((g) => g.community == this)
      .map((g) => g.shortTitle)
      .join('、');
}

enum Game {
  genshin,
  starRail,
  zenless,
  wutheringWaves,
  punishingGrayRaven,
  nevernessToEverness,
  towerOfFantasy
}

extension GameInfo on Game {
  String get title => switch (this) {
        Game.genshin => '原神',
        Game.starRail => '崩坏：星穹铁道',
        Game.zenless => '绝区零',
        Game.wutheringWaves => '鸣潮',
        Game.punishingGrayRaven => '战双帕弥什',
        Game.nevernessToEverness => '异环',
        Game.towerOfFantasy => '幻塔',
      };
  String get shortTitle => this == Game.starRail ? '星穹铁道' : title;
  Community get community => switch (this) {
        Game.genshin || Game.starRail || Game.zenless => Community.miyoushe,
        Game.wutheringWaves || Game.punishingGrayRaven => Community.kuro,
        Game.nevernessToEverness || Game.towerOfFantasy => Community.taygedo,
      };
  String get communityGameId => switch (this) {
        Game.wutheringWaves => '3',
        Game.punishingGrayRaven => '2',
        Game.nevernessToEverness => '1289',
        Game.towerOfFantasy => '1256',
        _ => '',
      };
  String get english => switch (this) {
        Game.genshin => 'GENSHIN IMPACT',
        Game.starRail => 'HONKAI: STAR RAIL',
        Game.zenless => 'ZENLESS ZONE ZERO',
        Game.wutheringWaves => 'WUTHERING WAVES',
        Game.punishingGrayRaven => 'PUNISHING: GRAY RAVEN',
        Game.nevernessToEverness => 'NEVERNESS TO EVERNESS',
        Game.towerOfFantasy => 'TOWER OF FANTASY',
      };
  String get biz => switch (this) {
        Game.genshin => 'hk4e_cn',
        Game.starRail => 'hkrpg_cn',
        Game.zenless => 'nap_cn',
        _ => '',
      };
  String get resource => switch (this) {
        Game.genshin => '原粹树脂',
        Game.starRail => '开拓力',
        Game.zenless => '电量',
        Game.wutheringWaves => '结晶波片',
        Game.punishingGrayRaven => '血清',
        Game.nevernessToEverness => '本性像素',
        Game.towerOfFantasy => '活力',
      };
  String get activityId => switch (this) {
        Game.genshin => 'e202311201442471',
        Game.starRail => 'e202304121516551',
        Game.zenless => 'e202406242138391',
        _ => '',
      };
  String get signGame => switch (this) {
        Game.genshin => 'hk4e',
        Game.starRail => 'hkrpg',
        Game.zenless => 'zzz',
        _ => '',
      };
}

int? number(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');
Map<String, dynamic> object(Object? value) => value is Map
    ? value.map((key, value) => MapEntry('$key', value))
    : <String, dynamic>{};

String chinaDay([DateTime? time]) => (time ?? DateTime.now())
    .toUtc()
    .add(const Duration(hours: 8))
    .toIso8601String()
    .substring(0, 10);

class Role {
  const Role(
      {required this.game,
      required this.uid,
      required this.region,
      required this.nickname,
      required this.serverName,
      this.level});
  final Game game;
  final String uid, region, nickname, serverName;
  final int? level;
  String get key => '${game.name}:$region:$uid';
  Map<String, dynamic> toJson() => {
        'game': game.name,
        'uid': uid,
        'region': region,
        'nickname': nickname,
        'serverName': serverName,
        'level': level
      };
  factory Role.fromJson(Map<String, dynamic> json) => Role(
      game: Game.values.byName(json['game'] as String),
      uid: json['uid'] as String,
      region: json['region'] as String,
      nickname: json['nickname'] as String,
      serverName: json['serverName'] as String,
      level: number(json['level']));
}

class Account {
  const Account(
      {required this.id,
      required this.cookie,
      required this.deviceId,
      required this.roles,
      this.community = Community.miyoushe,
      this.recordHeaders = const {},
      this.hiddenGames = const {},
      this.refreshToken});
  final String id, cookie, deviceId;
  final List<Role> roles;
  final Map<String, String> recordHeaders;
  final Community community;
  final String? refreshToken;
  final Set<Game> hiddenGames;
  Iterable<Role> get activeRoles =>
      roles.where((r) => !hiddenGames.contains(r.game));
  String get title =>
      roles.isEmpty ? '${community.title}账号' : roles.first.nickname;
  Map<String, dynamic> toJson() => {
        'id': id,
        'cookie': cookie,
        'deviceId': deviceId,
        'community': community.name,
        'recordHeaders': recordHeaders,
        'hiddenGames': hiddenGames.map((g) => g.name).toList(),
        if (refreshToken != null) 'refreshToken': refreshToken,
        'roles': roles.map((role) => role.toJson()).toList()
      };
  factory Account.fromJson(Map<String, dynamic> json) => Account(
      id: json['id'] as String,
      cookie: json['cookie'] as String,
      deviceId: json['deviceId'] as String,
      community:
          Community.values.byName(json['community'] as String? ?? 'miyoushe'),
      refreshToken: json['refreshToken'] as String?,
      recordHeaders: object(json['recordHeaders'])
          .map((key, value) => MapEntry(key, '$value')),
      hiddenGames: (json['hiddenGames'] as List? ?? const [])
          .map((g) => Game.values.byName(g as String))
          .toSet(),
      roles: (json['roles'] as List)
          .map((value) => Role.fromJson(object(value)))
          .toList());
  Account copyWith(
          {String? cookie,
          String? deviceId,
          Map<String, String>? recordHeaders,
          Set<Game>? hiddenGames,
          String? refreshToken}) =>
      Account(
          id: id,
          cookie: cookie ?? this.cookie,
          deviceId: deviceId ?? this.deviceId,
          roles: roles,
          community: community,
          refreshToken: refreshToken ?? this.refreshToken,
          recordHeaders: recordHeaders ?? this.recordHeaders,
          hiddenGames: hiddenGames ?? this.hiddenGames);
  // Deliberately keep credentials out of debug output and diagnostics.
  @override
  String toString() => 'Account(roles: ${roles.length})';
}

class Metric {
  const Metric(this.label, this.value, {this.complete = false});
  final String label, value;
  final bool complete;
}

class DailyNote {
  const DailyNote(
      {required this.syncedAt,
      this.energy,
      this.capacity,
      this.recoverySeconds,
      this.metrics = const []});
  final DateTime syncedAt;
  final int? energy, capacity, recoverySeconds;
  final List<Metric> metrics;
  double get ratio => energy == null || capacity == null || capacity! <= 0
      ? 0
      : (energy! / capacity!).clamp(0, 1).toDouble();
  bool get nearFull => energy != null && capacity != null && ratio >= .8;
  Duration? remainingAt(DateTime now) => recoverySeconds == null
      ? null
      : Duration(
          seconds:
              max(0, recoverySeconds! - now.difference(syncedAt).inSeconds));

  factory DailyNote.parse(Game game, Map<String, dynamic> data, DateTime at) {
    String count(Object? current, Object? max) =>
        number(current) == null || number(max) == null
            ? '暂未提供'
            : '${number(current)} / ${number(max)}';
    bool complete(Object? current, Object? max) =>
        number(current) != null &&
        number(max) != null &&
        number(max)! > 0 &&
        number(current)! >= number(max)!;
    switch (game) {
      case Game.wutheringWaves:
      case Game.punishingGrayRaven:
        final energy = object(
            data[game == Game.wutheringWaves ? 'energyData' : 'actionData']);
        final activity = object(
            data[game == Game.wutheringWaves ? 'livenessData' : 'activeData']);
        final reserve = object(data['storeEnergyData']);
        final current = number(energy['cur']),
            capacity = number(energy['total']);
        int? recovery;
        if (game == Game.wutheringWaves &&
            current != null &&
            capacity != null &&
            capacity > 0) {
          if (current >= capacity) {
            recovery = 0;
          } else {
            final raw = number(energy['refreshTimeStamp']);
            // Kuro supplies the absolute time when waveplates are full, not a
            // duration. Accept Unix seconds or milliseconds, never small offsets.
            if (raw != null && raw >= 1000000000) {
              final epochMs = raw >= 100000000000 ? raw : raw * 1000;
              final remaining =
                  ((epochMs - at.millisecondsSinceEpoch) / 1000).ceil();
              // A past deadline with non-full energy indicates inconsistent
              // cached data; it must not be labelled as already full.
              if (remaining > 0) recovery = remaining;
            }
          }
        }
        return DailyNote(
            syncedAt: at,
            energy: current,
            capacity: capacity,
            recoverySeconds: recovery,
            metrics: [
              Metric('每日活跃', count(activity['cur'], activity['total']),
                  complete: complete(activity['cur'], activity['total'])),
              if (reserve.isNotEmpty)
                Metric('备用结晶波片', count(reserve['cur'], reserve['total']))
            ]);
      case Game.nevernessToEverness:
        return DailyNote(
            syncedAt: at,
            energy: number(data['staminaValue']),
            capacity: number(data['staminaMaxValue']),
            metrics: [
              Metric('都市活力',
                  count(data['citystaminaValue'], data['citystaminaMaxValue'])),
              Metric(
                  '今日活跃',
                  number(data['dayvalue']) == null
                      ? '暂未提供'
                      : '${number(data['dayvalue'])} / 100',
                  complete: (number(data['dayvalue']) ?? -1) >= 100)
            ]);
      case Game.towerOfFantasy:
        return DailyNote(
            syncedAt: at, metrics: const [Metric('日常数据', '此版本暂不支持')]);
      case Game.genshin:
        final expeditions =
            data['expeditions'] is List ? data['expeditions'] as List : null;
        return DailyNote(
            syncedAt: at,
            energy: number(data['current_resin']),
            capacity: number(data['max_resin']),
            recoverySeconds: number(data['resin_recovery_time']),
            metrics: [
              Metric('每日委托',
                  count(data['finished_task_num'], data['total_task_num']),
                  complete: complete(
                      data['finished_task_num'], data['total_task_num'])),
              Metric(
                  '探索派遣',
                  expeditions == null
                      ? '暂未提供'
                      : '${expeditions.where((item) => object(item)['status'] == 'Finished').length} 项已完成',
                  complete: expeditions != null &&
                      expeditions.isNotEmpty &&
                      expeditions.every(
                          (item) => object(item)['status'] == 'Finished'))
            ]);
      case Game.starRail:
        return DailyNote(
            syncedAt: at,
            energy: number(data['current_stamina']),
            capacity: number(data['max_stamina']),
            recoverySeconds: number(data['stamina_recover_time']),
            metrics: [
              Metric('每日实训',
                  count(data['current_train_score'], data['max_train_score']),
                  complete: complete(
                      data['current_train_score'], data['max_train_score'])),
              Metric('历战余响',
                  count(data['weekly_cocoon_cnt'], data['weekly_cocoon_limit']))
            ]);
      case Game.zenless:
        final energy = object(data['energy']);
        final progress = object(energy['progress']);
        final vitality = object(data['vitality']);
        final vhs = object(data['vhs_sale']);
        return DailyNote(
            syncedAt: at,
            energy: number(progress['current']),
            capacity: number(progress['max']),
            recoverySeconds: number(energy['restore']),
            metrics: [
              Metric('今日活跃', count(vitality['current'], vitality['max']),
                  complete: complete(vitality['current'], vitality['max'])),
              Metric('录像店经营', vhs['sale_state']?.toString() ?? '暂未提供')
            ]);
    }
  }
}

enum SignStatus {
  unknown,
  pending,
  signed,
  alreadySigned,
  verification,
  expired,
  failed
}

extension SignStatusInfo on SignStatus {
  bool get isDone =>
      this == SignStatus.signed || this == SignStatus.alreadySigned;
  String get label => switch (this) {
        SignStatus.unknown => '待查询',
        SignStatus.pending => '待签到',
        SignStatus.signed => '签到成功',
        SignStatus.alreadySigned => '今日已签',
        SignStatus.verification => '需要验证',
        SignStatus.expired => '请重新登录',
        SignStatus.failed => '暂未成功',
      };
}

class GameEntry {
  GameEntry(
      {required this.role,
      required this.accountId,
      this.note,
      this.signStatus = SignStatus.unknown,
      this.noteError,
      this.signError});
  final Role role;
  final String accountId;
  DailyNote? note;
  SignStatus signStatus;
  String? noteError, signError;
  bool noteNeedsVerification = false;
  String? get error {
    final errors = [noteError, signError].whereType<String>().toSet();
    return errors.isEmpty ? null : errors.join(' ');
  }

  String get key => '$accountId:${role.key}';
}

class RoutineTask {
  RoutineTask(
      {required this.id,
      required this.game,
      required this.title,
      this.done = false});
  final String id, title;
  final Game game;
  bool done;
  Map<String, dynamic> toJson() =>
      {'id': id, 'game': game.name, 'title': title, 'done': done};
  factory RoutineTask.fromJson(Map<String, dynamic> json) => RoutineTask(
      id: json['id'] as String,
      title: json['title'] as String,
      game: Game.values.byName(json['game'] as String),
      done: json['done'] == true);
}

class Activity {
  Activity(this.text, {required this.demo, this.success = true})
      : at = DateTime.now();
  final String text;
  final bool demo, success;
  final DateTime at;
}
