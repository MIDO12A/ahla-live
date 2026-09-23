import 'dart:async';
import 'package:flutter/material.dart';
import '../models/lucky_bag_model.dart';
import 'lucky_bag_claim_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
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
                    color: const Color(0xFFFBA806).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFBA806), width: 1),
                  ),
                  child: Text(
                    isAr ? 'حقائب الحظ النشطة ()' : 'Active Lucky Bags ()',
                    style: const TextStyle(
                      color: Color(0xFFFBA806),
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
                      child: Text(
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
                      childAspectRatio: 0.85,
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
              children: [
                Image.asset(
                  'assets/images/ic_luckybag.png',
                  width: 65,
                  height: 65,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.card_giftcard,
                    color: Color(0xFFFBA806),
                    size: 48,
                  ),
                ),
                // countDownTv / remaining value badge at bottom of icon
                Positioned(
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xB3000000), // black_trans_70
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: Colors.white, width: 0.6),
                    ),
                    child: Text(
                      ' 🪙',
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
          const SizedBox(height: 4),
          // nameTv
          Text(
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
        ],
      ),
    );
  }
}
