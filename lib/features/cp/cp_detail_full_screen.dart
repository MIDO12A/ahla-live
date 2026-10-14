import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/cache/encrypted_image_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/dynamic_config_service.dart';
import '../../screens/room/widgets/svga_frame.dart';
import 'cp_service.dart';
import 'cp_rewards_screen.dart';
import 'cp_space_screen.dart';
import 'cp_settings_screen.dart';
import 'cp_invitation_list_screen.dart';

class CPDetailFullScreen extends StatefulWidget {
  final String? cpId;

  const CPDetailFullScreen({
    super.key,
    this.cpId,
  });

  @override
  State<CPDetailFullScreen> createState() => _CPDetailFullScreenState();
}

class _CPDetailFullScreenState extends State<CPDetailFullScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _ranking = [];
  List<Map<String, dynamic>> _rankRewards = [];
  String _rankPeriod = 'daily';

  Map<String, dynamic>? _myCpData;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Map<String, dynamic>? _rewardByType(int rankPosition, String rewardType) {
    try {
      return _rankRewards.firstWhere(
            (r) => (r['rank_position'] as int?) == rankPosition && (r['reward_type'] as String?) == rewardType,
      );
    } catch (_) {
      return null;
    }
  }

  String get _userFrameSvg => 'assets/svga/d28.svga'; // frame على المستخدم
  String get _partnerFrameSvg => 'assets/svga/d29.svga'; // frame على الشريك
  String get _centerFrameSvg => 'assets/svga/d33.svga'; // animation في المنتصف فوق الأيام

  String _rewardSvg(int rankPosition, String rewardType, String fallback) {
    final r = _rewardByType(rankPosition, rewardType);
    final svga = r?['svga_url'] as String? ?? '';
    return svga.isNotEmpty ? svga : fallback;
  }

  String _rewardImg(int rankPosition, String rewardType, String fallback) {
    final r = _rewardByType(rankPosition, rewardType);
    final img = r?['image_url'] as String? ?? '';
    return img.isNotEmpty ? img : fallback;
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final results = await Future.wait([
        CpService.getRanking(period: _rankPeriod, limit: 50),
        CpService.getRankRewards(period: _rankPeriod),
        CpService.getMyData(),
      ]);
      final rankingList = results[0] as List;
      final rewardsList = results[1] as List;
      final myData = results[2] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _ranking = rankingList.cast<Map<String, dynamic>>();
          _rankRewards = rewardsList.cast<Map<String, dynamic>>();
          _myCpData = myData;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshRanking() async {
    try {
      final results = await Future.wait([
        CpService.getRanking(period: _rankPeriod, limit: 50),
        CpService.getRankRewards(period: _rankPeriod),
        CpService.getMyData(),
      ]);
      if (mounted) {
        setState(() {
          _ranking = (results[0] as List).cast<Map<String, dynamic>>();
          _rankRewards = (results[1] as List).cast<Map<String, dynamic>>();
          _myCpData = results[2] as Map<String, dynamic>;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = DynamicConfigService();

    final user = context.watch<UserProvider>().currentUser;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF1A0B2E),
        body: Stack(
          children: [
            _buildDecoratedBackground(),
            Center(child: CircularProgressIndicator(color: cfg.goldColor)),
            _buildAppBar(context),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A0B2E),
      body: Stack(
        children: [
          _buildDecoratedBackground(),
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 190),
            child: Column(
              children: [
                const SizedBox(height: 120),
                _buildFirstPlace(cfg),
                const SizedBox(height: 16),
                _buildTimeFilter(cfg),
                const SizedBox(height: 20),
                _buildCpCards(cfg),
                const SizedBox(height: 24),
                _buildRankingList(cfg),
                const SizedBox(height: 40),
              ],
            ),
          ),
          _buildAppBar(context),
          _buildTopIcons(),
          _buildBottomPanel(user),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const SizedBox(width: 40),
            const Spacer(),
            const Text(
              'ترتيب',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_forward, color: Colors.white),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDecoratedBackground() {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/cp/cp_ranking_top_bg.webp'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }


  Widget _buildTimeFilter(DynamicConfigService cfg) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: _buildFilterButton('شهري', 'monthly')),
          const SizedBox(width: 8),
          Expanded(child: _buildFilterButton('أسبوعي', 'weekly')),
          const SizedBox(width: 8),
          Expanded(child: _buildFilterButton('يومي', 'daily')),
        ],
      ),
    );
  }

  Widget _buildFilterButton(String text, String value) {
    final isSelected = _rankPeriod == value;
    return GestureDetector(
      onTap: () {
        setState(() => _rankPeriod = value);
        _refreshRanking();
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
            text,
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

  Widget _buildFirstPlace(DynamicConfigService cfg) {
    final top = _ranking.isNotEmpty ? _ranking[0] : null;
    final avatar1 = (top?['user1'] is Map ? top!['user1']['avatar'] : null) ?? top?['avatar1']?.toString() ?? '';
    final avatar2 = (top?['user2'] is Map ? top!['user2']['avatar'] : null) ?? top?['avatar2']?.toString() ?? '';
    final badgeImg = _rewardImg(1, 'badge', '');
    final necklaceImg = _rewardImg(1, 'necklace', '');
    final userFrame = _rewardSvg(1, 'frame_svga', _userFrameSvg);
    final partnerFrame = _rewardSvg(1, 'frame_svga', _partnerFrameSvg);
    final centerAnim = _rewardSvg(1, 'center_svga', _centerFrameSvg);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            'assets/cp/ic_cp_ranking_heart_top1.webp',
            width: 370,
            height: 370,
            fit: BoxFit.contain,
          ),
          Positioned(
            top: 36,
            left: 0,
            right: 0,
            child: Center(
              child: Image.asset(
                'assets/cp/ic_cp_tab_no.webp',
                width: 120,
                height: 120,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 70,
                height: 70,
                child: avatar2.isNotEmpty
                    ? Stack(
                  alignment: Alignment.center,
                  children: [
                    CircleAvatar(
                      radius: 35,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      backgroundImage: EncryptedImageProvider(avatar2) as ImageProvider,
                    ),
                    if (partnerFrame.isNotEmpty)
                      SvgaFrame(svgaPath: partnerFrame, size: 70),
                    if (badgeImg.isNotEmpty)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Image.asset(badgeImg, width: 24, height: 24),
                      ),
                  ],
                )
                    : Image.asset(
                  'assets/cp/ic_add_cp.webp',
                  width: 60,
                  height: 60,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgaFrame(svgaPath: centerAnim, size: 48, fit: BoxFit.contain),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                    ).createShader(bounds),
                    child: const Text(
                      'top1',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 70,
                height: 70,
                child: avatar1.isNotEmpty
                    ? Stack(
                  alignment: Alignment.center,
                  children: [
                    CircleAvatar(
                      radius: 35,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      backgroundImage: EncryptedImageProvider(avatar1) as ImageProvider,
                    ),
                    if (userFrame.isNotEmpty)
                      SvgaFrame(svgaPath: userFrame, size: 70),
                    if (necklaceImg.isNotEmpty)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: Image.asset(necklaceImg, width: 30, height: 30),
                      ),
                  ],
                )
                    : Image.asset(
                  'assets/cp/ic_add_cp.webp',
                  width: 60,
                  height: 60,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _emptyRankData() => {
    'avatar1': '',
    'avatar2': '',
    'cp_days': 0,
  };

  Widget _buildCpCards(DynamicConfigService cfg) {
    final second = _ranking.length > 1 ? _ranking[1] : _emptyRankData();
    final third = _ranking.length > 2 ? _ranking[2] : _emptyRankData();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const Text(
            'top2',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          _buildCpCard(second, cfg, rankPosition: 2),
          const SizedBox(height: 20),
          const Text(
            'top3',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          _buildCpCard(third, cfg, rankPosition: 3),
        ],
      ),
    );
  }

  Widget _buildCpCard(Map<String, dynamic> data, DynamicConfigService cfg, {int rankPosition = 2}) {
    final avatar1 = (data['user1'] is Map ? data['user1']['avatar'] : null) ?? data['avatar1']?.toString() ?? '';
    final avatar2 = (data['user2'] is Map ? data['user2']['avatar'] : null) ?? data['avatar2']?.toString() ?? '';
    final days = (data['cp_days'] as num?)?.toInt() ?? 0;
    final badgeImg = _rewardImg(rankPosition, 'badge', '');
    final necklaceImg = _rewardImg(rankPosition, 'necklace', '');
    final userFrame = _rewardSvg(rankPosition, 'frame_svga', _userFrameSvg);
    final partnerFrame = _rewardSvg(rankPosition, 'frame_svga', _partnerFrameSvg);
    final centerAnim = _rewardSvg(rankPosition, 'center_svga', _centerFrameSvg);

    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        image: const DecorationImage(
          image: AssetImage('assets/cp/ic_agency_charm_item_bg.webp'),
          fit: BoxFit.fill,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Stack(
            alignment: Alignment.center,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                backgroundImage: avatar1.isNotEmpty
                    ? EncryptedImageProvider(avatar1) as ImageProvider
                    : const AssetImage('assets/cp/ic_cp_ranking_default_header.webp'),
              ),
              if (userFrame.isNotEmpty)
                SvgaFrame(svgaPath: userFrame, size: 56),
              if (badgeImg.isNotEmpty)
                Positioned(bottom: 0, right: 0, child: Image.asset(badgeImg, width: 20, height: 20)),
            ],
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgaFrame(svgaPath: centerAnim, size: 48, fit: BoxFit.contain),
                  Text(
                    '$days يوم',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                backgroundImage: avatar2.isNotEmpty
                    ? EncryptedImageProvider(avatar2) as ImageProvider
                    : const AssetImage('assets/cp/ic_cp_ranking_default_header.webp'),
              ),
              if (partnerFrame.isNotEmpty)
                SvgaFrame(svgaPath: partnerFrame, size: 56),
              if (necklaceImg.isNotEmpty)
                Positioned(top: 0, left: 0, child: Image.asset(necklaceImg, width: 24, height: 24)),
            ],
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildRankingList(DynamicConfigService cfg) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: List.generate(10, (i) {
          final idx = i + 3;
          final item = _ranking.length > idx ? _ranking[idx] : _emptyRankData();
          final rankLabel = 'top${i + 4}';
          return Padding(
            padding: EdgeInsets.only(bottom: i < 9 ? 16 : 0),
            child: Column(
              children: [
                Text(
                  rankLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                _buildCpCard(item, cfg, rankPosition: idx + 1),
              ],
            ),
          );
        }),
      ),
    );
  }



  void _showRulesDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            decoration: BoxDecoration(
              image: const DecorationImage(
                image: AssetImage('assets/cp/ic_accept_cp_invitation_dialog_bg.webp'),
                fit: BoxFit.fill,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                  ).createShader(bounds),
                  child: const Text(
                    'قواعد',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '■ الربط: عند إرسال هدية إلى مستخدم محدد بعدد أيام معينة يتم الربط المباشر بينكما.',
                  style: TextStyle(fontSize: 14, color: Colors.white, height: 1.6),
                ),
                const SizedBox(height: 12),
                const Text(
                  '■ التصفير: كل يوم أحد الساعة 12:00 صباحاً بتوقيت مصر.',
                  style: TextStyle(fontSize: 14, color: Colors.white, height: 1.6),
                ),
                const SizedBox(height: 12),
                const Text(
                  '■ المكافآت: توجد مكافآت للزوجين الأول والثاني والثالث.',
                  style: TextStyle(fontSize: 14, color: Colors.white, height: 1.6),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'حسناً',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopIcons() {
    return Stack(
      children: [
        // Left: Rules (القواعد)
        Positioned(
          top: MediaQuery.of(context).padding.top + 60,
          left: 12,
          child: GestureDetector(
            onTap: _showRulesDialog,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/cp/ic_cp_space_record_tab_selected_icon.webp',
                  width: 48,
                  height: 48,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 4),
                const Text(
                  'القواعد',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Right: Rewards (المكافآت)
        Positioned(
          top: MediaQuery.of(context).padding.top + 60,
          right: 12,
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CPRewardsScreen()),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/cp/ic_cp_space_entrance_icon.webp',
                  width: 48,
                  height: 48,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 4),
                const Text(
                  'المكافآت',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomPanel(dynamic user) {
    final avatarUrl = user?.photoUrl ?? '';
    final userName = user?.name ?? '---';
    final couple = _myCpData?['couple'] as Map<String, dynamic>?;
    final hasCp = _myCpData?['has_cp'] == true && couple != null;
    final partner = couple?['partner'] as Map<String, dynamic>?;
    final partnerAvatar = hasCp ? (partner?['avatar'] as String? ?? '') : '';
    final partnerName = hasCp ? (partner?['name'] as String? ?? '---') : 'إضافة CP';
    final cpDays = hasCp ? (couple['days_together'] as int? ?? 0) : 0;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 180,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/cp/ic_cp_ranking_mine_panel.webp'),
            fit: BoxFit.fitWidth,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CpSpaceScreen()),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          backgroundImage: avatarUrl.isNotEmpty
                              ? EncryptedImageProvider(avatarUrl) as ImageProvider
                              : const AssetImage('assets/cp/ic_cp_ranking_default_header.webp'),
                        ),
                        if (_userFrameSvg.isNotEmpty)
                          SvgaFrame(svgaPath: _userFrameSvg, size: 72),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    userName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgaFrame(svgaPath: _centerFrameSvg, size: 100, fit: BoxFit.contain),
                  const SizedBox(height: 6),
                  Text(
                    '$cpDays يوم',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => hasCp ? const CpSettingsScreen() : const CcInvitationListScreen(),
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        partnerAvatar.isNotEmpty
                            ? CircleAvatar(
                                radius: 36,
                                backgroundColor: Colors.white.withValues(alpha: 0.1),
                                backgroundImage: EncryptedImageProvider(partnerAvatar) as ImageProvider,
                              )
                            : Image.asset(
                                'assets/cp/ic_add_cp.webp',
                                width: 72,
                                height: 72,
                                fit: BoxFit.contain,
                              ),
                        if (partnerAvatar.isNotEmpty && _partnerFrameSvg.isNotEmpty)
                          SvgaFrame(svgaPath: _partnerFrameSvg, size: 72),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    partnerName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

}
