import express from 'express';
import cors from 'cors';
import authRoutes from './routes/auth';
import userRoutes from './routes/users';
import levelRoutes from './routes/levels';
import vipRoutes from './routes/vip';
import rechargeRoutes from './routes/recharge';
import agencyRoutes from './routes/agencies';
import rankingRoutes from './routes/rankings';
import cpRewardRoutes from './routes/cpRewards';
import luckyRoutes from './routes/lucky';
import giftsRoutes from './routes/gifts';
import hostTargetsRoutes from './routes/hostTargets';
import eventsRoutes from './routes/events';


import openapiDoc from './openapi.json';

const app = express();

app.use(cors());
app.use(express.json());

app.get('/health', (_req, res) => {
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

app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/users', userRoutes);
app.use('/api/v1/levels', levelRoutes);
app.use('/api/v1/vip', vipRoutes);
app.use('/api/v1/recharge', rechargeRoutes);
app.use('/api/v1/agencies', agencyRoutes);
app.use('/api/v1/rankings', rankingRoutes);
app.use('/api/v1/cp-rewards', cpRewardRoutes);
app.use('/api/v1/lucky', luckyRoutes);
app.use('/api/v1/gifts', giftsRoutes);
app.use('/api/v1/host-targets', hostTargetsRoutes);
app.use('/api/v1/events', eventsRoutes);


app.use((_req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

app.use((err: any, _req: any, res: any, _next: any) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

export default app;
