import 'dart:math';

enum Game { genshin, starRail, zenless }

extension GameInfo on Game {
  String get title => switch (this) {
        Game.genshin => '原神',
        Game.starRail => '崩坏：星穹铁道',
        Game.zenless => '绝区零',
      };
  String get shortTitle => switch (this) {
        Game.genshin => '原神',
        Game.starRail => '星穹铁道',
        Game.zenless => '绝区零',
      };
  String get english => switch (this) {
        Game.genshin => 'GENSHIN IMPACT',
        Game.starRail => 'HONKAI: STAR RAIL',
        Game.zenless => 'ZENLESS ZONE ZERO',
      };
  String get biz => switch (this) {
        Game.genshin => 'hk4e_cn',
        Game.starRail => 'hkrpg_cn',
        Game.zenless => 'nap_cn',
      };
  String get resource => switch (this) {
        Game.genshin => '原粹树脂',
        Game.starRail => '开拓力',
        Game.zenless => '电量',
      };
  String get activityId => switch (this) {
        Game.genshin => 'e202311201442471',
        Game.starRail => 'e202304121516551',
        Game.zenless => 'e202406242138391',
      };
  String get signGame => switch (this) {
        Game.genshin => 'hk4e',
        Game.starRail => 'hkrpg',
        Game.zenless => 'zzz',
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
      required this.roles});
  final String id, cookie, deviceId;
  final List<Role> roles;
  String get title => roles.isEmpty ? '米游社账号' : roles.first.nickname;
  Map<String, dynamic> toJson() => {
        'id': id,
        'cookie': cookie,
        'deviceId': deviceId,
        'roles': roles.map((role) => role.toJson()).toList()
      };
  factory Account.fromJson(Map<String, dynamic> json) => Account(
      id: json['id'] as String,
      cookie: json['cookie'] as String,
      deviceId: json['deviceId'] as String,
      roles: (json['roles'] as List)
          .map((value) => Role.fromJson(object(value)))
          .toList());
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
      this.error});
  final Role role;
  final String accountId;
  DailyNote? note;
  SignStatus signStatus;
  String? error;
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
