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
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnim;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutBack));

    _animController.forward();

    // Auto dismiss after 6 seconds
    _dismissTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) {
        _animController.reverse().then((_) {
          if (mounted) widget.onDismissed();
        });
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _animController.dispose();
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
        position: _slideAnim,
        child: GestureDetector(
        onTap: () {
          if (roomId.isNotEmpty) {
            navigateToRoom(
              context,
              roomName: roomName,
              hostName: '',
              roomId: roomId,
            );
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
                              if (multiplier != null && multiplier > 1) ...[
                                TextSpan(
                                  text: ' فاز بمضاعف ${multiplier}X ',
                                  style: const TextStyle(
                                    color: Color(0xFFFF416C),
                                    fontWeight: FontWeight.bold,
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
  );
}
}
