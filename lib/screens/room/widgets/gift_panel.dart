import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:provider/provider.dart';
import '../../../config/r.dart';
import '../../../features/cp/cp_service.dart';
import '../../../models/gift_model.dart' as gm;
import '../../../models/gift_category_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/supabase_service.dart';
import '../../../services/supabase_data_service.dart';
import '../../../services/media_cache_service.dart';
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
  final String roomName;
  final VoidCallback? onSend;
  final ValueChanged<String?>? onSendGift;
  final ValueChanged<Map<String, dynamic>?>? onSendGiftExtended;
  final void Function(bool allOk)? onGiftSettled;
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
    this.roomName = '',
    this.onSend,
    this.onSendGift,
    this.onSendGiftExtended,
    this.onGiftSettled,
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
  bool _giftsLoaded = false;
  bool _giftsLoading = false;
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
  // ✅ انتقال احترافي بين التصنيفات بالسحب أفقيًا: الصندوق نفسه ثابت،
  //    ومحتوى الشبكة فقط هو الذي ينزلق (PageView) مع حفظ اختيار كل تصنيف.
  late final PageController _categoryPageController =
  PageController(viewportFraction: 1.0);
  // كل تصنيف له ScrollController مستقل للتمرير الرأسي حتى لا تتعارض
  // الصفحات المجاورة في PageView.
  final Map<String, ScrollController> _gridControllers = {};
  ScrollController _gridControllerFor(String catId) =>
      _gridControllers.putIfAbsent(catId, () => ScrollController());
  String? _pageSyncedCatId;
  // ✅ منع الرجوع للتصنيف السابق أثناء السحب/الأنيميشن:
  //   - _userDragging: المستخدم يسحب الـ PageView حالياً.
  //   - _programmaticPage: انتقلنا برمجياً (ضغطة تبويب) — نتجاهل
  //     onPageChanged للصفحات الوسيطة حتى لا يرجع الاختيار لما قبلها.
  bool _userDragging = false;
  bool _programmaticPage = false;
  // ✅ الصفحة التي انتقلنا إليها بضغطة تبويب — نتجاهل أي إشعار قديم
  //    من الـ PageView حتى تصل إليها فعلياً (أو تنتهي المهلة).
  int? _programmaticPageIndex;
  Timer? _programmaticPageTimer;
  // مفاتيح التبويبات حتى نمرّز إلى التبويب المضغوط فعلياً بدل إزاحة
  // ثابتة (index * 75 - 100) التي كانت تخطئ عند اختلاف عرض الأسماء.
  final List<GlobalKey> _tabKeys = [];
  GlobalKey _tabKey(int index) {
    while (_tabKeys.length <= index) {
      _tabKeys.add(GlobalKey());
    }
    return _tabKeys[index];
  }

  final Map<String, String> _selectedGiftByCat = {};
  final List<Timer> _pendingDelays = [];

  // ── التحميل عند الطلب: لكل هدية حالة تحميل مستقلة لملف الأنيميشن الثقيل ──
  //    لا تُحمَّل كل الهدايا معاً — فقط عند اختيار الهدية، وتُحفظ في الكاش
  //    فلا تُحمَّل مرة أخرى.
  final Map<String, double> _giftAssetProgress = {}; // url -> 0.0 .. 1.0
  final Set<String> _giftAssetReady = {}; // urls جاهزة في الكاش/تم تحميلها
  final Set<String> _giftAssetFailed = {}; // urls فشل تحميلها
  final Map<String, Future<void>> _giftAssetDownloads = {};
  String? _lastReadyCheckGiftId;

  @override
  void initState() {
    super.initState();
    _initSelection();
    _loadGifts();
  }

  List<Map<String, dynamic>> get _allAvailableUsers {
    // ✅ المستلمون = الجالسون على المقاعد فقط. لا يظهر في «إرسال إلى»
    //    من لم يدخل الغرفة أو لم يصعد على مقعد — allRoomUsers (أعضاء
    //    الغرفة غير الجالسين) مستبعد عمداً من التحديد.
    final map = <String, Map<String, dynamic>>{};
    for (final u in widget.seatUsers) {
      final id = u['id']?.toString() ?? '';
      if (id.isNotEmpty) map[id] = u;
    }
    for (final u in widget.targetUsers) {
      final id = u['id']?.toString() ?? '';
      if (id.isNotEmpty && !map.containsKey(id)) map[id] = u;
    }
    return map.values.toList();
  }

  List<Map<String, dynamic>> get _effectiveSeatUsers {
    if (widget.seatUsers.isNotEmpty) return widget.seatUsers;
    return widget.targetUsers;
  }

  List<Map<String, dynamic>> get _effectiveRoomUsers => _allAvailableUsers;

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
          : (widget.targetUsers.isNotEmpty ? widget.targetUsers : _allAvailableUsers);
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
    _categoryPageController.dispose();
    for (final c in _gridControllers.values) {
      c.dispose();
    }
    _gridControllers.clear();
    _comboTimer?.cancel();
    _programmaticPageTimer?.cancel();
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

  /// ✅ تحميل الهدايا والتصنيفات — مُحسَّن لتقليل التزاحم على الشبكة:
  /// 1) عرض فوري من الكاش (بدون انتظار).
  /// 2) تحديث شبكي مؤجّل 600ms حتى لا يزاحم الكاش.
  /// 3) streams للتحديثات الحية.
  /// 4) prefetch محدود بأول 20 هدية فقط بدل القائمة الكاملة.
  void _loadGifts() {
    final fb = SupabaseService();
    final dataSvc = SupabaseDataService();

    void applyCategories(List<GiftCategory> cats) {
      if (!mounted) return;
      final filteredCats = cats.where((c) => c.id.toLowerCase() != 'all').toList();
      setState(() {
        _categories = filteredCats;
        if (_selectedCategoryId == null || _selectedCategoryId == 'all') {
          _selectedCategoryId = filteredCats.isNotEmpty ? filteredCats.first.id : null;
        }
      });
    }

    String giftsSignature = '';

    void applyGifts(List<gm.GiftModel> gifts) {
      if (!mounted || gifts.isEmpty) return;
      // ✅ لا نعيد بناء الشبكة إذا لم تتغير قائمة الهدايا — الـ stream
      //    يبعث كل 10 ثوانٍ وكان يسبب وميض/«إعادة تحميل» مرئي كل مرة.
      final sig = gifts
          .map((g) => '${g.id}:${g.value}:${g.sortOrder}')
          .join(',');
      if (sig == giftsSignature && _gifts.isNotEmpty) return;
      giftsSignature = sig;
      final wasEmpty = _gifts.isEmpty;
      setState(() {
        _gifts = gifts;
        if (wasEmpty) {
          _giftsLoaded = true;
          _giftsLoading = false;
        }
        if (_sel < 0 && _gifts.isNotEmpty) {
          _sel = 0;
        } else if (_sel >= _gifts.length) {
          _sel = _gifts.isNotEmpty ? 0 : -1;
        }
      });
      // ✅ لا نُحمّل ملفات الهدايا مسبقاً — التحميل يحدث عند الضغط على الهدية فقط
      //    (شريط تقدّم) وتُحفظ في الكاش فلا تُحمَّل مرة أخرى.
      if (_sel >= 0 && _sel < _gifts.length) {
        _syncGiftReadyFromCache(_gifts[_sel]);
      }
    }

    // 1) عرض فوري من الكاش
    setState(() => _giftsLoading = true);
    dataSvc.getGiftCategories().then(applyCategories).catchError((_) {});
    dataSvc.getGifts().then((gifts) {
      if (gifts.isNotEmpty) {
        applyGifts(gifts);
      } else {
        // الكاش فاضي - ننتظر التحميل من الشبكة
        setState(() => _giftsLoading = true);
      }
    }).catchError((_) {});

    // ✅ لا تحديث شبكي إجباري عند الفتح — الكتالوج له TTL (10 دقائق)
    //    + كاش قرص دائم + streams للتحديثات الحية. الفتح أصبح فورياً
    //    بدون إعادة تحميل كاملة كل مرة.

    // 3) streams للتحديثات الحية
    _catSub = fb.giftCategoriesStream().listen((cats) {
      if (mounted) applyCategories(cats);
    });
    _giftSub = fb.giftsStream().listen(applyGifts);
  }

  /// ✅ كل قسم يعرض كل ما بداخله — حتى لو الـ category_id مش مكتوب
  ///    بالطريقة المتوقعة، نعتمد على نوع الهدية كمان. ده بيمنع ظهور
  ///    قسم فاضي وهو في الحقيقة فيه هدايا (زي القسم السادس).
  bool _giftMatchesCategory(gm.GiftModel g, String categoryId) {
    final sel = categoryId.toLowerCase().trim();
    if (sel.isEmpty || sel == 'all') return true;
    final gid = (g.categoryId ?? '').toLowerCase().trim();
    if (gid == sel) return true;
    final type = g.giftType;
    if (sel == 'lucky' && type == 3) return true;
    if ((sel == 'cp' || sel == 'relationship') && type == 5) return true;
    if (sel == 'backpack' && type == 4) return true;
    if ((sel == 'luxury' || sel == 'celebrity' || sel == 'vip') && type == 2) {
      return true;
    }
    if (sel == 'general' && gid.isEmpty && type == 1) return true;
    return false;
  }

  List<gm.GiftModel> _getGiftsForCategory(String? categoryId) {
    if (categoryId == null ||
        categoryId.isEmpty ||
        categoryId.toLowerCase() == 'all') {
      return _gifts;
    }
    return _gifts
        .where((g) => _giftMatchesCategory(g, categoryId))
        .toList();
  }

  List<gm.GiftModel> get _filteredGifts => _getGiftsForCategory(_selectedCategoryId);

  // ═══════════════════════════════════════════════════════════════════
  //  التحميل عند الطلب (Lazy download) لملفات الهدايا الثقيلة
  // ═══════════════════════════════════════════════════════════════════

  /// رابط ملف الأنيميشن الثقيل للهدية إن كان عن بُعد (SVGA/فيديو).
  /// الملفات المحلية (assets) لا تحتاج تحميلاً.
  String? _giftHeavyAsset(gm.GiftModel g) {
    final anim = (g.animationAsset ?? '').trim();
    if (anim.isEmpty) return null;
    if (!anim.startsWith('http://') && !anim.startsWith('https://')) return null;
    return anim;
  }

  bool _isGiftAssetReady(gm.GiftModel g) {
    final url = _giftHeavyAsset(g);
    if (url == null) return true;
    return _giftAssetReady.contains(url);
  }

  double? _giftAssetProgressFor(gm.GiftModel g) {
    final url = _giftHeavyAsset(g);
    if (url == null) return null;
    if (_giftAssetReady.contains(url)) return 1.0;
    return _giftAssetProgress[url];
  }

  /// فحص الكاش فقط (بدون تحميل) — يُستدعى عند اختيار هدية مخزّنة مسبقاً
  /// حتى لا نحتاج إلى تحميلها مرة أخرى.
  void _syncGiftReadyFromCache(gm.GiftModel g) {
    final url = _giftHeavyAsset(g);
    if (url == null) return;
    if (_giftAssetReady.contains(url) || _giftAssetDownloads.containsKey(url)) {
      return;
    }
    MediaCacheService().isCached(url).then((cached) {
      if (!mounted || !cached) return;
      setState(() => _giftAssetReady.add(url));
    }).catchError((_) {});
  }

  /// يبدأ تحميل ملف الأنيميشن الثقيل للهدية [g] عند الطلب فقط، مع عرض شريط
  /// تقدّم على البطاقة. لا يُعاد التحميل إذا كان مُخزَّناً في الكاش.
  void _ensureGiftAssetLoaded(gm.GiftModel g) {
    final url = _giftHeavyAsset(g);
    if (url == null) return;
    if (_giftAssetReady.contains(url)) return;
    if (_giftAssetDownloads.containsKey(url)) return;

    setState(() {
      _giftAssetFailed.remove(url);
      _giftAssetProgress[url] = 0.0;
    });

    final future = () async {
      try {
        final already = await MediaCacheService().isCached(url);
        if (already) {
          if (mounted) {
            setState(() {
              _giftAssetProgress.remove(url);
              _giftAssetReady.add(url);
            });
          }
          return;
        }
        await MediaCacheService().downloadToBytesWithProgress(
          url,
          onProgress: (p) {
            if (!mounted) return;
            setState(() => _giftAssetProgress[url] = p);
          },
        );
        if (!mounted) return;
        setState(() {
          _giftAssetProgress.remove(url);
          _giftAssetReady.add(url);
          _giftAssetFailed.remove(url);
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _giftAssetProgress.remove(url);
          _giftAssetFailed.add(url);
        });
      } finally {
        _giftAssetDownloads.remove(url);
      }
    }();
    _giftAssetDownloads[url] = future;
  }

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
      // ✅ ترتيب حتمي: sort_order ثم id — cp و luxury كلاهما sort_order=2
      //    كان الترتيب يتقلب بين البناءات فيظهر القسم "اللي قبله".
      ..sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    // ✅ لا نخفي أي قسم — المستخدم لازم يقدر يوصل لكل الأقسام بالسحب،
    //    حتى لو القسم السادس فاضي أو هداياه متصنّفة بطريقة مختلفة.
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
      // ✅ لا نترك _pageSyncedCatId قديماً فيُطلق قفزة قديمة بعد التحديث.
      _pageSyncedCatId = _selectedCategoryId;
    }
    // Auto-select first gift if none selected
    final filtered = _filteredGifts;
    if ((_sel < 0 || _sel >= _gifts.length) && filtered.isNotEmpty) {
      final idx = _gifts.indexWhere((g) => g.id == filtered.first.id);
      if (idx >= 0) _sel = idx;
    }
    final selectedGift = (_sel >= 0 && _sel < _gifts.length) ? _gifts[_sel] : null;
    // عند تغيّر الهدية المختارة تلقائياً، نفحص الكاش فقط (بدون تحميل) حتى
    // تُرسَل الهدايا المخزّنة مسبقاً فوراً.
    if (selectedGift != null && selectedGift.id != _lastReadyCheckGiftId) {
      _lastReadyCheckGiftId = selectedGift.id;
      final sg = selectedGift;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncGiftReadyFromCache(sg);
      });
    }
    final isLuckyActive = _selectedCategoryId == 'lucky' || (selectedGift != null && (selectedGift.isLucky || selectedGift.categoryId == 'lucky' || selectedGift.type == 3));

    // ✅ رفع الصندوق فوق شريط التنقل السفلي الخاص بالجهاز (أزرار/إيماءات)
    //    حتى لا يختفي شريط الإرسال خلفه
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      // ✅ امتصاص أي سحب أفقي داخل لوحة الهدايا بالكامل (الهيدر، شريط
      //    التصنيفات، المسافات الفارغة) حتى لا يسرّب لإيماءة تنقّل في الأب
      //    فتفتح شاشة الترتيب بالغلط. PageView الداخلي أعمق في الشجرة،
      //    therefore يفوز بالـ gesture arena ويحتفظ بسحب التصنيفات كما هو.
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) {},
        onHorizontalDragUpdate: (_) {},
        onHorizontalDragEnd: (_) {},
        onHorizontalDragCancel: () {},
        child: ListenableBuilder(
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
                  color: dc.giftPanelBgColor.withValues(alpha: dc.giftPanelOpacity),
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
      ),
      ),
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
    if (index < 0 || index >= _tabKeys.length) return;
    final ctx = _tabKeys[index].currentContext;
    if (ctx == null || !ctx.mounted) return;
    // ✅ نمرّز إلى التبويب الحقيقي الذي انتقلنا إليه بدل الإزاحة الثابتة
    //    القديمة (index * 75 - 100) التي كانت تُظهر التصنيف الخطأ.
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 220),
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
            child: Directionality(
              // ✅ ثبّتنا اتجاه الشريط والـ PageView على RTL عشان السحب
              //    لليسار يروح للقسم اللي على اليسار والعكس — بغض النظر
              //    عن لغة الجهاز.
              textDirection: TextDirection.rtl,
              child: ListView(
              controller: _tabScrollController,
              scrollDirection: Axis.horizontal,
              // ✅ AlwaysScrollable حتى لو التصنيفات كلها جوه الشاشة —
              //    لازم شريط التصنيفات يطالب بالسحب الأفقي بنفسه بدل ما
              //    يسرّب للحاويات اللي فوقه (سببانتقال لشاشة الترتيب).
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              children: [
                for (int i = 0; i < allTabs.length; i++)
                  Builder(
                    builder: (context) {
                      final cat = allTabs[i];
                      final isSelected = _selectedCategoryId == cat.id;
                      return GestureDetector(
                        key: _tabKey(i),
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

  /// مصدر واحد للحقيقة: الشريط والشبكة يقرآن نفس `_selectedCategoryId`.
  /// ✅ التبديل بالضغط على التبويب أو بالسحب أفقيًا على شبكة الهدايا،
  ///    مع أنيميشن انزلاق ناعم لمحتوى الشبكة فقط (الصندوق ثابت)،
  ///    وتبقى الهدية المحددة محفوظة لكل تصنيف عند الرجوع إليه.
  void _selectCategory(List<GiftCategory> allTabs, int index) {
    if (index < 0 || index >= allTabs.length) return;
    final cat = allTabs[index];
    _scrollToTab(index);
    if (cat.id == _selectedCategoryId &&
        (_categoryPageController.page?.round() ?? index) == index) {
      return;
    }
    // ✅ الضغطة على التبويب تنتقل مباشرة — قفزة بلا أنيميشن حتى لا يمر
    //    الـ PageView على صفحات وسيطة تُحدّث التصنيف ثم ترجعه.
    _programmaticPage = true;
    _programmaticPageIndex = index;
    _applyCategory(cat);
    _pageSyncedCatId = cat.id;
    final ctrl = _categoryPageController;
    void doJump() {
      if (!mounted || !ctrl.hasClients) return;
      if (ctrl.page?.round() != index) ctrl.jumpToPage(index);
    }

    if (ctrl.hasClients) {
      doJump();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => doJump());
    }
    // ✅ الحماية لا تُزال بعد إطار واحد (كانت سبب الرجوع للتصنيف السابق):
    //    تُزال فقط عند وصول إشعار ScrollEnd للصفحة المطلوبة، أو بمهلة
    //    احتياطية في حال عدم وصول إشعار أصلاً.
    _programmaticPageTimer?.cancel();
    _programmaticPageTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      _programmaticPage = false;
      _programmaticPageIndex = null;
    });
  }

  /// يطبّق التصنيف المختار فورًا (تحديد الهدية + تسخين الصور + إرجاع التمرير).
  /// idempotent: استدعاؤه أكثر من مرة لنفس التصنيف لا يغيّر شيئًا.
  void _applyCategory(GiftCategory cat) {
    if (cat.id == _selectedCategoryId) return;
    _pageSyncedCatId = cat.id; // ✅ يُحدّث فوراً لمنع أي مزامنة خاطئة
    final filtered = _getGiftsForCategory(cat.id);
    setState(() {
      _selectedCategoryId = cat.id;
      final remembered = _selectedGiftByCat[cat.id];
      final targetId = (remembered != null && filtered.any((g) => g.id == remembered))
          ? remembered
          : (filtered.isNotEmpty ? filtered.first.id : null);
      if (targetId != null) {
        final idx = _gifts.indexWhere((g) => g.id == targetId);
        if (idx >= 0) _sel = idx;
      }
    });
    // ✅ لا نُحمّل ملفات الهدايا مسبقاً — التحميل عند الضغط على الهدية فقط.
    // ✅ إرجاع التمرير الرأسي لأعلى الشبكة عند تغيير التصنيف
    _resetGridScroll(cat.id);
  }

  /// ✅ onPageChanged هو المصدر الموثوق لاختيار القسم عند السحب — بيتطلق
  ///    بعد ما الصف يتثبت، عكس ScrollEnd اللي ممكن يقرأ رقم قديم وقت الـ snap.
  ///    كده السحب لليسار يروح للقسم اليسار واليمين للقسم اليمين مباشرة.
  void _onCategoryPageChanged(List<GiftCategory> allTabs, int index) {
    if (index < 0 || index >= allTabs.length) return;
    if (_programmaticPage) {
      // قفزة من ضغطة تبويب — ننتظر لحد ما تصل للصف المطلوب.
      if (index == _programmaticPageIndex) {
        _programmaticPage = false;
        _programmaticPageIndex = null;
        _programmaticPageTimer?.cancel();
        _pageSyncedCatId = allTabs[index].id;
      }
      return;
    }
    final cat = allTabs[index];
    print('[GiftPanel] category page changed -> index=$index id=${cat.id} name=${cat.name}');
    if (cat.id == _selectedCategoryId) {
      _pageSyncedCatId = cat.id;
      return;
    }
    _applyCategory(cat);
    _scrollToTab(index);
  }

  void _resetGridScroll(String catId) {
    final controller = _gridControllers[catId];
    if (controller == null) return;
    void doJump() {
      if (controller.hasClients) {
        controller.jumpTo(0);
      }
    }
    if (controller.hasClients) {
      doJump();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) doJump();
      });
    }
  }

  /// ✅ السحب لليسار/اليمين بيحدّد القسم من onPageChanged بعد ثبات الصف،
  ///    وضغطة التبويب بتنتقل مباشرة بـ jumpToPage دون صفحات وسيطة.
  ///    ScrollEnd بيتجاهل مصدر قديم كان بيرجّع الاختيار للخلف.
  Widget _buildGrid(DynamicConfigService dc, List<GiftCategory> allTabs) {
    if (allTabs.isEmpty) {
      return const Center(
        child: DText(
          'لا توجد تصنيفات',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    }

    // ✅ المزامنة عند تغيّر التصنيف من خارج الـ PageView فقط، وبشرط ألا
    //    يكون المستخدم بصدد السحب — حتى لا نقاتل السحب ونرجعه للخلف.
    final selectedIdx = allTabs.indexWhere((c) => c.id == _selectedCategoryId);
    if (selectedIdx >= 0 &&
        _selectedCategoryId != _pageSyncedCatId &&
        !_userDragging &&
        !_programmaticPage) {
      _pageSyncedCatId = _selectedCategoryId;
      final ctrl = _categoryPageController;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !ctrl.hasClients || _userDragging || _programmaticPage) {
          return;
        }
        // ✅ نُعيد حساب الفهرس هنا بدل الاعتماد على قيمة قديمة التقطناها
        //    أثناء البناء — القيمة القديمة كانت تسبب قفزة للخلف بعد التحديث.
        final idx = allTabs.indexWhere((c) => c.id == _selectedCategoryId);
        if (idx >= 0 && ctrl.page?.round() != idx) ctrl.jumpToPage(idx);
      });
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // تجاهل إشعارات الشبكات الرأسية داخل كل صفحة.
        if (n.depth != 0) return false;
        if (n is ScrollStartNotification) {
          _userDragging = true;
          return false;
        }
        if (n is ScrollEndNotification) {
          _userDragging = false;
          final ctrl = _categoryPageController;
          if (!ctrl.hasClients) return false;
          final settled = ctrl.page?.round();
          // ✅ قفزة برمجية (ضغطة تبويب): نتجاهل كل إشعارات PageView لحين
          //    الوصول للصفحة المطلوبة — إشعار قديم بالصفحة القديمة هو سبب الرجوع.
          if (_programmaticPage) {
            final target = _programmaticPageIndex;
            if (target == null || settled == target) {
              _programmaticPage = false;
              _programmaticPageIndex = null;
              _programmaticPageTimer?.cancel();
            }
            return false;
          }
          // ✅ لا نعيد تطبيق التصنيف هنا — onPageChanged هو اللي بيطبّقه
          //    بعد ثبات الصف. قراءة ctrl.page هنا كانت بترجع رقم قديم
          //    وقت الأنيميشن فترجّع الاختيار للخلف.
          final idx = allTabs.indexWhere((c) => c.id == _selectedCategoryId);
          if (idx >= 0) _scrollToTab(idx);
        }
        return false;
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: PageView.builder(
        controller: _categoryPageController,
        // ✅ Clamping بدل Bouncing: السحبة الواحدة بتقف على تصنيف واحد
        //    بالظبط وما بتعملش fling يتخطى تصنيفين أو يرجّع للخلف.
        physics: const ClampingScrollPhysics(),
        pageSnapping: true,
        itemCount: allTabs.length,
        onPageChanged: (i) => _onCategoryPageChanged(allTabs, i),
        itemBuilder: (context, i) => _buildCategoryGrid(allTabs[i], dc),
        ),
      ),
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
    
    // ✅ عرض مؤشر تحميل شفاف أثناء جلب الهدايا من الشبكة
    final showLoading = _giftsLoading && !_giftsLoaded && items.isEmpty;

    return Stack(
      children: [
        if (items.isEmpty && !showLoading)
          Center(
            key: ValueKey('empty_${cat.id}'),
            child: const DText(
              'لا توجد هدايا متاحة',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          )
        else if (items.isNotEmpty)
          Padding(
            key: ValueKey('cat_grid_${cat.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: GridView.builder(
              controller: _gridControllerFor(cat.id),
              padding: const EdgeInsets.only(top: 6, bottom: 50),
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              scrollCacheExtent: const ScrollCacheExtent.pixels(1400),
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 82 / 96,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) => _buildGiftItemFromList(items, i, dc),
            ),
          ),
        // ✅ طبقة التحميل الشفافة فوق الشبكة
        if (showLoading)
          Container(
            color: Colors.black.withValues(alpha: 0.3),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                  const SizedBox(height: 12),
                  DText(
                    'جاري تحميل الهدايا...',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGiftItemFromList(List<gm.GiftModel> items, int i, DynamicConfigService dc) {
    if (i >= items.length) return const SizedBox();
    final g = items[i];
    final sel = _sel >= 0 && _sel < _gifts.length && _gifts[_sel].id == g.id;

    // ✅ RepaintBoundary لعزل إعادة الرسم لكل بطاقة على حدة —
    //    عندما يتغير _sel، فقط البطاقتان المتأثرتان تُعاد رسمهما.
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          final idx = _gifts.indexWhere((x) => x.id == g.id);
          setState(() {
            _sel = idx;
            // ✅ نحفظ الاختيار لهذا التصنيف حتى لا يتغيّر عند العودة إليه
            _selectedGiftByCat[_selectedCategoryId ?? ''] = g.id;
          });
          // ✅ التحميل عند الطلب: عند الضغط على الهدية يُحمَّل ملف الأنيميشن
          //    مع شريط تقدّم، ويُحفظ في الكاش فلا يُحمَّل مرة أخرى.
          _ensureGiftAssetLoaded(g);
        },
        child: _buildGiftItemContent(g, sel, dc),
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

  Widget _buildGiftItemContent(gm.GiftModel g, bool sel, DynamicConfigService dc) {
    final hasCardBgImage = dc.giftPanelCardBgImage.isNotEmpty;
    // ── حالة تحميل ملف الأنيميشن (التحميل عند الطلب) ──
    final heavyAsset = _giftHeavyAsset(g);
    final assetProgress = _giftAssetProgressFor(g);
    final isDownloading = assetProgress != null && assetProgress < 1.0;
    final isFailed = heavyAsset != null && _giftAssetFailed.contains(heavyAsset);
    final needsDownload =
        heavyAsset != null && !_isGiftAssetReady(g) && !isDownloading && !isFailed;
    return AnimatedContainer(
      // ✅ تقليل مدة الأنيميشن — أخف على GPU عند التمرير السريع
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: hasCardBgImage ? null : dc.giftPanelCardBgColor,
        // ✅ إزالة الخلفية الرمادية الافتراضية (room_gift_img_pre) —
        //    الاختيار الآن يُظهر الإطار الذهبي فقط بدون مربع خلف الصورة.
        //    صورة الخلفية المخصصة من لوحة التحكم تبقى إن وُجدت.
        image: (sel && hasCardBgImage)
            ? DecorationImage(
                image: R.cachedImage(dc.giftPanelCardBgImage),
                fit: BoxFit.fill,
              )
            : null,
        borderRadius: BorderRadius.circular(4),
        border: sel
            ? Border.all(color: dc.giftPanelCardSelectedBorderColor, width: 1.5)
            : null,
        boxShadow: sel
            ? [
          BoxShadow(
            color: dc.giftPanelTabColor.withValues(alpha: 0.55),
            blurRadius: 14,
            spreadRadius: 1.5,
          ),
        ]
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
                      // ✅ easeOutBack أخف من elasticOut بنفس الإحساس البصري
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutBack,
                      child: g.iconAsset.isNotEmpty
                          ? R.loadImage(
                        g.iconAsset,
                        width: 60,
                        height: 60,
                        fit: BoxFit.contain,
                        // ✅ TODO: بعد تعديل R.loadImage لدعم cacheWidth/cacheHeight
                        //    أضف هنا: cacheWidth: 120, cacheHeight: 120
                        //    لفك الترميز بالحجم الفعلي فقط (أسرع 3-5x)
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
                // ── شريط تحميل الهدية عند الطلب ──
                if (isDownloading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.5),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: const Color(0xFFFFD700),
                              value: (assetProgress <= 0) ? null : assetProgress,
                            ),
                          ),
                          const SizedBox(height: 3),
                          DText(
                            '${(assetProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (isFailed)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _ensureGiftAssetLoaded(g),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.5),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.refresh_rounded,
                                size: 20, color: Colors.redAccent),
                            const SizedBox(height: 2),
                            DText(
                              'إعادة المحاولة',
                              style: const TextStyle(
                                  fontSize: 8, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (needsDownload)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Color(0x99000000),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.download_rounded,
                        size: 12,
                        color: Color(0xFFFFD700),
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

    // ✅ انتظار تحميل الهدايا من الكاش/الشبكة قبل الإرسال
    // إذا كانت الهدايا في الكاش (_giftsLoaded == true) → نرسل فوراً
    // إذا لم تكن محملة → ننتظر التحميل (مع timeout 10 ثواني)
    if (!_giftsLoaded) {
      setState(() => _giftsLoading = true);
      int waitCount = 0;
      while (!_giftsLoaded && waitCount < 100 && mounted) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }
      if (!mounted) return;
      if (!_giftsLoaded) {
        setState(() {
          _errorMsg = 'فشل تحميل الهدايا، يرجى المحاولة مرة أخرى';
        });
        final d = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _errorMsg = null);
        });
        _pendingDelays.add(d);
        return;
      }
    }

    if (_sel < 0 || _sel >= _gifts.length) return;

    final gift = _gifts[_sel];
    // ✅ لا يُسمح بالإرسال قبل اكتمال تحميل ملف الأنيميشن للهدية
    if (!_isGiftAssetReady(gift)) {
      _ensureGiftAssetLoaded(gift);
      if (mounted) {
        setState(() => _errorMsg = 'جاري تحميل الهدية، الرجاء الانتظار...');
        final d = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _errorMsg = null);
        });
        _pendingDelays.add(d);
      }
      return;
    }
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

    // إرسال عبر الشبكة في الخلفية دون حظر الواجهة إطلاقاً
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
            userProvider.deductCoinsLocally(gift.value * widget.selectedCount);
            ok = await fb.sendGift(
              roomId: widget.roomId,
              roomName: widget.roomName,
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
        // ✅ إعادة قراءة الرصيد من السيرفر بعد كل إرسال حتى تتطابق
        //    الأرقام الظاهرة في التطبيق مع لوحة التحكم تماماً.
        unawaited(userProvider.reloadUser());
        widget.onGiftSettled?.call(allOk);
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
              Row(
                children: [
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
                            color: const Color(0xFF14FAB1).withValues(alpha: 0.35),
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
    // ✅ الهدية جاهزة للإرسال فقط بعد تحميل ملف الأنيميشن (التحميل عند الطلب)
    final giftReady = gift == null || _isGiftAssetReady(gift);
    final assetProgress = gift != null ? _giftAssetProgressFor(gift) : null;
    final giftDownloading = assetProgress != null && assetProgress < 1.0;
    final canSend = canAfford && giftReady;

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
                    color: Colors.black.withValues(alpha: 0.25),
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  GestureDetector(
                    onTap: () {
                      // ✅ منع الإرسال أثناء تحميل الهدايا
                      if (_giftsLoading && !_giftsLoaded) {
                        setState(() {
                          _errorMsg = 'جاري تحميل الهدايا، الرجاء الانتظار...';
                        });
                        final d = Timer(const Duration(seconds: 2), () {
                          if (mounted) setState(() => _errorMsg = null);
                        });
                        _pendingDelays.add(d);
                        return;
                      }
                      // ✅ الهدية غير محمّلة بعد: ابدأ التحميل وامنع الإرسال
                      if (gift != null && !_isGiftAssetReady(gift)) {
                        _ensureGiftAssetLoaded(gift);
                        setState(() {
                          _errorMsg = _giftAssetFailed
                                  .contains(_giftHeavyAsset(gift))
                              ? 'تعذّر تحميل الهدية، اضغط الهدية لإعادة المحاولة'
                              : 'جاري تحميل الهدية، الرجاء الانتظار...';
                        });
                        final d = Timer(const Duration(seconds: 2), () {
                          if (mounted) setState(() => _errorMsg = null);
                        });
                        _pendingDelays.add(d);
                        return;
                      }
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
                            ? (canSend
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
                            // ✅ مؤشر تحميل ملف الهدية المختارة على زر الإرسال
                            if (giftDownloading)
                              Container(
                                color: Colors.black.withValues(alpha: 0.55),
                                child: Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      color: const Color(0xFFFFD700),
                                      strokeWidth: 2,
                                      value: assetProgress <= 0 ? null : assetProgress,
                                    ),
                                  ),
                                ),
                              ),
                            // ✅ مؤشر تحميل الهدايا على زر الإرسال
                            if (_giftsLoading && !_giftsLoaded)
                              Container(
                                color: Colors.black.withValues(alpha: 0.5),
                                child: const Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
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
      duration: const Duration(milliseconds: 4000),
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
  final VoidCallback? onBannerTap;
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
    this.onBannerTap,
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
  Offset _dragOffset = Offset.zero;

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

    _enterAnim = Tween<Offset>(
      begin: const Offset(1.5, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enterController, curve: Curves.easeOutCubic));

    _exitAnim = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-1.5, 0.0),
    ).animate(CurvedAnimation(parent: _exitController, curve: Curves.easeInCubic));

    _enterController.forward();

    // مهلة احتياطية فقط: اللافتة تُغلق فعلياً عند انتهاء الأنيميشن عبر
    // `onFinished`. نُبقي هذه المهلة طويلة حتى لا يُقطع الأنيميشن قبل اكتماله.
    _autoDismissTimer = Timer(const Duration(milliseconds: 12000), () {
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
            onTap: () {
              _autoDismissTimer?.cancel();
              final onBannerTap = widget.onBannerTap;
              if (onBannerTap != null) onBannerTap();
              _dismiss();
            },
            onPanStart: (_) {
              _autoDismissTimer?.cancel();
            },
            onPanUpdate: (details) {
              setState(() {
                _dragOffset += details.delta;
                if (_dragOffset.dy > 20) {
                  _dragOffset = Offset(_dragOffset.dx, 20);
                }
              });
            },
            onPanEnd: (details) {
              final dx = _dragOffset.dx;
              final dy = _dragOffset.dy;
              final vx = details.velocity.pixelsPerSecond.dx;
              final vy = details.velocity.pixelsPerSecond.dy;
              final shouldDismiss = dx.abs() > 55 ||
                  dy < -45 ||
                  vx.abs() > 600 ||
                  vy < -400;
              if (shouldDismiss) {
                _dragOffset = Offset.zero;
                _dismiss();
              } else {
                setState(() => _dragOffset = Offset.zero);
                _autoDismissTimer?.cancel();
                _autoDismissTimer =
                    Timer(const Duration(milliseconds: 2500), _dismiss);
              }
            },
            child: Transform.translate(
              offset: _dragOffset,
              child: Opacity(
                opacity:
                (1 - (_dragOffset.distance / 260)).clamp(0.35, 1.0),
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
        ),
      ),
    );
  }
}