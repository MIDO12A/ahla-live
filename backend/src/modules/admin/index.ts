import { Router, Request, Response } from 'express';

const adminRouter = Router();

adminRouter.get('/health', (_req: Request, res: Response) => {
  res.json({ module: 'admin', status: 'operational', timestamp: new Date().toISOString() });
});

export default adminRouter;
