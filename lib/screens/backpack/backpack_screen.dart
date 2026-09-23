import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../models/gift_model.dart' as gm;
import '../../models/store_item_model.dart';
import '../../providers/user_provider.dart';
import '../../services/supabase_service.dart';
import '../mall/mall_screen.dart';
import '../room/widgets/svga_player.dart';

class BackpackScreen extends StatefulWidget {
  const BackpackScreen({super.key});

  @override
  State<BackpackScreen> createState() => _BackpackScreenState();
}

class _BackpackScreenState extends State<BackpackScreen> {
  final SupabaseService _firebaseService = SupabaseService();

  // التصنيفات الأربعة الأصلية من PackageActivity.java + قسم الهدايا
  // ملاحظة هامة: تم تغيير مسمى "المخرجات" إلى "مؤثرات الدخول" بناءً على طلب المستخدم
  static const List<Map<String, String>> _categories = [
    {
      'key': 'frame',
      'name': 'إطار الرأس',
      'nor_ic': 'assets/mipmap-xxhdpi/mine_mall_type_head_wear_nor_ic.webp',
      'pre_ic': 'assets/mipmap-xxhdpi/mine_mall_type_head_wear_pre_ic.webp',
    },
    {
      'key': 'car',
      'name': 'المركبة',
      'nor_ic': 'assets/mipmap-xxhdpi/mine_mall_type_car_nor_ic.webp',
      'pre_ic': 'assets/mipmap-xxhdpi/mine_mall_type_car_pre_ic.webp',
    },
    {
      'key': 'entrance',
      'name': 'مؤثرات الدخول', // الاسم الدقيق لمؤثرات الدخول (TYPE_ENTRANCE)
      'nor_ic': 'assets/mipmap-xxhdpi/mine_mall_type_entrance_nor_ic.webp',
      'pre_ic': 'assets/mipmap-xxhdpi/mine_mall_type_entrance_pre_ic.webp',
    },
    {
      'key': 'bubble',
      'name': 'الفقاعة',
      'nor_ic': 'assets/mipmap-xxhdpi/mine_mall_type_bubble_nor_ic.webp',
      'pre_ic': 'assets/mipmap-xxhdpi/mine_mall_type_bubble_pre_ic.webp',
    },
    {
      'key': 'gifts',
      'name': 'الهدايا',
      'nor_ic': 'assets/mipmap-xxhdpi/mine_union_ic.webp',
      'pre_ic': 'assets/mipmap-xxhdpi/mine_union_ic.webp',
    },
    {
      'key': 'mic_wave',
      'name': 'موجات المايك',
      'nor_ic': 'assets/mipmap-xxhdpi/room_mic_on.webp',
      'pre_ic': 'assets/mipmap-xxhdpi/room_mic_on.webp',
    },
  ];

  int _selectedCategoryIndex = 0;
  StoreItemModel? _selectedItem;
  StoreItemModel? _previewItem; // معاينة ملء الشاشة للسيارات ومؤثرات الدخول

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF16151A), // color_16151A
      body: Stack(
        children: [
          // 1. خلفية المتجر والحقيبة العلوية mine_mall_top_bg
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 260,
            child: Image.asset(
              'assets/mipmap-xxhdpi/mine_mall_top_bg.webp',
              fit: BoxFit.cover,
            ),
          ),

          // 2. الهيكل الرئيسي للشاشة
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // شريط العنوان العلوي title_bar
                _buildTopBar(context),

                // شريط التبويبات التصنيفية الأفقي recyclerview_type
                _buildCategoryTabs(),

                const SizedBox(height: 12),

                // الحاوية السفلية الممتدة مع خلفية mine_mall_type_tab_item_bg
                Expanded(
                  child: Stack(
                    children: [
                      // الخلفية الداكنة
                      Positioned.fill(
                        top: 15,
                        child: Container(
                          color: const Color(0xFF16151A),
                        ),
                      ),
                      // رأس الحاوية المزخرف mine_mall_type_tab_item_bg
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 50,
                        child: Image.asset(
                          'assets/mipmap-xxhdpi/mine_mall_type_tab_item_bg.webp',
                          fit: BoxFit.fill,
                        ),
                      ),
                      // المحتوى: شبكة العناصر أو تبويب الهدايا
                      Positioned.fill(
                        top: 20,
                        child: _buildMainContent(userProvider, user),
                      ),
                    ],
                  ),
                ),

                // شريط الارتداء السفلي المطابق لـ cl_use في mine_mall_package.xml
                if (_categories[_selectedCategoryIndex]['key'] != 'gifts')
                  _buildBottomBar(userProvider, user),
              ],
            ),
          ),

          // 3. طبقة معاينة SVGA بالحجم الكامل (للسيارات ومؤثرات الدخول car_svga_play)
          if (_previewItem != null)
            _buildFullscreenAnimationOverlay(user),
        ],
      ),
    );
  }

  /// شريط العنوان العلوي المطابق لـ CommonTopBar
  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // زر الرجوع
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.transparent,
              child: Image.asset(
                'assets/mipmap-xxhdpi/back_white.webp',
                width: 22,
                height: 22,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              ),
            ),
          ),
          const Spacer(),
          const Text(
            'الحقيبة',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          // رابط مباشر للمتجر لسهولة التنقل
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MallScreen()),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0x33FAE9B5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x66FAE9B5)),
              ),
              child: Row(
                children: [
                  Image.asset(
                    'assets/mipmap-xxhdpi/mine_mall_ic.webp',
                    width: 16,
                    height: 16,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'المتجر',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFFAE9B5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// شريط التبويبات التصنيفية الأفقي المطابق لـ mine_adapter_mall_type.xml
  Widget _buildCategoryTabs() {
    return SizedBox(
      height: 85,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedCategoryIndex == index;
          final iconPath = isSelected ? cat['pre_ic']! : cat['nor_ic']!;
          final isAsset = iconPath.startsWith('assets/');

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategoryIndex = index;
                _selectedItem = null;
              });
            },
            child: Container(
              width: 78,
              height: 85,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // خلفية التحديد mine_mall_type_item_bg
                  if (isSelected)
                    Positioned.fill(
                      child: Image.asset(
                        'assets/mipmap-xxhdpi/mine_mall_type_item_bg.webp',
                        fit: BoxFit.fill,
                      ),
                    ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: isAsset
                            ? Image.asset(iconPath, fit: BoxFit.contain)
                            : R.loadImage(iconPath, fit: BoxFit.contain),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cat['name']!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? const Color(0xFFFAE9B5) : const Color(0x80FAE9B5),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// المحتوى الرئيسي للحقيبة
  Widget _buildMainContent(UserProvider userProvider, dynamic user) {
    final currentCat = _categories[_selectedCategoryIndex]['key']!;
    if (currentCat == 'gifts') {
      return _buildGiftsTab();
    }
    return _buildCategoryItems(userProvider, user, currentCat);
  }

  /// شبكة العناصر المملوكة للتصنيف الحالي
  Widget _buildCategoryItems(UserProvider userProvider, dynamic user, String category) {
    return StreamBuilder<List<StoreItemModel>>(
      stream: _firebaseService.storeItemsStream(),
      builder: (context, snapshot) {
        final allItems = snapshot.data ?? [];
        final userOwnedIds = user?.ownedItems ?? [];

        // 1. العناصر المشتراة من المتجر
        final storeItems = allItems
            .where((item) => item.category == category && userOwnedIds.contains(item.itemId))
            .toList();

        // 2. إطارات المستوى المكتسبة
        final levelFrames = category == 'frame'
            ? (user?.ownedLevelFrames ?? []).map((url) {
                return StoreItemModel(
                  itemId: url,
                  name: 'إطار المستوى',
                  category: 'frame',
                  iconAsset: url,
                  price: 0,
                );
              }).toList()
            : <StoreItemModel>[];

        // 3. ملحقات VIP المملوكة
        final vipItems = (user?.ownedVipItems ?? [])
            .where((m) => m['type'] == category)
            .map((m) {
              final url = m['url'] ?? '';
              return StoreItemModel(
                itemId: url,
                name: m['name']?.isNotEmpty == true ? m['name']! : 'VIP',
                category: category,
                iconAsset: url,
                svgaAsset: url.toLowerCase().endsWith('.svga') ? url : null,
                price: 0,
              );
            })
            .where((si) => !storeItems.any((s) => s.itemId == si.itemId))
            .toList();

        final displayItems = [...storeItems, ...vipItems, ...levelFrames];

        // إذا لم يكن هناك أي عنصر محدد حالياً، حدد أول عنصر تلقائياً
        if (displayItems.isNotEmpty && _selectedItem == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedItem == null) {
              setState(() => _selectedItem = displayItems.first);
            }
          });
        }

        // حالة الفراغ المطابقة لـ mine_layout_package_empty.xml
        if (displayItems.isEmpty) {
          return _buildEmptyState();
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemCount: displayItems.length,
          itemBuilder: (context, index) {
            final item = displayItems[index];
            final isSelected = _selectedItem?.itemId == item.itemId;
            final isEquipped = _isItemEquipped(item, user);
            final isAnimated = (item.svgaAsset != null && item.svgaAsset!.isNotEmpty) ||
                (item.videoAsset != null && item.videoAsset!.isNotEmpty) ||
                (item.animationUrl != null && item.animationUrl!.isNotEmpty) ||
                item.iconAsset.endsWith('.svga');

            return GestureDetector(
              onTap: () {
                setState(() => _selectedItem = item);
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFF262732),
                  image: isSelected
                      ? const DecorationImage(
                          image: AssetImage('assets/mipmap-xxhdpi/mine_mall_item_bg.webp'),
                          fit: BoxFit.fill,
                        )
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // معاينة الأيقونة
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Builder(builder: (_) {
                              final hasSvga = (item.svgaAsset != null && item.svgaAsset!.isNotEmpty) ||
                                  item.iconAsset.endsWith('.svga');
                              final svgaUrl = (item.svgaAsset != null && item.svgaAsset!.isNotEmpty)
                                  ? item.svgaAsset!
                                  : item.iconAsset;
                              if (hasSvga) {
                                return SvgaPlayer(
                                  assetPath: svgaUrl,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.contain,
                                  loops: true,
                                );
                              }
                              return R.loadImage(item.iconAsset, fit: BoxFit.contain);
                            }),
                          ),

                          // شارة قيد الاستخدام tv_dress_up_state
                          if (isEquipped)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFFC525), Color(0xFFDE880F)],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'قيد الاستخدام',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),

                          // علامة الفيديو لمعاينة التأثير الكامل iv_video_label
                          if (isAnimated)
                            Positioned(
                              left: 8,
                              bottom: 8,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => _previewItem = item);
                                },
                                child: Image.asset(
                                  'assets/mipmap-xxhdpi/mine_mall_video_ic.webp',
                                  width: 20,
                                  height: 20,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // اسم العنصر tv_item_name
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    const SizedBox(height: 4),

                    // المدة الزمنية / الصلاحية tv_gold_time مع أيقونة mine_mall_time_ic
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/mipmap-xxhdpi/mine_mall_time_ic.webp',
                            width: 14,
                            height: 14,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'دائم',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9BA1B6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// الحالة الفارغة المطابقة لـ mine_layout_package_empty.xml
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // أيقونة الحقيبة الفارغة mine_wallet_empty_ic (136x136)
          Image.asset(
            'assets/mipmap-xxhdpi/mine_wallet_empty_ic.webp',
            width: 136,
            height: 136,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 10),
          // النص التوضيحي tv_tip
          const Text(
            'لا توجد عناصر حالياً في هذا القسم',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF9BA1B6),
            ),
          ),
          const SizedBox(height: 36),
          // زر الذهاب إلى المتجر tv_goto_mall
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MallScreen()),
              );
            },
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 32),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFC525), Color(0xFFDE880F)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFDE880F).withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text(
                'الذهاب إلى المتجر',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// شريط الارتداء السفلي المطابق لـ cl_use في mine_mall_package.xml
  Widget _buildBottomBar(UserProvider userProvider, dynamic user) {
    final selected = _selectedItem;
    final isEquipped = selected != null && _isItemEquipped(selected, user);

    return Container(
      color: const Color(0xFF302218), // color_FF302218
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (selected != null)
            Text(
              'العنصر المحدد: ${selected.name}',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFFAE9B5),
                fontWeight: FontWeight.w500,
              ),
            )
          else
            const Text(
              'يرجى تحديد عنصر لارتدائه',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF9BA1B6),
              ),
            ),
          const Spacer(),

          // زر الارتداء أو إلغاء الارتداء tv_use
          GestureDetector(
            onTap: selected == null
                ? null
                : () async {
                    if (isEquipped) {
                      await userProvider.unequipItem(selected.category);
                    } else {
                      await userProvider.equipItem(selected.itemId, selected.category);
                    }
                    if (mounted) setState(() {});
                  },
            child: Container(
              width: 126,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: const AssetImage('assets/mipmap-xxhdpi/mine_mall_buy_ic.webp'),
                  fit: BoxFit.fill,
                  colorFilter: selected == null
                      ? ColorFilter.mode(Colors.black.withValues(alpha: 0.5), BlendMode.dstIn)
                      : null,
                ),
              ),
              child: Text(
                isEquipped ? 'إلغاء الارتداء' : 'ارتداء',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// معاينة ملء الشاشة للسيارات ومؤثرات الدخول car_svga_play
  Widget _buildFullscreenAnimationOverlay(dynamic user) {
    final item = _previewItem!;
    final svgaUrl = (item.svgaAsset != null && item.svgaAsset!.isNotEmpty)
        ? item.svgaAsset!
        : (item.animationUrl ?? item.iconAsset);
    final photoUrl = user?.photoUrl?.isNotEmpty == true ? user.photoUrl : null;
    final userName = user?.nickname ?? user?.name ?? '';

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.8),
        child: Stack(
          children: [
            // تشغيل SVGA مع الاستبدال الديناميكي للصورة والاسم
            Center(
              child: SvgaPlayer(
                key: ValueKey('preview_${item.itemId}'),
                assetPath: svgaUrl,
                width: double.infinity,
                height: 380,
                fit: BoxFit.contain,
                loops: true,
                imageReplacement: photoUrl != null
                    ? {'avatar': photoUrl, 'user_avatar': photoUrl}
                    : null,
                textReplacement: userName.isNotEmpty
                    ? {'name': 'مرحباً $userName', 'nickname': userName}
                    : null,
              ),
            ),

            // زر إغلاق المعاينة العلوية
            Positioned(
              top: 50,
              right: 20,
              child: GestureDetector(
                onTap: () => setState(() => _previewItem = null),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black54,
                  ),
                  child: Image.asset(
                    'assets/mipmap-xxhdpi/mine_mall_close_ic.webp',
                    width: 28,
                    height: 28,
                  ),
                ),
              ),
            ),

            // عنوان العنصر المعروض
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFAE9B5),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// تبويب سجل الهدايا المستلمة
  Widget _buildGiftsTab() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;
    if (uid == null) {
      return const Center(
        child: Text(
          'لا توجد هدايا',
          style: TextStyle(color: Color(0xFF9BA1B6), fontSize: 14),
        ),
      );
    }

    return StreamBuilder<List<gm.SentGiftModel>>(
      stream: _firebaseService.userReceivedGiftsStream(uid),
      builder: (context, snapshot) {
        final gifts = snapshot.data ?? [];
        if (gifts.isEmpty) {
          return const Center(
            child: Text(
              'لا توجد هدايا مستلمة حتى الآن',
              style: TextStyle(color: Color(0xFF9BA1B6), fontSize: 14),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: gifts.length,
          itemBuilder: (context, index) {
            final g = gifts[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF262732),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: g.senderPhotoUrl != null && g.senderPhotoUrl!.isNotEmpty
                        ? R.cachedImage(g.senderPhotoUrl!)
                        : null,
                    child: g.senderPhotoUrl == null || g.senderPhotoUrl!.isEmpty
                        ? Text(
                            g.senderName.isNotEmpty ? g.senderName[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.senderName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'أرسل ${g.giftName} (x${g.count})',
                          style: const TextStyle(
                            color: Color(0xFFFAE9B5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${g.value} ذهب',
                    style: const TextStyle(
                      color: Color(0xFFFFC525),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool _isItemEquipped(StoreItemModel item, dynamic user) {
    if (user == null) return false;
    switch (item.category) {
      case 'frame':
        return user.activeFrame == item.itemId ||
            (item.svgaAsset != null && item.svgaAsset!.isNotEmpty && user.activeFrame == item.svgaAsset);
      case 'bubble':
        return user.activeBubble == item.itemId ||
            user.activeBubble == item.svgaAsset ||
            user.activeBubble == item.iconAsset;
      case 'entrance':
        return user.activeEntrance == item.itemId ||
            (item.svgaAsset != null && item.svgaAsset!.isNotEmpty && user.activeEntrance == item.svgaAsset);
      case 'car':
        return user.activeCar == item.itemId ||
            (item.svgaAsset != null && item.svgaAsset!.isNotEmpty && user.activeCar == item.svgaAsset);
      case 'headwear':
        return user.activeHeadwear == item.itemId ||
            (item.svgaAsset != null && item.svgaAsset!.isNotEmpty && user.activeHeadwear == item.svgaAsset);
      case 'cover':
        return user.activeCover == item.itemId ||
            (item.svgaAsset != null && item.svgaAsset!.isNotEmpty && user.activeCover == item.svgaAsset);
      case 'necklace':
        return user.activeNecklace == item.itemId ||
            (item.svgaAsset != null && item.svgaAsset!.isNotEmpty && user.activeNecklace == item.svgaAsset);
      case 'mic_wave':
        return user.activeMicWave == item.itemId ||
            (item.svgaAsset != null && item.svgaAsset!.isNotEmpty && user.activeMicWave == item.svgaAsset) ||
            user.activeMicWave == item.iconAsset;
      default:
        return false;
    }
  }
}
