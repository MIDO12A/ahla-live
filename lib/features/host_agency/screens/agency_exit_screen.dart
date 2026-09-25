import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../../providers/user_provider.dart';
import '../../../services/firebase_service.dart';
import '../../../core/ui/in_app_toast.dart';
import '../data/agency_repository.dart';
import '../data/agency_models.dart';

// ═══════════════════════════════════════════════════════════════════
//  AgencyExitScreen — شاشة الخروج من الوكالة وإدارتها
//  - إذا كان المستخدم وكيل / مالك الوكالة:
//    • حذف الوكالة نهائياً
//    • فك ارتباط جميع المضيفين والأعضاء وإلغاء الوكالة من حساباتهم
//    • حذف وتصفير جميع مراحل وأهداف المستخدمين في الوكالة
//  - إذا كان المستخدم عضواً / مضيفاً:
//    • خروج من الوكالة وتصفير مراحله وإلغاء ارتباطه
// ═══════════════════════════════════════════════════════════════════
class AgencyExitScreen extends StatefulWidget {
  final String? agencyId;

  const AgencyExitScreen({super.key, this.agencyId});

  @override
  State<AgencyExitScreen> createState() => _AgencyExitScreenState();
}

class _AgencyExitScreenState extends State<AgencyExitScreen> {
  bool _loading = true;
  bool _processing = false;
  bool _isOwner = false;

  String? _agencyId;
  String _agencyName = '';
  int _memberCount = 0;
  String _tier = 'bronze';

  AgencyMemberInfo? _member;
  Map<String, dynamic>? _exitInfo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final uid = FirebaseAuth.instance.currentUser?.uid ??
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid;

    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      // 1. فحص ما إذا كان المستخدم هو وكيل / مالك الوكالة
      bool isOwner = false;
      String? aid = widget.agencyId;
      String aname = '';
      int mcount = 0;
      String tier = 'bronze';

      // أ) البحث بالـ agencyId المحدد
      if (aid != null && aid.isNotEmpty) {
        final agDoc = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('host_agencies').doc(aid).get();
        if (agDoc.exists) {
          final data = agDoc.data() ?? {};
          if (data['owner_id'] == uid) {
            isOwner = true;
          }
          aname = data['name']?.toString() ?? 'الوكالة';
          mcount = (data['member_count'] as num?)?.toInt() ?? 0;
          tier = data['tier']?.toString() ?? 'bronze';
        }
      }

      // ب) البحث في host_agencies حيث owner_id == uid
      if (!isOwner) {
        final ownerAgSnap = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
            .collection('host_agencies')
            .where('owner_id', isEqualTo: uid)
            .limit(1)
            .get();
        if (ownerAgSnap.docs.isNotEmpty) {
          isOwner = true;
          final d = ownerAgSnap.docs.first;
          aid = d.id;
          final data = d.data();
          aname = data['name']?.toString() ?? 'الوكالة';
          mcount = (data['member_count'] as num?)?.toInt() ?? 0;
          tier = data['tier']?.toString() ?? 'bronze';
        }
      }

      // ج) فحص host_agency_members حيث role == 'owner'
      if (!isOwner) {
        final memSnap = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
            .collection('host_agency_members')
            .where('user_id', isEqualTo: uid)
            .where('role', isEqualTo: 'owner')
            .limit(1)
            .get();
        if (memSnap.docs.isNotEmpty) {
          isOwner = true;
          aid ??= memSnap.docs.first.data()['agency_id']?.toString();
        }
      }

      // د) فحص users/{uid}.is_host_agent
      if (!isOwner) {
        final uDoc = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('users').doc(uid).get();
        if (uDoc.data()?['is_host_agent'] == true) {
          isOwner = true;
          aid ??= uDoc.data()?['agency_id']?.toString();
        }
      }

      // 2. إذا كان عضواً عادياً (مضيفاً)
      AgencyMemberInfo? memberInfo;
      if (!isOwner) {
        final stats = await AgencyRepository.getHostStats();
        memberInfo = stats?.member;
        if (aid == null || aid.isEmpty) {
          aid = memberInfo?.agencyId;
        }
        if (aid == null || aid.isEmpty) {
          final uDoc = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('users').doc(uid).get();
          aid = uDoc.data()?['agency_id']?.toString() ?? uDoc.data()?['host_agency_id']?.toString();
        }
        if (aname.isEmpty && aid != null && aid.isNotEmpty) {
          final agDoc = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('host_agencies').doc(aid).get();
          if (agDoc.exists) {
            aname = agDoc.data()?['name']?.toString() ?? 'الوكالة';
          }
        }
      }

      if (mounted) {
        setState(() {
          _isOwner = isOwner;
          _agencyId = aid;
          _agencyName = aname;
          _memberCount = mcount;
          _tier = tier;
          _member = memberInfo;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[AgencyExitScreen] load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── خروج الوكيل وحذف الوكالة نهائياً ─────────────────────────────
  Future<void> _handleOwnerExitAndDelete() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ??
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1414),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFFF5252), width: 1.5)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFFF5252), size: 28),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'تأكيد نهائي لحذف الوكالة',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: const Text(
          'أنت على وشك حذف الوكالة نهائياً والخروج منها بصفتك الوكيل والمؤسس.\n\n'
          '⚠️ سيؤدي هذا الإجراء فوراً إلى:\n'
          '• حذف الوكالة نهائياً من التطبيق.\n'
          '• إلغاء ارتباط جميع المضيفين والأعضاء وإزالة الوكالة من حساباتهم.\n'
          '• حذف وتصفير جميع مراحل وأهداف المستخدمين التابعين للوكالة.\n\n'
          'هل أنت متأكد تماماً من المتابعة؟ لا يمكن التراجع عن هذا الإجراء.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء التراجع', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5252),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('نعم، حذف الوكالة نهائياً', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _processing = true);

    try {
      final success = await FirebaseService().deleteAndExitAgencyByOwner(
        agencyId: _agencyId ?? '',
        ownerUid: uid,
      );

      if (!mounted) return;

      if (success) {
        KayanInAppToast.agency('✅ تم حذف الوكالة وتصفير مراحل جميع الأعضاء وفك ارتباطهم بنجاح');
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدث خطأ أثناء محاولة حذف الوكالة'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  // ─── خروج العضو (المضيف) من الوكالة ──────────────────────────────
  Future<void> _handleMemberExit() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ??
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F1B2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFD4AF37), width: 1)),
        title: const Row(
          children: [
            Icon(Icons.exit_to_app_rounded, color: Color(0xFFFF5252), size: 26),
            SizedBox(width: 8),
            Text('تأكيد مغادرة الوكالة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: const Text(
          'عند خروجك من الوكالة:\n'
          '• سيتم فك ارتباطك بالوكالة وإزالتها من حسابك.\n'
          '• سيتم حذف وتصفير مراحل التارجت المحققة الخاصة بك في هذه الوكالة.\n'
          '• ستحصل على وضع وكيل حر لمدة 7 أيام.\n\n'
          'هل تريد الاستمرار؟',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5252),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('تأكيد المغادرة', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _processing = true);

    try {
      final success = await FirebaseService().exitAgencyAsMember(
        agencyId: _agencyId ?? '',
        userId: uid,
      );

      if (!mounted) return;

      if (success) {
        KayanInAppToast.agency('✅ تم الخروج من الوكالة وتصفير مراحل التارجت بنجاح');
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر الخروج من الوكالة حالياً'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D1A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D0D1A),
          foregroundColor: Colors.white,
          title: Text(
            _isOwner ? 'إدارة وإنهاء الوكالة (الوكيل)' : 'مغادرة الوكالة',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          elevation: 0,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
            : _isOwner
                ? _buildOwnerView()
                : _buildMemberView(),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  //  واجهة خروج الوكيل وحذف الوكالة بالكامل
  // ═════════════════════════════════════════════════════════════════
  Widget _buildOwnerView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Owner badge header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2E1212), Color(0xFF1A0A0A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.4), width: 1.5),
              boxShadow: [
                BoxShadow(color: const Color(0xFFFF5252).withOpacity(0.15), blurRadius: 16, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5252).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shield_outlined, color: Color(0xFFFF5252), size: 40),
                ),
                const SizedBox(height: 14),
                const Text(
                  'أنت وكيل ومؤسس الوكالة',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  _agencyName.isNotEmpty ? _agencyName : 'وكالتي الرسمية',
                  style: const TextStyle(color: Color(0xFFFFD700), fontSize: 15, fontWeight: FontWeight.w600),
                ),
                if (_agencyId != null && _agencyId!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'معرف الوكالة: ${_agencyId!}',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Agency Quick Stats
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatMini(label: 'الأعضاء والمضيفين', value: '$_memberCount مضيف', icon: Icons.people_outline, color: const Color(0xFF00E5FF)),
                Container(width: 1, height: 32, color: Colors.white12),
                _StatMini(label: 'رتبة الوكالة', value: _tier.toUpperCase(), icon: Icons.workspace_premium_outlined, color: const Color(0xFFFFD700)),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Full Warning Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFFF5252).withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning_rounded, color: Color(0xFFFF5252), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'ماذا يحدث عند خروج الوكيل؟',
                      style: TextStyle(color: Color(0xFFFF5252), fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _WarningPoint(text: 'يتم حذف الوكالة نهائياً من قاعدة البيانات والتطبيق.'),
                _WarningPoint(text: 'يتم إلغاء ارتباط جميع المضيفين والأعضاء وإزالة الوكالة من حساباتهم.'),
                _WarningPoint(text: 'يتم حذف وتصفير جميع مراحل وأهداف وتارجت المستخدمين المسجلين في الوكالة.'),
                _WarningPoint(text: 'هذا الإجراء فوري ونهائي ولا يمكن التراجع عنه.'),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Big Red Action Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _processing ? null : _handleOwnerExitAndDelete,
              icon: _processing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.delete_forever_rounded, size: 24),
              label: Text(
                _processing ? 'جاري حذف الوكالة والأعضاء...' : 'الخروج من الوكالة وحذفها نهائياً',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5252),
                foregroundColor: Colors.white,
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  //  واجهة خروج العضو (المضيف)
  // ═════════════════════════════════════════════════════════════════
  Widget _buildMemberView() {
    final m = _member;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Warning card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFF5252).withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.25)),
            ),
            child: Column(
              children: [
                const Icon(Icons.exit_to_app_rounded, color: Color(0xFFFF5252), size: 44),
                const SizedBox(height: 12),
                const Text(
                  'مغادرة الوكالة',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'عند مغادرة الوكالة سيتم فك ارتباطك بالوكالة فوراً وتصفير مراحل التارجت المحققة بالوكالة.',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13, height: 1.5),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          if (m != null) ...[
            _InfoRow(icon: '♦', label: 'رصيد الألماس الحالي', value: '${_fmtK(m.diamondsBalance)} ♦', color: const Color(0xFFB39DDB)),
            const SizedBox(height: 12),
            _InfoRow(icon: '📊', label: 'ألماس الشهر (سيُصفَّر)', value: '${_fmtK(m.diamondsEarnedMonthly)} ♦', color: const Color(0xFFFF9800)),
            const SizedBox(height: 24),
          ],

          // Exit Action Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _processing ? null : _handleMemberExit,
              icon: _processing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.exit_to_app_rounded),
              label: Text(
                _processing ? 'جاري المغادرة...' : 'تأكيد الخروج من الوكالة',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5252),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Rules reminder
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📋 قواعد المغادرة', style: TextStyle(color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                _Rule('عند الخروج: يتم إلغاء تبعية حسابك للوكالة فوراً.'),
                _Rule('يتم تصفير مراحل وتارجت الألماس التابعة للوكالة السابقة.'),
                _Rule('ستحصل على وضع "وكيل حر" لمدة 7 أيام للانضمام لوكالة أخرى.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtK(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toString();
  }
}

class _StatMini extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatMini({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
      ],
    );
  }
}

class _WarningPoint extends StatelessWidget {
  final String text;
  const _WarningPoint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Color(0xFFFF5252), fontSize: 14, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final Color color;
  const _InfoRow({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13))),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
      ]),
    );
  }
}

class _Rule extends StatelessWidget {
  final String text;
  const _Rule(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('• ', style: TextStyle(color: Colors.white.withOpacity(0.4))),
        Expanded(child: Text(text, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12, height: 1.5))),
      ]),
    );
  }
}
