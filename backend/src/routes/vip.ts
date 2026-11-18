import { Router, Request, Response } from 'express';
import { getVipTiers, getVipTier, calculateVipLevel } from '../services/vipService';

const router = Router();

const SUPABASE_URL = 'https://pxyqgeitjdsilgfftnyd.supabase.co';
const SUPABASE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY ||
  'sb_publishable_q1Vtqddl7IZazMfLLbYuAw_Qi6NMFrv';

router.get('/tiers', (_req: Request, res: Response) => {
  res.json({ tiers: getVipTiers() });
});

// GET /api/v1/vip/:uid — بيانات VIP من Supabase (بدون Firebase)
router.get('/:uid', async (req: Request, res: Response) => {
  try {
    const { uid } = req.params;
    const url =
      `${SUPABASE_URL}/rest/v1/users?or=(uid.eq.${encodeURIComponent(uid)},id.eq.${encodeURIComponent(uid)})` +
      `&select=uid,recharge_exp,recharge_level&limit=1`;
    const sb = await fetch(url, {
      headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` },
    });
    const rows = (await sb.json()) as any[];
    const user = Array.isArray(rows) && rows.length > 0 ? rows[0] : null;
    if (!user) {
      res.status(404).json({ error: 'User not found' });
      return;
    }

    const rechargeExp = Number(user.recharge_exp || user.recharge_exp === 0 ? user.recharge_exp : 0) || 0;
    const tier = Number(user.recharge_level || calculateVipLevel(rechargeExp) || 0);
    const tierInfo = getVipTier(tier);
    const nextTierInfo = tier < 15 ? getVipTier(tier + 1) : null;

    res.json({
      current_tier: tier,
      tier_info: tierInfo || null,
      next_tier: tier < 15 ? tier + 1 : null,
      next_tier_info: nextTierInfo || null,
      recharge_for_next: nextTierInfo ? nextTierInfo.monthly_price - rechargeExp : 0,
    });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

export default router;
