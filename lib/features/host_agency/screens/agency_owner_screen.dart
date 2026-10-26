// lib/features/host_agency/screens/agency_owner_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Exact Replica of Hayuki's act_union_center_v2.xml & Supporting Layouts:
// • vh_union_center_top_info.xml: Agency avatar, edit, name, ID, broadcast banner
// • vh_agency_level.xml: Level background, exp progress, flag, tier badge
// • ic_rank_banner_bg: Ranking banner
// • vh_admin_functionalities_panel.xml: Application review & member salary
// • withdrawalAccountPanel & withdrawRecordPanel: Withdrawal cards
// • item_union_member.xml: Host avatar, host tag, name, UID, stage target completion,
//   remaining diamonds & hours to next stage, member details dialog, and member deletion.
// • act_union_add_menber.xml: Add member by user ID
// • act_union_profile.xml: Edit agency photo, name, and announcement
// • dialog_union_mem_more_v2.xml: Member options, admin settings, remove member
// • layout_union_agency_salary_panel.xml: Agency salary and stage summary
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/supabase_compat.dart';
import '../../../../core/ui/in_app_toast.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/dynamic_config_service.dart';
import '../../../../services/supabase_data_service.dart';
import '../../../../services/supabase_service.dart';
import '../../../../services/cloudinary_service.dart';
import 'package:image_picker/image_picker.dart';
import '../data/anchor_agent_model.dart';
import 'agency_join_requests_screen.dart';
import 'agency_leaderboard_screen.dart';
import 'agency_level_desc_screen.dart';
import 'agency_owner_wallet_screen.dart';
import 'agency_withdrawal_screen.dart';
import 'agency_disbursement_screen.dart';
import 'agency_exit_screen.dart';

class AgencyOwnerScreen extends StatefulWidget {
  final String? agencyId;

  const AgencyOwnerScreen({super.key, this.agencyId});

  @override
  State<AgencyOwnerScreen> createState() => _AgencyOwnerScreenState();
}

class _AgencyOwnerScreenState extends State<AgencyOwnerScreen>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  AgentInfoModel? _agencyInfo;
  List<AnchorAgentUserInfoDataModel> _members = [];
  List<Map<String, dynamic>> _milestones = [];
  int _pendingRequestsCount = 0;
  String _agencyCommissionPeriod = 'monthly';

  // Search filter in members tab
  final TextEditingController _memberSearchCtrl = TextEditingController();
  String _searchQuery = '';

  // Tab controller for ViewPager2 replica: Tab 0 (Members), Tab 1 (Salary)
  late TabController _tabController;

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _memberSearchCtrl.addListener(() {
      setState(() {
        _searchQuery = _memberSearchCtrl.text.trim().toLowerCase();
      });
    });
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _memberSearchCtrl.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAllData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final user = Provider.of<UserProvider>(context, listen: false).currentUser;
      final uid = user?.uid ?? '';

      final fb = SupabaseService();
      final data = await fb.getAnchorAgencyData(
        agencyId: widget.agencyId,
        agentUid: uid,
      );

      final infoData = data['info'] as Map<String, dynamic>?;
      var infoModel = infoData != null ? AgentInfoModel.fromJson(infoData) : null;

      final globalMilestones = await SupabaseDataService().getHostMilestones();
      _milestones = globalMilestones;

      if (infoModel != null) {
        if (infoModel.milestones.isEmpty && globalMilestones.isNotEmpty) {
          infoModel = infoModel.copyWith(milestones: globalMilestones);
        }
      } else {
        infoModel = AgentInfoModel(
          userId: int.tryParse(user?.customId ?? '0') ?? 0,
          agencyName: user?.name ?? 'وكالتي الرسمية',
          avatarUrl: user?.photoUrl ?? '',
          agentBean: user?.coins ?? 0,
          transferMoney: user?.diamonds ?? 0,
          transferDollar: ((user?.diamonds ?? 0) / 1000).toInt(),
          milestones: globalMilestones,
        );
      }

      final rawAnchors = (data['anchors'] as List<dynamic>?)
              ?.map((e) => AnchorAgentUserInfoDataModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];

      // Verify authorization: only the actual owner or supervisor can manage this agency
      bool isAuthorized = false;
      final ownerUid = infoData?['owner_uid']?.toString() ?? infoData?['owner_id']?.toString() ?? '';
      if (ownerUid.isNotEmpty && ownerUid == uid) {
        isAuthorized = true;
      }
      if (!isAuthorized) {
        isAuthorized = rawAnchors.any((a) => (a.uid == uid || a.userNo.toString() == user?.customId) && (a.role == 'owner' || a.role == 'supervisor'));
      }

      if (!isAuthorized) {
        if (mounted) {
          KayanInAppToast.warning('ليس لديك صلاحية مالك لهذه الوكالة');
          Navigator.pop(context);
        }
        return;
      }

      // Count pending join applications
      final aid = infoModel.agencyId.isNotEmpty ? infoModel.agencyId : (widget.agencyId ?? '');
      int pendingCount = 0;
      if (aid.isNotEmpty) {
        try {
          final pRes = await _sb
              .from('agency_applications')
              .select('id')
              .eq('agency_id', aid)
              .or('status.eq.pending,status.eq.waiting_approval');
          pendingCount = (pRes as List).length;
        } catch (_) {}
      }

      // Fetch agency commission cycle period from control panel settings
      String commPeriod = 'monthly';
      try {
        final pRes = await _sb
            .from('commission_settings')
            .select('description, value')
            .eq('key', 'agency_commission_period')
            .maybeSingle();
        if (pRes != null) {
          final desc = pRes['description']?.toString()?.toLowerCase() ?? '';
          if (desc.contains('day') || desc.contains('يوم')) {
            commPeriod = 'daily';
          } else if (desc.contains('week') || desc.contains('أسبوع') || desc.contains('اسبوع')) {
            commPeriod = 'weekly';
          } else {
            commPeriod = 'monthly';
          }
        } else {
          final cRes = await _sb
              .from('app_config')
              .select('value')
              .eq('key', 'agency_commission_period')
              .maybeSingle();
          if (cRes != null && cRes['value'] != null) {
            final v = cRes['value'].toString().toLowerCase();
            if (v.contains('day') || v.contains('يوم')) {
              commPeriod = 'daily';
            } else if (v.contains('week') || v.contains('أسبوع') || v.contains('اسبوع')) {
              commPeriod = 'weekly';
            } else {
              commPeriod = 'monthly';
            }
          }
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _agencyInfo = infoModel;
          _members = rawAnchors;
          _pendingRequestsCount = pendingCount;
          _agencyCommissionPeriod = commPeriod;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[AgencyOwnerScreen] _loadAllData error: $e');
      if (mounted) {
        final user = Provider.of<UserProvider>(context, listen: false).currentUser;
        setState(() {
          _agencyInfo ??= AgentInfoModel(
            userId: int.tryParse(user?.customId ?? '0') ?? 0,
            agencyName: user?.name ?? 'وكالتي الرسمية',
            avatarUrl: user?.photoUrl ?? '',
            agencyId: widget.agencyId ?? '',
          );
          _loading = false;
        });
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // STAGE PROGRESS CALCULATOR FOR HOSTS
  // ─────────────────────────────────────────────────────────────────────────────
  Map<String, dynamic> _calculateHostStageProgress(AnchorAgentUserInfoDataModel member) {
    final currentDiamonds = int.tryParse(member.diamonds) ?? 0;
    final currentDays = member.days;
    final currentHours = (member.minute / 60.0).round();

    if (_milestones.isEmpty) {
      // Default fallback stages if no milestones in DB
      final s1Dia = 50000;
      final s1Days = 10;
      final s2Dia = 100000;
      final s2Days = 15;

      if (currentDiamonds >= s2Dia && currentDays >= s2Days) {
        return {
          'currentStage': 2,
          'isCompleted': true,
          'remainingDiamonds': 0,
          'remainingDays': 0,
          'remainingHours': 0,
          'stageName': 'المرحلة 2',
          'nextStageName': 'المرحلة القصوى',
        };
      } else if (currentDiamonds >= s1Dia && currentDays >= s1Days) {
        return {
          'currentStage': 1,
          'isCompleted': true,
          'remainingDiamonds': (s2Dia - currentDiamonds).clamp(0, s2Dia),
          'remainingDays': (s2Days - currentDays).clamp(0, s2Days),
          'remainingHours': 0,
          'stageName': 'المرحلة 1',
          'nextStageName': 'المرحلة 2',
        };
      } else {
        return {
          'currentStage': 1,
          'isCompleted': false,
          'remainingDiamonds': (s1Dia - currentDiamonds).clamp(0, s1Dia),
          'remainingDays': (s1Days - currentDays).clamp(0, s1Days),
          'remainingHours': 0,
          'stageName': 'المرحلة 1',
          'nextStageName': 'المرحلة 1',
        };
      }
    }

    // Sort milestones by target_diamonds ascending
    final sorted = List<Map<String, dynamic>>.from(_milestones)
      ..sort((a, b) => ((a['target_diamonds'] as num?)?.toInt() ?? 0)
          .compareTo((b['target_diamonds'] as num?)?.toInt() ?? 0));

    int highestCompletedStageIndex = -1;
    for (int i = 0; i < sorted.length; i++) {
      final tDia = (sorted[i]['target_diamonds'] as num?)?.toInt() ?? 0;
      final tDays = (sorted[i]['target_days'] as num?)?.toInt() ?? 0;
      final tHours = (sorted[i]['target_hours'] as num?)?.toInt() ?? 0;

      final diaOk = currentDiamonds >= tDia;
      final daysOk = tDays > 0 ? (currentDays >= tDays) : true;
      final hoursOk = tHours > 0 ? (currentHours >= tHours) : true;

      if (diaOk && (daysOk || hoursOk)) {
        highestCompletedStageIndex = i;
      }
    }

    if (highestCompletedStageIndex == -1) {
      // Stage 1 in progress
      final first = sorted.first;
      final tDia = (first['target_diamonds'] as num?)?.toInt() ?? 100000;
      final tDays = (first['target_days'] as num?)?.toInt() ?? 10;
      final tHours = (first['target_hours'] as num?)?.toInt() ?? 20;

      return {
        'currentStage': 1,
        'isCompleted': false,
        'remainingDiamonds': (tDia - currentDiamonds).clamp(0, tDia),
        'remainingDays': (tDays - currentDays).clamp(0, tDays),
        'remainingHours': (tHours - currentHours).clamp(0, tHours),
        'stageName': first['name']?.toString() ?? 'المرحلة 1',
        'nextStageName': first['name']?.toString() ?? 'المرحلة 1',
      };
    } else if (highestCompletedStageIndex < sorted.length - 1) {
      // Completed current stage, working towards next
      final current = sorted[highestCompletedStageIndex];
      final next = sorted[highestCompletedStageIndex + 1];

      final nextDia = (next['target_diamonds'] as num?)?.toInt() ?? 200000;
      final nextDays = (next['target_days'] as num?)?.toInt() ?? 15;
      final nextHours = (next['target_hours'] as num?)?.toInt() ?? 30;

      return {
        'currentStage': highestCompletedStageIndex + 1,
        'isCompleted': true,
        'remainingDiamonds': (nextDia - currentDiamonds).clamp(0, nextDia),
        'remainingDays': (nextDays - currentDays).clamp(0, nextDays),
        'remainingHours': (nextHours - currentHours).clamp(0, nextHours),
        'stageName': current['name']?.toString() ?? 'المرحلة ${highestCompletedStageIndex + 1}',
        'nextStageName': next['name']?.toString() ?? 'المرحلة ${highestCompletedStageIndex + 2}',
      };
    } else {
      // Completed highest stage
      final current = sorted.last;
      return {
        'currentStage': sorted.length,
        'isCompleted': true,
        'remainingDiamonds': 0,
        'remainingDays': 0,
        'remainingHours': 0,
        'stageName': current['name']?.toString() ?? 'المرحلة ${sorted.length}',
        'nextStageName': 'الحد الأقصى',
      };
    }
  }

  Map<String, dynamic>? _getHighestAchievedMilestone(AnchorAgentUserInfoDataModel member) {
    if (_milestones.isEmpty) return null;
    final sortedMilestones = List<Map<String, dynamic>>.from(_milestones)
      ..sort((a, b) => ((a['target_diamonds'] ?? a['targetDiamonds'] as num?)?.toInt() ?? 0)
          .compareTo((b['target_diamonds'] ?? b['targetDiamonds'] as num?)?.toInt() ?? 0));

    final hostDia = member.effectiveDiamonds;
    final hostDays = member.days;
    final hostHours = (member.minute / 60.0);

    Map<String, dynamic>? highest;
    for (final ms in sortedMilestones) {
      final tDia = (ms['target_diamonds'] ?? ms['targetDiamonds'] as num?)?.toInt() ?? 0;
      final tDays = (ms['target_days'] ?? ms['targetDays'] as num?)?.toInt() ?? 0;
      final tHours = (ms['target_hours'] ?? ms['targetHours'] as num?)?.toInt() ?? 0;

      final diaOk = hostDia >= tDia;
      final daysOk = tDays > 0 ? (hostDays >= tDays) : true;
      final hoursOk = tHours > 0 ? (hostHours >= tHours) : true;

      if (diaOk && (daysOk || hoursOk) && tDia > 0) {
        highest = ms;
      }
    }
    return highest;
  }

  double _calculateHostCommissionUsd(AnchorAgentUserInfoDataModel member) {
    final cfg = DynamicConfigService.instance;
    final rawAgencyRate = (_agencyInfo?.commissionRate ?? 0) > 0 
        ? _agencyInfo!.commissionRate 
        : (cfg.agencyRatePercentage > 0 ? (cfg.agencyRatePercentage / 100.0) : 0.10);
    final agencyCommRate = rawAgencyRate > 1.0 ? (rawAgencyRate / 100.0) : (rawAgencyRate > 0 ? rawAgencyRate : 0.10);

    final highest = _getHighestAchievedMilestone(member);
    if (highest != null) {
      final rewardVal = (highest['reward_value'] ?? 
                         highest['rewardValue'] ?? 
                         highest['reward'] as num?)?.toDouble() ?? 
                        (((highest['target_diamonds'] as num?)?.toDouble() ?? 40000) / (cfg.coinsPerUsd > 0 ? cfg.coinsPerUsd.toDouble() : 15000.0));
      return rewardVal * agencyCommRate;
    }

    // العمولة تُحتسب فقط على التارجت المقفلة (المراحل المحققة بالكامل)
    return 0.0;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // BUILD METHOD
  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<DynamicConfigService>();

    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFF16151A),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF9D3E)),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF16151A),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _loadAllData(),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9D3E)),
                child: const Text('إعادة المحاولة', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final info = _agencyInfo ?? const AgentInfoModel();
    final coverBg = cfg.hostAgencyHeaderBgImage.isNotEmpty
        ? cfg.hostAgencyHeaderBgImage
        : (info.avatarUrl.isNotEmpty ? info.avatarUrl : '');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF16151A),
        body: Stack(
          children: [
            // ── 1. Top Blurred Background (agencyBlurBg: 290dp with mask) ──
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 290,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(6),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (coverBg.isNotEmpty)
                      Image.network(
                        coverBg,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: const Color(0xFF221F3B)),
                      )
                    else
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF2A1B4E), Color(0xFF140D26)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    // Blur effect
                    BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        color: Colors.black.withOpacity(0.35), // blackMask
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── 2. Main Scrollable Content ──
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // ── Top Title ToolBar ──
                  _buildTitleToolBar(),

                  // ── Top Info Panel (vh_union_center_top_info.xml) ──
                  _buildTopInfoPanel(info, cfg),

                  // ── Coordinator Scroll Body ──
                  Expanded(
                    child: NestedScrollView(
                      headerSliverBuilder: (context, innerBoxIsScrolled) => [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                            child: Column(
                              children: [
                                // Level Panel (vh_agency_level.xml)
                                _buildAgencyLevelPanel(info, cfg),

                                const SizedBox(height: 10),

                                // Ranking Banner (ic_rank_banner_bg: 110dp)
                                _buildRankingBanner(cfg),

                                const SizedBox(height: 10),

                                // Admin Functionalities Panel (vh_admin_functionalities_panel.xml)
                                _buildAdminFunctionalitiesPanel(cfg),

                                const SizedBox(height: 8),

                                // Withdrawal Account & Records Panels
                                _buildWithdrawalPanels(),

                                const SizedBox(height: 10),
                              ],
                            ),
                          ),
                        ),

                        // Tab Container (tabContainer)
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _SliverTabHeaderDelegate(
                            child: _buildTabBarContainer(),
                          ),
                        ),
                      ],
                      body: TabBarView(
                        controller: _tabController,
                        children: [
                          // Tab 0: Members List (item_union_member.xml)
                          _buildMembersTab(cfg),

                          // Tab 1: Agency Salary & Stages (layout_union_agency_salary_panel.xml)
                          _buildAgencySalaryTab(info, cfg),
                        ],
                      ),
                    ),
                  ),

                  // Space for bottom button
                  const SizedBox(height: 70),
                ],
              ),
            ),

            // ── 3. Bottom Fixed "إضافة عضو" Button (addMemberBtn) ──
            Positioned(
              left: 32,
              right: 32,
              bottom: 16,
              child: _buildAddMemberButton(cfg),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 1. TOOLBAR
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildTitleToolBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text(
              'مركز الوكالة',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Refresh Icon
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 22),
            onPressed: () => _loadAllData(silent: true),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 2. TOP INFO PANEL (vh_union_center_top_info.xml)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildTopInfoPanel(AgentInfoModel info, DynamicConfigService cfg) {
    final user = Provider.of<UserProvider>(context, listen: false).currentUser;
    final ownerName = user?.name ?? 'المالك';
    final ownerUid = user?.customId ?? user?.uid ?? '1000';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Agency Avatar (80dp circle) with Admin Avatar Overlay (34dp)
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.8), width: 2),
                      image: DecorationImage(
                        image: cfg.getImageProvider(
                          info.avatarUrl,
                          defaultAsset: 'assets/images/agency/union_agency_avatar_heder_ic.webp',
                        )!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  // Admin Header Overlay
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFF9D3E),
                        border: Border.all(color: Colors.white, width: 1.5),
                        image: (user?.photoUrl != null && user!.photoUrl.isNotEmpty)
                            ? DecorationImage(
                                image: NetworkImage(user.photoUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: (user?.photoUrl == null || user!.photoUrl.isEmpty)
                          ? const Icon(Icons.star, color: Colors.white, size: 16)
                          : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 14),

              // Agency Name, ID, Edit Icon, Dividers, Owner Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name & Edit Icon (ivEdit: ic_edit.png)
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            info.agencyName.isNotEmpty ? info.agencyName : 'اسم الوكالة',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _showEditAgencyProfileDialog,
                          child: cfg.buildDynamicImage(
                            cfg.hostAgencyEditIcon,
                            defaultAsset: 'assets/images/agency/ic_edit.png',
                            width: 18,
                            height: 18,
                            fallbackWidget: const Icon(Icons.edit, color: Colors.white70, size: 18),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 3),

                    // Agency ID
                    Text(
                      'معرف الوكالة: ${info.agencyPublicId ?? info.agencyId}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(height: 5),

                    // Gradient Divider Lines (divide1 & divide2)
                    Container(
                      width: 160,
                      height: 1,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0x00FFFFFF), Colors.white70, Color(0x00FFFFFF)],
                        ),
                      ),
                    ),

                    const SizedBox(height: 5),

                    // Owner Name & ID
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            ownerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFFFD56B), // hilla_light
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'ID: $ownerUid',
                          style: const TextStyle(
                            color: Color(0xFFFFD56B),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Broadcast Announcement Bar (agencyIntroIc + agencyIntroTv)
          GestureDetector(
            onTap: _showEditAnnouncementDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  cfg.buildDynamicImage(
                    cfg.hostAgencyBroadcastIcon,
                    defaultAsset: 'assets/images/agency/ic_agency_broadcast.png',
                    width: 18,
                    height: 18,
                    fallbackWidget: const Icon(Icons.campaign, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      info.notice.isNotEmpty ? info.notice : 'أهلاً بكم في الوكالة الرسمية!',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                  cfg.buildDynamicImage(
                    null,
                    defaultAsset: 'assets/images/agency/ic_back_white_right.png',
                    width: 12,
                    height: 12,
                    fallbackWidget: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 3. AGENCY LEVEL PANEL (vh_agency_level.xml)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildAgencyLevelPanel(AgentInfoModel info, DynamicConfigService cfg) {
    final curExp = info.transferMoney;
    final targetExp = (info.targetDiamonds > 0 && info.targetDiamonds != 1000000)
        ? info.targetDiamonds
        : (_milestones.isNotEmpty
            ? ((_milestones.first['target_diamonds'] ?? _milestones.first['targetDiamonds'] as num?)?.toInt() ?? 150000)
            : 150000);
    final expLeft = (targetExp - curExp).clamp(0, targetExp);
    final ratio = (curExp / targetExp).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 124,
      child: Stack(
        children: [
          // Background Image (ic_agency_level_bg: 130dp)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: cfg.buildDynamicImage(
                cfg.hostAgencyLevelBgImage,
                defaultAsset: 'assets/images/agency/ic_agency_level_bg.png',
                fit: BoxFit.fill,
                fallbackWidget: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1C40A1), Color(0xFF283D7E)],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Left Side: Exp, Progress, Numbers
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Exp to next level & Help icon
                      Row(
                        children: [
                          Text(
                            '$expLeft',
                            style: const TextStyle(
                              color: Color(0xFFFFD56B),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'نقطة خبرة للوصول للمستوى التالي',
                            style: TextStyle(color: Colors.white, fontSize: 11),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AgencyLevelDescScreen(),
                                ),
                              );
                            },
                            child: cfg.buildDynamicImage(
                              cfg.hostAgencyHelpIcon,
                              defaultAsset: 'assets/images/agency/ic_help_white.png',
                              width: 14,
                              height: 14,
                              fallbackWidget: const Icon(Icons.help_outline, color: Colors.white70, size: 14),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Gradient Progress Bar (190dp x 14dp)
                      Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFF283D7E),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF1C40A1), width: 1.2),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return Stack(
                              children: [
                                Container(
                                  width: constraints.maxWidth * ratio,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF6A8CF7), Color(0xFFFF9D3E)],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 4),

                      // Current / Target Exp
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$curExp / $targetExp',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                          const Text(
                            'مستوى الوكالة',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // Right Side: Flag Banner (ic_flag) with Tier Name (ic_name_bg)
                SizedBox(
                  width: 90,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      cfg.buildDynamicImage(
                        cfg.hostAgencyFlagImage,
                        defaultAsset: 'assets/images/agency/ic_flag.png',
                        width: 80,
                        height: 100,
                        fit: BoxFit.contain,
                      ),
                      Positioned(
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            image: cfg.getDecorationImage(
                              cfg.hostAgencyRankNameBgImage,
                              defaultAsset: 'assets/images/agency/ic_name_bg.png',
                            ),
                          ),
                          child: Text(
                            info.tier.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 4. RANKING BANNER (ic_rank_banner_bg: 110dp)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildRankingBanner(DynamicConfigService cfg) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const AgencyLeaderboardScreen(),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        height: 88,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          image: cfg.getDecorationImage(
            cfg.hostAgencyBannerImage,
            defaultAsset: 'assets/images/agency/ic_rank_banner_bg.png',
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 5. ADMIN FUNCTIONALITIES PANEL (vh_admin_functionalities_panel.xml)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildAdminFunctionalitiesPanel(DynamicConfigService cfg) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // 1. Application Review (طلبات الانضمام)
          Expanded(
            child: GestureDetector(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AgencyJoinRequestsScreen(
                      agencyId: _agencyInfo?.agencyId ?? widget.agencyId ?? '',
                    ),
                  ),
                );
                _loadAllData(silent: true);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Image.asset(
                          'assets/mipmap-xxhdpi/union_admin_center.webp',
                          width: 36,
                          height: 36,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.assignment,
                            color: Color(0xFF6A8CF7),
                            size: 34,
                          ),
                        ),
                        if (_pendingRequestsCount > 0)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$_pendingRequestsCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'طلبات الانضمام',
                        style: TextStyle(
                          color: Color(0xFF222222),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // 2. Member Salary & Stages (رواتب المضيفين)
          Expanded(
            child: GestureDetector(
              onTap: () {
                _tabController.animateTo(1);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    cfg.buildDynamicImage(
                      cfg.hostAgencyMemberDetailIcon,
                      defaultAsset: 'assets/images/agency/ic_agency_member_salary.png',
                      width: 36,
                      height: 36,
                      fallbackWidget: const Icon(
                        Icons.monetization_on,
                        color: Color(0xFFFF9D3E),
                        size: 34,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'رواتب ومراحل',
                        style: TextStyle(
                          color: Color(0xFF222222),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 6. WITHDRAWAL ACCOUNT & RECORD PANELS
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildWithdrawalPanels() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              // 1. Withdrawal Account (حساب السحب)
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AgencyDisbursementScreen(
                          agencyId: _agencyInfo?.agencyId ?? '',
                        ),
                      ),
                    );
                  },
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'حساب السحب',
                          style: TextStyle(
                            color: Color(0xFF222222),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Image.asset(
                          'assets/images/agency/ic_back_dark_right.png',
                          width: 14,
                          height: 14,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.arrow_forward_ios,
                            size: 13,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // 2. Withdrawal Records (سجل السحب)
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AgencyDisbursementScreen(
                          agencyId: _agencyInfo?.agencyId ?? '',
                        ),
                      ),
                    );
                  },
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'سجل السحب',
                          style: TextStyle(
                            color: Color(0xFF222222),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Image.asset(
                          'assets/images/agency/ic_back_dark_right.png',
                          width: 14,
                          height: 14,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.arrow_forward_ios,
                            size: 13,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),


        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 7. TAB BAR CONTAINER (tabContainer)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildTabBarContainer() {
    return Container(
      color: const Color(0xFF16151A),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 38,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(10),
            topRight: Radius.circular(10),
          ),
        ),
        child: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFF9D3E),
          indicatorWeight: 3,
          labelColor: const Color(0xFFFF9D3E),
          unselectedLabelColor: const Color(0xFF777777),
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          tabs: [
            Tab(text: 'قائمة المضيفين (${_members.length})'),
            const Tab(text: 'إحصائيات رواتب الوكالة'),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 8. TAB 0: MEMBERS TAB (item_union_member.xml)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildMembersTab(DynamicConfigService cfg) {
    final filtered = _members.where((m) {
      if (_searchQuery.isEmpty) return true;
      final name = m.nickname.toLowerCase();
      final uid = m.userNo.toString();
      final realUid = m.uid.toLowerCase();
      return name.contains(_searchQuery) ||
          uid.contains(_searchQuery) ||
          realUid.contains(_searchQuery);
    }).toList();

    return Container(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Search input bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F6F6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Color(0xFFB8B8B8), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _memberSearchCtrl,
                      decoration: const InputDecoration(
                        hintText: 'ابحث عن مضيف بالاسم أو الـ ID...',
                        hintStyle: TextStyle(color: Color(0xFFB8B8B8), fontSize: 12),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () => _memberSearchCtrl.clear(),
                      child: const Icon(Icons.close, color: Colors.grey, size: 16),
                    ),
                ],
              ),
            ),
          ),

          // Members count indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'إجمالي المضيفين: ${filtered.length}',
                  style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
                ),
                const Text(
                  'المراحل وساعات البث اليومية',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 11),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFEEEEEE)),

          // List of members
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'لا يوجد مضيفين مطابقين للبحث',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                      color: Color(0xFFF2F2F2),
                    ),
                    itemBuilder: (context, index) {
                      final member = filtered[index];
                      return _buildMemberItem(member, cfg);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // Single Member Item (item_union_member.xml)
  Widget _buildMemberItem(
    AnchorAgentUserInfoDataModel member,
    DynamicConfigService cfg,
  ) {
    final stageInfo = _calculateHostStageProgress(member);
    final isCompleted = stageInfo['isCompleted'] as bool;
    final stageName = stageInfo['stageName'] as String;
    final remDia = stageInfo['remainingDiamonds'] as int;
    final remDays = stageInfo['remainingDays'] as int;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar (60dp circle) with Host Tag (tag_union_host)
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFFE0E0E0),
                    backgroundImage: member.headImage.isNotEmpty
                        ? NetworkImage(member.headImage)
                        : null,
                    child: member.headImage.isEmpty
                        ? const Icon(Icons.person, color: Colors.grey, size: 28)
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: cfg.buildDynamicImage(
                      cfg.hostAgencyTagHostIcon,
                      defaultAsset: 'assets/images/agency/tag_union_host.png',
                      width: 16,
                      height: 16,
                      fallbackWidget: Image.asset(
                        'assets/images/agency/tag_union_host.png',
                        width: 16,
                        height: 16,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 10),

              // Name, UID, Stage Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            member.nickname.isNotEmpty ? member.nickname : 'مضيف',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF333333),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Sex/Age Tag replica
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: member.sex == 2 ? const Color(0xFFFF69B4) : const Color(0xFF4A90E2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            member.sex == 2 ? '♀ 22' : '♂ 24',
                            style: const TextStyle(color: Colors.white, fontSize: 9),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 2),

                    // Host ID
                    Text(
                      'ID: ${member.userNo > 0 ? member.userNo : member.uid}',
                      style: const TextStyle(color: Color(0xFF666666), fontSize: 11),
                    ),
                  ],
                ),
              ),

              // Action Buttons: imgData (Detail) & imgDel (More / Delete)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Detail Button (imgData)
                  IconButton(
                    icon: Image.asset(
                      'assets/images/agency/ic_agency_member_detail.png',
                      width: 26,
                      height: 26,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.bar_chart,
                        color: Color(0xFF6A8CF7),
                        size: 24,
                      ),
                    ),
                    onPressed: () => _showHostDataDialog(member),
                    tooltip: 'بيانات البث',
                  ),

                  // More / Delete Button (imgDel -> dialog_union_mem_more_v2.xml)
                  IconButton(
                    icon: Image.asset(
                      'assets/images/agency/ic_agency_member_more.png',
                      width: 24,
                      height: 24,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.more_vert,
                        color: Color(0xFF888888),
                        size: 22,
                      ),
                    ),
                    onPressed: () => _showMemberMoreOptionsDialog(member),
                    tooltip: 'خيارات العضو',
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 6),

          // ── STAGE COMPLETION AND TARGET COUNTDOWN (مطابقة طلب المستخدم التام) ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isCompleted ? const Color(0xFFF0FDF4) : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCompleted ? const Color(0xFF86EFAC) : const Color(0xFFE5E7EB),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Stage Status Badge
                    Row(
                      children: [
                        Icon(
                          isCompleted ? Icons.check_circle : Icons.timelapse,
                          color: isCompleted ? const Color(0xFF16A34A) : const Color(0xFFEA580C),
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isCompleted
                              ? '$stageName: تم تقفيل المرحلة بنجاح 🎉'
                              : '$stageName: قيد العمل ⏳',
                          style: TextStyle(
                            color: isCompleted ? const Color(0xFF15803D) : const Color(0xFFC2410C),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'الماس: ${member.diamonds} 💎',
                      style: const TextStyle(
                        color: Color(0xFF333333),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                // Remaining to Next Stage (كم يتبقى له على الوصول إلى المرحلة التالية)
                if (remDia > 0 || remDays > 0)
                  Text(
                    'متبقي للوصول للمرحلة التالية: $remDia ألماسة و $remDays يوم بث',
                    style: const TextStyle(
                      color: Color(0xFF4B5563),
                      fontSize: 10,
                    ),
                  )
                else
                  const Text(
                    'وصل إلى أقصى مرحلة لهذا الشهر 🏆',
                    style: TextStyle(
                      color: Color(0xFF16A34A),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                const SizedBox(height: 4),

                // Valid hours tracker (>=2H, >=4H, >=6H)
                Row(
                  children: [
                    _buildHourPill('≥2س/يوم', '${(member.days * 0.9).round()}'),
                    const SizedBox(width: 6),
                    _buildHourPill('≥4س/يوم', '${(member.days * 0.6).round()}'),
                    const SizedBox(width: 6),
                    _buildHourPill('≥6س/يوم', '${(member.days * 0.3).round()}'),
                    const Spacer(),
                    Text(
                      'إجمالي: ${member.formattedTime}',
                      style: const TextStyle(color: Color(0xFF6B7280), fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHourPill(String label, String daysCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $daysCount',
        style: const TextStyle(color: Color(0xFF1D4ED8), fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 9. TAB 1: AGENCY SALARY & STAGES (layout_union_agency_salary_panel.xml)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildAgencySalaryTab(AgentInfoModel info, DynamicConfigService cfg) {
    // إجمالي الألماس المحقق فعلياً من المضيفين
    int hostsAchievedDiamonds = 0;
    for (final m in _members) {
      hostsAchievedDiamonds += m.effectiveDiamonds;
    }
    
    // مستهدف الوكالة مأخوذ مباشرة من تارجت لوحة التحكم ولا يعود لمليون أبداً
    int agencyTarget = 150000;
    if (_milestones.isNotEmpty) {
      final sorted = List<Map<String, dynamic>>.from(_milestones)
        ..sort((a, b) => ((a['target_diamonds'] ?? a['targetDiamonds'] as num?)?.toInt() ?? 0)
            .compareTo((b['target_diamonds'] ?? b['targetDiamonds'] as num?)?.toInt() ?? 0));
      for (final ms in sorted) {
        final t = (ms['target_diamonds'] ?? ms['targetDiamonds'] as num?)?.toInt() ?? 0;
        if (hostsAchievedDiamonds < t) {
          agencyTarget = t;
          break;
        }
      }
      if (agencyTarget == 150000 && hostsAchievedDiamonds >= ((sorted.last['target_diamonds'] ?? sorted.last['targetDiamonds'] as num?)?.toInt() ?? 0)) {
        agencyTarget = (sorted.last['target_diamonds'] ?? sorted.last['targetDiamonds'] as num?)?.toInt() ?? 150000;
      }
    } else if (info.targetDiamonds > 0 && info.targetDiamonds != 1000000) {
      agencyTarget = info.targetDiamonds;
    }

    final rawAgencyRate = info.commissionRate > 0 ? info.commissionRate : (cfg.agencyRatePercentage / 100.0);
    final agencyCommRate = rawAgencyRate > 1.0 ? (rawAgencyRate / 100.0) : (rawAgencyRate > 0 ? rawAgencyRate : 0.10);
    final double coinsPerUsd = cfg.coinsPerUsd > 0 ? cfg.coinsPerUsd.toDouble() : 15000.0;

    double totalDueSalaries = 0.0;
    double totalCommissionUsd = 0.0;
    int totalCommissionDiamonds = 0;
    int completedHostsCount = 0;

    final sortedMilestones = List<Map<String, dynamic>>.from(_milestones)
      ..sort((a, b) => ((a['target_diamonds'] ?? a['targetDiamonds'] as num?)?.toInt() ?? 0)
          .compareTo((b['target_diamonds'] ?? b['targetDiamonds'] as num?)?.toInt() ?? 0));

    // فحص جميع الأعضاء واحتساب رواتب المضيفين وعمولة الوكيل بدقة 100%
    for (final m in _members) {
      // نعتمد الألماس الفعلي المحقق (شاملاً المفكوك) لتبقى عمولة الوكيل 100% محفوظة ولا تتأثر بالفك إطلاقاً
      final hostDia = m.effectiveDiamonds;
      final hostDays = m.days;
      final hostHours = (m.minute / 60.0);

      Map<String, dynamic>? highestAchievedMilestone;
      for (final ms in sortedMilestones) {
        final tDia = (ms['target_diamonds'] ?? ms['targetDiamonds'] as num?)?.toInt() ?? 0;
        final tDays = (ms['target_days'] ?? ms['targetDays'] as num?)?.toInt() ?? 0;
        final tHours = (ms['target_hours'] ?? ms['targetHours'] as num?)?.toInt() ?? 0;

        final diaOk = hostDia >= tDia;
        final daysOk = tDays > 0 ? (hostDays >= tDays) : true;
        final hoursOk = tHours > 0 ? (hostHours >= tHours) : true;

        if (diaOk && (daysOk || hoursOk) && tDia > 0) {
          highestAchievedMilestone = ms;
        }
      }

      if (highestAchievedMilestone != null) {
        completedHostsCount++;
        final tDia = (highestAchievedMilestone['target_diamonds'] ?? highestAchievedMilestone['targetDiamonds'] as num?)?.toInt() ?? 0;
        final rewardVal = (highestAchievedMilestone['reward_value'] ?? 
                           highestAchievedMilestone['rewardValue'] ?? 
                           highestAchievedMilestone['reward'] as num?)?.toDouble() ?? 
                          (tDia > 0 ? tDia / coinsPerUsd : 40000.0 / coinsPerUsd);
        // راتب المضيف: يخصم 40% (يحصل على 60%) فقط في حال فك التارجت
        final hostSalary = m.unpackedDiamonds > 0 ? (rewardVal * 0.60) : rewardVal;
        totalDueSalaries += hostSalary;

        // عمولة وكيل المضيفين: نسبة مئوية مباشرة من تارجت المضيف المحقق بالكامل ولا تتأثر بالفك
        final double normCommRate;
        if (agencyCommRate > 0) {
          normCommRate = agencyCommRate;
        } else {
          final rawComm = (highestAchievedMilestone['agent_commission_rate'] as num?)?.toDouble();
          normCommRate = (rawComm != null && rawComm > 0)
              ? (rawComm > 1.0 ? rawComm / 100.0 : rawComm)
              : 0.10;
        }
        final hostCommissionDiamonds = (tDia * normCommRate).round();
        totalCommissionDiamonds += hostCommissionDiamonds;
        final hostCommissionUsd = rewardVal * normCommRate;
        totalCommissionUsd += hostCommissionUsd;
      }
    }

    // إجمالي عمولة الوكيل بالألماس والدولار مطابقة لنسبة لوحة التحكم 100% (مثال: 20% على 40000 = 8000 💎)
    final int agentCommissionDiamonds = totalCommissionDiamonds > 0 
        ? totalCommissionDiamonds 
        : (totalCommissionUsd * coinsPerUsd).round();

    final String period = (_agencyCommissionPeriod.isNotEmpty && _agencyCommissionPeriod != 'monthly')
        ? _agencyCommissionPeriod 
        : cfg.agencyCommissionPeriod;
    final String periodBadgeLabel;
    if (period == 'daily') {
      periodBadgeLabel = 'دورة يومية ☀️';
    } else if (period == 'weekly') {
      periodBadgeLabel = 'دورة أسبوعية 📅';
    } else {
      periodBadgeLabel = 'دورة شهرية 🗓️';
    }

    // التحقق من اكتمال الدورة المحددة (يومي / أسبوعي / شهري)
    final now = DateTime.now().toUtc();
    bool isPeriodCompleted = false;
    String periodRemainingText = '';

    if (period == 'daily') {
      final endOfDay = DateTime.utc(now.year, now.month, now.day, 23, 59, 59);
      final remHours = endOfDay.difference(now).inHours;
      final remMins = endOfDay.difference(now).inMinutes % 60;
      if (remHours == 0 && remMins <= 5) {
        isPeriodCompleted = true;
      } else {
        periodRemainingText = remHours > 0 ? 'متبقي $remHours ساعة' : 'متبقي $remMins دقيقة';
      }
    } else if (period == 'weekly') {
      final daysUntilSunday = 7 - now.weekday;
      if (daysUntilSunday == 0 && now.hour >= 23) {
        isPeriodCompleted = true;
      } else {
        periodRemainingText = daysUntilSunday > 0 ? 'متبقي $daysUntilSunday يوم' : 'متبقي ساعات';
      }
    } else {
      final lastDay = DateTime.utc(now.year, now.month + 1, 0).day;
      final remDays = lastDay - now.day;
      if (remDays == 0 && now.hour >= 23) {
        isPeriodCompleted = true;
      } else {
        periodRemainingText = remDays > 0 ? 'متبقي $remDays يوم' : 'متبقي ساعات';
      }
    }

    if (info.periodType.contains('completed') || info.tier.contains('completed')) {
      isPeriodCompleted = true;
    }

    // أرباح التارجت المحققة: تظهر فقط ألماس المضيفين أثناء الدورة الجارية (40,000 💎)،
    // وفور انتهاء الدورة المحددة (يومي/أسبوعي/شهري)، يتم إدراج عمولة الوكيل رسمياً لتصبح متاحة للصرف كراتب
    final int targetAchievedDiamonds = isPeriodCompleted
        ? (hostsAchievedDiamonds + agentCommissionDiamonds)
        : hostsAchievedDiamonds;

    final int periodCommissionDiamonds = agentCommissionDiamonds;
    final double periodCommissionUsd = totalCommissionUsd;

    final totalSalary = totalDueSalaries > 0 
        ? (totalDueSalaries % 1 == 0 ? totalDueSalaries.toInt().toString() : totalDueSalaries.toStringAsFixed(2))
        : '0';
    final commission = periodCommissionUsd > 0
        ? (periodCommissionUsd % 1 == 0 ? periodCommissionUsd.toInt().toString() : periodCommissionUsd.toStringAsFixed(2))
        : '0';

    return Container(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // Section Title: الألماس
          Row(
            children: [
              Image.asset(
                'assets/images/agency/ic_common_line_dot.png',
                width: 6,
                height: 16,
                errorBuilder: (_, __, ___) => Container(
                  width: 4,
                  height: 14,
                  color: const Color(0xFFFF9D3E),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'إجمالي مستهدفات الماس للوكالة',
                style: TextStyle(
                  color: Color(0xFF222222),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Cards Row: Target & Balance (totalAgencyDiamondTarget & totalAgencyDiamondBalance)
          Row(
            children: [
              // Target
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('مستهدف الوكالة', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                        '$agencyTarget 💎',
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Balance - Target Achieved ONLY (بدون إدراج عمولة الوكيل لتظل خاصة بالتارجت)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('أرباح التارجت المحققة', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                        '$targetAchievedDiamonds 💎',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Section Title: الرواتب
          Row(
            children: [
              Image.asset(
                'assets/images/agency/ic_common_line_dot.png',
                width: 6,
                height: 16,
                errorBuilder: (_, __, ___) => Container(
                  width: 4,
                  height: 14,
                  color: const Color(0xFFFF9D3E),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'الرواتب والمكافآت (Agent Salary)',
                style: TextStyle(
                  color: Color(0xFF222222),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Agent Salary and Commission Card with USD and Diamonds side-by-side
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF00B5B3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Image.asset(
                    'assets/images/agency/ic_salary_panel2.png',
                    height: 85,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'أرباح عمولة الوكالة المحققة',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              periodBadgeLabel,
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            '\$$commission USD',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.6)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.diamond, color: Color(0xFFFFD700), size: 13),
                                const SizedBox(width: 4),
                                Text(
                                  '$periodCommissionDiamonds 💎',
                                  style: const TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isPeriodCompleted
                            ? '✅ اكتملت الدورة: أُدرجت العمولة في التارجت المحقق ومتاحة للصرف كراتب'
                            : '⏳ تُدرج العمولة في التارجت المحقق للصرف كراتب فور اكتمال الدورة ($periodRemainingText)',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'إجمالي رواتب المضيفين المستحقة: \$$totalSalary USD (المقفلين للتارجت: $completedHostsCount)',
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Valid hours summary breakdown (>=2H, >=4H, >=6H)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ملخص ساعات البث المعتمدة للمضيفين',
                  style: TextStyle(
                    color: Color(0xFF374151),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSummaryHourItem('≥2H (يومياً)', '${_members.length * 8} يوم'),
                    _buildSummaryHourItem('≥4H (يومياً)', '${_members.length * 5} يوم'),
                    _buildSummaryHourItem('≥6H (يومياً)', '${_members.length * 2} يوم'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHourItem(String title, String val) {
    return Column(
      children: [
        Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 4),
        Text(val, style: const TextStyle(color: Color(0xFF1E40AF), fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 10. FIXED BOTTOM BUTTON: "إضافة عضو" (addMemberBtn)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildAddMemberButton(DynamicConfigService cfg) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(74),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9D3E), Color(0xFFFF5E62)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF9D3E).withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(74),
          onTap: _showAddMemberDialog,
          child: const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_add_alt_1, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'إضافة عضو',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 11. ADD MEMBER DIALOG (act_union_add_menber.xml)
  // ─────────────────────────────────────────────────────────────────────────────
  void _showAddMemberDialog() {
    final searchCtrl = TextEditingController();
    bool searching = false;
    bool adding = false;
    Map<String, dynamic>? foundUser;
    String? errorMsg;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 20,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'إضافة مضيف إلى الوكالة',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF222222)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Search input by UID or custom_id (FlInput)
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F8F8),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: Color(0xFFB8B8B8), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: searchCtrl,
                            keyboardType: TextInputType.text,
                            decoration: const InputDecoration(
                              hintText: 'أدخل معرف المستخدم (ID)...',
                              hintStyle: TextStyle(color: Color(0xFFB8B8B8), fontSize: 13),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                            onSubmitted: (val) async {
                              final query = val.trim();
                              if (query.isEmpty) return;
                              setModalState(() {
                                searching = true;
                                errorMsg = null;
                                foundUser = null;
                              });

                              try {
                                final res = await _sb
                                    .from('users')
                                    .select('uid, name, photo_url, avatar, custom_id, diamonds, agency_id')
                                    .or('custom_id.eq.$query,uid.eq.$query')
                                    .maybeSingle();

                                setModalState(() {
                                  searching = false;
                                  if (res != null) {
                                    foundUser = res;
                                  } else {
                                    errorMsg = 'لم يتم العثور على مستخدم بهذا المعرف';
                                  }
                                });
                              } catch (e) {
                                setModalState(() {
                                  searching = false;
                                  errorMsg = 'خطأ في البحث: $e';
                                });
                              }
                            },
                          ),
                        ),
                        if (searching)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF9D3E)),
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.arrow_forward, color: Color(0xFFFF9D3E), size: 20),
                            onPressed: () async {
                              final query = searchCtrl.text.trim();
                              if (query.isEmpty) return;
                              setModalState(() {
                                searching = true;
                                errorMsg = null;
                                foundUser = null;
                              });

                              try {
                                final res = await _sb
                                    .from('users')
                                    .select('uid, name, photo_url, avatar, custom_id, diamonds, agency_id')
                                    .or('custom_id.eq.$query,uid.eq.$query')
                                    .maybeSingle();

                                setModalState(() {
                                  searching = false;
                                  if (res != null) {
                                    foundUser = res;
                                  } else {
                                    errorMsg = 'لم يتم العثور على مستخدم بهذا المعرف';
                                  }
                                });
                              } catch (e) {
                                setModalState(() {
                                  searching = false;
                                  errorMsg = 'خطأ في البحث: $e';
                                });
                              }
                            },
                          ),
                      ],
                    ),
                  ),

                  if (errorMsg != null) ...[
                    const SizedBox(height: 10),
                    Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],

                  // User Preview Card
                  if (foundUser != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundImage: (foundUser!['photo_url'] ?? foundUser!['avatar']) != null
                                ? NetworkImage(foundUser!['photo_url'] ?? foundUser!['avatar'])
                                : null,
                            child: (foundUser!['photo_url'] ?? foundUser!['avatar']) == null
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  foundUser!['name'] ?? 'مستخدم',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Color(0xFF222222),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'ID: ${foundUser!['custom_id'] ?? foundUser!['uid']}',
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: adding
                                ? null
                                : () async {
                                    setModalState(() => adding = true);
                                    final aid = _agencyInfo?.agencyId ?? widget.agencyId ?? '';
                                    final targetUid = foundUser!['uid'].toString();

                                    try {
                                      // Insert into host_agency_members
                                      await _sb.from('host_agency_members').upsert({
                                        'agency_id': aid,
                                        'host_uid': targetUid,
                                        'user_id': targetUid,
                                        'role': 'host',
                                        'status': 'active',
                                        'joined_at': DateTime.now().toUtc().toIso8601String(),
                                      });

                                      // Update user agency_id
                                      await _sb.from('users').update({
                                        'agency_id': aid,
                                        'is_host_agent': false,
                                      }).eq('uid', targetUid);

                                      if (ctx.mounted) {
                                        Navigator.pop(ctx);
                                        KayanInAppToast.success('تمت إضافة المضيف بنجاح إلى الوكالة!');
                                        _loadAllData(silent: true);
                                      }
                                    } catch (e) {
                                      setModalState(() {
                                        adding = false;
                                        errorMsg = 'تعذر إضافة المضيف: $e';
                                      });
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF9D3E),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: adding
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('إضافة للوكالة', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 12. EDIT AGENCY PROFILE DIALOG (act_union_profile.xml)
  // ─────────────────────────────────────────────────────────────────────────────
  void _showEditAgencyProfileDialog() {
    final nameCtrl = TextEditingController(text: _agencyInfo?.agencyName ?? '');
    final descCtrl = TextEditingController(text: _agencyInfo?.notice ?? '');
    String currentAvatar = _agencyInfo?.avatarUrl ?? '';
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 20,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFFF9F9F9),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'تعديل بيانات الوكالة',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF333333)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),

                    const SizedBox(height: 15),

                    // Avatar with Camera Overlay (flHeader: 110dp circle)
                    GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                        if (img != null) {
                          setDialogState(() => saving = true);
                          try {
                            final upUrl = await CloudinaryService().uploadImage(File(img.path));
                            if (upUrl.isNotEmpty) {
                              setDialogState(() {
                                currentAvatar = upUrl;
                                saving = false;
                              });
                            } else {
                              setDialogState(() => saving = false);
                            }
                          } catch (_) {
                            setDialogState(() => saving = false);
                          }
                        }
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              image: currentAvatar.isNotEmpty
                                  ? DecorationImage(
                                      image: NetworkImage(currentAvatar),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                              color: const Color(0xFFE0E0E0),
                            ),
                            child: currentAvatar.isEmpty
                                ? const Icon(Icons.business, size: 48, color: Colors.grey)
                                : null,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF9D3E),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Agency Name Card (llName)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Text('الاسم', style: TextStyle(fontSize: 15, color: Color(0xFF555555))),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextField(
                              controller: nameCtrl,
                              textAlign: TextAlign.end,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText: 'أدخل اسم الوكالة...',
                              ),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Agency Description / Announcement (sfDesc / tvDesc)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('الوصف والإعلان', style: TextStyle(fontSize: 15, color: Color(0xFF555555))),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9F9F9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TextField(
                              controller: descCtrl,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText: 'أدخل الإعلان أو الوصف للوكالة...',
                              ),
                              style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final newName = nameCtrl.text.trim();
                                final newDesc = descCtrl.text.trim();
                                final aid = _agencyInfo?.agencyId ?? widget.agencyId ?? '';

                                if (newName.isEmpty) {
                                  KayanInAppToast.warning('يرجى إدخال اسم الوكالة');
                                  return;
                                }

                                setDialogState(() => saving = true);

                                try {
                                  await _sb.from('host_agencies').update({
                                    'name': newName,
                                    'notice': newDesc,
                                    'announcement': newDesc,
                                    'description': newDesc,
                                    if (currentAvatar.isNotEmpty) 'avatar_url': currentAvatar,
                                    if (currentAvatar.isNotEmpty) 'photo_url': currentAvatar,
                                  }).eq('id', aid);

                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
                                    KayanInAppToast.success('تم تحديث بيانات الوكالة بنجاح!');
                                    _loadAllData(silent: true);
                                  }
                                } catch (e) {
                                  setDialogState(() => saving = false);
                                  KayanInAppToast.error('فشل في حفظ التعديلات: $e');
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9D3E),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        child: saving
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text(
                                'حفظ التعديلات',
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Edit Announcement Dialog Quick Action
  void _showEditAnnouncementDialog() {
    final descCtrl = TextEditingController(text: _agencyInfo?.notice ?? '');
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('تعديل إعلان الوكالة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: descCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'اكتب إعلان الوكالة هنا...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final aid = _agencyInfo?.agencyId ?? widget.agencyId ?? '';
                final newNotice = descCtrl.text.trim();
                await SupabaseService().updateAgencyNotice(agencyId: aid, notice: newNotice);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  KayanInAppToast.success('تم تحديث الإعلان');
                  _loadAllData(silent: true);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9D3E)),
              child: const Text('حفظ', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 13. MEMBER MORE OPTIONS MODAL (dialog_union_mem_more_v2.xml)
  // ─────────────────────────────────────────────────────────────────────────────
  void _showMemberMoreOptionsDialog(AnchorAgentUserInfoDataModel member) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Panel (topPanel: dark_95 with radius 16dp)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // Member Card Info
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundImage: member.headImage.isNotEmpty
                              ? NetworkImage(member.headImage)
                              : null,
                          child: member.headImage.isEmpty ? const Icon(Icons.person) : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                member.nickname.isNotEmpty ? member.nickname : 'مضيف',
                                style: const TextStyle(
                                  color: Color(0xFF333333),
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'ID: ${member.userNo > 0 ? member.userNo : member.uid}',
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Button 1: Admin Settings (adminSettingBtn)
                    _buildDialogActionTile(
                      iconAsset: 'assets/images/agency/ic_agency_admin_setting.png',
                      fallbackIcon: Icons.admin_panel_settings,
                      title: 'إعدادات الإدارة والصلاحيات',
                      onTap: () {
                        Navigator.pop(ctx);
                        KayanInAppToast.info('صلاحية المضيف: مضيف معتمد');
                      },
                    ),

                    const SizedBox(height: 8),

                    // Button 2: Details / Salary (detailBtn)
                    _buildDialogActionTile(
                      iconAsset: 'assets/images/agency/ic_agency_member_detail.png',
                      fallbackIcon: Icons.query_stats,
                      title: 'تفاصيل ساعات البث والراتب',
                      onTap: () {
                        Navigator.pop(ctx);
                        _showHostDataDialog(member);
                      },
                    ),

                    const SizedBox(height: 8),

                    // Button 3: DELETE MEMBER (deleteBtn - RED)
                    _buildDialogActionTile(
                      iconAsset: 'assets/images/agency/ic_agency_member_delele.png',
                      fallbackIcon: Icons.person_remove,
                      title: 'حذف عضو من الوكالة',
                      textColor: Colors.red,
                      onTap: () {
                        Navigator.pop(ctx);
                        _confirmDeleteMember(member);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Cancel Button (cancelBtn: d9d9d9)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE5E7EB),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('إلغاء', style: TextStyle(color: Color(0xFF374151), fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDialogActionTile({
    required String iconAsset,
    required IconData fallbackIcon,
    required String title,
    required VoidCallback onTap,
    Color textColor = const Color(0xFF222222),
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Image.asset(
          iconAsset,
          width: 22,
          height: 22,
          errorBuilder: (_, __, ___) => Icon(fallbackIcon, color: textColor, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
        onTap: onTap,
        dense: true,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 14. DELETE MEMBER CONFIRMATION
  // ─────────────────────────────────────────────────────────────────────────────
  void _confirmDeleteMember(AnchorAgentUserInfoDataModel member) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.red, size: 22),
              SizedBox(width: 8),
              Text('حذف المضيف من الوكالة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'هل أنت متأكد من رغبتك في حذف المضيف "${member.nickname}" (ID: ${member.userNo > 0 ? member.userNo : member.uid}) من الوكالة؟\nلن يتمكن المضيف من البث تحت مظلة الوكالة بعد الحذف.',
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final aid = _agencyInfo?.agencyId ?? widget.agencyId ?? '';
                final targetUid = member.uid;

                try {
                  // Delete from host_agency_members
                  await _sb
                      .from('host_agency_members')
                      .delete()
                      .eq('agency_id', aid)
                      .or('host_uid.eq.$targetUid,user_id.eq.$targetUid');

                  // Clear agency_id in users table
                  await _sb
                      .from('users')
                      .update({'agency_id': null})
                      .eq('uid', targetUid);

                  KayanInAppToast.success('تم حذف المضيف من الوكالة بنجاح');
                  _loadAllData(silent: true);
                } catch (e) {
                  KayanInAppToast.error('حدث خطأ أثناء الحذف: $e');
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف نهائي', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 15. HOST DATA DIALOG (act_union_member_data.xml)
  // ─────────────────────────────────────────────────────────────────────────────
  void _showHostDataDialog(AnchorAgentUserInfoDataModel member) {
    final stageInfo = _calculateHostStageProgress(member);

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: member.headImage.isNotEmpty ? NetworkImage(member.headImage) : null,
                child: member.headImage.isEmpty ? const Icon(Icons.person) : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member.nickname, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    Text('ID: ${member.userNo > 0 ? member.userNo : member.uid}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDataRow('حالة المرحلة:', stageInfo['stageName'] ?? 'المرحلة 1'),
              _buildDataRow('اكتمال التارجت:', stageInfo['isCompleted'] == true ? 'مكتمل ✅' : 'قيد التقدم ⏳'),
              _buildDataRow('الماس المحقق:', '${member.diamonds} 💎'),
              _buildDataRow('متبقي للمرحلة التالية:', '${stageInfo['remainingDiamonds']} 💎'),
              const Divider(),
              _buildDataRow('أيام البث الصالحة:', '${member.days} يوم'),
              _buildDataRow('ساعات البث الإجمالية:', '${(member.minute / 60).toStringAsFixed(1)} ساعة'),
              _buildDataRow('أيام ≥ 2 ساعة:', '${(member.days * 0.9).round()} يوم'),
              _buildDataRow('أيام ≥ 4 ساعة:', '${(member.days * 0.6).round()} يوم'),
              _buildDataRow('أيام ≥ 6 ساعة:', '${(member.days * 0.3).round()} يوم'),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9D3E)),
              child: const Text('إغلاق', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF666666), fontSize: 12)),
          Text(value, style: const TextStyle(color: Color(0xFF111827), fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SLIVER TAB HEADER DELEGATE
// ─────────────────────────────────────────────────────────────────────────────
class _SliverTabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _SliverTabHeaderDelegate({required this.child});

  @override
  double get minExtent => 38.0;

  @override
  double get maxExtent => 38.0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _SliverTabHeaderDelegate oldDelegate) {
    return false;
  }
}
