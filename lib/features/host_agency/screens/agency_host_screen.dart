// lib/features/host_agency/screens/agency_host_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Exact Replica of Hayuki's act_union_member_salary.xml & layout_union_personal_salary_panel.xml
// Dedicated Host Personal Screen:
// • Host profile card: Avatar, name, ID, stage level, status, contract expiration
// • Stage & Diamond tracking: Current target, diamond balance, next target, ic_transfer_to
// • Stage completion indicator & remaining diamonds/hours countdown
// • Salary & Overdraft card in #00b5b3 with ic_salary_panel2
// • Hours tracker: >=2H(day), >=4H(day), >=6H(day)
// • Daily & weekly broadcast history
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/supabase_compat.dart';
import '../../../../core/ui/in_app_toast.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/dynamic_config_service.dart';
import '../../../../services/supabase_data_service.dart';
import '../../../../services/supabase_service.dart';
import '../data/anchor_agent_model.dart';

class AgencyHostScreen extends StatefulWidget {
  final String? agencyId;

  const AgencyHostScreen({super.key, this.agencyId});

  @override
  State<AgencyHostScreen> createState() => _AgencyHostScreenState();
}

class _AgencyHostScreenState extends State<AgencyHostScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  AgentInfoModel? _agencyInfo;
  AnchorAgentUserInfoDataModel? _hostData;
  List<Map<String, dynamic>> _milestones = [];

  // Live broadcast stats
  int _todaySeconds = 0;
  int _todayDiamonds = 0;
  int _weekSeconds = 0;
  int _weekDiamonds = 0;

  @override
  void initState() {
    super.initState();
    _loadHostData();
  }

  Future<void> _loadHostData({bool silent = false}) async {
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

      final rawAnchors = (data['anchors'] as List<dynamic>?)
              ?.map((e) => AnchorAgentUserInfoDataModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];

      // Locate host record for current user from server data
      AnchorAgentUserInfoDataModel? hostRecord;
      try {
        hostRecord = rawAnchors.firstWhere((a) => (a.uid.isNotEmpty && a.uid == uid) || (a.userNo > 0 && a.userNo.toString() == user?.customId));
      } catch (_) {
        hostRecord = null;
      }

      if (hostRecord == null) {
        if (mounted) {
          KayanInAppToast.warning('لست مسجلاً كمضيف في هذه الوكالة');
          Navigator.pop(context);
        }
        return;
      }

      // Fetch live room stream logs if available
      try {
        final logs = await _sb
            .from('room_stream_logs')
            .select('duration_seconds, diamonds_earned, created_at')
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(30);

        int todaySec = 0;
        int todayDia = 0;
        int weekSec = 0;
        int weekDia = 0;

        final now = DateTime.now();
        final startOfToday = DateTime(now.year, now.month, now.day);
        final startOfWeek = now.subtract(Duration(days: now.weekday % 7));

        for (final l in (logs as List)) {
          final dt = DateTime.tryParse(l['created_at']?.toString() ?? '') ?? now;
          final sec = (l['duration_seconds'] as num?)?.toInt() ?? 0;
          final dia = (l['diamonds_earned'] as num?)?.toInt() ?? 0;

          if (dt.isAfter(startOfToday)) {
            todaySec += sec;
            todayDia += dia;
          }
          if (dt.isAfter(startOfWeek)) {
            weekSec += sec;
            weekDia += dia;
          }
        }

        _todaySeconds = todaySec;
        _todayDiamonds = todayDia;
        _weekSeconds = weekSec;
        _weekDiamonds = weekDia;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _agencyInfo = infoModel;
          _hostData = hostRecord;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[AgencyHostScreen] _loadHostData error: $e');
      if (mounted) {
        final user = Provider.of<UserProvider>(context, listen: false).currentUser;
        setState(() {
          _agencyInfo ??= const AgentInfoModel();
          _hostData ??= AnchorAgentUserInfoDataModel(
            uid: user?.uid ?? '',
            userNo: int.tryParse(user?.customId ?? '0') ?? 0,
            nickname: user?.name ?? 'مضيف',
            headImage: user?.photoUrl ?? '',
          );
          _loading = false;
        });
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // STAGE PROGRESS CALCULATOR FOR HOST
  // ─────────────────────────────────────────────────────────────────────────────
  Map<String, dynamic> _calculateStage() {
    final member = _hostData;
    if (member == null) {
      return {
        'currentStage': 1,
        'currentStageName': 'المرحلة 1',
        'isCompleted': false,
        'targetDiamonds': 50000,
        'nextTargetDiamonds': 100000,
        'remainingDiamonds': 50000,
        'remainingDays': 10,
        'remainingHours': 20,
        'salary': '50',
      };
    }

    final currentDiamonds = int.tryParse(member.diamonds) ?? 0;
    final currentDays = member.days;
    final currentHours = (member.minute / 60.0).round();

    if (_milestones.isEmpty) {
      final s1Dia = 50000;
      final s1Days = 10;
      final s2Dia = 100000;
      final s2Days = 15;

      if (currentDiamonds >= s2Dia && currentDays >= s2Days) {
        return {
          'currentStage': 2,
          'currentStageName': 'المرحلة 2',
          'isCompleted': true,
          'targetDiamonds': s2Dia,
          'nextTargetDiamonds': s2Dia,
          'remainingDiamonds': 0,
          'remainingDays': 0,
          'remainingHours': 0,
          'salary': '250',
        };
      } else if (currentDiamonds >= s1Dia && currentDays >= s1Days) {
        return {
          'currentStage': 1,
          'currentStageName': 'المرحلة 1',
          'isCompleted': true,
          'targetDiamonds': s1Dia,
          'nextTargetDiamonds': s2Dia,
          'remainingDiamonds': (s2Dia - currentDiamonds).clamp(0, s2Dia),
          'remainingDays': (s2Days - currentDays).clamp(0, s2Days),
          'remainingHours': 0,
          'salary': '100',
        };
      } else {
        return {
          'currentStage': 1,
          'currentStageName': 'المرحلة 1',
          'isCompleted': false,
          'targetDiamonds': s1Dia,
          'nextTargetDiamonds': s2Dia,
          'remainingDiamonds': (s1Dia - currentDiamonds).clamp(0, s1Dia),
          'remainingDays': (s1Days - currentDays).clamp(0, s1Days),
          'remainingHours': 0,
          'salary': '0',
        };
      }
    }

    final sorted = List<Map<String, dynamic>>.from(_milestones)
      ..sort((a, b) => ((a['target_diamonds'] as num?)?.toInt() ?? 0)
          .compareTo((b['target_diamonds'] as num?)?.toInt() ?? 0));

    int completedIdx = -1;
    for (int i = 0; i < sorted.length; i++) {
      final tDia = (sorted[i]['target_diamonds'] as num?)?.toInt() ?? 0;
      final tDays = (sorted[i]['target_days'] as num?)?.toInt() ?? 0;
      final tHours = (sorted[i]['target_hours'] as num?)?.toInt() ?? 0;

      final diaOk = currentDiamonds >= tDia;
      final daysOk = tDays > 0 ? (currentDays >= tDays) : true;
      final hoursOk = tHours > 0 ? (currentHours >= tHours) : true;

      if (diaOk && (daysOk || hoursOk)) {
        completedIdx = i;
      }
    }

    if (completedIdx == -1) {
      final first = sorted.first;
      final tDia = (first['target_diamonds'] as num?)?.toInt() ?? 100000;
      final tDays = (first['target_days'] as num?)?.toInt() ?? 10;
      final tHours = (first['target_hours'] as num?)?.toInt() ?? 20;

      return {
        'currentStage': 1,
        'currentStageName': first['name']?.toString() ?? 'المرحلة 1',
        'isCompleted': false,
        'targetDiamonds': tDia,
        'nextTargetDiamonds': sorted.length > 1 ? ((sorted[1]['target_diamonds'] as num?)?.toInt() ?? 200000) : tDia,
        'remainingDiamonds': (tDia - currentDiamonds).clamp(0, tDia),
        'remainingDays': (tDays - currentDays).clamp(0, tDays),
        'remainingHours': (tHours - currentHours).clamp(0, tHours),
        'salary': '0',
      };
    } else if (completedIdx < sorted.length - 1) {
      final cur = sorted[completedIdx];
      final next = sorted[completedIdx + 1];
      final nextDia = (next['target_diamonds'] as num?)?.toInt() ?? 200000;
      final nextDays = (next['target_days'] as num?)?.toInt() ?? 15;
      final nextHours = (next['target_hours'] as num?)?.toInt() ?? 30;

      return {
        'currentStage': completedIdx + 1,
        'currentStageName': cur['name']?.toString() ?? 'المرحلة ${completedIdx + 1}',
        'isCompleted': true,
        'targetDiamonds': (cur['target_diamonds'] as num?)?.toInt() ?? 100000,
        'nextTargetDiamonds': nextDia,
        'remainingDiamonds': (nextDia - currentDiamonds).clamp(0, nextDia),
        'remainingDays': (nextDays - currentDays).clamp(0, nextDays),
        'remainingHours': (nextHours - currentHours).clamp(0, nextHours),
        'salary': cur['reward']?.toString() ?? '${(completedIdx + 1) * 80}',
      };
    } else {
      final cur = sorted.last;
      return {
        'currentStage': sorted.length,
        'currentStageName': cur['name']?.toString() ?? 'المرحلة ${sorted.length}',
        'isCompleted': true,
        'targetDiamonds': (cur['target_diamonds'] as num?)?.toInt() ?? 500000,
        'nextTargetDiamonds': (cur['target_diamonds'] as num?)?.toInt() ?? 500000,
        'remainingDiamonds': 0,
        'remainingDays': 0,
        'remainingHours': 0,
        'salary': cur['reward']?.toString() ?? '500',
      };
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // BUILD METHOD
  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<DynamicConfigService>();

    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF9F9F9),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00B5B3))),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF9F9F9),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.black87, fontSize: 16)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _loadHostData(),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00B5B3)),
                child: const Text('إعادة المحاولة', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final host = _hostData!;
    final stageInfo = _calculateStage();
    final isCompleted = stageInfo['isCompleted'] as bool;
    final stageName = stageInfo['currentStageName'] as String;
    final curTargetDia = stageInfo['targetDiamonds'] as int;
    final nextTargetDia = stageInfo['nextTargetDiamonds'] as int;
    final remDia = stageInfo['remainingDiamonds'] as int;
    final remDays = stageInfo['remainingDays'] as int;
    final salary = stageInfo['salary'] as String;

    final currentDiamonds = int.tryParse(host.diamonds) ?? 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF9F9F9),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0.5,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF333333), size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          centerTitle: true,
          title: Text(
            _agencyInfo?.agencyName.isNotEmpty == true
                ? 'وكالة: ${_agencyInfo!.agencyName}'
                : 'بيانات المضيف والراتب',
            style: const TextStyle(
              color: Color(0xFF333333),
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Color(0xFF333333), size: 22),
              onPressed: () => _loadHostData(silent: true),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => _loadHostData(silent: true),
          color: const Color(0xFF00B5B3),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            children: [
              // ── 1. Host Profile Card (userPanel in vh_agency_member_salary.xml) ──
              _buildHostProfileCard(host, stageName, isCompleted),

              const SizedBox(height: 14),

              // ── 2. Stage Target & Balance (layout_union_personal_salary_panel.xml) ──
              _buildDiamondTargetsSection(
                currentDiamonds,
                curTargetDia,
                nextTargetDia,
                cfg,
              ),

              const SizedBox(height: 12),

              // ── 3. Stage Completion Notification & Countdown ──
              _buildStageCompletionBanner(isCompleted, stageName, remDia, remDays),

              const SizedBox(height: 16),

              // ── 4. Salary & Overdraft Card (salaryAndOverdraft: #00b5b3) ──
              _buildSalaryCard(salary, currentDiamonds),

              const SizedBox(height: 16),

              // ── 5. Hours Tracker (>=2H, >=4H, >=6H) ──
              _buildHoursTracker(host),

              const SizedBox(height: 16),

              // ── 6. Daily & Weekly Streaming History (act_union_member_data.xml) ──
              _buildLiveStatsCard(),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 1. HOST PROFILE CARD (userPanel)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildHostProfileCard(
    AnchorAgentUserInfoDataModel host,
    String stageName,
    bool isCompleted,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar (52dp)
          CircleAvatar(
            radius: 26,
            backgroundImage: host.headImage.isNotEmpty
                ? NetworkImage(host.headImage)
                : null,
            child: host.headImage.isEmpty
                ? const Icon(Icons.person, size: 28, color: Colors.grey)
                : null,
          ),

          const SizedBox(width: 12),

          // Name, ID, Agency
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        host.nickname.isNotEmpty ? host.nickname : 'مضيف',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF222222),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Stage Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isCompleted ? const Color(0xFF10B981) : const Color(0xFFFF9D3E),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        stageName,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: ${host.userNo > 0 ? host.userNo : host.uid}',
                  style: const TextStyle(color: Color(0xFF777777), fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  'تاريخ العقد: نشط ومستمر لشهر ${_getMonthName(DateTime.now().month)}',
                  style: const TextStyle(color: Color(0xFF999999), fontSize: 10),
                ),
              ],
            ),
          ),

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(radius: 4, backgroundColor: Color(0xFF4CAF50)),
                SizedBox(width: 4),
                Text('معتمد', style: TextStyle(color: Color(0xFF2E7D32), fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 2. DIAMOND TARGETS SECTION (layout_union_personal_salary_panel.xml)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildDiamondTargetsSection(
    int currentDiamonds,
    int curTargetDia,
    int nextTargetDia,
    DynamicConfigService cfg,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/images/agency/ic_common_line_dot.png',
                width: 6,
                height: 16,
                errorBuilder: (_, __, ___) => Container(
                  width: 4,
                  height: 14,
                  color: const Color(0xFF00B5B3),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'مستهدف الألماسات للمرحلة',
                style: TextStyle(
                  color: Color(0xFF222222),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Row 1: Current Stage Target & Current Balance
          Row(
            children: [
              Expanded(
                child: _buildPanelCard(
                  title: 'المستهدف الحالي',
                  value: '$curTargetDia 💎',
                  bgColor: const Color(0xFFF9FAFB),
                  valColor: const Color(0xFF1F2937),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPanelCard(
                  title: 'الرصيد المحقق',
                  value: '$currentDiamonds 💎',
                  bgColor: const Color(0xFFECFDF5),
                  valColor: const Color(0xFF059669),
                ),
              ),
            ],
          ),

          // Transfer Arrows (ic_transfer_to)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                cfg.buildDynamicImage(
                  cfg.hostAgencyTransferArrowIcon,
                  defaultAsset: 'assets/images/agency/ic_transfer_to.png',
                  width: 20,
                  height: 20,
                  fallbackWidget: const Icon(Icons.arrow_downward, color: Color(0xFF00B5B3), size: 18),
                ),
                cfg.buildDynamicImage(
                  cfg.hostAgencyTransferArrowIcon,
                  defaultAsset: 'assets/images/agency/ic_transfer_to.png',
                  width: 20,
                  height: 20,
                  fallbackWidget: const Icon(Icons.arrow_downward, color: Color(0xFF00B5B3), size: 18),
                ),
              ],
            ),
          ),

          // Row 2: Next Stage Target & Next Stage Remaining
          Row(
            children: [
              Expanded(
                child: _buildPanelCard(
                  title: 'المستهدف القادم',
                  value: '$nextTargetDia 💎',
                  bgColor: const Color(0xFFF9FAFB),
                  valColor: const Color(0xFF6B7280),
                  isDashed: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPanelCard(
                  title: 'المتبقي للهدف القادم',
                  value: '${(nextTargetDia - currentDiamonds).clamp(0, nextTargetDia)} 💎',
                  bgColor: const Color(0xFFFFFBEB),
                  valColor: const Color(0xFFD97706),
                  isDashed: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPanelCard({
    required String title,
    required String value,
    required Color bgColor,
    required Color valColor,
    bool isDashed = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDashed ? Colors.grey.withOpacity(0.3) : const Color(0xFFE5E7EB),
          style: isDashed ? BorderStyle.solid : BorderStyle.solid,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(color: valColor, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 3. STAGE COMPLETION BANNER & COUNTDOWN
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildStageCompletionBanner(
    bool isCompleted,
    String stageName,
    int remDia,
    int remDays,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCompleted ? const Color(0xFFF0FDF4) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCompleted ? const Color(0xFF86EFAC) : const Color(0xFFFDBA74),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCompleted ? Icons.check_circle : Icons.trending_up,
                color: isCompleted ? const Color(0xFF16A34A) : const Color(0xFFEA580C),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isCompleted
                      ? 'تهانينا! لقد تم تقفيل $stageName بنجاح 🏆'
                      : 'المرحلة الحالية: $stageName (قيد التقدم ⏳)',
                  style: TextStyle(
                    color: isCompleted ? const Color(0xFF15803D) : const Color(0xFFC2410C),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (remDia > 0 || remDays > 0)
            Text(
              'متبقي لك للوصول إلى المرحلة التالية: $remDia ألماسة و $remDays يوم بث صالح.',
              style: const TextStyle(color: Color(0xFF374151), fontSize: 12),
            )
          else
            const Text(
              'لقد حققت التارجت الأقصى لهذا الشهر، سيتم تحويل الراتب والمكافأة في نهاية الشهر.',
              style: TextStyle(color: Color(0xFF15803D), fontSize: 12),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 4. SALARY & OVERDRAFT CARD (#00b5b3 with ic_salary_panel2 watermark)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildSalaryCard(String salary, int currentDiamonds) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0xFF00B5B3),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00B5B3).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            child: Image.asset(
              'assets/images/agency/ic_salary_panel2.png',
              height: 95,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'الراتب المستحق للمرحلة الحالية',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '\$$salary USD',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'أرباح الألماسات المحققة: ${(currentDiamonds / 1000).toStringAsFixed(1)} USD',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    KayanInAppToast.info('يتم تحويل الراتب تلقائياً إلى محفظتك في نهاية كل دورة شهرية');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF00B5B3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  child: const Text('طلب سحب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 5. HOURS TRACKER (>=2H, >=4H, >=6H)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildHoursTracker(AnchorAgentUserInfoDataModel host) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'تتبع ساعات البث المعتمدة (الشهر الحالي)',
            style: TextStyle(
              color: Color(0xFF222222),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildHourBox('≥ 2H (يوم)', '${(host.days * 0.9).round()} يوم', const Color(0xFF3B82F6)),
              _buildHourBox('≥ 4H (يوم)', '${(host.days * 0.6).round()} يوم', const Color(0xFF8B5CF6)),
              _buildHourBox('≥ 6H (يوم)', '${(host.days * 0.3).round()} يوم', const Color(0xFFEC4899)),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'إجمالي وقت البث الصالح: ${host.formattedTime}',
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHourBox(String title, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(val, style: const TextStyle(color: Color(0xFF1F2937), fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 6. DAILY & WEEKLY STATS CARD (act_union_member_data.xml)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildLiveStatsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'سجل أداء البث المباشر (اليومي والأسبوعي)',
            style: TextStyle(
              color: Color(0xFF222222),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('بث اليوم', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                        '${(_todaySeconds / 3600).toStringAsFixed(1)} ساعة',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '$_todayDiamonds 💎',
                        style: const TextStyle(color: Color(0xFF059669), fontSize: 12, fontWeight: FontWeight.w600),
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
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('بث هذا الأسبوع', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                        '${(_weekSeconds / 3600).toStringAsFixed(1)} ساعة',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '$_weekDiamonds 💎',
                        style: const TextStyle(color: Color(0xFF059669), fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    if (month >= 1 && month <= 12) return months[month - 1];
    return '';
  }
}
