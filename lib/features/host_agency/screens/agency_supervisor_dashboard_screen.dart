// lib/features/host_agency/screens/agency_supervisor_dashboard_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// لوحة تحكم المشرف — مقيّدة (بدون محفظة / طرد / تعيين مشرفين)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/supabase_compat.dart';

import '../../../core/realtime/realtime_subscription.dart';
import '../../../core/realtime/supabase_realtime_bridge.dart';
import 'agency_join_requests_screen.dart';
import 'agency_invite_by_id_screen.dart';
import 'agency_chat_screen.dart';
import 'agency_leaderboard_screen.dart';
import '../data/agency_chat_models.dart';
import 'package:zero/core/dtext.dart';

// ── palette ───────────────────────────────────────────────────────────────────
const _bgDeep    = Color(0xFF03030A);
const _bgCard    = Color(0x800A0820);
const _border    = Color(0x2D00D4FF);
const _cyan      = Color(0xFF00D4FF);
const _gold      = Color(0xFFF6C453);
const _purple    = Color(0xFF9C6BFF);
const _green     = Color(0xFF00E5A0);
const _red       = Color(0xFFFF4D6D);
const _textMain  = Color(0xFFE8E6FF);
const _textMuted = Color(0xFF8A88AA);

// ─────────────────────────────────────────────────────────────────────────────
class AgencySupervisorDashboardScreen extends StatefulWidget {
  const AgencySupervisorDashboardScreen({super.key, this.agencyId});
  final String? agencyId;

  @override
  State<AgencySupervisorDashboardScreen> createState() =>
      _AgencySupervisorDashboardScreenState();
}

class _AgencySupervisorDashboardScreenState
    extends State<AgencySupervisorDashboardScreen>
    with TickerProviderStateMixin {
  final _sb = Supabase.instance.client;

  Map<String, dynamic>? _data;
  bool    _loading = true;
  String? _error;
  String? _resolvedAgencyId;

  late final AnimationController _pulseCtrl;
  late final AnimationController _shimmerCtrl;

  RealtimeSubscription? _rtMembers;
  Timer? _debounce;
  bool   _reloading = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl  = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _shimmerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
    _loadData();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _shimmerCtrl.dispose();
    _debounce?.cancel();
    _rtMembers?.dispose();
    super.dispose();
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      if (!_reloading) _loadData();
    });
  }

  void _bindRealtime(String agencyId) {
    _rtMembers?.dispose();
    _rtMembers = SupabaseRealtimeBridge.subscribePostgres(
      topic: 'sup_members:$agencyId',
      event: PostgresChangeEvent.all,
      table: 'host_agency_members',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'agency_id',
        value: agencyId,
      ),
      onPayload: (_) => _scheduleReload(),
    );
  }

  Future<void> _loadData() async {
    if (_reloading) return;
    _reloading = true;
    try {
      String? agencyId = widget.agencyId ?? _resolvedAgencyId;

      if (agencyId == null) {
        final uid = _sb.auth.currentUser?.id;
        if (uid == null) throw Exception('not_authenticated');
        final row = await _sb
            .from('host_agency_members')
            .select('agency_id')
            .eq('user_id', uid)
            .maybeSingle();
        if (row == null) throw Exception('not_in_agency');
        agencyId = row['agency_id'] as String;
        _resolvedAgencyId = agencyId;
        if (!mounted) return;
        _bindRealtime(agencyId);
      }

      final res = await _sb.rpc('agency_get_dashboard',
          params: {'p_agency_id': agencyId});
      final parsed = Map<String, dynamic>.from(res as Map);

      if (mounted) {
        setState(() {
          _data    = parsed;
          _loading = false;
          _error   = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    } finally {
      _reloading = false;
    }
  }

  String _fmt(dynamic v) {
    final n = (v is num ? v : num.tryParse(v.toString()) ?? 0).toInt();
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}م';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}ك';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: _bgDeep,
        body: _loading
            ? _buildLoading()
            : _error != null
                ? _buildError()
                : _buildBody(),
      ),
    );
  }

  Widget _buildLoading() => const Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      _NeonSpinner(),
      SizedBox(height: 16),
      DText('جارٍ تحميل بيانات الوكالة…',
          style: TextStyle(color: _textMuted, fontFamily: 'IBM Plex Sans Arabic')),
    ]),
  );

  Widget _buildError() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, color: _red, size: 48),
      const SizedBox(height: 12),
      DText(_error ?? 'خطأ',
          style: const TextStyle(color: _red, fontFamily: 'IBM Plex Sans Arabic')),
      const SizedBox(height: 16),
      _GlassButton(
        label: 'إعادة المحاولة', color: _cyan,
        onTap: () { setState(() { _loading = true; _error = null; }); _loadData(); },
      ),
    ]),
  );

  Widget _buildBody() {
    final d          = _data!;
    final agency     = d['agency']      as Map? ?? {};
    final members    = (d['members']    as List?)?.cast<Map>() ?? [];
    final milestones = (d['milestones'] as List?)?.cast<Map>() ?? [];

    final name   = agency['name']            ?? 'الوكالة';
    final spec   = agency['specialty']       ?? '';
    final totalD = agency['monthly_diamonds'] ?? 0;

    final ranked = [...members]
      ..sort((a, b) => ((b['week_diamonds'] ?? 0) as num)
          .compareTo((a['week_diamonds'] ?? 0) as num));

    return RefreshIndicator(
      color: _cyan,
      backgroundColor: _bgCard,
      onRefresh: _loadData,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            backgroundColor: Colors.transparent,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: _SupervisorHeader(
                name: name,
                spec: spec,
                totalDiamonds: totalD,
                memberCount: members.length,
                pulseCtrl: _pulseCtrl,
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 20),

                // ── شارة المشرف ──────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: _cyan.withOpacity(.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _cyan.withOpacity(.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.star_rounded, color: _cyan, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: DText(
                        'أنت مشرف في هذه الوكالة — يمكنك قبول الطلبات ودعوة الأعضاء',
                        style: TextStyle(color: _cyan, fontSize: 12,
                            fontFamily: 'IBM Plex Sans Arabic'),
                      ),
                    ),
                  ]),
                ),

                // ── KPI row ──────────────────────────────────────────────────
                Row(children: [
                  Expanded(child: _KpiTile(
                    label: 'ماسة الشهر', value: _fmt(totalD),
                    icon: '💎', color: _cyan)),
                  const SizedBox(width: 10),
                  Expanded(child: _KpiTile(
                    label: 'الأعضاء', value: '${members.length}',
                    icon: '👥', color: _purple)),
                  const SizedBox(width: 10),
                  Expanded(child: _KpiTile(
                    label: 'طلبات', value: '${(d['pending_members_count'] as num?)?.toInt() ?? 0}',
                    icon: '📥', color: _gold)),
                ]),

                const SizedBox(height: 24),

                // ── متصدرو الأسبوع ───────────────────────────────────────────
                if (ranked.isNotEmpty) ...[
                  const _SectionHeader(label: 'متصدرو الأسبوع', icon: '🏅'),
                  const SizedBox(height: 12),
                  _LeaderboardList(
                    members:  ranked,
                    shimmer:  _shimmerCtrl,
                    fmtFn:    _fmt,
                  ),
                  const SizedBox(height: 24),
                ],

                // ── أهداف الوكالة ────────────────────────────────────────────
                if (milestones.isNotEmpty) ...[
                  const _SectionHeader(label: 'أهداف الوكالة', icon: '🎯'),
                  const SizedBox(height: 12),
                  ...milestones.map((m) => _MilestoneCard(
                    milestone: m,
                    shimmer:   _shimmerCtrl,
                    fmtFn:     _fmt,
                  )),
                  const SizedBox(height: 24),
                ],

                // ── إجراءات سريعة (مقيّدة) ───────────────────────────────────
                const _SectionHeader(label: 'إجراءات سريعة', icon: '⚡'),
                const SizedBox(height: 12),
                _SupervisorQuickActions(
                  agencyId: _resolvedAgencyId ?? widget.agencyId ?? '',
                  agencyName: (agency['name'] as String?) ?? 'الوكالة',
                  pendingCount: (d['pending_members_count'] as num?)?.toInt() ?? 0,
                ),

                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────
class _SupervisorHeader extends StatelessWidget {
  const _SupervisorHeader({
    required this.name,
    required this.spec,
    required this.totalDiamonds,
    required this.memberCount,
    required this.pulseCtrl,
  });
  final String name, spec;
  final dynamic totalDiamonds;
  final int memberCount;
  final AnimationController pulseCtrl;

  String _fmt(dynamic v) {
    final n = (v is num ? v : num.tryParse(v.toString()) ?? 0).toInt();
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}م';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}ك';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseCtrl,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [
              _cyan.withOpacity(.10 + .05 * pulseCtrl.value),
              const Color(0xFF03030A),
            ],
          ),
        ),
        padding: EdgeInsets.only(
          top:    MediaQuery.of(context).padding.top + 12,
          left:   20, right: 20, bottom: 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: _cyan.withOpacity(.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _cyan.withOpacity(.4)),
                  boxShadow: [BoxShadow(
                    color: _cyan.withOpacity(.25 + .15 * pulseCtrl.value),
                    blurRadius: 16,
                  )],
                ),
                child: const Center(child: Icon(Icons.star_rounded, color: _cyan, size: 26)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  DText(name,
                      style: const TextStyle(color: _textMain, fontSize: 18,
                          fontWeight: FontWeight.bold, fontFamily: 'IBM Plex Sans Arabic')),
                  Row(children: [
                    if (spec.isNotEmpty)
                      DText(spec, style: const TextStyle(color: _textMuted,
                          fontSize: 12, fontFamily: 'IBM Plex Sans Arabic')),
                    if (spec.isNotEmpty) const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _cyan.withOpacity(.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _cyan.withOpacity(.4)),
                      ),
                      child: const DText('مشرف',
                          style: TextStyle(color: _cyan, fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                  ]),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            DText('${_fmt(totalDiamonds)} 💎 هذا الشهر',
                style: TextStyle(
                  color: _cyan, fontSize: 22, fontWeight: FontWeight.bold,
                  fontFamily: 'Space Grotesk',
                  shadows: [Shadow(color: _cyan.withOpacity(.6), blurRadius: 10)],
                )),
          ],
        ),
      ),
    );
  }
}

// ── Supervisor Quick Actions (مقيّدة) ─────────────────────────────────────────
class _SupervisorQuickActions extends StatelessWidget {
  const _SupervisorQuickActions({
    required this.agencyId,
    required this.agencyName,
    required this.pendingCount,
  });
  final String agencyId;
  final String agencyName;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _QuickAction(
        icon: Icons.group_add_rounded,
        emoji: '📥',
        label: 'طلبات الانضمام',
        badge: pendingCount,
        color: _cyan,
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => AgencyJoinRequestsScreen(agencyId: agencyId, canKick: false))),
      ),
      _QuickAction(
        icon: Icons.person_search_rounded,
        emoji: '🔍',
        label: 'دعوة بـ ID',
        badge: 0,
        color: _gold,
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => AgencyInviteByIdScreen(agencyId: agencyId, agencyName: agencyName))),
      ),
      _QuickAction(
        icon: Icons.chat_bubble_rounded,
        emoji: '💬',
        label: 'قروب الوكالة',
        badge: 0,
        color: _purple,
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => AgencyChatScreen(agencyId: agencyId, agencyName: agencyName, myRole: AgencyMemberRole.supervisor))),
      ),
      _QuickAction(
        icon: Icons.emoji_events_rounded,
        emoji: '🏆',
        label: 'التصنيف',
        badge: 0,
        color: _green,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgencyLeaderboardScreen())),
      ),
    ];

    return Row(
      children: actions.map((a) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _QuickActionCard(action: a),
        ),
      )).toList(),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String emoji;
  final String label;
  final int badge;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction({
    required this.icon, required this.emoji, required this.label,
    required this.badge, required this.color, required this.onTap,
  });
}

class _QuickActionCard extends StatelessWidget {
  final _QuickAction action;
  const _QuickActionCard({required this.action});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: action.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: action.color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: action.color.withOpacity(0.3)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(mainAxisSize: MainAxisSize.min, children: [
              DText(action.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 6),
              DText(action.label,
                style: TextStyle(color: action.color, fontSize: 11, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ]),
            if (action.badge > 0)
              Positioned(
                top: 0, right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DText('${action.badge}',
                      style: const TextStyle(color: Colors.white, fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── KpiTile ───────────────────────────────────────────────────────────────────
class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.label, required this.value,
      required this.icon, required this.color});
  final String label, value, icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _bgCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withOpacity(.25)),
      boxShadow: [BoxShadow(color: color.withOpacity(.08), blurRadius: 12)],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DText(icon, style: const TextStyle(fontSize: 20)),
      const SizedBox(height: 6),
      DText(value, style: TextStyle(color: color, fontSize: 18,
          fontWeight: FontWeight.bold, fontFamily: 'Space Grotesk',
          shadows: [Shadow(color: color.withOpacity(.5), blurRadius: 6)])),
      DText(label, style: const TextStyle(color: _textMuted, fontSize: 10,
          fontFamily: 'IBM Plex Sans Arabic')),
    ]),
  );
}

// ── LeaderboardList ───────────────────────────────────────────────────────────
class _LeaderboardList extends StatelessWidget {
  const _LeaderboardList({
    required this.members,
    required this.shimmer,
    required this.fmtFn,
  });
  final List<Map> members;
  final AnimationController shimmer;
  final String Function(dynamic) fmtFn;

  @override
  Widget build(BuildContext context) {
    final maxD = members.fold<double>(
      1,
      (prev, m) => math.max(prev, ((m['week_diamonds'] ?? 0) as num).toDouble()),
    );

    return Column(
      children: List.generate(members.length, (i) {
        final m    = members[i];
        final name = m['display_name'] ?? '—';
        final weekD = ((m['week_diamonds'] ?? 0) as num).toDouble();
        final pct  = (weekD / maxD).clamp(0.0, 1.0);
        final barC = i == 0 ? _gold : i == 1 ? _textMuted : i == 2 ? _cyan : _purple;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: i == 0 ? _gold.withOpacity(.3) : _border),
          ),
          child: Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: barC.withOpacity(.15),
                shape: BoxShape.circle,
                border: Border.all(color: barC.withOpacity(.4)),
              ),
              child: Center(child: DText('${i + 1}',
                  style: TextStyle(color: barC, fontSize: 12,
                      fontWeight: FontWeight.bold, fontFamily: 'Space Grotesk'))),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DText(name, style: const TextStyle(color: _textMain, fontSize: 13,
                    fontFamily: 'IBM Plex Sans Arabic')),
                const SizedBox(height: 6),
                Stack(children: [
                  Container(height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.06),
                        borderRadius: BorderRadius.circular(3),
                      )),
                  AnimatedFractionallySizedBox(
                    widthFactor: pct,
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    child: AnimatedBuilder(
                      animation: shimmer,
                      builder: (_, __) => Container(
                        height: 5,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          gradient: LinearGradient(colors: [
                            barC.withOpacity(.6), barC, barC.withOpacity(.6),
                          ]),
                          boxShadow: [BoxShadow(color: barC.withOpacity(.5), blurRadius: 4)],
                        ),
                      ),
                    ),
                  ),
                ]),
              ],
            )),
            const SizedBox(width: 10),
            DText('${fmtFn(weekD)} 💎',
                style: TextStyle(color: barC, fontSize: 12,
                    fontFamily: 'Space Grotesk', fontWeight: FontWeight.w600)),
          ]),
        );
      }),
    );
  }
}

// ── MilestoneCard ─────────────────────────────────────────────────────────────
class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({
    required this.milestone,
    required this.shimmer,
    required this.fmtFn,
  });
  final Map milestone;
  final AnimationController shimmer;
  final String Function(dynamic) fmtFn;

  @override
  Widget build(BuildContext context) {
    final name      = milestone['name']           ?? '';
    final target    = (milestone['target_value']  as num?)?.toDouble() ?? 1;
    final current   = (milestone['current_value'] as num?)?.toDouble() ?? 0;
    final completed = milestone['is_completed'] == true;
    final pct       = (current / target).clamp(0.0, 1.0);
    final barC      = completed ? _gold : _green;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: completed ? _gold.withOpacity(.4) : _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: DText(name,
              style: TextStyle(color: completed ? _gold : _textMain,
                  fontSize: 14, fontWeight: FontWeight.w600,
                  fontFamily: 'IBM Plex Sans Arabic'))),
          if (completed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _gold.withOpacity(.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _gold.withOpacity(.4)),
              ),
              child: const DText('✅ مكتمل',
                  style: TextStyle(color: _gold, fontSize: 11,
                      fontFamily: 'IBM Plex Sans Arabic')),
            ),
        ]),
        const SizedBox(height: 10),
        Stack(children: [
          Container(height: 8, decoration: BoxDecoration(
              color: Colors.white.withOpacity(.06),
              borderRadius: BorderRadius.circular(4))),
          AnimatedFractionallySizedBox(
            widthFactor: pct,
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            child: AnimatedBuilder(
              animation: shimmer,
              builder: (_, __) => Container(
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(colors: [
                    barC.withOpacity(.7), barC, barC.withOpacity(.7),
                  ]),
                  boxShadow: [BoxShadow(color: barC.withOpacity(.5), blurRadius: 6)],
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          DText('${(pct * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: barC, fontSize: 12,
                  fontFamily: 'Space Grotesk', fontWeight: FontWeight.bold)),
          DText('${fmtFn(current)} / ${fmtFn(target)} 💎',
              style: const TextStyle(color: _textMuted, fontSize: 11,
                  fontFamily: 'Space Grotesk')),
        ]),
      ]),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.icon});
  final String label, icon;

  @override
  Widget build(BuildContext context) => Row(children: [
    DText(icon, style: const TextStyle(fontSize: 18)),
    const SizedBox(width: 8),
    DText(label,
        style: const TextStyle(color: _textMain, fontSize: 16,
            fontWeight: FontWeight.bold, fontFamily: 'IBM Plex Sans Arabic')),
    const SizedBox(width: 12),
    Expanded(child: Container(height: 1, color: _border)),
  ]);
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.4)),
      ),
      child: DText(label, style: TextStyle(color: color,
          fontFamily: 'IBM Plex Sans Arabic', fontWeight: FontWeight.w600)),
    ),
  );
}

class _NeonSpinner extends StatefulWidget {
  const _NeonSpinner();

  @override
  State<_NeonSpinner> createState() => _NeonSpinnerState();
}

class _NeonSpinnerState extends State<_NeonSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, __) => Transform.rotate(
      angle: _c.value * 2 * math.pi,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(colors: [_cyan, _cyan.withOpacity(0)]),
          boxShadow: [BoxShadow(color: _cyan.withOpacity(.5), blurRadius: 12)],
        ),
      ),
    ),
  );
}
