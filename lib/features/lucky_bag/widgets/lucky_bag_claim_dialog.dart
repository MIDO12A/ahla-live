import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/user_provider.dart';
import '../models/lucky_bag_model.dart';
import '../services/lucky_bag_service.dart';

/// حوار فتح حقيبة الحظ المطابق لـ dialog_luckybag_open.xml
/// يدعم حالتي dialog_luckybag_ready_to_open.xml و dialog_luckybag_opened.xml
class LuckyBagClaimDialog extends StatefulWidget {
  final LuckyBagModel bag;
  final String roomId;

  const LuckyBagClaimDialog({
    super.key,
    required this.bag,
    required this.roomId,
  });

  static Future<void> show(BuildContext context, {required LuckyBagModel bag, required String roomId}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => LuckyBagClaimDialog(bag: bag, roomId: roomId),
    );
  }

  @override
  State<LuckyBagClaimDialog> createState() => _LuckyBagClaimDialogState();
}

class _LuckyBagClaimDialogState extends State<LuckyBagClaimDialog> with SingleTickerProviderStateMixin {
  bool _isOpen = false;
  bool _loading = false;
  int _wonAmount = 0;
  String? _errorMessage;
  late LuckyBagModel _currentBag;
  List<LuckyBagClaim> _claims = [];

  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _currentBag = widget.bag;
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _scaleAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack);
    _animCtrl.forward();

    _fetchDetails();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchDetails() async {
    final details = await LuckyBagService().getLuckyBagDetails(_currentBag.bagId);
    if (!mounted || details == null) return;

    final bagData = details['bag'] as Map<String, dynamic>?;
    final claimsData = details['claims'] as List<dynamic>?;

    final user = Provider.of<UserProvider>(context, listen: false).currentUser;
    final myUid = user?.uid;

    setState(() {
      if (bagData != null) {
        _currentBag = LuckyBagModel.fromJson(bagData);
      }
      if (claimsData != null) {
        _claims = claimsData.map((c) => LuckyBagClaim.fromJson(c as Map<String, dynamic>)).toList();
        if (myUid != null) {
          final myClaim = _claims.where((c) => c.claimerId == myUid).firstOrNull;
          if (myClaim != null) {
            _isOpen = true;
            _wonAmount = myClaim.amount;
          }
        }
      }
    });
  }

  Future<void> _handleOpen() async {
    if (_loading || _isOpen) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final res = await LuckyBagService().grabLuckyBag(
      roomId: widget.roomId,
      bagId: _currentBag.bagId,
    );

    if (!mounted) return;

    if (res.success) {
      setState(() {
        _loading = false;
        _isOpen = true;
        _wonAmount = res.amount;
      });
      _fetchDetails();
    } else {
      setState(() {
        _loading = false;
        _errorMessage = res.error ?? 'فشل فتح الحقيبة، ربما نفذت الحصص';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    return Center(
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Material(
          color: Colors.transparent,
          child: _isOpen ? _buildOpenedView(isAr) : _buildReadyToOpenView(isAr),
        ),
      ),
    );
  }

  /// حالة الاستعداد للفتح المطابقة لـ dialog_luckybag_ready_to_open.xml
  Widget _buildReadyToOpenView(bool isAr) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 290,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ic_luckybag_ready_open
              Image.asset(
                'assets/images/ic_luckybag_ready_open.png',
                width: 290,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  height: 320,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC62828),
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),

              // Sender Avatar & Name at upper section
              Positioned(
                top: 48,
                child: Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFFD54F), width: 2),
                      ),
                      child: ClipOval(
                        child: _currentBag.ownerAvatar.isNotEmpty
                            ? Image.network(
                                _currentBag.ownerAvatar,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _avatarFallback(),
                              )
                            : _avatarFallback(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _currentBag.ownerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _currentBag.greetingText.isNotEmpty
                          ? _currentBag.greetingText
                          : (isAr ? 'أرسل لك حقيبة حظ 🧧' : 'Sent a Lucky Bag 🧧'),
                      style: const TextStyle(
                        color: Color(0xFFFFF9C4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // Error message if any
              if (_errorMessage != null)
                Positioned(
                  bottom: 74,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

              // openBtn: ic_send_luckybag_btn (height 47dp, bottom 27dp)
              Positioned(
                bottom: 24,
                child: GestureDetector(
                  onTap: _loading ? null : _handleOpen,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset(
                        'assets/images/ic_send_luckybag_btn.png',
                        height: 47,
                        fit: BoxFit.contain,
                      ),
                      if (_loading)
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFFAF4C25)),
                        )
                      else
                        Text(
                          isAr ? 'فتح' : 'OPEN',
                          style: const TextStyle(
                            color: Color(0xFFAF4C25),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // closeBtn: 32x32dp
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white70, width: 1.5),
            ),
            child: const Icon(Icons.close, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }

  /// حالة بعد الفتح المطابقة لـ dialog_luckybag_opened.xml
  Widget _buildOpenedView(bool isAr) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 277,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ic_luckybag_opened_bg
              Image.asset(
                'assets/images/ic_luckybag_opened_bg.png',
                width: 277,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  height: 360,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC62828),
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),

              // Content inside opened background
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 70),

                    // userHeader (60x60dp)
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFFD54F), width: 2),
                      ),
                      child: ClipOval(
                        child: _currentBag.ownerAvatar.isNotEmpty
                            ? Image.network(
                                _currentBag.ownerAvatar,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _avatarFallback(),
                              )
                            : _avatarFallback(),
                      ),
                    ),
                    const SizedBox(height: 4),

                    // title (sender name)
                    Text(
                      _currentBag.ownerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // icon of prize (coins)
                    Image.asset(
                      'assets/images/common_gold_ic_3.png',
                      width: 72,
                      height: 72,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.monetization_on,
                        color: Color(0xFFFFD700),
                        size: 64,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // num (amount won)
                    Text(
                      '+ 🪙',
                      style: const TextStyle(
                        color: Color(0xFFFFFDBD),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const Spacer(),

                    // confirmBtn: ic_send_luckybag_btn (width 251dp, height 47dp)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Image.asset(
                              'assets/images/ic_send_luckybag_btn.png',
                              width: 220,
                              height: 45,
                              fit: BoxFit.fill,
                            ),
                            Text(
                              isAr ? 'تأكيد' : 'Confirm',
                              style: const TextStyle(
                                color: Color(0xFFAF4C25),
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // closeBtn
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white70, width: 1.5),
            ),
            child: const Icon(Icons.close, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _avatarFallback() {
    return Container(
      color: Colors.black26,
      child: const Icon(Icons.person, color: Colors.white, size: 30),
    );
  }
}
