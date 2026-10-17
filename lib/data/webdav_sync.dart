import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'sync_crypto.dart';
import 'sync_models.dart';

class RemoteVault {
  const RemoteVault(this.snapshot, this.etag);
  final SyncSnapshot snapshot;
  final String? etag;
  bool get canOverwrite =>
      etag != null && RegExp(r'^"[^"\r\n]+"$').hasMatch(etag!);
  @override
  String toString() => 'RemoteVault(redacted)';
}

class WebDavSyncClient {
  WebDavSyncClient(this.connection,
      {http.Client? transport, this.crypto = const SyncCrypto()})
      : _transport = transport ?? http.Client();
  final SyncConnection connection;
  final http.Client _transport;
  final SyncCrypto crypto;

  void _checkPassword(String password) {
    validateSyncPassword(password);
    if (password == connection.password) {
      throw const SyncException('同步密码必须与 WebDAV 应用密码不同，避免服务端同时持有解密密码。');
    }
  }

  Future<http.Response> _request(String method,
      {bool folder = false,
      String? body,
      Map<String, String> headers = const {}}) async {
    try {
      return await (() async {
        final request =
            http.Request(method, folder ? connection.folder : connection.file)
              ..followRedirects = false
              ..maxRedirects = 0
              ..headers.addAll({
                'authorization':
                    'Basic ${base64Encode(utf8.encode('${connection.username}:${connection.password}'))}',
                'cache-control': 'no-cache, no-store',
                ...headers
              });
        if (body != null) request.body = body;
        final response = await _transport.send(request);
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw const SyncException('WebDAV 认证失败，请检查用户名、应用密码和目录权限。');
        }
        if (response.statusCode >= 300 && response.statusCode < 400) {
          throw const SyncException('WebDAV 地址发生重定向，已停止。请填写最终 HTTPS 文件夹地址。');
        }
        if (response.statusCode == 412) {
          throw const SyncException('云端已被另一台设备更新。请重新读取并预览，未覆盖云端数据。');
        }
        final bytes = <int>[];
        await for (final part in response.stream) {
          if (bytes.length + part.length > maxSyncFile) {
            throw const SyncException('云端响应过大，已停止读取。');
          }
          bytes.addAll(part);
        }
        return http.Response.bytes(bytes, response.statusCode,
            headers: response.headers);
      })()
          .timeout(const Duration(seconds: 30));
    } on SyncException {
      rethrow;
    } on TimeoutException {
      throw SyncException(method == 'PUT'
          ? '上传超时，结果尚未确认。请先重新读取云端，不要连续上传。'
          : 'WebDAV 请求超时，请检查网络。');
    } catch (_) {
      throw SyncException(method == 'PUT'
          ? '上传连接中断，结果尚未确认。请先重新读取云端。'
          : '无法连接 WebDAV，请检查地址、网络和证书。');
    }
  }

  Future<void> testConnection() async {
    final r = await _request('PROPFIND',
        folder: true,
        headers: {
          'depth': '0',
          'content-type': 'application/xml; charset=utf-8'
        },
        body:
            '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>');
    if (r.statusCode != 207) {
      throw SyncException('WebDAV 文件夹不可用（HTTP ${r.statusCode}）。请先在服务端建立文件夹。');
    }
  }

  Future<RemoteVault?> download(String password) async {
    _checkPassword(password);
    final r = await _request('GET');
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) {
      throw SyncException('读取云端失败（HTTP ${r.statusCode}）。');
    }
    return RemoteVault(await crypto.decrypt(utf8.decode(r.bodyBytes), password),
        r.headers['etag']);
  }

  Future<void> upload(SyncSnapshot snapshot, String password,
      {required RemoteVault? previous}) async {
    _checkPassword(password);
    if (previous != null && !previous.canOverwrite) {
      throw const SyncException('服务未提供强 ETag，无法安全覆盖已有备份；仍可下载。');
    }
    final body = await crypto.encrypt(snapshot, password);
    final r = await _request('PUT', body: body, headers: {
      'content-type': 'application/json; charset=utf-8',
      if (previous == null)
        'if-none-match': '*'
      else
        'if-match': previous.etag!,
    });
    if (!const {200, 201, 204}.contains(r.statusCode)) {
      throw SyncException('上传未确认（HTTP ${r.statusCode}），请先重新读取云端。');
    }
    // Confirm the saved content, rather than trusting an optimistic PUT result.
    final confirmed = await download(password);
    if (confirmed?.snapshot.revision != snapshot.revision) {
      throw const SyncException('上传后云端版本未能确认，请重新读取云端。');
    }
  }

  void close() => _transport.close();
}
