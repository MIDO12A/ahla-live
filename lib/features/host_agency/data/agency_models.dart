// ═══════════════════════════════════════════════════════════════════
//  Agency Models — نظام الوكالات الشامل (v2 — موحد مع المحرك الجديد)
// ═══════════════════════════════════════════════════════════════════

import '../../../core/utils/server_time_service.dart';

// ─── درجة الوكالة ────────────────────────────────────────────────────────────
enum AgencyTier { bronze, silver, gold, platinum, diamond }

extension AgencyTierX on AgencyTier {
  String get label {
    switch (this) {
      case AgencyTier.bronze:   return 'برونز';
      case AgencyTier.silver:   return 'فضي';
      case AgencyTier.gold:     return 'ذهبي';
      case AgencyTier.platinum: return 'بلاتيني';
      case AgencyTier.diamond:  return 'ألماسي';
    }
  }

  static AgencyTier fromString(String s) {
    switch (s) {
      case 'silver':   return AgencyTier.silver;
      case 'gold':     return AgencyTier.gold;
      case 'platinum': return AgencyTier.platinum;
      case 'diamond':  return AgencyTier.diamond;
      default:         return AgencyTier.bronze;
    }
  }
}

// ─── إعدادات محرك الوكالة (من قاعدة البيانات) ───────────────────────────────
class AgencyEngineSettings {
  final int    hostSharePct;
  final int    agencySharePct;
  final int    platformSharePct;
  final double diamondToCoinRate;
  final int    dailyExchangeLimit;
  final double diamondToUsdRate;
  final double withdrawalFeePct;
  final double minWithdrawalUsd;
  final int    minDiamondsToWithdraw;
  final int    withdrawalCycleDays;
  final int    trialPeriodDays;
  final int    exitPenaltyCoins;
  final bool   engineEnabled;

  const AgencyEngineSettings({
    required this.hostSharePct,
    required this.agencySharePct,
    required this.platformSharePct,
    required this.diamondToCoinRate,
    required this.dailyExchangeLimit,
    required this.diamondToUsdRate,
    required this.withdrawalFeePct,
    required this.minWithdrawalUsd,
    required this.minDiamondsToWithdraw,
    required this.withdrawalCycleDays,
    required this.trialPeriodDays,
    required this.exitPenaltyCoins,
    required this.engineEnabled,
  });

  factory AgencyEngineSettings.fromMap(Map<String, dynamic> m) {
    return AgencyEngineSettings(
      hostSharePct:           (m['host_share_pct'] as num?)?.toInt()              ?? 70,
      agencySharePct:         (m['agency_share_pct'] as num?)?.toInt()            ?? 20,
      platformSharePct:       (m['platform_share_pct'] as num?)?.toInt()          ?? 10,
      diamondToCoinRate:      (m['diamond_to_coin_rate'] as num?)?.toDouble()     ?? 0.5,
      dailyExchangeLimit:     (m['daily_exchange_limit_diamonds'] as num?)?.toInt() ?? 500000,
      diamondToUsdRate:       (m['diamond_to_usd_rate'] as num?)?.toDouble()      ?? 0.0001,
      withdrawalFeePct:       (m['withdrawal_fee_pct'] as num?)?.toDouble()       ?? 10.0,
      minWithdrawalUsd:       (m['min_withdrawal_usd'] as num?)?.toDouble()       ?? 10.0,
      minDiamondsToWithdraw:  (m['min_diamonds_to_withdraw'] as num?)?.toInt()    ?? 100000,
      withdrawalCycleDays:    (m['withdrawal_cycle_days'] as num?)?.toInt()       ?? 30,
      trialPeriodDays:        (m['trial_period_days'] as num?)?.toInt()           ?? 7,
      exitPenaltyCoins:       (m['exit_penalty_coins'] as num?)?.toInt()          ?? 300000,
      engineEnabled:          m['engine_enabled'] as bool?                        ?? true,
    );
  }

  /// يحسب الكوينز المحصّلة من ألماس معين
  int coinsFromDiamonds(int diamonds) => (diamonds * diamondToCoinRate).floor();

  /// يحسب الدولارات قبل الرسوم
  double grossUsdFromDiamonds(int diamonds) => diamonds * diamondToUsdRate;

  /// يحسب الدولارات بعد الرسوم
  double netUsdFromDiamonds(int diamonds) {
    final gross = grossUsdFromDiamonds(diamonds);
    return gross * (1 - withdrawalFeePct / 100);
  }
}

// ─── بطاقة الوكالة (للعرض العام والتصنيف) ───────────────────────────────────
class AgencyCard {
  final String  id;
  final String? agencyPublicId;   // ≥ 5000 — المعرّف العام للوكالة
  final String  name;
  final String? description;
  final String? photoUrl;
  final String? country;
  final AgencyTier tier;
  final int? rank;
  final int memberCount;
  final int totalDiamondsMonthly;
  final int totalDiamondsCumulative;
  final bool isHallOfFame;
  final String status;
  final bool isMember;
  final bool canJoin;
  final bool hasPendingRequest;
  final String? ownerName;
  final String? ownerAvatarUrl;

  const AgencyCard({
    required this.id,
    this.agencyPublicId,
    required this.name,
    this.description,
    this.photoUrl,
    this.country,
    required this.tier,
    this.rank,
    required this.memberCount,
    required this.totalDiamondsMonthly,
    required this.totalDiamondsCumulative,
    required this.isHallOfFame,
    required this.status,
    this.isMember = false,
    this.canJoin = false,
    this.hasPendingRequest = false,
    this.ownerName,
    this.ownerAvatarUrl,
  });

/// Helper function to format any agency identifier into a 3-digit numeric string (100–999).
String formatAgencyNumericId(dynamic agencyDataOrId) {
  if (agencyDataOrId == null) return '100';

  if (agencyDataOrId is Map) {
    final pub = agencyDataOrId['agency_code'] ?? agencyDataOrId['agency_public_id'] ?? agencyDataOrId['code'];
    if (pub != null) {
      final s = pub.toString().trim();
      final n = int.tryParse(s);
      if (n != null) {
        if (n >= 100 && n <= 999) return n.toString();
        return (100 + (n % 900)).toString();
      }
    }
    final name = (agencyDataOrId['name'] ?? '').toString().trim();
    final nameNum = int.tryParse(name);
    if (nameNum != null && nameNum >= 100 && nameNum <= 999) {
      return nameNum.toString();
    }
    return formatAgencyNumericId(agencyDataOrId['id']);
  }

  final raw = agencyDataOrId.toString().trim();
  final directNum = int.tryParse(raw);
  if (directNum != null) {
    if (directNum >= 100 && directNum <= 999) return directNum.toString();
    return (100 + (directNum % 900)).toString();
  }

  final hash = raw.hashCode.abs();
  return (100 + (hash % 900)).toString();
}

  factory AgencyCard.fromMap(Map<String, dynamic> m) {
    return AgencyCard(
      id:                       m['id'] as String,
      agencyPublicId:           formatAgencyNumericId(m),
      name:                     m['name'] as String? ?? '—',
      description:              m['description'] as String?,
      photoUrl:                 m['photo_url'] as String?,
      country:                  m['country'] as String?,
      tier:                     AgencyTierX.fromString(m['tier'] as String? ?? 'bronze'),
      rank:                     (m['rank'] as num?)?.toInt(),
      memberCount:              (m['member_count'] as num?)?.toInt() ?? 0,
      totalDiamondsMonthly:     (m['total_diamonds_monthly'] as num?)?.toInt() ?? 0,
      totalDiamondsCumulative:  (m['total_diamonds_cumulative'] as num?)?.toInt() ?? 0,
      isHallOfFame:             m['is_hall_of_fame'] as bool? ?? false,
      status:                   m['status'] as String? ?? 'active',
      isMember:                 m['is_member'] as bool? ?? false,
      canJoin:                  m['can_join'] as bool? ?? false,
      hasPendingRequest:        m['has_pending_request'] as bool? ?? false,
      ownerName:                m['owner_name'] as String?
                                  ?? (m['owner'] as Map<String, dynamic>?)?['display_name'] as String?,
      ownerAvatarUrl:           m['owner_avatar'] as String?
                                  ?? (m['owner'] as Map<String, dynamic>?)?['avatar_url'] as String?,
    );
  }
}

// ─── صف التصنيف ───────────────────────────────────────────────────────────────
class AgencyLeaderboardEntry {
  final int     rank;
  final String  agencyId;
  final String? agencyPublicId;   // 3-digit numeric string (100..999)
  final String  name;
  final String? photoUrl;
  final AgencyTier tier;
  final int memberCount;
  final int totalDiamondsMonthly;
  final int totalDiamondsCumulative;
  final bool isHallOfFame;
  final String? country;

  const AgencyLeaderboardEntry({
    required this.rank,
    required this.agencyId,
    this.agencyPublicId,
    required this.name,
    this.photoUrl,
    required this.tier,
    required this.memberCount,
    required this.totalDiamondsMonthly,
    required this.totalDiamondsCumulative,
    required this.isHallOfFame,
    this.country,
  });

  factory AgencyLeaderboardEntry.fromMap(Map<String, dynamic> m) {
    return AgencyLeaderboardEntry(
      rank:                    (m['rank'] as num?)?.toInt() ?? 0,
      agencyId:                m['agency_id'] as String? ?? m['id'] as String,
      agencyPublicId:          formatAgencyNumericId(m),
      name:                    m['name'] as String? ?? '—',
      photoUrl:                m['photo_url'] as String?,
      tier:                    AgencyTierX.fromString(m['tier'] as String? ?? 'bronze'),
      memberCount:             (m['member_count'] as num?)?.toInt() ?? 0,
      totalDiamondsMonthly:    (m['total_diamonds_monthly'] as num?)?.toInt() ?? 0,
      totalDiamondsCumulative: (m['total_diamonds_cumulative'] as num?)?.toInt() ?? 0,
      isHallOfFame:            m['is_hall_of_fame'] as bool? ?? false,
      country:                 m['country'] as String?,
    );
  }
}

// ─── معلومات العضو في الوكالة ────────────────────────────────────────────────
class AgencyMemberInfo {
  final String memberId;
  final String userId;
  final String agencyId;
  final String role;   // owner / supervisor / host
  final String status;
  final int diamondsEarnedMonthly;
  final int diamondsEarnedCumulative;
  final int diamondsBalance;
  final int diamondsPendingWithdrawal;
  final int diamondsAvailable;           // = balance - pending
  final DateTime? trialEndsAt;
  final DateTime? joinDate;

  const AgencyMemberInfo({
    required this.memberId,
    required this.userId,
    required this.agencyId,
    required this.role,
    required this.status,
    required this.diamondsEarnedMonthly,
    required this.diamondsEarnedCumulative,
    required this.diamondsBalance,
    required this.diamondsPendingWithdrawal,
    required this.diamondsAvailable,
    this.trialEndsAt,
    this.joinDate,
  });

  factory AgencyMemberInfo.fromMap(Map<String, dynamic> m) {
    final balance  = (m['diamonds_balance'] as num?)?.toInt()             ?? 0;
    final pending  = (m['diamonds_pending_withdrawal'] as num?)?.toInt()  ?? 0;
    final available= (m['diamonds_available'] as num?)?.toInt()           ?? (balance - pending).clamp(0, balance);
    return AgencyMemberInfo(
      memberId:                  (m['member_id'] ?? m['id']).toString(),
      userId:                    m['user_id'] as String,
      agencyId:                  m['agency_id'] as String,
      role:                      m['role'] as String? ?? 'host',
      status:                    m['status'] as String? ?? 'active',
      diamondsEarnedMonthly:     (m['diamonds_earned_monthly'] as num?)?.toInt()    ?? 0,
      diamondsEarnedCumulative:  (m['diamonds_earned_cumulative'] as num?)?.toInt() ?? 0,
      diamondsBalance:           balance,
      diamondsPendingWithdrawal: pending,
      diamondsAvailable:         available,
      trialEndsAt: m['trial_ends_at'] != null
          ? DateTime.tryParse(m['trial_ends_at'] as String)
          : null,
      joinDate: m['join_date'] != null
          ? DateTime.tryParse(m['join_date'] as String)
          : null,
    );
  }

  bool get isInTrial {
    if (trialEndsAt == null) return false;
    return ServerTimeService.instance.now().isBefore(trialEndsAt!);
  }
}

// ─── هدف المضيف (v2 — مكافآت متعددة + تقدم) ─────────────────────────────────
class AgencyTarget {
  final String id;
  final String? title;
  final int targetDiamonds;
  final int rewardCoins;
  final int rewardDiamonds;
  final int rewardSvipDays;
  final int? rewardBadgeId;
  final int? rewardMedalId;
  final int? rewardFrameId;
  final String? rewardType;
  final double rewardValue;
  final String? rewardImageUrl;
  final String? backgroundUrl;
  // حالة التقدم (مُحسَبة من الـ API)
  final int earnedThisMonth;
  final int remaining;
  final double progressPct;
  final bool isAchieved;
  final int sortOrder;

  const AgencyTarget({
    required this.id,
    this.title,
    required this.targetDiamonds,
    this.rewardCoins     = 0,
    this.rewardDiamonds  = 0,
    this.rewardSvipDays  = 0,
    this.rewardBadgeId,
    this.rewardMedalId,
    this.rewardFrameId,
    this.rewardType,
    this.rewardValue     = 0.0,
    this.rewardImageUrl,
    this.backgroundUrl,
    this.earnedThisMonth = 0,
    this.remaining       = 0,
    this.progressPct     = 0,
    this.isAchieved      = false,
    this.sortOrder       = 0,
  });

  /// بناء من استجابة get_host_dashboard_v2 (نتيجة غنية مع التقدم)
  factory AgencyTarget.fromDashboardMap(Map<String, dynamic> m) {
    return AgencyTarget(
      id:              m['id'].toString(),
      title:           m['title'] as String?,
      targetDiamonds:  (m['target_diamonds'] as num?)?.toInt()  ?? 0,
      rewardCoins:     (m['reward_coins'] as num?)?.toInt()     ?? 0,
      rewardDiamonds:  (m['reward_diamonds'] as num?)?.toInt()  ?? 0,
      rewardSvipDays:  (m['reward_svip_days'] as num?)?.toInt() ?? 0,
      rewardBadgeId:   (m['reward_badge_id'] as num?)?.toInt(),
      rewardMedalId:   (m['reward_medal_id'] as num?)?.toInt(),
      rewardFrameId:   (m['reward_frame_id'] as num?)?.toInt(),
      rewardType:      m['reward_type'] as String?,
      rewardValue:     (m['reward_value'] as num?)?.toDouble() ?? 0.0,
      rewardImageUrl:  m['reward_image_url'] as String?,
      backgroundUrl:   m['background_url'] as String?,
      earnedThisMonth: (m['earned_this_month'] as num?)?.toInt() ?? 0,
      remaining:       (m['remaining'] as num?)?.toInt()         ?? 0,
      progressPct:     (m['progress_pct'] as num?)?.toDouble()   ?? 0.0,
      isAchieved:      m['is_achieved'] as bool?                 ?? false,
      sortOrder:       (m['sort_order'] as num?)?.toInt()        ?? 0,
    );
  }

  /// بناء من صف الجدول المباشر (بدون تقدم — يُحسَب لاحقاً)
  factory AgencyTarget.fromMap(Map<String, dynamic> m) {
    return AgencyTarget(
      id:             m['id'].toString(),
      title:          m['title'] as String?,
      targetDiamonds: (m['target_diamonds']
                       ?? m['diamond_threshold'] as num?)?.toInt() ?? 0,
      rewardCoins:    (m['reward_coins'] as num?)?.toInt()         ?? 0,
      rewardDiamonds: (m['reward_diamonds'] as num?)?.toInt()      ?? 0,
      rewardSvipDays: (m['reward_svip_days'] as num?)?.toInt()     ?? 0,
      rewardBadgeId:  (m['reward_badge_id'] as num?)?.toInt(),
      rewardMedalId:  (m['reward_medal_id'] as num?)?.toInt(),
      rewardFrameId:  (m['reward_frame_id'] as num?)?.toInt(),
      sortOrder:      (m['sort_order'] as num?)?.toInt()           ?? 0,
    );
  }

  String get rewardSummary {
    final parts = <String>[];
    if (rewardCoins    > 0) parts.add('${_fmt(rewardCoins)} كوينز');
    if (rewardDiamonds > 0) parts.add('${_fmt(rewardDiamonds)} ألماس');
    if (rewardSvipDays > 0) parts.add('$rewardSvipDays يوم SVIP');
    if (rewardBadgeId  != null) parts.add('شارة');
    if (rewardMedalId  != null) parts.add('وسام');
    if (rewardFrameId  != null) parts.add('إطار');
    return parts.isEmpty ? 'مكافأة خاصة' : parts.join(' + ');
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toString();
  }
}

// ─── معاملة دفتر الألماس ─────────────────────────────────────────────────────
class AgencyLedgerEntry {
  final int id;
  final String txnType;
  final int amount;
  final int direction;   // 1 = دخل، -1 = خرج
  final int balanceAfter;
  final String? note;
  final DateTime createdAt;

  const AgencyLedgerEntry({
    required this.id,
    required this.txnType,
    required this.amount,
    required this.direction,
    required this.balanceAfter,
    this.note,
    required this.createdAt,
  });

  factory AgencyLedgerEntry.fromMap(Map<String, dynamic> m) {
    return AgencyLedgerEntry(
      id:           (m['id'] as num).toInt(),
      txnType:      m['type'] as String? ?? m['txn_type'] as String? ?? '',
      amount:       (m['amount'] as num?)?.toInt() ?? 0,
      direction:    (m['direction'] as num?)?.toInt() ?? 1,
      balanceAfter: (m['balance_after'] as num?)?.toInt() ?? 0,
      note:         m['note'] as String?,
      createdAt:    DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  bool get isCredit => direction == 1;

  String get typeLabel {
    switch (txnType) {
      case 'gift_commission':   return 'عمولة هدية';
      case 'exchange_out':      return 'تبادل ألماس';
      case 'withdrawal_lock':   return 'تجميد سحب';
      case 'withdrawal_unlock': return 'إلغاء تجميد';
      case 'withdrawal_paid':   return 'سحب مكتمل';
      case 'transfer_out':      return 'تحويل لوكيل';
      case 'bonus':             return 'مكافأة هدف';
      case 'adjustment':        return 'تعديل إداري';
      default:                  return txnType;
    }
  }
}

// ─── حالة المضيف الكاملة (من get_host_dashboard_v2) ─────────────────────────
class HostAgencyStats {
  final AgencyCard? agency;
  final AgencyMemberInfo member;
  final List<AgencyTarget> targets;
  final List<AgencyLedgerEntry> recentLedger;
  final AgencyEngineSettings engine;
  // للتوافق مع الكود القديم
  final List<String> achievedTargetIds;
  final int rankInAgency;
  final int totalMembersInAgency;

  const HostAgencyStats({
    this.agency,
    required this.member,
    required this.targets,
    required this.recentLedger,
    required this.engine,
    required this.achievedTargetIds,
    this.rankInAgency       = 0,
    this.totalMembersInAgency = 0,
  });

  /// الهدف التالي غير المحقق
  AgencyTarget? get nextTarget {
    for (final t in targets) {
      if (!t.isAchieved) return t;
    }
    return null;
  }

  /// نسبة التقدم نحو الهدف التالي (0.0 – 1.0)
  double get nextTargetProgress {
    final t = nextTarget;
    if (t == null) return 1.0;
    return (t.progressPct / 100).clamp(0.0, 1.0);
  }
}

// ─── محفظة مالك الوكالة ───────────────────────────────────────────────────────
class AgencyOwnerWallet {
  final int balance;       // إجمالي الألماس
  final int pending;       // مجمَّد في انتظار السحب
  final int available;     // = balance - pending
  final int earnedTotal;   // تراكمي منذ التأسيس

  const AgencyOwnerWallet({
    required this.balance,
    required this.pending,
    required this.available,
    required this.earnedTotal,
  });

  factory AgencyOwnerWallet.fromMap(Map<String, dynamic> m) {
    return AgencyOwnerWallet(
      balance:     (m['balance']      as num?)?.toInt() ?? 0,
      pending:     (m['pending']      as num?)?.toInt() ?? 0,
      available:   (m['available']    as num?)?.toInt() ?? 0,
      earnedTotal: (m['earned_total'] as num?)?.toInt() ?? 0,
    );
  }

  factory AgencyOwnerWallet.empty() =>
      const AgencyOwnerWallet(balance: 0, pending: 0, available: 0, earnedTotal: 0);
}

// ─── حركة دفتر مالك الوكالة ──────────────────────────────────────────────────
class AgencyOwnerLedgerEntry {
  final int id;
  final String txnType;
  final int amount;
  final int direction;   // 1 = دخل، -1 = خرج
  final int balanceAfter;
  final String? note;
  final DateTime createdAt;

  const AgencyOwnerLedgerEntry({
    required this.id,
    required this.txnType,
    required this.amount,
    required this.direction,
    required this.balanceAfter,
    this.note,
    required this.createdAt,
  });

  factory AgencyOwnerLedgerEntry.fromMap(Map<String, dynamic> m) {
    return AgencyOwnerLedgerEntry(
      id:           (m['id'] as num).toInt(),
      txnType:      m['txn_type'] as String? ?? '',
      amount:       (m['amount'] as num?)?.toInt() ?? 0,
      direction:    (m['direction'] as num?)?.toInt() ?? 1,
      balanceAfter: (m['balance_after'] as num?)?.toInt() ?? 0,
      note:         m['note'] as String?,
      createdAt:    DateTime.tryParse(m['created_at'] as String? ?? '') ??
                    ServerTimeService.instance.now(),
    );
  }

  bool get isCredit => direction == 1;

  String get typeLabel {
    switch (txnType) {
      case 'gift_commission': return 'عمولة وكالة';
      case 'target_bonus':    return 'مكافأة هدف';
      case 'exchange':        return 'تبادل بكوينز';
      case 'withdrawal':      return 'طلب سحب';
      case 'transfer':        return 'تحويل لوكيل';
      case 'adjustment':      return 'تعديل إداري';
      default:                return txnType;
    }
  }
}

// ─── لوحة تحكم مالك الوكالة الكاملة ─────────────────────────────────────────
class AgencyOwnerDashboard {
  final AgencyOwnerWallet wallet;
  final AgencyEngineSettings rates;
  final List<AgencyOwnerLedgerEntry> ledger;

  const AgencyOwnerDashboard({
    required this.wallet,
    required this.rates,
    required this.ledger,
  });

  factory AgencyOwnerDashboard.fromMap(Map<String, dynamic> m) {
    final walletMap = m['wallet'] as Map<String, dynamic>? ?? {};
    final ratesMap  = m['rates']  as Map<String, dynamic>? ?? {};
    final ledgerList = (m['ledger'] as List<dynamic>?) ?? [];

    return AgencyOwnerDashboard(
      wallet: AgencyOwnerWallet.fromMap(walletMap),
      rates:  AgencyEngineSettings.fromMap(ratesMap),
      ledger: ledgerList
          .map((e) => AgencyOwnerLedgerEntry.fromMap(
                Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

// ─── 1. توثيق المضيف الحقيقي (Host Real-Name Verification) ───────────────────
enum HostDocType { idCard, passport, driverLicense }

extension HostDocTypeX on HostDocType {
  String get label {
    switch (this) {
      case HostDocType.idCard:        return 'بطاقة شخصية';
      case HostDocType.passport:      return 'جواز السفر';
      case HostDocType.driverLicense: return 'رخصة القيادة';
    }
  }

  String get code {
    switch (this) {
      case HostDocType.idCard:        return 'id_card';
      case HostDocType.passport:      return 'passport';
      case HostDocType.driverLicense: return 'driver_license';
    }
  }

  static HostDocType fromString(String? s) {
    switch (s) {
      case 'passport':       return HostDocType.passport;
      case 'driver_license': return HostDocType.driverLicense;
      default:               return HostDocType.idCard;
    }
  }
}

class HostVerificationModel {
  final String id;
  final String uid;
  final String fullName;
  final HostDocType docType;
  final String? docNumber;
  final String docFrontUrl;
  final String? docBackUrl;
  final String facePhoto1Url;
  final String facePhoto2Url;
  final String videoUrl;
  final int videoDurationSeconds;
  final String? previousPlatforms;
  final int dailyWorkHours;
  final String? country;
  final String? whatsapp;
  final String status; // pending / approved / rejected
  final String? rejectionReason;
  final DateTime? reviewedAt;
  final DateTime createdAt;

  const HostVerificationModel({
    required this.id,
    required this.uid,
    required this.fullName,
    required this.docType,
    this.docNumber,
    required this.docFrontUrl,
    this.docBackUrl,
    required this.facePhoto1Url,
    required this.facePhoto2Url,
    required this.videoUrl,
    required this.videoDurationSeconds,
    this.previousPlatforms,
    this.dailyWorkHours = 4,
    this.country,
    this.whatsapp,
    this.status = 'pending',
    this.rejectionReason,
    this.reviewedAt,
    required this.createdAt,
  });

  bool get isApproved => status == 'approved';
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';

  factory HostVerificationModel.fromMap(Map<String, dynamic> m) {
    return HostVerificationModel(
      id:                   m['id']?.toString() ?? '',
      uid:                  m['uid'] as String? ?? '',
      fullName:             m['full_name'] as String? ?? '',
      docType:              HostDocTypeX.fromString(m['doc_type'] as String?),
      docNumber:            m['doc_number'] as String?,
      docFrontUrl:          m['doc_front_url'] as String? ?? '',
      docBackUrl:           m['doc_back_url'] as String?,
      facePhoto1Url:        m['face_photo1_url'] as String? ?? '',
      facePhoto2Url:        m['face_photo2_url'] as String? ?? '',
      videoUrl:             m['video_url'] as String? ?? '',
      videoDurationSeconds: (m['video_duration_seconds'] as num?)?.toInt() ?? 5,
      previousPlatforms:    m['previous_platforms'] as String?,
      dailyWorkHours:       (m['daily_work_hours'] as num?)?.toInt() ?? 4,
      country:              m['country'] as String?,
      whatsapp:             m['whatsapp'] as String?,
      status:               m['status'] as String? ?? 'pending',
      rejectionReason:      m['rejection_reason'] as String?,
      reviewedAt:           m['reviewed_at'] != null ? DateTime.tryParse(m['reviewed_at']) : null,
      createdAt:            DateTime.tryParse(m['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}

// ─── 2. مستويات وامتيازات الوكالة (Agency Level & Tier Privileges) ─────────────
class AgencyLevelConfigModel {
  final int level;
  final String levelName;
  final int minExp;
  final int adminLimit;
  final int membersLimit;
  final double maintainExpPercentage; // 30.0%
  final String? badgeIconUrl;

  const AgencyLevelConfigModel({
    required this.level,
    required this.levelName,
    required this.minExp,
    required this.adminLimit,
    required this.membersLimit,
    this.maintainExpPercentage = 30.0,
    this.badgeIconUrl,
  });

  int get maintainExpThreshold => (minExp * (maintainExpPercentage / 100)).round();

  factory AgencyLevelConfigModel.fromMap(Map<String, dynamic> m) {
    return AgencyLevelConfigModel(
      level:                 (m['level'] as num?)?.toInt() ?? 1,
      levelName:             m['level_name'] as String? ?? 'مستوى ${m['level']}',
      minExp:                (m['min_exp'] as num?)?.toInt() ?? 0,
      adminLimit:            (m['admin_limit'] as num?)?.toInt() ?? 2,
      membersLimit:          (m['members_limit'] as num?)?.toInt() ?? 20,
      maintainExpPercentage: (m['maintain_exp_percentage'] as num?)?.toDouble() ?? 30.0,
      badgeIconUrl:          m['badge_icon_url'] as String?,
    );
  }
}

// ─── 3. تتبع ساعات البث اليومية والتارجت (Daily Live Hours Target) ───────────
class AgencyDailyHoursTarget {
  final String hostUid;
  final DateTime recordDate;
  final int liveDurationSeconds;
  final int diamondsEarned;
  final int daysGe2h; // عدد الأيام التي حققت >= 2 ساعة
  final int daysGe4h; // عدد الأيام التي حققت >= 4 ساعات
  final int daysGe6h; // عدد الأيام التي حققت >= 6 ساعات

  const AgencyDailyHoursTarget({
    required this.hostUid,
    required this.recordDate,
    required this.liveDurationSeconds,
    required this.diamondsEarned,
    this.daysGe2h = 0,
    this.daysGe4h = 0,
    this.daysGe6h = 0,
  });

  bool get isTodayGe2h => liveDurationSeconds >= 7200;
  bool get isTodayGe4h => liveDurationSeconds >= 14400;
  bool get isTodayGe6h => liveDurationSeconds >= 21600;

  String get formattedTodayHours {
    final hours = liveDurationSeconds / 3600;
    return '${hours.toStringAsFixed(1)} ساعة';
  }

  factory AgencyDailyHoursTarget.fromMap(Map<String, dynamic> m) {
    return AgencyDailyHoursTarget(
      hostUid:             m['host_uid'] as String? ?? '',
      recordDate:          DateTime.tryParse(m['record_date'] ?? '') ?? DateTime.now(),
      liveDurationSeconds: (m['live_duration_seconds'] as num?)?.toInt() ?? 0,
      diamondsEarned:      (m['diamonds_earned'] as num?)?.toInt() ?? 0,
      daysGe2h:            (m['days_ge_2h'] as num?)?.toInt() ?? 0,
      daysGe4h:            (m['days_ge_4h'] as num?)?.toInt() ?? 0,
      daysGe6h:            (m['days_ge_6h'] as num?)?.toInt() ?? 0,
    );
  }
}

// ─── 4. رواتب الوكالة والسحب على المكشوف (Salary & Overdraft Model) ───────────
class AgencySalaryOverdraftModel {
  final String agencyId;
  final String periodMonth;
  final int diamondTarget;
  final int diamondBalance;
  final int nextDiamondTarget;
  final double totalSalaryUsd;
  final double overdrawnAmountUsd;
  final double remainingSalaryUsd;
  final bool canOverdraft;

  const AgencySalaryOverdraftModel({
    required this.agencyId,
    required this.periodMonth,
    required this.diamondTarget,
    required this.diamondBalance,
    required this.nextDiamondTarget,
    required this.totalSalaryUsd,
    required this.overdrawnAmountUsd,
    required this.remainingSalaryUsd,
    this.canOverdraft = true,
  });

  double get targetProgressPercentage {
    if (diamondTarget <= 0) return 1.0;
    return (diamondBalance / diamondTarget).clamp(0.0, 1.0);
  }

  factory AgencySalaryOverdraftModel.fromMap(Map<String, dynamic> m) {
    final total = (m['total_salary_usd'] as num?)?.toDouble() ?? 0.0;
    final overdrawn = (m['overdrawn_amount_usd'] as num?)?.toDouble() ?? 0.0;
    return AgencySalaryOverdraftModel(
      agencyId:           m['agency_id']?.toString() ?? '',
      periodMonth:        m['period_month'] as String? ?? '',
      diamondTarget:      (m['diamond_target'] as num?)?.toInt() ?? 500000,
      diamondBalance:     (m['diamond_balance'] as num?)?.toInt() ?? 0,
      nextDiamondTarget:  (m['next_diamond_target'] as num?)?.toInt() ?? 1000000,
      totalSalaryUsd:     total,
      overdrawnAmountUsd: overdrawn,
      remainingSalaryUsd: (m['remaining_salary_usd'] as num?)?.toDouble() ?? (total - overdrawn),
      canOverdraft:       m['can_overdraft'] as bool? ?? true,
    );
  }
}

// ─── 5. مصفوفة صلاحيات المشرفين (Agency Admin Permissions Matrix) ────────────
class AgencyAdminPermissions {
  final String agencyId;
  final String adminUid;
  final bool canAuditJoin;
  final bool canAuditQuit;
  final bool canInvite;
  final bool canKickout;
  final bool canViewMemberSalary;
  final bool canViewAgencySalary;

  const AgencyAdminPermissions({
    required this.agencyId,
    required this.adminUid,
    this.canAuditJoin = true,
    this.canAuditQuit = false,
    this.canInvite = true,
    this.canKickout = false,
    this.canViewMemberSalary = false,
    this.canViewAgencySalary = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'agency_id': agencyId,
      'admin_uid': adminUid,
      'can_audit_join': canAuditJoin,
      'can_audit_quit': canAuditQuit,
      'can_invite': canInvite,
      'can_kickout': canKickout,
      'can_view_member_salary': canViewMemberSalary,
      'can_view_agency_salary': canViewAgencySalary,
    };
  }

  factory AgencyAdminPermissions.fromMap(Map<String, dynamic> m) {
    return AgencyAdminPermissions(
      agencyId:            m['agency_id']?.toString() ?? '',
      adminUid:            m['admin_uid'] as String? ?? '',
      canAuditJoin:        m['can_audit_join'] as bool? ?? true,
      canAuditQuit:        m['can_audit_quit'] as bool? ?? false,
      canInvite:           m['can_invite'] as bool? ?? true,
      canKickout:          m['can_kickout'] as bool? ?? false,
      canViewMemberSalary: m['can_view_member_salary'] as bool? ?? false,
      canViewAgencySalary: m['can_view_agency_salary'] as bool? ?? false,
    );
  }
}

