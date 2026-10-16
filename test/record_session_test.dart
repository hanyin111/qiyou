import 'package:flutter_test/flutter_test.dart';
import 'package:qiyou/data/record_browser_session.dart';
import 'package:qiyou/data/record_session_cookies.dart';
import 'package:qiyou/data/verification_diagnostics.dart';

void main() {
  test(
      'Browser bootstrap transfers only device cookies, never login credentials',
      () {
    final seeds = RecordBrowserSession.seedCookies(
        'account_id=1; cookie_token=secret; DEVICEFP=official-fp; _MHYUUID=official-device');
    expect(seeds, {'DEVICEFP': 'official-fp', '_MHYUUID': 'official-device'});
    final session = RecordBrowserSession.fromCookies(
        {...seeds, 'cookie_token': 'must-not-import', 'unrelated': 'analytics'},
        'Windows browser');
    expect(session, isNotNull);
    expect(session!.cookies, seeds);
    expect(
        RecordBrowserSession.fromCookies(
            {'DEVICEFP': '0000000000000000', '_MHYUUID': 'official-device'},
            'Windows browser'),
        isNull);
    expect(RecordBrowserSession.fromCookies(seeds, 'Windows\r\nHost: evil'),
        isNull);
  });
  test(
      'Temporary server cookies retain auth and stay scoped to account/device/host',
      () {
    final jar = RecordSessionCookies();
    final at = DateTime.utc(2026);
    jar.remember(
        'a',
        'device',
        'api.mihoyo.com',
        'acw_tc=sticky; Path=/, cookie_token=attacker; Path=/, aliyungf_tc=route; Path=/',
        at);
    const auth = 'account_id=1; cookie_token=original';
    expect(jar.header(auth, 'a', 'device', 'api.mihoyo.com', at),
        'account_id=1; cookie_token=original; acw_tc=sticky; aliyungf_tc=route');
    for (final scope in [
      ('other', 'device', 'api.mihoyo.com'),
      ('a', 'other', 'api.mihoyo.com'),
      ('a', 'device', 'other.mihoyo.com')
    ]) {
      expect(jar.header(auth, scope.$1, scope.$2, scope.$3, at), auth);
    }
    expect(
        jar.header(auth, 'a', 'device', 'api.mihoyo.com',
            at.add(const Duration(minutes: 10))),
        auth);
  });
  test('Official error details redact credentials, identifiers and long tokens',
      () {
    final safe = safeVerificationReason(
        'invalid request; token=short-secret; uid=123456789; proof=abcdefghijklmnopqrstuvwxyz123456; https://example.com/private',
        ['short-secret']);
    expect(safe, contains('invalid request'));
    for (final secret in [
      'short-secret',
      '123456789',
      'abcdefghijklmnopqrstuvwxyz123456',
      'https://example.com/private'
    ]) {
      expect(safe, isNot(contains(secret)));
    }
  });
}
