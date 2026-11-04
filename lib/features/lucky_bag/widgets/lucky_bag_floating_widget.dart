import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/r.dart';
import '../models/lucky_bag_config.dart';
import '../models/lucky_bag_model.dart';
import '../services/lucky_bag_service.dart';
import 'lucky_bag_claim_dialog.dart';
import 'lucky_bag_list_dialog.dart';
import 'package:zero/core/dtext.dart';

/// أيقونة حقيبة الحظ العائمة داخل الغرفة المطابقة لـ view_luckybag_item.xml
/// الحجم: 52dp مع شارة عدد الحقائب + عدّاد تنازلي أسفلها.
class LuckyBagFloatingWidget extends StatefulWidget {
  final String roomId;

  const LuckyBagFloatingWidget({super.key, required this.roomId});

  @override
  State<LuckyBagFloatingWidget> createState() => _LuckyBagFloatingWidgetState();
}

class _LuckyBagFloatingWidgetState extends State<LuckyBagFloatingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _scaleAnim;
  Timer? _ticker;
  LuckyBagConfig _config = const LuckyBagConfig();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _scaleAnim = Tween<double>(begin: 0.96, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    LuckyBagService().loadConfig().then((cfg) {
      if (mounted) setState(() => _config = cfg);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LuckyBagModel>>(
      stream: LuckyBagService().activeBagsStream(widget.roomId),
      builder: (context, snapshot) {
        final bags = snapshot.data ?? [];
        if (bags.isEmpty) return const SizedBox.shrink();

        // الأقرب انتهاءً أولاً
        final sorted = [...bags]..sort((a, b) => _expiry(a).compareTo(_expiry(b)));
        final currentBag = sorted.first;

        final remaining = _remaining(currentBag);
        if (remaining <= Duration.zero) return const SizedBox.shrink();

        final primary = _color(_config.primaryColor, const Color(0xFFFFF295));
        final countdownBg =
            _color(_config.countdownColor, const Color(0xB3000000));

        return ScaleTransition(
          scale: _scaleAnim,
          child: GestureDetector(
            onTap: () {
              if (sorted.length > 1) {
                LuckyBagListDialog.show(
                  context,
                  roomId: widget.roomId,
                  bags: sorted,
                );
              } else {
                LuckyBagClaimDialog.show(
                  context,
                  bag: currentBag,
                  roomId: widget.roomId,
                );
              }
            },
            child: SizedBox(
              width: 58,
              height: 58,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  _bagImage(primary),

                  // شارة عدد الحقائب المتبقية
                  PositionedDirectional(
                    top: -2,
                    end: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF2442),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      child: DText(
                        '${currentBag.remainingCount > 0 ? currentBag.remainingCount : sorted.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  // العدّاد التنازلي أسفل عدد الحقائب
                  Positioned(
                    bottom: -2,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: countdownBg,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: Colors.white, width: 0.6),
                      ),
                      child: DText(
                        _formatRemaining(remaining),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ),

                  if (sorted.length > 1)
                    Positioned(
                      left: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add, size: 10, color: Colors.black87),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bagImage(Color primary) {
    final image = _config.bagImage.trim();
    if (image.isNotEmpty) {
      return Image(
        image: R.cachedImage(image),
        width: 52,
        height: 52,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _fallbackIcon(primary),
      );
    }
    return Image.asset(
      'assets/images/ic_luckybag.png',
      width: 52,
      height: 52,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _fallbackIcon(primary),
    );
  }

  Widget _fallbackIcon(Color primary) {
    return Icon(Icons.card_giftcard, color: primary, size: 40);
  }

  DateTime _expiry(LuckyBagModel bag) {
    return DateTime.tryParse(bag.expiresAt ?? '')?.toLocal() ??
        DateTime.now().add(const Duration(hours: 1));
  }

  Duration _remaining(LuckyBagModel bag) {
    final diff = _expiry(bag).difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  String _formatRemaining(Duration d) {
    final total = d.inSeconds;
    if (total >= 3600) {
      final h = total ~/ 3600;
      final m = (total % 3600) ~/ 60;
      return '${h}h ${m.toString().padLeft(2, '0')}m';
    }
    final m = total ~/ 60;
    final s = total % 60;
    if (m > 0) {
      return '$m:${s.toString().padLeft(2, '0')}';
    }
    return '${s}s';
  }

  Color _color(String raw, Color fallback) {
    final cleaned = raw.replaceAll('#', '').trim();
    if (cleaned.length == 6) {
      final v = int.tryParse(cleaned, radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    if (cleaned.length == 8) {
      final v = int.tryParse(cleaned, radix: 16);
      if (v != null) return Color(v);
    }
    return fallback;
  }
}
