import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../services/dynamic_config_service.dart';
import '../../services/supabase_service.dart';
import '../../models/store_item_model.dart';
import '../../providers/user_provider.dart';
import '../room/widgets/svga_player.dart';
import '../room/widgets/vap_player.dart';

class MallScreen extends StatefulWidget {
  const MallScreen({super.key});

  @override
  State<MallScreen> createState() => _MallScreenState();
}

class _MallScreenState extends State<MallScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SupabaseService _firebaseService = SupabaseService();
  List<StoreItemModel> _allItems = [];
  StoreItemModel? _previewItem;
  StoreItemModel? _selectedItem;

  static const _categories = ['car', 'bubble', 'entrance', 'frame', 'cover'];
  static const _categoryNames = ['السيارات', 'الفقاعات', 'المخرجات', 'الاطارات', 'غلاف المستخدم'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openPreview(StoreItemModel item) {
    setState(() => _previewItem = item);
  }

  void _closePreview() {
    setState(() => _previewItem = null);
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.currentUser;
    final dc = DynamicConfigService();

    return ListenableBuilder(
      listenable: dc,
      builder: (context, _) {
        final dc = DynamicConfigService();
        return StreamBuilder<List<StoreItemModel>>(
          stream: _firebaseService.storeItemsStream(),
          builder: (context, snapshot) {
            _allItems = snapshot.data ?? [];
            if (_selectedItem == null && _allItems.isNotEmpty) {
              _selectedItem = _allItems.first;
            }

            final categoryItems = _categories.map((cat) =>
              _allItems.where((item) => !item.isHidden && item.category == cat).toList()
            ).toList();

            return Scaffold(
              backgroundColor: dc.primaryBg,
              body: Stack(
                children: [
                  Positioned.fill(
                    child: R.loadAsset(
                      dc.storeBackgroundImage.isNotEmpty
                          ? dc.storeBackgroundImage
                          : 'assets/mipmap-xxhdpi/mine_mall_top_bg.webp',
                      fit: BoxFit.cover,
                    ),
                  ),
                  Column(
                    children: [
                      SafeArea(
                        child: Stack(
                          children: [
                            if (dc.storeHeaderBgImage.isNotEmpty)
                              Positioned.fill(
                                child: R.loadAsset(dc.storeHeaderBgImage, fit: BoxFit.cover),
                              ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => Navigator.pop(context),
                                    child: R.image(
                                      'assets/mipmap-xxhdpi/back_white.webp',
                                      width: 24,
                                      height: 24,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    dc.screenTitles['store'] ?? 'المتجر',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: dc.storeHeaderTextColor,
                                    ),
                                  ),
                                  const Spacer(),
                                  const SizedBox(width: 40),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        color: dc.storeSectionBgImage.isNotEmpty ? null : dc.tabBarColor,
                        decoration: dc.storeSectionBgImage.isNotEmpty
                            ? BoxDecoration(image: DecorationImage(image: R.cachedImage(dc.storeSectionBgImage), fit: BoxFit.cover))
                            : null,
                        child: TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          labelColor: dc.goldColor,
                          unselectedLabelColor: dc.textSecondary,
                          indicatorColor: dc.goldColor,
                          indicatorWeight: 3,
                          labelStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          tabs: _categoryNames.map((name) =>
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Tab(text: name),
                            )
                          ).toList(),
                        ),
                      ),
                      Divider(height: 1, color: dc.textSecondary.withValues(alpha: 0.2)),
                      // cl_preview matching mine_activity_mall.xml
                      Container(
                        height: 140,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Center(
                          child: _buildClPreview(dc, _selectedItem, user),
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: categoryItems.map((items) =>
                            _buildItemsTab(items, userProvider)
                          ).toList(),
                        ),
                      ),
                      Container(
                        color: const Color(0xFF302218), // color_FF302218 from mine_activity_mall.xml
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            R.image(
                              dc.storeLockImage.isNotEmpty
                                  ? dc.storeLockImage
                                  : 'assets/mipmap-xxhdpi/common_gold_ic_1.webp',
                              width: 28,
                              height: 28,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              user?.coins.toString() ?? '0',
                              style: TextStyle(
                                fontSize: 17,
                                color: dc.goldColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            if (_selectedItem != null)
                              _buildBottomActionButton(userProvider, dc, _selectedItem!, user)
                            else
                              R.image(
                                'assets/mipmap-xxhdpi/mine_mall_buy_ic.webp',
                                width: 126,
                                height: 40,
                                fit: BoxFit.contain,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_previewItem != null)
                    Positioned.fill(
                      child: _buildPreviewOverlay(dc, _previewItem!, user),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPreviewOverlay(DynamicConfigService dc, StoreItemModel item, dynamic user) {
    return GestureDetector(
      onTap: _closePreview,
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
                  constraints: const BoxConstraints(maxHeight: 480),
                  decoration: BoxDecoration(
                    color: dc.storeCardBgColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: dc.storeAccentColor.withValues(alpha: 0.3)),
                    image: dc.storeCardBorderImage.isNotEmpty
                        ? DecorationImage(image: R.cachedImage(dc.storeCardBorderImage), fit: BoxFit.cover)
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        children: [
                          Container(
                            height: 260,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: dc.storeAccentImage.isNotEmpty ? null : dc.storeAccentColor.withValues(alpha: 0.1),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                              image: dc.storeAccentImage.isNotEmpty
                                  ? DecorationImage(image: R.cachedImage(dc.storeAccentImage), fit: BoxFit.cover)
                                  : dc.storeCardBgImage.isNotEmpty
                                      ? DecorationImage(image: R.cachedImage(dc.storeCardBgImage), fit: BoxFit.cover)
                                      : null,
                            ),
                            child: Center(
                              child: _buildPreviewContent(dc, item, user),
                            ),
                          ),
                          Positioned(
                            top: 8, right: 8,
                            child: GestureDetector(
                              onTap: _closePreview,
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
                        child: dc.storeTextImage.isNotEmpty
                            ? R.loadAsset(dc.storeTextImage, width: 24, height: 24)
                            : Text(
                                item.name,
                                style: TextStyle(color: dc.storeTextColor, fontSize: 16, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: dc.storeSubTextImage.isNotEmpty
                            ? R.loadAsset(dc.storeSubTextImage, width: 20, height: 20)
                            : Text(
                                _previewSubtitle(item.category),
                                style: TextStyle(color: dc.storeSubTextColor, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildPreviewContent(DynamicConfigService dc, StoreItemModel item, dynamic user) {
    switch (item.category) {
      case 'frame':
        final photoUrl = user?.photoUrl?.isNotEmpty == true ? user.photoUrl : null;
        final animUrl = item.animationUrl;
        if (animUrl != null && animUrl.isNotEmpty) {
          if (animUrl.endsWith('.mp4') || animUrl.endsWith('.vap')) {
            return VapPlayer(url: animUrl, width: 200, height: 200, fit: BoxFit.contain);
          }
          return SvgaPlayer(
            assetPath: animUrl,
            width: 200,
            height: 200,
            fit: BoxFit.contain,
            imageReplacement: photoUrl != null ? {item.photoKey ?? 'photo': photoUrl} : null,
            defaultImageUrl: item.defaultImage,
          );
        }
        return Stack(
          alignment: Alignment.center,
          children: [
            CircleAvatar(
              radius: 85,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              backgroundImage: photoUrl != null ? R.cachedImage(photoUrl) : null,
              child: photoUrl == null
                  ? Icon(Icons.person, size: 80, color: Colors.white.withValues(alpha: 0.5))
                  : null,
            ),
            R.loadImage(item.iconAsset, width: 170, height: 170, fit: BoxFit.contain),
          ],
        );
      case 'entrance':
        final userName = user?.name ?? '';
        final animUrl = item.animationUrl;
        if (animUrl != null && animUrl.isNotEmpty) {
          if (animUrl.endsWith('.mp4') || animUrl.endsWith('.vap')) {
            return VapPlayer(url: animUrl, width: 160, height: 160, fit: BoxFit.contain);
          }
          return SvgaPlayer(
            assetPath: animUrl,
            width: 160,
            height: 160,
            fit: BoxFit.contain,
            textReplacement: userName.isNotEmpty ? {item.nameKey ?? 'name': userName} : null,
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            R.loadImage(item.iconAsset, width: 120, height: 120, fit: BoxFit.contain),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                userName.isNotEmpty ? userName : 'اسم المستخدم',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      case 'cover':
        final photoUrl = user?.photoUrl?.isNotEmpty == true ? user.photoUrl : null;
        final animUrl = item.animationUrl;
        if (animUrl != null && animUrl.isNotEmpty) {
          if (animUrl.endsWith('.mp4') || animUrl.endsWith('.vap')) {
            return VapPlayer(url: animUrl, width: 200, height: 200, fit: BoxFit.contain);
          }
          return SvgaPlayer(
            assetPath: animUrl,
            width: 200,
            height: 200,
            fit: BoxFit.contain,
            imageReplacement: photoUrl != null ? {item.photoKey ?? 'photo': photoUrl} : null,
            defaultImageUrl: item.defaultImage,
          );
        }
        return Stack(
          alignment: Alignment.center,
          children: [
            CircleAvatar(
              radius: 85,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              backgroundImage: photoUrl != null ? R.cachedImage(photoUrl) : null,
              child: photoUrl == null
                  ? Icon(Icons.person, size: 80, color: Colors.white.withValues(alpha: 0.5))
                  : null,
            ),
            R.loadImage(item.iconAsset, width: 170, height: 170, fit: BoxFit.contain),
          ],
        );
      default:
        final animUrl = item.animationUrl;
        if (animUrl != null && animUrl.isNotEmpty) {
          if (animUrl.endsWith('.mp4') || animUrl.endsWith('.vap')) {
            return VapPlayer(url: animUrl, width: 150, height: 150, fit: BoxFit.contain);
          }
          return SvgaPlayer(
            assetPath: animUrl,
            width: 150,
            height: 150,
            fit: BoxFit.contain,
          );
        }
        return R.loadImage(item.iconAsset, width: 150, height: 150, fit: BoxFit.contain);
    }
  }

  String _previewSubtitle(String category) {
    switch (category) {
      case 'frame': return 'معاينة الإطار على الصورة الشخصية';
      case 'entrance': return 'معاينة المخرج مع اسم المستخدم';
      case 'bubble': return 'معاينة الفقاعة';
      case 'car': return 'معاينة السيارة';
      case 'cover': return 'معاينة الغلاف';
      default: return 'معاينة';
    }
  }

  BoxDecoration _cardDecoration(DynamicConfigService dc, {Color? color, String? imageUrl, double radius = 12, Color? borderColor, double borderWidth = 1}) {
    final bgColor = color ?? dc.storeCardBgColor;
    final bgImage = imageUrl ?? dc.storeCardBgImage;
    final borderImg = dc.storeCardBorderImage;
    return BoxDecoration(
      color: bgImage.isNotEmpty || borderImg.isNotEmpty ? null : bgColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? dc.storeCardBorderColor.withValues(alpha: 0.1), width: borderWidth),
      image: bgImage.isNotEmpty
          ? DecorationImage(image: R.cachedImage(bgImage), fit: BoxFit.cover)
          : borderImg.isNotEmpty
              ? DecorationImage(image: R.cachedImage(borderImg), fit: BoxFit.cover)
              : null,
    );
  }

  Widget _buildItemsTab(List<StoreItemModel> items, UserProvider userProvider) {
    final dc = DynamicConfigService();
    if (items.isEmpty) {
      return Center(
        child: Text('لا توجد عناصر بعد', style: TextStyle(color: dc.textSecondary)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
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
          final isOwned = userProvider.currentUser?.ownedItems.contains(item.itemId) ?? false;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedItem = item);
            },
            onDoubleTap: () => _openPreview(item),
            child: Container(
              decoration: _cardDecoration(
                dc,
                borderColor: isSelected ? const Color(0xFFFFD700) : null,
                borderWidth: isSelected ? 2.0 : 1.0,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: R.loadImage(item.iconAsset, fit: BoxFit.contain),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: dc.storeTextImage.isNotEmpty
                      ? R.loadAsset(dc.storeTextImage, width: 16, height: 16)
                      : Text(
                          item.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: dc.storeTextColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  ),
                  const SizedBox(height: 4),
                  if (!isOwned) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        R.image(
                          dc.storeLockImage.isNotEmpty
                              ? dc.storeLockImage
                              : 'assets/mipmap-xxhdpi/common_gold_ic_1.webp',
                          width: 14,
                          height: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.price.toString(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: dc.buttonColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        final success = await userProvider.purchaseItem(item);
                        if (success) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(dc.getScreenTitle('purchase_success', 'تم الشراء بنجاح!'))),
                            );
                            setState(() {});
                          }
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(dc.getScreenTitle('insufficient_coins', 'لا توجد عملات كافية!'))),
                            );
                          }
                        }
                      },
                      child: Container(
                        width: 100,
                        height: 32,
                        decoration: const BoxDecoration(
                          image: DecorationImage(
                            image: AssetImage('assets/mipmap-xxhdpi/mine_mall_buy_ic.webp'),
                            fit: BoxFit.fill,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            dc.getScreenTitle('buy', 'شراء'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    Text(
                      dc.getScreenTitle('owned', 'مملوك'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildClPreview(DynamicConfigService dc, StoreItemModel? item, dynamic user) {
    final photoUrl = user?.photoUrl?.isNotEmpty == true ? user.photoUrl : null;
    if (item == null) {
      return Container(
        width: 120,
        height: 120,
        alignment: Alignment.center,
        child: CircleAvatar(
          radius: 46,
          backgroundColor: Colors.white12,
          backgroundImage: photoUrl != null ? R.cachedImage(photoUrl) : null,
          child: photoUrl == null ? const Icon(Icons.person, size: 46, color: Colors.white54) : null,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 130,
          height: 110,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // iv_avatar (96x96 circle)
              CircleAvatar(
                radius: 44,
                backgroundColor: Colors.white12,
                backgroundImage: photoUrl != null ? R.cachedImage(photoUrl) : null,
                child: photoUrl == null ? const Icon(Icons.person, size: 44, color: Colors.white54) : null,
              ),
              // Live frame / car / entrance / bubble overlay (cl_preview)
              if (item.category == 'frame') ...[
                if (item.animationUrl?.isNotEmpty == true)
                  SvgaPlayer(
                    assetPath: item.animationUrl!,
                    width: 130,
                    height: 130,
                    fit: BoxFit.contain,
                  )
                else if (item.iconAsset.isNotEmpty)
                  R.loadImage(item.iconAsset, width: 120, height: 120, fit: BoxFit.contain),
              ] else if (item.category == 'bubble') ...[
                Positioned(
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0x33000000),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0x66FFD700)),
                    ),
                    child: const Text('مرحباً!', style: TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ),
              ] else ...[
                if (item.animationUrl?.isNotEmpty == true)
                  SvgaPlayer(
                    assetPath: item.animationUrl!,
                    width: 130,
                    height: 110,
                    fit: BoxFit.contain,
                  )
                else
                  R.loadImage(item.iconAsset, width: 90, height: 90, fit: BoxFit.contain),
              ],
            ],
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.name,
              style: TextStyle(
                color: dc.goldColor,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            R.image('assets/mipmap-xxhdpi/common_gold_ic_1.webp', width: 14, height: 14),
            const SizedBox(width: 4),
            Text(
              '${item.price}',
              style: const TextStyle(color: Color(0xFFFFEB3B), fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomActionButton(UserProvider userProvider, DynamicConfigService dc, StoreItemModel item, dynamic user) {
    final isOwned = userProvider.currentUser?.ownedItems.contains(item.itemId) ?? false;
    final isEquipped = (item.category == 'frame' && user?.activeFrame == item.itemId) ||
        (item.category == 'bubble' && user?.activeBubble == item.itemId) ||
        (item.category == 'car' && user?.activeCar == item.itemId) ||
        (item.category == 'entrance' && user?.activeEntrance == item.itemId);

    if (isOwned) {
      return GestureDetector(
        onTap: () async {
          if (isEquipped) {
            await userProvider.unequipItem(item.category);
          } else {
            await userProvider.equipItem(item.itemId, item.category);
          }
          if (mounted) setState(() {});
        },
        child: Container(
          width: 126,
          height: 40,
          decoration: BoxDecoration(
            color: isEquipped ? const Color(0x33FFFFFF) : const Color(0xFFD98B2B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFFD700), width: 1),
          ),
          child: Center(
            child: Text(
              isEquipped ? 'مُرتدى' : 'ارتداء',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () async {
        final success = await userProvider.purchaseItem(item);
        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(dc.getScreenTitle('purchase_success', 'تم الشراء بنجاح!'))),
            );
            setState(() {});
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(dc.getScreenTitle('insufficient_coins', 'لا توجد عملات كافية!'))),
            );
          }
        }
      },
      child: Container(
        width: 126,
        height: 40,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/mipmap-xxhdpi/mine_mall_buy_ic.webp'),
            fit: BoxFit.fill,
          ),
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${item.price} ',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                dc.getScreenTitle('buy', 'شراء'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
