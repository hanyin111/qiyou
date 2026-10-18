import 'dart:convert';
import 'dart:io';
import 'package:qiyou/data/community_sms_login.dart';
import 'package:qiyou/data/login_captcha_document.dart';

// Export the production documents for real WebKit integration tests. No account,
// phone number, OTP, proof, or session is included in these public fixtures.
void main(List<String> args) {
  final target = File(args.isEmpty
      ? 'ios/WidgetPreviewHost/CaptchaFixtures.json'
      : args.single);
  target.parent.createSync(recursive: true);
  target.writeAsStringSync(jsonEncode({
    'v4': loginCaptchaHtml(
        const LoginChallenge(id: 'ec4aa4174277d822d73f2442a165a2cd'),
        'synthetic-nonce'),
    'v3': loginCaptchaHtml(
        const LoginChallenge(
            id: 'synthetic-gt', challenge: 'synthetic-challenge'),
        'synthetic-nonce')
  }));
}
