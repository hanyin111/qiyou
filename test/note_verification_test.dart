import 'package:flutter_test/flutter_test.dart';
import 'package:qiyou/data/record_verification.dart';
import 'package:qiyou/ui/note_verification.dart';

void main() {
  test(
      'CAPTCHA page contains only a challenge and official SDK, no account context',
      () {
    final html = noteVerificationHtml(
        RecordVerification(
            gt: 'public-gt',
            challenge: 'public-challenge',
            accountId: 'must-not-enter-webview',
            deviceId: 'private-device',
            roleKey: 'private-role',
            issuedAt: DateTime.utc(2026)),
        'nonce');
    expect(html, contains('https://static.geetest.com/static/tools/gt.js'));
    expect(html, contains('"offline":false'));
    expect(html, contains('form-action \'none\''));
    for (final secret in [
      'must-not-enter-webview',
      'private-device',
      'private-role',
      'cookie_token'
    ]) {
      expect(html, isNot(contains(secret)));
    }
  });
  test('Malformed CAPTCHA messages cannot become request headers', () {
    expect(
        RecordVerificationProof.fromData({
          'geetest_challenge': 'challenge\r\nHost: evil',
          'geetest_validate': 'proof',
          'geetest_seccode': 'proof|jordan'
        }),
        isNull);
    expect(
        RecordVerificationProof.fromData({
          'geetest_challenge': 'challenge',
          'geetest_validate': 'proof',
          'geetest_seccode': 'false'
        }),
        isNull);
  });
}
