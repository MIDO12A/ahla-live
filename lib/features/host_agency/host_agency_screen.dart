import 'package:firebase_core/firebase_core.dart';
// lib/features/host_agency/host_agency_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Smart Agency Gateway Screen & Unions Hub
// Matches unions_activity_main.xml & unions_layout_rank_header.xml
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/supabase_compat.dart';

import '../../core/auth/auth_service.dart';
import '../../core/ui/in_app_toast.dart';
import 'screens/agency_profile_screen.dart';
import 'screens/anchor_agent_screen.dart';
import '../financial/agent_recharge_portal_screen.dart';

import '../../core/cache/encrypted_image_provider.dart';
import '../../config/r.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/user_provider.dart';
import '../../services/dynamic_config_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
class HostAgencyScreen extends StatefulWidget {
  const HostAgencyScreen({super.key});

  @override
  State<HostAgencyScreen> createState() => _HostAgencyScreenState();
}

class _HostAgencyScreenState extends State<HostAgencyScreen> {
  bool  _loading = true;
  _UserAgencyRole _role = _UserAgencyRole.none;
  String? _agencyId;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  // ── detect role ─────────────────────────────────────────────────────────────
  Future<void> _detect() async {
    final uid = AuthService.currentSession?.user.id ??
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      // 1. Check host_agency_members for active membership
      var row = await Supabase.instance.client
          .from('host_agency_members')
          .select('role, agency_id')
          .eq('user_id', uid)
          .eq('status', 'active')
          .maybeSingle();

      // 2. If not found, check if user is direct owner in host_agencies
      if (row == null) {
        final ag = await Supabase.instance.client
            .from('host_agencies')
            .select('id, name')
            .eq('owner_id', uid)
            .maybeSingle();
        if (ag != null) {
          row = {
            'role': 'owner',
            'agency_id': ag['id'],
          };
        }
      }

      // 3. If not found, check users/{uid}.agency_id
      if (row == null) {
        final userDoc = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('users').doc(uid).get();
        final agencyId = userDoc.data()?['agency_id'] as String?;
        if (agencyId != null && agencyId.isNotEmpty) {
          row = {
            'role': 'host',
            'agency_id': agencyId,
          };
        }
      }

      if (!mounted) return;
      if (row == null) {
        setState(() { _role = _UserAgencyRole.none; _loading = false; });
      } else {
        final roleStr = row['role'] as String? ?? 'host';
        final aid     = row['agency_id'] as String?;
        _UserAgencyRole role;
        if (roleStr == 'owner') {
          role = _UserAgencyRole.owner;
        } else if (roleStr == 'supervisor') {
          role = _UserAgencyRole.supervisor;
        } else {
          role = _UserAgencyRole.host;
        }
        setState(() { _role = role; _agencyId = aid; _loading = false; });
      }
    } catch (e) {
      debugPrint('[host_agency_screen] error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<DynamicConfigService>();
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFF1A1A1A),
        body: Center(
          child: CircularProgressIndicator(color: cfg.agencyAccent),
        ),
      );
    }

    // Route to the right dashboard immediately
    switch (_role) {
      case _UserAgencyRole.owner:
      case _UserAgencyRole.supervisor:
      case _UserAgencyRole.host:
        return AnchorAgentScreen(agencyId: _agencyId);
      case _UserAgencyRole.none:
        return _BrowseCreateScreen(
          role: _role,
          agencyId: _agencyId,
        );
    }
  }
}

// ── role enum ─────────────────────────────────────────────────────────────────
enum _UserAgencyRole { owner, supervisor, host, none }

// ═══════════════════════════════════════════════════════════════════════════════
//  Browse + Create Screen  —  matches unions_activity_main.xml
// ═══════════════════════════════════════════════════════════════════════════════
class _BrowseCreateScreen extends StatefulWidget {
  final _UserAgencyRole role;
  final String? agencyId;

  const _BrowseCreateScreen({
    this.role = _UserAgencyRole.none,
    this.agencyId,
  });

  @override
  State<_BrowseCreateScreen> createState() => _BrowseCreateScreenState();
}

class _BrowseCreateScreenState extends State<_BrowseCreateScreen>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;

  late final AnimationController _anim = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 900),
  )..forward();

  List<Map<String, dynamic>> _topAgencies = [];
  bool _loadingList = true;
  bool _creating    = false;

  final _nameCtrl    = TextEditingController();
  final _descCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  String? _selectedCountry;
  bool _showForm   = false;

  static const _countries = [
    'السعودية', 'الإمارات', 'الكويت', 'قطر', 'البحرين', 'عُمان',
    'مصر', 'الأردن', 'لبنان', 'العراق', 'سوريا', 'اليمن',
    'المغرب', 'تونس', 'الجزائر', 'ليبيا', 'السودان',
    'تركيا', 'إيران', 'باكستان', 'أخرى',
  ];

  @override
  void initState() {
    super.initState();
    _loadTop();
  }

  @override
  void dispose() {
    _anim.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTop() async {
    try {
      List rows;
      try {
        rows = await _sb
            .from('host_agencies')
            .select('id, name, tier, photo_url, total_diamonds_monthly, member_count, is_hall_of_fame')
            .eq('is_active', true)
            .order('total_diamonds_monthly', ascending: false)
            .limit(20);
      } catch (_) {
        rows = await _sb.from('host_agencies').select('*').limit(30);
      }
      if (mounted) {
        setState(() {
          _topAgencies = List<Map<String, dynamic>>.from(rows);
          _loadingList  = false;
        });
      }
    } catch (e) {
      debugPrint('[host_agency_screen] error: $e');
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _createAgency() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      KayanInAppToast.warning('أدخل اسم الوكالة');
      return;
    }
    final uid = AuthService.currentSession?.user.id ??
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) return;

    setState(() => _creating = true);
    try {
      await _sb.rpc('agency_create', params: {
        'p_name':        name,
        'p_description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'p_photo_url':   null,
        'p_phone':       _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'p_country':     _selectedCountry,
      });
      if (!mounted) return;
      KayanInAppToast.agency('تم إنشاء الوكالة بنجاح! 🎉');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HostAgencyScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      KayanInAppToast.warning('تعذر إنشاء الوكالة: $e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _openSearchDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AgencySearchSheet(onSelect: (agencyId) {
        Navigator.pop(ctx);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AgencyProfileScreen(agencyId: agencyId)),
        );
      }),
    );
  }

  void _openBdCenterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F1F1F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.verified_user_rounded, color: Color(0xFFFFFEEC93), size: 24),
                    SizedBox(width: 8),
                    Text(
                      'مركز تطوير الأعمال (BD Center)',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  '• مرحباً بك في مركز دعم وتطوير وكالات التطبيق الرسمية.\n'
                  '• يتم تقييم الوكالات أسبوعياً بناءً على إجمالي ألماس مضيفي الوكالة.\n'
                  '• الترقية إلى فئات متقدمة (Gold, Platinum, Diamond) تمنح الوكالة نسب أرباح إضافية ومكافآت حصرية.\n'
                  '• للتواصل مع فريق إدارة الوكالات ومسؤولي الـ BD يرجى مراجعة خدمة العملاء.',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF9500),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('فهمت ذلك', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<DynamicConfigService>();
    final bgImg = cfg.hostAgencyBgImage;

    final scrollView = CustomScrollView(
      slivers: [
        _buildHeader(cfg),
        SliverToBoxAdapter(child: _buildRechargeAgentBanner()),
        if (cfg.hostAgencyBannerImage.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: cfg.hostAgencyBannerImage.startsWith('http')
                    ? Image.network(cfg.hostAgencyBannerImage, height: 90, width: double.infinity, fit: BoxFit.cover)
                    : Image.asset(cfg.hostAgencyBannerImage, height: 90, width: double.infinity, fit: BoxFit.cover),
              ),
            ),
          ),
        SliverToBoxAdapter(child: _buildUnionRankHeader(cfg)),
        if (_showForm) ...[
          SliverToBoxAdapter(child: const SizedBox(height: 16)),
          SliverToBoxAdapter(child: _buildCreateForm(cfg)),
        ],
        SliverToBoxAdapter(child: const SizedBox(height: 12)),
        SliverToBoxAdapter(child: _buildRankTitleBanner()),
        const SliverToBoxAdapter(child: SizedBox(height: 10)),
        _buildRankAgenciesList(cfg),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: cfg.hostAgencyHeaderColor,
        body: FadeTransition(
          opacity: _anim,
          child: bgImg.isNotEmpty
              ? Container(
                  decoration: BoxDecoration(
                    image: bgImg.startsWith('http')
                        ? DecorationImage(image: NetworkImage(bgImg), fit: BoxFit.cover)
                        : DecorationImage(image: AssetImage(bgImg), fit: BoxFit.cover),
                  ),
                  child: scrollView,
                )
              : scrollView,
        ),
      ),
    );
  }

  Widget _buildRechargeAgentBanner() {
    final user = Provider.of<UserProvider>(context, listen: false).currentUser;
    if (user?.isRechargeAgent != true) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1E07), Color(0xFF1F1805)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFD700)),
            ),
            child: const Center(
              child: Text('💼', style: TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user?.rechargeAgencyName ?? 'وكالة الشحن المعتمدة',
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'وكيل معتمد',
                        style: TextStyle(color: Color(0xFFFFD700), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  'أنت وكيل شحن معتمد. انقر هنا لدخول لوحة تحكم الوكالة وشحن الرصيد.',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AgentRechargePortalScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'دخول البوابة',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(DynamicConfigService cfg) {
    return SliverAppBar(
      expandedHeight: 0,
      pinned: true,
      backgroundColor: const Color(0xFF1A1A1A),
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Image.asset(
          'assets/mipmap-xxhdpi/common_back_2.webp',
          width: 32,
          height: 32,
          errorBuilder: (_, __, ___) => const Icon(Icons.arrow_back, color: Colors.white),
        ),
        onPressed: () => Navigator.maybePop(context),
      ),
      title: Image.asset(
        R.unionsTitleIc,
        height: 24,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Text(
          'الوكالات',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: Image.asset(
            R.unionsSearchIc,
            width: 32,
            height: 32,
            errorBuilder: (_, __, ___) => const Icon(Icons.search, color: Colors.white),
          ),
          tooltip: 'بحث عن وكالة',
          onPressed: _openSearchDialog,
        ),
      ],
    );
  }

  // unions_layout_rank_header.xml
  Widget _buildUnionRankHeader(DynamicConfigService cfg) {
    return SizedBox(
      height: 230,
      width: double.infinity,
      child: Stack(
        children: [
          // Header background image
          Positioned.fill(
            child: cfg.hostAgencyHeaderBgImage.isNotEmpty
                ? (cfg.hostAgencyHeaderBgImage.startsWith('http')
                    ? Image.network(cfg.hostAgencyHeaderBgImage, fit: BoxFit.cover)
                    : Image.asset(cfg.hostAgencyHeaderBgImage, fit: BoxFit.cover))
                : Image.asset(
                    'assets/mipmap-xxhdpi/unions_rank_header_bg.webp',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF2E1A47), Color(0xFF1A1A1A)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
          ),
          // 4 function buttons
          Positioned(
            left: 12,
            right: 12,
            bottom: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // 1. Admin Center
                _buildFunctionButton(
                  iconAsset: 'assets/mipmap-xxhdpi/union_admin_center.webp',
                  title: 'مركز الإدارة',
                  onTap: () {
                    if (widget.role == _UserAgencyRole.owner || widget.role == _UserAgencyRole.supervisor) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AnchorAgentScreen(agencyId: widget.agencyId)),
                      );
                    } else {
                      KayanInAppToast.warning('هذا المركز مخصص لمدراء الوكالات فقط');
                    }
                  },
                ),
                // 2. My Agency
                _buildFunctionButton(
                  iconAsset: 'assets/mipmap-xxhdpi/union_my_agency.webp',
                  title: 'وكالتي',
                  onTap: () {
                    if (widget.role != _UserAgencyRole.none && widget.agencyId != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AgencyProfileScreen(agencyId: widget.agencyId!)),
                      );
                    } else {
                      KayanInAppToast.warning('لست منضماً لأي وكالة حالياً');
                    }
                  },
                ),
                // 3. Create Guild
                _buildFunctionButton(
                  iconAsset: 'assets/mipmap-xxhdpi/union_create_guild.webp',
                  title: 'إنشاء وكالة',
                  onTap: () {
                    setState(() {
                      _showForm = !_showForm;
                    });
                  },
                ),
                // 4. BD Center
                _buildFunctionButton(
                  iconAsset: 'assets/mipmap-xxhdpi/union_bd_center.webp',
                  title: 'مركز BD',
                  onTap: _openBdCenterSheet,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFunctionButton({
    required String iconAsset,
    required String title,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            iconAsset,
            width: 52,
            height: 52,
            errorBuilder: (_, __, ___) => Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.business, color: Colors.white),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFFFFFF5AD),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // unions_layout_rank_header.xml -> cl_title
  Widget _buildRankTitleBanner() {
    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/mipmap-xxhdpi/union_rank_title_bg.webp',
                fit: BoxFit.fill,
                errorBuilder: (_, __, ___) => Container(color: Colors.white10),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/mipmap-xxhdpi/union_rank_start.webp',
                height: 14,
                errorBuilder: (_, __, ___) => const SizedBox(),
              ),
              const SizedBox(width: 8),
              const Text(
                'ترتيب الوكالات الأسبوعي',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFFFF5AD),
                ),
              ),
              const SizedBox(width: 8),
              Image.asset(
                'assets/mipmap-xxhdpi/union_rank_end.webp',
                height: 14,
                errorBuilder: (_, __, ___) => const SizedBox(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRankAgenciesList(DynamicConfigService cfg) {
    if (_loadingList) {
      return SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: CircularProgressIndicator(color: cfg.agencyAccent),
          ),
        ),
      );
    }
    if (_topAgencies.isEmpty) {
      return const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('لا توجد وكالات بعد', style: TextStyle(color: Colors.white54)),
          ),
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final agency = _topAgencies[i];
          return _AgencyRankItem(
            agency: agency,
            rank: i + 1,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AgencyProfileScreen(agencyId: agency['id'] as String),
                ),
              );
            },
          );
        },
        childCount: _topAgencies.length,
      ),
    );
  }

  Widget _buildCreateForm(DynamicConfigService cfg) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFFEEC93).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'إنشاء وكالة جديدة',
            style: TextStyle(color: Color(0xFFFFFEEC93), fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),
          _field(_nameCtrl, 'اسم الوكالة *', Icons.badge_rounded),
          const SizedBox(height: 12),
          _field(_descCtrl, 'وصف الوكالة (اختياري)', Icons.description_rounded, maxLines: 2),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedCountry,
            dropdownColor: const Color(0xFF242424),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'الدولة (اختياري)',
              hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
              prefixIcon: const Icon(Icons.flag_rounded, color: Colors.white54, size: 18),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white24),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFFF9500)),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            items: _countries.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _selectedCountry = v),
          ),
          const SizedBox(height: 12),
          _field(_phoneCtrl, 'رقم الهاتف (اختياري)', Icons.phone_rounded, keyboardType: TextInputType.phone),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _creating ? null : _createAgency,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9500),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _creating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('تأكيد إنشاء الوكالة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint, IconData icon, {int maxLines = 1, TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white54, size: 18),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFFF9500)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

// ── union_layout_rank_item.xml ─────────────────────────────────────────────────
class _AgencyRankItem extends StatelessWidget {
  final Map<String, dynamic> agency;
  final int rank;
  final VoidCallback onTap;

  const _AgencyRankItem({
    required this.agency,
    required this.rank,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = agency['name'] as String? ?? 'وكالة';
    final photoUrl = agency['photo_url'] as String?;
    final diamonds = (agency['total_diamonds_monthly'] as num?)?.toInt() ?? 0;
    final members = (agency['member_count'] as num?)?.toInt() ?? 0;
    final id = agency['id'] as String? ?? '';
    final shortId = id.length > 8 ? id.substring(0, 8) : id;

    String cardBg;
    String numBg;
    String? labelIc;

    if (rank == 1) {
      cardBg = 'assets/mipmap-xxhdpi/union_rank_1_bg.webp';
      numBg = 'assets/mipmap-xxhdpi/union_rank_1_num_bg.webp';
      labelIc = 'assets/mipmap-xxhdpi/union_rank_label_1_ic.webp';
    } else if (rank == 2) {
      cardBg = 'assets/mipmap-xxhdpi/union_rank_2_bg.webp';
      numBg = 'assets/mipmap-xxhdpi/union_rank_2_num_bg.webp';
      labelIc = 'assets/mipmap-xxhdpi/union_rank_label_2_ic.webp';
    } else if (rank == 3) {
      cardBg = 'assets/mipmap-xxhdpi/union_rank_3_bg.webp';
      numBg = 'assets/mipmap-xxhdpi/union_rank_3_num_bg.webp';
      labelIc = 'assets/mipmap-xxhdpi/union_rank_label_3_ic.webp';
    } else {
      cardBg = 'assets/mipmap-xxhdpi/union_rank_default_bg.webp';
      numBg = 'assets/mipmap-xxhdpi/union_rank_default_num_bg.webp';
      labelIc = null;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 84,
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Stack(
          children: [
            // Background Image
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  cardBg,
                  fit: BoxFit.fill,
                  errorBuilder: (_, __, ___) => Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF242424),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                  ),
                ),
              ),
            ),
            // Rank Number & Label
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 58,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.asset(
                    numBg,
                    fit: BoxFit.fill,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  ),
                  if (labelIc != null)
                    Positioned(
                      top: 4,
                      child: Image.asset(
                        labelIc,
                        width: 24,
                        height: 24,
                        errorBuilder: (_, __, ___) => const SizedBox(),
                      ),
                    ),
                  Positioned(
                    bottom: labelIc != null ? 8 : null,
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: rank <= 3 ? 18 : 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content Row
            Positioned.fill(
              left: 62,
              right: 12,
              child: Row(
                children: [
                  // Agency Avatar
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFFEEC93), width: 1.5),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: (photoUrl != null && photoUrl.isNotEmpty)
                        ? Image(
                            image: EncryptedImageProvider(photoUrl),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                name.isNotEmpty ? name.characters.first : '?',
                                style: const TextStyle(color: Color(0xFFFFFEEC93), fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              name.isNotEmpty ? name.characters.first : '?',
                              style: const TextStyle(color: Color(0xFFFFFEEC93), fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  // Agency Name & Member count
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            // Member count badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    'assets/mipmap-xxhdpi/union_member_count_ic.webp',
                                    width: 14,
                                    height: 14,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.group, size: 12, color: Colors.white70),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$members',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'ID: $shortId',
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Diamonds
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        '♦',
                        style: TextStyle(color: Color(0xFFFFFEEC93), fontSize: 14),
                      ),
                      Text(
                        _fmt(diamonds),
                        style: const TextStyle(
                          color: Color(0xFFFFFEEC93),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ── unions_activity_search.xml ────────────────────────────────────────────────
class _AgencySearchSheet extends StatefulWidget {
  final void Function(String agencyId) onSelect;

  const _AgencySearchSheet({required this.onSelect});

  @override
  State<_AgencySearchSheet> createState() => _AgencySearchSheetState();
}

class _AgencySearchSheetState extends State<_AgencySearchSheet> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;

  void _doSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final rows = await Supabase.instance.client
          .from('host_agencies')
          .select('id, name, photo_url, member_count, total_diamonds_monthly')
          .or('name.ilike.%$q%,id.ilike.%$q%')
          .limit(15);
      if (mounted) {
        setState(() {
          _results = List<Map<String, dynamic>>.from(rows as List);
          _searching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          // Search Bar
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF292929),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/mipmap-xxhdpi/unions_search_ic.webp',
                        width: 20,
                        height: 20,
                        errorBuilder: (_, __, ___) => const Icon(Icons.search, color: Colors.white54, size: 20),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'ابحث عن اسم أو معرّف الوكالة...',
                            hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: _doSearch,
                        ),
                      ),
                      if (_searchCtrl.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _results = []);
                          },
                          child: const Icon(Icons.close, color: Colors.white54, size: 18),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Text('إلغاء', style: TextStyle(color: Color(0xFFD4D6E5), fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF9500)))
                : _results.isEmpty
                    ? Center(
                        child: Text(
                          _searchCtrl.text.isEmpty ? 'اكتب اسم أو معرّف الوكالة للبحث' : 'لم يتم العثور على أي وكالة',
                          style: const TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, i) {
                          final item = _results[i];
                          return _AgencyRankItem(
                            agency: item,
                            rank: i + 1,
                            onTap: () => widget.onSelect(item['id'] as String),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
