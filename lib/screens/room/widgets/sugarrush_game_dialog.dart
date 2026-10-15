// lib/screens/room/widgets/sugarrush_game_dialog.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../providers/user_provider.dart';
import '../../../core/network/supabase_service.dart';

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
  bool _isLoading = true;
  double _poolWinRate = 75.0;

  @override
  void initState() {
    super.initState();
    _loadPoolConfig();
    _initWebViewController();
  }

  Future<void> _loadPoolConfig() async {
    try {
      final res = await SupabaseService.client
          .from('game_jackpot_pool')
          .select('win_rate, is_active')
          .eq('id', 'sugarrush')
          .maybeSingle();

      if (res != null && mounted) {
        final winRate = res['win_rate'];
        if (winRate != null) {
          setState(() {
            _poolWinRate = (winRate as num).toDouble();
          });
        }
      }
    } catch (e) {
      debugPrint('[SugarRush] Error fetching pool config: $e');
    }
  }

  void _initWebViewController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
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
            debugPrint('[SugarRush] WebResourceError: ' + error.description);
          },
        ),
      )
      ..loadFlutterAsset('assets/games/sugarrush/index.html');
  }

  void _injectUserData() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;

    final userId = user?.id ?? '10001';
    final userName = user?.displayName ?? user?.name ?? 'Player';
    final userAvatar = user?.photoUrl ?? user?.avatar ?? '';
    final coins = user?.coins ?? 50000;

    final safeName = userName.replaceAll('"', '\\\"');
    final js = 'if (window.__sugarGame) { window.__sugarGame.initUser("' + userId + '", "' + safeName + '", "' + userAvatar + '", ' + coins.toString() + ', "' + widget.roomId + '", ' + _poolWinRate.toString() + '); }';

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
    final user = userProvider.user;
    if (user == null) return;

    try {
      final currentCoins = user.coins ?? 0;
      final newCoins = (currentCoins - betAmount).clamp(0, double.infinity).toInt();

      await SupabaseService.client
          .from('users')
          .update({'coins': newCoins})
          .eq('id', user.id);

      userProvider.updateUser(user.copyWith(coins: newCoins));

      await SupabaseService.client.rpc('increment_game_pool_balance', params: {
        'p_game_id': 'sugarrush',
        'p_amount': betAmount,
      }).catchError((_) {
        return SupabaseService.client
            .from('game_jackpot_pool')
            .update({'updated_at': DateTime.now().toIso8601String()})
            .eq('id', 'sugarrush');
      });
    } catch (e) {
      debugPrint('[SugarRush] Process bet deduction error: $e');
    }
  }

  Future<void> _processSpinOutcome(int betAmount, int winAmount, bool isWin) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    if (user == null) return;

    try {
      if (winAmount > 0) {
        final currentCoins = user.coins ?? 0;
        final newCoins = currentCoins + winAmount;

        await SupabaseService.client
            .from('users')
            .update({'coins': newCoins})
            .eq('id', user.id);

        userProvider.updateUser(user.copyWith(coins: newCoins));

        await SupabaseService.client.rpc('increment_game_pool_balance', params: {
          'p_game_id': 'sugarrush',
          'p_amount': -winAmount,
        }).catchError((_) => null);
      }

      await SupabaseService.client.from('game_bet_records').insert({
        'game_id': 'sugarrush',
        'user_id': user.id,
        'room_id': widget.roomId,
        'user_name': user.displayName ?? user.name ?? 'Player',
        'bet_amount': betAmount,
        'win_amount': winAmount,
        'net_result': winAmount - betAmount,
        'is_win': isWin,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[SugarRush] Process spin outcome error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.85),
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
                  color: Colors.black.withOpacity(0.6),
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
