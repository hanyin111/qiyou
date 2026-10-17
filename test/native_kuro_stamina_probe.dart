// Explicit local diagnostic entrypoint, excluded from the production entrypoint.
// Reads only Kuro accounts through the app's OS vault; never writes that vault,
// requests SMS, logs in, or signs in. Reports contain stamina values, not IDs.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:qiyou/data/community_http.dart';
import 'package:qiyou/data/device_bridge.dart';
import 'package:qiyou/data/miyoushe_client.dart';
import 'package:qiyou/domain/models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _Probe()));
}

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final destination = Platform.environment['QIYOU_STAMINA_REPORT'];
    if (destination == null) {
      exit(0);
    }
    final report = <String, dynamic>{
      'version': '0.1.10',
      'credential_values_recorded': false,
      'vault_write': false,
      'sign_requests': false
    };
    final results = <Map<String, dynamic>>[];
    try {
      final saved = await DeviceBridge().read();
      final accounts =
          (object(saved == null ? null : jsonDecode(saved))['accounts']
                      as List? ??
                  [])
              .map((a) => Account.fromJson(object(a)))
              .where((a) => a.community == Community.kuro);
      for (final account in accounts) {
        for (final role in account.activeRoles
            .where((r) => r.game == Game.wutheringWaves)) {
          final api = CommunityHttp(Community.kuro, 'api.kurobbs.com');
          var stage = 'data-token';
          final result = <String, dynamic>{};
          try {
            final headers = {
              'token': account.cookie,
              'source': 'android',
              'version': '3.1.3',
              'origin': 'https://www.kurobbs.com',
              'referer': 'https://www.kurobbs.com/',
              'did': account.deviceId,
              'devcode': account.recordHeaders['devcode'] ?? account.deviceId,
              if (account.recordHeaders['user-agent'] != null)
                'user-agent': account.recordHeaders['user-agent']!
            };
            final auth = object(await api.request(
                '/aki/roleBox/requestToken', headers,
                form: {'roleId': role.uid, 'serverId': role.region},
                acceptedCodes: const {0, 200}));
            final access = auth['accessToken'];
            if (access is! String || access.isEmpty) {
              throw StateError('Missing data token');
            }
            headers['b-at'] = access;
            final form = {
              'gameId': '3',
              'roleId': role.uid,
              'serverId': role.region
            };
            stage = 'widget-before-refresh';
            final before = object(await api.request(
                '/gamer/widget/game3/getData', headers,
                form: {...form, 'type': '2', 'sizeType': '1'},
                acceptedCodes: const {0, 200}));
            result['before_energy'] =
                number(object(before['energyData'])['cur']);
            stage = 'refresh-data';
            await api.request('/aki/roleBox/akiBox/refreshData', headers,
                form: form, acceptedCodes: const {0, 200});
            stage = 'widget-after-refresh';
            final after = object(await api.request(
                '/gamer/widget/game3/getData', headers,
                form: {...form, 'type': '2', 'sizeType': '1'},
                acceptedCodes: const {0, 200}));
            final note =
                DailyNote.parse(Game.wutheringWaves, after, DateTime.now());
            result.addAll({
              'after_energy': note.energy,
              'capacity': note.capacity,
              'recovery_seconds': note.recoverySeconds,
              'recovery_timestamp':
                  number(object(after['energyData'])['refreshTimeStamp']),
              'role_matches': after['roleId'] == null ||
                  after['roleId'].toString() == role.uid,
              'server_matches': after['serverId'] == null ||
                  after['serverId'].toString() == role.region,
              'passed': note.energy != null && note.capacity != null
            });
          } on MiyousheException catch (e) {
            result.addAll({
              'passed': false,
              'stage': stage,
              'code': e.code,
              'kind': e.kind.name
            });
          } catch (_) {
            result.addAll({'passed': false, 'stage': stage});
          } finally {
            api.close();
          }
          results.add(result);
        }
      }
      report['roles'] = results;
    } catch (_) {
      report['vault_read_failed'] = true;
    }
    await File(destination)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    exit(0);
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('正在核对鸣潮体力数据…')));
}
