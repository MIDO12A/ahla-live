import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../services/dynamic_config_service.dart';
import '../../services/supabase_service.dart';
import '../../providers/user_provider.dart';
import '../room/widgets/svga_player.dart';

class _DetailItem {
  final String name;
  final String description;
  final String svgaUrl;
  final String imageUrl;
  final bool isOwned;
  final String type;
  const _DetailItem({
    required this.name,
    this.description = '',
    this.svgaUrl = '',
    this.imageUrl = '',
    this.isOwned = false,
    this.type = '',
  });
}

class BadgesScreen extends StatefulWidget {
  const BadgesScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<BadgesScreen> createState() => _BadgesScreenState();
}

class _BadgesScreenState extends State<BadgesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SupabaseService _supabaseService = SupabaseService();
  List<Map<String, dynamic>> _allBadges = [];
  List<NecklaceItem> _allNecklaces = [];
  bool _loaded = false;
  _DetailItem? _detailItem;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTab.clamp(0, 1));
    _tabController.addListener(() => setState(() {}));
    _loadData();
  }

  Future<void> _loadData() async {
    final badges = await _supabaseService.getBadgesCatalog();
    _allBadges = badges;

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    final necklaces = await _supabaseService.getNecklacesCatalog();
    _allNecklaces = necklaces.map((n) {
      final nid = n['id']?.toString() ?? '';
      return NecklaceItem(
        id: nid,
        name: n['name']?.toString() ?? '',
        nameAr: n['name_ar']?.toString() ?? '',
        descriptionAr: n['description_ar']?.toString() ?? '',
        descriptionEn: n['description_en']?.toString() ?? '',
        imageUrl: n['image_url']?.toString() ?? '',
        svgaUrl: n['svga_url']?.toString(),
        owned: (user?.ownedItems.contains(nid) ?? false) || (user?.ownedNecklaces.contains(nid) ?? false),
      );
    }).toList();

    if (mounted) setState(() => _loaded = true);
  }

  bool _hasBadge(String badgeId) {
    final user = Provider.of<UserProvider>(context, listen: false).currentUser;
    if (user == null) return false;
    return user.ownedBadges.contains(badgeId);
  }

  String _badgeName(Map<String, dynamic> badge) {
    return badge['name_ar']?.toString() ?? badge['name']?.toString() ?? '';
  }

  String _badgeDesc(Map<String, dynamic> badge) {
    return badge['description_ar']?.toString() ?? badge['description']?.toString() ?? '';
  }

  void _openBadgeDetail(Map<String, dynamic> badge) {
    setState(() {
      _detailItem = _DetailItem(
        name: _badgeName(badge),
        description: _badgeDesc(badge),
        svgaUrl: badge['svga_url']?.toString() ?? '',
        imageUrl: badge['image_url']?.toString() ?? '',
        isOwned: _hasBadge(badge['id']?.toString() ?? ''),
        type: badge['type']?.toString() ?? '',
      );
    });
  }

  void _openNecklaceDetail(NecklaceItem item) {
    setState(() {
      _detailItem = _DetailItem(
        name: item.nameAr.isNotEmpty ? item.nameAr : item.name,
        description: item.descriptionAr,
        svgaUrl: item.svgaUrl ?? '',
        imageUrl: item.imageUrl,
        isOwned: item.owned,
        type: 'necklace',
      );
    });
  }

  void _closeDetail() {
    setState(() => _detailItem = null);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = DynamicConfigService();
    return ListenableBuilder(
      listenable: config,
      builder: (context, _) {
        final config = DynamicConfigService();
        return Scaffold(
          backgroundColor: config.primaryBg,
          body: Stack(
            children: [
              Positioned.fill(
                child: R.loadAsset(config.badgesBackgroundImage.isNotEmpty
                    ? config.badgesBackgroundImage
                    : 'assets/mipmap-xxhdpi/mine_mall_top_bg.webp',
                    fit: BoxFit.cover),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        height: 56,
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: R.loadAsset(R.backIc, width: 24, height: 24),
                              ),
                            ),
                            const Spacer(),
                            Text(config.screenTitles['badges'] ?? 'الشارات',
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            const SizedBox(width: 40),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          dividerColor: Colors.transparent,
                          indicator: BoxDecoration(
                            color: config.goldColor.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.white70,
                          tabs: [
                            Tab(text: config.screenTitles['badges_tab'] ?? 'الشارات'),
                            Tab(text: config.screenTitles['necklaces_tab'] ?? 'القلادات'),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildBadgesTab(config),
                          _buildNecklacesTab(config),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_detailItem != null) _buildDetailOverlay(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailOverlay() {
    final config = DynamicConfigService();
    final item = _detailItem!;
    return Positioned.fill(
      child: GestureDetector(
        onTap: _closeDetail,
        child: Stack(
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(color: Colors.black.withValues(alpha: 0.5)),
            ),
            Center(
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  constraints: const BoxConstraints(maxHeight: 500),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1a1a2e),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: config.badgesAccent.withValues(alpha: 0.3), width: 1),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        children: [
                          Container(
                            height: 220,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: config.badgesCardBg,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                              image: config.badgesCardBgImage.isNotEmpty
                                  ? DecorationImage(image: R.cachedImage(config.badgesCardBgImage), fit: BoxFit.cover)
                                  : null,
                              gradient: config.badgesCardBgImage.isNotEmpty
                                  ? null
                                  : LinearGradient(
                                      colors: [config.badgesHeaderBg, config.badgesCardBg],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                            ),
                            child: Center(
                              child: item.svgaUrl.isNotEmpty
                                  ? SvgaPlayer(assetPath: item.svgaUrl, width: 150, height: 150)
                                  : item.imageUrl.isNotEmpty
                                      ? R.loadAsset(item.imageUrl, width: 150, height: 150)
                                      : const SizedBox.shrink(),
                            ),
                          ),
                          Positioned(
                            top: 8, right: 8,
                            child: GestureDetector(
                              onTap: _closeDetail,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.black26,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(item.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                      ),
                      if (item.type.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: config.badgesAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: config.badgesAccent.withValues(alpha: 0.4)),
                          ),
                          child: Text(item.type == 'necklace' ? 'قلادة' : 'شارة', style: TextStyle(color: config.badgesAccent, fontSize: 10)),
                        ),
                      if (item.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                          child: Text(item.description, style: TextStyle(color: config.badgesSubText, fontSize: 12, height: 1.4), textAlign: TextAlign.center),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(item.isOwned ? Icons.check_circle : Icons.lock, color: item.isOwned ? Colors.green : Colors.orange, size: 22),
                            const SizedBox(width: 6),
                            Text(item.isOwned ? 'مملوك' : 'غير مملوك', style: TextStyle(color: item.isOwned ? Colors.green : Colors.orange, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _boxWithImage(Color color, String imageUrl, {double radius = 12, Color? borderColor, double borderWidth = 1.5}) {
    BoxDecoration d = BoxDecoration(
      color: imageUrl.isNotEmpty ? null : color,
      borderRadius: BorderRadius.circular(radius),
    );
    if (borderColor != null) {
      d = d.copyWith(border: Border.all(color: borderColor, width: borderWidth));
    }
    if (imageUrl.isNotEmpty) {
      d = d.copyWith(image: DecorationImage(image: R.cachedImage(imageUrl), fit: BoxFit.cover));
    }
    return d;
  }

  Widget _buildBadgesTab(DynamicConfigService config) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_allBadges.isEmpty) return Center(child: Text(config.screenTitles['no_badges'] ?? 'لا توجد شارات', style: TextStyle(color: config.textSecondary)));

    return GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.0,
            ),
            itemCount: _allBadges.length,
            itemBuilder: (context, index) {
              final badge = _allBadges[index];
              final bid = badge['id']?.toString() ?? '';
              final bSvg = badge['svga_url']?.toString() ?? '';
              final bImg = badge['image_url']?.toString() ?? '';
              final owned = _hasBadge(bid);
              final bName = _badgeName(badge);
              return GestureDetector(
                onTap: () => _openBadgeDetail(badge),
                child: Container(
                  decoration: _boxWithImage(
                    config.badgesItemBg.withValues(alpha: 0.5),
                    config.badgesItemBgImage,
                    radius: 12,
                    borderColor: config.badgesCardBorder.withValues(alpha: 0.2),
                    borderWidth: 1.5,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          if (bSvg.isNotEmpty)
                            SizedBox(width: 40, height: 40, child: SvgaPlayer(assetPath: bSvg, width: 40, height: 40))
                          else if (bImg.isNotEmpty)
                            R.loadAsset(bImg, width: 40, height: 40),
                          if (!owned)
                            R.loadAsset(config.badgesLockImage.isNotEmpty ? config.badgesLockImage : 'assets/mipmap-xxhdpi/room_gift_ic.webp', width: 20, height: 20),
                        ],
                      ),
                      if (bName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(bName, style: TextStyle(color: config.badgesTextColor, fontSize: 9), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ),
              );
            },
    );
  }

  Widget _buildNecklacesTab(DynamicConfigService config) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_allNecklaces.isEmpty) return Center(child: Text(config.screenTitles['no_necklaces'] ?? 'لا توجد قلادات', style: TextStyle(color: config.textSecondary)));

    return GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.0,
            ),
            itemCount: _allNecklaces.length,
            itemBuilder: (context, index) {
              final n = _allNecklaces[index];
              final nSvg = n.svgaUrl ?? '';
              final nName = n.nameAr.isNotEmpty ? n.nameAr : n.name;
              return GestureDetector(
                onTap: () => _openNecklaceDetail(n),
                child: Container(
                  decoration: _boxWithImage(
                    config.necklacesItemBg.withValues(alpha: 0.5),
                    config.necklacesItemBgImage,
                    radius: 12,
                    borderColor: config.necklacesCardBorder.withValues(alpha: 0.2),
                    borderWidth: 1.5,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          if (nSvg.isNotEmpty)
                            SizedBox(width: 56, height: 56, child: SvgaPlayer(assetPath: nSvg, width: 56, height: 56))
                          else if (n.imageUrl.isNotEmpty)
                            R.loadAsset(n.imageUrl, width: 56, height: 56),
                          if (!n.owned)
                            R.loadAsset(config.necklacesLockImage.isNotEmpty ? config.necklacesLockImage : 'assets/mipmap-xxhdpi/room_gift_ic.webp', width: 20, height: 20),
                        ],
                      ),
                      if (nName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(nName, style: TextStyle(color: config.necklacesTextColor, fontSize: 9), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ),
              );
            },
    );
  }
}

class NecklaceItem {
  final String id;
  final String name;
  final String nameAr;
  final String descriptionAr;
  final String descriptionEn;
  final String imageUrl;
  final String? svgaUrl;
  final bool owned;
  NecklaceItem({
    required this.id,
    required this.name,
    this.nameAr = '',
    this.descriptionAr = '',
    this.descriptionEn = '',
    required this.imageUrl,
    this.svgaUrl,
    this.owned = false,
  });
}
