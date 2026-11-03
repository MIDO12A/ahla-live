import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../services/dynamic_config_service.dart';
import '../../services/level_service.dart';
import '../../providers/user_provider.dart';
import 'package:zero/core/dtext.dart';

class LevelScreen extends StatefulWidget {
  const LevelScreen({super.key});

  @override
  State<LevelScreen> createState() => _LevelScreenState();
}

class _LevelScreenState extends State<LevelScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final LevelService _levelService = LevelService();
  List<LevelConfig> _wealthLevels = [];
  List<LevelConfig> _rechargeLevels = [];
  List<LevelConfig> _gemsLevels = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _levelService.addListener(_onLevelsChanged);
    _loadLevels();
  }

  Future<void> _loadLevels() async {
    try {
      await _levelService.loadAllLevels();
    } catch (e) {
      debugPrint('LevelScreen: error loading levels: $e');
    }
    _updateFromCache();
  }

  void _onLevelsChanged() {
    if (mounted) _updateFromCache();
  }

  void _updateFromCache() {
    setState(() {
      _wealthLevels = _levelService.cachedLevels['wealth'] ?? [];
      _rechargeLevels = _levelService.cachedLevels['recharge'] ?? [];
      _gemsLevels = _levelService.cachedLevels['gems'] ?? [];
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _levelService.removeListener(_onLevelsChanged);
    _tabController.dispose();
    super.dispose();
  }

  List<LevelConfig> _levelsForTab(int index) {
    switch (index) {
      case 0: return _wealthLevels;
      case 1: return _rechargeLevels;
      case 2: return _gemsLevels;
      default: return _wealthLevels;
    }
  }

  String _levelTypeKey(int index) {
    switch (index) {
      case 0: return 'wealth';
      case 1: return 'recharge';
      case 2: return 'gems';
      default: return 'wealth';
    }
  }

  int _currentLevel(int index, dynamic user) {
    if (user == null) return 1;
    switch (index) {
      case 0: return user.wealthLevel;
      case 1: return user.rechargeLevel;
      case 2: return user.gemsLevel;
      default: return 1;
    }
  }

  int _currentExp(int index, dynamic user) {
    if (user == null) return 0;
    switch (index) {
      case 0: return user.wealthExp;
      case 1: return user.rechargeExp;
      case 2: return user.gemsExp;
      default: return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dc = DynamicConfigService();
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.currentUser;

    return ListenableBuilder(
      listenable: dc,
      builder: (context, _) {
        final dc = DynamicConfigService();
        return Scaffold(
          backgroundColor: dc.primaryBg,
          body: Stack(
            children: [
              Positioned.fill(
                child: R.loadAsset(
                  dc.levelBackgroundImage.isNotEmpty
                      ? dc.levelBackgroundImage
                      : R.levelTopBg,
                  fit: BoxFit.cover,
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Stack(
                      children: [
                        if (dc.levelHeaderBgImage.isNotEmpty)
                          Positioned.fill(
                            child: R.loadAsset(dc.levelHeaderBgImage, fit: BoxFit.cover),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: R.image(
                                  R.backWhite,
                                  width: 24,
                                  height: 24,
                                ),
                              ),
                              const Spacer(),
                              DText(
                                dc.screenTitles['level'] ?? 'المستويات',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: dc.levelHeaderTextColor,
                                ),
                              ),
                              const Spacer(),
                              const SizedBox(width: 24),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Container(
                      color: dc.levelSectionBgImage.isNotEmpty ? null : dc.tabBarColor,
                      decoration: dc.levelSectionBgImage.isNotEmpty
                          ? BoxDecoration(image: DecorationImage(image: R.cachedImage(dc.levelSectionBgImage), fit: BoxFit.cover))
                          : null,
                      child: TabBar(
                        controller: _tabController,
                        labelColor: dc.levelAccentColor,
                        unselectedLabelColor: dc.levelSubTextColor,
                        indicatorColor: dc.levelAccentColor,
                        tabs: [
                          Tab(text: dc.getScreenTitle('wealth', 'Wealth')),
                          Tab(text: dc.getScreenTitle('recharge', 'Recharge')),
                          Tab(text: dc.getScreenTitle('gems', 'Attractiveness')),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: List.generate(3, (index) {
                          return _buildLevelList(
                            index: index,
                            levels: _levelsForTab(index),
                            type: _levelTypeKey(index),
                            user: user,
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLevelList({
    required int index,
    required List<LevelConfig> levels,
    required String type,
    required dynamic user,
  }) {
    final dc = DynamicConfigService();
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final cl = _currentLevel(index, user);
    final ce = _currentExp(index, user);
    final currentConfig = _levelService.getLevelConfig(type, cl);
    final maxExp = currentConfig?.maxExp ?? cl * 1000;
    final progress = (ce / maxExp).clamp(0.0, 1.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ===== المربع الكبير في الأعلى - المستوى الحالي =====
          _buildCurrentLevelBox(dc, currentConfig, cl, ce, maxExp, progress, type),

          const SizedBox(height: 24),

          // ===== 3 مربعات في الأسفل =====
          Row(
            children: [
              // المربع الأول - الإطار (Frame)
              Expanded(
                child: _buildRewardBox(
                  dc: dc,
                  label: 'Frame',
                  assetUrl: currentConfig?.frameUrl,
                  fallbackIcon: Icons.crop_square_outlined,
                ),
              ),
              const SizedBox(width: 12),
              // المربع الثاني - الشارة (Badge)
              Expanded(
                child: _buildRewardBox(
                  dc: dc,
                  label: 'Badge',
                  assetUrl: currentConfig?.badgeUrl,
                  fallbackIcon: Icons.verified_outlined,
                ),
              ),
              const SizedBox(width: 12),
              // المربع الثالث - أيقونة المستوى
              Expanded(
                child: _buildRewardBox(
                  dc: dc,
                  label: 'Level Icon',
                  assetUrl: currentConfig?.imageUrl,
                  fallbackIcon: Icons.star_outline,
                  fallbackText: '$cl',
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ===== قائمة المستويات التالية =====
          Row(
            children: [
              DText(
                dc.getScreenTitle('next_levels', 'Next Levels'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: dc.levelTextColor,
              ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (levels.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
                child: DText(
                  dc.getScreenTitle('no_levels', 'No levels configured yet'),
                  style: TextStyle(color: dc.levelSubTextColor),
                ),
            )
          else
            ...levels.map((config) {
              final isCurrent = config.level == cl;
              final isUnlocked = config.level <= cl;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: dc.levelCardBgImage.isNotEmpty || dc.levelCardBorderImage.isNotEmpty
                      ? null
                      : (isUnlocked ? dc.levelCardBgColor : dc.levelCardBgColor.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(12),
                  border: isCurrent
                      ? Border.all(color: dc.levelAccentColor, width: 2)
                      : null,
                  image: dc.levelCardBgImage.isNotEmpty
                      ? DecorationImage(image: R.cachedImage(dc.levelCardBgImage), fit: BoxFit.cover)
                      : dc.levelCardBorderImage.isNotEmpty
                          ? DecorationImage(image: R.cachedImage(dc.levelCardBorderImage), fit: BoxFit.cover)
                          : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isUnlocked
                            ? dc.levelAccentColor.withValues(alpha: 0.3)
                            : dc.levelSubTextColor.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: config.imageUrl != null
                          ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: R.loadAsset(
                          config.imageUrl!,
                          width: 48,
                          height: 48,
                        ),
                      )
                          : Center(
                          child: DText(
                            '${config.level}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isUnlocked ? dc.levelAccentColor : dc.levelSubTextColor,
                            ),
                          ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DText(
                            config.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: dc.levelTextColor,
                              ),
                          ),
                          if (config.frameUrl != null || config.badgeUrl != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  if (config.frameUrl != null)
                                    DText(
                                      'Frame',
                                      style: TextStyle(fontSize: 11, color: dc.levelSubTextColor),
                                    ),
                                  if (config.frameUrl != null && config.badgeUrl != null)
                                    const SizedBox(width: 8),
                                  if (config.badgeUrl != null)
                                    DText(
                                      'Badge',
                                      style: TextStyle(fontSize: 11, color: dc.levelSubTextColor),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (config.frameUrl != null)
                      Container(
                        width: 36,
                        height: 36,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: dc.levelAccentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: R.loadAsset(config.frameUrl!),
                        ),
                      ),
                    if (config.badgeUrl != null)
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: dc.levelAccentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: R.loadAsset(config.badgeUrl!),
                        ),
                      ),
                    const SizedBox(width: 8),
                    if (isUnlocked)
                      R.image(
                        R.commonNext4Ic,
                        width: 20,
                        height: 20,
                      )
                    else
                      Icon(
                        Icons.lock_outline,
                        color: dc.levelSubTextColor,
                        size: 20,
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  /// بناء مربع المكافأة (Frame / Badge / Level Icon)
  Widget _buildRewardBox({
    required DynamicConfigService dc,
    required String label,
    required String? assetUrl,
    required IconData fallbackIcon,
    String? fallbackText,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: dc.levelCardBgImage.isNotEmpty || dc.levelCardBorderImage.isNotEmpty || dc.levelAccentImage.isNotEmpty
            ? null
            : dc.levelCardBgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: dc.levelAccentColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
        image: dc.levelCardBgImage.isNotEmpty
            ? DecorationImage(image: R.cachedImage(dc.levelCardBgImage), fit: BoxFit.cover)
            : dc.levelCardBorderImage.isNotEmpty
                ? DecorationImage(image: R.cachedImage(dc.levelCardBorderImage), fit: BoxFit.cover)
                : dc.levelAccentImage.isNotEmpty
                    ? DecorationImage(image: R.cachedImage(dc.levelAccentImage), fit: BoxFit.cover)
                    : null,
        boxShadow: dc.levelCardBgImage.isNotEmpty || dc.levelCardBorderImage.isNotEmpty || dc.levelAccentImage.isNotEmpty ? null : [
          BoxShadow(
            color: dc.levelAccentColor.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: dc.levelAccentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: assetUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: R.loadAsset(assetUrl),
                  )
                : fallbackText != null
                    ? Center(
                        child: DText(
                          fallbackText,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: dc.levelAccentColor,
                          ),
                        ),
                      )
                    : Icon(
                        fallbackIcon,
                        size: 36,
                        color: dc.levelAccentColor.withValues(alpha: 0.6),
                      ),
          ),
          const SizedBox(height: 10),
          DText(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: dc.levelTextColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentLevelBox(
    DynamicConfigService dc,
    LevelConfig? config,
    int currentLevel,
    int currentExp,
    int maxExp,
    double progress,
    String type,
  ) {
    final progressColor = (config?.progressColor != null)
        ? Color(int.parse(config!.progressColor!.replaceAll('#', '0xFF')))
        : dc.levelAccentColor;

    final hasBg = config?.boxImageUrl != null;
    final useImage = dc.levelCardBgImage.isNotEmpty || dc.levelCardBorderImage.isNotEmpty;
    final box = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: useImage || hasBg ? dc.levelCardBgColor.withValues(alpha: 0.85) : dc.levelCardBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dc.levelAccentColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
        image: !hasBg && dc.levelCardBgImage.isNotEmpty
            ? DecorationImage(image: R.cachedImage(dc.levelCardBgImage), fit: BoxFit.cover)
            : !hasBg && dc.levelCardBorderImage.isNotEmpty
                ? DecorationImage(image: R.cachedImage(dc.levelCardBorderImage), fit: BoxFit.cover)
                : null,
        boxShadow: useImage || hasBg ? null : [
          BoxShadow(
            color: dc.levelAccentColor.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: dc.levelAccentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: dc.levelAccentColor.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: config?.imageUrl != null
                ? ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: R.loadAsset(
                config!.imageUrl!,
                width: 120,
                height: 120,
              ),
            )
                : Center(
              child: DText(
                '$currentLevel',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: dc.levelAccentColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          DText(
            config?.title ?? '$type $currentLevel',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: dc.levelTextColor,
            ),
          ),
          const SizedBox(height: 8),
          DText(
            'Experience: $currentExp / $maxExp',
            style: TextStyle(
              fontSize: 14,
              color: dc.levelSubTextColor,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 10,
            decoration: BoxDecoration(
              color: dc.levelSubTextColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(5),
            ),
            child: FractionallySizedBox(
              widthFactor: progress,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  color: progressColor,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          DText(
            '${(progress * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: dc.levelAccentColor,
            ),
          ),
        ],
      ),
    );

    if (config?.boxImageUrl != null) {
      return Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: R.loadAsset(
                config!.boxImageUrl!,
                fit: BoxFit.cover,
              ),
            ),
          ),
          box,
        ],
      );
    }
    return box;
  }
}