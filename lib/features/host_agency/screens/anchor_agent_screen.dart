import 'package:firebase_core/firebase_core.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/r.dart';
import '../../../../models/user_model.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/supabase_service.dart';
import '../../../../services/supabase_data_service.dart';
import '../data/anchor_agent_model.dart';
import 'agency_exit_screen.dart';
import 'agency_invite_by_id_screen.dart';
import 'agency_item_detail_screen.dart';
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
    _membersSub = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
        .collection('host_agency_members')
        .where('agency_id', isEqualTo: aid)
        .snapshots()
        .listen((_) => _scheduleReload());

    _agencySub?.cancel();
    _agencySub = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
        .collection('host_agencies')
        .doc(aid)
        .snapshots()
        .listen((_) => _scheduleReload());
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

      if (mounted) {
        setState(() {
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
          _anchors = (data['anchors'] as List<dynamic>?)
                  ?.map((e) => AnchorAgentUserInfoDataModel.fromJson(e as Map<String, dynamic>))
                  .toList() ??
              [];
          _loading = false;
        });

        final aid = _agentInfo?.agencyId ?? widget.agencyId;
        if (aid != null && aid.isNotEmpty && _membersSub == null) {
          _listenRealtime(aid);
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
          else
            _buildInviteHostsTab(isAr),

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

  /// Collapsing Header matching union_activity_my_agency.xml
  Widget _buildCollapsingHeader(AgentInfoModel? info, bool isAr) {
    final dc = DynamicConfigService();
    final agencyName = info?.agencyName.isNotEmpty == true ? info!.agencyName : (isAr ? 'وكالتي الرسمية' : 'My Agency');
    final agencyId = info?.userId.toString() ?? '10001';
    final memberCount = _anchors.length;

    return Stack(
      children: [
        // Background: union_my_agency_bg
        Positioned.fill(
          child: dc.hostAgencyHeaderBgImage.isNotEmpty
              ? (dc.hostAgencyHeaderBgImage.startsWith('http')
                  ? Image.network(dc.hostAgencyHeaderBgImage, fit: BoxFit.cover)
                  : Image.asset(dc.hostAgencyHeaderBgImage, fit: BoxFit.cover))
              : Image.asset(
                  R.unionMyAgencyBg,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: const Color(0xFF221A1A)),
                ),
        ),

        SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Top Action Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: Image.asset(
                        'assets/mipmap-xxhdpi/back_white_2.webp',
                        width: 28,
                        height: 28,
                        errorBuilder: (_, __, ___) => const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Text(
                      isAr ? 'وكالتي' : 'My Agency',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // Rules icon: union_rule_ic
                    IconButton(
                      icon: Image.asset(
                        R.unionRuleIc,
                        width: 26,
                        height: 26,
                        errorBuilder: (_, __, ___) => const Icon(Icons.help_outline, color: Colors.white),
                      ),
                      tooltip: isAr ? 'قوانين الوكالة' : 'Rules',
                      onPressed: () => _showRulesDialog(isAr),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Agency Avatar Stack: union_my_agency_avatar_bg + crown + avatar + border
              Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // Avatar base frame: union_my_agency_avatar_bg
                    Image.asset(
                      R.unionMyAgencyAvatarBg,
                      width: 130,
                      height: 130,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox(width: 130, height: 130),
                    ),

                    // Crown: union_agency_avatar_heder_ic
                    Positioned(
                      top: -10,
                      child: Image.asset(
                        R.unionAgencyAvatarHeaderIc,
                        width: 44,
                        height: 36,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),

                    // Agency Avatar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        width: 84,
                        height: 84,
                        color: Colors.white12,
                        child: (info?.avatarUrl.isNotEmpty == true)
                            ? Image(
                                image: R.cachedImage(info!.avatarUrl),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.shield, color: Colors.white54, size: 40),
                              )
                            : const Icon(Icons.shield, color: Colors.white54, size: 40),
                      ),
                    ),

                    // Border: union_avatar_border_ic
                    Image.asset(
                      R.unionAvatarBorderIc,
                      width: 90,
                      height: 90,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),

                    // Invite Host Badge: union_sub_agent_invite_bg
                    Positioned(
                      bottom: -10,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _currentTab = 2);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            image: const DecorationImage(
                              image: AssetImage(R.unionSubAgentInviteBg),
                              fit: BoxFit.fill,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(R.unionSubAgentInviteIc, width: 16, height: 16, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                              const SizedBox(width: 4),
                              Text(
                                isAr ? 'دعوة مضيف' : 'Invite Host',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Agency Name + Country
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (info?.countryFlagUrl.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Image.network(info!.countryFlagUrl, width: 22, height: 14),
                    ),
                  Text(
                    agencyName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 4),

              // Agency ID with union_id_ic
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(R.unionIdIc, width: 14, height: 14, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                  const SizedBox(width: 4),
                  Text(
                    'ID: $agencyId',
                    style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 12),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ── Stats Bar: cl_rank_detail (union_agency_info_bg) ──
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0x33000000),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x22FFFFFF)),
                ),
                child: Row(
                  children: [
                    // Rank
                    Expanded(
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(R.unionAgencyRank1Ic, width: 16, height: 16, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                              const SizedBox(width: 4),
                              Text(
                                isAr ? 'الترتيب' : 'Rank',
                                style: const TextStyle(color: Color(0xFFFFFFAD), fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'No.1',
                            style: TextStyle(color: Color(0xFFFFFFAD), fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 0.5, height: 28, color: Colors.white24),
                    // Members
                    Expanded(
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(R.unionAgencyMemberIc, width: 16, height: 16, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                              const SizedBox(width: 4),
                              Text(
                                isAr ? 'الأعضاء' : 'Members',
                                style: const TextStyle(color: Color(0xFFFFFFAD), fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            memberCount.toString(),
                            style: const TextStyle(color: Color(0xFFFFFFAD), fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 0.5, height: 28, color: Colors.white24),
                    // Commission %
                    Expanded(
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.percent, size: 14, color: Color(0xFFFFD700)),
                              const SizedBox(width: 4),
                              Text(
                                isAr ? 'العمولة' : 'Comm.',
                                style: const TextStyle(color: Color(0xFFFFFFAD), fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${((info?.commissionRate ?? 0.10) * 100).toInt()}%',
                            style: const TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 0.5, height: 28, color: Colors.white24),
                    // Tier
                    Expanded(
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.shield, size: 14, color: Color(0xFFFFD700)),
                              const SizedBox(width: 4),
                              Text(
                                isAr ? 'المستوى' : 'Tier',
                                style: const TextStyle(color: Color(0xFFFFFFAD), fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            info?.tier == 'gold'
                                ? 'ذهبي'
                                : info?.tier == 'silver'
                                    ? 'فضي'
                                    : info?.tier == 'diamond'
                                        ? 'ألماسي'
                                        : info?.tier == 'platinum'
                                            ? 'بلاتيني'
                                            : 'برونزي',
                            style: const TextStyle(color: Color(0xFFFFFFAD), fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ── Announcement / Notice Bar: cl_notice (union_dialog_agency_notice.xml) ──
              GestureDetector(
                onTap: () => _showNoticeDialog(isAr),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0x33000000),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x22FFFFFF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Image.asset(R.unionNoticeIc, width: 16, height: 16, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                          const SizedBox(width: 6),
                          Text(
                            isAr ? 'إعلان الوكالة' : 'Agency Notice',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white54),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _noticeText,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),
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
          _buildTabButton(1, isAr ? 'دخل الوكالة' : 'Income'),
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
          return Container(
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
                        ],
                      ),
                    ],
                  ),
                ),
                // Direct Kick Button
                if (anchor.role != 'owner') ...[
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
                ],
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
            ),
          );
        },
        childCount: _anchors.length,
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
      try {
        final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
        final memberDocs = await db.collection('host_agency_members')
            .where('agency_id', isEqualTo: agencyId)
            .where('user_id', isEqualTo: targetUid)
            .get();
        for (final d in memberDocs.docs) {
          await d.reference.delete();
        }
        await db.collection('users').doc(targetUid).set({
          'is_host': false,
          'agency_id': null,
          'agency_name': null,
        }, SetOptions(merge: true));
        if (agencyId.isNotEmpty) {
          await db.collection('host_agencies').doc(agencyId).update({'member_count': FieldValue.increment(-1)});
        }
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

  /// Tab 2: Income & Targets matching union_adapter_agency_detail_item.xml
  Widget _buildIncomeTab(AgentInfoModel? info, bool isAr) {
    final transferMoney = info?.transferMoney ?? 0;
    final dollar = info?.transferDollar ?? 0;
    final commRatePct = ((info?.commissionRate ?? 0.10) * 100).toInt();
    final targetDiamonds = info?.targetDiamonds ?? 1000000;
    final progress = targetDiamonds > 0 ? (transferMoney / targetDiamonds).clamp(0.0, 1.0) : 0.0;
    final percent = (progress * 100).toStringAsFixed(1);
    final salaryUsd = info?.salaryUsd ?? 0.0;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ── Agency Total Income Card ──
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2C2415), Color(0xFF1E1A16)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x33FFD700)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isAr ? 'أرباح وعمولة الوكالة' : 'Agency Earnings',
                        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0x33FFD700),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x55FFD700)),
                        ),
                        child: Text(
                          '$commRatePct% ${isAr ? 'عمولة الوكيل' : 'Commission'}',
                          style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '\$$dollar USD',
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$transferMoney ${isAr ? 'ماسة محققة هذا الشهر' : 'Diamonds monthly'}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Target Progress Card ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF242424),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x22FFFFFF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.track_changes, size: 18, color: Color(0xFFFFD700)),
                          const SizedBox(width: 6),
                          Text(
                            isAr ? 'الهدف الشهري للوكالة' : 'Monthly Target',
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0x22FFFFFF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          info?.tier == 'gold' ? 'المرحلة الذهبية' : info?.tier == 'silver' ? 'المرحلة الفضية' : 'المرحلة 1',
                          style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold),
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
                      valueColor: const AlwaysStoppedAnimation(Color(0xFFFFD700)),
                      minHeight: 10,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$transferMoney / $targetDiamonds 💎',
                        style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        isAr ? 'تم إنجاز $percent%' : '$percent% done',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                  if (salaryUsd > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0x1AFFD700),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x33FFD700)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.card_giftcard, size: 18, color: Color(0xFFFFD700)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isAr
                                  ? 'المكافأة / الراتب المستحق عند إكمال المرحلة: \$$salaryUsd USD'
                                  : 'Reward / Salary upon completion: \$$salaryUsd USD',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
      } else {
        // 2. Firestore fallback search
        final intId = int.tryParse(query);
        final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');

        var qSnap = await db.collection('users').where('custom_id', isEqualTo: query).limit(1).get();
        if (qSnap.docs.isEmpty && intId != null) {
          qSnap = await db.collection('users').where('custom_id', isEqualTo: intId).limit(1).get();
        }
        if (qSnap.docs.isEmpty) {
          qSnap = await db.collection('users').where('customId', isEqualTo: query).limit(1).get();
        }
        if (qSnap.docs.isEmpty && intId != null) {
          qSnap = await db.collection('users').where('customId', isEqualTo: intId).limit(1).get();
        }
        if (qSnap.docs.isEmpty) {
          final doc = await db.collection('users').doc(query).get();
          if (doc.exists && doc.data() != null) {
            final data = doc.data()!;
            _foundUser = {
              'uid': doc.id,
              'name': data['name'] ?? data['displayName'] ?? (isAr ? 'مستخدم' : 'User'),
              'avatar': data['photoUrl'] ?? data['photo_url'] ?? data['avatar'] ?? '',
              'custom_id': data['custom_id'] ?? data['customId'] ?? query,
              'level': data['level'] ?? 1,
              'country': data['country'] ?? '',
            };
          }
        } else {
          final doc = qSnap.docs.first;
          final data = doc.data();
          _foundUser = {
            'uid': doc.id,
            'name': data['name'] ?? data['displayName'] ?? (isAr ? 'مستخدم' : 'User'),
            'avatar': data['photoUrl'] ?? data['photo_url'] ?? data['avatar'] ?? '',
            'custom_id': data['custom_id'] ?? data['customId'] ?? query,
            'level': data['level'] ?? 1,
            'country': data['country'] ?? '',
          };
        }
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
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');

      // 1. Add to host_agency_join_requests
      await db.collection('host_agency_join_requests').add({
        'agency_id': agencyId,
        'user_id': targetUid,
        'agency_name': agencyName,
        'status': 'invited',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // 2. Send in-app notification to the user
      await db.collection('notifications').add({
        'uid': targetUid,
        'title': isAr ? 'دعوة انضمام لوكالة مضيفين 🎙️' : 'Host Agency Invitation 🎙️',
        'body': isAr
            ? 'تمت دعوتك من قِبل وكالة [$agencyName] للانضمام كمضيف رسمي.'
            : 'You have been invited by agency [$agencyName] to join as an official host.',
        'type': 'host_invite',
        'action': 'host_invite',
        'data': {
          'agency_id': agencyId,
          'agency_name': agencyName,
        },
        'is_read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // 3. Supabase notifications fallback
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
