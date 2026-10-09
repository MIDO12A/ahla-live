import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import '../../../config/r.dart';
import '../../../services/dynamic_config_service.dart';
import '../../../services/supabase_service.dart';
import '../../../services/supabase_data_service.dart';
import '../../../services/cloudinary_service.dart';
import '../../../providers/user_provider.dart';
import '../../../models/store_item_model.dart';
import '../../../models/app_asset_model.dart';
import 'svga_player.dart';

class RoomBackgroundBottomSheet extends StatefulWidget {
  final String roomId;
  final String currentBackground;
  
  const RoomBackgroundBottomSheet({
    super.key,
    required this.roomId,
    required this.currentBackground,
  });

  @override
  State<RoomBackgroundBottomSheet> createState() => _RoomBackgroundBottomSheetState();
}

class _RoomBackgroundBottomSheetState extends State<RoomBackgroundBottomSheet>
    with SingleTickerProviderStateMixin {
  final SupabaseService _db = SupabaseService();
  final CloudinaryService _uploadService = CloudinaryService();
  bool _isUploading = false;
  late TabController _tabController;
  List<StoreItemModel> _ownedBackgrounds = [];
  List<AppAssetModel> _adminBackgrounds = [];
  bool _loadingStoreBg = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadOwnedBackgrounds();
    _loadAdminBackgrounds();
  }

  void _loadAdminBackgrounds() async {
    try {
      final assets = await SupabaseDataService().getAppAssets();
      final bgAssets = assets.values
          .where((a) => (a.category == 'roomBg' || a.category == 'room_bg') && a.isActive)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      if (mounted && bgAssets.isNotEmpty) {
        setState(() {
          _adminBackgrounds = bgAssets;
        });
      }
    } catch (_) {}
  }

  void _loadOwnedBackgrounds() async {
    final user = Provider.of<UserProvider>(context, listen: false).currentUser;
    if (user == null) {
      if (mounted) setState(() => _loadingStoreBg = false);
      return;
    }
    try {
      final allItems = await SupabaseDataService().getStoreItems();
      final bgItems = allItems.where((item) =>
          item.category == 'room_bg' ||
          item.category == 'background' ||
          item.category == 'roomBg').toList();

      final owned = bgItems.where((item) =>
          user.ownedItems.contains(item.itemId)).toList();

      if (mounted) {
        setState(() {
          _ownedBackgrounds = owned;
          _loadingStoreBg = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingStoreBg = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _applyBackground(String url) async {
    try {
      await _db.updateRoomBackground(widget.roomId, url);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Localizations.localeOf(context).languageCode == 'ar' ? 'تم تغيير الخلفية بنجاح' : 'Background changed successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Localizations.localeOf(context).languageCode == 'ar' ? 'فشل تغيير الخلفية' : 'Failed to change background')),
        );
      }
    }
  }

  Future<void> _uploadCustomBackground() async {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final price = DynamicConfigService().roomBgPrice;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16151A),
        title: Text(isAr ? 'تأكيد' : 'Confirm', style: const TextStyle(color: Colors.white)),
        content: Text(
          isAr 
            ? 'رفع خلفية مخصصة سيكلفك $price عملة. هل تريد الاستمرار؟' 
            : 'Uploading a custom background will cost you $price coins. Continue?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'إلغاء' : 'Cancel', style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? 'موافق' : 'Confirm', style: const TextStyle(color: Color(0xFFFFE082))),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    final currentUser = Provider.of<UserProvider>(context, listen: false).currentUser;
    if (currentUser == null) return;
    
    if (currentUser.coins < price) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isAr ? 'رصيدك غير كافٍ' : 'Insufficient coins')),
      );
      return;
    }

    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() { _isUploading = true; });

    try {
      // Deduct coins
      if (price > 0) {
        final success = await _db.deductCoins(currentUser.uid, price, 'custom_room_bg');
        if (!success) {
          throw Exception('Failed to deduct coins');
        }
      }
      
      // Upload image
      final url = await _uploadService.uploadImage(File(image.path), publicId: 'room_backgrounds/${widget.roomId}_${DateTime.now().millisecondsSinceEpoch}');
      
      // Apply background
      _applyBackground(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isAr ? 'حدث خطأ أثناء الرفع' : 'Error during upload')),
        );
      }
    } finally {
      if (mounted) setState(() { _isUploading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final dynBackgrounds = DynamicConfigService().getAssetsByCategory('roomBg');
    // Merge both sources and deduplicate by remoteUrl/key
    final seen = <String>{};
    final backgrounds = <AppAssetModel>[];
    for (final b in [...dynBackgrounds, ..._adminBackgrounds]) {
      final key = b.remoteUrl ?? b.key;
      if (key.isNotEmpty && seen.add(key)) {
        backgrounds.add(b);
      }
    }
    final price = DynamicConfigService().roomBgPrice;

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: Color(0xFF16151A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isAr ? 'خلفية الغرفة' : 'Room Background',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: R.loadAssetOr(
                      '',
                      R.commonCloseIc2,
                      width: 22,
                      height: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Custom Upload Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: InkWell(
              onTap: _isUploading ? null : _uploadCustomBackground,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF23222A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFE082).withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isUploading)
                      const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFE082)),
                      )
                    else ...[
                      const Icon(Icons.photo_library, color: Color(0xFFFFE082), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        isAr ? 'إضافة خلفية من الجهاز' : 'Upload from Device',
                        style: const TextStyle(color: Color(0xFFFFE082), fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      if (price > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Image.asset('assets/images/coin.png', width: 12, height: 12),
                              const SizedBox(width: 4),
                              Text(
                                price.toString(),
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Tabs: Purchased vs Public
          Container(
            height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(18),
            ),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: const Color(0xFFDE880F),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              tabs: [
                Tab(text: isAr ? 'خلفياتي المملوكة (${_ownedBackgrounds.length})' : 'My Items (${_ownedBackgrounds.length})'),
                Tab(text: isAr ? 'الخلفيات العامة' : 'Public Backgrounds'),
              ],
            ),
          ),
          
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 1. Owned Store Backgrounds
                _loadingStoreBg
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFE082)))
                    : _ownedBackgrounds.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                isAr
                                    ? 'لا توجد لديك خلفيات مشتراة حالياً\nيمكنك شراء خلفيات مميزة من المتجر'
                                    : 'No purchased backgrounds yet\nGet exclusive backgrounds from the Store',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
                              ),
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 0.7,
                            ),
                            itemCount: _ownedBackgrounds.length,
                            itemBuilder: (context, index) {
                              final item = _ownedBackgrounds[index];
                              final assetUrl = (item.svgaAsset != null && item.svgaAsset!.isNotEmpty)
                                  ? item.svgaAsset!
                                  : item.iconAsset;
                              final isSelected = widget.currentBackground == assetUrl;

                              return GestureDetector(
                                onTap: () => _applyBackground(assetUrl),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFFFFE082) : Colors.white10,
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Builder(
                                          builder: (_) {
                                            if (assetUrl.isEmpty) return Container(color: Colors.black26);
                                            if (detectAssetType(assetUrl) == AssetType.svga) {
                                              return SvgaPlayer(assetPath: assetUrl, fit: BoxFit.cover, loops: true);
                                            }
                                            return Image.network(assetUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.black26));
                                          },
                                        ),
                                        Positioned(
                                          bottom: 0,
                                          left: 0,
                                          right: 0,
                                          child: Container(
                                            color: Colors.black54,
                                            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                                            child: Text(
                                              item.name,
                                              style: const TextStyle(color: Colors.white, fontSize: 10),
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          Container(
                                            color: Colors.black45,
                                            child: const Center(
                                              child: Icon(Icons.check_circle, color: Color(0xFFFFE082), size: 30),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                // 2. Admin Backgrounds List
                backgrounds.isEmpty
                    ? Center(
                        child: Text(
                          isAr ? 'لا توجد خلفيات مجانية متاحة' : 'No free backgrounds available',
                          style: const TextStyle(color: Colors.white54),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.7,
                        ),
                        itemCount: backgrounds.length,
                        itemBuilder: (context, index) {
                          final bg = backgrounds[index];
                          final isSelected = widget.currentBackground == bg.remoteUrl;
                          
                          return GestureDetector(
                            onTap: () => _applyBackground(bg.remoteUrl ?? ''),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFFFFE082) : Colors.white10,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Builder(
                                      builder: (_) {
                                        final url = bg.remoteUrl ?? '';
                                        if (url.isEmpty) return Container(color: Colors.black26);
                                        if (detectAssetType(url) == AssetType.svga) {
                                          return SvgaPlayer(assetPath: url, fit: BoxFit.cover, loops: true);
                                        }
                                        return Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.black26));
                                      },
                                    ),
                                    if (isSelected)
                                      Container(
                                        color: Colors.black45,
                                        child: const Center(
                                          child: Icon(Icons.check_circle, color: Color(0xFFFFE082), size: 30),
                                        ),
                                      ),
                                  ],
                                ),
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
}
