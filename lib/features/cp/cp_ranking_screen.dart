import 'package:flutter/material.dart';
import '../../config/r.dart';
import '../../screens/room/widgets/svga_frame.dart';
import 'cp_service.dart';

/// Relationship Ranking screen — matches act_relationship_ranking.xml
/// Tabs: Daily / Weekly / Monthly with podium + list.
class CpRankingScreen extends StatefulWidget {
  const CpRankingScreen({super.key});
  @override
  State<CpRankingScreen> createState() => _CpRankingScreenState();
}

class _CpRankingScreenState extends State<CpRankingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _ranking = [];
  bool _loading = true;
  String _period = 'daily';

  final _tabs = const [
    Tab(text: 'يومي'),
    Tab(text: 'أسبوعي'),
    Tab(text: 'شهري'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _period = switch (_tabController.index) {
          0 => 'daily',
          1 => 'week',
          _ => 'month',
        };
        _loadRanking();
      }
    });
    _loadRanking();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRanking() async {
    setState(() => _loading = true);
    try {
      final list = await CpService.getRanking(period: _period, limit: 50);
      if (mounted) setState(() { _ranking = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2e0d15),
      body: Stack(
        children: [
          // Background gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF4a1020), Color(0xFF2e0d15)],
                ),
              ),
            ),
          ),
          // Top animated SVGA background
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 280,
            child: const IgnorePointer(
              child: SvgaFrame(
                svgaPath: 'assets/svga/relationship_act_top_bg.svga',
                size: 280,
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Content
          Column(
            children: [
              // Top bar
              _buildTopBar(),
              // Tab bar
              Container(
                width: 232,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: TabBar(
                  controller: _tabController,
                  tabs: _tabs,
                  indicator: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFd32a43), Color(0xFFff6b9d)],
                    ),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  labelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 13,
                    color: Colors.white60,
                  ),
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                ),
              ),
              const SizedBox(height: 12),
              // Ranking content
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _ranking.isEmpty
                        ? const Center(
                            child: Text('لا يوجد ترتيب حالياً',
                                style: TextStyle(color: Colors.white54, fontSize: 14)))
                        : _buildRankingList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final statusH = MediaQuery.of(context).padding.top;
    return SizedBox(
      height: statusH + 50,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, statusH + 8, 12, 0),
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
            const Text('ترتيب العلاقات',
                style: TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            // Award button placeholder
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.emoji_events, color: Color(0xFFFFD54F), size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankingList() {
    final top3 = _ranking.take(3).toList();
    final rest = _ranking.skip(3).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Podium (top 3)
          _buildPodium(top3),
          const SizedBox(height: 20),
          // Rest of list
          ...rest.map((e) => _buildRankItem(e)),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPodium(List<Map<String, dynamic>> top3) {
    // Order: 2nd, 1st, 3rd
    final first = top3.isNotEmpty ? top3[0] : null;
    final second = top3.length > 1 ? top3[1] : null;
    final third = top3.length > 2 ? top3[2] : null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (second != null) _buildPodiumItem(second, 2, 90),
        const SizedBox(width: 8),
        if (first != null) _buildPodiumItem(first, 1, 110),
        const SizedBox(width: 8),
        if (third != null) _buildPodiumItem(third, 3, 80),
      ],
    );
  }

  Widget _buildPodiumItem(Map<String, dynamic> item, int rank, double height) {
    final u1 = item['user1'] as Map<String, dynamic>?;
    final u2 = item['user2'] as Map<String, dynamic>?;
    final score = item['score']?.toString() ?? '0';

    final medalColor = switch (rank) {
      1 => const Color(0xFFFFD54F),
      2 => const Color(0xFFB0BEC5),
      _ => const Color(0xFFA1887F),
    };

    final svgaRankAsset = switch (rank) {
      1 => 'assets/svga/cp1.svga',
      2 => 'assets/svga/cp2.svga',
      3 => 'assets/svga/cp3.svga',
      _ => '',
    };

    final animSize = rank == 1 ? 120.0 : 104.0;
    final avaSize = rank == 1 ? 38.0 : 34.0;
    final podiumWidth = rank == 1 ? 116.0 : 100.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // SVGA Rank Animation & Avatars
        SizedBox(
          width: animSize,
          height: animSize,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Avatars
              Positioned(
                bottom: rank == 1 ? 20 : 16,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _podiumAvatar(u1?['avatar']?.toString(), size: avaSize),
                    Transform.translate(
                      offset: const Offset(-8, 0),
                      child: _podiumAvatar(u2?['avatar']?.toString(), size: avaSize),
                    ),
                  ],
                ),
              ),
              // SVGA Animation overlay
              if (svgaRankAsset.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: SvgaFrame(
                      svgaPath: svgaRankAsset,
                      size: animSize,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Score
        Container(
          width: podiumWidth,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                medalColor.withValues(alpha: 0.35),
                const Color(0xFF2e0d15),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: medalColor.withValues(alpha: 0.6), width: 1.2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(score,
                  style: TextStyle(
                      color: medalColor, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              const Text('قربى', style: TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _podiumAvatar(String? url, {double size = 36}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFFFD54F), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 4,
          ),
        ],
      ),
      child: ClipOval(
        child: R.loadImage(
          url ?? R.avaBoy,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildRankItem(Map<String, dynamic> item) {
    final rank = item['rank']?.toString() ?? '-';
    final u1 = item['user1'] as Map<String, dynamic>?;
    final u2 = item['user2'] as Map<String, dynamic>?;
    final score = item['score']?.toString() ?? '0';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF770d1e).withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        children: [
          // Rank number
          SizedBox(
            width: 30,
            child: Text('#$rank',
                style: const TextStyle(
                    color: Color(0xFFffb565), fontSize: 14, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          // Avatars
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: R.loadImage(u1?['avatar']?.toString() ?? R.avaBoy,
                    width: 32, height: 32, fit: BoxFit.cover),
              ),
              const SizedBox(width: 4),
              ClipOval(
                child: R.loadImage(u2?['avatar']?.toString() ?? R.avaGirl,
                    width: 32, height: 32, fit: BoxFit.cover),
              ),
            ],
          ),
          const SizedBox(width: 10),
          // Names
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(u1?['name']?.toString() ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('& ${u2?['name']?.toString() ?? ''}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          // Score
          Text(score,
              style: const TextStyle(
                  color: Color(0xFFffb565), fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
