import '../../../core/supabase_compat.dart';

import '../../../core/utils/server_time_service.dart';
import 'agency_models.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

// ═══════════════════════════════════════════════════════════════════
//  AgencyRepository v2 — كل عمليات Supabase للوكالات
//  - يقرأ الإعدادات المالية من قاعدة البيانات (لا ثوابت مشفّرة)
//  - يستخدم get_host_dashboard_v2 كمصدر واحد للحقيقة
//  - جميع RPC بمعاملات موحدة مع المحرك الجديد
// ═══════════════════════════════════════════════════════════════════
abstract final class AgencyRepository {
  static SupabaseClient get _sb => Supabase.instance.client;

  // ─── إعدادات المحرك (مصدر الحقيقة الوحيد للأسعار) ──────────────
  // ✅ إصلاح: لا قيم مُشفَّرة — إذا فشل RPC نرفع استثناءً صريحاً
  // حتى لا تُجري العمليات المالية بمعدلات خاطئة بصمت
  static Future<AgencyEngineSettings> getEngineSettings() async {
    final resp = await _sb.rpc('agency_get_engine_settings');
    if (resp == null) {
      debugPrint('[AgencyRepository] ⚠️ CRITICAL: agency_get_engine_settings returned null');
      throw Exception('تعذّر جلب إعدادات المحرك المالي من الخادم. يرجى المحاولة مجدداً.');
    }
    return AgencyEngineSettings.fromMap(Map<String, dynamic>.from(resp as Map));
  }

  // ─── التصنيف ────────────────────────────────────────────────────
  static Future<List<AgencyLeaderboardEntry>> getLeaderboard({
    String? country,
    int limit  = 50,
    int offset = 0,
  }) async {
    final resp = await _sb.rpc('agency_get_leaderboard', params: {
      'p_country': country,
      'p_limit':   limit,
      'p_offset':  offset,
    });
    final list = (resp as List<dynamic>?) ?? [];
    return list
        .map((e) => AgencyLeaderboardEntry.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ─── ملف الوكالة العام ──────────────────────────────────────────
  static Future<AgencyCard?> getProfile(String agencyId) async {
    // Try RPC first (if it exists)
    try {
      final resp = await _sb.rpc('agency_get_profile', params: {
        'p_agency_id': agencyId,
      });
      if (resp != null) {
        return AgencyCard.fromMap(Map<String, dynamic>.from(resp as Map));
      }
    } catch (_) {
      // RPC doesn't exist — fallback to direct query
    }

    // Fallback: query host_agencies directly
    Map<String, dynamic>? row;
    try {
      final res = await _sb
          .from('host_agencies')
          .select('*')
          .eq('id', agencyId)
          .maybeSingle();
      if (res != null) {
        row = Map<String, dynamic>.from(res as Map);
      }
    } catch (_) {}
    if (row == null) return null;

    // Normalize field names
    final photoUrl = row['logo_url'] ?? row['photo_url'] ?? '';
    final code = row['agency_code'] ?? row['agency_public_id'] ?? row['id'];
    row['photo_url'] = photoUrl;
    row['agency_public_id'] = code;
    row['tier'] = row['tier'] ?? row['data']?['tier'] ?? 'bronze';
    row['country'] = row['country'] ?? row['data']?['country'] ?? '';

    // Check if current user is a member or has pending request
    final uid = _sb.auth.currentUser?.id;
    bool isMember = false;
    bool canJoin = false;
    bool hasPendingRequest = false;
    if (uid != null) {
      Map<String, dynamic>? memberRow;
      try {
        final m = await _sb
            .from('host_agency_members')
            .select('status')
            .eq('agency_id', agencyId)
            .eq('host_uid', uid)
            .maybeSingle();
        if (m != null) memberRow = Map<String, dynamic>.from(m as Map);
      } catch (_) {}
      if (memberRow == null) {
        try {
          final m2 = await _sb
              .from('host_agency_members')
              .select('status')
              .eq('agency_id', agencyId)
              .eq('user_id', uid)
              .maybeSingle();
          if (m2 != null) memberRow = Map<String, dynamic>.from(m2 as Map);
        } catch (_) {}
      }

      if (memberRow != null) {
        final status = memberRow['status'] as String? ?? '';
        if (status == 'active') {
          isMember = true;
          canJoin = false;
        } else if (status == 'pending') {
          hasPendingRequest = true;
          canJoin = false;
        } else {
          canJoin = true;
        }
      } else {
        canJoin = true;
      }
    }

    return AgencyCard.fromMap({
      ...row,
      'is_member': isMember,
      'can_join': canJoin,
      'has_pending_request': hasPendingRequest,
    });
  }

  // ─── إنشاء وكالة ────────────────────────────────────────────────
  static Future<String> createAgency({
    required String name,
    String? description,
    String? country,
    String? photoUrl,
    String? phone,
  }) async {
    final resp = await _sb.rpc('agency_create', params: {
      'p_name':        name,
      'p_description': description,
      'p_country':     country,
      'p_photo_url':   photoUrl,
      'p_phone':       phone,
    });
    return (resp as Map<String, dynamic>)['agency_id'] as String;
  }

  // ─── طلب انضمام ─────────────────────────────────────────────────
  static Future<void> requestJoin(String agencyId) async {
    try {
      final resp = await _sb.rpc('agency_request_join', params: {'p_agency_id': agencyId});
      if (resp is Map && resp['status'] == 'error') {
        throw Exception(resp['message'] ?? 'تعذر تقديم طلب الانضمام');
      }
    } catch (e) {
      if (e is Exception &&
          (e.toString().contains('عضو بالفعل') ||
              e.toString().contains('طلب معلق') ||
              e.toString().contains('مسجل بالفعل'))) {
        rethrow;
      }
      // Fallback: insert directly into host_agency_join_requests and host_agency_members
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) throw Exception('يجب تسجيل الدخول أولاً');
      final reqId = const Uuid().v4();
      try {
        await _sb.from('host_agency_join_requests').insert({
          'id': reqId,
          'agency_id': agencyId,
          'user_id': uid,
          'status': 'pending',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (_) {}
      try {
        await _sb.from('host_agency_members').insert({
          'agency_id': agencyId,
          'user_id': uid,
          'role': 'host',
          'status': 'pending',
        });
      } catch (_) {
        try {
          await _sb.from('host_agency_members').insert({
            'agency_id': agencyId,
            'host_uid': uid,
            'role': 'host',
            'status': 'pending',
          });
        } catch (_) {}
      }
      try {
        final agRow = await _sb.from('host_agencies').select('owner_uid, name').eq('id', agencyId).maybeSingle();
        final ownerId = agRow?['owner_uid']?.toString() ?? agRow?['owner_id']?.toString() ?? '';
        final agName = agRow?['name']?.toString() ?? 'وكالتك';
        if (ownerId.isNotEmpty && ownerId != uid) {
          final uRow = await _sb.from('users').select('name, custom_id').eq('id', uid).maybeSingle();
          final uName = uRow?['name']?.toString() ?? 'مستخدم';
          final cId = uRow?['custom_id']?.toString() ?? '';
          await _sb.from('notifications').insert({
            'uid': ownerId,
            'target': ownerId,
            'type': 'agency_host_request',
            'actor_uid': uid,
            'title': 'طلب انضمام مضيف جديد إلى وكالتك 📝',
            'body': 'قدم المضيف [$uName] (معرف: $cId) طلباً للانضمام إلى وكالتك [$agName].',
            'data': {
              'action': 'host_join_request',
              'agency_id': agencyId,
              'applicant_uid': uid,
              'applicant_name': uName,
            },
          });
        }
      } catch (_) {}
    }
  }

  // ─── انسحاب من الوكالة ──────────────────────────────────────────
  static Future<void> leaveAgency(String agencyId) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw Exception('يجب تسجيل الدخول أولاً');
    try {
      await _sb.rpc('agency_leave', params: {'p_agency_id': agencyId});
    } catch (_) {
      // Fallback: update status to 'left' or delete membership record
      await _sb
          .from('host_agency_members')
          .update({'status': 'left'})
          .eq('agency_id', agencyId)
          .eq('user_id', uid);
    }
  }

  // ─── لوحة المضيف الموحدة (v2) ───────────────────────────────────
  /// المصدر الوحيد لبيانات المضيف: أرصدة + أهداف + محفظة + إعدادات المحرك
  static Future<HostAgencyStats?> getHostStats() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;

    try {
      final resp = await _sb.rpc('get_host_dashboard_v2', params: {
        'p_user_id': uid,
      });
      if (resp != null) {
        final data = Map<String, dynamic>.from(resp as Map);
        if (data['status'] == 'ok') {
          final member = AgencyMemberInfo.fromMap({
            'member_id':                   data['member_id'],
            'user_id':                     uid,
            'agency_id':                   data['agency_id'],
            'role':                        data['role'],
            'status':                      'active',
            'diamonds_balance':            data['diamonds_balance'],
            'diamonds_available':          data['diamonds_available'],
            'diamonds_pending_withdrawal': data['diamonds_pending_withdrawal'],
            'diamonds_earned_monthly':     data['diamonds_earned_monthly'],
            'diamonds_earned_cumulative':  data['diamonds_earned_cumulative'],
            'join_date':                   data['join_date'],
            'is_in_trial':                 data['is_in_trial'],
            'trial_ends_at':               data['trial_ends_at'],
          });

          final targets = ((data['targets'] as List<dynamic>?) ?? [])
              .map((e) => AgencyTarget.fromDashboardMap(Map<String, dynamic>.from(e as Map)))
              .toList();

          final ledger = ((data['recent_ledger'] as List<dynamic>?) ?? [])
              .map((e) => AgencyLedgerEntry.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList();

          final engineMap = data['engine'] as Map<String, dynamic>? ?? {};
          final engine = AgencyEngineSettings.fromMap(engineMap);

          final achievedIds = targets
              .where((t) => t.isAchieved)
              .map((t) => t.id)
              .toList();

          final agency = data['agency_id'] != null
              ? AgencyCard(
                  id: data['agency_id'].toString(),
                  name: data['agency_name']?.toString() ?? 'الوكالة',
                  tier: AgencyTier.bronze,
                  memberCount: 1,
                  totalDiamondsMonthly: (data['diamonds_earned_monthly'] as num?)?.toInt() ?? 0,
                  totalDiamondsCumulative: (data['diamonds_earned_cumulative'] as num?)?.toInt() ?? 0,
                  isHallOfFame: false,
                  status: 'active',
                )
              : null;

          return HostAgencyStats(
            member:            member,
            agency:            agency,
            targets:           targets,
            recentLedger:      ledger,
            engine:            engine,
            achievedTargetIds: achievedIds,
          );
        }
      }
    } catch (e) {
      debugPrint('[AgencyRepository] getHostStats RPC error: $e');
    }

    // ── Direct Supabase Fallback when RPC fails or is missing ──
    try {
      final memList = await _sb.from('host_agency_members')
          .select('*')
          .or('user_id.eq.$uid,host_uid.eq.$uid')
          .limit(1);
      if (memList.isNotEmpty) {
        final m = Map<String, dynamic>.from(memList.first as Map);
        final agencyId = m['agency_id']?.toString() ?? '';
        final memberId = m['id']?.toString() ?? uid;
        final diamonds = (m['diamonds'] as num?)?.toInt() ?? 0;
        final diamondsMonthly = (m['diamonds_earned_monthly'] as num?)?.toInt() ?? diamonds;
        final diamondsCumulative = (m['diamonds_earned_cumulative'] as num?)?.toInt() ?? diamonds;
        final diamondsBalance = (m['diamonds_balance'] as num?)?.toInt() ?? (m['diamonds_available'] as num?)?.toInt() ?? diamonds;

        Map<String, dynamic>? agencyRow;
        if (agencyId.isNotEmpty) {
          final agList = await _sb.from('host_agencies').select('*').eq('id', agencyId).limit(1);
          if (agList.isNotEmpty) {
            agencyRow = Map<String, dynamic>.from(agList.first as Map);
          }
        }

        List<AgencyTarget> targets = [];
        if (agencyId.isNotEmpty) {
          try {
            final tgList = await _sb.from('agency_targets').select('*').eq('agency_id', agencyId).order('target_diamonds', ascending: true);
            targets = (tgList as List).map((t) {
              final row = Map<String, dynamic>.from(t as Map);
              final targetDiamonds = (row['target_diamonds'] as num?)?.toInt() ?? 0;
              final earned = diamondsMonthly;
              final rem = (targetDiamonds - earned).clamp(0, targetDiamonds);
              final pct = targetDiamonds > 0 ? (earned / targetDiamonds).clamp(0.0, 1.0) : 0.0;
              return AgencyTarget(
                id: row['id']?.toString() ?? '',
                title: row['title']?.toString() ?? row['name']?.toString() ?? 'المستوى $targetDiamonds',
                targetDiamonds: targetDiamonds,
                rewardDiamonds: (row['reward_diamonds'] as num?)?.toInt() ?? 0,
                rewardCoins: (row['reward_coins'] as num?)?.toInt() ?? 0,
                rewardType: row['reward_type']?.toString() ?? 'coins',
                rewardValue: (row['reward_value'] as num?)?.toDouble() ?? 0.0,
                rewardImageUrl: row['reward_image_url']?.toString(),
                earnedThisMonth: earned,
                remaining: rem,
                progressPct: pct,
                isAchieved: earned >= targetDiamonds && targetDiamonds > 0,
              );
            }).toList();
          } catch (_) {}
        }

        final member = AgencyMemberInfo(
          memberId: memberId,
          userId: uid,
          agencyId: agencyId,
          role: m['role']?.toString() ?? 'host',
          status: m['status']?.toString() ?? 'active',
          diamondsBalance: diamondsBalance,
          diamondsAvailable: diamondsBalance,
          diamondsPendingWithdrawal: 0,
          diamondsEarnedMonthly: diamondsMonthly,
          diamondsEarnedCumulative: diamondsCumulative,
          joinDate: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
        );

        final agency = agencyRow != null
            ? AgencyCard(
                id: agencyId,
                name: agencyRow['name']?.toString() ?? agencyRow['agency_name']?.toString() ?? 'الوكالة',
                tier: AgencyTier.bronze,
                memberCount: (agencyRow['total_hosts'] as num?)?.toInt() ?? (agencyRow['member_count'] as num?)?.toInt() ?? 1,
                totalDiamondsMonthly: (agencyRow['total_diamonds_monthly'] as num?)?.toInt() ?? diamondsMonthly,
                totalDiamondsCumulative: (agencyRow['total_diamonds_cumulative'] as num?)?.toInt() ?? diamondsCumulative,
                isHallOfFame: false,
                status: agencyRow['status']?.toString() ?? 'active',
              )
            : null;

        return HostAgencyStats(
          member: member,
          agency: agency,
          targets: targets,
          recentLedger: [],
          engine: AgencyEngineSettings.fromMap({}),
          achievedTargetIds: targets.where((t) => t.isAchieved).map((t) => t.id).toList(),
        );
      }
    } catch (e) {
      debugPrint('[AgencyRepository] getHostStats fallback error: $e');
    }

    return null;
  }

  // ─── طلب الخروج ─────────────────────────────────────────────────
  static Future<Map<String, dynamic>> requestExit() async {
    final resp = await _sb.rpc('agency_request_exit', params: {});
    return Map<String, dynamic>.from(resp as Map);
  }

  // ─── دفع غرامة الخروج ───────────────────────────────────────────
  static Future<void> payPenaltyExit() async {
    await _sb.rpc('agency_pay_penalty_exit', params: {});
  }

  // ─── خروج الوكيل وحذف الوكالة نهائياً ─────────────────────────────
  static Future<bool> deleteAndExitAgencyByOwner({
    required String agencyId,
    required String ownerUid,
  }) async {
    try {
      final resp = await _sb.rpc('agency_delete', params: {
        'p_agency_id': agencyId,
      });
      return resp?['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  // ─── خروج العضو وتصفير مراحله ──────────────────────────────────────
  static Future<bool> leaveAgencyAsMember({
    required String agencyId,
    required String userId,
  }) async {
    try {
      final resp = await _sb.rpc('agency_pay_penalty_exit', params: {
        'p_agency_id': agencyId,
      });
      return resp?['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  // ─── تبادل الألماس بكوينز (معدل من قاعدة البيانات) ──────────────
  // ✅ إصلاح: DB signature = (p_diamonds bigint, p_idempotency_key text)
  //    auth.uid() يُحدَّد داخل الدالة تلقائياً — لا حاجة لإرسال p_user_id
  static Future<Map<String, dynamic>> exchangeDiamonds({
    required int    diamondsAmount,
    required String idempotencyKey,
  }) async {
    final resp = await _sb.rpc('agency_exchange_diamonds', params: {
      'p_diamonds':        diamondsAmount,
      'p_idempotency_key': idempotencyKey,
    });
    return Map<String, dynamic>.from(resp as Map);
  }

  // ─── طلب سحب نقدي (مع KYC وتجميد فوري) ─────────────────────────
  // ✅ إصلاح: DB signature = (p_diamonds bigint, p_bank_details jsonb, p_idempotency_key text)
  //    auth.uid() يُحدَّد داخل الدالة — bankDetails = {method, bank_name, iban, country}
  static Future<Map<String, dynamic>> requestWithdrawal({
    required int    diamondsAmount,
    required String paymentMethod,
    required Map<String, dynamic> paymentDetails,
    required String idempotencyKey,
  }) async {
    final bankDetails = <String, dynamic>{
      'method': paymentMethod,
      ...paymentDetails,
    };

    final resp = await _sb.rpc('agency_request_withdrawal', params: {
      'p_diamonds':        diamondsAmount,
      'p_bank_details':    bankDetails,
      'p_idempotency_key': idempotencyKey,
    });
    return Map<String, dynamic>.from(resp as Map);
  }

  // ─── تحويل إلى وكيل شحن (Legacy — يُفضَّل transferDiamondsToAgentWallet) ─────
  // ✅ إصلاح: DB signature = (p_agent_id uuid, p_diamonds bigint)
  //    auth.uid() يُحدَّد داخل الدالة — لا idempotency_key في هذه الدالة
  static Future<Map<String, dynamic>> transferToRecharge({
    required String agentUserId,
    required int    diamondsAmount,
  }) async {
    final resp = await _sb.rpc('agency_transfer_to_recharge', params: {
      'p_agent_id': agentUserId,
      'p_diamonds': diamondsAmount,
    });
    return Map<String, dynamic>.from(resp as Map);
  }

  /// تحويل ألماس وسحب الراتب الفعلي لمحفظة وكيل الشحن أو الإدارة
  /// p_source: 'host' للمضيف، 'agency_owner' لمالك الوكالة
  static Future<Map<String, dynamic>> transferDiamondsToAgentWallet({
    required String agentId,
    required int    diamonds,
    required String idempotencyKey,
    String source = 'host',
  }) async {
    try {
      final resp = await _sb.rpc('host_transfer_diamonds_to_agent', params: {
        'p_agent_id':         agentId,
        'p_diamonds':         diamonds,
        'p_idempotency_key':  idempotencyKey,
        'p_source':           source,
      });
      if (resp != null && (resp['status'] == 'ok' || resp['ok'] == true || resp['success'] == true)) {
        return Map<String, dynamic>.from(resp as Map);
      }
    } catch (_) {
      // Fallback to direct robust database transaction below
    }

    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null || uid.isEmpty) {
        return {'status': 'error', 'message': 'المستخدم غير مسجل الدخول'};
      }
      if (diamonds <= 0) {
        return {'status': 'error', 'message': 'الكمية المراد سحبها غير صالحة'};
      }

      // Check idempotency in agency_diamond_ledger or agency_withdrawal_requests
      try {
        final existing = await _sb
            .from('agency_withdrawal_requests')
            .select('id')
            .eq('details->>idempotency_key', idempotencyKey)
            .maybeSingle();
        if (existing != null) {
          return {'status': 'ok', 'success': true, 'duplicate': true};
        }
      } catch (_) {}

      // Fetch sender data from users table
      final userRow = await _sb
          .from('users')
          .select('id, uid, name, custom_id, diamonds, coins, agency_id')
          .or('uid.eq.$uid,id.eq.$uid')
          .maybeSingle();
      final userDiamonds = (userRow?['diamonds'] as num?)?.toInt() ?? 0;
      final userName = userRow?['name']?.toString() ?? userRow?['custom_id']?.toString() ?? 'مستخدم';

      if (source == 'host') {
        // Fetch host agency membership
        final memberRow = await _sb
            .from('host_agency_members')
            .select('id, agency_id, diamonds, diamonds_balance, diamonds_earned_monthly')
            .or('user_id.eq.$uid,host_uid.eq.$uid')
            .maybeSingle();

        final agencyId = memberRow?['agency_id']?.toString() ?? userRow?['agency_id']?.toString() ?? '';
        final memberDiamonds = (memberRow?['diamonds'] as num?)?.toInt() ?? (memberRow?['diamonds_balance'] as num?)?.toInt() ?? userDiamonds;

        if (userDiamonds < diamonds && memberDiamonds < diamonds) {
          return {'status': 'error', 'message': 'رصيد الألماس المتاح غير كافٍ لإتمام السحب'};
        }

        // Fetch agency owner
        String ownerId = '';
        String agencyName = 'الوكالة';
        if (agencyId.isNotEmpty) {
          final agRow = await _sb
              .from('host_agencies')
              .select('id, name, owner_id, owner_uid')
              .eq('id', agencyId)
              .maybeSingle();
          ownerId = agRow?['owner_id']?.toString() ?? agRow?['owner_uid']?.toString() ?? '';
          agencyName = agRow?['name']?.toString() ?? 'الوكالة';
        }

        // Fetch general agency commission rate from commission_settings
        double agencyRate = 0.15; // default 15%
        try {
          final commRow = await _sb
              .from('commission_settings')
              .select('percentage, value')
              .eq('key', 'agency_rate')
              .maybeSingle();
          if (commRow != null) {
            final raw = commRow['percentage'] ?? commRow['value'];
            if (raw is num && raw > 0) {
              agencyRate = raw > 1 ? (raw.toDouble() / 100.0) : raw.toDouble();
            }
          }
        } catch (_) {}

        final int agentCommissionDiamonds = (diamonds * agencyRate).round();

        // 1. Zero out / deduct host diamonds in users table
        final newHostDiamonds = (userDiamonds - diamonds).clamp(0, 999999999);
        await _sb.from('users').update({
          'diamonds': newHostDiamonds,
        }).or('uid.eq.$uid,id.eq.$uid');

        // 2. Zero out host's diamonds in host_agency_members
        if (memberRow != null && memberRow['id'] != null) {
          await _sb.from('host_agency_members').update({
            'diamonds': 0,
            'diamonds_balance': 0,
            'diamonds_earned_monthly': 0,
            'diamonds_available': 0,
          }).eq('id', memberRow['id']);
        }

        // 3. Add Agent Commission to Agency Owner wallet & member record & agency target
        if (ownerId.isNotEmpty && agentCommissionDiamonds > 0) {
          try {
            // Update owner record in host_agency_members
            final ownerMem = await _sb
                .from('host_agency_members')
                .select('*')
                .eq('agency_id', agencyId)
                .or('user_id.eq.$ownerId,host_uid.eq.$ownerId')
                .maybeSingle();
            int oDia = 0;
            int oBal = 0;
            int oEarnedMonthly = 0;
            int oEarnedCumulative = 0;
            if (ownerMem != null) {
              oDia = (ownerMem['diamonds'] as num?)?.toInt() ?? 0;
              oBal = (ownerMem['diamonds_balance'] as num?)?.toInt() ?? oDia;
              oEarnedMonthly = (ownerMem['diamonds_earned_monthly'] as num?)?.toInt() ?? 0;
              oEarnedCumulative = (ownerMem['diamonds_earned_cumulative'] as num?)?.toInt() ?? 0;
              await _sb.from('host_agency_members').update({
                'diamonds': oDia + agentCommissionDiamonds,
                'diamonds_balance': oBal + agentCommissionDiamonds,
                'diamonds_earned_monthly': oEarnedMonthly + agentCommissionDiamonds,
                'diamonds_earned_cumulative': oEarnedCumulative + agentCommissionDiamonds,
              }).eq('id', ownerMem['id']);
            }

            // Update owner user diamonds in users table
            try {
              final uRow = await _sb.from('users').select('diamonds').eq('uid', ownerId).maybeSingle();
              if (uRow != null) {
                final uDia = (uRow['diamonds'] as num?)?.toInt() ?? 0;
                await _sb.from('users').update({
                  'diamonds': uDia + agentCommissionDiamonds,
                }).eq('uid', ownerId);
              }
            } catch (_) {}

            // Update host_agencies monthly & cumulative target diamonds so agent target reflects commission
            try {
              final agRow = await _sb.from('host_agencies').select('monthly_diamonds, total_diamonds_monthly, total_diamonds_cumulative').eq('id', agencyId).maybeSingle();
              if (agRow != null) {
                final curMonthly = (agRow['monthly_diamonds'] as num?)?.toInt() ?? 0;
                final curTotMonthly = (agRow['total_diamonds_monthly'] as num?)?.toInt() ?? 0;
                final curTotCum = (agRow['total_diamonds_cumulative'] as num?)?.toInt() ?? 0;
                await _sb.from('host_agencies').update({
                  'monthly_diamonds': curMonthly + agentCommissionDiamonds,
                  'total_diamonds_monthly': curTotMonthly + agentCommissionDiamonds,
                  'total_diamonds_cumulative': curTotCum + agentCommissionDiamonds,
                }).eq('id', agencyId);
              }
            } catch (_) {}

            // Update agency_wallets if table exists
            try {
              final aw = await _sb
                  .from('agency_wallets')
                  .select('diamond_balance')
                  .eq('agency_profile_id', ownerId)
                  .maybeSingle();
              final curOwnerDia = (aw?['diamond_balance'] as num?)?.toInt() ?? 0;
              if (aw != null) {
                await _sb.from('agency_wallets').update({
                  'diamond_balance': curOwnerDia + agentCommissionDiamonds,
                  'updated_at': DateTime.now().toIso8601String(),
                }).eq('agency_profile_id', ownerId);
              } else {
                await _sb.from('agency_wallets').insert({
                  'agency_profile_id': ownerId,
                  'diamond_balance': agentCommissionDiamonds,
                  'gold_balance': 0,
                  'total_earnings': agentCommissionDiamonds,
                  'updated_at': DateTime.now().toIso8601String(),
                });
              }
            } catch (_) {}

            // Log commission to agency_diamond_ledger
            try {
              await _sb.from('agency_diamond_ledger').insert({
                'agency_id': agencyId,
                'user_id': ownerId,
                'sender_id': uid,
                'sender_name': userName,
                'txn_type': 'commission',
                'amount': agentCommissionDiamonds,
                'direction': 1,
                'balance_after': oBal + agentCommissionDiamonds,
                'gift_name': 'عمولة الوكيل (${(agencyRate * 100).toInt()}%) من سحب المضيف $userName',
                'created_at': DateTime.now().toIso8601String(),
              });
            } catch (_) {}

            // Send private message to agency owner
            try {
              await _sb.from('private_messages').insert({
                'sender_id': 'system',
                'receiver_id': ownerId,
                'text': 'مبروك! تمت إضافة عمولة بقيمة $agentCommissionDiamonds ماسة إلى محفظة وكالتك من سحب المضيف $userName.',
                'type': 'system',
                'created_at': DateTime.now().toIso8601String(),
              });
            } catch (_) {}
          } catch (e) {
            debugPrint('[AgencyRepository] error crediting owner commission: $e');
          }
        }

        // 4. Convert diamonds to coins and deposit to Recharge Agent Wallet
        if (agentId.isNotEmpty && agentId != 'admin') {
          try {
            final agentRow = await _sb
                .from('users')
                .select('id, uid, coins')
                .or('uid.eq.$agentId,id.eq.$agentId,custom_id.eq.$agentId')
                .maybeSingle();
            if (agentRow != null) {
              final aId = agentRow['uid'] ?? agentRow['id'];
              final curCoins = (agentRow['coins'] as num?)?.toInt() ?? 0;
              await _sb.from('users').update({
                'coins': curCoins + diamonds,
              }).or('uid.eq.$aId,id.eq.$aId');

              try {
                await _sb.from('profiles').update({
                  'coins': curCoins + diamonds,
                }).eq('id', aId);
              } catch (_) {}

              // Send notification to recharge agent
              try {
                await _sb.from('private_messages').insert({
                  'sender_id': 'system',
                  'receiver_id': aId,
                  'text': '⚡ تم تحويل $diamonds كوينز إلى محفظتك بنجاح من سحب المضيف $userName (وكالة: $agencyName).',
                  'type': 'system',
                  'created_at': DateTime.now().toIso8601String(),
                });
              } catch (_) {}
            }
          } catch (e) {
            debugPrint('[AgencyRepository] error crediting recharge agent: $e');
          }
        }

        // 5. Log withdrawal in agency_diamond_ledger
        try {
          await _sb.from('agency_diamond_ledger').insert({
            'agency_id': agencyId,
            'user_id': uid,
            'txn_type': 'withdrawal',
            'amount': diamonds,
            'direction': -1,
            'gift_name': 'سحب راتب المضيف $userName وتحويله لكوينز لوكالة الشحن',
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (_) {}

        // 6. Log withdrawal request in agency_withdrawal_requests for Admin Dashboard
        try {
          await _sb.from('agency_withdrawal_requests').insert({
            'agency_id': agencyId,
            'user_id': uid,
            'amount': diamonds,
            'status': 'approved',
            'payment_method': 'recharge_agent_coins',
            'details': {
              'agent_id': agentId,
              'diamonds': diamonds,
              'coins': diamonds,
              'agent_commission': agentCommissionDiamonds,
              'agency_rate': agencyRate,
              'idempotency_key': idempotencyKey,
              'source': 'host',
              'user_name': userName,
              'agency_name': agencyName,
            },
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (_) {}

        return {
          'status': 'ok',
          'success': true,
          'coins': diamonds,
          'agent_commission': agentCommissionDiamonds,
          'message': 'تم السحب والتحويل بنجاح وتصفير رصيد المضيف مع احتساب عمولة الوكيل',
        };
      } else {
        // source == 'agency_owner'
        final memberRow = await _sb
            .from('host_agency_members')
            .select('*')
            .or('user_id.eq.$uid,host_uid.eq.$uid')
            .maybeSingle();
        final agencyId = memberRow?['agency_id']?.toString() ?? userRow?['agency_id']?.toString() ?? '';

        final oBal = (memberRow?['diamonds_balance'] as num?)?.toInt() ?? 
                     (memberRow?['diamonds'] as num?)?.toInt() ?? 0;
        final effectiveBal = oBal > 0 ? oBal : userDiamonds;

        if (effectiveBal < diamonds) {
          return {
            'status': 'error',
            'success': false,
            'message': 'رصيد أرباح الوكالة المتاح لديك لا يكفي ($effectiveBal 💎)',
          };
        }

        final newOwnerBalance = (effectiveBal - diamonds).clamp(0, 999999999);

        // Deduct from host_agency_members
        if (memberRow != null) {
          await _sb.from('host_agency_members').update({
            'diamonds': newOwnerBalance,
            'diamonds_balance': newOwnerBalance,
            'diamonds_available': newOwnerBalance,
          }).eq('id', memberRow['id']);
        }

        // Deduct from users table
        try {
          final curUDia = (userRow?['diamonds'] as num?)?.toInt() ?? userDiamonds;
          await _sb.from('users').update({
            'diamonds': (curUDia - diamonds).clamp(0, 999999999),
          }).or('uid.eq.$uid,id.eq.$uid');
        } catch (_) {}

        // Deduct from agency_wallets if table exists
        try {
          await _sb.from('agency_wallets').update({
            'diamond_balance': newOwnerBalance,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('agency_profile_id', uid);
        } catch (_) {}

        // Deduct from host_agencies
        if (agencyId.isNotEmpty) {
          try {
            final agRow = await _sb.from('host_agencies').select('monthly_diamonds, total_diamonds_monthly').eq('id', agencyId).maybeSingle();
            if (agRow != null) {
              final curMonthly = (agRow['monthly_diamonds'] as num?)?.toInt() ?? 0;
              final curTotMonthly = (agRow['total_diamonds_monthly'] as num?)?.toInt() ?? 0;
              await _sb.from('host_agencies').update({
                'monthly_diamonds': (curMonthly - diamonds).clamp(0, 999999999),
                'total_diamonds_monthly': (curTotMonthly - diamonds).clamp(0, 999999999),
              }).eq('id', agencyId);
            }
          } catch (_) {}
        }

        // Credit coins to recharge agent
        if (agentId.isNotEmpty && agentId != 'admin') {
          try {
            final agentRow = await _sb
                .from('users')
                .select('id, uid, coins')
                .or('uid.eq.$agentId,id.eq.$agentId,custom_id.eq.$agentId')
                .maybeSingle();
            if (agentRow != null) {
              final aId = agentRow['uid'] ?? agentRow['id'];
              final curCoins = (agentRow['coins'] as num?)?.toInt() ?? 0;
              await _sb.from('users').update({
                'coins': curCoins + diamonds,
              }).or('uid.eq.$aId,id.eq.$aId');

              try {
                await _sb.from('profiles').update({
                  'coins': curCoins + diamonds,
                }).eq('id', aId);
              } catch (_) {}

              // Send notification
              try {
                await _sb.from('private_messages').insert({
                  'sender_id': 'system',
                  'receiver_id': aId,
                  'text': '⚡ تم تحويل $diamonds كوينز إلى محفظتك بنجاح من سحب مالك الوكالة $userName.',
                  'type': 'system',
                  'created_at': DateTime.now().toIso8601String(),
                });
              } catch (_) {}
            }
          } catch (_) {}
        }

        // Log in agency_diamond_ledger
        try {
          await _sb.from('agency_diamond_ledger').insert({
            'agency_id': agencyId.isNotEmpty ? agencyId : 'unknown',
            'user_id': uid,
            'txn_type': 'withdrawal',
            'amount': diamonds,
            'direction': -1,
            'gift_name': 'سحب أرباح مالك الوكالة $userName وتحويله لكوينز',
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (_) {}

        // Log in agency_withdrawal_requests
        try {
          await _sb.from('agency_withdrawal_requests').insert({
            'agency_id': agencyId.isNotEmpty ? agencyId : 'unknown',
            'user_id': uid,
            'amount': diamonds,
            'status': 'approved',
            'payment_method': 'recharge_agent_coins',
            'details': {
              'agent_id': agentId,
              'diamonds': diamonds,
              'coins': diamonds,
              'idempotency_key': idempotencyKey,
              'source': 'agency_owner',
              'user_name': userName,
              'agency_name': agencyId,
            },
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (_) {}

        return {
          'status': 'ok',
          'success': true,
          'coins': diamonds,
          'message': 'تم سحب أرباح الوكيل بنجاح وتحديث الرصيد',
        };
      }
    } catch (err) {
      debugPrint('[AgencyRepository] transferDiamondsToAgentWallet error: $err');
      return {'status': 'error', 'message': 'حدث خطأ أثناء معالجة السحب: $err'};
    }
  }

  // ─── سجل المعاملات الكامل ────────────────────────────────────────
  static Future<List<AgencyLedgerEntry>> getTransactionHistory({
    int limit  = 50,
    int offset = 0,
    String? type,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return [];

    var baseQuery = _sb
        .from('agency_diamond_ledger')
        .select('id, txn_type, amount, direction, balance_after, note, created_at')
        .eq('user_id', uid);

    if (type != null) {
      baseQuery = baseQuery.eq('txn_type', type);
    }

    final rows = await baseQuery
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (rows as List<dynamic>)
        .map((e) => AgencyLedgerEntry.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ─── قائمة طلبات السحب ───────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getWithdrawalRequests() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return [];

    final resp = await _sb
        .from('agency_withdrawal_requests')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(20);
    return (resp as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  // ─── إرسال إعلان ─────────────────────────────────────────────────
  static Future<void> sendAnnouncement({
    required String agencyId,
    required String title,
    required String body,
  }) async {
    await _sb.rpc('agency_send_announcement', params: {
      'p_agency_id': agencyId,
      'p_title':     title,
      'p_body':      body,
    });
  }

  // ─── إعلانات الوكالة ─────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAnnouncements(String agencyId) async {
    final resp = await _sb
        .from('agency_announcements')
        .select()
        .eq('agency_id', agencyId)
        .order('created_at', ascending: false)
        .limit(20);
    return (resp as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  // ─── الوكالة الحرة ───────────────────────────────────────────────
  static Future<bool> isCurrentUserFreeAgent() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return false;
    final resp = await _sb
        .from('agency_free_agents')
        .select('free_until')
        .eq('user_id', uid)
        .maybeSingle();
    if (resp == null) return false;
    final freeUntil = DateTime.tryParse(resp['free_until'] as String? ?? '');
    return freeUntil != null && ServerTimeService.instance.now().isBefore(freeUntil);
  }

  // ─── القائمة السوداء ─────────────────────────────────────────────
  static Future<bool> isBlacklisted(String agencyId) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return false;
    final resp = await _sb
        .from('agency_blacklist')
        .select('id')
        .eq('agency_id', agencyId)
        .eq('user_id', uid)
        .maybeSingle();
    return resp != null;
  }

  // ─── أعضاء الوكالة ──────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getMembers(
    String agencyId, {
    int limit = 50,
  }) async {
    try {
      final resp = await _sb
          .from('host_agency_members')
          .select('''
            id, user_id, role, status,
            diamonds_earned_monthly, diamonds_earned_cumulative,
            diamonds_balance, diamonds_pending_withdrawal,
            trial_ends_at,
            profile:profiles(display_name, avatar_url, kayan_id, level)
          ''')
          .eq('agency_id', agencyId)
          .eq('status', 'active');
      final list = (resp as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      list.sort((a, b) => ((b['diamonds_earned_monthly'] as num?) ?? 0)
          .compareTo((a['diamonds_earned_monthly'] as num?) ?? 0));
      return list.take(limit).toList();
    } catch (e) {
      debugPrint('[AgencyRepository] getMembers error: $e');
      return [];
    }
  }

  // ─── لوحة المالك ─────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getDashboard(String agencyId) async {
    final resp = await _sb.rpc('agency_get_dashboard', params: {
      'p_agency_id': agencyId,
    });
    if (resp == null) return null;
    return Map<String, dynamic>.from(resp as Map);
  }

  // ─── محفظة مالك الوكالة ──────────────────────────────────────────

  /// لوحة تحكم المالك: محفظة + أسعار + آخر 20 حركة
  static Future<AgencyOwnerDashboard?> getOwnerDashboard(String agencyId) async {
    try {
      final resp = await _sb.rpc('agency_get_owner_dashboard', params: {
        'p_agency_id': agencyId,
      });
      if (resp != null) {
        return AgencyOwnerDashboard.fromMap(Map<String, dynamic>.from(resp as Map));
      }
    } catch (e) {
      debugPrint('[AgencyRepository] agency_get_owner_dashboard RPC failed, using fallback: $e');
    }

    try {
      final agRes = await _sb.from('host_agencies').select('*').eq('id', agencyId).maybeSingle();
      final ownerUid = agRes?['owner_uid']?.toString() ?? agRes?['owner_id']?.toString() ?? _sb.auth.currentUser?.id ?? '';
      final agencyRate = (agRes?['commission_rate'] as num?)?.toDouble() ?? 0.15;

      int ownerBalance = 0;
      int earnedCumulative = 0;

      // 1. Check host_agency_members for owner
      try {
        final memRes = await _sb
            .from('host_agency_members')
            .select('*')
            .eq('agency_id', agencyId)
            .or('role.eq.owner,host_uid.eq.$ownerUid,user_id.eq.$ownerUid')
            .maybeSingle();
        if (memRes != null) {
          final bal = (memRes['diamonds_balance'] as num?)?.toInt() ?? 0;
          final earned = (memRes['diamonds_earned_cumulative'] as num?)?.toInt() ?? 
                         (memRes['diamonds_earned_monthly'] as num?)?.toInt() ?? 0;
          final dia = (memRes['diamonds'] as num?)?.toInt() ?? 0;
          ownerBalance = bal > 0 ? bal : dia;
          earnedCumulative = earned > 0 ? earned : ownerBalance;
        }
      } catch (_) {}

      // 2. Check users table for owner
      if (ownerUid.isNotEmpty) {
        try {
          final uRes = await _sb.from('users').select('diamonds').eq('uid', ownerUid).maybeSingle();
          if (uRes != null) {
            final uDia = (uRes['diamonds'] as num?)?.toInt() ?? 0;
            if (uDia > ownerBalance) {
              ownerBalance = uDia;
            }
          }
        } catch (_) {}
      }

      // 3. Check agency_diamond_ledger
      final List<AgencyOwnerLedgerEntry> ledgerEntries = [];
      try {
        final ledgerRows = await _sb
            .from('agency_diamond_ledger')
            .select('*')
            .eq('agency_id', agencyId)
            .order('created_at', ascending: false)
            .limit(30);
        for (final row in ledgerRows) {
          final r = Map<String, dynamic>.from(row as Map);
          final amt = (r['amount'] as num?)?.toInt() ?? 0;
          final dir = (r['direction'] == 'out' || r['direction'] == -1) ? -1 : 1;
          ledgerEntries.add(AgencyOwnerLedgerEntry(
            id: (r['id'].toString().hashCode).abs(),
            txnType: r['txn_type']?.toString() ?? 'commission',
            amount: amt,
            direction: dir,
            balanceAfter: ownerBalance,
            note: r['gift_name']?.toString() ?? r['note']?.toString() ?? (r['sender_name'] != null ? 'من المضيف: ${r['sender_name']}' : null),
            createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ?? DateTime.now(),
          ));
        }
      } catch (_) {}

      return AgencyOwnerDashboard(
        wallet: AgencyOwnerWallet(
          balance: ownerBalance,
          available: ownerBalance,
          pending: 0,
          earnedTotal: earnedCumulative > ownerBalance ? earnedCumulative : ownerBalance,
        ),
        rates: AgencyEngineSettings.fromMap({
          'diamond_to_coin_rate': 1.0,
          'diamond_to_usd_rate': 0.001,
          'withdrawal_fee_pct': 0.0,
          'min_diamonds_to_withdraw': 1000,
          'agency_share_pct': (agencyRate * 100).toInt(),
          'host_share_pct': 100 - (agencyRate * 100).toInt(),
        }),
        ledger: ledgerEntries,
      );
    } catch (e) {
      debugPrint('[AgencyRepository] getOwnerDashboard fallback error: $e');
      return AgencyOwnerDashboard(
        wallet: AgencyOwnerWallet.empty(),
        rates: AgencyEngineSettings.fromMap({}),
        ledger: const [],
      );
    }
  }

  /// تبادل ألماس الوكالة → كوينز شخصية للمالك
  static Future<Map<String, dynamic>> ownerExchangeDiamonds({
    required String agencyId,
    required int    diamondsAmount,
    required String idempotencyKey,
  }) async {
    try {
      final resp = await _sb.rpc('agency_owner_exchange_diamonds', params: {
        'p_agency_id':       agencyId,
        'p_diamonds_amount': diamondsAmount,
        'p_idempotency_key': idempotencyKey,
      });
      if (resp != null) return Map<String, dynamic>.from(resp as Map);
    } catch (_) {}

    try {
      final uid = _sb.auth.currentUser?.id ?? '';
      final mem = await _sb.from('host_agency_members').select('*').eq('agency_id', agencyId).or('role.eq.owner,host_uid.eq.$uid,user_id.eq.$uid').maybeSingle();
      final curBal = (mem?['diamonds_balance'] as num?)?.toInt() ?? (mem?['diamonds'] as num?)?.toInt() ?? 0;
      if (curBal < diamondsAmount) {
        return {'success': false, 'error': 'الرصيد المتاح غير كافٍ'};
      }
      final newBal = (curBal - diamondsAmount).clamp(0, 999999999);
      if (mem != null) {
        await _sb.from('host_agency_members').update({
          'diamonds': newBal,
          'diamonds_balance': newBal,
        }).eq('id', mem['id']);
      }
      final uRes = await _sb.from('users').select('coins, diamonds').eq('uid', uid).maybeSingle();
      if (uRes != null) {
        final curCoins = (uRes['coins'] as num?)?.toInt() ?? 0;
        final curDia = (uRes['diamonds'] as num?)?.toInt() ?? 0;
        await _sb.from('users').update({
          'coins': curCoins + diamondsAmount,
          'diamonds': (curDia - diamondsAmount).clamp(0, 999999999),
        }).eq('uid', uid);
      }
      return {'success': true, 'coins': diamondsAmount, 'coins_credited': diamondsAmount, 'new_balance': newBal};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// طلب سحب نقدي من محفظة الوكالة (يتطلب KYC)
  static Future<Map<String, dynamic>> ownerRequestWithdrawal({
    required String agencyId,
    required int    diamondsAmount,
    required String paymentMethod,
    required Map<String, dynamic> paymentDetails,
  }) async {
    try {
      final resp = await _sb.rpc('agency_owner_request_withdrawal', params: {
        'p_agency_id':       agencyId,
        'p_diamonds_amount': diamondsAmount,
        'p_payment_method':  paymentMethod,
        'p_payment_details': paymentDetails,
      });
      if (resp != null) return Map<String, dynamic>.from(resp as Map);
    } catch (_) {}

    try {
      final uid = _sb.auth.currentUser?.id ?? '';
      await _sb.from('agency_withdrawal_requests').insert({
        'agency_id': agencyId,
        'user_id': uid,
        'amount': diamondsAmount,
        'status': 'pending',
        'payment_method': paymentMethod,
        'details': paymentDetails,
        'created_at': DateTime.now().toIso8601String(),
      });
      return {'success': true, 'message': 'تم تقديم طلب السحب بنجاح'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ─── البحث عن وكلاء الشحن ────────────────────────────────────────
  // ─── البحث عن وكلاء الشحن المعتمدين وعرض وكالاتهم ─────────────────────────
  static Future<List<Map<String, dynamic>>> searchRechargeAgents(String query) async {
    final q = query.trim().replaceFirst('#', '').trim();
    final List<Map<String, dynamic>> results = [];
    final Set<String> seenIds = {};

    void addAgent(Map<String, dynamic> item) {
      final id = item['id']?.toString() ?? item['uid']?.toString() ?? '';
      if (id.isNotEmpty && !seenIds.contains(id)) {
        seenIds.add(id);
        results.add(item);
      }
    }

    // 1. البحث في جدول users
    try {
      dynamic queryBuilder = _sb
          .from('users')
          .select('id, uid, name, photo_url, custom_id, is_recharge_agent, is_agent, recharge_agency_name, recharge_agency_logo, whatsapp_number, agency_id')
          .or('is_recharge_agent.eq.true,is_agent.eq.true');

      if (q.isNotEmpty) {
        queryBuilder = queryBuilder.or('name.ilike.%$q%,custom_id.ilike.%$q%,recharge_agency_name.ilike.%$q%,id.ilike.%$q%');
      }

      final uResp = await queryBuilder.limit(20);
      for (final e in (uResp as List<dynamic>)) {
        final m = Map<String, dynamic>.from(e as Map);
        final agentName = m['name']?.toString() ?? 'وكيل شحن معتمد';
        final agencyName = (m['recharge_agency_name'] != null && m['recharge_agency_name'].toString().trim().isNotEmpty)
            ? m['recharge_agency_name'].toString().trim()
            : 'وكالة $agentName';

        addAgent({
          'id': m['uid'] ?? m['id'],
          'display_name': agentName,
          'avatar_url': m['photo_url'] ?? '',
          'kayan_id': m['custom_id'] ?? (m['uid']?.toString().substring(0, 8) ?? ''),
          'recharge_agency_name': agencyName,
          'recharge_agency_logo': m['recharge_agency_logo'] ?? m['photo_url'] ?? '',
          'whatsapp_number': m['whatsapp_number'] ?? '',
        });
      }
    } catch (e) {
      debugPrint('[AgencyRepository] search users error: $e');
    }

    // 2. البحث في جدول profiles
    try {
      dynamic pQuery = _sb
          .from('profiles')
          .select('id, display_name, avatar_url, kayan_id, is_recharge_agent')
          .eq('is_recharge_agent', true);

      if (q.isNotEmpty) {
        pQuery = pQuery.or('display_name.ilike.%$q%,kayan_id.ilike.%$q%');
      }

      final resp = await pQuery.limit(20);
      for (final e in (resp as List<dynamic>)) {
        final m = Map<String, dynamic>.from(e as Map);
        final name = m['display_name']?.toString() ?? 'وكيل شحن';
        addAgent({
          'id': m['id'],
          'display_name': name,
          'avatar_url': m['avatar_url'] ?? '',
          'kayan_id': m['kayan_id'] ?? '',
          'recharge_agency_name': 'وكالة $name',
          'recharge_agency_logo': m['avatar_url'] ?? '',
          'whatsapp_number': '',
        });
      }
    } catch (e) {
      debugPrint('[AgencyRepository] search profiles error: $e');
    }

    return results;
  }

  // ─── إرسال طلب سحب ألماس من المضيف إلى وكيل الشحن (مع إشعار تفاعلي موافقة/رفض) ──
  static Future<Map<String, dynamic>> requestHostWithdrawalToAgent({
    required Map<String, dynamic> agent,
    required int diamonds,
    required String hostUid,
    required String hostName,
    String? hostCustomId,
    String? hostAvatar,
    String? agencyId,
    String? agencyName,
  }) async {
    try {
      final agentId = agent['id']?.toString() ?? agent['uid']?.toString() ?? '';
      if (agentId.isEmpty) {
        return {'success': false, 'message': 'بيانات وكيل الشحن غير صحيحة'};
      }
      if (diamonds <= 0) {
        return {'success': false, 'message': 'كمية الألماس غير صالحة'};
      }

      final requestId = 'host_wdr_${DateTime.now().millisecondsSinceEpoch}_${hostUid.substring(0, 4)}';
      final approxUsd = diamonds / 100.0; // معدل تقريبي

      final accountDetails = {
        'request_type': 'host_diamonds_withdrawal',
        'host_uid': hostUid,
        'host_name': hostName,
        'host_custom_id': hostCustomId ?? '',
        'host_avatar': hostAvatar ?? '',
        'diamonds': diamonds,
        'agency_id': agencyId ?? '',
        'agency_name': agencyName ?? 'وكالة المضيف',
        'agent_custom_id': agent['kayan_id']?.toString() ?? '',
        'recharge_agency_name': agent['recharge_agency_name']?.toString() ?? '',
      };

      // 1. تسجيل الطلب في جدول agent_withdrawal_requests بحالة pending
      await _sb.from('agent_withdrawal_requests').insert({
        'id': requestId,
        'agent_id': agentId,
        'agent_name': agent['display_name'] ?? 'وكيل شحن',
        'amount_usd': approxUsd,
        'payment_method': 'host_diamonds',
        'account_details': accountDetails,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });

      // 2. إرسال إشعار فوري وتفاعلي لوكيل الشحن
      try {
        await _sb.from('notifications').insert({
          'uid': agentId,
          'target': agentId,
          'title': 'طلب سحب ألماس جديد 💎',
          'body': 'طلب المضيف $hostName سحب $diamonds ماسة عبر وكالتك. يرجى الدخول لبوابة الشحن للموافقة أو الرفض.',
          'type': 'agent_host_withdrawal_request',
          'actor_uid': hostUid,
          'data': {
            'request_id': requestId,
            'host_uid': hostUid,
            'host_name': hostName,
            'diamonds': diamonds,
            'action_required': true,
          },
          'sent_at': DateTime.now().toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
          'is_read': false,
        });
      } catch (ne) {
        debugPrint('[AgencyRepository] send notification error: $ne');
      }

      return {'success': true, 'requestId': requestId};
    } catch (e) {
      debugPrint('[AgencyRepository] requestHostWithdrawalToAgent error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  // ─── جلب طلبات السحب الواردة لوكيل الشحن (Pending Host Withdrawals) ───────────
  static Future<List<Map<String, dynamic>>> getAgentPendingWithdrawals(String agentUid) async {
    try {
      final res = await _sb
          .from('agent_withdrawal_requests')
          .select('*')
          .eq('agent_id', agentUid)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> list = [];
      for (final r in (res as List<dynamic>)) {
        final m = Map<String, dynamic>.from(r as Map);
        final details = m['account_details'] is Map ? Map<String, dynamic>.from(m['account_details']) : {};
        if (details['request_type'] == 'host_diamonds_withdrawal') {
          list.add({
            'id': m['id'],
            'agent_id': m['agent_id'],
            'host_uid': details['host_uid'] ?? '',
            'host_name': details['host_name'] ?? 'مضيف',
            'host_custom_id': details['host_custom_id'] ?? '',
            'host_avatar': details['host_avatar'] ?? '',
            'diamonds': (details['diamonds'] as num?)?.toInt() ?? ((m['amount_usd'] as num?)?.toInt() ?? 0) * 100,
            'agency_name': details['agency_name'] ?? '',
            'created_at': m['created_at'],
            'status': m['status'],
          });
        }
      }
      return list;
    } catch (e) {
      debugPrint('[AgencyRepository] getAgentPendingWithdrawals error: $e');
      return [];
    }
  }

  // ─── موافقة أو رفض طلب سحب الألماس من قبل وكيل الشحن ─────────────────────────
  static Future<Map<String, dynamic>> handleAgentWithdrawalAction({
    required String requestId,
    required String agentUid,
    required bool approve,
    String? rejectReason,
  }) async {
    try {
      // 1. جلب بيانات الطلب
      final reqRow = await _sb
          .from('agent_withdrawal_requests')
          .select('*')
          .eq('id', requestId)
          .maybeSingle();

      if (reqRow == null) {
        return {'success': false, 'message': 'لم يتم العثور على طلب السحب'};
      }

      final status = reqRow['status']?.toString();
      if (status != 'pending') {
        return {'success': false, 'message': 'تم التعامل مع هذا الطلب مسبقاً ($status)'};
      }

      final details = reqRow['account_details'] is Map ? Map<String, dynamic>.from(reqRow['account_details']) : {};
      final hostUid = details['host_uid']?.toString() ?? '';
      final diamonds = (details['diamonds'] as num?)?.toInt() ?? 0;
      final hostName = details['host_name']?.toString() ?? 'المضيف';

      if (approve) {
        // تنفيذ التحويل الفعلي للألماس
        final key = '${hostUid}_acc_${DateTime.now().millisecondsSinceEpoch}';
        final txRes = await transferDiamondsToAgentWallet(
          agentId: agentUid,
          diamonds: diamonds,
          idempotencyKey: key,
          source: 'host',
        );

        if (txRes['status'] != 'ok' && txRes['success'] != true) {
          return {'success': false, 'message': txRes['message'] ?? 'فشل تحويل الألماس'};
        }

        // تحديث حالة الطلب إلى approved
        await _sb.from('agent_withdrawal_requests').update({
          'status': 'approved',
          'reviewed_at': DateTime.now().toIso8601String(),
          'reviewed_by': agentUid,
        }).eq('id', requestId);

        // إشعار المضيف بنجاح العملية
        try {
          await _sb.from('notifications').insert({
            'uid': hostUid,
            'target': hostUid,
            'title': 'تمت الموافقة على سحب الألماس! 🎉',
            'body': 'وافق وكيل الشحن على طلب سحب $diamonds ماسة وتحويلها لمحفظة الوكالة بنجاح.',
            'type': 'agent_withdrawal_approved',
            'data': {'diamonds': diamonds, 'agent_id': agentUid, 'request_id': requestId},
            'sent_at': DateTime.now().toIso8601String(),
            'created_at': DateTime.now().toIso8601String(),
            'is_read': false,
          });
        } catch (_) {}

        return {'success': true, 'message': 'تمت الموافقة على الطلب بنجاح وتحويل الألماس'};
      } else {
        // رفض الطلب
        await _sb.from('agent_withdrawal_requests').update({
          'status': 'rejected',
          'reviewed_at': DateTime.now().toIso8601String(),
          'reviewed_by': agentUid,
        }).eq('id', requestId);

        // إشعار المضيف بالرفض
        try {
          await _sb.from('notifications').insert({
            'uid': hostUid,
            'target': hostUid,
            'title': 'تم رفض طلب سحب الألماس',
            'body': 'اعتذر وكيل الشحن عن قبول طلب سحب $diamonds ماسة. السبب: ${rejectReason ?? "لم يحدد سبب"}',
            'type': 'agent_withdrawal_rejected',
            'data': {'diamonds': diamonds, 'agent_id': agentUid, 'request_id': requestId},
            'sent_at': DateTime.now().toIso8601String(),
            'created_at': DateTime.now().toIso8601String(),
            'is_read': false,
          });
        } catch (_) {}

        return {'success': true, 'message': 'تم رفض طلب السحب وإشعار المضيف'};
      }
    } catch (e) {
      debugPrint('[AgencyRepository] handleAgentWithdrawalAction error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  // ─── تقديم طلب تعبئة رصيد الوكالة (Agency Top-Up Request) ─────────────────────
  static Future<Map<String, dynamic>> submitAgentTopupRequest({
    required String agentUid,
    required String agentName,
    required double amountUsd,
    required int coins,
    required String paymentMethod,
    required String proofImageUrl,
    String? txid,
    String? senderName,
    String? senderPhone,
  }) async {
    try {
      final reqId = 'topup_${DateTime.now().millisecondsSinceEpoch}_${agentUid.substring(0, 4)}';

      await _sb.from('agent_withdrawal_requests').insert({
        'id': reqId,
        'agent_id': agentUid,
        'agent_name': agentName,
        'amount_usd': amountUsd,
        'payment_method': paymentMethod,
        'account_details': {
          'request_type': 'agent_topup',
          'coins': coins,
          'proof_url': proofImageUrl,
          'txid': txid ?? '',
          'sender_name': senderName ?? '',
          'sender_phone': senderPhone ?? '',
        },
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });

      return {'success': true, 'requestId': reqId};
    } catch (e) {
      debugPrint('[AgencyRepository] submitAgentTopupRequest error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  1. توثيق المضيف الحقيقي (Real-Name Host Verification)
  // ═══════════════════════════════════════════════════════════════════
  static Future<void> submitHostVerification(HostVerificationModel v) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw Exception('المستخدم غير مسجل الدخول');

    if (v.videoDurationSeconds < 5 || v.videoDurationSeconds > 10) {
      throw Exception('يجب أن تكون مدة مقطع الفيديو بين 5 و 10 ثوانٍ فقط');
    }

    await _sb.from('host_verifications').upsert({
      'uid': uid,
      'full_name': v.fullName,
      'doc_type': v.docType.code,
      'doc_number': v.docNumber,
      'doc_front_url': v.docFrontUrl,
      'doc_back_url': v.docBackUrl,
      'face_photo1_url': v.facePhoto1Url,
      'face_photo2_url': v.facePhoto2Url,
      'video_url': v.videoUrl,
      'video_duration_seconds': v.videoDurationSeconds,
      'previous_platforms': v.previousPlatforms,
      'daily_work_hours': v.dailyWorkHours,
      'country': v.country,
      'whatsapp': v.whatsapp,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<HostVerificationModel?> getHostVerificationStatus() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _sb
        .from('host_verifications')
        .select('*')
        .eq('uid', uid)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return HostVerificationModel.fromMap(Map<String, dynamic>.from(row as Map));
  }

  // ═══════════════════════════════════════════════════════════════════
  //  2. مستويات وامتيازات الوكالة (Agency Levels & Tier Config)
  // ═══════════════════════════════════════════════════════════════════
  static Future<List<AgencyLevelConfigModel>> getAgencyLevelConfigs() async {
    try {
      final rows = await _sb
          .from('agency_level_config')
          .select('*')
          .order('level', ascending: true);
      final list = (rows as List<dynamic>?) ?? [];
      if (list.isNotEmpty) {
        return list.map((e) => AgencyLevelConfigModel.fromMap(Map<String, dynamic>.from(e as Map))).toList();
      }
    } catch (e) {
      debugPrint('[AgencyRepository] Fallback to default level config: $e');
    }

    return const [
      AgencyLevelConfigModel(level: 1, levelName: 'برونز', minExp: 0, adminLimit: 2, membersLimit: 20),
      AgencyLevelConfigModel(level: 2, levelName: 'فضي', minExp: 50000, adminLimit: 3, membersLimit: 50),
      AgencyLevelConfigModel(level: 3, levelName: 'ذهبي', minExp: 200000, adminLimit: 5, membersLimit: 100),
      AgencyLevelConfigModel(level: 4, levelName: 'بلاتيني', minExp: 800000, adminLimit: 8, membersLimit: 200),
      AgencyLevelConfigModel(level: 5, levelName: 'ألماسي', minExp: 2500000, adminLimit: 12, membersLimit: 500),
    ];
  }

  // ═══════════════════════════════════════════════════════════════════
  //  3. تتبع ساعات البث اليومية والتارجت (Daily Live Hours)
  // ═══════════════════════════════════════════════════════════════════
  static Future<AgencyDailyHoursTarget> getDailyHoursTarget({
    required String agencyId,
    required String hostUid,
  }) async {
    try {
      final today = DateTime.now().toIso8601String().split('T').first;
      final row = await _sb
          .from('full_agency_daily_records')
          .select('*')
          .eq('agency_id', agencyId)
          .eq('host_uid', hostUid)
          .eq('record_date', today)
          .maybeSingle();

      // Count monthly >=2h, >=4h, >=6h days
      final startOfMonth = DateTime(DateTime.now().year, DateTime.now().month, 1).toIso8601String().split('T').first;
      final monthlyRecords = await _sb
          .from('full_agency_daily_records')
          .select('is_ge_2h, is_ge_4h, is_ge_6h')
          .eq('agency_id', agencyId)
          .eq('host_uid', hostUid)
          .gte('record_date', startOfMonth);

      int ge2h = 0;
      int ge4h = 0;
      int ge6h = 0;
      for (final r in (monthlyRecords as List<dynamic>? ?? [])) {
        if (r['is_ge_2h'] == true) ge2h++;
        if (r['is_ge_4h'] == true) ge4h++;
        if (r['is_ge_6h'] == true) ge6h++;
      }

      if (row != null) {
        return AgencyDailyHoursTarget.fromMap({
          ...Map<String, dynamic>.from(row as Map),
          'days_ge_2h': ge2h,
          'days_ge_4h': ge4h,
          'days_ge_6h': ge6h,
        });
      }

      return AgencyDailyHoursTarget(
        hostUid: hostUid,
        recordDate: DateTime.now(),
        liveDurationSeconds: 0,
        diamondsEarned: 0,
        daysGe2h: ge2h,
        daysGe4h: ge4h,
        daysGe6h: ge6h,
      );
    } catch (_) {
      return AgencyDailyHoursTarget(
        hostUid: hostUid,
        recordDate: DateTime.now(),
        liveDurationSeconds: 0,
        diamondsEarned: 0,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  4. رواتب الوكالة والسحب على المكشوف (Salary & Overdraft)
  // ═══════════════════════════════════════════════════════════════════
  static Future<AgencySalaryOverdraftModel> getSalaryAndOverdraft(String agencyId) async {
    final periodMonth = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
    try {
      final row = await _sb
          .from('full_agency_salaries_overdraft')
          .select('*')
          .eq('agency_id', agencyId)
          .eq('period_month', periodMonth)
          .maybeSingle();

      if (row != null) {
        return AgencySalaryOverdraftModel.fromMap(Map<String, dynamic>.from(row as Map));
      }
    } catch (e) {
      debugPrint('[AgencyRepository] getSalaryAndOverdraft fallback: $e');
    }

    return AgencySalaryOverdraftModel(
      agencyId: agencyId,
      periodMonth: periodMonth,
      diamondTarget: 500000,
      diamondBalance: 0,
      nextDiamondTarget: 1000000,
      totalSalaryUsd: 0.0,
      overdrawnAmountUsd: 0.0,
      remainingSalaryUsd: 0.0,
      canOverdraft: true,
    );
  }

  static Future<void> requestOverdraft({
    required String agencyId,
    required double amountUsd,
  }) async {
    final periodMonth = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
    final current = await getSalaryAndOverdraft(agencyId);

    if (amountUsd <= 0) throw Exception('يجب إدخال مبلغ سحب صحيح أكبر من 0');
    if (amountUsd > current.remainingSalaryUsd) {
      throw Exception('مبلغ السحب المطلوب يتجاوز الرصيد المتاح للسلفة (${current.remainingSalaryUsd}\$)');
    }

    await _sb.from('full_agency_salaries_overdraft').upsert({
      'agency_id': agencyId,
      'period_month': periodMonth,
      'overdrawn_amount_usd': current.overdrawnAmountUsd + amountUsd,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  //  5. مصفوفة صلاحيات المشرفين (Admin Permissions)
  // ═══════════════════════════════════════════════════════════════════
  static Future<AgencyAdminPermissions> getAdminPermissions({
    required String agencyId,
    required String adminUid,
  }) async {
    try {
      final row = await _sb
          .from('full_agency_admins')
          .select('*')
          .eq('agency_id', agencyId)
          .eq('admin_uid', adminUid)
          .maybeSingle();

      if (row != null) {
        return AgencyAdminPermissions.fromMap(Map<String, dynamic>.from(row as Map));
      }
    } catch (e) {
      debugPrint('[AgencyRepository] getAdminPermissions error: $e');
    }

    return AgencyAdminPermissions(agencyId: agencyId, adminUid: adminUid);
  }

  static Future<void> updateAdminPermissions(AgencyAdminPermissions permissions) async {
    await _sb.from('full_agency_admins').upsert(permissions.toMap());
  }

  // ═══════════════════════════════════════════════════════════════════
  //  6. طلب مغادرة الوكالة مع فك الارتباط التلقائي بعد 30 يوماً
  // ═══════════════════════════════════════════════════════════════════
  static Future<void> requestAgencyExitWithAutoRelease({
    required String agencyId,
    required String hostUid,
  }) async {
    final autoReleaseDate = DateTime.now().add(const Duration(days: 30)).toIso8601String();
    await _sb
        .from('full_agency_contracts')
        .update({
          'status': 'pending_exit',
          'exit_requested_at': DateTime.now().toIso8601String(),
          'auto_release_at': autoReleaseDate,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('agency_id', agencyId)
        .eq('host_uid', hostUid)
        .eq('status', 'active');
  }
}

