import app from './app';
import { config } from './config';

// On Vercel (serverless) the app is exported via api/index.ts — no listen, no cron.
if (!process.env.VERCEL) {
  app.listen(config.port, () => {
    console.log(`🚀 Zero Backend API running on port ${config.port}`);
    console.log(`📦 Environment: ${config.nodeEnv}`);
  });
}

export default app;
