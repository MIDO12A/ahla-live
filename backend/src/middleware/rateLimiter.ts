import { Request, Response, NextFunction } from 'express';

interface RateLimitRecord {
  count: number;
  resetAt: number;
}

/**
 * High-Performance In-Memory Rate Limiter Middleware
 * يحمي السيرفر من هجمات الإغراق (DoS / Spam) دون الحاجة لمكتبات خارجية ثقيلة
 * 
 * @param windowMs نافذة الوقت بالميلي ثانية (مثلاً 1000 = ثانية واحدة)
 * @param maxRequests أقصى عدد طلبات مسموح به خلال النافذة
 * @param message الرسالة المعادة عند تجاوز الحد
 */
export function createRateLimiter({
  windowMs = 1000,
  maxRequests = 5,
  message = 'Too many requests, please slow down.',
}: {
  windowMs?: number;
  maxRequests?: number;
  message?: string;
}) {
  const clients = new Map<string, RateLimitRecord>();

  // تنظيف دوري للذاكرة كل دقيقة لمنع تراكم المفاتيح
  setInterval(() => {
    const now = Date.now();
    for (const [key, record] of clients.entries()) {
      if (now > record.resetAt) {
        clients.delete(key);
      }
    }
  }, 60000);

  return (req: Request, res: Response, next: NextFunction) => {
    const clientIp =
      (req.headers['x-forwarded-for'] as string)?.split(',')[0].trim() ||
      req.socket.remoteAddress ||
      'unknown_client';

    const now = Date.now();
    const existing = clients.get(clientIp);

    if (!existing || now > existing.resetAt) {
      clients.set(clientIp, {
        count: 1,
        resetAt: now + windowMs,
      });
      return next();
    }

    if (existing.count >= maxRequests) {
      res.status(429).json({
        error: 'rate_limit_exceeded',
        message,
        retryAfterMs: Math.max(0, existing.resetAt - now),
      });
      return;
    }

    existing.count++;
    next();
  };
}
