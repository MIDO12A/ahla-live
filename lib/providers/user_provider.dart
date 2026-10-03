import '../services/supabase_data_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../models/store_item_model.dart';
import '../models/gifted_item_model.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../services/supabase_auth_service.dart';
import '../core/utils/id_generator.dart';

class UserProvider extends ChangeNotifier {
  UserModel? _currentUser;
  bool _isLoading = false;
  final SupabaseService _supabaseService = SupabaseService();
  StreamSubscription? _userSub;
  StreamSubscription? _giftedSub;
  Timer? _expiryTimer;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;

  void setUser(UserModel user) {
    _currentUser = user;
    notifyListeners();
  }

  void startListening(String uid) {
    _userSub?.cancel();
    _userSub = _supabaseService.userStream(uid).listen((user) {
      _currentUser = _ensureFrame(user);
      notifyListeners();
    });
    _giftedSub?.cancel();
    _giftedSub = _supabaseService.userGiftedItemsStream(uid).listen((items) async {
      await _reconcileGiftedItems(uid, items);
    });
    _expiryTimer?.cancel();
    _expiryTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (_currentUser != null) {
        final items = await _supabaseService.userGiftedItemsStream(_currentUser!.uid).first;
        await _reconcileGiftedItems(_currentUser!.uid, items);
      }
    });
  }

  Future<void> _reconcileGiftedItems(String uid, List<GiftedItemModel> items) async {
    final activeItemIds = <String>{};
    final expiredGiftIds = <String>[];
    for (final gift in items) {
      if (gift.isExpired) {
        expiredGiftIds.add(gift.id);
      } else {
        activeItemIds.add(gift.itemId);
      }
    }
    final user = _currentUser;
    if (user == null) return;
    final currentOwned = Set<String>.from(user.ownedItems);
    final needsUpdate = <String, dynamic>{};
    final newOwned = List<String>.from(currentOwned);

    bool changed = false;
    for (final itemId in activeItemIds) {
      if (!currentOwned.contains(itemId)) {
        newOwned.add(itemId);
        changed = true;
      }
    }

    final expiredItemIds = items.where((g) => g.isExpired).map((g) => g.itemId).toSet();
    for (final itemId in expiredItemIds) {
      if (currentOwned.contains(itemId)) {
        newOwned.remove(itemId);
        changed = true;
        if (user.activeFrame == itemId) needsUpdate['active_frame'] = null;
        if (user.activeHeadwear == itemId) needsUpdate['active_headwear'] = null;
        if (user.activeBubble == itemId) needsUpdate['active_bubble'] = null;
        if (user.activeEntrance == itemId) needsUpdate['active_entrance'] = null;
        if (user.activeCar == itemId) needsUpdate['active_car'] = null;
      }
    }

    if (changed) {
      needsUpdate['owned_items'] = newOwned;
      await _supabaseService.updateUser(uid, needsUpdate);
    }

    for (final giftId in expiredGiftIds) {
      await _supabaseService.removeGiftedItem(giftId);
    }
  }

  UserModel? _ensureFrame(UserModel? user) {
    return user;
  }

  void stopListening() {
    _userSub?.cancel();
    _userSub = null;
    _giftedSub?.cancel();
    _giftedSub = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
  }

  Future<void> loadUser(String uid) async {
    _isLoading = true;
    notifyListeners();
    _currentUser = await _supabaseService.getUser(uid);
    if (_currentUser == null) {
      final supaUser = SupabaseAuthService().currentUser;
      if (supaUser != null && supaUser.uid == uid) {
        _currentUser = UserModel(
          uid: uid,
          customId: '',
          name: supaUser.displayName ?? '',
          email: supaUser.email ?? '',
          photoUrl: supaUser.photoUrl ?? '',
          gender: 'male',
        );
      }
    }
    if (_currentUser != null && _currentUser!.customId.isEmpty) {
      // FIX: Use secure ID generator with uniqueness check
      String customId;
      try {
        // TODO: Use server-side generation first (preferred)
        final idResult = await ApiService().generateCustomId();
        customId = idResult['customId'] as String;
      } catch (_) {
        // FIX: Fallback to local secure generator with uniqueness check
        customId = await UserIdGenerator().generateUniqueId(
          minDigits: 6,
          maxDigits: 7,
        );
      }
      await _supabaseService.updateUser(uid, {'custom_id': customId});
      _currentUser = await _supabaseService.getUser(uid);
    }
    if (_currentUser != null && _currentUser!.photoUrl.isEmpty) {
      final supaUser = SupabaseAuthService().currentUser;
      final authPhoto = (supaUser != null && supaUser.uid == uid && supaUser.photoUrl != null && supaUser.photoUrl!.isNotEmpty)
          ? supaUser.photoUrl
          : FirebaseAuth.instance.currentUser?.photoURL;
      if (authPhoto != null && authPhoto.isNotEmpty) {
        _currentUser = _currentUser!.copyWith(photoUrl: authPhoto);
        try {
          await _supabaseService.updateUser(uid, {
            'photo_url': authPhoto,
            'photoUrl': authPhoto,
            'avatar': authPhoto,
            'avatar_url': authPhoto,
          });
        } catch (_) {}
      }
    }
    _isLoading = false;
    notifyListeners();
    startListening(uid);
    _checkExpiredBackpackItems(uid);
  }

  Future<void> _checkExpiredBackpackItems(String uid) async {
    try {
      final items = await SupabaseDataService().getUserBackpack(uid);
      final now = DateTime.now();
      final expired = items.where((d) {
        final expStr = d['expires_at']?.toString().trim();
        if (expStr == null || expStr.isEmpty || expStr == 'null') return false; // دائم لا ينتهي
        final expDate = DateTime.tryParse(expStr);
        if (expDate == null) return false;
        return expDate.isBefore(now);
      }).toList();

      if (expired.isNotEmpty) {
        bool frameExpired = false;
        for (var d in expired) {
          final cat = d['category']?.toString() ?? d['item_type']?.toString();
          if (cat == 'frame' && d['item_id'] == _currentUser?.activeFrame) {
            frameExpired = true;
          }
          final docId = d['id']?.toString();
          if (docId != null && docId.isNotEmpty) {
            await SupabaseDataService().deleteUserBackpackItem(docId);
          }
        }
        
        if (frameExpired) {
          await SupabaseDataService().updateUser(uid, {'active_frame': ''});
          _currentUser = _currentUser?.copyWith(activeFrame: '');
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error checking expired backpack items: $e');
    }
  }

  Future<void> updateUser(UserModel user) async {
    _currentUser = user;
    await _supabaseService.saveUser(user);
    notifyListeners();
  }

  void deductCoinsLocally(int amount) {
    if (_currentUser == null) return;
    final newCoins = (_currentUser!.coins - amount).clamp(0, 999999999);
    _currentUser = _currentUser!.copyWith(coins: newCoins);
    notifyListeners();
  }

  void addCoinsLocally(int amount) {
    if (_currentUser == null || amount <= 0) return;
    final newCoins = _currentUser!.coins + amount;
    _currentUser = _currentUser!.copyWith(coins: newCoins);
    notifyListeners();
  }

  Future<bool> purchaseItem(StoreItemModel item) async {
    if (_currentUser == null) return false;
    final success = await _supabaseService.purchaseItem(_currentUser!.uid, item);
    if (success) {
      await loadUser(_currentUser!.uid);
    }
    return success;
  }

  Future<void> equipItem(String itemId, String category) async {
    if (_currentUser == null) return;
    await _supabaseService.equipItem(_currentUser!.uid, itemId, category);
    await loadUser(_currentUser!.uid);
  }

  Future<void> unequipItem(String category) async {
    if (_currentUser == null) return;
    switch (category) {
      case 'frame':
        _currentUser = _currentUser!.copyWith(activeFrame: '');
        break;
      case 'headwear':
        _currentUser = _currentUser!.copyWith(activeHeadwear: '');
        break;
      case 'bubble':
        _currentUser = _currentUser!.copyWith(activeBubble: '');
        break;
      case 'entrance':
        _currentUser = _currentUser!.copyWith(activeEntrance: '');
        break;
      case 'car':
        _currentUser = _currentUser!.copyWith(activeCar: '');
        break;
      case 'cover':
        _currentUser = _currentUser!.copyWith(activeCover: '');
        break;
      case 'necklace':
        _currentUser = _currentUser!.copyWith(activeNecklace: '');
        break;
      case 'mic_wave':
        _currentUser = _currentUser!.copyWith(activeMicWave: '');
        break;
    }
    notifyListeners();
    await _supabaseService.unequipItem(_currentUser!.uid, category);
    await loadUser(_currentUser!.uid);
  }

  void clearUser() {
    stopListening();
    _currentUser = null;
    notifyListeners();
  }
}
