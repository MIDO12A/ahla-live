import 'dart:async';
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
  static bool _prefsLoaded = false;
  static const String _rewardsPrefsKey = 'signin_rewards_cache_v1';

  /// ✅ تسخين المكافآت من اللوحة تحكم مسبقاً —
  ///    يُستدعى عند إقلاع التطبيق حتى يفتح حوار الدخول لحظياً
  static Future<void> warmup() async {
    await getRewards();
  }

  /// استعادة المكافآت المحفوظة على القرص (آخر نسخة من اللوحة)
  static Future<void> _loadPersistedRewards() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_rewardsPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is List && decoded.isNotEmpty) {
        final rewards = decoded
            .whereType<Map>()
            .map((e) => _normalizeReward(Map<String, dynamic>.from(e)))
            .where((r) => r['is_active'] != false)
            .toList();
        if (rewards.isNotEmpty) {
          _cachedRewards = rewards;
          // ✅ اعتبرها "قديمة" إجباراً لتحديثها من الشبكة بالخلفية
          _rewardsFetchedAt =
              DateTime.now().subtract(const Duration(minutes: 5));
        }
      }
    } catch (_) {}
  }

  static Future<void> _persistRewards(List<Map<String, dynamic>> rewards) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_rewardsPrefsKey, jsonEncode(rewards));
    } catch (_) {}
  }

  /// يجلب مكافآت تسجيل الدخول من لوحة التحكم:
  ///   1) جدول signin_rewards
  ///   2) مفتاح signin_rewards داخل app_config (نفس قسم المهام اليومية)
  /// عند الفشل أو عدم وجود بيانات يعود لآخر نسخة محفوظة ثم الافتراضية.
  static Future<List<Map<String, dynamic>>> getRewards() async {
    final cached = _cachedRewards;
    final fetchedAt = _rewardsFetchedAt;
    if (cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < const Duration(seconds: 30)) {
      return cached;
    }

    // ✅ حمّل النسخة المحفوظة على القرص أولاً — إرجاع فوري
    //    مع تحديث من الشبكة بالخلفية (stale-while-revalidate)
    await _loadPersistedRewards();
    final persisted = _cachedRewards;

    final networkFuture = _fetchRewardsFromPanel();
    if (persisted != null) {
      // لدينا بيانات محفوظة — لا ننتظر الشبكة، حدّث للخلفية
      unawaited(networkFuture.then((rewards) {
        if (rewards != null) {
          _cachedRewards = rewards;
          _rewardsFetchedAt = DateTime.now();
          unawaited(_persistRewards(rewards));
        }
      }));
      return persisted;
    }

    final fetched = await networkFuture;
    if (fetched != null && fetched.isNotEmpty) {
      _cachedRewards = fetched;
      _rewardsFetchedAt = DateTime.now();
      unawaited(_persistRewards(fetched));
      return fetched;
    }
    return _defaultRewards;
  }

  /// جلب المكافآت من مصادر اللوحة — null عند الفشل الكامل
  static Future<List<Map<String, dynamic>>?> _fetchRewardsFromPanel() async {
    // 1) جدول signin_rewards
    try {
      final res = await SafeHttp.get(
            Uri.parse(
                '${SupabaseConfig.projectUrl}/rest/v1/signin_rewards?select=*&order=day_number.asc'),
            headers: {
              'apikey': SupabaseConfig.anonKey,
              'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body) as List;
        final rewards = list
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((r) => r['is_active'] != false)
            .map(_normalizeReward)
            .toList();
        if (rewards.isNotEmpty) return rewards;
      }
    } catch (e) {
      debugPrint('SigninService.getRewards table error: $e');
    }

    // 2) مفتاح signin_rewards داخل app_config — نفس إعدادات
    //    لوحة التحكم (بجانب tasks_config للمهام اليومية)
    try {
      final res = await SafeHttp.get(
            Uri.parse(
                '${SupabaseConfig.projectUrl}/rest/v1/app_config?key=eq.signin_rewards&select=value'),
            headers: {
              'apikey': SupabaseConfig.anonKey,
              'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body) as List;
        if (list.isNotEmpty) {
          var value = list.first['value'];
          if (value is String) {
            try {
              value = jsonDecode(value);
            } catch (_) {}
          }
          if (value is List && value.isNotEmpty) {
            final rewards = value
                .whereType<Map>()
                .map((e) => _normalizeReward(Map<String, dynamic>.from(e)))
                .where((r) => r['is_active'] != false && (r['day_number'] as num).toInt() > 0)
                .toList()
              ..sort((a, b) => (a['day_number'] as num)
                  .toInt()
                  .compareTo((b['day_number'] as num).toInt()));
            if (rewards.isNotEmpty) return rewards;
          }
        }
      }
    } catch (e) {
      debugPrint('SigninService.getRewards app_config error: $e');
    }
    return null;
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

  /// حذف كل بيانات تسجيل الدخول المحلية الخاصة بمستخدم عند حذف حسابه.
  /// المفاتيح مبنية بصيغة `signin_records_<uid>_<week>` و`signin_weekly_<uid>_<week>`.
  static Future<void> clearLocalForUser(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where(
            (k) => k.startsWith('signin_records_${uid}_') ||
                k.startsWith('signin_weekly_${uid}_'),
          );
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (_) {}
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

  /// هل عُرضت نافذة تسجيل الوصول اليوم؟ — تمنع إعادة فتحها
  /// كل إقلاع حتى لو لم يستلم المستخدم المكافأة بعد.
  static Future<bool> hasSigninShownToday(String uid) async {
    try {
      final todayStr = _dateStr(_todayUtc());
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('signin_shown_${uid}_$todayStr') == '1';
    } catch (_) {
      return false;
    }
  }

  /// تسجيل أن النافذة عُرضت اليوم (مرة واحدة يومياً كحد أقصى)
  static Future<void> markSigninShown(String uid) async {
    try {
      final todayStr = _dateStr(_todayUtc());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('signin_shown_${uid}_$todayStr', '1');
    } catch (_) {}
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
      final giftId = reward['gift_id']?.toString() ?? '';
      final giftData = reward['gift_data'] is Map ? Map<String, dynamic>.from(reward['gift_data'] as Map) : <String, dynamic>{};

      final newRecord = <String, dynamic>{
        'uid': uid,
        'signin_date': todayStr,
        'claimed_date': todayStr,
        'day_number': dayNumber,
        'week_start': weekStartStr,
        'reward_id': 'day_$dayNumber',
        'reward_value': value,
        'reward_type': valueType,
        'gift_id': giftId,
        'gift_data': giftData,
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

      // Award balance to Supabase based on value_type
      try {
        final userData = await SupabaseDataService().getUser(uid);
        switch (valueType) {
          case 'coins':
            final currentCoins = userData?.coins ?? 0;
            final newCoins = currentCoins + value;
            await SupabaseDataService().updateUser(uid, {'coins': newCoins});
            break;
          case 'diamonds':
            final currentDiamonds = userData?.diamonds ?? 0;
            final newDiamonds = currentDiamonds + value;
            await SupabaseDataService().updateUser(uid, {'diamonds': newDiamonds});
            break;
          case 'xp':
            // XP يضاف للمستوى عبر LevelService
            break;
          case 'gift':
            // إضافة عنصر للمستخدم (gift_id هو item_id)
            if (giftId.isNotEmpty) {
              final owned = List<String>.from(userData?.ownedItems ?? []);
              if (!owned.contains(giftId)) {
                owned.add(giftId);
                await SupabaseDataService().updateUser(uid, {'owned_items': owned});
              }
            }
            break;
          case 'custom':
            // مكافأة مخصصة - يتم التعامل معها حسب gift_data
            // مثال: gift_data = {'type': 'vip_tier', 'tier': 2, 'days': 30}
            final customType = giftData['type']?.toString() ?? '';
            if (customType == 'vip_tier') {
              final tier = (giftData['tier'] as num?)?.toInt() ?? 1;
              final days = (giftData['days'] as num?)?.toInt() ?? 0;
              // TODO: استدعاء خدمة VIP لترقية المستخدم
              debugPrint('Signin: Custom VIP tier reward - tier: $tier, days: $days');
            }
            break;
        }
      } catch (e) {
        debugPrint('Error updating user balance in Supabase: $e');
      }

      // Add XP if applicable (للـ value_type == 'xp' أو أي مكافأة لها قيمة)
      if (value > 0 && (valueType == 'xp' || valueType == 'coins' || valueType == 'diamonds')) {
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
        'gift_id': giftId,
        'gift_data': giftData,
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
