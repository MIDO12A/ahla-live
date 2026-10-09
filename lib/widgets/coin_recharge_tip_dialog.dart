import 'package:flutter/material.dart';
import '../config/r.dart';
import '../screens/wallet/wallet_main_screen.dart';

/// Reusable Insufficient Coins / Recharge Tip Dialog
/// Matches authentic dialog_coin_recharge_tip.xml
class CoinRechargeTipDialog extends StatelessWidget {
  final int totalCost;
  final int currentCoins;

  const CoinRechargeTipDialog({
    super.key,
    this.totalCost = 0,
    this.currentCoins = 0,
  });

  static Future<void> show(
    BuildContext context, {
    int totalCost = 0,
    int currentCoins = 0,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => CoinRechargeTipDialog(
        totalCost: totalCost,
        currentCoins: currentCoins,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 25, 20, 25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // FrameLayout matching dialog_coin_recharge_tip.xml: shadow_coins + dialog_coins
            SizedBox(
              height: 125,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 45,
                    child: Image.asset(
                      'assets/mipmap-xxhdpi/shadow_coins.png',
                      width: 120,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  Image.asset(
                    'assets/mipmap-xxhdpi/dialog_coins.png',
                    width: 100,
                    height: 100,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.monetization_on_rounded,
                      size: 80,
                      color: Color(0xFFFFD700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // tvContent (18sp #333333 matching dialog_coin_recharge_tip.xml)
            Text(
              isAr
                  ? 'رصيد العملات غير كافٍ،\nهل ترغب في الشحن للحصول على المزيد؟'
                  : 'Insufficient coins balance.\nWould you like to recharge for more?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
                height: 1.35,
              ),
            ),

            if (totalCost > 0) ...[
              const SizedBox(height: 8),
              Text(
                isAr
                    ? 'المطلوب: ${R.formatCoins(totalCost)} كوينز  |  لديك: ${R.formatCoins(currentCoins)} كوينز'
                    : 'Required: ${R.formatCoins(totalCost)} coins  |  Available: ${R.formatCoins(currentCoins)} coins',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF888888),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Action buttons: btnCancel + btnConfirm
            Row(
              children: [
                // btnCancel: #f5f5f5, radius 20, text #555555 "إلغاء"
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF5F5F5),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: Text(
                        isAr ? 'إلغاء' : 'Cancel',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF555555),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // btnConfirm: gradient #00deff -> #14fab1, radius 20, text white "شحن الآن"
                Expanded(
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00DEFF), Color(0xFF14FAB1)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF14FAB1).withOpacity(0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const WalletMainScreen(),
                            ),
                          );
                        },
                        child: Center(
                          child: Text(
                            isAr ? 'شحن الآن' : 'Recharge Now',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
