import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../agent_recharge_widgets.dart';
import '../agent_recharge_models.dart';

class AgentDashboardTab extends StatelessWidget {
  const AgentDashboardTab({
    super.key,
    required this.dashboard,
    required this.onRefresh,
    required this.onGoRecharge,
  });

  final AgentDashboardData dashboard;
  final VoidCallback        onRefresh;
  final VoidCallback        onGoRecharge;

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final d = dashboard;

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: KayanBrandColors.logoPrimary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _buildAgencySummaryCard(d),
          const SizedBox(height: 14),
          _buildKpiGrid(d),
          const SizedBox(height: 14),
          _buildWeekChart(d.weekChart),
          const SizedBox(height: 14),
          _buildRecentTxns(d.recentTxns),
          const SizedBox(height: 14),
          _buildQuickActions(context),
        ],
      ),
    );
  }

  // ─── Agency Wallet Summary Card ──────────────────────────────────
  Widget _buildAgencySummaryCard(AgentDashboardData d) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF16213E).withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(
            children: [
              const Text('🏅', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Text(
                'رصيد محفظة وكالة الشحن',
                style: GoogleFonts.tajawal(
                  fontSize: 14,
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.5)),
            ),
            child: Text(
              'وكالة نشطة ⚡',
              style: GoogleFonts.tajawal(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: const Color(0xFFFFD700),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${_fmt(d.agencyGold)} 🪙',
                style: GoogleFonts.tajawal(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFFFD700),
                ),
              ),
              Text(
                'كوين متاح لشحن المستخدمين',
                style: GoogleFonts.tajawal(fontSize: 11, color: Colors.white54),
              ),
            ]),
            ElevatedButton.icon(
              onPressed: onGoRecharge,
              icon: const Icon(Icons.send_rounded, size: 14),
              label: Text('شحن فوري', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '⚡ إجمالي شحن اليوم: ${_fmt(d.todayTotal)} كوين',
                style: GoogleFonts.tajawal(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
              ),
              Text(
                '${d.todayCount} عملية اليوم',
                style: GoogleFonts.tajawal(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  // ─── KPI Grid 2×2 ────────────────────────────────────────────────
  Widget _buildKpiGrid(AgentDashboardData d) {
    final kpis = [
      {
        'label': 'هذا الأسبوع',
        'value': _fmt(d.weekTotal),
        'sub': '${d.weekCount} عملية',
        'color': const Color(0xFF2196F3),
        'icon': '📅',
      },
      {
        'label': 'هذا الشهر',
        'value': _fmt(d.monthTotal),
        'sub': '${d.monthCount} عملية',
        'color': const Color(0xFF9C27B0),
        'icon': '🗓',
      },
      {
        'label': 'إجمالي الشحن',
        'value': _fmt(d.allTotal),
        'sub': '${d.allCount} عملية',
        'color': const Color(0xFFFF9800),
        'icon': '📈',
      },
      {
        'label': 'معدل اليومي',
        'value': d.allCount > 0
            ? _fmt(d.allTotal ~/ math.max(1, d.allCount))
            : '0',
        'sub': 'كوين/عملية',
        'color': const Color(0xFF4CAF50),
        'icon': '⚡',
      },
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.6,
      children: kpis
          .map((k) => Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(k['icon']!.toString(),
                              style: const TextStyle(fontSize: 20)),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: (k['color'] as Color)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(k['sub']!.toString(),
                                style: GoogleFonts.tajawal(
                                    fontSize: 9,
                                    color: k['color'] as Color,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(k['value']!.toString(),
                          style: GoogleFonts.tajawal(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: k['color'] as Color)),
                      Text(k['label']!.toString(),
                          style: GoogleFonts.tajawal(
                              fontSize: 11, color: Colors.black45)),
                    ]),
                  ],
                ),
              ))
          .toList(),
    );
  }

  // ─── Week Bar Chart ───────────────────────────────────────────────
  Widget _buildWeekChart(List<AgentDayChart> chart) {
    if (chart.isEmpty) return const SizedBox.shrink();
    final maxVal = chart.fold(0, (m, d) => math.max(m, d.total));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06), blurRadius: 12),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('الأسبوع الأخير',
              style: GoogleFonts.tajawal(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1a1a2e))),
          Text('آخر 7 أيام',
              style: GoogleFonts.tajawal(fontSize: 11, color: Colors.black38)),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 100,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(chart.length, (i) {
              final day = chart[i];
              final ratio = maxVal > 0 ? day.total / maxVal : 0.0;
              final isToday = i == 0;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (day.total > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              day.total >= 1000
                                  ? '${(day.total / 1000).toStringAsFixed(0)}K'
                                  : day.total.toString(),
                              style: GoogleFonts.tajawal(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: isToday
                                    ? KayanBrandColors.logoPrimary
                                    : Colors.black38,
                              ),
                            ),
                          ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: AnimatedContainer(
                            duration: Duration(milliseconds: 400 + i * 60),
                            height: math.max(6.0, ratio * 70),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: isToday
                                    ? [
                                        KayanBrandColors.logoPrimary,
                                        KayanBrandColors.logoPrimary
                                            .withValues(alpha: 0.5),
                                      ]
                                    : [
                                        const Color(0xFF2196F3),
                                        const Color(0xFF2196F3)
                                            .withValues(alpha: 0.4),
                                      ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isToday ? 'اليوم' : _shortDay(day.day),
                          style: GoogleFonts.tajawal(
                            fontSize: 9,
                            color: isToday
                                ? KayanBrandColors.logoPrimary
                                : Colors.black38,
                            fontWeight: isToday
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ]),
                ),
              );
            }),
          ),
        ),
      ]),
    );
  }

  String _shortDay(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final d = DateTime.parse(dateStr);
      const ar = ['', 'اثن', 'ثلا', 'أرب', 'خمس', 'جمع', 'سبت', 'أحد'];
      return ar[d.weekday];
    } catch (_) {
      return '';
    }
  }

  // ─── Recent Transactions ─────────────────────────────────────────
  Widget _buildRecentTxns(List<AgentRecentTxn> txns) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06), blurRadius: 12),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('آخر المعاملات',
            style: GoogleFonts.tajawal(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1a1a2e))),
        const SizedBox(height: 12),
        if (txns.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('لا توجد معاملات بعد',
                  style: GoogleFonts.tajawal(
                      fontSize: 13, color: Colors.black38)),
            ),
          )
        else
          ...txns.asMap().entries.map((e) {
            final i = e.key;
            final t = e.value;
            final isLast = i == txns.length - 1;
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: isLast
                  ? null
                  : BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color:
                                  Colors.black.withValues(alpha: 0.05)))),
              child: Row(children: [
                AgentAvatar(url: t.recipientAvatar, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.recipientName,
                            style: GoogleFonts.tajawal(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1a1a2e))),
                        if (t.recipientKayanId != null)
                          Text('# ${t.recipientKayanId}',
                              style: GoogleFonts.tajawal(
                                  fontSize: 11,
                                  color: KayanBrandColors.logoPrimary,
                                  fontWeight: FontWeight.w700)),
                        Text(_fmtAgo(t.createdAt),
                            style: GoogleFonts.tajawal(
                                fontSize: 10, color: Colors.black38)),
                      ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: KayanBrandColors.logoPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text('🪙 ${_fmt(t.goldAmount)}',
                      style: GoogleFonts.tajawal(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: KayanBrandColors.logoPrimary)),
                ),
              ]),
            );
          }),
      ]),
    );
  }

  String _fmtAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    return 'منذ ${diff.inDays} يوم';
  }

  // ─── Quick Actions ────────────────────────────────────────────────
  Widget _buildQuickActions(BuildContext context) {
    return Row(children: [
      Expanded(
        child: AgentQuickActionBtn(
          icon: '💸',
          label: 'شحن مستخدم',
          color: KayanBrandColors.logoPrimary,
          onTap: onGoRecharge,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: AgentQuickActionBtn(
          icon: '🪙',
          label: 'تعبئة الرصيد',
          color: const Color(0xFFFFB800),
          onTap: () => AgentTopupDialog.show(context, onSuccess: onRefresh),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: AgentQuickActionBtn(
          icon: '🔄',
          label: 'تحديث البيانات',
          color: const Color(0xFF2196F3),
          onTap: onRefresh,
        ),
      ),
    ]);
  }
}
