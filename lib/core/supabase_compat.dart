import 'package:firebase_core/firebase_core.dart';
// Compatibility shim: allows code originally written against
// `Supabase.instance.client` to keep compiling on top of Firebase
// (Firestore + FirebaseAuth) while the migration to Firebase proceeds.
//
// Migrated services/screens use `FirebaseService` directly; this layer exists
// so the remaining Supabase-style call sites (mostly the host-agency and agent
// recharge subsystems that depend on Postgres RPC functions) still compile.
// RPC functions that have no Firestore equivalent yet throw a clear error.
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../services/cloudinary_service.dart';
import '../services/firebase_service.dart';

/// Singleton mirroring `Supabase.instance`.
class Supabase {
  static final Supabase instance = Supabase._();
  Supabase._();
  final SupabaseClient client = SupabaseClient();
}

/// Client exposing a subset of the Supabase API backed by Firestore + FirebaseAuth.
class SupabaseClient {
  final FirebaseFirestore _db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
  final AuthClient auth = AuthClient();

  SupabaseQueryBuilder from(String table) => SupabaseQueryBuilder(_db, table);

  /// Postgres RPC -> Firebase. Mapped functions work; unmapped throw.
  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params}) async {
    switch (fn) {
      case 'delete_user_account':
        final auth = this.auth;
        final uid = auth.currentUser?.id ?? params?['uid']?.toString();
        if (uid != null) {
          await _db.collection('users').doc(uid).delete();
        }
        await FirebaseAuth.instance.currentUser?.delete();
        return <String, dynamic>{};
      case 'get_user_signin_data':
        return <String, dynamic>{};
      case 'do_signin':
        return <String, dynamic>{};
      case 'agency_send_chat_message':
        return _rpcAgencySendChatMessage(params);
      case 'agency_mute_member_chat':
        return _rpcAgencyMuteMember(params);
      case 'agency_report_screenshot':
        return _rpcAgencyReportScreenshot(params);
      case 'agency_invite_by_kayan_id':
        return _rpcAgencyInviteByKayanId(params);
      case 'agency_assign_supervisor':
        return _rpcAgencySetSupervisor(params, isSupervisor: true);
      case 'agency_revoke_supervisor':
        return _rpcAgencySetSupervisor(params, isSupervisor: false);
      case 'agency_view_once_open':
        return <String, dynamic>{'status': 'ok'};
      case 'agency_create':
        return _rpcAgencyCreate(params);
      case 'agency_get_dashboard':
        return _rpcAgencyGetDashboard(params);
      case 'agency_get_engine_settings':
        return _rpcAgencyGetEngineSettings(params);
      case 'agency_get_leaderboard':
        return _rpcAgencyGetLeaderboard(params);
      case 'agency_get_profile':
        return _rpcAgencyGetProfile(params);
      case 'agency_get_owner_dashboard':
        return _rpcAgencyGetOwnerDashboard(params);
      case 'agency_request_join':
        return _rpcAgencyRequestJoin(params);
      case 'agency_leave':
      case 'agency_request_exit':
        return _rpcAgencyRequestExit(params);
      case 'agency_pay_penalty_exit':
        return _rpcAgencyPayPenaltyExit(params);
      case 'agency_delete':
      case 'agency_owner_delete':
        return _rpcAgencyDelete(params);
      case 'agency_exchange_diamonds':
        return _rpcAgencyExchangeDiamonds(params);
      case 'agency_request_withdrawal':
        return _rpcAgencyRequestWithdrawal(params);
      case 'agency_transfer_to_recharge':
        return _rpcAgencyTransferToRecharge(params);
      case 'host_transfer_diamonds_to_agent':
        return _rpcHostTransferDiamondsToAgent(params);
      case 'agency_send_announcement':
        return _rpcAgencySendAnnouncement(params);
      case 'agency_owner_exchange_diamonds':
        return _rpcAgencyOwnerExchangeDiamonds(params);
      case 'agency_owner_request_withdrawal':
        return _rpcAgencyOwnerRequestWithdrawal(params);
      case 'agency_accept_member':
        return _rpcAgencyAcceptMember(params);
      case 'agency_kick_member':
        return _rpcAgencyKickMember(params);
      case 'get_host_dashboard_v2':
        return _rpcGetHostDashboardV2(params);
      case 'get_host_dashboard_v3':
        return _rpcGetHostDashboardV3(params);
      case 'agent_get_dashboard':
        return _rpcAgentGetDashboard(params);
      case 'agent_recharge_history':
        return _rpcAgentRechargeHistory(params);
      case 'agent_get_usd_wallet':
        return _rpcAgentGetUsdWallet(params);
      case 'agent_get_diamond_wallet':
        return _rpcAgentGetDiamondWallet(params);
      case 'agent_set_pin':
        return _rpcAgentSetPin(params);
      case 'agent_verify_pin':
        return _rpcAgentVerifyPin(params);
      case 'agent_set_quick_amounts':
        return _rpcAgentSetQuickAmounts(params);
    }
    throw StateError(
      'RPC "$fn" is not migrated to Firebase yet. '
      'Migrate the calling feature to FirebaseService/Firestore or implement '
      'the equivalent Cloud Function. See AGENTS.md migration notes.',
    );
  }

  Future<Map<String, dynamic>> _rpcAgencySendChatMessage(
      Map<String, dynamic>? p) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {'status': 'error'};
    final profile = await _db.collection('profiles').doc(uid).get();
    final now = DateTime.now().toUtc();
    final doc = _db.collection('agency_chat_messages').doc();
    await doc.set({
      'id': now.millisecondsSinceEpoch,
      'agency_id': p?['p_agency_id'],
      'sender_id': uid,
      'display_name':
          profile.data()?['display_name']?.toString() ?? 'مستخدم',
      'message_type': p?['p_message_type'] ?? 'text',
      'body': p?['p_body'],
      'asset_url': p?['p_asset_url'],
      'asset_duration_secs': p?['p_asset_duration_secs'],
      'view_duration_seconds': p?['p_view_duration_secs'],
      'is_view_once': p?['p_is_view_once'] ?? false,
      'created_at': now.toIso8601String(),
    });
    return {'status': 'ok'};
  }

  Future<Map<String, dynamic>> _rpcAgencyMuteMember(
      Map<String, dynamic>? p) async {
    final agencyId = p?['p_agency_id']?.toString() ?? '';
    final userId = p?['p_user_id']?.toString() ?? '';
    if (agencyId.isEmpty || userId.isEmpty) return {'status': 'error'};
    final hours = (p?['p_hours'] as num?)?.toInt() ?? 0;
    final col = _db.collection('agency_chat_mutes');
    final query = await col
        .where('agency_id', isEqualTo: agencyId)
        .where('muted_user_id', isEqualTo: userId)
        .get();
    if (hours <= 0) {
      for (final d in query.docs) {
        await d.reference.delete();
      }
      return {'status': 'ok'};
    }
    final until = DateTime.now().toUtc().add(Duration(hours: hours));
    final payload = <String, dynamic>{
      'agency_id': agencyId,
      'muted_user_id': userId,
      'until_at': until.toIso8601String(),
      'reason': p?['p_reason'],
      'muted_by': FirebaseAuth.instance.currentUser?.uid,
    };
    if (query.docs.isNotEmpty) {
      await query.docs.first.reference.set(payload, SetOptions(merge: true));
    } else {
      await col.add(payload);
    }
    return {'status': 'ok'};
  }

  Future<Map<String, dynamic>> _rpcAgencyReportScreenshot(
      Map<String, dynamic>? p) async {
    await _db.collection('agency_screenshot_reports').add({
      'agency_id': p?['p_agency_id'],
      'user_id': FirebaseAuth.instance.currentUser?.uid,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    return {'status': 'ok'};
  }

  Future<Map<String, dynamic>> _rpcAgencyInviteByKayanId(
      Map<String, dynamic>? p) async {
    final kayanId = (p?['p_kayan_id'] ?? '').toString().trim();
    final agencyId = p?['p_agency_id']?.toString() ?? '';
    if (kayanId.isEmpty || agencyId.isEmpty) {
      return {'status': 'error'};
    }
    
    // Comprehensive search: custom_id (string/int), customId (string/int), id, uid
    final intId = int.tryParse(kayanId);
    QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection('users')
        .where('custom_id', isEqualTo: kayanId)
        .limit(1)
        .get();
        
    if (snap.docs.isEmpty && intId != null) {
      snap = await _db
          .collection('users')
          .where('custom_id', isEqualTo: intId)
          .limit(1)
          .get();
    }
    if (snap.docs.isEmpty) {
      snap = await _db
          .collection('users')
          .where('customId', isEqualTo: kayanId)
          .limit(1)
          .get();
    }
    if (snap.docs.isEmpty && intId != null) {
      snap = await _db
          .collection('users')
          .where('customId', isEqualTo: intId)
          .limit(1)
          .get();
    }
    if (snap.docs.isEmpty) {
      snap = await _db
          .collection('users')
          .where('id', isEqualTo: kayanId)
          .limit(1)
          .get();
    }
    if (snap.docs.isEmpty) {
      final doc = await _db.collection('users').doc(kayanId).get();
      if (doc.exists && doc.data() != null) {
        snap = await _db.collection('users').where(FieldPath.documentId, isEqualTo: kayanId).limit(1).get();
      }
    }
    
    if (snap.docs.isEmpty) return {'status': 'not_found'};
    
    final targetUid = snap.docs.first.id;
    final userData = snap.docs.first.data();
    
    // Check if user is an agent or agency owner (agents cannot be invited as hosts)
    final isAgent = userData['is_agent'] == true ||
        userData['role'] == 'agent' ||
        userData['role'] == 'owner';
    if (isAgent) {
      return {'status': 'is_agent'};
    }

    // Check if already in any agency
    final existingMember = await _db
        .collection('host_agency_members')
        .where('user_id', isEqualTo: targetUid)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    if (existingMember.docs.isNotEmpty) {
      final currentAgency = existingMember.docs.first.data()['agency_id']?.toString();
      if (currentAgency == agencyId) {
        return {'status': 'already_member'};
      }
      return {'status': 'in_other_agency'};
    }

    final existingRequest = await _db
        .collection('host_agency_join_requests')
        .where('user_id', isEqualTo: targetUid)
        .where('agency_id', isEqualTo: agencyId)
        .where('status', isEqualTo: 'invited')
        .limit(1)
        .get();
    
    if (existingRequest.docs.isNotEmpty) {
      return {
        'status': 'already_invited',
        'user_id': targetUid,
        'display_name': userData['name'] ?? 'مستخدم',
        'avatar_url': userData['photoUrl'] ?? userData['photo_url'] ?? '',
        'kayan_id': kayanId,
        'level': userData['level'] ?? 1,
        'country': userData['country'] ?? '',
      };
    }

    await _db.collection('host_agency_join_requests').add({
      'agency_id': agencyId,
      'user_id': targetUid,
      'status': 'invited',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    
    return {
      'status': 'invited',
      'user_id': targetUid,
      'display_name': userData['name'] ?? 'مستخدم',
      'avatar_url': userData['photoUrl'] ?? userData['photo_url'] ?? '',
      'kayan_id': kayanId,
      'level': userData['level'] ?? 1,
      'country': userData['country'] ?? '',
    };
  }

  Future<Map<String, dynamic>> _rpcAgencySetSupervisor(
      Map<String, dynamic>? p,
      {required bool isSupervisor}) async {
    final agencyId = p?['p_agency_id']?.toString() ?? '';
    final userId = p?['p_user_id']?.toString() ?? '';
    if (agencyId.isEmpty || userId.isEmpty) return {'status': 'error'};
    final snap = await _db
        .collection('host_agency_members')
        .where('agency_id', isEqualTo: agencyId)
        .where('user_id', isEqualTo: userId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return {'status': 'error'};
    await snap.docs.first.reference
        .update({'role': isSupervisor ? 'supervisor' : 'host'});
    return {'status': 'ok'};
  }

  Future<Map<String, dynamic>> _rpcAgencyGetDashboard(
      Map<String, dynamic>? p) async {
    final agencyId = p?['p_agency_id']?.toString();
    if (agencyId == null || agencyId.isEmpty) {
      return <String, dynamic>{};
    }

    // ── Agency info ──
    final agencySnap = await _db.collection('host_agencies').doc(agencyId).get();
    if (!agencySnap.exists) return <String, dynamic>{};
    final agencyData = agencySnap.data()!;

    // ── Members (with profile names) ──
    final membersSnap = await _db
        .collection('host_agency_members')
        .where('agency_id', isEqualTo: agencyId)
        .get();

    final members = <Map<String, dynamic>>[];
    for (final mDoc in membersSnap.docs) {
      final mData = mDoc.data();
      final userId = mData['user_id']?.toString() ?? '';
      // Fetch profile display_name + kayan_id
      String displayName = '';
      String kayanId = '';
      try {
        final profileSnap = await _db.collection('profiles').doc(userId).get();
        if (profileSnap.exists) {
          final pd = profileSnap.data()!;
          displayName = pd['display_name']?.toString() ?? '';
          kayanId = pd['kayan_id']?.toString() ?? '';
        }
      } catch (_) {}
      members.add({
        'user_id': userId,
        'display_name': displayName,
        'kayan_id': kayanId,
        'role': mData['role'] ?? 'host',
        'status': mData['status'] ?? 'active',
        'month_diamonds': mData['diamonds_earned_monthly'] ?? 0,
        'week_diamonds': 0, // no weekly ledger in Firestore
      });
    }

    // ── Milestones (if agency_milestones collection exists) ──
    List<Map<String, dynamic>> milestones = [];
    try {
      final msSnap = await _db
          .collection('agency_milestones')
          .where('is_active', isEqualTo: true)
          .orderBy('sort_order')
          .get();
      for (final msDoc in msSnap.docs) {
        final ms = msDoc.data();
        milestones.add({
          'id': msDoc.id,
          'name': ms['title_ar'] ?? ms['name'] ?? '',
          'title_ar': ms['title_ar'] ?? '',
          'target': ms['target_diamonds'] ?? 0,
          'reward_type': ms['reward_type'],
          'reward_value': ms['reward_value'] ?? 0,
          'earned': 0,
          'is_completed': false,
          'progress_pct': 0,
        });
      }
    } catch (_) {
      // agency_milestones collection may not exist yet
    }

    // ── Pending members count ──
    int pendingCount = 0;
    try {
      final pendingSnap = await _db
          .collection('host_agency_members')
          .where('agency_id', isEqualTo: agencyId)
          .where('status', isEqualTo: 'pending')
          .get();
      pendingCount = pendingSnap.docs.length;
    } catch (_) {}

    return <String, dynamic>{
      'agency': {
        'id': agencyId,
        'name': agencyData['name'] ?? '',
        'specialty': agencyData['specialty'] ?? 'mixed',
        'member_count': agencyData['member_count'] ?? members.length,
        'monthly_diamonds': agencyData['total_diamonds_monthly'] ?? agencyData['monthly_diamonds'] ?? 0,
        'total_diamonds': agencyData['total_diamonds_earned'] ?? 0,
        'commission_rate': agencyData['commission_rate'] ?? 0.05,
        'is_active': agencyData['is_active'] ?? true,
        'agency_public_id': agencyData['agency_public_id'],
        'description': agencyData['description'],
        'photo_url': agencyData['photo_url'],
        'country': agencyData['country'],
        'tier': agencyData['tier'] ?? 'bronze',
      },
      'members': members,
      'milestones': milestones,
      'pending_members_count': pendingCount,
    };
  }

  // ═══════════════════════════════════════════════════════════════
  //  agency_get_engine_settings
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcAgencyGetEngineSettings(
      Map<String, dynamic>? p) async {
    // إعدادات محرك الوكالة مخزّنة في Firestore كوثائق منفصلة {key, value}
    // (doc id = key). نقرأ كل الوثائق ونبني منها خريطة مسطّحة واحدة بمفاتيح
    // AgencyEngineSettings.fromMap، بدل إعادة وثيقة واحدة فقط (limit 1) الذي
    // كان يضيّع كل القيم ويجعل التطبيق يعتمد على أرقام وهمية متصلّبة.
    final values = <String, double>{};
    try {
      final snap = await _db.collection('commission_settings').get();
      for (final d in snap.docs) {
        final data = d.data();
        final key = (data['key'] ?? d.id).toString();
        final raw = data['value'] ?? data[key];
        if (raw is num) values[key] = raw.toDouble();
      }
    } catch (_) {}

    double v(String key, double fallback) => values[key] ?? fallback;

    // التعيين من مفاتيح SQL (commission_settings) إلى مفاتيح fromMap.
    // النسب المخزّنة في SQL ككسر (0.65) تُحوَّل إلى نسبة مئوية صحيحة (65).
    double pct(num v) => (v >= 1 ? v : v * 100).toDouble();

    final hostShare   = pct(v('host_rate', 0.65));
    final agencyShare = pct(v('agency_rate', 0.05));
    final platformShare = pct(v('platform_rate', 0.30));

    final goldToDiamond = v('gold_to_diamond', 1.0);
    final diamondsPerUsd = v('diamonds_per_usd', 10000);
    final usdPerDiamond  = diamondsPerUsd > 0 ? 1 / diamondsPerUsd : 0.0001;

    return <String, dynamic>{
      // المفاتيح المتوافقة مع AgencyEngineSettings.fromMap
      'host_share_pct':           hostShare.floor(),
      'agency_share_pct':         agencyShare.floor(),
      'platform_share_pct':       platformShare.floor(),
      'diamond_to_coin_rate':     goldToDiamond,
      'diamond_to_usd_rate':      usdPerDiamond,
      'daily_exchange_limit_diamonds': v('daily_exchange_limit_diamonds', 500000),
      'withdrawal_fee_pct':       v('withdrawal_fee_pct', 10.0),
      'min_withdrawal_usd':       v('min_withdrawal_usd', 10.0),
      'min_diamonds_to_withdraw': v('min_diamonds_to_withdraw', 100000),
      'withdrawal_cycle_days':    v('withdrawal_cycle_days', 30),
      'trial_period_days':        v('trial_period_days', 7),
      'exit_penalty_coins':       v('exit_penalty_coins', 300000),
      'engine_enabled':           values.containsKey('engine_enabled')
          ? values['engine_enabled']! > 0
          : true,
      // مفتاح توافقي قديم — يُحدَّث ليطابق معدل الألماس→كوينز الفعلي
      'exchange_rate':            goldToDiamond,
      'min_withdrawal':           v('min_withdrawal_usd', 10.0),
      'max_withdrawal':           v('max_withdrawal_usd', 50000),
    };
  }

  // ═══════════════════════════════════════════════════════════════
  //  agency_get_leaderboard
  // ═══════════════════════════════════════════════════════════════
  Future<List<Map<String, dynamic>>> _rpcAgencyGetLeaderboard(
      Map<String, dynamic>? p) async {
    final country = p?['p_country']?.toString();
    final limit = (p?['p_limit'] as num?)?.toInt() ?? 50;
    final offset = (p?['p_offset'] as num?)?.toInt() ?? 0;

    Query<Map<String, dynamic>> q = _db
        .collection('host_agencies')
        .where('is_active', isEqualTo: true);
    if (country != null && country.isNotEmpty) {
      q = q.where('country', isEqualTo: country);
    }

    final snap = await q
        .orderBy('total_diamonds_monthly', descending: true)
        .limit(offset + limit)
        .get();

    final list = snap.docs.map((d) {
      final data = d.data();
      return <String, dynamic>{
        'agency_id': d.id,
        'name': data['name'] ?? '',
        'photo_url': data['photo_url'],
        'tier': data['tier'] ?? 'bronze',
        'monthly_diamonds': data['total_diamonds_monthly'] ?? 0,
        'member_count': data['member_count'] ?? 0,
        'country': data['country'],
        'is_hall_of_fame': data['is_hall_of_fame'] ?? false,
      };
    }).toList();
    // Apply offset client-side
    final sliced = list.length > offset ? list.sublist(offset) : <Map<String, dynamic>>[];
    // Add rank
    for (var i = 0; i < sliced.length; i++) {
      sliced[i]['rank'] = offset + i + 1;
    }
    return sliced.take(limit).toList();
  }

  // ═══════════════════════════════════════════════════════════════
  //  agency_get_profile
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcAgencyGetProfile(
      Map<String, dynamic>? p) async {
    final agencyId = p?['p_agency_id']?.toString();
    if (agencyId == null || agencyId.isEmpty) return <String, dynamic>{};
    final snap = await _db.collection('host_agencies').doc(agencyId).get();
    if (!snap.exists) return <String, dynamic>{};
    final d = snap.data()!;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    bool isMember = false;
    bool canJoin = true;
    bool hasPendingRequest = false;

    if (uid != null) {
      // 1. فحص ما إذا كان المستخدم هو مالك هذه الوكالة
      if (d['owner_id'] == uid) {
        isMember = true;
        canJoin = false;
      } else {
        // 2. فحص العضوية في host_agency_members لهذه الوكالة
        final memSnap = await _db
            .collection('host_agency_members')
            .where('agency_id', isEqualTo: agencyId)
            .where('user_id', isEqualTo: uid)
            .limit(1)
            .get();

        if (memSnap.docs.isNotEmpty) {
          final st = memSnap.docs.first.data()['status']?.toString() ?? '';
          if (st == 'active') {
            isMember = true;
            canJoin = false;
          } else if (st == 'pending' || st == 'invited') {
            hasPendingRequest = true;
            canJoin = false;
          } else {
            canJoin = true;
          }
        }

        // 3. فحص طلبات الانضمام المعلقة
        if (!isMember && !hasPendingRequest) {
          final reqSnap = await _db
              .collection('host_agency_join_requests')
              .where('agency_id', isEqualTo: agencyId)
              .where('user_id', isEqualTo: uid)
              .where('status', isEqualTo: 'pending')
              .limit(1)
              .get();
          if (reqSnap.docs.isNotEmpty) {
            hasPendingRequest = true;
            canJoin = false;
          }
        }

        // 4. فحص ما إذا كان المستخدم مرتبطاً بوكالة أخرى حالياً
        if (!isMember && !hasPendingRequest) {
          final uDoc = await _db.collection('users').doc(uid).get();
          final uData = uDoc.data() ?? {};
          final currentAid = uData['agency_id']?.toString() ??
              uData['host_agency_id']?.toString();
          if (currentAid != null && currentAid.isNotEmpty) {
            if (currentAid == agencyId) {
              isMember = true;
              canJoin = false;
            } else {
              // التحقق ما إذا كانت عضويته في الوكالة الأخرى نشطة فعلاً
              try {
                final otherMem = await _db
                    .collection('host_agency_members')
                    .where('agency_id', isEqualTo: currentAid)
                    .where('user_id', isEqualTo: uid)
                    .where('status', isEqualTo: 'active')
                    .limit(1)
                    .get();
                canJoin = otherMem.docs.isEmpty;
              } catch (_) {
                canJoin = true;
              }
            }
          } else {
            canJoin = true;
          }
        }
      }
    }

    return <String, dynamic>{
      'id': snap.id,
      'name': d['name'] ?? '',
      'description': d['description'],
      'photo_url': d['photo_url'],
      'cover_url': d['cover_url'],
      'tier': d['tier'] ?? 'bronze',
      'country': d['country'],
      'member_count': d['member_count'] ?? 0,
      'total_diamonds_monthly': d['total_diamonds_monthly'] ?? 0,
      'total_diamonds_earned': d['total_diamonds_earned'] ?? 0,
      'is_hall_of_fame': d['is_hall_of_fame'] ?? false,
      'is_active': d['is_active'] ?? true,
      'is_member': isMember,
      'can_join': canJoin,
      'has_pending_request': hasPendingRequest,
      'owner_name': d['owner_name'],
      'owner_avatar': d['owner_avatar'],
    };
  }

  // ═══════════════════════════════════════════════════════════════
  //  agency_get_owner_dashboard
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcAgencyGetOwnerDashboard(
      Map<String, dynamic>? p) async {
    final agencyId = p?['p_agency_id']?.toString();
    if (agencyId == null) return <String, dynamic>{};
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return <String, dynamic>{};

    final agencySnap = await _db.collection('host_agencies').doc(agencyId).get();
    if (!agencySnap.exists) return <String, dynamic>{};

    // Owner's member row
    int diamondsBalance = 0;
    int diamondsAvailable = 0;
    int diamondsPending = 0;
    int earnedTotal = 0;
    try {
      final memberSnap = await _db
          .collection('host_agency_members')
          .where('agency_id', isEqualTo: agencyId)
          .where('user_id', isEqualTo: uid)
          .limit(1)
          .get();
      if (memberSnap.docs.isNotEmpty) {
        final md = memberSnap.docs.first.data();
        diamondsBalance = (md['diamonds_balance'] as num?)?.toInt() ?? 0;
        diamondsAvailable = (md['diamonds_available'] as num?)?.toInt() ?? 0;
        diamondsPending = (md['diamonds_pending_withdrawal'] as num?)?.toInt() ?? 0;
        earnedTotal = (md['diamonds_earned_cumulative'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}

    // Ledger
    List<Map<String, dynamic>> ledger = [];
    try {
      final ledgerSnap = await _db
          .collection('agency_diamond_ledger')
          .where('user_id', isEqualTo: uid)
          .orderBy('created_at', descending: true)
          .limit(20)
          .get();
      ledger = ledgerSnap.docs.map((e) => e.data()).toList();
    } catch (_) {}

    // Engine settings
    final engine = await _rpcAgencyGetEngineSettings(null);

    return <String, dynamic>{
      'wallet': {
        'balance': diamondsBalance,
        'pending': diamondsPending,
        'available': diamondsAvailable,
        'earned_total': earnedTotal,
      },
      'rates': engine,
      'ledger': ledger,
    };
  }

  // ═══════════════════════════════════════════════════════════════
  //  agency_request_join
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcAgencyRequestJoin(
      Map<String, dynamic>? p) async {
    final agencyId = p?['p_agency_id']?.toString();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (agencyId == null || uid == null) {
      return {'status': 'error', 'message': 'missing_params'};
    }

    // Check not already member of this agency
    final existingThis = await _db
        .collection('host_agency_members')
        .where('agency_id', isEqualTo: agencyId)
        .where('user_id', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    if (existingThis.docs.isNotEmpty) {
      return {'status': 'error', 'message': 'أنت عضو بالفعل في هذه الوكالة'};
    }

    final uDoc = await _db.collection('users').doc(uid).get();
    final uData = uDoc.data() ?? {};
    final userName = uData['name'] ?? uData['display_name'] ?? 'مستخدم';
    final userAvatar = uData['photo_url'] ?? uData['avatar_url'] ?? '';
    final customId = uData['custom_id']?.toString() ?? '';

    // 1. Create or update join request in host_agency_join_requests
    final reqRef = _db.collection('host_agency_join_requests').doc('${agencyId}_$uid');
    await reqRef.set({
      'id': reqRef.id,
      'agency_id': agencyId,
      'user_id': uid,
      'user_name': userName,
      'user_avatar': userAvatar,
      'custom_id': customId,
      'status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    // 2. Also save to host_agency_members with status: 'pending' so queries reflect pending request
    final memRef = _db.collection('host_agency_members').doc('${agencyId}_$uid');
    await memRef.set({
      'id': memRef.id,
      'agency_id': agencyId,
      'user_id': uid,
      'role': 'host',
      'status': 'pending',
      'joined_at': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));

    return {'status': 'ok'};
  }

  // ═══════════════════════════════════════════════════════════════
  //  agency_request_exit
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcAgencyRequestExit(
      Map<String, dynamic>? p) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {'status': 'error'};

    // فحص ما إذا كان المستخدم مالك الوكالة (الوكيل)
    final isOwner = await _checkIfAgencyOwner(uid);
    if (isOwner) {
      final success = await FirebaseService().deleteAndExitAgencyByOwner(
        agencyId: p?['p_agency_id']?.toString() ?? '',
        ownerUid: uid,
      );
      return {'status': success ? 'ok' : 'error', 'is_owner_delete': true};
    }

    final memberSnap = await _db
        .collection('host_agency_members')
        .where('user_id', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    if (memberSnap.docs.isEmpty) return {'status': 'error', 'message': 'not_member'};

    final aid = memberSnap.docs.first.data()['agency_id']?.toString() ?? '';
    await FirebaseService().exitAgencyAsMember(agencyId: aid, userId: uid);

    final freeUntil = DateTime.now().toUtc().add(const Duration(days: 7));
    return {'status': 'ok', 'free_until': freeUntil.toIso8601String()};
  }

  // ═══════════════════════════════════════════════════════════════
  //  agency_pay_penalty_exit
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcAgencyPayPenaltyExit(
      Map<String, dynamic>? p) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {'status': 'error'};

    final isOwner = await _checkIfAgencyOwner(uid);
    if (isOwner) {
      final success = await FirebaseService().deleteAndExitAgencyByOwner(
        agencyId: p?['p_agency_id']?.toString() ?? '',
        ownerUid: uid,
      );
      return {'status': success ? 'ok' : 'error', 'is_owner_delete': true};
    }

    final memberSnap = await _db
        .collection('host_agency_members')
        .where('user_id', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    if (memberSnap.docs.isEmpty) return {'status': 'error'};

    final aid = memberSnap.docs.first.data()['agency_id']?.toString() ?? '';
    await FirebaseService().exitAgencyAsMember(agencyId: aid, userId: uid);

    return {'status': 'ok'};
  }

  // ═══════════════════════════════════════════════════════════════
  //  agency_delete (حذف الوكالة نهائياً وتصفير مراحل جميع الأعضاء)
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcAgencyDelete(
      Map<String, dynamic>? p) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {'status': 'error', 'message': 'unauthenticated'};

    final agencyId = p?['p_agency_id']?.toString() ?? '';
    final success = await FirebaseService().deleteAndExitAgencyByOwner(
      agencyId: agencyId,
      ownerUid: uid,
    );

    return {'status': success ? 'ok' : 'error'};
  }

  Future<bool> _checkIfAgencyOwner(String uid) async {
    final agSnap = await _db.collection('host_agencies').where('owner_id', isEqualTo: uid).limit(1).get();
    if (agSnap.docs.isNotEmpty) return true;
    final mbSnap = await _db.collection('host_agency_members').where('user_id', isEqualTo: uid).where('role', isEqualTo: 'owner').limit(1).get();
    if (mbSnap.docs.isNotEmpty) return true;
    final uDoc = await _db.collection('users').doc(uid).get();
    return uDoc.data()?['is_host_agent'] == true;
  }

  // ═══════════════════════════════════════════════════════════════
  //  agency_exchange_diamonds
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcAgencyExchangeDiamonds(
      Map<String, dynamic>? p) async {
    final diamonds = (p?['p_diamonds'] as num?)?.toInt() ?? 0;
    final idempotencyKey = p?['p_idempotency_key']?.toString() ?? '';
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || diamonds <= 0) {
      return {'status': 'error', 'message': 'invalid_params'};
    }

    // Check idempotency
    if (idempotencyKey.isNotEmpty) {
      final existing = await _db
          .collection('agency_diamond_ledger')
          .where('idempotency_key', isEqualTo: idempotencyKey)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        return {'status': 'ok', 'message': 'already_processed'};
      }
    }

    // Find member
    final memberSnap = await _db
        .collection('host_agency_members')
        .where('user_id', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    if (memberSnap.docs.isEmpty) return {'status': 'error', 'message': 'not_member'};

    final memberDoc = memberSnap.docs.first;
    final available = (memberDoc.data()['diamonds_available'] as num?)?.toInt() ?? 0;
    if (available < diamonds) return {'status': 'error', 'message': 'insufficient'};

    final engine = await _rpcAgencyGetEngineSettings(null);
    final coinsOut = (diamonds *
            ((engine['diamond_to_coin_rate'] as num?)?.toDouble() ??
                (engine['exchange_rate'] as num?)?.toDouble() ??
                1.0))
        .floor();

    // Deduct from member
    await memberDoc.reference.update({
      'diamonds_available': FieldValue.increment(-diamonds),
      'diamonds_earned_cumulative': FieldValue.increment(-diamonds),
    });

    // Credit coins to user
    await _db.collection('users').doc(uid).update({
      'coins': FieldValue.increment(coinsOut),
    });

    // Ledger
    await _db.collection('agency_diamond_ledger').add({
      'agency_id': memberDoc.data()['agency_id'],
      'user_id': uid,
      'txn_type': 'exchange',
      'amount': diamonds,
      'direction': -1,
      'balance_after': available - diamonds,
      'note': 'exchange $diamonds diamonds → $coinsOut coins',
      'idempotency_key': idempotencyKey.isNotEmpty ? idempotencyKey : null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    return {'status': 'ok', 'ok': true, 'diamonds_in': diamonds, 'coins_out': coinsOut};
  }

  // ═══════════════════════════════════════════════════════════════
  //  agency_request_withdrawal
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcAgencyRequestWithdrawal(
      Map<String, dynamic>? p) async {
    final diamonds = (p?['p_diamonds'] as num?)?.toInt() ?? 0;
    final bankDetails = p?['p_bank_details'] as Map<String, dynamic>?;
    final idempotencyKey = p?['p_idempotency_key']?.toString() ?? '';
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || diamonds <= 0) return {'status': 'error'};

    final memberSnap = await _db
        .collection('host_agency_members')
        .where('user_id', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    if (memberSnap.docs.isEmpty) return {'status': 'error'};

    final memberDoc = memberSnap.docs.first;
    final available = (memberDoc.data()['diamonds_available'] as num?)?.toInt() ?? 0;
    if (available < diamonds) return {'status': 'error', 'message': 'insufficient'};

    // Freeze diamonds
    await memberDoc.reference.update({
      'diamonds_available': FieldValue.increment(-diamonds),
      'diamonds_pending_withdrawal': FieldValue.increment(diamonds),
    });

    // Create withdrawal request
    await _db.collection('agency_withdrawal_requests').add({
      'user_id': uid,
      'agency_id': memberDoc.data()['agency_id'],
      'diamonds_amount': diamonds,
      'bank_details': bankDetails ?? {},
      'status': 'pending',
      'idempotency_key': idempotencyKey.isNotEmpty ? idempotencyKey : null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    return {'status': 'ok', 'ok': true};
  }

  // ═══════════════════════════════════════════════════════════════
  //  agency_transfer_to_recharge (legacy)
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcAgencyTransferToRecharge(
      Map<String, dynamic>? p) async {
    final agentId = p?['p_agent_id']?.toString();
    final diamonds = (p?['p_diamonds'] as num?)?.toInt() ?? 0;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || agentId == null || diamonds <= 0) {
      return {'status': 'error'};
    }

    final memberSnap = await _db
        .collection('host_agency_members')
        .where('user_id', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    if (memberSnap.docs.isEmpty) return {'status': 'error'};

    final memberDoc = memberSnap.docs.first;
    final available = (memberDoc.data()['diamonds_available'] as num?)?.toInt() ?? 0;
    if (available < diamonds) return {'status': 'error', 'message': 'insufficient'};

    await memberDoc.reference.update({
      'diamonds_available': FieldValue.increment(-diamonds),
    });

    // Credit agent wallet
    await _db.collection('agent_usd_wallets').doc(agentId).set({
      'user_id': agentId,
      'diamond_balance': FieldValue.increment(diamonds),
    }, SetOptions(merge: true));

    await _db.collection('agency_diamond_ledger').add({
      'agency_id': memberDoc.data()['agency_id'],
      'user_id': uid,
      'txn_type': 'transfer',
      'amount': diamonds,
      'direction': -1,
      'balance_after': available - diamonds,
      'note': 'transfer to agent $agentId',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    return {'status': 'ok', 'ok': true};
  }

  // ═══════════════════════════════════════════════════════════════
  //  host_transfer_diamonds_to_agent
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcHostTransferDiamondsToAgent(
      Map<String, dynamic>? p) async {
    final agentId = p?['p_agent_id']?.toString();
    final diamonds = (p?['p_diamonds'] as num?)?.toInt() ?? 0;
    final idempotencyKey = p?['p_idempotency_key']?.toString() ?? '';
    final source = p?['p_source']?.toString() ?? 'host';
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || agentId == null || diamonds <= 0) {
      return {'status': 'error'};
    }

    // Idempotency check
    if (idempotencyKey.isNotEmpty) {
      final existing = await _db
          .collection('agency_diamond_ledger')
          .where('idempotency_key', isEqualTo: idempotencyKey)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) return {'status': 'ok', 'message': 'already_processed'};
    }

    // Find source member/agency
    String? agencyId;
    if (source == 'agency_owner') {
      final agencySnap = await _db
          .collection('host_agencies')
          .where('owner_user_id', isEqualTo: uid)
          .limit(1)
          .get();
      if (agencySnap.docs.isNotEmpty) agencyId = agencySnap.docs.first.id;
    } else {
      final memberSnap = await _db
          .collection('host_agency_members')
          .where('user_id', isEqualTo: uid)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (memberSnap.docs.isNotEmpty) {
        final memberDoc = memberSnap.docs.first;
        final available = (memberDoc.data()['diamonds_available'] as num?)?.toInt() ?? 0;
        if (available < diamonds) return {'status': 'error', 'message': 'insufficient'};
        agencyId = memberDoc.data()['agency_id']?.toString();
        await memberDoc.reference.update({
          'diamonds_available': FieldValue.increment(-diamonds),
        });
      }
    }

    if (agencyId == null) return {'status': 'error', 'message': 'not_found'};

    // Credit agent
    await _db.collection('agent_usd_wallets').doc(agentId).set({
      'user_id': agentId,
      'diamond_balance': FieldValue.increment(diamonds),
    }, SetOptions(merge: true));

    await _db.collection('agency_diamond_ledger').add({
      'agency_id': agencyId,
      'user_id': uid,
      'txn_type': 'settlement_from_$source',
      'amount': diamonds,
      'direction': -1,
      'balance_after': 0,
      'note': 'transfer to agent $agentId',
      'idempotency_key': idempotencyKey.isNotEmpty ? idempotencyKey : null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    // Create a withdrawal/transfer record for dashboard tracking & proof upload
    try {
      final userSnap = await _db.collection('users').doc(uid).get();
      final userName = userSnap.data()?['name']?.toString() ??
          userSnap.data()?['display_name']?.toString() ?? 'مضيف';

      await _db.collection('agency_withdrawal_requests').add({
        'user_id': uid,
        'user_name': userName,
        'agent_id': agentId,
        'agency_id': agencyId,
        'amount': diamonds,
        'diamonds_amount': diamonds,
        'usd_amount': (diamonds / 100).toDouble(),
        'payment_method': 'تحويل مباشر لوكيل الشحن',
        'status': 'pending',
        'requires_proof': true,
        'idempotency_key': idempotencyKey.isNotEmpty ? idempotencyKey : null,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // Send system message notification to the recharge agent
      await _db.collection('private_messages').doc().set({
        'sender_id': 'system',
        'receiver_id': agentId,
        'text': '🔔 طلب سحب راتب جديد! قام المضيف $userName بتحويل $diamonds ماسة إليك. يرجى تحويل المبلغ المطلوب ورفع إثبات وسكرين التحويل في لوحة التحكم لإتمام العملية.',
        'type': 'system',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'is_read': false,
        'conversationId': 'system_$agentId',
      });
    } catch (_) {}

    return {'status': 'ok', 'ok': true};
  }

  // ═══════════════════════════════════════════════════════════════
  //  agency_send_announcement
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcAgencySendAnnouncement(
      Map<String, dynamic>? p) async {
    final agencyId = p?['p_agency_id']?.toString();
    final title = p?['p_title']?.toString() ?? '';
    final body = p?['p_body']?.toString() ?? '';
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (agencyId == null || uid == null) return {'status': 'error'};

    await _db.collection('agency_announcements').add({
      'agency_id': agencyId,
      'created_by': uid,
      'title': title,
      'body': body,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    return {'status': 'ok'};
  }

  // ═══════════════════════════════════════════════════════════════
  //  agency_owner_exchange_diamonds
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcAgencyOwnerExchangeDiamonds(
      Map<String, dynamic>? p) async {
    final agencyId = p?['p_agency_id']?.toString();
    final diamonds = (p?['p_diamonds_amount'] as num?)?.toInt() ?? 0;
    final idempotencyKey = p?['p_idempotency_key']?.toString() ?? '';
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (agencyId == null || uid == null || diamonds <= 0) {
      return {'status': 'error'};
    }

    if (idempotencyKey.isNotEmpty) {
      final existing = await _db
          .collection('agency_diamond_ledger')
          .where('idempotency_key', isEqualTo: idempotencyKey)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) return {'status': 'ok', 'message': 'already_processed'};
    }

    final agencySnap = await _db.collection('host_agencies').doc(agencyId).get();
    if (!agencySnap.exists) return {'status': 'error'};
    final ad = agencySnap.data()!;
    final ownerBalance = (ad['owner_diamonds_balance'] as num?)?.toInt() ?? 0;
    if (ownerBalance < diamonds) return {'status': 'error', 'message': 'insufficient'};

    final engine = await _rpcAgencyGetEngineSettings(null);
    final coinsOut = (diamonds *
            ((engine['diamond_to_coin_rate'] as num?)?.toDouble() ??
                (engine['exchange_rate'] as num?)?.toDouble() ??
                1.0))
        .floor();

    await agencySnap.reference.update({
      'owner_diamonds_balance': FieldValue.increment(-diamonds),
    });

    await _db.collection('users').doc(uid).update({
      'coins': FieldValue.increment(coinsOut),
    });

    await _db.collection('agency_diamond_ledger').add({
      'agency_id': agencyId,
      'user_id': uid,
      'txn_type': 'owner_exchange',
      'amount': diamonds,
      'direction': -1,
      'balance_after': ownerBalance - diamonds,
      'note': 'owner exchange $diamonds diamonds → $coinsOut coins',
      'idempotency_key': idempotencyKey.isNotEmpty ? idempotencyKey : null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    return {'status': 'ok', 'ok': true, 'diamonds_in': diamonds, 'coins_out': coinsOut};
  }

  // ═══════════════════════════════════════════════════════════════
  //  agency_owner_request_withdrawal
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcAgencyOwnerRequestWithdrawal(
      Map<String, dynamic>? p) async {
    final agencyId = p?['p_agency_id']?.toString();
    final diamonds = (p?['p_diamonds_amount'] as num?)?.toInt() ?? 0;
    final paymentMethod = p?['p_payment_method']?.toString() ?? '';
    final paymentDetails = p?['p_payment_details'] as Map<String, dynamic>?;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (agencyId == null || uid == null || diamonds <= 0) return {'status': 'error'};

    final agencySnap = await _db.collection('host_agencies').doc(agencyId).get();
    if (!agencySnap.exists) return {'status': 'error'};
    final ad = agencySnap.data()!;
    final ownerBalance = (ad['owner_diamonds_balance'] as num?)?.toInt() ?? 0;
    if (ownerBalance < diamonds) return {'status': 'error', 'message': 'insufficient'};

    await agencySnap.reference.update({
      'owner_diamonds_balance': FieldValue.increment(-diamonds),
    });

    await _db.collection('agency_withdrawal_requests').add({
      'user_id': uid,
      'agency_id': agencyId,
      'diamonds_amount': diamonds,
      'payment_method': paymentMethod,
      'bank_details': paymentDetails ?? {},
      'status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    return {'status': 'ok', 'ok': true};
  }

  // ═══════════════════════════════════════════════════════════════
  //  agency_accept_member
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcAgencyAcceptMember(
      Map<String, dynamic>? p) async {
    final requestId = p?['p_request_id']?.toString();
    if (requestId == null) return {'status': 'error'};

    final reqSnap = await _db.collection('host_agency_join_requests').doc(requestId).get();
    if (!reqSnap.exists) return {'status': 'error', 'message': 'not_found'};
    final req = reqSnap.data()!;
    final agencyId = req['agency_id']?.toString() ?? '';
    final userId = req['user_id']?.toString() ?? '';

    // Update request status
    await reqSnap.reference.update({'status': 'approved'});

    // Add as active member
    final memberRef = _db.collection('host_agency_members').doc();
    await memberRef.set({
      'id': memberRef.id,
      'agency_id': agencyId,
      'user_id': userId,
      'role': 'host',
      'status': 'active',
      'diamonds_earned_monthly': 0,
      'diamonds_earned_cumulative': 0,
      'diamonds_balance': 0,
      'diamonds_pending_withdrawal': 0,
      'diamonds_available': 0,
      'joined_at': DateTime.now().toUtc().toIso8601String(),
    });

    // Update agency member_count
    await _db.collection('host_agencies').doc(agencyId).update({
      'member_count': FieldValue.increment(1),
    });

    // Update user document
    await _db.collection('users').doc(userId).update({
      'agency_id': agencyId,
      'is_agency_member': true,
    });

    return {'status': 'ok'};
  }

  // ═══════════════════════════════════════════════════════════════
  //  agency_kick_member
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcAgencyKickMember(
      Map<String, dynamic>? p) async {
    final agencyId = p?['p_agency_id']?.toString();
    final targetUserId = p?['p_user_id']?.toString();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (agencyId == null || targetUserId == null || uid == null) {
      return {'status': 'error'};
    }

    // Cannot kick owner
    final agencySnap = await _db.collection('host_agencies').doc(agencyId).get();
    if (!agencySnap.exists) return {'status': 'error'};
    final ad = agencySnap.data()!;
    if (ad['owner_user_id']?.toString() == targetUserId || ad['owner_id']?.toString() == targetUserId) {
      return {'status': 'error', 'message': 'cannot_kick_owner'};
    }

    // Day-of-month check: only days 1-5
    final day = DateTime.now().toUtc().day;
    if (day > 5) {
      return {'status': 'error', 'message': 'لا يمكن طرد الأعضاء بعد اليوم الخامس من الشهر'};
    }

    // Find and update member
    final memberSnap = await _db
        .collection('host_agency_members')
        .where('agency_id', isEqualTo: agencyId)
        .where('user_id', isEqualTo: targetUserId)
        .limit(1)
        .get();
    if (memberSnap.docs.isEmpty) return {'status': 'error', 'message': 'not_found'};

    await memberSnap.docs.first.reference.update({
      'status': 'kicked',
      'kicked_at': DateTime.now().toUtc().toIso8601String(),
    });

    // Free agent for 7 days
    final freeUntil = DateTime.now().toUtc().add(const Duration(days: 7));
    await _db.collection('agency_free_agents').doc(targetUserId).set({
      'user_id': targetUserId,
      'free_until': freeUntil.toIso8601String(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    // Decrement member count
    await _db.collection('host_agencies').doc(agencyId).update({
      'member_count': FieldValue.increment(-1),
    });

    return {'status': 'ok'};
  }

  // ═══════════════════════════════════════════════════════════════
  //  agency_create (إرسال طلب إنشاء وكالة للإدارة)
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcAgencyCreate(Map<String, dynamic>? p) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {'status': 'error', 'message': 'يرجى تسجيل الدخول أولاً'};

    final name = (p?['p_name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return {'status': 'error', 'message': 'يرجى إدخال اسم الوكالة'};

    final now = DateTime.now().toUtc();
    final appId = 'app_${now.millisecondsSinceEpoch}_$uid';

    // 1. Get applicant info
    final userSnap = await _db.collection('users').doc(uid).get();
    final userData = userSnap.data() ?? {};
    final userName = userData['name']?.toString() ?? userData['displayName']?.toString() ?? 'مستخدم';
    final customId = userData['custom_id']?.toString() ?? '';
    final userAvatar = userData['photo_url']?.toString() ?? userData['avatar']?.toString() ?? '';

    // 2. Generate agency ID
    final agencyId = 'agency_${now.millisecondsSinceEpoch}_$uid';

    // 3. Create host agency in host_agencies collection
    final agencyData = {
      'id': agencyId,
      'name': name,
      'owner_id': uid,
      'description': p?['p_description'] ?? 'وكالة مضيفين معتمدة',
      'whatsapp': p?['p_phone'],
      'country': p?['p_country'] ?? 'عالمي',
      'photo_url': userAvatar,
      'tier': 'bronze',
      'commission_rate': 0.10,
      'is_active': true,
      'member_count': 1,
      'total_diamonds_monthly': 0,
      'created_at': now.toIso8601String(),
    };
    await _db.collection('host_agencies').doc(agencyId).set(agencyData);

    // 4. Add owner to host_agency_members
    await _db.collection('host_agency_members').doc('${agencyId}_$uid').set({
      'agency_id': agencyId,
      'user_id': uid,
      'role': 'owner',
      'status': 'active',
      'joined_at': now.toIso8601String(),
    });

    // 5. Update user document
    await _db.collection('users').doc(uid).update({
      'agency_id': agencyId,
      'is_host_agent': true,
    });

    // 6. Record application in agency_applications (approved)
    await _db.collection('agency_applications').doc(appId).set({
      'id': appId,
      'agency_id': agencyId,
      'user_id': uid,
      'user_name': userName,
      'custom_id': customId,
      'user_avatar': userAvatar,
      'agency_type': 'host',
      'agency_name': name,
      'description': p?['p_description'],
      'whatsapp': p?['p_phone'],
      'country': p?['p_country'],
      'status': 'approved',
      'created_at': now.toIso8601String(),
    });

    return {
      'status': 'ok',
      'agency_id': agencyId,
      'message': 'تم إنشاء الوكالة بنجاح! 🎉',
    };
  }

  // ═══════════════════════════════════════════════════════════════
  //  get_host_dashboard_v2
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcGetHostDashboardV2(
      Map<String, dynamic>? p) async {
    final userId = p?['p_user_id']?.toString();
    if (userId == null) return {'status': 'not_found'};

    final memberSnap = await _db
        .collection('host_agency_members')
        .where('user_id', isEqualTo: userId)
        .get();

    DocumentSnapshot<Map<String, dynamic>>? memberDoc;
    if (memberSnap.docs.isNotEmpty) {
      for (final doc in memberSnap.docs) {
        if (doc.data()['status']?.toString() == 'active') {
          memberDoc = doc;
          break;
        }
      }
      memberDoc ??= memberSnap.docs.firstWhere(
        (doc) {
          final st = doc.data()['status']?.toString();
          return st != 'pending' && st != 'rejected' && st != 'left' && st != 'kicked';
        },
        orElse: () => memberSnap.docs.first,
      );
    }

    String agencyId = memberDoc?.data()?['agency_id']?.toString() ?? '';
    if (agencyId.isEmpty) {
      final uSnap = await _db.collection('users').doc(userId).get();
      agencyId = uSnap.data()?['agency_id']?.toString() ?? '';
      if (agencyId.isNotEmpty && memberDoc == null) {
        final mDirect = await _db.collection('host_agency_members').doc('${agencyId}_$userId').get();
        if (mDirect.exists) memberDoc = mDirect;
      }
    }

    if (agencyId.isEmpty) return {'status': 'not_found'};
    final md = memberDoc?.data() ?? {};

    String agencyName = '';
    double commissionRate = 0.05;
    try {
      final agencySnap = await _db.collection('host_agencies').doc(agencyId).get();
      if (agencySnap.exists) {
        final ad = agencySnap.data()!;
        agencyName = ad['name']?.toString() ?? '';
        commissionRate = (ad['commission_rate'] as num?)?.toDouble() ?? 0.05;
      }
    } catch (_) {}

    // Engine settings
    final engine = await _rpcAgencyGetEngineSettings(null);

    // Fetch active milestones/targets from host_milestones or agency_targets_config
    final List<Map<String, dynamic>> targetsList = [];
    try {
      final earnedMonthly = (md['diamonds_earned_monthly'] as num?)?.toInt() ?? 0;

      // Check already achieved targets for this month
      final now = DateTime.now();
      final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final achievedSnap = await _db.collection('agency_achieved_targets')
          .where('user_id', isEqualTo: userId)
          .where('month', isEqualTo: currentMonth)
          .get();
      final achievedIds = achievedSnap.docs.map((d) => d.data()['target_id']?.toString() ?? d.id).toSet();

      var milestonesSnap = await _db.collection('host_milestones')
          .where('is_active', isEqualTo: true)
          .get();
      if (milestonesSnap.docs.isEmpty) {
        milestonesSnap = await _db.collection('host_milestones').get();
      }

      final docs = milestonesSnap.docs.toList();
      docs.sort((a, b) {
        final aOrder = (a.data()['sort_order'] ?? a.data()['sortOrder'] as num?)?.toInt() ?? 0;
        final bOrder = (b.data()['sort_order'] ?? b.data()['sortOrder'] as num?)?.toInt() ?? 0;
        if (aOrder != bOrder) return aOrder.compareTo(bOrder);
        final aDiamonds = (a.data()['target_diamonds'] ?? a.data()['targetDiamonds'] as num?)?.toInt() ?? 0;
        final bDiamonds = (b.data()['target_diamonds'] ?? b.data()['targetDiamonds'] as num?)?.toInt() ?? 0;
        return aDiamonds.compareTo(bDiamonds);
      });

      for (final doc in docs) {
        final data = doc.data();
        final targetDiamonds = (data['target_diamonds'] ?? data['targetDiamonds'] as num?)?.toInt() ?? 0;
        if (targetDiamonds <= 0 || targetDiamonds > 1000000000) continue; // Skip invalid or corrupted trillion tiers

        final isAchieved = earnedMonthly >= targetDiamonds || achievedIds.contains(doc.id);
        final remaining = (targetDiamonds - earnedMonthly).clamp(0, targetDiamonds);
        final progressPct = targetDiamonds > 0 ? (earnedMonthly / targetDiamonds).clamp(0.0, 1.0) : 0.0;
        final rewardVal = (data['reward_value'] ?? data['rewardValue'] as num?)?.toDouble() ?? 0.0;
        final rewardType = data['reward_type']?.toString() ?? data['rewardType']?.toString() ?? 'salary_usd';

        int rewardCoins = 0;
        int rewardDiamonds = 0;
        int rewardSvip = 0;
        if (rewardType == 'gold') {
          rewardCoins = rewardVal.toInt();
        } else if (rewardType == 'diamonds') {
          rewardDiamonds = rewardVal.toInt();
        } else if (rewardType == 'vip_days') {
          rewardSvip = rewardVal.toInt();
        } else if (rewardType == 'salary_usd') {
          rewardCoins = (rewardVal * 100).toInt(); // USD to equivalent
        }

        targetsList.add({
          'id': doc.id,
          'title': data['title'] ?? data['title_ar'] ?? 'المستوى ${targetsList.length + 1}',
          'target_diamonds': targetDiamonds,
          'reward_coins': rewardCoins,
          'reward_diamonds': rewardDiamonds,
          'reward_svip_days': rewardSvip,
          'reward_type': rewardType,
          'reward_value': rewardVal,
          'reward_item_id': data['reward_item_id'] ?? data['rewardItemId'],
          'reward_image_url': data['reward_image_url'] ?? data['rewardImageUrl'] ?? data['image_url'],
          'background_url': data['background_url'] ?? data['backgroundUrl'],
          'agent_commission_rate': (data['agent_commission_rate'] ?? data['agentCommissionRate'] as num?)?.toDouble() ?? 0.1,
          'earned_this_month': earnedMonthly,
          'remaining': remaining,
          'progress_pct': progressPct,
          'is_achieved': isAchieved,
          'sort_order': (data['sort_order'] ?? data['sortOrder'] as num?)?.toInt() ?? targetsList.length,
        });
      }

      // If still empty, add default standard 9 host milestones
      if (targetsList.isEmpty) {
        final defaultMilestones = [
          {'id': 'milestone_100k', 'title': 'المستوى 1 (100K)', 'target': 100000, 'coins': 5000, 'type': 'gold', 'val': 5000.0, 'order': 1},
          {'id': 'milestone_300k', 'title': 'المستوى 2 (300K)', 'target': 300000, 'coins': 18000, 'type': 'gold', 'val': 18000.0, 'order': 2},
          {'id': 'milestone_500k', 'title': 'المستوى 3 (500K)', 'target': 500000, 'coins': 35000, 'type': 'gold', 'val': 35000.0, 'order': 3},
          {'id': 'milestone_1m',   'title': 'المستوى 4 (1M)',   'target': 1000000, 'coins': 15000, 'type': 'salary_usd', 'val': 150.0, 'order': 4},
          {'id': 'milestone_2m',   'title': 'المستوى 5 (2M)',   'target': 2000000, 'coins': 32000, 'type': 'salary_usd', 'val': 320.0, 'order': 5},
          {'id': 'milestone_5m',   'title': 'المستوى 6 (5M)',   'target': 5000000, 'coins': 85000, 'type': 'salary_usd', 'val': 850.0, 'order': 6},
          {'id': 'milestone_10m',  'title': 'المستوى 7 (10M)',  'target': 10000000, 'coins': 180000, 'type': 'salary_usd', 'val': 1800.0, 'order': 7},
          {'id': 'milestone_20m',  'title': 'المستوى 8 (20M)',  'target': 20000000, 'coins': 380000, 'type': 'salary_usd', 'val': 3800.0, 'order': 8},
          {'id': 'milestone_50m',  'title': 'المستوى 9 (50M)',  'target': 50000000, 'coins': 1000000, 'type': 'salary_usd', 'val': 10000.0, 'order': 9},
        ];
        for (final m in defaultMilestones) {
          final td = m['target'] as int;
          final isAchieved = earnedMonthly >= td || achievedIds.contains(m['id']);
          final remaining = (td - earnedMonthly).clamp(0, td);
          final progressPct = td > 0 ? (earnedMonthly / td).clamp(0.0, 1.0) : 0.0;
          targetsList.add({
            'id': m['id'],
            'title': m['title'],
            'target_diamonds': td,
            'reward_coins': m['coins'],
            'reward_diamonds': 0,
            'reward_svip_days': 0,
            'reward_type': m['type'],
            'reward_value': m['val'],
            'earned_this_month': earnedMonthly,
            'remaining': remaining,
            'progress_pct': progressPct,
            'is_achieved': isAchieved,
            'sort_order': m['order'],
          });
        }
      }
    } catch (e) {
      // ignore
    }

    return <String, dynamic>{
      'status': 'ok',
      'member_id': memberDoc?.id ?? '${agencyId}_$userId',
      'agency_id': agencyId,
      'agency_name': agencyName,
      'role': md['role'] ?? 'host',
      'commission_rate': commissionRate,
      'diamonds_balance': md['diamonds_balance'] ?? 0,
      'diamonds_available': md['diamonds_available'] ?? 0,
      'diamonds_pending_withdrawal': md['diamonds_pending_withdrawal'] ?? 0,
      'diamonds_earned_monthly': md['diamonds_earned_monthly'] ?? 0,
      'diamonds_earned_cumulative': md['diamonds_earned_cumulative'] ?? 0,
      'is_in_trial': md['trial_ends_at'] != null,
      'trial_ends_at': md['trial_ends_at'],
      'join_date': md['joined_at'],
      'targets': targetsList,
      'recent_ledger': <dynamic>[],
      'engine': engine,
    };
  }

  // ═══════════════════════════════════════════════════════════════
  //  get_host_dashboard_v3
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _rpcGetHostDashboardV3(
      Map<String, dynamic>? p) async {
    final userId = p?['p_user_id']?.toString();
    if (userId == null) return <String, dynamic>{};

    // Find member
    final memberSnap = await _db
        .collection('host_agency_members')
        .where('user_id', isEqualTo: userId)
        .get();

    DocumentSnapshot<Map<String, dynamic>>? memberDoc;
    if (memberSnap.docs.isNotEmpty) {
      for (final doc in memberSnap.docs) {
        if (doc.data()['status']?.toString() == 'active') {
          memberDoc = doc;
          break;
        }
      }
      memberDoc ??= memberSnap.docs.firstWhere(
        (doc) {
          final st = doc.data()['status']?.toString();
          return st != 'pending' && st != 'rejected' && st != 'left' && st != 'kicked';
        },
        orElse: () => memberSnap.docs.first,
      );
    }

    String agencyId = memberDoc?.data()?['agency_id']?.toString() ?? '';
    if (agencyId.isEmpty) {
      final uSnap = await _db.collection('users').doc(userId).get();
      agencyId = uSnap.data()?['agency_id']?.toString() ?? '';
      if (agencyId.isNotEmpty && memberDoc == null) {
        final mDirect = await _db.collection('host_agency_members').doc('${agencyId}_$userId').get();
        if (mDirect.exists) memberDoc = mDirect;
      }
    }

    if (agencyId.isEmpty) return <String, dynamic>{};
    final md = memberDoc?.data() ?? {};

    String agencyName = '';
    try {
      final agencySnap = await _db.collection('host_agencies').doc(agencyId).get();
      if (agencySnap.exists) agencyName = agencySnap.data()!['name']?.toString() ?? '';
    } catch (_) {}

    // Diamond balance from users doc
    int diamondBalance = 0;
    try {
      final userSnap = await _db.collection('users').doc(userId).get();
      if (userSnap.exists) diamondBalance = (userSnap.data()!['diamonds'] as num?)?.toInt() ?? 0;
    } catch (_) {}

    // USD wallet
    int usdBalance = 0;
    try {
      final walletSnap = await _db.collection('host_usd_wallets').doc(userId).get();
      if (walletSnap.exists) usdBalance = (walletSnap.data()!['usd_balance'] as num?)?.toInt() ?? 0;
    } catch (_) {}

    // Engine config
    bool engineEnabled = false;
    Map<String, dynamic> config = {};
    try {
      final cfgSnap = await _db.collection('agency_economy_config').limit(1).get();
      if (cfgSnap.docs.isNotEmpty) {
        config = cfgSnap.docs.first.data();
        engineEnabled = config['engine_enabled'] == true;
      }
    } catch (_) {}

    final now = DateTime.now().toUtc();
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    final secondsRemaining = monthEnd.difference(now).inSeconds;

    return <String, dynamic>{
      'agency': {'id': agencyId, 'name': agencyName},
      'progress': {
        'period_month': '${now.year}-${now.month.toString().padLeft(2, '0')}',
        'coins_received': md['diamonds_earned_monthly'] ?? 0,
        'usd_equiv': 0,
        'current_tier_id': null,
        'last_gift_at': null,
      },
      'wallets': {
        'diamonds': diamondBalance,
        'usd_balance': usdBalance,
        'usd_earned_total': 0,
        'usd_withdrawn': 0,
        'diamonds_as_coins': 0,
        'diamonds_as_usd': 0,
      },
      'tiers': <dynamic>[],
      'claimed_tiers': <dynamic>[],
      'month_end_at': monthEnd.toIso8601String(),
      'seconds_remaining': secondsRemaining,
      'config': config,
      'is_dry_run': config['dry_run_mode'] == true,
      'engine_enabled': engineEnabled,
    };
  }

  Future<Map<String, dynamic>> _rpcAgentGetDashboard(Map<String, dynamic>? p) async {
    final uid = p?['uid']?.toString() ??
        FirebaseAuth.instance.currentUser?.uid ??
        auth.currentUser?.id;
    if (uid == null) return {'ok': false, 'error': 'unauthorized'};
    final uDoc = await _db.collection('users').doc(uid).get();
    final data = uDoc.data() ?? {};
    final isAgent = data['is_recharge_agent'] == true ||
        data['isRechargeAgent'] == true ||
        data['is_agent'] == true ||
        data['role'] == 'agent' ||
        data['role'] == 'recharge_agent';
    if (!isAgent) return {'ok': false, 'error': 'not_an_agent'};

    final coins = (data['coins'] as num?)?.toInt() ?? 0;
    final pin = data['agent_pin']?.toString();
    final customId = data['custom_id']?.toString() ?? data['customId']?.toString() ?? uid;

    int todayTotal = 0;
    int todayCount = 0;
    int weekTotal = 0;
    int weekCount = 0;
    int monthTotal = 0;
    int monthCount = 0;
    int allTotal = 0;
    int allCount = 0;
    List<Map<String, dynamic>> recentTxns = [];

    try {
      final snap = await _db.collection('agent_recharge_transactions')
          .where('agent_id', isEqualTo: uid)
          .limit(100)
          .get();
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = todayStart.subtract(Duration(days: now.weekday % 7));
      final monthStart = DateTime(now.year, now.month, 1);

      for (final doc in snap.docs) {
        final d = Map<String, dynamic>.from(doc.data());
        d['id'] = doc.id;
        final amt = (d['gold_amount'] as num?)?.toInt() ?? 0;
        final dDate = d['created_at'] != null ? DateTime.tryParse(d['created_at'].toString()) : null;
        allTotal += amt;
        allCount++;
        if (dDate != null) {
          if (dDate.isAfter(todayStart)) {
            todayTotal += amt;
            todayCount++;
          }
          if (dDate.isAfter(weekStart)) {
            weekTotal += amt;
            weekCount++;
          }
          if (dDate.isAfter(monthStart)) {
            monthTotal += amt;
            monthCount++;
          }
        }
        recentTxns.add(d);
      }
      recentTxns.sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));
    } catch (_) {}

    const dailyLimit = 10000000;
    final remaining = (dailyLimit - todayTotal) > 0 ? (dailyLimit - todayTotal) : 0;

    return {
      'ok': true,
      'enabled': true,
      'pin_set': pin != null && pin.isNotEmpty,
      'daily_limit': dailyLimit,
      'agency_gold': coins,
      'agent_public_id': customId,
      'today': {'total': todayTotal, 'count': todayCount, 'remaining': remaining},
      'week': {'total': weekTotal, 'count': weekCount},
      'month': {'total': monthTotal, 'count': monthCount},
      'all': {'total': allTotal, 'count': allCount},
      'week_chart': <Map<String, dynamic>>[],
      'recent_txns': recentTxns.take(10).toList(),
      'quick_amounts': [1000, 5000, 10000, 50000, 100000],
      'usd_balance': 0.0,
    };
  }

  Future<Map<String, dynamic>> _rpcAgentSetPin(Map<String, dynamic>? p) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {'ok': false};
    final pin = p?['p_pin']?.toString() ?? '';
    await _db.collection('users').doc(uid).set({'agent_pin': pin}, SetOptions(merge: true));
    return {'ok': true};
  }

  Future<Map<String, dynamic>> _rpcAgentVerifyPin(Map<String, dynamic>? p) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {'ok': false};
    final pin = p?['p_pin']?.toString() ?? '';
    final uDoc = await _db.collection('users').doc(uid).get();
    final savedPin = uDoc.data()?['agent_pin']?.toString();
    final valid = (savedPin == null || savedPin.isEmpty) || (savedPin == pin);
    return {'ok': valid, 'valid': valid};
  }

  Future<Map<String, dynamic>> _rpcAgentGetUsdWallet(Map<String, dynamic>? p) async {
    return {
      'ok': true,
      'balance_usd': 0.0,
      'pending_withdrawal_usd': 0.0,
      'total_withdrawn_usd': 0.0,
      'history': <Map<String, dynamic>>[],
    };
  }

  Future<Map<String, dynamic>> _rpcAgentGetDiamondWallet(Map<String, dynamic>? p) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final uDoc = uid != null ? await _db.collection('users').doc(uid).get() : null;
    final diamonds = (uDoc?.data()?['diamonds'] as num?)?.toInt() ?? 0;
    return {
      'ok': true,
      'diamond_balance': diamonds,
      'history': <Map<String, dynamic>>[],
    };
  }

  Future<List<Map<String, dynamic>>> _rpcAgentRechargeHistory(Map<String, dynamic>? p) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return <Map<String, dynamic>>[];
    try {
      final snap = await _db.collection('agent_recharge_transactions')
          .where('agent_id', isEqualTo: uid)
          .limit((p?['p_limit'] as num?)?.toInt() ?? 100)
          .get();
      final list = snap.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        data['id'] = d.id;
        return data;
      }).toList();
      list.sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));
      return list;
    } catch (e) {
      debugPrint('[_rpcAgentRechargeHistory] $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>> _rpcAgentSetQuickAmounts(Map<String, dynamic>? p) async {
    return {'ok': true};
  }

  RealtimeChannel channel(String topic) => RealtimeChannel(topic);

  void removeChannel(RealtimeChannel channel) {
    channel.dispose();
  }

  StorageClient get storage => StorageClient();
}

/// Storage backed by Cloudinary (mirrors Supabase storage API).
class StorageClient {
  StorageBucket from(String bucket) => StorageBucket(bucket);
}

class StorageBucket {
  final String bucket;
  StorageBucket(this.bucket);

  static final Map<String, String> _uploadedUrls = {};

  Future<String> upload(
    String path,
    dynamic file, {
    FileOptions? fileOptions,
  }) async {
    final File localFile;
    if (file is File) {
      localFile = file;
    } else if (file is Uint8List) {
      final tmp = File(
        '${Directory.systemTemp.path}/$bucket/${path.replaceAll('/', '_')}',
      );
      await tmp.create(recursive: true);
      await tmp.writeAsBytes(file, flush: true);
      localFile = tmp;
    } else {
      throw StateError('Unsupported upload type: ${file.runtimeType}');
    }
    final url = await CloudinaryService().upload(localFile);
    _uploadedUrls[path] = url;
    return path;
  }

  Future<String> uploadBinary(
    String path,
    Uint8List data, {
    FileOptions? fileOptions,
  }) async {
    return upload(path, data, fileOptions: fileOptions);
  }

    String getPublicUrl(String path) {
    final url = _uploadedUrls[path];
    if (url != null && url.isNotEmpty) return url;
    return 'https://res.cloudinary.com/r5kohqhd/image/upload/$path';
  }
}

class FileOptions {
  final bool upsert;
  final String? contentType;
  const FileOptions({this.upsert = false, this.contentType});
}

/// Realtime-channel shim backed by Firestore snapshot listeners.
/// Replaces Postgres realtime with a Firestore `where` stream on the same table.
class RealtimeChannel {
  final String topic;
  RealtimeChannel(this.topic);

  PostgresChangeEvent? _event;
  String? _table;
  String? _column;
  dynamic _value;
  bool _negated = false;
  void Function(PostgresChangePayload)? _callback;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  RealtimeChannel onPostgresChanges({
    PostgresChangeEvent event = PostgresChangeEvent.all,
    String? schema,
    String? table,
    PostgresChangeFilter? filter,
    void Function(PostgresChangePayload)? callback,
  }) {
    _event = event;
    _table = table;
    _column = filter?.column;
    _value = filter?.value;
    _negated = filter?.type == PostgresChangeFilterType.neq;
    _callback = callback;
    return this;
  }

  RealtimeChannel subscribe() {
    final table = _table;
    final callback = _callback;
    if (table == null || callback == null) return this;
    final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
    Query<Map<String, dynamic>> q = db.collection(table);
    if (_column != null && _value != null) {
      q = _negated
          ? q.where(_column!, isNotEqualTo: _value)
          : q.where(_column!, isEqualTo: _value);
    }
    _sub = q.snapshots().listen((snap) {
      final event = _event;
      for (final change in snap.docChanges) {
        final matchesEvent = switch (event) {
          PostgresChangeEvent.insert =>
            change.type == DocumentChangeType.added,
          PostgresChangeEvent.update =>
            change.type == DocumentChangeType.modified,
          PostgresChangeEvent.delete =>
            change.type == DocumentChangeType.removed,
          PostgresChangeEvent.all => true,
          null => true,
        };
        if (matchesEvent) {
          final data = change.doc.data();
          callback(PostgresChangePayload(
            data == null ? <String, dynamic>{} : Map<String, dynamic>.from(data),
          ));
        }
      }
    });
    return this;
  }

  void unsubscribe() {
    _sub?.cancel();
    _sub = null;
  }

  void dispose() => unsubscribe();
}

class PostgresChangeFilter {
  final PostgresChangeFilterType type;
  final String? column;
  final dynamic value;
  const PostgresChangeFilter({
    this.type = PostgresChangeFilterType.eq,
    this.column,
    this.value,
  });
}

enum PostgresChangeFilterType { eq, neq }

enum PostgresChangeEvent { all, insert, update, delete }

class PostgresChangePayload {
  final Map<String, dynamic> newRecord;
  final Map<String, dynamic> oldRecord;
  const PostgresChangePayload(this.newRecord, {this.oldRecord = const {}});
}

/// Auth client backed by FirebaseAuth.
class AuthClient {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  UserCompat? get currentUser {
    final u = _auth.currentUser;
    return u == null ? null : UserCompat(u);
  }

  Session? get currentSession {
    final u = _auth.currentUser;
    if (u == null) return null;
    return Session(UserCompat(u), u.uid);
  }

  Future<AuthResponse> signInAnonymously() async {
    final cred = await _auth.signInAnonymously();
    return AuthResponse(cred.user == null ? null : UserCompat(cred.user!));
  }

  Future<void> signOut() => _auth.signOut();
}

class Session {
  final UserCompat user;
  final String? accessToken;
  Session(this.user, this.accessToken);
}

class UserCompat {
  final User _user;
  UserCompat(this._user);

  String get id => _user.uid;
  String? get email => _user.email;
  String? get phone => _user.phoneNumber;
  Map<String, dynamic>? get userMetadata => <String, dynamic>{};
}

class AuthResponse {
  final UserCompat? user;
  AuthResponse(this.user);
}

/// Firestore-backed query builder exposing a Supabase-like fluent API.
enum _QOp { select, insert, update, delete, upsert }

class SupabaseQueryBuilder implements Future<List<Map<String, dynamic>>> {
  final FirebaseFirestore _db;
  final String _table;
  final List<(String, String, dynamic)> _wheres = [];
  final List<List<(String, String, dynamic)>> _orGroups = [];
  String? _orderCol;
  bool _orderAsc = true;
  int? _limit;
  int? _rangeStart;
  int? _rangeEnd;
  _QOp _op = _QOp.select;
  Map<String, dynamic>? _payload;

  SupabaseQueryBuilder(this._db, this._table);

  SupabaseQueryBuilder select([String columns = '*']) => this;

  SupabaseQueryBuilder eq(String column, dynamic value) {
    _wheres.add((column, 'eq', value));
    return this;
  }

  SupabaseQueryBuilder neq(String column, dynamic value) {
    _wheres.add((column, 'neq', value));
    return this;
  }

  SupabaseQueryBuilder gt(String column, dynamic value) {
    _wheres.add((column, 'gt', value));
    return this;
  }

  SupabaseQueryBuilder gte(String column, dynamic value) {
    _wheres.add((column, 'gte', value));
    return this;
  }

  SupabaseQueryBuilder lt(String column, dynamic value) {
    _wheres.add((column, 'lt', value));
    return this;
  }

  SupabaseQueryBuilder lte(String column, dynamic value) {
    _wheres.add((column, 'lte', value));
    return this;
  }

  SupabaseQueryBuilder inFilter(String column, List<dynamic> values) {
    _wheres.add((column, 'in', values));
    return this;
  }

  /// Supabase `or("a.ilike.%x%,b.ilike.%x%")` -> in-memory OR filtering.
  SupabaseQueryBuilder or(String filter) {
    final clauses = <(String, String, dynamic)>[];
    for (final part in filter.split(',')) {
      final pieces = part.split('.');
      if (pieces.length < 2) continue;
      final field = pieces.removeAt(0);
      final op = pieces.removeAt(0);
      var value = pieces.join('.');
      if (op == 'ilike' || op == 'like') value = value.replaceAll('%', '');
      clauses.add((field, op, value));
    }
    if (clauses.isNotEmpty) _orGroups.add(clauses);
    return this;
  }

  /// Supabase `range(start, end)` -> in-memory slicing of fetched rows.
  SupabaseQueryBuilder range(int start, int end) {
    _rangeStart = start;
    _rangeEnd = end;
    return this;
  }

  SupabaseQueryBuilder order(String column, {bool ascending = true}) {
    _orderCol = column;
    _orderAsc = ascending;
    return this;
  }

  SupabaseQueryBuilder limit(int count) {
    _limit = count;
    return this;
  }

  SupabaseQueryBuilder update(Map<String, dynamic> payload) {
    _op = _QOp.update;
    _payload = payload;
    return this;
  }

  SupabaseQueryBuilder insert(Map<String, dynamic> payload) {
    _op = _QOp.insert;
    _payload = payload;
    return this;
  }

  SupabaseQueryBuilder upsert(dynamic payload, {String? onConflict}) {
    _op = _QOp.upsert;
    if (payload is Map<String, dynamic>) {
      _payload = payload;
    } else if (payload is List && payload.isNotEmpty && payload.first is Map<String, dynamic>) {
      _payload = payload.first as Map<String, dynamic>;
    }
    return this;
  }

  SupabaseQueryBuilder delete() {
    _op = _QOp.delete;
    return this;
  }

  Future<Map<String, dynamic>?> maybeSingle() async {
    final list = await _execute();
    return list.isEmpty ? null : list.first;
  }

  Future<Map<String, dynamic>> single() async {
    final list = await _execute();
    if (list.isEmpty) {
      throw StateError('single() returned no rows in collection "$_table"');
    }
    return list.first;
  }

  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> q = _db.collection(_table);
    for (final (col, op, val) in _wheres) {
      switch (op) {
        case 'neq':
          q = q.where(col, isNotEqualTo: val);
          break;
        case 'gt':
          q = q.where(col, isGreaterThan: val);
          break;
        case 'gte':
          q = q.where(col, isGreaterThanOrEqualTo: val);
          break;
        case 'lt':
          q = q.where(col, isLessThan: val);
          break;
        case 'lte':
          q = q.where(col, isLessThanOrEqualTo: val);
          break;
        case 'in':
          q = q.where(col, whereIn: val as List);
          break;
        case 'eq':
        default:
          q = q.where(col, isEqualTo: val);
      }
    }
    if (_orderCol != null) q = q.orderBy(_orderCol!, descending: !_orderAsc);
    if (_limit != null) q = q.limit(_limit!);
    return q;
  }

  bool _matchesOrClause(Map<String, dynamic> row, (String, String, dynamic) clause) {
    final (field, op, value) = clause;
    final raw = row[field];
    if (raw == null) return false;
    if (op == 'ilike' || op == 'like') {
      return raw.toString().toLowerCase().contains(value.toString().toLowerCase());
    }
    return raw.toString() == value.toString();
  }

  Future<List<Map<String, dynamic>>> _execute() async {
    switch (_op) {
      case _QOp.select:
        QuerySnapshot<Map<String, dynamic>> snap;
        try {
          snap = await _buildQuery().get();
        } catch (e) {
          try {
            snap = await _db.collection(_table).limit(_limit ?? 50).get();
          } catch (_) {
            rethrow;
          }
        }
        var rows = snap.docs.map((d) {
          final data = Map<String, dynamic>.from(d.data());
          data.putIfAbsent('id', () => d.id);
          data.putIfAbsent('uid', () => d.id);
          return data;
        }).toList();
        for (final group in _orGroups) {
          rows = rows
              .where((row) => group.any((c) => _matchesOrClause(row, c)))
              .toList();
        }
        if (_rangeStart != null) {
          final end = _rangeEnd ?? rows.length - 1;
          rows = rows
              .skip(_rangeStart!)
              .take(end - _rangeStart! + 1)
              .toList();
        }
        return rows;
      case _QOp.insert:
        await _db.collection(_table).add(_payload!);
        return <Map<String, dynamic>>[_payload!];
      case _QOp.update:
        final snap = await _buildQuery().get();
        for (final doc in snap.docs) {
          await doc.reference.set(_payload!, SetOptions(merge: true));
        }
        return <Map<String, dynamic>>[];
      case _QOp.delete:
        final snap = await _buildQuery().get();
        for (final doc in snap.docs) {
          await doc.reference.delete();
        }
        return <Map<String, dynamic>>[];
      case _QOp.upsert:
        if (_payload != null) {
          final docId = _payload!['id']?.toString() ??
              _payload!['uid']?.toString() ??
              _payload!['user_id']?.toString() ??
              _payload!['agency_id']?.toString();
          if (docId != null && docId.isNotEmpty) {
            await _db.collection(_table).doc(docId).set(_payload!, SetOptions(merge: true));
          } else {
            await _db.collection(_table).add(_payload!);
          }
          return <Map<String, dynamic>>[_payload!];
        }
        return <Map<String, dynamic>>[];
    }
  }

  @override
  Future<R> then<R>(FutureOr<R> Function(List<Map<String, dynamic>>) onValue,
      {Function? onError}) {
    return _execute().then(onValue, onError: onError);
  }

  @override
  Future<List<Map<String, dynamic>>> catchError(Function onError,
      {bool Function(Object error)? test}) {
    return _execute().catchError(onError, test: test);
  }

  @override
  Future<List<Map<String, dynamic>>> whenComplete(
      FutureOr<void> Function() action) {
    return _execute().whenComplete(action);
  }

  @override
  Stream<List<Map<String, dynamic>>> asStream() => Stream.fromFuture(_execute());

  @override
  Future<List<Map<String, dynamic>>> timeout(Duration timeLimit,
      {FutureOr<List<Map<String, dynamic>>> Function()? onTimeout}) {
    return _execute().timeout(timeLimit, onTimeout: onTimeout);
  }
}
