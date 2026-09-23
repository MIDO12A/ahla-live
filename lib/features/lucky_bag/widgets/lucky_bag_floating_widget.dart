import 'package:flutter/material.dart';
import '../models/lucky_bag_model.dart';
import '../services/lucky_bag_service.dart';
import 'lucky_bag_claim_dialog.dart';
import 'lucky_bag_list_dialog.dart';

/// أيقونة حقيبة الحظ العائمة داخل الغرفة المطابقة لـ view_luckybag_item.xml
/// الحجم: 52.0dp x 52.0dp مع عداد تنازلي وشارة العدد
class LuckyBagFloatingWidget extends StatefulWidget {
  final String roomId;

  const LuckyBagFloatingWidget({super.key, required this.roomId});

  @override
  State<LuckyBagFloatingWidget> createState() => _LuckyBagFloatingWidgetState();
}

class _LuckyBagFloatingWidgetState extends State<LuckyBagFloatingWidget> with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _scaleAnim;

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
  }

  @override
  void dispose() {
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

        final currentBag = bags.first;

        return ScaleTransition(
          scale: _scaleAnim,
          child: GestureDetector(
            onTap: () {
              if (bags.length > 1) {
                LuckyBagListDialog.show(
                  context,
                  roomId: widget.roomId,
                  bags: bags,
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
              width: 52,
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // luckybagIv (52x52dp with ic_luckybag)
                  Image.asset(
                    'assets/images/ic_luckybag.png',
                    width: 52,
                    height: 52,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.card_giftcard,
                      color: Color(0xFFFBA806),
                      size: 40,
                    ),
                  ),

                  // countDownTv (ShapeTextView: 8dp, black_trans_70, stroke white, text white)
                  Positioned(
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                  // numDot / count badge at top right
                  if (bags.length > 1)
                    PositionedDirectional(
                      top: -2,
                      end: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF2442),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                        child: Text(
                          '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
}
