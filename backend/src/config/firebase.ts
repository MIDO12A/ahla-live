import { cert, getApps, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';

function initApp(): App {
  const existing = getApps();
  if (existing.length) return existing[0];

  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_B64;
  if (raw) {
    let json;
    const trimmed = raw.trim();
    if (trimmed.startsWith('{')) {
      json = JSON.parse(trimmed);
    } else {
      json = JSON.parse(Buffer.from(trimmed, 'base64').toString('utf8'));
    }
    return initializeApp({ credential: cert(json), projectId: json.project_id });
  }

  // Local dev: relies on GOOGLE_APPLICATION_CREDENTIALS or gcloud ADC.
  // نحدد projectId صراحة حتى يشتغل auth.verifyIdToken (التحقق عبر المفاتيح
  // العامة) حتى لو لم يُضبط service account في البيئة كاملة.
  return initializeApp({ projectId: process.env.FIREBASE_PROJECT_ID || 'ahla-live' });
}

const app = initApp();

export const db = getFirestore(app, 'default');
export const auth = getAuth(app);
export const firebaseWebApiKey = process.env.FIREBASE_WEB_API_KEY || '';
