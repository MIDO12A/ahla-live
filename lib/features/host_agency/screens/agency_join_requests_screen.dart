import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../core/supabase_compat.dart';
import '../../../core/utils/server_time_service.dart';
import 'package:flutter/foundation.dart';
import '../../../core/cache/encrypted_image_provider.dart';
import '../../../services/supabase_service.dart';

// ═══════════════════════════════════════════════════════════════════
//  AgencyJoinRequestsScreen — طلبات الانضمام (للمالك والمشرف)
//  يعرض: طلبات pending + قبول + رفض + بحث بالاسم
//  يدعم Realtime للتحديث الفوري
// ═══════════════════════════════════════════════════════════════════
class AgencyJoinRequestsScreen extends StatefulWidget {
  final String agencyId;
  /// إذا كان false: تُخفى أزرار الطرد (للمشرف الذي لا يملك صلاحية الطرد)
  final bool canKick;
  const AgencyJoinRequestsScreen({
    super.key,
    required this.agencyId,
    this.canKick = true,
  });

  @override
  State<AgencyJoinRequestsScreen> createState() => _AgencyJoinRequestsScreenState();
}

class _AgencyJoinRequestsScreenState extends State<AgencyJoinRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _sb = Supabase.instance.client;

  List<Map<String, dynamic>> _pending  = [];
  List<Map<String, dynamic>> _approved = [];
  List<Map<String, dynamic>> _rejected = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  void _subscribeRealtime() {
    _channel = _sb
        .channel('join_requests_${widget.agencyId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'host_agency_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'agency_id',
            value: widget.agencyId,
          ),
          callback: (_) => _load(),
        )
        .subscribe();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final candidateAgencyIds = <String>{widget.agencyId};
      try {
        final fs = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
        final aDoc = await fs.collection('host_agencies').doc(widget.agencyId).get();
        if (aDoc.exists) {
          final ad = aDoc.data() ?? {};
          if (ad['id'] != null) candidateAgencyIds.add(ad['id'].toString());
          if (ad['agency_id'] != null) candidateAgencyIds.add(ad['agency_id'].toString());
          if (ad['custom_id'] != null) candidateAgencyIds.add(ad['custom_id'].toString());
          if (ad['user_id'] != null) candidateAgencyIds.add(ad['user_id'].toString());
          if (ad['owner_id'] != null) candidateAgencyIds.add(ad['owner_id'].toString());
          if (ad['owner_uid'] != null) candidateAgencyIds.add(ad['owner_uid'].toString());
        }
      } catch (_) {}

      // 1. Fetch join requests from Supabase
      List<dynamic> reqResp = [];
      try {
        final res = await _sb.from('host_agency_join_requests')
            .select('*')
            .inFilter('agency_id', candidateAgencyIds.toList())
            .order('created_at', ascending: false)
            .limit(200);
        reqResp = List<dynamic>.from(res as List);
      } catch (e) {
        debugPrint('[AgencyJoinRequests] sb reqResp error: $e');
      }

      // 2. Fetch pending requests from Firestore across candidate agency IDs
      try {
        final fs = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
        final fsReqSnap = await fs.collection('host_agency_join_requests')
            .where('agency_id', whereIn: candidateAgencyIds.take(10).toList())
            .get();
        for (final doc in fsReqSnap.docs) {
          final data = doc.data();
          final id = doc.id;
          final uid = data['user_id']?.toString() ?? data['host_uid']?.toString() ?? data['applicant_uid']?.toString() ?? '';
          if (uid.isEmpty) continue;
          final already = reqResp.any((r) => r['id']?.toString() == id || (r['user_id']?.toString() == uid || r['host_uid']?.toString() == uid));
          if (!already) {
            reqResp.add({
              'id': id,
              'user_id': uid,
              'host_uid': uid,
              'status': data['status']?.toString() ?? 'pending',
              'created_at': data['created_at']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
              '_from_fs': true,
              '_user_name': data['user_name'],
              '_user_avatar': data['user_avatar'],
              '_custom_id': data['custom_id'],
            });
          }
        }

        // Also check if any join request notifications exist for the owner
        final notifsSnap = await fs.collection('notifications')
            .where('type', isEqualTo: 'agency_host_request')
            .limit(50)
            .get();
        for (final nDoc in notifsSnap.docs) {
          final nData = nDoc.data();
          final notifAgencyId = nData['data']?['agency_id']?.toString() ?? '';
          final applicantUid = nData['data']?['applicant_uid']?.toString() ?? nData['actor_uid']?.toString() ?? '';
          if (applicantUid.isNotEmpty && (candidateAgencyIds.contains(notifAgencyId) || candidateAgencyIds.contains(nData['uid']))) {
            final already = reqResp.any((r) => (r['user_id']?.toString() == applicantUid || r['host_uid']?.toString() == applicantUid));
            if (!already) {
              reqResp.add({
                'id': nDoc.id,
                'user_id': applicantUid,
                'host_uid': applicantUid,
                'status': 'pending',
                'created_at': nData['created_at']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
                '_from_fs': true,
                '_user_name': nData['data']?['applicant_name'] ?? nData['title'] ?? 'مستخدم',
                '_user_avatar': '',
                '_custom_id': '',
              });
            }
          }
        }
      } catch (e) {
        debugPrint('[AgencyJoinRequests] fsReqSnap error: $e');
      }

      // 3. Fetch members from Supabase
      List<dynamic> membResp = [];
      try {
        final res = await _sb.from('host_agency_members')
            .select('*')
            .inFilter('agency_id', candidateAgencyIds.toList())
            .neq('role', 'owner')
            .order('joined_at', ascending: false)
            .limit(200);
        membResp = List<dynamic>.from(res as List);
      } catch (e) {
        debugPrint('[AgencyJoinRequests] sb membResp error: $e');
      }

      // 4. Also fetch members from Firestore
      try {
        final fs = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
        final fsMembSnap = await fs.collection('host_agency_members')
            .where('agency_id', whereIn: candidateAgencyIds.take(10).toList())
            .get();
        for (final doc in fsMembSnap.docs) {
          final data = doc.data();
          final uid = data['user_id']?.toString() ?? data['host_uid']?.toString() ?? '';
          final role = data['role']?.toString() ?? 'host';
          if (role == 'owner' || uid.isEmpty) continue;
          final already = membResp.any((m) => m['id']?.toString() == doc.id || (m['user_id']?.toString() == uid || m['host_uid']?.toString() == uid));
          if (!already) {
            membResp.add({
              'id': doc.id,
              'user_id': uid,
              'host_uid': uid,
              'role': role,
              'status': data['status']?.toString() ?? 'active',
              'joined_at': data['joined_at']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
              'kicked_at': data['kicked_at']?.toString(),
            });
          }
        }
      } catch (e) {
        debugPrint('[AgencyJoinRequests] fsMembSnap error: $e');
      }

      final allUserIds = <String>{};
      for (final r in reqResp) {
        final uid = r['user_id']?.toString() ?? r['host_uid']?.toString() ?? r['applicant_uid']?.toString();
        if (uid != null && uid.isNotEmpty) allUserIds.add(uid);
      }
      for (final m in membResp) {
        final uid = m['user_id']?.toString() ?? m['host_uid']?.toString();
        if (uid != null && uid.isNotEmpty) allUserIds.add(uid);
      }

      final userProfiles = <String, Map<String, dynamic>>{};
      if (allUserIds.isNotEmpty) {
        try {
          final usersData = await _sb.from('users')
              .select('uid, name, photo_url, custom_id, level')
              .inFilter('uid', allUserIds.toList());
          for (final u in usersData) {
            final uId = u['uid']?.toString() ?? '';
            final photo = u['photo_url']?.toString();
            userProfiles[uId] = {
              'display_name': u['name'] ?? 'مستخدم',
              'avatar_url': photo,
              'kayan_id': u['custom_id']?.toString() ?? '',
              'level': (u['level'] as num?)?.toInt() ?? 1,
            };
          }
        } catch (e) {
          debugPrint('[AgencyJoinRequests] sb usersData error: $e');
        }

        // Fallback to Firestore users if missing or incomplete
        for (final uid in allUserIds) {
          if (!userProfiles.containsKey(uid) || userProfiles[uid]?['display_name'] == 'مستخدم') {
            try {
              final fs = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
              final uDoc = await fs.collection('users').doc(uid).get();
              if (uDoc.exists) {
                final d = uDoc.data() ?? {};
                userProfiles[uid] = {
                  'display_name': d['name'] ?? d['displayName'] ?? userProfiles[uid]?['display_name'] ?? 'مستخدم',
                  'avatar_url': d['photo_url'] ?? d['avatar'] ?? d['photoUrl'] ?? userProfiles[uid]?['avatar_url'],
                  'kayan_id': d['custom_id']?.toString() ?? d['customId']?.toString() ?? userProfiles[uid]?['kayan_id'] ?? '',
                  'level': (d['level'] as num?)?.toInt() ?? userProfiles[uid]?['level'] ?? 1,
                };
              }
            } catch (_) {}
          }
        }
      }

      final requests = reqResp.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final uid = m['user_id']?.toString() ?? m['host_uid']?.toString() ?? m['applicant_uid']?.toString() ?? '';
        m['user_id'] = uid;
        m['_req_id'] = m['id'];
        m['_source'] = 'request';
        final cachedProf = userProfiles[uid];
        m['profile'] = {
          'display_name': cachedProf?['display_name'] ?? m['_user_name'] ?? 'مستخدم',
          'avatar_url': cachedProf?['avatar_url'] ?? m['_user_avatar'],
          'kayan_id': cachedProf?['kayan_id'] ?? m['_custom_id']?.toString() ?? '',
          'level': cachedProf?['level'] ?? 1,
        };
        return m;
      }).toList();

      final members = membResp.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final uid = m['user_id']?.toString() ?? m['host_uid']?.toString() ?? '';
        m['user_id'] = uid;
        m['_source'] = 'member';
        final cachedProf = userProfiles[uid];
        m['profile'] = cachedProf ?? {
          'display_name': 'مستخدم',
          'avatar_url': null,
          'kayan_id': '',
          'level': 1,
        };
        return m;
      }).toList();

      if (!mounted) return;
      setState(() {
        _pending = [
          ...requests.where((m) => ['pending', 'invited'].contains(m['status'])),
          ...members.where((m) => m['status'] == 'pending' && !requests.any((r) => r['user_id'] == m['user_id'])),
        ];
        _approved = members.where((m) => m['status'] == 'active').toList();
        _rejected = [
          ...requests.where((m) => m['status'] == 'rejected'),
          ...members.where((m) => ['kicked', 'left', 'suspended', 'rejected', 'pending_exit', 'terminated'].contains(m['status'])),
        ]..sort((a, b) => (b['created_at'] ?? b['kicked_at'] ?? '').toString()
            .compareTo((a['created_at'] ?? a['kicked_at'] ?? '').toString()));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      debugPrint('[AgencyJoinRequests] _load error: $e');
    }
  }

  // p_reqId = host_agency_join_requests.id or host_agency_members.id
  Future<void> _accept(String reqId, String userId) async {
    try {
      try {
        await _sb.rpc('agency_accept_member', params: {
          'p_request_id': reqId,
        });
      } catch (rpcErr) {
        debugPrint('[AgencyJoinRequests] rpc agency_accept_member failed, falling back to direct update: $rpcErr');
      }

      // Update Supabase
      try {
        await _sb.from('host_agency_join_requests')
            .update({'status': 'accepted', 'resolved_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', reqId);
      } catch (_) {}

      if (userId.isNotEmpty) {
        try {
          await _sb.from('host_agency_members').upsert({
            'agency_id': widget.agencyId,
            'host_uid': userId,
            'user_id': userId,
            'role': 'host',
            'status': 'active',
            'joined_at': DateTime.now().toUtc().toIso8601String(),
          });
        } catch (_) {}
        try {
          await _sb.from('users').update({'agency_id': widget.agencyId}).eq('uid', userId);
        } catch (_) {}
      }

      // Update Firestore
      try {
        final fs = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
        await fs.collection('host_agency_join_requests').doc(reqId).set({
          'status': 'approved',
          'resolved_at': DateTime.now().toUtc().toIso8601String(),
        }, SetOptions(merge: true));

        if (userId.isNotEmpty) {
          await fs.collection('host_agency_join_requests').doc('${widget.agencyId}_$userId').set({
            'status': 'approved',
            'resolved_at': DateTime.now().toUtc().toIso8601String(),
          }, SetOptions(merge: true));

          await fs.collection('host_agency_members').doc('${widget.agencyId}_$userId').set({
            'agency_id': widget.agencyId,
            'user_id': userId,
            'role': 'host',
            'status': 'active',
            'joined_at': DateTime.now().toUtc().toIso8601String(),
          }, SetOptions(merge: true));

          await fs.collection('users').doc(userId).set({
            'agency_id': widget.agencyId,
            'is_agency_member': true,
          }, SetOptions(merge: true));

          await fs.collection('host_agencies').doc(widget.agencyId).set({
            'member_count': FieldValue.increment(1),
          }, SetOptions(merge: true));

          FirebaseService().sendNotification(
            uid: userId,
            type: 'agency_host_accepted',
            title: 'تم قبول انضمامك للوكالة 🎉',
            body: 'تهانينا! تمت الموافقة على طلب انضمامك إلى الوكالة كمضيف رسمي.',
            data: {'agency_id': widget.agencyId, 'status': 'accepted'},
          ).catchError((_) {});
        }
      } catch (fsErr) {
        debugPrint('[AgencyJoinRequests] Firestore accept error: $fsErr');
      }

      // Immediately remove accepted request from pending list locally and add to approved list
      final acceptedReq = _pending.firstWhere(
        (m) => m['_req_id'] == reqId || m['id'] == reqId || m['user_id'] == userId,
        orElse: () => <String, dynamic>{},
      );
      if (mounted) {
        setState(() {
          _pending.removeWhere((m) => m['_req_id'] == reqId || m['id'] == reqId || m['user_id'] == userId);
          if (acceptedReq.isNotEmpty) {
            final activeMember = Map<String, dynamic>.from(acceptedReq);
            activeMember['status'] = 'active';
            activeMember['role'] = 'host';
            activeMember['_source'] = 'member';
            if (!_approved.any((m) => m['user_id'] == userId)) {
              _approved.insert(0, activeMember);
            }
          }
        });
      }

      // Also clean up any pending notifications / Firestore request docs
      try {
        final fs = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
        await fs.collection('host_agency_join_requests').doc(reqId).delete();
        if (userId.isNotEmpty) {
          await fs.collection('host_agency_join_requests').doc('${widget.agencyId}_$userId').delete();
        }
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم قبول العضو في الوكالة بنجاح'), backgroundColor: Color(0xFF2E7D32)),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // userId = host_agency_join_requests.user_id أو host_agency_join_requests.id
  Future<void> _reject(String reqId, [String? userId]) async {
    try {
      // 1. Supabase
      try {
        await _sb.from('host_agency_join_requests')
            .update({'status': 'rejected', 'resolved_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', reqId)
            .eq('agency_id', widget.agencyId);
      } catch (_) {}

      // 2. Firestore
      try {
        final fs = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
        await fs.collection('host_agency_join_requests').doc(reqId).set({
          'status': 'rejected',
          'resolved_at': DateTime.now().toUtc().toIso8601String(),
        }, SetOptions(merge: true));

        if (userId != null && userId.isNotEmpty) {
          await fs.collection('host_agency_join_requests').doc('${widget.agencyId}_$userId').set({
            'status': 'rejected',
            'resolved_at': DateTime.now().toUtc().toIso8601String(),
          }, SetOptions(merge: true));
          await fs.collection('host_agency_members').doc('${widget.agencyId}_$userId').delete();

          FirebaseService().sendNotification(
            uid: userId,
            type: 'agency_host_rejected',
            title: 'تم رفض طلب الانضمام للوكالة',
            body: 'للأسف، تم رفض طلب انضمامك إلى الوكالة.',
            data: {'agency_id': widget.agencyId, 'status': 'rejected'},
          ).catchError((_) {});
        }
      } catch (fsErr) {
        debugPrint('[AgencyJoinRequests] Firestore reject error: $fsErr');
      }

      if (mounted) {
        setState(() {
          _pending.removeWhere((m) => m['_req_id'] == reqId || m['id'] == reqId || (userId != null && m['user_id'] == userId));
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم رفض الطلب')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _kick(String memberId) async {
    // فحص مبدئي في الواجهة (نافذة الطرد أيام 1-5) — وقت السيرفر السعودي
    if (ServerTimeService.instance.dayOfMonth > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ لا يمكن طرد الأعضاء بعد اليوم الخامس من الشهر.'),
          backgroundColor: Color(0xFFFF6F00),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('تأكيد الطرد', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هل تريد طرد هذا العضو من الوكالة؟',
              style: TextStyle(color: Colors.white.withOpacity(0.85)),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6F00).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFF6F00).withOpacity(0.3)),
              ),
              child: Text(
                'سيمنح العضو 7 أيام للانتقال لوكالة أخرى أو سحب ألماسه.\n'
                'بعد 7 أيام بدون انضمام، يتحول ألماسه لكوينز بنسبة 50%.',
                style: TextStyle(color: Colors.orange.shade300, fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('طرد', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      bool rpcSuccess = false;
      try {
        await _sb.rpc('agency_kick_member', params: {
          'p_agency_id': widget.agencyId,
          'p_user_id':   memberId,
        });
        rpcSuccess = true;
      } catch (rpcErr) {
        debugPrint('[AgencyJoinRequests] rpc agency_kick_member failed, falling back to direct update: $rpcErr');
      }

      final nowIso = DateTime.now().toUtc().toIso8601String();
      // Supabase direct fallback
      try {
        await _sb.from('host_agency_members')
            .update({'status': 'kicked', 'kicked_at': nowIso})
            .eq('agency_id', widget.agencyId)
            .or('id.eq.$memberId,user_id.eq.$memberId,host_uid.eq.$memberId');
        await _sb.from('users').update({'agency_id': null}).or('uid.eq.$memberId,id.eq.$memberId');
      } catch (_) {}

      // Firestore direct fallback
      try {
        final fs = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
        await fs.collection('host_agency_members').doc(memberId).set({
          'status': 'kicked',
          'kicked_at': nowIso,
        }, SetOptions(merge: true));
        await fs.collection('host_agency_members').doc('${widget.agencyId}_$memberId').set({
          'status': 'kicked',
          'kicked_at': nowIso,
        }, SetOptions(merge: true));
        await fs.collection('users').doc(memberId).set({
          'agency_id': null,
          'is_agency_member': false,
        }, SetOptions(merge: true));
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم طرد العضو من الوكالة بنجاح'),
          backgroundColor: Color(0xFFBF360C),
          duration: Duration(seconds: 4),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('لا يمكن') || e.toString().contains('ليس لديك')
          ? e.toString().replaceAll(RegExp(r'^.*Exception: '), '')
          : 'خطأ في الطرد: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red.shade900),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        foregroundColor: Colors.white,
        title: const Text('طلبات الانضمام', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFFD4AF37),
          labelColor: const Color(0xFFD4AF37),
          unselectedLabelColor: Colors.white38,
          tabs: [
            Tab(text: 'معلق (${_pending.length})'),
            Tab(text: 'أعضاء (${_approved.length})'),
            Tab(text: 'مرفوض/مطرود (${_rejected.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
          : TabBarView(
              controller: _tabs,
              children: [
                _buildList(_pending,  canAccept: true,  canKick: false),
                _buildList(_approved, canAccept: false, canKick: widget.canKick),
                _buildList(_rejected, canAccept: false, canKick: false),
              ],
            ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> list, {required bool canAccept, required bool canKick}) {
    if (list.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🏢', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 12),
        Text('لا توجد سجلات', style: TextStyle(color: Colors.white.withOpacity(0.4))),
      ]));
    }
    return RefreshIndicator(
      color: const Color(0xFFD4AF37),
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        itemCount: list.length,
        itemBuilder: (_, i) => _MemberCard(
          data: list[i],
          canAccept: canAccept,
          canKick:   canKick,
          // طلبات معلقة: نمرر _req_id للقبول والرفض
          // أعضاء نشطون: نمرر user_id للطرد
          onAccept: () => _accept(
            list[i]['_req_id'] as String? ?? list[i]['id'] as String? ?? list[i]['user_id'] as String,
            list[i]['user_id'] as String? ?? '',
          ),
          onReject: () => _reject(
            list[i]['_req_id'] as String? ?? list[i]['user_id'] as String,
            list[i]['user_id'] as String? ?? '',
          ),
          onKick:   () => _kick(list[i]['user_id'] as String),
        ),
      ),
    );
  }
}

// ─── Member Card ─────────────────────────────────────────────────
class _MemberCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool canAccept;
  final bool canKick;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onKick;

  const _MemberCard({
    required this.data,
    required this.canAccept,
    required this.canKick,
    required this.onAccept,
    required this.onReject,
    required this.onKick,
  });

  @override
  Widget build(BuildContext context) {
    final profile       = data['profile'] as Map<String, dynamic>? ?? {};
    final name          = profile['display_name'] as String? ?? '—';
    final avatar        = profile['avatar_url'] as String?;
    final kayanId       = profile['kayan_id'] as String?;
    final level         = (profile['level'] as num?)?.toInt() ?? 1;
    final date          = data['created_at'] as String?;
    final status        = data['status'] as String? ?? '';
    final freeUntilRaw  = data['free_agent_until'] as String?;

    // حساب المدة المتبقية للوكيل الحر — مقارنةً بوقت السيرفر السعودي
    Duration? freeRemaining;
    if (status == 'kicked' && freeUntilRaw != null) {
      final freeUntil = DateTime.tryParse(freeUntilRaw);
      if (freeUntil != null) {
        // free_agent_until مخزون بتوقيت UTC في قاعدة البيانات
        // نحوله لـ UTC+3 للمقارنة مع وقت السيرفر السعودي
        final freeUntilRiyadh = freeUntil.toUtc().add(const Duration(hours: 3));
        final diff = freeUntilRiyadh.difference(ServerTimeService.instance.now());
        if (!diff.isNegative) freeRemaining = diff;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: status == 'kicked'
            ? Colors.red.withOpacity(0.05)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == 'kicked'
              ? Colors.red.withOpacity(0.25)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFD4AF37).withOpacity(0.2),
                backgroundImage: avatar != null ? EncryptedImageProvider(avatar) : null,
                child: avatar == null
                    ? Text(
                        name.characters.first,
                        style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                    if (status == 'kicked')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.withOpacity(0.4)),
                        ),
                        child: const Text('مطرود 🔴', style: TextStyle(color: Colors.red, fontSize: 10)),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    Text('Lv.$level', style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 11)),
                    if (kayanId != null) ...[
                      Text(' · #$kayanId',
                          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                    ],
                  ]),
                  if (date != null)
                    Text(_formatDate(date),
                        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10)),
                ]),
              ),
              // Actions
              Column(mainAxisSize: MainAxisSize.min, children: [
                if (canAccept) ...[
                  _SmallBtn(label: 'قبول', color: Colors.green, onTap: onAccept),
                  const SizedBox(height: 6),
                  _SmallBtn(label: 'رفض', color: Colors.red, onTap: onReject),
                ],
                if (canKick)
                  _SmallBtn(label: 'طرد', color: const Color(0xFFFF5252), onTap: onKick),
              ]),
            ],
          ),
          // شريط الوكيل الحر — يظهر فقط للمطرودين ضمن نافذة الـ 7 أيام
          if (status == 'kicked' && freeRemaining != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.25)),
              ),
              child: Row(children: [
                const Text('⏳', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Text(
                  'وكيل حر — متبقي ${freeRemaining.inDays} يوم و${freeRemaining.inHours % 24} ساعة',
                  style: TextStyle(color: Colors.orange.shade300, fontSize: 11),
                ),
              ]),
            ),
          ],
          // تحذير انتهاء مهلة الوكيل الحر
          if (status == 'kicked' && freeUntilRaw != null && freeRemaining == null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '⚠️ انتهت مهلة الوكيل الحر — تم تحويل الألماس لكوينز (50%)',
                style: TextStyle(color: Colors.red.shade300, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.day}/${d.month}/${d.year}';
    } catch (e) {
debugPrint('[agency_join_requests_screen] error: $e');
      return iso;
    }
  }
}

class _SmallBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SmallBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
