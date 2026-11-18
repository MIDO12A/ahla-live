import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../config/supabase_config.dart';
import '../../providers/user_provider.dart';
import '../../services/safe_http.dart';
import '../../services/session_token_store.dart';
import '../../services/supabase_data_service.dart';
import '../wallet/wallet_main_screen.dart';
import 'package:zero/core/dtext.dart';

/// لعبة ألفا (Alfa Lucky 777) — لعبة H5 مستضافة على Vercel
/// تُفتح داخل WebView مع تمرير بيانات المستخدم كـ query params:
/// user_id, nickname, coins, avatar, win_rate, chips
class AlfaGameScreen extends StatefulWidget {
  const AlfaGameScreen({
    super.key,
    this.gameId = 'fe-game-lucky777',
    this.host = _defaultHost,
    this.appKey = _defaultAppKey,
    this.poolId,
    this.title,
    this.roomId,
    this.viewMode,
    this.onGameRatio,
  });

  /// معرّف اللعبة على منصة Alfa (fe-game-lucky777, fe-game-super77, ...)
  final String gameId;

  /// مضيف المنصة — الافتراضي alfa-game-rosy.vercel.app،
  /// وألعاب UTD/Alfa الجديدة على alfanexso.tech
  final String host;

  /// مفتاح التطبيق/التاجر على المنصة (app_key في رابط /play/)
  final String appKey;

  /// معرّف داخلي منفصل للـ pool/records — عندما تكون gameId
  /// مشتركة بين منصتين (مثل fe-game-super77 على alfanexso)
  final String? poolId;

  /// عنوان مخصص لشريط اللعبة — يُستخدم بدل «لعبة الحظ 777»
  final String? title;

  /// معرف الغرفة — يُرسل كـ roomId في رابط تشغيل اللعبة (بروتوكول StyeParty)
  final String? roomId;

  /// وضع عرض اللعبة — 'full' تملأ الشاشة، 'half' نصف الشاشة.
  /// يختلف حسب اللعبة حسب مواصفات مزوّد الألعاب.
  final String? viewMode;

  /// يُستدعى بمجرد ما الـ JS يقيس نسبة أبعاد canvas بتاع اللعبة،
  /// عشان الصندوق يتحجم تلقائياً على شكل اللعبة بدون ما نعرف قيم view_mode.
  final ValueChanged<double>? onGameRatio;

  static const String _defaultHost = 'alfa-game-rosy.vercel.app';
  static const String _defaultAppKey = 'alfa_key_goog_KuMTPgPJ';
  static const double _defaultWinRate = 75.0;

  static const List<String> _chips = [
    '1000',
    '5000',
    '10000',
    '50000',
    '500000',
  ];

  /// صندوق يتحجم تلقائياً من قياس الـ canvas، ويتكبر لحد **الشاشة الكاملة**،
  /// مع مقبض سحب لتعديل المقاس يدوياً. الخلفية شفافة بالكامل (بدون scrim).
  static Future<void> show(BuildContext context,
      {String gameId = 'fe-game-lucky777',
      String? host,
      String? appKey,
      String? poolId,
      String? title,
      String? roomId,
      String? viewMode}) {
    final media = MediaQuery.of(context);
    final screenH = media.size.height;
    final screenW = media.size.width;
    final minH = screenH * 0.35;
    final maxH = screenH; // ✅ لحد الشاشة الكاملة
    final height = ValueNotifier<double>(screenH * 0.88);
    var closed = false;
    var userResized = false;
    var dragStartH = 0.0;

    void onGameRatio(double ratio) {
      // الـ WebView ممكن يبعت قياس بعد ما الصندوق ابتدا يتقفل،
      // وبعد ما المستخدم يسحب المقاس يدوياً ما نرجعش نغيّره تلقائياً.
      if (closed || userResized) return;
      final wanted = (screenW / ratio).clamp(minH, maxH).toDouble();
      if ((wanted - height.value).abs() > 24) height.value = wanted;
    }

    void onDragStart(DragStartDetails d) {
      dragStartH = height.value;
      userResized = true;
    }

    void onDragUpdate(DragUpdateDetails d) {
      if (closed) return;
      height.value = (dragStartH - d.delta.dy).clamp(minH, maxH);
    }

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      // ✅ شفافية كاملة: showModalBottomSheet بيرسم scrim أسود وراء الصندوق
      //    افتراضياً — لغيناه عشان اللعبة تظهر على الخلفية الفعلية للتطبيق.
      barrierColor: Colors.transparent,
      builder: (_) => ValueListenableBuilder<double>(
        valueListenable: height,
        builder: (context, h, _) => Stack(
          children: [
            AnimatedContainer(
              duration: userResized ? Duration.zero : const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              height: h,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                child: AlfaGameScreen(
                  gameId: gameId,
                  host: host ?? _defaultHost,
                  appKey: appKey ?? _defaultAppKey,
                  poolId: poolId,
                  title: title,
                  roomId: roomId,
                  viewMode: viewMode,
                  onGameRatio: onGameRatio,
                ),
              ),
            ),
            // مقبض سحب شبه غير مرئي أعلى الصندوق — اسحبه لأعلى للتكبير
            // (لحد الشاشة الكاملة) ولأسفل للتصغير.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: onDragStart,
                onVerticalDragUpdate: onDragUpdate,
                child: const SizedBox(
                  height: 28,
                  child: Center(
                    child: Opacity(
                      opacity: 0.22,
                      child: SizedBox(
                        width: 44,
                        height: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.all(Radius.circular(2)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      closed = true;
      height.dispose();
    });
  }

  @override
  State<AlfaGameScreen> createState() => _AlfaGameScreenState();
}

class _AlfaGameScreenState extends State<AlfaGameScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  double _winRate = AlfaGameScreen._defaultWinRate;
  int _lastBet = 0;
  int? _lastGameCoins;

  /// آخر رصيد دفعناه للعبة — عشان ما نكتبش نفس القيمة كل ثانية فوق
  /// الرصيد الداخلي اللي اللعبة بتغيّره بنفسها بعد كل رهان/فوز.
  int? _lastPushedCoins;
  UserProvider? _userProvider;

  /// منع `alfa_sync` (كل ~300ms) من إطلاق reloadUser() في كل مرة — كان بيسبب
  /// تدفق طلبات Supabase وتأخير/تضارب في عرض الرصيد.
  DateTime? _lastBalanceRefreshAt;
  Timer? _balanceRefreshDebounce;

  static Map<String, String> get _headers => {
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
      };

  @override
  void initState() {
    super.initState();
    // ✅ إنشاء الكنترولر بشكل متزامن — بدون هذا كان build الأول يرمي
    //    LateInitializationError لأن _init() غير متزامن ويُكمله لاحقاً.
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // ✅ خلفية شفافة للـ WebView عشان شكل اللعبة يظهر كما هو بدون خلفية سوداء
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _loading = false);
              _injectGameHooks();
              // ✅ نفرض رصيد التطبيق الحقيقي داخل اللعبة فور تحميلها
              _injectBalanceMirror();
              _pushTrueCoins(force: true);
              // ✅ نمرّر ترتيبنا الحقيقي للعبة عبر window.setLeaderboard.
              _pushLeaderboard();
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            // نسمح فقط بالتنقل داخل نطاق اللعبة الموثوق
            if (uri != null &&
                uri.scheme == 'https' &&
                uri.host == widget.host) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: _onJsMessage,
      )
      ..addJavaScriptChannel(
        'AlfaBridgeChannel',
        onMessageReceived: _onJsMessage,
      );
    _init();
    // ✅ أي تغيير في رصيد التطبيق (تسوية لعبة، هدية، شحن...) يُدفع للعبة
    //    فوراً عبر window.__sugarGame.updateCoins — بدون bookkeeping دوري.
    _userProvider = Provider.of<UserProvider>(context, listen: false);
    _userProvider!.addListener(_onUserChanged);
  }

  @override
  void dispose() {
    _balanceRefreshDebounce?.cancel();
    _userProvider?.removeListener(_onUserChanged);
    super.dispose();
  }

  void _onUserChanged() {
    if (mounted) _pushTrueCoins();
  }

  Future<void> _init() async {
    _winRate = await _loadWinRate();
    if (!mounted) return;

    final user = Provider.of<UserProvider>(context, listen: false).currentUser;
    // ✅ PLAYER_TOKEN = توكن جلسة المستخدم (نفس x-session-token)
    //    حتى تتطابق طلبات الـ callbacks الموقعة MD5 مع هويتنا.
    final playerToken = SessionTokenStore.token ??
        'token_${user?.uid ?? 'guest'}_${DateTime.now().millisecondsSinceEpoch}';
    final params = <String, String>{
      // معاملات بروتوكول StyeParty الرسمية
      'gameId': widget.gameId,
      'uid': user?.uid ?? '',
      'token': playerToken,
      'roomId': widget.roomId ?? '',
      // ✅ view_mode لكل لعبة حسب مواصفات StyeParty —
      //    half للنصف شاشة (greedy/super77/lucky777)،
      //    full لملء الشاشة (crazy_fruit وغيرها).
      'view_mode': widget.viewMode ?? 'full',
      // معاملات إضافية للتوافق مع المنصة القديمة
      'user_id': user?.uid ?? '',
      'nickname': user?.name ?? '',
      'coins': (user?.coins ?? 0).toString(),
      'avatar': user?.photoUrl ?? '',
      'win_rate': _winRate.toString(),
      'chips': AlfaGameScreen._chips.join(','),
      'app_id': widget.appKey,
      'app_key': widget.appKey,
    };
    final url = Uri.parse(
            'https://${widget.host}/play/${widget.appKey}/${widget.gameId}')
        .replace(queryParameters: params)
        .toString();

    _controller.loadRequest(Uri.parse(url));
  }

  /// win_rate يُجلب من game_jackpot_pool إن وُجد صف للعبة،
  /// وإلا نستخدم القيمة الافتراضية.
  Future<double> _loadWinRate() async {
    try {
      final url = Uri.parse(
        '${SupabaseConfig.projectUrl}/rest/v1/game_jackpot_pool'
        '?select=win_rate&id=in.(alfa,lucky777)&limit=1',
      );
      final res = await SafeHttp.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        if (list.isNotEmpty) {
          final wr = (list.first as Map<String, dynamic>)['win_rate'];
          if (wr is num) return wr.toDouble();
        }
      }
    } catch (_) {}
    return AlfaGameScreen._defaultWinRate;
  }

  /// ✅ مزامنة الرصيد بالطريقة الرسمية اللي أكّدها المزوّد:
  ///    الرابط هو الحاكم عند الدخول (`coins=...`)، وداخل الجلسة نستخدم
  ///    `window.__sugarGame.updateCoins(n)` — نفس دالة Sugar Rush بالظبط.
  ///    كده الفوز/Zيادة والخسارة/النقصان بيحصلوا جوه اللعبة بشكل صحيح،
  ///    والسيرفر هو اللي بيحسم المبلغ النهائي عبر callback.
  ///    لا نعترض JSON.parse ولا نفرض الرصيد على saveUser — ده كان بيعطّل
  ///    خصم الرهان جوه اللعبة ويسبب تضارب مع التسوية.
  void _injectBalanceMirror() {
    final coins =
        Provider.of<UserProvider>(context, listen: false).currentUser?.coins ?? 0;
    final js = '''
(function(){
  var TRUTH = $coins;
  window.__alfaTruthCoins = TRUTH;
  // ✅ المزوّد أكّد 3 مداخل متطابقة لتحديث الرصيد داخل الـ WebView —
  //    نستدعيها كلها بنفس القيمة المطلقة (idempotent) عشان أي إصدار
  //    من اللعبة يلتقط التحديث فوراً بدون إعادة تحميل الصفحة.
  function official(n){
    var ok = false;
    try{
      var g = window.__sugarGame;
      if (g && typeof g.updateCoins === 'function') { g.updateCoins(n); ok = true; }
    }catch(e){}
    try{
      if (typeof window.updateCoins === 'function') { window.updateCoins(n); ok = true; }
    }catch(e){}
    try{
      var ab = window.AlfaBridge;
      if (ab && typeof ab.setCoins === 'function') { ab.setCoins(n); ok = true; }
    }catch(e){}
    return ok;
  }
  // مسار قديم احتياطي لمنصات Alfa القديمة اللي ما عندهاش __sugarGame.
  function legacy(n){
    try{
      ['userInfo','gameUser','user','__user','playerInfo','userData'].forEach(function(k){
        var u = window[k];
        if (!u || typeof u !== 'object') return;
        ['coins','coin','gold','balance','money'].forEach(function(f){
          if (Object.prototype.hasOwnProperty.call(u, f)) u[f] = n;
        });
      });
      ['AlfaBridge','alfaBridge','gameBridge','GameBridge','JSBridge','NativeBridge'].forEach(function(b){
        var bridge = window[b];
        if (!bridge || typeof bridge !== 'object') return;
        ['getUser','getUserInfo','getPlayerInfo','getAccount','getUserData'].forEach(function(fn){
          if (typeof bridge[fn] === 'function' && !bridge['__alfaTruth_'+fn]){
            bridge['__alfaTruth_'+fn] = true;
            var orig = bridge[fn];
            bridge[fn] = function(){
              var u = orig.apply(this, arguments);
              if (u && typeof u === 'object'){
                ['coins','coin','gold','balance','money'].forEach(function(f){
                  if (Object.prototype.hasOwnProperty.call(u, f)) u[f] = n;
                });
              }
              return u;
            };
          }
        });
      });
    }catch(e){}
  }
  function apply(n){
    var v = Number(n);
    if (!isFinite(v) || v < 0) return;
    TRUTH = Math.round(v);
    window.__alfaTruthCoins = TRUTH;
    if (!official(TRUTH)) legacy(TRUTH);
  }
  window.__alfaSetTruthCoins = apply;
  apply(TRUTH);
  // الدالة الرسمية ممكن تتسجّل بعد حقننا (Cocos init متأخر) — نعيد المحاولة
  // لفترة قصيرة بدون أي setInterval دائم عشان ما نكتبش فوق رصيد اللعبة.
  var tries = 0;
  var retry = setInterval(function(){
    if (official(TRUTH) || ++tries > 20) clearInterval(retry);
  }, 300);
  window.__alfaMirrorReady = true;
})();
''';
    _controller.runJavaScript(js);
  }

  /// يدفع أي تغيير في رصيد التطبيق (بعد تسوية الخادم / هدية / شحن) للعبة.
  /// لا نرسل نفس القيمة مرتين عشان ما نقطعش رصيد اللعبة أثناء الجولة.
  void _pushTrueCoins({bool force = false}) {
    final coins =
        (Provider.of<UserProvider>(context, listen: false).currentUser?.coins ?? 0)
            .toInt();
    if (!force && _lastPushedCoins == coins) return;
    _lastPushedCoins = coins;
    unawaited(_controller.runJavaScript(
      'window.__alfaSetTruthCoins && window.__alfaSetTruthCoins($coins);',
    ));
  }

  /// يمرّر ترتيب المتصدرين الحقيقي من تطبيقنا للعبة مباشرة.
  /// المزوّد أكّد دعم `window.setLeaderboard([...])` — نحقنه مع إعادة
  /// محاولة قصيرة لأن اللعبة قد تسجّل الدالة بعد اكتمال تهيئة Cocos.
  void _pushLeaderboard() {
    unawaited(_doPushLeaderboard());
  }

  Future<void> _doPushLeaderboard() async {
    try {
      final uri = Uri.parse(
        'https://ahla-live-api.vercel.app/api/v1/games/leaderboard',
      ).replace(queryParameters: {
        'game_id': widget.gameId,
        'limit': '10',
      });
      final res = await SafeHttp.get(uri, headers: _headers);
      if (res.statusCode != 200 || !mounted) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final rows = (body['rankings'] as List<dynamic>?) ?? const <dynamic>[];
      final list = rows.whereType<Map<String, dynamic>>().map((r) {
        return <String, dynamic>{
          'uid': r['user_id']?.toString() ?? '',
          'name': r['user_name']?.toString() ?? 'Player',
          'avatar': r['avatar']?.toString() ?? '',
          'score': (r['total'] as num?)?.toInt() ?? 0,
        };
      }).toList();
      if (list.isEmpty) return;
      final payload = jsonEncode(list);
      unawaited(_controller.runJavaScript('''
(function(){
  var data = $payload;
  var tries = 0;
  var timer = setInterval(function(){
    try{
      if (typeof window.setLeaderboard === 'function') {
        window.setLeaderboard(data);
        clearInterval(timer);
      } else if (++tries > 20) {
        clearInterval(timer);
      }
    }catch(e){ clearInterval(timer); }
  }, 300);
})();
'''));
    } catch (_) {}
  }

  /// نحقن خطافاً داخل صفحة H5 يلتقط خصم الرهان ومكافأة الفوز.
  /// الآلية الرئيسية: hook على AlfaBridge.saveUser + حساب فرق الرصيد —
  /// يلتقط أي تغيير كوينز (addCoins/deductCoins/حفظ مباشر) في كل ألعاب
  /// Alfa بما فيها roulette مثل super77 التي قد تتجاوز addCoins.
  /// window.__alfaSyncing يمنعFeedback loop عند مزامنة رصيدنا внутрاللعبة.
  void _injectGameHooks() {
    const js = r'''
(function(){
  function send(o){ try{ window.FlutterBridge.postMessage(JSON.stringify(o)); }catch(e){} }
  function hook(){
    try{
      // ✅ مراقبة رصيد اللعبة كل 300ms — ألعاب Alfa بنسخة Cocos/RTM
      //    (مثل super77) لا تمر عبر AlfaBridge.addCoins/deductCoins؛
      //    كل تغيير في الرصيد المخزن (رهان أو فوز) يُلتقط كفرق.
      if (window.AlfaBridge && !window.__alfaPollStarted){
        window.__alfaPollStarted = true;
        var ab = window.AlfaBridge;
        function coinsNow(){
          try{
            var u = ab.getUser();
            if (!u) return null;
            return Number(u.coins || u.coin || u.gold || u.diamond || 0);
          }catch(e){ return null; }
        }
        var lastCoins = coinsNow();
        send({action:'alfa_hook_ready'});
        setInterval(function(){
          try{
            if (window.__alfaSyncing) return;
            var c = coinsNow();
            if (c == null){ return; }
            if (lastCoins == null){ lastCoins = c; return; }
            if (c === lastCoins) return;
            lastCoins = c;
            send({action:'alfa_sync', amount: Math.round(c)});
          }catch(e){}
        }, 300);
      }
      // ✅ إشعارات الرصيد الفورية من سيرفر اللعبة (update_balance وغيرها)
      //    — الرصيد المطلق يُرسل كـ alfa_sync ويُحسب الفرق في الـ Dart
      if (!window.__alfaMsgHook){
        window.__alfaMsgHook = true;
        window.addEventListener('message', function(ev){
          try{
            var d = ev && ev.data;
            if (d == null) return;
            var s = (typeof d === 'string') ? d : JSON.stringify(d);
            if (!/coin|balance|diamond|gold|update/i.test(s)) return;
            var o = (typeof d === 'string') ? JSON.parse(d) : d;
            var coins = null;
            (function pick(x){
              if (!x || typeof x !== 'object' || coins != null) return;
              if (x.user && typeof x.user === 'object'){ pick(x.user); return; }
              var v = x.coins != null ? x.coins : (x.coin != null ? x.coin : (x.balance != null ? x.balance : (x.diamond != null ? x.diamond : (x.gold != null ? x.gold : null))));
              if (typeof v === 'number' && isFinite(v)) coins = Math.round(v);
            })(o);
            if (coins != null) send({action:'alfa_sync', amount: coins});
          }catch(e){}
        });
      }
      if (window.fun && !window.fun.__alfaHooked){
        var names = {
          openRecharge:'open_recharge', popUpBottomRecharge:'open_recharge',
          showRechargeDialog:'open_recharge',
          closeWebview:'close_game', closeCurWebView:'close_game',
          closeGameInRoomView:'close_game', closePage:'close_game'
        };
        for (var k in names){
          (function(key, act){
            var orig = window.fun[key];
            window.fun[key] = function(){
              send({action: act});
              try{ if (orig) return orig.apply(window.fun, arguments); }catch(e){}
            };
          })(k, names[k]);
        }
        window.fun.__alfaHooked = true;
      }
      // ✅ جاسوس debugging: نمرّر كل رسائل RTM وطلبات fetch/XHR
      //    للـ Dart لنرى كيف تتعامل اللعبة مع الرهان/الفوز فعلياً
      if (!window.__alfaNetSpy){
        window.__alfaNetSpy = true;
        function spy(o){ try{ send({action:'alfa_spy', data: JSON.stringify(o).slice(0,500)}); }catch(e){} }
        ['RTMRequestMsg','RTMResponseMsg','requestMsg','requestMsgNew'].forEach(function(n){
          var orig = window[n];
          if (typeof orig === 'function'){
            window[n] = function(p){
              spy({fn:n, params: (typeof p==='string'?p.slice(0,400):p)});
              return orig.apply(window, arguments);
            };
          }
        });
        var of = window.fetch;
        if (of){
          window.fetch = function(u, opt){
            try{ spy({fn:'fetch', url:String(u).slice(0,200), body: opt && opt.body ? String(opt.body).slice(0,300) : ''}); }catch(e){}
            return of.apply(window, arguments);
          };
        }
        var oo = XMLHttpRequest.prototype.open, os = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function(m,u){ this.__alfaUrl = m+' '+u; return oo.apply(this, arguments); };
        XMLHttpRequest.prototype.send = function(b){
          try{ spy({fn:'xhr', url:String(this.__alfaUrl||'').slice(0,200), body: b?String(b).slice(0,300):''}); }catch(e){}
          return os.apply(this, arguments);
        };
      }
      // ✅ قياس نسبة أبعاد اللعبة من داخل الـ WebView (canvas الداخلي)
      //    — الصندوق يتحجم تلقائياً على شكل اللعبة بدون قيم view_mode ثابتة.
      if (!window.__alfaSizeHook){
        window.__alfaSizeHook = true;
        function reportSize(){
          try{
            var c = document.querySelector('canvas');
            var w = 0, h = 0;
            if (c){
              w = c.width || 0; h = c.height || 0;           // دقة التصميم الداخلية
              if (!w || !h){ w = c.clientWidth || 0; h = c.clientHeight || 0; }
            }
            if (!w || !h){
              w = window.innerWidth || 0;
              h = document.documentElement.scrollHeight || window.innerHeight || 0;
            }
            if (w > 0 && h > 0){
              var ar = w / h;
              // تجاهل التغييرات الصغيرة عشان ما ندخلش حلقة resize ↔ measure
              if (!window.__alfaLastAr || Math.abs(ar - window.__alfaLastAr) > 0.02){
                window.__alfaLastAr = ar;
                send({action:'game_size', ratio: ar});
              }
            }
          }catch(e){}
        }
        window.addEventListener('resize', reportSize);
        setTimeout(reportSize, 400);
        setTimeout(reportSize, 1200);
        setInterval(reportSize, 5000);
      }
      return !!window.__alfaPollStarted;
    }catch(e){ return false; }
  }
  // ✅ إعادة حقن دورية كل ثانيتين — لو أعاد game-bridge تعريف AlfaBridge
  //    بعد الحقن الأول (Cocos init متأخر) تُفقد الـ hooks ونعود نلفّها
  var t = setInterval(function(){ try{ hook(); }catch(e){} }, 2000);
  hook();
})();
''';
    _controller.runJavaScript(js);
  }

  void _onJsMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      // ✅ قناة AlfaBridgeChannel الرسمية تبعت `event`، والقنوات القديمة
      //    (FlutterBridge) تبعت `action` — بنتعامل مع الاتنين بنفس المسار.
      final event = (data['event'] ?? data['action'] ?? '').toString();
      debugPrint('[AlfaGame] js event=$event amount=${data['amount']} coins=${data['coins']} spy=${data['data'] ?? ''}');
      switch (event) {
        case 'game_size':
          final ratio = (data['ratio'] as num?)?.toDouble();
          if (ratio != null && ratio > 0) widget.onGameRatio?.call(ratio);
          break;
        case 'closeWebView':
        case 'navigate_back':
        case 'close_game':
        case 'exit_game':
          if (mounted) Navigator.pop(context);
          break;
        case 'showLoading':
          if (mounted) setState(() => _loading = true);
          break;
        case 'closeLoading':
          if (mounted) setState(() => _loading = false);
          break;
        case 'open_recharge':
          _openRecharge();
          break;
        case 'update_balance':
        case 'coins_changed':
        case 'balance_update':
          // ✅ حدث التسوية الرسمي من AlfaBridgeChannel:
          //    coins  = الرصيد الإجمالي الجديد بعد الحركة
          //    diff   = الحركة بالسالب (bet) أو بالموجب (win)
          //    reason = 'bet' | 'win'
          //    styeParty = تفاصيل الطلب (orderId/roundId/type/coin/...)
          //    الرصيد الحقيقي في Supabase يُسوّى S2S — لا نطبّق diff محلياً
          //    على alfanexso عشان ما يحصلش خصم/إضافة مرتين.
          final rawCoins = data['coins'] ?? data['balance'];
          final coins = (rawCoins is num) ? rawCoins.toInt() : null;
          final reason = data['reason']?.toString() ?? '';
          debugPrint('[AlfaGame] update_balance coins=$coins reason=$reason styeParty=${data['styeParty']}');
          if (_isServerSettled) {
            if (coins != null) _lastGameCoins = coins; // baseline للـ poll
            _refreshBalanceFromServer();
          } else if (coins != null) {
            _applyGameCoins(coins); // فرق الرصيد = bet/win (منصات قديمة)
          }
          break;
        case 'alfa_bet':
        case 'alfa_win':
        case 'alfa_sync':
          // ✅ ألعاب StyeParty (alfanexso.tech): الرصيد يُسوّى
          //    server-to-server عبر /api/v1/games/change-balance —
          //    تطبيق الفرق محلياً هنا كان سيخصم/يضيف مرتين.
          //    نكتفي بتحديث الرصيد المعروض من السيرفر.
          if (_isServerSettled) {
            _refreshBalanceFromServer();
          } else {
            switch (event) {
              case 'alfa_bet':
                _handleBet((data['amount'] as num?)?.toInt() ?? 0);
                break;
              case 'alfa_win':
                _handleWin((data['amount'] as num?)?.toInt() ?? 0);
                break;
              case 'alfa_sync':
                _applyGameCoins((data['amount'] as num?)?.toInt());
                break;
            }
          }
          break;
        default:
          break;
      }
    } catch (_) {}
  }

  void _openRecharge() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WalletMainScreen()),
    );
  }

  /// رصيد لعبة مطلق (من poll أو إشعار السيرفر) — نحسب الفرق فقط
  /// حتى لا يتكرر الخصم/الإضافة إذا وصل نفس التغيير عبر مسارين.
  void _applyGameCoins(int? gameCoins) {
    if (gameCoins == null || gameCoins < 0) return;
    final prev = _lastGameCoins;
    _lastGameCoins = gameCoins;
    if (prev == null) return; // أول قراءة = خط أساس، لا نطبّق الفارق التراكمي
    final delta = gameCoins - prev;
    if (delta < 0) {
      _handleBet(-delta);
    } else if (delta > 0) {
      _handleWin(delta);
    }
  }

  /// خصم الرهان من الرصيد الحقيقي — يعكس أي نقص في رصيد اللعبة.
  /// اللعبة تدير اقتصادها الافتراضي بنفسها؛ نحن نمرّر الفرق فقط.
  void _handleBet(int amount) {
    if (amount <= 0) return;
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user == null) return;

    _lastBet = amount;
    userProvider.deductCoinsLocally(amount);
    debugPrint('[AlfaGame] bet $amount (atomic RPC)');

    // ✅ RPC ذرّي بدل قراءة user.coins ثم الكتابة — يمنع lost update
    //    مع callback السيرفر / الهدايا / الشحن في نفس اللحظة.
    SupabaseDataService().adjustUserWallet(user.uid, -amount, 0);
    _incrementPool(amount);
    // ✅ لا نزامن الرصيد داخل اللعبة — نسختها Cocos لها اقتصاد
    //    افتراضي مستقل، ودفع رصيدنا الحقيقي كان سيخربه
  }

  /// إضافة مكافأة الفوز للرصيد الحقيقي + تسجيل النتيجة
  void _handleWin(int amount) {
    if (amount <= 0) return;

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user == null) return;

    final bet = _lastBet;
    _lastBet = 0;

    userProvider.addCoinsLocally(amount);
    debugPrint('[AlfaGame] win $amount (bet=$bet) (atomic RPC)');

    // ✅ الفوز مضروب بالفعل في المضاعف جوّه اللعبة — نضيفه كما هو
    //    على أحدث رصيد في Supabase (بدون ضرب محلي وبدون خصم الرهان).
    SupabaseDataService().adjustUserWallet(user.uid, amount, 0);
    _incrementPool(-amount);
    _recordBet(user, bet, amount);
  }

  /// معرّف اللعبة الداخلي للـ pool/records — fe-game-super77 → super77
  /// (أو poolId مخصص عندما تتشارك منصتان نفس gameId)
  String get _poolGameId =>
      widget.poolId ?? widget.gameId.replaceFirst('fe-game-', '');

  /// ألعاب StyeParty على alfanexso.tech — الرصيد يُسوّى server-to-server
  /// عبر /api/v1/games/* callbacks، فلا نعدّل الرصيد محلياً من JS bridge.
  bool get _isServerSettled => widget.host == 'alfanexso.tech';

  /// يجلب الرصيد الحقيقي من Supabase ويحدّث الواجهة — userStream
  /// في UserProvider يلتقط تغيير coins تلقائياً لأنه في publication.
  void _refreshBalanceFromServer() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;
    if (uid == null) return;

    final now = DateTime.now();
    final last = _lastBalanceRefreshAt;
    const minGap = Duration(milliseconds: 900);
    if (last != null && now.difference(last) < minGap) {
      // حدّث مرة واحدة فقط بعد آخر إشارة بدل عشرات الطلبات المتتالية.
      _balanceRefreshDebounce?.cancel();
      _balanceRefreshDebounce = Timer(minGap, () => _doRefreshBalance(uid));
      return;
    }
    _doRefreshBalance(uid);
  }

  void _doRefreshBalance(String uid) {
    _lastBalanceRefreshAt = DateTime.now();
    unawaited(Provider.of<UserProvider>(context, listen: false).reloadUser().then((_) {
      // فور ما الرصيد الحقيقي يوصل من السيرفر، نفرضه جوه اللعبة
      if (mounted) _pushTrueCoins();
    }));
  }

  Future<void> _incrementPool(int amount) async {
    try {
      final rpcUrl = Uri.parse(
        '${SupabaseConfig.projectUrl}/rest/v1/rpc/increment_game_pool_balance',
      );
      await SafeHttp.post(
        rpcUrl,
        headers: _headers,
        body: jsonEncode({
          'p_game_id': _poolGameId,
          'p_amount': amount,
        }),
      );
    } catch (_) {}
  }

  Future<void> _recordBet(
    dynamic user,
    int betAmount,
    int winAmount,
  ) async {
    try {
      final recordUrl = Uri.parse(
        '${SupabaseConfig.projectUrl}/rest/v1/game_bet_records',
      );
      await SafeHttp.post(
        recordUrl,
        headers: {
          ..._headers,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'game_id': _poolGameId,
          'user_id': user.uid,
          'user_name': (user.name.isNotEmpty) ? user.name : 'Player',
          'bet_amount': betAmount,
          'win_amount': winAmount,
          'net_result': winAmount - betAmount,
          'is_win': winAmount > 0,
          'created_at': DateTime.now().toIso8601String(),
        }),
      );
    } catch (_) {}
  }

  void _showGameRecords() {
    final uid = Provider.of<UserProvider>(context, listen: false)
        .currentUser
        ?.uid ??
        '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GameRecordsSheet(uid: uid, gameId: _poolGameId),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ شفافية كاملة: لا scrim، لا خلفية سودا، لا اسم لعبة، لا كاس،
    //    ولا حتى دائرة داكنة للزر. الإغلاق بالرجوع / الضغط خارج الصندوق،
    //    والسجل بضغط مطوّل على منطقة غير مرئية أعلى اليمين.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: _controller)),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFC525)),
            ),
          Positioned(
            top: 30,
            right: 2,
            child: Opacity(
              opacity: 0.10, // شبه غير مرئي — ما يكسرش شفافية الشاشة
              child: IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 14),
                tooltip: 'إغلاق · ضغط مطوّل للسجل',
                onPressed: () => Navigator.pop(context),
                onLongPress: _showGameRecords,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// سجل مباراة اللعبة + ترتيب المتصدرين — يقرأ من game_bet_records
class _GameRecordsSheet extends StatefulWidget {
  final String uid;
  final String gameId;
  const _GameRecordsSheet({required this.uid, required this.gameId});

  @override
  State<_GameRecordsSheet> createState() => _GameRecordsSheetState();
}

class _GameRecordsSheetState extends State<_GameRecordsSheet> {
  bool _loading = true;
  List<Map<String, dynamic>> _myRecords = [];
  List<Map<String, dynamic>> _ranking = [];

  static Map<String, String> get _headers => {
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final base = SupabaseConfig.projectUrl;
      final results = await Future.wait([
        // سجلاتي الأخيرة
        SafeHttp.get(
          Uri.parse(
            '$base/rest/v1/game_bet_records'
            '?game_id=eq.${widget.gameId}&user_id=eq.${widget.uid}'
            '&select=bet_amount,win_amount,is_win,created_at'
            '&order=created_at.desc&limit=30',
          ),
          headers: _headers,
        ),
        // سجلات اللعبة الأخيرة لتجميع الترتيب
        SafeHttp.get(
          Uri.parse(
            '$base/rest/v1/game_bet_records'
            '?game_id=eq.${widget.gameId}'
            '&select=user_id,user_name,win_amount'
            '&order=created_at.desc&limit=2000',
          ),
          headers: _headers,
        ),
      ]);

      if (!mounted) return;
      final mine = jsonDecode(results[0].body);
      if (mine is List) {
        _myRecords = mine.whereType<Map<String, dynamic>>().toList();
      }

      final all = jsonDecode(results[1].body);
      if (all is List) {
        final totals = <String, Map<String, dynamic>>{};
        for (final row in all.whereType<Map<String, dynamic>>()) {
          final uid = row['user_id']?.toString() ?? '';
          if (uid.isEmpty) continue;
          final win = (row['win_amount'] as num?)?.toDouble() ?? 0;
          final entry = totals.putIfAbsent(uid, () => {
                'user_id': uid,
                'user_name': row['user_name']?.toString() ?? 'Player',
                'total': 0.0,
              });
          entry['total'] = (entry['total'] as double) + win;
        }
        final list = totals.values.toList()
          ..sort((a, b) =>
              (b['total'] as double).compareTo(a['total'] as double));
        _ranking = list.take(10).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Color(0xFF171226),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.emoji_events,
                    color: Color(0xFFFFC525), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: DText(
                    isAr ? 'سجل اللعبة والترتيب' : 'Game Records & Ranking',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          if (_loading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFFFC525)),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                children: [
                  _sectionTitle(isAr ? '🏆 المتصدرين' : '🏆 Top Players'),
                  if (_ranking.isEmpty)
                    _emptyText(isAr ? 'لا توجد نتائج بعد' : 'No results yet')
                  else
                    ..._ranking.asMap().entries.map(
                          (e) => _rankingTile(e.key + 1, e.value, isAr),
                        ),
                  const SizedBox(height: 16),
                  _sectionTitle(isAr ? '📜 آخر مبارياتي' : '📜 My Recent Games'),
                  if (_myRecords.isEmpty)
                    _emptyText(isAr ? 'لم تلعب بعد' : 'No games yet')
                  else
                    ..._myRecords.map((r) => _recordTile(r, isAr)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: DText(
          text,
          style: const TextStyle(
            color: Color(0xFFFFC525),
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  Widget _emptyText(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: DText(
          text,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      );

  Widget _rankingTile(int rank, Map<String, dynamic> p, bool isAr) {
    final medal = rank == 1
        ? '🥇'
        : rank == 2
            ? '🥈'
            : rank == 3
                ? '🥉'
                : '$rank';
    final total = (p['total'] as num?)?.toInt() ?? 0;
    final name = p['user_name']?.toString() ?? 'Player';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: DText(
              medal,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: DText(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          DText(
            '$total',
            style: const TextStyle(
              color: Color(0xFF00E676),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordTile(Map<String, dynamic> r, bool isAr) {
    final bet = (r['bet_amount'] as num?)?.toInt() ?? 0;
    final win = (r['win_amount'] as num?)?.toInt() ?? 0;
    final isWin = r['is_win'] == true;
    final dt = DateTime.tryParse(r['created_at']?.toString() ?? '');
    final time = dt == null
        ? ''
        : '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            isWin ? Icons.emoji_events : Icons.close,
            color: isWin ? const Color(0xFFFFC525) : Colors.white38,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DText(
                  isAr
                      ? 'رهان: $bet  →  ربح: $win'
                      : 'Bet: $bet  →  Win: $win',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (time.isNotEmpty)
                  DText(
                    time,
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
              ],
            ),
          ),
          DText(
            isWin ? '+$win' : '-$bet',
            style: TextStyle(
              color: isWin ? const Color(0xFF00E676) : Colors.redAccent,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
