import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/r.dart';
import '../../../features/cp/cp_service.dart';
import '../../../models/gift_model.dart' as gm;
import '../../../models/gift_category_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/supabase_service.dart';
import '../../../services/media_prefetch_service.dart';
import '../../../services/dynamic_config_service.dart';
import '../../wallet/wallet_main_screen.dart';
import 'svga_player.dart';
import 'vap_player.dart';

class GiftPanel extends StatefulWidget {
  final int selectedCount;
  final int coins;
  final List<Map<String, dynamic>> targetUsers;
  final String roomId;
  final VoidCallback? onSend;
  final ValueChanged<String?>? onSendGift;
  final ValueChanged<Map<String, dynamic>?>? onSendGiftExtended;
  final VoidCallback? onCountTap;
  final String? receiverId;
  final String? receiverName;

  const GiftPanel({
    super.key,
    this.selectedCount = 1,
    this.coins = 0,
    this.targetUsers = const [],
    this.roomId = '',
    this.onSend,
    this.onSendGift,
    this.onSendGiftExtended,
    this.onCountTap,
    this.receiverId,
    this.receiverName,
  });

  @override
  State<GiftPanel> createState() => _GiftPanelState();
}

class _GiftPanelState extends State<GiftPanel> {
  int _sel = -1;
  bool _sending = false;
  String? _errorMsg;
  final Set<String> _selectedUserIds = {};
  bool _isAllSelected = false;
  List<gm.GiftModel> _gifts = [];
  List<GiftCategory> _categories = [];
  String? _selectedCategoryId;
  StreamSubscription? _giftSub;
  StreamSubscription? _catSub;
  Timer? _comboTimer;
  int _comboSeconds = 0;
  int _comboMultiplier = 0;
  int _comboRemainingMs = 0;
  final List<Timer> _pendingDelays = [];

  @override
  void initState() {
    super.initState();
    _initSelection();
    _loadGifts();
  }

  void _initSelection() {
    _selectedUserIds.clear();
    if (widget.receiverId != null && widget.receiverId!.isNotEmpty) {
      _selectedUserIds.add(widget.receiverId!);
      _isAllSelected = false;
    } else {
      _isAllSelected = true;
      _selectedUserIds.addAll(
        widget.targetUsers
            .map((u) => u['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty),
      );
    }
  }

  @override
  void dispose() {
    for (final t in _pendingDelays) {
      t.cancel();
    }
    _comboTimer?.cancel();
    _giftSub?.cancel();
    _catSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(GiftPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.receiverId != oldWidget.receiverId) {
      _initSelection();
    }
  }

  void _loadGifts() {
    final fb = SupabaseService();
    _catSub = fb.giftCategoriesStream().listen((cats) {
      if (mounted) {
        setState(() {
          _categories = cats;
          _selectedCategoryId ??= 'all';
        });
      }
    });
    _giftSub = fb.giftsStream().listen((gifts) {
      MediaPrefetchService().prefetchGifts(gifts);
      if (mounted) {
        setState(() {
          _gifts = gifts;
          if (_sel >= _gifts.length) _sel = -1;
        });
      }
    });
  }

  List<gm.GiftModel> get _filteredGifts {
    if (_selectedCategoryId == null || _selectedCategoryId == 'all') {
      return _gifts;
    }
    final sel = _selectedCategoryId!.toLowerCase();
    if (sel == 'lucky' || sel.contains('حظ')) {
      return _gifts.where((g) => g.isLucky || g.giftType == 3 || g.categoryId == 'lucky' || (g.categoryId?.toLowerCase().contains('حظ') ?? false)).toList();
    }
    if (sel == 'luxury' || sel == 'vip' || sel.contains('فاخر')) {
      return _gifts.where((g) => g.isVap || g.bigEffect || g.giftType == 2 || g.categoryId == 'vip' || g.categoryId == 'luxury' || (g.categoryId?.toLowerCase().contains('فاخر') ?? false)).toList();
    }
    if (sel == 'cp' || sel.contains('ارتباط')) {
      return _gifts.where((g) => g.isCpGift || g.giftType == 5 || g.categoryId == 'cp' || (g.categoryId?.toLowerCase().contains('ارتباط') ?? false)).toList();
    }
    if (sel == 'normal' || sel == 'popular' || sel.contains('شائع') || sel.contains('عادي')) {
      return _gifts.where((g) => (g.giftType == 1 && !g.isLucky && !g.isCpGift) || g.categoryId == 'normal' || g.categoryId == 'popular' || (g.categoryId?.toLowerCase().contains('شائع') ?? false) || (g.categoryId?.toLowerCase().contains('عادي') ?? false)).toList();
    }
    if (sel == 'backpack' || sel.contains('حقيبة')) {
      return _gifts.where((g) => g.packageCount > 0 || g.giftType == 4 || g.categoryId == 'backpack' || (g.categoryId?.toLowerCase().contains('حقيبة') ?? false)).toList();
    }
    return _gifts.where((g) => g.categoryId == _selectedCategoryId).toList();
  }

  void _toggleSelectAll() {
    setState(() {
      if (_isAllSelected) {
        _isAllSelected = false;
        _selectedUserIds.clear();
      } else {
        _isAllSelected = true;
        _selectedUserIds.clear();
        _selectedUserIds.addAll(
          widget.targetUsers
              .map((u) => u['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty),
        );
      }
    });
  }

  void _toggleUser(String uid) {
    if (uid.isEmpty) return;
    setState(() {
      if (_isAllSelected) {
        _isAllSelected = false;
        _selectedUserIds.clear();
        _selectedUserIds.addAll(
          widget.targetUsers
              .map((u) => u['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty),
        );
        _selectedUserIds.remove(uid);
      } else {
        if (_selectedUserIds.contains(uid)) {
          _selectedUserIds.remove(uid);
        } else {
          _selectedUserIds.add(uid);
        }
        if (_selectedUserIds.length == widget.targetUsers.length && widget.targetUsers.isNotEmpty) {
          _isAllSelected = true;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dc = DynamicConfigService();
    final selectedGift = (_sel >= 0 && _sel < _gifts.length) ? _gifts[_sel] : null;
    final isLuckyActive = _selectedCategoryId == 'lucky' || (selectedGift != null && (selectedGift.isLucky || selectedGift.categoryId == 'lucky' || selectedGift.type == 3));

    return ListenableBuilder(
      listenable: dc,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLuckyActive)
              Container(
                height: 52,
                width: double.infinity,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/images/room_gift_lucky_introduce_bg.webp'),
                    fit: BoxFit.fill,
                  ),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: const Text(
                  'أرسل هدية الحظ واكسب مكافآت مضاعفة تصل إلى 500X!',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 2),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Container(
              height: 370,
              decoration: BoxDecoration(
                color: dc.giftPanelBgColor,
                image: dc.giftPanelBgImage.isNotEmpty
                    ? DecorationImage(
                        image: R.cachedImage(dc.giftPanelBgImage),
                        fit: BoxFit.cover,
                      )
                    : null,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Column(
                children: [
                  _buildHeader(dc),
                  Container(height: 0.5, color: const Color(0x1AFFFFFF)),
                  Expanded(child: _buildGrid(dc)),
                  _buildBottomOperate(dc),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(DynamicConfigService dc) {
    final users = widget.targetUsers;
    final allTabs = [
      const GiftCategory(id: 'all', name: 'الكل', sortOrder: -5),
      const GiftCategory(id: 'normal', name: 'شائع', sortOrder: -4),
      if (_gifts.any((g) => g.isVap || g.bigEffect || g.giftType == 2 || g.categoryId == 'luxury' || g.categoryId == 'vip'))
        const GiftCategory(id: 'luxury', name: '👑 فاخر', sortOrder: -3),
      if (_gifts.any((g) => g.isLucky || g.giftType == 3 || g.categoryId == 'lucky'))
        const GiftCategory(id: 'lucky', name: '🍀 الحظ', sortOrder: -2),
      if (_gifts.any((g) => g.isCpGift || g.giftType == 5 || g.categoryId == 'cp'))
        const GiftCategory(id: 'cp', name: '💍 الارتباط', sortOrder: -1),
      const GiftCategory(id: 'backpack', name: '🎒 الحقيبة', sortOrder: 0),
      ..._categories.where((c) {
        final id = c.id.toLowerCase();
        final name = c.name.toLowerCase();
        return !['all', 'normal', 'luxury', 'vip', 'lucky', 'cp', 'backpack'].contains(id) &&
               !name.contains('شائع') && !name.contains('فاخر') && !name.contains('حظ') && !name.contains('ارتباط') && !name.contains('حقيبة');
      }),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'إرسال إلى:',
                style: TextStyle(fontSize: 10, color: Colors.white70),
              ),
              const Spacer(),
              Text(
                'تم تحديد ${_selectedUserIds.length} من ${users.length}',
                style: const TextStyle(fontSize: 10, color: Color(0xFFFFD700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 58,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                GestureDetector(
                  onTap: _toggleSelectAll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      gradient: _isAllSelected
                          ? const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFDE880F)],
                            )
                          : null,
                      color: _isAllSelected ? null : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: _isAllSelected
                          ? Border.all(color: Colors.amberAccent, width: 1.5)
                          : Border.all(color: Colors.white12, width: 0.5),
                      boxShadow: _isAllSelected
                          ? [
                              BoxShadow(
                                color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                                blurRadius: 6,
                              )
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'الكل',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: _isAllSelected ? FontWeight.bold : FontWeight.normal,
                        color: _isAllSelected ? Colors.black87 : Colors.white70,
                      ),
                    ),
                  ),
                ),
                for (int idx = 0; idx < users.length; idx++)
                  _buildHeaderUserItem(users[idx], idx),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 28,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final cat in allTabs)
                  GestureDetector(
                    onTap: () => setState(() => _selectedCategoryId = cat.id),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: (_selectedCategoryId ?? 'all') == cat.id
                            ? dc.giftPanelTabColor
                            : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        cat.name,
                        style: TextStyle(
                          fontSize: 11,
                          color: (_selectedCategoryId ?? 'all') == cat.id
                              ? Colors.black87
                              : dc.giftPanelTabInactiveColor,
                          fontWeight: (_selectedCategoryId ?? 'all') == cat.id
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
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

  Widget _buildHeaderUserItem(Map<String, dynamic> u, int idx) {
    final uid = u['id']?.toString() ?? '';
    final selected = _selectedUserIds.contains(uid);

    return GestureDetector(
      onTap: () => _toggleUser(uid),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 38,
              height: 38,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Golden border glow when selected
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? const Color(0xFFFFD700) : Colors.white24,
                        width: selected ? 2.2 : 1.0,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                                blurRadius: 6,
                                spreadRadius: 1,
                              )
                            ]
                          : null,
                    ),
                  ),
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: (u['photoUrl'] != null &&
                            u['photoUrl'].toString().isNotEmpty)
                        ? R.cachedImage(u['photoUrl'].toString())
                        : null,
                    child: (u['photoUrl'] == null ||
                            u['photoUrl'].toString().isEmpty)
                        ? const Icon(Icons.person, size: 14, color: Colors.white70)
                        : null,
                  ),
                  if (selected)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 15,
                        height: 15,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFF9900)],
                          ),
                          boxShadow: [
                            BoxShadow(color: Colors.black45, blurRadius: 2),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.check, size: 10, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: 38,
              child: Text(
                u['name']?.toString() ?? '',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? const Color(0xFFFFD700) : Colors.white54,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(DynamicConfigService dc) {
    if (_selectedCategoryId == 'backpack') {
      return _buildBackpackGrid();
    }
    final items = _filteredGifts;
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد هدايا متاحة',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GridView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
          childAspectRatio: 80 / 93,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _buildGiftItem(i, dc),
      ),
    );
  }

  Widget _buildBackpackGrid() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.backpack_outlined, size: 48, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 8),
          Text(
            'الحقيبة',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 4),
          Text(
            'لا توجد عناصر متاحة للإرسال حالياً في الحقيبة',
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }

  Widget _buildGiftItem(int i, DynamicConfigService dc) {
    final items = _filteredGifts;
    if (i >= items.length) return const SizedBox();
    final g = items[i];
    final sel = _sel >= 0 && _sel < _gifts.length && _gifts[_sel].id == g.id;

    return GestureDetector(
      onTap: () {
        final idx = _gifts.indexWhere((x) => x.id == g.id);
        setState(() => _sel = idx);
      },
      child: _buildGiftItemContent(g, sel, dc),
    );
  }

  Widget _buildGiftItemContent(gm.GiftModel g, bool sel, DynamicConfigService dc) {
    final hasCardBgImage = dc.giftPanelCardBgImage.isNotEmpty;
    return Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: hasCardBgImage ? null : dc.giftPanelCardBgColor,
          image: sel
              ? (hasCardBgImage
                  ? DecorationImage(
                      image: R.cachedImage(dc.giftPanelCardBgImage),
                      fit: BoxFit.fill,
                    )
                  : const DecorationImage(
                      image: AssetImage(R.roomGiftImgPre),
                      fit: BoxFit.fill,
                    ))
              : null,
          borderRadius: BorderRadius.circular(4),
          border: sel
              ? Border.all(color: dc.giftPanelCardSelectedBorderColor, width: 1.5)
              : (dc.giftPanelCardBorderColor != Colors.transparent ? Border.all(color: dc.giftPanelCardBorderColor, width: 1) : null),
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: g.iconAsset.isNotEmpty
                          ? R.loadImage(
                              g.iconAsset,
                              width: 60,
                              height: 60,
                              fit: BoxFit.contain,
                            )
                          : const Icon(
                              Icons.card_giftcard,
                              color: Color(0xFFFFD700),
                              size: 34,
                            ),
                    ),
                  ),
                  if (g.isLucky)
                    Positioned(
                      top: 4,
                      right: 0,
                      child: dc.giftPanelLuckyBadgeImage.isNotEmpty
                          ? R.loadImage(dc.giftPanelLuckyBadgeImage, width: 30, height: 14)
                          : R.image(
                              R.roomGiftLuckyLabelIc,
                              width: 30,
                              height: 14,
                            ),
                    ),
                  if (g.isStar)
                    Positioned(
                      top: 4,
                      left: 0,
                      child: dc.giftPanelStarBadgeImage.isNotEmpty
                          ? R.loadImage(dc.giftPanelStarBadgeImage, width: 22, height: 14)
                          : R.image(
                              R.roomGiftStarLabelIc,
                              width: 22,
                              height: 14,
                            ),
                    ),
                  if (g.durationBadge.isNotEmpty)
                    Positioned(
                      top: 4,
                      left: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: dc.giftPanelDurationBadgeBg,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: dc.giftPanelDurationBadgeBg.withValues(alpha: 0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.favorite, size: 8, color: Colors.white),
                            const SizedBox(width: 2),
                            Text(
                              g.durationBadge,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (g.isMusic)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: R.image(
                        R.roomGiftMusicLabelIc,
                        width: 14,
                        height: 14,
                      ),
                    ),
                  if (g.packageCount > 0)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        constraints: const BoxConstraints(minWidth: 24),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE82323),
                          borderRadius: BorderRadius.circular(44),
                        ),
                        child: Text(
                          '${g.packageCount}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Text(
              g.name,
              style: TextStyle(
                fontSize: 10,
                color: dc.giftPanelTextColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  R.image(
                    R.commonGoldIc2,
                    width: 12,
                    height: 12,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    R.formatCoins(g.value),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFD3A350),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }

  Future<void> _sendGift() async {
    if (_sending) return;
    if (_sel < 0 || _sel >= _gifts.length) return;

    final gift = _gifts[_sel];
    final selectedTargets = widget.targetUsers
        .where((u) => _selectedUserIds.contains(u['id']?.toString()))
        .toList();

    if (selectedTargets.isEmpty) {
      if (!mounted) return;
      setState(() {
        _errorMsg = 'لم يتم تحديد أي مستلم';
      });
      final d1 = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _errorMsg = null);
      });
      _pendingDelays.add(d1);
      return;
    }

    final totalCost = gift.value * widget.selectedCount * selectedTargets.length;
    final availableCoins = Provider.of<UserProvider>(context, listen: false).currentUser?.coins ?? widget.coins;

    if (availableCoins < totalCost) {
      if (!mounted) return;
      _showInsufficientCoinsDialog(context, totalCost: totalCost, currentCoins: availableCoins);
      return;
    }

    setState(() => _sending = true);

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentUser = userProvider.currentUser;

    // خصم العملات لحظياً في الذاكرة لتحديث الواجهة فوراً (0ms latency)
    userProvider.deductCoinsLocally(totalCost);

    // TODO: Critical fix - Use strict boolean and type check for lucky gifts
    // Only use sendLuckyGift if gift.isLucky == true OR gift.type == 3
    final isLuckyGift = gift.isLucky || gift.type == 3;

    if (widget.onSend != null) {
      widget.onSend!();
    }
    final anim = gift.animationAsset;
    final defImg = gift.defaultImage;
    final effectiveAsset = (anim != null && anim.isNotEmpty) ? anim : gift.iconAsset;
    widget.onSendGift?.call(effectiveAsset);
    widget.onSendGiftExtended?.call({
      'gift': gift,
      'animationAsset': effectiveAsset,
      'nameKey': gift.nameKey,
      'photoKey': gift.photoKey,
      'defaultImage': (defImg != null && defImg.isNotEmpty) ? defImg : gift.iconAsset,
      'senderName': currentUser?.name ?? '',
      'senderPhotoUrl': currentUser?.photoUrl ?? '',
      'receiverId': selectedTargets.length == 1 ? selectedTargets.first['id']?.toString() : null,
      'receiverIds': selectedTargets.map((t) => t['id']?.toString()).whereType<String>().toList(),
      'selectedTargets': selectedTargets,
      'giftValue': gift.value,
      'giftCount': widget.selectedCount,
      'categoryId': gift.categoryId,
      'isLucky': isLuckyGift,
    });

    _startComboTimer();
    setState(() => _sending = false);

    // إرسال عبر الشبكة في الخلفية دون حظر الواجهة إطلاقاً (Background Future)
    if (widget.roomId.isNotEmpty && currentUser != null) {
      unawaited(Future(() async {
        final fb = SupabaseService();
        final results = await Future.wait(selectedTargets.map((r) async {
          final receiverId = r['id']?.toString() ?? '';
          final receiverName = r['name']?.toString() ?? '';
          bool ok;
          if (isLuckyGift) {
            final cover = gift.defaultImage ?? gift.iconAsset;
            final res = await fb.sendLuckyGift(
              roomId: widget.roomId,
              giftId: gift.id,
              giftName: gift.name,
              giftNameAr: gift.name,
              giftIconUrl: gift.iconAsset,
              giftCoverUrl: cover,
              giftBgUrl: cover,
              svgaAnimUrl: gift.animationAsset,
              senderId: currentUser.uid,
              senderName: currentUser.name,
              senderPhotoUrl: currentUser.photoUrl,
              receiverId: receiverId,
              receiverName: receiverName,
              value: gift.value,
              count: widget.selectedCount,
              comboId: 'combo_${DateTime.now().millisecondsSinceEpoch}',
              comboCount: widget.selectedCount,
            );
            ok = res != null;
            if (res != null && res['wonCoins'] != null) {
              final won = (res['wonCoins'] as num).toInt();
              if (won > 0) {
                userProvider.addCoinsLocally(won);
              }
            }
          } else {
            final cover = gift.defaultImage ?? gift.iconAsset;
            ok = await fb.sendGift(
              roomId: widget.roomId,
              giftId: gift.id,
              giftName: gift.name,
              animationAsset: gift.animationAsset,
              defaultImage: cover,
              senderId: currentUser.uid,
              senderName: currentUser.name,
              senderPhotoUrl: currentUser.photoUrl,
              receiverId: receiverId,
              receiverName: receiverName,
              value: gift.value,
              count: widget.selectedCount,
            );
          }
          if (ok && gift.isCpGift) {
            await CpService.sendGiftAndLink(
              giftId: gift.id,
              senderId: currentUser.uid,
              senderName: currentUser.name,
              receiverId: receiverId,
              receiverName: receiverName,
              giftName: gift.name,
              giftValue: gift.value,
            );
          }
          return ok;
        }));

        final allOk = results.every((ok) => ok);
        if (!allOk && mounted) {
          setState(() {
            _errorMsg = 'فشل إرسال الهدية — تأكد من رصيد العملات وحاول مجدداً';
          });
          final d3 = Timer(const Duration(seconds: 3), () {
            if (mounted) setState(() => _errorMsg = null);
          });
          _pendingDelays.add(d3);
        }
      }));
    }
  }

  void _startComboTimer() {
    _comboTimer?.cancel();
    _comboMultiplier = (_comboSeconds > 0) ? _comboMultiplier + 1 : 1;
    _comboSeconds = 10;
    _comboRemainingMs = 10000;
    setState(() {});

    _comboTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      _comboRemainingMs -= 100;
      if (_comboRemainingMs <= 0) {
        t.cancel();
        setState(() {
          _comboSeconds = 0;
          _comboMultiplier = 0;
          _comboRemainingMs = 0;
        });
      } else {
        setState(() {
          _comboSeconds = (_comboRemainingMs / 1000).ceil();
        });
      }
    });
  }

  void _showInsufficientCoinsDialog(BuildContext context, {int totalCost = 0, int currentCoins = 0}) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 36),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 25, 20, 25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // FrameLayout matching dialog_coin_recharge_tip.xml: shadow_coins + dialog_coins
              SizedBox(
                height: 125,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 45,
                      child: Image.asset(
                        'assets/mipmap-xxhdpi/shadow_coins.png',
                        width: 120,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                    Image.asset(
                      'assets/mipmap-xxhdpi/dialog_coins.png',
                      width: 100,
                      height: 100,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.monetization_on_rounded,
                        size: 80,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // tvContent (18sp #333333 matching dialog_coin_recharge_tip.xml)
              Text(
                isAr
                    ? 'رصيد العملات غير كافٍ،\nهل ترغب في الشحن للحصول على المزيد؟'
                    : 'Insufficient coins balance.\nWould you like to recharge for more?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                  height: 1.35,
                ),
              ),

              if (totalCost > 0) ...[
                const SizedBox(height: 8),
                Text(
                  isAr
                      ? 'المطلوب: ${R.formatCoins(totalCost)} كوينز  |  لديك: ${R.formatCoins(currentCoins)} كوينز'
                      : 'Required: ${R.formatCoins(totalCost)} coins  |  Available: ${R.formatCoins(currentCoins)} coins',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF888888),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action buttons: btnCancel + btnConfirm
              Row(
                children: [
                  // btnCancel: #f5f5f5, radius 20, text #555555 "إلغاء"
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF5F5F5),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: Text(
                          isAr ? 'إلغاء' : 'Cancel',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF555555),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // btnConfirm: gradient #00deff -> #14fab1, radius 20, text white "شحن الآن"
                  Expanded(
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00DEFF), Color(0xFF14FAB1)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF14FAB1).withOpacity(0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            Navigator.pop(dialogCtx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const WalletMainScreen(),
                              ),
                            );
                          },
                          child: Center(
                            child: Text(
                              isAr ? 'شحن الآن' : 'Recharge Now',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomOperate(DynamicConfigService dc) {
    final gift = _sel >= 0 && _sel < _gifts.length ? _gifts[_sel] : null;
    final selectedTargetsCount = widget.targetUsers
        .where((u) => _selectedUserIds.contains(u['id']?.toString()))
        .length;
    final totalCost = gift != null ? gift.value * widget.selectedCount * (selectedTargetsCount > 0 ? selectedTargetsCount : 1) : 0;
    final liveCoins = Provider.of<UserProvider>(context).currentUser?.coins ?? widget.coins;
    final canAfford = liveCoins >= totalCost && totalCost > 0;
    final double comboProgress = _comboRemainingMs > 0 ? (_comboRemainingMs / 10000.0).clamp(0.0, 1.0) : 0.0;

    return Container(
      height: 52,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_errorMsg != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                _errorMsg!,
                style: const TextStyle(fontSize: 10, color: Colors.redAccent),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left: Coins Display (tv_coins from layout_gift_panel_bottom_operate.xml)
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const WalletMainScreen(),
                    ),
                  );
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      R.image(
                        R.commonGoldIc1,
                        width: 18,
                        height: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        R.formatCoins(liveCoins),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: canAfford ? dc.giftPanelCoinsTextColor : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right, size: 14, color: Colors.white54),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Right: Combo Button or Count + Send Buttons
              if (_comboSeconds > 0)
                // Authentic Combo Button matching room_gift_combo_button.xml
                GestureDetector(
                  onTap: () {
                    if (!canAfford) {
                      _showInsufficientCoinsDialog(context, totalCost: totalCost, currentCoins: liveCoins);
                      return;
                    }
                    _sendGift();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 106,
                    height: 50,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Top timer row: clock icon (iv_time) + RoundedProgressBar
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Row(
                            children: [
                              Image.asset(
                                'assets/images/room_gift_combo_time_ic.webp',
                                width: 18,
                                height: 18,
                                errorBuilder: (_, __, ___) => const Icon(Icons.access_time, size: 14, color: Color(0xFFFFFED3)),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFAE62),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(color: const Color(0xFFFFFED3), width: 1.5),
                                  ),
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: comboProgress,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF3FD902),
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Bottom combo button (btn_combo 106x34dp)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              image: DecorationImage(
                                image: AssetImage(
                                  _sending
                                      ? 'assets/images/room_gift_combo_lucky_pre.webp'
                                      : 'assets/images/room_gift_combo_lucky_nor.webp',
                                ),
                                fit: BoxFit.fill,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (gift != null) ...[
                                  R.loadImage(
                                    gift.iconAsset.isNotEmpty ? gift.iconAsset : (gift.defaultImage ?? ''),
                                    width: 20,
                                    height: 20,
                                    fit: BoxFit.contain,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  'x$_comboMultiplier',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                        color: Color(0xFFBC0C1A),
                                        offset: Offset(1, 1),
                                        blurRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                // Normal Count + Send (tv_gift_num + tv_gift_send from layout_gift_panel_bottom_operate.xml)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Count dropdown (tv_gift_num 72x30dp)
                    GestureDetector(
                      onTap: widget.onCountTap,
                      child: Container(
                        width: 72,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: dc.giftPanelCountBtnBgColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            bottomLeft: Radius.circular(8),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${widget.selectedCount}',
                              style: TextStyle(
                                fontSize: 11,
                                color: dc.giftPanelCountBtnTextColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            R.image(
                              R.roomGiftNumOpenIc,
                              width: 10,
                              height: 10,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Send button (tv_gift_send 72x30dp)
                    GestureDetector(
                      onTap: () {
                        if (!canAfford) {
                          _showInsufficientCoinsDialog(context, totalCost: totalCost, currentCoins: liveCoins);
                          return;
                        }
                        _sendGift();
                      },
                      child: Container(
                        width: 72,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: canAfford
                              ? LinearGradient(
                                  colors: [dc.giftPanelSendBtnGradientStart, dc.giftPanelSendBtnGradientEnd],
                                )
                              : const LinearGradient(
                                  colors: [Color(0xFF666666), Color(0xFF444444)],
                                ),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                        child: _sending
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'إرسال',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: dc.giftPanelSendBtnTextColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class GiftSvgaOverlay extends StatelessWidget {
  final VoidCallback? onFinished;
  final String? animationAsset;
  final Map<String, String>? textReplacement;
  final Map<String, String>? imageReplacement;
  final String? defaultImageUrl;
  final bool showBackground;
  const GiftSvgaOverlay({
    super.key,
    this.onFinished,
    this.animationAsset,
    this.textReplacement,
    this.imageReplacement,
    this.defaultImageUrl,
    this.showBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final aa = animationAsset;

    final isImg = aa != null && isImageType(aa);
    final displayImg = isImg ? aa : (defaultImageUrl != null && defaultImageUrl!.isNotEmpty ? defaultImageUrl : null);

    return SizedBox.expand(
      child: IgnorePointer(
        child: Container(
          color: showBackground ? Colors.black.withValues(alpha: 0.25) : Colors.transparent,
          child: Center(
            child: aa != null && aa.isNotEmpty && !isImg
                ? isVideoType(aa)
                    ? VapPlayer(
                        url: aa,
                        width: screenSize.width,
                        height: screenSize.height,
                        loops: false,
                        onFinished: onFinished,
                        fit: BoxFit.cover,
                        textReplacement: textReplacement,
                        imageReplacement: imageReplacement,
                        defaultImageUrl: defaultImageUrl,
                      )
                    // ── ✅ Android: Native SVGAImageView — نفس سرعة الأصلي ──
                    // بدون textReplacement/imageReplacement → Native مباشر
                    // مع textReplacement/imageReplacement → Flutter (يدعم الحقن الديناميكي)
                    : (Platform.isAndroid &&
                              textReplacement == null &&
                              imageReplacement == null &&
                              aa.startsWith('http'))
                        ? SvgaNativePlayer(
                            url: aa,
                            width: screenSize.width,
                            height: screenSize.height,
                            loops: false,
                            onReady: null,
                            onError: onFinished,
                          )
                        : SvgaPlayer(
                        assetPath: aa,
                        width: screenSize.width,
                        height: screenSize.height,
                        loops: false,
                        fit: BoxFit.contain,
                        onFinished: onFinished,
                        textReplacement: textReplacement,
                        imageReplacement: imageReplacement,
                        defaultImageUrl: defaultImageUrl,
                      )
                : displayImg != null
                    ? _ImageGiftOverlay(
                        imageUrl: displayImg,
                        onFinished: onFinished,
                      )
                    : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _ImageGiftOverlay extends StatefulWidget {
  final String imageUrl;
  final VoidCallback? onFinished;

  const _ImageGiftOverlay({
    required this.imageUrl,
    this.onFinished,
  });

  @override
  State<_ImageGiftOverlay> createState() => _ImageGiftOverlayState();
}

class _ImageGiftOverlayState extends State<_ImageGiftOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.2, end: 1.2).chain(CurveTween(curve: Curves.easeOutBack)), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 15),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeInBack)), weight: 20),
    ]).animate(_ctrl);

    _fade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 65),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(_ctrl);

    _ctrl.forward().then((_) {
      if (mounted) widget.onFinished?.call();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final giftSize = (screenSize.width * 0.5).clamp(160.0, 340.0);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Opacity(
          opacity: _fade.value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: _scale.value,
            child: Container(
              width: giftSize,
              height: giftSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.4),
                    blurRadius: 30,
                    spreadRadius: 6,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image(
                image: R.cachedImage(widget.imageUrl),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.card_giftcard, size: 96, color: Colors.amber),
              ),
            ),
          ),
        );
      },
    );
  }
}

class GiftBannerOverlay extends StatelessWidget {
  final VoidCallback? onFinished;
  final String? animationAsset;
  final String? senderPhotoUrl;
  final String? receiverPhotoUrl;
  final String? giftImageUrl;
  final int giftCount;
  final String userRKey;
  final String userLKey;
  final String numberKey;
  final String giftKey;

  const GiftBannerOverlay({
    super.key,
    this.onFinished,
    this.animationAsset,
    this.senderPhotoUrl,
    this.receiverPhotoUrl,
    this.giftImageUrl,
    this.giftCount = 1,
    this.userRKey = 'user_r',
    this.userLKey = 'user_l',
    this.numberKey = 'number',
    this.giftKey = 'gift',
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final aa = animationAsset;
    if (aa == null || aa.isEmpty) return const SizedBox.shrink();

    final imageReplacement = <String, String>{};
    if (senderPhotoUrl != null && senderPhotoUrl!.isNotEmpty) {
      imageReplacement[userRKey] = senderPhotoUrl!;
    }
    if (receiverPhotoUrl != null && receiverPhotoUrl!.isNotEmpty) {
      imageReplacement[userLKey] = receiverPhotoUrl!;
    }
    if (giftImageUrl != null && giftImageUrl!.isNotEmpty) {
      imageReplacement[giftKey] = giftImageUrl!;
    }

    final textReplacement = <String, String>{};
    textReplacement[numberKey] = '$giftCount';

    final bannerHeight = 110.0;
    final topPadding = MediaQuery.of(context).padding.top;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onFinished,
        child: SizedBox(
          height: topPadding + bannerHeight,
          child: Stack(
            children: [
              if (isVideoType(aa))
                VapPlayer(
                  url: aa,
                  width: screenSize.width,
                  height: topPadding + bannerHeight,
                  loops: false,
                  onFinished: onFinished,
                  fit: BoxFit.contain,
                )
              else
                SvgaPlayer(
                  assetPath: aa,
                  width: screenSize.width,
                  height: topPadding + bannerHeight,
                  loops: false,
                  fit: BoxFit.contain,
                  onFinished: onFinished,
                  imageReplacement: imageReplacement.isNotEmpty
                      ? imageReplacement
                      : null,
                  textReplacement: textReplacement.isNotEmpty
                      ? textReplacement
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}