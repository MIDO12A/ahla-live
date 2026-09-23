import 'package:flutter/material.dart';
import '../../../../services/dynamic_config_service.dart';
import 'svga_player.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// RoomRocketWidget — صاروخ الغرفة الكريستالي ومستوى الطاقة والانفجار
// ═══════════════════════════════════════════════════════════════════════════════

class RoomRocketWidget extends StatelessWidget {
  final int energy;
  final int target;
  final VoidCallback onTap;

  const RoomRocketWidget({
    super.key,
    required this.energy,
    required this.target,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = DynamicConfigService();
    final effectiveTarget = target > 0 ? target : cfg.roomRocketTarget;
    final progress = (energy / effectiveTarget).clamp(0.0, 1.0);
    final percent = (progress * 100).toInt();

    final rocketSvga = cfg.roomRocketSvga;
    final rocketIcon = cfg.roomRocketIcon;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cfg.roomRocketAccentColor.withValues(alpha: 0.7), width: 1),
          boxShadow: [
            BoxShadow(
              color: cfg.roomRocketAccentColor.withValues(alpha: 0.3),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Rocket Icon or Animated SVGA
            if (rocketSvga.isNotEmpty && rocketSvga.endsWith('.svga'))
              SizedBox(
                width: 26,
                height: 26,
                child: SvgaPlayer(
                  assetPath: rocketSvga,
                  fit: BoxFit.contain,
                ),
              )
            else if (rocketIcon.startsWith('http://') || rocketIcon.startsWith('https://'))
              Image.network(
                rocketIcon,
                width: 22,
                height: 22,
                errorBuilder: (_, __, ___) => const Icon(Icons.rocket_launch, color: Color(0xFFFFD700), size: 18),
              )
            else
              Image.asset(
                'assets/images/icon_crysatal_rocket.png',
                width: 22,
                height: 22,
                errorBuilder: (_, __, ___) => const Icon(Icons.rocket_launch, color: Color(0xFFFFD700), size: 18),
              ),
            const SizedBox(width: 4),

            // Progress bar and percentage
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$percent%',
                      style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    width: 36,
                    height: 4,
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// حوار تفاصيل طاقة الصاروخ ومكافآت الانفجار
  static void showRocketInfoSheet(BuildContext context, int energy, int target) {
    final effectiveTarget = target > 0 ? target : 5000;
    final progress = (energy / effectiveTarget).clamp(0.0, 1.0);
    final remaining = effectiveTarget - energy > 0 ? effectiveTarget - energy : 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1C1428),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Indicator handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/icon_crysatal_rocket.png',
                    width: 28,
                    height: 28,
                    errorBuilder: (_, __, ___) => const Icon(Icons.rocket_launch, color: Color(0xFFFFD700)),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'صاروخ الغرفة الكريستالي',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Progress Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'طاقة الشحن الحالية:',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        Text(
                          '$energy / $effectiveTarget',
                          style: const TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 10,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'متبقي $remaining عملة لإطلاق وانفجار الصاروخ 🚀',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Description
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.stars, color: Color(0xFFFFD700), size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'عند إرسال الهدايا تزداد طاقة الصاروخ، وفور اكتمالها بنسبة 100% ينفجر الصاروخ ويسقط صناديق الكنز ومكافآت الحظ لجميع الحاضرين في الغرفة!',
                        style: TextStyle(color: Colors.white, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
