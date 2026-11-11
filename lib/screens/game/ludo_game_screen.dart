import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../../services/safe_http.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../providers/user_provider.dart';
import '../../providers/locale_provider.dart';
import 'package:zero/core/dtext.dart';

class LudoGameScreen extends StatefulWidget {
  final String roomId;

  const LudoGameScreen({super.key, required this.roomId});

  @override
  State<LudoGameScreen> createState() => _LudoGameScreenState();
}

class _LudoGameScreenState extends State<LudoGameScreen> {
  static const String _gameBase = 'https://web-mobile-rust.vercel.app/';

  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
    unawaited(_loadGame());
  }

  String _buildUrl() {
    final user = Provider.of<UserProvider>(context, listen: false).currentUser;
    final lang =
        Provider.of<LocaleProvider>(context, listen: false).locale?.languageCode ??
            'ar';
    final userId = Uri.encodeComponent(user?.uid ?? '');
    final roomId = Uri.encodeComponent(widget.roomId);
    final nickname = Uri.encodeComponent(user?.name ?? '');
    final avatar = Uri.encodeComponent(user?.photoUrl ?? '');
    final coins = user?.coins.toInt() ?? 0;
    return '${_gameBase}index.html'
        '?appChannel=goview'
        '&isDataByUrl=true'
        '&userId=$userId'
        '&roomId=$roomId'
        '&appId=1001'
        '&appKey=app_key_c052suexgl68'
        '&gameMode=3'
        '&language=$lang'
        '&role=2'
        '&nickname=$nickname'
        '&avatar=$avatar'
        '&coins=$coins';
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF120B17))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _failed = false;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _loading = false;
                _failed = true;
              });
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (uri.scheme == 'https' || uri.scheme == 'http') {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      );
  }

  Future<void> _loadGame() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    final url = _buildUrl();
    String? html;
    try {
      final res = await SafeHttp.get(Uri.parse(_gameBase))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        html = res.body;
      }
    } catch (_) {}

    if (!mounted) return;
    if (html == null || html.isEmpty) {
      // فشل جلب الغلاف: جرّب التحميل المباشر (دون حقن بيانات المستخدم).
      _controller.loadRequest(Uri.parse(url));
      return;
    }
    _controller.loadHtmlString(
      _injectGameData(html, url),
      baseUrl: url,
    );
  }

  String _injectGameData(String html, String url) {
    final params = Uri.parse(url).queryParameters;
    final real = <String, String>{
      'name': params['nickname'] ?? '',
      'avatar': params['avatar'] ?? '',
      'coins': params['coins'] ?? '',
    };
    final realJson = jsonEncode(real).replaceAll('</', r'<\/');
    final queryJson = jsonEncode(params).replaceAll('</', r'<\/');

    final script = '''
<script>
(function(){
  var REAL = $realJson;
  var QUERY = $queryJson;
  window.__lastPatchedLogin = null;

  function applyUser(u){
    if (!u) return;
    if (REAL.name) u.nickname = REAL.name;
    if (REAL.avatar) u.avatar = REAL.avatar;
    if (REAL.coins !== '') u.coin = Number(REAL.coins);
  }

  var SERVER_UID = null;
  function patchText(text){
    try {
      var o = JSON.parse(text);
      if (o && o.data) {
        if (o.msgId === 'Login' && o.data.userInfo) {
          SERVER_UID = o.data.userInfo.userId;
          applyUser(o.data.userInfo);
          window.__lastPatchedLogin = o;
        } else if (o.msgId === 'UserInfo') {
          applyUser(o.data);
        } else if (o.msgId === 'NoticeUserCoin' && o.data && o.data.userId === SERVER_UID) {
          if (REAL.coins !== '') o.data.coin = Number(REAL.coins);
        }
      }
      return JSON.stringify(o);
    } catch(e) { return text; }
  }

  function rewrite(ev){
    try {
      if (typeof ev.data === 'string') {
        var t = patchText(ev.data);
        if (t !== ev.data) {
          return new MessageEvent('message', {data:t, origin:ev.origin, lastEventId:ev.lastEventId, source:ev.source, ports:ev.ports});
        }
      } else if (ev.data instanceof ArrayBuffer) {
        var text = new TextDecoder().decode(ev.data);
        var p = patchText(text);
        if (p !== text) {
          return new MessageEvent('message', {data:new TextEncoder().encode(p).buffer, origin:ev.origin, lastEventId:ev.lastEventId, source:ev.source, ports:ev.ports});
        }
      }
    } catch(e) {}
    return ev;
  }

  var TrueWS = window.WebSocket;
  var wsDesc = Object.getOwnPropertyDescriptor(TrueWS.prototype, 'onmessage');
  function wrapWsHandler(fn){
    if (!fn) return fn;
    return function(ev){ return fn.call(this, rewrite(ev)); };
  }
  function PatchedWS(url, protocols){
    var ws = protocols ? new TrueWS(url, protocols) : new TrueWS(url);
    var _om = null;
    Object.defineProperty(ws, 'onmessage', {
      configurable: true,
      get: function(){ return _om; },
      set: function(fn){
        _om = wrapWsHandler(fn);
        if (wsDesc && wsDesc.set) wsDesc.set.call(ws, _om);
        else ws.addEventListener('message', _om);
      }
    });
    return ws;
  }
  PatchedWS.prototype = TrueWS.prototype;
  ['CONNECTING','OPEN','CLOSING','CLOSED'].forEach(function(k){ PatchedWS[k] = TrueWS[k]; });
  window.WebSocket = PatchedWS;

  function patchBSUtils(v){
    if (!v || typeof v.GetUrlParams !== 'function' || v.__ludoPatched) return v;
    var orig = v.GetUrlParams;
    v.GetUrlParams = function(href){
      var out = (orig ? orig.call(v, href) : null) || {};
      for (var k in QUERY) { if (out[k] == null) out[k] = QUERY[k]; }
      return out;
    };
    v.__ludoPatched = true;
    return v;
  }
  var bs = window.BSUtils;
  if (bs) patchBSUtils(bs);
  try {
    Object.defineProperty(window, 'BSUtils', {
      configurable: true,
      get: function(){ return bs; },
      set: function(v){ bs = patchBSUtils(v); }
    });
  } catch(e) {}
})();
</script>
''';

    var out = html;
    if (!out.contains('<base ')) {
      out = out.replaceFirst('<head>', '<head>\n<base href="$_gameBase">');
    }
    const marker = '<script src="src/settings.js"';
    final idx = out.indexOf(marker);
    if (idx >= 0) {
      out = out.replaceRange(idx, idx, script);
    } else {
      out = out.replaceFirst('</head>', '$script</head>');
    }
    out = out.replaceFirst(
      "if (!window.location.search || window.location.search.indexOf('appChannel') === -1) {",
      'if (false) {',
    );
    return out;
  }

  void _reload() {
    setState(() {
      _loading = true;
      _failed = false;
    });
    unawaited(_loadGame());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF120B17),
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const ColoredBox(
                color: Color(0xFF120B17),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFFFD700)),
                ),
              ),
            if (_failed)
              ColoredBox(
                color: const Color(0xFF120B17),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 56),
                      const SizedBox(height: 12),
                      const DText(
                        'تعذر تحميل اللعبة',
                        style: TextStyle(color: Colors.white70, fontSize: 15),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _reload,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD700),
                          foregroundColor: Colors.black,
                        ),
                        child: const DText('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
