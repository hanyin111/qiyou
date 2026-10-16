import '../domain/models.dart';

// Short-lived CAPTCHA data only. Account cookies never enter the CAPTCHA view.
class RecordVerification {
  const RecordVerification(
      {required this.gt,
      required this.challenge,
      required this.accountId,
      required this.deviceId,
      required this.roleKey,
      required this.issuedAt,
      this.requestPath = '',
      this.traceId = '',
      this.newCaptcha = true});
  final String gt, challenge, accountId, deviceId, roleKey;
  final String requestPath, traceId;
  final DateTime issuedAt;
  final bool newCaptcha;

  static bool validToken(Object? value) =>
      value is String && RegExp(r'^[a-zA-Z0-9_-]{1,1024}$').hasMatch(value);

  static bool validPass(Object? value) =>
      value is String &&
      RegExp(r'^[a-zA-Z0-9._~+/=-]{1,2048}$').hasMatch(value);

  static bool validTrace(Object? value) =>
      value is String && RegExp(r'^[a-zA-Z0-9._:-]{1,256}$').hasMatch(value);

  bool matches(Account account, Role role, DateTime now) =>
      accountId == account.id &&
      deviceId == account.deviceId &&
      roleKey == role.key &&
      !now.isBefore(issuedAt) &&
      now.difference(issuedAt) < const Duration(minutes: 5);
}

class RecordVerificationProof {
  const RecordVerificationProof(this.challenge, this.validate, this.seccode);
  final String challenge, validate, seccode;

  static RecordVerificationProof? fromData(Object? value) {
    final data = object(value);
    final challenge = data['geetest_challenge'];
    final validate = data['geetest_validate'];
    final seccode = data['geetest_seccode'];
    if (!RecordVerification.validToken(challenge) ||
        !RecordVerification.validToken(validate) ||
        seccode != '$validate|jordan') {
      return null;
    }
    return RecordVerificationProof(
        challenge as String, validate as String, seccode as String);
  }

  Map<String, String> toJson() => {
        'geetest_challenge': challenge,
        'geetest_validate': validate,
        'geetest_seccode': seccode
      };
}
