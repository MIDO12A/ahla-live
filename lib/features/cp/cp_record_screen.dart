import 'package:flutter/material.dart';
import '../../services/dynamic_config_service.dart';
import 'cp_service.dart';
import 'package:zero/core/dtext.dart';

/// Relationship Record screen — matches act_relationship_record.xml
/// Tabs: الكل / المرسلة / المستلمة + achievements grid.
class CpRecordScreen extends StatefulWidget {
  const CpRecordScreen({super.key});

  @override
  State<CpRecordScreen> createState() => _CpRecordScreenState();
}

class _CpRecordScreenState extends State<CpRecordScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _allRecords = [];
  List<Map<String, dynamic>> _achievements = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        CpService.getCpHistory(limit: 100),
        CpService.getCpAchievements(),
      ]);
      if (mounted) {
        setState(() {
          _allRecords = results[0];
          _achievements = results[1];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = DynamicConfigService();

    return Scaffold(
      backgroundColor: const Color(0xFF1a0a0e),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const DText('سجل العلاقات',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicator: const BoxDecoration(),
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: const Color(0xFFffb565),
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontSize: 16),
          splashFactory: NoSplash.splashFactory,
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'الكل'),
            Tab(text: 'المرسلة'),
            Tab(text: 'المستلمة'),
          ],
        ),
      ),
      body: _buildBody(cfg),
    );
  }

  Widget _buildBody(DynamicConfigService cfg) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.white54),
            const SizedBox(height: 16),
            const DText('حدث خطأ في تحميل السجل', style: TextStyle(color: Colors.white)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadData,
              child: const DText('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildRecordList(cfg, _allRecords),
        _buildRecordList(cfg, _allRecords.where((r) => r['direction'] == 'sent').toList()),
        _buildRecordList(cfg, _allRecords.where((r) => r['direction'] == 'received').toList()),
      ],
    );
  }

  Widget _buildRecordList(DynamicConfigService cfg, List<Map<String, dynamic>> records) {
    if (records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            const DText('لا توجد سجلات', style: TextStyle(color: Colors.white54, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      children: [
        // Achievements summary
        if (_achievements.isNotEmpty) ...[
          _buildAchievementsSummary(cfg),
          const SizedBox(height: 16),
        ],
        // Records list
        ...records.map((item) => _buildRecordItem(cfg, item)),
      ],
    );
  }

  Widget _buildAchievementsSummary(DynamicConfigService cfg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF4a1020), const Color(0xFF2e0d15)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFa31b44).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DText('الإنجازات',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: _achievements.take(4).map((a) {
              final icon = switch (a['icon']?.toString()) {
                'favorite' => Icons.favorite,
                'card_giftcard' => Icons.card_giftcard,
                'stars' => Icons.stars,
                _ => Icons.star,
              };
              return Expanded(
                child: Column(
                  children: [
                    Icon(icon, color: const Color(0xFFffb565), size: 24),
                    const SizedBox(height: 4),
                    DText(a['title']?.toString() ?? '',
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    DText(a['subtitle']?.toString() ?? '',
                        style: const TextStyle(color: Colors.white60, fontSize: 10)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordItem(DynamicConfigService cfg, Map<String, dynamic> item) {
    final userName = item['user_name'] as String? ?? '';
    final giftName = item['gift_name'] as String? ?? '';
    final giftValue = (item['gift_value'] as num?)?.toInt() ?? 0;
    final timestamp = item['timestamp'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF770d1e).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFffb565).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.card_giftcard, color: Color(0xFFffb565), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (giftName.isNotEmpty)
                  DText(giftName,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                DText(userName, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                if (giftValue > 0)
                  DText('$giftValue نقطة',
                      style: const TextStyle(color: Color(0xFFffb565), fontSize: 11)),
                if (timestamp.isNotEmpty)
                  DText(_formatTime(timestamp),
                      style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      final time = DateTime.parse(iso);
      final now = DateTime.now();
      final diff = now.difference(time);
      if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
      if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
      return 'منذ ${diff.inDays} ي';
    } catch (_) {
      return '';
    }
  }
}
