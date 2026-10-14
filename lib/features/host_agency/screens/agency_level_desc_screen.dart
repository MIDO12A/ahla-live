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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLevels();
  }

  Future<void> _loadLevels() async {
    try {
      final list = await AgencyRepository.getAgencyLevelConfigs();
      if (mounted) setState(() => _levels = list);
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
                  _buildLevelsTableCard(),
                  const SizedBox(height: 16),
                  _buildRulesCard(),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _buildHowToEarnCard() {
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
              Icon(Icons.bolt, color: Colors.amber, size: 24),
              SizedBox(width: 8),
              Text('كيفية كسب نقاط الخبرة (EXP)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '• كل 1 EXP = 1 نقطة نمو للوكالة.\n'
            '• يتم جمع نقاط الخبرة من إجمالي الهدايا والألماس المستلم والمرسل عبر جميع أعضاء ومضيفي الوكالة.\n'
            '• ترتفع رتبة الوكالة تلقائياً وتفتح امتيازات إدارية جديدة فور تحقيق نقاط المستوى التالي.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelsTableCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              'جدول الامتيازات وسعة المشرفين',
              style: TextStyle(color: Color(0xFF223E9E), fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF8198FB),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('المستوى', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF223E9E), fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 3, child: Text('الخبرة (EXP)', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF223E9E), fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 2, child: Text('المشرفين', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF223E9E), fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 2, child: Text('الأعضاء', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF223E9E), fontWeight: FontWeight.bold, fontSize: 12))),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ..._levels.map((lvl) {
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE8EDFF), width: 1)),
              ),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(lvl.levelName, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF223E9E), fontWeight: FontWeight.bold, fontSize: 12))),
                  Expanded(flex: 3, child: Text('${lvl.minExp}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black87, fontSize: 12))),
                  Expanded(flex: 2, child: Text('${lvl.adminLimit}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 12))),
                  Expanded(flex: 2, child: Text('${lvl.membersLimit}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 12))),
                ],
              ),
            );
          }),
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
            '1. الترقية (Upgrade): تحدث الترقية فوراً في أي وقت بمجرد وصول نقاط الخبرة لتارجت المستوى الجديد.\n\n'
            '2. الحفاظ على المستوى (Maintain): يجب تحقيق 30% على الأقل من نقاط المستوى شهرياً للحفاظ على رتبة الوكالة.\n\n'
            '3. التخفيض (Downgrade): إذا لم تحقق الوكالة حد الـ 30% خلال الشهر، سيتم تخفيض المستوى تلقائياً في بداية الشهر التالي.',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}
