// lib/screens/room/widgets/sugarrush_game_dialog.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../config/supabase_config.dart';
import '../../../providers/user_provider.dart';
import '../../../services/supabase_data_service.dart';

class SugarRushGameDialog extends StatefulWidget {
  final String roomId;

  const SugarRushGameDialog({
    super.key,
    required this.roomId,
  });

  static Future<void> show(BuildContext context, {required String roomId}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (_) => SugarRushGameDialog(roomId: roomId),
    );
  }

  @override
  State<SugarRushGameDialog> createState() => _SugarRushGameDialogState();
}

class _SugarRushGameDialogState extends State<SugarRushGameDialog> {
  late final WebViewController _controller;
  HttpServer? _localServer;
  int? _localPort;
  bool _isLoading = true;
  double _poolWinRate = 75.0;

  static const String _baseUrl = SupabaseConfig.projectUrl;
  static const String _anonKey = SupabaseConfig.anonKey;

  static Map<String, String> get _headers => {
        'apikey': _anonKey,
        'Authorization': 'Bearer $_anonKey',
        'Content-Type': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    _loadPoolConfig();
    _initWebViewController();
    _startLocalServer();
  }

  @override
  void dispose() {
    _localServer?.close(force: true);
    super.dispose();
  }

  Future<void> _loadPoolConfig() async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/game_jackpot_pool?id=eq.sugarrush&select=win_rate,is_active');
      final res = await http.get(url, headers: _headers);

      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        if (list.isNotEmpty && mounted) {
          final first = list.first as Map<String, dynamic>;
          final winRate = first['win_rate'];
          if (winRate != null) {
            setState(() {
              _poolWinRate = (winRate as num).toDouble();
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[SugarRush] Error fetching pool config: $e');
    }
  }

  Future<void> _startLocalServer() async {
    try {
      _localServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _localPort = _localServer!.port;
      debugPrint('[SugarRush] Local asset server listening on port: $_localPort');

      _localServer!.listen((HttpRequest request) async {
        try {
          var path = request.uri.path;
          if (path.isEmpty || path == '/') {
            path = '/index.html';
          }
          if (path.startsWith('/')) {
            path = path.substring(1);
          }

          final assetKey = 'assets/games/sugarrush/$path';
          ByteData byteData;
          try {
            byteData = await rootBundle.load(assetKey);
          } catch (_) {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
            return;
          }

          final bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);

          final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
          final contentType = switch (ext) {
            'html' => ContentType.html,
            'js' => ContentType('application', 'javascript', charset: 'utf-8'),
            'json' => ContentType.json,
            'css' => ContentType('text', 'css', charset: 'utf-8'),
            'png' => ContentType('image', 'png'),
            'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
            'webp' => ContentType('image', 'webp'),
            'gif' => ContentType('image', 'gif'),
            'mp3' => ContentType('audio', 'mpeg'),
            'ogg' => ContentType('audio', 'ogg'),
            'wav' => ContentType('audio', 'wav'),
            'wasm' => ContentType('application', 'wasm'),
            _ => ContentType.binary,
          };

          request.response.headers.contentType = contentType;
          request.response.headers.add('Access-Control-Allow-Origin', '*');
          request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
          request.response.headers.add('Access-Control-Allow-Headers', '*');
          request.response.add(bytes);
          await request.response.close();
        } catch (e) {
          try {
            request.response.statusCode = HttpStatus.internalServerError;
            await request.response.close();
          } catch (_) {}
        }
      });

      if (mounted) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final user = userProvider.currentUser;
        final userId = user?.uid ?? '10001';
        final userName = (user?.name.isNotEmpty ?? false) ? user!.name : 'Player';
        final userAvatar = user?.photoUrl ?? '';
        final coins = user?.coins ?? 50000;

        final queryParams = {
          'uid': userId,
          'playerId': userId,
          'name': userName,
          'avatar': userAvatar,
          'coins': coins.toString(),
          'ticket': 'ticket_$userId',
          'roomId': widget.roomId,
          'gameType': '1',
          'isProd': '0',
          'platform': 'android',
          'os': 'android',
          'DOMAIN': '127.0.0.1',
          'appDomain': '127.0.0.1',
          'language': 'en',
          'winRate': _poolWinRate.toString(),
        };

        final localUri = Uri.http('127.0.0.1:$_localPort', '/index.html', queryParams);
        debugPrint('[SugarRush] Loading game with query params: $localUri');
        _controller.loadRequest(localUri);
      }
    } catch (e) {
      debugPrint('[SugarRush] Error starting local server, fallback to asset: $e');
      if (mounted) {
        _controller.loadFlutterAsset('assets/games/sugarrush/index.html');
      }
    }
  }

  void _initWebViewController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setOnConsoleMessage((message) {
        debugPrint('[SugarRush Console] ${message.message}');
      })
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: _handleBridgeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (mounted) {
              setState(() => _isLoading = false);
              _injectUserData();
            }
          },
          onWebResourceError: (error) {
            debugPrint('[SugarRush] WebResourceError: ${error.description}');
          },
        ),
      );
  }

  void _injectUserData() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;

    final userId = user?.uid ?? '10001';
    final userName = (user?.name.isNotEmpty ?? false) ? user!.name : 'Player';
    final userAvatar = user?.photoUrl ?? '';
    final coins = user?.coins ?? 50000;

    final safeName = userName.replaceAll('"', '\\"');
    final js =
        'if (window.__sugarGame) { window.__sugarGame.initUser("$userId", "$safeName", "$userAvatar", $coins, "${widget.roomId}", $_poolWinRate); }';

    _controller.runJavaScript(js);
  }

  Future<void> _handleBridgeMessage(JavaScriptMessage message) async {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final action = data['action'] as String?;

      if (action == 'close') {
        if (mounted) Navigator.of(context).pop();
        return;
      }

      if (action == 'bet') {
        final betAmount = (data['betMoney'] as num?)?.toInt() ?? 0;
        await _processBetDeduction(betAmount);
      } else if (action == 'spin_result') {
        final betAmount = (data['betMoney'] as num?)?.toInt() ?? 0;
        final winAmount = (data['winMoney'] as num?)?.toInt() ?? 0;
        final isWin = data['isWin'] as bool? ?? false;
        await _processSpinOutcome(betAmount, winAmount, isWin);
      }
    } catch (e) {
      debugPrint('[SugarRush] Bridge message error: $e');
    }
  }

  Future<void> _processBetDeduction(int betAmount) async {
    if (betAmount <= 0) return;
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user == null) return;

    try {
      userProvider.deductCoinsLocally(betAmount);
      final newCoins = (user.coins - betAmount).clamp(0, 999999999);

      await SupabaseDataService().updateUser(user.uid, {'coins': newCoins});

      final rpcUrl = Uri.parse('$_baseUrl/rest/v1/rpc/increment_game_pool_balance');
      final rpcRes = await http.post(
        rpcUrl,
        headers: _headers,
        body: jsonEncode({
          'p_game_id': 'sugarrush',
          'p_amount': betAmount,
        }),
      );

      if (rpcRes.statusCode != 200 && rpcRes.statusCode != 204) {
        final patchUrl = Uri.parse('$_baseUrl/rest/v1/game_jackpot_pool?id=eq.sugarrush');
        await http.patch(
          patchUrl,
          headers: _headers,
          body: jsonEncode({'updated_at': DateTime.now().toIso8601String()}),
        );
      }
    } catch (e) {
      debugPrint('[SugarRush] Process bet deduction error: $e');
    }
  }

  Future<void> _processSpinOutcome(int betAmount, int winAmount, bool isWin) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user == null) return;

    try {
      if (winAmount > 0) {
        userProvider.addCoinsLocally(winAmount);
        final newCoins = user.coins + winAmount;

        await SupabaseDataService().updateUser(user.uid, {'coins': newCoins});

        final rpcUrl = Uri.parse('$_baseUrl/rest/v1/rpc/increment_game_pool_balance');
        await http.post(
          rpcUrl,
          headers: _headers,
          body: jsonEncode({
            'p_game_id': 'sugarrush',
            'p_amount': -winAmount,
          }),
        );
      }

      final betRecordUrl = Uri.parse('$_baseUrl/rest/v1/game_bet_records');
      await http.post(
        betRecordUrl,
        headers: _headers,
        body: jsonEncode({
          'game_id': 'sugarrush',
          'user_id': user.uid,
          'room_id': widget.roomId,
          'user_name': user.name.isNotEmpty ? user.name : 'Player',
          'bet_amount': betAmount,
          'win_amount': winAmount,
          'net_result': winAmount - betAmount,
          'is_win': isWin,
          'created_at': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('[SugarRush] Process spin outcome error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.85),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: WebViewWidget(controller: _controller),
                  ),
                ),
              ),
            ),
            if (_isLoading)
              Container(
                color: Colors.black,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF3366)),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'جاري تشغيل لعبة Sugar Rush...',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              top: 12,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 24),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
