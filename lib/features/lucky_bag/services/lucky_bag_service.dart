import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/supabase_compat.dart';
import '../../../models/message_model.dart';
import '../../../services/api_service.dart';
import '../../../services/supabase_data_service.dart';
import '../../../services/supabase_service.dart';
import '../models/lucky_bag_model.dart';
import '../widgets/lucky_bag_grab_overlay.dart';

/// خدمة المظاريف الحمراء وأكياس الحظ (Lucky Bag / Red Packet)
class LuckyBagService {
  static final LuckyBagService _instance = LuckyBagService._internal();
  factory LuckyBagService() => _instance;
  LuckyBagService._internal();

  final ApiService _api = ApiService();
  final FirebaseService _fb = FirebaseService();

  // ذاكرة تخزين مؤقتة للحقائب النشطة لضمان عملها فورياً بدون أخطاء 404
  final Map<String, Map<String, dynamic>> _localActiveBags = {};
  final Map<String, List<Map<String, dynamic>>> _localBagClaims = {};

  /// إرسال مظروف أحمر / حقيبة حظ إلى الغرفة.
  Future<Map<String, dynamic>?> sendLuckyBag({
    required String roomId,
    String type = 'coins',
    String scope = 'room',
    int? value,
    int? count,
    int? totalCoins,
    String? greetingText,
    bool isSuper = false,
  }) async {
    try {
      final res = await _api.sendLuckyBag(
        roomId: roomId,
        type: type,
        scope: scope,
        value: value,
        count: count,
        totalCoins: totalCoins,
        greetingText: greetingText,
        isSuper: isSuper,
      );
      if (res['success'] == true) return res;
    } catch (e) {
      debugPrint('[LuckyBagService] api sendLuckyBag failed: $e, using Supabase fallback');
    }

    // Direct Supabase Fallback
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return null;
      final ds = SupabaseDataService();
      final user = await ds.getUser(uid);
      final cost = totalCoins ?? ((value ?? 0) * (count ?? 1));
      if ((user?.coins ?? 0) < cost) return null;

      // خصم العملات من المرسل
      await ds.updateUser(uid, {
        'coins': (user?.coins ?? 0) - cost,
        'total_gifts_sent': (user?.totalGiftsSent ?? 0) + cost,
      });

      final bagId = 'bag_${DateTime.now().millisecondsSinceEpoch}_${uid.substring(0, math.min(6, uid.length))}';
      final bagPayload = <String, dynamic>{
        'id': bagId,
        'bag_id': bagId,
        'bagId': bagId,
        'room_id': roomId,
        'roomId': roomId,
        'owner_id': uid,
        'ownerId': uid,
        'owner_name': user?.name ?? 'مستخدم',
        'ownerName': user?.name ?? 'مستخدم',
        'owner_photo': user?.photoUrl ?? '',
        'ownerAvatar': user?.photoUrl ?? '',
        'owner_vip': user?.wealthLevel ?? 0,
        'ownerVip': user?.wealthLevel ?? 0,
        'owner_level': user?.level ?? 1,
        'ownerLevel': user?.level ?? 1,
        'type': type,
        'scope': scope,
        'value': value ?? (cost ~/ (count ?? 1)),
        'total_bags': count ?? 1,
        'totalBags': count ?? 1,
        'total_shares': count ?? 1,
        'totalShares': count ?? 1,
        'total_value': cost,
        'totalValue': cost,
        'remaining_value': cost,
        'remainingValue': cost,
        'claimed_shares': 0,
        'claimedShares': 0,
        'greeting_text': greetingText ?? 'حظ سعيد للجميع ✨',
        'greetingText': greetingText ?? 'حظ سعيد للجميع ✨',
        'is_super': isSuper,
        'isSuper': isSuper,
        'status': 'active',
        'created_at': DateTime.now().toIso8601String(),
        'expires_at': DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
      };

      _localActiveBags[bagId] = bagPayload;

      // بث رسالة في الغرفة
      unawaited(ds.sendMessage(MessageModel(
        msgId: const Uuid().v4(),
        roomId: roomId,
        senderUid: uid,
        senderName: user?.name ?? '',
        senderPhotoUrl: user?.photoUrl ?? '',
        type: 'lucky_bag',
        text: '🧧 أرسل حقيبة حظ بقيمة $cost 🪙 (${count ?? 1} حقيبة)',
        giftPayload: bagPayload,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      )).catchError((_) => false));

      return {
        'success': true,
        'bagId': bagId,
        'bag': bagPayload,
      };
    } catch (e) {
      debugPrint('[LuckyBagService] supabase fallback error: $e');
      return null;
    }
  }

  /// فتح / التقاط نصيب من المظروف الأحمر في الغرفة.
  Future<LuckyBagClaimResult> grabLuckyBag({
    required String roomId,
    String? bagId,
  }) async {
    try {
      final res = await _api.grabLuckyBag(roomId: roomId, bagId: bagId);
      return LuckyBagClaimResult.fromJson(res);
    } on ApiException catch (e) {
      final msg = e.message;
      if (msg != 'Route not found') {
        return LuckyBagClaimResult(
          success: false,
          error: _friendlyGrabError(msg),
        );
      }
    } catch (e) {
      debugPrint('grabLuckyBag API failed: $e, trying fallback');
    }

    // Direct Supabase Fallback for grabLuckyBag
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return const LuckyBagClaimResult(success: false, error: 'not_in_room');
      final ds = SupabaseDataService();
      final user = await ds.getUser(uid);
      if (user == null) return const LuckyBagClaimResult(success: false, error: 'not_in_room');

      final targetBagId = bagId ?? _localActiveBags.keys.lastOrNull;
      if (targetBagId == null) {
        return const LuckyBagClaimResult(success: false, error: 'no_active_bag');
      }

      final bagData = _localActiveBags[targetBagId];
      if (bagData != null) {
        if (bagData['owner_id'] == uid) {
          return const LuckyBagClaimResult(success: false, error: 'cannot_claim_own_bag');
        }
        final claims = _localBagClaims.putIfAbsent(targetBagId, () => []);
        if (claims.any((c) => c['claimer_id'] == uid)) {
          return const LuckyBagClaimResult(success: false, error: 'already_claimed');
        }

        final remainingVal = (bagData['remaining_value'] as num?)?.toInt() ?? 0;
        final totalShares = (bagData['total_shares'] as num?)?.toInt() ?? 1;
        final claimedShares = claims.length;
        final remainingShares = math.max(1, totalShares - claimedShares);

        if (remainingVal <= 0 || claimedShares >= totalShares) {
          bagData['status'] = 'done';
          return const LuckyBagClaimResult(success: false, error: 'bag_empty');
        }

        // حساب الحصة
        int wonAmount;
        if (remainingShares == 1) {
          wonAmount = remainingVal;
        } else {
          final avg = remainingVal ~/ remainingShares;
          final variance = (avg * 0.4).round();
          wonAmount = math.max(1, avg + (math.Random().nextInt(math.max(1, variance * 2)) - variance));
          wonAmount = math.min(wonAmount, remainingVal);
        }

        bagData['remaining_value'] = remainingVal - wonAmount;
        bagData['claimed_shares'] = claimedShares + 1;
        if (claimedShares + 1 >= totalShares || (remainingVal - wonAmount) <= 0) {
          bagData['status'] = 'done';
        }

        // إيداع العملات للفائز
        await ds.updateUser(uid, {
          'coins': user.coins + wonAmount,
        });

        final claimEntry = {
          'id': const Uuid().v4(),
          'claimer_id': uid,
          'claimer_name': user.name,
          'claimer_avatar': user.photoUrl,
          'amount': wonAmount,
          'created_at': DateTime.now().toIso8601String(),
        };
        claims.add(claimEntry);

        // إشعار الغرفة بالفوز
        unawaited(ds.sendMessage(MessageModel(
          msgId: const Uuid().v4(),
          roomId: roomId,
          senderUid: uid,
          senderName: user.name,
          senderPhotoUrl: user.photoUrl,
          type: 'text',
          text: '🎉 فتح حقيبة الحظ وحصل على $wonAmount 🪙!',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        )).catchError((_) => false));

        return LuckyBagClaimResult(
          success: true,
          bagId: targetBagId,
          amount: wonAmount,
          remaining: bagData['remaining_value'],
          isDone: bagData['status'] == 'done',
        );
      }
    } catch (e) {
      debugPrint('[LuckyBagService] grab fallback error: $e');
    }

    return const LuckyBagClaimResult(success: false, error: 'network_error');
  }

  /// جلب تفاصيل المظروف وقائمة الفائزين بالكامل
  Future<Map<String, dynamic>?> getLuckyBagDetails(String bagId) async {
    try {
      final res = await _api.getLuckyBagDetails(bagId);
      if (res['success'] == true) return res;
    } catch (e) {
      debugPrint('getLuckyBagDetails failed: $e');
    }

    final bagData = _localActiveBags[bagId];
    if (bagData != null) {
      return {
        'success': true,
        'bag': bagData,
        'claims': _localBagClaims[bagId] ?? [],
      };
    }
    return null;
  }

  String _friendlyGrabError(String code) {
    switch (code) {
      case 'cannot_claim_own_bag':
        return 'لا يمكنك التقاط كيس أرسلته بنفسك';
      case 'already_claimed':
        return 'لقد قمت بفتح هذا المظروف مسبقاً!';
      case 'mic_only':
        return 'هذا المظروف مخصص للمتواجدين على المايك فقط';
      case 'not_in_room':
        return 'يجب أن تكون داخل الغرفة للمشاركة';
      case 'bag_expired':
        return 'انتهت صلاحية هذا المظروف';
      case 'bag_empty':
        return 'تم توزيع كافة الأنصبة بالكامل!';
      case 'no_active_bag':
        return 'لا توجد مظاريف نشطة حالياً';
      case 'rate_limited':
        return 'تمهل قليلاً وحاول مجدداً';
      default:
        return 'جيت متأخر، تم فتح المظروف بالكامل';
    }
  }

  // ── عرض إشعار الالتقاط السريع ─────────────────────────
  OverlayEntry? _grabOverlay;

  void showGrabBanner(
    BuildContext context, {
    required String roomId,
    required LuckyBagModel bag,
    required VoidCallback onOpenDialog,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    _grabOverlay?.remove();
    _grabOverlay = OverlayEntry(
      builder: (ctx) => LuckyBagGrabOverlay(
        bag: bag,
        onTapOpen: () {
          _hideGrabBanner();
          onOpenDialog();
        },
        onGrab: () async {
          final result = await grabLuckyBag(
            roomId: roomId,
            bagId: bag.bagId,
          );
          if (!ctx.mounted) return;
          if (result.success) {
            _hideGrabBanner();
            _showGrabResult(ctx, result);
          } else {
            _showGrabResult(ctx, result);
          }
        },
      ),
    );
    overlay.insert(_grabOverlay!);
  }

  void _hideGrabBanner() {
    _grabOverlay?.remove();
    _grabOverlay = null;
  }

  void _showGrabResult(BuildContext context, LuckyBagClaimResult result) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? '🎉 مبروك! حصلت على ${result.amount} 🪙 من المظروف'
              : '⚠️ ${result.error ?? 'فشل فتح المظروف'}',
        ),
        duration: const Duration(seconds: 3),
        backgroundColor: result.success ? const Color(0xFF2E7D32) : const Color(0xFF7A3B00),
      ),
    );
  }

  /// تتبع المظاريف النشطة داخل الغرفة
  Stream<List<LuckyBagModel>> activeBagsStream(String roomId) {
    return _fb.activeLuckyBagsStream(roomId).map((list) {
      final combined = <String, LuckyBagModel>{};
      for (final m in list) {
        final b = LuckyBagModel.fromJson(m);
        combined[b.bagId] = b;
      }
      for (final local in _localActiveBags.values) {
        if ((local['room_id'] == roomId || local['roomId'] == roomId) &&
            local['status'] == 'active') {
          final b = LuckyBagModel.fromJson(local);
          combined[b.bagId] = b;
        }
      }
      return combined.values.toList();
    });
  }

  void dispose() {
    _grabOverlay?.remove();
    _grabOverlay = null;
  }
}