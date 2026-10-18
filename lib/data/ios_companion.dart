import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';

class IosCompanionBridge {
  static const channel = MethodChannel('app.qiyou/companion');
  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  Future<String> permission({bool request = false}) async =>
      await channel
          .invokeMethod<String>(request ? 'requestPermission' : 'permission') ??
      'unknown';
  Future<void> openSettings() => channel.invokeMethod<void>('openSettings');
  Future<bool> publish(Map<String, dynamic> payload) async =>
      await channel.invokeMethod<bool>('publish', jsonEncode(payload)) ?? false;
}

// Only display data crosses into the App Group. No UID, nickname, account ID,
// Cookie, token, device header or sync password is included in the widget file.
Map<String, dynamic> companionPayload(
    {required List<GameEntry> entries,
    required Set<Game> selected,
    required String signDay,
    required bool connected,
    required bool remindersEnabled,
    required DateTime now}) {
  const maxAge = Duration(hours: 6);
  bool fresh(GameEntry e) =>
      e.noteError == null &&
      e.note != null &&
      !e.note!.syncedAt.isAfter(now.add(const Duration(minutes: 5))) &&
      now.difference(e.note!.syncedAt) < maxAge;
  bool valid(GameEntry e) =>
      fresh(e) &&
      e.note!.energy != null &&
      e.note!.energy! >= 0 &&
      e.note!.capacity != null &&
      e.note!.capacity! > 0;
  DateTime? deadline(GameEntry e) {
    if (!valid(e)) return null;
    if (e.note!.energy! >= e.note!.capacity!) return now;
    final seconds = e.note!.recoverySeconds;
    if (seconds == null || seconds <= 0 || seconds > 7 * 86400) return null;
    return e.note!.syncedAt.add(Duration(seconds: seconds));
  }

  final games = <Map<String, dynamic>>[];
  final active = connected
      ? {for (final e in entries) e.key: e}.values.toList()
      : <GameEntry>[];
  for (final game in Game.values.where(selected.contains)) {
    final rows = active.where((e) => e.role.game == game).toList();
    if (rows.isEmpty) continue;
    final complete = rows.every(valid);
    final signed = signDay == chinaDay(now)
        ? rows.where((e) => e.signStatus.isDone && e.signError == null).length
        : 0;
    final attention = rows.any((e) =>
        e.signError != null ||
        const {SignStatus.failed, SignStatus.expired, SignStatus.verification}
            .contains(e.signStatus));
    final knownSign = signDay == chinaDay(now) &&
        rows.every((e) => e.signStatus != SignStatus.unknown);
    final dates = rows.map(deadline).toList();
    games.add({
      'game': game.name,
      'roleCount': rows.length,
      'signedRoles': signed,
      'sign': attention
          ? 'attention'
          : !knownSign
              ? 'unknown'
              : signed == rows.length
                  ? 'signed'
                  : signed == 0
                      ? 'pending'
                      : 'partial',
      'energy':
          complete ? rows.fold<int>(0, (n, e) => n + e.note!.energy!) : null,
      'capacity':
          complete ? rows.fold<int>(0, (n, e) => n + e.note!.capacity!) : null,
      'syncedAt': complete
          ? rows
              .map((e) => e.note!.syncedAt.millisecondsSinceEpoch)
              .reduce((a, b) => a < b ? a : b)
          : null,
      'fullAt': complete && dates.every((d) => d != null)
          ? dates
              .whereType<DateTime>()
              .reduce((a, b) => a.isAfter(b) ? a : b)
              .millisecondsSinceEpoch
          : null,
    });
  }
  final reminders = <Map<String, dynamic>>[];
  if (remindersEnabled) {
    for (final e in active) {
      final at = deadline(e);
      if (at == null ||
          !at.isAfter(now) ||
          e.note!.energy! >= e.note!.capacity!) {
        continue;
      }
      reminders.add({
        'id':
            'qiyou.energy.${sha256.convert(utf8.encode(e.key)).toString().substring(0, 24)}',
        'game': e.role.game.name,
        'fullAt': at.millisecondsSinceEpoch,
      });
    }
    reminders
        .sort((a, b) => (a['fullAt'] as int).compareTo(b['fullAt'] as int));
  }
  return {
    'snapshot': {
      'version': 1,
      'updatedAt': now.millisecondsSinceEpoch,
      'signDay': signDay,
      'connected': connected,
      'games': games
    },
    'remindersEnabled': remindersEnabled,
    'reminders': reminders.take(60).toList(),
  };
}
