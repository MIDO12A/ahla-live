import '../../../core/supabase_compat.dart';

import '../../../core/utils/server_time_service.dart';
import 'agency_models.dart';
import 'package:flutter/foundation.dart';

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
    final row = await _sb
        .from('host_agencies')
        .select('id, agency_public_id, name, description, photo_url, country, tier, total_diamonds_monthly, total_diamonds_cumulative, member_count, is_hall_of_fame, status')
        .eq('id', agencyId)
        .maybeSingle();
    if (row == null) return null;

    // Check if current user is a member or has pending request
    final uid = _sb.auth.currentUser?.id;
    bool isMember = false;
    bool canJoin = false;
    bool hasPendingRequest = false;
    if (uid != null) {
      final memberRow = await _sb
          .from('host_agency_members')
          .select('status')
          .eq('agency_id', agencyId)
          .eq('user_id', uid)
          .maybeSingle();
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
      ...Map<String, dynamic>.from(row as Map),
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
      // Fallback: insert directly into host_agency_members
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) throw Exception('يجب تسجيل الدخول أولاً');
      await _sb.from('host_agency_members').insert({
        'agency_id': agencyId,
        'user_id': uid,
        'role': 'host',
        'status': 'pending',
      });
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

    final resp = await _sb.rpc('get_host_dashboard_v2', params: {
      'p_user_id': uid,
    });
    if (resp == null) return null;
    final data = Map<String, dynamic>.from(resp as Map);
    if (data['status'] != 'ok') return null;

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

  /// تحويل ألماس لمحفظة وكيل الشحن الجديدة (host_transfer_diamonds_to_agent)
  /// p_source: 'host' للمضيف، 'agency_owner' لمالك الوكالة
  static Future<Map<String, dynamic>> transferDiamondsToAgentWallet({
    required String agentId,
    required int    diamonds,
    required String idempotencyKey,
    String source = 'host',
  }) async {
    final resp = await _sb.rpc('host_transfer_diamonds_to_agent', params: {
      'p_agent_id':         agentId,
      'p_diamonds':         diamonds,
      'p_idempotency_key':  idempotencyKey,
      'p_source':           source,
    });
    return Map<String, dynamic>.from(resp as Map);
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
    final resp = await _sb.rpc('agency_get_owner_dashboard', params: {
      'p_agency_id': agencyId,
    });
    if (resp == null) return null;
    return AgencyOwnerDashboard.fromMap(Map<String, dynamic>.from(resp as Map));
  }

  /// تبادل ألماس الوكالة → كوينز شخصية للمالك
  static Future<Map<String, dynamic>> ownerExchangeDiamonds({
    required String agencyId,
    required int    diamondsAmount,
    required String idempotencyKey,
  }) async {
    final resp = await _sb.rpc('agency_owner_exchange_diamonds', params: {
      'p_agency_id':       agencyId,
      'p_diamonds_amount': diamondsAmount,
      'p_idempotency_key': idempotencyKey,
    });
    return Map<String, dynamic>.from(resp as Map);
  }

  /// طلب سحب نقدي من محفظة الوكالة (يتطلب KYC)
  static Future<Map<String, dynamic>> ownerRequestWithdrawal({
    required String agencyId,
    required int    diamondsAmount,
    required String paymentMethod,
    required Map<String, dynamic> paymentDetails,
  }) async {
    final resp = await _sb.rpc('agency_owner_request_withdrawal', params: {
      'p_agency_id':       agencyId,
      'p_diamonds_amount': diamondsAmount,
      'p_payment_method':  paymentMethod,
      'p_payment_details': paymentDetails,
    });
    return Map<String, dynamic>.from(resp as Map);
  }

  // ─── البحث عن وكلاء الشحن ────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> searchRechargeAgents(String query) async {
    if (query.trim().length < 2) return [];
    final resp = await _sb
        .from('profiles')
        .select('id, display_name, avatar_url, kayan_id')
        .eq('is_recharge_agent', true)
        .or('display_name.ilike.%$query%,kayan_id.ilike.%$query%')
        .limit(10);
    return (resp as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
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

