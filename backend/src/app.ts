import express from 'express';
import cors from 'cors';
import vipRoutes from './routes/vip';
import rechargeRoutes from './routes/recharge';
import gamesRoutes from './routes/games';


import openapiDoc from './openapi.json';
import { createRateLimiter } from './middleware/rateLimiter';

const app = express();

app.use(cors());

// 🛡️ حماية السيرفر من الضغط والسبام (Rate Limiting: 25 طلب في الثانية لكل IP)
app.use(createRateLimiter({ windowMs: 1000, maxRequests: 25 }));

// ⚠️ على Vercel قد يسبق الـ runtime ويحوّل JSON إلى req.body object ويستهلك
//    الـ stream؛ استدعاء express.json() وقتها يرمي 500 قبل أي handler.
//    نستدعيه فقط لو الـ body لسه مش متحول.
const jsonParser = express.json();
app.use((req, res, next) => {
  const alreadyParsed =
    req.body != null && typeof req.body === 'object' && !Buffer.isBuffer(req.body);
  if (alreadyParsed) return next();
  jsonParser(req, res, next);
});
// بروتوكول StyeParty/game providers يرسل form-urlencoded غالباً
app.use(express.urlencoded({ extended: true }));

app.get('/', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'Ahla Live API Backend',
    version: '1.0.0',
    health: '/health',
    docs: '/docs',
    timestamp: new Date().toISOString(),
  });
});

app.get(['/health', '/api/health', '/api/v1/health'], (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Serve OpenAPI Specification JSON for Apidog/Swagger Syncing
app.get('/swagger.json', (_req, res) => {
  res.json(openapiDoc);
});

// Serve interactive Swagger UI documentation using CDN
app.get('/docs', (_req, res) => {
  res.send(`
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Zero Backend API Docs</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js" crossorigin></script>
  <script>
    window.onload = () => {
      window.ui = SwaggerUIBundle({
        url: '/swagger.json',
        dom_id: '#swagger-ui',
      });
    };
  </script>
</body>
</html>
  `);
});

import authRouter from './modules/auth';
import roomsRouter from './modules/rooms';
import economyRouter from './modules/economy';
import messagingRouter from './modules/messaging';
import agenciesRouter from './modules/agencies';
import adminRouter from './modules/admin';

// ═══════════════════════════════════════════════════════
// 6 MODULAR ARCHITECTURE MODULES
// ═══════════════════════════════════════════════════════
app.use('/api/v1/auth', authRouter);
app.use('/api/v1/rooms', roomsRouter);
app.use('/api/v1/economy', economyRouter);
app.use('/api/v1/messaging', messagingRouter);
app.use('/api/v1/agencies', agenciesRouter);
app.use('/api/v1/admin', adminRouter);

// المسارات المتوافقة رجعياً (Backward Compatibility)
app.use('/api/v1/vip', vipRoutes);
app.use('/api/v1/recharge', rechargeRoutes);
app.use('/api/v1/games', gamesRoutes);


app.use((_req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

app.use((err: any, _req: any, res: any, _next: any) => {
  // أخطاء قراءة الـ body نرد عليها بصيغة StyeParty بدل 500 عشان الشركة تشوف السبب
  if (err && (err.type === 'entity.parse.failed' || err instanceof SyntaxError)) {
    res.status(200).json({
      errorCode: 10001,
      errorMsg: 'Invalid request body',
      code: 10001,
      msg: 'Invalid request body',
      data: [],
    });
    return;
  }
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

export default app;
