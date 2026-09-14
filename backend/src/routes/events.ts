import { Router, Request, Response } from 'express';
import { FieldValue } from 'firebase-admin/firestore';
import { db } from '../config/database';
import { authenticate } from '../middleware/auth';

const router = Router();

export interface RechargeEventTier {
  id: string;
  target: number;
  name: string;
  name_en: string;
  icon: string;
  svga: string;
  reward_type: 'frame' | 'ride' | 'badge' | 'title';
  duration_days: number;
  bonus_coins: number;
}

export const RECHARGE_EVENT_TIERS: RechargeEventTier[] = [
  {
    id: 'tier_100k',
    target: 100000,
    name: 'تاج النجوم 100K',
    name_en: 'Star Crown 100K',
    icon: 'assets/recharge_event/100K.png',
    svga: 'assets/recharge_event/100k.svga',
    reward_type: 'frame',
    duration_days: 7,
    bonus_coins: 5000,
  },
  {
    id: 'tier_500k',
    target: 500000,
    name: 'شعلة المجد 500K',
    name_en: 'Glory Flame 500K',
    icon: 'assets/recharge_event/500K.png',
    svga: 'assets/recharge_event/500k.svga',
    reward_type: 'frame',
    duration_days: 15,
    bonus_coins: 25000,
  },
  {
    id: 'tier_1m',
    target: 1000000,
    name: 'سفينة الفضاء 1M',
    name_en: 'Space Cruiser 1M',
    icon: 'assets/recharge_event/1M.png',
    svga: 'assets/recharge_event/1M.svga',
    reward_type: 'ride',
    duration_days: 15,
    bonus_coins: 60000,
  },
  {
    id: 'tier_5m',
    target: 5000000,
    name: 'حصان الأساطير 5M',
    name_en: 'Mythic Steed 5M',
    icon: 'assets/recharge_event/5M.png',
    svga: 'assets/recharge_event/5M.svga',
    reward_type: 'ride',
    duration_days: 30,
    bonus_coins: 350000,
  },
  {
    id: 'tier_10m',
    target: 10000000,
    name: 'سيارة البرق 10M',
    name_en: 'Lightning Hypercar 10M',
    icon: 'assets/recharge_event/10M.png',
    svga: 'assets/recharge_event/10M.svga',
    reward_type: 'ride',
    duration_days: 30,
    bonus_coins: 800000,
  },
  {
    id: 'tier_20m',
    target: 20000000,
    name: 'دبابة النصر 20M',
    name_en: 'Victory Tank 20M',
    icon: 'assets/recharge_event/20M.png',
    svga: 'assets/recharge_event/20m.svga',
    reward_type: 'ride',
    duration_days: 30,
    bonus_coins: 1800000,
  },
  {
    id: 'tier_40m',
    target: 40000000,
    name: 'طائرة الشبح 40M',
    name_en: 'Phantom Jet 40M',
    icon: 'assets/recharge_event/40M.png',
    svga: 'assets/recharge_event/40M.svga',
    reward_type: 'ride',
    duration_days: 45,
    bonus_coins: 4000000,
  },
  {
    id: 'tier_60m',
    target: 60000000,
    name: 'تنين الجليد 60M',
    name_en: 'Frost Dragon 60M',
    icon: 'assets/recharge_event/60M.png',
    svga: 'assets/recharge_event/60M.svga',
    reward_type: 'ride',
    duration_days: 45,
    bonus_coins: 6500000,
  },
  {
    id: 'tier_80m',
    target: 80000000,
    name: 'عاصفة الصحراء 80M',
    name_en: 'Desert Storm 80M',
    icon: 'assets/recharge_event/80M.png',
    svga: 'assets/recharge_event/80M.svga',
    reward_type: 'ride',
    duration_days: 60,
    bonus_coins: 9000000,
  },
  {
    id: 'tier_100m',
    target: 100000000,
    name: 'قصر الملوك 100M',
    name_en: 'Royal Castle 100M',
    icon: 'assets/recharge_event/100M.png',
    svga: 'assets/recharge_event/100M.svga',
    reward_type: 'ride',
    duration_days: 60,
    bonus_coins: 12000000,
  },
  {
    id: 'tier_200m',
    target: 200000000,
    name: 'الملاك الذهبي 200M',
    name_en: 'Golden Archangel 200M',
    icon: 'assets/recharge_event/200M.png',
    svga: 'assets/recharge_event/200M.svga',
    reward_type: 'ride',
    duration_days: 90,
    bonus_coins: 25000000,
  },
  {
    id: 'tier_300m',
    target: 300000000,
    name: 'إمبراطور الظلام 300M',
    name_en: 'Shadow Emperor 300M',
    icon: 'assets/recharge_event/300M.png',
    svga: 'assets/recharge_event/300M.svga',
    reward_type: 'ride',
    duration_days: 90,
    bonus_coins: 40000000,
  },
  {
    id: 'tier_400m',
    target: 400000000,
    name: 'سيد الكون 400M',
    name_en: 'Cosmic Overlord 400M',
    icon: 'assets/recharge_event/400M.png',
    svga: 'assets/recharge_event/400M.svga',
    reward_type: 'ride',
    duration_days: 120,
    bonus_coins: 60000000,
  },
  {
    id: 'tier_500m',
    target: 500000000,
    name: 'أسطورة الزمان 500M',
    name_en: 'Eternal Legend 500M',
    icon: 'assets/recharge_event/500M.png',
    svga: 'assets/recharge_event/500M.svga',
    reward_type: 'ride',
    duration_days: 365,
    bonus_coins: 100000000,
  },
];

/**
 * GET /api/v1/events/recharge/active
 * Returns current recharge event metadata and all 14 tiers.
 */
router.get('/recharge/active', async (_req: Request, res: Response) => {
  const now = new Date();
  // Default active event window: current month
  const eventId = `recharge_${now.getFullYear()}_${String(now.getMonth() + 1).padStart(2, '0')}`;
  const endDate = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59);

  res.json({
    event: {
      id: eventId,
      title: 'مهرجان الشحن التراكمي الأسطوري',
      title_en: 'Legendary Cumulative Recharge Carnival',
      description: 'اشحن كوينز وافتح مؤثرات الـ SVGA الحصرية والسيارات الفارهة وبونص كوينز ضخم!',
      banner_url: 'assets/recharge_event/100M.png',
      starts_at: new Date(now.getFullYear(), now.getMonth(), 1).toISOString(),
      ends_at: endDate.toISOString(),
      is_active: true,
      tiers: RECHARGE_EVENT_TIERS,
    },
  });
});

/**
 * GET /api/v1/events/recharge/my-progress
 * Returns user's cumulative recharge progress and claimed tiers.
 */
router.get('/recharge/my-progress', authenticate, async (req: Request, res: Response) => {
  const uid = req.user?.uid;
  if (!uid) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }

  const now = new Date();
  const eventId = `recharge_${now.getFullYear()}_${String(now.getMonth() + 1).padStart(2, '0')}`;

  try {
    const progressDoc = await db.collection('recharge_event_progress').doc(`${eventId}_${uid}`).get();
    const data = progressDoc.exists ? (progressDoc.data() ?? {}) : {};

    const totalRecharged = Math.trunc(Number(data.total_recharged_coins ?? 0));
    const claimedTiers = Array.isArray(data.claimed_tiers) ? data.claimed_tiers : [];

    res.json({
      event_id: eventId,
      user_id: uid,
      total_recharged_coins: totalRecharged,
      claimed_tiers: claimedTiers,
    });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /api/v1/events/recharge/claim
 * Claims a completed tier reward and deposits into user_backpack & wallet.
 */
router.post('/recharge/claim', authenticate, async (req: Request, res: Response) => {
  const uid = req.user?.uid;
  if (!uid) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }

  const { tierId } = req.body ?? {};
  const tier = RECHARGE_EVENT_TIERS.find((t) => t.id === tierId);
  if (!tier) {
    res.status(400).json({ error: 'invalid_tier_id' });
    return;
  }

  const now = new Date();
  const eventId = `recharge_${now.getFullYear()}_${String(now.getMonth() + 1).padStart(2, '0')}`;
  const progressRef = db.collection('recharge_event_progress').doc(`${eventId}_${uid}`);
  const userRef = db.collection('users').doc(uid);
  const backpackRef = db.collection('user_backpack');

  try {
    await db.runTransaction(async (txn) => {
      const pSnap = await txn.get(progressRef);
      const pData = pSnap.exists ? (pSnap.data() ?? {}) : {};

      const totalRecharged = Math.trunc(Number(pData.total_recharged_coins ?? 0));
      const claimedTiers: string[] = Array.isArray(pData.claimed_tiers) ? pData.claimed_tiers : [];

      if (totalRecharged < tier.target) {
        throw new Error('tier_target_not_reached');
      }
      if (claimedTiers.includes(tier.id)) {
        throw new Error('tier_already_claimed');
      }

      // Add to claimed tiers
      claimedTiers.push(tier.id);
      txn.set(
        progressRef,
        {
          event_id: eventId,
          user_id: uid,
          claimed_tiers: claimedTiers,
          updated_at: now.toISOString(),
        },
        { merge: true },
      );

      // Add reward to backpack
      const expiresAt = new Date(now.getTime() + tier.duration_days * 86400000).toISOString();
      const backpackItemDoc = backpackRef.doc();
      txn.set(backpackItemDoc, {
        id: backpackItemDoc.id,
        user_id: uid,
        item_type: tier.reward_type,
        item_id: tier.id,
        name: tier.name,
        name_en: tier.name_en,
        icon_url: tier.icon,
        svga_url: tier.svga,
        expires_at: expiresAt,
        created_at: now.toISOString(),
        is_equipped: true,
      });

      // Award bonus coins if any
      if (tier.bonus_coins > 0) {
        txn.update(userRef, {
          coins: FieldValue.increment(tier.bonus_coins),
        });
      }

      // Send congratulatory private message
      txn.set(db.collection('private_messages').doc(), {
        sender_id: 'system',
        receiver_id: uid,
        text: `🎉 مبروك! لقد استلمت مكافأة حدث الشحن: ${tier.name} + ${tier.bonus_coins.toLocaleString()} كوينز بونص! تفقد حقيبتك الآن لتفعيلها.`,
        type: 'system',
        created_at: now.toISOString(),
        is_read: false,
        conversationId: `system_${uid}`,
      });
    });

    res.json({
      success: true,
      tier_id: tier.id,
      tier_name: tier.name,
      bonus_coins: tier.bonus_coins,
    });
  } catch (err: any) {
    res.status(400).json({ error: err.message || 'claim_failed' });
  }
});

/**
 * GET /api/v1/events/recharge/leaderboard
 * Returns top 20 rechargers in the current active event.
 */
router.get('/recharge/leaderboard', async (_req: Request, res: Response) => {
  const now = new Date();
  const eventId = `recharge_${now.getFullYear()}_${String(now.getMonth() + 1).padStart(2, '0')}`;

  try {
    const snap = await db
      .collection('recharge_event_progress')
      .where('event_id', '==', eventId)
      .orderBy('total_recharged_coins', 'desc')
      .limit(20)
      .get();

    const top = [];
    for (const doc of snap.docs) {
      const data = doc.data();
      const uid = String(data.user_id ?? '');
      const userSnap = await db.collection('users').doc(uid).get();
      const uData = userSnap.exists ? (userSnap.data() ?? {}) : {};
      top.push({
        user_id: uid,
        name: uData.name ?? 'مستخدم',
        photo_url: uData.photo_url ?? uData.photoUrl ?? '',
        total_coins: data.total_recharged_coins ?? 0,
      });
    }

    res.json({ leaderboard: top });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

export default router;
