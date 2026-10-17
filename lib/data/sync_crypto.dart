import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'sync_models.dart';

const maxSyncPlaintext = 480000;
const maxSyncFile = 700000;
const _aad = 'app.qiyou/sync/v1;scrypt=32768,8,1;AES-256-GCM';

void validateSyncPassword(String password) {
  if (password.runes.length < 12 || password.length > 256) {
    throw const SyncException('同步密码需至少 12 个字符，最多 256 个字符。');
  }
}

class SyncCrypto {
  const SyncCrypto();
  Future<String> encrypt(SyncSnapshot snapshot, String password) async {
    validateSyncPassword(password);
    return compute(
        _seal, {'value': jsonEncode(snapshot.toJson()), 'password': password});
  }

  Future<SyncSnapshot> decrypt(String file, String password) async {
    validateSyncPassword(password);
    if (file.length > maxSyncFile) throw const SyncException('云端文件过大，已停止读取。');
    final plain = await compute(_open, {'value': file, 'password': password});
    try {
      return SyncSnapshot.fromJson(
          Map<String, dynamic>.from(jsonDecode(plain) as Map));
    } on SyncException {
      rethrow;
    } catch (_) {
      throw const SyncException('云端数据格式不受支持，未更改本机账号。');
    }
  }
}

Uint8List _random(int size) => Uint8List.fromList(
    List.generate(size, (_) => Random.secure().nextInt(256)));

Uint8List _key(String password, Uint8List salt) {
  final bytes = Uint8List.fromList(utf8.encode(password));
  try {
    final kdf = Scrypt()..init(ScryptParameters(32768, 8, 1, 32, salt));
    return kdf.process(bytes);
  } finally {
    bytes.fillRange(0, bytes.length, 0);
  }
}

String _seal(Map<String, String> input) {
  final plain = Uint8List.fromList(utf8.encode(input['value']!));
  if (plain.length > maxSyncPlaintext) {
    throw const SyncException('账号数据过大，暂时无法同步。');
  }
  final salt = _random(16), nonce = _random(12);
  final key = _key(input['password']!, salt);
  try {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
          true,
          AEADParameters(KeyParameter(key), 128, nonce,
              Uint8List.fromList(utf8.encode(_aad))));
    return jsonEncode({
      'format': 'qiyou-encrypted-vault',
      'version': 1,
      'kdf': 'scrypt',
      'n': 32768,
      'r': 8,
      'p': 1,
      'cipher': 'AES-256-GCM',
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(cipher.process(plain))
    });
  } finally {
    key.fillRange(0, key.length, 0);
    plain.fillRange(0, plain.length, 0);
  }
}

String _open(Map<String, String> input) {
  Uint8List? key, plain;
  try {
    final e = Map<String, dynamic>.from(jsonDecode(input['value']!) as Map);
    // Reject unsupported cost parameters before deriving a key. A remote file
    // cannot request arbitrary memory/CPU work or downgrade the cipher.
    if (e['format'] != 'qiyou-encrypted-vault' ||
        e['version'] != 1 ||
        e['kdf'] != 'scrypt' ||
        e['n'] != 32768 ||
        e['r'] != 8 ||
        e['p'] != 1 ||
        e['cipher'] != 'AES-256-GCM') {
      throw const SyncException('云端加密格式不受支持，请使用兼容版本。');
    }
    final salt = base64Decode(e['salt'] as String);
    final nonce = base64Decode(e['nonce'] as String);
    final ciphertext = base64Decode(e['ciphertext'] as String);
    if (salt.length != 16 ||
        nonce.length != 12 ||
        ciphertext.length < 16 ||
        ciphertext.length > maxSyncPlaintext + 16) {
      throw const FormatException();
    }
    key = _key(input['password']!, salt);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
          false,
          AEADParameters(KeyParameter(key), 128, nonce,
              Uint8List.fromList(utf8.encode(_aad))));
    plain = cipher.process(ciphertext);
    return utf8.decode(plain);
  } on SyncException {
    rethrow;
  } catch (_) {
    throw const SyncException('同步密码不正确，或云端文件已损坏；未更改本机数据。');
  } finally {
    key?.fillRange(0, key.length, 0);
    plain?.fillRange(0, plain.length, 0);
  }
}
