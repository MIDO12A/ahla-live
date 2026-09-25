import 'package:firebase_core/firebase_core.dart';
// lib/features/host_agency/host_dashboard_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Glassmorphic 2035 Host Dashboard
// • Real-time diamond earnings (today / week / month)
// • Neon progress bars for monthly milestones
// • Agency membership card
// • Auto-refresh via StreamBuilder + periodic timer
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/supabase_compat.dart';

import '../../core/realtime/realtime_subscription.dart';
import '../../core/realtime/supabase_realtime_bridge.dart';
import '../../core/ui/in_app_toast.dart';
import 'data/agency_models.dart';
import 'data/agency_repository.dart';
import 'screens/agency_withdrawal_screen.dart';
import 'screens/agency_leaderboard_screen.dart';
import 'screens/agency_exit_screen.dart';
import 'screens/agency_item_detail_screen.dart';
import '../../config/r.dart';

import '../../core/cache/encrypted_image_provider.dart';
import 'package:provider/provider.dart';
import '../../services/dynamic_config_service.dart';

// ── palette ──────────────────────────────────────────────────────────────────
const Color _bgDeep     = Color(0xFF1A1A1A);
const Color _bgCard     = Color(0xFF242424);
const Color _border     = Color(0x22FFFFFF);
const Color _purple     = Color(0xFF9C6BFF);
const Color _gold       = Color(0xFFFFD700);
const Color _cyan       = Color(0xFF00D4FF);
const Color _red        = Color(0xFFFF4D6D);
const Color _textMain   = Color(0xFFFFFFFF);
const Color _textMuted  = Color(0x99FFFFFF);

// ─────────────────────────────────────────────────────────────────────────────
class HostDashboardScreen extends StatefulWidget {
  const HostDashboardScreen({super.key});

  @override
  State<HostDashboardScreen> createState() => _HostDashboardScreenState();
}

class _HostDashboardScreenState extends State<HostDashboardScreen>
    with TickerProviderStateMixin {
  final _sb = Supabase.instance.client;

  // data
  Map<String, dynamic>? _data;
  HostAgencyStats? _agencyStats;
  bool _loading = true;
  String? _error;

  // ── v3 engine data ─────────────────────────────────────────────────────────
  bool _engineV3Enabled = false;
  Map<String, dynamic>? _v3Data; // from get_host_dashboard_v3
  Timer? _countdownTimer;

  // animation controllers
  late final AnimationController _pulseCtrl;
  late final AnimationController _shimmerCtrl;

  // Realtime بديل Timer.periodic
  StreamSubscription? _fsMemberSub;
  StreamSubscription? _fsLedgerSub;
  RealtimeSubscription? _rtDiamonds;
  RealtimeSubscription? _rtMilestones;
  RealtimeSubscription? _rtProgress;   // v3: monthly progress
  RealtimeSubscription? _rtV2Diamonds; // v2: host_agency_members diamonds_available
  Timer? _debounce;
  bool   _reloading = false;
  int    _prevMonthDiamonds = 0; // لكشف التغيير والإشعار

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1500),
    )..repeat();

    _loadData();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _shimmerCtrl.dispose();
    _debounce?.cancel();
    _countdownTimer?.cancel();
    _fsMemberSub?.cancel();
    _fsLedgerSub?.cancel();
    _rtDiamonds?.dispose();
    _rtMilestones?.dispose();
    _rtProgress?.dispose();
    _rtV2Diamonds?.dispose();
    super.dispose();
  }

  // ── debounced reload ──────────────────────────────────────────────────────
  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      if (!_reloading) _loadData();
    });
  }

  // ── subscribe realtime (Firestore Live Stream for Gifts & Targets) ────────
  void _bindRealtime(String uid) {
    _fsMemberSub?.cancel();
    _fsLedgerSub?.cancel();
    _rtDiamonds?.dispose();
    _rtMilestones?.dispose();
    _rtV2Diamonds?.dispose();

    // ⚡ 1. استماع لحظي مباشر في Firestore لعضوية المضيف وألماسه عند استلام أي هدية
    _fsMemberSub = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
        .collection('host_agency_members')
        .where('user_id', isEqualTo: uid)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        final currentDiamonds = (data['diamonds_earned_monthly'] as num?)?.toInt() ?? 0;
        if (_prevMonthDiamonds > 0 && currentDiamonds > _prevMonthDiamonds) {
          final diff = currentDiamonds - _prevMonthDiamonds;
          KayanInAppToast.diamond('🎁 استلمت هدية جديدة! +${_fmtN(diff)} 💎');
          HapticFeedback.mediumImpact();
        }
        _prevMonthDiamonds = currentDiamonds;
        _scheduleReload();
      }
    }, onError: (e) => debugPrint('[HostDashboard] fsMemberSub error: $e'));

    // ⚡ 2. استماع لحظي لسجل هدايا المضيف في agency_diamond_ledger
    _fsLedgerSub = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
        .collection('agency_diamond_ledger')
        .where('user_id', isEqualTo: uid)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          final amount = (data?['amount'] as num?)?.toInt() ?? 0;
          final giftName = data?['gift_name']?.toString() ?? '';
          if (amount > 0 && change.newIndex == 0) {
            final title = giftName.isNotEmpty
                ? '🎁 هدية "$giftName" (+${_fmtN(amount)} 💎)'
                : '💎 هدية جديدة +${_fmtN(amount)} 💎';
            KayanInAppToast.diamond(title);
            HapticFeedback.lightImpact();
          }
          _scheduleReload();
        }
      }
    }, onError: (e) => debugPrint('[HostDashboard] fsLedgerSub error: $e'));

    // ✅ اشتراك بدفتر الألماس (المحرك القديم للتوافق)
    _rtDiamonds = SupabaseRealtimeBridge.subscribePostgres(
      topic: 'agency_ledger:$uid',
      event: PostgresChangeEvent.insert,
      table: 'agency_diamond_ledger',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: uid,
      ),
      onPayload: (payload) {
        final amount    = (payload.newRecord['amount'] as num?)?.toInt() ?? 0;
        final direction = (payload.newRecord['direction'] as num?)?.toInt() ?? 1;
        if (amount > 0 && direction == 1) {
          KayanInAppToast.diamond('حصلت على ${_fmtN(amount)} 💎 جديد!');
        }
        _scheduleReload();
      },
    );

    // ✅ اشتراك بـ host_agency_members (للتوافق)
    _rtV2Diamonds = SupabaseRealtimeBridge.subscribePostgres(
      topic: 'agency_member_v2:$uid',
      event: PostgresChangeEvent.update,
      table: 'host_agency_members',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: uid,
      ),
      onPayload: (payload) {
        final newDiamonds = (payload.newRecord['diamonds_available'] as num?)?.toInt();
        final oldDiamonds = (payload.oldRecord['diamonds_available'] as num?)?.toInt();
        if (newDiamonds != null && oldDiamonds != null && newDiamonds > oldDiamonds) {
          final diff = newDiamonds - oldDiamonds;
          KayanInAppToast.diamond('فُتح مستوى جديد! +${_fmtN(diff)} 💎');
        }
        _scheduleReload();
        _loadV3Data(uid);
      },
    );

    // اشتراك بالإنجازات
    _rtMilestones = SupabaseRealtimeBridge.subscribePostgres(
      topic: 'agency_achieved:$uid',
      event: PostgresChangeEvent.insert,
      table: 'agency_achieved_targets',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: uid,
      ),
      onPayload: (_) => _scheduleReload(),
    );
  }

  // ── v3 countdown ticker ──────────────────────────────────────────────────
  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _v3Data != null) setState(() {});
    });
  }

  // ── v3 data load ─────────────────────────────────────────────────────────
  Future<void> _loadV3Data(String uid) async {
    try {
      final res = await _sb.rpc('get_host_dashboard_v3', params: {'p_user_id': uid});
      if (res != null && res is Map) {
        final v3 = Map<String, dynamic>.from(res);
        if (mounted) {
          setState(() {
            _v3Data = v3;
            _engineV3Enabled = v3['engine_enabled'] == true;
          });
          _startCountdown();
          // Subscribe to progress changes
          if (_rtProgress == null) {
            _rtProgress = SupabaseRealtimeBridge.subscribePostgres(
              topic: 'host_progress:$uid',
              event: PostgresChangeEvent.update,
              table: 'host_monthly_progress',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: uid,
              ),
              onPayload: (_) => _loadV3Data(uid),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[HostDashboardScreen] v3 load error: $e');
    }
  }

  Future<void> _loadData() async {
    if (_reloading) return;
    _reloading = true;
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) throw Exception('not_authenticated');

      // ابدأ Realtime فور معرفة agencyId
      if (_rtDiamonds == null) _bindRealtime(uid);

      // تحميل بيانات المحرك بالتوازي
      _loadV3Data(uid);

      // استخدام get_host_dashboard_v2
            final results = await Future.wait<dynamic>([
        AgencyRepository.getHostStats(),
        _sb.from('profiles')
            .select('display_name, avatar_url, level, coins')
            .eq('id', uid)
            .maybeSingle(),
        _sb.from('agency_diamond_ledger')
            .select('amount, direction, created_at')
            .eq('user_id', uid)
            .eq('direction', 1)
            .gte('created_at', DateTime.now().toUtc().subtract(const Duration(hours: 24)).toIso8601String()),
        _sb.from('agency_diamond_ledger')
            .select('amount, direction, created_at')
            .eq('user_id', uid)
            .eq('direction', 1)
            .gte('created_at', DateTime.now().toUtc().subtract(const Duration(days: 7)).toIso8601String()),
      ]);

      final agencyStats = results[0] as HostAgencyStats?;
      final profileRow  = results[1] as Map<String, dynamic>?;
      final todayRows   = (results[2] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final weekRows    = (results[3] as List?)?.cast<Map<String, dynamic>>() ?? [];

      final todayD = todayRows.fold<int>(0, (sum, r) => sum + ((r['amount'] as num?)?.toInt() ?? 0));
      final weekD  = weekRows.fold<int>(0,  (sum, r) => sum + ((r['amount'] as num?)?.toInt() ?? 0));
      final monthD = agencyStats?.member.diamondsEarnedMonthly ?? 0;

      // جلب بيانات ساعات البث والأيام الفعالة من host_agency_members
      int liveHours = 0;
      int validDays = 0;
      try {
        final memSnap = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
            .collection('host_agency_members')
            .where('user_id', isEqualTo: uid)
            .limit(1)
            .get();
        if (memSnap.docs.isNotEmpty) {
          final mdata = memSnap.docs.first.data();
          liveHours = (mdata['live_hours_monthly'] as num?)?.toInt() ?? 0;
          validDays = (mdata['valid_days_monthly'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {}

      // بناء بيانات لوحة التحكم
      final built = <String, dynamic>{
        'profile': {
          'display_name': profileRow?['display_name'] ?? '—',
          'level':        profileRow?['level']        ?? 1,
          'avatar_url':   profileRow?['avatar_url'],
          'is_vip':       false,
        },
        'agency': agencyStats?.agency != null ? {
          'id':              agencyStats!.agency!.id,
          'name':            agencyStats.agency!.name,
          'commission_rate': 0.0,
        } : null,
        'milestones': (agencyStats?.targets ?? []).map((t) => <String, dynamic>{
          'id':                t.id,
          'title_ar':          t.title ?? '—',
          'name':              t.title ?? '—',
          'target':            t.targetDiamonds,
          'target_value':      t.targetDiamonds,
          'current_value':     t.earnedThisMonth,
          'reward_type':       t.rewardType ?? 'coins',
          'reward_value':      t.rewardValue > 0 ? t.rewardValue : t.rewardCoins,
          'reward_coins':      t.rewardCoins,
          'reward_diamonds':   t.rewardDiamonds,
          'reward_image_url':  t.rewardImageUrl,
          'background_url':    t.backgroundUrl,
          'period_type':       'monthly',
          'earned':            t.earnedThisMonth,
          'is_completed':      t.isAchieved,
          'reward_sent':       t.isAchieved,
          'progress_pct':      t.progressPct,
        }).toList(),
        'month_diamonds': monthD,
        'week_diamonds':  weekD,
        'today_diamonds': todayD,
        'live_hours_monthly': liveHours,
        'valid_days_monthly': validDays,
      };

      // كشف تغيير ماسات الشهر وإظهار toast
      final newMonthD = monthD;
      if (_prevMonthDiamonds > 0 && newMonthD > _prevMonthDiamonds) {
        final diff = newMonthD - _prevMonthDiamonds;
          KayanInAppToast.diamond('فُتح مستوى جديد! +${_fmtN(diff)} 💎');
      }
      _prevMonthDiamonds = newMonthD;

      if (mounted) {
        setState(() {
          _data        = built;
          _agencyStats = agencyStats;
          _loading     = false;
          _error       = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    } finally {
      _reloading = false;
    }
  }

  // ── helpers ─────────────────────────────────────────────────────────────
  String _fmt(dynamic v) {
    final n = (v is num ? v : num.tryParse(v.toString()) ?? 0).toInt();
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}م';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}ك';
    return n.toString();
  }

  static String _fmtN(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}م';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}ك';
    return n.toString();
  }

  // ── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    context.watch<DynamicConfigService>();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: _bgDeep,
        body: _loading
            ? _buildSkeleton()
            : _error != null
                ? _buildError()
                : _buildBody(),
      ),
    );
  }

  // ── skeleton ─────────────────────────────────────────────────────────────
  Widget _buildSkeleton() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NeonSpinner(),
          SizedBox(height: 16),
          Text('جارٍ تحميل البيانات...',
              style: TextStyle(color: _textMuted, fontFamily: 'IBM Plex Sans Arabic')),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: _red, size: 48),
          const SizedBox(height: 12),
          Text(_error ?? 'خطأ غير معروف',
              style: TextStyle(color: _red, fontFamily: 'IBM Plex Sans Arabic')),
          const SizedBox(height: 16),
          _GlassButton(
            label: 'إعادة المحاولة',
            color: _purple,
            onTap: () { setState(() { _loading = true; _error = null; }); _loadData(); },
          ),
        ],
      ),
    );
  }

  // ── main body ────────────────────────────────────────────────────────────
  Widget _buildBody() {
    final d          = _data!;
    final profile    = d['profile']  as Map? ?? {};
    final agency     = d['agency']   as Map?;
    final milestones = (d['milestones'] as List?)?.cast<Map>() ?? [];

    final monthD = d['month_diamonds'] ?? 0;
    final weekD  = d['week_diamonds']  ?? 0;
    final todayD = d['today_diamonds'] ?? 0;

    return RefreshIndicator(
      color: _purple,
      backgroundColor: _bgCard,
      onRefresh: _loadData,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ─ app bar ──────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 180,
            backgroundColor: Colors.transparent,
            pinned: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.exit_to_app_rounded, color: Colors.white70),
                tooltip: 'خروج من الوكالة',
                onPressed: () async {
                  final res = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => const AgencyExitScreen()),
                  );
                  if (res == true && mounted) {
                    Navigator.pop(context);
                  } else if (mounted) {
                    _loadData();
                  }
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeader(profile, agency),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 20),

                // ─ stat row ──────────────────────────────────────────────
                // v2 engine: عرض كوينز الشهر + ألماس متاح + المستوى
                if (_engineV3Enabled && _v3Data != null) ...[
                  Row(children: [
                    Expanded(child: _StatCard(
                      label: 'كوينز الشهر',
                      value: _fmt(_v3Data!['received_coins_monthly'] ?? 0),
                      icon: '🪙', color: _cyan, pulse: _pulseCtrl,
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _StatCard(
                      label: 'ألماس متاح',
                      value: _fmt(_v3Data!['diamonds_available'] ?? 0),
                      icon: '💎', color: _purple, pulse: _pulseCtrl,
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _StatCard(
                      label: 'المستوى',
                      value: (_v3Data!['current_level_number'] ?? 0).toString(),
                      icon: '🏆', color: _gold, pulse: _pulseCtrl,
                    )),
                  ]),
                ] else ...[
                  // v1 engine: عرض الألماس من دفتر الوكالة
                  Row(children: [
                    Expanded(child: _StatCard(
                      label: 'اليوم',
                      value: _fmt(todayD),
                      icon: '💎',
                      color: _cyan,
                      pulse: _pulseCtrl,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AgencyItemDetailScreen(
                            agencyId: (agency?['id'] as String?) ?? '',
                            agencyName: (agency?['name'] as String?) ?? 'الوكالة',
                            periodTitle: 'اليوم',
                            totalDiamonds: todayD,
                            commissionRate: 0.10,
                            members: const [],
                          ),
                        ),
                      ),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _StatCard(
                      label: 'الأسبوع',
                      value: _fmt(weekD),
                      icon: '⚡',
                      color: _purple,
                      pulse: _pulseCtrl,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AgencyItemDetailScreen(
                            agencyId: (agency?['id'] as String?) ?? '',
                            agencyName: (agency?['name'] as String?) ?? 'الوكالة',
                            periodTitle: 'هذا الأسبوع',
                            totalDiamonds: weekD,
                            commissionRate: 0.10,
                            members: const [],
                          ),
                        ),
                      ),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _StatCard(
                      label: 'الشهر',
                      value: _fmt(monthD),
                      icon: '🏆',
                      color: _gold,
                      pulse: _pulseCtrl,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AgencyItemDetailScreen(
                            agencyId: (agency?['id'] as String?) ?? '',
                            agencyName: (agency?['name'] as String?) ?? 'الوكالة',
                            periodTitle: 'هذا الشهر',
                            totalDiamonds: monthD,
                            commissionRate: 0.10,
                            members: const [],
                          ),
                        ),
                      ),
                    )),
                  ]),
                ],

                const SizedBox(height: 24),

                // ─ بطاقة البيانات الشهرية ونظام التارجت الأصلي (D:40) ─────────
                _D40MonthlyDataCard(
                  data: d,
                  milestones: milestones,
                  pulse: _pulseCtrl,
                ),
                const SizedBox(height: 24),

                // ─ v3 engine cards ────────────────────────────────────────
                if (_engineV3Enabled && _v3Data != null) ...[
                  _EngineV3Banner(v3: _v3Data!),
                  const SizedBox(height: 16),
                  _CoinsProgressCard(v3: _v3Data!, shimmer: _shimmerCtrl),
                  const SizedBox(height: 16),
                  _UsdWalletCard(v3: _v3Data!),
                  const SizedBox(height: 16),
                  _MonthCountdownCard(v3: _v3Data!),
                  const SizedBox(height: 24),
                ],

                // ─ agency card ───────────────────────────────────────────
                if (agency != null) ...[
                  _AgencyCard(agency: agency),
                  const SizedBox(height: 24),
                ],

                // ─ milestones (مراحل وتارجت الشهر) ─────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _SectionHeader(label: 'مراحل وتارجت الشهر', icon: '🎯'),
                    if (milestones.any((m) => m['is_completed'] == true))
                      GestureDetector(
                        onTap: () {
                          final totalAchievedDiamonds = milestones
                              .where((m) => m['is_completed'] == true)
                              .fold<int>(0, (acc, m) => acc + ((m['target_value'] as num?)?.toInt() ?? 0));
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AgencyWithdrawalScreen(
                                initialTab: 2, // تبويب وكيل الشحن
                                initialDiamonds: totalAchievedDiamonds > 0 ? totalAchievedDiamonds : null,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00D4FF), Color(0xFF9C6BFF)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.3), blurRadius: 8),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.account_balance_wallet_rounded, color: Colors.black, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'سحب جميع المراحل المحققة ⚡',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'IBM Plex Sans Arabic',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (milestones.isNotEmpty)
                  ...milestones.map((m) => _MilestoneCard(
                    milestone: m,
                    shimmer:   _shimmerCtrl,
                    onWithdraw: () {
                      final targetVal = (m['target_value'] as num?)?.toInt() ?? 0;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AgencyWithdrawalScreen(
                            initialTab: 2, // تحويل لوكيل الشحن
                            initialDiamonds: targetVal > 0 ? targetVal : null,
                          ),
                        ),
                      );
                    },
                  ))
                else ...[
                  // بطاقة تنبيهية في حال عدم توفر مراحل
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _bgCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border),
                    ),
                    child: const Center(
                      child: Text(
                        'جاري تحديث تارجت ومراحل هذا الشهر...',
                        style: TextStyle(color: _textMuted, fontSize: 13, fontFamily: 'IBM Plex Sans Arabic'),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // ─ agency wallet & targets ────────────────────────────────
                if (_agencyStats != null) ...[
                  _AgencyWalletCard(
                    stats: _agencyStats!,
                    onExchange: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AgencyWithdrawalScreen())),
                    onWithdraw: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AgencyWithdrawalScreen())),
                    onLeaderboard: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AgencyLeaderboardScreen())),
                    onExit: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AgencyExitScreen())),
                  ),
                  const SizedBox(height: 24),
                ],

                // ─ زر الخروج الدائم من الوكالة ─
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 24),
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final res = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(builder: (_) => const AgencyExitScreen()),
                      );
                      if (res == true && mounted) {
                        Navigator.pop(context);
                      } else if (mounted) {
                        _loadData();
                      }
                    },
                    icon: const Icon(Icons.exit_to_app_rounded, color: Color(0xFFFF5252), size: 20),
                    label: const Text(
                      'الخروج من الوكالة',
                      style: TextStyle(
                        color: Color(0xFFFF5252),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'IBM Plex Sans Arabic',
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFF5252), width: 1.2),
                      backgroundColor: const Color(0xFFFF5252).withOpacity(0.06),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── header ───────────────────────────────────────────────────────────────
  Widget _buildHeader(Map profile, Map? agency) {
    final name     = profile['display_name'] ?? 'مضيف';
    final level    = profile['level']         ?? 1;
    final avatar   = profile['avatar_url'];
    final isVip    = profile['is_vip'] == true;

    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            R.unionMyAgencyBg,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1A1A1A)),
          ),
        ),
        Container(
          color: Colors.black.withValues(alpha: 0.35),
        ),
        Padding(
          padding: EdgeInsets.only(
            top:    MediaQuery.of(context).padding.top + 12,
            left:   20,
            right:  20,
            bottom: 20,
          ),
          child: Row(
            children: [
              // avatar with authentic crown
              Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFFFD700), width: 2),
                    ),
                    child: CircleAvatar(
                      backgroundImage: avatar != null ? EncryptedImageProvider(avatar) : null,
                      backgroundColor: _bgCard,
                      child: avatar == null
                          ? const Icon(Icons.person, color: Colors.white54, size: 32)
                          : null,
                    ),
                  ),
                  Positioned(
                    top: -12,
                    child: Image.asset(
                      R.unionAgencyAvatarHeaderIc,
                      width: 28,
                      height: 24,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),

              // info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment:  MainAxisAlignment.center,
                  children: [
                    Row(children: [
                      Text(name,
                          style: const TextStyle(
                            color: Colors.white, fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'IBM Plex Sans Arabic',
                          )),
                      if (isVip) ...[
                        const SizedBox(width: 8),
                        _VipBadge(),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    Text('المستوى $level',
                        style: const TextStyle(color: Color(0xFFFFF5AD), fontSize: 13,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'IBM Plex Sans Arabic')),
                  ],
                ),
              ),

              // refresh icon
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                onPressed: _loadData,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.pulse,
    this.onTap,
  });

  final String label;
  final String value;
  final String icon;
  final Color  color;
  final AnimationController pulse;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    context.watch<DynamicConfigService>();
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (_, __) {
          final glow = pulse.value;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              image: const DecorationImage(
                image: AssetImage(R.unionAgencyItemBg),
                fit: BoxFit.fill,
              ),
              color: _bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: .25 + .15 * glow)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: .12 + .08 * glow),
                  blurRadius: 16 + 8 * glow,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(icon, style: const TextStyle(fontSize: 20)),
                    if (onTap != null)
                      Image.asset(
                        R.commonNext3Ic,
                        width: 16,
                        height: 16,
                        errorBuilder: (_, __, ___) => const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 12),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(value,
                    style: TextStyle(
                      color: color, fontSize: 18, fontWeight: FontWeight.bold,
                      fontFamily: 'Space Grotesk',
                      shadows: [Shadow(color: color.withValues(alpha: .6), blurRadius: 8)],
                    )),
                const SizedBox(height: 2),
                Text(label,
                    style: const TextStyle(color: _textMuted, fontSize: 11,
                        fontFamily: 'IBM Plex Sans Arabic')),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _AgencyCard extends StatelessWidget {
  const _AgencyCard({required this.agency});
  final Map agency;

  @override
  Widget build(BuildContext context) {
    context.watch<DynamicConfigService>();
    final name    = agency['name']            ?? 'وكالة';
    final spec    = agency['specialty']       ?? '';
    final rate    = agency['commission_rate'] ?? 0.05;
    final members = agency['member_count']    ?? 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_gold.withOpacity(.08), _bgCard],
          begin: AlignmentDirectional.topStart,
          end:   AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _gold.withOpacity(.3)),
        boxShadow: [BoxShadow(color: _gold.withOpacity(.08), blurRadius: 20)],
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: _gold.withOpacity(.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(child: Text('ðŸ¢', style: TextStyle(fontSize: 24))),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: TextStyle(color: _gold, fontSize: 15,
                    fontWeight: FontWeight.bold, fontFamily: 'IBM Plex Sans Arabic')),
            if (spec.isNotEmpty)
              Text(spec, style: TextStyle(color: _textMuted, fontSize: 12,
                  fontFamily: 'IBM Plex Sans Arabic')),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${(rate * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: _gold, fontSize: 18,
                  fontWeight: FontWeight.bold, fontFamily: 'Space Grotesk')),
          Text('$members عضو',
              style: TextStyle(color: _textMuted, fontSize: 11,
                  fontFamily: 'IBM Plex Sans Arabic')),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({
    required this.milestone,
    required this.shimmer,
    this.onWithdraw,
  });
  final Map milestone;
  final AnimationController shimmer;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    context.watch<DynamicConfigService>();
    final name      = milestone['name']            ?? '';
    final target    = (milestone['target_value']   as num?)?.toDouble() ?? 1;
    final current   = (milestone['current_value']  as num?)?.toDouble() ?? 0;
    final completed = milestone['is_completed']    == true;
    final reward    = milestone['reward_type']     ?? '';
    final rewardVal = milestone['reward_value'];
    final iconUrl   = milestone['reward_image_url'] as String?;
    final bgUrl     = milestone['background_url']   as String?;

    final pct = (current / target).clamp(0.0, 1.0);

    final barColor  = completed ? _gold : _purple;
    final rewardEmoji = _rewardEmoji(reward);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgUrl != null && bgUrl.isNotEmpty ? null : _bgCard,
        image: bgUrl != null && bgUrl.isNotEmpty
            ? DecorationImage(
                image: EncryptedImageProvider(bgUrl),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.4), BlendMode.darken),
              )
            : null,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: completed ? _gold.withOpacity(.6) : _border,
          width: completed ? 1.5 : 1.0,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (iconUrl != null && iconUrl.isNotEmpty) ...[
            Container(
              width: 36, height: 36,
              margin: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.white.withOpacity(0.05),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image(
                  image: EncryptedImageProvider(iconUrl),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.star, color: _gold, size: 20),
                ),
              ),
            ),
          ],
          Expanded(
            child: Text(name,
                style: TextStyle(
                  color: completed ? _gold : _textMain,
                  fontSize: 14, fontWeight: FontWeight.w600,
                  fontFamily: 'IBM Plex Sans Arabic',
                )),
          ),
          if (completed) ...[
            if (onWithdraw != null) ...[
              GestureDetector(
                onTap: onWithdraw,
                child: Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00D4FF), Color(0xFF00E5A0)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.3), blurRadius: 6),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.send_rounded, color: Colors.black, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'سحب المرحلة',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'IBM Plex Sans Arabic',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _gold.withOpacity(.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _gold.withOpacity(.4)),
              ),
              child: const Text('✅ مكتمل',
                  style: TextStyle(color: _gold, fontSize: 11,
                      fontFamily: 'IBM Plex Sans Arabic')),
            ),
          ],
        ]),
        const SizedBox(height: 10),

        // progress bar
        Stack(children: [
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.06),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          AnimatedFractionallySizedBox(
            widthFactor: pct,
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            child: AnimatedBuilder(
              animation: shimmer,
              builder: (_, __) {
                return Container(
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      colors: [
                        barColor.withOpacity(.7),
                        barColor,
                        barColor.withOpacity(.7),
                      ],
                      stops: [
                        (shimmer.value - .3).clamp(0.0, 1.0),
                        shimmer.value.clamp(0.0, 1.0),
                        (shimmer.value + .3).clamp(0.0, 1.0),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(color: barColor.withOpacity(.5), blurRadius: 6),
                    ],
                  ),
                );
              },
            ),
          ),
        ]),

        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${(pct * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: barColor, fontSize: 12,
                    fontFamily: 'Space Grotesk', fontWeight: FontWeight.bold)),
            Text('${_fmt(current)} / ${_fmt(target)} 💎',
                style: TextStyle(color: _textMuted, fontSize: 11,
                    fontFamily: 'Space Grotesk')),
            if (rewardVal != null)
              Text('$rewardEmoji $rewardVal',
                  style: TextStyle(color: _gold, fontSize: 11,
                      fontFamily: 'Space Grotesk')),
          ],
        ),
      ]),
    );
  }

  String _rewardEmoji(String type) {
    switch (type) {
      case 'gold':     return '🪙';
      case 'diamonds': return '💎';
      case 'vip_days': return '👑';
      case 'salary_usd': return '💵';
      case 'frame':    return '🖼️';
      case 'entry_effect': return '🚗';
      case 'badge':    return '🏅';
      default:         return '🎁';
    }
  }

  String _fmt(double n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}م';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}ك';
    return n.toStringAsFixed(0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared micro-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.icon});
  final String label;
  final String icon;

  @override
  Widget build(BuildContext context) {
    context.watch<DynamicConfigService>();
    return Row(children: [
      Text(icon, style: const TextStyle(fontSize: 18)),
      const SizedBox(width: 8),
      Text(label,
          style: const TextStyle(
            color: _textMain, fontSize: 16, fontWeight: FontWeight.bold,
            fontFamily: 'IBM Plex Sans Arabic',
          )),
      const SizedBox(width: 12),
      Expanded(child: Container(height: 1, color: _border)),
    ]);
  }
}

class _VipBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    context.watch<DynamicConfigService>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFF6C453)]),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text('VIP',
          style: TextStyle(color: Colors.black, fontSize: 10,
              fontWeight: FontWeight.bold, fontFamily: 'Space Grotesk')),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.label, required this.color, required this.onTap});
  final String label;
  final Color  color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    context.watch<DynamicConfigService>();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(.4)),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontFamily: 'IBM Plex Sans Arabic',
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _NeonSpinner extends StatefulWidget {
  const _NeonSpinner();

  @override
  State<_NeonSpinner> createState() => _NeonSpinnerState();
}

class _NeonSpinnerState extends State<_NeonSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    context.watch<DynamicConfigService>();
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.rotate(
        angle: _ctrl.value * 2 * math.pi,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(colors: [_purple, _purple.withOpacity(0)]),
            boxShadow: [BoxShadow(color: _purple.withOpacity(.5), blurRadius: 12)],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Agency Wallet & Target Progress Card (HA7 — injected into HostDashboardScreen)
// ─────────────────────────────────────────────────────────────────────────────
class _AgencyWalletCard extends StatelessWidget {
  final HostAgencyStats stats;
  final VoidCallback onExchange;
  final VoidCallback onWithdraw;
  final VoidCallback onLeaderboard;
  final VoidCallback onExit;

  const _AgencyWalletCard({
    required this.stats,
    required this.onExchange,
    required this.onWithdraw,
    required this.onLeaderboard,
    required this.onExit,
  });

  static String _fmtK(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toString();
  }

  static const _tierColors = {
    AgencyTier.bronze:   Color(0xFFCD7F32),
    AgencyTier.silver:   Color(0xFFC0C0C0),
    AgencyTier.gold:     Color(0xFFD4AF37),
    AgencyTier.platinum: Color(0xFF6ADBF5),
    AgencyTier.diamond:  Color(0xFFB39DDB),
  };

  @override
  Widget build(BuildContext context) {
    context.watch<DynamicConfigService>();
    final m          = stats.member;
    final a          = stats.agency;
    final nextTarget = stats.nextTarget;
    final progress   = stats.nextTargetProgress;
    final tierColor  = _tierColors[a?.tier ?? AgencyTier.gold] ?? _gold;

    return Container(
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tierColor.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: tierColor.withOpacity(0.08), blurRadius: 20)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Text('♦ محفظة الوكالة', style: TextStyle(color: tierColor, fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              GestureDetector(
                onTap: onLeaderboard,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: tierColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('🏆 التصنيف', style: TextStyle(color: tierColor, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),

          // Agency name + rank
          if (a != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: Text(a.name,
                style: TextStyle(color: _textMain, fontWeight: FontWeight.w600, fontSize: 14))),
              if (a.rank != null)
                Text('#${a.rank} عالمياً', style: TextStyle(color: tierColor.withOpacity(0.7), fontSize: 12)),
            ]),
          ),

          const SizedBox(height: 14),

          // Diamond wallet stats (✅ يعرض الرصيد المتاح بعد خصم المجمد)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              _WalletStat(label: '♦ الشهر',    value: _fmtK(m.diamondsEarnedMonthly),  color: _purple),
              _WalletStat(label: '♦ المتاح',   value: _fmtK(m.diamondsAvailable),       color: _cyan),
              _WalletStat(label: '♦ التراكمي', value: _fmtK(m.diamondsEarnedCumulative),color: _gold),
            ]),
          ),
          if (m.diamondsPendingWithdrawal > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Icon(Icons.lock_rounded, color: Color(0xFFFF9800), size: 12),
                const SizedBox(width: 4),
                Text('${_fmtK(m.diamondsPendingWithdrawal)} ♦ مجمد',
                    style: const TextStyle(color: Color(0xFFFF9800), fontSize: 11)),
              ]),
            ),
          const SizedBox(height: 4),

          const SizedBox(height: 14),

          // Target progress
          if (nextTarget != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('🎯 الهدف التالي: ', style: TextStyle(color: _textMuted, fontSize: 12)),
              Text('♦ محفظة الوكالة', style: TextStyle(color: tierColor, fontWeight: FontWeight.bold, fontSize: 15)),
                    const Spacer(),
                    Text('${(progress * 100).toStringAsFixed(0)}%', style: TextStyle(color: tierColor, fontSize: 12, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white.withOpacity(0.06),
                      valueColor: AlwaysStoppedAnimation<Color>(tierColor),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('المكافأة: ${nextTarget.rewardSummary}',
                    style: TextStyle(color: _textMuted, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Row(children: [
              Expanded(child: _WalletBtn(label: '🪙 تبادل', color: _cyan, onTap: onExchange)),
              const SizedBox(width: 8),
              Expanded(child: _WalletBtn(label: '💸 سحب', color: _gold, onTap: onWithdraw)),
              const SizedBox(width: 8),
              Expanded(child: _WalletBtn(label: '🚪 خروج', color: _red, onTap: onExit)),
            ]),
          ),

          // Rank in agency
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 14),
            child: Text(
              'ترتيبك في الوكالة: #${stats.rankInAgency} من ${stats.totalMembersInAgency}',
              style: TextStyle(color: _textMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletStat extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _WalletStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    context.watch<DynamicConfigService>();
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: _textMuted, fontSize: 10)),
        ]),
      ),
    );
  }
}

class _WalletBtn extends StatelessWidget {
  final String label;
  final Color  color;
  final VoidCallback onTap;
  const _WalletBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    context.watch<DynamicConfigService>();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// بطاقة البيانات الشهرية ونظام التارجت الأصلي المطابق لـ D:40
// layout: guild_anchor_monthly_data_view_layout.xml
// ─────────────────────────────────────────────────────────────────────────────
class _D40MonthlyDataCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final List<Map> milestones;
  final AnimationController pulse;

  const _D40MonthlyDataCard({
    required this.data,
    required this.milestones,
    required this.pulse,
  });

  String _fmtCompact(num val) {
    if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(1)}M';
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(0)}K';
    return val.toInt().toString();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<DynamicConfigService>();

    final monthDiamonds = (data['month_diamonds'] as num?)?.toInt() ?? 0;
    final liveHours = (data['live_hours_monthly'] as num?)?.toInt() ?? 0;
    final validDays = (data['valid_days_monthly'] as num?)?.toInt() ?? 0;
    final profile = data['profile'] as Map? ?? {};
    final level = profile['level'] ?? 1;

    // العثور على التارجت التالي وتارجت الشهر المحقق
    Map? nextMilestone;
    Map? achievedMilestone;
    for (final m in milestones) {
      final target = (m['target_value'] as num?)?.toInt() ?? 0;
      if (monthDiamonds >= target) {
        achievedMilestone = m;
      } else if (nextMilestone == null) {
        nextMilestone = m;
      }
    }
    nextMilestone ??= milestones.isNotEmpty ? milestones.last : null;

    final targetVal = (nextMilestone?['target_value'] as num?)?.toInt() ?? 100000;
    final progressPct = targetVal > 0 ? (monthDiamonds / targetVal).clamp(0.0, 1.0) : 0.0;
    final bonusVal = achievedMilestone != null
        ? (achievedMilestone['reward_value'] as num?)?.toInt() ?? (achievedMilestone['reward_coins'] as num?)?.toInt() ?? 0
        : (nextMilestone?['reward_coins'] as num?)?.toInt() ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16192E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان البطاقة ورأس التقدم
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.insights_rounded, color: Color(0xFFF5A601), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'البيانات الشهرية والتارجت (D:40)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'IBM Plex Sans Arabic',
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5A601).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF5A601).withOpacity(0.3)),
                ),
                child: Text(
                  '${(progressPct * 100).toStringAsFixed(1)}% مكتمل',
                  style: const TextStyle(
                    color: Color(0xFFF5A601),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Space Grotesk',
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // شريط التقدم نحو التارجت التالي
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progressPct,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF5A601)),
              minHeight: 7,
            ),
          ),

          const SizedBox(height: 16),

          // شبكة الحقول الـ 6 المطابقة تماماً لـ guild_anchor_monthly_data_view_layout.xml
          // الصف الأول: تارجت الكوينز + ألماس المضيف
          Row(
            children: [
              Expanded(
                child: _D40MetricTile(
                  title: 'تارجت الهدف القادم',
                  value: _fmtCompact(targetVal),
                  unit: '💎',
                  color: const Color(0xFFF5A601),
                  icon: Icons.track_changes_rounded,
                  bgGradient: const [Color(0x22F5A601), Color(0x05F5A601)],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _D40MetricTile(
                  title: 'ألماس هذا الشهر',
                  value: _fmtCompact(monthDiamonds),
                  unit: '💎',
                  color: const Color(0xFF7686FF),
                  icon: Icons.diamond_rounded,
                  bgGradient: const [Color(0x227686FF), Color(0x057686FF)],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // الصف الثاني: ساعات البث المباشر + أيام البث الفعالة
          Row(
            children: [
              Expanded(
                child: _D40MetricTile(
                  title: 'ساعات البث',
                  value: '$liveHours',
                  unit: 'ساعة',
                  color: const Color(0xFF8C5FFF),
                  icon: Icons.access_time_filled_rounded,
                  bgGradient: const [Color(0x228C5FFF), Color(0x058C5FFF)],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _D40MetricTile(
                  title: 'أيام النشاط الفعالة',
                  value: '$validDays',
                  unit: 'يوم',
                  color: const Color(0xFFFF5A7C),
                  icon: Icons.calendar_today_rounded,
                  bgGradient: const [Color(0x22FF5A7C), Color(0x05FF5A7C)],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // الصف الثالث: مستوى المضيف + بونص التارجت المالي
          Row(
            children: [
              Expanded(
                child: _D40MetricTile(
                  title: 'رتبة وتصنيف المضيف',
                  value: 'Lv.$level',
                  unit: '',
                  color: const Color(0xFF00E5A0),
                  icon: Icons.military_tech_rounded,
                  bgGradient: const [Color(0x2200E5A0), Color(0x0500E5A0)],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _D40MetricTile(
                  title: 'بونص التارجت المالي',
                  value: bonusVal > 0 ? _fmtCompact(bonusVal) : '0',
                  unit: '🪙',
                  color: const Color(0xFFFFCF5A),
                  icon: Icons.card_giftcard_rounded,
                  bgGradient: const [Color(0x22FFCF5A), Color(0x05FFCF5A)],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _D40MetricTile extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final Color color;
  final IconData icon;
  final List<Color> bgGradient;

  const _D40MetricTile({
    required this.title,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
    required this.bgGradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: bgGradient,
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 11,
                    fontFamily: 'IBM Plex Sans Arabic',
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Space Grotesk',
                      ),
                    ),
                    if (unit.isNotEmpty) ...[
                      const SizedBox(width: 3),
                      Text(
                        unit,
                        style: TextStyle(
                          color: color.withOpacity(0.8),
                          fontSize: 11,
                          fontFamily: 'IBM Plex Sans Arabic',
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
//  WIDGETS — المحرك الاقتصادي v3
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

// ─ بانر: المحرك v3 مُفعَّل ──────────────────────────────────────────────────
class _EngineV3Banner extends StatelessWidget {
  final Map<String, dynamic> v3;
  const _EngineV3Banner({required this.v3});

  @override
  Widget build(BuildContext context) {
    context.watch<DynamicConfigService>();
    final dryRun = v3['dry_run'] == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: dryRun
              ? [const Color(0xFF3D2A00), const Color(0xFF1A1000)]
              : [const Color(0xFF0A2A0A), const Color(0xFF030F03)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dryRun ? const Color(0xFFF59E0B) : const Color(0xFF22C55E),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Text(dryRun ? 'ðŸ§ª' : 'ðŸš€', style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              dryRun ? 'المحرك v2 — وضع الاختبار (لا مدفوعات حقيقية)'
                     : 'المحرك الاقتصادي v2 مُفعَّل — كوينز + مستويات + USD',
              style: TextStyle(
                color: dryRun ? const Color(0xFFF59E0B) : const Color(0xFF22C55E),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─ بطاقة: تقدم الكوينز نحو المستوى التالي ───────────────────────────────────
class _CoinsProgressCard extends StatelessWidget {
  final Map<String, dynamic> v3;
  final AnimationController shimmer;
  const _CoinsProgressCard({required this.v3, required this.shimmer});

  String _fmt(num n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}م';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}ك';
    return n.toInt().toString();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<DynamicConfigService>();
    final totalCoins   = (v3['received_coins_monthly'] as num?)?.toInt() ?? 0;
    final nextLevel    = v3['next_level'] as Map<String, dynamic>?;
    final levelsUnlocked = (v3['levels_unlocked'] as List?)?.cast<int>() ?? [];
    final curLevel     = (v3['current_level_number'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x800A0820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x2D9C6BFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🪙', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              const Text(
                'تقدم الكوينز الشهري',
                style: TextStyle(
                  color: Color(0xFFE8E6FF),
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              if (curLevel > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0x33F6C453),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x66F6C453)),
                  ),
                  child: Text(
                    'المستوى $curLevel ðŸ†',
                    style: const TextStyle(color: Color(0xFFF6C453), fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Total coins earned this month
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmt(totalCoins),
                style: const TextStyle(
                  color: Color(0xFF00D4FF),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text(
                ' كوينز هذا الشهر',
                style: TextStyle(color: Color(0xFF8A88AA), fontSize: 13),
              ),
            ],
          ),

          // Next level progress
          if (nextLevel != null) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  nextLevel['level_name'] ?? 'المستوى التالي',
                  style: const TextStyle(color: Color(0xFFF6C453), fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${_fmt((nextLevel['remaining_coins'] as num?) ?? 0)} متبقي',
                  style: const TextStyle(color: Color(0xFF8A88AA), fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ((nextLevel['pct_progress'] as num?)?.toDouble() ?? 0) / 100,
                backgroundColor: const Color(0x22FFFFFF),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF6C453)),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${nextLevel['pct_progress']?.toStringAsFixed(1) ?? 0}%',
                  style: const TextStyle(color: Color(0xFFF6C453), fontSize: 11, fontWeight: FontWeight.w600),
                ),
                Text(
                  'مكافأة: \$${nextLevel["host_cash_usd"] ?? 0} + 💎${_fmt((nextLevel["host_diamond_usd"] as num?) ?? 0)}',
                  style: const TextStyle(color: Color(0xFF22C55E), fontSize: 11),
                ),
              ],
            ),
          ] else if (levelsUnlocked.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 18),
                SizedBox(width: 6),
                Text(
                  'أنجزت جميع المستويات هذا الشهر! 🎉',
                  style: TextStyle(color: Color(0xFF22C55E), fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],

          // Unlocked levels badges
          if (levelsUnlocked.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: levelsUnlocked.map((lvl) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF1D3A00), Color(0xFF0A1A00)]),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF22C55E)),
                ),
                child: Text('✅ مستوى $lvl مكتمل',
                  style: const TextStyle(color: Color(0xFF22C55E), fontSize: 11, fontWeight: FontWeight.w600)),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ─ بطاقة: محفظة USD ──────────────────────────────────────────────────────────
class _UsdWalletCard extends StatelessWidget {
  final Map<String, dynamic> v3;
  const _UsdWalletCard({required this.v3});

  @override
  Widget build(BuildContext context) {
    context.watch<DynamicConfigService>();
    final usdBalance  = (v3['usd_balance'] as num?)?.toDouble() ?? 0;
    final totalEarned = (v3['total_earned_usd'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A1A0A), Color(0xFF030F03)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x4422C55E)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0x2222C55E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: Text('ðŸ’µ', style: TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('محفظة الدولار', style: TextStyle(color: Color(0xFF8A88AA), fontSize: 12)),
                Text(
                  '\$${usdBalance.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF22C55E),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'إجمالي المكتسَب: \$${totalEarned.toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
                ),
              ],
            ),
          ),
          if (usdBalance > 0)
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgencyWithdrawalScreen())),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0x2222C55E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x6622C55E)),
                ),
                child: const Text('سحب →', style: TextStyle(color: Color(0xFF22C55E), fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

// ─ بطاقة: عداد تنازلي لنهاية الشهر ──────────────────────────────────────────
class _MonthCountdownCard extends StatelessWidget {
  final Map<String, dynamic> v3;
  const _MonthCountdownCard({required this.v3});

  @override
  Widget build(BuildContext context) {
    context.watch<DynamicConfigService>();
    final secs = (v3['month_end_countdown_secs'] as num?)?.toInt() ?? 0;
    final days  = secs ~/ 86400;
    final hours = (secs % 86400) ~/ 3600;
    final mins  = (secs % 3600) ~/ 60;
    final s     = secs % 60;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x801A0820),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x449C6BFF)),
      ),
      child: Row(
        children: [
          const Text('â°', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('متبقي حتى إغلاق الشهر', style: TextStyle(color: Color(0xFF8A88AA), fontSize: 11)),
              const SizedBox(height: 4),
              Text(
                '$days يوم  $hours:${mins.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: Color(0xFF9C6BFF),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}



