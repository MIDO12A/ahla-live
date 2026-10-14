import 'dart:async';
import 'package:uuid/uuid.dart';
import '../../../../core/supabase_compat.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/r.dart';
import '../../../../models/user_model.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/supabase_service.dart';
import '../../../../services/supabase_data_service.dart';
import 'package:flutter/services.dart';
import '../data/agency_models.dart';
import '../data/agency_repository.dart';
import '../data/anchor_agent_model.dart';
import '../data/agency_chat_repository.dart';
import 'agency_exit_screen.dart';
import 'agency_invite_by_id_screen.dart';
import 'agency_item_detail_screen.dart';
import 'agency_join_requests_screen.dart';
import '../../../../services/dynamic_config_service.dart';

/// شاشة وكيل المضيفين وإدارة الوكالة (AnchorAgentActivity)
class AnchorAgentScreen extends StatefulWidget {
  final String? agencyId;

  const AnchorAgentScreen({super.key, this.agencyId});

  @override
  State<AnchorAgentScreen> createState() => _AnchorAgentScreenState();
}

class _AnchorAgentScreenState extends State<AnchorAgentScreen> {
  AgentInfoModel? _agentInfo;
  List<AnchorAgentUserInfoDataModel> _anchors = [];
  bool _loading = true;
  bool _isAgencyOwner = false;
  AnchorAgentUserInfoDataModel? _myAnchor;
  String? _error;
  StreamSubscription? _membersSub;
  StreamSubscription? _agencySub;
  Timer? _debounceTimer;

  // Invite Host State
  final TextEditingController _inviteSearchCtrl = TextEditingController();
  bool _inviteSearching = false;
  bool _inviteSending = false;
  Map<String, dynamic>? _foundUser;
  String? _inviteError;
  String? _inviteSuccess;

  @override
  void initState() {
    super.initState();
    _loadAgencyData();
  }

  @override
  void dispose() {
    _inviteSearchCtrl.dispose();
    _membersSub?.cancel();
    _agencySub?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _listenRealtime(String aid) {
    if (aid.isEmpty) return;
    _membersSub?.cancel();
    _agencySub?.cancel();
    _debounceTimer?.cancel();
    _debounceTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) {
        _loadAgencyData(silent: true);
      }
    });
  }

  void _scheduleReload() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _loadAgencyData(silent: true);
      }
    });
  }

  Future<void> _loadAgencyData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final user = Provider.of<UserProvider>(context, listen: false).currentUser;
      final uid = user?.uid ?? '';

      // جلب بيانات الوكالة والمضيفين
      final fb = SupabaseService();
      final data = await fb.getAnchorAgencyData(agencyId: widget.agencyId, agentUid: uid);

      final infoData = data['info'] as Map<String, dynamic>?;
      final infoModel = infoData != null ? AgentInfoModel.fromJson(infoData) : null;

      final loadedAnchors = (data['anchors'] as List<dynamic>?)
              ?.map((e) => AnchorAgentUserInfoDataModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];

      // فحص دقيق: المستخدم هو مالك الوكالة فقط إذا كان صاحب الوكالة الفعلي
      bool isOwner = false;
      final ownerUid = infoData?['owner_uid']?.toString() ?? infoData?['owner_id']?.toString() ?? '';
      if (ownerUid.isNotEmpty && ownerUid == uid) {
        isOwner = true;
      }
      if (!isOwner) {
        isOwner = loadedAnchors.any((a) => a.uid == uid && a.role == 'owner');
      }

      // البحث عن سجل المضيف الحالي إن وجد
      AnchorAgentUserInfoDataModel? currentHostRecord;
      try {
        currentHostRecord = loadedAnchors.firstWhere((a) => a.uid == uid);
      } catch (_) {
        currentHostRecord = null;
      }

      if (mounted) {
        setState(() {
          _isAgencyOwner = isOwner;
          _myAnchor = currentHostRecord;
          _agentInfo = infoModel ??
              AgentInfoModel(
                userId: int.tryParse(user?.customId ?? '0') ?? 0,
                agencyName: user?.name ?? 'وكالتي الرسمية',
                avatarUrl: user?.photoUrl ?? '',
                agentBean: user?.coins ?? 0,
                transferMoney: user?.diamonds ?? 0,
                transferDollar: ((user?.diamonds ?? 0) / 1000).toInt(),
              );
          if (_agentInfo?.notice.isNotEmpty == true) {
            _noticeText = _agentInfo!.notice;
          }
          _anchors = loadedAnchors;
          _loading = false;
        });

        final resolvedAid = _agentInfo?.agencyId ?? widget.agencyId;
        if (resolvedAid != null && resolvedAid.isNotEmpty && _membersSub == null) {
          _listenRealtime(resolvedAid);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (!silent) _error = 'حدث خطأ في تحميل بيانات الوكالة';
          _loading = false;
        });
      }
    }
  }

  int _currentTab = 0; // 0: Members, 1: Income, 2: Sub-agents
  String _noticeText = 'أهلاً بكم في الوكالة الرسمية! يرجى الالتزام بساعات البث المحددة وتحقيق التارجت الشهري للحصول على المكافآت.';

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final info = _agentInfo;
    final dc = DynamicConfigService();
    final bgImg = dc.hostsBgImage;
    final headerColor = dc.hostsHeaderColor;

    final scrollWidget = RefreshIndicator(
      color: const Color(0xFFFFD700),
      onRefresh: _loadAgencyData,
      child: CustomScrollView(
        slivers: [
          // ── CollapsingToolbar / App Bar matching union_activity_my_agency.xml ──
          SliverToBoxAdapter(
            child: _buildCollapsingHeader(info, isAr),
          ),

          // ── Tab Bar with union_tab_bg ──
          SliverToBoxAdapter(
            child: _buildTabBar(isAr),
          ),

          // ── Tab Content ──
          if (_currentTab == 0)
            _buildMembersList(isAr)
          else if (_currentTab == 1)
            _buildIncomeTab(info, isAr)
          else if (_isAgencyOwner)
            _buildInviteHostsTab(isAr)
          else
            _buildIncomeTab(info, isAr),

          if (_isAgencyOwner)
            _buildRemoveHostCard(isAr),

          const SliverToBoxAdapter(
            child: SizedBox(height: 60),
          ),
        ],
      ),
    );

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: headerColor,
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)))
            : (bgImg.isNotEmpty
                ? Container(
                    decoration: BoxDecoration(
                      image: bgImg.startsWith('http')
                          ? DecorationImage(image: NetworkImage(bgImg), fit: BoxFit.cover)
                          : DecorationImage(image: AssetImage(bgImg), fit: BoxFit.cover),
                    ),
                    child: scrollWidget,
                  )
                : scrollWidget),
      ),
    );
  }

  Widget _buildRemoveHostCard(bool isAr) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C34),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.35)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_remove_rounded, color: Color(0xFFFF5252), size: 22),
                  const SizedBox(width: 8),
                  Text(
                    isAr ? 'إزالة مضيف من الوكالة' : 'Remove Host from Agency',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                isAr
                    ? 'يمكنك اختيار أي مضيف لإزالته وإنهاء ارتباطه بالوكالة فوراً دون التأثير على حساب الوكالة.'
                    : 'Select any host to remove them and unlink them from your agency immediately.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showRemoveHostModal(isAr),
                  icon: const Icon(Icons.person_remove, size: 20),
                  label: Text(
                    isAr ? 'إزالة مضيف' : 'Remove Host',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5252),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRemoveHostModal(bool isAr) {
    final hostsToRemove = _anchors.where((a) => a.role != 'owner').toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.person_remove_rounded, color: Color(0xFFFF5252), size: 22),
                    const SizedBox(width: 8),
                    Text(
                      isAr ? 'إزالة مضيف من الوكالة' : 'Remove Host from Agency',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  isAr ? 'اختر المضيف الذي ترغب في إزالته وفك ارتباطه بالوكالة فوراً:' : 'Select a host to remove from your agency:',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                ),
                const SizedBox(height: 16),
                if (hostsToRemove.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        isAr ? 'لا يوجد مضيفين في الوكالة حالياً للإزالة' : 'No hosts available to remove',
                        style: const TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: hostsToRemove.length,
                      separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                      itemBuilder: (ctx, i) {
                        final anchor = hostsToRemove[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.white12,
                            backgroundImage: anchor.avatarUrl.isNotEmpty ? R.cachedImage(anchor.avatarUrl) : null,
                            child: anchor.avatarUrl.isEmpty ? const Icon(Icons.person, color: Colors.white54) : null,
                          ),
                          title: Text(
                            anchor.nickname.isNotEmpty ? anchor.nickname : (isAr ? 'مضيف' : 'Host'),
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'ID: ${anchor.userNo > 0 ? anchor.userNo : anchor.userId} • ${_getAnchorStage(anchor.totalDiamond, isAr)} • ${(anchor.minute / 60).toStringAsFixed(1)} ${isAr ? 'ساعة' : 'hrs'}',
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                          ),
                          trailing: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _handleKickMember(anchor, isAr);
                            },
                            icon: const Icon(Icons.person_remove, size: 14, color: Colors.white),
                            label: Text(isAr ? 'إزالة' : 'Remove', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF5252),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Collapsing Header matching act_union_center_v2.xml & vh_union_center_top_info.xml
  Widget _buildCollapsingHeader(AgentInfoModel? info, bool isAr) {
    final user = Provider.of<UserProvider>(context, listen: false).currentUser;
    final dc = DynamicConfigService();
    final agencyName = info?.agencyName.isNotEmpty == true ? info!.agencyName : (isAr ? 'وكالتي الرسمية' : 'My Agency');
    final displayAgencyId = formatAgencyNumericId(info?.agencyPublicId ?? (info?.agencyId.isNotEmpty == true ? info!.agencyId : widget.agencyId ?? (info?.userId != 0 ? info?.userId.toString() : '100')));
    final memberCount = _anchors.length;
    final ownerName = user?.name ?? 'المدير';
    final ownerId = user?.customId ?? user?.uid ?? '1000';
    final expNeeded = 50000;
    final currExp = ((info?.agentBean ?? 0) % expNeeded);

    return Stack(
      children: [
        // ── agencyBlurBg + blackMask (مطابق لـ act_union_center_v2.xml) ──
        Positioned.fill(
          child: Stack(
            fit: StackFit.expand,
            children: [
              dc.hostAgencyHeaderBgImage.isNotEmpty
                  ? (dc.hostAgencyHeaderBgImage.startsWith('http')
                      ? Image.network(dc.hostAgencyHeaderBgImage, fit: BoxFit.cover)
                      : Image.asset(dc.hostAgencyHeaderBgImage, fit: BoxFit.cover))
                  : Image.asset(
                      R.unionMyAgencyBg,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: const Color(0xFF141923)),
                    ),
              Container(color: Colors.black.withOpacity(0.55)), // blackMask (20% to 55%)
            ],
          ),
        ),

        SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top Toolbar (toolBar) ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: Image.asset(
                        'assets/mipmap-xxhdpi/back_white_2.webp',
                        width: 24,
                        height: 24,
                        errorBuilder: (_, __, ___) => const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Text(
                      _isAgencyOwner ? (isAr ? 'مركز الوكالة' : 'Agency Center') : (isAr ? 'وكالتي الرسمية' : 'My Agency'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (_isAgencyOwner) ...[
                      IconButton(
                        icon: const Icon(Icons.group_add_rounded, color: Color(0xFFFFD700), size: 24),
                        tooltip: isAr ? 'طلبات الانضمام' : 'Join Requests',
                        onPressed: () {
                          final aid = _agentInfo?.agencyId ?? widget.agencyId ?? '';
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AgencyJoinRequestsScreen(
                                agencyId: aid,
                                canKick: true,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                    IconButton(
                      icon: Image.asset(
                        R.unionRuleIc,
                        width: 24,
                        height: 24,
                        errorBuilder: (_, __, ___) => const Icon(Icons.help_outline, color: Colors.white),
                      ),
                      tooltip: isAr ? 'قوانين الوكالة' : 'Rules',
                      onPressed: () => _showRulesDialog(isAr),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // ── vh_union_center_top_info.xml (شاشة مالك الوكالة وشاشة المضيف) ──
              if (_isAgencyOwner) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Agency Avatar (80dp) + Admin Badge (34dp)
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: (info?.avatarUrl.isNotEmpty == true)
                                  ? Image(
                                      image: R.cachedImage(info!.avatarUrl),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.shield, color: Colors.white54, size: 38),
                                    )
                                  : const Icon(Icons.shield, color: Colors.white54, size: 38),
                            ),
                          ),
                          Positioned(
                            bottom: -2,
                            right: isAr ? null : -2,
                            left: isAr ? -2 : null,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFFFD700),
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: const Center(
                                child: Icon(Icons.admin_panel_settings_rounded, size: 16, color: Color(0xFF522800)),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(width: 16),

                      // Agency Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Agency Name + Edit Pencil
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    agencyName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () => _showNoticeDialog(isAr),
                                  child: dc.buildDynamicImage(
                                    dc.hostAgencyEditIcon,
                                    defaultAsset: R.hykIcEdit,
                                    width: 18,
                                    height: 18,
                                    fallbackWidget: const Icon(Icons.edit_note_rounded, color: Colors.white70, size: 20),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            // Agency ID
                            Text(
                              'ID: $displayAgencyId',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            // Gradient Divider Line (divide1 + divide2)
                            Container(
                              height: 1.2,
                              width: 180,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.transparent, Colors.white70, Colors.transparent],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Owner Name & ID in #00b5b3 (hilla_light)
                            Row(
                              children: [
                                Text(
                                  ownerName,
                                  style: const TextStyle(
                                    color: Color(0xFF00B5B3),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '(ID: $ownerId)',
                                  style: const TextStyle(
                                    color: Color(0xFF00B5B3),
                                    fontSize: 11,
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
              ] else ...[
                // ── شاشة المضيف (Host Header) ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF00B5B3), width: 2),
                        ),
                        child: ClipOval(
                          child: (user?.photoUrl.isNotEmpty == true)
                              ? Image(
                                  image: R.cachedImage(user!.photoUrl),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white54, size: 36),
                                )
                              : const Icon(Icons.person, color: Colors.white54, size: 36),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.name ?? 'المضيف',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'ID: ${user?.customId ?? user?.uid ?? ''}',
                              style: const TextStyle(color: Color(0xFF00B5B3), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'وكالة: $agencyName (ID: $displayAgencyId)',
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // ── Broadcast Notice (agencyIntroIc + agencyIntroTv + arrowIv) ──
              GestureDetector(
                onTap: () => _showNoticeDialog(isAr),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0x3D000000),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.15)),
                  ),
                  child: Row(
                    children: [
                      dc.buildDynamicImage(
                        dc.hostAgencyBroadcastIcon,
                        defaultAsset: R.hykIcAgencyBroadcast,
                        width: 18,
                        height: 18,
                        fallbackWidget: const Icon(Icons.campaign_rounded, color: Color(0xFFFFD700), size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _noticeText,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Image.asset(
                        R.hykIcBackDarkRight,
                        width: 14,
                        height: 14,
                        errorBuilder: (_, __, ___) => const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 18),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Level Panel (vh_agency_level.xml) for Owner ──
              if (_isAgencyOwner) ...[
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    image: dc.getDecorationImage(
                      dc.hostAgencyLevelBgImage,
                      defaultAsset: R.hykIcAgencyLevelBg,
                      fit: BoxFit.fill,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Progress & EXP
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '$currExp',
                                  style: const TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isAr ? 'نقطة خبرة للترقية' : 'EXP to next level',
                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                                const SizedBox(width: 4),
                                dc.buildDynamicImage(
                                  dc.hostAgencyHelpIcon,
                                  defaultAsset: R.hykIcHelpWhite,
                                  width: 14,
                                  height: 14,
                                  fallbackWidget: const Icon(Icons.help_outline_rounded, size: 14, color: Colors.white54),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Gradient Progress Bar (#6a8cf7 to #ff9d3e)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                height: 12,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF283D7E),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFF1C40A1), width: 1),
                                ),
                                child: FractionallySizedBox(
                                  alignment: isAr ? Alignment.centerRight : Alignment.centerLeft,
                                  widthFactor: (currExp / expNeeded).clamp(0.05, 1.0),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Color(0xFF6A8CF7), Color(0xFFFF9D3E)],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '$currExp / $expNeeded',
                                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                                ),
                                Text(
                                  isAr ? 'المستوى القادم' : 'Next Level',
                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 14),

                      // Level Flag / Badge (clFlag)
                      Container(
                        width: 76,
                        height: 70,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        decoration: BoxDecoration(
                          image: dc.getDecorationImage(
                            dc.hostAgencyFlagImage,
                            defaultAsset: R.hykIcFlag,
                            fit: BoxFit.fill,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('👑', style: TextStyle(fontSize: 18)),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                image: dc.getDecorationImage(
                                  dc.hostAgencyRankNameBgImage,
                                  defaultAsset: R.hykIcNameBg,
                                  fit: BoxFit.fill,
                                ),
                              ),
                              child: Text(
                                info?.tier?.toUpperCase() ?? 'DIAMOND',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // ── Panels: withdrawalAccountPanel & withdrawRecordPanel ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      // حساب السحب
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AgencyOwnerWalletScreen(),
                              ),
                            );
                          },
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF00B5B3), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    isAr ? 'حساب السحب' : 'Withdraw Account',
                                    style: const TextStyle(
                                      color: Color(0xFF222222),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF00E5A0),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right_rounded, color: Colors.black38, size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // سجل السحب
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AgencyOwnerWalletScreen(),
                              ),
                            );
                          },
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.receipt_long_rounded, color: Color(0xFF00B5B3), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    isAr ? 'سجل السحب' : 'Withdraw Records',
                                    style: const TextStyle(
                                      color: Color(0xFF222222),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded, color: Colors.black38, size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }

  /// Tab bar matching union_layout_agency_tab_custom_view.xml & union_tab_bg
  Widget _buildTabBar(bool isAr) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          _buildTabButton(0, isAr ? 'أعضاء الوكالة' : 'Members'),
          _buildTabButton(
            1,
            _isAgencyOwner
                ? (isAr ? 'دخل الوكالة' : 'Income')
                : (isAr ? 'مستوى دخلي ومراحلي' : 'My Income & Stages'),
          ),
          if (_isAgencyOwner)
            _buildTabButton(2, isAr ? 'دعوات المضيفين' : 'Host Invites'),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String title) {
    final isSelected = _currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentTab = index),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFFD700) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              color: isSelected ? const Color(0xFF1A1A1A) : Colors.white70,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  /// Tab 1: Members List matching union_adapter_agency_item.xml
  Widget _buildMembersList(bool isAr) {
    if (_anchors.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: Text(
              isAr ? 'لا يوجد أعضاء في الوكالة حالياً' : 'No members yet',
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, index) {
          final anchor = _anchors[index];
          return GestureDetector(
            onTap: () => _showHostDetailsModal(anchor, isAr),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF242424),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white12,
                    backgroundImage: anchor.avatarUrl.isNotEmpty ? R.cachedImage(anchor.avatarUrl) : null,
                    child: anchor.avatarUrl.isEmpty ? const Icon(Icons.person, color: Colors.white54) : null,
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
                                anchor.nickname.isNotEmpty ? anchor.nickname : (isAr ? 'مضيف' : 'Host'),
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (anchor.role == 'owner') ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFFD700), Color(0xFFFF9800)],
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.workspace_premium, color: Colors.black, size: 12),
                                    const SizedBox(width: 2),
                                    Text(
                                      isAr ? 'ملك الوكالة' : 'Agency Owner',
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: anchor.role == 'supervisor' ? const Color(0x33FF9800) : const Color(0x22FFFFFF),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  anchor.role == 'supervisor' ? (isAr ? 'مشرف' : 'Admin') : (isAr ? 'مضيف' : 'Host'),
                                  style: TextStyle(
                                    color: anchor.role == 'supervisor' ? const Color(0xFFFF9800) : Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 6),
                            // Stage badge (المرحلة)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0x33FFD700),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0x55FFD700)),
                              ),
                              child: Text(
                                _getAnchorStage(anchor.totalDiamond, isAr),
                                style: const TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (anchor.role == 'owner') ...[
                          Text(
                            isAr ? '👑 ملك الوكالة' : '👑 Agency Owner',
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        Text(
                          'ID: ${anchor.userNo > 0 ? anchor.userNo : anchor.userId}',
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            // Hours count (عدد الساعات)
                            const Icon(Icons.access_time_rounded, color: Color(0xFF00D4FF), size: 13),
                            const SizedBox(width: 3),
                            Text(
                              '${(anchor.minute / 60).toStringAsFixed(1)} ${isAr ? 'ساعة' : 'hrs'}',
                              style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 10),
                            // Diamonds count (عدد الماس)
                            Image.asset(R.commonDiamondIc, width: 12, height: 12, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                            const SizedBox(width: 3),
                            Text(
                              '${anchor.totalDiamond} 💎',
                              style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            if (_isAgencyOwner) ...[
                              const SizedBox(width: 8),
                              Builder(
                                builder: (_) {
                                  final mDiamonds = int.tryParse(anchor.diamonds) ?? int.tryParse(anchor.totalDiamond) ?? 0;
                                  double cRate = _agentInfo?.commissionRate ?? 0.10;
                                  if (_agentInfo?.milestones != null && _agentInfo!.milestones.isNotEmpty) {
                                    for (final m in _agentInfo!.milestones) {
                                      final t = (m['target_diamonds'] as num?)?.toInt() ?? 0;
                                      if (mDiamonds >= t && t > 0) {
                                        cRate = (m['agent_commission_rate'] as num?)?.toDouble() ?? cRate;
                                      }
                                    }
                                  }
                                  final earnedComm = (mDiamonds * cRate).toInt();
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0x2200E676),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(color: const Color(0x5500E676)),
                                    ),
                                    child: Text(
                                      '${isAr ? 'العمولة' : 'Comm'}: $earnedComm 💎',
                                      style: const TextStyle(color: Color(0xFF69F0AE), fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Direct Kick Button & Management Menu (For Owner Only)
                  if (_isAgencyOwner && anchor.role != 'owner') ...[
                    ElevatedButton.icon(
                      onPressed: () => _handleKickMember(anchor, isAr),
                      icon: const Icon(Icons.person_remove_rounded, size: 13, color: Colors.white),
                      label: Text(
                        isAr ? 'طرد' : 'Kick',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5252),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        minimumSize: const Size(56, 30),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
                      color: const Color(0xFF2C2C34),
                      onSelected: (action) => _handleMemberAction(anchor, action, isAr),
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'role',
                          child: Row(
                            children: [
                              const Icon(Icons.security, color: Colors.amber, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                anchor.role == 'supervisor' ? (isAr ? 'تنزيل إلى مضيف' : 'Demote to Host') : (isAr ? 'ترقية إلى مشرف' : 'Promote to Admin'),
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'remove',
                          child: Row(
                            children: [
                              const Icon(Icons.person_remove, color: Colors.redAccent, size: 18),
                              const SizedBox(width: 8),
                              Text(isAr ? 'طرد من الوكالة' : 'Kick Member', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
        childCount: _anchors.length,
      ),
    );
  }

  /// نافذة تفاصيل المضيف الشاملة لمالك الوكالة (Host Details & Commission Modal)
  void _showHostDetailsModal(AnchorAgentUserInfoDataModel anchor, bool isAr) {
    final hostDiamonds = int.tryParse(anchor.totalDiamond) ?? 0;
    final liveHours = (anchor.minute / 60.0).toStringAsFixed(1);
    final commRate = _agentInfo?.commissionRate ?? 0.10;
    final agentEarnedDiamonds = (hostDiamonds * commRate).toInt();
    final agentEarnedUsd = (agentEarnedDiamonds / 1000).toStringAsFixed(2);
    final stageName = _getAnchorStage(anchor.totalDiamond, isAr);
    final targetDiamonds = anchor.targetDiamonds > 0 ? anchor.targetDiamonds : 100000;
    final progressPct = ((hostDiamonds / targetDiamonds).clamp(0.0, 1.0) * 100).toStringAsFixed(1);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B1B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Header with Host Avatar, Name, ID, and Badges
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white12,
                    backgroundImage: anchor.avatarUrl.isNotEmpty ? R.cachedImage(anchor.avatarUrl) : null,
                    child: anchor.avatarUrl.isEmpty ? const Icon(Icons.person, color: Colors.white54, size: 30) : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          anchor.nickname.isNotEmpty ? anchor.nickname : (isAr ? 'مضيف' : 'Host'),
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'ID: ${anchor.userNo > 0 ? anchor.userNo : (anchor.userId > 0 ? anchor.userId : (anchor.uid.length > 8 ? anchor.uid.substring(0, 8) : anchor.uid))}',
                          style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: anchor.role == 'owner'
                                    ? const Color(0xFFFFD700)
                                    : (anchor.role == 'supervisor' ? const Color(0xFFFF9800) : const Color(0x33FFFFFF)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                anchor.role == 'owner'
                                    ? (isAr ? '👑 ملك الوكالة' : '👑 Agency Owner')
                                    : (anchor.role == 'supervisor' ? (isAr ? 'مشرف وكالة' : 'Admin') : (isAr ? 'مضيف رسمي' : 'Host')),
                                style: TextStyle(
                                  color: anchor.role == 'owner' ? Colors.black : Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0x22FFD700),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0x44FFD700)),
                              ),
                              child: Text(
                                stageName,
                                style: const TextStyle(color: Color(0xFFFFD700), fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Agent Commission from this Host Banner (عمولة الوكيل المكتسبة من المضيف)
              if (_isAgencyOwner && anchor.role != 'owner') ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2E2412), Color(0xFF1E190E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x55FFD700)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Color(0x33FFD700),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.monetization_on, color: Color(0xFFFFD700), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isAr ? 'عمولة الوكالة المحتسبة من هذا المضيف ⚡' : 'Agency Commission from Host ⚡',
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$agentEarnedDiamonds 💎  (~\$$agentEarnedUsd USD) • بنسبة ${((commRate) * 100).toInt()}%',
                              style: const TextStyle(color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Performance Cards Grid
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF26262F),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Image.asset(R.commonDiamondIc, width: 14, height: 14, errorBuilder: (_, __, ___) => const Icon(Icons.diamond, color: Color(0xFFFFD700), size: 14)),
                              const SizedBox(width: 5),
                              Text(isAr ? 'ألماس الشهر' : 'Monthly Diamonds', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('${anchor.totalDiamond} 💎', style: const TextStyle(color: Color(0xFFFFD700), fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF26262F),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.access_time_filled, color: Color(0xFF00D4FF), size: 14),
                              SizedBox(width: 5),
                              Text('ساعات البث', style: TextStyle(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('$liveHours ساعة', style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF26262F),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.calendar_today, color: Color(0xFF4CAF50), size: 14),
                              SizedBox(width: 5),
                              Text('الأيام الفعالة', style: TextStyle(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('${anchor.days} يوم', style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF26262F),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.track_changes, color: Color(0xFFFF9800), size: 14),
                              SizedBox(width: 5),
                              Text('إنجاز التارجت', style: TextStyle(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('$progressPct%', style: const TextStyle(color: Color(0xFFFF9800), fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Target Progress Bar
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF24242C),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(isAr ? 'تقدم التارجت والمرحلة:' : 'Target & Stage:', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        Text('$hostDiamonds / $targetDiamonds 💎', style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: targetDiamonds > 0 ? (hostDiamonds / targetDiamonds).clamp(0.0, 1.0) : 0.0,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation(Color(0xFFFFD700)),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Action Buttons for Agency Owner
              if (_isAgencyOwner && anchor.role != 'owner') ...[
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _handleMemberAction(anchor, 'role', isAr);
                        },
                        icon: const Icon(Icons.security, size: 18),
                        label: Text(
                          anchor.role == 'supervisor' ? (isAr ? 'تنزيل لمضيف' : 'Demote') : (isAr ? 'ترقية لمشرف' : 'Promote'),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF33333F),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _handleKickMember(anchor, isAr);
                        },
                        icon: const Icon(Icons.person_remove_rounded, size: 18, color: Colors.white),
                        label: Text(
                          isAr ? 'طرد من الوكالة' : 'Kick Host',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5252),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleMemberAction(AnchorAgentUserInfoDataModel anchor, String action, bool isAr) async {
    final agencyId = _agentInfo?.agencyId ?? widget.agencyId ?? '';
    if (action == 'role') {
      final newRole = anchor.role == 'supervisor' ? 'host' : 'supervisor';
      final label = newRole == 'supervisor' ? (isAr ? 'ترقية إلى مشرف' : 'Promote to Admin') : (isAr ? 'تنزيل إلى مضيف' : 'Demote to Host');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF24242A),
          title: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(
            isAr
                ? 'هل أنت متأكد من تغيير رتبة [${anchor.nickname}] إلى [${newRole == 'supervisor' ? 'مشرف وكالة' : 'مضيف'}]؟'
                : 'Are you sure you want to change role of ${anchor.nickname} to $newRole?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(isAr ? 'إلغاء' : 'Cancel', style: const TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700)),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isAr ? 'تأكيد' : 'Confirm', style: const TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (ok == true && anchor.uid.isNotEmpty) {
        await SupabaseService().updateAgencyMemberRole(agencyId: agencyId, memberUid: anchor.uid, newRole: newRole);
        _loadAgencyData();
      }
    } else if (action == 'remove') {
      _handleKickMember(anchor, isAr);
    }
  }

  Future<void> _handleKickMember(AnchorAgentUserInfoDataModel anchor, bool isAr) async {
    final agencyId = _agentInfo?.agencyId ?? widget.agencyId ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF24242A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF5252), size: 22),
            const SizedBox(width: 8),
            Text(isAr ? 'طرد من الوكالة' : 'Kick from Agency', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          isAr
              ? 'هل أنت متأكد من طرد المضيف [${anchor.nickname.isNotEmpty ? anchor.nickname : anchor.userId}] من الوكالة فوراً؟ سيتم فك ارتباطه وحذف عضويته.'
              : 'Are you sure you want to kick [${anchor.nickname}] from the agency immediately?',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'إلغاء' : 'Cancel', style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5252)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? 'طرد فوراً' : 'Kick Now', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (ok == true) {
      final targetUid = anchor.uid.isNotEmpty ? anchor.uid : anchor.userId.toString();
      try {
        await SupabaseService().removeAgencyMember(agencyId: agencyId, memberUid: targetUid);
      } catch (_) {}


      if (mounted) {
        setState(() {
          _anchors.removeWhere((a) => (anchor.uid.isNotEmpty && a.uid == anchor.uid) || a.userId == anchor.userId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAr ? 'تم طرد المضيف بنجاح وإنهاء عضويته' : 'Host kicked successfully'),
            backgroundColor: const Color(0xFFFF5252),
          ),
        );
      }
    }
  }

  String _getAnchorStage(String diamondsStr, bool isAr) {
    final d = double.tryParse(diamondsStr) ?? 0.0;
    if (d >= 5000000) return isAr ? 'المرحلة 7' : 'Stage 7';
    if (d >= 2000000) return isAr ? 'المرحلة 6' : 'Stage 6';
    if (d >= 1000000) return isAr ? 'المرحلة 5' : 'Stage 5';
    if (d >= 500000) return isAr ? 'المرحلة 4' : 'Stage 4';
    if (d >= 300000) return isAr ? 'المرحلة 3' : 'Stage 3';
    if (d >= 100000) return isAr ? 'المرحلة 2' : 'Stage 2';
    return isAr ? 'المرحلة 1' : 'Stage 1';
  }

  /// Tab 2: Income & Targets (دخل الوكالة للمالك / مستوى دخلي والمراحل للمضيف)
  Widget _buildIncomeTab(AgentInfoModel? info, bool isAr) {
    final dc = DynamicConfigService();
    int totalAnchorsDiamonds = 0;
    int totalAgentCommissionDiamonds = 0;
    for (final a in _anchors) {
      final hostMonthlyDiamonds = int.tryParse(a.diamonds) ?? int.tryParse(a.totalDiamond) ?? 0;
      totalAnchorsDiamonds += hostMonthlyDiamonds;

      double hostCommRate = info?.commissionRate ?? 0.10;
      if (info?.milestones != null && info!.milestones.isNotEmpty) {
        for (final m in info.milestones) {
          final t = (m['target_diamonds'] as num?)?.toInt() ?? 0;
          if (hostMonthlyDiamonds >= t && t > 0) {
            hostCommRate = (m['agent_commission_rate'] as num?)?.toDouble() ?? hostCommRate;
          }
        }
      }
      totalAgentCommissionDiamonds += (hostMonthlyDiamonds * hostCommRate).toInt();
    }
    final rawTransfer = info?.transferMoney ?? 0;
    final totalAgencyDiamonds = rawTransfer > 0 ? rawTransfer : totalAnchorsDiamonds;
    final ownerCommissionUsd = (totalAgentCommissionDiamonds / 1000).toStringAsFixed(1);
    final agencyDollar = info?.transferDollar != 0 && info?.transferDollar != null
        ? info!.transferDollar.toString()
        : ownerCommissionUsd;
    final commRatePct = ((info?.commissionRate ?? 0.10) * 100).toInt();

    // حساب أرقام المضيف الشخصية إذا لم يكن مالكاً
    final user = Provider.of<UserProvider>(context, listen: false).currentUser;
    final hostDiamonds = int.tryParse(_myAnchor?.diamonds ?? '') ?? (user?.diamonds ?? 0);
    final hostHours = ((_myAnchor?.minute ?? 0.0) / 60.0);
    final effectiveDiamonds = _isAgencyOwner ? totalAgencyDiamonds : hostDiamonds;
    final hostDollar = (hostDiamonds / 1000).toStringAsFixed(1);

    int stageTarget = 100000;
    if (effectiveDiamonds >= 5000000) {
      stageTarget = 10000000;
    } else if (effectiveDiamonds >= 2000000) {
      stageTarget = 5000000;
    } else if (effectiveDiamonds >= 1000000) {
      stageTarget = 2000000;
    } else if (effectiveDiamonds >= 500000) {
      stageTarget = 1000000;
    } else if (effectiveDiamonds >= 300000) {
      stageTarget = 500000;
    } else if (effectiveDiamonds >= 100000) {
      stageTarget = 300000;
    } else {
      stageTarget = 100000;
    }

    final targetDiamonds = _isAgencyOwner
        ? ((info?.targetDiamonds != null && info!.targetDiamonds > 0 && info.targetDiamonds != 1000000) ? info.targetDiamonds : stageTarget)
        : (_myAnchor != null && _myAnchor!.targetDiamonds > 0 ? _myAnchor!.targetDiamonds : stageTarget);

    final progress = targetDiamonds > 0 ? (effectiveDiamonds / targetDiamonds).clamp(0.0, 1.0) : 0.0;
    final percent = (progress * 100).toStringAsFixed(1);
    final salaryUsd = info?.salaryUsd ?? 0.0;
    final currentStageLabel = _getAnchorStage(effectiveDiamonds.toString(), isAr);
    final transferMoney = effectiveDiamonds;

    final hostValidDays2h = hostHours >= 2 ? (hostHours / 2).toInt() : 0;
    final hostValidDays4h = hostHours >= 4 ? (hostHours / 4).toInt() : 0;
    final hostValidDays6h = hostHours >= 6 ? (hostHours / 6).toInt() : 0;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ══════════════════════════════════════════════════════════
            //  قسم الألماس (diamondTv) - مطابق لـ layout_union_salary_panel
            // ══════════════════════════════════════════════════════════
            // ══════════════════════════════════════════════════════════
            //  قسم الألماس (diamondTv) - مطابق لـ layout_union_salary_panel
            // ══════════════════════════════════════════════════════════
            Row(
              children: [
                dc.buildDynamicImage(
                  dc.hostAgencyLineDotIcon,
                  defaultAsset: R.hykIcCommonLineDot,
                  width: 14,
                  height: 14,
                  fallbackWidget: Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: dc.hostAgencyCardColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isAr ? 'الألماس' : 'Diamonds',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // البطاقتان الفيروزيتان للألماس (#00b5b3) أو المستبدلتان بالصور من اللوحة
            Row(
              children: [
                // البطاقة 1: المستهدف
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      image: dc.getDecorationImage(
                        dc.hostAgencyDiamondCardBgImage,
                        fit: BoxFit.cover,
                      ),
                      color: dc.hostAgencyDiamondCardBgImage.isNotEmpty ? null : dc.hostAgencyCardColor,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: dc.hostAgencyCardColor.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          bottom: -6,
                          right: isAr ? null : -6,
                          left: isAr ? -6 : null,
                          child: Opacity(
                            opacity: 0.35,
                            child: dc.buildDynamicImage(
                              dc.hostAgencyDiamondWatermark,
                              defaultAsset: R.hykIcSalaryPanel1,
                              height: 40,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isAgencyOwner
                                  ? (isAr ? 'مستهدف ألماس الوكالة' : 'Agency Diamond Target')
                                  : (isAr ? 'مستهدف ألماسي الحالي' : 'My Diamond Target'),
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text('💎', style: TextStyle(fontSize: 16)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '$targetDiamonds',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // البطاقة 2: الرصيد الفعلي
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      image: dc.getDecorationImage(
                        dc.hostAgencyDiamondCardBgImage,
                        fit: BoxFit.cover,
                      ),
                      color: dc.hostAgencyDiamondCardBgImage.isNotEmpty ? null : dc.hostAgencyCardColor,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: dc.hostAgencyCardColor.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          bottom: -6,
                          right: isAr ? null : -6,
                          left: isAr ? -6 : null,
                          child: Opacity(
                            opacity: 0.35,
                            child: dc.buildDynamicImage(
                              dc.hostAgencyDiamondWatermark,
                              defaultAsset: R.hykIcSalaryPanel1,
                              height: 40,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isAgencyOwner
                                  ? (isAr ? 'إنتاج ألماس الوكالة' : 'Agency Diamonds')
                                  : (isAr ? 'رصيدي المحقق حالياً' : 'My Actual Diamonds'),
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text('💎', style: TextStyle(fontSize: 16)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '$effectiveDiamonds',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // للمضيف: معاينة المرحلة القادمة مع سهم التحويل (ic_transfer_to)
            if (!_isAgencyOwner) ...[
              const SizedBox(height: 6),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    dc.buildDynamicImage(dc.hostAgencyTransferArrowIcon, defaultAsset: R.hykIcTransferTo, width: 22, height: 22),
                    dc.buildDynamicImage(dc.hostAgencyTransferArrowIcon, defaultAsset: R.hykIcTransferTo, width: 22, height: 22),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0x3300B5B3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x6600B5B3), width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr ? 'المستهدف القادم' : 'Next Target',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${targetDiamonds * 2} 💎',
                            style: const TextStyle(color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0x3300B5B3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x6600B5B3), width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr ? 'راتب المرحلة القادمة' : 'Next Stage Salary',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '\$${((targetDiamonds * 2) / 1000).toStringAsFixed(1)} USD',
                            style: const TextStyle(color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 18),

            // ══════════════════════════════════════════════════════════
            //  قسم الراتب والسحب (salaryTv) - البطاقة الكبرى الفيروزية
            // ══════════════════════════════════════════════════════════
            Row(
              children: [
                dc.buildDynamicImage(
                  dc.hostAgencyLineDotIcon,
                  defaultAsset: R.hykIcCommonLineDot,
                  width: 14,
                  height: 14,
                  fallbackWidget: Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: dc.hostAgencyCardColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isAr ? 'الراتب' : 'Salary',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── agentSalaryAndOverdraft / salaryAndOverdraft (#00b5b3) ──
            Container(
              decoration: BoxDecoration(
                image: dc.getDecorationImage(
                  dc.hostAgencySalaryCardBgImage,
                  fit: BoxFit.cover,
                ),
                color: dc.hostAgencySalaryCardBgImage.isNotEmpty ? null : dc.hostAgencyCardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: dc.hostAgencyCardColor.withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    bottom: 0,
                    right: isAr ? null : 0,
                    left: isAr ? 0 : null,
                    child: Opacity(
                      opacity: 0.35,
                      child: dc.buildDynamicImage(
                        dc.hostAgencySalaryWatermark,
                        defaultAsset: R.hykIcSalaryPanel2,
                        height: 75,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // القسم الأيسر: الراتب وزر السحب
                            Expanded(
                              flex: 6,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isAgencyOwner
                                        ? (isAr ? 'راتب مالك الوكالة المحتسب' : 'Agency Owner Salary')
                                        : (isAr ? 'راتب المرحلة الحالية' : 'Current Stage Salary'),
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _isAgencyOwner ? '\$$agencyDollar USD' : '\$$hostDollar USD',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  // زر السحب الأبيض البيضاوي (overdraftBtn)
                                  GestureDetector(
                                    onTap: () {
                                      if (_isAgencyOwner) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => const AgencyOwnerWalletScreen()),
                                        );
                                      } else {
                                        _openTransferSalaryToAgentModal(hostDiamonds, isAr);
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                                      decoration: BoxDecoration(
                                        image: dc.getDecorationImage(
                                          dc.hostAgencyWithdrawBtnImage,
                                          fit: BoxFit.fill,
                                        ),
                                        color: dc.hostAgencyWithdrawBtnImage.isNotEmpty ? null : Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.15),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        _isAgencyOwner ? (isAr ? 'السحب' : 'Withdraw') : (isAr ? 'سحب الراتب ككوينز' : 'Withdraw Salary'),
                                        style: TextStyle(
                                          color: dc.hostAgencyWithdrawBtnImage.isNotEmpty ? Colors.white : const Color(0xFF00B5B3),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // خط فاصل عمودي (Guideline 72%)
                            Container(
                              width: 1,
                              height: 90,
                              color: Colors.white.withOpacity(0.35),
                              margin: const EdgeInsets.symmetric(horizontal: 10),
                            ),

                            // القسم الأيمن: المسحوب والمتبقي
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isAr ? 'المسحوب' : 'Overdrawn',
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '\$${_isAgencyOwner ? (info?.transferDollar ?? 0) : 0} USD',
                                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    isAr ? 'المتبقي' : 'Remaining',
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _isAgencyOwner ? '\$$agencyDollar USD' : '\$$hostDollar USD',
                                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                ],
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

            // للمضيف: شريط ساعات البث الصالحة (vh_agency_member_salary.xml)
            if (!_isAgencyOwner) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  image: dc.getDecorationImage(
                    dc.hostsHoursCardBgImage,
                    fit: BoxFit.cover,
                  ),
                  color: dc.hostsHoursCardBgImage.isNotEmpty ? null : dc.hostsCardColor,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '>=2H(day): ',
                          style: TextStyle(color: Color(0xFF222222), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '$hostValidDays2h ${isAr ? 'يوم' : 'd'}',
                          style: const TextStyle(color: Color(0xFF00B5B3), fontSize: 13, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    Container(width: 1, height: 16, color: Colors.black12),
                    Row(
                      children: [
                        const Text(
                          '>=4H(day): ',
                          style: TextStyle(color: Color(0xFF222222), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '$hostValidDays4h ${isAr ? 'يوم' : 'd'}',
                          style: const TextStyle(color: Color(0xFF00B5B3), fontSize: 13, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    Container(width: 1, height: 16, color: Colors.black12),
                    Row(
                      children: [
                        const Text(
                          '>=6H(day): ',
                          style: TextStyle(color: Color(0xFF222222), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '$hostValidDays6h ${isAr ? 'يوم' : 'd'}',
                          style: const TextStyle(color: Color(0xFF00B5B3), fontSize: 13, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 18),

            // ── Target Progress Card ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1B2230),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x3300B5B3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.track_changes, size: 18, color: Color(0xFF00B5B3)),
                          const SizedBox(width: 6),
                          Text(
                            _isAgencyOwner
                                ? (isAr ? 'الهدف الشهري للوكالة' : 'Monthly Target')
                                : (isAr ? 'مستوى تقدمي في المرحلة والتارجت' : 'My Stage & Target Progress'),
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0x3300B5B3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          currentStageLabel,
                          style: const TextStyle(color: Color(0xFF00B5B3), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF00B5B3)),
                      minHeight: 10,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$effectiveDiamonds / $targetDiamonds 💎',
                        style: const TextStyle(color: Color(0xFF00B5B3), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        isAr ? 'تم إنجاز $percent%' : '$percent% done',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Milestones Ladder Button ──
            InkWell(
              onTap: () => _showMilestonesSheet(info, isAr),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF332A15), Color(0xFF221F1C)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x44FFD700)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.military_tech, color: Color(0xFFFFD700), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr ? 'سلّم المراحل والتارجت والرواتب' : 'Milestones & Salary Ladder',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isAr
                                ? 'اضغط لعرض كافة المراحل، نسب العمولة، ومكافآت كل مرحلة'
                                : 'Tap to view all tiers, commission rates & salaries',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFFFFD700)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Section Title: تقارير الدخل المفصلة (union_adapter_agency_detail_header.xml) ──
            Align(
              alignment: isAr ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                isAr ? 'تقارير أرباح الوكالة حسب الفترات' : 'Detailed Period Earnings',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // بطاقة هذا الشهر
            _buildPeriodItem(
              title: isAr ? 'هذا الشهر' : 'This Month',
              diamonds: transferMoney,
              rate: commRatePct,
              isAr: isAr,
            ),
            // بطاقة هذا الأسبوع
            _buildPeriodItem(
              title: isAr ? 'هذا الأسبوع' : 'This Week',
              diamonds: (transferMoney * 0.35).toInt(),
              rate: commRatePct,
              isAr: isAr,
            ),
            // بطاقة أمس
            _buildPeriodItem(
              title: isAr ? 'أمس' : 'Yesterday',
              diamonds: (transferMoney * 0.05).toInt(),
              rate: commRatePct,
              isAr: isAr,
            ),
            // بطاقة اليوم
            _buildPeriodItem(
              title: isAr ? 'اليوم' : 'Today',
              diamonds: (transferMoney * 0.04).toInt(),
              rate: commRatePct,
              isAr: isAr,
            ),
          ],
        ),
      ),
    );
  }

  /// Period Item Card matching union_agency_item_bg & union_adapter_agency_detail_header.xml
  Widget _buildPeriodItem({
    required String title,
    required int diamonds,
    required int rate,
    required bool isAr,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AgencyItemDetailScreen(
              agencyId: _agentInfo?.agencyId ?? widget.agencyId ?? '',
              agencyName: _agentInfo?.agencyName ?? '',
              periodTitle: title,
              totalDiamonds: diamonds,
              commissionRate: _agentInfo?.commissionRate ?? 0.10,
              members: _anchors.map((a) => {
                'id': a.uid,
                'nickname': a.nickname,
                'avatar_url': a.avatarUrl,
                'user_id': a.userId,
                'diamonds_earned_monthly': int.tryParse(a.totalDiamond) ?? 0,
                'live_seconds': (a.minute * 60).toInt(),
              }).toList(),
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          image: const DecorationImage(
            image: AssetImage(R.unionAgencyItemBg),
            fit: BoxFit.fill,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                Image.asset(
                  R.commonNext3Ic,
                  width: 20,
                  height: 20,
                  errorBuilder: (_, __, ___) => const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 14),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Image.asset(R.commonDiamondIc, width: 16, height: 16, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                          const SizedBox(width: 6),
                          Text(
                            diamonds.toString(),
                            style: const TextStyle(color: Color(0xFFFFF5AD), fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isAr ? 'دخل الألماس' : 'Diamond Income',
                        style: const TextStyle(color: Color(0x80FFF5AD), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Image.asset(R.unionRate1Ic, width: 16, height: 16, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                          const SizedBox(width: 6),
                          Text(
                            '$rate %',
                            style: const TextStyle(color: Color(0xFFFFF5AD), fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isAr ? 'نسبة العمولة' : 'Commission Rate',
                        style: const TextStyle(color: Color(0x80FFF5AD), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Milestones Bottom Sheet
  void _showMilestonesSheet(AgentInfoModel? info, bool isAr) {
    final milestones = info?.milestones ?? [];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E24),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.military_tech, color: Color(0xFFFFD700), size: 22),
                    const SizedBox(width: 8),
                    Text(
                      isAr ? 'سلّم المراحل والتارجت والمكافآت' : 'Milestones & Targets',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isAr
                  ? 'يتم تحديد عمولة الوكيل والراتب بناءً على المرحلة التي يحققها المضيفون'
                  : 'Agency commission and salary are based on active host stages',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 14),
            const Divider(color: Colors.white12),
            Expanded(
              child: milestones.isEmpty
                  ? Center(
                      child: Text(
                        isAr ? 'لم تتم إضافة مراحل بعد من لوحة التحكم' : 'No milestones configured yet',
                        style: const TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      itemCount: milestones.length,
                      itemBuilder: (ctx, i) {
                        final m = milestones[i];
                        final title = m['title']?.toString() ?? '${isAr ? 'المرحلة' : 'Stage'} ${i + 1}';
                        final targetDiamonds = (m['target_diamonds'] as num?)?.toInt() ?? 0;
                        final comm = (m['agent_commission_rate'] as num?)?.toDouble() ?? 0.10;
                        final commPct = (comm * 100).toInt();
                        final rewardVal = (m['reward_value'] as num?)?.toDouble() ?? 0.0;
                        final rewardType = m['reward_type']?.toString() ?? 'salary_usd';
                        final period = m['period_type']?.toString() ?? 'monthly';
                        final isDone = (info?.transferMoney ?? 0) >= targetDiamonds && targetDiamonds > 0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDone ? const Color(0x224CAF50) : const Color(0xFF282830),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDone ? const Color(0x554CAF50) : const Color(0x1AFFFFFF),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: isDone ? const Color(0xFF4CAF50) : const Color(0x22FFD700),
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    color: isDone ? Colors.white : const Color(0xFFFFD700),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                        ),
                                        if (isDone) ...[
                                          const SizedBox(width: 6),
                                          const Icon(Icons.check_circle, size: 14, color: Color(0xFF4CAF50)),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${isAr ? 'الهدف:' : 'Target:'} $targetDiamonds 💎 • ${isAr ? 'العمولة:' : 'Commission:'} $commPct%',
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                    if (rewardVal > 0) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        rewardType == 'salary_usd'
                                            ? '${isAr ? 'الراتب:' : 'Salary:'} \$$rewardVal USD ($period)'
                                            : '${isAr ? 'المكافأة:' : 'Reward:'} $rewardVal ($rewardType)',
                                        style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tab 3: Invite Hosts (دعوة مضيف برقم الآيدي والاسم والصورة وإرسال الإشعار)
  Widget _buildInviteHostsTab(bool isAr) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Welcome / Info Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2C2415), Color(0xFF1E1A17)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFFFFD700), size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAr ? 'دعوة مستخدم للانضمام كمضيف' : 'Invite User to Agency',
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isAr
                              ? 'أدخل آيدي المستخدم للبحث عنه، ثم اضغط لإرسال دعوة انضمام مباشرة لإشعاراته.'
                              : 'Enter user ID to search, then send an invitation notification.',
                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Search Bar by ID
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF242424),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.search, color: Color(0xFFFFD700), size: 22),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _inviteSearchCtrl,
                      keyboardType: TextInputType.text,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: isAr ? 'أدخل آيدي المستخدم (ID) مثلاً: 12345' : 'Enter User ID (e.g. 12345)',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _searchUserToInvite(isAr),
                    ),
                  ),
                  if (_inviteSearching)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFD700)),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ElevatedButton(
                        onPressed: () => _searchUserToInvite(isAr),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD700),
                          foregroundColor: const Color(0xFF1A1A1A),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        child: Text(isAr ? 'بحث' : 'Search', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Error or Success message
            if (_inviteError != null && _inviteError!.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5252).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFFF5252), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_inviteError!, style: const TextStyle(color: Color(0xFFFF5252), fontSize: 12)),
                    ),
                  ],
                ),
              ),

            if (_inviteSuccess != null && _inviteSuccess!.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Color(0xFF4CAF50), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_inviteSuccess!, style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 12)),
                    ),
                  ],
                ),
              ),

            // Found User Card
            if (_foundUser != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF24242A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.5)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.white12,
                          backgroundImage: (_foundUser!['avatar']?.toString().isNotEmpty ?? false)
                              ? R.cachedImage(_foundUser!['avatar'].toString())
                              : null,
                          child: (_foundUser!['avatar']?.toString().isEmpty ?? true)
                              ? const Icon(Icons.person, color: Colors.white54, size: 30)
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _foundUser!['name']?.toString() ?? (isAr ? 'مستخدم' : 'User'),
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'ID: ${_foundUser!['custom_id'] ?? _foundUser!['user_id'] ?? ''}',
                                style: const TextStyle(color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              if (_foundUser!['level'] != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Level ${_foundUser!['level']}',
                                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _inviteSending ? null : () => _sendHostInvite(isAr),
                        icon: _inviteSending
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A1A1A)))
                            : const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          isAr ? 'إرسال دعوة انضمام للوكالة 📨' : 'Send Agency Invitation 📨',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD700),
                          foregroundColor: const Color(0xFF1A1A1A),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _searchUserToInvite(bool isAr) async {
    final query = _inviteSearchCtrl.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _inviteSearching = true;
      _inviteError = null;
      _inviteSuccess = null;
      _foundUser = null;
    });

    try {
      // 1. Supabase search
      UserModel? supaUser;
      try {
        supaUser = await SupabaseDataService().findUserByIdOrCustomId(query);
      } catch (_) {}

      if (supaUser != null && supaUser.uid.isNotEmpty) {
        _foundUser = {
          'uid': supaUser.uid,
          'name': supaUser.name.isNotEmpty ? supaUser.name : (isAr ? 'مستخدم' : 'User'),
          'avatar': supaUser.photoUrl,
          'custom_id': supaUser.customId.isNotEmpty ? supaUser.customId : query,
          'level': supaUser.level,
          'country': supaUser.country,
        };
      }

      if (_foundUser == null) {
        _inviteError = isAr ? 'لم يتم العثور على أي مستخدم بهذا الرقم (ID)' : 'No user found with this ID';
      }
    } catch (e) {
      _inviteError = isAr ? 'حدث خطأ أثناء البحث عن المستخدم' : 'Error searching user';
    } finally {
      if (mounted) setState(() => _inviteSearching = false);
    }
  }

  Future<void> _sendHostInvite(bool isAr) async {
    if (_foundUser == null) return;
    final targetUid = _foundUser!['uid']?.toString() ?? '';
    final targetName = _foundUser!['name']?.toString() ?? (isAr ? 'مستخدم' : 'User');
    final targetId = _foundUser!['custom_id']?.toString() ?? '';
    final agencyId = _agentInfo?.agencyId ?? widget.agencyId ?? '';
    final agencyName = _agentInfo?.agencyName ?? 'الوكالة الرسمية';

    if (targetUid.isEmpty || agencyId.isEmpty) return;

    // Check if already in agency
    final isAlreadyMember = _anchors.any((a) => a.uid == targetUid || (targetId.isNotEmpty && a.userId.toString() == targetId));
    if (isAlreadyMember) {
      setState(() {
        _inviteError = isAr ? 'هذا المستخدم عضو بالفعل في وكالتك!' : 'User is already a member of your agency!';
      });
      return;
    }

    setState(() {
      _inviteSending = true;
      _inviteError = null;
      _inviteSuccess = null;
    });

    try {
      // 1. Try AgencyChatRepository invitation flow first
      if (targetId.isNotEmpty) {
        try {
          final res = await AgencyChatRepository.inviteByKayanId(
            agencyId: agencyId,
            kayanId: targetId,
          );
          if (res['status'] == 'invited' || res['status'] == 'already_invited') {
            setState(() {
              _inviteSuccess = isAr
                  ? 'تم إرسال دعوة الانضمام إلى [$targetName] بنجاح! سينضم لوكالتك فور قبوله للدعوة.'
                  : 'Invitation sent to [$targetName] successfully! They will join once accepted.';
              _foundUser = null;
              _inviteSearchCtrl.clear();
            });
            return;
          }
        } catch (_) {}
      }

      // 2. Fallback: Supabase direct upsert to host_agency_join_requests
      final reqId = const Uuid().v4();
      final nowIso = DateTime.now().toUtc().toIso8601String();
      try {
        await Supabase.instance.client.from('host_agency_join_requests').upsert({
          'id': reqId,
          'agency_id': agencyId,
          'user_id': targetUid,
          'host_uid': targetUid,
          'applicant_uid': targetUid,
          'status': 'invited',
          'created_at': nowIso,
        });
      } catch (sbErr) {
        debugPrint('[AnchorAgentScreen] Supabase host_agency_join_requests insert error: $sbErr');
      }



      // 5. Supabase notifications fallback
      try {
        await SupabaseDataService().sendNotification(
          uid: targetUid,
          type: 'host_invite',
          title: isAr ? 'دعوة انضمام لوكالة مضيفين 🎙️' : 'Host Agency Invitation 🎙️',
          body: isAr
              ? 'تمت دعوتك من قِبل وكالة [$agencyName] للانضمام كمضيف رسمي.'
              : 'You have been invited by agency [$agencyName] to join as an official host.',
          data: {
            'agency_id': agencyId,
            'agency_name': agencyName,
          },
        );
      } catch (_) {}

      setState(() {
        _inviteSuccess = isAr
            ? 'تم إرسال دعوة الانضمام إلى [$targetName] بنجاح! سينضم لوكالتك فور قبوله للدعوة.'
            : 'Invitation sent to [$targetName] successfully! They will join once accepted.';
        _foundUser = null;
        _inviteSearchCtrl.clear();
      });
    } catch (e) {
      debugPrint('[AnchorAgentScreen] _sendHostInvite error: $e');
      setState(() {
        _inviteError = isAr ? 'فشل إرسال الدعوة، يرجى المحاولة لاحقاً' : 'Failed to send invite, try again later';
      });
    } finally {
      if (mounted) setState(() => _inviteSending = false);
    }
  }

  /// Announcement Dialog with Edit Capability
  void _showNoticeDialog(bool isAr) {
    final textCtrl = TextEditingController(text: _noticeText);
    bool editing = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: const Color(0xFF24242A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isAr ? 'إعلان الوكالة' : 'Agency Notice',
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    if (_isAgencyOwner)
                      IconButton(
                        icon: Icon(editing ? Icons.close : Icons.edit, color: const Color(0xFFFFD700), size: 20),
                        tooltip: isAr ? 'تعديل الإعلان' : 'Edit Notice',
                        onPressed: () {
                          setDialogState(() => editing = !editing);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (!editing)
                  Text(
                    _noticeText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFD4D6E5), fontSize: 14, height: 1.4),
                  )
                else
                  TextField(
                    controller: textCtrl,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF1E1E24),
                      hintText: isAr ? 'اكتب إعلان الوكالة هنا...' : 'Type agency announcement...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                const SizedBox(height: 20),
                const Divider(color: Color(0xFF454658), height: 1),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          isAr ? 'إغلاق' : 'Close',
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ),
                    ),
                    if (editing)
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFD700),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () async {
                            final newNotice = textCtrl.text.trim();
                            if (newNotice.isNotEmpty) {
                              final agencyId = _agentInfo?.agencyId ?? widget.agencyId ?? '';
                              if (agencyId.isNotEmpty) {
                                await SupabaseService().updateAgencyNotice(agencyId: agencyId, notice: newNotice);
                              }
                              setState(() => _noticeText = newNotice);
                            }
                            Navigator.pop(ctx);
                          },
                          child: Text(
                            isAr ? 'حفظ الإعلان' : 'Save',
                            style: const TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Rules Dialog matching union_activity_rule.xml
  void _showRulesDialog(bool isAr) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF24242A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isAr ? 'قواعد وإرشادات الوكالة' : 'Agency Rules',
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              const Text(
                '1. يجب على المضيفين البث لمدة لا تقل عن 20 ساعة أسبوعياً.\n2. تحسب العمولات نهاية كل شهر ميلادي.\n3. يمنع منعاً باتاً نقل المضيفين بين الوكالات دون موافقة الإدارة.\n4. التحويلات تتم بالماس المعتمد فقط.',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text(isAr ? 'فهمت ذلك' : 'Understood', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// نافذة تحويل الراتب إلى وكيل الشحن للمضيف
  void _openTransferSalaryToAgentModal(int availableDiamonds, bool isAr) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => _HostTransferSalaryModal(
        agencyId: _agentInfo?.agencyId ?? widget.agencyId ?? '',
        availableDiamonds: availableDiamonds,
        isAr: isAr,
        onSuccess: () {
          _loadAgencyData(silent: true);
        },
      ),
    );
  }

  /// Invite dialog
  void _showInviteDialog(bool isAr) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF24242A),
        title: Text(isAr ? 'دعوة وكيل فرعي' : 'Invite Sub-agent', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          isAr ? 'شارك كود الوكالة الخاص بك مع الوكيل الجديد للانضمام تحت إدارتك.' : 'Share your agency code to invite sub-agents.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isAr ? 'إغلاق' : 'Close', style: const TextStyle(color: Color(0xFFFFD700))),
          ),
        ],
      ),
    );
  }

  /// 1. بطاقة معلومات الوكالة العلوية (Header Card)
  Widget _buildAgencyHeaderCard() {
    final info = _agentInfo;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E26),
        borderRadius: BorderRadius.circular(16),
        image: const DecorationImage(
          image: AssetImage('assets/images/bg_anchor_agent_info.png'),
          fit: BoxFit.cover,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        children: [
          // شارة عنوان بطاقة الوكالة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFB74D), Color(0xFFFFA726)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'معلومات الوكالة',
              style: TextStyle(
                color: Color(0xFF211211),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // صورة الوكيل
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFFD700), width: 2),
                  image: (info?.avatarUrl.isNotEmpty ?? false)
                      ? DecorationImage(
                          image: R.cachedImage(info!.avatarUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: (info?.avatarUrl.isEmpty ?? true)
                    ? const Icon(Icons.person, color: Colors.white70, size: 28)
                    : null,
              ),
              const SizedBox(width: 12),
              // اسم الوكالة ومعرف الوكيل
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (info?.countryFlagUrl.isNotEmpty ?? false)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Image.network(info!.countryFlagUrl, width: 18, height: 12),
                          ),
                        Expanded(
                          child: Text(
                            info?.agencyName.isNotEmpty ?? false
                                ? info!.agencyName
                                : 'وكالة النجوم المعتمدة',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID الوكيل: ${info?.userId ?? 0}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      'إجمالي المضيفين: ${_anchors.length} مضيف',
                      style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 10),
          // إحصائيات الأرباح والتحويلات
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('الماسات المكتسبة 💎', R.formatCoins(info?.transferMoney ?? 0)),
              Container(width: 1, height: 24, color: Colors.white12),
              _buildStatItem('قيمة الأرباح المستحقة', '\$${info?.transferDollar ?? 0} USD'),
              Container(width: 1, height: 24, color: Colors.white12),
              _buildStatItem('رصيد الكوينز 🪙', R.formatCoins(info?.agentBean ?? 0)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFFBD98C),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 10),
        ),
      ],
    );
  }

  /// 2. قسم جدول المضيفين (3 أعمدة متناسقة)
  Widget _buildAnchorsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // عنوان القسم
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/icon_title_bg.png'),
                  fit: BoxFit.fill,
                ),
              ),
              child: const Text(
                'جميع المضيفين',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // شريط عناوين الأعمدة الثلاثة
          Row(
            children: [
              Expanded(child: _buildColumnTabHeader('assets/images/icon_tab_one.png', 'بيانات المضيف')),
              Expanded(child: _buildColumnTabHeader('assets/images/icon_tab_two.png', 'وقت المايك')),
              Expanded(child: _buildColumnTabHeader('assets/images/icon_tab_three.png', 'تارجت الذهب')),
            ],
          ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          // قائمة المضيفين
          if (_anchors.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: const [
                  Icon(Icons.people_outline, size: 48, color: Colors.black26),
                  SizedBox(height: 8),
                  Text('لا يوجد مضيفين منضمين للوكالة بعد', style: TextStyle(color: Colors.black45, fontSize: 13)),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _anchors.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF2F2F2)),
              itemBuilder: (context, index) => _buildAnchorItemRow(_anchors[index]),
            ),
        ],
      ),
    );
  }

  Widget _buildColumnTabHeader(String bgAsset, String title) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(bgAsset),
          fit: BoxFit.fill,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF333333),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// سطر بيانات المضيف المطابق لـ `item_anchor_info_data.xml`
  Widget _buildAnchorItemRow(AnchorAgentUserInfoDataModel anchor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        children: [
          // العمود 1: بيانات المضيف (الصورة + الاسم + المعرف)
          Expanded(
            flex: 4,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: anchor.headImage.isNotEmpty
                      ? R.cachedImage(anchor.headImage)
                      : null,
                  child: anchor.headImage.isEmpty
                      ? const Icon(Icons.person, size: 20, color: Colors.white70)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              anchor.nickname,
                              style: const TextStyle(
                                color: Color(0xFF333333),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (anchor.vip > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFFD700), Color(0xFFFF9900)],
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'VIP${anchor.vip}',
                                style: const TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ID: ${anchor.userNo > 0 ? anchor.userNo : anchor.userId}',
                        style: const TextStyle(color: Color(0xFF888888), fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // العمود 2: وقت التواجد على المايك
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  anchor.formattedTime,
                  style: const TextStyle(
                    color: Color(0xFF333333),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          // العمود 3: تارجت الذهب والماسات
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${R.formatCoins(int.tryParse(anchor.diamonds) ?? 0)} 💎',
                  style: const TextStyle(
                    color: Color(0xFFDE880F),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: anchor.targetProgress,
                    minHeight: 4,
                    backgroundColor: const Color(0xFFEEEEEE),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFFDE880F)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  نافذة تحويل الراتب إلى وكيل الشحن للمضيف (_HostTransferSalaryModal)
// ═══════════════════════════════════════════════════════════════════
class _HostTransferSalaryModal extends StatefulWidget {
  final String agencyId;
  final int availableDiamonds;
  final bool isAr;
  final VoidCallback onSuccess;

  const _HostTransferSalaryModal({
    required this.agencyId,
    required this.availableDiamonds,
    required this.isAr,
    required this.onSuccess,
  });

  @override
  State<_HostTransferSalaryModal> createState() => _HostTransferSalaryModalState();
}

class _HostTransferSalaryModalState extends State<_HostTransferSalaryModal> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _diamondsCtrl = TextEditingController();

  List<Map<String, dynamic>> _searchResults = [];
  Map<String, dynamic>? _selectedAgent;
  bool _searching = false;
  bool _submitting = false;
  Timer? _debounce;
  int _diamonds = 0;

  final List<int> _quickTargets = [100000, 300000, 500000, 1000000, 2000000, 5000000];

  @override
  void dispose() {
    _searchCtrl.dispose();
    _diamondsCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _doSearch(query));
  }

  Future<void> _doSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      if (mounted) setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await AgencyRepository.searchRechargeAgents(q);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectQuickTarget(int amount) {
    setState(() {
      _diamonds = amount;
      _diamondsCtrl.text = amount.toString();
    });
  }

  Future<void> _handleTransfer() async {
    final isAr = widget.isAr;
    if (_selectedAgent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isAr ? 'يرجى اختيار وكيل الشحن أولاً' : 'Please select a recharge agent first'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_diamonds <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isAr ? 'يرجى إدخال أو تحديد كمية الألماس المراد تحويلها' : 'Please enter valid diamond amount'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_diamonds > widget.availableDiamonds) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isAr ? 'رصيد الألماس المتاح لديك لا يكفي (${widget.availableDiamonds} 💎)' : 'Insufficient diamond balance (${widget.availableDiamonds} 💎)'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final agentName = _selectedAgent!['display_name']?.toString() ?? 'وكيل الشحن';
    final agentKayanId = _selectedAgent!['kayan_id']?.toString() ?? _selectedAgent!['id']?.toString() ?? '';

    // تأكيد العملية
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.send_rounded, color: Color(0xFF00D4FF), size: 24),
            const SizedBox(width: 8),
            Text(
              isAr ? 'تأكيد تحويل الراتب' : 'Confirm Salary Transfer',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAr
                  ? 'هل أنت متأكد من تحويل $_diamonds ماسة إلى وكيل الشحن؟'
                  : 'Are you sure you want to transfer $_diamonds diamonds to recharge agent?',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x2200D4FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x4400D4FF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${isAr ? 'اسم الوكيل:' : 'Agent:'} $agentName',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${isAr ? 'آيدي الوكيل (ID):' : 'Agent ID:'} $agentKayanId',
                    style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${isAr ? 'الكمية المحولة كوينز فوراً:' : 'Coins credited:'} $_diamonds 🪙',
                    style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isAr
                  ? '⚡ ستصل الكوينز فوراً لمحفظة وكيل الشحن مع إشعار رسمي ببياناتك كمرسل.'
                  : '⚡ Coins will be credited to agent instantly with notification of your ID and Name.',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'إلغاء' : 'Cancel', style: const TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D4FF),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? 'تأكيد وإرسال' : 'Confirm & Send', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _submitting = true);
    try {
      final user = Provider.of<UserProvider>(context, listen: false).currentUser;
      final uid = user?.uid ?? Supabase.instance.client.auth.currentUser?.id ?? '';
      final agentId = _selectedAgent!['id']?.toString() ?? _selectedAgent!['uid']?.toString() ?? '';
      final idempotencyKey = '${uid}_host_txfr_${DateTime.now().millisecondsSinceEpoch}';

      final res = await AgencyRepository.transferDiamondsToAgentWallet(
        agentId: agentId,
        diamonds: _diamonds,
        idempotencyKey: idempotencyKey,
        source: 'host',
      );

      if (res['status'] == 'ok' || res['ok'] == true || res['success'] == true) {
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAr
                  ? '✅ تم تحويل $_diamonds ماسة بنجاح إلى وكيل الشحن [$agentName] وتم إشعاره فوراً!'
                  : '✅ Successfully transferred $_diamonds diamonds to $agentName!',
            ),
            backgroundColor: const Color(0xFF00C853),
          ),
        );
        widget.onSuccess();
      } else {
        if (!mounted) return;
        final msg = res['message']?.toString() ?? res['error']?.toString() ?? (isAr ? 'فشل تحويل الراتب' : 'Transfer failed');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${isAr ? 'خطأ:' : 'Error:'} $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        decoration: const BoxDecoration(
          color: Color(0xFF161622),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 14,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Title Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0x3300D4FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.currency_exchange_rounded, color: Color(0xFF00D4FF), size: 22),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr ? 'تحويل الراتب إلى وكيل الشحن' : 'Transfer Salary to Recharge Agent',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            isAr ? 'تحويل فوري من ألماس المضيف إلى كوينز الوكيل' : 'Instant host diamonds to agent coins',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Balance card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF222230),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x33FFD700)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Image.asset(R.commonDiamondIc, width: 18, height: 18, errorBuilder: (_, __, ___) => const Icon(Icons.diamond, size: 18, color: Color(0xFFFFD700))),
                        const SizedBox(width: 8),
                        Text(
                          isAr ? 'رصيدك المتاح للتحويل:' : 'Your available balance:',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                    Text(
                      '${widget.availableDiamonds} 💎',
                      style: const TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Search Agent Input
              Text(
                isAr ? '1. البحث عن وكيل الشحن (بالآيدي أو الاسم):' : '1. Search Recharge Agent (by ID or Name):',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF222230),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x33FFFFFF)),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: isAr ? 'أدخل آيدي الوكيل (ID) أو اسمه...' : 'Enter Agent ID or Name...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF00D4FF), size: 20),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00D4FF))),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),

              // Search Results List
              if (_searchResults.isNotEmpty && _selectedAgent == null) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E28),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x3300D4FF)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
                    itemBuilder: (ctx, i) {
                      final item = _searchResults[i];
                      final name = item['display_name']?.toString() ?? 'وكيل معتمد';
                      final cid = item['kayan_id']?.toString() ?? item['id']?.toString() ?? '';
                      final avatar = item['avatar_url']?.toString() ?? '';

                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFF00D4FF).withOpacity(0.2),
                          backgroundImage: avatar.isNotEmpty ? R.cachedImage(avatar) : null,
                          child: avatar.isEmpty ? const Icon(Icons.person, color: Color(0xFF00D4FF), size: 16) : null,
                        ),
                        title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: Text('ID: $cid', style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 11)),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white54),
                        onTap: () {
                          setState(() {
                            _selectedAgent = item;
                            _searchCtrl.text = name;
                            _searchResults = [];
                          });
                        },
                      );
                    },
                  ),
                ),
              ],

              // Selected Agent Card
              if (_selectedAgent != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x1F00D4FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF00D4FF)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFF00D4FF).withOpacity(0.2),
                        backgroundImage: (_selectedAgent!['avatar_url']?.toString() ?? '').isNotEmpty
                            ? R.cachedImage(_selectedAgent!['avatar_url'].toString())
                            : null,
                        child: (_selectedAgent!['avatar_url']?.toString() ?? '').isEmpty
                            ? const Icon(Icons.person, color: Color(0xFF00D4FF), size: 20)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _selectedAgent!['display_name']?.toString() ?? 'وكيل الشحن',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0x3300D4FF),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isAr ? 'وكيل معتمد' : 'Verified Agent',
                                    style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ID: ${_selectedAgent!['kayan_id'] ?? _selectedAgent!['id']}',
                              style: const TextStyle(color: Colors.white60, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                        onPressed: () {
                          setState(() {
                            _selectedAgent = null;
                            _searchCtrl.clear();
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),

              // Stage / Quick Target Selection
              Text(
                isAr ? '2. تحديد التارجت أو المرحلة الخاصة بك:' : '2. Select Your Milestone Stage or Target:',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _quickTargets.map((target) {
                  final isSelected = _diamonds == target;
                  final stageLabel = _getAnchorStage(target.toString(), isAr);
                  return GestureDetector(
                    onTap: () => _selectQuickTarget(target),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF00D4FF) : const Color(0xFF222230),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF00D4FF) : const Color(0x33FFFFFF),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            stageLabel,
                            style: TextStyle(
                              color: isSelected ? Colors.black : const Color(0xFFFFD700),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '$target 💎',
                            style: TextStyle(
                              color: isSelected ? Colors.black : Colors.white70,
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Custom Diamond Input
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF222230),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x33FFFFFF)),
                ),
                child: TextField(
                  controller: _diamondsCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: isAr ? 'أو أدخل كمية الماس مخصصة...' : 'Or enter custom diamond amount...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                    prefixIcon: Image.asset(R.commonDiamondIc, width: 16, height: 16, errorBuilder: (_, __, ___) => const Icon(Icons.diamond, color: Color(0xFFFFD700))),
                    suffixText: isAr ? 'ماسة' : 'diamonds',
                    suffixStyle: const TextStyle(color: Color(0xFFFFD700), fontSize: 12),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onChanged: (v) {
                    setState(() => _diamonds = int.tryParse(v) ?? 0);
                  },
                ),
              ),
              const SizedBox(height: 20),

              // Submit Button
              ElevatedButton(
                onPressed: _submitting ? null : _handleTransfer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D4FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                child: _submitting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.send_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            isAr ? 'إرسال الراتب إلى وكيل الشحن فوراً ⚡' : 'Transfer Salary to Agent Now ⚡',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getAnchorStage(String diamondsStr, bool isAr) {
    final d = double.tryParse(diamondsStr) ?? 0.0;
    if (d >= 5000000) return isAr ? 'المرحلة 7' : 'Stage 7';
    if (d >= 2000000) return isAr ? 'المرحلة 6' : 'Stage 6';
    if (d >= 1000000) return isAr ? 'المرحلة 5' : 'Stage 5';
    if (d >= 500000) return isAr ? 'المرحلة 4' : 'Stage 4';
    if (d >= 300000) return isAr ? 'المرحلة 3' : 'Stage 3';
    if (d >= 100000) return isAr ? 'المرحلة 2' : 'Stage 2';
    return isAr ? 'المرحلة 1' : 'Stage 1';
  }
}
