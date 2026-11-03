import 'dart:async';
import 'package:flutter/material.dart';
import '../../../config/r.dart';
import 'package:zero/core/dtext.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// RoomMemberEnterBanner — layout_room_member_enter.xml
//
// Matches decompiled layout_room_member_enter.xml:
// - Background: room_member_enter_bg.webp
// - User name: tv_name (white, 13sp)
// - Avatar & VIP badge
// - Smooth entrance animation from right to left (RTL) / left to right
// ═══════════════════════════════════════════════════════════════════════════════

class RoomMemberEnterBanner extends StatefulWidget {
  final String userName;
  final String userPhotoUrl;
  final int userLevel;
  final VoidCallback onFinished;

  const RoomMemberEnterBanner({
    super.key,
    required this.userName,
    required this.userPhotoUrl,
    this.userLevel = 1,
    required this.onFinished,
  });

  @override
  State<RoomMemberEnterBanner> createState() => _RoomMemberEnterBannerState();
}

class _RoomMemberEnterBannerState extends State<RoomMemberEnterBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slideAnim;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(-1.2, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));

    _ctrl.forward();

    _timer = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) {
        _ctrl.reverse().then((_) {
          if (mounted) widget.onFinished();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnim,
      child: Container(
        height: 48,
        constraints: const BoxConstraints(maxWidth: 290),
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            // Background image: room_member_enter_bg
            Positioned.fill(
              child: Image.asset(
                'assets/images/room_member_enter_bg.webp',
                fit: BoxFit.fill,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xCC6A11CB), Color(0xCC2575FC)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // User Avatar
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black26, blurRadius: 4),
                      ],
                    ),
                    child: ClipOval(
                      child: widget.userPhotoUrl.isNotEmpty
                          ? Image(
                              image: R.cachedImage(widget.userPhotoUrl),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white, size: 20),
                            )
                          : const Icon(Icons.person, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // User name & Welcome text
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: DText(
                                widget.userName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            // User Level badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD700),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: DText(
                                'Lv.${widget.userLevel}',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        const DText(
                          'دخل إلى الغرفة',
                          style: TextStyle(
                            color: Color(0xFF41FE88),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
