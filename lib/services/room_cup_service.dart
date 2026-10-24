import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';
import 'supabase_data_service.dart';
import '../core/supabase_compat.dart';

class MilestoneTier {
  final String id;
  final int minCoins;
  final double percentage;
  final String label;
  final int bonusCoins;

  const MilestoneTier({
    required this.id,
    required this.minCoins,
    required this.percentage,
    required this.label,
    this.bonusCoins = 0,
  });

  factory MilestoneTier.fromMap(Map<String, dynamic> map) {
    return MilestoneTier(
      id: map['id']?.toString() ?? '',
      minCoins: (map['minCoins'] as num?)?.toInt() ?? 0,
      percentage: (map['percentage'] as num?)?.toDouble() ?? 0.0,
      label: map['label']?.toString() ?? '',
      bonusCoins: (map['bonusCoins'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'minCoins': minCoins,
    'percentage': percentage,
    'label': label,
    'bonusCoins': bonusCoins,
  };
}

class OwnerCupPeriodConfig {
  final bool enabled;
  final double basePercentage;
  final bool useMilestones;
  final int minRoomCoinsToQualify;
  final String svgaFrame;
  final String badgeIcon;
  final int daysValid;
  final List<MilestoneTier> milestones;
  final String disbursementSchedule;
  final int customDays;
  final String disbursementTimeUtc;
  final String payoutMethod;

  const OwnerCupPeriodConfig({
    required this.enabled,
    required this.basePercentage,
    required this.useMilestones,
    required this.minRoomCoinsToQualify,
    required this.svgaFrame,
    required this.badgeIcon,
    required this.daysValid,
    required this.milestones,
    this.disbursementSchedule = 'weekly',
    this.customDays = 7,
    this.disbursementTimeUtc = '00:00',
    this.payoutMethod = 'both',
  });

  factory OwnerCupPeriodConfig.fromMap(Map<String, dynamic> map, {required bool isWeekly}) {
    final rawMilestones = map['milestones'] as List? ?? [];
    final parsedMilestones = rawMilestones
        .map((m) => MilestoneTier.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();

    return OwnerCupPeriodConfig(
      enabled: map['enabled'] as bool? ?? true,
      basePercentage: (map['basePercentage'] as num?)?.toDouble() ?? (isWeekly ? 15.0 : 10.0),
      useMilestones: map['useMilestones'] as bool? ?? false,
      minRoomCoinsToQualify: (map['minRoomCoinsToQualify'] as num?)?.toInt() ?? (isWeekly ? 50000 : 10000),
      svgaFrame: map['svgaFrame']?.toString() ?? 'assets/svga/kojuyee_room_rank_border1.svga',
      badgeIcon: map['badgeIcon']?.toString() ?? 'assets/images/rank_top_avatar_1.webp',
      daysValid: (map['daysValid'] as num?)?.toInt() ?? (isWeekly ? 7 : 1),
      milestones: parsedMilestones,
      disbursementSchedule: map['disbursementSchedule']?.toString() ?? (isWeekly ? 'weekly' : 'daily'),
      customDays: (map['customDays'] as num?)?.toInt() ?? (isWeekly ? 7 : 1),
      disbursementTimeUtc: map['disbursementTimeUtc']?.toString() ?? '00:00',
      payoutMethod: map['payoutMethod']?.toString() ?? 'both',
    );
  }
}

class RoomOwnerCupConfig {
  final OwnerCupPeriodConfig daily;
  final OwnerCupPeriodConfig weekly;

  const RoomOwnerCupConfig({
    required this.daily,
    required this.weekly,
  });

  factory RoomOwnerCupConfig.fromMap(Map<String, dynamic> map) {
    final dailyMap = map['daily'] is Map ? Map<String, dynamic>.from(map['daily'] as Map) : <String, dynamic>{};
    final weeklyMap = map['weekly'] is Map ? Map<String, dynamic>.from(map['weekly'] as Map) : <String, dynamic>{};

    return RoomOwnerCupConfig(
      daily: OwnerCupPeriodConfig.fromMap(dailyMap, isWeekly: false),
      weekly: OwnerCupPeriodConfig.fromMap(weeklyMap, isWeekly: true),
    );
  }
}

typedef RoomCupConfig = RoomOwnerCupConfig;

class RoomCupService {
  static final RoomCupService _instance = RoomCupService._internal();
  factory RoomCupService() => _instance;
  RoomCupService._internal();

  RoomOwnerCupConfig? _cachedConfig;
  DateTime? _lastFetch;

  Future<RoomOwnerCupConfig> getConfig({bool refresh = false}) async {
    if (!refresh && _cachedConfig != null && _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(seconds: 10)) {
      return _cachedConfig!;
    }

    try {
      final raw = await SupabaseService().getAppConfig('room_cup_rewards');
      if (raw != null) {
        Map<String, dynamic> map;
        if (raw is String) {
          map = jsonDecode(raw) as Map<String, dynamic>;
        } else if (raw is Map) {
          map = Map<String, dynamic>.from(raw);
        } else {
          map = {};
        }
        _cachedConfig = RoomOwnerCupConfig.fromMap(map);
        _lastFetch = DateTime.now();
        return _cachedConfig!;
      }
    } catch (e) {
      debugPrint('[RoomCupService] Error fetching config: $e');
    }

    _cachedConfig = RoomOwnerCupConfig.fromMap({});
    _lastFetch = DateTime.now();
    return _cachedConfig!;
  }

  /// Calculates and pays out Room Cup profits to the Room Owner
  Future<Map<String, dynamic>> settleRoomCupForOwner({
    required String roomId,
    required bool isWeekly,
    bool force = false,
  }) async {
    final cfg = await getConfig(refresh: true);
    final periodConfig = isWeekly ? cfg.weekly : cfg.daily;

    if (!periodConfig.enabled && !force) {
      return {'ok': false, 'message': 'نظام كأس الغرفة معطل حالياً'};
    }

    try {
      final sb = Supabase.instance.client;

      // 1. Fetch Room Owner (host_uid)
      final roomData = await sb.from('rooms').select('room_id, name, host_uid, host_name').eq('room_id', roomId).maybeSingle();
      if (roomData == null) {
        return {'ok': false, 'message': 'الغرفة غير موجودة'};
      }

      final ownerUid = roomData['host_uid']?.toString() ?? '';
      final roomName = roomData['name']?.toString() ?? roomId;
      final ownerName = roomData['host_name']?.toString() ?? 'مالك الغرفة';

      if (ownerUid.isEmpty) {
        return {'ok': false, 'message': 'لا يوجد معرف مالك محدد للغرفة'};
      }

      // 2. Fetch sent gifts in timeframe according to schedule
      final now = DateTime.now().toUtc();
      final Duration timeframe = periodConfig.disbursementSchedule == 'daily'
          ? const Duration(days: 1)
          : periodConfig.disbursementSchedule == 'monthly'
              ? const Duration(days: 30)
              : periodConfig.disbursementSchedule == 'custom'
                  ? Duration(days: periodConfig.customDays > 0 ? periodConfig.customDays : 7)
                  : const Duration(days: 7);

      final cutoff = now.subtract(timeframe);

      final res = await sb
          .from('sent_gifts')
          .select('count, value')
          .eq('room_id', roomId)
          .gte('created_at', cutoff.toIso8601String());

      final gifts = (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      int roomTotalCoins = 0;
      for (final g in gifts) {
        final count = (g['count'] as num?)?.toInt() ?? 1;
        final value = (g['value'] as num?)?.toInt() ?? 0;
        roomTotalCoins += (count * value);
      }

      // Check minimum qualification
      final minCoinsToQualify = (periodConfig.useMilestones && periodConfig.milestones.isNotEmpty)
          ? periodConfig.milestones.map((m) => m.minCoins).reduce((a, b) => a < b ? a : b)
          : periodConfig.minRoomCoinsToQualify;

      if (roomTotalCoins < minCoinsToQualify && !force) {
        return {
          'ok': false,
          'message': 'إجمالي كوينز الغرفة ($roomTotalCoins) لم يصل للحد الأدنى ($minCoinsToQualify)'
        };
      }

      // Determine applied percentage and matched milestone
      double appliedPercentage = periodConfig.basePercentage;
      int bonusCoins = 0;
      MilestoneTier? matchedMilestone;

      if (periodConfig.useMilestones && periodConfig.milestones.isNotEmpty) {
        final sorted = [...periodConfig.milestones]..sort((a, b) => b.minCoins.compareTo(a.minCoins));
        for (final m in sorted) {
          if (roomTotalCoins >= m.minCoins) {
            matchedMilestone = m;
            appliedPercentage = m.percentage;
            bonusCoins = m.bonusCoins;
            break;
          }
        }
      }

      final ownerProfitCoins = ((roomTotalCoins * appliedPercentage) / 100).round() + bonusCoins;

      if (ownerProfitCoins > 0) {
        // 3. Deposit coins directly to Room Owner
        final uData = await sb.from('users').select('coins').or('uid.eq.$ownerUid,id.eq.$ownerUid').maybeSingle();
        final curCoins = (uData?['coins'] as num?)?.toInt() ?? 0;
        await sb.from('users').update({'coins': curCoins + ownerProfitCoins}).or('uid.eq.$ownerUid,id.eq.$ownerUid');

        // 4. Deliver trophy frame or badge to Owner's backpack
        if (periodConfig.svgaFrame.isNotEmpty || periodConfig.badgeIcon.isNotEmpty) {
          final expiresAt = DateTime.now().add(Duration(days: periodConfig.daysValid)).toIso8601String();
          await sb.from('user_backpack').insert({
            'user_id': ownerUid,
            'item_id': 'owner_cup_${isWeekly ? 'weekly' : 'daily'}_${DateTime.now().millisecondsSinceEpoch}',
            'item_name': 'كأس الغرفة - $roomName',
            'item_type': periodConfig.svgaFrame.isNotEmpty ? 'frame' : 'badge',
            'item_icon': periodConfig.badgeIcon,
            'item_svga': periodConfig.svgaFrame,
            'duration_days': periodConfig.daysValid,
            'expires_at': expiresAt,
            'created_at': DateTime.now().toIso8601String(),
            'is_equipped': true,
            'source': 'owner_room_cup_${isWeekly ? 'weekly' : 'daily'}',
          });
        }

        // 5. Send official system notification to the Owner
        final tierLabel = matchedMilestone?.label.isNotEmpty == true ? ' [${matchedMilestone!.label}]' : '';
        await SupabaseDataService().sendNotification(
          uid: ownerUid,
          type: 'room_cup_award',
          actorUid: ownerUid,
          title: '🏆 مبروك! أرباح كأس الغرفة لغرفتك$tierLabel',
          body: 'تهانينا لمالك غرفة "$roomName"! حققت غرفتك إجمالي دعم $roomTotalCoins كوينز، وتم إيداع أرباح الكأس بنسبة $appliedPercentage% بإجمالي: +$ownerProfitCoins كوينز في محفظتك بنجاح 🎁!',
        );
      }

      return {
        'ok': true,
        'roomTotalCoins': roomTotalCoins,
        'ownerUid': ownerUid,
        'ownerName': ownerName,
        'appliedPercentage': appliedPercentage,
        'ownerProfitCoins': ownerProfitCoins,
        'matchedTierName': matchedMilestone?.label ?? '',
      };
    } catch (e) {
      debugPrint('[RoomCupService] Settlement error: $e');
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// جلب تفاصيل وإحصائيات كأس الغرفة وأرباح صاحب الغرفة الجاهزة للاستلام
  Future<Map<String, dynamic>> fetchRoomCupStatus(String roomId, {bool isWeekly = true}) async {
    try {
      final cfg = await getConfig(refresh: true);
      final periodConfig = isWeekly ? cfg.weekly : cfg.daily;
      final sb = Supabase.instance.client;

      final roomData = await sb.from('rooms').select('room_id, name, host_uid, host_name').eq('room_id', roomId).maybeSingle();
      if (roomData == null) return {'ok': false};

      final ownerUid = roomData['host_uid']?.toString() ?? '';
      final now = DateTime.now().toUtc();
      final Duration timeframe = periodConfig.disbursementSchedule == 'daily'
          ? const Duration(days: 1)
          : periodConfig.disbursementSchedule == 'monthly'
              ? const Duration(days: 30)
              : periodConfig.disbursementSchedule == 'custom'
                  ? Duration(days: periodConfig.customDays > 0 ? periodConfig.customDays : 7)
                  : const Duration(days: 7);

      final cutoff = now.subtract(timeframe);

      final res = await sb
          .from('sent_gifts')
          .select('count, value')
          .eq('room_id', roomId)
          .gte('created_at', cutoff.toIso8601String());

      final gifts = (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      int roomTotalCoins = 0;
      for (final g in gifts) {
        final count = (g['count'] as num?)?.toInt() ?? 1;
        final value = (g['value'] as num?)?.toInt() ?? 0;
        roomTotalCoins += (count * value);
      }

      double appliedPercentage = periodConfig.basePercentage;
      int bonusCoins = 0;
      MilestoneTier? matchedMilestone;
      MilestoneTier? nextMilestone;

      if (periodConfig.useMilestones && periodConfig.milestones.isNotEmpty) {
        // Find highest achieved milestone
        final sortedDesc = [...periodConfig.milestones]..sort((a, b) => b.minCoins.compareTo(a.minCoins));
        for (final m in sortedDesc) {
          if (roomTotalCoins >= m.minCoins) {
            matchedMilestone = m;
            appliedPercentage = m.percentage;
            bonusCoins = m.bonusCoins;
            break;
          }
        }

        // Find next milestone target
        final sortedAsc = [...periodConfig.milestones]..sort((a, b) => a.minCoins.compareTo(b.minCoins));
        for (final m in sortedAsc) {
          if (roomTotalCoins < m.minCoins) {
            nextMilestone = m;
            break;
          }
        }
      }

      final ownerProfitCoins = ((roomTotalCoins * appliedPercentage) / 100).round() + bonusCoins;
      final minCoinsToQualify = (periodConfig.useMilestones && periodConfig.milestones.isNotEmpty)
          ? periodConfig.milestones.map((m) => m.minCoins).reduce((a, b) => a < b ? a : b)
          : periodConfig.minRoomCoinsToQualify;

      final isQualified = roomTotalCoins >= minCoinsToQualify;

      return {
        'ok': true,
        'enabled': periodConfig.enabled,
        'roomTotalCoins': roomTotalCoins,
        'minToQualify': minCoinsToQualify,
        'appliedPercentage': appliedPercentage,
        'ownerProfitCoins': ownerProfitCoins,
        'isQualified': isQualified,
        'ownerUid': ownerUid,
        'matchedTierName': matchedMilestone?.label ?? '',
        'matchedTierMinCoins': matchedMilestone?.minCoins ?? 0,
        'nextTierName': nextMilestone?.label ?? '',
        'nextTierCoins': nextMilestone?.minCoins ?? 0,
        'disbursementSchedule': periodConfig.disbursementSchedule,
        'payoutMethod': periodConfig.payoutMethod,
      };
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }
}

