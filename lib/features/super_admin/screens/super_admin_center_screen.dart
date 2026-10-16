import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/user_model.dart';
import '../widgets/salary_disburse_dialog.dart';
import '../widgets/store_gift_dialog.dart';

class SuperAdminCenterScreen extends StatefulWidget {
  final UserModel currentUser;

  const SuperAdminCenterScreen({
    Key? key,
    required this.currentUser,
  }) : super(key: key);

  @override
  State<SuperAdminCenterScreen> createState() => _SuperAdminCenterScreenState();
}

class _SuperAdminCenterScreenState extends State<SuperAdminCenterScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _myAgencies = [];
  List<Map<String, dynamic>> _myAdmins = [];
  List<Map<String, dynamic>> _myBds = [];

  double _totalAgenciesEarnings = 0.0;
  double _mySalary = 0.0;
  double _myCommissionRate = 0.0;
  double _myCommissionEarned = 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final myId = widget.currentUser.id;

      // 1. Fetch Super Admin profile metrics
      final userRes = await _supabase
          .from('users')
          .select('super_admin_salary, super_admin_commission_rate')
          .eq('id', myId)
          .maybeSingle();

      _mySalary = (userRes?['super_admin_salary'] as num?)?.toDouble() ?? (widget.currentUser.superAdminSalary ?? 0.0);
      _myCommissionRate = (userRes?['super_admin_commission_rate'] as num?)?.toDouble() ?? (widget.currentUser.superAdminCommissionRate ?? 0.0);

      // 2. Fetch agencies created by this super admin
      final agencyRes = await _supabase
          .from('host_agencies')
          .select('id, agency_name, agency_code, owner_id, total_earnings, created_at, status')
          .eq('super_admin_id', myId);

      _myAgencies = List<Map<String, dynamic>>.from(agencyRes ?? []);

      _totalAgenciesEarnings = 0.0;
      for (final a in _myAgencies) {
        final earnings = (a['total_earnings'] as num?)?.toDouble() ?? 0.0;
        _totalAgenciesEarnings += earnings;
      }

      _myCommissionEarned = (_totalAgenciesEarnings * (_myCommissionRate / 100.0));

      // 3. Fetch Admins supervised by this Super Admin
      final adminRes = await _supabase
          .from('users')
          .select('id, name, user_id, avatar_url, admin_salary, admin_commission_rate, created_at')
          .eq('admin_supervisor_id', myId)
          .eq('is_admin', true);

      _myAdmins = List<Map<String, dynamic>>.from(adminRes ?? []);

      // 4. Fetch BDs created/supervised by this Super Admin
      final bdRes = await _supabase
          .from('users')
          .select('id, name, user_id, avatar_url, bd_salary, bd_commission_rate, created_at')
          .eq('bd_supervisor_id', myId)
          .eq('is_bd', true);

      _myBds = List<Map<String, dynamic>>.from(bdRes ?? []);

    } catch (e) {
      debugPrint('Error loading super admin data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Quick Actions ---
  void _openSalaryDisburse() {
    showDialog(
      context: context,
      builder: (_) => SalaryDisburseDialog(
        currentUserId: widget.currentUser.id,
        currentUserName: widget.currentUser.name,
        role: 'super_admin',
        availableSalary: _mySalary,
      ),
    ).then((_) => _loadData());
  }

  void _openStoreGift() {
    showDialog(
      context: context,
      builder: (_) => StoreGiftDialog(
        senderId: widget.currentUser.id,
        senderName: widget.currentUser.name,
      ),
    );
  }

  // Invite user to open an agency
  void _inviteUserToCreateAgency() {
    final searchCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.business_center, color: Color(0xFFFFD700)),
            SizedBox(width: 8),
            Text('دعوة مستخدم لفتح وكالة', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'أدخل المعرف (User ID) للمستخدم المراد دعوته لإنشاء وكالة تحت إشرافك:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: searchCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'مثال: 100234',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black),
            onPressed: () async {
              final targetId = searchCtrl.text.trim();
              if (targetId.isEmpty) return;
              Navigator.pop(ctx);
              _sendAgencyInvitation(targetId);
            },
            child: const Text('إرسال الدعوة'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendAgencyInvitation(String userShortId) async {
    try {
      final user = await _supabase
          .from('users')
          .select('id, name')
          .eq('user_id', userShortId)
          .maybeSingle();

      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('المستخدم غير موجود'), backgroundColor: Colors.red),
        );
        return;
      }

      await _supabase.from('notifications').insert({
        'user_id': user['id'],
        'title': 'دعوة لإنشاء وكالة جديدة',
        'body': 'تمت دعوتك من قِبل السوبر أدمن (${widget.currentUser.name}) لفتح وكالة جديدة',
        'type': 'agency_invitation',
        'data': {
          'super_admin_id': widget.currentUser.id,
          'super_admin_name': widget.currentUser.name,
        },
        'created_at': DateTime.now().toIso8601String(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إرسال دعوة إنشاء الوكالة إلى ${user['name']} بنجاح!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في إرسال الدعوة: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // Appoint / Invite Admin
  void _appointAdminDialog() {
    final searchCtrl = TextEditingController();
    final salaryCtrl = TextEditingController(text: '0');
    final commissionCtrl = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('تعيين مسؤول Admin جديد', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('معرف المستخدم (User ID):', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: searchCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '100234',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              const Text('الراتب الشهري (USD):', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: salaryCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              const Text('نسبة العمولة (%):', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: commissionCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
            onPressed: () async {
              final targetId = searchCtrl.text.trim();
              if (targetId.isEmpty) return;
              final salary = double.tryParse(salaryCtrl.text.trim()) ?? 0.0;
              final comm = double.tryParse(commissionCtrl.text.trim()) ?? 0.0;
              Navigator.pop(ctx);
              _executeAssignStaff(targetId, isStaffAdmin: true, salary: salary, commission: comm);
            },
            child: const Text('تعيين Admin'),
          ),
        ],
      ),
    );
  }

  // Appoint / Invite BD
  void _appointBdDialog() {
    final searchCtrl = TextEditingController();
    final salaryCtrl = TextEditingController(text: '0');
    final commissionCtrl = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.workspace_premium, color: Color(0xFFFFD700)),
            SizedBox(width: 8),
            Text('تعيين مسؤول BD جديد', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('معرف المستخدم (User ID):', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: searchCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '100234',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              const Text('الراتب الشهري (USD):', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: salaryCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              const Text('نسبة العمولة (%):', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: commissionCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black),
            onPressed: () async {
              final targetId = searchCtrl.text.trim();
              if (targetId.isEmpty) return;
              final salary = double.tryParse(salaryCtrl.text.trim()) ?? 0.0;
              final comm = double.tryParse(commissionCtrl.text.trim()) ?? 0.0;
              Navigator.pop(ctx);
              _executeAssignStaff(targetId, isStaffAdmin: false, salary: salary, commission: comm);
            },
            child: const Text('تعيين BD'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeAssignStaff(String userShortId, {required bool isStaffAdmin, required double salary, required double commission}) async {
    try {
      final user = await _supabase
          .from('users')
          .select('id, name')
          .eq('user_id', userShortId)
          .maybeSingle();

      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('المستخدم غير موجود'), backgroundColor: Colors.red),
        );
        return;
      }

      final updateData = isStaffAdmin
          ? {
              'is_admin': true,
              'admin_supervisor_id': widget.currentUser.id,
              'admin_salary': salary,
              'admin_commission_rate': commission,
            }
          : {
              'is_bd': true,
              'bd_supervisor_id': widget.currentUser.id,
              'bd_salary': salary,
              'bd_commission_rate': commission,
            };

      await _supabase.from('users').update(updateData).eq('id', user['id']);

      await _supabase.from('notifications').insert({
        'user_id': user['id'],
        'title': isStaffAdmin ? 'تم تعيينك مسؤول Admin' : 'تم تعيينك مسؤول BD',
        'body': 'تهانينا! قام السوبر أدمن (${widget.currentUser.name}) بتعيينك رسمياً في المنصب',
        'type': isStaffAdmin ? 'admin_assigned' : 'bd_assigned',
        'created_at': DateTime.now().toIso8601String(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تعيين ${user['name']} بنجاح!'),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في التعيين: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E15),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1C29),
        elevation: 0,
        title: const Text(
          'مركز السوبر أدمن (Super Admin)',
          style: TextStyle(color: Color(0xFFFFD700), fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFFFFD700)),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderCard(),
                  const SizedBox(height: 16),
                  _buildStatsGrid(),
                  const SizedBox(height: 16),
                  _buildActionsRow(),
                  const SizedBox(height: 20),
                  _buildTabBar(),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 400,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildAgenciesTab(),
                        _buildAdminsTab(),
                        _buildBdsTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2C1E4A), Color(0xFF151628)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage: widget.currentUser.avatarUrl != null
                ? NetworkImage(widget.currentUser.avatarUrl!)
                : null,
            child: widget.currentUser.avatarUrl == null
                ? const Icon(Icons.shield, color: Color(0xFFFFD700), size: 30)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.currentUser.name,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('SUPER ADMIN', style: TextStyle(color: Color(0xFFFFD700), fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: ${widget.currentUser.userId} | نسبة العمولة: ${_myCommissionRate.toStringAsFixed(1)}%',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.6,
      children: [
        _buildStatCard('راتبي المتاح', '\$${_mySalary.toStringAsFixed(0)}', Icons.account_balance_wallet, Colors.greenAccent),
        _buildStatCard('عمولتي المكتسبة', '\$${_myCommissionEarned.toStringAsFixed(0)}', Icons.monetization_on, const Color(0xFFFFD700)),
        _buildStatCard('إجمالي أرباح الوكالات', '\$${_totalAgenciesEarnings.toStringAsFixed(0)}', Icons.trending_up, Colors.cyanAccent),
        _buildStatCard('إجمالي الوكالات', '${_myAgencies.length}', Icons.apartment, Colors.purpleAccent),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C29),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title, style: const TextStyle(color: Colors.white70, fontSize: 11), maxLines: 1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildActionsRow() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildActionButton('صرف الراتب', Icons.currency_exchange, Colors.greenAccent, _openSalaryDisburse),
        _buildActionButton('إهداء متجر', Icons.card_giftcard, const Color(0xFFFFD700), _openStoreGift),
        _buildActionButton('دعوة وكالة', Icons.add_business, Colors.amberAccent, _inviteUserToCreateAgency),
        _buildActionButton('تعيين Admin', Icons.security, Colors.blueAccent, _appointAdminDialog),
        _buildActionButton('تعيين BD', Icons.workspace_premium, Colors.deepPurpleAccent, _appointBdDialog),
      ],
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C29),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: const Color(0xFFFFD700),
        labelColor: const Color(0xFFFFD700),
        unselectedLabelColor: Colors.white54,
        tabs: [
          Tab(text: 'الوكالات (${_myAgencies.length})'),
          Tab(text: 'مسؤولو Admin (${_myAdmins.length})'),
          Tab(text: 'مسؤولو BD (${_myBds.length})'),
        ],
      ),
    );
  }

  Widget _buildAgenciesTab() {
    if (_myAgencies.isEmpty) {
      return const Center(child: Text('لا توجد وكالات مسجلة تحتك حالياً', style: TextStyle(color: Colors.white38)));
    }
    return ListView.builder(
      itemCount: _myAgencies.length,
      itemBuilder: (context, index) {
        final agency = _myAgencies[index];
        final earnings = (agency['total_earnings'] as num?)?.toDouble() ?? 0.0;
        final commission = earnings * (_myCommissionRate / 100.0);
        return Card(
          color: const Color(0xFF1E2030),
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFFFD700),
              child: Icon(Icons.business, color: Colors.black, size: 20),
            ),
            title: Text(agency['agency_name'] ?? 'وكالة بدون اسم', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text('كود: ${agency['agency_code'] ?? '-'} | أرباح: \$${earnings.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('عمولتك', style: TextStyle(color: Colors.white38, fontSize: 10)),
                Text('+\$${commission.toStringAsFixed(1)}', style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAdminsTab() {
    if (_myAdmins.isEmpty) {
      return const Center(child: Text('لا يوجد مسؤولو Admin تحت إشرافك حالياً', style: TextStyle(color: Colors.white38)));
    }
    return ListView.builder(
      itemCount: _myAdmins.length,
      itemBuilder: (context, index) {
        final admin = _myAdmins[index];
        final salary = (admin['admin_salary'] as num?)?.toDouble() ?? 0.0;
        final commRate = (admin['admin_commission_rate'] as num?)?.toDouble() ?? 0.0;
        return Card(
          color: const Color(0xFF1E2030),
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: admin['avatar_url'] != null ? NetworkImage(admin['avatar_url']) : null,
              child: admin['avatar_url'] == null ? const Icon(Icons.person, color: Colors.blueAccent) : null,
            ),
            title: Text(admin['name'] ?? 'بدون اسم', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text('ID: ${admin['user_id']} | عمولة: ${commRate.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            trailing: Text('راتب: \$${salary.toStringAsFixed(0)}', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }

  Widget _buildBdsTab() {
    if (_myBds.isEmpty) {
      return const Center(child: Text('لا يوجد مسؤولو BD تحت إشرافك حالياً', style: TextStyle(color: Colors.white38)));
    }
    return ListView.builder(
      itemCount: _myBds.length,
      itemBuilder: (context, index) {
        final bd = _myBds[index];
        final salary = (bd['bd_salary'] as num?)?.toDouble() ?? 0.0;
        final commRate = (bd['bd_commission_rate'] as num?)?.toDouble() ?? 0.0;
        return Card(
          color: const Color(0xFF1E2030),
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: bd['avatar_url'] != null ? NetworkImage(bd['avatar_url']) : null,
              child: bd['avatar_url'] == null ? const Icon(Icons.person, color: Color(0xFFFFD700)) : null,
            ),
            title: Text(bd['name'] ?? 'بدون اسم', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text('ID: ${bd['user_id']} | عمولة: ${commRate.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            trailing: Text('راتب: \$${salary.toStringAsFixed(0)}', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }
}
