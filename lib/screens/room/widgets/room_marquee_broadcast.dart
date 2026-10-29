import 'dart:async';
import 'package:flutter/material.dart';
import '../../../config/r.dart';
import '../room_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// RoomMarqueeBroadcast — view_room_all_banner.xml
//
// Matches decompiled view_room_all_banner.xml:
// - Background: room_all_gift_banner_bg.9.png
// - Avatar: RoundImageView 36×36 circle
// - Description: tv_gift_desc with sender, gift/multiplier, and room info
// - Clickable to jump into the lucky room immediately
// ═══════════════════════════════════════════════════════════════════════════════

class RoomMarqueeBroadcast extends StatefulWidget {
  final Map<String, dynamic> broadcast;
  final VoidCallback onDismissed;

  const RoomMarqueeBroadcast({
    super.key,
    required this.broadcast,
    required this.onDismissed,
  });

  @override
  State<RoomMarqueeBroadcast> createState() => _RoomMarqueeBroadcastState();
}

class _RoomMarqueeBroadcastState extends State<RoomMarqueeBroadcast>
    with TickerProviderStateMixin {
  late AnimationController _enterController;
  late AnimationController _exitController;
  late Animation<Offset> _enterAnim;
  late Animation<Offset> _exitAnim;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    // الدخول من أقصى اليمين نحو المنتصف
    _enterAnim = Tween<Offset>(
      begin: const Offset(1.5, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enterController, curve: Curves.easeOutCubic));

    // الخروج بالمرور الكامل نحو أقصى اليسار دون أي انقطاع
    _exitAnim = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-1.5, 0.0),
    ).animate(CurvedAnimation(parent: _exitController, curve: Curves.easeInCubic));

    _enterController.forward();

    // Auto dismiss after 4.8 seconds with smooth exit to the left
    _dismissTimer = Timer(const Duration(milliseconds: 4800), () {
      _dismiss();
    });
  }

  void _dismiss() {
    if (!mounted) return;
    _dismissTimer?.cancel();
    _exitController.forward().then((_) {
      if (mounted) widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _enterController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final senderName = widget.broadcast['sender_name']?.toString() ?? 'مستخدم';
    final senderPhoto = widget.broadcast['sender_photo_url']?.toString() ?? '';
    final roomName = widget.broadcast['room_name']?.toString() ?? 'غرفة صوتية';
    final roomId = widget.broadcast['room_id']?.toString() ?? '';
    final content = widget.broadcast['content']?.toString() ?? '';
    final giftIcon = widget.broadcast['gift_icon']?.toString();
    final multiplier = widget.broadcast['multiplier'];

    return RepaintBoundary(
      child: SlideTransition(
        position: _exitAnim,
        child: SlideTransition(
          position: _enterAnim,
          child: GestureDetector(
        onTap: () {
          if (roomId.isNotEmpty && mounted) {
            try {
              navigateToRoom(
                context,
                roomName: roomName,
                hostName: '',
                roomId: roomId,
              );
            } catch (_) {}
          }
        },
        child: SizedBox(
          width: double.infinity,
          height: 92,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. Background image (view_room_all_banner.xml -> iv_bg: @mipmap/room_all_gift_banner_bg, fitXY, minHeight 92dp)
              Positioned.fill(
                child: Image.asset(
                  'assets/images/room_all_gift_banner_bg.9.png',
                  fit: BoxFit.fill,
                  errorBuilder: (_, __, ___) => Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
                    ),
                  ),
                ),
              ),

              // 2. Avatar (iv_avatar: 36x36 circle, marginStart=53dp, centered vertically)
              Positioned(
                left: 53,
                top: (92 - 36) / 2,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: senderPhoto.isNotEmpty
                        ? Image(
                            image: R.cachedImage(senderPhoto),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey[800],
                              child: const Icon(Icons.person, color: Colors.white, size: 20),
                            ),
                          )
                        : Container(
                            color: Colors.grey[800],
                            child: const Icon(Icons.person, color: Colors.white, size: 20),
                          ),
                  ),
                ),
              ),

              // 3. Description (tv_gift_desc: marginStart=6dp after avatar, marginEnd=63dp, 12sp, textColor=@color/white)
              Positioned(
                left: 53 + 36 + 6,
                right: 63,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              height: 1.3,
                            ),
                            children: [
                              TextSpan(
                                text: '$senderName ',
                                style: const TextStyle(
                                  color: Color(0xFFFFEB3B),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (multiplier != null && (multiplier is num ? (multiplier as num).toInt() : int.tryParse(multiplier.toString()) ?? 0) > 1) ...[
                                TextSpan(
                                  text: ' 🔥 فاز بمضاعف ${(multiplier is num ? (multiplier as num).toInt() : int.tryParse(multiplier.toString()) ?? 0)}X ',
                                  style: TextStyle(
                                    color: ((multiplier is num ? (multiplier as num).toInt() : int.tryParse(multiplier.toString()) ?? 0) >= 500)
                                        ? const Color(0xFFFF1493)
                                        : (((multiplier is num ? (multiplier as num).toInt() : int.tryParse(multiplier.toString()) ?? 0) >= 250)
                                            ? const Color(0xFFFF6F00)
                                            : (((multiplier is num ? (multiplier as num).toInt() : int.tryParse(multiplier.toString()) ?? 0) >= 100)
                                                ? const Color(0xFFFF0055)
                                                : const Color(0xFFFF416C))),
                                    fontWeight: FontWeight.w900,
                                    shadows: const [
                                      Shadow(color: Color(0xAA000000), blurRadius: 4, offset: Offset(0, 1)),
                                    ],
                                  ),
                                ),
                              ],
                              TextSpan(
                                text: content.isNotEmpty ? content : 'في غرفة $roomName',
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (giftIcon != null && giftIcon.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image(
                            image: R.cachedImage(giftIcon),
                            width: 32,
                            height: 32,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
}
}
