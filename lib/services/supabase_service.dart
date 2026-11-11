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
import 'dynamic_config_service.dart';
import 'agency_target_evaluator.dart';
import 'global_banner_service.dart';

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

  Future<UserModel?> getUser(String uid) => _ds.getUser(uid);

  Stream<UserModel?> userStream(String uid) {
    final controller = StreamController<UserModel?>.broadcast();
    Timer? pollTimer;

    void fetchSupabase() async {
      try {
        final u = await _ds.getUser(uid);
        if (u != null && !controller.isClosed) {
          controller.add(u);
        }
      } catch (_) {}
    }

    fetchSupabase();
    pollTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => fetchSupabase());

    controller.onCancel = () {
      pollTimer?.cancel();
    };

    return controller.stream;
  }

  Future<void> saveUser(UserModel user) async {
    await _ds.updateUser(user.uid, user.toMap());
  }

  Future<bool> updateUser(String uid, Map<String, dynamic> data) =>
      _ds.updateUser(uid, data);

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
      final ok = await _ds.updateUser(uid, updates);
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
      });
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
      });
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
    while (true) {
      try {
        if (watermark == null) {
          final broadcasts = await _ds.getRecentBroadcasts(limit: 10);
          if (broadcasts.isNotEmpty) {
            yield broadcasts;
            for (final b in broadcasts) {
              final ts = b['created_at']?.toString();
              if (ts != null && ts.isNotEmpty) {
                if (watermark == null || ts.compareTo(watermark) > 0) {
                  watermark = ts;
                }
              }
            }
          }
          // نبدأ من نقطة متأخرة 60 ثانية لتغطية أي فارق بين ساعة الجهاز والسيرفر
          watermark ??= DateTime.now()
              .toUtc()
              .subtract(const Duration(seconds: 60))
              .toIso8601String();
        } else {
          // تداخل بسيط لضمان عدم فقدان أي بث عند تزامن الطلبات
          final since = DateTime.tryParse(watermark)
                  ?.toUtc()
                  .subtract(const Duration(seconds: 2))
                  .toIso8601String() ??
              watermark;
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
      // أقل من ثانية: نص فوز هدية الحظ يظهر في كل الغرف فوراً (250ms)
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }

  Stream<Map<String, dynamic>> globalBigWinStream() async* {
    final Set<String> seenWins = {};
    while (true) {
      try {
        final announcements = await _ds.getRecentGlobalAnnouncements(limit: 5);
        for (final a in announcements) {
          final id = a['id']?.toString() ?? '';
          if (id.isNotEmpty && !seenWins.contains(id)) {
            seenWins.add(id);
            if (seenWins.length > 50) seenWins.remove(seenWins.first);
            yield a;
          }
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 1));
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
    required int value,
    int count = 1,
    String? comboId,
    int comboCount = 1,
    List<int>? preDrawnMultipliers,
  }) async {
    int totalWonCoins = 0;
    int maxMultiplier = 0;
    bool isBigWin = false;
    List<int> multipliers = [];
    num serverNewBalance = 0;
    final totalCost = value * count;
    final bool isSelfSend = senderId == receiverId;

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

      // 2. توزيع الماس والتارجت للمستلم لهدايا الحظ حسب نسبة التارجت (تعمل في كل الحالات)
      final luckyTargetPct = DynamicConfigService().luckyGiftTargetPercentage;
      final int recipientDiamonds = luckyTargetPct > 0
          ? math.max(1, ((totalCost * luckyTargetPct) / 100.0).round())
          : 0;
      if (recipientDiamonds > 0) {
        final rUser = await _ds.getUser(receiverId);
        if (rUser != null) {
          await _ds.updateUser(receiverId, {
            'total_gifts_received':
                rUser.totalGiftsReceived + recipientDiamonds,
          });
        }
        // الرصيد يُحدَّث داخل RPC/المسار الاحتياطي (عضو وكالة أو محفظة شخصية)
        await _ds.creditHostAgencyMemberDiamonds(
            receiverId, recipientDiamonds);
      }

      // 3. تسجيل الهدية في جدول sent_gifts بـ Supabase بنسبة كاريزما المستلم المحددة
      final effectiveSeatCharmValue =
          luckyTargetPct > 0 ? ((value * luckyTargetPct) / 100.0).round() : 0;
      unawaited(_ds
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
          .catchError((_) => false));
      unawaited(_ds.incrementRoomGifts(roomId, totalCost));

      // 4. بث رسالة الغرفة عبر room_messages في Supabase
      final luckyMsgId = const Uuid().v4();
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

      // رسالة نظام مرئية لجميع مستخدمي الغرفة لإعلان الفائز بالمحظوظ
      if (totalWonCoins > 0 || maxMultiplier > 1) {
        final winnerText = maxMultiplier > 1
            ? '🍀 $receiverName فاز بالمحظوظ! مضاعف ${maxMultiplier}X — ربح $totalWonCoins 🪙'
            : '🍀 $receiverName فاز بهدية الحظ "$giftNameAr" وربح $totalWonCoins 🪙!';
        unawaited(_ds
            .sendMessage(MessageModel(
              msgId: '${luckyMsgId}_win',
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

      // 5. بث نص الفوز لكافة الغرف فوراً عبر جدول broadcasts
      //    نفس النص الذي يراه المستخدم في شات الغرفة.
      final String broadcastContent = totalWonCoins > 0 || maxMultiplier > 1
          ? '$senderName 🍀 $giftNameAr x$count (فاز بـ $totalWonCoins 🪙)'
          : '$senderName 🍀 $giftNameAr x$count';

      final String bCastId = const Uuid().v4();
      unawaited(_ds
          .recordBroadcast(
            senderUid: senderId,
            senderName: senderName,
            senderPhotoUrl: senderPhotoUrl,
            roomId: roomId,
            content: broadcastContent,
            giftIcon: giftIconUrl,
            multiplier: maxMultiplier,
            type: 'lucky_gift',
            broadcastId: bCastId,
          )
          .catchError((_) => false));

      // ✅ حقن محلي فوري: نص هدية الحظ يظهر لحظياً عند ضغط زر الإرسال
      //    بدل انتظار رحلة الطلب للسيرفر وعودة البث. نفس المعرف يُرسل
      //    للسيرفر فيتجاهل النظام النسخة المكررة تلقائياً.
      GlobalBannerService.instance.echoBroadcastLocally({
        'id': bCastId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'sender_uid': senderId,
        'sender_name': senderName,
        'sender_photo_url': senderPhotoUrl,
        'room_id': roomId,
        'content': broadcastContent,
        'gift_icon': giftIconUrl,
        'gift_name': giftNameAr,
        'type': 'lucky_gift',
        'multiplier': maxMultiplier,
        'won_coins': totalWonCoins,
        'count': count,
      });

      // نص الفوز يصل لكل الأجهزة (بما فيها المرسل) عبر Supabase Realtime
      // مع polling احتياطي كل 500ms في GlobalBannerService.

      if (isBigWin || maxMultiplier >= 10) {
        unawaited(_ds
            .recordGlobalAnnouncement(
              type: 'lucky_big_win',
              senderName: senderName,
              giftName: giftNameAr,
              roomId: roomId,
              multiplier: maxMultiplier,
              totalWon: totalWonCoins,
            )
            .catchError((_) => false));
      }

      // 6. تقييم التارجت للوكيل في الخلفية
      unawaited(AgencyTargetEvaluator.evaluateHostTargets(receiverId)
          .catchError((_) {}));

      // 7. إشعار الاستلام للمستلم
      if (!isSelfSend) {
        unawaited(sendNotification(
          uid: receiverId,
          type: 'gift',
          actorUid: senderId,
          title: '🍀 هدية حظ من $senderName',
          body:
              '$senderName أرسل لك "$giftNameAr" x$count (بقيمة $totalCost عملة)',
          data: <String, dynamic>{
            'sender_name': senderName,
            'sender_photo': senderPhotoUrl,
            'gift_id': giftId,
            'gift_name': giftNameAr,
            'gift_image': giftIconUrl,
            'value': value,
            'count': count,
            'room_id': roomId,
            'is_lucky': true,
          },
        ).catchError((_) {}));
      }

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
  }) async {
    final totalCost = value * count;
    final isSelfSend = senderId == receiverId;

    try {
      // 1. خصم الكوينز من المرسل (مُسلسَل لمنع تصادم القراءة-الكتابة عند الكومبو/تعدد المستلمين)
      final hostRatePct = DynamicConfigService().hostRatePercentage;
      final hostDiamonds = (totalCost * (hostRatePct / 100.0)).round();

      // ⚡ خصم atomic بطلب واحد (RPC) — بدون قراءة مسبقة وبدون قائمة انتظار
      // فيصبح إرسال الهدية أسرع بكثير عند الكومبو/الضغط المطوّل
      final spendRes = await _ds.spendUserCoins(senderId, totalCost);
      final bool deducted;
      if (spendRes != null) {
        deducted = spendRes['ok'] == true;
      } else {
        // احتياطي: إذا لم يكن RPC مُطبَّقاً على السيرفر بعد
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
      if (!deducted) return false;

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

      // 1.5 ⚡ بث رسالة الهدية في الشات فوراً — قبل أي عمليات رصيد إضافية
      // حتى تظهر لدى جميع المستخدمين في أقل من ثانية
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

      unawaited(_ds
          .sendMessage(MessageModel(
            msgId: const Uuid().v4(),
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
          .catchError((_) => false));

      // 2. توزيع الماس وفق سياسة النظام المعتمدة (100% للمضيف كاملة، وعمولة وكيل المضيف تُضاف لرصيده دون أي خصم من المضيف)
      if (isSelfSend) {
        // الرصيد يُحدَّث داخل RPC/المسار الاحتياطي (عضو وكالة أو محفظة شخصية)
        await _ds.creditHostAgencyMemberDiamonds(senderId, hostDiamonds);
      } else {
        final rUser = await _ds.getUser(receiverId);
        if (rUser != null) {
          await _ds.updateUser(receiverId, {
            'total_gifts_received': rUser.totalGiftsReceived + hostDiamonds,
          });
        }
        // الرصيد يُحدَّث داخل RPC/المسار الاحتياطي (عضو وكالة أو محفظة شخصية)
        await _ds.creditHostAgencyMemberDiamonds(receiverId, hostDiamonds);
      }

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
        'content': giftBroadcastContent,
        'gift_icon': effectiveIcon,
        'gift_name': giftName,
        'type': totalCost >= 500 ? 'big_gift' : 'gift',
        'value': value,
        'count': count,
        'total_cost': totalCost,
      });

      // 5. تقييم التارجت للوكيل وإشعار المستلم
      unawaited(AgencyTargetEvaluator.evaluateHostTargets(receiverId)
          .catchError((_) {}));
      if (!isSelfSend) {
        unawaited(sendNotification(
          uid: receiverId,
          type: 'gift',
          actorUid: senderId,
          title: '🎁 هدية من $senderName',
          body: '$senderName أرسل لك "$giftName" x$count ($totalCost)',
          data: <String, dynamic>{
            'sender_name': senderName,
            'sender_photo': senderPhotoUrl,
            'gift_id': giftId,
            'gift_name': giftName,
            'gift_image': effectiveIcon,
            'value': value,
            'count': count,
            'room_id': roomId,
          },
        ).catchError((_) {}));
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
    while (true) {
      try {
        final rooms = await _ds.getAllRooms();
        yield rooms;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 4));
    }
  }

  Stream<RoomModel?> roomStream(String roomId) async* {
    while (true) {
      try {
        final room = await _ds.getRoom(roomId);
        yield room;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  Future<bool> updateRoom(String roomId, Map<String, dynamic> updates) =>
      _ds.updateRoom(roomId, updates);

  Future<bool> clearRoomCharisma(String roomId) =>
      _ds.clearRoomCharisma(roomId);

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
    while (true) {
      try {
        final members = await _ds.getRoomMembers(roomId);
        yield members;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  Stream<Map<int, Map<String, dynamic>>> seatsStream(String roomId) async* {
    while (true) {
      try {
        final seats = await _ds.getSeats(roomId);
        if (seats != null) yield seats;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 1));
    }
  }

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
    while (true) {
      try {
        final msgs = await _ds.getRoomMessages(roomId, sinceMs: sinceMs);
        if (msgs.isNotEmpty) {
          var newest = sinceMs ?? 0;
          for (final m in msgs) {
            if (m.timestamp > newest) newest = m.timestamp;
          }
          if (newest > (sinceMs ?? 0)) sinceMs = newest - 1;
        } else if (sinceMs == null) {
          sinceMs = DateTime.now().millisecondsSinceEpoch - 5000;
        }
        yield msgs;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  Stream<List<gm.SentGiftModel>> sentGiftsStream(String roomId) async* {
    final byId = <String, gm.SentGiftModel>{};
    DateTime? newest;
    bool firstLoad = true;
    int failures = 0;
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
      final delayMs = ok ? 700 : const [700, 1500, 3000, 5000][failures];
      await Future.delayed(Duration(milliseconds: delayMs));
    }
  }

  Stream<List<gm.GiftModel>> giftsStream() async* {
    int failures = 0;
    while (true) {
      var ok = false;
      try {
        final gifts = await _ds.getGifts(allowCache: false);
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
    int failures = 0;
    while (true) {
      var ok = false;
      try {
        final cats = await _ds.getGiftCategories(allowCache: false);
        yield cats;
        ok = true;
      } catch (_) {}
      failures = ok ? 0 : (failures + 1 > 3 ? 3 : failures + 1);
      final delayMs =
          ok ? 20000 : const [20000, 30000, 45000, 60000][failures];
      await Future.delayed(Duration(milliseconds: delayMs));
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
    yield [];
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
        msgId: 'entrance_${uid}_$ts',
        roomId: roomId,
        senderUid: uid,
        senderName: name,
        senderPhotoUrl: photoUrl,
        text: 'joined',
        type: 'entrance',
        timestamp: ts,
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
        msgId: 'exit_${uid ?? name}_$ts',
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
              .toList();
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 4));
    }
  }

  Future<List<Map<String, dynamic>>> getGlobalRankings(
      {required bool isWealth, required String timeframe}) async {
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
      final filtered = await _ds.getSentGifts('', limit: 3000, after: cutoff);

      final Map<String, int> totals = {};
      final Map<String, Map<String, dynamic>> userDetails = {};
      for (final g in filtered) {
        final uid = isWealth ? g.senderId : g.receiverId;
        if (uid.isEmpty) continue;
        final name = isWealth ? g.senderName : g.receiverName;
        final photo = isWealth ? (g.senderPhotoUrl ?? '') : '';
        final cost = (g.value * g.count).toInt();
        totals[uid] = (totals[uid] ?? 0) + cost;
        if (!userDetails.containsKey(uid) ||
            (userDetails[uid]!['photoUrl'] as String).isEmpty) {
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
          final usersRes = await _sb
              .from('users')
              .select('id, custom_id, name, avatar, photo_url')
              .inFilter('id', topUids);
          if (usersRes is List) {
            for (final u in usersRes) {
              final uMap = Map<String, dynamic>.from(u as Map);
              final uId = uMap['id']?.toString() ?? '';
              if (uId.isNotEmpty) {
                final cId = (uMap['custom_id'] ?? '').toString();
                final uName = (uMap['name'] ?? '').toString();
                final uPhoto =
                    (uMap['photo_url'] ?? uMap['avatar'] ?? '').toString();
                if (userDetails.containsKey(uId)) {
                  userDetails[uId]!['custom_id'] = cId;
                  if (uName.isNotEmpty) userDetails[uId]!['name'] = uName;
                  if (uPhoto.isNotEmpty) userDetails[uId]!['photoUrl'] = uPhoto;
                } else {
                  userDetails[uId] = {
                    'id': uId,
                    'custom_id': cId,
                    'name': uName,
                    'photoUrl': uPhoto,
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
        return {
          'id': uid,
          'uid': uid,
          'user_id': uid,
          'custom_id': cId,
          'display_id': cId,
          'name': userDetails[uid]?['name'] ?? 'مستخدم',
          'photoUrl': userDetails[uid]?['photoUrl'] ?? '',
          'photo_url': userDetails[uid]?['photoUrl'] ?? '',
          'amount': totals[uid] ?? 0,
          'points': totals[uid] ?? 0,
          'score': totals[uid] ?? 0,
          'total_gifts_sent': isWealth ? (totals[uid] ?? 0) : 0,
          'total_gifts_received': !isWealth ? (totals[uid] ?? 0) : 0,
        };
      }).toList();

      // إذا كانت النتائج أقل من 3، نجلب من جدول users مع الحفاظ على custom_id
      if (result.length < 3) {
        try {
          final usersQuery = isWealth
              ? await _sb
                  .from('users')
                  .select(
                      'id, custom_id, name, avatar, photo_url, total_gifts_sent, wealth_exp')
                  .order('total_gifts_sent', ascending: false)
                  .limit(10)
              : await _sb
                  .from('users')
                  .select(
                      'id, custom_id, name, avatar, photo_url, total_gifts_received, charm')
                  .order('total_gifts_received', ascending: false)
                  .limit(10);
          final existingIds = result.map((r) => r['id'].toString()).toSet();
          for (final u in (usersQuery as List)) {
            final uId = (u['id'] ?? '').toString();
            if (uId.isEmpty || existingIds.contains(uId)) continue;
            final pts = isWealth
                ? ((u['total_gifts_sent'] as num?)?.toInt() ??
                    (u['wealth_exp'] as num?)?.toInt() ??
                    0)
                : ((u['total_gifts_received'] as num?)?.toInt() ??
                    (u['charm'] as num?)?.toInt() ??
                    0);
            if (pts > 0) {
              final photo = (u['photo_url'] ?? u['avatar'] ?? '').toString();
              final cId = (u['custom_id'] ?? '').toString();
              result.add({
                'id': uId,
                'uid': uId,
                'user_id': uId,
                'custom_id': cId,
                'display_id': cId,
                'name': (u['name'] ?? 'مستخدم').toString(),
                'photoUrl': photo,
                'photo_url': photo,
                'amount': pts,
                'points': pts,
                'score': pts,
                'total_gifts_sent': isWealth ? pts : 0,
                'total_gifts_received': !isWealth ? pts : 0,
              });
              existingIds.add(uId);
            }
          }
        } catch (_) {}
      }

      return result;
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getRoomGlobalRanking(
      {required String timeframe}) async {
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

      final filtered = await _ds.getSentGifts('', limit: 3000, after: cutoff);

      final Map<String, int> roomTotals = {};
      for (final g in filtered) {
        if (g.roomId.isNotEmpty) {
          roomTotals[g.roomId] =
              (roomTotals[g.roomId] ?? 0) + (g.value * g.count).toInt();
        }
      }
      final sortedKeys = roomTotals.keys.toList()
        ..sort((a, b) => roomTotals[b]!.compareTo(roomTotals[a]!));
      final List<Map<String, dynamic>> result = [];
      for (final rid in sortedKeys.take(50)) {
        final room = await _ds.getRoom(rid);
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

      // إذا كانت قائمة الغرف أقل من 3، نجلب كـ fallback من جدول rooms
      if (result.length < 3) {
        try {
          final topRooms = await _sb
              .from('rooms')
              .select('*')
              .order('total_gifts', ascending: false)
              .limit(10);
          final existingRids =
              result.map((r) => r['room_id'].toString()).toSet();
          for (final r in (topRooms as List)) {
            final rid = (r['room_id'] ?? r['id'] ?? '').toString();
            if (rid.isEmpty || existingRids.contains(rid)) continue;
            final amt = (r['total_gifts'] as num?)?.toInt() ??
                (r['hot_value'] as num?)?.toInt() ??
                0;
            final photo =
                (r['room_photo_url'] ?? r['bg_image'] ?? '').toString();
            result.add({
              'id': rid,
              'uid': rid,
              'roomId': rid,
              'room_id': rid,
              'name': (r['name'] ?? 'غرفة #$rid').toString(),
              'photoUrl': photo,
              'photo_url': photo,
              'room_photo_url': photo,
              'host_name': (r['host_name'] ?? '').toString(),
              'password': (r['password'] ?? '').toString(),
              'amount': amt,
              'points': amt,
              'total_value': amt,
              'total_gifts': amt,
              'hot_value': amt,
            });
            existingRids.add(rid);
          }
        } catch (_) {}
      }

      return result;
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getRoomRankings({
    required String roomId,
    required bool isWealth,
    required String timeframe,
  }) async {
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
        // على مدار الشهر الحالي
        cutoff = DateTime.utc(now.year, now.month, 1);
      }

      // احترام وقت تصفير كاريزما الغرفة: نستبعد الهدايا الأقدم من التصفير
      // من ترتيب الغرفة فقط دون المساس بالترتيب العام.
      DateTime? clearedAt;
      if (roomId.isNotEmpty) {
        try {
          final roomRes = await SafeHttp.get(
            Uri.parse('$_baseUrl/rest/v1/rooms?room_id=eq.$roomId&select=charisma_cleared_at&limit=1'),
            headers: _headers,
          );
          if (roomRes.statusCode == 200) {
            final roomList = jsonDecode(roomRes.body);
            if (roomList is List && roomList.isNotEmpty) {
              final ms = ((roomList.first as Map)['charisma_cleared_at'] as num?)?.toInt() ?? 0;
              if (ms > 0) {
                clearedAt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
              }
            }
          }
        } catch (_) {}
      }
      final effectiveCutoff = (cutoff == null ||
              (clearedAt != null && clearedAt.isAfter(cutoff)))
          ? (clearedAt ?? cutoff)
          : cutoff;

      final allGifts =
          await _ds.getSentGifts(roomId, limit: 1000, after: effectiveCutoff);
      if (allGifts.isEmpty) return [];

      // تصفير القائمة عند انتهاء الفترة أو تصفير كاريزما الغرفة
      final filtered = effectiveCutoff != null
          ? allGifts
              .where((g) => g.timestamp.isAfter(effectiveCutoff))
              .toList()
          : allGifts;

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
      final topKeys = sortedKeys.take(20).toList();

      // Fetch user profile info (photo_url, avatar, custom_id, level) for the ranked users
      final Map<String, Map<String, dynamic>> enrichedUsers = {};
      if (topKeys.isNotEmpty) {
        try {
          final inFilter = topKeys.map((k) => '"$k"').join(',');
          final uUrl = Uri.parse(
              '$_baseUrl/rest/v1/users?or=(uid.in.($inFilter),id.in.($inFilter))&select=uid,id,name,custom_id,photo_url,avatar,level');
          final uRes = await SafeHttp.get(uUrl, headers: _headers);
          if (uRes.statusCode == 200) {
            final List uList = jsonDecode(uRes.body);
            for (final u in uList) {
              final m = Map<String, dynamic>.from(u as Map);
              final uidVal = m['uid']?.toString();
              final idVal = m['id']?.toString();
              if (uidVal != null && uidVal.isNotEmpty)
                enrichedUsers[uidVal] = m;
              if (idVal != null && idVal.isNotEmpty) enrichedUsers[idVal] = m;
            }
          }
        } catch (_) {}
      }

      return topKeys.map((uid) {
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
        final level = (enriched['level'] as num?)?.toInt() ?? 1;
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
        };
      }).toList();
    } catch (e) {
      debugPrint('[SupabaseService] getRoomRankings error: $e');
      return [];
    }
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

/// لضمان التوافق مع أي استدعاء لـ FirebaseService
typedef FirebaseService = SupabaseService;
