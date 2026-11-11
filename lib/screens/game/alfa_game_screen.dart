import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../config/supabase_config.dart';
import '../../providers/user_provider.dart';
import '../../services/safe_http.dart';
import 'package:zero/core/dtext.dart';

/// لعبة ألفا (Alfa Lucky 777) — لعبة H5 مستضافة على Vercel
/// تُفتح داخل WebView مع تمرير بيانات المستخدم كـ query params:
/// user_id, nickname, coins, avatar, win_rate, chips
class AlfaGameScreen extends StatefulWidget {
  const AlfaGameScreen({super.key});

  static const String _gamePath =
      'https://alfa-game-rosy.vercel.app/play/alfa_key_goog_KuMTPgPJ/fe-game-lucky777';
  static const String _allowedHost = 'alfa-game-rosy.vercel.app';
  static const double _defaultWinRate = 75.0;

  static const List<String> _chips = [
    '1000',
    '5000',
    '10000',
    '50000',
    '500000',
  ];

  /// تُعرض بنصف الشاشة كصندوق سفلي — نفس نمط لعبة Sugar Rush
  static Future<void> show(BuildContext context) {
    final sheetHeight = MediaQuery.of(context).size.height * 0.58;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SizedBox(
        height: sheetHeight,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: const AlfaGameScreen(),
        ),
      ),
    );
  }

  @override
  State<AlfaGameScreen> createState() => _AlfaGameScreenState();
}

class _AlfaGameScreenState extends State<AlfaGameScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  double _winRate = AlfaGameScreen._defaultWinRate;

  static Map<String, String> get _headers => {
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
      };

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _winRate = await _loadWinRate();
    if (!mounted) return;

    final user = Provider.of<UserProvider>(context, listen: false).currentUser;
    final params = <String, String>{
      'user_id': user?.uid ?? '',
      'nickname': user?.name ?? '',
      'coins': (user?.coins ?? 0).toString(),
      'avatar': user?.photoUrl ?? '',
      'win_rate': _winRate.toString(),
      'chips': AlfaGameScreen._chips.join(','),
    };
    final url = Uri.parse(AlfaGameScreen._gamePath)
        .replace(queryParameters: params)
        .toString();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            // نسمح فقط بالتنقل داخل نطاق اللعبة الموثوق
            if (uri != null &&
                uri.scheme == 'https' &&
                uri.host == AlfaGameScreen._allowedHost) {
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
      ..loadRequest(Uri.parse(url));
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

  void _onJsMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      switch (data['action']) {
        case 'closeWebView':
        case 'navigate_back':
          if (mounted) Navigator.pop(context);
          break;
        case 'showLoading':
          if (mounted) setState(() => _loading = true);
          break;
        case 'closeLoading':
          if (mounted) setState(() => _loading = false);
          break;
        default:
          break;
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // شريط علوي مضغوط داخل الصندوق — عنوان + زر إغلاق
            Container(
              height: 40,
              padding: EdgeInsets.symmetric(horizontal: isAr ? 4 : 12, vertical: 4),
              child: Row(
                children: [
                  if (isAr)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                      onPressed: () => Navigator.pop(context),
                    )
                  else
                    const Spacer(),
                  Expanded(
                    child: DText(
                      isAr ? 'لعبة الحظ 777' : 'Lucky 777',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isAr)
                    const Spacer()
                  else
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                      onPressed: () => Navigator.pop(context),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_loading)
                    const Center(
                      child: CircularProgressIndicator(color: Color(0xFFFFC525)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
