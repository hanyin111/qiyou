import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DeviceBridge {
  static const _channel = MethodChannel('app.qiyou/device');
  bool get supportsAccounts => !kIsWeb;
  Future<String?> read() async =>
      kIsWeb ? null : _channel.invokeMethod<String>('read');
  Future<void> write(String value) async {
    if (kIsWeb) {
      throw UnsupportedError('Browser preview does not accept credentials');
    }
    await _channel.invokeMethod<void>('write', value);
  }

  Future<void> delete() async {
    if (!kIsWeb) await _channel.invokeMethod<void>('delete');
  }
}
