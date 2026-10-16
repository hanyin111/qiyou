// Local read-only diagnostic. Account values remain inside this native process.
// Never prints raw responses, credentials, account IDs, role IDs or device IDs.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:qiyou/data/device_bridge.dart';
import 'package:qiyou/data/taygedo_client.dart';
import 'package:qiyou/domain/models.dart';

final report = <String, Object?>{
  'performs_sign_in': false,
  'modifies_account_store': false
};
final client = http.Client();

Future<Map<String, dynamic>> read(
    String label, String host, String path, Map<String, String> headers,
    {Map<String, String>? form, Map<String, String>? query}) async {
  try {
    final response = await (() async {
      final request = http.Request(
          form == null ? 'GET' : 'POST', Uri.https(host, path, query))
        ..followRedirects = false
        ..headers.addAll(headers);
      if (form != null) request.bodyFields = form;
      final stream = await client.send(request);
      final bytes = <int>[];
      await for (final chunk in stream.stream) {
        if (bytes.length + chunk.length > 2 * 1024 * 1024) {
          throw const FormatException();
        }
        bytes.addAll(chunk);
      }
      Map<String, dynamic> payload = {};
      try {
        payload = object(jsonDecode(utf8.decode(bytes)));
      } catch (_) {}
      report[label] = {
        'http': stream.statusCode,
        'code': number(payload['code']),
        'access_token_present':
            object(payload['data'])['accessToken'] is String,
        'pixel_stamina_present':
            object(payload['data'])['staminaValue'] != null,
        'sign_state_present': object(payload['data'])['todaySign'] is bool,
      };
      return payload;
    })()
        .timeout(const Duration(seconds: 15));
    return response;
  } catch (_) {
    report[label] = {'request_failed': true};
    return {};
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final saved = await DeviceBridge().read();
    final accounts =
        (object(jsonDecode(saved ?? '{}'))['accounts'] as List? ?? [])
            .map((raw) => Account.fromJson(object(raw)))
            .toList();
    final kuro =
        accounts.where((a) => a.community == Community.kuro).firstOrNull;
    final role =
        kuro?.roles.where((r) => r.game == Game.wutheringWaves).firstOrNull;
    if (kuro != null && role != null) {
      final headers = <String, String>{
        'token': kuro.cookie,
        'did': kuro.deviceId,
        'devcode': kuro.recordHeaders['devcode'] ?? kuro.deviceId,
        'source': 'h5',
        'version': '3.1.3',
        if (kuro.recordHeaders['user-agent'] case final String ua)
          'user-agent': ua
      };
      final form = {'roleId': role.uid, 'serverId': role.region};
      await read('kuro_web_protocol', 'api.kurobbs.com',
          '/aki/roleBox/requestToken', headers,
          form: form);
      final result = await read(
          'kuro_native_protocol',
          'api.kurobbs.com',
          '/aki/roleBox/requestToken',
          {...headers, 'source': 'android', 'b-at': ''},
          form: form);
      final token = object(result['data'])['accessToken'];
      if (token is String && token.isNotEmpty) {
        await read(
            'kuro_widget',
            'api.kurobbs.com',
            '/gamer/widget/game3/getData',
            {...headers, 'source': 'android', 'b-at': token},
            form: {...form, 'gameId': '3', 'type': '2', 'sizeType': '1'});
      }
    }
    final tjd =
        accounts.where((a) => a.community == Community.taygedo).firstOrNull;
    final nte =
        tjd?.roles.where((r) => r.game == Game.nevernessToEverness).firstOrNull;
    if (tjd != null && nte != null) {
      final headers = <String, String>{
        if (tjd.recordHeaders['auth-type'] == 'cookie')
          'cookie': tjd.cookie
        else
          'authorization': tjd.cookie,
        if (tjd.recordHeaders['authorization'] case final String token)
          'authorization': token,
        if (tjd.recordHeaders['user-agent'] case final String ua)
          'user-agent': ua,
        'origin': 'https://www.tajiduo.com',
        'referer': 'https://www.tajiduo.com/bbs/',
      };
      final native = <String, String>{
        ...headers,
        'appversion': TaygedoClient.appVersion,
        'platform': 'android',
        'uid': tjd.id.replaceFirst('taygedo:', ''),
        'deviceid': tjd.deviceId,
        'ds': TaygedoClient.signature(
            DateTime.now().millisecondsSinceEpoch ~/ 1000, 'probe123'),
      };
      report['tjd_cookie_auth'] = tjd.recordHeaders['auth-type'] == 'cookie';
      // Names are protocol metadata, never Cookie values.
      if (tjd.recordHeaders['auth-type'] == 'cookie') {
        report['tjd_cookie_names'] = tjd.cookie
            .split(';')
            .map((s) => s.split('=').first.trim())
            .where((s) => RegExp(r'^[A-Za-z0-9_.-]{1,60}$').hasMatch(s))
            .toList();
      }
      await read('tjd_cookie_game', 'bbs-api.tajiduo.com',
          '/apihub/awapi/yh/roleHome', headers,
          query: {'roleId': nte.uid});
      await read('tjd_signed_game', 'bbs-api.tajiduo.com',
          '/apihub/awapi/yh/roleHome', native,
          query: {'roleId': nte.uid});
      final webToken = tjd.cookie
          .split(';')
          .where((s) => s.trim().startsWith('tjd_token='))
          .firstOrNull;
      if (webToken != null) {
        final raw = webToken.trim().substring('tjd_token='.length);
        final token = Uri.decodeComponent(raw);
        await read('tjd_cookie_token_game', 'bbs-api.tajiduo.com',
            '/apihub/awapi/yh/roleHome', {...native, 'authorization': token},
            query: {'roleId': nte.uid});
        await read('tjd_cookie_token_sign_state', 'bbs-api.tajiduo.com',
            '/apihub/awapi/signin/state', {...native, 'authorization': token},
            query: {'gameId': nte.game.communityGameId});
      }
      final login = await read('tjd_web_session', 'bbs-api.tajiduo.com',
          '/usercenter/wapi/login', headers);
      final access = object(login['data'])['accessToken'];
      if (access is String && access.isNotEmpty) {
        await read('tjd_exchanged_game', 'bbs-api.tajiduo.com',
            '/apihub/awapi/yh/roleHome', {...native, 'authorization': access},
            query: {'roleId': nte.uid});
      }
    }
  } catch (_) {
    report['probe_failed'] = true;
  } finally {
    client.close();
    final path = Platform.environment['QIYOU_API_PROBE_REPORT'];
    if (path != null) await File(path).writeAsString(jsonEncode(report));
  }
  exit(0);
}
