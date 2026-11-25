import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'safe_http.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../models/user_model.dart';
import '../models/room_model.dart';
import '../models/message_model.dart';
import '../models/gift_model.dart' as gm;
import '../models/gift_category_model.dart';
import '../models/gift_banner_config_model.dart';
import '../models/store_item_model.dart';
import '../models/gifted_item_model.dart';
import '../models/banner_config.dart';
import '../models/notification_model.dart';
import '../core/supabase_compat.dart';
import '../core/utils/id_generator.dart';
import 'supabase_data_service.dart';
import 'supabase_realtime_service.dart';
import 'proto_gift_push_service.dart';
import 'dynamic_config_service.dart';
import 'agency_target_evaluator.dart';
import 'global_banner_service.dart';
import 'level_service.dart';

/// خدمة إدارة وتنسيق عمليات Supabase المباشرة (SupabaseService)
/// تضمن الاتصال فائق السرعة مع https://supabase.com وتحديث رصيد العملات فوريًا بـ 0ms
class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  SupabaseClient get _sb => Supabase.instance.client;
  final SupabaseDataService _ds = SupabaseDataService();
  static const String _baseUrl = SupabaseConfig.projectUrl;
  static const String _anonKey = SupabaseConfig.anonKey;

  // ✅ كاش بسيط لترتيب الغرف لتسريع الفتح المتكرر
  static final Map<String, CachedRanking> _roomRankingCache = {};
  static const Duration _cacheTtl = Duration(minutes: 2);

  static Map<String, String> get _headers => {
        'apikey': _anonKey,
        'Authorization': 'Bearer $_anonKey',
        'Content-Type': 'application/json',
      };

  void init() {
    debugPrint('[SupabaseService] Initialized with Supabase URL: $_baseUrl');
  }

  static Future<void> _coinTxQueue = Future<void>.value();

  /// يُسلسل خصم/إضافة الكوينز لمنع تصادم القراءة-الكتابة عند الإرسال المتتابع
  /// (كومبو أو عدة مستلمين) حتى لا تضيع بعض عمليات الخصم.
  Future<T> _serializeCoinTx<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _coinTxQueue = _coinTxQueue.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// تعديل رصيد الكوينز/الألماس بشكل متسلسل (قراءة-تعديل-كتابة) داخل نفس الطابور
  /// المستخدم في خصم الهدايا، حتى لا تُكتب قيمة قديمة فوق خصم/إضافة حديثة.
  /// يرجع الرصيد الجديد أو null عند الفشل.
  Future<Map<String, num>?> adjustUserBalance(
    String uid, {
    num coinsDelta = 0,
    num diamondsDelta = 0,
  }) {
    if (coinsDelta == 0 && diamondsDelta == 0) return Future.value(null);
    return _serializeCoinTx(() async {
      final user = await _ds.getUser(uid);
      if (user == null) return null;
      final updates = <String, dynamic>{};
      num newCoins = user.coins;
      num newDiamonds = user.diamonds;
      if (coinsDelta != 0) {
        newCoins = (user.coins + coinsDelta).clamp(0, 999999999).toInt();
        updates['coins'] = newCoins;
      }
      if (diamondsDelta != 0) {
        newDiamonds = (user.diamonds + diamondsDelta).clamp(0, 999999999).toInt();
        updates['diamonds'] = newDiamonds;
      }
      final ok = await _ds.updateUser(uid, updates);
      if (!ok) return null;
      return <String, num>{'coins': newCoins, 'diamonds': newDiamonds};
    });
  }

  /// جلب مستند إعدادات أو صف من جدول عبر مفتاح key
  Future<Map<String, dynamic>?> getDoc(String table, String key) async {
    try {
      final res = await _sb.from(table).select().eq('key', key).maybeSingle();
      return res != null ? Map<String, dynamic>.from(res) : null;
    } catch (e) {
      debugPrint('[SupabaseService] getDoc error ($table, $key): $e');
      return null;
    }
  }

  Future<bool> disburseSalary({
    required String agencyId,
    required String hostUid,
    required int amount,
    String scheduleType = 'manual',
  }) =>
      _ds.disburseSalary(
        agencyId: agencyId,
        hostUid: hostUid,
        amount: amount,
        scheduleType: scheduleType,
      );

  // ═══════════════════════════════════════════════════════
  // USER OPERATIONS (SUPABASE)
  // ═══════════════════════════════════════════════════════

  Future<UserModel?> getUser(String uid, {bool throwOnError = false}) =>
      _ds.getUser(uid, throwOnError: throwOnError);

  /// بيانات المستخدم الحالي — تصل لحظياً عبر Realtime عند أي تغيير في صفّه
  /// (رصيد، مستوى، صورة…)، والـ polling (كل ثانيتين) يبقى شبكة أمان فقط
  /// عندما لا تكون قناة users حيّة.
  Stream<UserModel?> userStream(String uid) async* {
    final rt = SupabaseRealtimeService.instance;
    final topic = 'users:$uid';
    rt.subscribeTable(
      table: 'users',
      topic: topic,
      filter: 'uid=eq.$uid',
      events: const ['INSERT', 'UPDATE'],
    );
    try {
      while (true) {
        try {
          final u = await _ds.getUser(uid);
          if (u != null) yield u;
        } catch (_) {}
        await rt.waitForTableChange(
          topic: topic,
          tables: const {'users'},
          fallback: const Duration(seconds: 2),
          safety: const Duration(seconds: 8),
        );
      }
    } finally {
      rt.unsubscribeTopic(topic);
    }
  }

  Future<void> saveUser(UserModel user) async {
    await _ds.updateUser(user.uid, user.toMap());
  }

  Future<bool> updateUser(
    String uid,
    Map<String, dynamic> data, {
    bool allowIdentityChange = false,
  }) =>
      _ds.updateUser(uid, data, allowIdentityChange: allowIdentityChange);

  /// مigrated المستخدمين الذين لديهم IDs أبجدية رقمية إلى IDs رقمية (6-7 أرقام)
  /// يستخدم UserIdGenerator.migrateToNumericId لتوليد رقم ثابت لكل مستخدم
  Future<void> migrateAlphanumericCustomIds() async {
    try {
      // جلب جميع المستخدمين
      final users = await _ds.getAllUsers();
      int migratedCount = 0;
      
      for (final user in users) {
        final currentId = user.customId;
        
        // تخطي إذا كان فارغاً أو صالح بالفعل
        if (currentId.isEmpty) continue;
        if (UserIdGenerator.isValidCustomId(currentId)) continue;
        
        // تحويل الـ ID الأبجدي الرقمي إلى رقمي
        final newNumericId = UserIdGenerator.migrateToNumericId(currentId);
        
        // التحقق من أن الرقم الجديد غير مستخدم
        final isUnique = await UserIdGenerator().checkIdUniqueness(newNumericId);
        if (!isUnique) {
          // إذا كان مستخدماً، استخدم رقم عشوائي جديد
          final fallbackId = generateQuickCustomId(digits: 7);
          final fallbackUnique = await UserIdGenerator().checkIdUniqueness(fallbackId);
          if (!fallbackUnique) continue;
          
          await _ds.updateUser(user.uid, {
            'custom_id': fallbackId,
            'original_custom_id': currentId, // حفظ الـ ID القديم للرجوع إليه
          }, allowIdentityChange: true);
        } else {
          await _ds.updateUser(user.uid, {
            'custom_id': newNumericId,
            'original_custom_id': currentId, // حفظ الـ ID القديم للرجوع إليه
          }, allowIdentityChange: true);
        }
        
        migratedCount++;
        debugPrint('[SupabaseService] Migrated user ${user.uid}: $currentId -> $newNumericId');
      }
      
      debugPrint('[SupabaseService] Migration complete. Migrated $migratedCount users.');
    } catch (e) {
      debugPrint('[SupabaseService] Migration error: $e');
    }
  }

  Stream<List<GiftedItemModel>> userGiftedItemsStream(String uid) =>
      _ds.userGiftedItemsStream(uid);

  Future<bool> removeGiftedItem(String giftId) => _ds.removeGiftedItem(giftId);

  Future<bool> purchaseItem(String uid, StoreItemModel item) async {
    try {
      final u = await _ds.getUser(uid);
      if (u == null || u.coins < item.price) return false;
      final owned = List<String>.from(u.ownedItems);
      if (!owned.contains(item.itemId)) owned.add(item.itemId);
      final updates = <String, dynamic>{
        'coins': u.coins - item.price,
        'owned_items': owned,
      };
      if (item.category == 'special_id') {
        final special = item.effectiveCustomId;
        if (special == null || special.isEmpty) return false;
        // منع شراء آيدي مميز مستخدم فعلياً من حساب آخر
        final holders = await _ds.getUsersByCustomId(special);
        if (holders.any((h) => h.uid != uid)) return false;
        updates['custom_id'] = special;
        updates['active_special_id'] = item.itemId;
        final orig = u.originalCustomId?.trim() ?? '';
        if ((orig.isEmpty || orig == special) &&
            u.customId.isNotEmpty &&
            u.customId != special) {
          updates['original_custom_id'] = u.customId;
        }
      }
      final ok = await _ds.updateUser(
        uid,
        updates,
        allowIdentityChange: item.category == 'special_id',
      );
      if (ok && item.category == 'special_id') {
        unawaited(_ds.markStoreItemSold(item.itemId));
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> equipItem(String uid, String itemId, String category) async {
    if (category == 'special_id') {
      final storeItem = await _ds.getStoreItemById(itemId);
      final special = storeItem?.effectiveCustomId;
      if (special == null || special.isEmpty) return false;
      final u = await _ds.getUser(uid);
      final owned = u?.ownedItems ?? const <String>[];
      if (!owned.contains(itemId)) return false;
      final holders = await _ds.getUsersByCustomId(special);
      if (holders.any((h) => h.uid != uid)) return false;
      final orig = u?.originalCustomId?.trim() ?? '';
      final current = u?.customId ?? '';
      return await _ds.updateUser(uid, {
        'custom_id': special,
        'active_special_id': itemId,
        if (orig.isEmpty && current.isNotEmpty && current != special)
          'original_custom_id': current,
      }, allowIdentityChange: true);
    }
    final updateMap = <String, dynamic>{};
    switch (category) {
      case 'frame':
        updateMap['active_frame'] = itemId;
        break;
      case 'headwear':
        updateMap['active_headwear'] = itemId;
        break;
      case 'bubble':
        updateMap['active_bubble'] = itemId;
        break;
      case 'entrance':
        updateMap['active_entrance'] = itemId;
        break;
      case 'car':
        updateMap['active_car'] = itemId;
        break;
      default:
        updateMap['active_$category'] = itemId;
    }
    return await _ds.updateUser(uid, updateMap);
  }

  Future<bool> unequipItem(String uid, String category) async {
    if (category == 'special_id') {
      final u = await _ds.getUser(uid);
      var restore = u?.originalCustomId?.trim() ?? '';
      if (restore.isEmpty) {
        restore = await UserIdGenerator().generateUniqueId();
      }
      return await _ds.updateUser(uid, {
        'custom_id': restore,
        'active_special_id': '',
      }, allowIdentityChange: true);
    }
    final updateMap = <String, dynamic>{
      'active_$category': '',
    };
    return await _ds.updateUser(uid, updateMap);
  }

  // ═══════════════════════════════════════════════════════
  // ROOM & SEATS OPERATIONS (SUPABASE)
  // ═══════════════════════════════════════════════════════

  Future<RoomModel?> getRoom(String roomId) => _ds.getRoom(roomId);

  Future<void> toggleMute(String roomId, int seatIndex, bool muted) =>
      _ds.toggleMute(roomId, seatIndex, muted);

  Future<void> leaveSeatForUser(String roomId, String uid) =>
      _ds.leaveSeatForUser(roomId, uid);

  Future<void> leaveRoom(String roomId, String uid) =>
      _ds.leaveRoom(roomId, uid);

  // ═══════════════════════════════════════════════════════
  // BANNERS & BROADCASTS (SUPABASE)
  // ═══════════════════════════════════════════════════════

  Stream<List<GiftBannerConfig>> giftBannerConfigsStream() async* {
    while (true) {
      try {
        final configs = await _ds.getGiftBannerConfigs();
        yield configs;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 15));
    }
  }

  Stream<List<Map<String, dynamic>>> globalBroadcastStream() async* {
    String? watermark;
    var firstPass = true;
    // ✅ Realtime-first: اشتراك INSERT على جدول broadcasts عبر Phoenix
    //    WebSocket — نص فوز الحظ يصل لحظياً بدل انتظار دورة polling.
    //    الـ polling يبقى شبكة أمان فقط (3s عند موت القناة، 10s أمان
    //    عند حياتها) بدل الاستعلام كل 250ms من كل عميل — هذا يخفّض
    //    حمل السيرفر ~16 ضعفاً ويزيل latency الـ polling.
    final rt = SupabaseRealtimeService.instance;
    const topic = 'broadcasts:global';
    rt.subscribeTable(
      table: 'broadcasts',
      topic: topic,
      events: const ['INSERT'],
    );
    try {
      while (true) {
      try {
        if (firstPass) {
          firstPass = false;
          // ⚠️ لا نعرض البثوث القديمة عند فتح التطبيق إطلاقاً.
          // كانت تُرسل أول 10 بثوث محفوظة على السيرفر فتظهر «لافتات
          // مخزّنة» تتحرك بلا أي مستخدم يلعب. نستخدمها فقط لتحديد
          // نقطة البداية (watermark) ثم نعرض الجديد فقط.
          final broadcasts = await _ds.getRecentBroadcasts(limit: 10);
          DateTime floor =
              DateTime.now().toUtc().subtract(const Duration(seconds: 20));
          for (final b in broadcasts) {
            final ts = DateTime.tryParse(b['created_at']?.toString() ?? '');
            if (ts != null && ts.toUtc().isAfter(floor)) {
              floor = ts.toUtc();
            }
          }
          watermark = floor.toIso8601String();
        } else {
          // تداخل بسيط لضمان عدم فقدان أي بث عند تزامن الطلبات
          final String since = DateTime.tryParse(watermark ?? '')
                  ?.toUtc()
                  .subtract(const Duration(seconds: 2))
                  .toIso8601String() ??
              (watermark ??
                  DateTime.now()
                      .toUtc()
                      .subtract(const Duration(seconds: 20))
                      .toIso8601String());
          final broadcasts =
              await _ds.getBroadcastsSince(since, limit: 20);
          if (broadcasts.isNotEmpty) {
            yield broadcasts;
            for (final b in broadcasts) {
              final ts = b['created_at']?.toString();
              if (ts != null && ts.isNotEmpty && ts.compareTo(watermark!) > 0) {
                watermark = ts;
              }
            }
          }
        }
      } catch (_) {}
        // ✅ انتظار ذكي: إشعار Realtime فوري عند أي INSERT على broadcasts،
        //    أو fallback كل 6s إن ماتت القناة، أو safety كل 20s كحد أقصى.
        await rt.waitForTableChange(
          topic: topic,
          tables: const {'broadcasts'},
          fallback: const Duration(seconds: 6),
          safety: const Duration(seconds: 20),
        );
      }
    } finally {
      rt.unsubscribeTopic(topic);
    }
  }

  Future<bool> sendGlobalBroadcast({
    required String senderUid,
    required String senderName,
    required String senderPhotoUrl,
    required String roomId,
    required String roomName,
    required String content,
    String? giftIcon,
    int? multiplier,
    String type = 'lucky_gift',
  }) {
    return _ds.recordBroadcast(
      senderUid: senderUid,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      roomId: roomId,
      roomName: roomName,
      content: content,
      giftIcon: giftIcon,
      multiplier: multiplier,
      type: type,
    );
  }

  // ═══════════════════════════════════════════════════════
  // LUCKY GIFTS & RTP ALGORITHM (AUTHENTIC 82.5%)
  // ═══════════════════════════════════════════════════════

  List<int> drawLuckyMultipliers(int count,
      {int cardCount = 4, double? customWinRate}) {
    final random = math.Random.secure();

    // حساب نسبة الفوز والخسارة بناء على إعدادات لوحة التحكم
    final winRate = customWinRate ?? 15.0;
    final lossThreshold = math.min(
        100000, math.max(0, ((100.0 - winRate) / 100.0 * 100000).round()));
    final effectiveCount = count > 0 ? count : 1;
    final wonMultipliers = <int>[];

    for (int c = 0; c < effectiveCount; c++) {
      final roll = random.nextInt(100000);
      int mult;
      if (roll < lossThreshold) {
        mult = 0;
      } else {
        final winRoll = random.nextInt(100000);
        if (winRoll < 65000) {
          mult = 1;
        } else if (winRoll < 88000) {
          mult = 2;
        } else if (winRoll < 96000) {
          mult = 5;
        } else if (winRoll < 98800) {
          mult = 10;
        } else if (winRoll < 99700) {
          mult = 20;
        } else if (winRoll < 99950) {
          mult = 50;
        } else if (winRoll < 99990) {
          mult = 100;
        } else {
          mult = 500;
        }
      }
      if (mult > 0) {
        wonMultipliers.add(mult);
      }
    }

    final cards = List<int>.filled(cardCount, 0);
    final indices = List<int>.generate(cardCount, (i) => i)..shuffle(random);
    for (int i = 0; i < wonMultipliers.length && i < cardCount; i++) {
      cards[indices[i]] = wonMultipliers[i];
    }
    for (int i = cardCount; i < wonMultipliers.length; i++) {
      final randomIdx = random.nextInt(cardCount);
      cards[randomIdx] += wonMultipliers[i];
    }

    return cards;
  }

  // ═══════════════════════════════════════════════════════
  // SEND LUCKY GIFT (ULTRA-FAST DIRECT SUPABASE CALL)
  // ═══════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> sendLuckyGift({
    required String roomId,
    required String giftId,
    required String giftName,
    required String giftNameAr,
    required String giftIconUrl,
    required String giftCoverUrl,
    required String giftBgUrl,
    String? svgaAnimUrl,
    required String senderId,
    required String senderName,
    required String senderPhotoUrl,
    required String receiverId,
    required String receiverName,
    String? receiverPhotoUrl,
    required int value,
    int count = 1,
    String? comboId,
    int comboCount = 1,
    List<int>? preDrawnMultipliers,
    String? giftCategoryId,
  }) async {
    int totalWonCoins = 0;
    int maxMultiplier = 0;
    bool isBigWin = false;
    List<int> multipliers = [];
    num serverNewBalance = 0;
    final totalCost = value * count;
    // معرّف ثابت للرسالة يستخدمه الإطار الاستباقي والإطار الكامل بعد التسوية،
    // فيمنع المسار البطيء من إعادة حقن نفس الصف عند وصول room_messages.
    final luckyMsgId = const Uuid().v4();

    // ⚡ إطار مرئي استباقي (Hijoy-style): أنيميشن/تحليق/صوت يصل لبقية أعضاء
    //    الغرفة في لحظة الضغطة، قبل رحلة RPC. لا يحمل أي بيانات فوز أو رصيد،
    //    فالتسوية تظل الحاكمة والإطار الكامل بعدها يحمل النتيجة الحقيقية.
    unawaited(ProtoGiftPushService.instance.sendLuckyGift(
      roomId: roomId,
      giftId: giftId,
      giftName: giftNameAr,
      giftIcon: giftIconUrl,
      giftCoverUrl: giftCoverUrl,
      animationAsset: svgaAnimUrl ?? '',
      senderId: senderId,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      receiverId: receiverId,
      receiverName: receiverName,
      count: count,
      value: value,
      comboId: comboId ?? luckyMsgId,
      comboCount: comboCount,
      messageId: luckyMsgId,
      isPreview: true,
    ));

    try {
      // 1. استدعاء المعاملة الذرية من Supabase عبر RPC (process_lucky_gift)
      final rpcUrl = Uri.parse('$_baseUrl/rest/v1/rpc/process_lucky_gift');
      final rpcRes = await SafeHttp.post(
            rpcUrl,
            headers: _headers,
            body: jsonEncode({
              'p_user_id': senderId,
              'p_room_id': roomId,
              'p_receiver_id': receiverId,
              'p_gift_id': giftId,
              'p_count': count,
              'p_unit_price': value,
            }),
          )
          .timeout(const Duration(seconds: 8));

      bool rpcSucceeded = false;
      if (rpcRes.statusCode >= 200 && rpcRes.statusCode < 300) {
        try {
          final Map<String, dynamic> rpcData =
              jsonDecode(rpcRes.body) as Map<String, dynamic>;
          if (rpcData['success'] == true) {
            totalWonCoins = (rpcData['won_coins'] as num?)?.toInt() ?? 0;
            maxMultiplier = (rpcData['multiplier'] as num?)?.toInt() ?? 0;
            isBigWin = rpcData['is_big_win'] == true || maxMultiplier >= 10;
            serverNewBalance =
                (rpcData['new_balance'] as num?)?.toInt() ?? 0;
            final rawMults = rpcData['multipliers'] as List<dynamic>?;
            if (rawMults != null) {
              multipliers = rawMults.map((e) => (e as num).toInt()).toList();
            } else {
              multipliers = preDrawnMultipliers ?? drawLuckyMultipliers(count);
            }
            rpcSucceeded = true;
          } else {
            debugPrint(
                '[SupabaseService] process_lucky_gift returned error: ${rpcData['error']}');
            if (rpcData['error']?.toString().contains('غير كاف') == true) {
              return null; // Insufficient coins confirmed by database
            }
          }
        } catch (_) {}
      }

      if (!rpcSucceeded) {
        // Fallback آمن مرتبط بمحفظة الحظ ونسب الفوز/الخسارة من لوحة التحكم
        debugPrint('[SupabaseService] process_lucky_gift fallback triggered');
        final sUser = await _ds.getUser(senderId);
        final currentCoins = sUser?.coins ?? 0;
        if (currentCoins < totalCost) {
          debugPrint(
              '[SupabaseService] Fallback insufficient coins: have $currentCoins, need $totalCost');
          return null;
        }

        // استعلام إعدادات المحفظة ونسبة الفوز المضبوطة من لوحة التحكم
        double poolWinRate = 15.0;
        int poolBalance = 0;
        try {
          final pool = await _ds.getLuckyPool();
          if (pool != null) {
            poolWinRate = (pool['win_rate'] as num?)?.toDouble() ?? 15.0;
            poolBalance = (pool['balance'] as num?)?.toInt() ?? 0;
          }
        } catch (_) {}

        multipliers = preDrawnMultipliers ??
            drawLuckyMultipliers(count, customWinRate: poolWinRate);
        for (final m in multipliers) {
          final wonAmount = (value * m);
          if (wonAmount <= poolBalance || poolBalance > 0) {
            totalWonCoins += wonAmount;
            if (m > maxMultiplier) maxMultiplier = m;
          }
        }
        isBigWin = maxMultiplier >= 10;
        serverNewBalance =
            math.max(0, currentCoins - totalCost + totalWonCoins).toInt();

        await _ds.updateUser(senderId, {
          'coins': serverNewBalance,
          'total_gifts_sent': (sUser?.totalGiftsSent ?? 0) + totalCost,
        });

        // خصم أرباح الفوز من محفظة الحظ بالسيرفر وتحديث السجلات
        if (totalWonCoins > 0) {
          unawaited(_ds.deductLuckyPoolPayout(
              totalWonCoins, maxMultiplier, senderId));
        }
      }

      // 2. حساب حصص الماس/الكاريزما — التنفيذ الفعلي مؤجّل للخلفية بعد بث النص
      //    (كان انتظار هذه الطلبات هنا يؤخر كتابة رسالة الشات ثوانٍ طويلة).
      final luckyTargetPct = DynamicConfigService().luckyGiftTargetPercentage;
      final int recipientDiamonds = luckyTargetPct > 0
          ? math.max(1, ((totalCost * luckyTargetPct) / 100.0).round())
          : 0;
      final effectiveSeatCharmValue =
          luckyTargetPct > 0 ? ((value * luckyTargetPct) / 100.0).round() : 0;

      // 3. بث رسالة الغرفة عبر room_messages في Supabase
      // معرّفات ثابتة لرسالة النظام وصف البث — تُرسل داخل البث السريع ليستخدمها
      // الطرف المستقبل ويمنع الازدواج عند وصول الصفوف الحقيقية بعدين.
      final winMsgId = const Uuid().v4();
      final bCastId = const Uuid().v4();
      final luckyGiftPayload = {
        'gift_icon': giftIconUrl,
        'image_url': giftIconUrl,
        'gift_name': giftNameAr,
        'count': count,
        'won_coins': totalWonCoins,
        'multiplier': maxMultiplier,
        'receiver_name': receiverName,
        'roomId': roomId,
        'sender': {
          'id': senderId,
          'nickname': senderName,
          'avatar': senderPhotoUrl,
        },
        'receiver': {
          'id': receiverId,
          'nickname': receiverName,
        },
        'gift': {
          'id': giftId,
          'giftName': giftName,
          'giftNameAr': giftNameAr,
          'coinPrice': value,
          'giftIconUrl': giftIconUrl,
          'giftCoverUrl': giftCoverUrl,
          'giftBgUrl': giftBgUrl,
          'svgaAnimUrl': svgaAnimUrl,
        },
        'combo': {
          'comboId': comboId ?? luckyMsgId,
          'comboCount': comboCount,
          'times': count,
        },
        'results': {
          'multipliers': multipliers,
          'cards': List.generate(
              multipliers.length,
              (i) => {
                    'index': i,
                    'multiplier': multipliers[i],
                    'wonCoins': value * multipliers[i],
                    'giftName': giftNameAr,
                    'giftIcon': giftIconUrl,
                  }),
          'totalWonCoins': totalWonCoins,
          'maxMultiplier': maxMultiplier,
          'isBigWin': isBigWin,
        },
      };

      unawaited(_ds
          .sendMessage(MessageModel(
            msgId: luckyMsgId,
            roomId: roomId,
            senderUid: senderId,
            senderName: senderName,
            senderPhotoUrl: senderPhotoUrl,
            type: 'lucky_gift',
            text:
                '$senderName 🍀 $giftNameAr x$count (فاز بـ $totalWonCoins 🪙)',
            imageUrl: giftIconUrl,
            giftPayload: luckyGiftPayload,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ))
          .catchError((_) => false));

      // ⚡ بث ثنائي للهدية المحظوظة (Protobuf). الإطار الواحد يحمل الآن
      //    رسالة النظام + نص البانر + كروت المضاعفات + بيانات البانر الكبير،
      //    فتصل كلها بنفس سرعة نص الفوز بدل انتظار room_messages/broadcasts.
      final String winnerText = (totalWonCoins > 0 || maxMultiplier > 1)
          ? (maxMultiplier > 1
              ? '🍀 $receiverName فاز بالمحظوظ! مضاعف ${maxMultiplier}X — ربح $totalWonCoins 🪙'
              : '🍀 $receiverName فاز بهدية الحظ "$giftNameAr" وربح $totalWonCoins 🪙!')
          : '';
      // ⛔ اللافتات تبدأ من الحد الأدنى للمضاعف (افتراضياً 5X):
      //    لا نبث ولا نحقن محلياً أي مضاعف 1X/2X/3X/4X إطلاقاً.
      final int minLuckyBannerMult =
          DynamicConfigService().luckyBannerMinMultiplier;
      final bool shouldShowLuckyBanner =
          maxMultiplier >= minLuckyBannerMult || isBigWin;
      final String broadcastText = shouldShowLuckyBanner
          ? '$senderName 🍀 $giftNameAr x$count (فاز بمضاعف ${maxMultiplier}X — $totalWonCoins 🪙)'
          : '';

      unawaited(ProtoGiftPushService.instance.sendLuckyGift(
        roomId: roomId,
        giftId: giftId,
        giftName: giftNameAr,
        giftIcon: giftIconUrl,
        giftCoverUrl: giftCoverUrl,
        animationAsset: svgaAnimUrl ?? '',
        senderId: senderId,
        senderName: senderName,
        senderPhotoUrl: senderPhotoUrl,
        receiverId: receiverId,
        receiverName: receiverName,
        count: count,
        value: value,
        jackpotMultiplier: maxMultiplier,
        wonCoins: totalWonCoins,
        multipliers: multipliers,
        isBigWin: isBigWin,
        winnerText: winnerText,
        systemMessageId: winMsgId,
        broadcastText: broadcastText,
        broadcastId: shouldShowLuckyBanner ? bCastId : '',
        customSvgaUrl: svgaAnimUrl ?? '',
        comboId: comboId ?? luckyMsgId,
        comboCount: comboCount,
        periodSec: 0,
        messageId: luckyMsgId,
      ));

      // رسالة نظام مرئية لجميع مستخدمي الغرفة لإعلان الفائز بالمحظوظ.
      // نفس الـ UUID أُرسل في البث السريع (system_message_id) لمنع التكرار.
      if (winnerText.isNotEmpty) {
        unawaited(_ds
            .sendMessage(MessageModel(
              msgId: winMsgId,
              roomId: roomId,
              senderUid: 'system',
              senderName: 'نظام',
              senderPhotoUrl: '',
              type: 'system',
              text: winnerText,
              timestamp: DateTime.now().millisecondsSinceEpoch + 100,
            ))
            .catchError((_) => false));
      }

      // 5. بث نص الفوز لكافة الغرف فوراً عبر جدول broadcasts (مسار التخزين).
      //    النص نفسه أُرسل قبل قليل في البث السريع (broadcast_text/broadcast_id)،
      //    فالصف هنا للمحفوظات فقط ولن يتكرر عرضه عند الطرف المستقبل.
      if (shouldShowLuckyBanner) {
        unawaited(_ds
            .recordBroadcast(
              senderUid: senderId,
              senderName: senderName,
              senderPhotoUrl: senderPhotoUrl,
              roomId: roomId,
              content: broadcastText,
              giftIcon: giftIconUrl,
              multiplier: maxMultiplier,
              type: 'lucky_gift',
              broadcastId: bCastId,
              categoryId: giftCategoryId,
            )
            .catchError((_) => false));

        // ✅ صف بث ثانٍ مخصص للافة فيديو فوز المحظوظ (lucky_win):
        //   sender_* هنا تمثل الفائز (المستلم) وليس مرسل الهدية، والمبلغ
        //    يُكتب داخل content بصيغة «... — ربح N 🪙» ليسحبه العميل.
        if (maxMultiplier >= 5) {
          unawaited(_ds
              .recordBroadcast(
                senderUid: receiverId,
                senderName: receiverName,
                senderPhotoUrl: receiverPhotoUrl,
                roomId: roomId,
                roomName: '',
                content: winnerText.isNotEmpty
                    ? winnerText
                    : '🍀 $receiverName فاز بالمحظوظ! مضاعف ${maxMultiplier}X — ربح $totalWonCoins 🪙',
                giftIcon: giftIconUrl,
                multiplier: maxMultiplier,
                type: 'lucky_win',
                categoryId: giftCategoryId,
              )
              .catchError((_) => false));

          // ✅ عرض محلي فوري للمرسل — لا ينتظر رحلة البث回来 من
          //    السيرفر (التي قد تتأخر ثوانٍ). عند وصول البث الحقيقي
          //    يتجاهله GlobalBannerService كمكرر عبر _recentLuckyWinKeys.
          GlobalBannerService.instance.showLuckyWinVideo({
            'id': '${luckyMsgId}_luckwinvideo_local',
            'senderName': receiverName,
            'senderAvatar': receiverPhotoUrl,
            'winnerUid': receiverId,
            'multiplier': maxMultiplier,
            'totalWon': totalWonCoins,
            'roomId': roomId,
            'roomName': '',
            'categoryId': giftCategoryId,
          });
        }

        // ⛔ لا حقن محلي لنص الفوز — يُعرض فقط عبر البث القادم من السيرفر
        //    (Realtime/Pusher) حتى لا تظهر رسالة محلية غير موثّقة.
      }

      // نص الفوز يصل لكل الأجهزة (بما فيها المرسل) عبر Supabase Realtime
      // مع polling احتياطي كل 500ms في GlobalBannerService.

      // 6. العمليات الخلفية غير المعطِّلة: ماس المستلم + سجلات الهدايا + أهداف
      //    الوكالة + إشعار الاستلام. هذه الخطوات كانت تُنتظر قبل كتابة رسالة
      //    الشات، فكان نص الفوز (آخر رسالة) يتأخر ثوانٍ طويلة. الآن تُنفَّذ
      //    بعد إطلاق البث مباشرةً فيعود الرد للواجهة فوراً.
      unawaited(() async {
        try {
          if (recipientDiamonds > 0) {
            // ✅ عدّاد المستلم عبر RPC ذرّي — لا PATCH مباشر على
            //    حساب مستخدم آخر (حارس الكتابة).
            await _ds.bumpUserStat(
                receiverId, 'total_gifts_received', recipientDiamonds);
            // الرصيد يُحدَّث داخل RPC/المسار الاحتياطي (عضو وكالة أو محفظة شخصية)
            await _ds.creditHostAgencyMemberDiamonds(
                receiverId, recipientDiamonds);
          }

          // ✅ المستويات: إرسال الحظ → ثروة المرسل، استلام الماس → جواهر المستلم
          unawaited(LevelService()
              .addExp(uid: senderId, type: 'wealth', amount: totalCost)
              .catchError((_) => null));
          if (receiverId != senderId) {
            final gemsAmount =
                recipientDiamonds > 0 ? recipientDiamonds : totalCost;
            unawaited(LevelService()
                .addExp(uid: receiverId, type: 'gems', amount: gemsAmount)
                .catchError((_) => null));
          }

          await _ds
              .recordSentGift(
                roomId: roomId,
                giftId: giftId,
                giftName: giftNameAr.isNotEmpty ? giftNameAr : giftName,
                animationAsset: svgaAnimUrl ?? giftIconUrl,
                senderId: senderId,
                senderName: senderName,
                senderPhotoUrl: senderPhotoUrl,
                receiverId: receiverId,
                receiverName: receiverName,
                value: effectiveSeatCharmValue,
                count: count,
              )
              .catchError((_) => false);
          await _ds.incrementRoomGifts(roomId, totalCost);

          // تقييم التارجت للوكيل
          await AgencyTargetEvaluator.evaluateHostTargets(receiverId)
              .catchError((_) {});

          // ✅ لا إشعارات هدايا في رسائل النظام — تقليل حمل على النظام
        } catch (e) {
          debugPrint('[SupabaseService] lucky gift side-effects error: $e');
        }
      }());

      return {
        'success': true,
        'wonCoins': totalWonCoins,
        'multipliers': multipliers,
        'maxMultiplier': maxMultiplier,
        'isBigWin': isBigWin,
        'newBalance': serverNewBalance,
        'msgId': luckyMsgId,
        'payload': luckyGiftPayload,
      };
    } catch (e) {
      debugPrint('[SupabaseService] sendLuckyGift error: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════
  // SEND REGULAR GIFT (SUPABASE DIRECT)
  // ═══════════════════════════════════════════════════════

  Future<bool> sendGift({
    required String roomId,
    String? roomName,
    required String giftId,
    required String giftName,
    String? animationAsset,
    String? defaultImage,
    required String senderId,
    required String senderName,
    String? senderPhotoUrl,
    required String receiverId,
    required String receiverName,
    required int value,
    int count = 1,
    ValueChanged<double>? onProgress,
  }) async {
    final totalCost = value * count;
    final isSelfSend = senderId == receiverId;

    try {
      // 1. خصم الكوينز من المرسل (مُسلسَل لمنع تصادم القراءة-الكتابة عند الكومبو/تعدد المستلمين)
      final hostRatePct = DynamicConfigService().hostRatePercentage;
      final hostDiamonds = (totalCost * (hostRatePct / 100.0)).round();

      // ⚡ بث رسالة الهدية في الشات فوراً — بالتوازي مع خصم الكوينز
      //    وليس بعده، حتى لا تنتظر الرسالة رحلة RPC كاملة وتظهر
      //    لدى الجميع (بما فيهم المرسل) في أقل زمن ممكن حتى مع الإرسال المتتابع.
      final animAsset = animationAsset ?? '';
      final staticCover = (defaultImage != null && defaultImage.isNotEmpty)
          ? defaultImage
          : ((animAsset.isNotEmpty &&
                  !animAsset.endsWith('.svga') &&
                  !animAsset.endsWith('.vap') &&
                  !animAsset.endsWith('.mp4'))
              ? animAsset
              : '');
      final effectiveIcon = animAsset.isNotEmpty ? animAsset : staticCover;
      final giftMsgId = const Uuid().v4();
      final giftMsgFuture = _ds
          .sendMessage(MessageModel(
            msgId: giftMsgId,
            roomId: roomId,
            senderUid: senderId,
            senderName: senderName,
            senderPhotoUrl: senderPhotoUrl ?? '',
            type: 'gift',
            text: '$senderName أرسل $giftName x$count إلى $receiverName',
            imageUrl: staticCover.isNotEmpty ? staticCover : effectiveIcon,
            giftPayload: {
              'gift_id': giftId,
              'gift_name': giftName,
              'gift_icon': staticCover.isNotEmpty ? staticCover : effectiveIcon,
              'image_url': staticCover.isNotEmpty ? staticCover : effectiveIcon,
              'default_image': staticCover,
              'count': count,
              'value': value,
              'receiver_id': receiverId,
              'receiver_name': receiverName,
              'animation_asset': animAsset,
            },
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ))
          .catchError((_) => false);

      // ⚡ بث ثنائي فوري قبل خصم الكوينز (زي مسار الرسالة الاستباقية تماماً):
      //    العرض يصل لبقية الغرفة في نفس لحظة الضغطة بدل انتظار RPC الخصم.
      //    البث للعرض فقط ولا يخصم/يضيف رصيداً؛ ولو فشل الخصم نبعت إلغاءً.
      final giftPushFuture = ProtoGiftPushService.instance.sendGift(
        roomId: roomId,
        giftId: giftId,
        giftName: giftName,
        giftIcon: staticCover,
        animationAsset: animAsset,
        senderId: senderId,
        senderName: senderName,
        senderPhotoUrl: senderPhotoUrl ?? '',
        receiverId: receiverId,
        receiverName: receiverName,
        count: count,
        value: value,
        messageId: giftMsgId,
        receiverIds: [receiverId],
      );

      onProgress?.call(0.1);
      onProgress?.call(0.3);

      // 🛡️ 1. محاولة الإرسال السيادي الذري من السيرفر حصراً (Server-Authoritative Send Gift RPC)
      //    يقوم بالخصم، والإيداع، وتسجيل الهدية، وتحديث الغرفة، وحساب الوكالة في حركة ذرية واحدة غير قابلة للتجزئة
      final String idemKey = 'gift_${giftMsgId}';
      final authoritativeRes = await _ds.sendGiftAuthoritative(
        senderId: senderId,
        receiverId: receiverId,
        roomId: roomId,
        giftId: giftId,
        count: count,
        idempotencyKey: idemKey,
      );

      final bool deducted;
      final bool isAuthoritativeSuccess = authoritativeRes != null && authoritativeRes['ok'] == true;

      if (isAuthoritativeSuccess) {
        deducted = true;
      } else if (authoritativeRes != null && authoritativeRes['error'] == 'insufficient_coins') {
        deducted = false;
      } else {
        // احتياطي: إذا لم يكن RPC السيادي مضافاً في بيئة العمل بعد
        final spendRes = await _ds.spendUserCoins(senderId, totalCost);
        if (spendRes != null) {
          deducted = spendRes['ok'] == true;
        } else {
          deducted = await _serializeCoinTx(() async {
            final sUser = await _ds.getUser(senderId);
            final currentCoins = sUser?.coins ?? 0;
            if (currentCoins < totalCost) return false;
            return _ds.updateUser(senderId, {
              'coins': currentCoins - totalCost,
              'total_gifts_sent': (sUser?.totalGiftsSent ?? 0) + totalCost,
            });
          });
        }
      }

      if (!deducted) {
        // فشل الخصم: احذف رسالة الهدية التي بُثت استباقياً حتى لا
        // يبقى أثر لهدية لم تُرسل فعلياً.
        unawaited(giftMsgFuture.then((ok) {
          if (ok == true) _ds.deleteRoomMessage(giftMsgId);
        }).catchError((_) {}));
        // الإطار المرئي سبق الخصم — اطلب من بقية الأجهزة حذف أثره.
        unawaited(giftPushFuture.then((_) {
          return ProtoGiftPushService.instance.cancelGift(
            roomId: roomId,
            messageId: giftMsgId,
          );
        }).catchError((_) => false));
        onProgress?.call(0.0);
        return false;
      }

      onProgress?.call(0.5);

      // إذا نجحت الدالة السيادية (Authoritative)، فجميع العمليات (إيداع، وكالة، سنت_جيفت، غرفة) نُفذت ذرياً داخل السيرفر بالفعل!
      if (!isAuthoritativeSuccess) {
        // عدّاد الهدايا المستلمة للمرسل في حالة الإرسال لنفسه
        if (isSelfSend) {
          unawaited(() async {
            try {
              final sUser = await _ds.getUser(senderId);
              if (sUser == null) return;
              await _ds.updateUser(senderId, {
                'total_gifts_received':
                    sUser.totalGiftsReceived + hostDiamonds,
              });
            } catch (_) {}
          }());
        }

        // 2. توزيع الماس وفق سياسة النظام المعتمدة (100% للمضيف كاملة، وعمولة وكيل المضيف تُضاف لرصيده دون أي خصم من المضيف)
        if (isSelfSend) {
          await _ds.creditHostAgencyMemberDiamonds(senderId, hostDiamonds);
        } else {
          await _ds.bumpUserStat(
              receiverId, 'total_gifts_received', hostDiamonds);
          await _ds.creditHostAgencyMemberDiamonds(receiverId, hostDiamonds);
        }

        onProgress?.call(0.7);
        // 3. تسجيل الهدية في السجل ورفع عدّادات الغرفة (الخلفية)
        unawaited(_ds
            .recordSentGift(
              roomId: roomId,
              giftId: giftId,
              giftName: giftName,
              animationAsset: effectiveIcon,
              senderId: senderId,
              senderName: senderName,
              senderPhotoUrl: senderPhotoUrl,
              receiverId: receiverId,
              receiverName: receiverName,
              value: value,
              count: count,
            )
            .catchError((_) => false));
        unawaited(_ds.incrementRoomGifts(roomId, totalCost));
      } else {
        onProgress?.call(0.7);
      }

      onProgress?.call(0.9);

      // 4. بث كل هدية لكل الغرف — نفس النص الظاهر في شات الغرفة
      final String giftBroadcastContent =
          '$senderName أرسل $giftName x$count إلى $receiverName';
      final String giftBCastId = const Uuid().v4();
      unawaited(_ds
          .recordBroadcast(
            senderUid: senderId,
            senderName: senderName,
            senderPhotoUrl: senderPhotoUrl,
            roomId: roomId,
            roomName: roomName,
            content: giftBroadcastContent,
            giftIcon: effectiveIcon,
            type: totalCost >= 500 ? 'big_gift' : 'gift',
            broadcastId: giftBCastId,
          )
          .catchError((_) => false));

      // ✅ حقن محلي فوري: لافتة/نص الهدية يظهر لحظياً عند الإرسال
      GlobalBannerService.instance.echoBroadcastLocally({
        'id': giftBCastId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'sender_uid': senderId,
        'sender_name': senderName,
        'sender_photo_url': senderPhotoUrl,
        'room_id': roomId,
        'room_name': roomName ?? '',
        'content': giftBroadcastContent,
        'gift_icon': effectiveIcon,
        'gift_name': giftName,
        'type': totalCost >= 500 ? 'big_gift' : 'gift',
        'value': value,
        'count': count,
        'total_cost': totalCost,
      });

      // 5. تقييم التارجت للوكيل — بدون إشعار هدية في رسائل النظام
      unawaited(AgencyTargetEvaluator.evaluateHostTargets(receiverId)
          .catchError((_) {}));

      // ✅ المستويات: الإرسال يرفع «الثروة» للمرسل والاستلام يرفع
      //    «الجواهر» للمستلم — عبر add_user_exp RPC ذرّي (يعمل لأي uid).
      unawaited(LevelService()
          .addExp(uid: senderId, type: 'wealth', amount: totalCost)
          .catchError((_) => null));
      if (receiverId != senderId) {
        final gemsAmount = hostDiamonds > 0 ? hostDiamonds : totalCost;
        unawaited(LevelService()
            .addExp(uid: receiverId, type: 'gems', amount: gemsAmount)
            .catchError((_) => null));
      }

      return true;
    } catch (e) {
      debugPrint('[SupabaseService] sendGift error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // NOTIFICATIONS (SUPABASE)
  // ═══════════════════════════════════════════════════════

  Future<void> sendNotification({
    required String uid,
    required String type,
    String? actorUid,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/notifications');
      await SafeHttp.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'id': const Uuid().v4(),
          'uid': uid,
          'target': uid,
          'type': type,
          'actor_uid': actorUid ?? '',
          'title': title,
          'body': body,
          'data': data ?? {},
          'is_read': false,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('[SupabaseService] sendNotification error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // AGENCY OPERATIONS (SUPABASE)
  // ═══════════════════════════════════════════════════════

  Future<bool> deleteAndExitAgencyByOwner(
      {required String agencyId, required String ownerUid}) async {
    try {
      if (agencyId.isNotEmpty) {
        try {
          await _sb.from('host_agencies').delete().eq('id', agencyId);
        } catch (_) {}
        try {
          await _sb
              .from('host_agency_members')
              .delete()
              .eq('agency_id', agencyId);
        } catch (_) {}
        try {
          await _sb
              .from('agency_applications')
              .delete()
              .eq('agency_id', agencyId);
        } catch (_) {}
        try {
          await _sb.from('users').update({
            'agency_id': null,
            'host_agency_id': null,
          }).eq('agency_id', agencyId);
        } catch (_) {}
        try {
          await SafeHttp.delete(
            Uri.parse('$_baseUrl/rest/v1/host_agencies?id=eq.$agencyId'),
            headers: _headers,
          );
          await SafeHttp.delete(
            Uri.parse(
                '$_baseUrl/rest/v1/host_agency_members?agency_id=eq.$agencyId'),
            headers: _headers,
          );
        } catch (_) {}
      }
      try {
        await _sb.from('users').update({
          'agency_id': null,
          'host_agency_id': null,
          'is_agency_owner': false,
          'is_host_agent': false,
        }).or('uid.eq.$ownerUid,id.eq.$ownerUid');
      } catch (_) {}
      await _ds.updateUser(ownerUid, {
        'agency_id': null,
        'is_agency_owner': false,
        'is_host_agent': false,
      });
      return true;
    } catch (e) {
      debugPrint('[SupabaseService] deleteAndExitAgencyByOwner error: $e');
      return false;
    }
  }

  Future<bool> exitAgencyAsMember(
      {required String agencyId, required String userId}) async {
    try {
      // 1. Delete from host_agency_members via Supabase Client & REST
      try {
        if (agencyId.isNotEmpty) {
          await _sb
              .from('host_agency_members')
              .delete()
              .eq('agency_id', agencyId)
              .or('user_id.eq.$userId,host_uid.eq.$userId');
        }
        await _sb
            .from('host_agency_members')
            .delete()
            .or('user_id.eq.$userId,host_uid.eq.$userId');
      } catch (e) {
        debugPrint(
            '[SupabaseService] delete host_agency_members client error: $e');
      }
      try {
        if (agencyId.isNotEmpty) {
          await SafeHttp.delete(
            Uri.parse(
                '$_baseUrl/rest/v1/host_agency_members?agency_id=eq.$agencyId&user_id=eq.$userId'),
            headers: _headers,
          );
          await SafeHttp.delete(
            Uri.parse(
                '$_baseUrl/rest/v1/host_agency_members?agency_id=eq.$agencyId&host_uid=eq.$userId'),
            headers: _headers,
          );
        }
        await SafeHttp.delete(
          Uri.parse('$_baseUrl/rest/v1/host_agency_members?user_id=eq.$userId'),
          headers: _headers,
        );
        await SafeHttp.delete(
          Uri.parse(
              '$_baseUrl/rest/v1/host_agency_members?host_uid=eq.$userId'),
          headers: _headers,
        );
      } catch (e) {
        debugPrint('[SupabaseService] delete host_agency_members error: $e');
      }

      // 2. Delete any applications from agency_applications
      try {
        if (agencyId.isNotEmpty) {
          await _sb
              .from('agency_applications')
              .delete()
              .eq('agency_id', agencyId)
              .or('user_id.eq.$userId,applicant_uid.eq.$userId');
        }
        await _sb
            .from('agency_applications')
            .delete()
            .or('user_id.eq.$userId,applicant_uid.eq.$userId');
      } catch (_) {}
      try {
        await SafeHttp.delete(
          Uri.parse('$_baseUrl/rest/v1/agency_applications?user_id=eq.$userId'),
          headers: _headers,
        );
      } catch (_) {}

      // 3. Clear agency in users table completely
      try {
        await _sb.from('users').update({
          'agency_id': null,
          'host_agency_id': null,
          'is_host_agent': false,
        }).or('uid.eq.$userId,id.eq.$userId');
      } catch (e) {
        debugPrint('[SupabaseService] _sb updateUser agency error: $e');
      }
      try {
        await _ds.updateUser(userId, {
          'agency_id': null,
          'is_host_agent': false,
        });
        await SafeHttp.patch(
          Uri.parse('$_baseUrl/rest/v1/users?uid=eq.$userId'),
          headers: _headers,
          body: jsonEncode({'agency_id': null, 'is_host_agent': false}),
        );
      } catch (e) {
        debugPrint('[SupabaseService] updateUser agency_id error: $e');
      }

      return true;
    } catch (e) {
      debugPrint('[SupabaseService] exitAgencyAsMember error: $e');
      return false;
    }
  }

  Future<bool> updateAgencyMemberRole({
    required String agencyId,
    required String memberUid,
    required String newRole,
  }) async {
    try {
      final res = await SafeHttp.patch(
        Uri.parse(
            '$_baseUrl/rest/v1/host_agency_members?agency_id=eq.$agencyId&user_id=eq.$memberUid'),
        headers: _headers,
        body: jsonEncode({'role': newRole}),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseService] updateAgencyMemberRole error: $e');
      return false;
    }
  }

  Future<bool> transferCoinsToMember({
    required String agentUid,
    required String targetUserNoOrId,
    required int amount,
  }) async {
    try {
      final agent = await _ds.getUser(agentUid);
      if (agent == null || agent.coins < amount) return false;

      UserModel? target = await _ds.getUser(targetUserNoOrId);
      if (target == null) {
        final list = await _ds.getUsersByCustomId(targetUserNoOrId);
        if (list.isNotEmpty) target = list.first;
      }
      if (target == null) return false;

      // خصم من الوكيل وإضافة للمستلم
      await _ds.updateUser(agentUid, {'coins': agent.coins - amount});
      await _ds.updateUser(target.uid, {'coins': target.coins + amount});

      await _ds.recordAgentTransaction(
        agentId: agentUid,
        targetUid: target.uid,
        targetCustomId: target.customId,
        amountCoins: amount,
      );

      return true;
    } catch (e) {
      debugPrint('[SupabaseService] transferCoinsToMember error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // ADDITIONAL ROOM, MESSAGING & SOCIAL OPERATIONS (SUPABASE)
  // ═══════════════════════════════════════════════════════

  final Map<String, StoreItemModel> _storeItems = {};

  StoreItemModel? getStoreItemSync(String itemId) => _storeItems[itemId];

  Future<void> addCoins(String uid, int amount) async {
    final u = await _ds.getUser(uid);
    if (u != null) {
      await _ds.updateUser(uid, {'coins': u.coins + amount});
    }
  }

  Future<bool> deductCoins(String uid, int amount, [String? reason]) async {
    final u = await _ds.getUser(uid);
    if (u != null && u.coins >= amount) {
      await _ds.updateUser(uid, {'coins': math.max(0, u.coins - amount).toInt()});
      return true;
    }
    return false;
  }

  Future<String> createRoom({
    required String name,
    String description = '',
    String roomPhotoUrl = '',
    required String hostUid,
    required String hostCustomId,
    required String hostName,
    String hostPhotoUrl = '',
    bool isLocked = false,
    String password = '',
    String category = '',
    String country = '',
  }) async {
    String resolvedRoomId =
        (hostCustomId.trim().isNotEmpty && hostCustomId.trim() != 'null')
            ? hostCustomId.trim()
            : hostUid;
    final r = RoomModel(
      roomId: resolvedRoomId,
      name: name,
      description: description,
      roomPhotoUrl: roomPhotoUrl,
      hostUid: hostUid,
      hostName: hostName,
      hostPhotoUrl: hostPhotoUrl,
      isLocked: isLocked,
      password: password,
      category: category,
      country: country,
    );
    await _ds.createRoom(r);
    return resolvedRoomId;
  }

  Future<bool> migrateUserRoomId(String hostUid, String newRoomId) =>
      _ds.migrateUserRoomId(hostUid, newRoomId);

  Future<RoomModel?> getRoomByHost(String hostUid) =>
      _ds.getRoomByHostUid(hostUid);

  Stream<List<RoomModel>> allRoomsStream() async* {
    final rt = SupabaseRealtimeService.instance;
    rt.subscribeTable(table: 'rooms', topic: 'rooms');
    try {
      while (true) {
        try {
          final rooms = await _ds.getAllRooms();
          yield rooms;
        } catch (_) {}
        // مع Realtime: يصل التحديث لحظياً عند أي تغيير في rooms،
        // والـ polling يصبح مجرد شبكة أمان بطيئة (8 ثوانٍ).
        // الكاش داخل getAllRooms يخفف الحمل أكثر (15 ثانية).
        await rt.waitForTableChange(
          topic: 'rooms',
          tables: const {'rooms'},
          fallback: const Duration(seconds: 8),
          safety: const Duration(seconds: 20),
        );
      }
    } finally {
      rt.unsubscribeTopic('rooms');
    }
  }

  Stream<RoomModel?> roomStream(String roomId) async* {
    final rt = SupabaseRealtimeService.instance;
    final topic = 'rooms:$roomId';
    rt.subscribeTable(
      table: 'rooms',
      topic: topic,
      filter: 'room_id=eq.$roomId',
    );
    try {
      while (true) {
        try {
          final room = await _ds.getRoom(roomId);
          yield room;
        } catch (_) {}
        await rt.waitForTableChange(
          topic: topic,
          tables: const {'rooms'},
          fallback: const Duration(seconds: 2),
          safety: const Duration(seconds: 10),
        );
      }
    } finally {
      rt.unsubscribeTopic(topic);
    }
  }

  Future<bool> updateRoom(String roomId, Map<String, dynamic> updates) =>
      _ds.updateRoom(roomId, updates);

  Future<bool> clearRoomCharisma(String roomId, {int? clearedAt}) =>
      _ds.clearRoomCharisma(roomId, clearedAt: clearedAt);

  Future<bool> clearRoomMessages(String roomId, {int? clearedAt}) =>
      _ds.clearRoomMessages(roomId, clearedAt: clearedAt);

  Future<void> updateRoomBackground(String roomId, String bgUrl) async {
    await _ds.updateRoom(roomId, {'bg_image': bgUrl});
  }

  Future<void> updateRoomSeatStyle(String roomId, int seatStyleIndex) =>
      _ds.updateRoom(roomId, {'seat_style': seatStyleIndex.toString()});

  Future<void> updateRoomSeatCount(String roomId, int count) =>
      _ds.updateRoom(roomId, {'seat_count': count});

  Future<void> followRoom(String uid, String roomId) async {
    final u = await _ds.getUser(uid);
    if (u != null) {
      final list = List<String>.from(u.followedRooms);
      if (!list.contains(roomId)) {
        list.add(roomId);
        await _ds.updateUser(uid, {'followed_rooms': list});
      }
    }
  }

  Future<void> unfollowRoom(String uid, String roomId) async {
    final u = await _ds.getUser(uid);
    if (u != null) {
      final list = List<String>.from(u.followedRooms)..remove(roomId);
      await _ds.updateUser(uid, {'followed_rooms': list});
    }
  }

  Future<bool> joinRoom(String roomId, UserModel user) =>
      _ds.joinRoom(roomId, user);

  Future<List<UserModel>> getRoomMembers(String roomId) =>
      _ds.getRoomMembers(roomId);

  Stream<List<UserModel>> roomMembersStream(String roomId) async* {
    final rt = SupabaseRealtimeService.instance;
    final topic = 'room_members:$roomId';
    rt.subscribeTable(
      table: 'room_members',
      topic: topic,
      filter: 'room_id=eq.$roomId',
    );
    // ✅ تحديث تزايدي من أحداث Realtime: كل heartbeat حضور (30s) لكل
    //    مستخدم كان يوقظ كل العملاء فيعيد كل واحد جلب القائمة كاملة —
    //    N طلبات REST لكل موجة ping. الآن نطبّق سجل الحدث على الكاش
    //    المحلي مباشرة، والجلب الكامل احتياط كل 30s فقط.
    final pending = <RealtimeChange>[];
    final changesSub = rt.changes.listen((c) {
      if (c.table == 'room_members') pending.add(c);
    });
    final byUid = <String, UserModel>{};
    try {
      // جلب أولي كامل
      try {
        final members = await _ds.getRoomMembers(roomId);
        byUid
          ..clear()
          ..addEntries(members.map((m) => MapEntry(m.uid, m)));
        yield members;
      } catch (_) {}

      var lastFullFetch = DateTime.now();
      while (true) {
        // طبّق كل تغييرات Realtime المتراكمة على الكاش
        if (pending.isNotEmpty) {
          var needsFull = false;
          for (final c in pending) {
            final rec = c.record;
            if (c.type == 'DELETE') {
              final delUid = (c.oldRecord['uid'] ?? rec['uid'])?.toString() ?? '';
              if (delUid.isNotEmpty) {
                byUid.remove(delUid);
              } else {
                needsFull = true;
              }
              continue;
            }
            final uid = rec['uid']?.toString() ?? '';
            if (uid.isEmpty) {
              needsFull = true;
              continue;
            }
            try {
              final m = UserModel.fromMap(Map<String, dynamic>.from(rec));
              if (m.uid.isNotEmpty) byUid[m.uid] = m;
            } catch (_) {
              needsFull = true;
            }
          }
          pending.clear();
          if (needsFull) {
            // سجل DELETE/تالف — نجلب القائمة كاملة للاتساق
            try {
              final members = await _ds.getRoomMembers(roomId);
              byUid
                ..clear()
                ..addEntries(members.map((m) => MapEntry(m.uid, m)));
              lastFullFetch = DateTime.now();
              yield members;
              continue;
            } catch (_) {}
          }
          yield byUid.values.toList();
          continue;
        }

        // انتظر حدثاً واحداً أو انتهاء المهلة ثم أعد الفحص.
        // قناة ميتة → دورة قصيرة 5s (سلوك الـ polling القديم).
        // قناة حية → أحداث فورية + مزامنة كاملة كل 30s كأمان.
        final channelLive = rt.isTopicLive(topic);
        try {
          await rt.changes
              .firstWhere((c) => c.table == 'room_members')
              .timeout(channelLive
                  ? const Duration(seconds: 30)
                  : const Duration(seconds: 5));
        } catch (_) {}

        if (!channelLive ||
            DateTime.now().difference(lastFullFetch) >
                const Duration(seconds: 30)) {
          try {
            final members = await _ds.getRoomMembers(roomId);
            byUid
              ..clear()
              ..addEntries(members.map((m) => MapEntry(m.uid, m)));
            lastFullFetch = DateTime.now();
            yield members;
          } catch (_) {}
        }
      }
    } finally {
      changesSub.cancel();
      rt.unsubscribeTopic(topic);
    }
  }

  Stream<Map<int, Map<String, dynamic>>> seatsStream(String roomId) async* {
    final rt = SupabaseRealtimeService.instance;
    final topic = 'room_seats:$roomId';
    rt.subscribeTable(
      table: 'room_seats',
      topic: topic,
      filter: 'room_id=eq.$roomId',
    );

    // كاش محلي سريع لحالة المقاعد لتحديثها لحظياً عند وصول broadcast بدون انتظار استعلام DB
    final Map<int, Map<String, dynamic>> localSeatState = {};

    // الاستماع لأحداث البث اللحظية للمقاعد (أخذ مقعد / مغادرة / كتم)
    final broadcastSub = rt.broadcasts.listen((event) {
      if (event['event'] == 'seat_change') {
        final data = event['data'];
        if (data is Map) {
          final action = data['action']?.toString();
          final seatIdx = (data['seat_index'] as num?)?.toInt() ?? -1;
          if (action == 'take' && seatIdx >= 0) {
            final user = data['user'];
            if (user is Map) {
              localSeatState[seatIdx] = Map<String, dynamic>.from(user);
            }
          } else if (action == 'leave') {
            if (seatIdx >= 0) {
              localSeatState.remove(seatIdx);
            } else {
              final uid = data['user']?['uid']?.toString() ?? data['user']?['id']?.toString();
              if (uid != null && uid.isNotEmpty) {
                localSeatState.removeWhere((_, u) => (u['uid'] == uid || u['id'] == uid));
              }
            }
          } else if (action == 'mute' && seatIdx >= 0 && localSeatState.containsKey(seatIdx)) {
            localSeatState[seatIdx]!['is_muted'] = data['is_muted'] == true;
          }
        }
      }
    });

    try {
      while (true) {
        try {
          final seats = await _ds.getSeats(roomId);
          if (seats != null) {
            localSeatState.clear();
            localSeatState.addAll(seats);
            yield Map<int, Map<String, dynamic>>.from(localSeatState);
          } else if (localSeatState.isNotEmpty) {
            yield Map<int, Map<String, dynamic>>.from(localSeatState);
          }
        } catch (_) {
          if (localSeatState.isNotEmpty) {
            yield Map<int, Map<String, dynamic>>.from(localSeatState);
          }
        }
        await rt.waitForTableChange(
          topic: topic,
          tables: const {'room_seats'},
          fallback: const Duration(seconds: 2),
          safety: const Duration(seconds: 5),
        );
      }
    } finally {
      broadcastSub.cancel();
      rt.unsubscribeTopic(topic);
    }
  }

  Future<Map<int, Map<String, dynamic>>?> getSeats(String roomId) =>
      _ds.getSeats(roomId);

  Future<bool> takeSeat(String roomId, int seatIndex, UserModel user) =>
      _ds.takeSeat(roomId: roomId, seatIndex: seatIndex, user: user);

  Future<bool> restoreSeatIfFree({
    required String roomId,
    required int seatIndex,
    required UserModel user,
  }) =>
      _ds.restoreSeatIfFree(
        roomId: roomId,
        seatIndex: seatIndex,
        user: user,
      );

  Future<bool> leaveSeat(String roomId, int seatIndex) =>
      _ds.leaveSeat(roomId, seatIndex);

  Future<bool> toggleSeatLock(String roomId, int seatIndex, bool locked) =>
      _ds.toggleSeatLock(roomId, seatIndex, locked);

  Future<void> sendSeatEmoji(
    String roomId,
    String emoji,
    String senderUid,
    String senderName,
    String senderPhotoUrl, {
    int? seatIndex,
  }) async {
    await _ds.sendMessage(MessageModel(
      msgId: const Uuid().v4(),
      roomId: roomId,
      senderUid: senderUid,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      type: 'seat_emoji',
      text: emoji,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<bool> sendMessage(
    String roomId,
    String text,
    String senderUid,
    String senderName,
    String senderPhotoUrl, {
    String? type,
    String? imageUrl,
    Map<String, dynamic>? giftPayload,
    String? activeBubble,
  }) async {
    return _ds.sendMessage(MessageModel(
      msgId: const Uuid().v4(),
      roomId: roomId,
      senderUid: senderUid,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      type: type ?? 'text',
      text: text,
      imageUrl: imageUrl,
      giftPayload: giftPayload,
      activeBubble: activeBubble,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<bool> sendImageMessage(String roomId, String imageUrl,
      String senderUid, String senderName, String senderPhotoUrl,
      {String type = 'image'}) {
    return sendMessage(roomId, '', senderUid, senderName, senderPhotoUrl,
        type: type, imageUrl: imageUrl);
  }

  Future<int?> fetchServerTimeMs() => _ds.fetchServerTimeMs();

  Stream<List<MessageModel>> messagesStream(String roomId,
      {String? since}) async* {
    var sinceMs = int.tryParse(since ?? '');
    // ✅ Fallback: إذا لم يُمرّر since (مثلاً فشل وقت السيرفر)، افتراضياً آخر ساعة
    // هذا يمنع تحميل رسائل قديمة جداً عند إعادة الدخول
    sinceMs ??= DateTime.now().millisecondsSinceEpoch - 3600000; // 1 ساعة
    
    final rt = SupabaseRealtimeService.instance;
    final topic = 'room_messages:$roomId';
    // Realtime يدفع الرسائل الجديدة فوراً لشاشة الغرفة (insertRealtimeRoomMessage)
    // فيكفي هنا شبكة أمان بطيئة بدل طلب REST كل 150ms.
    rt.subscribeRoom(roomId);
    try {
      while (true) {
        try {
          final msgs = await _ds.getRoomMessages(roomId, sinceMs: sinceMs);
          if (msgs.isNotEmpty) {
            var newest = sinceMs ?? 0;
            for (final m in msgs) {
              if (m.timestamp > newest) newest = m.timestamp;
            }
            // تداخل 2 ثانية: رسائل قد تُلتزَم بترتيب مختلف عن ترتيب
            // created_at (طوابع معاملات Postgres) خاصة في دفعات الإرسال
            // الكبيرة — بدون تداخل كافٍ قد تُفوَّت رسائل نهائياً.
            if (newest > (sinceMs ?? 0)) sinceMs = newest - 2000;
          } else {
            // sinceMs already has a default, no need for fallback
          }
          yield msgs;
        } catch (_) {}
        await rt.waitForTableChange(
          topic: topic,
          tables: const {'room_messages'},
          fallback: const Duration(milliseconds: 500),
          safety: const Duration(milliseconds: 2500),
        );
      }
    } finally {
      rt.unsubscribeTopic(topic);
    }
  }

  Stream<List<gm.SentGiftModel>> sentGiftsStream(String roomId) async* {
    final byId = <String, gm.SentGiftModel>{};
    DateTime? newest;
    bool firstLoad = true;
    int failures = 0;
    final rt = SupabaseRealtimeService.instance;
    final topic = 'sent_gifts:$roomId';
    rt.subscribeTable(
      table: 'sent_gifts',
      topic: topic,
      filter: 'room_id=eq.$roomId',
    );
    try {
      while (true) {
        var ok = false;
        try {
          final batch = await _ds.getSentGifts(
            roomId,
            limit: firstLoad ? 500 : 100,
            after: firstLoad || newest == null
                ? null
                : newest.subtract(const Duration(seconds: 2)),
          );
          if (firstLoad) byId.clear();
          for (final g in batch) {
            byId[g.id] = g;
            if (newest == null || g.timestamp.isAfter(newest)) {
              newest = g.timestamp;
            }
          }
          if (byId.length > 500) {
            final sorted = byId.values.toList()
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
            byId
              ..clear()
              ..addEntries(sorted.take(500).map((g) => MapEntry(g.id, g)));
          }
          firstLoad = false;
          final merged = byId.values.toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
          yield merged;
          ok = true;
        } catch (_) {}
        failures = ok ? 0 : (failures + 1 > 3 ? 3 : failures + 1);
        if (ok) {
          // مع Realtime يصبح الجلب البطيء شبكة أمان فقط (2.5 ثانية)
          await rt.waitForTableChange(
            topic: topic,
            tables: const {'sent_gifts'},
            fallback: const Duration(milliseconds: 700),
            safety: const Duration(milliseconds: 2500),
          );
        } else {
          await Future.delayed(
            Duration(milliseconds: const [700, 1500, 3000, 5000][failures]),
          );
        }
      }
    } finally {
      rt.unsubscribeTopic(topic);
    }
  }

  Stream<List<gm.GiftModel>> giftsStream() async* {
    int failures = 0;
    bool firstEmission = true;
    while (true) {
      var ok = false;
      try {
        // ✅ أول قراءة من الشبكة (بدون كاش) حتى يظهر سعر الهدية في
        //    الصندوق مطابقاً لقيمة لوحة التحكم فور فتح الغرفة، ثم نكتفي
        //    بالكاش في الدورات التالية لتقليل الضغط على الشبكة.
        final gifts = await _ds.getGifts(allowCache: !firstEmission);
        firstEmission = false;
        yield gifts;
        ok = true;
      } catch (_) {}
      failures = ok ? 0 : (failures + 1 > 3 ? 3 : failures + 1);
      final delayMs =
          ok ? 10000 : const [10000, 20000, 30000, 60000][failures];
      await Future.delayed(Duration(milliseconds: delayMs));
    }
  }

  Stream<List<GiftCategory>> giftCategoriesStream() async* {
    // ✅ القسم المضاف من لوحة التحكم لازم يظهر فوراً: كاش الذاكرة مدته
    //    10 دقائق، فالقراءة بالكاش كانت تُخفي أي إضافة حتى تنتهي المدة.
    //    - أول قراءة + أي حدث Realtime ⇒ شبكة إجبارية (allowCache: false)
    //    - الدورات العادية ⇒ من الكاش لتقليل الضغط
    const topic = 'gift_categories:all';
    final rt = SupabaseRealtimeService.instance;
    rt.subscribeTable(
      table: 'gift_categories',
      topic: topic,
      events: const ['INSERT', 'UPDATE', 'DELETE'],
    );
    bool forceNetwork = true;
    final sub = rt.changes.listen((change) {
      if (change.table == 'gift_categories') forceNetwork = true;
    });
    try {
      int failures = 0;
      while (true) {
        var ok = false;
        try {
          // نقرأ العلم ونصفّره **قبل** الجلب: أي تغيير يصل أثناء الجلب
          // يرفعه من جديد فيُجبر الدورة الجاية على القراءة من الشبكة.
          final shouldForce = forceNetwork;
          forceNetwork = false;
          final cats = await _ds.getGiftCategories(allowCache: !shouldForce);
          yield cats;
          ok = true;
        } catch (_) {}
        failures = ok ? 0 : (failures + 1 > 3 ? 3 : failures + 1);
        final delayMs =
            ok ? 20000 : const [20000, 30000, 45000, 60000][failures];
        // استيقاظ فوري عند INSERT/UPDATE/DELETE على gift_categories،
        // وإلا ننتظر المهلة الدورية (محاكاة الـ polling القديم).
        await rt.waitForTableChange(
          topic: topic,
          tables: const {'gift_categories'},
          fallback: Duration(milliseconds: delayMs),
        );
      }
    } finally {
      sub.cancel();
      rt.unsubscribeTopic(topic);
    }
  }

  Stream<List<StoreItemModel>> storeItemsStream() async* {
    while (true) {
      try {
        final items = await _ds.getStoreItems();
        for (final it in items) {
          _storeItems[it.itemId] = it;
        }
        yield items;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 30));
    }
  }

  Future<List<StoreItemModel>> getStoreItems() async {
    final items = await _ds.getStoreItems();
    for (final it in items) {
      _storeItems[it.itemId] = it;
    }
    return items;
  }

  Future<({bool success, num coinsReceived, String? error})>
      exchangeDiamondsToCoins({
    required String uid,
    required int diamonds,
    int? rate,
    double? coinsPerDiamond,
    int? minDiamonds,
  }) async {
    final effectiveMultiplier = (coinsPerDiamond != null && coinsPerDiamond > 0)
        ? coinsPerDiamond
        : (DynamicConfigService().coinsPerDiamond > 0
            ? DynamicConfigService().coinsPerDiamond
            : (rate != null && rate > 0
                ? (rate == 1 ? 1.0 : 1.0 / rate)
                : 1.0));

    final effectiveMin = minDiamonds ?? (rate != null && rate > 0 ? rate : 1);

    if (diamonds < 1) {
      return (
        success: false,
        coinsReceived: 0,
        error: 'يرجى إدخال كمية ألماس صحيحة'
      );
    }
    if (diamonds < effectiveMin) {
      return (
        success: false,
        coinsReceived: 0,
        error: 'الحد الأدنى للتبديل هو $effectiveMin ألماس'
      );
    }

    final idem = 'wallet_xchg_${uid}_${DateTime.now().millisecondsSinceEpoch}';

    // 1) المسار الذري: RPC يخصم من محفظة العضو فقط ويضيف الكوينز للشخصية
    try {
      final resp = await _sb.rpc('agency_exchange_diamonds_v2', params: {
        'p_diamonds': diamonds,
        'p_idempotency_key': idem,
        'p_user_id': uid,
        'p_coins_per_diamond': effectiveMultiplier,
      });
      if (resp is Map) {
        final m = Map<String, dynamic>.from(resp);
        if (m['success'] == true) {
          final coins = (m['coins_received'] as num?)?.toDouble() ?? 0;
          unawaited(AgencyTargetEvaluator.evaluateHostTargets(uid)
              .catchError((_) {}));
          return (success: true, coinsReceived: coins, error: null);
        }
        final rpcError = (m['error'] ?? 'exchange_failed').toString();
        if (rpcError == 'insufficient_balance') {
          final available = (m['available'] as num?)?.toInt();
          return (
            success: false,
            coinsReceived: 0,
            error: available != null
                ? 'المتاح للتبديل من التارجت الشهري: $available ألماس'
                : 'الرصيد المتاح للتبديل غير كافٍ',
          );
        }
        if (rpcError != 'unauthorized' && rpcError != 'forbidden') {
          return (
            success: false,
            coinsReceived: 0,
            error: rpcError,
          );
        }
      }
    } catch (e) {
      debugPrint(
          '[exchangeDiamondsToCoins] agency_exchange_diamonds_v2 RPC error: $e');
    }

    // 2) Fallback متوافق مع مخطط قديم — نفس المعادلة وبدون خصم مزدوج
    try {
      try {
        final existing = await _sb
            .from('diamond_exchange_log')
            .select('coins')
            .eq('idempotency_key', idem)
            .maybeSingle();
        if (existing != null) {
          return (
            success: true,
            coinsReceived: (existing['coins'] as num?)?.toDouble() ?? 0,
            error: null,
          );
        }
      } catch (_) {}

      final uRow = await _sb
          .from('users')
          .select('diamonds, coins')
          .or('uid.eq.$uid,id.eq.$uid')
          .maybeSingle();
      final curDiamonds = (uRow?['diamonds'] as num?)?.toInt() ?? 0;
      final curCoins = (uRow?['coins'] as num?)?.toDouble() ?? 0;

      final memRows = await _sb
          .from('host_agency_members')
          .select(
              'id, agency_id, diamonds_balance, diamonds_available, diamonds_earned_monthly, unpacked_target_diamonds')
          .or('host_uid.eq.$uid,user_id.eq.$uid')
          .limit(1);
      final member = memRows.isNotEmpty
          ? Map<String, dynamic>.from(memRows.first as Map)
          : null;

      // عضو وكالة: الرصيد من محفظة الوكالة فقط. غير عضو: من المحفظة الشخصية.
      final memberBalance = member == null
          ? curDiamonds
          : ((member['diamonds_available'] as num?)?.toInt() ??
              (member['diamonds_balance'] as num?)?.toInt() ??
              0);
      final memberMonthly =
          (member?['diamonds_earned_monthly'] as num?)?.toInt() ?? 0;
      final exchangeable = member == null
          ? memberBalance
          : (memberBalance < memberMonthly ? memberBalance : memberMonthly);

      if (exchangeable < diamonds) {
        return (
          success: false,
          coinsReceived: 0,
          error: 'المتاح للتبديل من التارجت الشهري غير كافٍ'
        );
      }

      final coinsToReceive =
          (diamonds * effectiveMultiplier * 100).round() / 100;
      if (coinsToReceive <= 0) {
        return (
          success: false,
          coinsReceived: 0,
          error: 'كمية الألماس غير كافية للحصول على كوينز'
        );
      }
      final newDiamonds =
          (memberBalance - diamonds).clamp(0, 999999999).toInt();
      final newCoins = curCoins + coinsToReceive;

      if (member == null) {
        await _sb.from('users').update({
          'diamonds': newDiamonds,
          'coins': newCoins.round(),
        }).or('uid.eq.$uid,id.eq.$uid');
      } else {
        // لا نمسّ users.diamonds لعضو الوكالة — الكوينز فقط
        await _sb.from('users').update({
          'coins': newCoins.round(),
        }).or('uid.eq.$uid,id.eq.$uid');
      }

      if (member != null) {
        final curMonthly =
            (member['diamonds_earned_monthly'] as num?)?.toInt() ?? 0;
        final curUnpacked =
            (member['unpacked_target_diamonds'] as num?)?.toInt() ?? 0;

        await _sb.from('host_agency_members').update({
          'diamonds': newDiamonds,
          'diamonds_balance': newDiamonds,
          'diamonds_available': newDiamonds,
          'diamonds_earned_monthly':
              (curMonthly - diamonds).clamp(0, 999999999),
          'unpacked_target_diamonds': curUnpacked + diamonds,
          'has_unpacked_target': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', member['id']);

        final agencyId = member['agency_id']?.toString() ?? '';
        if (agencyId.isNotEmpty) {
          try {
            await _sb.from('agency_diamond_ledger').insert({
              'agency_id': agencyId,
              'user_id': uid,
              'txn_type': 'exchange',
              'amount': diamonds,
              'direction': -1,
              'balance_after': newDiamonds,
              'note': 'تبديل ألماس إلى كوينز',
              'idempotency_key': idem,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            });
          } catch (_) {}
        }
      }

      try {
        await _sb.from('diamond_exchange_log').insert({
          'user_id': uid,
          'diamonds': diamonds,
          'coins': coinsToReceive.round(),
          'balance_after': newDiamonds,
          'idempotency_key': idem,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (_) {}

      unawaited(AgencyTargetEvaluator.evaluateHostTargets(uid));
      return (success: true, coinsReceived: coinsToReceive, error: null);
    } catch (e) {
      return (success: false, coinsReceived: 0, error: e.toString());
    }
  }

  Stream<List<Map<String, dynamic>>> storeCategoriesStream() async* {
    yield [];
  }

  Stream<List<BannerConfig>> bannersStream() async* {
    while (true) {
      try {
        final banners = await _ds.getBanners();
        yield banners;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 30));
    }
  }

  Stream<List<Map<String, dynamic>>> entrancesStream(String roomId) async* {
    if (roomId.isEmpty) return;
    final rt = SupabaseRealtimeService.instance;
    final topic = 'entrances:$roomId';
    rt.subscribeTable(
      table: 'room_messages',
      topic: topic,
      filter: "room_id=eq.$roomId,type=eq.entrance",
      events: const ['INSERT'],
    );
    try {
      // Initial fetch for any entrance messages since joining
      final msgs = await _ds.getRoomMessages(roomId, limit: 50);
      final entranceMsgs = msgs.where((m) => m.type == 'entrance').toList();
      if (entranceMsgs.isNotEmpty) {
        yield entranceMsgs.map((m) => {
          'uid': m.senderUid,
          'name': m.senderName,
          'photoUrl': m.senderPhotoUrl,
          'entranceItem': m.imageUrl,
          'carItem': m.giftPayload?['carItem'],
          'timestamp': m.timestamp,
          'msgId': m.msgId,
        }).toList();
      }
      while (true) {
        await rt.waitForTableChange(
          topic: topic,
          tables: const {'room_messages'},
          fallback: const Duration(milliseconds: 500),
          safety: const Duration(seconds: 8),
        );
        // Fetch new entrance messages
        final newMsgs = await _ds.getRoomMessages(roomId, limit: 20);
        final newEntrances = newMsgs.where((m) => m.type == 'entrance').toList();
        if (newEntrances.isNotEmpty) {
          yield newEntrances.map((m) => {
            'uid': m.senderUid,
            'name': m.senderName,
            'photoUrl': m.senderPhotoUrl,
            'entranceItem': m.imageUrl,
            'carItem': m.giftPayload?['carItem'],
            'timestamp': m.timestamp,
            'msgId': m.msgId,
          }).toList();
        }
      }
    } finally {
      rt.unsubscribeTopic(topic);
    }
  }

  Future<void> logEntrance(
    String roomId,
    String uid,
    String name,
    String photoUrl,
    String? entranceItem, {
    String? carItem,
  }) async {
    if (roomId.isEmpty || uid.isEmpty) return;
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      await _ds.sendMessage(MessageModel(
        // ✅ msg_id عمود UUID في room_messages — أي قيمة غير UUID
        //    (مثل 'entrance_...') كان يرفضها PostgREST 400 فلا تُسجَّل
        //    رسالة الدخول أبداً ولا تظهر مؤثرات الدخول للآخرين.
        msgId: const Uuid().v4(),
        roomId: roomId,
        senderUid: uid,
        senderName: name,
        senderPhotoUrl: photoUrl,
        text: 'joined',
        type: 'entrance',
        timestamp: ts,
        imageUrl: entranceItem?.isNotEmpty == true ? entranceItem : null,
        giftPayload: carItem?.isNotEmpty == true ? {'carItem': carItem} : null,
      ));
    } catch (_) {}
  }

  Future<void> logExit(
    String roomId,
    String name, {
    String? uid,
    String? photoUrl,
  }) async {
    if (roomId.isEmpty || name.isEmpty) return;
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      await _ds.sendMessage(MessageModel(
        msgId: const Uuid().v4(),
        roomId: roomId,
        senderUid: uid ?? 'system',
        senderName: name,
        senderPhotoUrl: photoUrl ?? '',
        text: 'left',
        type: 'entrance',
        timestamp: ts,
      ));
    } catch (_) {}
  }

  Future<void> sendSeatInvite(
    String roomId, {
    required String inviterUid,
    required String inviterName,
    required String targetUid,
    String? targetName,
    required int seatIndex,
  }) async {
    await sendNotification(
      uid: targetUid,
      type: 'seat_invite',
      actorUid: inviterUid,
      title: 'دعوة للصعود على المايك',
      body: 'دعاك $inviterName للصعود على المايك رقم ${seatIndex + 1}',
      data: {'room_id': roomId, 'seat_index': seatIndex},
    );
  }

  Stream<bool> userRoomBanStream(String roomId, String uid) async* {
    while (true) {
      bool banned = false;
      try {
        banned = await isUserBlockedFromRoom(roomId, uid);
      } catch (_) {}
      yield banned;
      if (banned) return;
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  Stream<List<Map<String, dynamic>>> roomBlocksStream(String roomId) async* {
    while (true) {
      try {
        final url = Uri.parse(
            '$_baseUrl/rest/v1/room_blocks?room_id=eq.$roomId&select=*&order=created_at.desc');
        final res = await SafeHttp.get(url, headers: _headers);
        if (res.statusCode == 200) {
          final List list = jsonDecode(res.body);
          yield list
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 4));
    }
  }

  Future<void> kickUserFromRoom(
    String roomId,
    String kickerUid,
    String targetUid, {
    String kickerName = '',
    String targetName = '',
    bool addToBlacklist = false,
    String? reason,
  }) async {
    // Remove the seat + membership first so every client sees them gone.
    await _ds.leaveSeatForUser(roomId, targetUid);
    await _ds.leaveRoom(roomId, targetUid);

    final kicker = kickerName.isNotEmpty ? kickerName : 'المشرف';
    final target = targetName.isNotEmpty ? targetName : 'مستخدم';
    final text = 'تم طرد $target من الغرفة بواسطة $kicker';
    unawaited(_ds
        .sendMessage(MessageModel(
          msgId: const Uuid().v4(),
          roomId: roomId,
          senderUid: 'system',
          senderName: 'نظام',
          senderPhotoUrl: '',
          type: 'room_kick',
          text: text,
          giftPayload: {
            'kickedUid': targetUid,
            'kicked_uid': targetUid,
            'kicked_name': target,
            'kickerUid': kickerUid,
            'kicker_uid': kickerUid,
            'kicker_name': kicker,
            'reason': reason ?? '',
          },
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ))
        .catchError((_) => false));

    unawaited(sendNotification(
      uid: targetUid,
      type: 'room_kick',
      actorUid: kickerUid,
      title: 'تم طردك من الغرفة',
      body: reason != null && reason.isNotEmpty
          ? '$text — السبب: $reason'
          : text,
      data: {
        'room_id': roomId,
        'kicked_uid': targetUid,
        'kicker_name': kicker,
        'reason': reason ?? '',
      },
    ));

    if (addToBlacklist) {
      await blockUserFromRoom(roomId, kickerUid, targetUid, reason: reason);
    }
  }

  Future<void> blockUserFromRoom(
      String roomId, String blockerUid, String blockedUid,
      {String? reason, int durationMinutes = 60}) async {
    try {
      final deleteUrl = Uri.parse(
          '$_baseUrl/rest/v1/room_blocks?room_id=eq.$roomId&blocked_uid=eq.$blockedUid');
      await SafeHttp.delete(deleteUrl, headers: _headers);
      await SafeHttp.post(
        Uri.parse('$_baseUrl/rest/v1/room_blocks'),
        headers: _headers,
        body: jsonEncode({
          'room_id': roomId,
          'blocker_uid': blockerUid,
          'blocked_uid': blockedUid,
          'reason': reason ?? '',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('[SupabaseService] blockUserFromRoom error: $e');
    }
    await _ds.leaveSeatForUser(roomId, blockedUid);
    await _ds.leaveRoom(roomId, blockedUid);
  }

  Future<void> unblockUserFromRoom(String roomId, String blockedUid) async {
    try {
      final url = Uri.parse(
          '$_baseUrl/rest/v1/room_blocks?room_id=eq.$roomId&blocked_uid=eq.$blockedUid');
      await SafeHttp.delete(url, headers: _headers);
    } catch (e) {
      debugPrint('[SupabaseService] unblockUserFromRoom error: $e');
    }
  }

  Future<bool> isUserBlockedFromRoom(String roomId, String uid) async {
    try {
      final url = Uri.parse(
          '$_baseUrl/rest/v1/room_blocks?room_id=eq.$roomId&blocked_uid=eq.$uid&select=id');
      final res = await SafeHttp.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.isNotEmpty;
      }
    } catch (e) {
      debugPrint('[SupabaseService] isUserBlockedFromRoom error: $e');
    }
    return false;
  }

  Future<void> followUser(String uid, String targetUid) =>
      _ds.followUser(uid, targetUid);

  Future<void> unfollowUser(String uid, String targetUid) =>
      _ds.unfollowUser(uid, targetUid);

  Future<bool> isFollowing(String uid, String targetUid) =>
      _ds.isFollowing(uid, targetUid);

  Future<void> recordProfileVisit({
    required String visitedUid,
    required String visitorUid,
    String? visitorName,
    String? visitorPhoto,
  }) =>
      _ds.logProfileVisit(visitedUid, visitorUid);

  Future<Map<String, gm.GiftModel>> getGiftsCatalog() async {
    try {
      final list = await _ds.getGifts();
      return {for (var g in list) g.id: g};
    } catch (_) {
      return {};
    }
  }

  Future<List<gm.SentGiftModel>> getReceivedGifts(String uid) =>
      _ds.getReceivedGifts(uid);

  Future<String?> getUserCurrentRoomId(String uid) async {
    try {
      final u = await _ds.getUser(uid);
      return u?.hostedRoomId;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getFollowing(String uid) =>
      _ds.getFollowingUsers(uid);

  Future<List<Map<String, dynamic>>> getFans(String uid) =>
      _ds.getFollowerUsers(uid);

  Future<List<Map<String, dynamic>>> getMutualFriends(String uid) =>
      _ds.getMutualFriends(uid);

  Future<List<Map<String, dynamic>>> getVisitors(String uid) =>
      _ds.getVisitorUsers(uid);

  Future<List<Map<String, dynamic>>> getReports() async {
    try {
      final url =
          Uri.parse('$_baseUrl/rest/v1/reports?select=*&order=created_at.desc');
      final res = await SafeHttp.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> resolveReport(String reportId) async {
    try {
      await SafeHttp.patch(
        Uri.parse('$_baseUrl/rest/v1/reports?id=eq.$reportId'),
        headers: _headers,
        body: jsonEncode({
          'status': 'resolved',
          'resolved_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } catch (_) {}
  }

  Future<void> blockUser(String blockerUid, String blockedUid) async {
    if (blockerUid.isEmpty || blockedUid.isEmpty) return;
    try {
      await SafeHttp.post(
        Uri.parse('$_baseUrl/rest/v1/blocks?on_conflict=blocker_uid,blocked_uid'),
        headers: {
          ..._headers,
          'Prefer': 'resolution=ignore-duplicates',
        },
        body: jsonEncode({
          'blocker_uid': blockerUid,
          'blocked_uid': blockedUid,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('[SupabaseService] blockUser error: $e');
    }
  }

  Future<void> unblockUser(String blockerUid, String blockedUid) async {
    if (blockerUid.isEmpty || blockedUid.isEmpty) return;
    try {
      final url = Uri.parse(
          '$_baseUrl/rest/v1/blocks?blocker_uid=eq.$blockerUid&blocked_uid=eq.$blockedUid');
      await SafeHttp.delete(url, headers: _headers);
    } catch (e) {
      debugPrint('[SupabaseService] unblockUser error: $e');
    }
  }

  Future<List<String>> getBlockedUids(String uid) async {
    if (uid.isEmpty) return [];
    try {
      final url = Uri.parse(
          '$_baseUrl/rest/v1/blocks?blocker_uid=eq.$uid&select=blocked_uid');
      final res = await SafeHttp.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list
            .map((e) => (e as Map)['blocked_uid']?.toString() ?? '')
            .where((v) => v.isNotEmpty)
            .toList();
      }
    } catch (e) {
      debugPrint('[SupabaseService] getBlockedUids error: $e');
    }
    return [];
  }

  Future<void> reportUser(
      {required String reporterUid,
      required String reportedUid,
      required String reason,
      String? description}) async {
    try {
      await SafeHttp.post(
        Uri.parse('$_baseUrl/rest/v1/reports'),
        headers: _headers,
        body: jsonEncode({
          'id': const Uuid().v4(),
          'reporter_uid': reporterUid,
          'reported_uid': reportedUid,
          'reason': reason,
          'description': description ?? '',
          'status': 'pending',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } catch (_) {}
  }

  Stream<List<gm.SentGiftModel>> userReceivedGiftsStream(String uid) async* {
    while (true) {
      try {
        final gifts = await _ds.getReceivedGifts(uid);
        yield gifts;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  static int _convSortTime(Map<String, dynamic> row) {
    final raw = row['last_time'] ?? row['last_timestamp'] ?? row['timestamp'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw != null) {
      final parsed = DateTime.tryParse(raw.toString());
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    return 0;
  }

  Stream<List<Map<String, dynamic>>> conversationsStream(String uid) async* {
    final profileCache = <String, Map<String, String>>{};
    while (true) {
      try {
        final List rows = await _sb
            .from('conversations')
            .select()
            .or('uid.eq.$uid,other_uid.eq.$uid')
            .order('last_time', ascending: false);

        final byConv = <String, Map<String, dynamic>>{};
        for (final raw in rows) {
          final row = Map<String, dynamic>.from(raw as Map);
          final convId = (row['conv_id'] ?? '').toString();
          if (convId.isEmpty) continue;
          final rowUid = (row['uid'] ?? '').toString();
          if (rowUid != uid) {
            row['other_uid'] = rowUid;
            row['other_name'] = '';
            row['other_photo_url'] = '';
          }
          final existing = byConv[convId];
          if (existing == null ||
              ((existing['uid'] ?? '').toString() != uid && rowUid == uid)) {
            byConv[convId] = row;
          }
        }

        final missing = byConv.values
            .where((r) =>
                (r['other_name'] ?? '').toString().isEmpty &&
                (r['other_uid'] ?? '').toString().isNotEmpty)
            .map((r) => r['other_uid'].toString())
            .toSet()
            .where((u) => !profileCache.containsKey(u))
            .toList();
        for (final otherUid in missing) {
          try {
            final u = await _ds.getUser(otherUid);
            if (u != null) {
              profileCache[otherUid] = {
                'name': u.name,
                'photo': u.photoUrl,
                'custom_id': u.customId,
              };
            }
          } catch (_) {}
        }
        for (final row in byConv.values) {
          final cached = profileCache[(row['other_uid'] ?? '').toString()];
          if (cached == null) continue;
          if ((row['other_name'] ?? '').toString().isEmpty) {
            row['other_name'] = cached['name'] ?? '';
          }
          if ((row['other_photo_url'] ?? '').toString().isEmpty) {
            row['other_photo_url'] = cached['photo'] ?? '';
          }
          if ((row['other_custom_id'] ?? '').toString().isEmpty) {
            row['other_custom_id'] = cached['custom_id'] ?? '';
          }
        }

        final list = byConv.values.toList()
          ..sort((a, b) => _convSortTime(b).compareTo(_convSortTime(a)));
        yield list;
      } catch (e) {
        debugPrint('[SupabaseService] conversationsStream error: $e');
      }
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  Stream<List<MessageModel>> privateMessagesStream(
      String conversationId) async* {
    while (true) {
      try {
        List<MessageModel> parse(http.Response res) =>
            (jsonDecode(res.body) as List).map((e) {
              final m = Map<String, dynamic>.from(e as Map);
              if (m['image_url'] == null || m['image_url'].toString().isEmpty) {
                m['image_url'] = m['media_url'];
              }
              return MessageModel.fromMap(m);
            }).toList();

        List<MessageModel> messages = [];
        final primaryUrl = Uri.parse(
            '$_baseUrl/rest/v1/private_messages?conv_id=eq.$conversationId&order=created_at.asc');
        final primary = await SafeHttp.get(primaryUrl, headers: _headers);
        if (primary.statusCode == 200) {
          messages = parse(primary);
        }

        if (messages.isEmpty) {
          final convParts = conversationId.split('_');
          String filter =
              'or=(conversation_id.eq.$conversationId,conv_id.eq.$conversationId';
          if (convParts.length == 2 &&
              convParts[0].isNotEmpty &&
              convParts[1].isNotEmpty) {
            final u1 = convParts[0];
            final u2 = convParts[1];
            filter +=
                ',and(sender_uid.eq.$u1,receiver_uid.eq.$u2),and(sender_uid.eq.$u2,receiver_uid.eq.$u1)';
          }
          filter += ')&order=created_at.asc';

          final legacy = await SafeHttp.get(
              Uri.parse('$_baseUrl/rest/v1/private_messages?$filter'),
              headers: _headers);
          if (legacy.statusCode == 200) {
            messages = parse(legacy);
          }
        }

        yield messages;
      } catch (e) {
        debugPrint('[SupabaseService] privateMessagesStream error: $e');
      }
      await Future.delayed(const Duration(milliseconds: 1000));
    }
  }

  Future<void> sendPrivateMessage({
    String? conversationId,
    String? senderId,
    String? senderUid,
    required String senderName,
    String? senderPhotoUrl,
    String? receiverId,
    String? receiverUid,
    String? receiverName,
    String? receiverPhotoUrl,
    required String text,
    String type = 'text',
    String? imageUrl,
  }) async {
    try {
      final effectiveSenderUid = senderId ?? senderUid ?? '';
      final effectiveReceiverUid = receiverId ?? receiverUid ?? '';
      if (effectiveSenderUid.isEmpty || effectiveReceiverUid.isEmpty) {
        debugPrint(
            '[SupabaseService] sendPrivateMessage aborted: empty sender ($effectiveSenderUid) or receiver ($effectiveReceiverUid)');
        return;
      }
      final effectiveConvId =
          (conversationId != null && conversationId.isNotEmpty)
              ? conversationId
              : (effectiveSenderUid.compareTo(effectiveReceiverUid) < 0
                  ? '${effectiveSenderUid}_$effectiveReceiverUid'
                  : '${effectiveReceiverUid}_$effectiveSenderUid');

      final msgId = const Uuid().v4();
      final now = DateTime.now().millisecondsSinceEpoch;
      final isoNow = DateTime.now().toUtc().toIso8601String();

      // 1. مزامنة جدول المحادثات أولاً لاستيفاء قيد المفتاح الأجنبي (Foreign Key)
      final lastMsgText =
          text.isNotEmpty ? text : (type == 'image' ? '[صورة]' : '');
      final senderConv = {
        'conv_id': effectiveConvId,
        'uid': effectiveSenderUid,
        'other_uid': effectiveReceiverUid,
        'other_name': receiverName ?? '',
        'other_photo_url': receiverPhotoUrl ?? '',
        'last_message': lastMsgText,
        'last_time': isoNow,
        'unread_count': 0,
      };

      int receiverUnread = 1;
      try {
        final existing = await _sb
            .from('conversations')
            .select('unread_count')
            .eq('uid', effectiveReceiverUid)
            .eq('conv_id', effectiveConvId)
            .maybeSingle();
        if (existing != null) {
          receiverUnread =
              ((existing['unread_count'] as num?)?.toInt() ?? 0) + 1;
        }
      } catch (_) {}

      final receiverConv = {
        'conv_id': effectiveConvId,
        'uid': effectiveReceiverUid,
        'other_uid': effectiveSenderUid,
        'other_name': senderName,
        'other_photo_url': senderPhotoUrl ?? '',
        'last_message': lastMsgText,
        'last_time': isoNow,
        'unread_count': receiverUnread,
      };

      bool convReady = false;
      try {
        final dualRes = await SafeHttp.post(
          Uri.parse('$_baseUrl/rest/v1/conversations'),
          headers: {
            ..._headers,
            'Prefer': 'resolution=merge-duplicates,return=minimal',
          },
          body: jsonEncode([senderConv, receiverConv]),
        );
        convReady = dualRes.statusCode >= 200 && dualRes.statusCode < 300;
        if (!convReady) {
          debugPrint(
              '[SupabaseService] conversations dual upsert HTTP ${dualRes.statusCode}: ${dualRes.body}');
        }
      } catch (e) {
        debugPrint('[SupabaseService] conversations dual upsert failed: $e');
      }
      if (!convReady) {
        try {
          final singleRes = await SafeHttp.post(
            Uri.parse('$_baseUrl/rest/v1/conversations'),
            headers: {
              ..._headers,
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: jsonEncode(senderConv),
          );
          convReady = singleRes.statusCode >= 200 && singleRes.statusCode < 300;
          if (!convReady) {
            debugPrint(
                '[SupabaseService] conversations single upsert HTTP ${singleRes.statusCode}: ${singleRes.body}');
          }
        } catch (e) {
          debugPrint(
              '[SupabaseService] conversations single upsert failed: $e');
        }
      }

      // 2. إدراج الرسالة في جدول private_messages بالحقول المعتمدة بقاعدة البيانات
      final msgBody = {
        'id': msgId,
        'conversation_id': effectiveConvId,
        'conv_id': effectiveConvId,
        'sender_uid': effectiveSenderUid,
        'receiver_uid': effectiveReceiverUid,
        'receiver_name': receiverName ?? '',
        'receiver_photo_url': receiverPhotoUrl ?? '',
        'text': text,
        'type': type,
        'media_url': imageUrl ?? '',
        'timestamp': now,
        'created_at': isoNow,
        'is_read': false,
      };

      Object? lastError;
      try {
        await _sb.from('private_messages').insert(msgBody);
        return;
      } catch (e) {
        lastError = e;
        debugPrint('[SupabaseService] private_messages SDK insert failed: $e');
      }

      try {
        final msgRes = await SafeHttp.post(
          Uri.parse('$_baseUrl/rest/v1/private_messages'),
          headers: _headers,
          body: jsonEncode(msgBody),
        );
        if (msgRes.statusCode >= 200 && msgRes.statusCode < 300) return;
        lastError = 'HTTP ${msgRes.statusCode} - ${msgRes.body}';
        debugPrint(
            '[SupabaseService] private_messages HTTP failed: $lastError');
      } catch (e) {
        lastError = e;
        debugPrint('[SupabaseService] private_messages HTTP error: $e');
      }

      // 3. محاولة أخيرة بأقل الحقول المطلوبة (توافق مع مخططات قديمة)
      try {
        await _sb.from('private_messages').insert({
          'id': msgId,
          'conv_id': effectiveConvId,
          'sender_uid': effectiveSenderUid,
          'receiver_uid': effectiveReceiverUid,
          'text': text,
          'created_at': isoNow,
        });
        return;
      } catch (e) {
        lastError = e;
        debugPrint(
            '[SupabaseService] private_messages minimal insert failed: $e');
      }

      throw Exception('تعذر إرسال الرسالة: $lastError');
    } catch (e) {
      debugPrint('[SupabaseService] sendPrivateMessage error: $e');
      rethrow;
    }
  }

  Future<void> markConversationRead(String uid, String conversationId) async {
    try {
      await _sb
          .from('conversations')
          .update({'unread_count': 0})
          .eq('uid', uid)
          .eq('conv_id', conversationId);
    } catch (_) {}
    try {
      await _sb
          .from('private_messages')
          .update({'is_read': true})
          .eq('receiver_uid', uid)
          .eq('conv_id', conversationId)
          .eq('is_read', false);
    } catch (_) {}
  }

  Stream<List<NotificationModel>> notificationsStream({String? uid}) async* {
    while (true) {
      try {
        final filter = uid != null && uid.isNotEmpty
            ? '?or=(uid.eq.$uid,target.eq.$uid,target.eq.all)&order=created_at.desc&limit=50'
            : '?order=created_at.desc&limit=50';
        final url = Uri.parse('$_baseUrl/rest/v1/notifications$filter');
        final res = await SafeHttp.get(url, headers: _headers);
        if (res.statusCode == 200) {
          final List list = jsonDecode(res.body);
          yield list
              .map((e) => NotificationModel.fromMap(
                  Map<String, dynamic>.from(e as Map)))
              // ✅ لا تظهر إشعارات الهدايا في رسائل النظام —
              //    المستخدم لا يريد رسالة «X أرسل لك هدية» هناك.
              //    استثناء: دعوات ربط CP (cp_relationship_request)
              //    لازم تظهر عشان الطرف يقدر يقبل/يرفض.
              .where((n) {
                if (n.type == 'gift' ||
                    n.type == 'gift_from_admin') {
                  return false;
                }
                if (n.type == 'cp_gift') {
                  final action = n.data?['action']?.toString();
                  final reqId =
                      n.data?['request_id']?.toString() ?? '';
                  return action == 'cp_relationship_request' ||
                      reqId.isNotEmpty;
                }
                return true;
              })
              .toList();
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 4));
    }
  }

  /// لقطات الهدايا للفترات الثلاث (يومي/أسبوعي/شهري) — تُجلب مرة واحدة
  /// فقط وتُشتق منها كل تصنيفات الترتيب (ثروة/سحر/غرف)، بدل إطلاق
  /// 9 طلبات متطابقة تقريباً لكل تصنيف على حدة.
  Future<Map<String, List<gm.SentGiftModel>>> getRankingGiftSnapshots(
      {List<String>? timeframes}) async {
    final now = DateTime.now().toUtc();
    final allCutoffs = <String, DateTime>{
      'daily': now.subtract(const Duration(hours: 24)),
      'weekly': now.subtract(const Duration(days: 7)),
      'monthly': now.subtract(const Duration(days: 30)),
    };
    final cutoffs = timeframes == null
        ? allCutoffs
        : Map.fromEntries(
            allCutoffs.entries.where((e) => timeframes.contains(e.key)));

    if (cutoffs.isEmpty) return <String, List<gm.SentGiftModel>>{};

    // ✅ جلب مُرقّم (paged) — نتجاوز سقف PostgREST (1000 صف/طلب) الذي كان
    //    يُسقط معظم المرسلين من تصنيفات الثروة/السحر، ونقيّد بالحد الأدنى
    //    للفترة (شهري = 30 يوماً) لتقليل حجم البيانات.
    final earliest = cutoffs.values.reduce((a, b) => a.isBefore(b) ? a : b);
    // Initialise all keys BEFORE fetching so a failure can never produce an
    // empty map (the old log showed snapshots=0 and hid the real cause).
    final result = <String, List<gm.SentGiftModel>>{
      for (final k in cutoffs.keys) k: <gm.SentGiftModel>[],
    };
    try {
      final all = await _ds.getSentGiftsPaged(after: earliest);
      for (final entry in cutoffs.entries) {
        result[entry.key] = all
            .where((g) => !g.timestamp.toUtc().isBefore(entry.value))
            .toList();
      }
    } catch (e) {
      debugPrint('[getRankingGiftSnapshots] fetch error: $e');
    }
    debugPrint('[getRankingGiftSnapshots] counts: '
        '${result.entries.map((e) => "${e.key}=${e.value.length}").join(", ")}');
    return result;
  }


  /// Same data as [getRankingGiftSnapshots], but emits each period as soon
  /// as its own fetch finishes. The daily query (24h) is tiny, so the UI can
  /// render it immediately instead of waiting for the heavy 30-day query.
  /// All three fetches start in parallel.
  Stream<MapEntry<String, List<gm.SentGiftModel>>>
      rankingGiftSnapshotsStream({List<String>? timeframes}) {
    final controller = StreamController<
        MapEntry<String, List<gm.SentGiftModel>>>();
    final now = DateTime.now().toUtc();
    final allCutoffs = <String, DateTime>{
      'daily': now.subtract(const Duration(hours: 24)),
      'weekly': now.subtract(const Duration(days: 7)),
      'monthly': now.subtract(const Duration(days: 30)),
    };
    final cutoffs = timeframes == null
        ? allCutoffs
        : Map.fromEntries(
            allCutoffs.entries.where((e) => timeframes.contains(e.key)));

    final pending = <Future<void>>[];
    for (final entry in cutoffs.entries) {
      final period = entry.key;
      final cutoff = entry.value;
      pending.add(_ds.getSentGiftsPaged(after: cutoff).then((gifts) {
        final filtered = gifts
            .where((g) => !g.timestamp.toUtc().isBefore(cutoff))
            .toList();
        debugPrint('[rankingSnapshots] $period=${filtered.length}');
        if (!controller.isClosed) {
          controller.add(MapEntry(period, filtered));
        }
      }).catchError((Object e) {
        debugPrint('[rankingSnapshots] $period error: $e');
        if (!controller.isClosed) {
          controller.add(MapEntry(period, <gm.SentGiftModel>[]));
        }
      }));
    }
    Future.wait(pending).whenComplete(() {
      if (!controller.isClosed) controller.close();
    });
    return controller.stream;
  }

  Future<List<gm.SentGiftModel>> getSentGiftsPaged({
    DateTime? after,
    String roomId = '',
    int pageSize = 1000,
    int maxRows = 20000,
  }) =>
      _ds.getSentGiftsPaged(
          after: after, roomId: roomId, pageSize: pageSize, maxRows: maxRows);

  Future<List<Map<String, dynamic>>> getGlobalRankings(
      {required bool isWealth,
      required String timeframe,
      List<gm.SentGiftModel>? gifts}) async {
    try {
      final now = DateTime.now().toUtc();
      DateTime? cutoff;
      if (timeframe == 'daily') {
        cutoff = now.subtract(const Duration(hours: 24));
      } else if (timeframe == 'weekly') {
        cutoff = now.subtract(const Duration(days: 7));
      } else if (timeframe == 'monthly') {
        cutoff = now.subtract(const Duration(days: 30));
      }

      // Fetch gifts filtered by timeframe directly from Supabase
      // (gifts: لقطة جاهزة من getRankingGiftSnapshots عند توفرها)
      final filtered = gifts ??
          await _ds.getSentGiftsPaged(after: cutoff);

      final Map<String, int> totals = {};
      final Map<String, Map<String, dynamic>> userDetails = {};
      for (final g in filtered) {
        final uid = isWealth ? g.senderId : g.receiverId;
        if (uid.isEmpty) continue;
        final name = isWealth ? g.senderName : g.receiverName;
        final photo = isWealth ? (g.senderPhotoUrl ?? '') : '';
        final cost = (g.value * g.count).toInt();
        totals[uid] = (totals[uid] ?? 0) + cost;
        final existingPhoto = userDetails[uid]?['photoUrl']?.toString() ?? '';
        if (!userDetails.containsKey(uid) || existingPhoto.isEmpty) {
          userDetails[uid] = {
            'id': uid,
            'name': name.isNotEmpty ? name : 'مستخدم',
            'photoUrl': photo,
          };
        }
      }

      final sortedKeys = totals.keys.toList()
        ..sort((a, b) => totals[b]!.compareTo(totals[a]!));
      final topUids = sortedKeys.take(50).toList();

      // جلب الآيدي الرقمي الحقيقي (custom_id) والبروفايل لكافة المتصدرين
      if (topUids.isNotEmpty) {
        try {
          final inFilter = topUids.map((k) => '"$k"').join(',');
          final uUrl = Uri.parse(
              '$_baseUrl/rest/v1/users?uid=in.($inFilter)&select=uid,name,custom_id,photo_url,level');
          final uRes = await SafeHttp.get(uUrl, headers: _headers,
              timeout: const Duration(seconds: 15));
          if (uRes.statusCode == 200) {
            final List uList = jsonDecode(uRes.body);
            for (final u in uList) {
              final uMap = Map<String, dynamic>.from(u as Map);
              final uId = (uMap['uid'] ?? uMap['id'])?.toString() ?? '';
              final cId = (uMap['custom_id'] ?? '').toString();
              final uName = (uMap['name'] ?? '').toString();
              final uPhoto = (uMap['photo_url'] ?? '').toString();
              if (uId.isNotEmpty) {
                if (userDetails.containsKey(uId)) {
                  userDetails[uId]!['custom_id'] = cId;
                  if (uName.isNotEmpty) userDetails[uId]!['name'] = uName;
                  if (uPhoto.isNotEmpty) userDetails[uId]!['photoUrl'] = uPhoto;
                  userDetails[uId]!['level'] = uMap['level'] ?? 1;
                } else {
                  userDetails[uId] = {
                    'id': uId,
                    'custom_id': cId,
                    'name': uName,
                    'photoUrl': uPhoto,
                    'level': uMap['level'] ?? 1,
                  };
                }
              }
            }
          }
        } catch (e) {
          debugPrint('[getGlobalRankings] fetch users custom_id error: $e');
        }
      }

      final result = sortedKeys.map((uid) {
        final cId = userDetails[uid]?['custom_id']?.toString() ?? '';
        // ✅ المستوى حسب نوع الترتيب (ثروة/سحر) مع الرجوع للحقل العام.
        final lvl = isWealth
            ? ((userDetails[uid]?['wealth_level'] as num?)?.toInt() ??
                (userDetails[uid]?['level'] as num?)?.toInt() ??
                1)
            : ((userDetails[uid]?['gems_level'] as num?)?.toInt() ??
                (userDetails[uid]?['level'] as num?)?.toInt() ??
                1);
        return {
          'id': uid,
          'uid': uid,
          'user_id': uid,
          'custom_id': cId,
          'display_id': cId,
          'name': userDetails[uid]?['name'] ?? 'مستخدم',
          'photoUrl': userDetails[uid]?['photoUrl'] ?? '',
          'photo_url': userDetails[uid]?['photoUrl'] ?? '',
          'level': lvl,
          'wealth_level': (userDetails[uid]?['wealth_level'] as num?)?.toInt() ?? lvl,
          'gems_level': (userDetails[uid]?['gems_level'] as num?)?.toInt() ?? lvl,
          'amount': totals[uid] ?? 0,
          'points': totals[uid] ?? 0,
          'score': totals[uid] ?? 0,
          'total_gifts_sent': isWealth ? (totals[uid] ?? 0) : 0,
          'total_gifts_received': !isWealth ? (totals[uid] ?? 0) : 0,
        };
      }).toList();

      // ✅ لا نضيف مستخدمين من جدول users هنا: تلك إجماليات عمر الحساب
      //    فتظهر نفس الأسماء في اليومي/الأسبوعي/الشهري. الترتيب يجب أن يحتوي
      //    فقط على من أرسل/استقبل هدايا داخل نافذة الفترة المطلوبة.
      return result;
    } catch (e) {
      debugPrint('[getGlobalRankings] error: $e');
      return [];
    }
  }

  /// جلب بيانات الترتيب مباشرة من الـ Views السريعة في Supabase
  Future<List<Map<String, dynamic>>> getRankingsFromView(
      String viewName, {int limit = 50}) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/$viewName?select=*&limit=$limit');
      final res = await SafeHttp.get(url, headers: _headers, timeout: const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((e) {
              final p = (e['points'] as num?)?.toInt() ??
                  (e['amount'] as num?)?.toInt() ??
                  (e['score'] as num?)?.toInt() ??
                  (e['total_gifts'] as num?)?.toInt() ??
                  0;
              return p > 0;
            })
            .toList();
      }
    } catch (e) {
      debugPrint('[getRankingsFromView] $viewName error: $e');
    }
    return [];
  }

  /// أعلى المراكز في الترتيب اليومي (الثروة/السحر/الغرف) مباشرةً من **نفس
  /// الـ Views التي تقرأ منها شاشة الترتيب** (`daily_wealth_ranking`,
  /// `daily_charm_ranking`, `daily_rooms_ranking`) — فتتطابق بطاقات
  /// الاستكشاف مع شاشة الترتيب في البيانات والصور تماماً، بدل إعادة
  /// الحساب من جدول الهدايا (وهو ما كان يُرجع صوراً/نتائج مختلفة).
  Future<Map<String, List<Map<String, dynamic>>>>
      getDailyTopRankingsFromViews() async {
    final out = <String, List<Map<String, dynamic>>>{
      'wealth': <Map<String, dynamic>>[],
      'charm': <Map<String, dynamic>>[],
      'rooms': <Map<String, dynamic>>[],
    };
    try {
      final results = await Future.wait<dynamic>([
        // SupabaseQueryBuilder.catchError يمرّر الدالة إلى Future<List<Map>>
        // الأصلي — يجب أن يُرجع نفس النوع، وإلا رمى Dart "onError must return
        // a value of the future's type" وأفقد البطاقات كلها عند أي فشل REST.
        _sb
            .from('daily_wealth_ranking')
            .select('*')
            .limit(3)
            .catchError((_) => <Map<String, dynamic>>[]),
        _sb
            .from('daily_charm_ranking')
            .select('*')
            .limit(3)
            .catchError((_) => <Map<String, dynamic>>[]),
        _sb
            .from('daily_rooms_ranking')
            .select('*')
            .limit(3)
            .catchError((_) => <Map<String, dynamic>>[]),
      ]);

      List<Map<String, dynamic>> norm(dynamic rows) {
        return (rows as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((e) {
          final p = (e['points'] as num?)?.toInt() ??
              (e['amount'] as num?)?.toInt() ??
              (e['total_gifts'] as num?)?.toInt() ??
              0;
          return p > 0;
        }).map((e) {
          // قد يعود اسم العمود مختلفاً بين الـ Views (`photo_url`,
          // `photoUrl`, `avatar`, `room_photo_url` …) — نوحّدها كلها
          // إلى `photoUrl` حتى تجدها البطاقات في الاستكشاف/الترتيب.
          String pick(List<String> keys) {
            for (final k in keys) {
              final v = (e[k] ?? '').toString().trim();
              if (v.isNotEmpty && v != 'null') return v;
            }
            return '';
          }

          final photo = pick(const [
            'photoUrl',
            'photo_url',
            'avatar',
            'avatar_url',
            'room_photo_url',
            'room_photo',
            'cover_image',
            'image',
            'bg_image',
          ]);
          return <String, dynamic>{
            ...e,
            'photoUrl': photo,
            'photo_url': photo,
          };
        }).toList();
      }

      out['wealth'] = norm(results[0]);
      out['charm'] = norm(results[1]);
      out['rooms'] = norm(results[2]);
    } catch (e) {
      debugPrint('[getDailyTopRankingsFromViews] error: $e');
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> getRoomGlobalRanking(
      {required String timeframe, List<gm.SentGiftModel>? gifts}) async {
    try {
      final now = DateTime.now().toUtc();
      DateTime? cutoff;
      if (timeframe == 'daily') {
        cutoff = now.subtract(const Duration(hours: 24));
      } else if (timeframe == 'weekly') {
        cutoff = now.subtract(const Duration(days: 7));
      } else if (timeframe == 'monthly') {
        cutoff = now.subtract(const Duration(days: 30));
      }

      final filtered = gifts ??
          await _ds.getSentGiftsPaged(after: cutoff);

      final Map<String, int> roomTotals = {};
      for (final g in filtered) {
        if (g.roomId.isNotEmpty) {
          roomTotals[g.roomId] =
              (roomTotals[g.roomId] ?? 0) + (g.value * g.count).toInt();
        }
      }
      final sortedKeys = roomTotals.keys.toList()
        ..sort((a, b) => roomTotals[b]!.compareTo(roomTotals[a]!));
      final topRoomIds = sortedKeys.take(50).toList();

      // ✅ طلب واحد لكل الغرف — getRoom المتكرر كان يطلق
      //    RPC كوينز شهرية ثقيل لكل غرفة (50 استعلاماً متزامناً
      //    يخنق السيرفر ويعلّق الترتيب لدقائق)
      final roomRows = await _ds.getRoomsByIds(topRoomIds);
      final roomById = {
        for (final r in roomRows) r.roomId: r,
      };

      final List<Map<String, dynamic>> result = [];
      for (final rid in topRoomIds) {
        final room = roomById[rid];
        final amt = roomTotals[rid] ?? 0;
        final photo = (room?.roomPhotoUrl.isNotEmpty == true)
            ? room!.roomPhotoUrl
            : (room?.bgImage ?? '');
        result.add({
          'id': rid,
          'uid': rid,
          'roomId': rid,
          'room_id': rid,
          'name': room?.name ?? 'غرفة #$rid',
          'photoUrl': photo,
          'photo_url': photo,
          'room_photo_url': photo,
          'host_name': room?.hostName ?? '',
          'password': room?.password ?? '',
          'amount': amt,
          'points': amt,
          'total_value': amt,
          'total_gifts': amt,
          'hot_value': amt,
        });
      }

      // إذا لم تكن هناك هدايا للغرف في هذه الفترة، نعرض أكثر الغرف نشاطاً من جدول rooms
      if (result.isEmpty) {
        try {
          var allRooms = await _ds.getAllRooms();
          if (allRooms.isEmpty) {
            // استعلام مباشر سريع لتفادي أي تعليق في دوال الإحصائيات الشهرية
            final url = Uri.parse('$_baseUrl/rest/v1/rooms?select=*&order=total_gifts.desc&limit=20');
            final rRes = await SafeHttp.get(url, headers: _headers, timeout: const Duration(seconds: 8));
            if (rRes.statusCode == 200) {
              final List rList = jsonDecode(rRes.body);
              allRooms = rList.map((e) => RoomModel.fromMap(e as Map<String, dynamic>)).toList();
            }
          }
          for (final r in allRooms.take(20)) {
            final amt = r.totalGifts > 0 ? r.totalGifts : (r.hotValue > 0 ? r.hotValue : 100);
            final photo = r.roomPhotoUrl.isNotEmpty ? r.roomPhotoUrl : r.bgImage;
            result.add({
              'id': r.roomId,
              'uid': r.roomId,
              'roomId': r.roomId,
              'room_id': r.roomId,
              'name': r.name.isNotEmpty ? r.name : 'غرفة #${r.roomId}',
              'photoUrl': photo,
              'photo_url': photo,
              'room_photo_url': photo,
              'host_name': r.hostName,
              'password': r.password,
              'amount': amt,
              'points': amt,
              'total_value': amt,
              'total_gifts': amt,
              'hot_value': amt,
            });
          }
        } catch (_) {}
      }

      return result;
    } catch (e) {
      debugPrint('[getRoomGlobalRanking] error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getRoomRankings({
    required String roomId,
    required bool isWealth,
    required String timeframe,
  }) async {
    // ✅ التحقق من الكاش أولاً
    final cacheKey = '${roomId}_${isWealth ? 'wealth' : 'magic'}_$timeframe';
    final cached = _roomRankingCache[cacheKey];
    if (cached != null && cached.isValid) {
      debugPrint('[getRoomRankings] returning cached data for $cacheKey');
      return cached.data;
    }

    try {
      final now = DateTime.now().toUtc();
      DateTime? cutoff;
      if (timeframe == 'daily') {
        // على مدار 24 ساعة
        cutoff = now.subtract(const Duration(hours: 24));
      } else if (timeframe == 'weekly') {
        // على مدار 7 أيام
        cutoff = now.subtract(const Duration(days: 7));
      } else if (timeframe == 'monthly') {
        // ✅ نافذة متدحرجة 30 يوماً (وليست الشهر الميلادي) — تُصفَّر تلقائياً
        //    كل 30 يوماً وتتوافق مع الترتيب العام.
        cutoff = now.subtract(const Duration(days: 30));
      }

      // ✅ شاشة الترتيب منفصلة تماماً عن تصفير كاريزما المقاعد:
      // تصفير الكاريزما يؤثر فقط على عدادات المقاعد اللحظية للأشخاص الجالسين،
      // بينما شاشة الترتيب تعتمد على الفترة الزمنية (يومي / أسبوعي / شهري)
      // لتحفظ سجلات المتصدرين والهدايا بدون شطبها من الترتيب.
      final effectiveCutoff = cutoff;

      // ✅ 1. محاولة جلب هدايا الغرفة حسب الوقت المحدد
      var allGifts =
          await _ds.getSentGiftsPaged(after: effectiveCutoff, roomId: roomId);
      // ✅ 2. إذا كانت فارغة (مثلاً الهدايا أقدم من 24 ساعة)، نجلب هدايا الغرفة بدون تقييد زمني صارم
      if (allGifts.isEmpty) {
        allGifts = await _ds.getSentGiftsPaged(roomId: roomId, pageSize: 50, maxRows: 100);
      }
      // ✅ 3. محاولة مطابقة room_id بدون فواصل أو مسافات
      final cleanRoomId = roomId.trim();
      var roomGifts = allGifts.where((g) => g.roomId.trim() == cleanRoomId).toList();
      if (roomGifts.isEmpty && allGifts.isNotEmpty) {
        roomGifts = allGifts;
      }
      if (roomGifts.isEmpty) return [];

      // إذا كانت هناك هدايا ضمن الفترة نأخذها، وإلا نستخدم آخر هدايا للغرفة
      final filteredPeriod = effectiveCutoff != null
          ? roomGifts
              .where((g) => !g.timestamp.toUtc().isBefore(effectiveCutoff.toUtc()))
              .toList()
          : roomGifts;
      final filtered = filteredPeriod.isNotEmpty ? filteredPeriod : roomGifts;

      if (filtered.isEmpty) return [];

      final Map<String, int> totals = {};
      final Map<String, Map<String, dynamic>> userDetails = {};
      for (final g in filtered) {
        final uid = isWealth ? g.senderId : g.receiverId;
        final name = isWealth ? g.senderName : g.receiverName;
        final cost = (g.value * g.count).toInt();
        if (uid.isEmpty) continue;
        totals[uid] = (totals[uid] ?? 0) + cost;
        userDetails[uid] ??= {
          'id': uid,
          'name': name,
          'photoUrl': isWealth ? (g.senderPhotoUrl ?? '') : '',
        };
      }

      final sortedKeys = totals.keys.toList()
        ..sort((a, b) => totals[b]!.compareTo(totals[a]!));
      // ✅ أعلى 20 مرسلين/مستلمين داخل هذه الغرفة.
      final topKeys = sortedKeys.take(20).toList();

      // Fetch user profile info (photo_url, avatar, custom_id, level, wealth_level, gems_level)
      final Map<String, Map<String, dynamic>> enrichedUsers = {};
      if (topKeys.isNotEmpty) {
        try {
          final inFilter = topKeys.map((k) => '"$k"').join(',');
          final uUrl = Uri.parse(
              '$_baseUrl/rest/v1/users?uid=in.($inFilter)&select=uid,name,custom_id,photo_url,level,wealth_level,gems_level');
          final uRes = await SafeHttp.get(uUrl, headers: _headers,
              timeout: const Duration(seconds: 15));
          if (uRes.statusCode == 200) {
            final List uList = jsonDecode(uRes.body);
            for (final u in uList) {
              final m = Map<String, dynamic>.from(u as Map);
              final uidVal = m['uid']?.toString() ?? '';
              if (uidVal.isNotEmpty) {
                enrichedUsers[uidVal] = m;
              }
            }
          }
        } catch (_) {}
      }

      // ✅ تخزين في الكاش
      final result = topKeys.map((uid) {
        final local = userDetails[uid] ?? {};
        final enriched = enrichedUsers[uid] ?? {};
        final name = (enriched['name']?.toString().isNotEmpty == true)
            ? enriched['name'].toString()
            : (local['name']?.toString().isNotEmpty == true
                ? local['name'].toString()
                : 'مستخدم');
        final rawPhoto = (enriched['photo_url']?.toString().isNotEmpty == true)
            ? enriched['photo_url'].toString()
            : ((enriched['avatar']?.toString().isNotEmpty == true)
                ? enriched['avatar'].toString()
                : (local['photoUrl']?.toString() ?? ''));
        final customId = enriched['custom_id']?.toString() ?? '';
        // ✅ المستوى الصحيح حسب نوع الترتيب: الثروة → wealth_level،
        //    السحر/الجاذبية → gems_level، مع الرجوع للحقل العام `level`.
        final level = isWealth
            ? ((enriched['wealth_level'] as num?)?.toInt() ??
                (enriched['level'] as num?)?.toInt() ??
                1)
            : ((enriched['gems_level'] as num?)?.toInt() ??
                (enriched['level'] as num?)?.toInt() ??
                1);
        final total = totals[uid] ?? 0;

        return {
          'id': uid,
          'uid': uid,
          'user_id': uid,
          'name': name,
          'user_name': name,
          'photoUrl': rawPhoto,
          'photo_url': rawPhoto,
          'user_photo_url': rawPhoto,
          'custom_id': customId,
          'display_id': customId,
          'amount': total,
          'total_value': total,
          'points': total,
          'score': total,
          'level': level,
          'wealth_level': (enriched['wealth_level'] as num?)?.toInt() ?? level,
          'gems_level': (enriched['gems_level'] as num?)?.toInt() ?? level,
        };
      }).toList();
      _roomRankingCache[cacheKey] = CachedRanking(result, DateTime.now());
      return result;
    } catch (e) {
      debugPrint('[SupabaseService] getRoomRankings error: $e');
      // ✅ انقطاع الشبكة ≠ ترتيب فارغ: أعد آخر نسخة محفوظة (حتى لو انتهت
      //    الـ TTL) حتى لا تظهر شاشة «لا توجد بيانات» بسبب DNS/timeout.
      final stale = _roomRankingCache[cacheKey];
      return stale?.data ?? [];
    }
  }

  /// إبطال كاش ترتيب غرفة — تُستدعى عند وصول هدية جديدة عبر Realtime
  /// حتى تنعكس على الترتيب فوراً بدل انتظار انتهاء TTL (دقيقتان).
  void invalidateRoomRankingCache(String roomId) {
    _roomRankingCache.removeWhere((k, _) => k.startsWith('${roomId}_'));
  }

  Future<List<Map<String, dynamic>>> getBadgesCatalog() => _ds.getBadges();

  Future<List<Map<String, dynamic>>> getNecklacesCatalog() =>
      _ds.getNecklaces();

  Future<dynamic> getAppConfig(String key) async {
    final cfg = await _ds.getAppConfig();
    return cfg[key];
  }

  Future<Map<String, dynamic>> getAnchorAgencyData(
      {String? agencyId, required String agentUid}) async {
    try {
      final ag = await _ds.getHostAgencyForUser(agentUid, agencyId: agencyId);
      if (ag != null && ag['id'] != null) {
        final aid = ag['id'].toString();
        final members = await _ds.getHostAgencyMembers(aid);
        final milestones = await _ds.getHostMilestones();
        ag['milestones'] = milestones;
        return {
          'info': ag,
          'anchors': members,
        };
      }
    } catch (_) {}
    return {};
  }

  Future<bool> updateAgencyNotice({String? agencyId, String? notice}) async {
    try {
      final res = await SafeHttp.patch(
        Uri.parse('$_baseUrl/rest/v1/host_agencies?id=eq.$agencyId'),
        headers: _headers,
        body: jsonEncode(
            {'announcement': notice, 'notice': notice, 'description': notice}),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeAgencyMember(
          {String? agencyId, String? memberUid, String? userId}) =>
      exitAgencyAsMember(
          agencyId: agencyId ?? '', userId: memberUid ?? userId ?? '');

  Future<Map<String, dynamic>> createAgentDiamondWithdrawalRequest(
      {required String agentUid,
      required String targetUid,
      required int diamondsAmount}) async {
    try {
      final res = await SafeHttp.post(
        Uri.parse('$_baseUrl/rest/v1/agent_withdrawal_requests'),
        headers: _headers,
        body: jsonEncode({
          'id': const Uuid().v4(),
          'agent_uid': agentUid,
          'target_uid': targetUid,
          'diamonds_amount': diamondsAmount,
          'status': 'pending',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      return {'success': res.statusCode >= 200 && res.statusCode < 300};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> respondToAgentWithdrawalRequest(
      {required String requestId,
      required String userUid,
      required bool approved,
      String? agentId,
      int? diamondsAmount,
      String? targetName}) async {
    try {
      final res = await SafeHttp.patch(
        Uri.parse(
            '$_baseUrl/rest/v1/agent_withdrawal_requests?id=eq.$requestId'),
        headers: _headers,
        body: jsonEncode({
          'status': approved ? 'approved' : 'rejected',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      return {
        'status': res.statusCode >= 200 && res.statusCode < 300 ? 'ok' : 'error'
      };
    } catch (_) {
      return {'status': 'error'};
    }
  }

  Stream<List<Map<String, dynamic>>> activeLuckyBagsStream(
      String roomId) async* {
    yield [];
  }

  Future<void> setDoc(
      String collection, String docId, Map<String, dynamic> data) async {
    try {
      final body = Map<String, dynamic>.from(data);
      if (!body.containsKey('id')) body['id'] = docId;
      await SafeHttp.post(
        Uri.parse('$_baseUrl/rest/v1/$collection?on_conflict=id'),
        headers: {
          ..._headers,
          'Prefer': 'resolution=merge-duplicates',
        },
        body: jsonEncode(body),
      );
    } catch (_) {}
  }
}

/// كاش لترتيب الغرف
class CachedRanking {
  final List<Map<String, dynamic>> data;
  final DateTime timestamp;
  CachedRanking(this.data, this.timestamp);
  bool get isValid => DateTime.now().difference(timestamp) < SupabaseService._cacheTtl;
}

/// لضمان التوافق مع أي استدعاء لـ FirebaseService
typedef FirebaseService = SupabaseService;