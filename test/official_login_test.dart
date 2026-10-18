import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:qiyou/ui/official_login.dart';

void main() {
  test('iOS login requests desktop pages while retaining an isolated session',
      () {
    final settings = officialLoginSettings(platform: TargetPlatform.iOS);
    expect(settings.incognito, isTrue);
    expect(settings.userAgent, officialDesktopUserAgent);
    expect(settings.userAgent, isNot(contains('Mobile')));
    expect(settings.userAgent, isNot(contains('iPhone')));
    expect(settings.preferredContentMode, UserPreferredContentMode.DESKTOP);
    expect(settings.allowFileAccess, isFalse);
    expect(settings.supportMultipleWindows, isFalse);
  });
  test('Android and Windows retain their existing browser identity', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
      final settings = officialLoginSettings(platform: platform);
      expect(settings.userAgent, isNull);
      expect(settings.incognito, isTrue);
      expect(
          settings.preferredContentMode, UserPreferredContentMode.RECOMMENDED);
    }
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
