import express from 'express';
import cors from 'cors';
import vipRoutes from './routes/vip';
import rechargeRoutes from './routes/recharge';
import gamesRoutes from './routes/games';


import openapiDoc from './openapi.json';

const app = express();

app.use(cors());

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

// ✅ الباك إند صار Supabase-only — لا Firebase.
//    كل بيانات التطبيق على Supabase؛ هذه الباك إند تخدم فقط:
//    - /api/v1/games      → بروتوكول StyeParty (رصيد + نتائج)
//    - /api/v1/vip        → بيانات VIP (يقرأ من Supabase)
//    - /api/v1/recharge   → خطط الشحن static
//    باقي المسارات القديمة (auth/users/gifts/lucky/...) كانت
//    تعتمد على Firestore وأُزيلت — التطبيق لا يستدعيها أصلاً.
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
