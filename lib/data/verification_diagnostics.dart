import 'verification_diagnostics_stub.dart'
    if (dart.library.io) 'verification_diagnostics_io.dart' as writer;

String safeVerificationReason(Object? message, Iterable<String> secrets) {
  if (message is! String) return '';
  var value = message.substring(0, message.length > 512 ? 512 : message.length);
  final values = secrets.where((s) => s.isNotEmpty).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final secret in values) {
    value = value.replaceAll(secret, '[已隐藏]');
  }
  value = value
      .replaceAll(RegExp(r'https?://\S+'), '[链接已隐藏]')
      .replaceAll(RegExp(r'[a-zA-Z0-9_+/=-]{24,}'), '[已隐藏]')
      .replaceAll(RegExp(r'\d{6,}'), '[已隐藏]')
      .replaceAll(RegExp(r'[\x00-\x1f]'), ' ')
      .trim();
  return value.substring(0, value.length > 160 ? 160 : value.length);
}

Future<void> writeVerificationDiagnostic(Map<String, Object?> data) =>
    writer.writeVerificationDiagnostic(data);
