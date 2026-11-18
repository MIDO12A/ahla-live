import { Router, Request, Response } from 'express';

const router = Router();

// ✅ خطط الشحن — نفس قائمة rechargeService.RECHARGE_PLANS
//    (نُقلت هنا مباشرة لأن rechargeService كان يعتمد على Firestore
//    الذي لم يعد مستخدَماً في هذا الباك إند — كل بيانات التطبيق
//    على Supabase).
const RECHARGE_PLANS = [
  { id: 1, name: '50 Diamonds', price: 1, diamonds: 50, bonus_diamonds: 0, popular: false },
  { id: 2, name: '200 Diamonds', price: 2, diamonds: 200, bonus_diamonds: 10, popular: false },
  { id: 3, name: '500 Diamonds', price: 5, diamonds: 500, bonus_diamonds: 25, popular: false },
  { id: 4, name: '1,200 Diamonds', price: 10, diamonds: 1200, bonus_diamonds: 50, popular: true },
  { id: 5, name: '2,500 Diamonds', price: 20, diamonds: 2500, bonus_diamonds: 150, popular: false },
  { id: 6, name: '6,000 Diamonds', price: 50, diamonds: 6000, bonus_diamonds: 400, popular: false },
  { id: 7, name: '15,000 Diamonds', price: 100, diamonds: 15000, bonus_diamonds: 1500, popular: true },
  { id: 8, name: '40,000 Diamonds', price: 250, diamonds: 40000, bonus_diamonds: 5000, popular: false },
  { id: 9, name: '100,000 Diamonds', price: 500, diamonds: 100000, bonus_diamonds: 20000, popular: false },
  { id: 10, name: '250,000 Diamonds', price: 1000, diamonds: 250000, bonus_diamonds: 75000, popular: true },
];

router.get('/plans', (_req: Request, res: Response) => {
  res.json({ plans: RECHARGE_PLANS });
});

export default router;
