import { Router, Request, Response } from 'express';
import { FieldValue } from 'firebase-admin/firestore';
import { db } from '../config/database';
import { authenticate } from '../middleware/auth';

const router = Router();

function asInt(v: unknown): number {
  if (typeof v === 'number') return Math.trunc(v);
  const n = parseInt(String(v ?? ''), 10);
  return Number.isFinite(n) ? n : 0;
}

function asNum(v: unknown): number {
  if (typeof v === 'number') return v;
  const n = parseFloat(String(v ?? ''));
  return Number.isFinite(n) ? n : 0;
}

/**
 * Server-authoritative host target evaluator (V2.7). Rewards and commissions
 * are computed and written ONLY from the backend — a client can never award
 * itself (or anyone else) salary, frames or agency profit. This function is
 * invoked from the gift route after a successful host reward deposit, and is
 * idempotent thanks to agency_achieved_targets/{host}_{target}_{YYYY-MM}.
 */
export async function evaluateHostTargets(hostUserId: string): Promise<string[]> {
  const awarded: string[] = [];

  // 1. Host must be an active agency member.
  const memberQs = await db
    .collection('host_agency_members')
    .where('user_id', '==', hostUserId)
    .where('status', '==', 'active')
    .limit(1)
    .get();
  if (memberQs.empty) return awarded;
  const memberData = memberQs.docs[0].data() ?? {};
  const agencyId = String(memberData.agency_id ?? '');
  const diamondsMonthly = asInt(memberData.diamonds_earned_monthly);
  const liveSecondsMonthly = asInt(memberData.live_seconds_monthly);
  const liveHoursMonthly = asNum(memberData.live_hours_monthly ?? (liveSecondsMonthly / 3600));
  const validDaysMonthly = asInt(memberData.valid_days_monthly);

  // 2. Gather active targets from milestones + dedicated config.
  const [milestonesSnap, targetsSnap] = await Promise.all([
    db.collection('host_milestones').where('is_active', '==', true).get(),
    db.collection('agency_targets_config').orderBy('target_diamonds', 'asc').get(),
  ]);
  const allTargets: Array<{ id: string; targetData: Record<string, unknown> }> = [];
  milestonesSnap.docs.forEach((d) => allTargets.push({ id: d.id, targetData: d.data() }));
  targetsSnap.docs.forEach((d) => allTargets.push({ id: d.id, targetData: d.data() }));
  if (allTargets.length === 0) return awarded;

  const now = new Date();
  const currentMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;

  for (const t of allTargets) {
    const targetDiamonds = asInt(t.targetData.target_diamonds);
    const requiredHours = asNum(t.targetData.required_hours ?? t.targetData.target_hours ?? 0);
    const requiredDays = asInt(t.targetData.required_days ?? t.targetData.target_days ?? 0);
    const targetId = t.id;

    if (targetDiamonds <= 0 || diamondsMonthly < targetDiamonds) continue;
    if (requiredHours > 0 && liveHoursMonthly < requiredHours) continue;
    if (requiredDays > 0 && validDaysMonthly < requiredDays) continue;

    const achievedRef = db
      .collection('agency_achieved_targets')
      .doc(`${hostUserId}_${targetId}_${currentMonth}`);
    const achievedSnap = await achievedRef.get();
    if (achievedSnap.exists) continue;

    const rewardType = String(t.targetData.reward_type ?? 'salary_usd');
    const rewardValue = asNum(t.targetData.reward_value);
    const rewardItemId = String(t.targetData.reward_item_id ?? '');
    const rawRate = t.targetData.agent_commission_rate;
    const rawProfit = t.targetData.agency_profit_percent;
    const commissionRate =
      typeof rawRate === 'number'
        ? rawRate
        : typeof rawProfit === 'number'
          ? rawProfit / 100
          : 0.1;
    const rewardFrameId =
      rewardType === 'frame' && rewardItemId.length > 0
        ? rewardItemId
        : String(t.targetData.reward_frame_id ?? '');
    const rewardBadgeId =
      rewardType === 'badge' && rewardItemId.length > 0
        ? rewardItemId
        : String(t.targetData.reward_badge_id ?? '');
    const durationDays = asInt(t.targetData.reward_duration_days) || 30;
    const expiresAt = new Date(now.getTime() + durationDays * 86400000).toISOString();

    // Run the whole reward in one transaction to stay consistent.
    await db.runTransaction(async (txn) => {
      // ── ALL READS FIRST ──
      // Firestore transactions forbid ANY read after the first write.
      // Reading the agency AFTER txn.set below cancelled the transaction.
      let agencySnap: any = null;
      if (commissionRate > 0 && agencyId.length > 0) {
        agencySnap = await txn.get(db.collection('host_agencies').doc(agencyId));
      }

      txn.set(achievedRef, {
        user_id: hostUserId,
        agency_id: agencyId,
        target_id: targetId,
        month: currentMonth,
        reward_type: rewardType,
        reward_value: rewardValue,
        reward_item_id: rewardItemId,
        achieved_at: new Date().toISOString(),
      });

      // Agency owner commission.
      if (commissionRate > 0 && agencyId.length > 0) {
        if (agencySnap && agencySnap.exists) {
          const ownerId = String(agencySnap.data()?.owner_id ?? '');
          if (ownerId.length > 0) {
            const profit = Math.trunc(targetDiamonds * commissionRate);
            txn.set(
              db.collection('agency_wallets').doc(agencyId),
              { diamond_balance: FieldValue.increment(profit) },
              { merge: true },
            );
            txn.set(
              db.collection('private_messages').doc(),
              {
                sender_id: 'system',
                receiver_id: ownerId,
                text: `مبروك! تمت إضافة عمولة بقيمة $profit ماسة إلى محفظة وكالتك، لنجاح مضيفك في تحقيق تارجت $targetDiamonds 💎.`,
                type: 'system',
                created_at: new Date().toISOString(),
                is_read: false,
                conversationId: `system_${ownerId}`,
              },
              { merge: true },
            );
          }
        }
      }

      // Host rewards.
      const hostRef = db.collection('users').doc(hostUserId);
      if (rewardType === 'gold' && rewardValue > 0) {
        txn.update(hostRef, { coins: FieldValue.increment(Math.trunc(rewardValue)) });
      } else if (rewardType === 'diamonds' && rewardValue > 0) {
        txn.update(hostRef, { diamonds: FieldValue.increment(Math.trunc(rewardValue)) });
      } else if (rewardType === 'salary_usd' && rewardValue > 0) {
        txn.set(db.collection('host_salaries').doc(), {
          user_id: hostUserId,
          agency_id: agencyId,
          target_id: targetId,
          amount_usd: rewardValue,
          target_diamonds: targetDiamonds,
          month: currentMonth,
          status: 'pending_payout',
          created_at: new Date().toISOString(),
        });
      }

      // Backpack rewards.
      const backpackRef = db.collection('user_backpack');
      if (rewardFrameId.length > 0) {
        txn.set(backpackRef.doc(), {
          user_id: hostUserId,
          item_type: 'frame',
          item_id: rewardFrameId,
          expires_at: expiresAt,
          created_at: new Date().toISOString(),
        });
        txn.update(hostRef, { active_frame: rewardFrameId });
      }
      if (rewardBadgeId.length > 0) {
        txn.set(backpackRef.doc(), {
          user_id: hostUserId,
          item_type: 'badge',
          item_id: rewardBadgeId,
          expires_at: expiresAt,
          created_at: new Date().toISOString(),
        });
      }
      if (rewardItemId.length > 0 && rewardType === 'gift_item') {
        txn.set(backpackRef.doc(), {
          user_id: hostUserId,
          item_type: 'gift',
          item_id: rewardItemId,
          count: rewardValue > 0 ? Math.trunc(rewardValue) : 1,
          created_at: new Date().toISOString(),
        });
      }

      txn.set(db.collection('private_messages').doc(), {
        sender_id: 'system',
        receiver_id: hostUserId,
        text: `🎉 تهانينا! لقد حققت هدف $targetDiamonds 💎.`,
        type: 'system',
        created_at: new Date().toISOString(),
        is_read: false,
        conversationId: `system_${hostUserId}`,
      });
    });

    awarded.push(targetId);
  }

  return awarded;
}

/**
 * POST /api/v1/host-targets/evaluate
 *  - body: { hostUserId }
 *  - Only the authenticated host (self) may trigger their own evaluation.
 */
router.post('/evaluate', authenticate, async (req: Request, res: Response) => {
  const hostUserId = String(req.body?.hostUserId ?? '');
  if (!hostUserId) {
    res.status(400).json({ error: 'Missing hostUserId' });
    return;
  }
  // V1.2: a user may only evaluate their OWN targets — no cross-account gifting.
  if (hostUserId !== req.user?.uid) {
    res.status(403).json({ error: 'Forbidden: you can only evaluate your own host targets' });
    return;
  }

  try {
    const awarded = await evaluateHostTargets(hostUserId);
    res.json({ evaluated: true, awarded });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /api/v1/host-targets/live-heartbeat
 * Records live broadcast / mic session minutes for the host.
 *  - body: { roomId, minutes }
 *  - Increments live_seconds_monthly and computes live_hours_monthly
 *  - Tracks today's date (YYYY-MM-DD) to increment valid_days_monthly (min 60 mins/day)
 *  - Triggers target evaluation
 */
router.post('/live-heartbeat', authenticate, async (req: Request, res: Response) => {
  const hostUserId = req.user?.uid;
  if (!hostUserId) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }

  const { roomId, minutes: rawMinutes } = req.body ?? {};
  const minutes = Math.max(1, Math.min(60, Number(rawMinutes) || 1));
  const seconds = minutes * 60;

  try {
    const memberQs = await db
      .collection('host_agency_members')
      .where('user_id', '==', hostUserId)
      .where('status', '==', 'active')
      .limit(1)
      .get();

    if (memberQs.empty) {
      res.json({ success: true, message: 'not_an_active_host' });
      return;
    }

    const memberDoc = memberQs.docs[0];
    const memberData = memberDoc.data() ?? {};
    const now = new Date();
    const todayStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
    const lastLiveDate = String(memberData.last_live_date ?? '');
    let todaySeconds = asInt(memberData.today_live_seconds);
    if (lastLiveDate !== todayStr) {
      todaySeconds = 0;
    }
    todaySeconds += seconds;

    const newTotalSeconds = asInt(memberData.live_seconds_monthly) + seconds;
    const newTotalHours = Math.round((newTotalSeconds / 3600) * 100) / 100;
    let validDays = asInt(memberData.valid_days_monthly);

    // If reached 60 mins today and today wasn't counted yet
    const lastCountedValidDay = String(memberData.last_counted_valid_day ?? '');
    const reachedMinDay = todaySeconds >= 3600;
    if (reachedMinDay && lastCountedValidDay !== todayStr) {
      validDays += 1;
    }

    await memberDoc.ref.update({
      live_seconds_monthly: newTotalSeconds,
      live_hours_monthly: newTotalHours,
      today_live_seconds: todaySeconds,
      last_live_date: todayStr,
      last_live_at: now.toISOString(),
      valid_days_monthly: validDays,
      ...(reachedMinDay && lastCountedValidDay !== todayStr ? { last_counted_valid_day: todayStr } : {}),
    });

    evaluateHostTargets(hostUserId).catch((err) => {
      console.error('[live-heartbeat] host target evaluation error:', err);
    });

    res.json({
      success: true,
      live_hours_monthly: newTotalHours,
      valid_days_monthly: validDays,
      today_minutes: Math.round(todaySeconds / 60),
    });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

export default router;