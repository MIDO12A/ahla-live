import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../services/safe_http.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/supabase_config.dart';
import '../../services/supabase_data_service.dart';
import '../../services/level_service.dart';

/// Weekly Sign-In system backed by Local Persistence + Supabase Coin Crediting.
class SigninService {
  SigninService._();
  static final SigninService _instance = SigninService._();
  factory SigninService() => _instance;

  static const int _daysPerWeek = 7;

  // ═══════════════════════════════════════════════════════
  // Date helpers
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

  /// Week starts on Monday
  static DateTime _weekStart(DateTime day) {
    final monday = day.subtract(Duration(days: day.weekday - 1));
    return DateTime.utc(monday.year, monday.month, monday.day);
  }

  // ═══════════════════════════════════════════════════════
  // Rewards catalog
  // ═══════════════════════════════════════════════════════

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

  static List<Map<String, dynamic>>? _cachedRewards;
  static DateTime? _rewardsFetchedAt;

  /// يجلب مكافآت تسجيل الدخول من لوحة التحكم (جدول signin_rewards).
  /// عند فشل الشبكة أو عدم وجود بيانات يعود للقيم الافتراضية.
  static Future<List<Map<String, dynamic>>> getRewards() async {
    final cached = _cachedRewards;
    final fetchedAt = _rewardsFetchedAt;
    if (cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < const Duration(seconds: 30)) {
      return cached;
    }
    try {
      final res = await SafeHttp.get(
            Uri.parse(
                '${SupabaseConfig.projectUrl}/rest/v1/signin_rewards?select=*&order=day_number.asc'),
            headers: {
              'apikey': SupabaseConfig.anonKey,
              'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
            },
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body) as List;
        final rewards = list
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((r) => r['is_active'] != false)
            .map(_normalizeReward)
            .toList();
        if (rewards.isNotEmpty) {
          _cachedRewards = rewards;
          _rewardsFetchedAt = DateTime.now();
          return rewards;
        }
      }
    } catch (e) {
      debugPrint('SigninService.getRewards fetch error: $e');
    }
    return _defaultRewards;
  }

  static Map<String, dynamic> _normalizeReward(Map<String, dynamic> r) {
    final dayNum = (r['day_number'] as num?)?.toInt() ??
        (r['dayNumber'] as num?)?.toInt() ??
        0;
    return {
      'day_number': dayNum,
      'label_ar': r['label_ar']?.toString() ?? r['labelAr']?.toString() ?? 'اليوم $dayNum',
      'label_en': r['label_en']?.toString() ?? r['labelEn']?.toString() ?? 'Day $dayNum',
      'icon_url': r['icon_url']?.toString() ?? r['iconUrl']?.toString() ?? '',
      'svga_url': r['svga_url']?.toString() ?? r['svgaUrl']?.toString() ?? '',
      'value': (r['value'] as num?)?.toInt() ?? 0,
      'value_type': r['value_type']?.toString() ?? r['valueType']?.toString() ?? 'coins',
      'gift_id': r['gift_id']?.toString() ?? r['giftId']?.toString() ?? '',
      'is_double': r['is_double'] == true || r['isDouble'] == true,
      'is_active': r['is_active'] != false,
    };
  }

  // ═══════════════════════════════════════════════════════
  // Read current week state
  // ═══════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> getUserSigninData(String uid) async {
    try {
      final today = _todayUtc();
      final weekStart = _weekStart(today);
      final weekStartStr = _dateStr(weekStart);

      final prefs = await SharedPreferences.getInstance();
      final recordsJson = prefs.getString('signin_records_${uid}_$weekStartStr');
      List<Map<String, dynamic>> records = [];
      if (recordsJson != null && recordsJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(recordsJson) as List;
          records = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } catch (_) {}
      }

      final weeklyJson = prefs.getString('signin_weekly_${uid}_$weekStartStr');
      Map<String, dynamic> weekly = {};
      if (weeklyJson != null && weeklyJson.isNotEmpty) {
        try {
          weekly = Map<String, dynamic>.from(jsonDecode(weeklyJson) as Map);
        } catch (_) {}
      }

      return <String, dynamic>{
        'week_start': weekStartStr,
        'rewards': await getRewards(),
        'records': records,
        'weekly': weekly,
      };
    } catch (e) {
      debugPrint('SigninService.getUserSigninData error: $e');
      return <String, dynamic>{
        'week_start': '',
        'rewards': _defaultRewards,
        'records': <Map<String, dynamic>>[],
        'weekly': <String, dynamic>{},
      };
    }
  }

  /// Check if user has claimed today
  static Future<bool> hasClaimedToday(String uid) async {
    try {
      final today = _todayUtc();
      final weekStart = _weekStart(today);
      final weekStartStr = _dateStr(weekStart);
      final todayStr = _dateStr(today);

      final prefs = await SharedPreferences.getInstance();
      final recordsJson = prefs.getString('signin_records_${uid}_$weekStartStr');
      if (recordsJson != null && recordsJson.isNotEmpty) {
        final decoded = jsonDecode(recordsJson) as List;
        return decoded.any((e) => (e['claimed_date'] ?? e['signin_date']) == todayStr);
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // Claim today's reward
  // ═══════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> doSignin(String uid) async {
    final today = _todayUtc();
    final weekStart = _weekStart(today);
    final todayStr = _dateStr(today);
    final weekStartStr = _dateStr(weekStart);

    try {
      final prefs = await SharedPreferences.getInstance();
      final recordsKey = 'signin_records_${uid}_$weekStartStr';
      final weeklyKey = 'signin_weekly_${uid}_$weekStartStr';

      final recordsJson = prefs.getString(recordsKey);
      List<Map<String, dynamic>> records = [];
      if (recordsJson != null && recordsJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(recordsJson) as List;
          records = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } catch (_) {}
      }

      // Check if already claimed today
      final alreadyClaimed = records.any((r) => (r['claimed_date'] ?? r['signin_date']) == todayStr);
      if (alreadyClaimed) {
        return {'success': false, 'error': 'already_signed_in'};
      }

      final dayNumber = (records.length + 1).clamp(1, _daysPerWeek);
      final rewards = await getRewards();
      Map<String, dynamic>? reward;
      for (final r in rewards) {
        if ((r['day_number'] as num).toInt() == dayNumber) {
          reward = r;
          break;
        }
      }
      if (reward == null) {
        return {'success': false, 'error': 'reward_not_found'};
      }

      final valueType = reward['value_type']?.toString() ?? 'coins';
      final value = (reward['value'] ?? 0) as int;
      final isDouble = reward['is_double'] == true;

      final newRecord = <String, dynamic>{
        'uid': uid,
        'signin_date': todayStr,
        'claimed_date': todayStr,
        'day_number': dayNumber,
        'week_start': weekStartStr,
        'reward_id': 'day_$dayNumber',
        'reward_value': value,
        'reward_type': valueType,
        'gift_id': reward['gift_id'] ?? '',
        'is_double': isDouble,
        'is_makeup': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      records.add(newRecord);
      await prefs.setString(recordsKey, jsonEncode(records));

      final newWeekly = <String, dynamic>{
        'uid': uid,
        'week_start': weekStartStr,
        'consecutive_days': records.length,
        'total_days': records.length,
        'all_claimed': records.length >= _daysPerWeek,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      await prefs.setString(weeklyKey, jsonEncode(newWeekly));

      // Award balance to Supabase
      try {
        final userData = await SupabaseDataService().getUser(uid);
        if (valueType == 'coins') {
          final currentCoins = userData?.coins ?? 0;
          final newCoins = currentCoins + value;
          await SupabaseDataService().updateUser(uid, {'coins': newCoins});
        } else if (valueType == 'diamonds') {
          final currentDiamonds = userData?.diamonds ?? 0;
          final newDiamonds = currentDiamonds + value;
          await SupabaseDataService().updateUser(uid, {'diamonds': newDiamonds});
        }
      } catch (e) {
        debugPrint('Error updating user balance in Supabase: $e');
      }

      // Add XP if applicable
      if (value > 0) {
        try {
          final levelService = LevelService();
          await levelService.loadAllLevels();
          await levelService.addExp(uid: uid, type: 'recharge', amount: value);
        } catch (_) {}
      }

      return <String, dynamic>{
        'success': true,
        'day_number': dayNumber,
        'reward_value': value,
        'reward_type': valueType,
        'gift_id': reward['gift_id'] ?? '',
        'is_double': isDouble,
        'weekly': newWeekly,
      };
    } catch (e) {
      debugPrint('SigninService.doSignin error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  static String encodeReward(Map<String, dynamic> reward) => jsonEncode(reward);
}
