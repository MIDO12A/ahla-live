import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/supabase_compat.dart';
import '../../../core/cache/encrypted_image_provider.dart';
import '../../../core/utils/server_time_service.dart';
import '../data/agency_models.dart';
import '../data/agency_repository.dart';

// ═══════════════════════════════════════════════════════════════════
//  AgencyDisbursementScreen — شاشة صرف الأرباح والرواتب
//  ◄ التبويب 1: صرف إلى الإدارة (سحب بنكي / USDT وتصفير الراتب عند الصرف)
//  ◄ التبويب 2: صرف إلى وكيل الشحن (بحث بالآيدي + بطاقة الوكيل + إشعار تفاعلي موافقة/رفض + تصفير التارجت فوراً)
// ═══════════════════════════════════════════════════════════════════
class AgencyDisbursementScreen extends StatefulWidget {
  final String? agencyId;
  final int initialTab;
  final int? initialDiamonds;

  const AgencyDisbursementScreen({
    super.key,
    this.agencyId,
    this.initialTab = 0,
    this.initialDiamonds,
  });

  @override
  State<AgencyDisbursementScreen> createState() => _AgencyDisbursementScreenState();
}

class _AgencyDisbursementScreenState extends State<AgencyDisbursementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _loading = true;
  String? _error;

  // إحصائيات المضيف / المستخدم
  AgencyMemberInfo? _member;
  AgencyEngineSettings? _engine;
  AgencyOwnerDashboard? _ownerDash;
  bool _isOwner = false;
  int _availableDiamonds = 0;
  int _monthlyTarget = 0;

  static const _gold = Color(0xFFD4AF37);
  static const _dark = Color(0xFF0D0D1A);
  static const _card = Color(0xFF1A1A2E);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this, initialIndex: widget.initialTab.clamp(0, 1));
    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) {
        setState(() {
          _error = 'المستخدم غير مسجل الدخول';
          _loading = false;
        });
        return;
      }

      HostAgencyStats? hostStats;
      AgencyEngineSettings engine = AgencyEngineSettings.defaults;
      AgencyOwnerDashboard? ownerDash;

      try {
        hostStats = await AgencyRepository.getHostStats();
      } catch (e) {
        debugPrint('[AgencyDisbursementScreen] getHostStats error: $e');
      }

      try {
        engine = await AgencyRepository.getEngineSettings();
      } catch (e) {
        debugPrint('[AgencyDisbursementScreen] getEngineSettings error: $e');
      }

      if (widget.agencyId != null && widget.agencyId!.isNotEmpty) {
        try {
          ownerDash = await AgencyRepository.getOwnerDashboard(widget.agencyId!);
        } catch (e) {
          debugPrint('[AgencyDisbursementScreen] getOwnerDashboard error: $e');
        }
      }

      if (ownerDash != null) {
        _isOwner = true;
        _ownerDash = ownerDash;
        _availableDiamonds = ownerDash.wallet.available;
      } else if (hostStats?.member != null) {
        _member = hostStats!.member;
        _availableDiamonds = _member!.diamondsAvailable;
        _monthlyTarget = _member!.diamondsEarnedMonthly;
      } else {
        // فحص مباشر من جدول المستخدمين
        try {
          final uRow = await Supabase.instance.client
              .from('users')
              .select('diamonds')
              .eq('uid', uid)
              .maybeSingle();
          _availableDiamonds = (uRow?['diamonds'] as num?)?.toInt() ?? 0;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _engine = engine;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      debugPrint('[AgencyDisbursementScreen] _loadAll error: $e');
      if (mounted) {
        setState(() {
          _engine = AgencyEngineSettings.defaults;
          _loading = false;
          _error = null;
        });
      }
    }
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(2)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: _dark,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'صرف الأرباح والرواتب',
          style: TextStyle(
            color: _gold,
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _gold),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _gold),
            onPressed: _loadAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: _gold,
          labelColor: _gold,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(text: '🏛️ صرف إلى الإدارة'),
            Tab(text: '⚡ صرف إلى وكيل الشحن'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : _error != null
              ? _buildErrorView()
              : Column(
                  children: [
                    _buildBalanceHeader(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabCtrl,
                        children: [
                          _DisburseToAdminTab(
                            availableDiamonds: _availableDiamonds,
                            agencyId: widget.agencyId,
                            engine: _engine,
                            onSuccess: _loadAll,
                          ),
                          _DisburseToRechargeAgentTab(
                            availableDiamonds: _availableDiamonds,
                            initialDiamonds: widget.initialDiamonds,
                            agencyId: widget.agencyId,
                            onSuccess: _loadAll,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildBalanceHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1B4E), Color(0xFF140D28)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              const Text('الرصيد المتاح للصرف',
                  style: TextStyle(color: Colors.white60, fontFamily: 'Tajawal', fontSize: 12)),
              const SizedBox(height: 4),
              Text('${_fmt(_availableDiamonds)} 💎',
                  style: const TextStyle(
                      color: _gold, fontFamily: 'Tajawal', fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          Container(width: 1, height: 36, color: Colors.white12),
          Column(
            children: [
              Text(_isOwner ? 'تارجت الوكالة' : 'تارجت الشهر الحالي',
                  style: const TextStyle(color: Colors.white60, fontFamily: 'Tajawal', fontSize: 12)),
              const SizedBox(height: 4),
              Text('${_fmt(_monthlyTarget)} ♦',
                  style: const TextStyle(
                      color: Color(0xFF00E5A0), fontFamily: 'Tajawal', fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(_error ?? 'حدث خطأ غير متوقع',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 14)),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _gold),
              onPressed: _loadAll,
              child: const Text('إعادة المحاولة', style: TextStyle(color: Colors.black, fontFamily: 'Tajawal')),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  القسم 1: صرف إلى الإدارة
// ═══════════════════════════════════════════════════════════════════
class _DisburseToAdminTab extends StatefulWidget {
  final int availableDiamonds;
  final String? agencyId;
  final AgencyEngineSettings? engine;
  final VoidCallback onSuccess;

  const _DisburseToAdminTab({
    required this.availableDiamonds,
    this.agencyId,
    this.engine,
    required this.onSuccess,
  });

  @override
  State<_DisburseToAdminTab> createState() => _DisburseToAdminTabState();
}

class _DisburseToAdminTabState extends State<_DisburseToAdminTab> {
  final _amountCtrl = TextEditingController();
  final _payDetailsCtrl = TextEditingController();
  String _selectedMethod = 'bank_transfer';
  bool _submitting = false;

  static const _gold = Color(0xFFD4AF37);
  static const _card = Color(0xFF1A1A2E);

  @override
  void dispose() {
    _amountCtrl.dispose();
    _payDetailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitAdminDisbursement() async {
    final amount = int.tryParse(_amountCtrl.text.trim()) ?? 0;
    final details = _payDetailsCtrl.text.trim();

    if (amount <= 0) {
      _snack('يرجى إدخال كمية ألماس صحيحة');
      return;
    }
    if (amount > widget.availableDiamonds) {
      _snack('الرصيد المتاح لديك غير كافٍ للصرف (${widget.availableDiamonds} 💎)');
      return;
    }
    if (details.isEmpty) {
      _snack('يرجى كتابة تفاصيل الحساب البنكي أو المحفظة');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('تأكيد طلب الصرف إلى الإدارة',
            style: TextStyle(color: _gold, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('كمية الألماس: $amount 💎',
                style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
            const SizedBox(height: 6),
            Text('طريقة الاستلام: $_selectedMethod',
                style: const TextStyle(color: Colors.white70, fontFamily: 'Tajawal')),
            const SizedBox(height: 10),
            const Text('⚠️ تنبيه: سيتم تصفير الراتب والتراجع عن التارجت المقابل فور إتمام الصرف.',
                style: TextStyle(color: Colors.amber, fontFamily: 'Tajawal', fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _gold),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد وإرسال',
                style: TextStyle(color: Colors.black, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _submitting = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) throw Exception('المستخدم غير مسجل الدخول');

      // تسجيل طلب الصرف في جدول agency_withdrawal_requests
      await Supabase.instance.client.from('agency_withdrawal_requests').insert({
        'user_id': uid,
        'agency_id': widget.agencyId,
        'diamonds_amount': amount,
        'payment_method': _selectedMethod,
        'payment_details': {'details': details, 'source': 'disbursement_screen'},
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });

      // تصفير / خصم التارجت والرصيد المتاح للمستخدم فوراً
      try {
        final mRow = await Supabase.instance.client
            .from('host_agency_members')
            .select('id, diamonds_earned_monthly, diamonds_balance')
            .or('user_id.eq.$uid,host_uid.eq.$uid')
            .maybeSingle();

        if (mRow != null) {
          final curM = (mRow['diamonds_earned_monthly'] as num?)?.toInt() ?? 0;
          final curB = (mRow['diamonds_balance'] as num?)?.toInt() ?? 0;
          await Supabase.instance.client.from('host_agency_members').update({
            'diamonds_earned_monthly': (curM - amount).clamp(0, 999999999),
            'diamonds_balance': (curB - amount).clamp(0, 999999999),
            'diamonds': (curB - amount).clamp(0, 999999999),
          }).eq('id', mRow['id']);
        }

        // تصفير الرواتب المستحقة في جدول الرواتب
        await Supabase.instance.client.from('host_salaries').update({
          'status': 'disbursed',
          'disbursed_at': DateTime.now().toIso8601String(),
        }).eq('user_id', uid).eq('status', 'pending');
      } catch (_) {}

      if (!mounted) return;
      _snack('✅ تم إرسال طلب الصرف إلى الإدارة وتصفير التارجت بنجاح', ok: true);
      _amountCtrl.clear();
      _payDetailsCtrl.clear();
      widget.onSuccess();
    } catch (e) {
      if (mounted) _snack('فشل إرسال طلب الصرف: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Tajawal')),
      backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: _gold, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'عند طلب الصرف إلى الإدارة، تتم مراجعة الحساب البنكي وتحويل المستحقات مع تصفير التارجت والراتب المكتسب فوراً.',
                  style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('كمية الألماس للصرف',
            style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _amountCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: 'أدخل كمية الألماس...',
            hintStyle: const TextStyle(color: Colors.white24, fontFamily: 'Tajawal'),
            suffixIcon: TextButton(
              onPressed: () => _amountCtrl.text = widget.availableDiamonds.toString(),
              child: const Text('الكل', style: TextStyle(color: _gold, fontFamily: 'Tajawal')),
            ),
            filled: true,
            fillColor: _card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 16),
        const Text('طريقة الدفع والاستلام',
            style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 13)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedMethod,
          dropdownColor: _card,
          style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal'),
          decoration: InputDecoration(
            filled: true,
            fillColor: _card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
          items: const [
            DropdownMenuItem(value: 'bank_transfer', child: Text('🏦 تحويل بنكي (IBAN)')),
            DropdownMenuItem(value: 'usdt_trc20', child: Text('🪙 محفظة USDT (TRC-20)')),
            DropdownMenuItem(value: 'wise', child: Text('🌐 حساب Wise')),
            DropdownMenuItem(value: 'cash', child: Text('💵 استلام نقدي / كاش')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _selectedMethod = v);
          },
        ),
        const SizedBox(height: 16),
        const Text('تفاصيل الحساب أو العنوان',
            style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _payDetailsCtrl,
          style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal'),
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'اكتب رقم الآيبان، اسم البنك، أو عنوان محفظة USDT...',
            hintStyle: const TextStyle(color: Colors.white24, fontFamily: 'Tajawal'),
            filled: true,
            fillColor: _card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _submitting ? null : _submitAdminDisbursement,
            child: _submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                : const Text('إرسال طلب الصرف إلى الإدارة 🚀',
                    style: TextStyle(color: Colors.black, fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  القسم 2: صرف إلى وكيل الشحن
// ═══════════════════════════════════════════════════════════════════
class _DisburseToRechargeAgentTab extends StatefulWidget {
  final int availableDiamonds;
  final int? initialDiamonds;
  final String? agencyId;
  final VoidCallback onSuccess;

  const _DisburseToRechargeAgentTab({
    required this.availableDiamonds,
    this.initialDiamonds,
    this.agencyId,
    required this.onSuccess,
  });

  @override
  State<_DisburseToRechargeAgentTab> createState() => _DisburseToRechargeAgentTabState();
}

class _DisburseToRechargeAgentTabState extends State<_DisburseToRechargeAgentTab> {
  final _searchCtrl = TextEditingController();
  final _diamondsCtrl = TextEditingController();
  List<Map<String, dynamic>> _allAgents = [];
  List<Map<String, dynamic>> _filteredAgents = [];
  Map<String, dynamic>? _selectedAgent;
  bool _loadingAgents = true;
  bool _submitting = false;

  static const _gold = Color(0xFFD4AF37);
  static const _card = Color(0xFF1A1A2E);

  @override
  void initState() {
    super.initState();
    if (widget.initialDiamonds != null && widget.initialDiamonds! > 0) {
      _diamondsCtrl.text = widget.initialDiamonds.toString();
    }
    _loadRechargeAgents();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _diamondsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRechargeAgents() async {
    setState(() => _loadingAgents = true);
    try {
      final agents = await AgencyRepository.searchRechargeAgents('');
      if (!mounted) return;
      setState(() {
        _allAgents = agents;
        _filteredAgents = agents;
        _loadingAgents = false;
      });
    } catch (e) {
      debugPrint('[DisburseToRechargeAgentTab] error: $e');
      if (mounted) setState(() => _loadingAgents = false);
    }
  }

  void _onSearch(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _filteredAgents = _allAgents);
      return;
    }
    setState(() {
      _filteredAgents = _allAgents.where((agent) {
        final kid = (agent['kayan_id'] ?? '').toString().toLowerCase();
        final name = (agent['display_name'] ?? '').toString().toLowerCase();
        final agName = (agent['recharge_agency_name'] ?? '').toString().toLowerCase();
        final phone = (agent['whatsapp_number'] ?? '').toString().toLowerCase();
        final uid = (agent['id'] ?? agent['uid'] ?? '').toString().toLowerCase();
        return kid.contains(query) || name.contains(query) || agName.contains(query) || phone.contains(query) || uid.contains(query);
      }).toList();
    });
  }

  Future<void> _submitTransferToAgent() async {
    final diamonds = int.tryParse(_diamondsCtrl.text.trim()) ?? 0;

    if (_selectedAgent == null) {
      _snack('يرجى اختيار وكيل الشحن من القائمة');
      return;
    }
    if (diamonds <= 0) {
      _snack('يرجى إدخال كمية ألماس صحيحة');
      return;
    }
    if (diamonds > widget.availableDiamonds) {
      _snack('الرصيد المتاح غير كافٍ (${widget.availableDiamonds} 💎)');
      return;
    }

    final agentName = _selectedAgent!['display_name'] ?? 'وكيل الشحن';
    final agencyName = _selectedAgent!['recharge_agency_name'] ?? 'وكالة الشحن';
    final agentKid = _selectedAgent!['kayan_id'] ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('تأكيد إرسال طلب الصرف',
            style: TextStyle(color: _gold, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الكمية المراد صرفها: $diamonds 💎',
                style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
            const SizedBox(height: 6),
            Text('الوكيل المستلم: $agentName (#$agentKid)',
                style: const TextStyle(color: Colors.white70, fontFamily: 'Tajawal')),
            Text('الوكالة: $agencyName',
                style: const TextStyle(color: Colors.white70, fontFamily: 'Tajawal')),
            const SizedBox(height: 10),
            const Text(
              '⚠️ تنبيه: سيتم إرسال إشعار فوري للوكيل لمراجعة الطلب والموافقة عليه.\nعند الموافقة، يتم تصفير التارجت والراتب فوراً ونقل الرصيد إلى محفظة وكالة الشحن المعتمدة.',
              style: TextStyle(color: Color(0xFF00E5A0), fontFamily: 'Tajawal', fontSize: 12, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _gold),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إرسال للوكيل',
                style: TextStyle(color: Colors.black, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _submitting = true);
    try {
      final myUid = Supabase.instance.client.auth.currentUser?.id ?? '';
      String myName = 'مستخدم';
      String myCustomId = '';
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('display_name, custom_id, kayan_id')
            .eq('id', myUid)
            .maybeSingle();
        if (profile != null) {
          myName = profile['display_name'] ?? 'مستخدم';
          myCustomId = (profile['custom_id'] ?? profile['kayan_id'] ?? '').toString();
        }
      } catch (_) {}

      final res = await AgencyRepository.requestHostWithdrawalToAgent(
        agent: _selectedAgent!,
        diamonds: diamonds,
        hostUid: myUid,
        hostName: myName,
        hostCustomId: myCustomId,
        agencyId: widget.agencyId,
      );

      if (res['success'] != true) {
        throw Exception(res['message'] ?? 'فشل إرسال طلب السحب للوكيل');
      }

      if (!mounted) return;
      _snack('✅ تم إرسال طلب الصرف إلى الوكيل بنجاح! سيتم التحويل بمجرد موافقته.', ok: true);
      _diamondsCtrl.clear();
      setState(() => _selectedAgent = null);
      widget.onSuccess();
    } catch (e) {
      if (mounted) _snack('فشل إرسال الطلب: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Tajawal')),
      backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // شريط البحث بالآيدي أو الاسم
        TextField(
          controller: _searchCtrl,
          onChanged: _onSearch,
          style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal'),
          decoration: InputDecoration(
            hintText: 'ابحث بالآيدي (#ID) أو اسم وكيل الشحن...',
            hintStyle: const TextStyle(color: Colors.white24, fontFamily: 'Tajawal'),
            prefixIcon: const Icon(Icons.search_rounded, color: _gold),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white38),
                    onPressed: () {
                      _searchCtrl.clear();
                      _onSearch('');
                    },
                  )
                : null,
            filled: true,
            fillColor: _card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 14),

        // بطاقة الوكيل المختار
        if (_selectedAgent != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _gold.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _gold.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: _gold.withOpacity(0.2),
                  backgroundImage: (_selectedAgent!['recharge_agency_logo'] != null &&
                          _selectedAgent!['recharge_agency_logo'].toString().isNotEmpty)
                      ? EncryptedImageProvider(_selectedAgent!['recharge_agency_logo'] as String)
                      : (_selectedAgent!['avatar_url'] != null &&
                              _selectedAgent!['avatar_url'].toString().isNotEmpty)
                          ? EncryptedImageProvider(_selectedAgent!['avatar_url'] as String)
                          : null,
                  child: const Icon(Icons.storefront_rounded, color: _gold),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedAgent!['recharge_agency_name'] ?? 'وكالة شحن معتمدة',
                        style: const TextStyle(color: _gold, fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        'الوكيل: ${_selectedAgent!['display_name']} (#${_selectedAgent!['kayan_id'] ?? ''})',
                        style: const TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => setState(() => _selectedAgent = null),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('كمية الألماس المراد تحويلها للوكيل',
              style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _diamondsCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'أدخل كمية الألماس...',
              hintStyle: const TextStyle(color: Colors.white24, fontFamily: 'Tajawal'),
              suffixIcon: TextButton(
                onPressed: () => _diamondsCtrl.text = widget.availableDiamonds.toString(),
                child: const Text('الكل', style: TextStyle(color: _gold, fontFamily: 'Tajawal')),
              ),
              filled: true,
              fillColor: _card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5A0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _submitting ? null : _submitTransferToAgent,
              child: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Text('إرسال طلب الصرف إلى وكيل الشحن ⚡',
                      style: TextStyle(color: Colors.black, fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 18),
        ],

        // قائمة وكلاء الشحن المعتمدين
        const Text('وكلاء الشحن المعتمدون في التطبيق',
            style: TextStyle(color: Colors.white60, fontFamily: 'Tajawal', fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_loadingAgents)
          const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: _gold)))
        else if (_filteredAgents.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('لا توجد وكالات شحن مطابقة للبحث',
                  style: TextStyle(color: Colors.white38, fontFamily: 'Tajawal')),
            ),
          )
        else
          ..._filteredAgents.map((agent) {
            final isSelected = _selectedAgent?['id'] == agent['id'];
            final name = agent['display_name'] ?? 'وكيل شحن';
            final agName = agent['recharge_agency_name'] ?? 'وكالة شحن';
            final kid = agent['kayan_id'] ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isSelected ? _gold.withOpacity(0.12) : _card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isSelected ? _gold : Colors.white12),
              ),
              child: ListTile(
                onTap: () => setState(() => _selectedAgent = agent),
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: _gold.withOpacity(0.2),
                  backgroundImage: (agent['recharge_agency_logo'] != null && agent['recharge_agency_logo'].toString().isNotEmpty)
                      ? EncryptedImageProvider(agent['recharge_agency_logo'] as String)
                      : (agent['avatar_url'] != null && agent['avatar_url'].toString().isNotEmpty)
                          ? EncryptedImageProvider(agent['avatar_url'] as String)
                          : null,
                  child: const Icon(Icons.storefront_rounded, color: _gold, size: 18),
                ),
                title: Text(agName,
                    style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('الوكيل: $name (#$kid)',
                    style: const TextStyle(color: Colors.white54, fontFamily: 'Tajawal', fontSize: 12)),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSelected ? _gold : Colors.white12,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => setState(() => _selectedAgent = agent),
                  child: Text(isSelected ? 'محدد ✓' : 'اختيار',
                      style: TextStyle(
                          color: isSelected ? Colors.black : Colors.white,
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            );
          }),
      ],
    );
  }
}
