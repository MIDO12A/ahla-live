// lib/features/host_agency/data/agency_chat_repository.dart
// ─────────────────────────────────────────────────────────────────────────────
// عمليات Supabase لقروب الوكالة
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../core/supabase_compat.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/realtime/realtime_subscription.dart';
import '../../../core/realtime/supabase_realtime_bridge.dart';
import '../../../services/supabase_data_service.dart';
import 'agency_chat_models.dart';

abstract final class AgencyChatRepository {
  static SupabaseClient get _sb => Supabase.instance.client;

  // ── جلب آخر N رسالة من القروب ────────────────────────────────────────────
  static Future<List<AgencyChatMessage>> fetchHistory({
    required String agencyId,
    int limit = 80,
  }) async {
    final myId = AuthService.currentSession?.user.id;
    try {
      final rows = await _sb
          .from('agency_chat_messages')
          .select()
          .eq('agency_id', agencyId)
          .order('created_at', ascending: false)
          .limit(limit);
      final list = (rows as List)
          .map((r) => AgencyChatMessage.fromRow(
                Map<String, dynamic>.from(r as Map),
                myId: myId,
              ))
          .toList();
      return list.reversed.toList();
    } catch (e) {
      debugPrint('[AgencyChatRepository] fetchHistory error: $e');
      return [];
    }
  }

  // ── Realtime — الاستماع للرسائل الجديدة ──────────────────────────────────
  static RealtimeSubscription subscribeInserts({
    required String agencyId,
    required void Function(AgencyChatMessage msg) onMessage,
  }) {
    final myId = AuthService.currentSession?.user.id;
    return SupabaseRealtimeBridge.subscribePostgres(
      topic: 'agency_chat:$agencyId',
      event: PostgresChangeEvent.insert,
      table: 'agency_chat_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'agency_id',
        value: agencyId,
      ),
      onPayload: (payload) {
        final row = payload.newRecord;
        onMessage(AgencyChatMessage.fromRow(
          Map<String, dynamic>.from(row),
          myId: myId,
        ));
      },
    );
  }

  // ── إرسال رسالة نصية ─────────────────────────────────────────────────────
  static Future<String?> sendText({
    required String agencyId,
    required String body,
    bool   isViewOnce = false,
    int?   viewDurationSecs,
  }) async {
    try {
      final resp = await _sb.rpc('agency_send_chat_message', params: {
        'p_agency_id':          agencyId,
        'p_message_type':       'text',
        'p_body':               body.trim(),
        'p_is_view_once':       isViewOnce,
        'p_view_duration_secs': viewDurationSecs,
      });
      final status = (resp as Map?)?['status']?.toString() ?? 'error';
      return status == 'ok' ? null : status;
    } catch (e) {
      debugPrint('[AgencyChatRepository] sendText error: $e');
      return 'db_error';
    }
  }

  // ── رفع صورة وإرسالها ─────────────────────────────────────────────────────
  static Future<String?> sendImage({
    required String agencyId,
    required File   imageFile,
    bool   isViewOnce = false,
    int?   viewDurationSecs,
  }) async {
    try {
      final uid = AuthService.currentSession?.user.id;
      if (uid == null) return 'not_authenticated';

      final ts  = DateTime.now().millisecondsSinceEpoch;
      final ext = imageFile.path.split('.').last.toLowerCase();
      final path = '$agencyId/$uid/${ts}.$ext';

      await _sb.storage
          .from('agency-chat-images')
          .upload(path, imageFile, fileOptions: const FileOptions(upsert: true));

      final url = _sb.storage.from('agency-chat-images').getPublicUrl(path);

      final resp = await _sb.rpc('agency_send_chat_message', params: {
        'p_agency_id':          agencyId,
        'p_message_type':       'image',
        'p_asset_url':          url,
        'p_is_view_once':       isViewOnce,
        'p_view_duration_secs': viewDurationSecs,
      });
      final status = (resp as Map?)?['status']?.toString() ?? 'error';
      return status == 'ok' ? null : status;
    } catch (e) {
      debugPrint('[AgencyChatRepository] sendImage error: $e');
      return 'upload_error';
    }
  }

  // ── رفع تسجيل صوتي وإرساله ───────────────────────────────────────────────
  static Future<String?> sendAudio({
    required String agencyId,
    required File   audioFile,
    required int    durationSecs,
    bool isViewOnce = false,
  }) async {
    try {
      final uid = AuthService.currentSession?.user.id;
      if (uid == null) return 'not_authenticated';

      final ts   = DateTime.now().millisecondsSinceEpoch;
      final path = '$agencyId/$uid/${ts}.m4a';

      await _sb.storage
          .from('agency-chat-audio')
          .upload(path, audioFile, fileOptions: const FileOptions(upsert: true));

      final url = _sb.storage.from('agency-chat-audio').getPublicUrl(path);

      final resp = await _sb.rpc('agency_send_chat_message', params: {
        'p_agency_id':            agencyId,
        'p_message_type':         'audio',
        'p_asset_url':            url,
        'p_asset_duration_secs':  durationSecs,
        'p_is_view_once':         isViewOnce,
      });
      final status = (resp as Map?)?['status']?.toString() ?? 'error';
      return status == 'ok' ? null : status;
    } catch (e) {
      debugPrint('[AgencyChatRepository] sendAudio error: $e');
      return 'upload_error';
    }
  }

  // ── فتح رسالة view-once (مرة واحدة) ─────────────────────────────────────
  static Future<Map<String, dynamic>?> openViewOnce(int messageId) async {
    try {
      final resp = await _sb.rpc('agency_view_once_open', params: {
        'p_message_id': messageId,
      });
      if (resp == null) return null;
      return Map<String, dynamic>.from(resp as Map);
    } catch (e) {
      debugPrint('[AgencyChatRepository] openViewOnce error: $e');
      return null;
    }
  }

  // ── إبلاغ عن محاولة لقطة شاشة ────────────────────────────────────────────
  static Future<void> reportScreenshot(String agencyId) async {
    try {
      await _sb.rpc('agency_report_screenshot', params: {
        'p_agency_id': agencyId,
      });
    } catch (e) {
      debugPrint('[AgencyChatRepository] reportScreenshot error: $e');
    }
  }

  // ── كتم / رفع كتم عضو ────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> muteMember({
    required String agencyId,
    required String userId,
    required int    hours, // 0 = رفع الكتم
    String? reason,
  }) async {
    try {
      final resp = await _sb.rpc('agency_mute_member_chat', params: {
        'p_agency_id': agencyId,
        'p_user_id':   userId,
        'p_hours':     hours,
        'p_reason':    reason,
      });
      return Map<String, dynamic>.from(resp as Map);
    } catch (e) {
      debugPrint('[AgencyChatRepository] muteMember error: $e');
      return {'status': 'error'};
    }
  }

  // ── جلب حالة كتمي الحالية ─────────────────────────────────────────────────
  static Future<DateTime?> getMyMuteStatus(String agencyId) async {
    final uid = AuthService.currentSession?.user.id;
    if (uid == null) return null;
    try {
      final row = await _sb
          .from('agency_chat_mutes')
          .select('until_at')
          .eq('agency_id', agencyId)
          .eq('muted_user_id', uid)
          .maybeSingle();
      if (row == null) return null;
      final dt = DateTime.tryParse((row['until_at'] ?? '').toString());
      if (dt == null || dt.isBefore(DateTime.now())) return null;
      return dt;
    } catch (e) {
      debugPrint('[AgencyChatRepository] getMyMuteStatus error: $e');
      return null;
    }
  }

  // ── جلب دوري جماعي لبيانات المرسلين (أفاتار + دور + شارات) ─────────────
  static Future<Map<String, AgencyChatUserMeta>> fetchUserMeta({
    required String agencyId,
    required List<String> userIds,
  }) async {
    if (userIds.isEmpty) return {};
    try {
      final results = await Future.wait([
        _sb
            .from('profiles')
            .select('id, avatar_url, chat_frame_url, vip_level, country')
            .inFilter('id', userIds),
        _sb
            .from('host_agency_members')
            .select('user_id, role')
            .eq('agency_id', agencyId)
            .eq('status', 'active')
            .inFilter('user_id', userIds),
        _sb
            .from('user_bag')
            .select('user_id, asset_url')
            .eq('item_type', 'necklace')
            .eq('is_equipped', true)
            .inFilter('user_id', userIds),
      ]);

      final profileRows  = (results[0] as List).cast<Map<String, dynamic>>();
      final roleRows     = (results[1] as List).cast<Map<String, dynamic>>();
      final necklaceRows = (results[2] as List).cast<Map<String, dynamic>>();

      final roleMap = <String, AgencyMemberRole>{};
      for (final r in roleRows) {
        final uid = r['user_id']?.toString() ?? '';
        if (uid.isEmpty) continue;
        roleMap[uid] = AgencyMemberRole.fromString(r['role']?.toString());
      }

      final necklaceMap = <String, String>{};
      for (final r in necklaceRows) {
        final uid = r['user_id']?.toString() ?? '';
        final url = r['asset_url']?.toString() ?? '';
        if (uid.isNotEmpty && url.isNotEmpty) necklaceMap[uid] = url;
      }

      final result = <String, AgencyChatUserMeta>{};
      for (final p in profileRows) {
        final uid = p['id']?.toString() ?? '';
        if (uid.isEmpty) continue;
        result[uid] = AgencyChatUserMeta(
          avatarUrl:       p['avatar_url']?.toString(),
          chatFrameUrl:    p['chat_frame_url']?.toString(),
          vipLevel:        (p['vip_level'] as int?) ?? 0,
          agencyRole:      roleMap[uid],
          countryCode:     p['country']?.toString(),
          necklaceIconUrl: necklaceMap[uid],
        );
      }
      return result;
    } catch (e) {
      debugPrint('[AgencyChatRepository] fetchUserMeta error: $e');
      return {};
    }
  }

  // ── دعوة مستخدم بـ Kayan ID ───────────────────────────────────────────────
  static Future<Map<String, dynamic>> inviteByKayanId({
    required String agencyId,
    required String kayanId,
  }) async {
    final cleanId = kayanId.trim();

    // 1. Try Supabase RPC first
    try {
      final resp = await _sb.rpc('agency_invite_by_kayan_id', params: {
        'p_agency_id': agencyId,
        'p_kayan_id':  cleanId,
      });
      if (resp != null && resp is Map) {
        final status = resp['status']?.toString();
        if (status != null && status != 'error') {
          return Map<String, dynamic>.from(resp);
        }
      }
    } catch (e) {
      debugPrint('[AgencyChatRepository] inviteByKayanId RPC error: $e');
    }

    // 2. Resilient fallback: find user and create invitation directly
    try {
      final user = await SupabaseDataService().findUserByIdOrCustomId(cleanId);
      if (user == null) {
        return {'status': 'not_found'};
      }

      // Check if already in this agency
      if (user.agencyId == agencyId) {
        return {'status': 'already_member'};
      }
      if (user.agencyId != null && user.agencyId!.isNotEmpty && user.agencyId != agencyId) {
        return {'status': 'in_other_agency'};
      }

      final reqId = const Uuid().v4();
      final nowIso = DateTime.now().toUtc().toIso8601String();

      // Upsert in Supabase host_agency_join_requests
      try {
        await _sb.from('host_agency_join_requests').upsert({
          'id': reqId,
          'agency_id': agencyId,
          'user_id': user.uid,
          'host_uid': user.uid,
          'applicant_uid': user.uid,
          'status': 'invited',
          'created_at': nowIso,
        });
      } catch (sbErr) {
        debugPrint('[AgencyChatRepository] fallback sb invite error: $sbErr');
      }

      // Send invitation notification via Supabase
      try {
        await SupabaseDataService().sendNotification(
          uid: user.uid,
          title: 'دعوة انضمام لوكالة مضيفين 🎙️',
          body: 'تمت دعوتك للانضمام كمضيف رسمي في الوكالة.',
          type: 'host_invite',
          data: {'agency_id': agencyId, 'action': 'host_invite'},
        );
      } catch (notifErr) {
        debugPrint('[AgencyChatRepository] notification error: $notifErr');
      }

      return {
        'status': 'invited',
        'user_id': user.uid,
        'display_name': user.name,
        'avatar_url': user.photoUrl,
        'custom_id': user.customId,
        'level': user.level,
        'country': user.country,
      };
    } catch (fallbackErr) {
      debugPrint('[AgencyChatRepository] invite fallback error: $fallbackErr');
      return {'status': 'error'};
    }
  }

  // ── تعيين / إلغاء مشرف ───────────────────────────────────────────────────
  static Future<Map<String, dynamic>> assignSupervisor({
    required String agencyId,
    required String userId,
  }) async {
    try {
      final resp = await _sb.rpc('agency_assign_supervisor', params: {
        'p_agency_id': agencyId,
        'p_user_id':   userId,
      });
      return Map<String, dynamic>.from(resp as Map);
    } catch (e) {
      debugPrint('[AgencyChatRepository] assignSupervisor error: $e');
      return {'status': 'error'};
    }
  }

  static Future<Map<String, dynamic>> revokeSupervisor({
    required String agencyId,
    required String userId,
  }) async {
    try {
      final resp = await _sb.rpc('agency_revoke_supervisor', params: {
        'p_agency_id': agencyId,
        'p_user_id':   userId,
      });
      return Map<String, dynamic>.from(resp as Map);
    } catch (e) {
      debugPrint('[AgencyChatRepository] revokeSupervisor error: $e');
      return {'status': 'error'};
    }
  }
}
