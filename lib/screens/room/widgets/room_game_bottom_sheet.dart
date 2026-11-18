import 'dart:async';
import 'package:flutter/material.dart';
import '../../../config/r.dart';
import '../../../services/dynamic_config_service.dart';
import 'sugarrush_game_dialog.dart';
import '../../game/alfa_game_screen.dart';
import '../../game/game_teaming_screen.dart';
import '../../../services/network_ping_service.dart';
import 'package:zero/core/dtext.dart';

class RoomGameBottomSheet extends StatefulWidget {
  final String roomId;
  final void Function(String gameKey, String gameName)? onGameSelect;

  const RoomGameBottomSheet({
    super.key,
    required this.roomId,
    this.onGameSelect,
  });

  static Future<void> show(BuildContext context, {
    required String roomId,
    void Function(String gameKey, String gameName)? onGameSelect,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RoomGameBottomSheet(
        roomId: roomId,
        onGameSelect: onGameSelect,
      ),
    );
  }

  @override
  State<RoomGameBottomSheet> createState() => _RoomGameBottomSheetState();
}

class _RoomGameBottomSheetState extends State<RoomGameBottomSheet>
    with SingleTickerProviderStateMixin {
  late final ScrollController _broadcastScrollController;
  Timer? _marqueeTimer;

  static const List<Map<String, String>> _games = [
    {
      'key': 'sugarrush',
      'name_ar': 'Sugar Rush',
      'name_en': 'Sugar Rush',
      'icon': 'assets/images/icon_game_fuiter.png',
      'hot': 'true',
    },
    {
      'key': 'ludo',
      'name_ar': 'لودو',
      'name_en': 'Ludo',
      'icon': 'assets/images/icon_game_center_ludo.png',
      'hot': 'true',
      'platform': 'alfanexso',
      'game_id': 'fe-game-cocos-ludo',
      'pool_id': 'cocos_ludo',
      'view_mode': 'full',
    },
    {
      'key': 'crazy_fruit',
      'name_ar': 'الفواكه المجنونة',
      'name_en': 'Crazy Fruit',
      'icon': 'assets/images/icon_game_crazy_fruit.png',
      'hot': 'false',
      'platform': 'alfanexso',
      'game_id': 'fe-game-crazy-fruit',
      'pool_id': 'crazy_fruit',
      'view_mode': 'full',
    },
    {
      'key': 'greedy',
      'name_ar': 'لعبة الطماع',
      'name_en': 'Greedy Wolves',
      'icon': 'assets/images/icon_game_greedy.png',
      'hot': 'false',
      'platform': 'alfanexso',
      'game_id': 'fe-game-greedy',
      'pool_id': 'greedy',
      'view_mode': 'half',
    },
    {
      'key': 'super_77',
      'name_ar': 'سوبر 77',
      'name_en': 'Super 77',
      'icon': 'assets/images/icon_hu_game_777.png',
      'hot': 'true',
      'platform': 'alfanexso',
      'game_id': 'fe-game-super77',
      'pool_id': 'super77',
      'view_mode': 'half',
    },
    {
      'key': 'lucky_777',
      'name_ar': '777 الحظ',
      'name_en': 'Lucky 777',
      'icon': 'assets/images/icon_hu_game_777.png',
      'hot': 'true',
      'platform': 'alfanexso',
      'game_id': 'fe-game-lucky777',
      'pool_id': 'lucky777',
      'view_mode': 'half',
    },
    {
      'key': 'sudan',
      'name_ar': 'سباق السودان',
      'name_en': 'Sudan Race',
      'icon': 'assets/images/icon_game_sudan.png',
      'hot': 'false',
      'platform': 'alfanexso',
      'game_id': 'fe-game-sudan',
      'pool_id': 'sudan',
      'view_mode': 'half',
    },
    {
      'key': 'gift_spin',
      'name_ar': 'عجلة الهدايا',
      'name_en': 'Gift Spin',
      'icon': 'assets/images/icon_game_giftspin.png',
      'hot': 'false',
      'platform': 'alfanexso',
      'game_id': 'fe-game-giftspin',
      'pool_id': 'giftspin',
      'view_mode': 'half',
    },
  ];

  static const List<String> _broadcastMessages = [
    'مبروك للمستخدم 89210 الفوز بـ 50,000 كوينز في لودو! 🎉',
    'مبروك للمستخدم 77412 الفوز بالجائزة الكبرى 100,000 في 777! 💎',
    'فوز ساحق للمستخدم 55301 في دومينو بـ 35,000 كوينز! 🏆',
    'تهانينا للمستخدم 10294 الفوز بمضاعف 500X في عجلة الحظ! 🔥',
  ];

  int _broadcastIdx = 0;

  @override
  void initState() {
    super.initState();
    _broadcastScrollController = ScrollController();
    _marqueeTimer = Timer.periodic(const Duration(seconds: 4), (t) {
      if (mounted) {
        setState(() {
          _broadcastIdx = (_broadcastIdx + 1) % _broadcastMessages.length;
        });
      }
    });
    // ✅ قياس حقيقي لزمن الاستجابة (Ping) لعرض جودة الشبكة داخل المركز
    NetworkPingService.instance.start();
  }

  @override
  void dispose() {
    _marqueeTimer?.cancel();
    _broadcastScrollController.dispose();
    NetworkPingService.instance.stop();
    super.dispose();
  }

  void _handleGameTap(Map<String, String> game, bool isAr) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final appContext = navigator.context;
    Navigator.pop(context);
    final gameName = isAr ? game['name_ar']! : game['name_en']!;
    widget.onGameSelect?.call(game['key']!, gameName);

    if (game['key'] == 'sugarrush') {
      SugarRushGameDialog.show(appContext, roomId: widget.roomId);
      return;
    }

    // ✅ ألعاب منصة StyeParty/Alfa على alfanexso.tech
    //    APP_KEY الرسمي من مزوّد الألعاب: alfa_key_app_ahal_377
    //    الرصيد يُسوّى server-to-server عبر /api/v1/games/* callbacks.
    if (game['platform'] == 'alfanexso') {
      AlfaGameScreen.show(
        appContext,
        gameId: game['game_id']!,
        host: 'alfanexso.tech',
        appKey: 'alfa_key_app_ahal_377',
        poolId: game['pool_id'],
        title: gameName,
        roomId: widget.roomId,
        viewMode: game['view_mode'],
      );
      return;
    }

    // Launch Teaming screen or game lobby
    navigator.push(
      MaterialPageRoute(
        builder: (_) => const GameTeamingScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final cfg = DynamicConfigService();
    final bgPath = cfg.gameCenterBgImage.isNotEmpty
        ? cfg.gameCenterBgImage
        : 'assets/mipmap-xxhdpi/room_game_bg.webp';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * cfg.gameCenterSheetHeight,
      ),
      decoration: BoxDecoration(
        color: cfg.gameCenterBgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        image: DecorationImage(
          image: R.cachedImage(bgPath),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Top Bar (iv_top_bg + room_game_title_ic + iv_close) ──
          SizedBox(
            height: 56,
            child: Stack(
              children: [
                // Top header background
                Positioned.fill(
                  child: R.loadAssetOr(
                    cfg.gameCenterTopBgImage,
                    'assets/mipmap-xxhdpi/room_game_top_bg.webp',
                    fit: BoxFit.fill,
                  ),
                ),

                // Center Title Icon: room_game_title_ic
                Center(
                  child: R.loadAssetOr(
                    cfg.gameCenterTitleImage,
                    'assets/mipmap-xxhdpi/room_game_title_ic.webp',
                    height: 28,
                    fit: BoxFit.contain,
                  ),
                ),

                // ✅ شارة جودة الشبكة (Ping حقيقي بالمللي ثانية)
                Positioned(
                  top: 14,
                  right: isAr ? 14 : null,
                  left: isAr ? null : 14,
                  child: ValueListenableBuilder<int?>(
                    valueListenable: NetworkPingService.instance.pingMs,
                    builder: (context, ms, _) {
                      final color = NetworkPingService.qualityColor(ms);
                      final label = ms == null ? '---' : '$ms';
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 4),
                            DText(
                              '$label ms',
                              style: TextStyle(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Close Button: room_game_close_ic
                Positioned(
                  top: 10,
                  right: isAr ? null : 14,
                  left: isAr ? 14 : null,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    behavior: HitTestBehavior.opaque,
                    child: R.loadAssetOr(
                      cfg.gameCenterCloseImage,
                      'assets/mipmap-xxhdpi/room_game_close_ic.webp',
                      width: 28,
                      height: 28,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── Broadcast Bar (room_game_broadcast_bg + icon + marquee text) ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                image: DecorationImage(
                  image: R.cachedImage(cfg.gameCenterBroadcastBgImage.isNotEmpty
                      ? cfg.gameCenterBroadcastBgImage
                      : 'assets/mipmap-xxhdpi/room_game_broadcast_bg.webp'),
                  fit: BoxFit.fill,
                ),
              ),
              child: Row(
                children: [
                  R.loadAssetOr(
                    cfg.gameCenterBroadcastIconImage,
                    'assets/mipmap-xxhdpi/room_game_broadcast_ic.webp',
                    width: 20,
                    height: 20,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.5),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: DText(
                        _broadcastMessages[_broadcastIdx],
                        key: ValueKey<int>(_broadcastIdx),
                        style: TextStyle(
                          fontSize: 11,
                          color: cfg.gameCenterBroadcastTextColor,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // ── Grid of Games (room_adapter_game_item.xml) ──
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cfg.gameCenterColumns,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.85,
                ),
                itemCount: _games.length,
                itemBuilder: (context, index) {
                  final game = _games[index];
                  final name = isAr ? game['name_ar']! : game['name_en']!;
                  final isHot = game['hot'] == 'true';

                  return GestureDetector(
                    onTap: () => _handleGameTap(game, isAr),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Square game icon with ratio 1:1 and rounded corners
                        Expanded(
                          child: Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.35),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.asset(
                                    game['icon']!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: const Color(0xFF2A2040),
                                      child: const Center(
                                        child: Icon(Icons.sports_esports, color: Colors.white70, size: 36),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Hot badge
                              if (isHot)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          cfg.gameCenterHotColor,
                                          Color.lerp(cfg.gameCenterHotColor, Colors.black, 0.25)!,
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const DText(
                                      'HOT',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 6),

                        // Game Name (tv_game_name)
                        DText(
                          name,
                          style: TextStyle(
                            fontSize: 12,
                            color: cfg.gameCenterGameNameColor,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
