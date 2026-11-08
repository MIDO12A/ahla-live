import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/supabase_compat.dart';
import 'dynamic_config_service.dart';

class AgencyTargetEvaluator {
  static SupabaseClient get _sb => Supabase.instance.client;

  static Future<void> evaluateHostTargets(String hostUserId) async {
    try {
      // 1. Get host's agency_member doc
      final memberQs = await _sb.from('host_agency_members')
          .select('*')
          .or('user_id.eq.$hostUserId,host_uid.eq.$hostUserId');

      Map<String, dynamic>? memberDoc;
      if (memberQs.isNotEmpty) {
        for (final doc in memberQs) {
          final m = Map<String, dynamic>.from(doc as Map);
          final st = m['status']?.toString();
          if (st == 'active') {
            memberDoc = m;
            break;
          }
        }
        if (memberDoc == null) {
          for (final doc in memberQs) {
            final m = Map<String, dynamic>.from(doc as Map);
            final st = m['status']?.toString();
            if (st != 'pending' && st != 'rejected' && st != 'left' && st != 'kicked') {
              memberDoc = m;
              break;
            }
          }
          memberDoc ??= Map<String, dynamic>.from(memberQs.first as Map);
        }
      }

      String agencyId = memberDoc?['agency_id']?.toString() ?? '';
      if (agencyId.isEmpty) {
        final uSnap = await _sb.from('users')
            .select('agency_id')
            .or('uid.eq.$hostUserId,id.eq.$hostUserId')
            .maybeSingle();
        agencyId = uSnap?['agency_id']?.toString() ?? '';
        if (agencyId.isNotEmpty && memberDoc == null) {
          final mDirect = await _sb.from('host_agency_members')
              .select('*')
              .eq('agency_id', agencyId)
              .or('user_id.eq.$hostUserId,host_uid.eq.$hostUserId')
              .maybeSingle();
          if (mDirect != null) memberDoc = Map<String, dynamic>.from(mDirect as Map);
        }
      }

      if (agencyId.isEmpty) return;

      final md = memberDoc ?? {};
      final diamondsMonthly = (md['diamonds_earned_monthly'] as num?)?.toInt() ?? (md['diamonds_balance'] as num?)?.toInt() ?? 0;
      final liveSeconds = (md['live_seconds_monthly'] as num?)?.toInt() ?? 0;
      final liveHours = (md['live_hours_monthly'] as num?)?.toDouble() ?? (liveSeconds / 3600.0);
      final validDays = (md['valid_days_monthly'] as num?)?.toInt() ?? 0;

      // 2. Get global targets config from app_config 'host_milestones_list' & host_milestones
      List<dynamic> milestonesSnap = [];
      try {
        final cfgRow = await _sb.from('app_config').select('value').eq('key', 'host_milestones_list').maybeSingle();
        if (cfgRow != null && cfgRow['value'] != null) {
          final v = cfgRow['value'];
          if (v is List) {
            milestonesSnap = v;
          } else if (v is String) {
            milestonesSnap = jsonDecode(v);
          }
        }
      } catch (_) {}
      if (milestonesSnap.isEmpty) {
        try {
          milestonesSnap = await _sb.from('host_milestones')
              .select('*')
              .eq('is_active', true);
          if (milestonesSnap.isEmpty) {
            milestonesSnap = await _sb.from('host_milestones').select('*');
          }
        } catch (_) {}
      }

      List<dynamic> targetsSnap = [];
      try {
        targetsSnap = await _sb.from('agency_targets_config')
            .select('*')
            .order('target_diamonds', ascending: true);
      } catch (_) {}

      final List<Map<String, dynamic>> allTargets = [];
      for (final doc in milestonesSnap) {
        allTargets.add(Map<String, dynamic>.from(doc as Map));
      }
      for (final doc in targetsSnap) {
        allTargets.add(Map<String, dynamic>.from(doc as Map));
      }
      if (allTargets.isEmpty) return;

      final now = DateTime.now();
      final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

      // 3. For each target, check if achieved
      for (final td in allTargets) {
        final targetDiamonds = (td['target_diamonds'] as num?)?.toInt() ?? 0;
        final requiredHours = (td['required_hours'] as num?)?.toDouble() ?? (td['target_hours'] as num?)?.toDouble() ?? 0.0;
        final requiredDays = (td['required_days'] as num?)?.toInt() ?? (td['target_days'] as num?)?.toInt() ?? 0;
        final targetId = td['id']?.toString() ?? '';

        // تجاهل المراحل المعطّلة من لوحة التحكم.
        final activeFlag = td['is_active'] ?? td['isActive'];
        if (activeFlag == false || activeFlag == 0) continue;

        final achievedId = '${hostUserId}_${targetId}_$currentMonth';

        if (targetDiamonds > 0 && diamondsMonthly >= targetDiamonds) {
          if (requiredHours > 0 && liveHours < requiredHours) continue;
          if (requiredDays > 0 && validDays < requiredDays) continue;

          // Did they already achieve this target this month?
          try {
            final achievedSnap = await _sb.from('agency_achieved_targets')
                .select('id')
                .eq('id', achievedId)
                .maybeSingle();

            if (achievedSnap == null) {
              // HIT TARGET!
              await _awardTarget(
                hostUserId: hostUserId,
                agencyId: agencyId,
                targetId: targetId,
                targetData: td,
                achievedId: achievedId,
                currentMonth: currentMonth,
              );
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error evaluating host targets: $e');
    }
  }

  /// Records active mic time for the host and updates monthly hours + valid days.
  static Future<void> recordLiveMinutes(String hostUserId, int minutes) async {
    try {
      final memberQs = await _sb.from('host_agency_members')
          .select('*')
          .or('user_id.eq.$hostUserId,host_uid.eq.$hostUserId')
          .eq('status', 'active')
          .limit(1);
      if (memberQs.isEmpty) return;

      final data = Map<String, dynamic>.from(memberQs.first as Map);
      final memberDocId = data['id']?.toString() ?? '';
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final lastDate = data['last_live_date']?.toString() ?? '';
      int todaySec = (data['today_live_seconds'] as num?)?.toInt() ?? 0;
      if (lastDate != todayStr) todaySec = 0;
      todaySec += (minutes * 60);

      final totalSec = ((data['live_seconds_monthly'] as num?)?.toInt() ?? 0) + (minutes * 60);
      final totalHours = (totalSec / 3600.0);
      int validDays = (data['valid_days_monthly'] as num?)?.toInt() ?? 0;

      final lastCounted = data['last_counted_valid_day']?.toString() ?? '';
      final reachedDay = todaySec >= 3600;
      if (reachedDay && lastCounted != todayStr) {
        validDays += 1;
      }

      final updatePayload = <String, dynamic>{
        'live_seconds_monthly': totalSec,
        'live_hours_monthly': double.parse(totalHours.toStringAsFixed(2)),
        'today_live_seconds': todaySec,
        'last_live_date': todayStr,
        'last_live_at': now.toIso8601String(),
        'valid_days_monthly': validDays,
        if (reachedDay && lastCounted != todayStr) 'last_counted_valid_day': todayStr,
      };

      if (memberDocId.isNotEmpty) {
        await _sb.from('host_agency_members').update(updatePayload).eq('id', memberDocId);
      } else {
        await _sb.from('host_agency_members').update(updatePayload).or('user_id.eq.$hostUserId,host_uid.eq.$hostUserId');
      }

      await evaluateHostTargets(hostUserId);
    } catch (e) {
      debugPrint('Error recording live minutes: $e');
    }
  }

  static Future<void> _awardTarget({
    required String hostUserId,
    required String agencyId,
    required String targetId,
    required Map<String, dynamic> targetData,
    required String achievedId,
    required String currentMonth,
  }) async {
    final targetDiamonds = (targetData['target_diamonds'] as num?)?.toInt() ?? 0;
    final rewardType = targetData['reward_type']?.toString() ?? 'salary_usd';
    final rawRewardValue = (targetData['reward_value'] as num?)?.toDouble() ?? 0.0;
    final rewardItemId = targetData['reward_item_id']?.toString() ?? '';
    final rewardFrameId = targetData['reward_frame_id']?.toString() ?? (rewardType == 'frame' ? rewardItemId : null);
    final rewardBadgeId = targetData['reward_badge_id']?.toString() ?? (rewardType == 'badge' ? rewardItemId : null);
    final rewardDurationDays = (targetData['reward_duration_days'] as num?)?.toInt() ?? 30;

    // فحص ما إذا كان المضيف قد قام بفك ألماس من التارجت خلال الشهر
    bool hasUnpacked = false;
    try {
      final mRow = await _sb.from('host_agency_members')
          .select('unpacked_target_diamonds, has_unpacked_target')
          .or('user_id.eq.$hostUserId,host_uid.eq.$hostUserId')
          .maybeSingle();
      if (mRow != null) {
        final unp = (mRow['unpacked_target_diamonds'] as num?)?.toInt() ?? 0;
        hasUnpacked = unp > 0 || mRow['has_unpacked_target'] == true;
      }
    } catch (_) {}

    // في حال فك المضيف من التارجت، يتم احتساب الراتب بنسبة 60% فقط (خصم 40% من الراتب)
    // مثلاً: إذا كان الراتب 9 دولار، ينزل إلى 5.4 دولار (~ 5 دولار)
    final salaryRate = DynamicConfigService().hostTargetSalaryRate; // 0.60
    final rewardValue = hasUnpacked ? (rawRewardValue * salaryRate) : rawRewardValue;

    // 1. Mark as achieved
    try {
      await _sb.from('agency_achieved_targets').upsert({
        'id': achievedId,
        'agency_id': agencyId,
        'target_diamonds': targetDiamonds,
        'reward_amount': rewardValue,
        'month': currentMonth,
        'achieved_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[AgencyTargetEvaluator] error upserting achieved target: $e');
    }

    // 2. Give rewards to Host automatically
    final expiresAt = DateTime.now().add(Duration(days: rewardDurationDays)).toIso8601String();

    try {
      if (rewardType == 'gold' && rewardValue > 0) {
        final u = await _sb.from('users').select('coins').or('uid.eq.$hostUserId,id.eq.$hostUserId').maybeSingle();
        final cur = (u?['coins'] as num?)?.toInt() ?? 0;
        await _sb.from('users').update({
          'coins': cur + rewardValue.toInt(),
        }).or('uid.eq.$hostUserId,id.eq.$hostUserId');
      } else if (rewardType == 'diamonds' && rewardValue > 0) {
        final rewardDiamonds = rewardValue.toInt();
        final idem = 'target_reward_${hostUserId}_${targetId}_$currentMonth';
        var credited = false;
        try {
          final rpcRes = await _sb.rpc('agency_credit_member_reward', params: {
            'p_host_uid': hostUserId,
            'p_diamonds': rewardDiamonds,
            'p_idem_key': idem,
            'p_note': 'مكافأة تارجت $targetDiamonds 💎',
          });
          credited = rpcRes is Map &&
              (rpcRes['status'] == 'ok' ||
                  rpcRes['status'] == 'already_processed');
        } catch (e) {
          debugPrint(
              '[AgencyTargetEvaluator] agency_credit_member_reward failed: $e');
        }

        if (!credited) {
          Map<String, dynamic>? mSnap;
          try {
            mSnap = await _sb.from('host_agency_members')
                .select('id, diamonds, diamonds_balance, diamonds_available')
                .or('user_id.eq.$hostUserId,host_uid.eq.$hostUserId')
                .maybeSingle();
          } catch (_) {}

          if (mSnap != null) {
            final d1 = (mSnap['diamonds'] as num?)?.toInt() ?? 0;
            final d2 = (mSnap['diamonds_balance'] as num?)?.toInt() ?? 0;
            final d3 = (mSnap['diamonds_available'] as num?)?.toInt() ?? 0;
            final newBalance = d2 + rewardDiamonds;
            await _sb.from('host_agency_members').update({
              'diamonds': d1 + rewardDiamonds,
              'diamonds_balance': newBalance,
              'diamonds_available': d3 + rewardDiamonds,
            }).eq('id', mSnap['id']);
            try {
              await _sb.from('agency_diamond_ledger').insert({
                'agency_id': agencyId,
                'user_id': hostUserId,
                'txn_type': 'target_reward',
                'amount': rewardDiamonds,
                'direction': 1,
                'balance_after': newBalance,
                'note': 'مكافأة تارجت $targetDiamonds 💎',
                'sender_name': 'النظام',
                'idempotency_key': idem,
                'created_at': DateTime.now().toUtc().toIso8601String(),
              });
            } catch (_) {}
          } else {
            final u = await _sb.from('users').select('diamonds').or('uid.eq.$hostUserId,id.eq.$hostUserId').maybeSingle();
            final cur = (u?['diamonds'] as num?)?.toInt() ?? 0;
            await _sb.from('users').update({
              'diamonds': cur + rewardDiamonds,
            }).or('uid.eq.$hostUserId,id.eq.$hostUserId');
          }
        }
      } else if (rewardType == 'salary_usd' && rewardValue > 0) {
        await _sb.from('host_salaries').insert({
          'id': 'sal_${hostUserId}_${targetId}_$currentMonth',
          'host_uid': hostUserId,
          'agency_id': agencyId,
          'month': currentMonth,
          'total_diamonds': targetDiamonds,
          'base_salary_usd': rewardValue,
          'bonus_usd': 0,
          'total_salary_usd': rewardValue,
          'status': 'pending',
          'created_at': DateTime.now().toIso8601String(),
        });

        if (hasUnpacked) {
          try {
            await _sendSystemMessage(
              hostUserId,
              'مبروك! حققت تارجت $targetDiamonds 💎. نظراً لفك جزء من ألماس التارجت، تم احتساب الراتب بنسبة 60% بقيمة ${rewardValue.toStringAsFixed(1)}\$ بدلاً من ${rawRewardValue.toStringAsFixed(1)}\$ (تم تطبيق خصم 40% من الراتب).',
            );
          } catch (_) {}
        }

        // Update host_usd_wallets
        try {
          final uwSnap = await _sb.from('host_usd_wallets')
              .select('balance_usd')
              .eq('host_uid', hostUserId)
              .maybeSingle();
          if (uwSnap != null) {
            final curUsd = (uwSnap['balance_usd'] as num?)?.toDouble() ?? 0.0;
            await _sb.from('host_usd_wallets').update({
              'balance_usd': curUsd + rewardValue,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('host_uid', hostUserId);
          } else {
            await _sb.from('host_usd_wallets').insert({
              'host_uid': hostUserId,
              'balance_usd': rewardValue,
              'frozen_usd': 0,
              'updated_at': DateTime.now().toIso8601String(),
            });
          }
        } catch (_) {}
      }

      // Backpack rewards (frames, badges, store items)
      if (rewardFrameId != null && rewardFrameId.isNotEmpty) {
        await _sb.from('user_backpack').insert({
          'user_id': hostUserId,
          'item_type': 'frame',
          'item_id': rewardFrameId,
          'expires_at': expiresAt,
          'created_at': DateTime.now().toIso8601String(),
        });
        await _sb.from('users').update({
          'active_frame': rewardFrameId,
        }).or('uid.eq.$hostUserId,id.eq.$hostUserId');
      }

      if (rewardBadgeId != null && rewardBadgeId.isNotEmpty) {
        await _sb.from('user_backpack').insert({
          'user_id': hostUserId,
          'item_type': 'badge',
          'item_id': rewardBadgeId,
          'expires_at': expiresAt,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      if (rewardItemId.isNotEmpty && rewardType == 'gift_item') {
        await _sb.from('user_backpack').insert({
          'user_id': hostUserId,
          'item_type': 'gift',
          'item_id': rewardItemId,
          'count': (rewardValue > 0 ? rewardValue.toInt() : 1),
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('[AgencyTargetEvaluator] error awarding items: $e');
    }

    // 4. Send System Message to Host with celebration
    String rewardDesc = rewardType == 'salary_usd' ? '$rewardValue\$' :
                        rewardType == 'gold' ? '${rewardValue.toInt()} عملة ذهبية' :
                        rewardType == 'diamonds' ? '${rewardValue.toInt()} ماسة' : 'مكافأة مميزة';
    String msg = '🎉 تهانينا! لقد حققت هدف $targetDiamonds 💎 وحصلت على $rewardDesc وجوائزك التلقائية.';
    await _sendSystemMessage(hostUserId, msg, imageUrl: targetData['reward_image_url']?.toString());
  }

  static Future<void> _sendSystemMessage(String userId, String text, {String? imageUrl}) async {
    try {
      await _sb.from('private_messages').insert({
        'sender_id': 'system',
        'receiver_id': userId,
        'text': text,
        'image_url': imageUrl ?? '',
        'type': 'system',
        'created_at': DateTime.now().toIso8601String(),
        'is_read': false,
        'conversation_id': 'system_$userId',
      });

      // Update conversation
      final conv = await _sb.from('conversations')
          .select('id, unread_count2')
          .eq('id', 'system_$userId')
          .maybeSingle();
      final unread = (conv?['unread_count2'] as num?)?.toInt() ?? 0;
      await _sb.from('conversations').upsert({
        'id': 'system_$userId',
        'user1_id': 'system',
        'user2_id': userId,
        'last_message': text,
        'last_message_time': DateTime.now().toIso8601String(),
        'unread_count1': 0,
        'unread_count2': unread + 1,
      });
    } catch (e) {
      debugPrint('[AgencyTargetEvaluator] _sendSystemMessage error: $e');
    }
  }
}
