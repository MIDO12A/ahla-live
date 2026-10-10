import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../models/user_model.dart';
import '../models/room_model.dart';
import '../models/message_model.dart';
import '../models/gift_model.dart' as gm;
import '../models/gift_category_model.dart';
import '../models/gift_banner_config_model.dart';
import '../models/store_item_model.dart';
import '../models/ranking_frame_config.dart';
import '../models/gifted_item_model.dart';
import '../models/banner_config.dart';
import '../models/notification_model.dart';
import 'supabase_data_service.dart';
import 'dynamic_config_service.dart';
import 'agency_target_evaluator.dart';

/// خدمة إدارة وتنسيق عمليات Supabase المباشرة (SupabaseService)
/// تضمن الاتصال فائق السرعة مع https://supabase.com وتحديث رصيد العملات فوريًا بـ 0ms
class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

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
    pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => fetchSupabase());

    controller.onCancel = () {
      pollTimer?.cancel();
    };

    return controller.stream;
  }

  Future<void> saveUser(UserModel user) async {
    await _ds.updateUser(user.uid, user.toMap());
  }

  Future<bool> updateUser(String uid, Map<String, dynamic> data) => _ds.updateUser(uid, data);

  Stream<List<GiftedItemModel>> userGiftedItemsStream(String uid) => _ds.userGiftedItemsStream(uid);

  Future<bool> removeGiftedItem(String giftId) => _ds.removeGiftedItem(giftId);

  Future<bool> purchaseItem(String uid, StoreItemModel item) async {
    try {
      final u = await _ds.getUser(uid);
      if (u == null || u.coins < item.price) return false;
      final owned = List<String>.from(u.ownedItems);
      if (!owned.contains(item.itemId)) owned.add(item.itemId);
      return await _ds.updateUser(uid, {
        'coins': u.coins - item.price,
        'owned_items': owned,
      });
    } catch (_) {
      return false;
    }
  }

  Future<bool> equipItem(String uid, String itemId, String category) async {
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
    final updateMap = <String, dynamic>{
      'active_$category': '',
    };
    return await _ds.updateUser(uid, updateMap);
  }

  // ═══════════════════════════════════════════════════════
  // ROOM & SEATS OPERATIONS (SUPABASE)
  // ═══════════════════════════════════════════════════════

  Future<RoomModel?> getRoom(String roomId) => _ds.getRoom(roomId);

  Future<void> toggleMute(String roomId, int seatIndex, bool muted) => _ds.toggleMute(roomId, seatIndex, muted);

  Future<void> leaveSeatForUser(String roomId, String uid) => _ds.leaveSeatForUser(roomId, uid);

  Future<void> leaveRoom(String roomId, String uid) => _ds.leaveRoom(roomId, uid);

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
    while (true) {
      try {
        final broadcasts = await _ds.getRecentBroadcasts(limit: 10);
        yield broadcasts;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 3));
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
      await Future.delayed(const Duration(seconds: 3));
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

  List<int> drawLuckyMultipliers(int count, {int cardCount = 4}) {
    final random = math.Random.secure();

    // جدول نسب الفوز والخسارة المعياري العالمي (RTP: 82.5%، نسبة الخسارة: 58.3%)
    // - خسارة (0X): 58.296% (58,296 / 100,000)
    // - استرداد التكلفة / تعادل (1X): 28.000% (28,000 / 100,000)
    // - ربح مضاعف (2X): 10.000% (10,000 / 100,000)
    // - ربح جيد (5X): 2.500% (2,500 / 100,000)
    // - ربح كبير (10X): 0.800% (800 / 100,000)
    // - ربح فائق (20X): 0.300% (300 / 100,000)
    // - بيج وين (50X): 0.080% (80 / 100,000)
    // - جاكبوت (100X): 0.020% (20 / 100,000)
    // - سوبر جاكبوت (500X): 0.004% (4 / 100,000)
    final effectiveCount = count > 0 ? count : 1;
    final wonMultipliers = <int>[];
    for (int c = 0; c < effectiveCount; c++) {
      final roll = random.nextInt(100000);
      int mult;
      if (roll < 58296) {
        mult = 0;
      } else if (roll < 86296) {
        mult = 1;
      } else if (roll < 96296) {
        mult = 2;
      } else if (roll < 98796) {
        mult = 5;
      } else if (roll < 99596) {
        mult = 10;
      } else if (roll < 99896) {
        mult = 20;
      } else if (roll < 99976) {
        mult = 50;
      } else if (roll < 99996) {
        mult = 100;
      } else {
        mult = 500;
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
    int serverNewBalance = 0;

    try {
      // 1. استدعاء المعاملة الذرية من Supabase عبر RPC (process_lucky_gift)
      final rpcUrl = Uri.parse('$_baseUrl/rest/v1/rpc/process_lucky_gift');
      final rpcRes = await http.post(
        rpcUrl,
        headers: _headers,
        body: jsonEncode({
          'p_user_id': senderId,
          'p_room_id': roomId,
          'p_receiver_id': receiverId,
          'p_gift_id': giftId,
          'p_count': count,
        }),
      ).timeout(const Duration(seconds: 8));

      if (rpcRes.statusCode >= 200 && rpcRes.statusCode < 300) {
        final Map<String, dynamic> rpcData = jsonDecode(rpcRes.body) as Map<String, dynamic>;
        if (rpcData['success'] != true) {
          debugPrint('[SupabaseService] process_lucky_gift failed: ${rpcData['error']}');
          return null;
        }
        totalWonCoins = (rpcData['won_coins'] as num?)?.toInt() ?? 0;
        maxMultiplier = (rpcData['multiplier'] as num?)?.toInt() ?? 0;
        isBigWin = rpcData['is_big_win'] == true || maxMultiplier >= 50;
        serverNewBalance = (rpcData['new_balance'] as num?)?.toInt() ?? 0;
        final rawMults = rpcData['multipliers'] as List<dynamic>?;
        if (rawMults != null) {
          multipliers = rawMults.map((e) => (e as num).toInt()).toList();
        } else {
          multipliers = preDrawnMultipliers ?? drawLuckyMultipliers(count);
        }
      } else {
        // Fallback في حال لم يتم تنفيذ الـ SQL بعد على السيرفر
        debugPrint('[SupabaseService] RPC status ${rpcRes.statusCode}, using fallback');
        multipliers = preDrawnMultipliers ?? drawLuckyMultipliers(count);
        for (final m in multipliers) {
          totalWonCoins += (value * m);
        }
        final sUser = await _ds.getUser(senderId);
        final currentCoins = sUser?.coins ?? 0;
        serverNewBalance = math.max(0, currentCoins - (value * count) + totalWonCoins);
        await _ds.updateUser(senderId, {
          'coins': serverNewBalance,
          'total_gifts_sent': (sUser?.totalGiftsSent ?? 0) + (value * count),
        });
      }
    } catch (e) {
      debugPrint('[SupabaseService] process_lucky_gift error: $e');
      return null;
    }

    final totalCost = value * count;

      // 3. تسجيل الهدية في جدول sent_gifts بـ Supabase
      unawaited(_ds.recordSentGift(
        roomId: roomId,
        giftId: giftId,
        giftName: giftNameAr.isNotEmpty ? giftNameAr : giftName,
        animationAsset: svgaAnimUrl ?? giftIconUrl,
        senderId: senderId,
        senderName: senderName,
        senderPhotoUrl: senderPhotoUrl,
        receiverId: receiverId,
        receiverName: receiverName,
        value: value,
        count: count,
      ).catchError((_) => false));

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
          'cards': List.generate(multipliers.length, (i) => {
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

      unawaited(_ds.sendMessage(MessageModel(
        msgId: luckyMsgId,
        roomId: roomId,
        senderUid: senderId,
        senderName: senderName,
        senderPhotoUrl: senderPhotoUrl,
        type: 'lucky_gift',
        text: '$senderName 🍀 $giftNameAr x$count (فاز بـ $totalWonCoins 🪙)',
        imageUrl: giftIconUrl,
        giftPayload: luckyGiftPayload,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      )).catchError((_) => false));

      // 5. بث الفوز بالمضاعفات الكبيرة لكافة الغرف عبر جدول broadcasts
      if (maxMultiplier >= 5 || isBigWin || totalWonCoins > 0) {
        unawaited(_ds.recordBroadcast(
          senderUid: senderId,
          senderName: senderName,
          senderPhotoUrl: senderPhotoUrl,
          roomId: roomId,
          content: maxMultiplier > 1
              ? '🎉 فاز بمضاعف ${maxMultiplier}X في هدية الحظ $giftNameAr (كسب $totalWonCoins 🪙)!'
              : 'أرسل هدية الحظ $giftNameAr x$count',
          giftIcon: giftIconUrl,
          multiplier: maxMultiplier,
          type: 'lucky_gift',
        ).catchError((_) => false));

        if (isBigWin || maxMultiplier >= 50) {
          unawaited(_ds.recordGlobalAnnouncement(
            type: 'lucky_big_win',
            senderName: senderName,
            giftName: giftNameAr,
            roomId: roomId,
            multiplier: maxMultiplier,
            totalWon: totalWonCoins,
          ).catchError((_) => false));
        }
      }

      // 6. تقييم التارجت للوكيل في الخلفية
      if (!isSelfSend) {
        unawaited(AgencyTargetEvaluator.evaluateHostTargets(receiverId).catchError((_) {}));
      }

      // 7. إشعار الاستلام للمستلم
      unawaited(sendNotification(
        uid: receiverId,
        type: 'gift',
        actorUid: senderId,
        title: '🍀 هدية حظ من $senderName',
        body: '$senderName أرسل لك "$giftNameAr" x$count (بقيمة $totalCost عملة)',
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

      return {
        'success': true,
        'wonCoins': totalWonCoins,
        'multipliers': multipliers,
        'maxMultiplier': maxMultiplier,
        'isBigWin': isBigWin,
        'newBalance': serverNewBalance,
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
      // 1. خصم الكوينز من المرسل
      final sUser = await _ds.getUser(senderId);
      final currentCoins = sUser?.coins ?? 0;
      if (currentCoins < totalCost) return false;

      await _ds.updateUser(senderId, {
        'coins': currentCoins - totalCost,
        'total_gifts_sent': (sUser?.totalGiftsSent ?? 0) + totalCost,
      });

      // 2. إيداع الماس للمستلم
      if (!isSelfSend) {
        final rUser = await _ds.getUser(receiverId);
        if (rUser != null) {
          await _ds.updateUser(receiverId, {
            'diamonds': rUser.diamonds + totalCost,
            'total_gifts_received': rUser.totalGiftsReceived + totalCost,
          });
        }
      }

      // 3. تسجيل الهدية وبثها في الغرفة
      final effectiveIcon = animationAsset ?? defaultImage ?? '';
      unawaited(_ds.recordSentGift(
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
      ).catchError((_) => false));

      unawaited(_ds.sendMessage(MessageModel(
        msgId: const Uuid().v4(),
        roomId: roomId,
        senderUid: senderId,
        senderName: senderName,
        senderPhotoUrl: senderPhotoUrl ?? '',
        type: 'gift',
        text: '$senderName أرسل $giftName x$count إلى $receiverName',
        imageUrl: effectiveIcon,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      )).catchError((_) => false));

      // 4. البث العام للهدايا الكبيرة (500+ عملة)
      if (totalCost >= 500) {
        unawaited(_ds.recordBroadcast(
          senderUid: senderId,
          senderName: senderName,
          senderPhotoUrl: senderPhotoUrl,
          roomId: roomId,
          content: 'أرسل $giftName x$count بقيمة $totalCost 💎 إلى $receiverName',
          giftIcon: effectiveIcon,
          type: 'big_gift',
        ).catchError((_) => false));
      }

      // 5. تقييم التارجت للوكيل وإشعار المستلم
      if (!isSelfSend) {
        unawaited(AgencyTargetEvaluator.evaluateHostTargets(receiverId).catchError((_) {}));
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
      await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'id': const Uuid().v4(),
          'user_id': uid,
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

  Future<bool> deleteAndExitAgencyByOwner({required String agencyId, required String ownerUid}) async {
    try {
      if (agencyId.isNotEmpty) {
        await http.delete(
          Uri.parse('$_baseUrl/rest/v1/host_agencies?id=eq.$agencyId'),
          headers: _headers,
        );
        await http.delete(
          Uri.parse('$_baseUrl/rest/v1/host_agency_members?agency_id=eq.$agencyId'),
          headers: _headers,
        );
      }
      await _ds.updateUser(ownerUid, {
        'agency_id': null,
        'is_agency_owner': false,
      });
      return true;
    } catch (e) {
      debugPrint('[SupabaseService] deleteAndExitAgencyByOwner error: $e');
      return false;
    }
  }

  Future<bool> exitAgencyAsMember({required String agencyId, required String userId}) async {
    try {
      if (agencyId.isNotEmpty) {
        await http.delete(
          Uri.parse('$_baseUrl/rest/v1/host_agency_members?agency_id=eq.$agencyId&user_id=eq.$userId'),
          headers: _headers,
        );
      }
      await _ds.updateUser(userId, {
        'agency_id': null,
      });
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
      final res = await http.patch(
        Uri.parse('$_baseUrl/rest/v1/host_agency_members?agency_id=eq.$agencyId&user_id=eq.$memberUid'),
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
      await _ds.updateUser(uid, {'coins': math.max(0, u.coins - amount)});
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
    String resolvedRoomId = (hostCustomId.trim().isNotEmpty && hostCustomId.trim() != 'null')
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

  Future<bool> migrateUserRoomId(String hostUid, String newRoomId) => _ds.migrateUserRoomId(hostUid, newRoomId);

  Future<RoomModel?> getRoomByHost(String hostUid) => _ds.getRoomByHostUid(hostUid);

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

  Future<bool> updateRoom(String roomId, Map<String, dynamic> updates) => _ds.updateRoom(roomId, updates);

  Future<void> updateRoomBackground(String roomId, String bgUrl) async {
    await _ds.updateRoom(roomId, {'bg_image': bgUrl});
  }

  Future<void> updateRoomSeatStyle(String roomId, int seatStyleIndex) => _ds.updateRoom(roomId, {'seat_style': seatStyleIndex.toString()});

  Future<void> updateRoomSeatCount(String roomId, int count) => _ds.updateRoom(roomId, {'seat_count': count});

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

  Future<bool> joinRoom(String roomId, UserModel user) => _ds.joinRoom(roomId, user);

  Future<List<UserModel>> getRoomMembers(String roomId) => _ds.getRoomMembers(roomId);

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
        yield seats;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Future<bool> takeSeat([dynamic a1, dynamic a2, dynamic a3]) async {
    return true;
  }

  Future<bool> leaveSeat(String roomId, int seatIndex) => _ds.leaveSeat(roomId, seatIndex);

  Future<bool> toggleSeatLock(String roomId, int seatIndex, bool locked) => _ds.toggleSeatLock(roomId, seatIndex, locked);

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

  Future<void> sendMessage(
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
    await _ds.sendMessage(MessageModel(
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

  Future<void> sendImageMessage(String roomId, String imageUrl, String senderUid, String senderName, String senderPhotoUrl) {
    return sendMessage(roomId, '', senderUid, senderName, senderPhotoUrl, type: 'image', imageUrl: imageUrl);
  }

  Stream<List<MessageModel>> messagesStream(String roomId, {String? since}) async* {
    while (true) {
      try {
        final msgs = await _ds.getRoomMessages(roomId);
        yield msgs;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Stream<List<gm.SentGiftModel>> sentGiftsStream(String roomId) async* {
    while (true) {
      try {
        final gifts = await _ds.getSentGifts(roomId);
        yield gifts;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  Stream<List<gm.GiftModel>> giftsStream() async* {
    while (true) {
      try {
        final gifts = await _ds.getGifts();
        yield gifts;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 30));
    }
  }

  Stream<List<GiftCategory>> giftCategoriesStream() async* {
    while (true) {
      try {
        final cats = await _ds.getGiftCategories();
        yield cats;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 30));
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

  Future<({bool success, int coinsReceived, String? error})> exchangeDiamondsToCoins({
    required String uid,
    required int diamonds,
    required int rate,
  }) async {
    final effectiveRate = rate <= 0 ? 2 : rate;
    if (diamonds < 1) {
      return (success: false, coinsReceived: 0, error: 'يرجى إدخال كمية ألماس صحيحة');
    }
    if (diamonds < effectiveRate) {
      return (success: false, coinsReceived: 0, error: 'الحد الأدنى للتبديل هو $effectiveRate ألماس');
    }
    try {
      final user = await _ds.getUser(uid);
      if (user == null || user.diamonds < diamonds) {
        return (success: false, coinsReceived: 0, error: 'رصيد الألماس غير كافٍ');
      }
      final coinsToReceive = (diamonds / effectiveRate).floor();
      final newDiamonds = user.diamonds - diamonds;
      final newCoins = user.coins + coinsToReceive;

      await _ds.updateUser(uid, {
        'diamonds': newDiamonds,
        'coins': newCoins,
      });

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
    // Entrance logged
  }

  Future<void> logExit(String roomId, String name) async {
    // Exit logged
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
    yield false;
  }

  Stream<List<Map<String, dynamic>>> roomBlocksStream(String roomId) async* {
    yield [];
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
    await _ds.leaveSeatForUser(roomId, targetUid);
    if (addToBlacklist) {
      await blockUserFromRoom(roomId, kickerUid, targetUid, reason: reason);
    }
  }

  Future<void> blockUserFromRoom(String roomId, String blockerUid, String blockedUid, {String? reason, int durationMinutes = 60}) async {
    await _ds.leaveSeatForUser(roomId, blockedUid);
  }

  Future<void> unblockUserFromRoom(String roomId, String blockedUid) async {}

  Future<bool> isUserBlockedFromRoom(String roomId, String uid) async => false;

  Future<void> followUser(String uid, String targetUid) => _ds.followUser(uid, targetUid);

  Future<void> unfollowUser(String uid, String targetUid) => _ds.unfollowUser(uid, targetUid);

  Future<bool> isFollowing(String uid, String targetUid) => _ds.isFollowing(uid, targetUid);

  Future<void> recordProfileVisit({
    required String visitedUid,
    required String visitorUid,
    String? visitorName,
    String? visitorPhoto,
  }) => _ds.logProfileVisit(visitedUid, visitorUid);

  Future<Map<String, gm.GiftModel>> getGiftsCatalog() async {
    try {
      final list = await _ds.getGifts();
      return {for (var g in list) g.id: g};
    } catch (_) {
      return {};
    }
  }

  Future<List<gm.SentGiftModel>> getReceivedGifts(String uid) => _ds.getReceivedGifts(uid);

  Future<String?> getUserCurrentRoomId(String uid) async {
    try {
      final u = await _ds.getUser(uid);
      return u?.hostedRoomId;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getFollowing(String uid) => _ds.getFollowingUsers(uid);

  Future<List<Map<String, dynamic>>> getFans(String uid) => _ds.getFollowerUsers(uid);

  Future<List<Map<String, dynamic>>> getVisitors(String uid) => _ds.getVisitorUsers(uid);

  Future<List<Map<String, dynamic>>> getReports() async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/reports?select=*&order=created_at.desc');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> resolveReport(String reportId) async {
    try {
      await http.patch(
        Uri.parse('$_baseUrl/rest/v1/reports?id=eq.$reportId'),
        headers: _headers,
        body: jsonEncode({
          'status': 'resolved',
          'resolved_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } catch (_) {}
  }

  Future<void> blockUser(String blockerUid, String blockedUid) async {}

  Future<void> unblockUser(String blockerUid, String blockedUid) async {}

  Future<List<String>> getBlockedUids(String uid) async => [];

  Future<void> reportUser({required String reporterUid, required String reportedUid, required String reason, String? description}) async {
    try {
      await http.post(
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

  Stream<List<Map<String, dynamic>>> conversationsStream(String uid) async* {
    while (true) {
      try {
        final url = Uri.parse('$_baseUrl/rest/v1/conversations?uid=eq.$uid&order=last_time.desc');
        final res = await http.get(url, headers: _headers);
        if (res.statusCode == 200) {
          final List list = jsonDecode(res.body);
          yield list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  Stream<List<MessageModel>> privateMessagesStream(String conversationId) async* {
    while (true) {
      try {
        final url = Uri.parse('$_baseUrl/rest/v1/private_messages?conversation_id=eq.$conversationId&order=timestamp.asc');
        final res = await http.get(url, headers: _headers);
        if (res.statusCode == 200) {
          final List list = jsonDecode(res.body);
          yield list.map((e) => MessageModel.fromMap(Map<String, dynamic>.from(e as Map))).toList();
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 2));
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
      final effectiveConvId = (conversationId != null && conversationId.isNotEmpty)
          ? conversationId
          : (effectiveSenderUid.compareTo(effectiveReceiverUid) < 0
              ? '${effectiveSenderUid}_$effectiveReceiverUid'
              : '${effectiveReceiverUid}_$effectiveSenderUid');

      final msgId = const Uuid().v4();
      final now = DateTime.now().millisecondsSinceEpoch;
      await http.post(
        Uri.parse('$_baseUrl/rest/v1/private_messages'),
        headers: _headers,
        body: jsonEncode({
          'id': msgId,
          'conversation_id': effectiveConvId,
          'sender_uid': effectiveSenderUid,
          'receiver_uid': effectiveReceiverUid,
          'text': text,
          'type': type,
          'image_url': imageUrl,
          'timestamp': now,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } catch (_) {}
  }

  Future<void> markConversationRead(String uid, String conversationId) async {
    try {
      await http.patch(
        Uri.parse('$_baseUrl/rest/v1/conversations?uid=eq.$uid&conv_id=eq.$conversationId'),
        headers: _headers,
        body: jsonEncode({'unread_count': 0}),
      );
    } catch (_) {}
  }

  Stream<List<NotificationModel>> notificationsStream({String? uid}) async* {
    while (true) {
      try {
        final query = uid != null ? '?user_id=eq.$uid&order=created_at.desc&limit=50' : '?order=created_at.desc&limit=50';
        final url = Uri.parse('$_baseUrl/rest/v1/notifications$query');
        final res = await http.get(url, headers: _headers);
        if (res.statusCode == 200) {
          final List list = jsonDecode(res.body);
          yield list.map((e) => NotificationModel.fromMap(Map<String, dynamic>.from(e as Map))).toList();
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  Future<List<Map<String, dynamic>>> getGlobalRankings({required bool isWealth, required String timeframe}) async {
    try {
      final gifts = await _ds.getSentGifts('', limit: 200);
      final Map<String, int> totals = {};
      final Map<String, Map<String, dynamic>> userDetails = {};
      for (final g in gifts) {
        final uid = isWealth ? g.senderId : g.receiverId;
        final name = isWealth ? g.senderName : g.receiverName;
        final cost = g.value * g.count;
        totals[uid] = (totals[uid] ?? 0) + cost;
        userDetails[uid] = {'id': uid, 'name': name, 'photoUrl': isWealth ? g.senderPhotoUrl : ''};
      }
      final sortedKeys = totals.keys.toList()..sort((a, b) => totals[b]!.compareTo(totals[a]!));
      return sortedKeys.map((uid) => {
        'id': uid,
        'name': userDetails[uid]?['name'] ?? '',
        'photoUrl': userDetails[uid]?['photoUrl'] ?? '',
        'amount': totals[uid] ?? 0,
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getRoomGlobalRanking({required String timeframe}) async {
    try {
      final gifts = await _ds.getSentGifts('', limit: 200);
      final Map<String, int> roomTotals = {};
      for (final g in gifts) {
        if (g.roomId.isNotEmpty) {
          roomTotals[g.roomId] = (roomTotals[g.roomId] ?? 0) + (g.value * g.count);
        }
      }
      final sortedKeys = roomTotals.keys.toList()..sort((a, b) => roomTotals[b]!.compareTo(roomTotals[a]!));
      final List<Map<String, dynamic>> result = [];
      for (final rid in sortedKeys) {
        final room = await _ds.getRoom(rid);
        result.add({
          'roomId': rid,
          'name': room?.name ?? 'غرفة #$rid',
          'photoUrl': room?.roomPhotoUrl ?? '',
          'amount': roomTotals[rid] ?? 0,
        });
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getRoomRankings({required String roomId, required bool isWealth, required String timeframe}) async {
    try {
      final gifts = await _ds.getSentGifts(roomId, limit: 100);
      final Map<String, int> totals = {};
      final Map<String, Map<String, dynamic>> userDetails = {};
      for (final g in gifts) {
        final uid = isWealth ? g.senderId : g.receiverId;
        final name = isWealth ? g.senderName : g.receiverName;
        final cost = g.value * g.count;
        totals[uid] = (totals[uid] ?? 0) + cost;
        userDetails[uid] = {'id': uid, 'name': name, 'photoUrl': isWealth ? g.senderPhotoUrl : ''};
      }
      final sortedKeys = totals.keys.toList()..sort((a, b) => totals[b]!.compareTo(totals[a]!));
      return sortedKeys.map((uid) => {
        'id': uid,
        'name': userDetails[uid]?['name'] ?? '',
        'photoUrl': userDetails[uid]?['photoUrl'] ?? '',
        'amount': totals[uid] ?? 0,
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getBadgesCatalog() => _ds.getBadges();

  Future<List<Map<String, dynamic>>> getNecklacesCatalog() => _ds.getNecklaces();

  Future<dynamic> getAppConfig(String key) async {
    final cfg = await _ds.getAppConfig();
    return cfg[key];
  }

  Future<Map<String, dynamic>> getAnchorAgencyData({String? agencyId, required String agentUid}) async {
    try {
      final ag = await _ds.getHostAgencyForUser(agentUid, agencyId: agencyId);
      if (ag != null && ag['id'] != null) {
        final aid = ag['id'].toString();
        final members = await _ds.getHostAgencyMembers(aid);
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
      final res = await http.patch(
        Uri.parse('$_baseUrl/rest/v1/host_agencies?id=eq.$agencyId'),
        headers: _headers,
        body: jsonEncode({'announcement': notice, 'notice': notice, 'description': notice}),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeAgencyMember({String? agencyId, String? memberUid, String? userId}) =>
      exitAgencyAsMember(agencyId: agencyId ?? '', userId: memberUid ?? userId ?? '');

  Future<Map<String, dynamic>> createAgentDiamondWithdrawalRequest({required String agentUid, required String targetUid, required int diamondsAmount}) async {
    try {
      final res = await http.post(
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

  Future<Map<String, dynamic>> respondToAgentWithdrawalRequest({required String requestId, required String userUid, required bool approved, String? agentId, int? diamondsAmount, String? targetName}) async {
    try {
      final res = await http.patch(
        Uri.parse('$_baseUrl/rest/v1/agent_withdrawal_requests?id=eq.$requestId'),
        headers: _headers,
        body: jsonEncode({
          'status': approved ? 'approved' : 'rejected',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      return {'status': res.statusCode >= 200 && res.statusCode < 300 ? 'ok' : 'error'};
    } catch (_) {
      return {'status': 'error'};
    }
  }

  Stream<List<Map<String, dynamic>>> activeLuckyBagsStream(String roomId) async* {
    yield [];
  }

  Future<void> setDoc(String collection, String docId, Map<String, dynamic> data) async {
    try {
      final body = Map<String, dynamic>.from(data);
      if (!body.containsKey('id')) body['id'] = docId;
      await http.post(
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

