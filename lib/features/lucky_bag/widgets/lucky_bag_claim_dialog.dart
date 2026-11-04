import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/r.dart';
import '../../../providers/user_provider.dart';
import '../models/lucky_bag_config.dart';
import '../models/lucky_bag_model.dart';
import '../services/lucky_bag_service.dart';
import 'package:zero/core/dtext.dart';

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
  Timer? _refreshTimer;
  Timer? _countdownTimer;
  LuckyBagConfig _config = const LuckyBagConfig();

  @override
  void initState() {
    super.initState();
    _currentBag = widget.bag;
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _scaleAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack);
    _animCtrl.forward();

    LuckyBagService().loadConfig().then((cfg) {
      if (mounted) setState(() => _config = cfg);
    });

    _fetchDetails();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _fetchDetails(),
    );
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _countdownTimer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  Duration get _remaining {
    final expires = DateTime.tryParse(_currentBag.expiresAt ?? '');
    if (expires == null) return Duration.zero;
    final diff = expires.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  String get _remainingLabel {
    final s = _remaining.inSeconds;
    if (s <= 0) return 'انتهى الوقت';
    final m = s ~/ 60;
    final sec = s % 60;
    return m > 0
        ? '$m:${sec.toString().padLeft(2, '0')}'
        : '$sec ثانية';
  }

  bool get _isExpired => _remaining.inSeconds <= 0;

  Color _parseColor(String raw, Color fallback) {
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

  Color get _primary => _parseColor(_config.primaryColor, const Color(0xFFFFF295));
  Color get _countdownColor =>
      _parseColor(_config.countdownColor, const Color(0xCC000000));

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

      // إذا انتهت الحقيبة أو لم يتبقَّ أنصبة ولم يكن المستخدم قد استلم بعد
      if (!_isOpen && _currentBag.status != 'active' && _errorMessage == null) {
        _errorMessage = _currentBag.status == 'expired' || _isExpired
            ? 'انتهت صلاحية الحقيبة'
            : 'تم توزيع كل الأنصبة';
      }
    });
  }

  Future<void> _handleOpen() async {
    if (_loading || _isOpen) return;
    if (_isExpired || _currentBag.status != 'active') {
      setState(() {
        _errorMessage = _currentBag.status == 'expired' || _isExpired
            ? 'انتهت صلاحية الحقيبة'
            : 'تم توزيع كل الأنصبة';
      });
      return;
    }
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
                            ? Image(
                                image: R.cachedImage(_currentBag.ownerAvatar),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _avatarFallback(),
                              )
                            : _avatarFallback(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    DText(
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
                    DText(
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

              // العدّاد التنازلي لصلاحية الحقيبة
              Positioned(
                top: 146,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.86),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DText(
                    _remainingLabel,
                    style: TextStyle(
                      color: _countdownColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
                    child: DText(
                      _errorMessage!,
                      style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

              // openBtn: ic_send_luckybag_btn (height 47dp, bottom 27dp)
              Positioned(
                bottom: 24,
                child: Opacity(
                  opacity: (_isExpired || _currentBag.status != 'active') ? 0.5 : 1,
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
                          DText(
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
                child: Padding(
                  padding: const EdgeInsets.only(top: 62, bottom: 12, left: 18, right: 18),
                  child: Column(
                    children: [
                      // userHeader
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _primary, width: 2),
                        ),
                        child: ClipOval(
                          child: _currentBag.ownerAvatar.isNotEmpty
                              ? Image(
                                  image: R.cachedImage(_currentBag.ownerAvatar),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _avatarFallback(),
                                )
                              : _avatarFallback(),
                        ),
                      ),
                      const SizedBox(height: 4),

                      // title (sender name)
                      DText(
                        _currentBag.ownerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),

                      // icon of prize (coins)
                      Image.asset(
                        'assets/images/common_gold_ic_3.png',
                        width: 50,
                        height: 50,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.monetization_on,
                          color: Color(0xFFFFD700),
                          size: 46,
                        ),
                      ),
                      const SizedBox(height: 2),

                      // num (amount won) — القيمة الفعلية التي استلمها المستخدم
                      DText(
                        '+ $_wonAmount 🪙',
                        style: TextStyle(
                          color: _primary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // ملخص الحقيبة + العدّاد
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _chip(
                            isAr
                                ? 'الإجمالي ${_currentBag.totalValue}'
                                : 'Total ${_currentBag.totalValue}',
                          ),
                          const SizedBox(width: 6),
                          _chip(
                            isAr
                                ? 'متبقي ${_currentBag.remainingCount}'
                                : 'Left ${_currentBag.remainingCount}',
                          ),
                          const SizedBox(width: 6),
                          _chip(_remainingLabel, color: _countdownColor),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // المستلمون
                      Row(
                        children: [
                          DText(
                            isAr ? 'المستلمون' : 'Winners',
                            style: const TextStyle(
                              color: Color(0xFFFFF9C4),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          DText(
                            '${_claims.length}/${_currentBag.totalShares}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Expanded(child: _buildWinnersList(isAr)),
                      const SizedBox(height: 6),

                      // confirmBtn
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Image.asset(
                              'assets/images/ic_send_luckybag_btn.png',
                              width: 210,
                              height: 42,
                              fit: BoxFit.fill,
                            ),
                            DText(
                              isAr ? 'تأكيد' : 'Confirm',
                              style: const TextStyle(
                                color: Color(0xFFAF4C25),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
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

  Widget _chip(String text, {Color color = const Color(0xFF134015)}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(9),
      ),
      child: DText(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildWinnersList(bool isAr) {
    if (_claims.isEmpty) {
      return Center(
        child: DText(
          isAr ? 'لا يوجد مستلمون بعد' : 'No winners yet',
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      );
    }
    final sorted = [..._claims]..sort((a, b) {
        if (a.isLuckiest != b.isLuckiest) return a.isLuckiest ? -1 : 1;
        return b.amount.compareTo(a.amount);
      });
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
        itemCount: sorted.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: Colors.white.withValues(alpha: 0.08),
        ),
        itemBuilder: (context, index) {
          final c = sorted[index];
          final highlight = c.isLuckiest;
          return SizedBox(
            height: 28,
            child: Row(
              children: [
                Icon(
                  Icons.emoji_events,
                  size: 12,
                  color: highlight ? const Color(0xFFFFD54F) : Colors.white38,
                ),
                const SizedBox(width: 3),
                Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white24,
                  ),
                  child: ClipOval(
                    child: c.claimerAvatar.isNotEmpty
                        ? Image(
                            image: R.cachedImage(c.claimerAvatar),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.person,
                              size: 12,
                              color: Colors.white70,
                            ),
                          )
                        : const Icon(
                            Icons.person,
                            size: 12,
                            color: Colors.white70,
                          ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: DText(
                    c.claimerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: highlight ? const Color(0xFFFFD54F) : Colors.white,
                      fontSize: 11,
                    ),
                  ),
                ),
                DText(
                  '${c.amount} 🪙',
                  style: const TextStyle(
                    color: Color(0xFFFFF9C4),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _avatarFallback() {
    return Container(
      color: Colors.black26,
      child: const Icon(Icons.person, color: Colors.white, size: 30),
    );
  }
}
