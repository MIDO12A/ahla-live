import { useEffect, useMemo, useState } from 'react';
import { AlertTriangle, ChevronDown, ChevronUp, Code2, FileCode2, Search, ShieldAlert, ShieldCheck, Wrench } from 'lucide-react';
import { supabase } from '../lib/supabase';

type Severity = 'critical' | 'high' | 'medium' | 'low';
type Status = 'open' | 'fixed' | 'accepted';

interface Vulnerability {
  id: string;
  title: string;
  severity: Severity;
  area: string;
  file: string;
  code: string;
  impact: string;
  fix: string;
}

const SEVERITY_LABEL: Record<Severity, string> = {
  critical: 'حرجة',
  high: 'عالية',
  medium: 'متوسطة',
  low: 'منخفضة',
};

const SEVERITY_STYLE: Record<Severity, string> = {
  critical: 'bg-rose-500/15 text-rose-300 border-rose-500/30',
  high: 'bg-orange-500/15 text-orange-300 border-orange-500/30',
  medium: 'bg-amber-500/15 text-amber-300 border-amber-500/30',
  low: 'bg-cyan-500/15 text-cyan-300 border-cyan-500/30',
};

const STATUS_LABEL: Record<Status, string> = {
  open: 'مفتوحة',
  fixed: 'تم الإصلاح',
  accepted: 'مقبولة مؤقتاً',
};

const VULNERABILITIES: Vulnerability[] = [
  {
    id: 'SEC-001',
    title: 'قاعدة الكتابة العامة تسمح لأي مسجّل بتعديل أي مجموعة',
    severity: 'critical',
    area: 'Firestore Rules',
    file: 'firestore.rules:38-41',
    code: `match /{col}/{document} {
  allow read: if signedIn() || isCatalog(col);
  allow write: if isAdmin() || signedIn() || ...;
}`,
    impact: 'أي مستخدم مسجّل يستطيع الكتابة في أي مجموعة غير مذكورة صراحةً، بما فيها بيانات مالية وإدارية.',
    fix: 'اجعل القاعدة deny by default، واسمح فقط بالمجموعات المصرّح بها مع التحقق من الملكية أو isAdmin.',
  },
  {
    id: 'SEC-002',
    title: 'أي مستخدم يستطيع تحديث وثيقة أي مستخدم آخر',
    severity: 'critical',
    area: 'Firestore Rules',
    file: 'firestore.rules:47-51',
    code: `match /users/{uid} {
  allow read: if signedIn();
  allow update: if signedIn();
}`,
    impact: 'تعديل أرصدة وأدوار وحظر أي مستخدم عبر استدعاء Firestore مباشرة من العميل.',
    fix: `allow update: if signedIn() && request.auth.uid == uid
  && !request.resource.data.diff(resource.data).affectedKeys()
       .hasAny(['coins','diamonds','role','is_admin','banned']);`,
  },
  {
    id: 'SEC-003',
    title: 'محافظ العملات قابلة للتعديل من أي مستخدم',
    severity: 'critical',
    area: 'Firestore Rules',
    file: 'firestore.rules:67-71',
    code: `match /user_wallets/{uid} {
  allow read: if signedIn();
  allow create, update: if signedIn();
}`,
    impact: 'أي مستخدم مسجّل يعدّل محفظة أي مستخدم آخر ويرفع رصيده بلا قيود.',
    fix: 'قصر القراءة على المالك أو الإدارة، ومنع الكتابة من العميل؛ العمليات المالية عبر Cloud Function/RPC فقط.',
  },
  {
    id: 'SEC-004',
    title: 'بيانات الوكالات والعمولات مفتوحة للكتابة للمستخدمين',
    severity: 'critical',
    area: 'Firestore Rules',
    file: 'firestore.rules:116-123',
    code: `match /{col}/{id} {
  allow read, write: if signedIn() && (
    col == 'host_agencies' ||
    col.matches('host_agency_.*') ||
    col.matches('agency_.*') ||
    col.matches('agent_.*'));
}`,
    impact: 'تعديل نسب العمولات والأرصدة وسجلات السحب لكل الوكالات من أي حساب مسجّل.',
    fix: 'الكتابة للإدارة فقط، وقراءة العضو على وكالته فقط. المالية عبر دوال خادم مع تحقق ملكية الوكالة.',
  },
  {
    id: 'SEC-005',
    title: 'إعدادات Supabase تسمح بكتابة anon على host_agencies',
    severity: 'critical',
    area: 'Supabase RLS',
    file: 'Supabase /host_agencies',
    code: `PATCH /rest/v1/host_agencies?id=eq.<agency_id>
Body: { "commission_rate": 20 }
=> 200 OK (تم التحقق فعلياً بمفتاح anon)`,
    impact: 'أي شخص يملك مفتاح anon (منشور داخل التطبيق) يستطيع تغيير عمولة أي وكالة أو تعطيلها.',
    fix: 'تفعيل RLS على host_agencies و host_agency_members و agency_*، ومنع anon من UPDATE/DELETE، مع سياسات عضوية/إدارة.',
  },
  {
    id: 'SEC-006',
    title: 'مفتاح Cloudinary السري مضمّن داخل كود لوحة التحكم',
    severity: 'critical',
    area: 'Secrets',
    file: 'admincore-dashboard/src/lib/storage.ts:26-27',
    code: `cloudName: 'dl30muiuc',
apiKey: '<hardcoded>',
apiSecret: '<hardcoded>',
uploadPreset: 'zero_app'`,
    impact: 'تسريب مفتاح API/Secret يسمح بحذف أو رفع أو استهلاك حصة الحساب بالكامل.',
    fix: 'ألغِ المفاتيح الحالية وأنشئ غيرها، وانقل الرفع Signed إلى خادم/Cloud Function، واستخدم Unsigned preset للعميل فقط.',
  },
  {
    id: 'SEC-007',
    title: 'توكن Supabase شخصي مكشوف داخل ملف مؤقت',
    severity: 'critical',
    area: 'Secrets',
    file: 'tmp_check_rpc.js',
    code: `Authorization: Bearer sbp_<REDACTED>
// التوكن غير صالح حالياً (401) لكنه مكشوف في مساحة العمل`,
    impact: 'أي توكن PAT مسرّب يمنح وصولاً إدارياً كاملاً لقاعدة البيانات إذا كان صالحاً.',
    fix: 'أبطل التوكن من Supabase Dashboard، احذف الملف، وأضف tmp_* إلى .gitignore (موجود) مع فحص سجل Git.',
  },
  {
    id: 'SEC-008',
    title: 'مفتاح خدمة Firebase موجود على القرص',
    severity: 'high',
    area: 'Secrets',
    file: 'backend/serviceAccountKey.json',
    code: `{
  "type": "service_account",
  "project_id": "...",
  "private_key": "-----BEGIN PRIVATE KEY-----..."
}`,
    impact: 'المفتاح غير متتبع في Git لكنه موجود على الجهاز؛ أي نسخ احتياطي أو مشاركة للمجلد تسرّبه.',
    fix: 'احذف المفتاح من القرص أو خزّنه في Secret Manager، أنشئ مفتاحاً جديداً، وأبطل القديم.',
  },
  {
    id: 'SEC-009',
    title: 'استبدال رصيد السحب يتم من العميل (fallback)',
    severity: 'high',
    area: 'Flutter / Agency',
    file: 'lib/features/host_agency/data/agency_repository.dart',
    code: `await _supabase.from('host_agency_members')
  .update({'diamonds_balance': newBalance})
  .eq('id', memberId);`,
    impact: 'عميل معدّل يستدعي Supabase مباشرة ويصرف أكثر من التارجت الشهري أو يعدّل رصيد عضو آخر.',
    fix: 'احذف أي كتابة مالية مباشرة من Flutter، واعتمد RPC SECURITY DEFINER مع تحقق uid + التارجت + القفل الذري.',
  },
  {
    id: 'SEC-010',
    title: 'سقف السحب غير مطبق على الخادم بعد',
    severity: 'high',
    area: 'Database',
    file: 'supabase/migrations/20261108_agency_withdrawal_monthly_cap.sql',
    code: `-- migration جاهزة لكن غير مطبقة
LEAST(diamonds_available, diamonds_earned_monthly)`,
    impact: 'الواجهة تعرض min(balance, monthly) بينما الخادم ما زال يسمح بالرصيد الكامل، لذا يمكن تجاوز السقف.',
    fix: 'طبّق الـ migration عبر SQL Editor أو Management API، ثم اختبر RPC السحب بمستخدم owner ومضيف.',
  },
  {
    id: 'SEC-011',
    title: 'إشعارات مزيفة من أي مستخدم',
    severity: 'high',
    area: 'Firestore Rules',
    file: 'firestore.rules:74-77',
    code: `match /notifications/{id} {
  allow create: if signedIn() || isAdmin();
}`,
    impact: 'إرسال إشعارات تصيّد أو رسائل إدارية مزيفة باسم التطبيق أو مستخدمين آخرين.',
    fix: 'منع الإنشاء من العميل، والسماح به عبر خادم فقط مع التحقق من المرسل ونوع الإشعار.',
  },
  {
    id: 'SEC-012',
    title: 'ملفات تعريف المستخدمين قابلة للتعديل من الجميع',
    severity: 'high',
    area: 'Firestore Rules',
    file: 'firestore.rules:61-64',
    code: `match /profiles/{uid} {
  allow read: if signedIn();
  allow write: if signedIn();
}`,
    impact: 'تغيير اسم/صورة/بايو أي مستخدم وانتحال شخصيته.',
    fix: 'allow write: if signedIn() && request.auth.uid == uid; مع حماية الحقول الحساسة.',
  },
  {
    id: 'SEC-013',
    title: 'الهدايا والرسائل والغرف قابلة للتلاعب',
    severity: 'high',
    area: 'Firestore Rules',
    file: 'firestore.rules:79-100',
    code: `match /sent_gifts/{id} { allow read, write: if signedIn(); }
match /room_messages/{id} { allow read, write: if signedIn(); }
match /rooms/{id} { allow write: if signedIn(); }`,
    impact: 'إرسال هدايا بدون خصم رصيد، حذف رسائل، أو تعديل غرف الآخرين.',
    fix: 'الهدايا والرسائل تمر عبر خادم يخصم الرصيد ويكتب السجل؛ الكتابة على الغرف للمالك/الإدارة فقط.',
  },
  {
    id: 'SEC-014',
    title: 'مكافآت المستخدمين يمكن إنشاؤها من العميل',
    severity: 'high',
    area: 'Firestore Rules',
    file: 'firestore.rules:109-113',
    code: `match /user_rewards/{id} {
  allow read: if signedIn() && request.auth.uid == resource.data.user_uid;
  allow create: if signedIn();
}`,
    impact: 'إنشاء سجل مكافأة لنفس المستخدم ثم المطالبة بها، أو تلويث سجل التوزيع.',
    fix: 'allow create: if isAdmin() فقط، أو عبر Cloud Function تتحقق من استحقاق المكافأة.',
  },
  {
    id: 'SEC-015',
    title: 'أول مسجّل يصبح أدمن تلقائياً',
    severity: 'high',
    area: 'Auth Bootstrap',
    file: 'firestore.rules:129-138',
    code: `match /admin_users/{uid} {
  allow create: if signedIn() &&
    !exists(/databases/$(database)/documents/admin_users/_config);
}`,
    impact: 'إذا حُذف ختم _config أو حدث سباق أثناء الإعداد، يستطيع أي مستخدم ترقية نفسه إلى أدمن.',
    fix: 'أزل bootstrap من قواعد العميل، وأنشئ أول أدمن عبر Admin SDK أو سكربت seed بمفاتيح خادم.',
  },
  {
    id: 'SEC-016',
    title: 'قراءة قائمة المشرفين متاحة لكل مسجّل',
    severity: 'medium',
    area: 'Firestore Rules',
    file: 'firestore.rules:129-137',
    code: `match /admin_users/{uid} { allow read: if signedIn(); }
match /admin_users/_config { allow read: if signedIn(); }`,
    impact: 'كشف هويات المشرفين وتسهيل استهدافهم بهندسة اجتماعية.',
    fix: 'اجعل القراءة isAdmin فقط، وبيانات الأدمن العامة تُعرض عبر view منفصل عند الحاجة.',
  },
  {
    id: 'SEC-017',
    title: 'بيانات العلاقات CP مفتوحة للكتابة',
    severity: 'medium',
    area: 'Firestore Rules',
    file: 'firestore.rules:102-105',
    code: `match /cp_couples/{id} { allow read, write: if signedIn(); }
match /cp_requests/{id} { allow read, write: if signedIn(); }
match /cp_gift_logs/{id} { allow read, write: if signedIn(); }`,
    impact: 'إنشاء/فسخ علاقات أو تزوير سجل هدايا CP دون موافقة الطرف الآخر أو خصم رصيد.',
    fix: 'قصر الكتابة على أطراف العلاقة، وتمرير تغيير الحالة عبر دالة خادم تتحقق من الطلب والموافقة.',
  },
  {
    id: 'SEC-018',
    title: 'مواضع حساسة تعتمد على تحقق العميل فقط',
    severity: 'medium',
    area: 'Flutter',
    file: 'lib/screens/wallet/wallet_main_screen.dart',
    code: `final cap = member.diamondsExchangeable;
final amount = value.clamp(0, cap);`,
    impact: 'أي تحقق في الواجهة يمكن تجاوزه باستدعاء REST/RPC مباشرة؛ الواجهة ليست حداً أمنياً.',
    fix: 'أعد نفس القيود داخل RPC/Trigger على الخادم، واجعل الواجهة للعرض فقط.',
  },
  {
    id: 'SEC-019',
    title: 'بيانات users.agency_id غير متزامنة (سلامة بيانات)',
    severity: 'medium',
    area: 'Data Integrity',
    file: 'users / host_agencies / host_agency_members',
    code: `users.agency_id = null
users.is_host_agent = false
host_agency_members.role = 'owner'
host_agencies.owner_uid = '<uid>'`,
    impact: 'المالك يظهر بلا وكالة في صفحة المستخدمين، وتفشل الفلاتر والتقارير المعتمدة على users.agency_id.',
    fix: 'Trigger على host_agencies/host_agency_members يزامن users، مع backfill لمرة واحدة (لوحة التحكم تعرض overlay مؤقتاً).',
  },
  {
    id: 'SEC-020',
    title: 'بلاغات الأخطاء قابلة للإنشاء من أي زائر',
    severity: 'low',
    area: 'Firestore Rules',
    file: 'firestore.rules:140-144',
    code: `match /bug_reports/{id} {
  allow create: if signedIn();
  allow read, delete: if isAdmin();
}`,
    impact: 'إغراق سجل الأخطاء ببلاغات وهمية واستهلاك مساحة/مراجعة.',
    fix: 'أضف rate limit على مستوى Cloud Function، وتحقق من حجم ونوع الحقول قبل الحفظ.',
  },
  {
    id: 'SEC-021',
    title: 'Trigger تحديث الوكالة يشير إلى جدول غير موجود ويعطّل تحديث المستخدمين',
    severity: 'critical',
    area: 'Database Trigger',
    file: 'public.sync_agency_diamonds() / trigger_sync_agency_diamonds on users',
    code: `UPDATE public.agencies
SET total_diamonds = v_total_diamonds,
    monthly_diamonds = v_total_diamonds
WHERE id = v_agency_id;`,
    impact: 'أي UPDATE على users (رصيد، دور، بيانات) يفشل بـ relation "public.agencies" does not exist، ما يعطّل الحفظ والتعديل.',
    fix: 'تم استبدال الجسم باستدعاء agency_recalc_totals(text) للوكالة القديمة والجديدة، وإضافة SET search_path وRETURN COALESCE(NEW, OLD).',
  },
];

const STORAGE_KEY = 'security_audit_status_v1';

export default function SecurityAudit() {
  const [search, setSearch] = useState('');
  const [severity, setSeverity] = useState<Severity | 'all'>('all');
  const [statusFilter, setStatusFilter] = useState<Status | 'all'>('all');
  const [openId, setOpenId] = useState<string | null>('SEC-001');
  const [statuses, setStatuses] = useState<Record<string, Status>>(() => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      return raw ? JSON.parse(raw) : {};
    } catch {
      return {};
    }
  });

  useEffect(() => {
    let cancelled = false;
    Promise.resolve(
      supabase.from('app_config').select('value').eq('key', 'security_audit_status').maybeSingle()
    ).then(({ data }) => {
      if (cancelled || !data?.value) return;
      const remote = typeof data.value === 'string' ? JSON.parse(data.value) : data.value;
      if (remote && typeof remote === 'object') {
        setStatuses(prev => ({ ...prev, ...remote }));
      }
    }, () => {});
    return () => { cancelled = true; };
  }, []);

  const setStatus = (id: string, status: Status) => {
    setStatuses(prev => {
      const next = { ...prev, [id]: status };
      try { localStorage.setItem(STORAGE_KEY, JSON.stringify(next)); } catch {}
      void Promise.resolve(
        supabase.from('app_config').upsert({ key: 'security_audit_status', value: next }, { onConflict: 'key' })
      ).then(() => {}, () => {});
      return next;
    });
  };

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return VULNERABILITIES.filter(v => {
      if (severity !== 'all' && v.severity !== severity) return false;
      const currentStatus = statuses[v.id] || 'open';
      if (statusFilter !== 'all' && currentStatus !== statusFilter) return false;
      if (!q) return true;
      return [v.id, v.title, v.area, v.file, v.impact, v.fix, v.code]
        .join(' ')
        .toLowerCase()
        .includes(q);
    });
  }, [search, severity, statusFilter, statuses]);

  const counts = useMemo(() => {
    const base = { critical: 0, high: 0, medium: 0, low: 0 };
    for (const v of VULNERABILITIES) base[v.severity] += 1;
    return base;
  }, []);

  const fixedCount = useMemo(
    () => VULNERABILITIES.filter(v => (statuses[v.id] || 'open') === 'fixed').length,
    [statuses]
  );

  return (
    <div className="space-y-5">
      <div className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h2 className="text-white text-lg font-bold flex items-center gap-2">
            <ShieldAlert className="w-5 h-5 text-rose-400" />
            سجل ثغرات التطبيق
          </h2>
          <p className="text-slate-500 text-xs mt-1">
            {VULNERABILITIES.length} ثغرة موثقة — {fixedCount} تم إصلاحها — راجع الكود وطبّق الحل ثم علّم الحالة.
          </p>
        </div>
        <div className="flex items-center gap-2 text-[11px] text-slate-400 bg-[#141417] border border-white/10 rounded-xl px-3 py-2">
          <ShieldCheck className="w-4 h-4 text-emerald-400" />
          الحالة محفوظة في إعدادات اللوحة (app_config) مع نسخة محلية
        </div>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {(['critical', 'high', 'medium', 'low'] as Severity[]).map(sev => (
          <button
            key={sev}
            onClick={() => setSeverity(severity === sev ? 'all' : sev)}
            className={`text-left rounded-xl border p-3 transition-all ${SEVERITY_STYLE[sev]} ${severity === sev ? 'ring-2 ring-white/20' : 'hover:brightness-110'}`}
          >
            <div className="text-[10px] uppercase tracking-wide opacity-80">{SEVERITY_LABEL[sev]}</div>
            <div className="text-xl font-bold mt-1">{counts[sev]}</div>
          </button>
        ))}
      </div>

      <div className="flex flex-wrap gap-2 items-center">
        <div className="relative flex-1 min-w-[220px]">
          <Search className="w-4 h-4 text-slate-500 absolute left-3 top-1/2 -translate-y-1/2" />
          <input
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder="ابحث بالاسم، الملف، الكود، أو الحل..."
            className="w-full bg-[#141417] border border-white/10 rounded-xl py-2 pl-9 pr-3 text-xs text-white placeholder:text-slate-600 focus:outline-none focus:border-indigo-500/50"
          />
        </div>
        <select
          value={severity}
          onChange={e => setSeverity(e.target.value as Severity | 'all')}
          className="bg-[#141417] border border-white/10 rounded-xl py-2 px-3 text-xs text-slate-300 focus:outline-none"
        >
          <option value="all">كل الخطورة</option>
          <option value="critical">حرجة</option>
          <option value="high">عالية</option>
          <option value="medium">متوسطة</option>
          <option value="low">منخفضة</option>
        </select>
        <select
          value={statusFilter}
          onChange={e => setStatusFilter(e.target.value as Status | 'all')}
          className="bg-[#141417] border border-white/10 rounded-xl py-2 px-3 text-xs text-slate-300 focus:outline-none"
        >
          <option value="all">كل الحالات</option>
          <option value="open">مفتوحة</option>
          <option value="fixed">تم الإصلاح</option>
          <option value="accepted">مقبولة مؤقتاً</option>
        </select>
      </div>

      <div className="space-y-3">
        {filtered.length === 0 && (
          <div className="text-center text-slate-500 text-xs py-10 bg-[#141417] border border-white/10 rounded-xl">
            لا توجد ثغرات مطابقة للفلتر الحالي.
          </div>
        )}
        {filtered.map(v => {
          const currentStatus = statuses[v.id] || 'open';
          const isOpen = openId === v.id;
          return (
            <div key={v.id} className="bg-[#141417] border border-white/10 rounded-xl overflow-hidden">
              <div className="p-4 flex items-start gap-3 flex-wrap">
                <div className={`mt-0.5 shrink-0 rounded-lg border px-2 py-1 text-[10px] font-bold ${SEVERITY_STYLE[v.severity]}`}>
                  {SEVERITY_LABEL[v.severity]}
                </div>
                <div className="flex-1 min-w-[220px]">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="text-[10px] font-mono text-slate-500">{v.id}</span>
                    <span className="text-xs text-slate-500">{v.area}</span>
                    <span className={`text-[10px] px-2 py-0.5 rounded-full border ${
                      currentStatus === 'fixed'
                        ? 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30'
                        : currentStatus === 'accepted'
                          ? 'bg-amber-500/15 text-amber-300 border-amber-500/30'
                          : 'bg-rose-500/15 text-rose-300 border-rose-500/30'
                    }`}>
                      {STATUS_LABEL[currentStatus]}
                    </span>
                  </div>
                  <h3 className="text-sm font-bold text-white mt-1">{v.title}</h3>
                  <div className="flex items-center gap-1.5 text-[10px] text-slate-500 mt-1 font-mono">
                    <FileCode2 className="w-3 h-3" />
                    {v.file}
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <select
                    value={currentStatus}
                    onChange={e => setStatus(v.id, e.target.value as Status)}
                    className="bg-[#0f0f11] border border-white/10 rounded-lg py-1.5 px-2 text-[10px] text-slate-300 focus:outline-none"
                  >
                    <option value="open">مفتوحة</option>
                    <option value="fixed">تم الإصلاح</option>
                    <option value="accepted">مقبولة مؤقتاً</option>
                  </select>
                  <button
                    onClick={() => setOpenId(isOpen ? null : v.id)}
                    className="p-1.5 rounded-lg bg-white/5 hover:bg-white/10 text-slate-400"
                    aria-label="تفاصيل الثغرة"
                  >
                    {isOpen ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
                  </button>
                </div>
              </div>

              {isOpen && (
                <div className="border-t border-white/5 p-4 space-y-4 bg-[#101012]">
                  <div>
                    <div className="flex items-center gap-1.5 text-[11px] font-bold text-rose-300 mb-1.5">
                      <AlertTriangle className="w-3.5 h-3.5" />
                      التأثير
                    </div>
                    <p className="text-xs text-slate-300 leading-relaxed">{v.impact}</p>
                  </div>
                  <div>
                    <div className="flex items-center gap-1.5 text-[11px] font-bold text-cyan-300 mb-1.5">
                      <Code2 className="w-3.5 h-3.5" />
                      الكود الحالي
                    </div>
                    <pre className="bg-[#0a0a0c] border border-white/10 rounded-lg p-3 text-[10px] leading-relaxed text-slate-300 overflow-x-auto whitespace-pre-wrap font-mono">
                      {v.code}
                    </pre>
                  </div>
                  <div>
                    <div className="flex items-center gap-1.5 text-[11px] font-bold text-emerald-300 mb-1.5">
                      <Wrench className="w-3.5 h-3.5" />
                      الحل المقترح
                    </div>
                    <p className="text-xs text-slate-300 leading-relaxed">{v.fix}</p>
                  </div>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
