import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../services/supabase_service.dart';
import '../../models/store_item_model.dart';
import '../../providers/user_provider.dart';
import '../room/widgets/svga_player.dart';
import '../room/widgets/vap_player.dart';

/// شاشة المتجر الرسمية المطابقة لملف mine_activity_mall.xml
/// وملفات التخطيط الأصلية:
/// - mine_adapter_mall_type.xml (أقسام المتجر العلوية)
/// - mine_adapter_mall_type_item.xml (بطاقات العناصر)
/// - mine_dialog_mall_item_buy.xml (نافذة تأكيد الشراء)
class MallScreen extends StatefulWidget {
  const MallScreen({super.key});

  @override
  State<MallScreen> createState() => _MallScreenState();
}

class _MallScreenState extends State<MallScreen> {
  final SupabaseService _firebaseService = SupabaseService();
  List<StoreItemModel> _allItems = [];
  StoreItemModel? _selectedItem;
  int _selectedCategoryIndex = 0;

  static const List<Map<String, String>> _categoriesData = [
    {
      'key': 'frame',
      'name': 'إطار الرأس',
      'nor_ic': 'assets/mipmap-xxhdpi/mine_mall_type_head_wear_nor_ic.webp',
      'pre_ic': 'assets/mipmap-xxhdpi/mine_mall_type_head_wear_pre_ic.webp',
    },
    {
      'key': 'bubble',
      'name': 'الفقاعة',
      'nor_ic': 'assets/mipmap-xxhdpi/mine_mall_type_bubble_nor_ic.webp',
      'pre_ic': 'assets/mipmap-xxhdpi/mine_mall_type_bubble_pre_ic.webp',
    },
    {
      'key': 'entrance',
      'name': 'تأثير الدخول',
      'nor_ic': 'assets/mipmap-xxhdpi/mine_mall_type_entrance_nor_ic.webp',
      'pre_ic': 'assets/mipmap-xxhdpi/mine_mall_type_entrance_pre_ic.webp',
    },
    {
      'key': 'car',
      'name': 'مركبة الدخول',
      'nor_ic': 'assets/mipmap-xxhdpi/mine_mall_type_car_nor_ic.webp',
      'pre_ic': 'assets/mipmap-xxhdpi/mine_mall_type_car_pre_ic.webp',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  void _loadItems() {
    _firebaseService.storeItemsStream().listen((items) {
      if (mounted) {
        setState(() {
          _allItems = items;
          if (_selectedItem == null && _allItems.isNotEmpty) {
            final firstCat = _categoriesData[_selectedCategoryIndex]['key']!;
            final catItems = _allItems.where((i) => i.category == firstCat).toList();
            if (catItems.isNotEmpty) {
              _selectedItem = catItems.first;
            } else {
              _selectedItem = _allItems.first;
            }
          }
        });
      }
    });
  }

  List<StoreItemModel> _getItemsForCategory(String categoryKey) {
    return _allItems.where((item) => item.category == categoryKey).toList();
  }

  bool _isItemEquipped(StoreItemModel item, dynamic user) {
    if (user == null) return false;
    switch (item.category) {
      case 'frame':
        return user.activeFrame == item.itemId;
      case 'bubble':
        return user.activeBubble == item.itemId ||
            user.activeBubble == item.svgaAsset ||
            user.activeBubble == item.iconAsset;
      case 'entrance':
        return user.activeEntrance == item.itemId;
      case 'car':
        return user.activeCar == item.itemId;
      default:
        return false;
    }
  }

  bool _isItemOwned(StoreItemModel item, UserProvider userProvider) {
    final owned = userProvider.currentUser?.ownedItems ?? [];
    return owned.contains(item.itemId);
  }

  /// فتح نافذة تأكيد الشراء الأصلية mine_dialog_mall_item_buy.xml
  void _showBuyConfirmDialog(StoreItemModel item, UserProvider userProvider) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: _buildBuyDialogContent(ctx, item, userProvider),
      ),
    );
  }

  Widget _buildBuyDialogContent(BuildContext ctx, StoreItemModel item, UserProvider userProvider) {
    final isAnimated = (item.svgaAsset != null && item.svgaAsset!.isNotEmpty) ||
        (item.videoAsset != null && item.videoAsset!.isNotEmpty) ||
        (item.animationUrl != null && item.animationUrl!.isNotEmpty);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // زر الإغلاق العلوي iv_close
          Align(
            alignment: Alignment.topRight,
            child: GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Image.asset(
                  'assets/mipmap-xxhdpi/mine_mall_close_ic.webp',
                  width: 32,
                  height: 32,
                ),
              ),
            ),
          ),
          // البطاقة الحاوية mine_mall_item_buy_bg
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            decoration: BoxDecoration(
              color: const Color(0xFF262732),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // العنوان tv_title ("تأكيد الشراء")
                const Text(
                  'تأكيد الشراء',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),

                // صورة المعاينة iv_preview مع علامة الفيديو إن وجدت
                SizedBox(
                  width: 110,
                  height: 110,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      R.loadImage(item.iconAsset, width: 100, height: 100, fit: BoxFit.contain),
                      if (isAnimated)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Image.asset(
                            'assets/mipmap-xxhdpi/mine_mall_video_ic.webp',
                            width: 18,
                            height: 18,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // اسم العنصر tv_desc
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFAE9B5),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),

                // السعر مع أيقونة common_gold_ic_3
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/mipmap-xxhdpi/common_gold_ic_3.webp',
                      width: 18,
                      height: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${item.price}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFAE9B5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // زرا الإلغاء والشراء
                Row(
                  children: [
                    // زر الإلغاء tv_cancel
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(ctx).pop(),
                        child: Container(
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF565964),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'إلغاء',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // زر الشراء tv_confirm
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          final success = await userProvider.purchaseItem(item);
                          if (mounted) {
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم الشراء بنجاح!', textAlign: TextAlign.center),
                                  backgroundColor: Color(0xFF388E3C),
                                ),
                              );
                              setState(() {});
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('لا توجد عملات كافية لشراء هذا العنصر!', textAlign: TextAlign.center),
                                  backgroundColor: Color(0xFFD32F2F),
                                ),
                              );
                            }
                          }
                        },
                        child: Container(
                          height: 38,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            image: DecorationImage(
                              image: AssetImage('assets/mipmap-xxhdpi/mine_mall_buy_ic.webp'),
                              fit: BoxFit.fill,
                            ),
                          ),
                          child: const Text(
                            'شراء',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.currentUser;
    final currentCat = _categoriesData[_selectedCategoryIndex]['key']!;
    final items = _getItemsForCategory(currentCat);

    return Scaffold(
      backgroundColor: const Color(0xFF130E14),
      body: Stack(
        children: [
          // الخلفية الأصلية mine_mall_top_bg.webp
          Positioned.fill(
            child: Image.asset(
              'assets/mipmap-xxhdpi/mine_mall_top_bg.webp',
              fit: BoxFit.cover,
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // شريط العنوان العلوي title_bar
                _buildTopBar(),

                // شريط الأقسام الأفقي recyclerview_type (ارتفاع 85dp)
                _buildCategoriesBar(),

                // منطقة المعاينة الحية cl_preview (ارتفاع 120dp)
                _buildLivePreviewArea(user),

                // شبكة العناصر mine_fragment_mall_type
                Expanded(
                  child: _buildItemsGrid(items, userProvider, user),
                ),

                // الشريط السفلي للشراء cl_buy
                _buildBottomBar(userProvider, user),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// شريط العنوان العلوي
  Widget _buildTopBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: const Icon(
              Icons.arrow_back_ios_new,
              color: Colors.white,
              size: 20,
            ),
          ),
          const Expanded(
            child: Text(
              'المتجر',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 20),
        ],
      ),
    );
  }

  /// شريط تصنيفات المتجر المطابق لـ mine_adapter_mall_type.xml
  Widget _buildCategoriesBar() {
    return SizedBox(
      height: 85,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: _categoriesData.length,
        itemBuilder: (context, index) {
          final cat = _categoriesData[index];
          final isSelected = _selectedCategoryIndex == index;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategoryIndex = index;
                final catItems = _getItemsForCategory(cat['key']!);
                if (catItems.isNotEmpty) {
                  _selectedItem = catItems.first;
                } else {
                  _selectedItem = null;
                }
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
                      Image.asset(
                        isSelected ? cat['pre_ic']! : cat['nor_ic']!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.contain,
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

  /// منطقة المعاينة الحية cl_preview (صورة المستخدم وعليها الإطار/السيارة/الفقاعة)
  Widget _buildLivePreviewArea(dynamic user) {
    final photoUrl = user?.photoUrl?.isNotEmpty == true ? user.photoUrl : null;
    final item = _selectedItem;

    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.center,
      child: SizedBox(
        width: 120,
        height: 120,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // صورة المستخدم الدائرية iv_avatar (96x96)
            CircleAvatar(
              radius: 44,
              backgroundColor: Colors.white12,
              backgroundImage: photoUrl != null ? R.cachedImage(photoUrl) : null,
              child: photoUrl == null
                  ? const Icon(Icons.person, size: 44, color: Colors.white54)
                  : null,
            ),

            // معاينة الإطار frame
            if (item != null && item.category == 'frame') ...[
              if (item.animationUrl?.isNotEmpty == true)
                SvgaPlayer(
                  assetPath: item.animationUrl!,
                  width: 126,
                  height: 126,
                  fit: BoxFit.contain,
                )
              else if (item.iconAsset.isNotEmpty)
                R.loadImage(item.iconAsset, width: 120, height: 120, fit: BoxFit.contain),
            ] else if (item != null && item.category == 'bubble') ...[
              // معاينة الفقاعة bubble
              Positioned(
                bottom: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0x66000000),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0x88FFD700)),
                  ),
                  child: const Text(
                    'مرحباً بك!',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
            ] else if (item != null) ...[
              // معاينة السيارة أو الدخولية
              if (item.animationUrl?.isNotEmpty == true)
                SvgaPlayer(
                  assetPath: item.animationUrl!,
                  width: 120,
                  height: 110,
                  fit: BoxFit.contain,
                )
              else
                R.loadImage(item.iconAsset, width: 85, height: 85, fit: BoxFit.contain),
            ],
          ],
        ),
      ),
    );
  }

  /// شبكة بطاقات العناصر المطابقة لـ mine_adapter_mall_type_item.xml
  Widget _buildItemsGrid(List<StoreItemModel> items, UserProvider userProvider, dynamic user) {
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد عناصر في هذا القسم',
          style: TextStyle(color: Color(0x80FAE9B5), fontSize: 14),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = _selectedItem?.itemId == item.itemId;
        final isOwned = _isItemOwned(item, userProvider);
        final isEquipped = _isItemEquipped(item, user);
        final isAnimated = (item.svgaAsset != null && item.svgaAsset!.isNotEmpty) ||
            (item.videoAsset != null && item.videoAsset!.isNotEmpty) ||
            (item.animationUrl != null && item.animationUrl!.isNotEmpty);

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedItem = item;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0x1AFFDA83), // color_1affda83 (mine_mall_item_nor_bg)
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? const Color(0xFFFFD700) : Colors.white.withValues(alpha: 0.08),
                width: isSelected ? 2.0 : 1.0,
              ),
            ),
            child: Column(
              children: [
                // صورة العنصر iv_mall_img
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: R.loadImage(item.iconAsset, fit: BoxFit.contain),
                      ),
                      // علامة الفيديو iv_video_label
                      if (isAnimated)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Image.asset(
                            'assets/mipmap-xxhdpi/mine_mall_video_ic.webp',
                            width: 16,
                            height: 16,
                          ),
                        ),
                      // شارة الملكية أو الارتداء tv_dress_up_state
                      if (isOwned)
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
                            child: Text(
                              isEquipped ? 'قيد الاستخدام' : 'مملوك',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
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
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFAE9B5),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 4),

                // السعر مع أيقونة common_gold_ic_5 (tv_gold_time)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/mipmap-xxhdpi/common_gold_ic_5.webp',
                        width: 15,
                        height: 15,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${item.price}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFAE9B5),
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
  }

  /// شريط الشراء السفلي المطابق لـ cl_buy في mine_activity_mall.xml
  Widget _buildBottomBar(UserProvider userProvider, dynamic user) {
    final selected = _selectedItem;
    final isOwned = selected != null && _isItemOwned(selected, userProvider);
    final isEquipped = selected != null && _isItemEquipped(selected, user);

    return Container(
      color: const Color(0xFF302218), // color_FF302218
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // رصيد الكويزات tv_gold_coin مع أيقونة common_gold_ic_1
          Image.asset(
            'assets/mipmap-xxhdpi/common_gold_ic_1.webp',
            width: 26,
            height: 26,
          ),
          const SizedBox(width: 7),
          Text(
            '${user?.coins ?? 0}',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFAE9B5),
            ),
          ),
          const Spacer(),

          // زر الشراء أو الارتداء tv_buy
          if (selected != null)
            GestureDetector(
              onTap: () async {
                if (isOwned) {
                  // إذا كان مملوكاً -> ارتداء أو إلغاء الارتداء
                  if (isEquipped) {
                    await userProvider.unequipItem(selected.category);
                  } else {
                    await userProvider.equipItem(selected.itemId, selected.category);
                  }
                  if (mounted) setState(() {});
                } else {
                  // إذا لم يكن مملوكاً -> فتح نافذة الشراء
                  _showBuyConfirmDialog(selected, userProvider);
                }
              },
              child: Container(
                width: 126,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/mipmap-xxhdpi/mine_mall_buy_ic.webp'),
                    fit: BoxFit.fill,
                  ),
                ),
                child: Text(
                  isOwned
                      ? (isEquipped ? 'إلغاء الارتداء' : 'ارتداء')
                      : 'شراء',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            Image.asset(
              'assets/mipmap-xxhdpi/mine_mall_buy_ic.webp',
              width: 126,
              height: 40,
              fit: BoxFit.contain,
            ),
        ],
      ),
    );
  }
}
