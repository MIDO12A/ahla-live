import 'package:flutter/material.dart';
import '../../../../services/supabase_service.dart';
import '../../../../services/dynamic_config_service.dart';
import '../../../../config/r.dart';
import '../../user_profile/user_profile_screen.dart';

class RoomRankBottomSheet extends StatefulWidget {
  final String roomId;
  const RoomRankBottomSheet({Key? key, required this.roomId}) : super(key: key);

  @override
  State<RoomRankBottomSheet> createState() => _RoomRankBottomSheetState();
}

class _RoomRankBottomSheetState extends State<RoomRankBottomSheet> {
  int _mainTabIndex = 0; // 0 for Wealth (الثروة), 1 for Magic (السحر)
  int _subTabIndex = 0; // 0 for Daily (يوميا), 1 for Weekly (أسبوعيًا), 2 for Monthly (شهريا)

  List<Map<String, dynamic>> _rankings = [];
  bool _isLoading = true;

  void _openUserProfile(Map<String, dynamic>? item) {
    if (item == null) return;
    final uid = (item['uid'] ?? item['id'] ?? item['user_id'] ?? '').toString();
    if (uid.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UserProfileScreen(targetUid: uid),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchRankings();
  }

  void _fetchRankings() async {
    setState(() => _isLoading = true);
    final String timeframe = _subTabIndex == 0 ? 'daily' : _subTabIndex == 1 ? 'weekly' : 'monthly';
    final bool isWealth = _mainTabIndex == 0;
    
    try {
      final data = await FirebaseService().getRoomRankings(
        roomId: widget.roomId,
        isWealth: isWealth,
        timeframe: timeframe,
      );
      if (mounted) {
        setState(() {
          _rankings = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _rankings = [];
          _isLoading = false;
        });
      }
    }
  }

  void _onMainTabChanged(int index) {
    if (_mainTabIndex != index) {
      setState(() {
        _mainTabIndex = index;
      });
      _fetchRankings();
    }
  }

  void _onSubTabChanged(int index) {
    if (_subTabIndex != index) {
      setState(() {
        _subTabIndex = index;
      });
      _fetchRankings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double screenWidth = MediaQuery.of(context).size.width;
    final dc = DynamicConfigService();

    final bgImage = dc.globalRankBg.isNotEmpty
        ? dc.globalRankBg
        : (_mainTabIndex == 0 ? 'assets/images/rank_room_bg.webp' : 'assets/images/rank_charm_bg.webp');

    return Container(
      width: screenWidth,
      height: screenHeight * 0.88,
      decoration: BoxDecoration(
        color: const Color(0xFF16151A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        image: DecorationImage(
          image: AssetImage(bgImage),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      ),
      child: Stack(
        children: [
          // Background light glow (rank_room_light_ic.webp)
          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Opacity(
              opacity: 0.85,
              child: Image.asset(
                'assets/images/rank_room_light_ic.webp',
                fit: BoxFit.fitWidth,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),

          // Close button
          Positioned(
            top: 16,
            left: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ),
          ),

          Column(
            children: [
              const SizedBox(height: 16),
              // Main Tabs (السحر، الثروة)
              _buildMainTabs(),
              const SizedBox(height: 14),
              // Sub Tabs (يوميا، أسبوعيًا، شهريا)
              _buildSubTabs(),
              const SizedBox(height: 10),

              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFD54F)))
                    : _rankings.isEmpty
                        ? _buildEmptyState()
                        : _buildRankContent(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(
          'assets/images/rank_yesterday_top_1.webp',
          width: 90,
          height: 90,
          errorBuilder: (_, __, ___) => const Icon(Icons.emoji_events, color: Color(0xFFFFD54F), size: 70),
        ),
        const SizedBox(height: 12),
        const Text(
          'لا توجد بيانات ترتيب حالياً',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildRankContent() {
    // Top 3 users for podium
    final top1 = _rankings.isNotEmpty ? _rankings[0] : null;
    final top2 = _rankings.length > 1 ? _rankings[1] : null;
    final top3 = _rankings.length > 2 ? _rankings[2] : null;
    final restList = _rankings.length > 3 ? _rankings.sublist(3) : <Map<String, dynamic>>[];

    return CustomScrollView(
      slivers: [
        // Top 3 Podium View (rank_adapter_item_second.xml)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: _buildPodium(top1: top1, top2: top2, top3: top3),
          ),
        ),

        // Rest of ranking list (rank_adapter_item.xml)
        if (restList.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = restList[index];
                  final rank = index + 4;
                  return _buildRestItem(item, rank);
                },
                childCount: restList.length,
              ),
            ),
          ),
      ],
    );
  }

  // Authentic Top 3 Podium (rank_adapter_item_second.xml)
  Widget _buildPodium({
    Map<String, dynamic>? top1,
    Map<String, dynamic>? top2,
    Map<String, dynamic>? top3,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Rank 2 (Left - cl_third)
        Expanded(
          flex: 3,
          child: _buildPodiumUser(
            item: top2,
            rank: 2,
            avatarSize: 62,
            frameSize: 104,
            frameAsset: 'assets/images/rank_top_avatar_2.webp',
            baseAsset: 'assets/images/rank_top_bg_2.webp',
          ),
        ),
        const SizedBox(width: 4),

        // Rank 1 (Center - cl_second, elevated)
        Expanded(
          flex: 4,
          child: _buildPodiumUser(
            item: top1,
            rank: 1,
            avatarSize: 76,
            frameSize: 124,
            frameAsset: 'assets/images/rank_top_avatar_1.webp',
            baseAsset: 'assets/images/rank_top_bg_1.webp',
            isCenter: true,
          ),
        ),
        const SizedBox(width: 4),

        // Rank 3 (Right - cl_four)
        Expanded(
          flex: 3,
          child: _buildPodiumUser(
            item: top3,
            rank: 3,
            avatarSize: 62,
            frameSize: 104,
            frameAsset: 'assets/images/rank_top_avatar_3.webp',
            baseAsset: 'assets/images/rank_top_bg_3.webp',
          ),
        ),
      ],
    );
  }

  Widget _buildPodiumUser({
    required Map<String, dynamic>? item,
    required int rank,
    required double avatarSize,
    required double frameSize,
    required String frameAsset,
    required String baseAsset,
    bool isCenter = false,
  }) {
    final photoUrl = (item?['user_photo_url'] ?? item?['photo_url'] ?? item?['photoUrl'] ?? '').toString();
    final name = (item?['user_name'] ?? item?['name'] ?? (item != null ? 'User' : 'شاغر')).toString();
    final rawCid = (item?['custom_id'] ?? item?['display_id'] ?? item?['customId'] ?? '').toString();
    final rawUid = (item?['uid'] ?? item?['id'] ?? item?['user_id'] ?? '').toString();
    final customId = (rawCid.isNotEmpty && !rawCid.contains('-')) 
        ? rawCid 
        : (rawUid.length > 8 ? rawUid.substring(0, 8) : rawUid);
    final value = item?['total_value'] ?? item?['amount'] ?? item?['points'] ?? item?['score'] ?? 0;

    return GestureDetector(
      onTap: () => _openUserProfile(item),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
        // Avatar + Authentic Frame (rank_top_avatar_1..3)
        SizedBox(
          width: frameSize,
          height: frameSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Avatar circle
              ClipOval(
                child: SizedBox(
                  width: avatarSize,
                  height: avatarSize,
                  child: photoUrl.isNotEmpty
                      ? R.loadImage(photoUrl, width: avatarSize, height: avatarSize, fit: BoxFit.cover)
                      : Container(
                          color: Colors.white10,
                          child: Icon(Icons.person, color: Colors.white38, size: avatarSize * 0.5),
                        ),
                ),
              ),
              // Authentic Crown/Ring Frame
              Image.asset(
                frameAsset,
                width: frameSize,
                height: frameSize,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),

        // Podium Base Image (rank_top_bg_1..3)
        Transform.translate(
          offset: const Offset(0, -12),
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Image.asset(
                baseAsset,
                width: double.infinity,
                fit: BoxFit.fitWidth,
                errorBuilder: (_, __, ___) => const SizedBox(height: 20),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 14, left: 4, right: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Name
                    Text(
                      name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isCenter ? 13 : 11,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    if (customId.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        'ID: $customId',
                        style: const TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 9,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    // Gold increase pill (rank_gold_shape_bg)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0x66000000),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x33FFD54F), width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/images/common_gold_ic_8.webp',
                            width: 12,
                            height: 12,
                            errorBuilder: (_, __, ___) => const Icon(Icons.monetization_on, size: 12, color: Color(0xFFFFD54F)),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$value',
                            style: const TextStyle(
                              color: Color(0xFFFAE9B5),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Image.asset(
                            'assets/images/rank_gold_increase_ic.webp',
                            width: 10,
                            height: 10,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  }

  // Authentic List Item (rank_adapter_item.xml)
  Widget _buildRestItem(Map<String, dynamic> item, int rank) {
    final photoUrl = (item['user_photo_url'] ?? item['photo_url'] ?? item['photoUrl'] ?? '').toString();
    final name = (item['user_name'] ?? item['name'] ?? 'User').toString();
    final rawCid = (item['custom_id'] ?? item['display_id'] ?? item['customId'] ?? '').toString();
    final rawUid = (item['uid'] ?? item['id'] ?? item['user_id'] ?? '').toString();
    final customId = (rawCid.isNotEmpty && !rawCid.contains('-')) 
        ? rawCid 
        : (rawUid.length > 8 ? rawUid.substring(0, 8) : rawUid);
    final value = item['total_value'] ?? item['amount'] ?? item['points'] ?? item['score'] ?? 0;
    final level = item['level'] ?? 1;

    return InkWell(
      onTap: () => _openUserProfile(item),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF16151A).withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          // Rank Number with rank_num_bg (32×38dp)
          SizedBox(
            width: 32,
            height: 38,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Image.asset(
                  'assets/images/rank_num_bg.webp',
                  width: 32,
                  height: 38,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
                Text(
                  '$rank',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // User Avatar (44×44dp)
          ClipOval(
            child: SizedBox(
              width: 44,
              height: 44,
              child: photoUrl.isNotEmpty
                  ? R.loadImage(photoUrl, width: 44, height: 44, fit: BoxFit.cover)
                  : Container(
                      color: Colors.white10,
                      child: const Icon(Icons.person, color: Colors.white38, size: 24),
                    ),
            ),
          ),
          const SizedBox(width: 12),

          // Name and ID column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Level badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFC525), Color(0xFFDE880F)],
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Lv.$level',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'ID: ${customId.isNotEmpty ? customId : '------'}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Gold pill with rank_gold_increase_ic
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x33FFD54F)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/common_gold_ic_8.webp',
                  width: 13,
                  height: 13,
                  errorBuilder: (_, __, ___) => const Icon(Icons.monetization_on, size: 13, color: Color(0xFFFFD54F)),
                ),
                const SizedBox(width: 4),
                Text(
                  '$value',
                  style: const TextStyle(
                    color: Color(0xFFFAE9B5),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Image.asset(
                  'assets/images/rank_gold_increase_ic.webp',
                  width: 11,
                  height: 11,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  }

  // Tab Controls
  Widget _buildMainTabs() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildMainTabItem('السحر', 1),
        const SizedBox(width: 48),
        _buildMainTabItem('الثروة', 0),
      ],
    );
  }

  Widget _buildMainTabItem(String title, int index) {
    final bool isActive = _mainTabIndex == index;
    return GestureDetector(
      onTap: () => _onMainTabChanged(index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              color: isActive ? const Color(0xFFFFD54F) : Colors.white70,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 24,
            height: 3,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFFFFD54F) : Colors.transparent,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      height: 34,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0x33FFD54F), width: 1),
      ),
      child: Row(
        children: [
          _buildSubTabItem('شهريا', 2),
          _buildSubTabItem('أسبوعيًا', 1),
          _buildSubTabItem('يوميا', 0),
        ],
      ),
    );
  }

  Widget _buildSubTabItem(String title, int index) {
    final bool isActive = _subTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onSubTabChanged(index),
        child: Container(
          alignment: Alignment.center,
          decoration: isActive
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(17),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD54F), Color(0xFFF57F17)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                )
              : null,
          child: Text(
            title,
            style: TextStyle(
              color: isActive ? Colors.black : Colors.white70,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}