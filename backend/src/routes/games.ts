import { Router, Request, Response } from 'express';
import crypto from 'crypto';
import { config } from '../config';

const router = Router();

// ألعاب الكازينو (Alfa/UTD) — الجداول والـ RPCs تعيش في Supabase وليس Firestore.
// نستدعي Supabase REST مباشرة بنفس المفتاح العام الذي يستخدمه التطبيق.
const SUPABASE_URL =
  process.env.SUPABASE_URL || 'https://pxyqgeitjdsilgfftnyd.supabase.co';
const SUPABASE_KEY =
  process.env.SUPABASE_SERVICE_KEY ||
  process.env.SUPABASE_ANON_KEY ||
  'sb_publishable_q1Vtqddl7IZazMfLLbYuAw_Qi6NMFrv';

const headers = {
  apikey: SUPABASE_KEY,
  Authorization: `Bearer ${SUPABASE_KEY}`,
  'Content-Type': 'application/json',
};

async function sbGet(path: string): Promise<any> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers });
  if (!res.ok) throw new Error(`Supabase GET ${path} -> ${res.status}`);
  return res.json();
}

// ─── Idempotency orders — جدول game_provider_orders في Supabase ────
// نفس orderId ما يتكرر: نفحص قبل التسوية ونسجل بعدها.
async function sbOrderExists(orderId: string): Promise<boolean> {
  const rows = await sbGet(
    `game_provider_orders?order_id=eq.${encodeURIComponent(orderId)}&select=order_id&limit=1`
  );
  return Array.isArray(rows) && rows.length > 0;
}

async function sbOrderSave(row: Record<string, any>): Promise<void> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/game_provider_orders`, {
    method: 'POST',
    headers: { ...headers, Prefer: 'resolution=ignore-duplicates' },
    body: JSON.stringify(row),
  });
  if (!res.ok) {
    console.error('[games] order save failed:', res.status, await res.text());
  }
}

// ─── GET /api/v1/games/config?game_id=ludo ─────────────────────────────
// إعدادات اللعبة: win_rate, is_active, jackpot... من game_jackpot_pool
router.get('/config', async (req: Request, res: Response) => {
  try {
    const gameId = String(req.query.game_id || '').trim();
    if (!gameId) {
      res.status(400).json({ error: 'game_id is required' });
      return;
    }
    const rows = await sbGet(
      `game_jackpot_pool?id=eq.${encodeURIComponent(gameId)}&select=*`
    );
    res.json({ game_id: gameId, config: Array.isArray(rows) ? rows[0] ?? null : null });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// ─── GET /api/v1/games/leaderboard?game_id=ludo&limit=10 ───────────────
// ترتيب المتصدرين — تجميع win_amount لكل مستخدم من game_bet_records
router.get('/leaderboard', async (req: Request, res: Response) => {
  try {
    const gameId = String(req.query.game_id || 'lucky777').trim();
    const limit = Math.min(parseInt(String(req.query.limit || '10'), 10) || 10, 100);

    const rows = await sbGet(
      `game_bet_records?game_id=eq.${encodeURIComponent(gameId)}` +
        `&select=user_id,user_name,win_amount&order=created_at.desc&limit=2000`
    );

    const totals = new Map<string, { user_id: string; user_name: string; total: number; avatar: string }>();
    for (const row of Array.isArray(rows) ? rows : []) {
      const uid = String(row.user_id || '');
      if (!uid) continue;
      const win = Number(row.win_amount) || 0;
      const entry = totals.get(uid) || {
        user_id: uid,
        user_name: String(row.user_name || 'Player'),
        total: 0,
        avatar: '',
      };
      entry.total += win;
      totals.set(uid, entry);
    }

    const rankings = [...totals.values()]
      .sort((a, b) => b.total - a.total)
      .slice(0, limit);

    // صور اللاعبين مطلوبة لتتمرير الترتيب للعبة عبر window.setLeaderboard.
    try {
      const uids = rankings.map((r) => r.user_id).filter(Boolean);
      if (uids.length) {
        const conds = uids.map((u) => `uid.eq.${encodeURIComponent(u)}`).join(',');
        const users = await sbGet(
          `users?or=(${conds})&select=uid,id,photo_url&limit=${uids.length}`
        );
        const avatars = new Map<string, string>();
        for (const u of Array.isArray(users) ? users : []) {
          avatars.set(String(u.uid || u.id), String(u.photo_url || ''));
        }
        for (const r of rankings) r.avatar = avatars.get(r.user_id) || '';
      }
    } catch (_) {
      for (const r of rankings) r.avatar = '';
    }

    res.json({ game_id: gameId, rankings });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// ─── GET /api/v1/games/records?game_id=ludo&user_id=xxx&limit=30 ───────
// آخر نتائج لعبة — سجلات اللاعب أو عامة
router.get('/records', async (req: Request, res: Response) => {
  try {
    const gameId = String(req.query.game_id || 'lucky777').trim();
    const userId = String(req.query.user_id || '').trim();
    const limit = Math.min(parseInt(String(req.query.limit || '30'), 10) || 30, 200);

    let path =
      `game_bet_records?game_id=eq.${encodeURIComponent(gameId)}` +
      `&select=game_id,user_id,user_name,bet_amount,win_amount,net_result,is_win,created_at` +
      `&order=created_at.desc&limit=${limit}`;
    if (userId) path += `&user_id=eq.${encodeURIComponent(userId)}`;

    const rows = await sbGet(path);
    res.json({ game_id: gameId, records: rows });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// ─── POST /api/v1/games/callback ────────────────────────────────────────
// تسوية جولة لعبة (رهان/فوز) — يحدّث رصيد المستخدم + سجل النتيجة +
// رصيد الـ pool ذرّياً عبر RPC مخصوص في Supabase.
// محمي بسر مشترك في الهيدر: x-game-secret — يُمرَّر لـ Supabase كـ p_secret.
// السر لازم يطابق app_config.game_provider_secret في قاعدة البيانات.
router.post('/callback', async (req: Request, res: Response) => {
  try {
    const secret = String(req.headers['x-game-secret'] || '');
    const expected = (
      process.env.GAME_API_SECRET || config.payment.webhookSecret || ''
    ).trim();
    if (!expected || secret !== expected) {
      res.status(401).json({ error: 'Invalid game secret' });
      return;
    }

    const { game_id, user_id, user_name, bet_amount, win_amount } = req.body || {};
    if (!game_id || user_id == null) {
      res.status(400).json({ error: 'game_id and user_id are required' });
      return;
    }

    const res2 = await fetch(
      `${SUPABASE_URL}/rest/v1/rpc/game_provider_settle_round`,
      {
        method: 'POST',
        headers,
        body: JSON.stringify({
          p_secret: secret,
          p_user_id: String(user_id),
          p_user_name: String(user_name || 'Player'),
          p_game_id: String(game_id),
          p_bet_amount: Math.max(0, Math.round(Number(bet_amount) || 0)),
          p_win_amount: Math.max(0, Math.round(Number(win_amount) || 0)),
        }),
      }
    );

    const text = await res2.text();
    if (!res2.ok) {
      res.status(502).json({ error: 'Settlement failed', detail: text });
      return;
    }

    let result: any = null;
    try { result = JSON.parse(text); } catch (_) {}

    if (result && result.status && result.status !== 'ok') {
      const code = result.status === 'unauthorized' ? 401
        : result.status === 'user_not_found' ? 404
        : result.status === 'insufficient_coins' ? 409
        : 400;
      res.status(code).json(result);
      return;
    }

    res.json({ ok: true, ...result });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// =============================================================================
// بروتوكول StyeParty Callback API — الشركة تنادي هذه المسارات على سيرفرنا
// Base: /api/v1/games  |  APP_KEY: alfa_key_app_ahal_377
// التوقيع MD5 (concat بدون فواصل):
//   get-user-info : md5(gameId + uid + token + roomId + APP_KEY)
//   change-balance: md5(orderId + gameId + roundId + uid + coin + type
//                        + rewardType + token + winId + roomId + APP_KEY)
//   make-up-orders: md5(orderId + gameId + roundId + uid + coin
//                        + rewardType + winId + roomId + APP_KEY)
// =============================================================================
const GAME_APP_KEY = process.env.GAME_APP_KEY || 'alfa_key_app_ahal_377';
const GAME_PROVIDER_SECRET = (
  process.env.GAME_API_SECRET || config.payment.webhookSecret || ''
).trim();

// ✅ لو السر غير مضبوط، كل عمليات التسوية سترجع unauthorized من Supabase.
//    نطبع تحذير صريح عند بدء السيرفر بدل ما نكتشف المشكلة بعد فوات الأوان.
if (!GAME_PROVIDER_SECRET) {
  console.error(
    '[games] ⚠️ GAME_API_SECRET is empty — StyeParty settlements WILL FAIL. ' +
    'Set GAME_API_SECRET on Vercel to the value of app_config.game_provider_secret.'
  );
}

function md5(s: string): string {
  return crypto.createHash('md5').update(s, 'utf8').digest('hex');
}

/** يدمج body (json أو form) + query في كائن واحد — كل القيم strings */
function params(req: Request): Record<string, string> {
  const out: Record<string, string> = {};
  const merge = (src: any) => {
    if (!src || typeof src !== 'object') return;
    for (const [k, v] of Object.entries(src)) {
      if (v == null) continue;
      out[k] = String(v);
    }
  };
  merge(req.query);
  merge(req.body);
  return out;
}

/** يقبل sign إما في حقل sign أو query — مقارنة نصية بسيطة */
function signOk(p: Record<string, string>, expected: string): boolean {
  const got = (p.sign || p.sign_str || '').toLowerCase();
  return got !== '' && got === expected.toLowerCase();
}

// 'debit'  = حدث رهان: يُخصم من رصيد Supabase (اللعبة خصمته من رصيدها
//            الداخلي أيضاً — الرهان الحقيقي لازم ينعكس على المحفظة).
// 'credit' = حدث فوز: يُضاف للرصيد.
type Direction = 'credit' | 'debit' | null;

/**
 * اتجاه التسوية — أخطر جزء في البروتوكول.
 *
 * قاعدة المالك (2026-11-21): الرهان يُخصم من رصيد التطبيق فعلياً —
 *   المستخدم يراهن 1000 على كل خانة (4 خانات = 4000 خصم)، والفوز
 *   يُضاف مرة واحدة فقط للخانة الفائزة (مثال: ×5 على 1000 = +5000).
 *   الصافي لمثال المستخدم = +1000.
 *
 * الترتيب: diff/change الموقّع ← إشارة coin السالبة ← type الرقمي
 *          ← reason صريح ← كلمات type/rewardType ← null (نرفض التسوية).
 * القاعدة الذهبية: لو مش متأكدين، ما نكتبش رصيد.
 */
function resolveDirection(p: Record<string, string>): Direction {
  const get = (k: string) => (p[k] == null ? '' : String(p[k]).trim());
  const reason = get('reason').toLowerCase();
  const type = get('type').toLowerCase();
  const rewardType = get('rewardType').toLowerCase();
  const all = `${reason} ${type} ${rewardType}`.toLowerCase();

  const isDebitWord = /\b(bet|bets|betting|debit|lose|lost|loss|wager|stake|deduct)\b/.test(all);
  const isCreditWord = /\b(win|wins|winner|reward|credit|prize|bonus|gain)\b/.test(all);

  // 1) الفرق الموقّع — أقوى إشارة، لأن reason ممكن يكون ثابت لـ كل أحداث اللعبة.
  //    نستخدم diff/change فقط، مش coin (ده رصيد مطلق بعد العملية).
  for (const key of ['diff', 'change']) {
    const raw = get(key);
    if (!raw) continue;
    const n = Number(raw);
    if (Number.isFinite(n) && n !== 0) return n < 0 ? 'debit' : 'credit';
  }

  // 2) بعض المزوّدين بيبعتوا coin سالب للخصم (قبل ما ناخد abs)
  if (/^-/.test(get('coin'))) return 'debit';

  // 3) نوع رقمي — بروتوكول StyeParty: type="1" رهان (خصم)، type="2" فوز (إضافة)
  if (type === '1') return 'debit';
  if (type === '2') return 'credit';

  // 4) reason صريح (المزوّد بيبعت "bet" / "win" فعلياً)
  if (reason && isDebitWord !== isCreditWord) {
    return isDebitWord ? 'debit' : 'credit';
  }

  // 5) كلمات type / rewardType
  if (isDebitWord !== isCreditWord) return isDebitWord ? 'debit' : 'credit';

  // 6) غامض — نرفض بدل ما نكتب رصيد غلط
  console.error('[games] ambiguous settlement direction — REFUSING:', {
    orderId: get('orderId'),
    type: get('type'),
    rewardType: get('rewardType'),
    reason: get('reason'),
    diff: get('diff'),
    coin: get('coin'),
    uid: get('uid'),
  });
  return null;
}

// ─── صيغة الرد مطابقة لـ api.styeparty.xyz/api/leader-cc-game ────
//    نجاح: {"errorCode":0,"errorMsg":"success","data":{...}}
//    فشل  : {"errorCode":10004,"errorMsg":"Verify signature fail","data":[]}
//    وHTTP دائماً 200 — خطأ الـ signature عندهم يرجع 200 أيضاً.
//    نرجع الحقلين معاً (errorCode + code/msg) احتياطاً لأي parser.
function ok(data: any) {
  return { errorCode: 0, errorMsg: 'success', code: 200, msg: 'success', data };
}
function fail(errorCode: number, msg: string) {
  return { errorCode, errorMsg: msg, code: errorCode, msg, data: [] };
}

async function handleGetUserInfo(req: Request, res: Response) {
  try {
    const p = params(req);
    const { gameId, uid, token, roomId } = p;
    if (!gameId || !uid) {
      res.status(200).json(fail(10001, 'gameId and uid are required'));
      return;
    }
    const expected = md5(`${gameId}${uid}${token || ''}${roomId || ''}${GAME_APP_KEY}`);
    if (!signOk(p, expected)) {
      res.status(200).json(fail(10004, 'Verify signature fail'));
      return;
    }

    const rows = await sbGet(
      `users?or=(uid.eq.${encodeURIComponent(uid)},id.eq.${encodeURIComponent(uid)},custom_id.eq.${encodeURIComponent(uid)})` +
        `&select=uid,id,name,coins,diamonds,photo_url,recharge_level&limit=1`
    );
    const u = Array.isArray(rows) ? rows[0] : null;
    if (!u) {
      res.status(200).json(fail(10002, 'user not found'));
      return;
    }

    res.json(ok({
      uid: u.uid || u.id,
      userId: u.uid || u.id,
      nickname: u.name || 'Player',
      name: u.name || 'Player',
      coins: Number(u.coins) || 0,
      coin: Number(u.coins) || 0,
      balance: Number(u.coins) || 0,
      diamonds: Number(u.diamonds) || 0,
      vipLevel: Number(u.recharge_level) || 0,
      water: 0,
      avatar: u.photo_url || '',
    }));
  } catch (err: any) {
    res.status(200).json(fail(10099, err.message));
  }
}

async function handleChangeBalance(req: Request, res: Response) {
  try {
    const p = params(req);
    const { orderId, gameId, roundId, uid, coin, type, rewardType, token, winId, roomId } = p;
    if (!orderId || !gameId || !uid || coin == null) {
      res.status(200).json(fail(10001, 'orderId, gameId, uid and coin are required'));
      return;
    }
    const expected = md5(
      `${orderId}${gameId}${roundId || ''}${uid}${coin}${type || ''}` +
      `${rewardType || ''}${token || ''}${winId || ''}${roomId || ''}${GAME_APP_KEY}`
    );
    if (!signOk(p, expected)) {
      res.status(200).json(fail(10004, 'Verify signature fail'));
      return;
    }

    // Idempotency: نفس orderId ما يتكرر
    if (await sbOrderExists(orderId)) {
      res.json(ok({ orderId, duplicate: true }));
      return;
    }

    const amount = Math.abs(Math.round(Number(coin) || 0));
    if (amount <= 0) {
      res.status(200).json(fail(10001, 'invalid coin amount'));
      return;
    }

    // الاتجاه من reason/diff/type — لو مش واضح نرفض بدل ما نكتب رصيد غلط.
    const direction = resolveDirection(p);
    if (!direction) {
      res.status(200).json(fail(10007, 'ambiguous settlement direction'));
      return;
    }

    console.log('[games] change-balance direction:', {
      orderId, uid, gameId, coin, type, rewardType,
      reason: p.reason, diff: p.diff, change: p.change, direction,
    });

    // مطابقة المستخدم: إذا أرسلت اللعبة المعرف الرقمي custom_id نحله إلى uid الحقيقي في Supabase
    const rows = await sbGet(
      `users?or=(uid.eq.${encodeURIComponent(uid)},id.eq.${encodeURIComponent(uid)},custom_id.eq.${encodeURIComponent(uid)})` +
        `&select=uid,id,name,coins&limit=1`
    );
    const targetUser = Array.isArray(rows) ? rows[0] : null;
    const resolvedUserId = targetUser ? (targetUser.uid || targetUser.id) : uid;

    let result: any;
    if (direction === 'debit') {
      result = await settleRound({
        userId: resolvedUserId,
        userName: p.userName || p.nickname || targetUser?.name || 'Player',
        gameId,
        bet: amount,
        win: 0,
      });
    } else {
      result = await settleRound({
        userId: resolvedUserId,
        userName: p.userName || p.nickname || targetUser?.name || 'Player',
        gameId,
        bet: 0,
        win: amount,
      });
    }

    if (result.status !== 'ok') {
      const ec =
        result.status === 'unauthorized' ? 10006
        : result.status === 'user_not_found' ? 10002
        : result.status === 'insufficient_coins' ? 10003
        : 10005;
      console.error('[games] change-balance settlement failed:', orderId, result.status);
      res.status(200).json(fail(ec, result.status));
      return;
    }

    await sbOrderSave({
      order_id: orderId,
      game_id: gameId,
      round_id: roundId || null,
      uid,
      coin: amount,
      type: type || null,
      reward_type: rewardType || null,
      win_id: winId || null,
      room_id: roomId || null,
      direction,
      result,
    });

    console.log('[games] settled:', orderId, gameId, uid, 'direction=', direction, 'net=', result.net, 'coins=', result.coins);
    res.json(ok({
      orderId,
      net: result.net,
      coins: result.coins,
      coin: result.coins,
      balance: result.coins,
      direction,
    }));
  } catch (err: any) {
    res.status(200).json(fail(10099, err.message));
  }
}

async function handleMakeUpOrders(req: Request, res: Response) {
  try {
    const p = params(req);
    const body: any = req.body && typeof req.body === 'object' ? req.body : {};
    const list: any[] = Array.isArray(body.orders) ? body.orders : [body];

    const results: any[] = [];
    for (const item of list) {
      const q = { ...p, ...item };
      const { orderId, gameId, roundId, uid, coin, rewardType, winId, roomId } = q;
      if (!orderId || !gameId || !uid || coin == null) {
        results.push({ orderId, error: 'missing fields' });
        continue;
      }
      const expected = md5(
        `${orderId}${gameId}${roundId || ''}${uid}${coin}` +
        `${rewardType || ''}${winId || ''}${roomId || ''}${GAME_APP_KEY}`
      );
      if (!signOk(q, expected)) {
        results.push({ orderId, error: 'invalid sign' });
        continue;
      }

      const amount = Math.abs(Math.round(Number(coin) || 0));
      if (await sbOrderExists(orderId)) {
        results.push({ orderId, duplicate: true });
        continue;
      }

      const direction = resolveDirection(q);
      if (!direction) {
        results.push({ orderId, error: 'ambiguous direction', errorCode: 10007 });
        continue;
      }
      console.log('[games] make-up direction:', {
        orderId, uid, gameId, coin, type: q.type, rewardType,
        reason: q.reason, diff: q.diff, change: q.change, direction,
      });
      const uRows = await sbGet(
        `users?or=(uid.eq.${encodeURIComponent(uid)},id.eq.${encodeURIComponent(uid)},custom_id.eq.${encodeURIComponent(uid)})` +
          `&select=uid,id,name,coins&limit=1`
      );
      const muUser = Array.isArray(uRows) ? uRows[0] : null;
      const muResolvedUid = muUser ? (muUser.uid || muUser.id) : uid;

      const result = await settleRound({
        userId: muResolvedUid,
        userName: q.userName || q.nickname || muUser?.name || 'Player',
        gameId,
        bet: direction === 'debit' ? amount : 0,
        win: direction === 'credit' ? amount : 0,
      });
      if (result.status === 'ok') {
        await sbOrderSave({
          order_id: orderId,
          game_id: gameId,
          round_id: roundId || null,
          uid,
          coin: amount,
          reward_type: rewardType || null,
          win_id: winId || null,
          room_id: roomId || null,
          direction,
          makeup: true,
          result,
        });
        results.push({ orderId, ok: true, net: result.net, direction });
      } else {
        console.error('[games] make-up settlement failed:', orderId, result.status);
        results.push({
          orderId,
          error: result.status,
          errorCode: result.status === 'unauthorized' ? 10006 : 10005,
        });
      }
    }

    res.json(ok({ processed: results.length, results }));
  } catch (err: any) {
    res.status(200).json(fail(10099, err.message));
  }
}

// ─── POST /api/v1/games (Dispatcher الرئيسي للمسار المباشر) ───────────────
// إذا قامت شركة الألعاب أو أي عميل بإرسال POST مباشرة إلى Base URL (/api/v1/games)
// يتم فحص المعاملات وتوجيه الطلب تلقائياً للعملية المناسبة بدل إرجاع 404.
router.post('/', async (req: Request, res: Response) => {
  const p = params(req);
  const action = (p.action || p.method || p.act || p.cmd || '').toLowerCase();

  console.log('[games] Root POST /api/v1/games received:', {
    action,
    hasOrderId: !!p.orderId,
    hasCoin: p.coin != null,
    hasUid: !!p.uid,
    hasGameId: !!p.gameId,
  });

  if (action === 'get-user-info' || action === 'getuserinfo' || action === 'userinfo') {
    return handleGetUserInfo(req, res);
  }
  if (action === 'change-balance' || action === 'changebalance' || action === 'balance') {
    return handleChangeBalance(req, res);
  }
  if (action === 'make-up-orders' || action === 'makeuporders') {
    return handleMakeUpOrders(req, res);
  }

  // التعرف التلقائي حسب الحقول
  if (p.orderId && p.coin != null) {
    return handleChangeBalance(req, res);
  }
  if (p.uid && !p.orderId) {
    return handleGetUserInfo(req, res);
  }

  // إذا كانت طلبات تعويض متراكمة في body.orders
  const body: any = req.body && typeof req.body === 'object' ? req.body : {};
  if (Array.isArray(body.orders)) {
    return handleMakeUpOrders(req, res);
  }

  // رد معياري متوافق مع بروتوكول الألعاب بدلاً من 404
  res.json(ok({
    status: 'ok',
    message: 'Ahla Live Games API is ready',
    supportedEndpoints: ['/get-user-info', '/change-balance', '/make-up-orders', '/leaderboard', '/config'],
  }));
});

// ─── POST /api/v1/games/get-user-info ──────────────────────────────────
router.post('/get-user-info', handleGetUserInfo);

// ─── POST /api/v1/games/change-balance ─────────────────────────────────
router.post('/change-balance', handleChangeBalance);

// ─── POST /api/v1/games/make-up-orders ─────────────────────────────────
router.post('/make-up-orders', handleMakeUpOrders);

/** يستدعي RPC التسوية في Supabase — نفس منطق /callback */
async function settleRound(args: {
  userId: string;
  userName: string;
  gameId: string;
  bet: number;
  win: number;
}): Promise<any> {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/rpc/game_provider_settle_round`,
    {
      method: 'POST',
      headers,
      body: JSON.stringify({
        p_secret: GAME_PROVIDER_SECRET,
        p_user_id: args.userId,
        p_user_name: args.userName,
        p_game_id: args.gameId,
        p_bet_amount: args.bet,
        p_win_amount: args.win,
      }),
    }
  );
  const text = await res.text();
  if (!res.ok) throw new Error(`settle_round -> ${res.status} ${text}`);
  try { return JSON.parse(text); } catch { return { status: 'ok' }; }
}

export default router;
