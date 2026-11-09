import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/supabase_config.dart';

/// طبقة خدمة كود الدعوة (Invitation Code) — تطابق صفحة h5.halopartyvip.com/invite-register
/// تعتمد على جدول user_invites + RPCs في migration 20261115_user_invite_codes.sql
class InviteService {
  static final InviteService _instance = InviteService._internal();
  factory InviteService() => _instance;
  InviteService._internal();

  static const String _baseUrl = SupabaseConfig.projectUrl;
  static const String _anonKey = SupabaseConfig.anonKey;

  static Map<String, String> get _headers => {
        'apikey': _anonKey,
        'Authorization': 'Bearer $_anonKey',
        'Content-Type': 'application/json',
      };

  /// ملخص المدعوين: { totalInviteQuantity, totalCommission }
  Future<Map<String, dynamic>> getInviteSummary(String uid) async {
    try {
      final resp = await http
          .get(
            Uri.parse('$_baseUrl/rest/v1/rpc/get_invite_summary')
                .replace(queryParameters: {'p_uid': uid}),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return {'totalInviteQuantity': 0, 'totalCommission': 0};
  }

  /// ربط كود الداعي: invitee يبدّل مرة واحدة فقط
  Future<Map<String, dynamic>> bindInviter(String inviteeUid, String inviterCustomId) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/rest/v1/rpc/bind_inviter'),
            headers: _headers,
            body: jsonEncode({
              'p_invitee_uid': inviteeUid,
              'p_inviter_custom_id': inviterCustomId.trim(),
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
      return {'ok': false, 'message': 'network_error'};
    } catch (_) {
      return {'ok': false, 'message': 'network_error'};
    }
  }

  /// من دعاني؟ (user_invites حيث أنا المدعو)
  Future<Map<String, dynamic>?> getInviterOf(String uid) async {
    try {
      final resp = await http
          .get(
            Uri.parse('$_baseUrl/rest/v1/user_invites')
                .replace(queryParameters: {'invitee_uid': 'eq.$uid', 'select': '*'}),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is List && decoded.isNotEmpty) {
          return Map<String, dynamic>.from(decoded.first);
        }
      }
    } catch (_) {}
    return null;
  }

  /// قائمة الذين دعوتهم (مع بياناتهم من users)
  Future<List<Map<String, dynamic>>> getInvitedUsers(String uid) async {
    try {
      final resp = await http
          .get(
            Uri.parse('$_baseUrl/rest/v1/user_invites')
                .replace(queryParameters: {'inviter_uid': 'eq.$uid', 'select': '*', 'order': 'created_at.desc'}),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return [];
      final decoded = jsonDecode(resp.body);
      if (decoded is! List) return [];
      final rows = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final inviteeIds = rows.map((r) => r['invitee_uid']?.toString() ?? '').where((e) => e.isNotEmpty).toList();
      if (inviteeIds.isEmpty) return rows;
      // جلب بيانات المدعوين من users
      final usersResp = await http
          .get(
            Uri.parse('$_baseUrl/rest/v1/users').replace(queryParameters: {
              'uid': 'in.(${inviteeIds.join(',')})',
              'select': 'uid,name,photo_url,custom_id',
            }),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      if (usersResp.statusCode == 200) {
        final users = jsonDecode(usersResp.body);
        if (users is List) {
          final map = <String, Map<String, dynamic>>{};
          for (final u in users) {
            final m = Map<String, dynamic>.from(u as Map);
            map[m['uid']?.toString() ?? ''] = m;
          }
          for (final r in rows) {
            final u = map[r['invitee_uid']?.toString() ?? ''];
            if (u != null) {
              r['name'] = u['name'];
              r['photo_url'] = u['photo_url'];
              r['custom_id'] = u['custom_id'];
            }
          }
        }
      }
      return rows;
    } catch (_) {
      return [];
    }
  }

  /// إعدادات الدعوة من app_config.invite_settings
  /// { invite_bonus_coins, inviter_reward, invitee_reward, screen }
  Future<Map<String, dynamic>> getInviteSettings() async {
    try {
      final resp = await http
          .get(
            Uri.parse('$_baseUrl/rest/v1/app_config')
                .replace(queryParameters: {'key': 'eq.invite_settings', 'select': 'value'}),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is List && decoded.isNotEmpty) {
          final v = decoded.first['value'];
          if (v is Map) return Map<String, dynamic>.from(v);
          if (v is String) {
            final p = jsonDecode(v);
            if (p is Map) return Map<String, dynamic>.from(p);
          }
        }
      }
    } catch (_) {}
    return {};
  }

  /// حالة المكافأة اليومية: { enabled, claimed, reward, title, description }
  Future<Map<String, dynamic>> getDailyRewardStatus(String uid) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/rest/v1/rpc/get_daily_reward_status'),
            headers: _headers,
            body: jsonEncode({'p_uid': uid}),
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return {'enabled': false, 'claimed': false};
  }

  /// استلام المكافأة اليومية (مرة واحدة يومياً لكل مستخدم)
  Future<Map<String, dynamic>> claimDailyReward(String uid) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/rest/v1/rpc/claim_daily_reward'),
            headers: _headers,
            body: jsonEncode({'p_uid': uid}),
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
      return {'ok': false, 'message': 'network_error'};
    } catch (_) {
      return {'ok': false, 'message': 'network_error'};
    }
  }

  /// إحصائيات لعب المدعوين: مجموع الرهانات اليوم وأمس لكل uid
  /// يعيد { uid: {'today': double, 'yesterday': double} }
  Future<Map<String, Map<String, double>>> getInviteesGameStats(List<String> uids) async {
    final result = <String, Map<String, double>>{};
    if (uids.isEmpty) return result;
    try {
      final inFilter = uids.map((u) => '"$u"').join(',');
      final resp = await http
          .get(
            Uri.parse('$_baseUrl/rest/v1/game_bet_records')
                .replace(queryParameters: {
                  'user_id': 'in.($inFilter)',
                  'select': 'user_id,bet_amount,created_at',
                  'order': 'created_at.desc',
                  'limit': '5000',
                }),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return result;
      final decoded = jsonDecode(resp.body);
      if (decoded is! List) return result;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      for (final row in decoded) {
        if (row is! Map) continue;
        final uid = row['user_id']?.toString() ?? '';
        if (uid.isEmpty) continue;
        final bet = (row['bet_amount'] as num?)?.toDouble() ?? 0;
        final dt = DateTime.tryParse(row['created_at']?.toString() ?? '');
        if (dt == null) continue;
        final day = DateTime(dt.year, dt.month, dt.day);
        final entry = result.putIfAbsent(uid, () => {'today': 0, 'yesterday': 0});
        if (day.isAtSameMomentAs(today)) {
          entry['today'] = (entry['today'] ?? 0) + bet;
        } else if (day.isAtSameMomentAs(yesterday)) {
          entry['yesterday'] = (entry['yesterday'] ?? 0) + bet;
        }
      }
    } catch (_) {}
    return result;
  }

  /// اسم عنصر من المتجر (لعرض المكافآت من نوع item/vip_item)
  Future<String> getStoreItemName(String itemId) async {
    if (itemId.isEmpty) return '';
    try {
      final resp = await http
          .get(
            Uri.parse('$_baseUrl/rest/v1/store_items')
                .replace(queryParameters: {
                  'or': '(item_id.eq.$itemId,id.eq.$itemId)',
                  'select': 'name',
                  'limit': '1',
                }),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is List && decoded.isNotEmpty) {
          final m = Map<String, dynamic>.from(decoded.first as Map);
          return m['name']?.toString() ?? '';
        }
      }
    } catch (_) {}
    return '';
  }

  /// صرف مكافآت المدعوين (invite_bonus_coins لاحقاً من app_config.invite_settings)
  Future<Map<String, dynamic>> claimInviteRewards(String uid) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/rest/v1/rpc/claim_invite_rewards'),
            headers: _headers,
            body: jsonEncode({'p_uid': uid}),
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
      return {'ok': false, 'message': 'network_error'};
    } catch (_) {
      return {'ok': false, 'message': 'network_error'};
    }
  }
}
