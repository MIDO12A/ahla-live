import 'package:flutter/material.dart';
import '../../../core/supabase_compat.dart';
import '../../../core/ui/in_app_toast.dart';
import '../../../models/store_item_model.dart';
import '../../../models/user_model.dart';
import '../../../services/supabase_data_service.dart';
import '../../../services/supabase_service.dart';

class StoreGiftDialog extends StatefulWidget {
  final UserModel currentUser;

  const StoreGiftDialog({
    super.key,
    required this.currentUser,
  });

  static Future<void> show(BuildContext context, {required UserModel currentUser}) {
    return showDialog(
      context: context,
      builder: (_) => StoreGiftDialog(currentUser: currentUser),
    );
  }

  @override
  State<StoreGiftDialog> createState() => _StoreGiftDialogState();
}

class _StoreGiftDialogState extends State<StoreGiftDialog> {
  final _sb = Supabase.instance.client;
  final _userIdController = TextEditingController();

  bool _searchingUser = false;
  Map<String, dynamic>? _targetUser;
  String? _userSearchError;

  bool _loadingItems = true;
  List<StoreItemModel> _storeItems = [];
  String _selectedCategory = 'all';
  StoreItemModel? _selectedItem;
  bool _gifting = false;

  @override
  void initState() {
    super.initState();
    _fetchStoreItems();
  }

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  Future<void> _fetchStoreItems() async {
    setState(() => _loadingItems = true);
    try {
      final items = await FirebaseService().getStoreItems();
      if (mounted) {
        setState(() {
          _storeItems = items;
          _loadingItems = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  Future<void> _searchUser() async {
    final query = _userIdController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _userSearchError = 'يرجى إدخال معرف المستخدم';
        _targetUser = null;
      });
      return;
    }

    setState(() {
      _searchingUser = true;
      _userSearchError = null;
    });

    try {
      final res = await _sb
          .from('users')
          .select('uid, id, custom_id, name, photo_url, owned_items, owned_necklaces, owned_badges')
          .or('custom_id.eq.$query,uid.eq.$query,id.eq.$query')
          .maybeSingle();

      if (res == null) {
        setState(() {
          _userSearchError = 'لم يتم العثور على مستخدم بهذا المعرف';
          _targetUser = null;
        });
      } else {
        setState(() {
          _targetUser = res;
          _userSearchError = null;
        });
      }
    } catch (e) {
      setState(() {
        _userSearchError = 'خطأ أثناء البحث: $e';
        _targetUser = null;
      });
    } finally {
      if (mounted) setState(() => _searchingUser = false);
    }
  }

  Future<void> _submitGift() async {
    if (_targetUser == null) {
      KayanInAppToast.warning('يرجى تحديد المستخدم أولاً');
      return;
    }
    if (_selectedItem == null) {
      KayanInAppToast.warning('يرجى اختيار العنصر المراد إهداؤه');
      return;
    }

    setState(() => _gifting = true);

    try {
      final targetUid = _targetUser!['uid']?.toString() ?? _targetUser!['id']?.toString() ?? '';
      final itemId = _selectedItem!.itemId;
      final itemName = _selectedItem!.name;

      // 1. Fetch target user current owned items
      final userRow = await _sb
          .from('users')
          .select('owned_items, owned_necklaces, owned_badges')
          .eq('uid', targetUid)
          .maybeSingle();

      List<dynamic> ownedItems = (userRow?['owned_items'] as List?) ?? [];
      List<dynamic> ownedNecklaces = (userRow?['owned_necklaces'] as List?) ?? [];
      List<dynamic> ownedBadges = (userRow?['owned_badges'] as List?) ?? [];

      final updateMap = <String, dynamic>{};
      if (_selectedItem!.category == 'necklace') {
        if (!ownedNecklaces.contains(itemId)) ownedNecklaces.add(itemId);
        updateMap['owned_necklaces'] = ownedNecklaces;
      } else if (_selectedItem!.category == 'badge') {
        if (!ownedBadges.contains(itemId)) ownedBadges.add(itemId);
        updateMap['owned_badges'] = ownedBadges;
      } else {
        if (!ownedItems.contains(itemId)) ownedItems.add(itemId);
        updateMap['owned_items'] = ownedItems;
      }

      await _sb.from('users').update(updateMap).eq('uid', targetUid);

      // 2. Send in-app notification to the recipient
      await SupabaseDataService().sendNotification(
        uid: targetUid,
        type: 'gift_from_admin',
        actorUid: widget.currentUser.uid,
        title: 'إهداء خاص من الإدارة 🎁',
        body: 'لقد استلمت إهداء مميز من إدارة التطبيق: $itemName',
        data: {
          'item_id': itemId,
          'item_name': itemName,
          'item_category': _selectedItem!.category,
          'sender_name': widget.currentUser.name,
        },
      );

      if (mounted) {
        KayanInAppToast.success('تم إرسال الإهداء بنجاح إلى ${_targetUser!['name']} 🎉');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        KayanInAppToast.error('فشل إرسال الإهداء: $e');
      }
    } finally {
      if (mounted) setState(() => _gifting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = _selectedCategory == 'all'
        ? _storeItems
        : _storeItems.where((it) => it.category == _selectedCategory).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 680),
        decoration: BoxDecoration(
          color: const Color(0xFF141A32),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF9C6BFF).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.card_giftcard_rounded, color: Color(0xFF9C6BFF), size: 22),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'إرسال إهداء من المتجر',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(color: Color(0x22FFFFFF), height: 1),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Search User
                    const Text(
                      'المستلم (معرف المستخدم ID)',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _userIdController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'أدخل معرف المستخدم المراد إهداؤه',
                              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                              filled: true,
                              fillColor: const Color(0xFF0A0E21),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onSubmitted: (_) => _searchUser(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _searchingUser ? null : _searchUser,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6C63FF),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          child: _searchingUser
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('بحث', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),

                    if (_userSearchError != null) ...[
                      const SizedBox(height: 6),
                      Text(_userSearchError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                    ],

                    if (_targetUser != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5A0).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF00E5A0).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundImage: _targetUser!['photo_url'] != null &&
                                      _targetUser!['photo_url'].toString().isNotEmpty
                                  ? NetworkImage(_targetUser!['photo_url'])
                                  : null,
                              child: _targetUser!['photo_url'] == null ||
                                      _targetUser!['photo_url'].toString().isEmpty
                                  ? const Icon(Icons.person, color: Colors.white, size: 18)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _targetUser!['name'] ?? 'مستخدم',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    'ID: ${_targetUser!['custom_id'] ?? _targetUser!['uid']}',
                                    style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.check_circle_rounded, color: Color(0xFF00E5A0), size: 20),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 18),

                    // Category Filter Pills
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('الكل', 'all'),
                          _buildFilterChip('إطارات', 'frame'),
                          _buildFilterChip('فقاعات', 'bubble'),
                          _buildFilterChip('دخول وسيارات', 'entrance'),
                          _buildFilterChip('قلادات', 'necklace'),
                          _buildFilterChip('شارات', 'badge'),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Items Grid
                    if (_loadingItems)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(30.0),
                          child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
                        ),
                      )
                    else if (filteredItems.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(30.0),
                          child: Text('لا توجد عناصر متاحة في هذا القسم', style: TextStyle(color: Colors.white38)),
                        ),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: filteredItems.length,
                        itemBuilder: (_, index) {
                          final item = filteredItems[index];
                          final isSelected = _selectedItem?.itemId == item.itemId;

                          return GestureDetector(
                            onTap: () => setState(() => _selectedItem = item),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF6C63FF).withValues(alpha: 0.25)
                                    : const Color(0xFF0A0E21),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFFFFB800) : Colors.white.withValues(alpha: 0.08),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: item.iconAsset.startsWith('http')
                                          ? Image.network(item.iconAsset, fit: BoxFit.contain)
                                          : Image.asset(item.iconAsset, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.image, color: Colors.white38)),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                    child: Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isSelected ? const Color(0xFFFFB800) : Colors.white,
                                        fontSize: 11,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),

            const Divider(color: Color(0x22FFFFFF), height: 1),

            // Bottom Actions
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء', style: TextStyle(color: Colors.white60)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: (_targetUser == null || _selectedItem == null || _gifting) ? null : _submitGift,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _gifting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'إرسال الإهداء 🎁',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
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

  Widget _buildFilterChip(String label, String category) {
    final isSelected = _selectedCategory == category;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = category),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C63FF) : const Color(0xFF0A0E21),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF6C63FF) : Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF8E9BB0),
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
