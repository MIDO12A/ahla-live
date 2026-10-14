import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../config/r.dart';
import '../models/lucky_gift_model.dart';

/// واجهة كروت الحظ ثلاثية الأبعاد (3D Flip Card Layout)
/// مطابقة لنظام ChatRoomLuckyGiftLayout (صفين، 8 كروت كحد أقصى للجولة مع دوران 3D تتابعي)
class LuckyCardFlipLayout extends StatefulWidget {
  final LuckyGiftBroadcastData data;
  final VoidCallback onFinished;

  const LuckyCardFlipLayout({
    Key? key,
    required this.data,
    required this.onFinished,
  }) : super(key: key);

  @override
  State<LuckyCardFlipLayout> createState() => _LuckyCardFlipLayoutState();
}

class _LuckyCardFlipLayoutState extends State<LuckyCardFlipLayout>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _flipAnimations;
  int _currentFlippingIndex = 0;
  bool _wasFinished = false;
  Timer? _safetyTimer;

  void _finishOnce() {
    if (_wasFinished) return;
    _wasFinished = true;
    _safetyTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onFinished();
    });
  }

  @override
  void initState() {
    super.initState();
    // مهلة أمان: مهما حدث (بيانات ناقصة، استثناء، إلغاء) نحرر الطابور
    // حتى لا تعلق الشاشة بطبقة الحظ إلى الأبد (كان سبب التجميد).
    _safetyTimer = Timer(const Duration(seconds: 12), _finishOnce);

    final cardCount = min(widget.data.cards.length, 8);
    _controllers = List.generate(
      cardCount,
      (index) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400),
      ),
    );

    _flipAnimations = _controllers.map((ctrl) {
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: ctrl, curve: Curves.easeInOutBack),
      );
    }).toList();

    _startSequentialFlipping();
  }

  void _startSequentialFlipping() async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      for (int i = 0; i < _controllers.length; i++) {
        if (!mounted) return;
        setState(() => _currentFlippingIndex = i);
        await _controllers[i].forward();
        widget.data.cards[i].isFlipped = true;
        await Future.delayed(const Duration(milliseconds: 150));
      }

      // الانتظار بعد كشف جميع الكروت ثم الإغلاق التلقائي
      await Future.delayed(const Duration(milliseconds: 2500));
      if (mounted) {
        _finishOnce();
      }
    } catch (_) {
      // أي خطأ: لا نترك الشاشة معلقة
      _finishOnce();
    }
  }

  @override
  void dispose() {
    _safetyTimer?.cancel();
    _controllers.forEach((ctrl) {
      if (ctrl.isAnimating) ctrl.stop();
      ctrl.dispose();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.data.cards.take(8).toList();
    final topCards = cards.take(4).toList();
    final bottomCards = cards.skip(4).take(4).toList();

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.85),
                const Color(0xFF1F0D3D).withOpacity(0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFFFD700).withOpacity(0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withOpacity(0.25),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // رأس النافذة: معلومات المرسل والمستلم والهدية
              _buildHeader(),
              const SizedBox(height: 16),

              // الصف العلوي للكروت (حتى 4 كروت)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(topCards.length, (index) {
                  return _build3DCard(index, topCards[index]);
                }),
              ),

              if (bottomCards.isNotEmpty) ...[
                const SizedBox(height: 12),
                // الصف السفلي للكروت (حتى 4 كروت)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(bottomCards.length, (index) {
                    final cardIdx = index + 4;
                    return _build3DCard(cardIdx, bottomCards[index]);
                  }),
                ),
              ],

              const SizedBox(height: 16),
              // إجمالي الربح
              _buildTotalSummary(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFF9800).withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFFB300)),
          ),
          child: Row(
            children: [
              const Text('🍀 ', style: TextStyle(fontSize: 16)),
              Text(
                '${widget.data.senderName} أرسل ${widget.data.gift.giftNameAr}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (widget.data.comboCount > 1) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Combo x${widget.data.comboCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _build3DCard(int index, LuckyCardResult card) {
    return AnimatedBuilder(
      animation: _flipAnimations[index],
      builder: (context, child) {
        final angle = _flipAnimations[index].value * pi;
        final isBack = angle > (pi / 2);

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.002)
            ..rotateY(angle),
          child: Container(
            width: 74,
            height: 108,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: isBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(pi),
                    child: _buildCardBack(card),
                  )
                : _buildCardFront(),
          ),
        );
      },
    );
  }

  Widget _buildCardFront() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [Color(0xFF8A2387), Color(0xFFE94057), Color(0xFFF27121)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.4),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: const Color(0xFFFFD700), width: 1.2),
      ),
      child: const Center(
        child: Icon(
          Icons.help_outline_rounded,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildCardBack(LuckyCardResult card) {
    final isWin = card.multiplier > 0;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: isWin
              ? [const Color(0xFF2C3E50), const Color(0xFF000000)]
              : [Colors.grey.shade800, Colors.black],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(
          color: isWin
              ? (card.multiplier >= 10 ? const Color(0xFFFFD700) : const Color(0xFF00E676))
              : Colors.grey.shade600,
          width: 1.5,
        ),
        boxShadow: isWin
            ? [
                BoxShadow(
                  color: (card.multiplier >= 10 ? Colors.amber : Colors.green)
                      .withOpacity(0.5),
                  blurRadius: 8,
                )
              ]
            : [],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isWin) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: card.multiplier >= 10 ? Colors.amber.shade900 : Colors.green.shade800,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${card.multiplier}X',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Image(
              image: R.cachedImage(card.giftIcon.isNotEmpty ? card.giftIcon : widget.data.gift.giftIconUrl),
              width: 38,
              height: 38,
              errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard, color: Colors.amber, size: 36),
            ),
            const SizedBox(height: 4),
            Text(
              '+${card.wonCoins}',
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ] else ...[
            const Icon(Icons.sentiment_dissatisfied, color: Colors.white54, size: 30),
            const SizedBox(height: 4),
            const Text(
              'حظ أوفر',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTotalSummary() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'إجمالي الجائزة: ',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const Icon(Icons.monetization_on, color: Color(0xFFFFD700), size: 18),
          const SizedBox(width: 4),
          Text(
            '${widget.data.totalWonCoins} كوينز',
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
