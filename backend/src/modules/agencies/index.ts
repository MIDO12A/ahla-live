import { Router, Request, Response } from 'express';

const agenciesRouter = Router();

agenciesRouter.get('/health', (_req: Request, res: Response) => {
  res.json({ module: 'agencies', status: 'operational', timestamp: new Date().toISOString() });
});

export default agenciesRouter;
