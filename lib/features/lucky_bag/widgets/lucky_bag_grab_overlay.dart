import 'dart:async';
import 'package:flutter/material.dart';
import '../models/lucky_bag_model.dart';

/// طبقة عائمة أعلى الغرفة تُظهر المظروف الأحمر النشط مع زر «فتح».
class LuckyBagGrabOverlay extends StatefulWidget {
  final LuckyBagModel bag;
  final Future<void> Function() onGrab;
  final VoidCallback? onTapOpen;
  final VoidCallback? onDismiss;

  const LuckyBagGrabOverlay({
    super.key,
    required this.bag,
    required this.onGrab,
    this.onTapOpen,
    this.onDismiss,
  });

  @override
  State<LuckyBagGrabOverlay> createState() => _LuckyBagGrabOverlayState();
}

class _LuckyBagGrabOverlayState extends State<LuckyBagGrabOverlay> {
  Timer? _expiryTimer;
  Duration _remaining = const Duration(seconds: 90);
  bool _grabbing = false;

  @override
  void initState() {
    super.initState();
    _calculateRemaining();
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _calculateRemaining();
    });
  }

  void _calculateRemaining() {
    if (widget.bag.expiresAt != null) {
      final exp = DateTime.tryParse(widget.bag.expiresAt!);
      if (exp != null) {
        final diff = exp.difference(DateTime.now());
        setState(() {
          _remaining = diff.isNegative ? Duration.zero : diff;
          if (_remaining.inSeconds <= 0) {
            _expiryTimer?.cancel();
          }
        });
        return;
      }
    }
    setState(() {
      _remaining -= const Duration(seconds: 1);
      if (_remaining.inSeconds <= 0) {
        _expiryTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleGrab() async {
    if (_grabbing) return;
    setState(() => _grabbing = true);
    await widget.onGrab();
    if (mounted) setState(() => _grabbing = false);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final isExpired = _remaining.inSeconds <= 0;
    final seconds = _remaining.inSeconds;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: widget.onTapOpen,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: widget.bag.isSuper
                    ? [const Color(0xFF8E0E00), const Color(0xFF1F1C18), const Color(0xFFD4145A)]
                    : [const Color(0xFFB71C1C), const Color(0xFFD32F2F), const Color(0xFFE53935)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: widget.bag.isSuper ? const Color(0xFFFFD700) : const Color(0xFFFFCC80),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.5),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // Red packet icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFA000).withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFFD54F), width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: const Text('🧧', style: TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              isAr
                                  ? (widget.bag.isSuper ? '👑 مظروف سوبر من ${widget.bag.ownerName}' : '🧧 مظروف حظ من ${widget.bag.ownerName}')
                                  : '${widget.bag.ownerName} Red Packet',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFFFF9C4),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.bag.greetingText.isNotEmpty
                            ? widget.bag.greetingText
                            : (isAr ? 'مجموع ${widget.bag.totalValue} 🪙 · ${widget.bag.totalBags} نصيب' : '${widget.bag.totalValue} coins · ${widget.bag.totalBags} shares'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!isExpired)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${seconds}s',
                      style: const TextStyle(
                        color: Color(0xFFFFEB3B),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _grabbing ? null : (widget.onTapOpen ?? _handleGrab),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD54F), Color(0xFFFF8F00)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: _grabbing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            isAr ? 'افتح' : 'Open',
                            style: const TextStyle(
                              color: Color(0xFF5D1000),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
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