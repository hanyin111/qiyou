import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../app_state.dart';
import '../data/miyoushe_client.dart';
import '../domain/models.dart';
import 'official_login.dart';

Uri officialRecordUrl(Role role) => role.game == Game.zenless
    ? Uri.https('act.mihoyo.com', '/app/mihoyo-zzz-game-record/m.html',
        {'game_id': '8'})
    : Uri.https('webstatic.mihoyo.com', '/app/community-game-records/',
        {'game_id': role.game == Game.genshin ? '2' : '6'});

bool matchesOfficialNote(Uri? url, Role role) {
  if (url == null ||
      url.scheme != 'https' ||
      url.host != 'api-takumi-record.mihoyo.com' ||
      url.queryParameters['role_id'] != role.uid ||
      url.queryParameters['server'] != role.region) {
    return false;
  }
  return url.path ==
      switch (role.game) {
        Game.genshin => '/game_record/app/genshin/api/dailyNote',
        Game.starRail => '/game_record/app/hkrpg/api/note',
        Game.zenless => '/event/game_record_zzz/api/zzz/note',
      };
}

Future<void> openOfficialRecord(
    BuildContext context, AppState state, GameEntry entry) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => OfficialRecordPage(state, entry)));
}

class OfficialRecordPage extends StatefulWidget {
  const OfficialRecordPage(this.state, this.entry, {super.key});
  final AppState state;
  final GameEntry entry;
  @override
  State<OfficialRecordPage> createState() => _OfficialRecordPageState();
}

class _OfficialRecordPageState extends State<OfficialRecordPage> {
  String message = '在官方工具中打开实时便笺，按页面提示完成验证。';
  bool syncing = false;
  bool received = false;
  final requestHeaders = <String, Map<String, String>>{};
  final noteRequests = <String>{};

  Map<String, dynamic> eventData(dynamic value) =>
      object(value is String ? jsonDecode(value) : value);

  Future<void> initialize(InAppWebViewController controller) async {
    try {
      final account = widget.state.accounts
          .firstWhere((a) => a.id == widget.entry.accountId);
      final cookies = MiyousheClient.parseCookie(account.cookie);
      if (defaultTargetPlatform == TargetPlatform.windows) {
        await controller.callDevToolsProtocolMethod(
            methodName: 'Network.enable');
        await controller.callDevToolsProtocolMethod(
            methodName: 'Network.setCookies',
            parameters: {
              'cookies': [
                for (final domain in ['.mihoyo.com', '.miyoushe.com'])
                  for (final cookie in cookies.entries)
                    {
                      'name': cookie.key,
                      'value': cookie.value,
                      'domain': domain,
                      'path': '/',
                      'secure': true,
                      'httpOnly': true
                    }
              ]
            });
        await controller.addDevToolsProtocolEventListener(
            eventName: 'Network.requestWillBeSent',
            callback: (event) {
              final data = eventData(event);
              final request = object(data['request']);
              if (!matchesOfficialNote(
                  Uri.tryParse('${request['url']}'), widget.entry.role)) {
                return;
              }
              requestHeaders['${data['requestId']}'] =
                  object(request['headers'])
                      .map((key, value) => MapEntry(key, '$value'));
            });
        await controller.addDevToolsProtocolEventListener(
            eventName: 'Network.responseReceived',
            callback: (event) {
              final data = eventData(event);
              final response = object(data['response']);
              if (matchesOfficialNote(
                  Uri.tryParse('${response['url']}'), widget.entry.role)) {
                noteRequests.add('${data['requestId']}');
              }
            });
        await controller.addDevToolsProtocolEventListener(
            eventName: 'Network.loadingFinished',
            callback: (event) async {
              final id = '${eventData(event)['requestId']}';
              if (!noteRequests.remove(id) || syncing || !mounted) return;
              syncing = true;
              try {
                final result = object(await controller
                    .callDevToolsProtocolMethod(
                        methodName: 'Network.getResponseBody',
                        parameters: {'requestId': id}));
                final raw = result['body'];
                if (raw is! String || raw.length > 2000000) return;
                final body = object(jsonDecode(result['base64Encoded'] == true
                    ? utf8.decode(base64Decode(raw))
                    : raw));
                if (number(body['retcode']) != 0) {
                  if (mounted) {
                    setState(() => message = '官方便笺仍要求验证，请按官方页面提示操作。');
                  }
                  return;
                }
                await widget.state.acceptOfficialNote(widget.entry,
                    object(body['data']), requestHeaders[id] ?? {});
                received = true;
                if (mounted) setState(() => message = '便笺已同步，可以返回游戏页。');
              } catch (_) {
                if (mounted) {
                  setState(() => message = '未能同步便笺，请在官方页面重新打开实时便笺后重试。');
                }
              } finally {
                requestHeaders.remove(id);
                syncing = false;
              }
            });
      } else {
        for (final cookie in cookies.entries) {
          await CookieManager.instance().setCookie(
              url: WebUri('https://webstatic.mihoyo.com/'),
              domain: '.mihoyo.com',
              name: cookie.key,
              value: cookie.value,
              isSecure: true,
              isHttpOnly: true);
        }
      }
      await controller.loadUrl(
          urlRequest: URLRequest(
              url: WebUri.uri(officialRecordUrl(widget.entry.role))));
    } catch (_) {
      if (mounted) setState(() => message = '官方工具未能打开，请返回后重试。');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text('${widget.entry.role.game.shortTitle} · 官方工具'),
          actions: [
            TextButton(
                onPressed: () async {
                  if (!received) await widget.state.refresh();
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('完成并返回')),
            const SizedBox(width: 16),
          ]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Text(message)),
        Expanded(
            child: InAppWebView(
          initialData: InAppWebViewInitialData(data: '<html></html>'),
          initialSettings: InAppWebViewSettings(
              incognito: true,
              isInspectable: false,
              useShouldOverrideUrlLoading: true,
              allowFileAccess: false,
              allowContentAccess: false,
              saveFormData: false),
          onWebViewCreated: initialize,
          shouldOverrideUrlLoading: (_, action) async =>
              action.isForMainFrame &&
                      action.request.url?.toString() != 'about:blank' &&
                      !isOfficialLoginUrl(action.request.url)
                  ? NavigationActionPolicy.CANCEL
                  : NavigationActionPolicy.ALLOW,
        )),
      ]));
}
