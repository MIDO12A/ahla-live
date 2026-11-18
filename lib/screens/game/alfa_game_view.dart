// =============================================================================
//  Alfa Game Hub - Production-Ready Flutter Integration Widget (alfa_game_view.dart)
//  ملف الربط التلقائي الشامل لألعاب Alfa Game داخل تطبيقات فلاتر (Android / iOS)
// =============================================================================
//
//  [العربية]: ويدجت فلاتر كامل وتلقائي 100% لدمج وتشغيل ألعاب منصة Alfa Game بسطر واحد!
//  يقوم بسحب وتوليد كل شيء تلقائياً (المعرف، الاسم، الصورة، والرصيد) دون الحاجة
//  لأن يكتب المبرمج أي كود إضافي!
//
//  [English]: 1-line complete auto-discovery Flutter widget for Alfa Game Hub.
//  Automatically generates and manages player ID, name, avatar, coins, and sync!
//
// -----------------------------------------------------------------------------
//  1. التبعيات المطلوبة في ملف pubspec.yaml (Dependencies):
// -----------------------------------------------------------------------------
//  dependencies:
//    flutter:
//      sdk: flutter
//    webview_flutter: ^4.10.0
//
// -----------------------------------------------------------------------------
//  2. طريقة الاستدعاء التلقائية الكاملة (سطر كود واحد فقط! ⚡):
// -----------------------------------------------------------------------------
//  AlfaGame.open(context, 'fe-game-lucky777');
//
//  * يقوم هذا السطر بسحب مفتاح التطبيق، وتعيين معرف اللاعب، ورصيد الكوينز،
//    وفتح اللعبة بنصف شاشة، ومزامنة الأرباح والخسائر تلقائياً بالكامل!
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/session_token_store.dart';

/// ============================================================================
/// [AlfaGame] - المحرك التلقائي الشامل (سطر واحد لتشغيل كل شيء تلقائياً)
/// ============================================================================
class AlfaGame {
  /// مفتاح التطبيق الخاص بمنصتك (مدمج تلقائياً)
  static String defaultAppKey = 'alfa_key_app_ahal_377';

  /// رابط سيرفر المنصة
  static String defaultServerUrl = 'https://alfanexso.tech';

  /// سجل ألعاب المزوّد — يسمح بـ AlfaGame.open(context, 'greedy')
  /// بدل كتابة المعرّف الكامل. مطابق لقائمة alfa_config.json.
  static final Map<String, Map<String, dynamic>> gameRegistry = {
    'super77': {'id': 'fe-game-super77', 'name': 'سوبر 77 VIP', 'mode': 'half'},
    'lucky777': {'id': 'fe-game-lucky777', 'name': 'Lucky 777', 'mode': 'half'},
    'greedy': {'id': 'fe-game-greedy', 'name': 'لعبة الطماع', 'mode': 'half'},
    'crazy_fruit': {'id': 'fe-game-crazy-fruit', 'name': 'فواكه كاش', 'mode': 'full'},
    'sudan': {'id': 'fe-game-sudan', 'name': 'سباق السودان', 'mode': 'half'},
    'gift_spin': {'id': 'fe-game-giftspin', 'name': 'عجلة الهدايا VIP', 'mode': 'half'},
    'ludo': {'id': 'fe-game-cocos-ludo', 'name': 'لودو كينغ', 'mode': 'full'},
  };

  /// تحميل إعدادات alfa_config.json (إن وُجدت) — يحدّث السيرفر/المفتاح/الألعاب.
  static void configureFromJson(Map<String, dynamic> json) {
    if (json['serverUrl'] is String) defaultServerUrl = json['serverUrl'] as String;
    if (json['appKey'] is String) defaultAppKey = json['appKey'] as String;
    final games = json['games'];
    if (games is Map) {
      games.forEach((k, v) {
        if (v is Map<String, dynamic>) gameRegistry[k] = v;
      });
    }
  }

  // ذاكرة محلية تلقائية للاعب على هذا الجهاز
  static String? _cachedPlayerId;
  static int _cachedCoins = 1000000;

  /// --------------------------------------------------------------------------
  /// الدالة السحرية للتشغيل التلقائي بالكامل (Auto-Launch with 1 Line):
  ///
  /// مثال الاستدعاء الفوري دون أي إعدادات إضافية:
  /// ```dart
  /// AlfaGame.open(context, 'fe-game-lucky777');
  /// ```
  /// --------------------------------------------------------------------------
  static Future<void> open(
    BuildContext context,
    String gameId, {
    String? playerId,
    String? uid,
    String? token,
    String? roomId,
    String? playerName,
    String? avatarUrl,
    int? coins,
    int winRate = 75,
    String viewMode = 'half',
    String? appKey,
    void Function(int newBalance, int diff)? onBalanceChanged,
  }) async {
    // 0. حل معرّف اللعبة المختصر تلقائياً (مثال: greedy → fe-game-greedy)
    String resolvedGameId = gameId;
    String effectiveViewMode = viewMode;
    final info = gameRegistry[gameId];
    if (info != null) {
      resolvedGameId = (info['id'] ?? gameId) as String;
      if (info['mode'] is String) effectiveViewMode = info['mode'] as String;
    }

    // 1. توليد أو استرجاع معرف اللاعب تلقائياً
    if (playerId != null && playerId.isNotEmpty) {
      _cachedPlayerId = playerId;
    } else if (_cachedPlayerId == null) {
      final nowStr = DateTime.now().millisecondsSinceEpoch.toString();
      _cachedPlayerId = 'player_' + nowStr.substring(nowStr.length - 6);
    }
    final effectiveId = _cachedPlayerId!;

    // ✅ معاملات بروتوكول StyeParty المطلوبة لتوقيع الـ callbacks:
    //    uid = معرف المستخدم في تطبيقنا، token = توكن الجلسة،
    //    roomId = الغرفة الحالية (قد تكون فارغة خارج الغرف).
    final effectiveUid = (uid != null && uid.isNotEmpty) ? uid : effectiveId;
    final effectiveToken = (token != null && token.isNotEmpty)
        ? token
        : (SessionTokenStore.token ??
            'token_${effectiveUid}_${DateTime.now().millisecondsSinceEpoch}');
    final effectiveRoomId = roomId ?? '';

    // 2. تعيين اسم اللاعب تلقائياً
    final effectiveName = playerName ??
        'لاعب #' + effectiveId.replaceAll('player_', '');

    // 3. تعيين رصيد الكوينز تلقائياً
    if (coins != null) {
      _cachedCoins = coins;
    }
    final effectiveCoins = _cachedCoins;

    final effectiveAppKey = appKey ?? defaultAppKey;

    if (effectiveViewMode == 'half') {
      await AlfaGameView.showAsBottomSheet(
        context,
        serverUrl: defaultServerUrl,
        appKey: effectiveAppKey,
        gameId: resolvedGameId,
        playerId: effectiveId,
        uid: effectiveUid,
        token: effectiveToken,
        roomId: effectiveRoomId,
        playerName: effectiveName,
        avatarUrl: avatarUrl ?? '',
        initialCoins: effectiveCoins,
        winRate: winRate,
        onBalanceChanged: (newBalance, diff) {
          _cachedCoins = newBalance;
          onBalanceChanged?.call(newBalance, diff);
        },
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            body: SafeArea(
              child: AlfaGameView(
                serverUrl: defaultServerUrl,
                appKey: effectiveAppKey,
                gameId: resolvedGameId,
                playerId: effectiveId,
                uid: effectiveUid,
                token: effectiveToken,
                roomId: effectiveRoomId,
                playerName: effectiveName,
                avatarUrl: avatarUrl ?? '',
                initialCoins: effectiveCoins,
                winRate: winRate,
                viewMode: 'full',
                onBalanceChanged: (newBalance, diff) {
                  _cachedCoins = newBalance;
                  onBalanceChanged?.call(newBalance, diff);
                },
                onGameExit: () => Navigator.pop(context),
              ),
            ),
          ),
        ),
      );
    }
  }
}

/// ============================================================================
/// [AlfaGameView] - الويدجت الداخلي المتقدم لعرض اللعبة وإدارة جلسة الـ WebView
/// ============================================================================
class AlfaGameView extends StatefulWidget {
  final String serverUrl;
  final String appKey;
  final String gameId;
  final String playerId;
  final String uid;
  final String token;
  final String roomId;
  final String playerName;
  final String avatarUrl;
  final int initialCoins;
  final int winRate;
  final String viewMode;
  final void Function(int newBalance, int diff)? onBalanceChanged;
  final VoidCallback? onGameExit;

  const AlfaGameView({
    Key? key,
    this.serverUrl = 'https://alfanexso.tech',
    required this.appKey,
    required this.gameId,
    required this.playerId,
    this.uid = '',
    this.token = '',
    this.roomId = '',
    required this.playerName,
    this.avatarUrl = '',
    required this.initialCoins,
    this.winRate = 75,
    this.viewMode = 'half',
    this.onBalanceChanged,
    this.onGameExit,
  }) : super(key: key);

  /// استدعاء كنافذة سفلية نصف شاشة (Bottom Sheet Modal 53%)
  static Future<void> showAsBottomSheet(
    BuildContext context, {
    String serverUrl = 'https://alfanexso.tech',
    required String appKey,
    required String gameId,
    required String playerId,
    String uid = '',
    String token = '',
    String roomId = '',
    required String playerName,
    String avatarUrl = '',
    required int initialCoins,
    int winRate = 75,
    void Function(int newBalance, int diff)? onBalanceChanged,
    VoidCallback? onGameExit,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (ctx) {
        final screenHeight = MediaQuery.of(context).size.height;
        return Container(
          height: screenHeight * 0.53, // 53% ارتفاع مثالي لبث المحادثة والدردشة
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // مقبض النافذة
              Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                width: 44,
                height: 4.5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Expanded(
                child: AlfaGameView(
                  serverUrl: serverUrl,
                  appKey: appKey,
                  gameId: gameId,
                  playerId: playerId,
                  uid: uid,
                  token: token,
                  roomId: roomId,
                  playerName: playerName,
                  avatarUrl: avatarUrl,
                  initialCoins: initialCoins,
                  winRate: winRate,
                  viewMode: 'half',
                  onBalanceChanged: onBalanceChanged,
                  onGameExit: onGameExit ?? () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  State<AlfaGameView> createState() => _AlfaGameViewState();
}

class _AlfaGameViewState extends State<AlfaGameView> {
  late final WebViewController _controller;
  bool _isLoading = true;
  late int _currentCoins;

  @override
  void initState() {
    super.initState();
    _currentCoins = widget.initialCoins;
    _initWebView();
  }

  String _buildGameUrl() {
    final cleanHost = widget.serverUrl.replaceAll(RegExp(r'/+$'), '');
    final effectiveUid = widget.uid.isNotEmpty ? widget.uid : widget.playerId;
    final effectiveToken = widget.token.isNotEmpty
        ? widget.token
        : (SessionTokenStore.token ??
            'token_${effectiveUid}_${DateTime.now().millisecondsSinceEpoch}');
    final uri = Uri.parse('$cleanHost/play/${widget.appKey}/${widget.gameId}').replace(
      queryParameters: {
        // ✅ معاملات StyeParty الرسمية — نفس رابط الربط المعطى،
        //    وهي التي يوقّع عليها السيرفر في callbacks.
        'gameId': widget.gameId,
        'uid': effectiveUid,
        'token': effectiveToken,
        'roomId': widget.roomId,
        'view_mode': widget.viewMode,
        // معاملات التوافق مع المنصة القديمة (لا تؤثر على التوقيع)
        'user_id': widget.playerId,
        'name': widget.playerName,
        'avatar': widget.avatarUrl.isNotEmpty
            ? widget.avatarUrl
            : '$cleanHost/public/emojis/emoji_rich.png',
        'coins': _currentCoins.toString(),
        'win_rate': widget.winRate.toString(),
        'app_key': widget.appKey,
      },
    );
    return uri.toString();
  }

  void _initWebView() {
    final gameUrl = _buildGameUrl();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F172A))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
            _injectSecurityAndBridge();
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('[AlfaGame] WebView error: ${error.description}');
          },
          onNavigationRequest: (NavigationRequest request) {
            if (!request.url.contains(widget.serverUrl) &&
                !request.url.startsWith('about:blank')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..addJavaScriptChannel(
        'AlfaBridgeChannel',
        onMessageReceived: (JavaScriptMessage message) {
          _handleJavaScriptMessage(message.message);
        },
      )
      ..loadRequest(Uri.parse(gameUrl));
  }

  void _injectSecurityAndBridge() {
    _controller.runJavaScript('''
      window.addEventListener('contextmenu', function(e) { e.preventDefault(); });
      window.addEventListener('message', function(event) {
        if (event && event.data && window.AlfaBridgeChannel) {
          try {
            var payload = typeof event.data === 'string' ? event.data : JSON.stringify(event.data);
            window.AlfaBridgeChannel.postMessage(payload);
          } catch(e) {}
        }
      });
      console.log('[AlfaGame] Auto Bridge Active');
    ''');
  }

  void _handleJavaScriptMessage(String rawMessage) {
    try {
      final dynamic data = jsonDecode(rawMessage);
      if (data is! Map<String, dynamic>) return;

      final event = data['event'] ?? data['action'] ?? data['type'] ?? '';

      // حدث تحديث الرصيد التلقائي (فوز أو خسارة أو رهان ومزامنة المحفظة)
      if (event == 'update_balance' ||
          event == 'coins_changed' ||
          event == 'balance_update' ||
          event == 'ALFA_USER_UPDATE') {
        int? parsedCoins;
        int parsedDiff = 0;

        if (data['user'] is Map) {
          final u = data['user'] as Map;
          if (u['coins'] != null && u['coins'] is num) {
            parsedCoins = (u['coins'] as num).toInt();
          }
        }
        if (parsedCoins == null) {
          final rawCoins = data['coins'] ?? data['balance'];
          if (rawCoins != null && rawCoins is num) {
            parsedCoins = rawCoins.toInt();
          }
        }
        final rawDiff = data['diff'] ?? data['change'];
        if (rawDiff != null && rawDiff is num) {
          parsedDiff = rawDiff.toInt();
        }

        final newCoins = parsedCoins ?? _currentCoins;
        if (newCoins != _currentCoins || parsedDiff != 0) {
          if (mounted) {
            setState(() => _currentCoins = newCoins);
          }
          widget.onBalanceChanged?.call(newCoins, parsedDiff);
        }
      }

      // حدث الخروج من اللعبة
      if (event == 'exit_game' || event == 'close' || event == 'back') {
        widget.onGameExit?.call();
      }
    } catch (e) {
      debugPrint('[AlfaGame] Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          Container(
            color: const Color(0xFF0F172A),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00F2FE)),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'جاري تشغيل اللعبة تلقائياً... 🎮',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
