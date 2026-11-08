# نظام الوكالات — شرح كامل (Arabic)

> مرجع تشغيلي وتقني لنظام الوكالات (Host Agency) في التطبيق ولوحة التحكم.
> يعتمد على قاعدة Supabase (Postgres) + تطبيق Flutter + لوحة تحكم React.

---

## 1. نظرة عامة

نظام الوكالات يتيح لمالك الوكالة (Agent/Owner) إدارة مجموعة من المضيفين (Hosts)، ومتابعة إنتاجهم من الألماس، وصرف رواتبهم ومكافآتهم، وتحقيق عمولة الوكالة.

المبادئ الأساسية:

- **فصل المحافظ**: محفظة المضيف/الوكالة في `host_agency_members` مستقلة تماماً عن المحفظة الشخصية `users.diamonds` ومحفظة وكيل الشحن `agency_wallets`.
- **العمولة لا تُصرف فوراً**: تُحتسب كـ **استحقاق معلّق** (pending) وتُصدر حسب **دورة إصدار** يحددها الأدمن.
- **كل حركة مالية مسجلة** في دفتر `agency_diamond_ledger` مع `idempotency_key` لمنع التكرار.
- **المصدر الوحيد للنسب**: إعدادات لوحة التحكم العامة (`commission_settings` + `app_config.agency_financial_policy`)، وليس لكل وكالة على حدة.

---

## 2. الكيانات والجداول

### `host_agencies` — الوكالة
| الحقل | الوصف |
|---|---|
| `id` | معرف الوكالة (TEXT) |
| `name` | اسم الوكالة |
| `agency_code` | رقم/كود الوكالة |
| `owner_uid` / `owner_id` | مالك الوكالة |
| `level`, `monthly_exp` | المستوى والخبرة |
| `total_diamonds_monthly` | إجمالي إنتاج الشهر (من الأعضاء) |
| `total_diamonds_cumulative` | إجمالي الإنتاج التراكمي |
| `pending_commission_diamonds` | **عمولة معلّقة بانتظار الإصدار** |
| `released_commission_diamonds` | إجمالي العمولة التي أُصدرت تاريخياً |
| `next_commission_release_at` | موعد الإصدار القادم |
| `last_commission_release_at` | آخر إصدار |

### `host_agency_members` — عضو/مضيف في الوكالة
| الحقل | الوصف |
|---|---|
| `agency_id`, `host_uid`, `user_id`, `role` | الربط والدور (`owner` / `supervisor` / `host`) |
| `status` | `active` / `kicked` ... |
| `diamonds_balance` / `diamonds_available` | رصيد محفظة الوكالة |
| `diamonds_earned_monthly` | إنتاج الشهر (سقف السحب/التبادل) |
| `diamonds_earned_cumulative` | الإنتاج التراكمي |
| `diamonds` | نسخة متوافقة من الرصيد |

### `agency_diamond_ledger` — دفتر الحركات
`txn_type` يشمل: `gift`، `gift_commission`، `commission_accrual`، `commission_release`، `exchange`، `withdrawal`، `adjustment` ...
مع `direction` (1 دخل / -1 خرج)، `amount`، `balance_after`، `note`، `idempotency_key`.

### `agency_withdrawal_requests` — طلبات السحب
حالة الطلب: `pending` → `approved` / `rejected`. عند الإنشاء يُجمَّد المبلغ من رصيد العضو/المالك.

### `agency_wallets` — محفظة وكيل الشحن
منفصلة تماماً ولا تُلمس من تدفقات المضيف.

### جداول إعدادات
- `app_config` (JSONB): `agency_financial_policy`، `agency_commission_cycle`، `agency_commission_period`، `host_milestones_list`.
- `commission_settings`: `agency_rate`، `coins_per_usd`، `host_rate`، ... (قيم رقمية).

---

## 3. مسار الهدية (Gift → Host)

عند إرسال هدية لمضيف داخل غرفة:

1. يُستدعى `agency_credit_gift_diamonds(...)`.
2. يفوّض إلى `agency_credit_host_target_diamonds(host_uid, diamonds, rate, idem, source)`.
3. إذا كان المضيف **عضو وكالة نشط**:
   - يُضاف الألماس إلى محفظته: `diamonds_balance` + `diamonds_available` + `diamonds`، وكذلك `diamonds_earned_monthly` و `diamonds_earned_cumulative`.
   - تُسجَّل الحركة في `agency_diamond_ledger` بنوع `gift`.
   - تُحتسب **عمولة المالك** = `ROUND(diamonds × rate)` وتُضاف إلى `host_agencies.pending_commission_diamonds` (وليس لمحفظة المالك مباشرة).
4. إذا لم يكن عضواً: تُعاد `not_member`، ويتولى التطبيق المسار الاحتياطي (المحفظة الشخصية).

> ملاحظة: لا تُصرف عمولة المالك فوراً بعد الآن؛ تبقى معلّقة حتى دورة الإصدار.

---

## 4. حساب العمولة ودورة الإصدار

### النسبة
- المصدر: `DynamicConfigService.agencyRatePercentage` (افتراضي 20%).
- قاعدة التطبيع: إذا كانت القيمة > 1 تُقسم على 100 (20 → 0.20).
- `commissionDiamonds = totalDiamonds × rate`
- `USD = commissionDiamonds ÷ coins_per_usd` (افتراضي 10,000 💎 = 1$).

### دورة الإصدار (`app_config.agency_commission_cycle`)
```json
{
  "period": "monthly",       // daily | weekly | monthly
  "week_start": 1,           // 1=الاثنين .. 7=الأحد
  "release_day": 1,          // أسبوعياً 1..7 — شهرياً 1..28
  "release_time": "00:00",   // HH:MM
  "timezone": "Asia/Riyadh",
  "auto_release": false
}
```

### الدوال
| الدالة | الوظيفة |
|---|---|
| `agency_commission_cycle_config()` | قراءة الدورة مع القيم الافتراضية |
| `agency_compute_next_release(from)` | حساب موعد الإصدار القادم |
| `agency_accrue_commission(agency_id, diamonds, note)` | إضافة استحقاق معلّق (بدون صرف) |
| `agency_release_commission(agency_id, force, note)` | إصدار المعلّق إلى محفظة المالك |
| `agency_release_due_commissions()` | إصدار كل المستحق (يحترم `auto_release`) |
| `agency_commission_release_info(agency_id)` | `pending`, `released`, `next_release_at`, `cycle` |

### سلوك الإصدار
- يضيف المبلغ إلى `diamonds` / `diamonds_balance` / `diamonds_available` لصف المالك في `host_agency_members`.
- **لا يزيد** `diamonds_earned_cumulative` (لتجنّب ازدواج الاحتساب في إجماليات الوكالة).
- يزيد `released_commission_diamonds` ويصفّر `pending_commission_diamonds` ويحدّث `next_commission_release_at`.
- يسجّل حركة `commission_release` في الدفتر.

### أين تُحتسب؟ (مصدر واحد فقط)
- **العمولة تُحتسب على الإنتاج فقط** (ألماس الهدايا الوارد للمضيف) — عبر `agency_credit_host_target_diamonds` (المسار الرئيسي) والمسار الاحتياطي في `SupabaseDataService.creditHostAgencyMemberDiamonds`.
- **لا تُحتسب أي عمولة إضافية عند تحقق التارجت** — تم إزالة احتساب `target_diamonds × rate` من `AgencyTargetEvaluator._awardTarget` لأنه كان يضاعف العمولة (الإنتاج + التارجت).
- مكافآت التارجت من نوع `diamonds` تُصرف عبر RPC `agency_credit_member_reward` وتُسجَّل في الدفتر بنوع `target_reward` (بدون احتساب عمولة عليها).

---

## 5. راتب المضيف والتارجت (Milestones)

- تُعرَّف المراحل في `app_config.host_milestones_list` وتُدار من لوحة التحكم.
- لكل مرحلة: `target_diamonds`، `target_days`، `target_hours`، `reward_value`.
- يُقيَّم المضيف في `AgencyTargetEvaluator` حسب إنتاجه (`commissionDiamonds`) وساعاته/أيامه.
- عند تحقق أعلى مرحلة:
  - يُمنح **راتب المضيف** (`reward_value`) في محفظة العضو.
  - **لا تُحتسب عمولة وكالة إضافية على التارجت** — العمولة تُحتسب مسبقاً على الإنتاج الفعلي فقط (20% من ألماس الهدايا).
  - مكافآت نوع `diamonds` تُصرف عبر `agency_credit_member_reward` وتُسجَّل في الدفتر.
- في حال "فك التارجت" (unpack) يُخصم 40% من راتب المضيف (يحصل على 60%).

---

## 6. التبادل (Exchange) والحد الشهري

### المضيف — `agency_exchange_diamonds_v2`
- يحوّل ألماس محفظة الوكالة إلى كوينز شخصية.
- السقف الشهري = `diamonds_earned_monthly` (أو حد أقصى أعلى إن وُجد).
- يخصم من `diamonds_balance`/`diamonds_available` ويضيف كوينز إلى `users.coins`.
- يسجّل `exchange` في الدفتر.

### المالك — `agency_owner_exchange_diamonds_v2`
- نفس المنطق لكن من صف المالك، مع سقف شهري خاص (`20261107_agency_exchange_monthly_cap.sql`).

> **قابل للسحب** = `min(balance, monthly)`. هذا ما يظهر في لوحة التحكم.

---

## 7. السحب (Withdrawal)

1. **إنشاء الطلب**: `agency_request_withdrawal_v2` (مضيف) أو `agency_owner_request_withdrawal_v2` (مالك).
   - يُجمَّد المبلغ من `diamonds_available` (ينقص) مع بقائه في `diamonds_balance`.
   - يُنشأ صف في `agency_withdrawal_requests` بحالة `pending`.
2. **الاعتماد**: `agency_approve_withdrawal` — يخصم المبلغ نهائياً من الرصيد ويسجّل الحركة.
3. **الرفض**: `agency_reject_withdrawal` — يعيد المبلغ إلى `diamonds_available`.
4. السقف الشهري مفعّل عبر `20261108_agency_withdrawal_monthly_cap.sql`.

---

## 8. صرف رواتب المضيفين (Disbursement)

- من شاشة الوكالة: `_CommissionDisbursementCard` → `disburseSalary`.
- **ليس** عمولة المالك؛ بل **صرف راتب مضيف** من محفظة العضو في الوكالة إلى محفظته الشخصية `users.diamonds`.
- يخصم من `host_agency_members` ويضيف إلى `users.diamonds` للمضيف المستهدف.

---

## 9. لوحة التحكم (Admin)

### صفحة الوكالات — تبويب العمولة (`CommissionTab`)
- تعديل النسب: `coins_per_usd`, `host_rate`, `agency_rate`, `host_target_exchange_rate`, ...
- **إعدادات دورة الإصدار**: period / week_start / release_day / release_time / timezone / auto_release.
- **جدول الوكالات**: المعلّق، المُصدر، موعد الإصدار القادم، زر «إصدار الآن».
- زر «إصدار المستحق الآن»: يصدر كل وكالة حلّ موعدها.

### صفحة المستخدمين (`Users.tsx`)
- عمود **Dia**: يعرض `max(users.diamonds, محفظة الوكالة)` مع تفصيل «شخصي • وكالة».
- عمود **Agency Dia**: يعرض إجمالي محفظة الوكالة مع «قابل للسحب • شهر».

> سبب وجود صفر في `Dia` سابقاً: أرباح المضيفين تُخزَّن في `host_agency_members` وليس `users.diamonds`.

---

## 10. التطبيق (Flutter)

| الشاشة/الملف | الوظيفة |
|---|---|
| `agency_owner_screen.dart` | لوحة المالك: الأعضاء، الراتب، العمولة المعلّقة والموعد القادم |
| `agency_dashboard_screen.dart` | لوحة عامة + بطاقة صرف رواتب المضيفين |
| `agency_disbursement_screen.dart` | تبويبات الصرف |
| `agency_host_screen.dart` | شاشة المضيف |
| `commission_period_dialog.dart` | إعداد دورة الإصدار (Super Admin) |
| `agency_repository.dart` | `getCommissionReleaseInfo` / `releaseCommission` / `releaseDueCommissions` |
| `agency_target_evaluator.dart` | تقييم التارجت واحتساب العمولة المعلّقة |
| `dynamic_config_service.dart` | قراءة الدورة والنسب + signature للتحديث الفوري |

---

## 11. مخطط التدفق (نصي)

```
هدية → agency_credit_gift_diamonds
        └→ agency_credit_host_target_diamonds
             ├→ محفظة المضيف (balance/available/monthly/cumulative) + ledger(gift)
             └→ host_agencies.pending_commission_diamonds += ROUND(diamonds × rate)

دورة الإصدار (auto أو يدوي)
   └→ agency_release_commission
        ├→ محفظة المالك (balance/available)  [بدون cumulative]
        ├→ released_commission_diamonds += pending
        ├→ pending = 0 + next_release محسوب
        └→ ledger(commission_release)

سحب: request (تجميد) → approve (خصم نهائي) / reject (إرجاع)
تبادل: exchange (سقف شهري) → كوينز شخصية
راتب مضيف: disburseSalary → users.diamonds للمضيف
```

---

## 12. ملاحظات تشغيلية

- **ترتيب الهجرة**: طبّق `20261110_agency_commission_release_cycle.sql` بعد `20261109_agency_get_dashboard.sql`.
- **العمولة التاريخية**: ما صُرف قبل تفعيل الدورة موجود بالفعل في محافظ المالكين، ولا يُعاد ترحيله إلى `pending`.
- **`auto_release=false`**: الإصدار يدوي من لوحة التحكم. عند `true` يعمل `agency_release_due_commissions`.
- **المنطقة الزمنية**: تُحسب المواعيد بتوقيت `timezone` المحدد ثم تُخزَّن UTC.
- **عدم تعديل `diamonds_earned_cumulative` عند الإصدار** مقصود لمنع تضاعف إجماليات الوكالة.
- **المصدر الوحيد للنسبة** هو الإعداد العام؛ لا تعتمد على `host_agencies.commission_rate`.
