import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../config/r.dart';
import '../../../../screens/room/widgets/svga_player.dart';

/// ويدجت طيران الهدية إلى مقعد المستخدم المستلم في الغرفة (Gift Seat Flight Animation)
/// يدعم إرسال هدية لمقعد محدد أو الطيران المتوازي لكافة مقاعد المستخدمين (Send to All Mic Users)
class GiftSeatFlightOverlay extends StatefulWidget {
  final String giftIconUrl;
  final String? giftAnimAsset; // SVGA أو VAP
  final String type; // 'image', 'svga', 'vap'
  final Offset startOffset; // نقطة انطلاق الهدية (مثلاً أسفل الشاشة أو زر الإرسال)
  final List<Offset> targetOffsets; // إحداثيات مقاعد المستلمين على الشاشة
  final VoidCallback onFinished;

  const GiftSeatFlightOverlay({
    Key? key,
    required this.giftIconUrl,
    this.giftAnimAsset,
    this.type = 'image',
    required this.startOffset,
    required this.targetOffsets,
    required this.onFinished,
  }) : super(key: key);

  @override
  State<GiftSeatFlightOverlay> createState() => _GiftSeatFlightOverlayState();
}

class _GiftSeatFlightOverlayState extends State<GiftSeatFlightOverlay>
    with TickerProviderStateMixin {
  late AnimationController _flightController;
  late Animation<double> _flightProgress;
  late AnimationController _burstController;
  late Animation<double> _burstScale;
  late Animation<double> _burstOpacity;
  bool _hasArrived = false;
  bool _wasFinished = false;
  Timer? _safetyTimer;

  void _finishOnce() {
    if (_wasFinished) return;
    _wasFinished = true;
    _safetyTimer?.cancel();
    if (mounted) widget.onFinished();
  }

  @override
  void initState() {
    super.initState();
    _safetyTimer = Timer(const Duration(seconds: 4), _finishOnce);

    _flightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _flightProgress = CurvedAnimation(
      parent: _flightController,
      curve: Curves.easeOutCubic,
    );

    _burstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _burstScale = Tween<double>(begin: 0.6, end: 1.5).animate(
      CurvedAnimation(parent: _burstController, curve: Curves.easeOutBack),
    );
    _burstOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _burstController, curve: Curves.easeIn),
    );

    _flightController.forward().then((_) {
      if (!mounted) return;
      setState(() {
        _hasArrived = true;
      });
      _burstController.forward().then((_) {
        _finishOnce();
      });
    });
  }

  @override
  void dispose() {
    _safetyTimer?.cancel();
    _flightController.dispose();
    _burstController.dispose();
    super.dispose();
  }

  // حساب مسار منحنى بيزييه الانسيابي (Bézier Curve)
  Offset _calculateBezierPoint(Offset p0, Offset p2, double t) {
    final midX = (p0.dx + p2.dx) / 2;
    final p1 = Offset(
      midX + (p0.dx > p2.dx ? -20 : 20),
      min(p0.dy, p2.dy) - 70,
    );

    final u = 1.0 - t;
    final x = u * u * p0.dx + 2 * u * t * p1.dx + t * t * p2.dx;
    final y = u * u * p0.dy + 2 * u * t * p1.dy + t * t * p2.dy;
    return Offset(x, y);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([_flightController, _burstController]),
        builder: (context, child) {
          final t = _flightProgress.value;

          // Scale: 0.7 at start -> 1.2 mid flight -> shrinks down to 0.1 at arrival
          double flightScale;
          double flightOpacity;
          if (t < 0.6) {
            flightScale = 0.7 + (t / 0.6) * 0.5; // 0.7 -> 1.2
            flightOpacity = 1.0;
          } else {
            final subT = (t - 0.6) / 0.4;
            flightScale = 1.2 * (1.0 - subT); // 1.2 -> 0.0
            flightOpacity = (1.0 - subT).clamp(0.0, 1.0);
          }

          return Stack(
            children: widget.targetOffsets.map((target) {
              final currentPos = _calculateBezierPoint(widget.startOffset, target, t);

              return Positioned(
                left: currentPos.dx - 28,
                top: currentPos.dy - 28,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Flying Gift (scales down and disappears on arrival)
                    if (!_hasArrived && flightOpacity > 0.01)
                      Opacity(
                        opacity: flightOpacity,
                        child: Transform.scale(
                          scale: flightScale,
                          child: widget.giftIconUrl.startsWith('http')
                              ? Image(
                                  image: R.cachedImage(widget.giftIconUrl),
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard, color: Colors.amber, size: 36),
                                )
                              : Image.asset(
                                  widget.giftIconUrl,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard, color: Colors.amber, size: 36),
                                ),
                        ),
                      ),

                    // Arrival Sparkle / Star Burst (at the target seat)
                    if (_hasArrived)
                      Opacity(
                        opacity: _burstOpacity.value,
                        child: Transform.scale(
                          scale: _burstScale.value,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  const Color(0xFFFFE082).withOpacity(0.9),
                                  const Color(0xFFFFB300).withOpacity(0.5),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                '✨',
                                style: TextStyle(fontSize: 28),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
