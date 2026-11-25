import { Router, Request, Response } from 'express';

/**
 * Auth & Users Module (وحدة المصادقة والمستخدمين)
 * - فحص التوكنات وتراخيص الجلسات
 */
const authRouter = Router();

authRouter.get('/verify-session', (req: Request, res: Response) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) {
    res.status(401).json({ valid: false, error: 'No authorization header' });
    return;
  }
  res.json({ valid: true, timestamp: new Date().toISOString() });
});

authRouter.get('/health', (_req: Request, res: Response) => {
  res.json({ module: 'auth', status: 'operational', timestamp: new Date().toISOString() });
});

export default authRouter;
