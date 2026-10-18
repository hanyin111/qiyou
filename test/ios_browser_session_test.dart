import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qiyou/data/ios_browser_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.qiyou/browser-session');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('iOS cookie read binds and clears the exact private WebView nonce',
      () async {
    final scripts = <String>[];
    String? requestedNonce;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readCookies');
      requestedNonce = call.arguments['nonce'] as String;
      expect(requestedNonce, matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(call.arguments['urls'], ['https://user.mihoyo.com/']);
      expect(scripts.single, contains("value: '$requestedNonce'"));
      return {'account_id_v2': '7', 'cookie_token_v2': 'synthetic-private'};
    });
    final result = await readIosBrowserCookies(
        evaluate: (source) async {
          scripts.add(source);
          return source.contains('defineProperty') ? true : null;
        },
        urls: ['https://user.mihoyo.com/']);
    expect(result['cookie_token_v2'], 'synthetic-private');
    expect(scripts.last, contains('delete window.__qiyouSessionReadNonce'));
    expect(scripts.last, contains(requestedNonce!));
    expect(scripts.join(), isNot(contains('document.cookie')));
  });

  test('iOS does not fall back to another store when native reading fails',
      () async {
    var cleaned = false;
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'BROWSER_SESSION');
    });
    await expectLater(
        readIosBrowserCookies(
            evaluate: (source) async {
              if (source.contains('delete window')) cleaned = true;
              return true;
            },
            urls: ['https://user.mihoyo.com/']),
        throwsA(isA<PlatformException>()));
    expect(cleaned, isTrue);
  });

  test('iOS rejects an unbound page before accessing native cookies', () async {
    var nativeCalled = false;
    messenger.setMockMethodCallHandler(channel, (_) async {
      nativeCalled = true;
      return {};
    });
    await expectLater(
        readIosBrowserCookies(
            evaluate: (_) async => false, urls: ['https://user.mihoyo.com/']),
        throwsStateError);
    expect(nativeCalled, isFalse);
  });
}
