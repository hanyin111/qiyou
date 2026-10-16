import 'package:flutter_test/flutter_test.dart';
import 'package:qiyou/ui/official_login.dart';
import 'package:qiyou/ui/official_record.dart';
import 'package:qiyou/domain/models.dart';

void main() {
  test('Official note import must match endpoint, selected UID and server', () {
    const role = Role(
        game: Game.zenless,
        uid: '1',
        region: 'prod_gf_cn',
        nickname: 'Test',
        serverName: 'Test');
    const base =
        'https://api-takumi-record.mihoyo.com/event/game_record_zzz/api/zzz/note';
    expect(
        matchesOfficialNote(
            Uri.parse('$base?role_id=1&server=prod_gf_cn'), role),
        isTrue);
    expect(
        matchesOfficialNote(
            Uri.parse('$base?role_id=2&server=prod_gf_cn'), role),
        isFalse);
    expect(matchesOfficialNote(Uri.parse('$base?role_id=1&server=other'), role),
        isFalse);
    expect(
        matchesOfficialNote(
            Uri.parse(
                'https://evil.example/event/game_record_zzz/api/zzz/note?role_id=1&server=prod_gf_cn'),
            role),
        isFalse);
  });
  test('Login navigation permits only HTTPS official domains', () {
    for (final value in [
      'https://user.mihoyo.com/',
      'https://m.miyoushe.com/ys/'
    ]) {
      expect(isOfficialLoginUrl(Uri.parse(value)), isTrue);
    }
    for (final value in [
      'http://user.mihoyo.com/',
      'https://mihoyo.com.evil.example/',
      'https://evil-mihoyo.com/',
      'file:///C:/local.html',
      'javascript:alert(1)'
    ]) {
      expect(isOfficialLoginUrl(Uri.parse(value)), isFalse);
    }
  });
}
