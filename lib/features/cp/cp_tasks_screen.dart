import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../providers/user_provider.dart';
import '../../services/dynamic_config_service.dart';
import 'cp_service.dart';
import 'cp_ranking_screen.dart';

/// Relationship Tasks screen — matches act_relationship_task.xml
/// Shows: header avatars, engagement score, progress bar, daily tasks, bind button.
class CpTasksScreen extends StatefulWidget {
  const CpTasksScreen({super.key});
  @override
  State<CpTasksScreen> createState() => _CpTasksScreenState();
}

class _CpTasksScreenState extends State<CpTasksScreen> {
  Map<String, dynamic> _data = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final data = await CpService.getMyData();
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = DynamicConfigService();
    final couple = _data['couple'] as Map<String, dynamic>?;
    final hasCp = _data['has_cp'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFF2e0d15),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !hasCp
              ? _buildNoCpState()
              : Stack(
                  children: [
                    // Top background
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 200,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF5a1525), Color(0xFF2e0d15)],
                          ),
                        ),
                      ),
                    ),
                    // Content
                    SingleChildScrollView(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top + 60,
                        bottom: 100,
                      ),
                      child: Column(
                        children: [
                          _buildHeaderAvatars(couple),
                          const SizedBox(height: 14),
                          _buildProgressBar(couple),
                          const SizedBox(height: 33),
                          _buildDescription(couple),
                          const SizedBox(height: 20),
                          _buildTodayScorePanel(couple),
                          const SizedBox(height: 10),
                          _buildTasksList(),
                        ],
                      ),
                    ),
                    // Top bar
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 12,
                      right: 12,
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
                            ),
                          ),
                          const Spacer(),
                          // Ranking button
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(55),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                            ),
                            child: GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const CpRankingScreen()),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.emoji_events, color: Color(0xFFffb565), size: 14),
                                  SizedBox(width: 4),
                                  Text('الترتيب', style: TextStyle(color: Colors.white, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Bottom bind button
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: _buildBottomPanel(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildNoCpState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite_border, color: Colors.white24, size: 80),
          const SizedBox(height: 16),
          const Text('ليس لديك علاقة CP',
              style: TextStyle(color: Colors.white54, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildHeaderAvatars(Map<String, dynamic>? couple) {
    final partner = couple?['partner'] as Map<String, dynamic>?;
    final user = context.read<UserProvider>().currentUser;
    final myAvatar = user?.photoUrl ?? '';
    final partnerAvatar = partner?['avatar']?.toString() ?? '';
    final totalScore = (couple?['total_score'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Row(
        children: [
          // My avatar
          ClipOval(
            child: R.loadImage(myAvatar, width: 72, height: 72, fit: BoxFit.cover),
          ),
          // Partner avatar (overlapping)
          Transform.translate(
            offset: const Offset(-7, 0),
            child: ClipOval(
              child: R.loadImage(partnerAvatar, width: 72, height: 72, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 10),
          // Score info
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('نقاط القربى',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('$totalScore',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(Map<String, dynamic>? couple) {
    final totalScore = (couple?['total_score'] as num?)?.toInt() ?? 0;
    final currentLv = _calcLevel(totalScore);
    final nextLv = currentLv + 1;
    final currentLvMin = _lvMinScore(currentLv);
    final nextLvMin = _lvMinScore(nextLv);
    final progress = nextLvMin > currentLvMin
        ? ((totalScore - currentLvMin) / (nextLvMin - currentLvMin)).clamp(0.0, 1.0)
        : 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        children: [
          LayoutBuilder(builder: (context, constraints) {
            return Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4a1020),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  height: 8,
                  width: constraints.maxWidth * progress,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFd32a43), Color(0xFFff6b9d)],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$currentLvMin', style: const TextStyle(color: Colors.white, fontSize: 12)),
              Text('$nextLvMin', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDescription(Map<String, dynamic>? couple) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: const Text(
        'أكمل المهام اليومية لزيادة نقاط القربى ورفع مستوى علاقتكم. كلما زادت نقاطكم، حصلت على مكافآت أفضل!',
        style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildTodayScorePanel(Map<String, dynamic>? couple) {
    final weekScore = (couple?['week_score'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4c1522), Color(0xFF7e141b)],
        ),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFa31b44), width: 1),
      ),
      child: Row(
        children: [
          const Text('نقاط القربى',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          const Spacer(),
          const Text('ربحت اليوم:',
              style: TextStyle(color: Colors.white, fontSize: 14)),
          const SizedBox(width: 7),
          Text('$weekScore',
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTasksList() {
    final tasks = [
      {'title': 'إرسال هدية CP', 'reward': '+10', 'icon': Icons.card_giftcard, 'color': const Color(0xFFff6b9d)},
      {'title': 'الدخول معاً لغرفة', 'reward': '+5', 'icon': Icons.meeting_room, 'color': const Color(0xFFffb565)},
      {'title': 'إرسال رسالة في الغرفة', 'reward': '+2', 'icon': Icons.chat_bubble, 'color': const Color(0xFF64b5f6)},
      {'title': 'مشاهدة بث مشترك', 'reward': '+3', 'icon': Icons.live_tv, 'color': const Color(0xFF81c784)},
      {'title': 'إرسال هدية في الغرفة', 'reward': '+8', 'icon': Icons.favorite, 'color': const Color(0xFFce93d8)},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          ...tasks.map((task) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF4a1020).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF770d1e), width: 1),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: (task['color'] as Color).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(task['icon'] as IconData,
                          color: task['color'] as Color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(task['title'] as String,
                          style: const TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (task['color'] as Color).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${task['reward']} قربى',
                          style: TextStyle(
                              color: task['color'] as Color,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      color: const Color(0xFF2e0d15),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: SafeArea(
        child: GestureDetector(
          onTap: () {
            // Navigate to bind/send invitation
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFd32a43), Color(0xFFff6b9d)],
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFd32a43).withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Text('اربط علاقتك الآن',
                  style: TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ),
    );
  }

  int _calcLevel(int score) {
    if (score >= 1000) return 6;
    if (score >= 500) return 5;
    if (score >= 200) return 4;
    if (score >= 100) return 3;
    if (score >= 30) return 2;
    return 1;
  }

  int _lvMinScore(int lv) {
    return switch (lv) {
      1 => 0,
      2 => 30,
      3 => 100,
      4 => 200,
      5 => 500,
      6 => 1000,
      _ => 0,
    };
  }
}
