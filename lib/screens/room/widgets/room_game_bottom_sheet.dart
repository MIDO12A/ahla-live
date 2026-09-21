// lib/screens/room/widgets/room_game_bottom_sheet.dart
// ─────────────────────────────────────────────────────────────────────────────
// Room Game Bottom Sheet — matches room_fragment_game.xml & room_adapter_game_item.xml
// • iv_game_bg / iv_top_bg / iv_close / room_game_title_ic
// • ll_broad_cast: room_game_broadcast_bg + room_game_broadcast_ic + marquee text
// • recyclerview_game: grid with iv_game (1:1 rounded) + tv_game_name marquee
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../config/r.dart';
import '../../game/game_teaming_screen.dart';

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
      'key': 'domino',
      'name_ar': 'دومينو',
      'name_en': 'Domino',
      'icon': 'assets/images/icon_game_center_domino.png',
      'hot': 'true',
    },
    {
      'key': 'ludo',
      'name_ar': 'لودو',
      'name_en': 'Ludo',
      'icon': 'assets/images/icon_game_center_ludo.png',
      'hot': 'true',
    },
    {
      'key': 'fruit',
      'name_ar': 'ماكينة الفواكه',
      'name_en': 'Fruit Master',
      'icon': 'assets/images/icon_game_fuiter.png',
      'hot': 'false',
    },
    {
      'key': 'lucky_777',
      'name_ar': '777 الحظ',
      'name_en': 'Lucky 777',
      'icon': 'assets/images/icon_hu_game_777.png',
      'hot': 'true',
    },
    {
      'key': 'wheel',
      'name_ar': 'عجلة الحظ',
      'name_en': 'Lucky Wheel',
      'icon': 'assets/images/icon_game_turntable_h5.png',
      'hot': 'false',
    },
    {
      'key': 'red_black',
      'name_ar': 'أحمر وأسود',
      'name_en': 'Red & Black',
      'icon': 'assets/images/icon_game_red.png',
      'hot': 'false',
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
  }

  @override
  void dispose() {
    _marqueeTimer?.cancel();
    _broadcastScrollController.dispose();
    super.dispose();
  }

  void _handleGameTap(Map<String, String> game, bool isAr) {
    Navigator.pop(context);
    final gameName = isAr ? game['name_ar']! : game['name_en']!;
    widget.onGameSelect?.call(game['key']!, gameName);

    // Launch Teaming screen or game lobby
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const GameTeamingScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1428),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        image: DecorationImage(
          image: AssetImage('assets/mipmap-xxhdpi/room_game_bg.webp'),
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
                  child: Image.asset(
                    'assets/mipmap-xxhdpi/room_game_top_bg.webp',
                    fit: BoxFit.fill,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),

                // Center Title Icon: room_game_title_ic
                Center(
                  child: Image.asset(
                    'assets/mipmap-xxhdpi/room_game_title_ic.webp',
                    height: 28,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Text(
                      isAr ? 'الألعاب' : 'Games',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
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
                    child: Image.asset(
                      'assets/mipmap-xxhdpi/room_game_close_ic.webp',
                      width: 28,
                      height: 28,
                      errorBuilder: (_, __, ___) => const Icon(Icons.close, color: Colors.white70),
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
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/mipmap-xxhdpi/room_game_broadcast_bg.webp'),
                  fit: BoxFit.fill,
                ),
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Image.asset(
                    'assets/mipmap-xxhdpi/room_game_broadcast_ic.webp',
                    width: 20,
                    height: 20,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.volume_up, color: Color(0xFFFFD700), size: 16),
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
                      child: Text(
                        _broadcastMessages[_broadcastIdx],
                        key: ValueKey<int>(_broadcastIdx),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
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
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
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
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
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
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
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
