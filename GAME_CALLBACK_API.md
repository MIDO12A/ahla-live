# بروتوكول StyeParty Callback API — Ahla Live

> آخر تحديث: 2026-11-18 — بيانات شركة الألعاب + حالة التطبيق في الريبو

---

## 1) بيانات الاعتماد

| الحقل | القيمة |
|---|---|
| **APP_KEY** | `alfa_key_app_ahal_377` |
| **Callback Base URL المعتمد** | `https://ahla-live-api.vercel.app/api/v1/games` |
| المتغير في الباكند | `GAME_APP_KEY` (القيمة الافتراضية مطابقة أعلاه) |
| السر المشترك للتسوية | `GAME_API_SECRET` (لا يُخزّن في هذا الملف) |

مسارات مرجع الشركة (الصيغة/الرد المعياري — تُقابل مساراتنا على الـ Base URL أعلاه):

```
POST https://alfanexso.tech/api/leader-cc-game/get-user-info
POST https://alfanexso.tech/api/leader-cc-game/change-balance
POST https://alfanexso.tech/api/leader-cc-game/make-up-orders
```

> ملاحظة: `alfanexso.tech` هو مرجع الشركة. التطبيق يستقبل النسخة الخاصة بنا تحت
> `https://ahla-live-api.vercel.app/api/v1/games/...`.

---

## 2) المسارات المدعومة وقواعد التوقيع MD5 (lowercase)

التوقيع = `md5(concat بدون فواصل)` + APP_KEY في الآخر. يُقبل من `body.sign` أو query،
بمقارنة غير حساسة لحالة الأحرف.

| المسار | الوظيفة | الصيغة |
|---|---|---|
| `POST /get-user-info` | بيانات اللاعب والرصيد قبل الجولة | `md5(gameId + uid + token + roomId + APP_KEY)` |
| `POST /change-balance` | خصم رهان / إضافة فوز (idempotent بـ `orderId`) | `md5(orderId + gameId + roundId + uid + coin + type + rewardType + token + winId + roomId + APP_KEY)` |
| `POST /make-up-orders` | تعويض/إعادة محاولة أوامر (كائن واحد أو `orders[]`) | `md5(orderId + gameId + roundId + uid + coin + rewardType + winId + roomId + APP_KEY)` |

### صيغة الرد (مطابقة للشركة — HTTP دائماً 200)

```json
// نجاح
{ "errorCode": 0, "errorMsg": "success", "code": 200, "msg": "success", "data": { } }

// فشل توقيع
{ "errorCode": 10004, "errorMsg": "Verify signature fail", "code": 10004, "msg": "Verify signature fail", "data": [] }
```

رموز الأخطاء المستخدمة: `10001` حقول ناقصة · `10002` مستخدم غير موجود ·
`10003` رصيد غير كافٍ · `10004` توقيع خاطئ · `10005` فشل التسوية ·
`10006` سر التسوية (`GAME_API_SECRET`) غير مضبوط على سيرفرنا ·
`10007` اتجاه التسوية غامض (تم رفض العملية حمايةً للرصيد) · `10099` خطأ داخلي.

### اتجاه التسوية (أهم قاعدة)

**قاعدة المالك (2026-11-18): الرهان (`type=1`) ملهوش أي تأثير على رصيد Supabase —
لا خصم ولا إضافة.** اللعبة استهلكت الرهان جوه رصيدها عند الدخول (`coins=` مطلق)،
فخصمه تاني في callback = خصم مزدوج. مثال: رصيد `5,871,400` + فوز `20,000`
لازم يطلع `5,891,400` (مش `5,886,400`).

الترتيب المستخدم في `backend/src/routes/games.ts`:

1. `diff` / `change` الموقّع (`-5000` = رهان/تجاهل، `+5000` = فوز/إضافة).
2. إشارة `coin` السالبة.
3. `type` الرقمي لبروتوكول StyeParty: **`1` = رهان (تجاهل)، `2` = فوز (إضافة)**
   (مؤكّد من `game_provider_orders`: كل `type=1` بـ `coin=5000`، و`type=2`
   بمبالغ فوز كبيرة مثل 20000 / 80000 / 320000 / 5600000).
4. `reason` صريح (`bet` / `win`).
5. كلمات `type` / `rewardType`.
6. لو كل ما سبق غامض → **نرفض** بـ `10007` ولا نكتب أي رصيد.

سلوك الاستجابة:

| الحدث | الاتجاه الداخلي | التأثير | `data` |
|---|---|---|---|
| `type=1` / رهان | `ignore` | صفر — الرصيد يفضل زي ما هو | `net:0`, `ignoredBet:true`, `coins:<الرصيد الحالي>` |
| `type=2` / فوز | `credit` | `+coin` فقط (`bet=0` دايماً) | `net:+coin`, `coins:<الجديد>` |

الأمر يُسجَّل في `game_provider_orders` في الحالتين (`direction = ignored_bet`
أو `credit`) عشان الـ idempotency يشتغل، لكن حدث الرهان ما بيستدعي RPC أصلاً.

> ✅ التسوية تتم ذرّياً داخل `game_provider_settle_round`: الرصيد + `game_bet_records`
> + `game_jackpot_pool` في معاملة واحدة. النسخة الجديدة تستخدم `UPDATE ... RETURNING`
> بدل `SELECT` ثم `UPDATE` عشان ما يحصلش lost update مع callback متوازية
> (`supabase/migrations/20261118_fix_game_settlement_atomic.sql`).
> التطبيق يستلم النتيجة عبر `reloadUser()` من Supabase — لا يكتب الرصيد بنفسه.
>
> ⚠️ قبل التشغيل: نفّذ `supabase_game_provider_orders.sql` +
> `supabase/migrations/20261118_fix_game_settlement_atomic.sql` على Supabase،
> واضبط `GAME_API_SECRET` على Vercel بنفس قيمة `app_config.game_provider_secret`.

> 🛠️ تصحيحات قديمة:
> - `20261118_fix_game_settlement_credits.sql` — خصم كل `type=1` اللي اتحسب
>   `credit` قديماً (اتنفّذ بالفعل).
> - `20261118_refund_last_bet_d35a.sql` — استرداد آخر رهان 5,000 ⇒ `5,891,400`.
> - `20261118_refund_all_bet_debits.sql` — خيار بديل لاسترداد كل خصومات الرهان
>   (440,000 للمستخدم النشط) — **لا يُنفَّذ بدون موافقة**.

### حالة التشغيل — تحقّق حي (2026-11-18)

| الفحص | النتيجة |
|---|---|
| نشر `ahla-live-api` (production) | ✅ `dpl_DrJJfa5WPUwFMRGgJmp2QkUTvHhC` |
| `POST /get-user-info` بـ JSON | ✅ `10004` (بدل HTTP 500 القديم) |
| `POST /change-balance` بتوقيع صحيح + uid وهمي | ✅ `10002 user_not_found` ⇒ السر مطابق (ولو كان غلط لرجع `10006`) |
| لوج Vercel | `[games] change-balance settlement failed: <orderId> user_not_found` |
| جدول `game_provider_orders` | ✅ موجود، والصف يُحفظ **بعد نجاح** التسوية فقط (يسمح بإعادة المحاولة) |

> ملاحظة: المفتاح العام الصالح للمشروع هو `sb_publishable_...` (يبدأ بـ `sb_publishable_`)،
> أما مفتاح `sbp_...` الذي زوّدت به فهو لمشروع آخر ويرجع `401 Invalid API key`.

### رابط تشغيل اللعبة من التطبيق (StyeParty params)

```
https://alfanexso.tech/play/alfa_key_app_ahal_377/fe-game-greedy
  ?gameId=fe-game-greedy
  &uid={STYEPARTY_USER_ID}
  &token={PLAYER_TOKEN}
  &roomId={ROOM_ID}
  &view_mode=half
```

| المعامل | المصدر في التطبيق |
|---|---|
| `gameId` | معرّف اللعبة (`fe-game-greedy`، `fe-game-lucky777`، ...) |
| `uid` | `user.uid` من `UserProvider` |
| `token` | `SessionTokenStore.token` (نفس `x-session-token`) |
| `roomId` | `roomId` الممرّر من الغرفة (فارغ خارج الغرف) |
| `view_mode` | يُمرَّر للتوافق فقط؛ **ارتفاع الصندوق تلقائي** من قياس `canvas` (انظر §6) |

> التطبيق يضيف أيضاً `user_id` / `nickname` / `coins` / `avatar` / `win_rate`
> كمعاملات توافق مع المنصة القديمة — التوقيع يعتمد على الخمسة أعلاه فقط.

### الألعاب المدمجة (7 ألعاب + Sugar Rush محلياً)

| المفتاح | `game_id` | الحالة |
|---|---|---|
| ludo | `fe-game-cocos-ludo` | ✅ |
| crazy_fruit | `fe-game-crazy-fruit` | ✅ |
| greedy | `fe-game-greedy` | ✅ |
| super77 | `fe-game-super77` | ✅ |
| lucky777 | `fe-game-lucky777` | ✅ |
| sudan | `fe-game-sudan` | ✅ (أُضيفت 2026-11-18) |
| gift_spin | `fe-game-giftspin` | ✅ (أُضيفت 2026-11-18) |

> القائمة في `lib/screens/room/widgets/room_game_bottom_sheet.dart`، وسجل
> المعرّفات المختصرة في `AlfaGame.gameRegistry` (`alfa_game_view.dart`).

---

## 3) حالة التطبيق في الريبو (مطابقة ✅)

- `backend/src/routes/games.ts` (الأسطر 185–422): APP_KEY + المسارات الثلاثة + صيغ MD5 مطابقة للبينات المرسلة.
- `backend/src/app.ts` س73: `app.use('/api/v1/games', gamesRoutes)`.
- `api/index.ts`: يمرّر الطلب إلى `backend/src/app` على Vercel.
- `vercel.json`: `rewrites` يوجّه `/api/v1/(.*)` إلى `/api/index`.
- `lib/screens/game/alfa_game_screen.dart` س167–186: يمرّر `gameId`، `uid`، `token`
  (SessionTokenStore)، `roomId` و`coins` للعبة — وهي نفس الحقول المطلوبة للتوقيع،
  والرصيد في الرابط هو الحاكم عند الدخول (رد الشركة 2026-11-18).
- نفس الملف: `_pushTrueCoins()` يستدعي `window.__sugarGame.updateCoins(n)` داخل
  الجلسة فور أي تغيير في رصيد التطبيق.
- `supabase_game_provider_api.sql`: `game_provider_settle_round` يضبط الرصيد/السجل/Pool ذرّياً.

---

## 4) ما نحتاجه من شركة الألعاب

> ✅ **اتحلّت**: مقاس الصندوق (`view_mode`) — التطبيق بقى بيقيس نسبة أبعاد
> `canvas` من داخل الـ WebView ويضبط الارتفاع تلقائياً بين 40% و95% من الشاشة
> (انظر §6). ما نحتاجش قائمة قيم `half/full/غيرها`.

### رد الشركة (2026-11-18) — تم استيعابه في الكود

- **Zero-Cache / URL Absolute Priority**: اللعبة بقت تعتمد `coins=` في رابط
  الدخول بشكل مطلق. دخول بـ `coins=0` ⇒ رصيد 0 فوراً بدون رجوع لكاش قديم؛
  `coins=500` ⇒ 500؛ وأي رصيد جديد نفتح بيه اللعبة لاحقاً يُعتمد فوراً.
- **`window.__sugarGame.updateCoins(n)`**: الدالة متوفرة ومفعّلة في ألعاب
  Alfa/StyeParty بنفس سلوك Sugar Rush — التطبيق بيستدعيها عند كل تغيير في
  الرصيد الحقيقي (بعد التسوية/هدية/شحن).
- معنى كده: خصم الرهان بيحصل **جوه اللعبة فقط** (−1000 ⇒ −1000)، والفوز بيضاف
  (+1000 ⇒ +1000، +10000 ⇒ +10000). السيرفر بيضيف الفوز بس عبر callback،
  ومبيخصموش الرهان تاني (خصم مزدوج كان بيخلّي `5,871,400 + 20,000 = 5,886,400`).

**انسخ الأسئلة المتبقية دي وابعتها لشركة الألعاب كما هي:**

1. **رابط الـ callback اللي الـ H5 بيناديه فعلياً**: هو
   `https://ahla-live-api.vercel.app/api/v1/games/change-balance` ولا
   `https://alfanexso.tech/api/leader-cc-game/change-balance`؟ لازم نتأكد إن
   التسوية بتوصل لسيرفرنا. التطبيق بيسجّل كل طلبات `fetch`/XHR في اللوج تحت
   `[AlfaGame] js action=alfa_spy`.
2. **تأكيد حقول الاتجاه في `change-balance`**: هل `diff`/`change` دايماً موقّع
   (سالب للرهان وموجب للفوز)؟ وهل `reason` بيبعت `bet` و`win` فعلياً؟ الكود
   بقى يفضّل `diff` ثم `reason` ويرفض التسوية لو غامض (`10007`) — نريد تأكيد
   القيم عشان نقلّل حالات الرفض.
3. **خلفية شفافة**: شيلنا واجهتنا بالكامل؛ لو `canvas` بتاعكم بيرسم خلفية معتمة
   محتاجين بارامتر/حل منكم عشان اللعبة تظهر بشكلها بدون خلفية سودا.

### نقاط داخلية (لا تحتاج الشركة)

1. **الـ idempotency**: الفحص (`sbOrderExists`) ثم الحفظ (`sbOrderSave`) ليس ذرياً؛
   يُفضّل قيد `unique(order_id)` + تسوية داخل RPC واحد.
2. **`coin` كما وصلت**: التوقيع يحسب على النص الخام، بينما المبلغ يُقرّب بـ `abs/round`.
   لازم نضمن صيغة ثابتة (`100` وليس أحياناً `100.0`).
3. **متغيرات البيئة على Vercel**: ضبط `GAME_APP_KEY` و `GAME_API_SECRET` صراحةً
   بدل الاعتماد على القيم الافتراضية في الكود.
4. **مقارنة التوقيع**: حالياً مقارنة نصية؛ الأفضل `timingSafeEqual` بعد التحقق من الطول.

---

## 5) توليد توقيع للاختبار (Node)

```bash
node -e "const c=require('crypto');const K='alfa_key_app_ahal_377';" \
"console.log(c.createHash('md5').update('GAME'+'UID'+'TOKEN'+'ROOM'+K).digest('hex'))"
```

ثم أرسل:

```bash
curl -s -X POST https://ahla-live-api.vercel.app/api/v1/games/get-user-info \
  -H 'Content-Type: application/json' \
  -d '{"gameId":"GAME","uid":"UID","token":"TOKEN","roomId":"ROOM","sign":"<MD5>"}'
```

---

## 6) المقاس والشفافية ومزامنة الرصيد داخل WebView

### المقاس

`AlfaGameScreen.show()` يبدأ بارتفاع **88%** من الشاشة (تكبير عن الـ 58% القديمة)،
ثم الـ JS المُحقون يقيس نسبة أبعاد الـ canvas:

```js
var c = document.querySelector('canvas');
var ar = (c.width / c.height) || (c.clientWidth / c.clientHeight);
send({ action: 'game_size', ratio: ar });
```

- الحد الأقصى **الشاشة الكاملة (100%)** والأدنى 35%.
- مقبض سحب شبه غير مرئي أعلى الصندوق يسمح بتغيير المقاس يدوياً؛ بعد أول سحب
  يتوقف الضبط التلقائي احتراماً لاختيار المستخدم.
- تجاهل الفروق < 24px عشان ما يحصلش حلقة `resize ↔ measure`.

### الشفافية الكاملة

- `barrierColor: Colors.transparent` في `showModalBottomSheet` — **مفيش scrim أسود** وراء اللعبة.
- `Scaffold.backgroundColor = Colors.transparent` و`setBackgroundColor(Colors.transparent)` للـ WebView.
- لا اسم لعبة، لا كاس، لا دائرة داكنة للزر. الإغلاق بالرجوع/الضغط خارج الصندوق،
  وسجل اللعبة بضغط مطوّل على منطقة غير مرئية أعلى اليمين.

### فرض الرصيد الحقيقي (0 ⇒ 0 و1000 ⇒ 1000)

اللعبة كانت بتقرأ رصيد من مخزنها الخاص وبتضيف رصيد افتراضي. أضفنا `_injectBalanceMirror()`
اللي يكتب رصيد Supabase الحقيقي في:

- `AlfaBridge` / `gameBridge` / `JSBridge` (دوال `getUser` و`saveUser`)،
- `JSON.parse` (كل كائن يُفكّ من استجابة السيرفر)،
- `localStorage` وكل كائنات `window` المعروفة،

ويعيد الفرض كل 700ms، مع `_pushTrueCoins()` كل ثانية وفور `reloadUser()` بعد
أي تسوية خادم. النتيجة: الرصيد الظاهر جوه اللعبة = رصيد المستخدم في التطبيق بالظبط.
