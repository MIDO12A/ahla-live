import 'dart:math';
import 'package:flutter/material.dart';

class VipCoverAnimator extends StatefulWidget {
  final String? vipLevel;
  final Widget child;

  const VipCoverAnimator({
    super.key,
    this.vipLevel,
    required this.child,
  });

  @override
  State<VipCoverAnimator> createState() => _VipCoverAnimatorState();
}

class _VipCoverAnimatorState extends State<VipCoverAnimator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Particle> _particles = [];
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _initParticles();
    _controller.addListener(() => setState(() {}));
  }

  void _initParticles() {
    _particles.clear();
    for (int i = 0; i < 8; i++) {
      _particles.add(_Particle(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        size: 2 + _rng.nextDouble() * 4,
        speed: 0.2 + _rng.nextDouble() * 0.4,
        delay: _rng.nextDouble(),
        opacity: 0.3 + _rng.nextDouble() * 0.7,
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isVip => widget.vipLevel != null;

  @override
  Widget build(BuildContext context) {
    if (!_isVip) return widget.child;

    final progress = _controller.value;

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _VipCoverPainter(
                particles: _particles,
                progress: progress,
                goldColor: const Color(0xFFFFC525),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    const Color(0xFFFFC525).withValues(alpha: 0.6 * _pulseValue(progress)),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    const Color(0xFFFFC525).withValues(alpha: 0.6 * _pulseValue(progress)),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _pulseValue(double t) {
    return (sin(t * pi * 2) + 1) / 2;
  }
}

class _Particle {
  final double x;
  final double y;
  final double size;
  final double speed;
  final double delay;
  final double opacity;

  const _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.delay,
    required this.opacity,
  });
}

class _VipCoverPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final Color goldColor;

  _VipCoverPainter({
    required this.particles,
    required this.progress,
    required this.goldColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = (progress + p.delay) % 1.0;
      final yPos = (p.y - t * p.speed) % 1.0;
      final opacity = (sin(t * pi) * p.opacity).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = goldColor.withValues(alpha: opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

      canvas.drawCircle(
        Offset(p.x * size.width, yPos * size.height),
        p.size,
        paint,
      );
    }

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          goldColor.withValues(alpha: 0.08 * _pulse(progress)),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: size.width * 0.6,
      ));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), glowPaint);
  }

  double _pulse(double t) {
    return (sin(t * pi * 2) + 1) / 2;
  }

  @override
  bool shouldRepaint(covariant _VipCoverPainter oldDelegate) => true;
}
