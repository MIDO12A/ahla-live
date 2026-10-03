import 'package:flutter/material.dart';
import '../../../core/supabase_compat.dart';

import '../../../core/utils/server_time_service.dart';
import 'package:flutter/foundation.dart';

import '../../../core/cache/encrypted_image_provider.dart';

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
      List<dynamic> reqResp = [];
      try {
        reqResp = await _sb.from('host_agency_join_requests')
            .select('id, user_id, status, created_at')
            .eq('agency_id', widget.agencyId)
            .inFilter('status', ['pending', 'invited', 'rejected'])
            .order('created_at', ascending: false)
            .limit(200);
      } catch (e) {
        debugPrint('[AgencyJoinRequests] reqResp error: $e');
      }

      List<dynamic> membResp = [];
      try {
        membResp = await _sb.from('host_agency_members')
            .select('id, user_id, role, status, joined_at, kicked_at')
            .eq('agency_id', widget.agencyId)
            .neq('role', 'owner')
            .inFilter('status', ['active', 'pending', 'suspended', 'kicked', 'left'])
            .order('joined_at', ascending: false)
            .limit(200);
      } catch (e) {
        debugPrint('[AgencyJoinRequests] membResp error: $e');
      }

      final allUserIds = <String>{};
      for (final r in reqResp) {
        final uid = r['user_id']?.toString();
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
              .select('id, uid, name, photo_url, avatar, custom_id, level')
              .filter('id', 'in', allUserIds.toList());
          for (final u in usersData) {
            final uId = u['id']?.toString() ?? u['uid']?.toString() ?? '';
            final photo = u['photo_url']?.toString() ?? u['avatar']?.toString();
            userProfiles[uId] = {
              'display_name': u['name'] ?? 'مستخدم',
              'avatar_url': photo,
              'kayan_id': u['custom_id']?.toString() ?? '',
              'level': (u['level'] as num?)?.toInt() ?? 1,
            };
          }
        } catch (_) {}
      }

      final requests = reqResp.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final uid = m['user_id']?.toString() ?? '';
        m['_req_id'] = m['id'];
        m['_source'] = 'request';
        m['profile'] = userProfiles[uid] ?? {
          'display_name': 'مستخدم',
          'avatar_url': null,
          'kayan_id': '',
          'level': 1,
        };
        return m;
      }).toList();

      final members = membResp.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final uid = m['user_id']?.toString() ?? m['host_uid']?.toString() ?? '';
        m['user_id'] = uid;
        m['_source'] = 'member';
        m['profile'] = userProfiles[uid] ?? {
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
          ...members.where((m) => ['kicked', 'left', 'suspended'].contains(m['status'])),
        ]..sort((a, b) => (b['created_at'] ?? b['kicked_at'] ?? '').toString()
            .compareTo((a['created_at'] ?? a['kicked_at'] ?? '').toString()));
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
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
        await _sb.from('host_agency_join_requests')
            .update({'status': 'accepted', 'resolved_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', reqId);
        if (userId.isNotEmpty) {
          await _sb.from('host_agency_members').upsert({
            'agency_id': widget.agencyId,
            'user_id': userId,
            'role': 'host',
            'status': 'active',
            'joined_at': DateTime.now().toUtc().toIso8601String(),
          });
          await _sb.from('users').update({'agency_id': widget.agencyId}).eq('id', userId);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم قبول العضو'), backgroundColor: Color(0xFF2E7D32)),
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
  Future<void> _reject(String reqId) async {
    try {
      // ✅ تحديث host_agency_join_requests بالـ request ID
      await _sb.from('host_agency_join_requests')
          .update({'status': 'rejected', 'resolved_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', reqId)
          .eq('agency_id', widget.agencyId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم رفض الطلب')),
      );
      _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
      );
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
      // استدعاء RPC الرسمي — يُطبّق كل قواعد العمل:
      // ✅ التحقق من الصلاحيات (مالك/مشرف فقط)
      // ✅ فحص نافذة الطرد (1-5 من الشهر) بتوقيت السعودية
      // ✅ حماية الألماس (لا تُمس لحظة الطرد)
      // ✅ تسجيل في agency_free_agents مع free_agent_until
      // ✅ إشعار الوكالة عبر Realtime
      // ✅ إصلاح: RPC يقبل p_user_id (UUID) — لا int.parse
      await _sb.rpc('agency_kick_member', params: {
        'p_agency_id': widget.agencyId,
        'p_user_id':   memberId,   // memberId هو user_id (UUID)
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم طرد العضو — لديه 7 أيام للانتقال لوكالة أخرى'),
          backgroundColor: Color(0xFFBF360C),
          duration: Duration(seconds: 4),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      // عرض رسالة الخطأ من قاعدة البيانات بشكل واضح
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
