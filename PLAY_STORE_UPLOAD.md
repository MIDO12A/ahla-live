# بيانات رفع Google Play — Ahla Live

> آخر تحديث: 2026-11-18 — generated for Play Console upload (تمت مراجعة قسم الباكند مقابل `backend/src/app.ts`)

---

## 1) معلومات الإصدار (من `pubspec.yaml`)

| الحقل | القيمة |
|---|---|
| **versionName** | `1.0.2369` |
| **versionCode** | `2000023538` |
| الصيغة الكاملة | `1.0.2369+2000023538` |

> ⚠️ versionCode ضخم (`2000023538`) — مقبول في Play Console ما دام أكبر من آخر رفع.
> لو Google Play رفضه (أكبر من الحد أو مكرر) نرجعه لصيغة أصغر مثل `2369`.

## 2) هوية التطبيق

| الحقل | القيمة |
|---|---|
| **Package name (applicationId)** | `com.ahlalive.app` |
| Namespace | `com.ahlalive.app` |
| اسم التطبيق | Ahla Live |
| minSdk / targetSdk | من Flutter defaults (`flutter.minSdkVersion` / `flutter.targetSdkVersion`) |
| Compile SDK | Flutter default |

## 3) التوقيع (Release Signing)

الملف: `android/key.properties`

| الحقل | القيمة |
|---|---|
| storeFile | `android/app/zero-release-key.jks` |
| keyAlias | `zero` |
| storePassword | `oeqfI3v6CT1dzu4yiEmNn5JV` |
| keyPassword | `oeqfI3v6CT1dzu4yiEmNn5JV` |

- إذا `key.properties` أو الـ keystore مو موجود → الـ release build يوقع بـ **debug key** (Play Console يرفضه).
- لازم ترفع بنفس الـ keystore القديم اللي مرفوع بيه التطبيق على Play — غير كذا Play يرفض الـ update (App signing by Google Play يتطلب نفس upload key).

## 4) بناء ملف الرفع (AAB)

```powershell
# بناء AAB موقّع (الصيغة المطلوبة لـ Play Console)
C:\flutter\bin\flutter.bat build appbundle --release

# أو APK موقّع (للرفع اليدوي/الاختبار)
C:\flutter\bin\flutter.bat build apk --release
```

**المخرجات:**
- AAB: `build/app/outputs/bundle/release/app-release.aab`
- APK: `build/app/outputs/apk/release/app-release.apk` (آخر بناء: 325 MB — 11/15)

## 5) خطوات الرفع في Play Console

1. افتح [Google Play Console](https://play.google.com/console) → تطبيق **Ahla Live**
2. **Release → Production** (أو Testing track للتجربة)
3. **Create new release** → ارفع `app-release.aab`
4. Play Console يعرض versionCode/versionName تلقائياً — تأكد `2000023538` > آخر نسخة مرفوعة
5. أضف **Release notes** ("ما الجديد") بالعربي والإنجليزي
6. Review → Start rollout

## 6) الباكند الخاص بالتطبيق

| الحقل | القيمة |
|---|---|
| **Base URL** | `https://ahla-live-api.vercel.app/api/v1` |
| الاستضافة | Vercel — مشروع `ahla-live-api` |
| Framework | Express (TypeScript) |
| قاعدة البيانات | Supabase (للألعاب) + Firestore (للباقي) |

**الـ endpoints المتاحة فعلياً على السيرفر** (حسب `backend/src/app.ts`):

```
/api/v1/vip           → GET /tiers , GET /:uid
/api/v1/recharge      → GET /plans
/api/v1/games         → config, leaderboard, records, callback,
                        get-user-info, change-balance, make-up-orders
/health , /api/health , /api/v1/health , /docs , /swagger.json
```

> ⚠️ مسارات `auth/users/levels/agencies/rankings/cp-rewards/lucky/gifts/host-targets/events`
> ملفاتها موجودة في `backend/src/routes/` لكنها **غير مُركّبة** في `app.ts` — التطبيق
> يقرأ هذه البيانات مباشرة من Supabase/Firestore، فلا تستدعِها على هذا السيرفر.
> كذلك `set-tier` و `create-order/orders` غير موجودة (فقط `/tiers` و `/plans`).

**Games API (لشركة الألعاب):**

```
GET  /api/v1/games/config?game_id={id}
GET  /api/v1/games/leaderboard?game_id={id}&limit=10
GET  /api/v1/games/records?game_id={id}&user_id={uid}
POST /api/v1/games/callback   (header: x-game-secret) — تسوية قديمة

// بروتوكول StyeParty — التوقيع MD5 (التفاصيل في GAME_CALLBACK_API.md)
POST /api/v1/games/get-user-info
       sign = md5(gameId + uid + token + roomId + APP_KEY)
POST /api/v1/games/change-balance
       sign = md5(orderId + gameId + roundId + uid + coin + type + rewardType + token + winId + roomId + APP_KEY)
POST /api/v1/games/make-up-orders
       sign = md5(orderId + gameId + roundId + uid + coin + rewardType + winId + roomId + APP_KEY)

APP_KEY = alfa_key_app_ahal_377 | الرد دائماً HTTP 200 مع errorCode/errorMsg/data
```

## 7) ملاحظات تقنية مهمة

- `isMinifyEnabled = false` و `isShrinkResources = false` — حجم الـ APK كبير (~325MB) بسبب الأصول (SVGA، صور، ألعاب). ممكن تفعيل R8 لاحقاً لتصغير الحجم لكن يحتاج اختبار.
- قاعدة البيانات الرئيسية: **Supabase** + الباكند الخاص أعلاه.
- أيقونات/أصول جديدة غير متتبعة في git — تأكد `flutter pub get` بعد سحب آخر نسخة.

## 8) Troubleshooting

| المشكلة | الحل |
|---|---|
| "You uploaded an APK" | Play Console يرفض APK — لازم **AAB** (`build appbundle`) |
| "versionCode already used" |زوّد الرقم في `pubspec.yaml` (`version: 1.0.XXXX+CODE`) |
| "signed with wrong key" | تأكد `android/app/zero-release-key.jks` موجود و `key.properties` صحيح |
| AAB كبير جداً | طبيعي — المشروع فيه أصول تقيلة؛ opt-in play asset delivery ممكن لاحقاً |
