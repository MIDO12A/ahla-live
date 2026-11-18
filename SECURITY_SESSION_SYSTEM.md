# نظام حماية الحسابات — Session Tokens + حارس الكتابة

> شرح كامل لكل ما تم تنفيذه: البنية، الملفات، طريقة العمل، وما تبقى.

---

## 1) المشكلة الأصلية

قاعدة البيانات كانت تسمح لأي شخص يملك **المفتاح العمومي** (anon/publishable key — موجود
جوه التطبيق) بقراءة وكتابة أي صف في `users` مباشرة عبر PostgREST. يعني أي حد يقدر:

- يفتح ملف الـ APK → يطلع المفتاح → يضرب على السيرفر.
- يقرأ `users.last_ip` (الذي كان يخزّن PIN) → يدخل أي حساب.
- يكتب على أي حساب: يغيّر الماس/الكوينز/الاسم/البيانات.

**الحل**: نظام جلسات (Session Tokens) — بعد إثبات الهوية يصدر السيرفر توكناً
فريداً، والتطبيق يحمله مع كل طلب، والسيرفر يرفض الكتابة بدون توكن صالح.

---

## 2) البنية — 3 طبقات

```
[تسجيل الدخول]                    [كل طلبات التطبيق]                [قاعدة البيانات]
OTP / PIN / Google        ──►   x-session-token header      ──►   user_sessions (مقيد)
      │                              │                              │
      ▼                              ▼                              ▼
 السيرفر يثبت الهوية          كل REST/RPC يحمل التوكن      trg_users_write_guard
 ويصدر token                 (SupabaseDataService +         على جدول users
                              supabase_auth_service +
                              supabase_compat)
```

### الطبقة 1 — إصدار التوكن (السيرفر فقط)

| الطريقة | الإثبات | الدالة |
|---|---|---|
| OTP (رمز SMS) | كود صحيح من `login_otps` | `verify_login_otp` |
| PIN | هاش PIN مطابق في `login_pins` | `verify_login_pin` |
| Google | Supabase JWT حقيقي (`auth.uid()`) | `create_session` |

- المستخدم **الجديد** يحصل على جلسة مرتبطة بالـ **هاتف** (`uid=NULL`) —
  تُربط تلقائياً بالـ uid عند إنشاء صف `users` (trigger
  `trg_bind_session_on_user_insert`).
- مدة الجلسة: **90 يوم**.
- جدول `user_sessions` مقيد بـ RLS — `REVOKE ALL` عن anon — مستحيل قراءة
  توكنات الآخرين.

### الطبقة 2 — إرسال التوكن (التطبيق)

- `session_token_store.dart` — مخزن محلي (ذاكرة + SharedPreferences).
- `_headers` في `supabase_data_service.dart` و `supabase_auth_service.dart`
  يضيفان `x-session-token` تلقائياً.
- `supabase_compat.dart` (كل استدعاءات `.from()` و `.rpc()`) يضيفه أيضاً —
  **تغطية 100% للطلبات**.
- يُحفظ عند: OTP login، PIN login، Google login (`issueGoogleSession`).
- يُمحى عند: تسجيل الخروج.

### الطبقة 3 — فرض الحماية (السيرفر)

`trg_users_write_guard` — trigger على `users` BEFORE INSERT/UPDATE/DELETE:

- يقرأ `x-session-token` من headers الطلب عبر `app_request_uid()`.
- **يسمح** فقط إذا: الجلسة صالحة و`session.uid = uid الصف`، أو (INSERT)
  جلسة هاتفية غير مرتبطة تطابق `phone` الصف الجديد.
- **`service_role` يتجاوز دائماً**.
- **مشرفو لوحة التحكم**: أي `authenticated` JWT موجود في `admin_users`
  (بمطابقة email أو uid) يُسمح له بالكتابة — جلسة supabase-js تُجدَّد
  تلقائياً فهي فعلياً دائمة المدة، **لا يحتاج Dashboard أي تعديل**.

### أوضاع الحارس — `app_config.users_write_guard`

| القيمة | السلوك |
|---|---|
| `off` | معطّل تماماً |
| `audit` | **يسمح** لكن يسجّل كل مخالفة في `guard_violations` |
| `enforce` | يرفض الكتابة بدون جلسة صالحة |

**الافتراضي حالياً: `audit`** — نراقب المخالفات قبل التفعيل الفعلي.

---

## 3) Phase 2 — RPCs للعمليات بين المستخدمين

الكتابات على حسابات **مستخدمين آخرين** (هدية تُضيف ماساً للمستلم مثلاً)
لا يمكن أن تمر بتوكن المرسل — فحوّلتها لدوال `SECURITY DEFINER` ذرّية في
`supabase_phase2_wallet_rpcs.sql`، كلها تتطلب جلسة صالحة (`app_request_uid()`):

| الدالة | الوظيفة | الحقول المسموحة |
|---|---|---|
| `bump_user_stat` | زيادة عدّاد | `total_gifts_received`, `total_gifts_sent`, `charm`, `wealth_exp`, `gems_exp` فقط |
| `adjust_user_wallet` | كوينز/ماس atomic | `coins`, `diamonds` — مع منع الرصيد السالب |
| `credit_user_diamonds` | ماس هدية/مكافأة | يوجّه: عضو وكالة → محفظة الوكالة + إجمالياتها المحسوبة من مجموع الأعضاء؛ غير عضو → `users.diamonds` |
| `set_user_field` | حقل تجميلي | `active_frame`, `active_bubble`, `active_entrance`, `active_avatar_frame`, `title`, `signature` |

### ما تم تحويله فعلياً في كود التطبيق

- عدّاد `total_gifts_received` للمستلم (هدية عادية + هدية حظ)
- fallback ماس الوكالة في `creditHostAgencyMemberDiamonds` → `credit_user_diamonds`
- مكافآت CP: كوينز الشريكين + خصم المرسل ( atomic — يمنع الرصيد السالب)
- أرباح الكأس لمالك الغرفة
- مكافآت التارجت: كوينز + ماس شخصي + `active_frame`

---

## 4) تغيير اسم المستخدم ورمز الدخول (PIN)

- **الاسم**: موجود أصلاً في `edit_profile_screen.dart` — تعديل الاسم
  والتوقيع يُحفظ عبر `updateUser` (يعمل مع التوكن تلقائياً).
- **رمز الدخول**: أُضيف قسم «تغيير رمز الدخول (PIN)» في شاشة تعديل
  الملف الشخصي — يفتح dialog بثلاث خانات (قديم/جديد/تأكيد) ويستدعي
  `change_login_pin` الذي **يتحقق من الرمز القديم سيرفرياً** قبل التحديث
  (الهاش في `login_pins` المقيد — لا يُقرأ من العميل).

---

## 5) ملفات SQL — الترتيب المطلوب تشغيله

```
1) supabase_master_setup.sql / supabase_migrations_all.sql  (الأساس — إن لم تُشغَّل)
2) supabase_auth_security_fix.sql    — login_otps/login_pins + unique indexes
3) supabase_agency_commission_fix.sql — عمولات الوكالة + cron
4) supabase_broadcasts_realtime.sql   — Realtime لجدول broadcasts
5) supabase_session_tokens.sql        — الجلسات + الحارس + change_login_pin
6) supabase_phase2_wallet_rpcs.sql    — RPCs المحفظة/الإحصائيات
```

> ملاحظة: `verify_login_otp`/`verify_login_pin`/`create_session` معرّفة
> في الملف 5 — لو شغّلت ملفاً قديماً فيه نسخ أقدم منها بعده، ستُستبدل.
> شغّل 5 و 6 **آخر شيء**.

---

## 6) ما تبقى — بصراحة

- **`guard_violations`**: راقب الجدول بعد أيام من التشغيل — كل صف =
  كتابة بين مستخدمين لم تُحوَّل بعد (شاشات الوكالة/الأدمن/المرتبات...).
  حوّلها لـ RPCs أو اقبلها، ثم غيّر `users_write_guard` إلى `'enforce'`.
- **الـ RPCs محمية بجلسة فقط**: أي مستخدم مسجّل يقدر نظرياً استدعاء
  `adjust_user_wallet` لأي uid. المنع الكامل = ربطها بمعاملة حقيقية
  (مثلاً `send_gift_atomic` ينفّذ الخصم+الإضافة+التسجيل في transaction واحد).
- **المستخدمون القدامى**: لا يملكون توكناً حتى أول login بعد التحديث —
  في وضع `audit` هذا يظهر كمخالفات، وكتاباتهم الذاتية ستُسجَّل
  ثم تختفي بعد إعادة الدخول.
- **`SELECT` على `users` ما زال عاماً** — أي حد يقرأ الملفات العامة.
  إخفاء البيانات الحساسة (رصيد/هاتف) يتطلب Views أو RLS SELECT أضيق —
  مهمة منفصلة.
- **ثغرة التسجيل بـ PIN بدون OTP**: `signInOrRegisterWithPhone` ينشئ
  حساباً لأي رقم دون إثبات ملكية الهاتف — يُنصح بإلزام OTP قبل أول تعيين PIN.
