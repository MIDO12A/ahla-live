import 'package:flutter/material.dart';
import '../data/agency_models.dart';
import '../data/agency_repository.dart';

class AgencyLevelDescScreen extends StatefulWidget {
  const AgencyLevelDescScreen({super.key});

  @override
  State<AgencyLevelDescScreen> createState() => _AgencyLevelDescScreenState();
}

class _AgencyLevelDescScreenState extends State<AgencyLevelDescScreen> {
  List<AgencyLevelConfigModel> _levels = [];
  List<AgencyExpTaskModel> _tasks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final lvls = await AgencyRepository.getAgencyLevelConfigs();
      final tasks = await AgencyRepository.getAgencyExpTasks();
      if (mounted) {
        setState(() {
          _levels = lvls;
          _tasks = tasks;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C2979),
      appBar: AppBar(
        title: const Text('مستويات وامتيازات الوكالة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0C2979),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildHowToEarnCard(),
                  const SizedBox(height: 16),
                  _buildLevelsCards(),
                  const SizedBox(height: 16),
                  _buildRulesCard(),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  /// بطاقة مهام نمو نقاط الخبرة (EXP Tasks)
  Widget _buildHowToEarnCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B3B98),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt, color: Colors.amber, size: 24),
              SizedBox(width: 8),
              Text('مهام نمو نقاط الخبرة للوكالة (EXP)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'يقوم مضيفو وأعضاء الوكالة بالمشاركة في الأنشطة التالية لاكتساب نقاط الخبرة ورفع مستوى الوكالة تلقائياً:',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          ..._tasks.map((task) => _buildTaskItem(task)),
        ],
      ),
    );
  }

  Widget _buildTaskItem(AgencyExpTaskModel task) {
    IconData iconData = Icons.star;
    Color iconColor = Colors.amber;
    if (task.key.contains('seat') || task.iconName == 'Mic') {
      iconData = Icons.mic;
      iconColor = Colors.amberAccent;
    } else if (task.key.contains('luck') || task.iconName == 'Dices') {
      iconData = Icons.casino;
      iconColor = Colors.purpleAccent;
    } else if (task.key.contains('recharge') || task.iconName == 'CreditCard') {
      iconData = Icons.credit_card;
      iconColor = Colors.greenAccent;
    } else if (task.key.contains('gift') || task.iconName == 'Gift') {
      iconData = Icons.card_giftcard;
      iconColor = Colors.pinkAccent;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(iconData, color: iconColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      task.titleAr.isNotEmpty ? task.titleAr : task.title,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.withOpacity(0.3)),
                      ),
                      child: Text(
                        task.expRateDesc,
                        style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  task.description,
                  style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                ),
                if (task.dailyMaxExp > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '• الحد الأقصى اليومي: ${task.dailyMaxExp} EXP',
                      style: const TextStyle(color: Colors.cyanAccent, fontSize: 10),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// بطاقات مستويات الوكالة ومكافآت المضيفين
  Widget _buildLevelsCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text(
            'مستويات الوكالة ومكافآت المضيفين 🏆',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        ..._levels.map((lvl) => _buildSingleLevelCard(lvl)),
      ],
    );
  }

  Widget _buildSingleLevelCard(AgencyLevelConfigModel lvl) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Level name + EXP
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF223E9E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'المستوى ${lvl.level}',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    lvl.levelName,
                    style: const TextStyle(color: Color(0xFF1B3B98), fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '⚡ ${lvl.minExp} EXP',
                  style: const TextStyle(color: Color(0xFF223E9E), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFE8EDFF)),
          const SizedBox(height: 10),

          // Rewards section
          Row(
            children: [
              const Icon(Icons.card_giftcard, size: 16, color: Colors.amber),
              const SizedBox(width: 6),
              const Text('مكافأة كل مضيف نشط بالوكالة:', style: TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),

          // Coins & Diamonds Badges
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (lvl.rewardCoins > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🪙', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                        '${lvl.rewardCoins} كوينز',
                        style: const TextStyle(color: Color(0xFFB8860B), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              if (lvl.rewardDiamonds > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.cyan.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('💎', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                        '${lvl.rewardDiamonds} ماسة',
                        style: const TextStyle(color: Colors.teal, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // Store Items Rewards
          if (lvl.storeRewardItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('جوائز المتجر المودعة بالحقيبة:', style: TextStyle(color: Colors.black54, fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: lvl.storeRewardItems.map((item) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFD8B4FE)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.itemIcon.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            item.itemIcon,
                            width: 18,
                            height: 18,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(Icons.inventory_2, size: 14, color: Colors.purple),
                          ),
                        )
                      else
                        const Icon(Icons.inventory_2, size: 14, color: Colors.purple),
                      const SizedBox(width: 5),
                      Text(item.itemName, style: const TextStyle(color: Color(0xFF6B21A8), fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      Text(
                        item.days == 0 ? '(دائم)' : '(${item.days} يوم)',
                        style: const TextStyle(color: Color(0xFF9333EA), fontSize: 10),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          // Reason / Justification
          if (lvl.rewardReason != null && lvl.rewardReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: Color(0xFFD97706)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'السبب: ${lvl.rewardReason}',
                      style: const TextStyle(color: Color(0xFF92400E), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('سعة المشرفين: ${lvl.adminLimit}', style: const TextStyle(color: Colors.black54, fontSize: 11)),
              Text('سعة الأعضاء: ${lvl.membersLimit}', style: const TextStyle(color: Colors.black54, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRulesCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B3B98),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: Colors.cyanAccent, size: 24),
              SizedBox(width: 8),
              Text('شروط الترقية والحفاظ على المستوى', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '1. الترقية (Upgrade): تحدث الترقية فوراً في أي وقت بمجرد وصول نقاط الخبرة لتارجت المستوى الجديد، وتُصرف المكافآت لكافة المضيفين بالوكالة.\n\n'
            '2. الحفاظ على المستوى (Maintain): يجب تحقيق 30% على الأقل من نقاط المستوى شهرياً للحفاظ على رتبة الوكالة.\n\n'
            '3. التخفيض (Downgrade): إذا لم تحقق الوكالة حد الـ 30% خلال الشهر، سيتم تخفيض المستوى تلقائياً في بداية الشهر التالي.',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

