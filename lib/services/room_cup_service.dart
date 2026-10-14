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

  const MilestoneTier({
    required this.id,
    required this.minCoins,
    required this.percentage,
    required this.label,
  });

  factory MilestoneTier.fromMap(Map<String, dynamic> map) {
    return MilestoneTier(
      id: map['id']?.toString() ?? '',
      minCoins: (map['minCoins'] as num?)?.toInt() ?? 0,
      percentage: (map['percentage'] as num?)?.toDouble() ?? 0.0,
      label: map['label']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'minCoins': minCoins,
    'percentage': percentage,
    'label': label,
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

  const OwnerCupPeriodConfig({
    required this.enabled,
    required this.basePercentage,
    required this.useMilestones,
    required this.minRoomCoinsToQualify,
    required this.svgaFrame,
    required this.badgeIcon,
    required this.daysValid,
    required this.milestones,
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

class RoomCupService {
  static final RoomCupService _instance = RoomCupService._internal();
  factory RoomCupService() => _instance;
  RoomCupService._internal();

  RoomOwnerCupConfig? _cachedConfig;
  DateTime? _lastFetch;

  Future<RoomOwnerCupConfig> getConfig({bool refresh = false}) async {
    if (!refresh && _cachedConfig != null && _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(minutes: 5)) {
      return _cachedConfig!;
    }

    try {
      final raw = await FirebaseService().getAppConfig('room_cup_rewards');
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
    final cfg = await getConfig();
    final periodConfig = isWeekly ? cfg.weekly : cfg.daily;

    if (!periodConfig.enabled && !force) {
      return {'ok': false, 'message': 'نظام كأس الغرفة معطل'};
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

      // 2. Fetch sent gifts in timeframe
      final now = DateTime.now().toUtc();
      final cutoff = isWeekly
          ? now.subtract(const Duration(days: 7))
          : now.subtract(const Duration(days: 1));

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

      if (roomTotalCoins < periodConfig.minRoomCoinsToQualify && !force) {
        return {
          'ok': false,
          'message': 'إجمالي كوينز الغرفة ($roomTotalCoins) لم يصل للحد الأدنى (${periodConfig.minRoomCoinsToQualify})'
        };
      }

      // Determine applied percentage
      double appliedPercentage = periodConfig.basePercentage;
      if (periodConfig.useMilestones && periodConfig.milestones.isNotEmpty) {
        final sorted = [...periodConfig.milestones]..sort((a, b) => b.minCoins.compareTo(a.minCoins));
        final match = sorted.firstWhere(
          (m) => roomTotalCoins >= m.minCoins,
          orElse: () => sorted.last,
        );
        if (roomTotalCoins >= match.minCoins) {
          appliedPercentage = match.percentage;
        }
      }

      final ownerProfitCoins = ((roomTotalCoins * appliedPercentage) / 100).round();

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
            'item_name': 'كأس الغرفة ${isWeekly ? 'الأسبوعي' : 'اليومي'} - $roomName',
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
        await SupabaseDataService().sendNotification(
          uid: ownerUid,
          type: 'room_cup_award',
          actorUid: ownerUid,
          title: '🏆 مبروك! أرباح ${isWeekly ? 'كأس الغرفة الأسبوعي' : 'كأس الغرفة اليومي'} لغرفتك',
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
      };
    } catch (e) {
      debugPrint('[RoomCupService] Settlement error: $e');
      return {'ok': false, 'error': e.toString()};
    }
  }
}
