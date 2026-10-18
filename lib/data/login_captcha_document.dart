import 'dart:convert';
import 'community_sms_login.dart';

// This local document receives only a public challenge and a one-use nonce.
String loginCaptchaHtml(LoginChallenge challenge, String nonce) {
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,1024}$').hasMatch(challenge.id) ||
      (!challenge.isV4 &&
          !RegExp(r'^[a-zA-Z0-9_-]{1,1024}$').hasMatch(challenge.challenge))) {
    throw const FormatException('Invalid official CAPTCHA configuration');
  }
  final config = challenge.isV4
      ? {
          'captchaId': challenge.id,
          'product': 'popup',
          'language': 'zho',
          // Local WebViews have about:/file: origins. GT4 otherwise inherits
          // that protocol for its API and secondary script requests.
          'protocol': 'https://',
          'timeout': 20000
        }
      : {
          'gt': challenge.id,
          'challenge': challenge.challenge,
          'new_captcha': true,
          'offline': false,
          'https': true,
          'product': 'popup',
          'lang': 'zh-cn',
          'width': '300px',
          'timeout': 20000
        };
  final script = challenge.isV4
      ? 'https://static.geetest.com/v4/gt4.js'
      : 'https://static.geetest.com/static/tools/gt.js';
  final initialize = challenge.isV4 ? 'initGeetest4' : 'initGeetest';
  return '''<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' https://*.geetest.com https://*.geevisit.com https://*.gsensebot.com; connect-src https://*.geetest.com https://*.geevisit.com https://*.gsensebot.com; img-src data: blob: https://*.geetest.com https://*.geevisit.com https://*.gsensebot.com; style-src 'unsafe-inline' https://*.geetest.com https://*.geevisit.com https://*.gsensebot.com; font-src https://*.geetest.com; frame-src https://*.geetest.com https://*.geevisit.com https://*.gsensebot.com; worker-src blob: https://*.geetest.com; base-uri 'none'; form-action 'none'">
<style>html,body{margin:0;height:100%;background:#fff}body{display:flex;align-items:center;justify-content:center}#captcha{min-height:44px;max-width:100%}#status{font:14px sans-serif;color:#666;text-align:center;padding:16px}</style></head>
<body><main><div id="status" role="status">正在加载验证码…</div><div id="captcha"></div></main><script>
(function() {
  let stopped = false;
  const nonce = ${jsonEncode(nonce)};
  const status = document.getElementById('status');
  function send(phase, result, reason) {
    const go = function() {
      window.flutter_inappwebview.callHandler('qiyouLoginCaptcha', {nonce:nonce,phase:phase,result:result,reason:reason});
    };
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) go();
    else window.addEventListener('flutterInAppWebViewPlatformReady', go, {once:true});
  }
  function fail(reason) {
    if (stopped) return;
    stopped = true;
    clearTimeout(deadline);
    status.hidden = false;
    status.textContent = '官方验证码加载失败，请重新加载。';
    send('error', null, reason);
  }
  const deadline = setTimeout(function() { fail('timeout'); }, 25000);
  window.addEventListener('error', function() { fail('script'); });
  window.addEventListener('unhandledrejection', function() { fail('script'); });
  const script = document.createElement('script');
  script.src = ${jsonEncode(script)};
  script.onerror = function() { fail('resource'); };
  script.onload = function() {
    if (stopped) return;
    try {
      if (typeof window.$initialize !== 'function') { fail('initialization'); return; }
      window.$initialize(${jsonEncode(config)}, function(captcha) {
        if (stopped) return;
        captcha.onReady(function() {
          if (stopped) return;
          clearTimeout(deadline);
          status.hidden = true;
          send('ready');
        });
        captcha.onError(function() { fail('resource'); });
        captcha.onSuccess(function() {
          if (stopped) return;
          const result = captcha.getValidate();
          if (!result) { fail('proof'); return; }
          stopped = true;
          clearTimeout(deadline);
          send('success', result);
        });
        captcha.appendTo('#captcha');
      });
    } catch (_) { fail('initialization'); }
  };
  document.head.appendChild(script);
})();
</script></body></html>''';
}
