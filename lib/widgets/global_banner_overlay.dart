import 'package:flutter/material.dart';
import '../services/global_banner_service.dart';
import '../screens/room/widgets/gift_panel.dart';
import '../features/lucky_gift/widgets/big_win_banner.dart';
import '../screens/room/widgets/room_marquee_broadcast.dart';

/// ويدجت تغليف عامة على مستوى التطبيق (GlobalBannerOverlay)
/// تُركّب في جذر الـ MaterialApp.builder وتضمن ظهور:
/// 1. لافتات الهدايا المخصصة SVGA (المضافة من لوحة التحكم)
/// 2. بانرات فوز الحظ الكبرى الأسطورية (Big Win Banner)
/// 3. شريط الإعلان الماركي لجميع الغرف القابل للنقر
class GlobalBannerOverlay extends StatelessWidget {
  final Widget child;

  const GlobalBannerOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GlobalBannerService.instance,
      builder: (context, _) {
        final svc = GlobalBannerService.instance;
        final giftBanner = svc.activeGiftBanner;
        final bigWin = svc.activeBigWin;
        final marquee = svc.activeMarquee;

        final hasGiftBanner = giftBanner != null;
        final hasBigWin = bigWin != null;
        final topPadding = MediaQuery.of(context).padding.top;

        String safeSenderPhoto = 'assets/mipmap-xxhdpi/ic_avatar_default.webp';
        String safeReceiverPhoto = 'assets/mipmap-xxhdpi/ic_avatar_default.webp';
        String safeGiftImage = 'assets/mipmap-xxhdpi/common_gold_ic_4.webp';

        if (giftBanner != null) {
          final s = giftBanner['senderPhotoUrl']?.toString();
          if (s != null && s.trim().isNotEmpty) safeSenderPhoto = s;

          final r = giftBanner['receiverPhotoUrl']?.toString();
          if (r != null && r.trim().isNotEmpty) safeReceiverPhoto = r;

          final g = giftBanner['defaultImage']?.toString() ?? giftBanner['giftImageUrl']?.toString();
          if (g != null && g.trim().isNotEmpty) safeGiftImage = g;
        }

        return Stack(
          textDirection: TextDirection.ltr,
          children: [
            // الشاشة الأصلية
            child,

            // 1. شريط ولافتة الهدية المخصصة SVGA / VAP مع Fallback كامل
            if (hasGiftBanner)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: GiftBannerOverlay(
                  animationAsset: giftBanner['animationAsset']?.toString(),
                  senderPhotoUrl: safeSenderPhoto,
                  receiverPhotoUrl: safeReceiverPhoto,
                  giftImageUrl: safeGiftImage,
                  giftCount: (giftBanner['giftCount'] as num?)?.toInt() ?? 1,
                  userRKey: giftBanner['userRKey']?.toString() ?? 'user_r',
                  userLKey: giftBanner['userLKey']?.toString() ?? 'user_l',
                  numberKey: giftBanner['numberKey']?.toString() ?? 'number',
                  giftKey: giftBanner['giftKey']?.toString() ?? 'gift',
                  onFinished: () => svc.dismissGiftBanner(),
                ),
              ),

            // 2. بانر فوز الحظ الأسطوري (50X / 100X / 250X / 500X / 1000X)
            if (hasBigWin)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: BigWinBanner(
                  senderName: bigWin['senderName']?.toString() ?? 'مستخدم',
                  senderAvatar: (bigWin['senderAvatar'] != null && bigWin['senderAvatar'].toString().isNotEmpty)
                      ? bigWin['senderAvatar'].toString()
                      : 'assets/mipmap-xxhdpi/ic_avatar_default.webp',
                  giftName: bigWin['giftName']?.toString() ?? 'هدية الحظ',
                  multiplier: (bigWin['multiplier'] as num?)?.toInt() ?? 100,
                  totalWon: (bigWin['totalWon'] as num?)?.toInt() ?? 0,
                  lang: Localizations.localeOf(context).languageCode == 'ar' ? 'ar' : 'en',
                  onDismiss: () => svc.dismissBigWin(),
                ),
              ),

            // 3. شريط الإعلان الماركي لجميع الغرف (قابلة للنقر للدخول السريع للروم)
            if (marquee != null)
              Positioned(
                top: hasGiftBanner
                    ? (topPadding + 115)
                    : hasBigWin
                        ? (topPadding + 145)
                        : (topPadding + 10),
                left: 0,
                right: 0,
                child: RoomMarqueeBroadcast(
                  key: ValueKey(marquee['id'] ?? marquee['timestamp'] ?? DateTime.now().millisecondsSinceEpoch),
                  broadcast: marquee,
                  onDismissed: () => svc.dismissMarquee(),
                ),
              ),
          ],
        );
      },
    );
  }
}
