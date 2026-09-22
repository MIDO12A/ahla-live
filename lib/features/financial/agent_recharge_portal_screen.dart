import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/supabase_compat.dart';

import '../../core/auth/auth_service.dart';
import 'agent_recharge/agent_recharge_models.dart';
import 'agent_recharge/tabs/agent_dashboard_tab.dart';
import 'agent_recharge/tabs/agent_recharge_tab.dart';
import 'agent_recharge/tabs/agent_history_tab.dart';
import 'agent_recharge/tabs/agent_diamond_tab.dart';
import 'agent_recharge/tabs/agent_usd_tab.dart';
import 'agent_recharge_widgets.dart';
import '../../services/dynamic_config_service.dart';

// ══════════════════════════════════════════════════════════════════════
//  AgentRechargePortalScreen — Orchestrator
//  ► Tab 0: 📊 لوحة التحكم   → AgentDashboardTab
//  ► Tab 1: 💸 شحن مستخدم   → AgentRechargeTab
//  ► Tab 2: 📋 سجل العمليات  → AgentHistoryTab
//  ► Tab 3: 💎 ألماسي        → AgentDiamondWalletTab
//  ► Tab 4: 💵 الدولار       → AgentUsdWalletTab
// ══════════════════════════════════════════════════════════════════════
class AgentRechargePortalScreen extends StatefulWidget {
  const AgentRechargePortalScreen({super.key});
  @override
  State<AgentRechargePortalScreen> createState() =>
      _AgentRechargePortalScreenState();
}

class _AgentRechargePortalScreenState extends State<AgentRechargePortalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = true;
  bool _isAgent = false;
  AgentDashboardData? _dashboard;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final uid = AuthService.currentSession?.user.id ??
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    await _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    final uid = AuthService.currentSession?.user.id ?? user?.uid;

    try {
      final res = await Supabase.instance.client.rpc(
        'agent_get_dashboard',
        params: {'uid': uid},
      );
      if (!mounted) return;
      if (res is Map && res['ok'] == true) {
        setState(() {
          _isAgent = true;
          _dashboard = AgentDashboardData.fromMap(
              Map<String, dynamic>.from(res));
          _loading = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('[agent_recharge] rpc error: $e');
    }

    // Fallback: Check user provider and Firestore directly
    if (user?.isRechargeAgent == true || uid != null) {
      try {
        final uDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final data = uDoc.data() ?? {};
        final isAgent = user?.isRechargeAgent == true ||
            data['is_recharge_agent'] == true ||
            data['isRechargeAgent'] == true ||
            data['is_agent'] == true ||
            data['role'] == 'agent';

        if (isAgent && mounted) {
          final coins = (data['coins'] as num?)?.toInt() ?? user?.coins ?? 0;
          final customId = data['custom_id']?.toString() ?? user?.customId ?? uid;
          final pin = data['agent_pin']?.toString();

          setState(() {
            _isAgent = true;
            _dashboard = AgentDashboardData(
              enabled: true,
              pinSet: pin != null && pin.isNotEmpty,
              dailyLimit: 10000000,
              agencyGold: coins,
              agentPublicId: customId,
              todayTotal: 0,
              todayCount: 0,
              todayRemaining: 10000000,
              weekTotal: 0,
              weekCount: 0,
              monthTotal: 0,
              monthCount: 0,
              allTotal: 0,
              allCount: 0,
              weekChart: const [],
              recentTxns: const [],
              quickAmounts: const [1000, 5000, 10000, 50000, 100000],
              usdBalance: 0.0,
            );
            _loading = false;
          });
          return;
        }
      } catch (e) {
        debugPrint('[agent_recharge] fallback error: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isAgent = false;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    if (!_isAgent) return _buildLockedScreen();

    final dash = _dashboard!;
    if (!dash.enabled) return _buildDisabledScreen();
    if (!dash.pinSet) {
      return AgentPinSetupScreen(onDone: _bootstrap);
    }

    final dc = DynamicConfigService();
    final bgImg = dc.agentRechargeBgImage;
    final accentColor = dc.agentRechargeAccentColor;

    Widget content = Column(children: [
      AgentRechargeHeader(
        agencyGold: dash.agencyGold,
        agentPublicId: dash.agentPublicId,
        onBack: () => Navigator.of(context).pop(),
        onResetPin: () => AgentResetPinDialog.show(context),
      ),
      if (dc.agentRechargeBannerImage.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: dc.agentRechargeBannerImage.startsWith('http')
                ? Image.network(dc.agentRechargeBannerImage, height: 90, width: double.infinity, fit: BoxFit.cover)
                : Image.asset(dc.agentRechargeBannerImage, height: 90, width: double.infinity, fit: BoxFit.cover),
          ),
        ),
      Container(
        color: const Color(0xFF1E1D24),
        child: TabBar(
          controller: _tabs,
          indicatorColor: accentColor,
          indicatorWeight: 3,
          labelStyle: GoogleFonts.tajawal(
              fontSize: 13, fontWeight: FontWeight.w800),
          unselectedLabelStyle: GoogleFonts.tajawal(
              fontSize: 13, fontWeight: FontWeight.w600),
          labelColor: accentColor,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: '📊 لوحة التحكم'),
            Tab(text: '💸 شحن'),
            Tab(text: '📋 السجل'),
            Tab(text: '💎 ألماسي'),
            Tab(text: '💵 الدولار'),
          ],
        ),
      ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              AgentDashboardTab(
                dashboard: dash,
                onRefresh: _loadDashboard,
                onGoRecharge: () => _tabs.animateTo(1),
              ),
              AgentRechargeTab(
                agencyGold: dash.agencyGold,
                dailyRemaining: dash.todayRemaining,
                quickAmounts: dash.quickAmounts,
                onSuccess: _loadDashboard,
                onQuickAmountsChanged: (newAmounts) {
                  if (mounted) {
                    setState(() {
                      _dashboard =
                          dash.copyWithQuickAmounts(newAmounts);
                    });
                  }
                },
              ),
              const AgentHistoryTab(),
              const AgentDiamondWalletTab(),
              const AgentUsdWalletTab(),
            ],
          ),
        ),
      ]);

    return Scaffold(
      backgroundColor: dc.agentRechargeHeaderColor,
      body: bgImg.isNotEmpty
          ? Container(
              decoration: BoxDecoration(
                image: bgImg.startsWith('http')
                    ? DecorationImage(image: NetworkImage(bgImg), fit: BoxFit.cover)
                    : DecorationImage(image: AssetImage(bgImg), fit: BoxFit.cover),
              ),
              child: content,
            )
          : content,
    );
  }

  Widget _buildLockedScreen() => Scaffold(
        appBar: AppBar(
          title: Text('وكالة الشحن',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('🔒', style: TextStyle(fontSize: 52)),
              const SizedBox(height: 16),
              Text('حسابك غير مفعّل كوكيل شحن',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('تواصل مع الإدارة لتفعيل الصلاحية',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(
                      fontSize: 13, color: Colors.black54)),
            ]),
          ),
        ),
      );

  Widget _buildDisabledScreen() => Scaffold(
        appBar: AppBar(
          title: Text('وكالة الشحن',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('⛔', style: TextStyle(fontSize: 52)),
              const SizedBox(height: 16),
              Text('حسابك موقوف مؤقتاً',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.red)),
              const SizedBox(height: 8),
              Text('تواصل مع الإدارة لإعادة التفعيل',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(
                      fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: _bootstrap,
                icon: const Icon(Icons.refresh_rounded),
                label: Text('إعادة المحاولة',
                    style: GoogleFonts.tajawal(
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      );
}
