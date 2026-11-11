import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import '../../services/safe_http.dart';
import '../supabase_compat.dart';

import '../auth/supabase_ready.dart';
import '../config/api_config.dart';

/// عمليات مالية عبر RPC أو Railway API — مفاتيح منع التكرار لكل طلب.
abstract final class FinancialService {
  static String newIdempotencyKey() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 30)}';

  static Future<Map<String, dynamic>?> previewRechargeTarget({
    required String kind,
    required String idOrCode,
  }) async {
    if (!isSupabaseReady()) return null;
    try {
      final v = await Supabase.instance.client.rpc(
        'preview_recharge_target_by_code',
        params: {'p_kind': kind, 'p_code': idOrCode.trim()},
      );
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      return null;
    } catch (e) {
      debugPrint('[financial_service] error: $e');
      return null;
    }
  }

  static Future<String?> adminRechargeGold({
    required String targetKind,
    required String targetId,
    required int amount,
    required String idempotencyKey,
  }) async {
    if (!isSupabaseReady()) return 'غير متصل';
    try {
      await Supabase.instance.client.rpc(
        'admin_recharge_gold',
        params: {
          'p_target_kind': targetKind,
          'p_target_id': targetId,
          'p_amount': amount,
          'p_idempotency_key': idempotencyKey,
        },
      );
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String?> sendRoomGift({
    required String receiverId,
    required String roomId,
    required int goldAmount,
    required String idempotencyKey,
  }) async {
    debugPrint(
      '[GIFT_PATH] legacy sendRoomGift blocked | rid=$receiverId | room=$roomId',
    );
    return 'مسار الهدايا القديم متوقف. استخدم صندوق الهدايا الجديد.';
  }

  /// إرسال هدية لعدة مستلمين دفعة واحدة (كل المايكات).
  ///
  /// يستدعي RPC `send_room_gift_to_multiple` الذي ينفّذ transaction واحدة
  /// تخصم من المرسل وتوزع على كل [receiverIds] بـ [goldPerReceiver] لكل واحد.
  ///
  /// **RPC signature (Supabase SQL):**
  /// ```sql
  /// create or replace function send_room_gift_to_multiple(
  ///   p_receiver_ids  uuid[],
  ///   p_room_id       uuid,
  ///   p_gold_per_receiver int,
  ///   p_idempotency_key   text
  /// ) returns void language plpgsql security definer as $$
  /// declare
  ///   _sender_id uuid := auth.uid();
  ///   _total_gold int := p_gold_per_receiver * array_length(p_receiver_ids, 1);
  ///   _rid uuid;
  /// begin
  ///   -- التحقق من الرصيد
  ///   if (select gold_balance from user_wallets where user_id = _sender_id) < _total_gold then
  ///     raise exception 'رصيد غير كافٍ';
  ///   end if;
  ///   -- خصم من المرسل
  ///   update user_wallets set gold_balance = gold_balance - _total_gold
  ///     where user_id = _sender_id;
  ///   -- إضافة لكل مستلم
  ///   foreach _rid in array p_receiver_ids loop
  ///     insert into user_wallets (user_id, diamond_balance)
  ///       values (_rid, p_gold_per_receiver)
  ///       on conflict (user_id) do update
  ///         set diamond_balance = user_wallets.diamond_balance + p_gold_per_receiver;
  ///   end loop;
  /// end;
  /// $$;
  /// ```
  static Future<String?> sendGiftToMultipleReceivers({
    required List<String> receiverIds,
    required String roomId,
    required int goldPerReceiver,
    required String idempotencyKey,
  }) async {
    debugPrint(
      '[GIFT_PATH] legacy sendGiftToMultipleReceivers blocked | room=$roomId',
    );
    return 'مسار الهدايا القديم متوقف. استخدم صندوق الهدايا الجديد.';
  }

  /// إعلان فوز بلعبة في الشريط الفاخر (يستدعى من منطق اللعبة عند تحقق الشروط).
  static Future<String?> enqueueRoomGameWinAnnouncement({
    required String roomId,
    required String winnerUserId,
    required int coinsWon,
    String? gameIconUrl,
  }) async {
    if (!isSupabaseReady()) return 'غير متصل';
    try {
      await Supabase.instance.client.rpc(
        'enqueue_room_game_win_announcement',
        params: {
          'p_room_id': roomId,
          'p_winner_id': winnerUserId,
          'p_coins_won': coinsWon,
          'p_game_icon_url': gameIconUrl,
        },
      );
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// إعلان حظ بضعف عالٍ (≥١٠٠) في الشريط الفاخر.
  static Future<String?> enqueueRoomLuckyMultiplierAnnouncement({
    required String roomId,
    required String actorUserId,
    required int coinsWon,
    required int multiplier,
    String? giftImageUrl,
  }) async {
    if (!isSupabaseReady()) return 'غير متصل';
    try {
      await Supabase.instance.client.rpc(
        'enqueue_room_lucky_multiplier_announcement',
        params: {
          'p_room_id': roomId,
          'p_actor_id': actorUserId,
          'p_coins_won': coinsWon,
          'p_multiplier': multiplier,
          'p_gift_image_url': giftImageUrl,
        },
      );
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<({String? error, int goldReceived})> exchangeDiamondsToGold({
    required int diamondAmount,
    required String idempotencyKey,
  }) async {
    if (!isSupabaseReady()) {
      return (error: 'غير متصل', goldReceived: 0);
    }
    try {
      final v = await Supabase.instance.client.rpc(
        'exchange_diamonds_to_gold',
        params: {
          'p_diamond_amount': diamondAmount,
          'p_idempotency_key': idempotencyKey,
        },
      );
      final g = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
      return (error: null, goldReceived: g);
    } catch (e) {
      return (error: e.toString(), goldReceived: 0);
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Railway /gifts/send-fast — BullMQ Queue (يرد 202 فوراً)
  // ────────────────────────────────────────────────────────────────────────────

  /// إرسال هدية واحدة لمستلم واحد عبر Railway (BullMQ).
  ///
  /// يرد 202 Accepted فوراً — الـ worker يكمل العملية في الخلفية.
  /// يُرجع null عند النجاح أو رسالة الخطأ.
  static Future<String?> sendGiftFast({
    required String giftId,
    required String roomId,
    required int quantity,
    String? recipientId,
    // Deprecated display/price params are kept for call-site compatibility only.
    // The request body below intentionally sends IDs + quantity + idempotency.
    // Pricing and gift metadata are loaded from the server/DB only.
    int? price, // سعر الهدية الواحدة (coins)
    String? giftNameAr, // اسم الهدية بالعربية
    String? giftFileUrl, // رابط ملف الهدية (Lottie/WebP/SVGA...)
    String? giftThumbnailUrl, // رابط الصورة المصغّرة
    String? giftFormat, // صيغة الملف (lottie/webp/svga/gif...)
    String? senderName, // اسم المُرسِل
    String? senderAvatar, // صورة المُرسِل
    String? receiverName, // اسم المُستقبِل
    // ── idempotency للـ retry (يُمرَّر من sendGiftFastMulti) ──────────────────
    String?
    clientIdempotencyKey, // Railway يستخدمه كـ BullMQ jobId → deduplication
  }) async {
    // ── [DEBUG Step 0.0] — يُحذف بعد تأكيد المسار ────────────────────────────
    debugPrint(
      '[GIFT_PATH] sendGiftFast → Railway /gifts/send-fast | gid=$giftId | room=$roomId',
    );
    // ─────────────────────────────────────────────────────────────────────────
    if (!isSupabaseReady()) return 'غير متصل';
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return 'لا توجد جلسة مستخدم';

      final response = await SafeHttp.post(
            Uri.parse('$ApiConfig.kayanApiBase/gifts/send-fast'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode({
              'gift_id': giftId,
              'room_id': roomId,
              'quantity': quantity,
              if (recipientId != null && recipientId.isNotEmpty)
                'recipient_id': recipientId,
              // يُمرَّر فقط عند sendGiftFastMulti — Railway يستخدمه كـ BullMQ jobId
              if (clientIdempotencyKey != null &&
                  clientIdempotencyKey.isNotEmpty)
                'client_idem_key': clientIdempotencyKey,
            }),
          )
          .timeout(const Duration(seconds: 10));

      // ── [DEBUG Step 0.0] — يُحذف بعد تأكيد المسار ────────────────────────
      debugPrint(
        '[GIFT_PATH] Railway response: HTTP ${response.statusCode} | body=${response.body}',
      );
      // ──────────────────────────────────────────────────────────────────────

      if (response.statusCode >= 200 && response.statusCode < 300) return null;

      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final raw = body['error']?.toString() ?? 'خطأ ${response.statusCode}';
        return _friendlyError(raw);
      } catch (parseErr) {
        debugPrint(
          '[financial_service] sendGiftFast body parse failed '
          '(status=${response.statusCode}): $parseErr',
        );
        return 'خطأ ${response.statusCode}';
      }
    } catch (e) {
      debugPrint('[financial_service] sendGiftFast error: $e');
      return _friendlyError(e.toString());
    }
  }

  /// تحويل رسائل الخطأ التقنية إلى نص عربي مفهوم
  static String _friendlyError(String raw) {
    if (raw.contains('insufficient gold') || raw.contains('رصيد غير كافٍ')) {
      return 'رصيدك غير كافٍ لإرسال هذه الهدية';
    }
    if (raw.contains('not authenticated') || raw.contains('JWT')) {
      return 'انتهت جلستك، سجّل الدخول مجدداً';
    }
    if (raw.contains('idempotency')) {
      return 'تم إرسال هذه الهدية مسبقاً';
    }
    if (raw.contains('SocketException') || raw.contains('Failed host lookup')) {
      return 'لا يوجد اتصال بالإنترنت';
    }
    // استخرج message: من PostgrestException إذا تسرّبت
    final msgMatch = RegExp(r'message:\s*([^,)]+)').firstMatch(raw);
    if (msgMatch != null) return msgMatch.group(1)!.trim();
    return raw;
  }

  /// تنسيق الكوينز للعرض (1500 → "1,500"، 1200000 → "1.2M")
  static String _fmtCoins(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return '$v';
  }

  /// إرسال هدية لعدة مستلمين عبر Railway — يُنشئ job منفصل لكل مستلم.
  ///
  /// **SSOT Phase 1B fixes:**
  /// 1. Pre-check الرصيد قبل إطلاق N طلب متوازٍ — يمنع إرسال جزئي.
  /// 2. Batch idempotency key ثابت لكل مستلم — Railway يستخدمه كـ BullMQ jobId
  ///    فإذا أعاد المستخدم الإرسال بنفس الـ batchKey تُتجاهل التكرارات.
  static Future<String?> sendGiftFastMulti({
    required String giftId,
    required String roomId,
    required int quantity,
    required List<String> recipientIds,
    // ── Pre-check: رصيد المستخدم الحالي (من الـ UI — لا DB fetch جديد) ────────
    int?
    coinsBalance, // إذا مُرِّر ← نتحقق أن balance >= price*qty*n قبل الإرسال
    // حقول العرض الفوري (تُمرَّر لكل طلب)
    int? price,
    String? giftNameAr,
    String? giftFileUrl,
    String? giftThumbnailUrl,
    String? giftFormat,
    String? senderName,
    String? senderAvatar,
  }) async {
    if (recipientIds.isEmpty) return 'لا يوجد مستلمون';

    // ── Pre-check: تحقق من الرصيد قبل إطلاق N طلب متوازٍ ──────────────────
    // يمنع حالة: user لديه 1000 كوين لكنه يُرسل لـ 5 مستلمين بـ 500 كوين لكل منهم
    // بدون هذا الفحص ينجح الطلب الأول ويفشل الباقون — إرسال جزئي مُربِك.
    if (coinsBalance != null && price != null && price > 0) {
      final totalCost = price * quantity * recipientIds.length;
      if (coinsBalance < totalCost) {
        final n = recipientIds.length;
        return 'رصيدك غير كافٍ — '
            'تحتاج ${_fmtCoins(totalCost)} كوين لإرسال الهدية لـ $n مستلم'
            ' (رصيدك: ${_fmtCoins(coinsBalance)})';
      }
    }

    // ── Batch idempotency key — ثابت لكل الطلبات في هذه الدُّفعة ─────────────
    // إذا أُعيد الاستدعاء بنفس batchKey (retry UI) ← نفس per-recipient keys
    // ← Railway يستخدمها كـ BullMQ jobId ← يُتجاهل الـ job المكرر تلقائياً.
    final batchKey = newIdempotencyKey();

    final results = await Future.wait(
      recipientIds.map(
        (rid) => sendGiftFast(
          giftId: giftId,
          roomId: roomId,
          quantity: quantity,
          recipientId: rid,
          price: price,
          giftNameAr: giftNameAr,
          giftFileUrl: giftFileUrl,
          giftThumbnailUrl: giftThumbnailUrl,
          giftFormat: giftFormat,
          senderName: senderName,
          senderAvatar: senderAvatar,
          // مفتاح فريد لكل مستلم مُشتق من batchKey — يضمن deduplication بالـ Railway
          clientIdempotencyKey: '${batchKey}_$rid',
          // receiverName غير مُمرَّر — كل مستلم مختلف، الـ worker يجلبه
        ),
      ),
    );
    return results.firstWhere((e) => e != null, orElse: () => null);
  }

  /// شحن كوينز لمستخدم — يمر عبر Railway API (rate limiting + JWT validation).
  /// [recipientKayanId] هو الرقم العام للمستخدم (kayan_id من profiles).
  static Future<String?> agentRechargeUser({
    required int recipientKayanId,
    required int goldAmount,
    required String idempotencyKey,
  }) async {
    if (!isSupabaseReady()) return 'غير متصل';

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return 'لا توجد جلسة مستخدم';

      final response = await SafeHttp.post(
            Uri.parse('$ApiConfig.kayanApiBase/coins/recharge'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode({
              'recipientKayanId': recipientKayanId,
              'amount': goldAmount,
              'idempotencyKey': idempotencyKey,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) return null;

      // استخرج رسالة الخطأ من السيرفر
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return body['error']?.toString() ?? 'خطأ ${response.statusCode}';
      } catch (parseErr) {
        debugPrint(
          '[financial_service] agentRechargeUser body parse failed '
          '(status=${response.statusCode}): $parseErr',
        );
        return 'خطأ ${response.statusCode}';
      }
    } catch (e) {
      debugPrint('[financial_service] agentRechargeUser error: $e');
      return e.toString();
    }
  }

  static Future<List<Map<String, dynamic>>> agentRechargeHistory({
    int limit = 200,
  }) async {
    if (!isSupabaseReady()) return const [];
    try {
      final v = await Supabase.instance.client.rpc(
        'agent_recharge_history',
        params: {'p_limit': limit},
      );
      if (v is List) {
        return v.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      if (v is String) {
        final decoded = jsonDecode(v);
        if (decoded is List) {
          return decoded
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }
      return const [];
    } catch (e) {
      debugPrint('[financial_service] error: $e');
      return const [];
    }
  }
}
