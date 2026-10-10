import 'package:flutter/material.dart';
import '../../core/supabase_compat.dart';
import '../../core/widgets/cached_image.dart';
import 'package:provider/provider.dart';
import '../room/widgets/svga_player.dart';
import '../room/widgets/vap_player.dart';
import '../../config/r.dart';
import '../../providers/user_provider.dart';
import '../../services/api_service.dart';
import '../../services/supabase_service.dart';
import '../../services/supabase_data_service.dart';
import '../../services/dynamic_config_service.dart';
import '../wallet/wallet_main_screen.dart';

const _vip = 'assets/vip';

class VipCenterScreen extends StatefulWidget {
  const VipCenterScreen({super.key});
  @override
  State<VipCenterScreen> createState() => _VipCenterScreenState();
}

class _VipCenterScreenState extends State<VipCenterScreen> {
  final _supabase = Supabase.instance.client;
  final _api = ApiService();
  List<Map<String, dynamic>> _tiers = [];
  int _selectedIndex = 0;
  bool _loading = true;
  bool _purchasing = false;
  late final PageController _pageController = PageController();
  late final RealtimeChannel _realtimeSub;

  @override
  void initState() {
    super.initState();
    _loadTiers();
    _loadUserVip();
    _realtimeSub = _supabase.channel('vip_config_screen').onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'vip_config',
      callback: (_) => _loadTiers(),
    ).subscribe();
  }

  @override
  void dispose() {
    _supabase.removeChannel(_realtimeSub);
    super.dispose();
  }

  Future<void> _loadUserVip() async {
    final user = context.read<UserProvider>().currentUser;
    if (user == null) return;
    try {
      await _api.getUserVip(user.uid);
    } catch (_) {}
  }

  Future<void> _loadTiers() async {
    try {
      var tiers = await SupabaseDataService().getVipConfigs();
      if (tiers.isEmpty) {
        final res = await _supabase.from('vip_config').select('*').order('tier');
        tiers = (res as List).cast<Map<String, dynamic>>();
      }
      if (mounted) {
        setState(() {
          _tiers = tiers;
          int minIdx = 0;
          int? minTier;
          for (int i = 0; i < tiers.length; i++) {
            final t = tiers[i]['tier'];
            final tn = t is int ? t : int.tryParse(t?.toString() ?? '');
            if (tn != null && (minTier == null || tn < minTier)) {
              minTier = tn;
              minIdx = i;
            }
          }
          _selectedIndex = minIdx;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Map<String, dynamic>? get _tier => _tiers.isNotEmpty ? _tiers[_selectedIndex] : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _tiers.length,
                    onPageChanged: (i) => setState(() => _selectedIndex = i),
                    itemBuilder: (_, i) {
                      return _TierPage(
                        tier: _tiers[i],
                      );
                    },
                  ),
                ),
                if (_tiers.isNotEmpty)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 12,
                    right: 12,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _buildVipNameHeader(_tier!),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70, size: 24),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_tiers.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildPurchaseBar(_tier!),
                  ),
              ],
            ),
    );
  }

  Widget _buildVipNameHeader(Map<String, dynamic> t) {
    final nameImg = (t['image_url']?.toString().isNotEmpty == true)
        ? t['image_url']?.toString()
        : null;
    final name = t['name']?.toString() ?? 'VIP';
    if (nameImg != null && nameImg.isNotEmpty) {
      return CachedNetImage(
        nameImg,
        height: 32,
        fit: BoxFit.contain,
        error: (_, __, ___) => Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
          ),
        ),
      );
    }
    return Text(
      name,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
      ),
    );
  }

  Widget _buildPurchaseBar(Map<String, dynamic> t) {
    final cfg = DynamicConfigService();
    final price = t['price'];
    final priceStr = price != null ? '${price.toStringAsFixed(0)}' : '--';

    final buyBtnImgUrl = t['buy_btn_img_url']?.toString() ?? (cfg.vipBuyBtnImgUrl.isNotEmpty ? cfg.vipBuyBtnImgUrl : null);
    final coinImgUrl = t['coin_img_url']?.toString() ?? (cfg.vipCoinImgUrl.isNotEmpty ? cfg.vipCoinImgUrl : null);
    final barBgStr = t['purchase_bar_bg']?.toString();
    final isBarBgUrl = barBgStr != null && (barBgStr.startsWith('http://') || barBgStr.startsWith('https://'));
    final perTierBgImg = isBarBgUrl ? barBgStr : null;
    final barBgImg = perTierBgImg ?? (cfg.vipPurchaseBarImgUrl.isNotEmpty ? cfg.vipPurchaseBarImgUrl : null);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.all(Radius.circular(cfg.borderRadius.toDouble() + 8)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.all(Radius.circular(cfg.borderRadius.toDouble() + 8)),
        child: Stack(
          children: [
            if (barBgImg != null)
              Positioned.fill(
                child: CachedNetImage(barBgImg, fit: BoxFit.cover),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(cfg.borderRadius.toDouble()),
                    ),
                    child: coinImgUrl != null && coinImgUrl.isNotEmpty
                        ? CachedNetImage(coinImgUrl, fit: BoxFit.contain, width: 28, height: 28)
                        : R.loadImage(
                            '$_vip/ico_vip_04coin.webp',
                            fit: BoxFit.contain,
                            width: 28,
                            height: 28,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Coins',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        priceStr,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: cfg.goldColor,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _purchasing ? null : () => _handlePurchase(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      decoration: BoxDecoration(
                        color: cfg.buttonColor,
                        borderRadius: BorderRadius.circular(cfg.borderRadius.toDouble()),
                        boxShadow: [
                          BoxShadow(
                            color: cfg.buttonColor.withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: _purchasing
                          ? SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: cfg.buttonTextColor))
                          : (buyBtnImgUrl != null && buyBtnImgUrl.isNotEmpty
                              ? CachedNetImage(buyBtnImgUrl, height: 24, fit: BoxFit.contain)
                              : Text(
                                  'Buy',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: cfg.buttonTextColor,
                                  ),
                                )),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePurchase() async {
    final t = _tier;
    if (t == null) return;
    final price = t['price'];
    if (price == null) return;
    final priceInt = price is int ? price : (price is double ? price.toInt() : int.tryParse(price.toString()) ?? 0);
    if (priceInt <= 0) return;

    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;
    if (user == null) return;

    // Quick client-side check for immediate feedback (real check happens in the transaction)
    if (user.coins < priceInt) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرصيد غير كافي! جارٍ تحويلك إلى الشحن...')),
      );
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => const WalletMainScreen(),
        ));
      }
      return;
    }

    setState(() => _purchasing = true);
    try {
      final uid = user.uid;

      final ownedItems = List<String>.from(user.ownedItems);
      final ownedVipItems = user.ownedVipItems.map((m) => Map<String, String>.from(m)).toList();

      String dbKey(String field, String fallback) {
        final k = t['${field}_key']?.toString();
        return (k != null && k.isNotEmpty) ? k : fallback;
      }

      void processAcc(String? url, String key) {
        if (url != null && url.isNotEmpty && !ownedItems.contains(url)) {
          ownedItems.add(url);
        }
      }

      void processImg(String? url) {
        if (url != null && url.isNotEmpty && !ownedItems.contains(url)) {
          ownedItems.add(url);
        }
      }

      void addVipItem(String type, String? url, String? name) {
        if (url == null || url.isEmpty) return;
        final already = ownedVipItems.any((m) => m['url'] == url);
        if (!already) {
          ownedVipItems.add({'type': type, 'url': url, 'name': name ?? 'VIP'});
        }
      }

      addVipItem('frame', t['headwear_url']?.toString(), t['headwear_name']?.toString());
      processAcc(t['headwear_url']?.toString(), dbKey('headwear', 'active_headwear'));
      processImg(t['headwear_img_url']?.toString());
      addVipItem('bubble', t['bubble_url']?.toString(), t['bubble_name']?.toString());
      processAcc(t['bubble_url']?.toString(), dbKey('bubble', 'active_bubble'));
      processImg(t['bubble_img_url']?.toString());
      addVipItem('entrance', t['entrance_url']?.toString(), t['entrance_name']?.toString());
      processAcc(t['entrance_url']?.toString(), dbKey('entrance', 'active_entrance'));
      processImg(t['entrance_img_url']?.toString());
      addVipItem('necklace', t['necklace_url']?.toString(), t['necklace_name']?.toString());
      processAcc(t['necklace_url']?.toString(), dbKey('necklace', 'active_necklace'));
      processImg(t['necklace_img_url']?.toString());
      addVipItem('car', t['car_url']?.toString(), t['car_name']?.toString());
      processAcc(t['car_url']?.toString(), dbKey('car', 'active_car'));
      processImg(t['car_img_url']?.toString());
      addVipItem('cover', t['cover_url']?.toString(), t['cover_name']?.toString());
      processAcc(t['cover_url']?.toString(), dbKey('cover', 'active_cover'));
      processImg(t['cover_img_url']?.toString());
      addVipItem('medal', t['medal_url']?.toString(), t['medal_name']?.toString());
      processImg(t['medal_url']?.toString());
      processImg(t['medal_img_url']?.toString());

      final additional = t['additional_files'];
      if (additional is List) {
        for (final f in additional) {
          final fm = f as Map<String, dynamic>;
          final url = fm['url']?.toString();
          if (url != null && url.isNotEmpty) {
            addVipItem(fm['type']?.toString() ?? 'item', url, fm['name']?.toString());
            processImg(url);
          }
        }
      }

      final items = t['items'];
      if (items is List) {
        for (final item in items) {
          final m = item as Map<String, dynamic>;
          final url = m['svgaUrl']?.toString() ?? m['img']?.toString();
          if (url != null && url.isNotEmpty) {
            addVipItem('item', url, m['name']?.toString() ?? m['title']?.toString());
            processImg(url);
          }
        }
      }

      // ✅ Add ALL store_items from VIP categories to backpack
      final vipCategories = ['car', 'bubble', 'entrance', 'frame', 'cover'];
      try {
        final storeItems = await _supabase
            .from('store_items')
            .select('item_id')
            .inFilter('category', vipCategories);
        for (final s in (storeItems as List<dynamic>?) ?? []) {
          final id = s['item_id']?.toString();
          if (id != null && !ownedItems.contains(id)) {
            ownedItems.add(id);
          }
        }
      } catch (_) {}

      // ✅ Transactional coin deduction — real balance check on Firestore
      final deducted = await FirebaseService().deductCoins(uid, priceInt, 'vip_purchase');
      if (!deducted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('الرصيد غير كافي! جارٍ تحويلك إلى الشحن...')),
          );
          await Future.delayed(const Duration(milliseconds: 500));
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => const WalletMainScreen(),
          ));
        }
        return;
      }

      final updates = <String, dynamic>{
        'owned_items': ownedItems,
        'owned_vip_items': ownedVipItems,
        'active_headwear': t['headwear_url']?.toString() ?? user.activeHeadwear,
        'active_frame': t['headwear_url']?.toString() ?? user.activeFrame,
        'active_bubble': t['bubble_url']?.toString() ?? user.activeBubble,
        'active_entrance': t['entrance_url']?.toString() ?? user.activeEntrance,
        'active_necklace': t['necklace_url']?.toString() ?? user.activeNecklace,
        'active_car': t['car_url']?.toString() ?? user.activeCar,
        'active_cover': t['cover_url']?.toString() ?? user.activeCover,
      };
      updates.removeWhere((k, v) => v == null || v.toString().isEmpty);

      await _supabase.from('users').update(updates).eq('uid', uid);
      // Reload the user so the backpack and balance update immediately
      await userProvider.loadUser(uid);
      if (mounted) await _loadUserVip();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم شراء VIP بنجاح! تم تجهيز الإكسسوارات وإضافتها إلى الحقيبة.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الشراء: $e')),
        );
      }
    }
    if (mounted) setState(() => _purchasing = false);
  }

}

class _TierPage extends StatelessWidget {
  final Map<String, dynamic> tier;
  const _TierPage({required this.tier});

  @override
  Widget build(BuildContext context) {
    final topRowHeight = 56.0;
    final topPad = MediaQuery.of(context).padding.top + 8 + topRowHeight + 12;
    final bgUrl = tier['bg_url']?.toString();
    final tierNum = tier['tier']?.toString() ?? '1';

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildBg(context, bgUrl, tierNum),
        SingleChildScrollView(
          padding: EdgeInsets.only(top: topPad, bottom: 130),
          child: _TierContent(tier: tier),
        ),
      ],
    );
  }

  Widget _buildBg(BuildContext context, String? bgUrl, String tierNum) {
    if (bgUrl != null && bgUrl.isNotEmpty) {
      if (isVideoType(bgUrl)) {
        return VapPlayer(url: bgUrl, fit: BoxFit.fill, loops: true);
      }
      return CachedNetImage(
        bgUrl,
        fit: BoxFit.fill,
        width: double.infinity,
        height: double.infinity,
        error: (_, __, ___) => _assetBg(tierNum),
      );
    }
    return _assetBg(tierNum);
  }

  Widget _assetBg(String tierNum) {
    final cfg = DynamicConfigService();
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          '$_vip/img_vip_bg_$tierNum.webp',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.2,
                colors: [
                  cfg.vipCardBgColor,
                  Color.alphaBlend(cfg.vipCardBgColor.withValues(alpha: 0.7), Colors.black),
                  Colors.black,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0, right: 0, bottom: 0, height: 80,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, const Color(0xFF0A1F0A)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TierContent extends StatelessWidget {
  final Map<String, dynamic> tier;
  const _TierContent({required this.tier});

  List<Map<String, String?>> _accessories() {
    final accessories = <Map<String, String?>>[];
    void addAcc(String? img, String? svgaUrl, String name, String type, {String? cardBg, String? key}) {
      if ((img == null || img.isEmpty) && (svgaUrl == null || svgaUrl.isEmpty)) return;
      accessories.add({'img': img ?? '', 'svga': svgaUrl ?? '', 'name': name, 'type': type, 'cardBg': cardBg, 'key': key ?? ''});
    }

    addAcc(tier['headwear_img_url']?.toString(), tier['headwear_url']?.toString(), tier['headwear_name']?.toString() ?? 'Frame', 'frame', cardBg: tier['headwear_card_bg']?.toString(), key: tier['headwear_key']?.toString());
    addAcc(tier['bubble_img_url']?.toString(), tier['bubble_url']?.toString(), tier['bubble_name']?.toString() ?? 'Bubble', 'bubble', cardBg: tier['bubble_card_bg']?.toString(), key: tier['bubble_key']?.toString());
    addAcc(tier['entrance_img_url']?.toString(), tier['entrance_url']?.toString(), tier['entrance_name']?.toString() ?? 'Entrance', 'entrance', cardBg: tier['entrance_card_bg']?.toString(), key: tier['entrance_key']?.toString());
    addAcc(tier['necklace_img_url']?.toString(), tier['necklace_url']?.toString(), tier['necklace_name']?.toString() ?? 'Necklace', 'necklace', cardBg: tier['necklace_card_bg']?.toString(), key: tier['necklace_key']?.toString());
    addAcc(tier['car_img_url']?.toString(), tier['car_url']?.toString(), tier['car_name']?.toString() ?? 'Car', 'car', cardBg: tier['car_card_bg']?.toString(), key: tier['car_key']?.toString());
    addAcc(tier['cover_img_url']?.toString(), tier['cover_url']?.toString(), tier['cover_name']?.toString() ?? 'Cover', 'cover', cardBg: tier['cover_card_bg']?.toString(), key: tier['cover_key']?.toString());
    addAcc(tier['ring_img_url']?.toString(), tier['ring_url']?.toString(), tier['ring_name']?.toString() ?? 'Ring', 'ring', cardBg: tier['ring_card_bg']?.toString(), key: tier['ring_key']?.toString());

    // 1. Benefits (امتيازات VIP المضافة من اللوحة)
    final benefits = tier['benefits'];
    if (benefits is List) {
      for (final b in benefits) {
        if (b == null) continue;
        if (b is String && b.isNotEmpty) {
          String bName = b;
          String bImg = '$_vip/ico_vip_marking_vip1.webp';
          if (b.toLowerCase().contains('badge') || b.contains('شارة')) {
            bName = 'شارة VIP';
            bImg = '$_vip/ico_vip_marking_vip1.webp';
          } else if (b.toLowerCase().contains('room') || b.contains('إطار') || b.contains('border')) {
            bName = 'إطار الغرفة المميز';
            bImg = '$_vip/img_kuang_vip_1.webp';
          } else if (b.toLowerCase().contains('level') || b.contains('مستوى')) {
            bName = 'تسريع ترقية المستوى';
            bImg = 'assets/mipmap-xxhdpi/mine_level_ic.webp';
          } else if (b.toLowerCase().contains('custom_id') || b.contains('آيدي') || b.contains('id')) {
            bName = 'آيدي VIP خاص';
            bImg = 'assets/mipmap-xxhdpi/common_user_id_ic.webp';
          }
          accessories.add({
            'img': bImg,
            'svga': null,
            'name': bName,
            'type': 'benefit',
            'key': b,
          });
        } else if (b is Map) {
          final bm = Map<String, dynamic>.from(b);
          final img = bm['img']?.toString() ?? bm['icon']?.toString() ?? bm['url']?.toString();
          final svga = bm['svga']?.toString() ?? bm['svgaUrl']?.toString();
          final name = bm['name']?.toString() ?? bm['title']?.toString() ?? 'Benefit';
          accessories.add({
            'img': img ?? svga ?? '$_vip/ico_vip_marking_vip1.webp',
            'svga': svga,
            'name': name,
            'type': bm['type']?.toString() ?? 'benefit',
            'key': bm['key']?.toString() ?? '',
          });
        }
      }
    }

    // 2. Additional Files
    final additional = tier['additional_files'];
    if (additional is List) {
      for (final f in additional) {
        final fm = f as Map<String, dynamic>;
        final url = fm['url']?.toString();
        if (url != null && url.isNotEmpty) {
          final ft = fm['type']?.toString() ?? '';
          accessories.add({
            'img': url,
            'svga': ft == 'svga' ? url : null,
            'name': fm['name']?.toString() ?? 'Accessory',
            'type': ft,
            'key': fm['key']?.toString() ?? '',
          });
        }
      }
    }

    // 3. Custom Items
    final items = tier['items'];
    if (items is List) {
      for (final item in items) {
        final m = item as Map<String, dynamic>;
        final img = m['img']?.toString();
        final svga = m['svgaUrl']?.toString();
        if ((img != null && img.isNotEmpty) || (svga != null && svga.isNotEmpty)) {
          accessories.add({
            'img': img ?? svga,
            'svga': svga,
            'name': m['name']?.toString() ?? m['title']?.toString() ?? 'Item',
            'type': 'item',
            'key': m['key']?.toString() ?? '',
          });
        }
      }
    }

    // 4. Custom Accessories list
    final accList = tier['accessories'];
    if (accList is List) {
      for (final acc in accList) {
        if (acc is Map) {
          final m = Map<String, dynamic>.from(acc);
          final img = m['img']?.toString() ?? m['icon']?.toString() ?? m['url']?.toString();
          final svga = m['svga']?.toString() ?? m['svgaUrl']?.toString();
          if ((img != null && img.isNotEmpty) || (svga != null && svga.isNotEmpty)) {
            accessories.add({
              'img': img ?? svga,
              'svga': svga,
              'name': m['name']?.toString() ?? m['title']?.toString() ?? 'Accessory',
              'type': m['type']?.toString() ?? 'accessory',
              'key': m['key']?.toString() ?? '',
            });
          }
        }
      }
    }

    return accessories;
  }

  @override
  Widget build(BuildContext context) {
    final badgeImg = tier['medal_img_url']?.toString();
    final badgeSvga = tier['medal_url']?.toString();
    final accessories = _accessories();

    return Column(
      children: [
        if (badgeSvga != null && badgeSvga.isNotEmpty)
          SizedBox(
            height: 160,
            child: Center(
              child: SvgaPlayer(assetPath: badgeSvga, width: 140, height: 140, loops: true),
            ),
          )
        else if (badgeImg != null && badgeImg.isNotEmpty)
          SizedBox(
            height: 160,
            child: Center(
              child: isVideoType(badgeImg)
                  ? VapPlayer(url: badgeImg, width: 140, height: 140, loops: true)
                  : CachedNetImage(badgeImg, height: 140, fit: BoxFit.contain),
            ),
          ),
        const SizedBox(height: 20),
        _divider(),
        const SizedBox(height: 16),
        if (accessories.isNotEmpty)
          _grid(context, accessories)
        else
          _defaultGrid(context),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _divider() {
    final cfg = DynamicConfigService();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      height: 2,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, cfg.goldColor, Colors.transparent],
        ),
        boxShadow: [
          BoxShadow(
            color: cfg.goldColor.withValues(alpha: 0.3),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }

  Color _tierColor() {
    final c = tier['color']?.toString();
    if (c == null || c.isEmpty) return const Color(0xFFDE880F);
    if (c.startsWith('http://') || c.startsWith('https://')) return const Color(0xFFDE880F);
    try { return Color(int.parse(c.replaceFirst('#', '0xFF'))); }
    catch (_) { return const Color(0xFFDE880F); }
  }

  double _cardRadius() {
    final r = tier['card_radius'];
    if (r is num) return r.toDouble();
    return 16;
  }

  Widget _grid(BuildContext context, List<Map<String, String?>> items) {
    final color = _tierColor();
    final radius = _cardRadius();
    final globalCardBg = tier['card_bg_url']?.toString();
    final chunks = <List<Map<String, String?>>>[];
    for (int i = 0; i < items.length; i += 3) {
      chunks.add(items.sublist(i, i + 3 > items.length ? items.length : i + 3));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: chunks.map((chunk) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: chunk.map((item) {
                return Expanded(child: _itemCard(context, item, color, radius, globalCardBg));
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _defaultGrid(BuildContext context) {
    final tierNum = tier['tier']?.toString() ?? '1';
    final defaultItems = [
      {'type': 'badge', 'name': 'Badge', 'img': '$_vip/ico_vip_marking_vip$tierNum.webp', 'svga': null},
      {'type': 'frame', 'name': 'Frame', 'img': '$_vip/img_kuang_vip_1.webp', 'svga': null},
      {'type': 'bubble', 'name': 'Bubble', 'img': '$_vip/ico_vip_lv$tierNum.webp', 'svga': null},
      {'type': 'entrance', 'name': 'Entrance', 'img': '$_vip/dressing_vip$tierNum.webp', 'svga': null},
      {'type': 'necklace', 'name': 'Necklace', 'img': '$_vip/ico_vip_marking_vip$tierNum.webp', 'svga': null},
      {'type': 'car', 'name': 'Car', 'img': '$_vip/ico_vip_marking_vip$tierNum.webp', 'svga': null},
      {'type': 'cover', 'name': 'Cover', 'img': '$_vip/ico_vip_marking_vip$tierNum.webp', 'svga': null},
      {'type': 'item', 'name': 'VIP $tierNum', 'img': '$_vip/vip${tierNum}_1.webp', 'svga': null},
    ];
    return _grid(context, defaultItems);
  }

  Widget _itemCard(BuildContext context, Map<String, String?> item, Color color, double radius, String? globalCardBg) {
    final cfg = DynamicConfigService();
    final svga = item['svga'] ?? '';
    final img = (item['img']?.isNotEmpty == true) ? item['img']! : svga;
    final name = item['name'] ?? '';
    final hasSvga = svga.isNotEmpty;
    final cardBg = (globalCardBg?.isNotEmpty == true) ? globalCardBg : (cfg.vipCardBgImgUrl.isNotEmpty ? cfg.vipCardBgImgUrl : null);

    return GestureDetector(
      onTap: () {
        final previewUrl = hasSvga ? item['svga']! : img;
        if (previewUrl.isNotEmpty) _showPreview(context, previewUrl, name, hasSvga, color, item['type'] ?? '');
      },
      child: Container(
        margin: const EdgeInsets.all(4),
        constraints: const BoxConstraints(maxHeight: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: cfg.vipCardBorderColor.withValues(alpha: 0.3), width: 1),
        ),
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (cardBg != null && cardBg.isNotEmpty)
                  CachedNetImage(
                    cardBg,
                    fit: BoxFit.cover,
                    error: (_, __, ___) =>
                        Container(color: cfg.vipCardBgColor.withValues(alpha: 0.6)),
                  )
                else
                  Container(color: cfg.vipCardBgColor.withValues(alpha: 0.6)),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _preview(img, color, hasSvga: hasSvga),
                      ),
                    ),
                    if (name.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 10,
                            color: color.withValues(alpha: 0.8),
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _preview(String imgUrl, Color color, {bool hasSvga = false}) {
    if (imgUrl.isEmpty) {
      if (hasSvga) return Icon(Icons.movie_creation_outlined, color: color, size: 30);
      return const SizedBox.shrink();
    }
    if (imgUrl.startsWith('http')) {
      if (isVideoType(imgUrl)) {
        return VapPlayer(url: imgUrl, fit: BoxFit.contain);
      }
      return CachedNetImage(
        imgUrl,
        fit: BoxFit.contain,
        error: (_, __, ___) =>
            hasSvga ? Icon(Icons.movie_creation_outlined, color: color, size: 30) : Icon(Icons.star, color: color, size: 30),
      );
    }
    return Image.asset(
      imgUrl,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          hasSvga ? Icon(Icons.movie_creation_outlined, color: color, size: 30) : Icon(Icons.star, color: color, size: 30),
    );
  }

  void _showPreview(BuildContext context, String url, String name, bool isSvga, Color color, String type) {
    final isBubble = type == 'bubble';
    final isVideo = isVideoType(url);

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (name.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: isSvga && url.endsWith('.svga')
                              ? SvgaPlayer(assetPath: url, width: 320, height: 320, loops: true)
                              : isVideo
                                  ? VapPlayer(url: url, width: 320, height: 320, loops: true)
                                  : R.loadImage(url, fit: BoxFit.contain),
                        ),
                        if (isBubble)
                          Positioned(
                            top: 40,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Text(
                                'السلام عليكم',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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
      ),
    );
  }
}
