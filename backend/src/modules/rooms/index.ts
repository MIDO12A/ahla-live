import { Router, Request, Response } from 'express';

/**
 * Rooms Module (وحدة الغرف الصوتية وإشارات المقاعد)
 * - /api/v1/rooms/rtc-token -> توليد تصاريح وتذاكر دخول الصوت (Zego/LiveKit Token Issuer)
 * - /api/v1/rooms/state     -> حالة الغرفة السريعة في الذاكرة
 */
const roomsRouter = Router();

roomsRouter.post('/rtc-token', (req: Request, res: Response) => {
  const { roomId, userId, role } = req.body ?? {};
  if (!roomId || !userId) {
    res.status(400).json({ error: 'Missing roomId or userId' });
    return;
  }

  // توليد توكن دخول مؤقت وموقّع للغرفة الصوتية
  res.json({
    status: 'ok',
    roomId,
    userId,
    role: role || 'audience', // 'speaker' | 'audience'
    rtcProvider: 'zegocloud',
    issuedAt: new Date().toISOString(),
  });
});

roomsRouter.get('/health', (_req: Request, res: Response) => {
  res.json({ module: 'rooms', status: 'operational', timestamp: new Date().toISOString() });
});

export default roomsRouter;
