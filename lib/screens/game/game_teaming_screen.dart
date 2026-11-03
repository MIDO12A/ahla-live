import 'package:flutter/material.dart';
import '../../config/r.dart';
import '../../config/app_colors.dart';
import 'package:zero/core/dtext.dart';

class GameTeamingScreen extends StatefulWidget {
  const GameTeamingScreen({super.key});

  @override
  State<GameTeamingScreen> createState() => _GameTeamingScreenState();
}

class _GameTeamingScreenState extends State<GameTeamingScreen> {
  final TextEditingController _searchController = TextEditingController();
  final List<Map<String, String>> _games = [
    {'name': 'ببجي', 'icon': '🎮', 'players': '٢٬٥٠٠ لاعب'},
    {'name': 'فري فاير', 'icon': '🔥', 'players': '١٬٨٠٠ لاعب'},
    {'name': 'فورتنايت', 'icon': '⚔️', 'players': '٣٬٢٠٠ لاعب'},
    {'name': 'كول أوف ديوتي', 'icon': '🔫', 'players': '٢٬١٠٠ لاعب'},
    {'name': 'فيفا', 'icon': '⚽', 'players': '١٬٥٠٠ لاعب'},
    {'name': 'كراش', 'icon': '🟣', 'players': '٩٠٠ لاعب'},
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.roomBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: R.image(R.backIc, width: 28, height: 28),
                  ),
                  const SizedBox(width: 8),
                  const DText(
                    'تشكيلة الألعاب',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _searchController,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'ابحث عن لعبة...',
                  hintStyle: const TextStyle(color: AppColors.textTertiary),
                  hintTextDirection: TextDirection.rtl,
                  prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 22),
                  filled: true,
                  fillColor: AppColors.cardBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: _games.length,
                itemBuilder: (context, index) => _buildGameCard(_games[index]),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: BoxDecoration(
                color: AppColors.roomBg,
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.giftBtnGradient,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Center(
                  child: DText(
                    'إنشاء غرفة',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameCard(Map<String, String> game) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Stack(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primaryBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: DText(
                    game['icon']!,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              DText(
                game['name']!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              DText(
                game['players']!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.greenAccent,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
