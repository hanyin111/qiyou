import 'package:flutter_test/flutter_test.dart';
import 'package:qiyou/ui/official_login.dart';

void main() {
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
