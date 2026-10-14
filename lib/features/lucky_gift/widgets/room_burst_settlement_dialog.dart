import 'package:flutter/material.dart';
import '../models/lucky_gift_model.dart';

/// نافذة تسوية أرباح الانفجار والكومبو (RoomBurstSettlementDialog)
/// تظهر بعد انتهاء مؤقت الضغط المتتالي لحصر إجمالي المضاعفات والأرباح
class RoomBurstSettlementDialog extends StatefulWidget {
  final LuckyGiftModel gift;
  final int comboCount;
  final int totalWonGold;
  final List<int> multipliers;

  const RoomBurstSettlementDialog({
    Key? key,
    required this.gift,
    required this.comboCount,
    required this.totalWonGold,
    required this.multipliers,
  }) : super(key: key);

  @override
  State<RoomBurstSettlementDialog> createState() => _RoomBurstSettlementDialogState();
}

class _RoomBurstSettlementDialogState extends State<RoomBurstSettlementDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
