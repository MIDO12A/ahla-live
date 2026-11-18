import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../models/store_item_model.dart';
import '../../models/gifted_item_model.dart';
import '../../providers/user_provider.dart';
import '../../models/user_model.dart';
import '../../services/supabase_service.dart';
import '../mall/mall_screen.dart';
import '../room/widgets/svga_player.dart';
import '../room/widgets/vap_player.dart';
import 'package:zero/core/dtext.dart';

class BackpackScreen extends StatefulWidget {
  const BackpackScreen({super.key});

  @override
  State<BackpackScreen> createState() => _BackpackScreenState();
}

class _BackpackScreenState extends State<BackpackScreen> {
  final SupabaseService _firebaseService = SupabaseService();

  // التصنيفات الأصلية من PackageActivity.java
  // تم حذف تبويب "الهدايا" بناءً على طلب المستخدم
  static const List<Map<String, String>> _categories = [
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
      'name': 'مؤثرات الدخول',
      'nor_ic': 'assets/mipmap-xxhdpi/mine_mall_type_entrance_nor_ic.webp',
      'pre_ic': 'assets/mipmap-xxhdpi/mine_mall_type_entrance_pre_ic.webp',
    },
    {
      'key': 'car',
      'name': 'المركبة',
      'nor_ic': 'assets/mipmap-xxhdpi/mine_mall_type_car_nor_ic.webp',
      'pre_ic': 'assets/mipmap-xxhdpi/mine_mall_type_car_pre_ic.webp',
    },
    {
      'key': 'cover',
      'name': 'غلاف الملف',
      'nor_ic': 'assets/mipmap-xxhdpi/ic_profile_card.png',
      'pre_ic': 'assets/mipmap-xxhdpi/ic_profile_card.png',
    },
    {
      'key': 'ring',
      'name': 'الخواتم',
      'nor_ic': 'assets/mipmap-xxhdpi/ic_id_card_prop.png',
      'pre_ic': 'assets/mipmap-xxhdpi/ic_id_card_prop.png',
    },
    {
      'key': 'special',
      'name': 'المؤثرات',
      'nor_ic': 'assets/mipmap-xxhdpi/mine_mall_tab_vip_ic.webp',
      'pre_ic': 'assets/mipmap-xxhdpi/mine_mall_tab_vip_ic.webp',
    },
    {
      'key': 'mic_wave',
      'name': 'موجات المايك',
      'nor_ic': 'assets/mipmap-xxhdpi/room_mic_on.webp',
      'pre_ic': 'assets/mipmap-xxhdpi/room_mic_on.webp',
    },
    {
      'key': 'special_id',
      'name': 'الآيديهات المميزة',
      'nor_ic': 'assets/mipmap-xxhdpi/common_user_id_ic.webp',
      'pre_ic': 'assets/mipmap-xxhdpi/common_user_id_ic.webp',
    },
  ];

  int _selectedCategoryIndex = 0;
  StoreItemModel? _selectedItem;
  StoreItemModel? _previewItem;

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF16151A),
      body: Stack(
        children: [
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
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildTopBar(context),
                _buildCategoryTabs(),
                const SizedBox(height: 12),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        top: 15,
                        child: Container(
                          color: const Color(0xFF16151A),
                        ),
                      ),
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
                      Positioned.fill(
                        top: 20,
                        child: _buildMainContent(userProvider, user),
                      ),
                    ],
                  ),
                ),
                _buildBottomBar(userProvider, user),
              ],
            ),
          ),
          if (_previewItem != null)
            _buildFullscreenAnimationOverlay(user),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
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
          const DText(
            'الحقيبة',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
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
                  const DText(
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
                      DText(
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

  Widget _buildMainContent(UserProvider userProvider, dynamic user) {
    final currentCat = _categories[_selectedCategoryIndex]['key']!;
    return _buildCategoryItems(userProvider, user, currentCat);
  }

  Widget _buildCategoryItems(UserProvider userProvider, dynamic user, String category) {
    final uid = user?.uid ?? '';
    return StreamBuilder<List<GiftedItemModel>>(
      stream: uid.isNotEmpty ? _firebaseService.userGiftedItemsStream(uid) : const Stream.empty(),
      builder: (context, giftedSnap) {
        final giftedItems = giftedSnap.data ?? [];
        final giftMap = <String, GiftedItemModel>{};
        for (final gi in giftedItems) {
          if (!gi.isExpired) {
            giftMap[gi.itemId] = gi;
          }
        }

        return StreamBuilder<List<StoreItemModel>>(
          stream: _firebaseService.storeItemsStream(),
          builder: (context, snapshot) {
            final allItems = snapshot.data ?? [];
            final userOwnedIds = user?.ownedItems ?? [];

            // 1. العناصر المشتراة من المتجر
            final catLower = category.toLowerCase();
            final storeItems = allItems
                .where((item) {
              final iCat = item.category.toLowerCase();
              final matchesCat = iCat == catLower ||
                  (catLower == 'entrance' && (iCat == 'entrance_effects' || iCat == 'entrance_effect' || iCat.contains('دخول'))) ||
                  (catLower == 'car' && (iCat == 'cars' || iCat == 'vehicle' || iCat.contains('مركب') || iCat.contains('سيار')));
              return matchesCat && userOwnedIds.contains(item.itemId);
            })
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
                .where((m) {
              final t = (m['type'] ?? '').toString().toLowerCase();
              return t == catLower ||
                  (catLower == 'frame' && t == 'headwear') ||
                  (catLower == 'car' && t == 'cars') ||
                  (catLower == 'entrance' && t.contains('entrance'));
            })
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

            if (displayItems.isNotEmpty && _selectedItem == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _selectedItem == null) {
                  setState(() => _selectedItem = displayItems.first);
                }
              });
            }

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
                                    child: const DText(
                                      'قيد الاستخدام',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
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
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: DText(
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
                        Builder(builder: (_) {
                          final gifted = giftMap[item.itemId];
                          String durationText = 'دائم';
                          if (gifted != null && gifted.expiresAt > 0) {
                            final remainingMs = gifted.expiresAt - DateTime.now().millisecondsSinceEpoch;
                            if (remainingMs > 0) {
                              final days = (remainingMs / (1000 * 60 * 60 * 24)).ceil();
                              if (days > 1) {
                                durationText = '$days يوم';
                              } else {
                                final hours = (remainingMs / (1000 * 60 * 60)).ceil();
                                durationText = hours > 0 ? '$hours ساعة' : 'ينتهي قريباً';
                              }
                            } else {
                              durationText = 'منتهي الصلاحية';
                            }
                          }
                          return Padding(
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
                                DText(
                                  durationText,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF9BA1B6),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/mipmap-xxhdpi/mine_wallet_empty_ic.webp',
            width: 136,
            height: 136,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 10),
          const DText(
            'لا توجد عناصر حالياً في هذا القسم',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF9BA1B6),
            ),
          ),
          const SizedBox(height: 36),
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
              child: const DText(
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

  Widget _buildBottomBar(UserProvider userProvider, dynamic user) {
    final selected = _selectedItem;
    final isEquipped = selected != null && _isItemEquipped(selected, user);

    return Container(
      color: const Color(0xFF302218),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (selected != null)
            DText(
              'العنصر المحدد: ${selected.name}',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFFAE9B5),
                fontWeight: FontWeight.w500,
              ),
            )
          else
            const DText(
              'يرجى تحديد عنصر لارتدائه',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF9BA1B6),
              ),
            ),
          const Spacer(),
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
              child: DText(
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

  Widget _buildFullscreenAnimationOverlay(UserModel? user) {
    final item = _previewItem!;
    final animUrl = (item.videoAsset != null && item.videoAsset!.isNotEmpty)
        ? item.videoAsset!
        : ((item.svgaAsset != null && item.svgaAsset!.isNotEmpty)
        ? item.svgaAsset!
        : (item.animationUrl ?? item.iconAsset));
    final isVideo = item.isVideo || animUrl.toLowerCase().endsWith('.mp4') || animUrl.toLowerCase().endsWith('.vap');
    final photoUrl = (user != null && user.photoUrl.isNotEmpty) ? user.photoUrl : null;
    final userName = user?.name ?? '';

    final imageReplacement = <String, String>{};
    if (photoUrl != null) {
      imageReplacement['avatar'] = photoUrl;
      imageReplacement['user_avatar'] = photoUrl;
      if (item.photoKey != null && item.photoKey!.isNotEmpty) {
        imageReplacement[item.photoKey!] = photoUrl;
      }
    }

    final textReplacement = <String, String>{};
    if (userName.isNotEmpty) {
      textReplacement['name'] = 'مرحباً $userName';
      textReplacement['nickname'] = userName;
      if (item.nameKey != null && item.nameKey!.isNotEmpty) {
        textReplacement[item.nameKey!] = userName;
      }
    }

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.8),
        child: Stack(
          children: [
            Center(
              child: isVideo
                  ? VapPlayer(
                key: ValueKey('preview_vap_${item.itemId}'),
                url: animUrl,
                width: double.infinity,
                height: 380,
                fit: BoxFit.contain,
                loops: true,
                defaultImageUrl: item.iconAsset,
              )
                  : SvgaPlayer(
                key: ValueKey('preview_${item.itemId}'),
                assetPath: animUrl,
                width: double.infinity,
                height: 380,
                fit: BoxFit.contain,
                loops: true,
                defaultImageUrl: item.iconAsset,
                imageReplacement: imageReplacement.isNotEmpty ? imageReplacement : null,
                textReplacement: textReplacement.isNotEmpty ? textReplacement : null,
              ),
            ),
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
                  child: DText(
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
      case 'special_id':
        final cid = item.effectiveCustomId;
        return cid != null && user.customId == cid;
      default:
        return false;
    }
  }
}