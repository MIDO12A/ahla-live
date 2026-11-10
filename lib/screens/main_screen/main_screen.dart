import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../providers/user_provider.dart';
import '../../services/dynamic_config_service.dart';
import '../../services/update_service.dart';
import '../../l10n/app_localizations.dart';
import '../discover/room_discover_screen.dart';
import '../message/message_screen.dart';
import '../login/profile_screen.dart';
import '../room/widgets/svga_player.dart';
import '../../widgets/app_update_dialog.dart';
import '../../features/signin/weekly_signin_screen.dart';
import '../../features/rewards/daily_reward_dialog.dart';
import '../../services/supabase_service.dart';
import '../room/widgets/room_marquee_broadcast.dart';
import '../../features/lucky_gift/services/lucky_gift_service.dart';
import 'package:zero/core/dtext.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  late PageController _pageController;
  int _currentIndex = 0;
  Timer? _updatePoll;
  bool _checkingUpdate = false;
  StreamSubscription? _broadcastSub;
  final ValueNotifier<Map<String, dynamic>?> _broadcastNotifier = ValueNotifier<Map<String, dynamic>?>(null);
  final Set<String> _seenBroadcastIds = <String>{};
  // الصفحات تُنشأ مرة واحدة — لا تُعاد بناؤها مع كل تحديث إعدادات
  late final List<Widget> _pages = [
    RoomDiscoverScreen(),
    MessageScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    WidgetsBinding.instance.addObserver(this);
    // Check for updates and daily checkin immediately after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _checkUpdate();
      await WeeklySigninScreen.showIfNeeded(context);
      if (mounted) {
        await DailyRewardDialog.showIfNeeded(context);
      }
    });
    // Periodic update check while the app is open (splash only checks cold start)
    _updatePoll = Timer.periodic(const Duration(minutes: 15), (_) => _checkUpdate());

    // ✅ الاستماع للبانرات العامة وبانرات فوز الحظ (100X, 250X, 500X) عبر كل شاشات التطبيق
    _broadcastSub = FirebaseService().globalBroadcastStream().listen((broadcasts) {
      if (!mounted || broadcasts.isEmpty) return;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      for (final latest in broadcasts) {
        final bTs = (latest['timestamp'] as num?)?.toInt() ??
            (DateTime.tryParse(latest['created_at']?.toString() ?? '')?.millisecondsSinceEpoch ?? 0);
        // تجاهل البثوث التي لا تحمل وقت سيرفر صالح حتى لا تُعاد القديمة عند كل فتح.
        if (bTs <= 0) continue;
        final isRecent = (nowMs - bTs).abs() < 90000;
        if (!isRecent) continue;
        final bId = latest['id']?.toString() ?? '${bTs}_${latest['sender_uid']}';
        if (_seenBroadcastIds.contains(bId)) continue;
        _seenBroadcastIds.add(bId);
        _broadcastNotifier.value = latest;

        // إذا كان فوزاً كبيراً 10X فما فوق، تشغيل بانر SVGA العالمي الأسطوري
        final mult = latest['multiplier'] is num
            ? (latest['multiplier'] as num).toInt()
            : int.tryParse(latest['multiplier']?.toString() ?? '0') ?? 0;
        if (mult >= 10 && mounted) {
          LuckyGiftService().showBigWinBanner(
            context,
            senderName: latest['sender_name']?.toString() ?? 'مستخدم',
            senderAvatar: latest['sender_photo_url']?.toString() ?? '',
            giftName: latest['gift_name']?.toString() ?? 'هدية الحظ',
            multiplier: mult,
            totalWon: (latest['won_coins'] as num?)?.toInt() ?? 0,
          );
        }
        break; // Display the newest unseen broadcast immediately
      }
    });
  }

  Future<void> _checkUpdate() async {
    if (_checkingUpdate) return;
    _checkingUpdate = true;
    try {
      final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
      final update = await UpdateService.instance.checkForUpdate();
      if (update != null && mounted) {
        await AppUpdateDialog.show(context, update);
        if (uid != null && mounted) {
          await Provider.of<UserProvider>(context, listen: false).loadUser(uid);
        }
      }
    } catch (_) {} finally {
      _checkingUpdate = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!UpdateService.instance.sessionUpdateDismissed && !UpdateService.instance.isDownloading) {
        _checkUpdate();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updatePoll?.cancel();
    _broadcastSub?.cancel();
    _broadcastNotifier.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            children: _pages,
          ),

              // ── Global Marquee Broadcast for all screens ──
              ValueListenableBuilder<Map<String, dynamic>?>(
                valueListenable: _broadcastNotifier,
                builder: (context, broadcast, _) {
                  if (broadcast == null) return const SizedBox.shrink();
                    return Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 0,
                      right: 0,
                      child: RoomMarqueeBroadcast(
                        key: ValueKey(broadcast['id'] ?? broadcast['timestamp'] ?? DateTime.now().millisecondsSinceEpoch),
                        broadcast: broadcast,
                        onDismissed: () {
                          _broadcastNotifier.value = null;
                        },
                      ),
                    );
                },
              ),
            ],
          ),
          bottomNavigationBar: ListenableBuilder(
            listenable: DynamicConfigService(),
            builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      DynamicConfigService().bottomNavGradientStart,
                      DynamicConfigService().bottomNavGradientEnd,
                    ],
                  ),
                  image: DynamicConfigService().bottomNavBgImage.isNotEmpty
                      ? DecorationImage(
                          image: R.cachedImage(DynamicConfigService().bottomNavBgImage),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildNavItem(
                          index: 0,
                          normalIcon: R.tabDiscoverNor,
                          selectedIcon: R.tabDiscoverPre,
                          label: l10n.tabDiscover,
                        ),
                        _buildNavItem(
                          index: 1,
                          normalIcon: R.tabMessageNor,
                          selectedIcon: R.tabMessagePre,
                          label: l10n.tabMessage,
                        ),
                        _buildNavItem(
                          index: 2,
                          normalIcon: R.tabMineNor,
                          selectedIcon: R.tabMinePre,
                          label: l10n.tabProfile,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          ),
        );
  }

  Widget _navIconWidget(String iconPath) {
    if (iconPath.endsWith('.svga') || iconPath.endsWith('.vap')) {
      return SvgaPlayer(
        assetPath: iconPath,
        width: 48,
        height: 48,
        fit: BoxFit.contain,
      );
    }
    return R.image(iconPath, width: 48, height: 48, fit: BoxFit.contain);
  }

  Widget _buildNavItem({
    required int index,
    required String normalIcon,
    required String selectedIcon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _currentIndex = index);
        // تبديل فوري بدون أنيميشن —zero perceptible delay
        _pageController.jumpToPage(index);
      },
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: _navIconWidget(isSelected ? selectedIcon : normalIcon),
            ),
            const SizedBox(height: 2),
            DText(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
                color: isSelected 
                    ? DynamicConfigService().bottomNavActiveTextColor 
                    : DynamicConfigService().bottomNavInactiveTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
