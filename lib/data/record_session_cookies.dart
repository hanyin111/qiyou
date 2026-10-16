// Only short-lived infrastructure cookies; no auth cookie can be replaced.
class RecordSessionCookies {
  final _sessions = <String, Map<String, ({String value, DateTime expires})>>{};
  String _key(String accountId, String deviceId, String host) =>
      '$accountId:$deviceId:$host';

  void remember(String accountId, String deviceId, String host,
      String? setCookie, DateTime now) {
    if (setCookie == null || setCookie.length > 16000) return;
    final session =
        _sessions.putIfAbsent(_key(accountId, deviceId, host), () => {});
    for (final match in RegExp(r'(?:^|,)\s*(aliyungf_tc|acw_tc)=([^;,\s]*)')
        .allMatches(setCookie)) {
      final name = match[1]!;
      final value = match[2]!;
      if (value.isEmpty) {
        session.remove(name);
      } else if (value.length <= 2048 &&
          !RegExp(r'[\r\n\x00]').hasMatch(value)) {
        session[name] =
            (value: value, expires: now.add(const Duration(minutes: 10)));
      }
    }
  }

  String header(String original, String accountId, String deviceId, String host,
      DateTime now) {
    final session = _sessions[_key(accountId, deviceId, host)];
    if (session == null) return original;
    session.removeWhere((_, cookie) => !now.isBefore(cookie.expires));
    if (session.isEmpty) return original;
    final kept = original
        .split(';')
        .where((pair) => !session.containsKey(pair.split('=').first.trim()));
    return [
      ...kept.map((p) => p.trim()).where((p) => p.isNotEmpty),
      ...session.entries.map((e) => '${e.key}=${e.value.value}')
    ].join('; ');
  }
}
