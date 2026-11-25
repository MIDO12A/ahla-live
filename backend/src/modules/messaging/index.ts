import { Router, Request, Response } from 'express';

const messagingRouter = Router();

messagingRouter.get('/health', (_req: Request, res: Response) => {
  res.json({ module: 'messaging', status: 'operational', timestamp: new Date().toISOString() });
});

export default messagingRouter;
