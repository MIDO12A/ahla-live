import 'dart:async';
import 'package:flutter/material.dart';
import '../../../config/r.dart';
import '../models/lucky_bag_config.dart';
import '../models/lucky_bag_model.dart';
import '../services/lucky_bag_service.dart';
import 'lucky_bag_claim_dialog.dart';
import 'package:zero/core/dtext.dart';

/// قائمة حقائب الحظ المتاحة في الغرفة المطابقة لـ dialog_luckybag_list.xml
class LuckyBagListDialog extends StatefulWidget {
  final String roomId;
  final List<LuckyBagModel> bags;

  const LuckyBagListDialog({
    super.key,
    required this.roomId,
    required this.bags,
  });

  static Future<void> show(
    BuildContext context, {
    required String roomId,
    required List<LuckyBagModel> bags,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => LuckyBagListDialog(roomId: roomId, bags: bags),
    );
  }

  @override
  State<LuckyBagListDialog> createState() => _LuckyBagListDialogState();
}

class _LuckyBagListDialogState extends State<LuckyBagListDialog> {
  Timer? _timer;
  LuckyBagConfig _config = const LuckyBagConfig();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    LuckyBagService().loadConfig().then((cfg) {
      if (mounted) setState(() => _config = cfg);
    });
  }

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

  Color get _primary =>
      _parseColor(_config.primaryColor, const Color(0xFFFBA806));
  Color get _countdownColor =>
      _parseColor(_config.countdownColor, const Color(0xB3000000));

  Duration _remaining(LuckyBagModel bag) {
    final expires = DateTime.tryParse(bag.expiresAt ?? '');
    if (expires == null) return Duration.zero;
    final diff = expires.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  String _formatRemaining(LuckyBagModel bag) {
    final total = _remaining(bag).inSeconds;
    if (total <= 0) return 'انتهى';
    final m = total ~/ 60;
    final s = total % 60;
    if (m > 0) return '$m:${s.toString().padLeft(2, '0')}';
    return '${s}s';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      decoration: const BoxDecoration(
        color: Color(0xE6000000), // black_trans_90
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Header / Tab bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _primary, width: 1),
                  ),
                  child: DText(
                    isAr
                        ? 'حقائب الحظ النشطة (${widget.bags.length})'
                        : 'Active Lucky Bags (${widget.bags.length})',
                    style: TextStyle(
                      color: _primary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.white12),

          // Bags Grid / List (vh_luckybag_list_item.xml)
          Flexible(
            child: widget.bags.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: DText(
                        isAr ? 'لا توجد حقائب حظ حالياً' : 'No lucky bags available',
                        style: const TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.62,
                    ),
                    itemCount: widget.bags.length,
                    itemBuilder: (context, index) {
                      final bag = widget.bags[index];
                      return _buildBagItem(bag, isAr);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBagItem(LuckyBagModel bag, bool isAr) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop();
        LuckyBagClaimDialog.show(
          context,
          bag: bag,
          roomId: widget.roomId,
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 65dp x 65dp luckybagIv (vh_luckybag_list_item.xml)
          SizedBox(
            width: 65,
            height: 65,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                _config.bagImage.trim().isNotEmpty
                    ? Image(
                        image: R.cachedImage(_config.bagImage),
                        width: 65,
                        height: 65,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => _fallbackBagIcon(),
                      )
                    : Image.asset(
                        'assets/images/ic_luckybag.png',
                        width: 65,
                        height: 65,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => _fallbackBagIcon(),
                      ),
                // عدد الحقائب المتبقية
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF2442),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 0.8),
                    ),
                    child: DText(
                      '${bag.remainingCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // العدّاد التنازلي أسفل الصورة
                Positioned(
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: _countdownColor,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: Colors.white, width: 0.6),
                    ),
                    child: DText(
                      _formatRemaining(bag),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // nameTv
          DText(
            bag.ownerName.isNotEmpty ? bag.ownerName : (isAr ? 'حقيبة الحظ' : 'Lucky Bag'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          // القيمة المتبقية داخل الحقيبة
          DText(
            '${bag.remainingValue} 🪙',
            style: TextStyle(
              color: _primary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackBagIcon() {
    return Icon(
      Icons.card_giftcard,
      color: _primary,
      size: 48,
    );
  }
}
