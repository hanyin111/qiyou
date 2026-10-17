import 'dart:convert';
import 'dart:io';

// Developer-launched local test only. No auth values, raw payloads or uploads.
Future<void> writeVerificationDiagnostic(Map<String, Object?> data,
    {String environmentKey = 'QIYOU_VERIFICATION_REPORT'}) async {
  final path = Platform.environment[environmentKey];
  if (path == null || path.isEmpty) return;
  try {
    await File(path).writeAsString(jsonEncode(data), flush: true);
  } catch (_) {
    // Diagnostics must not change the result of the official request.
  }
}
