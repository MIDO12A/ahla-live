import 'dart:async';
import 'package:flutter/material.dart';
import '../../../config/r.dart';
import '../models/lucky_gift_model.dart';
import 'lucky_card_flip_layout.dart';
import 'room_burst_settlement_dialog.dart';

/// واجهة الكومبو والانفجار لهدايا الحظ (RoomBurstDialog)
/// تتيح للمستخدم الضغط المتتالي السريع مع عداد زمني، وحساب مضاعفات متراكمة
class RoomBurstDialog extends StatefulWidget {
  final LuckyGiftModel gift;
  final String roomId;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final String receiverId;
  final String receiverName;
  final Function(LuckyGiftModel gift, int count, String comboId, int comboCount) onSendBurst;

  const RoomBurstDialog({
    Key? key,
    required this.gift,
    required this.roomId,
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    required this.receiverId,
    required this.receiverName,
    required this.onSendBurst,
  }) : super(key: key);

  @override
  State<RoomBurstDialog> createState() => _RoomBurstDialogState();
}

class _RoomBurstDialogState extends State<RoomBurstDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  int _comboCount = 0;
  int _totalWonGold = 0;
  final List<int> _allMultipliers = [];
  Timer? _countdownTimer;
  double _remainingProgress = 1.0; // من 1.0 إلى 0.0
  static const int _comboTimeoutMs = 3000;
  DateTime _lastTapTime = DateTime.now();
  late String _comboId;

  @override
  void initState() {
    super.initState();
    _comboId = 'combo_${DateTime.now().millisecondsSinceEpoch}';
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      lowerBound: 0.9,
      upperBound: 1.15,
    );
    _pulseAnim = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);

    _startCountdown();
    // إرسال أول ضربة تلقائياً عند الفتح
    _onTapBurst();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    const tickMs = 50;
    _countdownTimer = Timer.periodic(const Duration(milliseconds: tickMs), (timer) {
      final elapsed = DateTime.now().difference(_lastTapTime).inMilliseconds;
      final remaining = (_comboTimeoutMs - elapsed) / _comboTimeoutMs;

      if (remaining <= 0) {
        timer.cancel();
        _onComboFinished();
      } else {
        if (mounted) {
          setState(() {
            _remainingProgress = remaining;
          });
        }
      }
    });
  }

  void _onTapBurst() {
    _lastTapTime = DateTime.now();
    _pulseController.forward().then((_) => _pulseController.reverse());

    setState(() {
      _comboCount++;
    });

    // استدعاء دالة الإرسال في السيرفر
    widget.onSendBurst(widget.gift, 1, _comboId, _comboCount);
    _startCountdown();
  }

  /// تسجيل نتيجة السحب المكتملة من السيرفر
  void updateWithResult(int wonCoins, int multiplier) {
    if (!mounted) return;
    setState(() {
      _totalWonGold += wonCoins;
      _allMultipliers.add(multiplier);
    });
  }

  void _onComboFinished() {
    if (!mounted) return;
    Navigator.of(context).pop();
    // الاستلام تلقائي ومباشر بدون نافذة تسوية أرباح
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Container(
          width: 280,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2E0854), Color(0xFF180B2B)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFFFD700), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withOpacity(0.3),
                blurRadius: 25,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // عنوان الكومبو
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.flash_on, color: Colors.amberAccent, size: 24),
                  Text(
                    'COMBO x$_comboCount',
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // شريط المؤقت الزمني
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: _remainingProgress,
                  minHeight: 8,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _remainingProgress > 0.3 ? const Color(0xFFFF9100) : Colors.redAccent,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // زر الضغط المتتالي السريع (Burst Trigger Button)
              GestureDetector(
                onTap: _onTapBurst,
                child: ScaleTransition(
                  scale: _pulseAnim,
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFF6D00), Color(0xFFD50000)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF6D00).withOpacity(0.7),
                          blurRadius: 20,
                          spreadRadius: 3,
                        ),
                      ],
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image(
                          image: R.cachedImage(widget.gift.giftIconUrl),
                          width: 56,
                          height: 56,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.card_giftcard,
                            color: Colors.white,
                            size: 50,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'اضغط سريعاً!',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              // إجمالي الربح التراكمي المباشر
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  'الأرباح المباشرة: +$_totalWonGold 🪙',
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
