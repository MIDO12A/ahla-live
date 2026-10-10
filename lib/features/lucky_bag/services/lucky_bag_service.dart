import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
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
      return res['success'] == true ? res : null;
    } catch (e) {
      debugPrint('sendLuckyBag failed: $e');
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
      return LuckyBagClaimResult(
        success: false,
        error: _friendlyGrabError(msg),
      );
    } catch (e) {
      debugPrint('grabLuckyBag failed: $e');
      return const LuckyBagClaimResult(success: false, error: 'network_error');
    }
  }

  /// جلب تفاصيل المظروف وقائمة الفائزين بالكامل
  Future<Map<String, dynamic>?> getLuckyBagDetails(String bagId) async {
    try {
      final res = await _api.getLuckyBagDetails(bagId);
      if (res['success'] == true) return res;
    } catch (e) {
      debugPrint('getLuckyBagDetails failed: $e');
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
    return _fb.activeLuckyBagsStream(roomId).map((list) => list
        .map((m) => LuckyBagModel.fromJson(m))
        .toList());
  }

  void dispose() {
    _grabOverlay?.remove();
    _grabOverlay = null;
  }
}