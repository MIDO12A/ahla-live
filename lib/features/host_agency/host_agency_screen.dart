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
import '../../services/supabase_auth_service.dart';
import '../../core/ui/in_app_toast.dart';
import 'screens/agency_profile_screen.dart';
import 'screens/anchor_agent_screen.dart';
import 'screens/agency_pending_approval_screen.dart';

import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../services/cloudinary_service.dart';
import '../../services/supabase_data_service.dart';
import '../../models/user_model.dart';
import 'screens/bd_center_screen.dart';
import '../../core/cache/encrypted_image_provider.dart';
import '../../config/r.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../services/dynamic_config_service.dart';
import 'data/agency_models.dart';

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
  String? _agencyName;
  Map<String, dynamic>? _pendingApplicationData;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  // ── detect role ─────────────────────────────────────────────────────────────
  Future<void> _detect() async {
    final user = Provider.of<UserProvider>(context, listen: false).currentUser;
    final uid = user?.uid ??
        SupabaseAuthService().currentUser?.uid ??
        AuthService.currentSession?.user.id;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      Map<String, dynamic>? row;

      // 1. Check Supabase host_agency_members (column is host_uid or user_id)
      try {
        final m = await Supabase.instance.client
            .from('host_agency_members')
            .select('role, agency_id')
            .or('host_uid.eq.$uid,user_id.eq.$uid')
            .eq('status', 'active')
            .maybeSingle();
        if (m != null && m['agency_id'] != null && m['agency_id'].toString().isNotEmpty && m['agency_id'].toString() != 'null') {
          row = {'role': m['role'] ?? 'host', 'agency_id': m['agency_id'].toString()};
        }
      } catch (_) {}

      // 2. Check Supabase host_agencies (column is owner_uid) - only if active
      if (row == null) {
        try {
          final ag = await Supabase.instance.client
              .from('host_agencies')
              .select('id, name, status, is_active, owner_uid, owner_id')
              .or('owner_uid.eq.$uid,owner_id.eq.$uid')
              .maybeSingle();
          if (ag != null && ag['id'] != null && (ag['status'] == 'active' || ag['is_active'] == true)) {
            row = {'role': 'owner', 'agency_id': ag['id'].toString(), 'name': ag['name']?.toString()};
          }
        } catch (_) {}
      }

      // 3. Check Supabase users table - verify user is actually the agency owner
      if (row == null) {
        try {
          final u = await Supabase.instance.client
              .from('users')
              .select('agency_id, is_host_agent')
              .eq('uid', uid)
              .maybeSingle();
          if (u != null && u['agency_id'] != null && u['agency_id'].toString().isNotEmpty && u['agency_id'].toString() != 'null' && u['is_host_agent'] == true) {
            final agCheck = await Supabase.instance.client
                .from('host_agencies')
                .select('owner_uid, owner_id, name')
                .eq('id', u['agency_id'].toString())
                .maybeSingle();
            final isRealOwner = agCheck != null && (agCheck['owner_uid'] == uid || agCheck['owner_id'] == uid);
            if (isRealOwner) {
              row = {
                'role': 'owner',
                'agency_id': u['agency_id'].toString(),
                'name': agCheck['name']?.toString(),
              };
            }
          }
        } catch (_) {}
      }

      // 4. Check pending agency application if user doesn't have an active agency
      if (row == null) {
        Map<String, dynamic>? pendingApp;
        try {
          final pRows = await Supabase.instance.client
              .from('agency_applications')
              .select('*')
              .eq('applicant_uid', uid)
              .order('created_at', ascending: false)
              .limit(1);
          if (pRows.isNotEmpty) {
            final appRow = Map<String, dynamic>.from(pRows.first as Map);
            final st = appRow['status']?.toString().toLowerCase();
            // Only true pending/waiting applications block the user
            if (st == 'pending' || st == 'waiting_approval') {
              pendingApp = appRow;
            }
          }
        } catch (_) {}

        if (pendingApp != null) {
          if (!mounted) return;
          setState(() {
            _role = _UserAgencyRole.pendingApproval;
            _pendingApplicationData = pendingApp;
            _agencyId = pendingApp?['agency_id']?.toString();
            _agencyName = null;
            _loading = false;
          });
          return;
        }
      }

      if (!mounted) return;
      if (row == null) {
        setState(() {
          _role = _UserAgencyRole.none;
          _agencyId = null;
          _agencyName = null;
          _loading = false;
        });
      } else {
        final roleStr = row['role'] as String? ?? 'host';
        final aid     = row['agency_id'] as String?;
        String? agName = row['name'] as String?;

        if (agName == null && aid != null && aid.isNotEmpty) {
          try {
            final agInfo = await Supabase.instance.client
                .from('host_agencies')
                .select('name')
                .eq('id', aid)
                .maybeSingle();
            if (agInfo != null && agInfo['name'] != null) {
              agName = agInfo['name'].toString();
            }
          } catch (_) {}
        }

        _UserAgencyRole role;
        if (roleStr == 'owner') {
          role = _UserAgencyRole.owner;
        } else if (roleStr == 'supervisor') {
          role = _UserAgencyRole.supervisor;
        } else {
          role = _UserAgencyRole.host;
        }
        setState(() {
          _role = role;
          _agencyId = aid;
          _agencyName = agName;
          _loading = false;
        });
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

    // Always open browse and create screen by default for full agency access
    return _BrowseCreateScreen(
      role: _role,
      agencyId: _agencyId,
      agencyName: _agencyName,
      pendingApplication: _pendingApplicationData,
    );
  }
}

// ── role enum ─────────────────────────────────────────────────────────────────
enum _UserAgencyRole { owner, supervisor, host, pendingApproval, none }

// ═══════════════════════════════════════════════════════════════════════════════
//  Browse + Create Screen  —  matches unions_activity_main.xml
// ═══════════════════════════════════════════════════════════════════════════════
class _BrowseCreateScreen extends StatefulWidget {
  final _UserAgencyRole role;
  final String? agencyId;
  final String? agencyName;
  final Map<String, dynamic>? pendingApplication;

  const _BrowseCreateScreen({
    this.role = _UserAgencyRole.none,
    this.agencyId,
    this.agencyName,
    this.pendingApplication,
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

  final _nameCtrl       = TextEditingController();
  final _descCtrl       = TextEditingController();
  final _phoneCtrl      = TextEditingController();
  final _supervisorCtrl = TextEditingController();
  String? _selectedCountry;
  bool _showForm      = false;
  File? _agencyImage;
  bool _pickingImage  = false;
  String? _supervisorName;
  bool _lookingUpSupervisor = false;

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
    _supervisorCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAgencyImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked != null) {
        setState(() {
          _agencyImage = File(picked.path);
        });
      }
    } catch (e) {
      debugPrint('[host_agency_screen] image pick error: $e');
    }
  }

  Future<void> _lookupSupervisor(String id) async {
    final clean = id.trim();
    if (clean.isEmpty) {
      setState(() => _supervisorName = null);
      return;
    }
    setState(() => _lookingUpSupervisor = true);
    try {
      final user = await SupabaseDataService().findUserByIdOrCustomId(clean);
      if (mounted) {
        setState(() {
          _supervisorName = user != null && user.name.isNotEmpty ? user.name : null;
          _lookingUpSupervisor = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _lookingUpSupervisor = false);
    }
  }

  Future<void> _loadTop() async {
    try {
      List rows = [];
      try {
        rows = await _sb
            .from('active_agencies')
            .select('id, name, tier, photo_url, total_diamonds_monthly, member_count, is_hall_of_fame')
            .order('total_diamonds_monthly', ascending: false)
            .limit(50);
      } catch (_) {}

      if (rows.isEmpty) {
        try {
          rows = await _sb
              .from('host_agencies')
              .select('*')
              .order('created_at', ascending: false)
              .limit(50);
        } catch (_) {}
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
      KayanInAppToast.warning('يرجى إدخال اسم الوكالة');
      return;
    }

    final supervisorQuery = _supervisorCtrl.text.trim();
    if (supervisorQuery.isEmpty) {
      KayanInAppToast.warning('يجب إدخال آيدي المشرف أو مسؤول الـ BD التابع له');
      return;
    }

    final currentUser = Provider.of<UserProvider>(context, listen: false).currentUser;
    final uid = currentUser?.uid ??
        SupabaseAuthService().currentUser?.uid ??
        AuthService.currentSession?.user.id;
    if (uid == null) {
      KayanInAppToast.warning('يجب تسجيل الدخول أولاً');
      return;
    }

    setState(() => _creating = true);
    try {
      // 1. Resolve supervisor details
      UserModel? supervisorUser;
      try {
        supervisorUser = await SupabaseDataService().findUserByIdOrCustomId(supervisorQuery);
      } catch (_) {}

      final supervisorUid = supervisorUser?.uid ?? supervisorQuery;
      final supervisorCustomId = supervisorUser?.customId.isNotEmpty == true ? supervisorUser!.customId : supervisorQuery;
      final supervisorName = supervisorUser?.name.isNotEmpty == true ? supervisorUser!.name : (_supervisorName ?? 'مشرف معتمد');

      // 2. Upload photo if selected
      String? photoUrl;
      if (_agencyImage != null) {
        try {
          photoUrl = await CloudinaryService().uploadImage(
            _agencyImage!,
            publicId: 'agency_${DateTime.now().millisecondsSinceEpoch}',
          );
        } catch (uploadErr) {
          debugPrint('[host_agency_screen] upload photo error: $uploadErr');
        }
      }

      final now = DateTime.now().toUtc();
      final nowIso = now.toIso8601String();
      final agencyId = 'agency_${now.millisecondsSinceEpoch}_$uid';
      final agencyCode = (100 + (now.millisecondsSinceEpoch % 900)).toString();
      final finalLogo = photoUrl ?? currentUser?.photoUrl ?? '';

      // 3. Application payload for Supabase agency_applications table
      final appId = 'app_${now.millisecondsSinceEpoch}_$uid';
      final applicationPayload = {
        'id': appId,
        'applicant_uid': uid,
        'agency_name': name,
        'description': _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : 'وكالة مضيفين معتمدة',
        'whatsapp': _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
        'country': _selectedCountry ?? 'عالمي',
        'status': 'pending',
        'created_at': nowIso,
      };

      // 4. Pre-register agency record as pending in Supabase host_agencies
      final agencyCodeInt = int.tryParse(agencyCode) ?? (100 + (now.millisecondsSinceEpoch % 900));
      final agencyPayload = {
        'id': agencyId,
        'name': name,
        'agency_code': agencyCodeInt,
        'owner_uid': uid,
        'owner_id': uid,
        'description': _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : 'وكالة مضيفين معتمدة',
        'logo_url': finalLogo,
        'background_url': '',
        'announcement': '',
        'level': 1,
        'monthly_exp': 0,
        'total_exp': 0,
        'total_diamonds_monthly': 0,
        'total_diamonds_cumulative': 0,
        'monthly_diamonds': 0,
        'member_count': 1,
        'admin_count': 0,
        'is_active': false,
        'status': 'pending',
        'data': {
          'whatsapp': _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
          'country': _selectedCountry ?? 'عالمي',
          'tier': 'bronze',
          'commission_rate': 0.10,
          'supervisor_id': supervisorCustomId,
          'supervisor_uid': supervisorUid,
          'supervisor_custom_id': supervisorCustomId,
          'supervisor_name': supervisorName,
          'bd_uid': supervisorUid,
          'bd_id': supervisorCustomId,
          'app_id': appId,
          'agency_code': agencyCode,
          'user_name': currentUser?.name ?? 'مستخدم',
          'custom_id': currentUser?.customId ?? '',
          'user_avatar': finalLogo,
        },
        'created_at': nowIso,
        'updated_at': nowIso,
      };

      // 5. Save to Supabase (agency_applications & host_agencies)
      try {
        await _sb.from('agency_applications').insert(applicationPayload);
      } catch (appErr) {
        debugPrint('[host_agency_screen] Supabase insert agency_applications error: $appErr');
      }

      try {
        await _sb.from('host_agencies').upsert(agencyPayload);
      } catch (agErr) {
        debugPrint('[host_agency_screen] Supabase upsert host_agencies error: $agErr');
      }

      // 6. Send notification to supervisor via Supabase
      if (supervisorUid.isNotEmpty && supervisorUid != uid) {
        try {
          await SupabaseDataService().sendNotification(
            uid: supervisorUid,
            type: 'agency_application',
            title: 'طلب فتح وكالة جديدة تحت إشرافك 🎙️',
            body: 'قدم المستخدم [${currentUser?.name ?? "مستخدم"}] طلب فتح وكالة [$name] تحت إشرافك.',
            data: {'agency_id': agencyId, 'app_id': appId},
          );
        } catch (e) {
          debugPrint('[host_agency_screen] supervisor notification error: $e');
        }
      }

      if (!mounted) return;
      KayanInAppToast.agency('تم إرسال طلب فتح الوكالة بنجاح وهو بانتظار موافقة الإدارة ⏳');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AgencyPendingApprovalScreen(
            applicationData: applicationPayload,
            agencyId: agencyId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      KayanInAppToast.warning('تعذر إرسال طلب الوكالة: $e');
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

  Future<void> _openBdCenterSheet() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    var user = userProvider.currentUser;
    final uid = user?.uid ?? AuthService.currentSession?.user.id ?? SupabaseAuthService().currentUser?.uid;

    if (uid == null || uid.isEmpty) {
      KayanInAppToast.warning('يرجى تسجيل الدخول أولاً');
      return;
    }

    bool isBd = user?.isBd == true;

    // Comprehensive check across Supabase users and app_config
    if (!isBd) {
      // 1. Supabase users table
      try {
        final row = await _sb.from('users').select('is_bd, role').or('uid.eq.$uid,id.eq.$uid').maybeSingle();
        if (row != null && (row['is_bd'] == true || row['role'] == 'bd' || ['supervisor', 'admin', 'super_admin'].contains(row['role']))) {
          isBd = true;
        }
      } catch (_) {}

      // 2. Supabase app_config (bd_meta_$uid)
      if (!isBd) {
        try {
          final cfg = await _sb.from('app_config').select('value').eq('key', 'bd_meta_$uid').maybeSingle();
          if (cfg != null && cfg['value'] != null) {
            final val = cfg['value'] as Map?;
            if (val != null && val['status'] != 'revoked') {
              isBd = true;
            }
          }
        } catch (_) {}
      }


    }

    if (isBd) {
      await userProvider.loadUser(uid);
      user = userProvider.currentUser;
      if (user != null && !user.isBd) {
        user = user.copyWith(isBd: true);
      }
      if (mounted && user != null) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BDCenterScreen(currentUser: user!)),
        );
      }
      return;
    }

    if (!mounted) return;
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
                  '• الترقية إلى فئات متقدمة تمنح الوكالة نسب أرباح إضافية ومكافآت حصرية.\n'
                  '• للتواصل مع فريق إدارة الوكالات ومسؤولي الـ BD يرجى مراجعة خدمة العملاء.',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 14),
                if (user != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Color(0xFFFF9500), size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'إذا تم تعيينك مؤخراً كـ BD أو مشرف، اضغط أدناه لتحديث الصلاحيات والدخول للمركز.',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          bool verified = false;

                          // Refresh and verify BD status
                          try {
                            final row = await _sb.from('users').select('is_bd, role').or('uid.eq.$uid,id.eq.$uid').maybeSingle();
                            if (row != null && (row['is_bd'] == true || row['role'] == 'bd')) {
                              verified = true;
                            }
                          } catch (_) {}

                          if (!verified) {
                            try {
                              final cfg = await _sb.from('app_config').select('value').eq('key', 'bd_meta_$uid').maybeSingle();
                              if (cfg != null && cfg['value'] != null) {
                                final val = cfg['value'] as Map?;
                                if (val != null && val['status'] != 'revoked') verified = true;
                              }
                            } catch (_) {}
                          }



                          if (verified) {
                            await userProvider.loadUser(uid);
                            var fresh = userProvider.currentUser;
                            if (fresh != null && !fresh.isBd) {
                              fresh = fresh.copyWith(isBd: true);
                            }
                            if (context.mounted && fresh != null) {
                              KayanInAppToast.success('تم تفعيل صلاحيات الـ BD بنجاح 🎉');
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => BDCenterScreen(currentUser: fresh!)),
                              );
                              return;
                            }
                          }

                          KayanInAppToast.warning('حسابك ليس مسجلاً كمسؤول BD بعد');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9500),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('تحديث والدخول كـ BD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إغلاق', style: TextStyle(color: Colors.white54)),
                    ),
                  ],
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
        if (widget.agencyId != null && widget.agencyId!.isNotEmpty && widget.role != _UserAgencyRole.none)
          SliverToBoxAdapter(child: _buildMyAgencyCard(cfg)),
        if (widget.role == _UserAgencyRole.pendingApproval)
          SliverToBoxAdapter(child: _buildPendingApprovalCard()),
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

  // ── My Agency Quick Entry Banner ──
  Widget _buildMyAgencyCard(DynamicConfigService cfg) {
    final roleText = widget.role == _UserAgencyRole.owner
        ? 'مالك الوكالة'
        : widget.role == _UserAgencyRole.supervisor
            ? 'مشرف الوكالة'
            : 'مضيف رسمي بالوكالة';

    final agencyDisplayName = widget.agencyName != null && widget.agencyName!.isNotEmpty
        ? widget.agencyName!
        : 'وكالتي الرسمية';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E1A47), Color(0xFF1E1E2E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
            ),
            child: const Icon(Icons.shield_rounded, color: Color(0xFFFFD700), size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9500).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFF9500), width: 0.8),
                      ),
                      child: Text(
                        roleText,
                        style: const TextStyle(
                          color: Color(0xFFFF9500),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  agencyDisplayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                const Text(
                  'اضغط للدخول إلى لوحة التحكم والتارجت والأرباح',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AnchorAgentScreen(agencyId: widget.agencyId),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9500),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              minimumSize: Size.zero,
              elevation: 4,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('دخول', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios_rounded, size: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Pending Approval Banner ──
  Widget _buildPendingApprovalCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2416),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFF9500).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded, color: Color(0xFFFF9500), size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'طلب الانضمام قيد المراجعة',
                  style: TextStyle(color: Color(0xFFFFFEEC93), fontSize: 13, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 2),
                Text(
                  'تم إرسال طلبك إلى إدارة الوكالة وهو قيد التدقيق حالياً.',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AgencyPendingApprovalScreen(
                    applicationData: widget.pendingApplication,
                    agencyId: widget.agencyId,
                  ),
                ),
              );
            },
            child: const Text('متابعة', style: TextStyle(color: Color(0xFFFF9500), fontWeight: FontWeight.bold)),
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
                    if (widget.role != _UserAgencyRole.none && widget.agencyId != null && widget.agencyId!.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AnchorAgentScreen(agencyId: widget.agencyId)),
                      );
                    } else {
                      KayanInAppToast.warning('لست منضماً لأي وكالة حالياً - يمكنك تصفح قائمة الوكالات أدناه لتقديم طلب انضمام');
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
          const Center(
            child: Text(
              'إنشاء وكالة مضيفين جديدة',
              style: TextStyle(color: Color(0xFFFFFEEC93), fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ),
          const SizedBox(height: 16),

          // ── Agency Avatar Picker ──
          Center(
            child: GestureDetector(
              onTap: _pickAgencyImage,
              child: Stack(
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.08),
                      border: Border.all(color: const Color(0xFFFF9500), width: 2),
                      image: _agencyImage != null
                          ? DecorationImage(image: FileImage(_agencyImage!), fit: BoxFit.cover)
                          : null,
                    ),
                    child: _agencyImage == null
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo_rounded, color: Color(0xFFFFFEEC93), size: 28),
                                SizedBox(height: 4),
                                Text(
                                  'شعار الوكالة',
                                  style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF9500),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.edit, color: Colors.white, size: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          _field(_nameCtrl, 'اسم الوكالة *', Icons.badge_rounded),
          const SizedBox(height: 12),

          // ── Required Supervisor / BD ID ──
          _field(
            _supervisorCtrl,
            'آيدي المشرف أو مسؤول الـ BD *',
            Icons.supervisor_account_rounded,
            onChanged: _lookupSupervisor,
          ),
          if (_lookingUpSupervisor) ...[
            const SizedBox(height: 6),
            const Row(
              children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF9500))),
                SizedBox(width: 8),
                Text('جاري التحقق من هوية المشرف...', style: TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ] else if (_supervisorName != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5A0).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF00E5A0).withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified, color: Color(0xFF00E5A0), size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'المشرف المعتمد: $_supervisorName',
                    style: const TextStyle(color: Color(0xFF00E5A0), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ] else if (_supervisorCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text(
              '⚠️ سيتم ربط طلب الوكالة بالآيدي المدخل لإشراف الـ BD',
              style: TextStyle(color: Color(0xFFFFB800), fontSize: 11),
            ),
          ],
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
          _field(_phoneCtrl, 'رقم الهاتف / واتساب (اختياري)', Icons.phone_rounded, keyboardType: TextInputType.phone),
          const SizedBox(height: 18),
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

  Widget _field(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    int maxLines = 1,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
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
    final photoUrl = agency['photo_url'] as String? ?? agency['photoUrl'] as String? ?? agency['logo_url'] as String? ?? agency['avatar'] as String?;
    final diamonds = (agency['total_diamonds_monthly'] as num?)?.toInt() ?? 0;
    final members = (agency['member_count'] as num?)?.toInt() ?? 0;
    final displayId = formatAgencyNumericId(agency);

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
                            image: (photoUrl.startsWith('http') && !photoUrl.endsWith('.enc'))
                                ? R.cachedImage(photoUrl)
                                : EncryptedImageProvider(photoUrl),
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
                              'ID: $displayId',
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
      final combined = <Map<String, dynamic>>[];
      final seenIds = <String>{};

      // 1. Supabase search
      try {
        final rows = await Supabase.instance.client
            .from('host_agencies')
            .select('id, name, photo_url, member_count, total_diamonds_monthly, agency_public_id, agency_code')
            .or('name.ilike.%$q%,id.ilike.%$q%,agency_public_id.ilike.%$q%,agency_code.ilike.%$q%')
            .limit(20);
        for (final r in rows) {
          final m = Map<String, dynamic>.from(r as Map);
          final id = m['id']?.toString() ?? '';
          if (id.isNotEmpty && !seenIds.contains(id)) {
            seenIds.add(id);
            combined.add(m);
          }
        }
      } catch (_) {}



      // If user typed 3-digit number (e.g. 100, 200), prioritize matches where formatAgencyNumericId == q
      combined.sort((a, b) {
        final numA = formatAgencyNumericId(a);
        final numB = formatAgencyNumericId(b);
        if (numA == q && numB != q) return -1;
        if (numB == q && numA != q) return 1;
        return 0;
      });

      if (mounted) {
        setState(() {
          _results = combined;
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
