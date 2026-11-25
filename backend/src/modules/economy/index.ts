import { Router, Request, Response } from 'express';
import gamesRoutes from '../../routes/games';
import vipRoutes from '../../routes/vip';
import rechargeRoutes from '../../routes/recharge';

/**
 * Economy Module (وحدة الاقتصاد والهدايا والألعاب)
 * - /api/v1/economy/games    -> ألعاب StyeParty/H5 وتسوية الأرصدة
 * - /api/v1/economy/vip      -> بيانات مستويات وباقات الـ VIP
 * - /api/v1/economy/recharge -> خطط الشحن والدفع
 */
const economyRouter = Router();

economyRouter.use('/games', gamesRoutes);
economyRouter.use('/vip', vipRoutes);
economyRouter.use('/recharge', rechargeRoutes);

economyRouter.get('/health', (_req: Request, res: Response) => {
  res.json({ module: 'economy', status: 'operational', timestamp: new Date().toISOString() });
});

export default economyRouter;
