import '../../services/supabase_auth_service.dart';
import 'dart:convert';

import '../../core/supabase_compat.dart';
import 'package:flutter/foundation.dart';

import '../../services/supabase_service.dart';
import '../../services/supabase_data_service.dart';

class CpService {
  static SupabaseClient get _sb => Supabase.instance.client;

  static String? get _uid => SupabaseAuthService().currentUser?.uid;

  // ═══════════════════════════════════════════════════════
  // My Data
  // ═══════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> getMyData([String? userUid]) async {
    final uid = userUid ?? _uid;
    if (uid == null) return <String, dynamic>{'error': 'Not authenticated'};

    final couple = await _findActiveCoupleFor(uid);

    Map<String, dynamic>? activeTheme;
    if (couple != null) {
      final themeId = couple['active_theme_id'] as String?;
      if (themeId != null && themeId.isNotEmpty) {
        activeTheme = await _getTheme(themeId);
      }
    }

    final pending = await _findRequestsFor(uid, status: 'pending');
    final rejected = await _findRequestsFor(uid, status: 'rejected');
    final history = await _findHistoryFor(uid);

    final result = <String, dynamic>{
      'has_cp': couple != null,
      'active_theme': activeTheme,
      'pending_requests': pending,
      'rejected_requests': rejected,
      'history': history,
    };

    if (couple != null) {
      final partnerUid = couple['user1_uid'] == uid
          ? couple['user2_uid'] as String
          : couple['user1_uid'] as String;
      final partner = await SupabaseDataService().getUser(partnerUid);

      final startedRaw = couple['started_at'];
      final startedAt = _parseDate(startedRaw);
      final daysTogether = startedAt != null
          ? DateTime.now().difference(startedAt).inDays
          : 0;

      result['couple'] = <String, dynamic>{
        'id': couple['id'],
        'partner': <String, dynamic>{
          'uid': partnerUid,
          'name': partner?.name ?? '',
          'avatar': partner?.photoUrl ?? '',
        },
        'gift_id': couple['gift_id']?.toString() ?? 'ring_1',
        'started_at': couple['started_at'],
        'countdown_end': couple['countdown_end'],
        'days_together': daysTogether,
        'total_score': (couple['total_score'] as num?)?.toInt() ?? 0,
        'week_score': (couple['week_score'] as num?)?.toInt() ?? 0,
        'month_score': (couple['month_score'] as num?)?.toInt() ?? 0,
        'theme': activeTheme,
      };
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════
  // Ranking
  // ═══════════════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> getRanking({
    String period = 'week',
    int limit = 50,
  }) async {
    final scoreField = switch (period) {
      'week' => 'week_score',
      'month' => 'month_score',
      _ => 'total_score',
    };

    List<dynamic> snap = [];
    try {
      snap = await _sb.from('cp_couples').select('*').order(scoreField, ascending: false).limit(limit * 2);
    } catch (_) {}
    final rows = <Map<String, dynamic>>[];
    final seenPairs = <String>{};
    final seenUsers = <String>{};
    final now = DateTime.now();

    for (final doc in snap) {
      if (rows.length >= limit) break;
      final d = Map<String, dynamic>.from(doc as Map);
      if (d['ended_at'] != null) continue;

      final exp = _parseDate(d['expires_at'] ?? d['countdown_end']);
      if (exp != null && exp.isBefore(now)) {
        if (d['id'] != null) {
          _sb.from('cp_couples').update(<String, dynamic>{
            'ended_at': _now(),
            'updated_at': _now(),
          }).eq('id', d['id']).catchError((_) {});
        }
        continue;
      }

      final u1Uid = d['user1_uid']?.toString() ?? '';
      final u2Uid = d['user2_uid']?.toString() ?? '';
      if (u1Uid.isEmpty || u2Uid.isEmpty) continue;

      final pairKey = ([u1Uid, u2Uid]..sort()).join('_');
      if (seenPairs.contains(pairKey) || seenUsers.contains(u1Uid) || seenUsers.contains(u2Uid)) {
        continue;
      }
      seenPairs.add(pairKey);
      seenUsers.add(u1Uid);
      seenUsers.add(u2Uid);

      final u1 = await SupabaseDataService().getUser(u1Uid);
      final u2 = await SupabaseDataService().getUser(u2Uid);

      int days = 1;
      try {
        if (d['created_at'] is String) {
          days = DateTime.now().difference(DateTime.parse(d['created_at'])).inDays + 1;
        } else if (d['created_at'] is int) {
          days = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(d['created_at'])).inDays + 1;
        }
      } catch (_) {}

      rows.add(<String, dynamic>{
        'rank': rows.length + 1,
        'user1': <String, dynamic>{'name': u1?.name ?? '', 'avatar': u1?.photoUrl ?? ''},
        'user2': <String, dynamic>{'name': u2?.name ?? '', 'avatar': u2?.photoUrl ?? ''},
        'avatar1': u1?.photoUrl ?? '',
        'avatar2': u2?.photoUrl ?? '',
        'name1': u1?.name ?? '',
        'name2': u2?.name ?? '',
        'user1_uid': u1Uid,
        'user2_uid': u2Uid,
        'score': (d[scoreField] as num?)?.toInt() ?? 0,
        'cp_days': days,
      });
    }

    return rows;
  }

  // ═══════════════════════════════════════════════════════
  // Themes & Settings
  // ═══════════════════════════════════════════════════════


  static Future<List<Map<String, dynamic>>> getThemes() async {
    try {
      final snap = await _sb.from('cp_themes').select('*').order('sort_order', ascending: true);
      final list = (snap as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => e['is_active'] != false)
          .toList();
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> getSettings() async {
    try {
      final snap = await _sb.from('cp_settings').select('*');
      final map = <String, dynamic>{};
      for (final doc in (snap as List<dynamic>)) {
        final d = Map<String, dynamic>.from(doc as Map);
        final k = d['id'] ?? d['key'];
        if (k != null) {
          map[k.toString()] = d['value'];
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  // ═══════════════════════════════════════════════════════
  // Requests
  // ═══════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> sendRequest(
    String receiverId, {
    String? message,
    String? giftId,
    int durationHours = 24,
  }) async {
    final sender = _uid;
    if (sender == null) return <String, dynamic>{'error': 'Not authenticated'};
    if (sender == receiverId) {
      return <String, dynamic>{'error': 'Cannot send request to yourself'};
    }

    if (await _findActiveCoupleFor(sender) != null) {
      return <String, dynamic>{'error': 'You already have an active CP'};
    }
    if (await _findActiveCoupleFor(receiverId) != null) {
      return <String, dynamic>{'error': 'Receiver already has an active CP'};
    }

    final pending = await _findRequestsFor(sender, status: 'pending');
    for (final r in pending) {
      if (r['receiver_uid'] == receiverId) {
        return <String, dynamic>{'error': 'Request already sent'};
      }
    }

    final resp = await _sb.from('cp_requests').insert(<String, dynamic>{
      'sender_uid': sender,
      'receiver_uid': receiverId,
      'message': message,
      'gift_id': giftId,
      'duration_hours': durationHours,
      'status': 'pending',
      'created_at': _now(),
    }).select('id').maybeSingle();

    return <String, dynamic>{'success': true, 'id': resp?['id']?.toString()};
  }

  static Future<Map<String, dynamic>> respondRequest(
    String requestId,
    bool accept,
  ) async {
    final receiver = _uid;
    if (receiver == null) return <String, dynamic>{'error': 'Not authenticated'};

    final reqDoc = await _sb.from('cp_requests').select('*').eq('id', requestId).maybeSingle();
    if (reqDoc == null) return <String, dynamic>{'error': 'Request not found'};
    final req = Map<String, dynamic>.from(reqDoc as Map);
    if (req['receiver_uid'] != receiver) {
      return <String, dynamic>{'error': 'Not your request'};
    }

    await _sb.from('cp_requests').update(<String, dynamic>{
      'status': accept ? 'accepted' : 'rejected',
      'responded_at': _now(),
    }).eq('id', requestId);

    if (accept) {
      final senderUid = req['sender_uid'] as String;
      final durationHours = (req['duration_hours'] as num?)?.toInt() ?? 24;
      final expireTime = DateTime.now().add(Duration(hours: durationHours)).toIso8601String();
      await _endActiveCouplesFor(senderUid);
      await _endActiveCouplesFor(receiver);

      await _sb.from('cp_couples').insert(<String, dynamic>{
        'user1_uid': senderUid,
        'user2_uid': receiver,
        'started_at': _now(),
        'countdown_end': expireTime,
        'expires_at': expireTime,
        'duration_hours': durationHours,
        'total_score': 0,
        'week_score': 0,
        'month_score': 0,
        'created_at': _now(),
        'updated_at': _now(),
      });

      // Grant CP Link Rewards for Male & Female partners
      try {
        await _grantCpLinkRewards(
          senderUid: senderUid,
          receiverUid: receiver,
          giftId: req['gift_id'] as String?,
        );
      } catch (e) {
        debugPrint('Error granting CP link rewards: $e');
      }
    }

    return <String, dynamic>{'success': true};
  }

  static Future<void> _grantCpLinkRewards({
    required String senderUid,
    required String receiverUid,
    String? giftId,
  }) async {
    final u1 = await SupabaseDataService().getUser(senderUid);
    final u2 = await SupabaseDataService().getUser(receiverUid);

    Map<String, dynamic>? giftData;
    if (giftId != null && giftId.isNotEmpty) {
      final snap = await _sb.from('cp_gifts').select('*').eq('id', giftId).maybeSingle();
      if (snap != null) {
        giftData = Map<String, dynamic>.from(snap as Map);
      } else {
        final gSnap = await _sb.from('gifts').select('*').eq('id', giftId).maybeSingle();
        if (gSnap != null) giftData = Map<String, dynamic>.from(gSnap as Map);
      }
    }

    final settings = await getSettings();

    // Male reward extraction
    final maleName = giftData?['male_reward_name']?.toString() ??
        settings['cp_link_male_reward_name']?.toString() ??
        '';
    final maleType = giftData?['male_reward_type']?.toString() ??
        settings['cp_link_male_reward_type']?.toString() ??
        'ring';
    final maleSvga = giftData?['male_reward_svga']?.toString() ??
        settings['cp_link_male_reward_svga']?.toString() ??
        '';
    final maleIcon = giftData?['male_reward_icon']?.toString() ??
        settings['cp_link_male_reward_icon']?.toString() ??
        '';
    final maleCoins = (giftData?['male_reward_coins'] as num?)?.toInt() ??
        (int.tryParse(settings['cp_link_male_reward_coins']?.toString() ?? '0') ?? 0);
    final maleDays = (giftData?['male_reward_days'] as num?)?.toInt() ??
        (int.tryParse(settings['cp_link_male_reward_days']?.toString() ?? '7') ?? 7);

    // Female reward extraction
    final femaleName = giftData?['female_reward_name']?.toString() ??
        settings['cp_link_female_reward_name']?.toString() ??
        '';
    final femaleType = giftData?['female_reward_type']?.toString() ??
        settings['cp_link_female_reward_type']?.toString() ??
        'ring';
    final femaleSvga = giftData?['female_reward_svga']?.toString() ??
        settings['cp_link_female_reward_svga']?.toString() ??
        '';
    final femaleIcon = giftData?['female_reward_icon']?.toString() ??
        settings['cp_link_female_reward_icon']?.toString() ??
        '';
    final femaleCoins = (giftData?['female_reward_coins'] as num?)?.toInt() ??
        (int.tryParse(settings['cp_link_female_reward_coins']?.toString() ?? '0') ?? 0);
    final femaleDays = (giftData?['female_reward_days'] as num?)?.toInt() ??
        (int.tryParse(settings['cp_link_female_reward_days']?.toString() ?? '7') ?? 7);

    // Determine who gets male vs female reward
    final u1Gender = u1?.gender;
    final u2Gender = u2?.gender;
    final u1IsFemale = (u1Gender?.toLowerCase() == 'female' || u1Gender == 'أنثى' || u1Gender == '2');
    final u2IsFemale = (u2Gender?.toLowerCase() == 'female' || u2Gender == 'أنثى' || u2Gender == '2');

    final maleUid = u1IsFemale ? receiverUid : (u2IsFemale ? senderUid : senderUid);
    final femaleUid = maleUid == senderUid ? receiverUid : senderUid;

    // Deliver to male backpack & coins
    if (maleName.isNotEmpty || maleSvga.isNotEmpty || maleIcon.isNotEmpty) {
      await _sb.from('user_backpack').insert(<String, dynamic>{
        'user_id': maleUid,
        'item_id': 'cp_reward_male_${DateTime.now().millisecondsSinceEpoch}',
        'item_name': maleName.isNotEmpty ? maleName : 'مكافأة ارتباط CP',
        'item_type': maleType,
        'item_icon': maleIcon,
        'item_svga': maleSvga,
        'duration_days': maleDays,
        'expires_at': DateTime.now().add(Duration(days: maleDays)).toIso8601String(),
        'created_at': _now(),
        'is_equipped': false,
        'source': 'cp_link',
      });
      if (maleCoins > 0) {
        final u = await _sb.from('users').select('coins').or('uid.eq.$maleUid,id.eq.$maleUid').maybeSingle();
        final cur = (u?['coins'] as num?)?.toInt() ?? 0;
        await _sb.from('users').update({'coins': cur + maleCoins}).or('uid.eq.$maleUid,id.eq.$maleUid');
      }
      await SupabaseDataService().sendNotification(
        uid: maleUid,
        type: 'cp_link_reward',
        actorUid: femaleUid,
        title: '🎉 مبروك الارتباط!',
        body: 'تم استلام مكافأة الشريك ($maleName) في حقيبتك بنجاح 🎁',
      );
    }

    // Deliver to female backpack & coins
    if (femaleName.isNotEmpty || femaleSvga.isNotEmpty || femaleIcon.isNotEmpty) {
      await _sb.from('user_backpack').insert(<String, dynamic>{
        'user_id': femaleUid,
        'item_id': 'cp_reward_female_${DateTime.now().millisecondsSinceEpoch}',
        'item_name': femaleName.isNotEmpty ? femaleName : 'مكافأة ارتباط CP',
        'item_type': femaleType,
        'item_icon': femaleIcon,
        'item_svga': femaleSvga,
        'duration_days': femaleDays,
        'expires_at': DateTime.now().add(Duration(days: femaleDays)).toIso8601String(),
        'created_at': _now(),
        'is_equipped': false,
        'source': 'cp_link',
      });
      if (femaleCoins > 0) {
        final u = await _sb.from('users').select('coins').or('uid.eq.$femaleUid,id.eq.$femaleUid').maybeSingle();
        final cur = (u?['coins'] as num?)?.toInt() ?? 0;
        await _sb.from('users').update({'coins': cur + femaleCoins}).or('uid.eq.$femaleUid,id.eq.$femaleUid');
      }
      await SupabaseDataService().sendNotification(
        uid: femaleUid,
        type: 'cp_link_reward',
        actorUid: maleUid,
        title: '🎉 مبروك الارتباط!',
        body: 'تم استلام مكافأة الشريكة ($femaleName) في حقيبتك بنجاح 🎁',
      );
    }
  }

  static Future<bool> setTheme(String themeId) async {
    final uid = _uid;
    if (uid == null) return false;
    final couple = await _findActiveCoupleFor(uid);
    if (couple == null) return false;
    await _sb.from('cp_couples').update(<String, dynamic>{
      'active_theme_id': themeId,
      'updated_at': _now(),
    }).eq('id', couple['id']);
    return true;
  }

  static Future<bool> endCp() async {
    final uid = _uid;
    if (uid == null) return false;
    final couple = await _findActiveCoupleFor(uid);
    if (couple == null) return false;
    await _sb.from('cp_couples').update(<String, dynamic>{
      'ended_at': _now(),
      'updated_at': _now(),
    }).eq('id', couple['id']);
    return true;
  }

  // ═══════════════════════════════════════════════════════
  // Gifts & Cars
  // ═══════════════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> getCpGifts() async {
    try {
      final snap = await _sb.from('cp_gifts').select('*').order('sort_order', ascending: true);
      return (snap as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => e['is_active'] != false)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getCpCars() async {
    try {
      final snap = await _sb.from('cp_cars').select('*').order('sort_order', ascending: true);
      return (snap as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => e['is_active'] != false)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> sendCpGift({
    required String giftId,
    required String receiverId,
  }) async {
    final sender = _uid;
    if (sender == null) return <String, dynamic>{'error': 'Not authenticated'};

    final giftSnap = await _sb.from('cp_gifts').select('*').eq('id', giftId).maybeSingle();
    if (giftSnap == null || giftSnap['is_active'] == false) {
      return <String, dynamic>{'error': 'Gift not found'};
    }
    final gift = Map<String, dynamic>.from(giftSnap as Map);
    final giftValue = (gift['value'] as num?)?.toInt() ?? 0;
    final giftName = gift['name_ar']?.toString() ?? gift['name']?.toString() ?? '';

    final couple = await _findActiveCoupleFor(sender);
    if (couple == null) return <String, dynamic>{'error': 'No active CP'};

    final partnerUid = couple['user1_uid'] == sender
        ? couple['user2_uid'] as String
        : couple['user1_uid'] as String;
    if (partnerUid != receiverId) {
      return <String, dynamic>{'error': 'Receiver is not your CP partner'};
    }

    final senderDoc = await _sb.from('users').select('coins').or('uid.eq.$sender,id.eq.$sender').maybeSingle();
    final balance = (senderDoc?['coins'] as num?)?.toInt() ?? 0;
    if (balance < giftValue) {
      return <String, dynamic>{
        'error': 'Insufficient coins',
        'need': giftValue,
        'balance': balance,
      };
    }

    final dType = gift['duration_type']?.toString();
    final dVal = (gift['duration_value'] as num?)?.toInt();
    int extraHours = 0;
    if (dType == 'hours' && dVal != null && dVal > 0) {
      extraHours = dVal;
    } else if (dType == 'days' && dVal != null && dVal > 0) {
      extraHours = dVal * 24;
    } else {
      extraHours = (gift['duration_hours'] as num?)?.toInt() ??
          ((gift['duration_days'] as num?)?.toInt() != null
              ? (gift['duration_days'] as num).toInt() * 24
              : ((gift['cp_gift_duration_hours'] as num?)?.toInt() ?? 0));
    }

    await _sb.from('users').update({
      'coins': balance - giftValue,
    }).or('uid.eq.$sender,id.eq.$sender');

    final curTotal = (couple['total_score'] as num?)?.toInt() ?? 0;
    final curWeek = (couple['week_score'] as num?)?.toInt() ?? 0;
    final curMonth = (couple['month_score'] as num?)?.toInt() ?? 0;
    final coupleUpdates = <String, dynamic>{
      'total_score': curTotal + giftValue,
      'week_score': curWeek + giftValue,
      'month_score': curMonth + giftValue,
      'updated_at': _now(),
    };

    if (extraHours > 0) {
      final curExp = _parseDate(couple['expires_at'] ?? couple['countdown_end']) ?? DateTime.now();
      final baseDate = curExp.isAfter(DateTime.now()) ? curExp : DateTime.now();
      final newExp = baseDate.add(Duration(hours: extraHours)).toIso8601String();
      coupleUpdates['countdown_end'] = newExp;
      coupleUpdates['expires_at'] = newExp;
    }

    await _sb.from('cp_couples').update(coupleUpdates).eq('id', couple['id']);

    await _sb.from('cp_gift_logs').insert(<String, dynamic>{
      'couple_id': couple['id'],
      'sender_uid': sender,
      'receiver_uid': receiverId,
      'gift_id': giftId,
      'gift_name': giftName,
      'gift_value': giftValue,
      'created_at': _now(),
    });

    await SupabaseDataService().sendNotification(
      uid: receiverId,
      type: 'cp_gift',
      actorUid: sender,
      title: '🎁 هدية CP',
      body: 'أرسل لك شريكك هدية 🎁',
      data: <String, dynamic>{
        'gift_name': giftName,
        'gift_value': giftValue,
        'couple_id': couple['id'],
      },
    );

    return <String, dynamic>{
      'success': true,
      'gift_value': giftValue,
      'new_score': curTotal + giftValue,
    };
  }

  /// Send a CP gift to create or strengthen a CP relationship.
  /// If user has no CP, sends a request + notification with gift info.
  /// Returns: {success: bool, message: String, couple_id?: String}
  static Future<Map<String, dynamic>> sendGiftAndLink({
    required String giftId,
    required String senderId,
    required String senderName,
    required String receiverId,
    String? receiverName,
    String? giftName,
    int? giftValue,
    int durationHours = 24,
  }) async {
    try {
      final myData = await getMyData();
      final couple = myData['couple'] as Map<String, dynamic>?;

      if (couple != null) {
        final partnerId = couple['partner']?['uid'] as String?;
        if (partnerId == receiverId) {
          try {
            return await sendCpGift(giftId: giftId, receiverId: receiverId);
          } catch (_) {
            await sendCpGiftNotification(
              senderId: senderId,
              senderName: senderName,
              receiverId: receiverId,
              receiverName: receiverName ?? '',
              giftName: giftName,
              giftValue: giftValue,
            );
            return <String, dynamic>{
              'success': true,
              'message': 'تم إرسال الهدية لشريكك بنجاح',
            };
          }
        }
        return <String, dynamic>{'error': 'لديك علاقة CP بالفعل مع شخص آخر'};
      }

      int finalDurationHours = durationHours;
      try {
        final dur = await SupabaseDataService().getGiftCpDurationHours(giftId);
        if (dur != null && dur > 0) {
          finalDurationHours = dur;
        }
      } catch (_) {}

      try {
        final gSnap = await _sb.from('cp_gifts').select('*').eq('id', giftId).maybeSingle();
        Map<String, dynamic>? gData;
        if (gSnap != null) {
          gData = Map<String, dynamic>.from(gSnap as Map);
        } else {
          final regSnap = await _sb.from('gifts').select('*').eq('id', giftId).maybeSingle();
          if (regSnap != null) gData = Map<String, dynamic>.from(regSnap as Map);
        }

        if (gData != null) {
          final dType = gData['duration_type']?.toString();
          final dVal = (gData['duration_value'] as num?)?.toInt();
          if (dType == 'hours' && dVal != null && dVal > 0) {
            finalDurationHours = dVal;
          } else if (dType == 'days' && dVal != null && dVal > 0) {
            finalDurationHours = dVal * 24;
          } else {
            final dDays = (gData['duration_days'] as num?)?.toInt();
            final dHours = (gData['duration_hours'] as num?)?.toInt() ?? (gData['cp_gift_duration_hours'] as num?)?.toInt();
            if (dDays != null && dDays > 0) {
              finalDurationHours = dDays * 24;
            } else if (dHours != null && dHours > 0) {
              finalDurationHours = dHours;
            }
          }
        }
      } catch (_) {}

      final expireTime = DateTime.now().add(Duration(hours: finalDurationHours)).toIso8601String();
      try {
        await _endActiveCouplesFor(senderId);
        await _endActiveCouplesFor(receiverId);
        await _sb.from('cp_couples').insert(<String, dynamic>{
          'user1_uid': senderId,
          'user2_uid': receiverId,
          'started_at': _now(),
          'countdown_end': expireTime,
          'expires_at': expireTime,
          'duration_hours': finalDurationHours,
          'total_score': giftValue ?? 0,
          'week_score': giftValue ?? 0,
          'month_score': giftValue ?? 0,
          'created_at': _now(),
          'updated_at': _now(),
        });
      } catch (cpErr) {
        debugPrint('[CpService] direct link error: $cpErr');
      }

      final reqResult = await sendRequest(
        receiverId,
        message: 'أرسل لك هدية CP 🎁',
        giftId: giftId,
        durationHours: finalDurationHours,
      );
      final success = reqResult['success'] == true || reqResult['id'] != null;
      if (!success) {
        return <String, dynamic>{'error': reqResult['error'] ?? 'فشل إرسال الطلب'};
      }

      final requestId = reqResult['id']?.toString();
      await sendCpGiftNotification(
        senderId: senderId,
        senderName: senderName,
        receiverId: receiverId,
        receiverName: receiverName ?? '',
        giftName: giftName,
        giftValue: giftValue,
        requestId: requestId,
      );

      return <String, dynamic>{
        'success': true,
        'message': 'تم إرسال هدية CP وطلب الارتباط بنجاح',
        'request_id': requestId,
      };
    } catch (e) {
      return <String, dynamic>{'error': e.toString()};
    }
  }

  /// Send CP gift notification to partner (not linked yet) with accept/decline action.
  static Future<void> sendCpGiftNotification({
    required String senderId,
    required String senderName,
    required String receiverId,
    required String receiverName,
    String? giftName,
    int? giftValue,
    String? requestId,
  }) async {
    await SupabaseDataService().sendNotification(
      uid: receiverId,
      type: 'cp_gift',
      actorUid: senderId,
      title: '💝 هدية CP من $senderName',
      body: 'أرسل $senderName هدية CP لك. هل توافق على ربط علاقة CP?',
      data: <String, dynamic>{
        'sender_id': senderId,
        'sender_name': senderName,
        'gift_name': giftName ?? '',
        'gift_value': giftValue ?? 0,
        if (requestId != null) 'request_id': requestId,
        'action': 'cp_relationship_request',
      },
    );
  }

  // ═══════════════════════════════════════════════════════
  // History & Achievements
  // ═══════════════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> getCpHistory({int limit = 50}) async {
    final uid = _uid;
    if (uid == null) return <Map<String, dynamic>>[];

    final couple = await _findLatestCoupleFor(uid);
    if (couple == null) return <Map<String, dynamic>>[];

    try {
      final snap = await _sb
          .from('cp_gift_logs')
          .select('*')
          .eq('couple_id', couple['id'])
          .order('created_at', ascending: false)
          .limit(limit);

      final result = <Map<String, dynamic>>[];
      for (final doc in (snap as List<dynamic>)) {
        final log = Map<String, dynamic>.from(doc as Map);
        final sender = await SupabaseDataService().getUser(log['sender_uid'] as String? ?? '');
        result.add(<String, dynamic>{
          'id': log['id'],
          'action': 'gift',
          'user_name': sender?.name ?? '',
          'gift_name': log['gift_name'] ?? '',
          'gift_value': (log['gift_value'] as num?)?.toInt() ?? 0,
          'timestamp': log['created_at'],
        });
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getCpAchievements({String? coupleId}) async {
    final uid = _uid;
    if (uid == null) return <Map<String, dynamic>>[];

    Map<String, dynamic>? couple;
    if (coupleId != null && coupleId.isNotEmpty) {
      final doc = await _sb.from('cp_couples').select('*').eq('id', coupleId).maybeSingle();
      if (doc != null) couple = Map<String, dynamic>.from(doc as Map);
    } else {
      couple = await _findActiveCoupleFor(uid);
    }
    if (couple == null) return <Map<String, dynamic>>[];

    int giftCount = 0;
    int totalGiftValue = 0;
    try {
      final logs = await _sb
          .from('cp_gift_logs')
          .select('gift_value')
          .eq('couple_id', couple['id']);
      giftCount = logs.length;
      for (final log in logs) {
        totalGiftValue += (log['gift_value'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}

    final startedRaw = couple['started_at'];
    final endedRaw = couple['ended_at'];
    final startedAt = _parseDate(startedRaw);
    final endedAt = _parseDate(endedRaw) ?? DateTime.now();
    final daysTogether = startedAt != null
        ? endedAt.difference(startedAt).inDays
        : 0;

    return <Map<String, dynamic>>[
      <String, dynamic>{'icon': 'favorite', 'title': '$daysTogether يوم', 'subtitle': 'معاً'},
      <String, dynamic>{'icon': 'favorite', 'title': '${couple['total_score'] ?? 0}', 'subtitle': 'القربى'},
      <String, dynamic>{'icon': 'card_giftcard', 'title': '$giftCount', 'subtitle': 'الهدايا'},
      <String, dynamic>{'icon': 'stars', 'title': '$totalGiftValue', 'subtitle': 'قيمة الهدايا'},
    ];
  }

  /// Get the total CP gift value sent by a specific user (individual, not couple).
  static Future<int> getUserCpGiftTotal(String uid) async {
    try {
      final snap = await _sb
          .from('cp_gift_logs')
          .select('gift_value')
          .eq('sender_uid', uid);
      var total = 0;
      for (final doc in snap) {
        total += (doc['gift_value'] as num?)?.toInt() ?? 0;
      }
      return total;
    } catch (e) {
      debugPrint('[CpService] getUserCpGiftTotal error: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════
  // Rank Rewards
  // ═══════════════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> getRankRewards({String period = 'weekly'}) async {
    try {
      final snap = await _sb
          .from('cp_rank_rewards')
          .select('*')
          .eq('period', period);
      final list = (snap as List<dynamic>).map((e) {
        return Map<String, dynamic>.from(e as Map);
      }).where((d) => d['isActive'] != false && d['is_active'] != false).toList();
      list.sort((a, b) {
        final rankCmp = ((a['rank_position'] as num?)?.toInt() ?? 0)
            .compareTo((b['rank_position'] as num?)?.toInt() ?? 0);
        if (rankCmp != 0) return rankCmp;
        return ((a['slot_index'] as num?)?.toInt() ?? 0)
            .compareTo((b['slot_index'] as num?)?.toInt() ?? 0);
      });
      return list;
    } catch (e) {
      debugPrint('[CpService] getRankRewards error: $e');
      try {
        final settings = await getSettings();
        final raw = settings['cp_rank_rewards_data']?.toString();
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          final all = List<Map<String, dynamic>>.from(decoded as List);
          final filtered = all.where((r) => r['period'] == period).toList();
          filtered.sort((a, b) {
            final rankCmp = ((a['rank_position'] as int?) ?? 0).compareTo((b['rank_position'] as int?) ?? 0);
            if (rankCmp != 0) return rankCmp;
            return ((a['slot_index'] as int?) ?? 0).compareTo((b['slot_index'] as int?) ?? 0);
          });
          return filtered;
        }
      } catch (_) {}
    }
    return <Map<String, dynamic>>[];
  }

  /// Realtime stream of rank rewards for a period (cp_rank_rewards collection).
  static Stream<List<Map<String, dynamic>>> rewardsStream({
    String period = 'weekly',
  }) {
    return _sb.from('cp_rank_rewards').stream(primaryKey: ['id']).map((list) {
      final res = list
          .map((e) => Map<String, dynamic>.from(e))
          .where((d) => d['period'] == period && d['is_active'] != false && d['isActive'] != false)
          .toList();
      res.sort((a, b) {
        final rankCmp = ((a['rank_position'] as num?)?.toInt() ?? 0)
            .compareTo((b['rank_position'] as num?)?.toInt() ?? 0);
        if (rankCmp != 0) return rankCmp;
        return ((a['slot_index'] as num?)?.toInt() ?? 0)
            .compareTo((b['slot_index'] as num?)?.toInt() ?? 0);
      });
      return res;
    });
  }

  // ═══════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════

  static String _now() => DateTime.now().toIso8601String();

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  /// Active couple (ended_at is null and not expired) where [uid] is a member.
  static Future<Map<String, dynamic>?> _findActiveCoupleFor(String uid) async {
    try {
      final res = await _sb.from('cp_couples')
          .select('*')
          .or('user1_uid.eq.$uid,user2_uid.eq.$uid')
          .isFilter('ended_at', null)
          .limit(10);
      final now = DateTime.now();
      for (final doc in res) {
        final d = Map<String, dynamic>.from(doc as Map);
        final exp = _parseDate(d['expires_at'] ?? d['countdown_end']);
        if (exp != null && exp.isBefore(now)) {
          if (d['id'] != null) {
            _sb.from('cp_couples').update(<String, dynamic>{
              'ended_at': _now(),
              'updated_at': _now(),
            }).eq('id', d['id']).catchError((_) {});
          }
          continue;
        }
        return d;
      }
    } catch (_) {}
    return null;
  }

  /// Most recent couple (active or ended) for [uid].
  static Future<Map<String, dynamic>?> _findLatestCoupleFor(String uid) async {
    try {
      final res = await _sb.from('cp_couples')
          .select('*')
          .or('user1_uid.eq.$uid,user2_uid.eq.$uid')
          .order('created_at', ascending: false)
          .limit(1);
      if (res.isNotEmpty) {
        return Map<String, dynamic>.from(res.first as Map);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _endActiveCouplesFor(String uid) async {
    final couple = await _findActiveCoupleFor(uid);
    if (couple == null) return;
    await _sb.from('cp_couples').update(<String, dynamic>{
      'ended_at': _now(),
      'updated_at': _now(),
    }).eq('id', couple['id']);
  }

  static Future<Map<String, dynamic>?> _getTheme(String themeId) async {
    try {
      final doc = await _sb.from('cp_themes').select('*').eq('id', themeId).maybeSingle();
      if (doc != null) return Map<String, dynamic>.from(doc as Map);
    } catch (_) {}
    return null;
  }

  static Future<List<Map<String, dynamic>>> _findRequestsFor(String uid,
      {String? status}) async {
    try {
      var query = _sb.from('cp_requests').select('*').eq('receiver_uid', uid);
      if (status != null) {
        query = query.eq('status', status);
      }
      final res = await query;
      final list = <Map<String, dynamic>>[];
      for (final doc in res) {
        final d = Map<String, dynamic>.from(doc as Map);
        final sender = await SupabaseDataService().getUser(d['sender_uid'] as String? ?? '');
        list.add(<String, dynamic>{
          'id': d['id'],
          'sender_uid': d['sender_uid'],
          'receiver_uid': d['receiver_uid'],
          'status': d['status'],
          'message': d['message'],
          'sender_name': sender?.name ?? '',
          'sender_avatar': sender?.photoUrl ?? '',
        });
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> _findHistoryFor(String uid) async {
    try {
      final res = await _sb.from('cp_couples')
          .select('*')
          .or('user1_uid.eq.$uid,user2_uid.eq.$uid')
          .not('ended_at', 'is', null)
          .order('ended_at', ascending: false);
      final ended = <Map<String, dynamic>>[];
      for (final doc in res) {
        final d = Map<String, dynamic>.from(doc as Map);
        final isUser1 = d['user1_uid'] == uid;
        final partnerUid = isUser1 ? d['user2_uid'] as String : d['user1_uid'] as String;
        final partner = await SupabaseDataService().getUser(partnerUid);
        ended.add(<String, dynamic>{
          'partner_name': partner?.name ?? '',
          'partner_avatar': partner?.photoUrl ?? '',
          'total_score': (d['total_score'] as num?)?.toInt() ?? 0,
          'started_at': d['started_at'],
          'ended_at': d['ended_at'],
        });
      }
      return ended;
    } catch (_) {
      return [];
    }
  }
}
