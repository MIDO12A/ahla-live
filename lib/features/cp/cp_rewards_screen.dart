import 'package:flutter/material.dart';
import '../../core/widgets/cached_image.dart';
import '../../screens/room/widgets/svga_frame.dart';
import '../../services/dynamic_config_service.dart';
import 'cp_service.dart';

class CPRewardsScreen extends StatefulWidget {
  const CPRewardsScreen({super.key});

  @override
  State<CPRewardsScreen> createState() => _CPRewardsScreenState();
}

class _CPRewardsScreenState extends State<CPRewardsScreen> {
  String _period = 'daily';
  Map<String, dynamic> _settings = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final settings = await CpService.getSettings();
      if (mounted) setState(() => _settings = settings);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cfg = DynamicConfigService();

    return Scaffold(
      backgroundColor: cfg.cpHeaderBg,
      body: Stack(
        children: [
          _buildBackground(cfg),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: Column(
                      children: [
                        _buildPeriodTabs(cfg),
                        const SizedBox(height: 16),
                        _buildRewardsDisplay(cfg),
                        const SizedBox(height: 20),
                        _buildRules(cfg),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(DynamicConfigService cfg) {
    final bg = cfg.cpBackgroundImage;
    if (bg.startsWith('assets/')) {
      return Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(bg),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/cp/cp_ranking_top_bg.webp'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
            ),
          ),
          const Spacer(),
          const Text(
            'المكافآت',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildPeriodTabs(DynamicConfigService cfg) {
    final tabs = [
      if (_settingBool('rewards_show_daily')) _periodTab(cfg, 'يومي', 'daily'),
      if (_settingBool('rewards_show_weekly')) _periodTab(cfg, 'أسبوعي', 'weekly'),
      if (_settingBool('rewards_show_monthly')) _periodTab(cfg, 'شهري', 'monthly'),
    ];
    if (tabs.isEmpty) return const SizedBox.shrink();
    return Row(children: tabs.map((t) {
      final i = tabs.indexOf(t);
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(left: i < tabs.length - 1 ? 6 : 0),
          child: t,
        ),
      );
    }).toList());
  }

  Widget _periodTab(DynamicConfigService cfg, String label, String value) {
    final isSelected = _period == value;
    return GestureDetector(
      onTap: () {
        setState(() => _period = value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
              isSelected
                  ? 'assets/cp/ic_cp_space_tab_selected_bg.webp'
                  : 'assets/cp/ic_cp_space_tab_unselected_bg.webp',
            ),
            fit: BoxFit.fill,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : Colors.white54,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRewardsDisplay(DynamicConfigService cfg) {
    // StreamBuilder: يعرض مكافآت الفترة لحظياً (أي تعديل من لوحة التحكم يظهر فوراً)
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CpService.rewardsStream(period: _period),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator(color: cfg.cpGold, strokeWidth: 2));
        }
        final rewards = snapshot.data ?? [];
        if (rewards.isEmpty) return const SizedBox.shrink();

        final bgUrl = _settings['rewards_box_bg'] as String? ?? '';
        final grouped = <int, List<Map<String, dynamic>>>{};
        for (final r in rewards) {
          final rank = (r['rank_position'] as int?) ?? 0;
          grouped.putIfAbsent(rank, () => []).add(r);
        }
        final sortedRanks = grouped.keys.toList()..sort();

        return Column(
          children: sortedRanks.expand((rank) {
            final items = grouped[rank]!;
            items.sort((a, b) => ((a['slot_index'] as int?) ?? 0).compareTo((b['slot_index'] as int?) ?? 0));
            return [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [cfg.cpGold, cfg.cpAccent],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Top $rank',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: cfg.cpHeaderBg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: items.map((r) => _buildRewardBox(cfg, r, bgUrl)).toList(),
              ),
              const SizedBox(height: 16),
            ];
          }).toList(),
        );
      },
    );
  }

  Widget _buildRewardBox(DynamicConfigService cfg, Map<String, dynamic> reward, String bgUrl) {
    final label = reward['label_ar'] as String? ?? reward['label_en'] as String? ?? '';
    final svgaUrl = reward['svga_url'] as String? ?? '';
    final imageUrl = reward['image_url'] as String? ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            image: bgUrl.isNotEmpty
                ? DecorationImage(
                    image: NetworkImage(bgUrl),
                    fit: BoxFit.fill,
                  )
                : null,
            color: bgUrl.isEmpty ? Colors.white.withValues(alpha: 0.1) : null,
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Center(
            child: svgaUrl.isNotEmpty
                ? SvgaFrame(svgaPath: svgaUrl, size: 52, fit: BoxFit.contain)
                : imageUrl.isNotEmpty
                    ? CachedNetImage(imageUrl, width: 52, height: 52, fit: BoxFit.contain)
                    : const Icon(Icons.card_giftcard, color: Colors.white54, size: 28),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 72,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRules(DynamicConfigService cfg) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final rulesText = isAr ? _settings['rewards_rules_ar'] ?? '' : _settings['rewards_rules_en'] ?? '';
    if (rulesText.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cfg.cpGold.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [cfg.cpGold, cfg.cpAccent],
            ).createShader(bounds),
            child: const Text(
              'القواعد',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            rulesText,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  bool _settingBool(String key) {
    final val = _settings[key] ?? 'true';
    return val == 'true' || val == '1';
  }
}
