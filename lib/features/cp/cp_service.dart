import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../services/firebase_service.dart';

/// CP (Relationships) service backed by Firestore.
///
/// Collections mirror the original Postgres tables:
///   cp_couples, cp_requests, cp_themes, cp_settings,
///   cp_gifts, cp_cars, cp_gift_logs, cp_rank_rewards
///
/// Response shapes match the original RPC output so screens are unchanged.
class CpService {
  static FirebaseFirestore get _db => FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'default',
      );

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

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
      final partner = await FirebaseService().getUser(partnerUid);

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

    final snap = await _db.collection('cp_couples').orderBy(scoreField, descending: true).get();
    final rows = <Map<String, dynamic>>[];
    final seenPairs = <String>{};
    final seenUsers = <String>{};
    final now = DateTime.now();

    for (final doc in snap.docs) {
      if (rows.length >= limit) break;
      final d = doc.data();
      if (d['ended_at'] != null) continue;

      final exp = _parseDate(d['expires_at'] ?? d['countdown_end']);
      if (exp != null && exp.isBefore(now)) {
        doc.reference.update(<String, dynamic>{
          'ended_at': _now(),
          'updated_at': _now(),
        }).catchError((_) {});
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

      final u1 = await FirebaseService().getUser(u1Uid);
      final u2 = await FirebaseService().getUser(u2Uid);

      int days = 1;
      try {
        if (d['created_at'] is Timestamp) {
          days = DateTime.now().difference((d['created_at'] as Timestamp).toDate()).inDays + 1;
        } else if (d['created_at'] is String) {
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
    final snap = await _db.collection('cp_themes').orderBy('sort_order').get();
    final list = snap.docs
        .where((e) => e.data()['is_active'] != false)
        .map((e) {
          final d = e.data();
          d['id'] = e.id;
          return d;
        })
        .toList();
    return list;
  }

  static Future<Map<String, dynamic>> getSettings() async {
    final snap = await _db.collection('cp_settings').get();
    final map = <String, dynamic>{};
    for (final doc in snap.docs) {
      map[doc.id] = doc.data()['value'];
    }
    return map;
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

    final doc = await _db.collection('cp_requests').add(<String, dynamic>{
      'sender_uid': sender,
      'receiver_uid': receiverId,
      'message': message,
      'gift_id': giftId,
      'duration_hours': durationHours,
      'status': 'pending',
      'created_at': _now(),
    });

    return <String, dynamic>{'success': true, 'id': doc.id};
  }

  static Future<Map<String, dynamic>> respondRequest(
    String requestId,
    bool accept,
  ) async {
    final receiver = _uid;
    if (receiver == null) return <String, dynamic>{'error': 'Not authenticated'};

    final reqDoc = await _db.collection('cp_requests').doc(requestId).get();
    if (!reqDoc.exists) return <String, dynamic>{'error': 'Request not found'};
    final req = reqDoc.data()!;
    if (req['receiver_uid'] != receiver) {
      return <String, dynamic>{'error': 'Not your request'};
    }

    await reqDoc.reference.update(<String, dynamic>{
      'status': accept ? 'accepted' : 'rejected',
      'responded_at': _now(),
    });

    if (accept) {
      final senderUid = req['sender_uid'] as String;
      final durationHours = (req['duration_hours'] as num?)?.toInt() ?? 24;
      final expireTime = DateTime.now().add(Duration(hours: durationHours)).toIso8601String();
      await _endActiveCouplesFor(senderUid);
      await _endActiveCouplesFor(receiver);

      await _db.collection('cp_couples').add(<String, dynamic>{
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
    final u1 = await FirebaseService().getUser(senderUid);
    final u2 = await FirebaseService().getUser(receiverUid);

    Map<String, dynamic>? giftData;
    if (giftId != null && giftId.isNotEmpty) {
      final snap = await _db.collection('cp_gifts').doc(giftId).get();
      if (snap.exists) {
        giftData = snap.data();
      } else {
        final gSnap = await _db.collection('gifts').doc(giftId).get();
        if (gSnap.exists) giftData = gSnap.data();
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
      await _db.collection('user_backpack').add(<String, dynamic>{
        'user_id': maleUid,
        'item_id': 'cp_reward_male_${DateTime.now().millisecondsSinceEpoch}',
        'item_name': maleName.isNotEmpty ? maleName : 'مكافأة ارتباط CP (شاب)',
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
        await _db.collection('users').doc(maleUid).update({
          'coins': FieldValue.increment(maleCoins),
        });
      }
      await FirebaseService().sendNotification(
        uid: maleUid,
        type: 'cp_link_reward',
        actorUid: femaleUid,
        title: '🎉 مبروك الارتباط!',
        body: 'تم استلام مكافأة الشريك ($maleName) في حقيبتك بنجاح 🎁',
      );
    }

    // Deliver to female backpack & coins
    if (femaleName.isNotEmpty || femaleSvga.isNotEmpty || femaleIcon.isNotEmpty) {
      await _db.collection('user_backpack').add(<String, dynamic>{
        'user_id': femaleUid,
        'item_id': 'cp_reward_female_${DateTime.now().millisecondsSinceEpoch}',
        'item_name': femaleName.isNotEmpty ? femaleName : 'مكافأة ارتباط CP (فتاة)',
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
        await _db.collection('users').doc(femaleUid).update({
          'coins': FieldValue.increment(femaleCoins),
        });
      }
      await FirebaseService().sendNotification(
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
    await _db.collection('cp_couples').doc(couple['id']).update(<String, dynamic>{
      'active_theme_id': themeId,
      'updated_at': _now(),
    });
    return true;
  }

  static Future<bool> endCp() async {
    final uid = _uid;
    if (uid == null) return false;
    final couple = await _findActiveCoupleFor(uid);
    if (couple == null) return false;
    await _db.collection('cp_couples').doc(couple['id']).update(<String, dynamic>{
      'ended_at': _now(),
      'updated_at': _now(),
    });
    return true;
  }

  // ═══════════════════════════════════════════════════════
  // Gifts & Cars
  // ═══════════════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> getCpGifts() async {
    final snap = await _db.collection('cp_gifts').orderBy('sort_order').get();
    final list = snap.docs
        .where((e) => e.data()['is_active'] != false)
        .map((e) {
          final d = e.data();
          d['id'] = e.id;
          return d;
        })
        .toList();
    return list;
  }

  static Future<List<Map<String, dynamic>>> getCpCars() async {
    final snap = await _db.collection('cp_cars').orderBy('sort_order').get();
    final list = snap.docs
        .where((e) => e.data()['is_active'] != false)
        .map((e) {
          final d = e.data();
          d['id'] = e.id;
          return d;
        })
        .toList();
    return list;
  }

  static Future<Map<String, dynamic>> sendCpGift({
    required String giftId,
    required String receiverId,
  }) async {
    final sender = _uid;
    if (sender == null) return <String, dynamic>{'error': 'Not authenticated'};

    final giftSnap = await _db.collection('cp_gifts').doc(giftId).get();
    if (!giftSnap.exists || giftSnap.data()?['is_active'] == false) {
      return <String, dynamic>{'error': 'Gift not found'};
    }
    final gift = giftSnap.data()!;
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

    final senderDoc = await _db.collection('users').doc(sender).get();
    final balance = (senderDoc.data()?['coins'] as num?)?.toInt() ?? 0;
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

    final batch = _db.batch();
    batch.update(_db.collection('users').doc(sender), <String, dynamic>{
      'coins': FieldValue.increment(-giftValue),
    });

    final coupleUpdates = <String, dynamic>{
      'total_score': FieldValue.increment(giftValue),
      'week_score': FieldValue.increment(giftValue),
      'month_score': FieldValue.increment(giftValue),
      'updated_at': _now(),
    };

    if (extraHours > 0) {
      final curExp = _parseDate(couple['expires_at'] ?? couple['countdown_end']) ?? DateTime.now();
      final baseDate = curExp.isAfter(DateTime.now()) ? curExp : DateTime.now();
      final newExp = baseDate.add(Duration(hours: extraHours)).toIso8601String();
      coupleUpdates['countdown_end'] = newExp;
      coupleUpdates['expires_at'] = newExp;
    }

    batch.update(_db.collection('cp_couples').doc(couple['id']), coupleUpdates);
    await batch.commit();

    await _db.collection('cp_gift_logs').add(<String, dynamic>{
      'couple_id': couple['id'],
      'sender_uid': sender,
      'receiver_uid': receiverId,
      'gift_id': giftId,
      'gift_name': giftName,
      'gift_value': giftValue,
      'created_at': _now(),
    });

    await FirebaseService().sendNotification(
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
      'new_score': ((couple['total_score'] as num?)?.toInt() ?? 0) + giftValue,
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
            // If the gift is not a CP gift, just send a notification
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
        final gSnap = await _db.collection('cp_gifts').doc(giftId).get();
        Map<String, dynamic>? gData;
        if (gSnap.exists) {
          gData = gSnap.data();
        } else {
          final regSnap = await _db.collection('gifts').doc(giftId).get();
          if (regSnap.exists) gData = regSnap.data();
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
    await FirebaseService().sendNotification(
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

    final snap = await _db
        .collection('cp_gift_logs')
        .where('couple_id', isEqualTo: couple['id'])
        .get();

    final logs = snap.docs.map((e) => e.data()).toList();
    logs.sort((a, b) =>
        (b['created_at']?.toString() ?? '').compareTo(a['created_at']?.toString() ?? ''));

    final result = <Map<String, dynamic>>[];
    for (final log in logs.take(limit)) {
      final sender = await FirebaseService().getUser(log['sender_uid'] as String? ?? '');
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
  }

  static Future<List<Map<String, dynamic>>> getCpAchievements({String? coupleId}) async {
    final uid = _uid;
    if (uid == null) return <Map<String, dynamic>>[];

    Map<String, dynamic>? couple;
    if (coupleId != null && coupleId.isNotEmpty) {
      final doc = await _db.collection('cp_couples').doc(coupleId).get();
      if (doc.exists) couple = doc.data()!;
    } else {
      couple = await _findActiveCoupleFor(uid);
    }
    if (couple == null) return <Map<String, dynamic>>[];

    final logs = await _db
        .collection('cp_gift_logs')
        .where('couple_id', isEqualTo: couple['id'])
        .get();

    final giftCount = logs.docs.length;
    var totalGiftValue = 0;
    for (final log in logs.docs) {
      totalGiftValue += (log.data()['gift_value'] as num?)?.toInt() ?? 0;
    }

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
      final snap = await _db
          .collection('cp_gift_logs')
          .where('sender_uid', isEqualTo: uid)
          .get();
      var total = 0;
      for (final doc in snap.docs) {
        total += (doc.data()['gift_value'] as num?)?.toInt() ?? 0;
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
      final snap = await _db
          .collection('cp_rank_rewards')
          .where('period', isEqualTo: period)
          .get();
      final list = snap.docs.map((e) {
        final d = e.data();
        d['id'] = e.id;
        return d;
      }).where((d) => d['isActive'] != false).toList();
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
  /// يُحدَّث فورياً عند أي تعديل من لوحة التحكم (سيّدة على isActive والفرز).
  static Stream<List<Map<String, dynamic>>> rewardsStream({
    String period = 'weekly',
  }) {
    return _db.collection('cp_rank_rewards').snapshots().map((snap) {
      final list = snap.docs.map((e) {
        final d = e.data();
        d['id'] = e.id;
        return d;
      }).where((d) => d['period'] == period && d['isActive'] != false).toList();
      list.sort((a, b) {
        final rankCmp = ((a['rank_position'] as num?)?.toInt() ?? 0)
            .compareTo((b['rank_position'] as num?)?.toInt() ?? 0);
        if (rankCmp != 0) return rankCmp;
        return ((a['slot_index'] as num?)?.toInt() ?? 0)
            .compareTo((b['slot_index'] as num?)?.toInt() ?? 0);
      });
      return list;
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
    final results = await Future.wait([
      _db.collection('cp_couples').where('user1_uid', isEqualTo: uid).limit(10).get(),
      _db.collection('cp_couples').where('user2_uid', isEqualTo: uid).limit(10).get(),
    ]);
    final now = DateTime.now();
    for (final snap in results) {
      for (final doc in snap.docs) {
        final d = doc.data();
        if (d['ended_at'] == null) {
          final exp = _parseDate(d['expires_at'] ?? d['countdown_end']);
          if (exp != null && exp.isBefore(now)) {
            doc.reference.update(<String, dynamic>{
              'ended_at': _now(),
              'updated_at': _now(),
            }).catchError((_) {});
            continue;
          }
          d['id'] = doc.id;
          return d;
        }
      }
    }
    return null;
  }

  /// Most recent couple (active or ended) for [uid].
  static Future<Map<String, dynamic>?> _findLatestCoupleFor(String uid) async {
    final results = await Future.wait([
      _db.collection('cp_couples').where('user1_uid', isEqualTo: uid).limit(50).get(),
      _db.collection('cp_couples').where('user2_uid', isEqualTo: uid).limit(50).get(),
    ]);
    Map<String, dynamic>? latest;
    String? latestDocId;
    String? latestKey;
    for (final snap in results) {
      for (final doc in snap.docs) {
        final d = doc.data();
        final key = d['ended_at']?.toString() ?? d['created_at']?.toString() ?? '';
        if (latest == null || key.compareTo(latestKey ?? '') > 0) {
          latest = d;
          latestDocId = doc.id;
          latestKey = key;
        }
      }
    }
    if (latest != null) latest['id'] = latestDocId;
    return latest;
  }

  static Future<void> _endActiveCouplesFor(String uid) async {
    final couple = await _findActiveCoupleFor(uid);
    if (couple == null) return;
    await _db.collection('cp_couples').doc(couple['id']).update(<String, dynamic>{
      'ended_at': _now(),
      'updated_at': _now(),
    });
  }

  static Future<Map<String, dynamic>?> _getTheme(String themeId) async {
    final doc = await _db.collection('cp_themes').doc(themeId).get();
    if (!doc.exists) return null;
    final d = doc.data()!;
    d['id'] = doc.id;
    return d;
  }

  static Future<List<Map<String, dynamic>>> _findRequestsFor(String uid,
      {String? status}) async {
    final snap = await _db
        .collection('cp_requests')
        .where('receiver_uid', isEqualTo: uid)
        .get();
    final list = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      if (status != null && d['status'] != status) continue;
      final sender = await FirebaseService().getUser(d['sender_uid'] as String? ?? '');
      list.add(<String, dynamic>{
        'id': doc.id,
        'sender_uid': d['sender_uid'],
        'receiver_uid': d['receiver_uid'],
        'status': d['status'],
        'message': d['message'],
        'sender_name': sender?.name ?? '',
        'sender_avatar': sender?.photoUrl ?? '',
      });
    }
    return list;
  }

  static Future<List<Map<String, dynamic>>> _findHistoryFor(String uid) async {
    final results = await Future.wait([
      _db.collection('cp_couples').where('user1_uid', isEqualTo: uid).get(),
      _db.collection('cp_couples').where('user2_uid', isEqualTo: uid).get(),
    ]);
    final ended = <Map<String, dynamic>>[];
    for (final snap in results) {
      for (final doc in snap.docs) {
        final d = doc.data();
        if (d['ended_at'] == null) continue;
        final isUser1 = d['user1_uid'] == uid;
        final partnerUid = isUser1 ? d['user2_uid'] as String : d['user1_uid'] as String;
        final partner = await FirebaseService().getUser(partnerUid);
        ended.add(<String, dynamic>{
          'partner_name': partner?.name ?? '',
          'partner_avatar': partner?.photoUrl ?? '',
          'total_score': (d['total_score'] as num?)?.toInt() ?? 0,
          'started_at': d['started_at'],
          'ended_at': d['ended_at'],
        });
      }
    }
    ended.sort((a, b) =>
        (b['ended_at']?.toString() ?? '').compareTo(a['ended_at']?.toString() ?? ''));
    return ended;
  }
}
