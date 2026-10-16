import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import 'community_client.dart';
import 'community_http.dart';
import 'miyoushe_client.dart';

class TaygedoClient implements CommunityClient {
  TaygedoClient({http.Client? transport, DateTime Function()? clock})
      : _api = CommunityHttp(Community.taygedo, 'bbs-api.tajiduo.com',
            transport: transport),
        _clock = clock ?? DateTime.now;
  final CommunityHttp _api;
  final DateTime Function() _clock;
  static const appVersion = '1.2.5';
  // Public protocol metadata, not an account secret.
  static String signature(int timestamp, String nonce) =>
      '$timestamp,$nonce,${md5.convert(utf8.encode('$timestamp$nonce${appVersion}pUds3dfMkl'))}';
  Map<String, String> _headers(Account account, {bool native = false}) => {
        if (account.recordHeaders['auth-type'] == 'cookie')
          'cookie': account.cookie
        else
          'authorization': account.cookie,
        if (account.recordHeaders['authorization'] case final String token)
          'authorization': token,
        'origin': account.recordHeaders['auth-type'] == 'cookie'
            ? 'https://www.tajiduo.com'
            : 'https://webstatic.tajiduo.com',
        'referer': account.recordHeaders['auth-type'] == 'cookie'
            ? 'https://www.tajiduo.com/bbs/'
            : 'https://webstatic.tajiduo.com/',
        if (account.recordHeaders['user-agent'] case final String ua)
          'user-agent': ua,
        if (native) ...{
          'appversion': appVersion,
          'platform': 'android',
          'uid': account.id.replaceFirst('taygedo:', ''),
          'deviceid': account.deviceId,
          'ds': signature(_clock().millisecondsSinceEpoch ~/ 1000,
              newCommunityDeviceId().substring(0, 8)),
        }
      };
  @override
  Future<Account> connect(String input, {String? existingDeviceId}) async {
    final auth = communityCredential(input, allowCookie: true);
    final device = existingDeviceId ?? newCommunityDeviceId();
    final metadata = {
      if (auth['cookie'] != null) 'auth-type': 'cookie',
      if (auth['cookie'] != null && auth['token'] != null)
        'authorization': auth['token']!,
      if (auth['user-agent'] != null) 'user-agent': auth['user-agent']!
    };
    var account = Account(
        id: '',
        cookie: auth['cookie'] ?? auth['token']!,
        deviceId: device,
        community: Community.taygedo,
        recordHeaders: metadata,
        roles: const []);
    final profile = object(await _api.request(
        '/usercenter/wapi/getUserFullInfo', _headers(account)));
    final uid =
        requiredText(object(profile['user'])['uid'], '塔吉多未返回账号编号，请重新登录。');
    account = Account(
        id: 'taygedo:$uid',
        cookie: account.cookie,
        deviceId: device,
        community: Community.taygedo,
        recordHeaders: metadata,
        roles: const []);
    final cards = await _api.request(
        '/apihub/api/getGameRecordCard', _headers(account, native: true),
        query: {'uid': uid});
    if (cards is! List) {
      throw const MiyousheException(
          ApiFailure.protocol, '塔吉多角色数据格式有变化，暂时无法连接。');
    }
    final roles = <Role>[];
    final seen = <String>{};
    for (final raw in cards) {
      final card = object(raw);
      final game = [Game.nevernessToEverness, Game.towerOfFantasy]
          .where((g) => g.communityGameId == '${card['gameId']}')
          .firstOrNull;
      if (game == null) continue;
      final info = object(card['bindRoleInfo']);
      if (info['roleId'] == null || '${info['roleId']}' == '0') continue;
      final role = Role(
          game: game,
          uid: requiredText(info['roleId'], '塔吉多未返回角色编号。'),
          region: info['serverId']?.toString() ?? '',
          nickname: '${info['roleName'] ?? game.shortTitle}',
          serverName: '${info['serverName'] ?? '国服'}',
          level: number(info['lev'] ?? info['level']));
      if (seen.add(role.key)) roles.add(role);
    }
    if (roles.isEmpty) {
      throw const MiyousheException(
          ApiFailure.protocol, '未发现已绑定的异环或幻塔角色，请先在塔吉多绑定角色。');
    }
    return Account(
        id: account.id,
        cookie: account.cookie,
        deviceId: device,
        community: Community.taygedo,
        recordHeaders: metadata,
        roles: roles);
  }

  void _check(Account account, Role role) {
    if (account.community != Community.taygedo ||
        role.game.community != Community.taygedo ||
        !account.roles.any((r) => r.key == role.key)) {
      throw const MiyousheException(
          ApiFailure.credentials, '塔吉多账号与角色不匹配，请重新连接。');
    }
  }

  @override
  Future<DailyNote> daily(Account account, Role role) async {
    _check(account, role);
    if (role.game == Game.towerOfFantasy) {
      return DailyNote.parse(role.game, const {}, _clock());
    }
    final data = object(await _api.request(
        '/apihub/awapi/yh/roleHome', _headers(account),
        query: {'roleId': role.uid}));
    final note = DailyNote.parse(role.game, data, _clock());
    if (note.energy == null || note.capacity == null || note.capacity! <= 0) {
      throw const MiyousheException(
          ApiFailure.protocol, '塔吉多未返回完整体力数据，请先在官方社区启用游戏工具。');
    }
    return note;
  }

  @override
  Future<SignStatus> signInfo(Account account, Role role) async {
    _check(account, role);
    final data = object(await _api.request(
        '/apihub/awapi/signin/state', _headers(account),
        query: {'gameId': role.game.communityGameId}));
    return strictSignState(data['todaySign'], Community.taygedo);
  }

  @override
  Future<SignStatus> sign(Account account, Role role) async {
    if ((await signInfo(account, role)).isDone) return SignStatus.alreadySigned;
    await _api.request('/apihub/awapi/sign', _headers(account),
        form: {'roleId': role.uid, 'gameId': role.game.communityGameId});
    if (!(await signInfo(account, role)).isDone) {
      throw const MiyousheException(
          ApiFailure.protocol, '塔吉多尚未确认签到结果，请稍后刷新状态。');
    }
    return SignStatus.signed;
  }

  @override
  void close() => _api.close();
}
