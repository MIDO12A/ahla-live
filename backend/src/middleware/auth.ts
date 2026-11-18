import { Request, Response, NextFunction } from 'express';
import jwt, { JwtPayload } from 'jsonwebtoken';
import crypto from 'crypto';
import { config } from '../config';
import { db } from '../config/database';
import { auth } from '../config/firebase';
import { AuthPayload } from '../types';

declare global {
  namespace Express {
    interface Request {
      user?: AuthPayload;
    }
  }
}

// ── تحقق من Firebase ID tokens دون الاعتماد على service account ────────────
// يتحقق من توقيع التوكن عبر المفاتيح العامة الصادرة من Google
// (securetoken@system.gserviceaccount.com). لا يتطلب أي private key،
// وبنفس مستوى أمان firebase-admin.verifyIdToken.
const FIREBASE_PROJECT_ID = (
  process.env.FIREBASE_PROJECT_ID || 'zeroappzero-e1b4a'
).replace(/[^\x20-\x7E]/g, '');
let tokenPublicKeys: Record<string, string> = {};
let keysFetchedAt = 0;

async function getTokenPublicKeys(): Promise<Record<string, string>> {
  if (Object.keys(tokenPublicKeys).length && Date.now() - keysFetchedAt < 3600_000) {
    return tokenPublicKeys;
  }
  try {
    const res = await fetch(
      'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com',
      { headers: { 'Cache-Control': 'max-age=3600' } }
    );
    if (!res.ok) return tokenPublicKeys;
    const data = (await res.json()) as Record<string, string>;
    tokenPublicKeys = data;
    keysFetchedAt = Date.now();
  } catch (e) {
    console.error('[auth] fetch token keys failed:', (e as Error).message);
  }
  return tokenPublicKeys;
}

async function verifyFirebaseTokenWithPublicKey(token: string): Promise<AuthPayload | null> {
  try {
    if (token.split('.').length !== 3) return null;
    const header = JSON.parse(Buffer.from(token.split('.')[0], 'base64url').toString('utf8')) as { kid?: string };
    if (!header.kid) return null;
    const keys = await getTokenPublicKeys();
    const cert = keys[header.kid];
    if (!cert) return null;
    // X509 certificates must be converted to a raw public key object
    // before being passed to jsonwebtoken (it rejects certificate PEMs).
    const publicKey = crypto.createPublicKey(cert);
    const payload = jwt.verify(token, publicKey, {
      algorithms: ['RS256'],
      audience: FIREBASE_PROJECT_ID,
      issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
    }) as JwtPayload;
    if (!payload?.sub) return null;
    return { uid: payload.sub, role: 'user' };
  } catch (e) {
    console.error('[auth] public-key verify failed:', (e as Error).message);
    return null;
  }
}

async function verifyFirebaseIdToken(token: string): Promise<AuthPayload | null> {
  try {
    const decoded = await auth.verifyIdToken(token);
    if (!decoded?.uid) return null;
    return { uid: decoded.uid, role: 'user' };
  } catch (e) {
    // سجل السبب الدقيق (خطأ في متغير FIREBASE_SERVICE_ACCOUNT_B64،
    // تطابق المشروع، أو توكن منتهٍ) ليتضح في سجلات Vercel/Functions.
    console.error('[auth] verifyIdToken failed:', (e as Error).message);
    // fallback: التحقق عبر المفاتيح العامة (بدون service account)
    return verifyFirebaseTokenWithPublicKey(token);
  }
}

async function verifyCustomToken(token: string): Promise<AuthPayload | null> {
  try {
    const payload = jwt.verify(token, config.jwt.secret) as AuthPayload;
    return payload;
  } catch {
    return null;
  }
}

async function resolveRole(uid: string): Promise<AuthPayload['role']> {
  try {
    // Admins of the dashboard live in admin_users; app-level admins in users.role.
    const adminDoc = await db.collection('admin_users').doc(uid).get();
    if (adminDoc.exists) return 'admin';
    const userDoc = await db.collection('users').doc(uid).get();
    const role = (userDoc.data()?.role as string) || 'user';
    return (role === 'admin' || role === 'agent' ? role : 'user') as AuthPayload['role'];
  } catch {
    return 'user';
  }
}

export async function authenticate(req: Request, res: Response, next: NextFunction): Promise<void> {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Unauthorized: No token provided' });
    return;
  }

  const token = authHeader.slice(7);

  let payload = await verifyCustomToken(token);
  if (!payload) {
    payload = await verifyFirebaseIdToken(token);
  }

  if (!payload) {
    res.status(401).json({ error: 'Unauthorized: Invalid token' });
    return;
  }

  req.user = { ...payload, role: await resolveRole(payload.uid) };
  next();
}

export async function optionalAuth(req: Request, _res: Response, next: NextFunction): Promise<void> {
  const authHeader = req.headers.authorization;
  if (authHeader?.startsWith('Bearer ')) {
    const token = authHeader.slice(7);
    let payload = await verifyCustomToken(token);
    if (!payload) {
      payload = await verifyFirebaseIdToken(token);
    }
    if (payload) {
      req.user = { ...payload, role: await resolveRole(payload.uid) };
    }
  }
  next();
}

export function requireRole(...roles: string[]) {
  return (req: Request, res: Response, next: NextFunction): void => {
    if (!req.user) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }
    if (!roles.includes(req.user.role)) {
      res.status(403).json({ error: 'Forbidden: Insufficient permissions' });
      return;
    }
    next();
  };
}

export function generateToken(payload: AuthPayload): string {
  return jwt.sign(payload, config.jwt.secret, { expiresIn: config.jwt.expiresIn as any });
}
