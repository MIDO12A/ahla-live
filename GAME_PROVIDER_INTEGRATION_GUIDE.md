# Game Provider Integration & Balance Mismatch Guide
# دليل ربط مزوّد الألعاب وتشخيص عدم تطابق الرصيد

> **Version / الإصدار:** 2026-11-18  
> **Audience / الجمهور:** المطوّر الذي سيستلم ملف الربط (Backend + Flutter + Admin)  
> **Goal / الهدف:** شرح كيف يتدفّق الرصيد بين التطبيق ← مزوّد الألعاب ← الباكند ← Supabase ← لوحة التحكم، ولماذا يظهر رصيد مختلف أحياناً، وكيف نتأكد أن الإصلاح مُطبَّق.  
> **Related files / ملفات مرجعية:** `GAME_CALLBACK_API.md`, `backend/src/routes/games.ts`, `supabase_game_provider_api.sql`, `supabase/migrations/20261118_fix_game_settlement_atomic.sql`, `lib/screens/game/alfa_game_screen.dart`.

---

## 0. Quick summary — الملخص السريع

| | English | العربية |
|---|---|---|
| **Source of truth** | `public.users.coins` in **Supabase Postgres** (project `pxyqgeitjdsilgfftnyd`). App, backend callbacks and dashboard all read/write this same column. | مصدر الحقيقة هو العمود `coins` في جدول `users` داخل **Supabase Postgres** (نفس المشروع). التطبيق والـ callbacks ولوحة التحكم يقرأون ويكتبون نفس العمود. |
| **Bet (`type=1`)** | **NEVER touch Supabase balance.** The game already deducted it inside its own wallet. | **لا يلمّس رصيد Supabase إطلاقاً.** اللعبة خصمته داخل محفظتها قبل callback. |
| **Win (`type=2`)** | **Credit only the win amount.** Always send `p_bet_amount = 0` to the RPC. | **يُضاف مبلغ الفوز فقط.** نرسل دائماً `p_bet_amount = 0` إلى الـ RPC. |
| **Multiplier rule (all games)** | The provider computes `win = bet × multiplier` **inside the game**. Our backend never multiplies — it credits the reported `coin` verbatim. bet `1000` × `x5` ⇒ `coin=5000`; bet `1` × `x5` ⇒ `coin=5`. | مزوّد الألعاب يحسب `الفوز = الرهان × المضاعف` **جوه اللعبة**. باكدنا لا يضاعف أبداً — يضيف قيمة `coin` كما وصلت. رهان `1000` × `x5` ⇒ `coin=5000`؛ رهان `1` × `x5` ⇒ `coin=5`. |
| **Biggest mismatch cause** | **Two ledgers:** backend gift/lucky/recharge routes still write coins to **Firestore**, while app + dashboard read **Supabase `users.coins`**. No mirror exists. | **دفتران:** مسارات الهدايا/الحظ/الشحن في الباكند تكتب الكوينز في **Firestore**، بينما التطبيق واللوحة يقرأون **Supabase**. لا توجد مزامنة بينهما. |
| **Second cause (games)** | Double deduction of the bet + lost update from parallel callbacks. | الخصم المزدوج للرهان + ضياع التحديث عند توالي callback متوازية. |

**Arithmetic example / مثال حسابي حاسم:**  
`5,871,400 + 20,000` must be `5,891,400` — **not** `5,886,400`.  
If you see `5,886,400`, the 5,000 bet was deducted a second time in our callback.

---

## 1. Architecture — المعمارية

```
┌──────────────┐  1) open game URL (coins=<absolute balance>)   ┌────────────────────┐
│ Flutter App  │ ──────────────────────────────────────────────► │ Game H5 (Alfa /    │
│ alfa_game_   │                                                 │ StyeParty)         │
│ screen.dart  │ ◄────────────────────────────────────────────── │ alfanexso.tech     │
└──────┬───────┘  2) game plays, deducts bet internally           └─────────┬──────────┘
       │                                                                   │ 3) Server-to-server callback
       │ 5) reloadUser() via Supabase Realtime                             │    POST /api/v1/games/change-balance
       ▼                                                                   ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│ Backend (Vercel): backend/src/routes/games.ts                                   │
│   • verify MD5 sign  • resolveDirection()  • idempotency (order_id)              │
│   • bet  → ignore (no RPC)   • win → game_provider_settle_round(bet=0, win=N)    │
└───────────────────────────────┬──────────────────────────────────────────────────┘
                                │ 4) RPC (SECURITY DEFINER)
                                ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│ Supabase Postgres: users.coins + game_bet_records + game_jackpot_pool            │
│ (one atomic UPDATE ... RETURNING)                                                │
└───────────────┬────────────────────────────────────┬─────────────────────────────┘
                │ 6) realtime userStream              │ 7) getUsers()
                ▼                                     ▼
        ┌───────────────┐                    ┌──────────────────┐
        │ Flutter UI    │                    │ Admin Dashboard  │
        │ UserProvider  │                    │ Users.tsx        │
        └───────────────┘                    └──────────────────┘
```

**بالعربية:** اللعبة تفتح برابط يحمل الرصيد المطلق `coins=...`. اللعبة تخصم الرهان من رصيدها الداخلي. عند الفوز ترسل callback للسيرفر؛ السيرفر يضيف الفوز فقط إلى `users.coins` في Supabase داخل معاملة واحدة ذرّية. التطبيق يستلم التغيير عبر Realtime (`reloadUser()`) ولوحة التحكم تقرأ نفس الجدول.

---

## 2. Source of truth — مصدر الحقيقة (مهم جداً)

| Component | Reads / writes | File |
|---|---|---|
| Flutter app | `SupabaseDataService.getUser()` + Realtime `users:$uid` | `lib/services/supabase_service.dart:134`, `lib/providers/user_provider.dart:33` |
| Game callback backend | `rpc/game_provider_settle_round` + `game_provider_orders` | `backend/src/routes/games.ts:541` |
| Admin dashboard | `client.from('users').select('*')` | `admincore-dashboard/src/lib/db.ts:201-209`, `src/lib/supabase.ts:7-15` |

✅ All three point at **`https://pxyqgeitjdsilgfftnyd.supabase.co`** with the publishable key `sb_publishable_...`.

⚠️ **Do NOT use an `sbp_...` key** — it belongs to a different project and returns `401 Invalid API key`. This makes the dashboard show stale/empty data and looks exactly like a "balance mismatch".

📌 **Historical note / ملاحظة تاريخية:** `AGENTS.md` describes an earlier migration of the dashboard to a Firestore compat layer. The **current** `src/lib/supabase.ts` is a real Supabase client again (commit `4ce0eee` reverted it). If you ever see the dashboard reading Firestore while the app reads Supabase, that alone explains a mismatch — verify both sides point at the same project before debugging anything else.

### 2.1 The dual-ledger problem — مشكلة الدفترين (SPIF: أهم سبب)

The **Node backend** still has Firestore wired in (`backend/src/config/firebase.ts:26-34`, project `ahla-live`). Several routes write `users/{uid}.coins` **in Firestore**, never in Supabase:

| File | What it writes |
|---|---|
| `backend/src/routes/gifts.ts:85-149` | sender `coins - totalCost`, receiver `diamonds`, `walletRef.diamond_balance` |
| `backend/src/routes/lucky.ts:211-316` | lucky-draw coin/diamond changes |
| `backend/src/routes/luckyBags.ts:96-170`, `:366-393` | lucky-bag balance changes |
| `backend/src/routes/events.ts:303-306` | event rewards |
| `backend/src/services/levelService.ts:67-68` | level-up coins |
| `backend/src/services/cpRewardService.ts:376` | relationship rewards |
| `backend/src/routes/hostTargets.ts:105-106` | host target rewards |
| `backend/src/services/rechargeService.ts:97-102` | recharge credits |

The Flutter app has **no** `cloud_firestore` dependency and reads only Supabase `users.coins`. The dashboard also reads Supabase. **There is no Firestore → Supabase coin mirror anywhere in the repo.** (Diamonds have `backend_diamond_sync_and_financial_engine.sql` triggers; coins do not.)

**Consequence / النتيجة:** a gift or lucky-bag win can be recorded in Firestore and be invisible to both the app and the dashboard. Conversely, a game-provider win is recorded in Supabase and invisible to any Firestore-based observer. This is the #1 reason two "balance" numbers disagree.

**Repair options / الحلول:**
1. **Preferred:** change those backend routes to call a Supabase atomic RPC (`adjust_user_wallet`, `game_provider_settle_round`, or a new `apply_coin_delta`) instead of Firestore `txn.update`.
2. If Firestore must stay: add a mirrored write to Supabase in the same request (and a reconciliation job for historical rows). Never rely on one side alone.
3. Add a `users.coins` sync trigger/mirror analogous to the diamond sync, and monitor drift with a scheduled job.

---

## 3. Credentials & environment — بيانات الاعتماد

| Variable | Where | Value / notes |
|---|---|---|
| `GAME_APP_KEY` | Vercel (backend) | `alfa_key_app_ahal_377` (APP_KEY of the provider) |
| `GAME_API_SECRET` | Vercel (backend) | Must equal `app_config.game_provider_secret` in Supabase. Seed value is in `supabase_game_provider_api.sql` line 21 — **do not hardcode it in docs or client code**. |
| `SUPABASE_URL` | Vercel / dashboard env | `https://pxyqgeitjdsilgfftnyd.supabase.co` |
| `SUPABASE_SERVICE_KEY` or `SUPABASE_ANON_KEY` | Vercel | Prefer service key; fallback publishable key. |
| `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` | Dashboard build | Same project as above. |

**Provider reference endpoints (their format, not ours):**
```
POST https://alfanexso.tech/api/leader-cc-game/get-user-info
POST https://alfanexso.tech/api/leader-cc-game/change-balance
POST https://alfanexso.tech/api/leader-cc-game/make-up-orders
```
**Our endpoints (what the H5 must call):**
```
POST https://ahla-live-api.vercel.app/api/v1/games/get-user-info
POST https://ahla-live-api.vercel.app/api/v1/games/change-balance
POST https://ahla-live-api.vercel.app/api/v1/games/make-up-orders
```

---

## 4. Endpoints & signatures — المسارات والتوقيع

Signature = `md5(concat without separators, lowercase)`, always appending `APP_KEY` last. Accepted in `body.sign` or query, compared case-insensitively.

التوقيع = `md5` لسلسلة الحقول متلاصقة بدون فواصل + `APP_KEY` في الآخر، ويُقبل من body أو query.

| Endpoint | Signature formula |
|---|---|
| `get-user-info` | `md5(gameId + uid + token + roomId + APP_KEY)` |
| `change-balance` | `md5(orderId + gameId + roundId + uid + coin + type + rewardType + token + winId + roomId + APP_KEY)` |
| `make-up-orders` | `md5(orderId + gameId + roundId + uid + coin + rewardType + winId + roomId + APP_KEY)` |

**Response format — HTTP is ALWAYS 200** (same as provider):
```json
{ "errorCode": 0, "errorMsg": "success", "code": 200, "msg": "success", "data": { } }
{ "errorCode": 10004, "errorMsg": "Verify signature fail", "code": 10004, "msg": "Verify signature fail", "data": [] }
```

| Code | Meaning / المعنى |
|---|---|
| 10001 | Missing fields / حقول ناقصة |
| 10002 | User not found / مستخدم غير موجود |
| 10003 | Insufficient coins / رصيد غير كافٍ |
| 10004 | Bad signature / توقيع خاطئ |
| 10005 | Settlement failed / فشل التسوية |
| 10006 | `GAME_API_SECRET` not set on our server / السر غير مضبوط عندنا |
| 10007 | Ambiguous direction — refused to write balance / اتجاه غامض — رفضنا الكتابة حمايةً للرصيد |
| 10099 | Internal error / خطأ داخلي |

---

## 5. THE OWNER RULE — قاعدة المالك (أهم قاعدة في الملف)

> **EN:** The bet is consumed **inside the game's own wallet** when the player enters with `coins=<absolute>`. Our callback must therefore never deduct it again. Only the win is credited.

> **AR:** الرهان يتخصم **جوه محفظة اللعبة نفسها** عند الدخول بالرصيد المطلق `coins=`. لذلك يجب ألا نخصمه مرة ثانية في callback. الفوز فقط هو الذي يُضاف.

| Event | Provider sends | Our internal direction | Effect on `users.coins` |
|---|---|---|---|
| Bet | `type=1`, `coin=5000` | `ignored_bet` | **0** — no RPC call at all. Order is still saved for idempotency. |
| Win | `type=2`, `coin=20000` | `credit` | `+20000`, with `p_bet_amount = 0` |

Implementation: `backend/src/routes/games.ts` lines 251-296 (`resolveDirection`) and 406-419.

```ts
if (direction === 'ignore') {
  result = { status: 'ok', net: 0, coins: await sbCurrentCoins(uid) }; // لا كتابة رصيد
} else {
  result = await settleRound({ ..., bet: 0, win: amount }); // الفوز فقط
}
```

❌ Old broken behaviour: treating `type=1` as a debit → `5,871,400 - 5,000 + 20,000 = 5,886,400`.  
✅ Correct behaviour: `5,871,400 + 20,000 = 5,891,400`.

### 5.1 The multiplier rule — قاعدة المضاعف (تسري على كل الألعاب)

> **EN — Business rule confirmed by the product owner:** In **every** game shipped in the app, the number the player wagers is multiplied by the win multiplier. The provider performs this calculation **inside the game**, and the win callback delivers the **already-multiplied result** in `coin`.

> **AR — قاعدة مؤكدة من صاحب المنتج:** في **كل** الألعاب المركّبة في التطبيق، الرقم الذي يرهنه اللاعب يُضاعَف بمعامل الفوز (multiplier). المزوّد يقوم بهذا الحساب **داخل اللعبة**، و callback الفوز يرسل النتيجة **بعد الضرب** في حقل `coin`.

| Bet (رهان) | Multiplier | Provider sends `coin` (win) | credited to `users.coins` |
|---|---|---|---|
| `1000` | `x5` | `5000` | `+5000` |
| `1` | `x5` | `5` | `+5` |
| `5000` | `x4` | `20000` | `+20000` |

**Implementation consequence / النتيجة على التنفيذ:**

- ✅ Our backend **NEVER recomputes** `bet × multiplier`. It credits `Math.abs(coin)` verbatim (`games.ts:388`, `:412-418`).
- ✅ Our backend **NEVER deducts the bet** for `type=1` (it was already consumed inside the game).
- ❌ Any code that does `coins += bet × mult` **on top of** the callback would double-pay.
- ❌ Any code that does `coins -= bet` on `type=1` would double-deduct.

**⚠️ Verify once with real data — تحقق مرة واحدة بالبيانات الحقيقية:** confirm whether the `coin` value on `type=2` is the **gross payout** (`bet × multiplier`, stake included) or the **net profit** (`bet × multiplier - bet`). Compare three numbers for one round:
1. `coin` in the win callback (`game_provider_orders`),
2. the bet amount,
3. the game's displayed balance before vs after the round.

If `game_final = game_start - bet + coin`, then crediting `coin` is correct. If `game_final = game_start - bet + (coin - bet)`, then the provider is reporting gross and we must credit `coin - bet`. **Do not guess — verify before changing settlement math.**

---

## 6. Direction detection — تحديد اتجاه التسوية

Priority used by `resolveDirection()` (first match wins):

1. Signed `diff` / `change` (`-5000` → ignore, `+5000` → credit). Note: use `diff`, **not** `coin` (coin is the absolute post-operation balance).
2. Negative `coin` sign.
3. Numeric `type`: **`1` = bet → ignore, `2` = win → credit** (confirmed from `game_provider_orders` data).
4. Explicit `reason` (`bet` / `win`).
5. Words inside `type` / `rewardType`.
6. Ambiguous → reject with `10007`. **Golden rule: if unsure, write nothing.**

الترتيب بالعربية: `diff/change` الموقّعة ← إشارة `coin` السالبة ← `type` الرقمي ← `reason` ← كلمات `type/rewardType` ← رفض `10007`.

---

## 7. Atomic settlement — التسوية الذرية

`game_provider_settle_round` (SECURITY DEFINER) does in ONE transaction:
- authenticate `p_secret` against `app_config.game_provider_secret`
- `UPDATE users SET coins = COALESCE(coins,0) + (win - bet) ... RETURNING coins` ← **row lock, no lost update**
- insert into `game_bet_records`
- adjust `game_jackpot_pool`

Required migration: `supabase/migrations/20261118_fix_game_settlement_atomic.sql`.  
The older version used `SELECT` then `UPDATE`; two parallel callbacks could read the same balance and overwrite each other.

**بالعربية:** النسخة القديمة كانت تقرأ الرصيد ثم تكتبه، فCALLBACK اتنين في نفس اللحظة كانوا يقرأوا نفس القيمة وآخر واحد يلغي التاني. الإصلاح يستخدم `UPDATE ... RETURNING` عشان الصف يتقفل والزيادة تحسب من أحدث قيمة.

---

## 8. Idempotency — منع التسوية المزدوجة

- Table `game_provider_orders`, `order_id` is **PRIMARY KEY** (`supabase_game_provider_orders.sql`).
- Flow: `sbOrderExists(orderId)` → settle → `sbOrderSave(row)`.
- Wins and ignored bets are both recorded (`direction = credit | ignored_bet`).
- ⚠️ The check-and-save is not itself atomic; the PRIMARY KEY is what actually protects you. Keep it.
- ⚠️ The SQL ships an `anon` RLS policy with full access as a temporary fallback. Remove it once `SUPABASE_SERVICE_KEY` is configured.

---

## 9. App side — جهة التطبيق

- Launch URL: `https://alfanexso.tech/play/<APP_KEY>/<gameId>?gameId=...&uid=<uid>&token=<SessionTokenStore.token>&roomId=<roomId>&view_mode=half`
- `coins=<user.coins>` is passed as an **absolute** value; the provider confirmed zero-cache priority (`coins=0` ⇒ 0 immediately).
- `_injectBalanceMirror()` writes the true Supabase balance into `AlfaBridge`/`gameBridge`/`JSBridge`, `localStorage` and parsed JSON every 700ms; `_pushTrueCoins()` calls `window.__sugarGame.updateCoins(n)`.
- After any settlement: `reloadUser()` → `_pushTrueCoins()` (`alfa_game_screen.dart:702-708`).
- **Critical gate:** `_isServerSettled => widget.host == 'alfanexso.tech'` (`alfa_game_screen.dart:681`). Only when this is `true` are local `_handleBet/_handleWin` writes skipped. A different host string (e.g. `www.alfanexso.tech`, `http://`, trailing slash) makes the app write coins **locally AND through the callback** → guaranteed mismatch.

**بالعربية:** لازم يتأكد المطوّر إن قيمة `host` تساوي `alfanexso.tech` بالظبط، وإلا التطبيق هيخصم/يضيف الرصيد محلياً بالـ JS bridge وكمان السيرفر هيعمل التسوية → رصيد مزدوج.

### 9.1 Games actually shipped in the app — الألعاب الموجودة فعلياً في التطبيق

> ℹ️ This section was added after inspecting `lib/screens/room/widgets/room_game_bottom_sheet.dart`. The multiplier rule (§5.1) applies to **all 8 games**, but they settle through **two different paths**.

The game list (`room_game_bottom_sheet.dart:45-130`):

| # | Key | `game_id` | Settlement path / مسار التسوية |
|---|---|---|---|
| 1 | `sugarrush` | (local HTML served by `HttpServer`) | **App-side** — `sugarrush_game_dialog.dart:302-415` |
| 2 | `ludo` | `fe-game-cocos-ludo` | **Provider callback** — `alfa_game_screen.dart` |
| 3 | `crazy_fruit` | `fe-game-crazy-fruit` | Provider callback |
| 4 | `greedy` | `fe-game-greedy` | Provider callback |
| 5 | `super_77` | `fe-game-super77` | Provider callback |
| 6 | `lucky_777` | `fe-game-lucky777` | Provider callback |
| 7 | `sudan` | `fe-game-sudan` | Provider callback |
| 8 | `gift_spin` | `fe-game-giftspin` | Provider callback |

**Path A — Sugar Rush (local game, app writes the ledger):**
- The game JS calls the Flutter JS bridge with `action:'bet', betMoney:X` and `action:'spin_result', betMoney:X, winMoney:Y, isWin`.
- Flutter deducts `betMoney` from `users.coins` (`:335-370`), then adds `winMoney` (`:372-415`).
- `winMoney` is **already multiplied by the game** — Flutter never multiplies. `net_result = winAmount - betAmount` is only written to `game_bet_records` for analytics (`:406`).
- ✅ **Fixed 2026-11-18:** this path now uses `adjustUserWallet(uid, ±delta, 0)` (atomic RPC) instead of `updateUser(user.uid, {'coins': user.coins ± amount})`. The old code caused lost updates: when `spin_result` arrived before the bet write completed, Flutter read the **pre-bet** balance and wrote `start + win`, silently dropping the bet deduction — so the app showed `+win` (e.g. `+5000` for bet `1000` × `x5`) instead of `+win - bet` (`+4000`). This was the direct source of the app-vs-dashboard mismatch.

**Path B — 7 provider games (server-to-server):**
- Launched with `coins=<absolute Supabase balance>`; `_isServerSettled == true` for `alfanexso.tech` so local `_handleBet/_handleWin` are skipped (`alfa_game_screen.dart:584-605`).
- The game computes `bet × multiplier` and reports it as `coin` in `type=2`; our backend credits `coin` verbatim.
- `_recordBet()` only writes the analytics row; it does not change the balance.

**بالعربية:** الألعاب 8: لعبة Sugar Rush محلية والتطبيق نفسه بيخصم الرهان ويضيف الفوز (`winMoney` — يعني مضروب في المضاعف جوّه اللعبة)، و7 ألعاب من المزوّد (`alfanexso.tech`) التسوية بتاعتها server-to-server والسيرفر بيضيف `coin` كما وصل. في الحالتين **احنا ما بنضاعفش** — اللعبة هي اللي بتحسب.

---

## 10. Why the balance does not match — ليه الرصيد مش متطابق

| # | Cause / السبب | Symptom / العَرَض | Fix / الحل |
|---|---|---|---|
| 1 | **Dual ledger — Firestore vs Supabase ( biggest )** — دفتران: Firestore و Supabase | Gift/lucky/recharge credited in Firestore but app+dashboard show old Supabase value | See §2.1 — route backend writes to Supabase RPC or mirror both |
| 2 | Bet treated as debit (old callback) — خصم الرهان مرتين | App shows `balance - bet` after a win | Deploy current `games.ts` (`resolveDirection` ignores `type=1`) |
| 3 | Lost update from parallel callbacks — ضياع تحديث | Random contradictions in `game_provider_orders` | Apply `20261118_fix_game_settlement_atomic.sql` |
| 4 | Non-atomic read-modify-write on app and dashboard — قراءة ثم كتابة غير ذرّية | A later PATCH overwrites an atomic RPC increment | Use RPCs (`adjust_user_wallet`, `spend_user_coins`) everywhere |
| 5 | `saveUser()` PATCHes the **whole** `UserModel` — حفظ النموذج كاملاً | Editing an unrelated field restores old `coins`/`diamonds` from a stale model | Patch only changed fields |
| 6 | Wrong host string → both local & server writes — المضيف غلط | Balance changes twice per round | Keep host exactly `alfanexso.tech` |
| 7 | `GAME_API_SECRET` empty/mismatched — السر غلط | `errorCode 10006`, wins never credited | Set env = `app_config.game_provider_secret`; redeploy |
| 8 | Wrong Supabase key (`sbp_...`) — مفتاح مشروع غلط | `401 Invalid API key`, dashboard stale | Use `sb_publishable_...` for this project |
| 9 | Third balance `user_wallets.gold_balance` — رصيد ثالث | A service updates gold_balance but displayed coins unchanged | Decide one canonical field; sync or remove the other |
| 10 | Missing RPCs (`add_coins_safe`, `admin_recharge_gold`, `exchange_diamonds_to_gold`, `preview_recharge_target_by_code`) — دوال غير موجودة | Silent fallback to non-atomic direct writes | Deploy the RPCs; remove silent fallbacks |
| 11 | Duplicate `orderId` race — تكرار الطلب | Win credited twice | Keep `order_id PRIMARY KEY`; don't remove it |
| 12 | Optimistic coins window (5s) in `UserProvider` — تحديث متفائل (`user_provider.dart:38-47`) | App temporarily differs from DB | Wait 5s / force `reloadUser()` |
| 13 | Provider cached old `coins` — اللعبة استخدمت كاش قديم | In-game balance differs from app/dashboard | Provider confirmed zero-cache; re-open with fresh `coins` |
| 14 | Manual admin edit vs callback in flight — تعديل أدمن مع callback | Last writer wins | Serialize manual edits; check `updated_at` |

---

## 11. Deployment checklist — قائمة النشر

1. Apply `supabase_game_provider_orders.sql` on Supabase.
2. Apply `supabase_game_provider_api.sql` (creates `game_provider_settle_round` + secret seed).
3. Apply `supabase/migrations/20261118_fix_game_settlement_atomic.sql` (overwrites the RPC with atomic version).
4. Set Vercel env: `GAME_APP_KEY`, `GAME_API_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` (or anon fallback).
5. Deploy backend (`api/index.ts`, `vercel.json` rewrites `/api/v1/(.*)` → `/api/index`).
6. Verify dashboard and app use the same Supabase project/key.
7. Run the verification commands below.

---

## 12. Verification — التحقق

Generate a test sign / توليع توقيع اختبار:
```bash
node -e "const c=require('crypto');const K='alfa_key_app_ahal_377';" \
"console.log(c.createHash('md5').update('GAME'+'UID'+'TOKEN'+'ROOM'+K).digest('hex'))"
```

Test `get-user-info`:
```bash
curl -s -X POST https://ahla-live-api.vercel.app/api/v1/games/get-user-info \
  -H 'Content-Type: application/json' \
  -d '{"gameId":"fe-game-greedy","uid":"UID","token":"TOKEN","roomId":"ROOM","sign":"<MD5>"}'
```

Check DB state / فحص قاعدة البيانات:
```sql
SELECT coins, diamonds, updated_at FROM public.users WHERE uid = 'UID';
SELECT gold_balance, diamond_balance FROM public.user_wallets WHERE uid = 'UID';
SELECT order_id, type, coin, direction, result, created_at
FROM public.game_provider_orders WHERE uid = 'UID' ORDER BY created_at DESC LIMIT 20;
SELECT game_id, bet_amount, win_amount, net_result, created_at
FROM public.game_bet_records WHERE user_id = 'UID' ORDER BY created_at DESC LIMIT 20;
SELECT status, amount FROM public.recharge_requests WHERE user_id = 'UID' ORDER BY created_at DESC;
```

Compare with Firestore (the other ledger!) using the Admin SDK or Firebase Console:
```
users/{UID}.coins
users/{UID}.diamonds
user_wallets/{UID}
```
If Firestore `coins` ≠ Supabase `users.coins`, you have confirmed cause #1 — a gift/lucky/recharge route credited one side only.

Expected log lines / الأسطر المتوقعة في لوج Vercel:
```
[games] change-balance direction: { ... direction: 'ignored_bet' }   → لا تغيير رصيد
[games] settled: <orderId> ... net= 20000 coins= 5891400              → فوز فقط
```

---

## 13. Handoff checklist — قائمة التسليم للمطوّر الجديد

- [ ] Read `GAME_CALLBACK_API.md` (Arabic deep-dive) and this file.
- [ ] **Compare Firestore `users/{uid}.coins` with Supabase `users.coins` for an affected user.** Fix the writers listed in §2.1 if they differ.
- [ ] Confirm all 3 migrations are applied (check with the SQL above).
- [ ] Confirm `GAME_API_SECRET` matches `app_config.game_provider_secret`.
- [ ] Confirm host string is exactly `alfanexso.tech` in every game registry entry.
- [ ] Confirm bet orders show `direction = ignored_bet` and `net = 0`.
- [ ] Confirm win orders show `net = +coin` and `bet_amount = 0`.
- [ ] **Verify the multiplier rule (§5.1) on a real round:** bet `1000` × `x5` ⇒ `coin=5000`, and bet `1` × `x5` ⇒ `coin=5`. Confirm the credited value is exactly the `coin` reported by the provider (no local re-multiplication, no bet deduction), and check gross-vs-net payout with the example in §5.1.
- [ ] Check both settlement paths in §9.1: Sugar Rush (`winMoney`) and the 7 provider games (`type=2 coin`). Neither must multiply locally.
- [x] Sugar Rush read-modify-write replaced with `adjustUserWallet` atomic RPC (`sugarrush_game_dialog.dart:347,389`) — **done 2026-11-18**.
- [x] `alfa_game_screen.dart` local `_handleBet/_handleWin` also switched to atomic RPC — **done 2026-11-18**.
- [ ] Confirm no code path still does `read → add → PATCH` on `users.coins` (app, dashboard, signin, backend).
- [ ] Confirm RPCs `add_coins_safe`, `admin_recharge_gold`, `exchange_diamonds_to_gold` exist on the deployed project (remove silent fallbacks).
- [ ] Confirm app balance updates only after `reloadUser()` from Supabase.
- [ ] Confirm dashboard `Users` page shows the same `coins` value as the app after a 5s refresh.
- [ ] Ask the provider to confirm which callback URL their H5 actually calls (ours vs `alfanexso.tech`).

---

## 14. Security notes — ملاحظات أمنية

- `game_provider_settle_round` accepts the secret as an RPC argument; it is `SECURITY DEFINER` and sets `app.write_guard_bypass='provider'` **only inside its own transaction**.
- MD5 comparison is currently plain string; prefer `timingSafeEqual` after a length check.
- Keep the raw `coin` string for signature verification, but use the rounded `amount` for the ledger — otherwise retries can produce different signatures.
- Remove the `anon` policy on `game_provider_orders` once service-role is configured.
