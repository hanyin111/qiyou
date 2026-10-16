import 'dart:convert';
import '../domain/models.dart';
import 'community_http.dart';
import 'miyoushe_client.dart';

// The official SMS form owns the phone, OTP and CAPTCHA. We neither inspect
// its phone/OTP fields nor solve its CAPTCHA. Select the documented app login
// channel, and retain only the returned community token in native memory.
String kuroAppLoginScript(String nonce) => '''(() => {
  if (location.protocol !== 'https:' || location.hostname !== 'www.kurobbs.com') return;
  const originalOpen = XMLHttpRequest.prototype.open;
  const originalHeader = XMLHttpRequest.prototype.setRequestHeader;
  const originalSend = XMLHttpRequest.prototype.send;
  const pending = new WeakSet();
  const hasSource = new WeakSet();
  XMLHttpRequest.prototype.open = function(method, url, ...rest) {
    pending.delete(this); hasSource.delete(this);
    let target;
    try { target = new URL(url, location.href); } catch (_) {}
    if (String(method).toUpperCase() === 'POST' && target &&
        target.protocol === 'https:' && target.hostname === 'api.kurobbs.com' &&
        ['/user/sdkLogin', '/user/sdkLoginForH5'].includes(target.pathname)) {
      pending.add(this);
      target.pathname = '/user/sdkLogin';
      url = target.href;
    }
    return originalOpen.call(this, method, url, ...rest);
  };
  XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
    if (pending.has(this) && String(name).toLowerCase() === 'source') {
      value = 'android'; hasSource.add(this);
    }
    return originalHeader.call(this, name, value);
  };
  XMLHttpRequest.prototype.send = function(body) {
    if (pending.has(this)) {
      if (!hasSource.has(this)) originalHeader.call(this, 'source', 'android');
      const device = localStorage.getItem('dc');
      // The official form sends mobile and code. Append only the SDK's device
      // field; never parse, retain or forward those form values to Dart.
      if (typeof body === 'string' && device) body += '&devCode=' + encodeURIComponent(device);
      this.addEventListener('load', () => {
        try {
          const result = this.responseType === 'json' ? this.response : JSON.parse(this.responseText);
          const data = result && result.data;
          if (this.status === 200 && [0, 200].includes(result.code) &&
              data && typeof data.token === 'string' && data.token.length > 0) {
            const dc = localStorage.getItem('dc');
            window.flutter_inappwebview.callHandler('qiyouKuroAppSession', {
              nonce: '$nonce', token: data.token, did: dc, devcode: dc,
              'user-agent': navigator.userAgent
            });
          }
        } catch (_) {}
      }, {once: true});
    }
    return originalSend.call(this, body);
  };
})()''';

String? kuroAppLoginCredential(Object? raw, String nonce) {
  final data = object(raw);
  if (data['nonce'] != nonce) return null;
  final token = data['token'], device = data['did'];
  if (token is! String ||
      token.isEmpty ||
      device is! String ||
      device.isEmpty ||
      device != data['devcode']) {
    throw const MiyousheException(
        ApiFailure.credentials, '库街区未返回完整的游戏登录会话，请重新短信登录。');
  }
  return jsonEncode(communityCredential(jsonEncode({
    'token': token,
    'did': device,
    'devcode': device,
    'user-agent': data['user-agent'],
  })));
}
