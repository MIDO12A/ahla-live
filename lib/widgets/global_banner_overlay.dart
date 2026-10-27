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
///
/// جميع البانرات تعمل وفق نظام طابور موحد متتابع (FIFO Queue):
/// - يظهر بانر واحد فقط في كل لحظة دون أي تكرار أو تراكم فوق بعضها.
/// - كل بانر يدخل بسلاسة من اليمين إلى اليسار وينتهي ليأتي الذي بعده بانتظام.
class GlobalBannerOverlay extends StatelessWidget {
  final Widget child;

  const GlobalBannerOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GlobalBannerService.instance,
      builder: (context, _) {
        final svc = GlobalBannerService.instance;
        final banner = svc.currentBanner;
        final topPadding = MediaQuery.of(context).padding.top;

        return Stack(
          textDirection: TextDirection.ltr,
          children: [
            // الشاشة الأصلية للتطبيق
            child,

            // عرض البانر النشط الوحيد حالياً وفق نظام الطابور المنظم
            if (banner != null)
              Positioned(
                top: banner.type == GlobalBannerType.marquee
                    ? (topPadding + 10)
                    : 0,
                left: 0,
                right: 0,
                child: _buildBanner(context, banner, svc),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBanner(BuildContext context, QueuedBannerItem banner, GlobalBannerService svc) {
    switch (banner.type) {
      case GlobalBannerType.giftBanner:
        final gb = banner.data;
        String safeSenderPhoto = gb['senderPhotoUrl']?.toString() ?? 'assets/mipmap-xxhdpi/ic_avatar_default.webp';
        String safeReceiverPhoto = gb['receiverPhotoUrl']?.toString() ?? 'assets/mipmap-xxhdpi/ic_avatar_default.webp';
        String safeGiftImage = gb['defaultImage']?.toString() ?? gb['giftImageUrl']?.toString() ?? 'assets/mipmap-xxhdpi/common_gold_ic_4.webp';
        return GiftBannerOverlay(
          key: ValueKey(banner.id),
          animationAsset: gb['animationAsset']?.toString(),
          senderPhotoUrl: safeSenderPhoto,
          receiverPhotoUrl: safeReceiverPhoto,
          giftImageUrl: safeGiftImage,
          giftCount: (gb['giftCount'] as num?)?.toInt() ?? 1,
          userRKey: gb['userRKey']?.toString() ?? 'user_r',
          userLKey: gb['userLKey']?.toString() ?? 'user_l',
          numberKey: gb['numberKey']?.toString() ?? 'number',
          giftKey: gb['giftKey']?.toString() ?? 'gift',
          onFinished: () => svc.nextBanner(),
        );

      case GlobalBannerType.bigWin:
        final bw = banner.data;
        return BigWinBanner(
          key: ValueKey(banner.id),
          senderName: bw['senderName']?.toString() ?? 'مستخدم',
          senderAvatar: (bw['senderAvatar'] != null && bw['senderAvatar'].toString().isNotEmpty)
              ? bw['senderAvatar'].toString()
              : 'assets/mipmap-xxhdpi/ic_avatar_default.webp',
          giftName: bw['giftName']?.toString() ?? 'هدية الحظ',
          multiplier: (bw['multiplier'] as num?)?.toInt() ?? 100,
          totalWon: (bw['totalWon'] as num?)?.toInt() ?? 0,
          lang: Localizations.localeOf(context).languageCode == 'ar' ? 'ar' : 'en',
          onDismiss: () => svc.nextBanner(),
        );

      case GlobalBannerType.marquee:
        return RoomMarqueeBroadcast(
          key: ValueKey(banner.id),
          broadcast: banner.data,
          onDismissed: () => svc.nextBanner(),
        );
    }
  }
}
