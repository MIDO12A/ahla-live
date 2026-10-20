// ─── Models ─────────────────────────────────────────────────────────
class AgentDayChart {
  final String day;
  final int    total;
  final int    txCount;
  const AgentDayChart({required this.day, required this.total, required this.txCount});
  factory AgentDayChart.fromMap(Map<String,dynamic> m) => AgentDayChart(
    day:     m['day']?.toString() ?? '',
    total:   (m['total'] as num?)?.toInt() ?? 0,
    txCount: (m['tx_count'] as num?)?.toInt() ?? 0,
  );
}

class AgentRecentTxn {
  final int    goldAmount;
  final String status;
  final String recipientName;
  final String? recipientAvatar;
  final String? recipientKayanId;
  final DateTime createdAt;
  const AgentRecentTxn({
    required this.goldAmount, required this.status,
    required this.recipientName, this.recipientAvatar,
    this.recipientKayanId, required this.createdAt,
  });
  factory AgentRecentTxn.fromMap(Map<String,dynamic> m) => AgentRecentTxn(
    goldAmount:        (m['gold_amount'] as num?)?.toInt() ?? 0,
    status:            m['status']?.toString() ?? 'completed',
    recipientName:     m['recipient_name']?.toString() ?? 'مستخدم',
    recipientAvatar:   m['recipient_avatar']?.toString(),
    recipientKayanId:  m['recipient_kayan_id']?.toString(),
    createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
  );
}

class AgentDashboardData {
  final bool    enabled;
  final bool    pinSet;
  final int     dailyLimit;
  final int     agencyGold;
  final String? agentPublicId;
  // Today
  final int    todayTotal;
  final int    todayCount;
  final int    todayRemaining;
  // Week
  final int    weekTotal;
  final int    weekCount;
  // Month
  final int    monthTotal;
  final int    monthCount;
  // All time
  final int    allTotal;
  final int    allCount;
  // Chart + recent
  final List<AgentDayChart>  weekChart;
  final List<AgentRecentTxn> recentTxns;
  // أزرار سريعة قابلة للتخصيص
  final List<int> quickAmounts;
  // محفظة الدولار
  final double usdBalance;

  const AgentDashboardData({
    required this.enabled, required this.pinSet,
    required this.dailyLimit, required this.agencyGold,
    this.agentPublicId,
    required this.todayTotal, required this.todayCount, required this.todayRemaining,
    required this.weekTotal,  required this.weekCount,
    required this.monthTotal, required this.monthCount,
    required this.allTotal,   required this.allCount,
    required this.weekChart,  required this.recentTxns,
    required this.quickAmounts,
    this.usdBalance = 0.0,
  });

  AgentDashboardData copyWith({
    bool? enabled,
    bool? pinSet,
    int? dailyLimit,
    int? agencyGold,
    String? agentPublicId,
    int? todayTotal,
    int? todayCount,
    int? todayRemaining,
    int? weekTotal,
    int? weekCount,
    int? monthTotal,
    int? monthCount,
    int? allTotal,
    int? allCount,
    List<AgentDayChart>? weekChart,
    List<AgentRecentTxn>? recentTxns,
    List<int>? quickAmounts,
    double? usdBalance,
  }) => AgentDashboardData(
    enabled:        enabled ?? this.enabled,
    pinSet:         pinSet ?? this.pinSet,
    dailyLimit:     dailyLimit ?? this.dailyLimit,
    agencyGold:     agencyGold ?? this.agencyGold,
    agentPublicId:  agentPublicId ?? this.agentPublicId,
    todayTotal:     todayTotal ?? this.todayTotal,
    todayCount:     todayCount ?? this.todayCount,
    todayRemaining: todayRemaining ?? this.todayRemaining,
    weekTotal:      weekTotal ?? this.weekTotal,
    weekCount:      weekCount ?? this.weekCount,
    monthTotal:     monthTotal ?? this.monthTotal,
    monthCount:     monthCount ?? this.monthCount,
    allTotal:       allTotal ?? this.allTotal,
    allCount:       allCount ?? this.allCount,
    weekChart:      weekChart ?? this.weekChart,
    recentTxns:     recentTxns ?? this.recentTxns,
    quickAmounts:   quickAmounts ?? this.quickAmounts,
    usdBalance:     usdBalance ?? this.usdBalance,
  );

  /// Returns a copy with updated quickAmounts
  AgentDashboardData copyWithQuickAmounts(List<int> newAmounts) => copyWith(quickAmounts: newAmounts);

  factory AgentDashboardData.fromMap(Map<String,dynamic> m) {
    final today = m['today'] as Map? ?? {};
    final week  = m['week']  as Map? ?? {};
    final month = m['month'] as Map? ?? {};
    final all   = m['all_time'] as Map? ?? {};
    final rawAmounts = m['quick_amounts'];
    final quickAmounts = rawAmounts is List
        ? rawAmounts.map((e) => (e as num).toInt()).toList()
        : [100, 500, 1000, 5000];
    return AgentDashboardData(
      enabled:        m['enabled']         == true,
      pinSet:         m['pin_set']         == true,
      dailyLimit:     (m['daily_limit']    as num?)?.toInt() ?? 100000,
      agencyGold:     (m['agency_gold']    as num?)?.toInt() ?? 0,
      agentPublicId:  m['agent_public_id'] as String?,
      todayTotal:     (today['total']      as num?)?.toInt() ?? 0,
      todayCount:     (today['count']      as num?)?.toInt() ?? 0,
      todayRemaining: (today['remaining']  as num?)?.toInt() ?? 100000,
      weekTotal:      (week['total']       as num?)?.toInt() ?? 0,
      weekCount:      (week['count']       as num?)?.toInt() ?? 0,
      monthTotal:     (month['total']      as num?)?.toInt() ?? 0,
      monthCount:     (month['count']      as num?)?.toInt() ?? 0,
      allTotal:       (all['total']        as num?)?.toInt() ?? 0,
      allCount:       (all['count']        as num?)?.toInt() ?? 0,
      weekChart: (m['week_chart'] as List? ?? [])
          .map((e) => AgentDayChart.fromMap(Map<String,dynamic>.from(e as Map)))
          .toList(),
      recentTxns: (m['recent_txns'] as List? ?? [])
          .map((e) => AgentRecentTxn.fromMap(Map<String,dynamic>.from(e as Map)))
          .toList(),
      quickAmounts: quickAmounts,
      usdBalance: (m['usd_balance'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
