import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/supabase_compat.dart';
import '../../../core/ui/in_app_toast.dart';
import '../../../models/user_model.dart';
import '../../../services/supabase_data_service.dart';
import '../widgets/salary_disburse_dialog.dart';
import '../widgets/store_gift_dialog.dart';

const Color _bgDeep    = Color(0xFF070A1E);
const Color _bgCard    = Color(0xFF131835);
const Color _crimson   = Color(0xFFFF4D4D);
const Color _gold      = Color(0xFFFFB800);
const Color _cyan      = Color(0xFF00D4FF);
const Color _green     = Color(0xFF00E5A0);
const Color _textMain  = Color(0xFFFFFFFF);
const Color _textMuted = Color(0xFF8E9BB0);

class AdminCenterScreen extends StatefulWidget {
  final UserModel currentUser;

  const AdminCenterScreen({
    super.key,
    required this.currentUser,
  });

  @override
  State<AdminCenterScreen> createState() => _AdminCenterScreenState();
}

class _AdminCenterScreenState extends State<AdminCenterScreen> with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;

  late TabController _tabController;
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _agencies = [];
  List<Map<String, dynamic>> _bdManagers = [];

  int _totalDiamonds = 0;
  int _totalHosts = 0;
  double _salary = 0.0;
  double _commissionRate = 10.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _salary = widget.currentUser.adminSalary;
    _commissionRate = widget.currentUser.adminCommissionRate;
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _loading = true);
    try {
      final uid = widget.currentUser.uid;

      // 1. Fetch metadata from app_config if exists
      try {
        final cfg = await _sb.from('app_config').select('value').eq('key', 'admin_meta_$uid').maybeSingle();
        if (cfg != null && cfg['value'] != null) {
          final val = Map<String, dynamic>.from(cfg['value'] as Map);
          if (val['salary'] != null) _salary = (val['salary'] as num).toDouble();
          if (val['commissionRate'] != null) _commissionRate = (val['commissionRate'] as num).toDouble();
        }
      } catch (_) {}

      // 2. Fetch fresh user row
      try {
        final uRow = await _sb
            .from('users')
            .select('admin_salary, admin_commission_rate')
            .eq('uid', uid)
            .maybeSingle();
        if (uRow != null) {
          if (uRow['admin_salary'] != null) _salary = (uRow['admin_salary'] as num).toDouble();
          if (uRow['admin_commission_rate'] != null) {
            _commissionRate = (uRow['admin_commission_rate'] as num).toDouble();
          }
        }
      } catch (_) {}

      // 3. Fetch agencies created by / under this Admin
      final rawAgencies = await _sb
          .from('host_agencies')
          .select('id, name, owner_uid, owner_name, status, total_diamonds, hosts_count, data, created_at')
          .order('created_at', ascending: false);

      final filteredAgencies = <Map<String, dynamic>>[];
      int diamondsSum = 0;
      int hostsSum = 0;

      for (final a in rawAgencies) {
        final data = a['data'] is Map ? (a['data'] as Map) : {};
        final adminId = data['admin_id']?.toString() ?? data['created_by_admin']?.toString() ?? '';
        final creatorUid = data['creator_uid']?.toString() ?? '';

        if (adminId == uid || creatorUid == uid || data['admin_custom_id'] == widget.currentUser.customId) {
          filteredAgencies.add(a);
          diamondsSum += (a['total_diamonds'] as num? ?? 0).toInt();
          hostsSum += (a['hosts_count'] as num? ?? 0).toInt();
        }
      }

      // 4. Fetch BD managers under this Admin
      final bdRows = await _sb
          .from('users')
          .select('uid, id, custom_id, name, photo_url, is_bd, bd_supervisor_id, bd_salary, bd_commission_rate')
          .eq('is_bd', true);

      final filteredBds = <Map<String, dynamic>>[];
      for (final b in bdRows) {
        if (b['bd_supervisor_id']?.toString() == uid || b['bd_supervisor_id']?.toString() == widget.currentUser.customId) {
          filteredBds.add(b);
        }
      }

      if (mounted) {
        setState(() {
          _agencies = filteredAgencies;
          _bdManagers = filteredBds;
          _totalDiamonds = diamondsSum;
          _totalHosts = hostsSum;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _openDisburseSalary() {
    SalaryDisburseDialog.show(
      context,
      currentUser: widget.currentUser,
      role: 'admin',
      currentSalary: _salary,
      onDisbursed: _fetchData,
    );
  }

  void _openStoreGift() {
    StoreGiftDialog.show(context, currentUser: widget.currentUser);
  }

  void _openInviteAgencyDialog() {
    final userCtrl = TextEditingController();
    final agencyNameCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: _crimson, width: 1.5)),
        title: const Text('دعوة مستخدم لفتح وكالة 🏢', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: userCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'معرف المستخدم (ID أو Custom ID)',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                filled: true,
                fillColor: _bgDeep,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: agencyNameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'اسم الوكالة المقترح (اختياري)',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                filled: true,
                fillColor: _bgDeep,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(color: Colors.white60))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _crimson, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              final targetQuery = userCtrl.text.trim();
              if (targetQuery.isEmpty) return;

              try {
                final targetUser = await _sb.from('users').select('uid, id, name').or('custom_id.eq.$targetQuery,uid.eq.$targetQuery,id.eq.$targetQuery').maybeSingle();
                if (targetUser == null) {
                  KayanInAppToast.warning('لم يتم العثور على المستخدم');
                  return;
                }

                final targetUid = targetUser['uid']?.toString() ?? targetUser['id']?.toString() ?? '';
                await SupabaseDataService().sendNotification(
                  uid: targetUid,
                  type: 'agency_invite',
                  actorUid: widget.currentUser.uid,
                  title: 'دعوة لفتح وكالة جديدة 🏢',
                  body: 'تمت دعوتك من قِبل الإدارة (${widget.currentUser.name}) لفتح وكالة جديدة',
                  data: {
                    'action': 'agency_invite',
                    'admin_id': widget.currentUser.uid,
                    'admin_name': widget.currentUser.name,
                    'agency_name': agencyNameCtrl.text.trim(),
                  },
                );

                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  KayanInAppToast.success('تم إرسال دعوة فتح الوكالة بنجاح 🎉');
                }
              } catch (e) {
                KayanInAppToast.error('فشل إرسال الدعوة: $e');
              }
            },
            child: const Text('إرسال الدعوة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDeep,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_crimson, Color(0xFFB30000)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'ADMIN',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'لوحة الإدارة',
              style: TextStyle(color: _textMain, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _crimson, size: 22),
            onPressed: _fetchData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _crimson))
          : _error != null
              ? _buildErrorView()
              : _buildMainContent(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            const Text('تعذر تحميل بيانات الإدارة', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(color: _textMuted, fontSize: 12)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _fetchData, child: const Text('إعادة المحاولة')),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return RefreshIndicator(
      onRefresh: _fetchData,
      color: _crimson,
      backgroundColor: _bgCard,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Card
          _buildAdminHeader(),

          const SizedBox(height: 16),

          // Quick Action Buttons
          _buildActionButtonsRow(),

          const SizedBox(height: 18),

          // Statistics Grid
          _buildStatsGrid(),

          const SizedBox(height: 20),

          // Tabs
          TabBar(
            controller: _tabController,
            indicatorColor: _crimson,
            indicatorWeight: 3,
            labelColor: _crimson,
            unselectedLabelColor: _textMuted,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            tabs: [
              Tab(text: 'الوكالات (${_agencies.length})'),
              Tab(text: 'مدراء BD (${_bdManagers.length})'),
            ],
          ),

          const SizedBox(height: 12),

          SizedBox(
            height: 420,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAgenciesTab(),
                _buildBdsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A1020), Color(0xFF1B2148)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _crimson.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _crimson.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [_crimson, Color(0xFF990000)]),
              boxShadow: [
                BoxShadow(
                  color: _crimson.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.shield_rounded, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.currentUser.name.isNotEmpty ? widget.currentUser.name : 'Admin',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.verified_user_rounded, color: _crimson, size: 20),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: ${widget.currentUser.customId.isNotEmpty ? widget.currentUser.customId : widget.currentUser.uid}',
                  style: const TextStyle(color: _cyan, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtonsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildQuickActionButton(
            label: 'صرف الراتب',
            icon: Icons.account_balance_wallet_rounded,
            color: _gold,
            onTap: _openDisburseSalary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildQuickActionButton(
            label: 'دعوة وكالة',
            icon: Icons.domain_add_rounded,
            color: _cyan,
            onTap: _openInviteAgencyDialog,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildQuickActionButton(
            label: 'إهداء متجر',
            icon: Icons.card_giftcard_rounded,
            color: _green,
            onTap: _openStoreGift,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'الوكالات المنشأة',
                value: '${_agencies.length}',
                icon: Icons.corporate_fare_rounded,
                color: _cyan,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                title: 'إجمالي التارجت (ماس)',
                value: _totalDiamonds.toString(),
                icon: Icons.diamond_rounded,
                color: const Color(0xFF00E5FF),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'الراتب المعتمد',
                value: '${_salary.toInt()}',
                icon: Icons.attach_money_rounded,
                color: _gold,
                subtitle: '$_commissionRate% عمولة تارجت',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                title: 'مدراء BD التابعون',
                value: '${_bdManagers.length}',
                icon: Icons.badge_rounded,
                color: _crimson,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 15),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }

  Widget _buildAgenciesTab() {
    if (_agencies.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.domain_disabled_rounded, color: Colors.white24, size: 48),
            SizedBox(height: 8),
            Text('لا توجد وكالات مسجلة تحتك حالياً', style: TextStyle(color: _textMuted, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _agencies.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final a = _agencies[index];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.business_rounded, color: _cyan, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a['name'] ?? 'وكالة', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text('المالك: ${a['owner_name'] ?? a['owner_uid'] ?? "-"} • ${a['hosts_count'] ?? 0} مضيف', style: const TextStyle(color: _textMuted, fontSize: 11)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.diamond_rounded, color: _cyan, size: 14),
                      const SizedBox(width: 4),
                      Text('${a['total_diamonds'] ?? 0}', style: const TextStyle(color: _gold, fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text('تارجت الوكالة', style: TextStyle(color: _textMuted, fontSize: 10)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBdsTab() {
    if (_bdManagers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.person_off_rounded, color: Colors.white24, size: 48),
            SizedBox(height: 8),
            Text('لا يوجد مسؤولو BD معينين تحت إشرافك', style: TextStyle(color: _textMuted, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _bdManagers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final b = _bdManagers[index];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _crimson.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _crimson.withValues(alpha: 0.2),
                backgroundImage: b['photo_url'] != null && b['photo_url'].toString().isNotEmpty ? NetworkImage(b['photo_url']) : null,
                child: b['photo_url'] == null || b['photo_url'].toString().isEmpty ? const Icon(Icons.person, color: _crimson) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b['name'] ?? 'مسؤول BD', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text('ID: ${b['custom_id'] ?? b['uid']}', style: const TextStyle(color: _cyan, fontSize: 11)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('عمولة: ${b['bd_commission_rate'] ?? 10}%', style: const TextStyle(color: _green, fontWeight: FontWeight.bold, fontSize: 12)),
                  Text('راتب: \$${b['bd_salary'] ?? 0}', style: const TextStyle(color: _gold, fontSize: 11)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
