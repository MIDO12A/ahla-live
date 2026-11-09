// lib/screens/room/widgets/sugarrush_game_dialog.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../config/r.dart';
import '../../../config/supabase_config.dart';
import '../../../providers/user_provider.dart';
import '../../../services/supabase_data_service.dart';
import '../../wallet/wallet_main_screen.dart';
import 'package:zero/core/dtext.dart';

class SugarRushGameDialog extends StatefulWidget {
  final String roomId;

  const SugarRushGameDialog({
    super.key,
    required this.roomId,
  });

  static Future<void> show(BuildContext context, {required String roomId}) {
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
          child: SugarRushGameDialog(roomId: roomId),
        ),
      ),
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

  // Room seats overlay (like the Ludo room view)
  Timer? _seatsTimer;
  List<Map<String, dynamic>> _seatPlayers = [];
  bool _showSeats = false;

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
    _startSeatsPolling();
  }

  @override
  void dispose() {
    _seatsTimer?.cancel();
    _localServer?.close(force: true);
    super.dispose();
  }

  void _startSeatsPolling() {
    _seatsTimer?.cancel();
    _refreshSeats();
    _seatsTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshSeats());
  }

  Future<void> _refreshSeats() async {
    try {
      final seatMap = await SupabaseDataService().getSeats(widget.roomId);
      if (seatMap == null || !mounted) return;
      final players = <Map<String, dynamic>>[];
      final entries = seatMap.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final e in entries) {
        final d = e.value;
        final uid = d['uid']?.toString() ?? '';
        if (uid.isEmpty || uid == 'null') continue;
        if (d['is_locked'] == true) continue;
        players.add({
          'seatIndex': e.key,
          'uid': uid,
          'name': d['name']?.toString() ?? '',
          'photoUrl': d['photo_url']?.toString() ?? '',
          'isMuted': d['is_muted'] == true,
        });
      }
      if (mounted) {
        setState(() => _seatPlayers = players);
      }
    } catch (_) {}
  }

  void _syncCoinsToGame() {
    if (!mounted) return;
    final coins = Provider.of<UserProvider>(context, listen: false)
            .currentUser
            ?.coins ??
        0;
    _controller.runJavaScript(
      'if (window.__sugarGame && window.__sugarGame.updateCoins) { window.__sugarGame.updateCoins($coins); }',
    );
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
        final customId = user?.customId.trim() ?? '';
        final rawUid = user?.uid ?? '10001';
        final numericId = int.tryParse(customId) ??
            int.tryParse(rawUid) ??
            (int.tryParse(rawUid.replaceAll(RegExp(r'\D'), '')) ?? 10001);
        final playerIdStr = numericId.toString();

        final userName = (user?.name.isNotEmpty ?? false) ? user!.name : 'Player';
        final userAvatar = user?.photoUrl ?? '';
        final coins = user?.coins ?? 50000;

        final queryParams = {
          'uid': playerIdStr,
          'playerId': playerIdStr,
          'uuid': user?.uid ?? '',
          'name': userName,
          'avatar': userAvatar,
          'coins': coins.toString(),
          'ticket': 'ticket_$playerIdStr',
          'roomId': widget.roomId,
          'gameType': '1',
          'isProd': '0',
          'platform': 'android',
          'os': 'android',
          'DOMAIN': '127.0.0.1',
          'containerUrl': '127.0.0.1',
          'serverAddress': '127.0.0.1',
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

    final customId = user?.customId.trim() ?? '';
    final rawUid = user?.uid ?? '10001';
    final numericId = int.tryParse(customId) ??
        int.tryParse(rawUid) ??
        (int.tryParse(rawUid.replaceAll(RegExp(r'\D'), '')) ?? 10001);
    final playerIdStr = numericId.toString();

    final userName = (user?.name.isNotEmpty ?? false) ? user!.name : 'Player';
    final userAvatar = user?.photoUrl ?? '';
    final coins = user?.coins ?? 50000;

    final safeName = userName.replaceAll('"', '\\"');
    final js =
        'if (window.__sugarGame) { window.__sugarGame.initUser("$playerIdStr", "$safeName", "$userAvatar", $coins, "${widget.roomId}", $_poolWinRate, "${user?.uid ?? ''}"); }';

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

      if (action == 'charge' || action == 'recharge' || action == 'openChargePage') {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const WalletMainScreen()),
          );
        }
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
    if (user.coins < betAmount) return; // blocked client-side; JS already rejected the spin

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
      _syncCoinsToGame();
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
      _syncCoinsToGame();
    } catch (e) {
      debugPrint('[SugarRush] Process spin outcome error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: WebViewWidget(controller: _controller),
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
                      DText(
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
            // Room seats toggle (players on mic, like the room view)
            Positioned(
              top: 12,
              left: 16,
              child: GestureDetector(
                onTap: () => setState(() => _showSeats = !_showSeats),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _seatPlayers.isNotEmpty
                          ? const Color(0xFFFFD700)
                          : Colors.white24,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.groups, color: Colors.white, size: 16),
                      const SizedBox(width: 5),
                      Text(
                        '${_seatPlayers.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_showSeats)
              Positioned(
                left: 12,
                right: 12,
                bottom: 24,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 160),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: _seatPlayers.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: DText(
                            'لا يوجد لاعبين على المقاعد',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _seatPlayers.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
                          itemBuilder: (context, i) {
                            final p = _seatPlayers[i];
                            final photo = p['photoUrl']?.toString() ?? '';
                            return ListTile(
                              dense: true,
                              leading: Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: const Color(0xFF2A2040),
                                    backgroundImage: photo.isNotEmpty ? R.cachedImage(photo) : null,
                                    child: photo.isEmpty
                                        ? const Icon(Icons.person, size: 16, color: Colors.white54)
                                        : null,
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: p['isMuted'] == true ? Colors.red : const Color(0xFF00E676),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.black, width: 1),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              title: DText(
                                p['name']?.toString() ?? '',
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: DText(
                                'مقعد ${((p['seatIndex'] as num?)?.toInt() ?? 0) + 1}',
                                style: const TextStyle(color: Colors.white38, fontSize: 10),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
                                ),
                                child: const DText(
                                  'يلعب',
                                  style: TextStyle(color: Color(0xFFFFD700), fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
          ],
        ),
    );
  }
}
