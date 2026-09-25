import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../services/level_service.dart';

/// Weekly Sign-In system backed by Firestore.
///
/// Collections mirror the legacy Postgres tables 1:1:
///   signin_rewards   -> 7 configurable daily rewards (admin editable)
///   signin_records   -> per-day claim records  (doc id: uid_date)
///   signin_weekly    -> per-week totals        (doc id: uid_weekStart)
class SigninService {
  SigninService._();
  static final SigninService _instance = SigninService._();
  factory SigninService() => _instance;

  static FirebaseFirestore get _db => FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'default',
      );

  static const int _daysPerWeek = 7;

  // ═══════════════════════════════════════════════════════
  // Date helpers (no intl dependency)
  // ═══════════════════════════════════════════════════════

  static String _dateStr(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static DateTime _todayUtc() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }

  /// Week starts on Monday (matches Postgres `date_trunc('week', ...)`).
  static DateTime _weekStart(DateTime day) {
    final monday = day.subtract(Duration(days: day.weekday - 1));
    return DateTime.utc(monday.year, monday.month, monday.day);
  }

  // ═══════════════════════════════════════════════════════
  // Rewards catalog
  // ═══════════════════════════════════════════════════════

  /// Defaults mirror `20260730_weekly_signin.sql` seed. Used only when the
  /// `signin_rewards` collection is empty (first run / fresh backend).
  static const List<Map<String, dynamic>> _defaultRewards = [
    {
      'day_number': 1, 'label_ar': 'اليوم 1', 'label_en': 'Day 1',
      'icon_url': 'assets/mipmap-xxhdpi/ic_signing_ok.png', 'svga_url': '',
      'value': 50, 'value_type': 'coins', 'gift_id': '', 'is_double': false, 'is_active': true,
    },
    {
      'day_number': 2, 'label_ar': 'اليوم 2', 'label_en': 'Day 2',
      'icon_url': 'assets/mipmap-xxhdpi/ic_signing_ok.png', 'svga_url': '',
      'value': 100, 'value_type': 'coins', 'gift_id': '', 'is_double': false, 'is_active': true,
    },
    {
      'day_number': 3, 'label_ar': 'اليوم 3', 'label_en': 'Day 3',
      'icon_url': 'assets/mipmap-xxhdpi/ic_signing_ok.png', 'svga_url': '',
      'value': 150, 'value_type': 'coins', 'gift_id': '', 'is_double': false, 'is_active': true,
    },
    {
      'day_number': 4, 'label_ar': 'اليوم 4', 'label_en': 'Day 4',
      'icon_url': 'assets/mipmap-xxhdpi/ic_signing_ok.png', 'svga_url': '',
      'value': 200, 'value_type': 'coins', 'gift_id': '', 'is_double': false, 'is_active': true,
    },
    {
      'day_number': 5, 'label_ar': 'اليوم 5', 'label_en': 'Day 5',
      'icon_url': 'assets/mipmap-xxhdpi/ic_signing_ok.png', 'svga_url': '',
      'value': 300, 'value_type': 'coins', 'gift_id': '', 'is_double': false, 'is_active': true,
    },
    {
      'day_number': 6, 'label_ar': 'اليوم 6', 'label_en': 'Day 6',
      'icon_url': 'assets/mipmap-xxhdpi/ic_signing_ok.png', 'svga_url': '',
      'value': 400, 'value_type': 'coins', 'gift_id': '', 'is_double': false, 'is_active': true,
    },
    {
      'day_number': 7, 'label_ar': 'اليوم 7', 'label_en': 'Day 7',
      'icon_url': 'assets/mipmap-xxhdpi/ic_checkin_gift.png', 'svga_url': '',
      'value': 500, 'value_type': 'coins', 'gift_id': '', 'is_double': true, 'is_active': true,
    },
  ];

  static Future<void> _seedRewardsIfEmpty() async {
    final snap = await _db.collection('signin_rewards').limit(1).get();
    if (snap.docs.isNotEmpty) return;
    final batch = _db.batch();
    for (final r in _defaultRewards) {
      batch.set(
        _db.collection('signin_rewards').doc('day_${r['day_number']}'),
        r,
      );
    }
    await batch.commit();
  }

  /// Active rewards ordered by day, with `id` attached.
  static Future<List<Map<String, dynamic>>> getRewards() async {
    try {
      await _seedRewardsIfEmpty();
      final snap = await _db
          .collection('signin_rewards')
          .where('is_active', isEqualTo: true)
          .orderBy('day_number')
          .get();
      final rows = snap.docs
          .map((d) {
            final m = Map<String, dynamic>.from(d.data());
            m['id'] = d.id;
            return m;
          })
          .toList();
      if (rows.isEmpty) return _defaultRewards;
      return rows;
    } catch (e) {
      debugPrint('SigninService.getRewards error: $e');
      return _defaultRewards;
    }
  }

  // ═══════════════════════════════════════════════════════
  // Read current week state
  // ═══════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> getUserSigninData(String uid) async {
    try {
      final today = _todayUtc();
      final weekStart = _weekStart(today);
      final weekStartStr = _dateStr(weekStart);

      final rewards = await getRewards();

      final recordsSnap = await _db
          .collection('signin_records')
          .where('uid', isEqualTo: uid)
          .where('week_start', isEqualTo: weekStartStr)
          .orderBy('day_number')
          .get();
      final records = recordsSnap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        return m;
      }).toList();

      final weeklyDoc = await _db
          .collection('signin_weekly')
          .doc('${uid}_$weekStartStr')
          .get();
      final weekly = weeklyDoc.exists
          ? Map<String, dynamic>.from(weeklyDoc.data() ?? {})
          : <String, dynamic>{};

      return <String, dynamic>{
        'week_start': weekStartStr,
        'rewards': rewards,
        'records': records,
        'weekly': weekly,
      };
    } catch (e) {
      debugPrint('SigninService.getUserSigninData error: $e');
      return <String, dynamic>{
        'week_start': '',
        'rewards': <Map<String, dynamic>>[],
        'records': <Map<String, dynamic>>[],
        'weekly': <String, dynamic>{},
      };
    }
  }

  /// التحقق مما إذا كان المستخدم قد استلم مكافأة اليوم بالفعل
  static Future<bool> hasClaimedToday(String uid) async {
    try {
      final today = _todayUtc();
      final todayStr = _dateStr(today);
      final doc = await _db.collection('signin_records').doc('${uid}_$todayStr').get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // Claim today's reward (transactional)
  // ═══════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> doSignin(String uid) async {
    final today = _todayUtc();
    final weekStart = _weekStart(today);
    final todayStr = _dateStr(today);
    final weekStartStr = _dateStr(weekStart);

    try {
      final rewards = await getRewards();
      if (rewards.isEmpty) {
        return {'success': false, 'error': 'reward_not_found'};
      }

      final recordRef = _db.collection('signin_records').doc('${uid}_$todayStr');
      final weeklyRef = _db.collection('signin_weekly').doc('${uid}_$weekStartStr');
      final userRef = _db.collection('users').doc(uid);

      final claimedDayNumber = <int?>[];
      final claimedReward = <Map<String, dynamic>?>[];

      await _db.runTransaction((txn) async {
        final existing = await txn.get(recordRef);
        if (existing.exists) {
          claimedDayNumber.add(-1);
          return;
        }

        final weekSnap = await txn.get(weeklyRef);
        final weekData = weekSnap.exists ? weekSnap.data() ?? {} : <String, dynamic>{};
        final claimedCount = (weekData['total_days'] ?? 0) as int;
        final dayNumber = (claimedCount + 1).clamp(1, _daysPerWeek);

        Map<String, dynamic>? reward;
        for (final r in rewards) {
          if ((r['day_number'] as num).toInt() == dayNumber) {
            reward = r;
            break;
          }
        }
        if (reward == null) return;

        final valueType = reward['value_type']?.toString() ?? 'coins';
        final value = (reward['value'] ?? 0) as int;
        final isDouble = reward['is_double'] == true;
        final giftId = reward['gift_id']?.toString() ?? '';

        txn.set(recordRef, <String, dynamic>{
          'uid': uid,
          'signin_date': todayStr,
          'day_number': dayNumber,
          'week_start': weekStartStr,
          'reward_id': reward['id'] ?? '',
          'reward_value': value,
          'reward_type': valueType,
          'gift_id': giftId,
          'is_double': isDouble,
          'is_makeup': false,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });

        final totalCoins = (weekData['total_coins'] ?? 0) as int;
        final totalDiamonds = (weekData['total_diamonds'] ?? 0) as int;
        final totalXp = (weekData['total_xp'] ?? 0) as int;
        final newTotalDays = ((weekData['total_days'] ?? 0) as int) + 1;

        final newWeekly = <String, dynamic>{
          'uid': uid,
          'week_start': weekStartStr,
          'consecutive_days': 1,
          'total_days': newTotalDays,
          'total_coins': totalCoins + (valueType == 'coins' ? value : 0),
          'total_diamonds': totalDiamonds + (valueType == 'diamonds' ? value : 0),
          'total_xp': totalXp + (valueType == 'xp' ? value : 0),
          'all_claimed': newTotalDays >= _daysPerWeek,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
        txn.set(weeklyRef, newWeekly, SetOptions(merge: true));

        // Award balance / inventory in the same transaction.
        final userSnap = await txn.get(userRef);
        if (userSnap.exists) {
          final userData = userSnap.data() ?? {};
          final updates = <String, dynamic>{};
          if (valueType == 'coins') {
            updates['coins'] = ((userData['coins'] ?? 0) as int) + value;
          } else if (valueType == 'diamonds') {
            updates['diamonds'] = ((userData['diamonds'] ?? 0) as int) + value;
          } else if (valueType == 'gift' && giftId.isNotEmpty) {
            final owned = List<String>.from(userData['owned_items'] ?? []);
            if (!owned.contains(giftId)) {
              owned.add(giftId);
              updates['owned_items'] = owned;
            }
          }
          if (updates.isNotEmpty) txn.update(userRef, updates);
        }

        claimedDayNumber.add(dayNumber);
        claimedReward.add(reward);
      });

      final dayNumber = claimedDayNumber.isNotEmpty ? claimedDayNumber.first : null;
      if (dayNumber == null) {
        return {'success': false, 'error': 'reward_not_found'};
      }
      if (dayNumber == -1) {
        return {'success': false, 'error': 'already_signed_in'};
      }

      final reward = claimedReward.first ?? <String, dynamic>{};
      final valueType = reward['value_type']?.toString() ?? 'coins';
      final value = (reward['value'] ?? 0) as int;

      // XP is granted outside the transaction (LevelService owns level fields).
      if (valueType == 'xp' && value > 0) {
        try {
          final levelService = LevelService();
          await levelService.loadAllLevels();
          await levelService.addExp(uid: uid, type: 'recharge', amount: value);
        } catch (e) {
          debugPrint('SigninService xp award error: $e');
        }
      }

      // Refresh the real streak (days claimed consecutively ending today).
      final streak = await computeStreak(uid);
      await _db.collection('signin_weekly').doc('${uid}_$weekStartStr').update({
        'consecutive_days': streak,
      });

      final weekly = await _db.collection('signin_weekly').doc('${uid}_$weekStartStr').get();
      final weeklyData = weekly.exists
          ? Map<String, dynamic>.from(weekly.data() ?? {})
          : <String, dynamic>{};
      weeklyData['consecutive_days'] = streak;
      return <String, dynamic>{
        'success': true,
        'day_number': dayNumber,
        'reward_value': value,
        'reward_type': valueType,
        'gift_id': reward['gift_id'] ?? '',
        'is_double': reward['is_double'] == true,
        'weekly': weeklyData,
      };
    } catch (e) {
      debugPrint('SigninService.doSignin error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Computes the current streak by walking backwards from [today].
  static Future<int> computeStreak(String uid) async {
    try {
      var streak = 0;
      var day = _todayUtc();
      final checked = <String>{};
      for (var i = 0; i < 30; i++) {
        final dayStr = _dateStr(day);
        if (checked.contains(dayStr)) break;
        checked.add(dayStr);
        final doc = await _db.collection('signin_records').doc('${uid}_$dayStr').get();
        if (!doc.exists) {
          if (i == 0) {
            day = day.subtract(const Duration(days: 1));
            continue;
          }
          break;
        }
        streak++;
        day = day.subtract(const Duration(days: 1));
      }
      return streak;
    } catch (e) {
      debugPrint('SigninService.computeStreak error: $e');
      return 0;
    }
  }

  /// Serializes a reward map (kept for debug/inspection).
  static String encodeReward(Map<String, dynamic> reward) => jsonEncode(reward);
}
