import 'package:http/http.dart' as http;
import '../domain/models.dart';
import 'community_client.dart';
import 'community_http.dart';
import 'miyoushe_client.dart';

class KuroClient implements CommunityClient {
  KuroClient({http.Client? transport, DateTime Function()? clock})
      : _api = CommunityHttp(Community.kuro, 'api.kurobbs.com',
            transport: transport),
        _clock = clock ?? DateTime.now;
  final CommunityHttp _api;
  final DateTime Function() _clock;
  final _access = <String, ({String token, DateTime expires})>{};

  Map<String, String> _headers(Account account) => {
        'token': account.cookie,
        'source': 'android',
        'version': '3.1.3',
        'origin': 'https://www.kurobbs.com',
        'referer': 'https://www.kurobbs.com/',
        'devcode': account.recordHeaders['devcode'] ?? account.deviceId,
        'did': account.deviceId,
        if (account.recordHeaders['user-agent'] case final String ua)
          'user-agent': ua,
      };

  @override
  Future<Account> connect(String input, {String? existingDeviceId}) async {
    final auth = communityCredential(input);
    // Data tokens are tied to the device used by the official login. A newly
    // generated ID cannot replace the browser's dc value.
    final device = auth['did'] ??
        auth['devcode'] ??
        existingDeviceId ??
        newCommunityDeviceId();
    final headers = {
      for (final key in ['devcode', 'user-agent'])
        if (auth[key] != null) key: auth[key]!
    };
    final temporary = Account(
        id: '',
        cookie: auth['token']!,
        deviceId: device,
        community: Community.kuro,
        recordHeaders: headers,
        roles: const []);
    final roles = <Role>[];
    String? userId;
    for (final game in [Game.wutheringWaves, Game.punishingGrayRaven]) {
      final data = await _api.request('/gamer/role/list', _headers(temporary),
          form: {'gameId': game.communityGameId},
          acceptedCodes: const {0, 200});
      if (data is! List) {
        throw const MiyousheException(
            ApiFailure.protocol, '库街区角色列表格式有变化，暂时无法连接。');
      }
      for (final raw in data) {
        final item = object(raw);
        final uid = requiredText(item['roleId'], '库街区未返回角色编号。');
        final server =
            requiredText(item['serverId'], '库街区未返回角色服务器。请先在官方社区绑定角色。');
        final owner = item['userId']?.toString();
        if (owner != null && owner.isNotEmpty) {
          if (userId != null && userId != owner) {
            throw const MiyousheException(
                ApiFailure.protocol, '库街区账号信息不一致，请重新登录。');
          }
          userId = owner;
        }
        roles.add(Role(
            game: game,
            uid: uid,
            region: server,
            nickname: '${item['roleName'] ?? game.shortTitle}',
            serverName: '${item['serverName'] ?? '国服'}',
            level: number(item['gameLevel'] ?? item['level'])));
      }
    }
    if (roles.isEmpty) {
      throw const MiyousheException(
          ApiFailure.protocol, '未发现鸣潮或战双帕弥什角色，请先在库街区绑定角色。');
    }
    final id = requiredText(userId, '库街区未返回账号编号，暂时无法安全保存此账号。');
    _access.removeWhere((key, _) => key.startsWith('kuro:$id:'));
    return Account(
        id: 'kuro:$id',
        cookie: temporary.cookie,
        deviceId: device,
        community: Community.kuro,
        recordHeaders: headers,
        roles: roles);
  }

  void _check(Account account, Role role) {
    if (account.community != Community.kuro ||
        role.game.community != Community.kuro ||
        !account.roles.any((r) => r.key == role.key)) {
      throw const MiyousheException(
          ApiFailure.credentials, '库街区账号与角色不匹配，请重新连接。');
    }
  }

  Map<String, String> _role(Role role) => {
        'gameId': role.game.communityGameId,
        'serverId': role.region,
        'roleId': role.uid
      };
  Future<Map<String, String>> _gameHeaders(Account account, Role role) async {
    _check(account, role);
    final headers = _headers(account);
    if (role.game == Game.wutheringWaves) {
      final key = '${account.id}:${account.deviceId}:${role.key}';
      var access = _access[key];
      if (access == null || !_clock().isBefore(access.expires)) {
        final data = object(await _api.request(
            '/aki/roleBox/requestToken', headers,
            form: {'roleId': role.uid, 'serverId': role.region},
            acceptedCodes: const {0, 200}));
        final token = data['accessToken'];
        if (token is! String ||
            token.isEmpty ||
            RegExp(r'[\r\n]').hasMatch(token)) {
          throw const MiyousheException(
              ApiFailure.protocol, '库街区未返回数据访问令牌，请重新连接。');
        }
        access =
            (token: token, expires: _clock().add(const Duration(minutes: 5)));
        _access[key] = access;
      }
      headers['b-at'] = access.token;
    }
    return headers;
  }

  @override
  Future<DailyNote> daily(Account account, Role role) async {
    final headers = await _gameHeaders(account, role);
    if (role.game == Game.wutheringWaves) {
      // The widget endpoint can keep an old snapshot after stamina is spent.
      // Ask the official role service to refresh before reading that snapshot.
      // Failure stops this query instead of presenting cached data as current.
      await _api.request('/aki/roleBox/akiBox/refreshData', headers,
          form: _role(role), acceptedCodes: const {0, 200});
    }
    final data = object(await _api.request(
        role.game == Game.wutheringWaves
            ? '/gamer/widget/game3/getData'
            : '/haru/roleBox/dailyData',
        headers,
        form: {
          ..._role(role),
          'type': '2',
          if (role.game == Game.wutheringWaves) 'sizeType': '1'
        },
        acceptedCodes: const {
          0,
          200
        }));
    if (data['temporaryClose'] == true) {
      throw const MiyousheException(ApiFailure.protocol, '库街区暂时关闭了此角色的数据查询。');
    }
    if ((data['roleId'] != null && data['roleId'].toString() != role.uid) ||
        (data['serverId'] != null &&
            data['serverId'].toString() != role.region)) {
      throw const MiyousheException(
          ApiFailure.protocol, '库街区返回的角色与当前选择不一致，已停止显示。');
    }
    final note = DailyNote.parse(role.game, data, _clock());
    if (note.energy == null || note.capacity == null || note.capacity! <= 0) {
      throw const MiyousheException(
          ApiFailure.protocol, '库街区未返回完整体力数据，请先在官方社区开启数据展示。');
    }
    return note;
  }

  @override
  Future<SignStatus> signInfo(Account account, Role role) async {
    _check(account, role);
    final data = object(await _api.request(
        '/encourage/signIn/initSignInV2', _headers(account),
        form: {..._role(role), 'userId': account.id.substring(5)},
        acceptedCodes: const {0, 200}));
    return strictSignState(data['isSigIn'], Community.kuro);
  }

  @override
  Future<SignStatus> sign(Account account, Role role) async {
    if ((await signInfo(account, role)).isDone) return SignStatus.alreadySigned;
    await _api.request('/encourage/signIn/v2', _headers(account), form: {
      ..._role(role),
      'userId': account.id.substring(5),
      'reqMonth': chinaDay(_clock()).substring(5, 7)
    }, acceptedCodes: const {
      0,
      200,
      1511
    });
    if (!(await signInfo(account, role)).isDone) {
      throw const MiyousheException(
          ApiFailure.protocol, '库街区尚未确认签到结果，请稍后刷新状态。');
    }
    return SignStatus.signed;
  }

  @override
  void close() {
    _access.clear();
    _api.close();
  }
}
