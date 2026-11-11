import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/r.dart';
import '../../../features/cp/cp_service.dart';
import '../../../models/gift_model.dart' as gm;
import '../../../models/gift_category_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/supabase_service.dart';
import '../../../services/supabase_data_service.dart';
import '../../../services/media_prefetch_service.dart';
import '../../../services/dynamic_config_service.dart';
import '../../wallet/wallet_main_screen.dart';
import 'svga_player.dart';
import 'vap_player.dart';
import 'package:zero/core/dtext.dart';
import '../../../widgets/special_name_text.dart';

class GiftPanel extends StatefulWidget {
  final int selectedCount;
  final num coins;
  final List<Map<String, dynamic>> targetUsers;
  final List<Map<String, dynamic>> seatUsers;
  final List<Map<String, dynamic>> allRoomUsers;
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
    this.seatUsers = const [],
    this.allRoomUsers = const [],
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
  List<gm.GiftModel> _gifts = [];
  List<GiftCategory> _categories = [];
  String? _selectedCategoryId;
  StreamSubscription? _giftSub;
  StreamSubscription? _catSub;
  Timer? _comboTimer;
  int _comboSeconds = 0;
  int _comboMultiplier = 0;
  int _comboRemainingMs = 0;
  late final ScrollController _tabScrollController = ScrollController();
  final List<Timer> _pendingDelays = [];

  @override
  void initState() {
    super.initState();
    _initSelection();
    _loadGifts();
  }

  List<Map<String, dynamic>> get _allAvailableUsers {
    final map = <String, Map<String, dynamic>>{};
    for (final u in widget.seatUsers) {
      final id = u['id']?.toString() ?? '';
      if (id.isNotEmpty) map[id] = u;
    }
    for (final u in widget.targetUsers) {
      final id = u['id']?.toString() ?? '';
      if (id.isNotEmpty && !map.containsKey(id)) map[id] = u;
    }
    for (final u in widget.allRoomUsers) {
      final id = u['id']?.toString() ?? '';
      if (id.isNotEmpty && !map.containsKey(id)) map[id] = u;
    }
    return map.values.toList();
  }

  List<Map<String, dynamic>> get _effectiveSeatUsers {
    if (widget.seatUsers.isNotEmpty) return widget.seatUsers;
    return widget.targetUsers;
  }

  List<Map<String, dynamic>> get _effectiveRoomUsers {
    if (widget.allRoomUsers.isNotEmpty) return widget.allRoomUsers;
    return _allAvailableUsers;
  }

  bool _manuallySelectedAll = false;

  bool get _isAllSelected {
    final targets = _effectiveSeatUsers.isNotEmpty ? _effectiveSeatUsers : _effectiveRoomUsers;
    if (targets.isEmpty) return false;
    final targetIds = targets.map((u) => u['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
    if (targetIds.isEmpty) return false;
    if (!_manuallySelectedAll && targetIds.length <= 1) return false;
    return targetIds.every((id) => _selectedUserIds.contains(id));
  }

  void _toggleSelectAll() {
    final targets = _effectiveSeatUsers.isNotEmpty ? _effectiveSeatUsers : _effectiveRoomUsers;
    final targetIds = targets.map((u) => u['id']?.toString() ?? '').where((id) => id.isNotEmpty).toList();
    if (targetIds.isEmpty) return;

    setState(() {
      if (_isAllSelected) {
        _manuallySelectedAll = false;
        _selectedUserIds.clear();
        if (targetIds.isNotEmpty) {
          _selectedUserIds.add(targetIds.first);
        }
      } else {
        _manuallySelectedAll = true;
        _selectedUserIds.clear();
        _selectedUserIds.addAll(targetIds);
      }
    });
  }

  void _initSelection() {
    _selectedUserIds.clear();
    _manuallySelectedAll = false;
    if (widget.receiverId != null && widget.receiverId!.isNotEmpty) {
      _selectedUserIds.add(widget.receiverId!);
    } else {
      final list = widget.seatUsers.isNotEmpty
          ? widget.seatUsers
          : (widget.targetUsers.isNotEmpty ? widget.targetUsers : widget.allRoomUsers);
      if (list.isNotEmpty) {
        final firstId = list.first['id']?.toString() ?? '';
        if (firstId.isNotEmpty) {
          _selectedUserIds.add(firstId);
        }
      }
    }
  }

  @override
  void dispose() {
    for (final t in _pendingDelays) {
      t.cancel();
    }
    _tabScrollController.dispose();
    _comboTimer?.cancel();
    _giftSub?.cancel();
    _catSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(GiftPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.receiverId != oldWidget.receiverId ||
        (_selectedUserIds.isEmpty && widget.targetUsers.isNotEmpty) ||
        widget.targetUsers.length != oldWidget.targetUsers.length) {
      _initSelection();
    }
  }

  void _loadGifts() {
    final fb = SupabaseService();
    // Instant initial load from Supabase directly
    SupabaseDataService().getGiftCategories().then((cats) {
      if (mounted) {
        final filteredCats = cats.where((c) => c.id.toLowerCase() != 'all').toList();
        setState(() {
          _categories = filteredCats;
          if (_selectedCategoryId == null || _selectedCategoryId == 'all') {
            _selectedCategoryId = filteredCats.isNotEmpty ? filteredCats.first.id : null;
          }
        });
      }
    }).catchError((_) {});
    SupabaseDataService().getGifts().then((gifts) {
      if (mounted && gifts.isNotEmpty) {
        MediaPrefetchService().prefetchGifts(gifts);
        setState(() {
          _gifts = gifts;
          if (_sel < 0 && _gifts.isNotEmpty) {
            _sel = 0;
          }
        });
      }
    }).catchError((_) {});

    _catSub = fb.giftCategoriesStream().listen((cats) {
      if (mounted) {
        final filteredCats = cats.where((c) => c.id.toLowerCase() != 'all').toList();
        setState(() {
          _categories = filteredCats;
          if (_selectedCategoryId == null || _selectedCategoryId == 'all') {
            _selectedCategoryId = filteredCats.isNotEmpty ? filteredCats.first.id : null;
          }
        });
      }
    });
    _giftSub = fb.giftsStream().listen((gifts) {
      MediaPrefetchService().prefetchGifts(gifts);
      if (mounted) {
        setState(() {
          _gifts = gifts;
          if (_sel < 0 && _gifts.isNotEmpty) {
            _sel = 0;
          } else if (_sel >= _gifts.length) {
            _sel = _gifts.isNotEmpty ? 0 : -1;
          }
        });
      }
    });
  }

  List<gm.GiftModel> _getGiftsForCategory(String? categoryId) {
    if (categoryId == null ||
        categoryId.isEmpty ||
        categoryId.toLowerCase() == 'all') {
      return _gifts;
    }
    final sel = categoryId.toLowerCase();
    return _gifts
        .where((g) => (g.categoryId ?? '').toLowerCase() == sel)
        .toList();
  }

  List<gm.GiftModel> get _filteredGifts => _getGiftsForCategory(_selectedCategoryId);


  void _toggleUser(String uid) {
    if (uid.isEmpty) return;
    setState(() {
      if (_selectedUserIds.contains(uid)) {
        _selectedUserIds.remove(uid);
        _manuallySelectedAll = false;
      } else {
        _selectedUserIds.add(uid);
        final targets = _effectiveSeatUsers.isNotEmpty ? _effectiveSeatUsers : _effectiveRoomUsers;
        if (targets.isNotEmpty && _selectedUserIds.length >= targets.length) {
          _manuallySelectedAll = true;
        }
      }
    });
  }

  List<GiftCategory> _getAllTabs(bool isAr) {
    final tabs = _categories
        .where((c) => c.id.toLowerCase() != 'all')
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return tabs;
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.maybeLocaleOf(context)?.languageCode != 'en';
    final dc = DynamicConfigService();
    final allTabs = _getAllTabs(isAr);
    if (allTabs.isEmpty) {
      _selectedCategoryId = null;
    } else if (_selectedCategoryId == null ||
        _selectedCategoryId == 'all' ||
        !allTabs.any((c) => c.id == _selectedCategoryId)) {
      _selectedCategoryId = allTabs.first.id;
    }
    // Auto-select first gift if none selected
    final filtered = _filteredGifts;
    if ((_sel < 0 || _sel >= _gifts.length) && filtered.isNotEmpty) {
      final idx = _gifts.indexWhere((g) => g.id == filtered.first.id);
      if (idx >= 0) _sel = idx;
    }
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
                child: const DText(
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
              height: 450,
              decoration: BoxDecoration(
                color: dc.giftPanelBgColor.withOpacity(dc.giftPanelOpacity),
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
                  _buildHeader(dc, allTabs, isAr),
                  Container(height: 0.5, color: const Color(0x1AFFFFFF)),
                  Expanded(child: _buildGrid(dc, allTabs)),
                  _buildBottomOperate(dc),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAllSelectButton(DynamicConfigService dc, bool isAr) {
    final isSelected = _isAllSelected;
    final customImg = isSelected
        ? dc.giftPanelAllSelectedImage
        : dc.giftPanelAllUnselectedImage;
    final effectiveImg = customImg.isNotEmpty ? customImg : 'assets/images/ic_gift_select_all.png';

    return GestureDetector(
      onTap: _toggleSelectAll,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                image: DecorationImage(
                  image: R.cachedImage(effectiveImg),
                  fit: BoxFit.cover,
                ),
                border: Border.all(
                  color: isSelected ? const Color(0xFFFFD700) : Colors.white24,
                  width: isSelected ? 2.0 : 1.0,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                          blurRadius: 8,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: isSelected
                  ? Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0x55000000),
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        size: 20,
                        color: Color(0xFFFFD700),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: 44,
              child: DText(
                isAr ? 'الكل' : 'All',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? const Color(0xFFFFD700) : Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToTab(int index) {
    if (!_tabScrollController.hasClients) return;
    final targetOffset = (index * 75.0) - 100.0;
    _tabScrollController.animateTo(
      targetOffset.clamp(0.0, _tabScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Widget _buildHeader(DynamicConfigService dc, List<GiftCategory> allTabs, bool isAr) {
    final users = _allAvailableUsers.isNotEmpty ? _allAvailableUsers : widget.targetUsers;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DText(
                isAr ? 'إرسال إلى:' : 'Send to:',
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
              const Spacer(),
              DText(
                isAr
                    ? 'تم تحديد ${_selectedUserIds.length} من ${users.length}'
                    : 'Selected ${_selectedUserIds.length} of ${users.length}',
                style: const TextStyle(fontSize: 10, color: Color(0xFFFFD700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 58,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              children: [
                _buildAllSelectButton(dc, isAr),
                for (int idx = 0; idx < users.length; idx++)
                  _buildHeaderUserItem(users[idx], idx),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 28,
            child: ListView(
              controller: _tabScrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                for (int i = 0; i < allTabs.length; i++)
                  Builder(
                    builder: (context) {
                      final cat = allTabs[i];
                      final isSelected = _selectedCategoryId == cat.id;
                      return GestureDetector(
                        onTap: () => _selectCategory(allTabs, i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? dc.giftPanelTabColor
                                : Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: dc.giftPanelTabColor.withValues(alpha: 0.45),
                                      blurRadius: 10,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              fontSize: 11,
                              color: isSelected
                                  ? Colors.black87
                                  : dc.giftPanelTabInactiveColor,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            child: DText(cat.name),
                          ),
                        ),
                      );
                    },
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
              child: SpecialNameText(
                text: u['name']?.toString() ?? '',
                customId: u['customId']?.toString() ?? u['custom_id']?.toString(),
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

  /// مصدر واحد للحقيقة: الشريط والجريد يقرآن نفس `_selectedCategoryId`
  /// (بدون PageView حتى لا تعود التبويبة للشائع بسبب تعارض حالة الصفحة).
  void _selectCategory(List<GiftCategory> allTabs, int index) {
    if (index < 0 || index >= allTabs.length) return;
    final cat = allTabs[index];
    _scrollToTab(index);
    setState(() {
      _selectedCategoryId = cat.id;
      final filtered = _getGiftsForCategory(cat.id);
      if (filtered.isNotEmpty) {
        final idx = _gifts.indexWhere((g) => g.id == filtered.first.id);
        if (idx >= 0) _sel = idx;
      }
    });
  }

  Widget _buildGrid(DynamicConfigService dc, List<GiftCategory> allTabs) {
    if (allTabs.isEmpty) {
      return const Center(
        child: DText(
          'لا توجد تصنيفات',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    }
    final idx = allTabs.indexWhere((c) => c.id == _selectedCategoryId);
    final currentIdx = idx >= 0 ? idx : 0;
    final cat = allTabs[currentIdx];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() < 250) return;
        _selectCategory(allTabs, v < 0 ? currentIdx + 1 : currentIdx - 1);
      },
      child: _buildCategoryGrid(cat, dc),
    );
  }

  Widget _buildCategoryGrid(GiftCategory cat, DynamicConfigService dc) {
    if (cat.id.toLowerCase() == 'backpack' || cat.name.toLowerCase().contains('حقيبة')) {
      return KeyedSubtree(
        key: ValueKey('backpack_grid_${cat.id}'),
        child: _buildBackpackGrid(),
      );
    }
    final items = _getGiftsForCategory(cat.id);
    if (items.isEmpty) {
      return Center(
        key: ValueKey('empty_${cat.id}'),
        child: const DText(
          'لا توجد هدايا متاحة',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    }
    return Padding(
      key: ValueKey('cat_grid_${cat.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: GridView.builder(
        padding: const EdgeInsets.only(top: 6, bottom: 50),
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 82 / 96,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _buildGiftItemFromList(items, i, dc),
      ),
    );
  }

  Widget _buildGiftItemFromList(List<gm.GiftModel> items, int i, DynamicConfigService dc) {
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

  Widget _buildBackpackGrid() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.backpack_outlined, size: 48, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 8),
          DText(
            'الحقيبة',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 4),
          DText(
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
    return AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
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
              : null,
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: AnimatedScale(
                        scale: sel ? 1.14 : 1.0,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.elasticOut,
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
                            DText(
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
                        child: DText(
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
            DText(
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
                  DText(
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
    final allUsers = _allAvailableUsers.isNotEmpty ? _allAvailableUsers : widget.targetUsers;
    final selectedTargets = allUsers
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
    final availableCoins = Provider.of<UserProvider>(context, listen: false).currentUser?.coins ?? 0;

    if (availableCoins < totalCost) {
      if (!mounted) return;
      _comboTimer?.cancel();
      setState(() {
        _comboSeconds = 0;
        _comboMultiplier = 0;
        _comboRemainingMs = 0;
      });
      _showInsufficientCoinsDialog(context, totalCost: totalCost, currentCoins: availableCoins);
      return;
    }

    setState(() => _sending = true);
    widget.onSend?.call();

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentUser = userProvider.currentUser;

    // TODO: Critical fix - Use strict boolean and type check for lucky gifts
    // Only use sendLuckyGift if gift.isLucky == true OR gift.type == 3
    final isLuckyGift = gift.isLucky || gift.type == 3;
    final fb = SupabaseService();
    final stepCount = widget.selectedCount > 0 ? widget.selectedCount : 1;

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
              count: stepCount,
              comboId: 'combo_${DateTime.now().millisecondsSinceEpoch}',
              comboCount: stepCount,
            );
            ok = res != null;
            if (res != null && mounted) {
              final newBal = (res['newBalance'] as num?)?.toDouble();
              if (newBal != null) {
                Provider.of<UserProvider>(context, listen: false).updateCoinsImmediately(newBal);
              }
            }
          } else {
            final cover = gift.defaultImage ?? gift.iconAsset;
            // خصم فوري من الرصيد المحلي حتى تنقص الكوينز لحظياً (مطابق لهدايا الحظ)
            userProvider.deductCoinsLocally(gift.value * widget.selectedCount);
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
            if (!ok) {
              // فشل الإرسال: أعِد مزامنة الرصيد من الخادم بدل إبقاء الخصم الوهمي
              unawaited(userProvider.reloadUser());
            }
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
    final step = widget.selectedCount > 0 ? widget.selectedCount : 1;
    _comboMultiplier = (_comboSeconds > 0) ? _comboMultiplier + step : step;
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

  void _showInsufficientCoinsDialog(BuildContext context, {int totalCost = 0, num currentCoins = 0}) {
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
              DText(
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
                DText(
                  isAr
                      ? 'المطلوب: ${R.formatCoins(totalCost)} كوينز  |  لديك: ${R.formatCoinsFraction(currentCoins)} كوينز'
                      : 'Required: ${R.formatCoins(totalCost)} coins  |  Available: ${R.formatCoinsFraction(currentCoins)} coins',
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
                        child: DText(
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
                            child: DText(
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
    final selectedTargetsCount = _selectedUserIds.length;
    final totalCost = gift != null ? gift.value * widget.selectedCount * (selectedTargetsCount > 0 ? selectedTargetsCount : 1) : 0;
    final currUser = Provider.of<UserProvider>(context).currentUser;
    final liveCoins = currUser != null ? currUser.coins : widget.coins;
    final canAfford = liveCoins >= totalCost && totalCost > 0;

    return Container(
      height: 52,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_errorMsg != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: DText(
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
                      DText(
                        R.formatCoinsFraction(liveCoins),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right, size: 14, color: Colors.white54),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Right: Count + Send (single combo button lives on the room screen)
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
                          color: dc.giftPanelCountBtnImage.isEmpty
                              ? dc.giftPanelCountBtnBgColor
                              : null,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            bottomLeft: Radius.circular(8),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            bottomLeft: Radius.circular(8),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (dc.giftPanelCountBtnImage.isNotEmpty)
                                Image(
                                  image: R.cachedImage(dc.giftPanelCountBtnImage),
                                  fit: BoxFit.fill,
                                )
                              else
                                Image.asset(
                                  R.checkinDialogConfirmBigBtn,
                                  fit: BoxFit.fill,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
                              Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    DText(
                                      '${widget.selectedCount}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: dc.giftPanelCountBtnImage
                                                .isNotEmpty
                                            ? dc.giftPanelCountBtnTextColor
                                            : Colors.white,
                                        fontWeight: FontWeight.bold,
                                        shadows: const [
                                          Shadow(
                                            color: Colors.black54,
                                            offset: Offset(1, 1),
                                            blurRadius: 2,
                                          ),
                                        ],
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
                            ],
                          ),
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
                          gradient: dc.giftPanelSendBtnImage.isEmpty
                              ? (canAfford
                                  ? LinearGradient(
                                      colors: [dc.giftPanelSendBtnGradientStart, dc.giftPanelSendBtnGradientEnd],
                                    )
                                  : const LinearGradient(
                                      colors: [Color(0xFF666666), Color(0xFF444444)],
                                    ))
                              : null,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (dc.giftPanelSendBtnImage.isNotEmpty)
                                Image(
                                  image: R.cachedImage(dc.giftPanelSendBtnImage),
                                  fit: BoxFit.fill,
                                )
                              else
                                Image.asset(
                                  R.checkinDialogConfirmBigBtn,
                                  fit: BoxFit.fill,
                                  errorBuilder: (_, __, ___) => Center(
                                    child: DText(
                                      'إرسال',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: dc.giftPanelSendBtnTextColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              if (_sending)
                                const Center(
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
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

class GiftBannerOverlay extends StatefulWidget {
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
  State<GiftBannerOverlay> createState() => _GiftBannerOverlayState();
}

class _GiftBannerOverlayState extends State<GiftBannerOverlay>
    with TickerProviderStateMixin {
  late AnimationController _enterController;
  late AnimationController _exitController;
  late Animation<Offset> _enterAnim;
  late Animation<Offset> _exitAnim;
  bool _isDismissing = false;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    // الدخول بسلاسة من أقصى اليمين
    _enterAnim = Tween<Offset>(
      begin: const Offset(1.5, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enterController, curve: Curves.easeOutCubic));

    // الخروج بالمرور الكامل نحو أقصى اليسار دون أي انقطاع
    _exitAnim = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-1.5, 0.0),
    ).animate(CurvedAnimation(parent: _exitController, curve: Curves.easeInCubic));

    _enterController.forward();

    // إغلاق البانر تلقائياً بعد 4.5 ثوانٍ مع خروج سلس لأقصى اليسار
    _autoDismissTimer = Timer(const Duration(milliseconds: 4500), () {
      _dismiss();
    });
  }

  void _dismiss() {
    if (_isDismissing || !mounted) return;
    _isDismissing = true;
    _autoDismissTimer?.cancel();
    _exitController.forward().then((_) {
      if (mounted) {
        widget.onFinished?.call();
      }
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _enterController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final aa = widget.animationAsset;
    if (aa == null || aa.isEmpty) return const SizedBox.shrink();

    final imageReplacement = <String, String>{};
    if (widget.senderPhotoUrl != null && widget.senderPhotoUrl!.isNotEmpty) {
      imageReplacement[widget.userRKey] = widget.senderPhotoUrl!;
    }
    if (widget.receiverPhotoUrl != null && widget.receiverPhotoUrl!.isNotEmpty) {
      imageReplacement[widget.userLKey] = widget.receiverPhotoUrl!;
    }
    if (widget.giftImageUrl != null && widget.giftImageUrl!.isNotEmpty) {
      imageReplacement[widget.giftKey] = widget.giftImageUrl!;
    }

    final textReplacement = <String, String>{};
    textReplacement[widget.numberKey] = '${widget.giftCount}';

    final bannerHeight = 110.0;
    final topPadding = MediaQuery.of(context).padding.top;

    return RepaintBoundary(
      child: SlideTransition(
        position: _exitAnim,
        child: SlideTransition(
          position: _enterAnim,
          child: GestureDetector(
            onTap: _dismiss,
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
                      onFinished: _dismiss,
                      fit: BoxFit.contain,
                    )
                  else
                    SvgaPlayer(
                      assetPath: aa,
                      width: screenSize.width,
                      height: topPadding + bannerHeight,
                      loops: false,
                      fit: BoxFit.contain,
                      onFinished: _dismiss,
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
        ),
      ),
    );
  }
}