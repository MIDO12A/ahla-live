import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class AgencyTargetEvaluator {
  static FirebaseFirestore get _db => FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'default',
      );

  static Future<void> evaluateHostTargets(String hostUserId) async {
    try {
      // 1. Get host's agency_member doc
      final memberQs = await _db.collection('host_agency_members')
          .where('user_id', isEqualTo: hostUserId)
          .get();

      DocumentSnapshot<Map<String, dynamic>>? memberDoc;
      if (memberQs.docs.isNotEmpty) {
        for (final doc in memberQs.docs) {
          final st = doc.data()['status']?.toString();
          if (st == 'active') {
            memberDoc = doc;
            break;
          }
        }
        memberDoc ??= memberQs.docs.firstWhere(
          (doc) {
            final st = doc.data()['status']?.toString();
            return st != 'pending' && st != 'rejected' && st != 'left' && st != 'kicked';
          },
          orElse: () => memberQs.docs.first,
        );
      }

      String agencyId = memberDoc?.data()?['agency_id']?.toString() ?? '';
      if (agencyId.isEmpty) {
        final uSnap = await _db.collection('users').doc(hostUserId).get();
        agencyId = uSnap.data()?['agency_id']?.toString() ?? '';
        if (agencyId.isNotEmpty && memberDoc == null) {
          final mDirect = await _db.collection('host_agency_members').doc('${agencyId}_$hostUserId').get();
          if (mDirect.exists) memberDoc = mDirect;
        }
      }

      if (agencyId.isEmpty) return;

      final md = memberDoc?.data() ?? {};
      final d1 = (md['diamonds_earned_monthly'] as num?)?.toInt() ?? 0;
      final d2 = (md['diamonds_balance'] as num?)?.toInt() ?? 0;
      final d3 = (md['diamonds'] as num?)?.toInt() ?? 0;
      final diamondsMonthly = [d1, d2, d3].reduce((curr, next) => curr > next ? curr : next);
      final liveSeconds = (md['live_seconds_monthly'] as num?)?.toInt() ?? 0;
      final liveHours = (md['live_hours_monthly'] as num?)?.toDouble() ?? (liveSeconds / 3600.0);
      final validDays = (md['valid_days_monthly'] as num?)?.toInt() ?? 0;

      // 2. Get global targets config from host_milestones and agency_targets_config
      var milestonesSnap = await _db.collection('host_milestones')
          .where('is_active', isEqualTo: true)
          .get();
      if (milestonesSnap.docs.isEmpty) {
        milestonesSnap = await _db.collection('host_milestones').get();
      }

      final targetsSnap = await _db.collection('agency_targets_config')
          .orderBy('target_diamonds', descending: false)
          .get();

      final List<Map<String, dynamic>> allTargets = [];
      for (final doc in milestonesSnap.docs) {
        final d = doc.data();
        d['id'] = doc.id;
        allTargets.add(d);
      }
      for (final doc in targetsSnap.docs) {
        final d = doc.data();
        d['id'] = doc.id;
        allTargets.add(d);
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

        if (targetDiamonds > 0 && diamondsMonthly >= targetDiamonds) {
          if (requiredHours > 0 && liveHours < requiredHours) continue;
          if (requiredDays > 0 && validDays < requiredDays) continue;

          // Did they already achieve this target this month?
          final achievedId = '${hostUserId}_${targetId}_$currentMonth';
          final achievedRef = _db.collection('agency_achieved_targets').doc(achievedId);

          final achievedSnap = await achievedRef.get();
          if (!achievedSnap.exists) {
            // HIT TARGET!
            await _awardTarget(
              hostUserId: hostUserId,
              agencyId: agencyId,
              targetId: targetId,
              targetData: td,
              achievedRef: achievedRef,
              currentMonth: currentMonth,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error evaluating host targets: $e');
    }
  }

  /// Records active mic time for the host and updates monthly hours + valid days.
  static Future<void> recordLiveMinutes(String hostUserId, int minutes) async {
    try {
      final memberQs = await _db.collection('host_agency_members')
          .where('user_id', isEqualTo: hostUserId)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (memberQs.docs.isEmpty) return;

      final doc = memberQs.docs.first;
      final data = doc.data();
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

      await doc.reference.update({
        'live_seconds_monthly': totalSec,
        'live_hours_monthly': double.parse(totalHours.toStringAsFixed(2)),
        'today_live_seconds': todaySec,
        'last_live_date': todayStr,
        'last_live_at': now.toIso8601String(),
        'valid_days_monthly': validDays,
        if (reachedDay && lastCounted != todayStr) 'last_counted_valid_day': todayStr,
      });

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
    required DocumentReference achievedRef,
    required String currentMonth,
  }) async {
    final targetDiamonds = (targetData['target_diamonds'] as num?)?.toInt() ?? 0;
    final rewardType = targetData['reward_type']?.toString() ?? 'salary_usd';
    final rewardValue = (targetData['reward_value'] as num?)?.toDouble() ?? 0.0;
    final rewardItemId = targetData['reward_item_id']?.toString() ?? '';
    final num? rawCommissionRate = targetData['agent_commission_rate'] as num?;
    final num? rawProfitPercent = targetData['agency_profit_percent'] as num?;
    final double agentCommissionRate = rawCommissionRate?.toDouble() ??
        (rawProfitPercent != null ? (rawProfitPercent.toDouble() / 100.0) : 0.1);
    final rewardFrameId = targetData['reward_frame_id']?.toString() ?? (rewardType == 'frame' ? rewardItemId : null);
    final rewardBadgeId = targetData['reward_badge_id']?.toString() ?? (rewardType == 'badge' ? rewardItemId : null);
    final rewardDurationDays = (targetData['reward_duration_days'] as num?)?.toInt() ?? 30;

    // 1. Mark as achieved
    await achievedRef.set({
      'user_id': hostUserId,
      'agency_id': agencyId,
      'target_id': targetId,
      'month': currentMonth,
      'reward_type': rewardType,
      'reward_value': rewardValue,
      'reward_item_id': rewardItemId,
      'achieved_at': DateTime.now().toIso8601String(),
    });

    // 2. Give agent commission to Agency Owner
    if (agentCommissionRate > 0 && agencyId.isNotEmpty) {
      final agencySnap = await _db.collection('host_agencies').doc(agencyId).get();
      if (agencySnap.exists) {
        final ownerId = agencySnap.data()?['owner_id']?.toString() ?? '';
        if (ownerId.isNotEmpty) {
          final profit = (targetDiamonds * agentCommissionRate).toInt();

          final agencyWalletRef = _db.collection('agency_wallets').doc(agencyId);
          final awSnap = await agencyWalletRef.get();
          if (awSnap.exists) {
            await agencyWalletRef.update({
              'diamond_balance': FieldValue.increment(profit),
            });
          } else {
            await agencyWalletRef.set({
              'agency_id': agencyId,
              'diamond_balance': profit,
              'gold_balance': 0,
            });
          }

          // Also update owner agency member diamonds balance
          try {
            final ownerMemQs = await _db.collection('host_agency_members')
                .where('agency_id', isEqualTo: agencyId)
                .where('user_id', isEqualTo: ownerId)
                .limit(1)
                .get();
            if (ownerMemQs.docs.isNotEmpty) {
              await ownerMemQs.docs.first.reference.update({
                'diamonds': FieldValue.increment(profit),
                'diamonds_balance': FieldValue.increment(profit),
                'diamonds_available': FieldValue.increment(profit),
              });
            }
          } catch (_) {}

          // Notify owner
          await _sendSystemMessage(ownerId, 'مبروك! تمت إضافة عمولة بقيمة $profit ماسة (بنسبة ${(agentCommissionRate * 100).toStringAsFixed(1)}%) إلى محفظة وكالتك، لنجاح مضيفك في تحقيق تارجت $targetDiamonds 💎.');
        }
      }
    }

    // 3. Give rewards to Host automatically
    final expiresAt = DateTime.now().add(Duration(days: rewardDurationDays)).toIso8601String();

    if (rewardType == 'gold' && rewardValue > 0) {
      await _db.collection('users').doc(hostUserId).update({
        'coins': FieldValue.increment(rewardValue.toInt()),
      });
    } else if (rewardType == 'diamonds' && rewardValue > 0) {
      await _db.collection('users').doc(hostUserId).update({
        'diamonds': FieldValue.increment(rewardValue.toInt()),
      });
      // Also update host_agency_members
      try {
        final mRef = _db.collection('host_agency_members')
            .where('user_id', isEqualTo: hostUserId)
            .limit(1);
        final mSnap = await mRef.get();
        if (mSnap.docs.isNotEmpty) {
          await mSnap.docs.first.reference.update({
            'diamonds': FieldValue.increment(rewardValue.toInt()),
            'diamonds_balance': FieldValue.increment(rewardValue.toInt()),
            'diamonds_available': FieldValue.increment(rewardValue.toInt()),
          });
        }
      } catch (_) {}
    } else if (rewardType == 'salary_usd' && rewardValue > 0) {
      await _db.collection('host_salaries').doc().set({
        'user_id': hostUserId,
        'agency_id': agencyId,
        'target_id': targetId,
        'amount_usd': rewardValue,
        'target_diamonds': targetDiamonds,
        'month': currentMonth,
        'status': 'pending_payout',
        'created_at': DateTime.now().toIso8601String(),
      });

      // Update host_usd_wallets
      try {
        final usdWalletRef = _db.collection('host_usd_wallets').doc(hostUserId);
        final uwSnap = await usdWalletRef.get();
        if (uwSnap.exists) {
          await usdWalletRef.update({
            'usd_balance': FieldValue.increment(rewardValue),
          });
        } else {
          await usdWalletRef.set({
            'user_id': hostUserId,
            'usd_balance': rewardValue,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      } catch (_) {}
    }
    
    // Backpack rewards (frames, badges, store items)
    if (rewardFrameId != null && rewardFrameId.isNotEmpty) {
       await _db.collection('user_backpack').doc().set({
         'user_id': hostUserId,
         'item_type': 'frame',
         'item_id': rewardFrameId,
         'expires_at': expiresAt,
         'created_at': DateTime.now().toIso8601String(),
       });
       await _db.collection('users').doc(hostUserId).update({
         'active_frame': rewardFrameId,
       });
    }
    
    if (rewardBadgeId != null && rewardBadgeId.isNotEmpty) {
       await _db.collection('user_backpack').doc().set({
         'user_id': hostUserId,
         'item_type': 'badge',
         'item_id': rewardBadgeId,
         'expires_at': expiresAt,
         'created_at': DateTime.now().toIso8601String(),
       });
    }

    if (rewardItemId.isNotEmpty && rewardType == 'gift_item') {
      await _db.collection('user_backpack').doc().set({
        'user_id': hostUserId,
        'item_type': 'gift',
        'item_id': rewardItemId,
        'count': (rewardValue > 0 ? rewardValue.toInt() : 1),
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    
    // 4. Send System Message to Host with celebration
    String rewardDesc = rewardType == 'salary_usd' ? '$rewardValue\$' :
                        rewardType == 'gold' ? '${rewardValue.toInt()} عملة ذهبية' :
                        rewardType == 'diamonds' ? '${rewardValue.toInt()} ماسة' : 'مكافأة مميزة';
    String msg = '🎉 تهانينا! لقد حققت هدف $targetDiamonds 💎 وحصلت على $rewardDesc وجوائزك التلقائية.';
    await _sendSystemMessage(hostUserId, msg, imageUrl: targetData['reward_image_url']?.toString());
  }
  
  static Future<void> _sendSystemMessage(String userId, String text, {String? imageUrl}) async {
     await _db.collection('private_messages').doc().set({
        'sender_id': 'system',
        'receiver_id': userId,
        'text': text,
        'image_url': imageUrl ?? '',
        'type': 'system',
        'created_at': DateTime.now().toIso8601String(),
        'is_read': false,
        'conversationId': 'system_$userId',
     });
     
     // Update conversation
     await _db.collection('conversations').doc('system_$userId').set({
        'id': 'system_$userId',
        'user1Id': 'system',
        'user2Id': userId,
        'lastMessage': text,
        'lastMessageTime': DateTime.now().toIso8601String(),
        'unreadCount1': 0,
        'unreadCount2': FieldValue.increment(1),
     }, SetOptions(merge: true));
  }
}
