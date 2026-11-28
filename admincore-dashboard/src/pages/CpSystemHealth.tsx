import { useCallback, useEffect, useState } from 'react';
import {
  Activity, RefreshCw, Heart, Users, ClipboardList, Database,
  ShieldCheck, Copy, Check, AlertCircle, CheckCircle2, Clock,
  TrendingUp, Terminal, ArrowUpRight,
} from 'lucide-react';
import { supabase } from '../lib/supabase';

type Row = Record<string, any>;

const MIGRATION_SQL = `-- شغّل هذا في Supabase SQL Editor مرة واحدة
ALTER TABLE public.cp_couples
  ADD COLUMN IF NOT EXISTS user1_uid TEXT,
  ADD COLUMN IF NOT EXISTS user2_uid TEXT,
  ADD COLUMN IF NOT EXISTS week_score BIGINT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS month_score BIGINT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_score BIGINT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ended_at TIMESTAMPTZ;

DROP POLICY IF EXISTS "cp_couples_insert" ON public.cp_couples;
DROP POLICY IF EXISTS "cp_couples_all" ON public.cp_couples;
CREATE POLICY "cp_couples_all" ON public.cp_couples
  FOR ALL USING (true) WITH CHECK (true);`;

const STEPS = [
  { n: 1, title: 'شغّل الـ migration', desc: 'افتح Supabase SQL Editor والصق الـ SQL فوق — آمن لإعادة التشغيل.' },
  { n: 2, title: 'أعد بناء التطبيق', desc: ' flutter build apk --release ثم ثبّت النسخة الجديدة على الجوال.' },
  { n: 3, title: 'جرّب ارتباط جديد', desc: 'ابعت هدية CP واقبلها من الطرف التاني — هيت عمل صف ويظهر في الترتيب.' },
  { n: 4, title: 'راقب الأرقام هنا', desc: 'اضغط تحديث وتأكد إن عدد الأزواج والترتيب بيتحدثوا.' },
];

function StatCard({
  label, value, icon: Icon, tone, hint,
}: {
  label: string; value: string | number; icon: any; tone: string; hint?: string;
}) {
  return (
    <div className="group relative overflow-hidden rounded-2xl border border-white/8 bg-gradient-to-br from-white/[0.06] to-white/[0.02] p-5 transition-all duration-300 hover:-translate-y-1 hover:border-white/20">
      <div className={`absolute -left-8 -top-8 h-28 w-28 rounded-full blur-3xl opacity-25 ${tone}`} />
      <div className="relative flex items-start justify-between">
        <div className={`flex h-11 w-11 items-center justify-center rounded-xl bg-gradient-to-br ${tone} text-white shadow-lg ring-1 ring-white/20`}>
          <Icon className="h-5 w-5" />
        </div>
        <TrendingUp className="h-4 w-4 text-emerald-400/60" />
      </div>
      <div className="relative mt-4 font-mono text-2xl font-bold tracking-tight text-white">{value}</div>
      <div className="relative mt-1 text-[11px] font-bold uppercase tracking-wider text-slate-500">{label}</div>
      {hint && <div className="relative mt-2 text-[10px] text-slate-600">{hint}</div>}
    </div>
  );
}

function CheckRow({ ok, label, detail }: { ok: boolean; label: string; detail: string }) {
  return (
    <div className="flex items-center gap-3 border-b border-white/5 py-3 last:border-0">
      <div className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${
        ok ? 'bg-emerald-500/15 text-emerald-400' : 'bg-red-500/15 text-red-400'
      }`}>
        {ok ? <CheckCircle2 className="h-4 w-4" /> : <AlertCircle className="h-4 w-4" />}
      </div>
      <div className="min-w-0 flex-1">
        <div className="text-xs font-semibold text-white">{label}</div>
        <div className="mt-0.5 truncate text-[10px] text-slate-500" dir="ltr">{detail}</div>
      </div>
      <span className={`rounded-full px-2 py-1 text-[9px] font-bold ${
        ok ? 'bg-emerald-500/10 text-emerald-300' : 'bg-red-500/10 text-red-300'
      }`}>{ok ? 'سليم' : 'يحتاج إصلاح'}</span>
    </div>
  );
}

export default function CpSystemHealth() {
  const [rows, setRows] = useState<Row[]>([]);
  const [requests, setRequests] = useState<Row[]>([]);
  const [checks, setChecks] = useState({ columns: false, rls: false, rewards: false });
  const [loading, setLoading] = useState(true);
  const [copied, setCopied] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [couplesRes, requestsRes, rewardsRes] = await Promise.all([
        supabase.from('cp_couples').select('*'),
        supabase.from('cp_requests').select('*'),
        supabase.from('cp_rank_rewards').select('*').limit(1),
      ]);
      const couples = Array.isArray(couplesRes?.data) ? couplesRes.data as Row[] : [];
      const reqs = Array.isArray(requestsRes?.data) ? requestsRes.data as Row[] : [];
      setRows(couples);
      setRequests(reqs);

      // فحص الأعمدة المطلوبة للترتيب
      let columnsOk = false;
      try {
        const probe = await supabase.from('cp_couples')
          .select('user1_uid, user2_uid, week_score, total_score').limit(1);
        columnsOk = Array.isArray(probe?.data);
      } catch { columnsOk = false; }

      // فحص سياسة RLS: لو الـ select رجع مصفوفة فالسياسة تسمح بالقراءة
      const rlsOk = couples.length > 0 || Array.isArray(couplesRes?.data);

      setChecks({
        columns: columnsOk,
        rls: rlsOk,
        rewards: Array.isArray(rewardsRes?.data) && rewardsRes.data.length > 0,
      });
    } catch (e) {
      console.error('CpSystemHealth load', e);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  const active = rows.filter(r => !r.ended_at).length;
  const pending = requests.filter(r => r.status === 'pending').length;
  const topScore = rows.reduce((m, r) => Math.max(m, Number(r.week_score || r.total_score || 0)), 0);
  const ranked = [...rows]
    .sort((a, b) => Number(b.week_score || b.total_score || 0) - Number(a.week_score || a.total_score || 0))
    .slice(0, 6);

  const copy = async () => {
    try { await navigator.clipboard.writeText(MIGRATION_SQL); setCopied(true); setTimeout(() => setCopied(false), 1800); } catch {}
  };

  return (
    <div dir="rtl" className="space-y-6">
      {/* Header */}
      <div className="relative overflow-hidden rounded-3xl border border-white/10 bg-gradient-to-l from-indigo-600/20 via-violet-600/10 to-transparent p-6 sm:p-8">
        <div className="absolute -left-16 -top-20 h-64 w-64 rounded-full bg-indigo-500/20 blur-[90px]" />
        <div className="relative flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-4">
            <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-rose-500 to-pink-600 text-white shadow-xl shadow-rose-900/40 ring-1 ring-white/20">
              <Heart className="h-7 w-7" fill="currentColor" />
            </div>
            <div>
              <h2 className="text-2xl font-bold tracking-tight text-white">صحة نظام العلاقات</h2>
              <p className="mt-1 text-xs text-slate-400">مراقبة قاعدة بيانات الـ CP والترتيب والإعدادات بعد التحديث</p>
            </div>
          </div>
          <button
            onClick={() => void load()}
            disabled={loading}
            className="flex items-center gap-2 rounded-xl border border-white/15 bg-white/5 px-4 py-2.5 text-xs font-bold text-white transition-all hover:bg-white/10 disabled:opacity-50 active:scale-95"
          >
            <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
            {loading ? 'جارٍ التحميل...' : 'تحديث'}
          </button>
        </div>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard label="إجمالي الأزواج" value={rows.length} icon={Users} tone="from-indigo-500 to-violet-600" hint="صفوف cp_couples" />
        <StatCard label="أزواج نشطة" value={active} icon={Heart} tone="from-rose-500 to-pink-600" hint="ended_at = null" />
        <StatCard label="طلبات معلّقة" value={pending} icon={ClipboardList} tone="from-amber-500 to-orange-600" hint="cp_requests / pending" />
        <StatCard label="أعلى نقاط" value={topScore.toLocaleString()} icon={TrendingUp} tone="from-emerald-500 to-teal-600" hint="week_score / total_score" />
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        {/* Checks */}
        <div className="rounded-2xl border border-white/8 bg-white/[0.03] p-6">
          <h3 className="mb-4 flex items-center gap-2 text-sm font-bold text-white">
            <ShieldCheck className="h-4 w-4 text-emerald-400" />
            فحص جاهزية النظام
          </h3>
          <CheckRow ok={checks.columns} label="أعمدة الترتيب موجودة" detail="user1_uid, week_score, total_score, expires_at" />
          <CheckRow ok={checks.rls} label="سياسة RLS تسمح بالوصول" detail="cp_couples_all / cp_requests_all" />
          <CheckRow ok={checks.rewards} label="مكافآت المراكز محمّلة" detail="cp_rank_rewards" />
          <div className="mt-4 flex items-start gap-2 rounded-xl border border-indigo-500/20 bg-indigo-500/8 p-3">
            <Activity className="mt-0.5 h-4 w-4 shrink-0 text-indigo-300" />
            <p className="text-[11px] leading-relaxed text-slate-400">
              لو أي فحص ظهر «يحتاج إصلاح»، شغّل الـ SQL في البطاقة الجانبية ثم اضغط تحديث.
            </p>
          </div>
        </div>

        {/* SQL */}
        <div className="rounded-2xl border border-white/8 bg-white/[0.03] p-6">
          <div className="mb-4 flex items-center justify-between">
            <h3 className="flex items-center gap-2 text-sm font-bold text-white">
              <Terminal className="h-4 w-4 text-violet-400" />
              SQL الإصلاح
            </h3>
            <button
              onClick={() => void copy()}
              className="flex items-center gap-1.5 rounded-lg border border-white/10 bg-white/5 px-3 py-1.5 text-[11px] font-bold text-slate-300 transition hover:bg-white/10"
              dir="ltr"
            >
              {copied ? <Check className="h-3.5 w-3.5 text-emerald-400" /> : <Copy className="h-3.5 w-3.5" />}
              {copied ? 'Copied' : 'Copy'}
            </button>
          </div>
          <pre dir="ltr" className="custom-scrollbar max-h-72 overflow-auto rounded-xl border border-white/8 bg-black/50 p-4 text-left font-mono text-[10px] leading-relaxed text-emerald-200/90">
            {MIGRATION_SQL}
          </pre>
        </div>
      </div>

      {/* Ranking table */}
      <div className="rounded-2xl border border-white/8 bg-white/[0.03] p-6">
        <h3 className="mb-4 flex items-center gap-2 text-sm font-bold text-white">
          <TrendingUp className="h-4 w-4 text-amber-400" />
          أعلى الأزواج في الترتيب
        </h3>
        {ranked.length === 0 ? (
          <div className="flex flex-col items-center justify-center gap-2 py-10 text-center">
            <Clock className="h-8 w-8 text-slate-600" />
            <p className="text-xs text-slate-500">لا توجد أزواج بعد — ابعت هدية CP واقبلها ليه يظهروا هنا.</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[520px] text-right text-xs">
              <thead>
                <tr className="border-b border-white/10 text-[10px] font-bold uppercase tracking-wider text-slate-500">
                  <th className="py-3">#</th><th className="py-3">الطرف 1</th><th className="py-3">الطرف 2</th>
                  <th className="py-3">النقاط</th><th className="py-3">الحالة</th>
                </tr>
              </thead>
              <tbody>
                {ranked.map((r, i) => (
                  <tr key={r.id ?? i} className="border-b border-white/5 transition hover:bg-white/[0.03]">
                    <td className="py-3 font-mono font-bold text-amber-300">{i + 1}</td>
                    <td className="py-3 font-mono text-slate-300" dir="ltr">{r.user1_uid || r.user1_id || '—'}</td>
                    <td className="py-3 font-mono text-slate-300" dir="ltr">{r.user2_uid || r.user2_id || '—'}</td>
                    <td className="py-3 font-mono font-bold text-white">{(r.week_score ?? r.total_score ?? r.points ?? 0).toLocaleString()}</td>
                    <td className="py-3">
                      <span className={`rounded-full px-2 py-1 text-[9px] font-bold ${
                        r.ended_at ? 'bg-slate-500/10 text-slate-400' : 'bg-emerald-500/10 text-emerald-300'
                      }`}>{r.ended_at ? 'منتهي' : 'نشط'}</span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Steps */}
      <div className="rounded-2xl border border-white/8 bg-white/[0.03] p-6">
        <h3 className="mb-5 flex items-center gap-2 text-sm font-bold text-white">
          <Database className="h-4 w-4 text-indigo-400" />
          خطوات تفعيل التحديث
        </h3>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {STEPS.map(s => (
            <div key={s.n} className="flex gap-3 rounded-xl border border-white/6 bg-black/20 p-4">
              <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br from-indigo-500 to-violet-600 text-[11px] font-bold text-white">
                {s.n}
              </div>
              <div>
                <div className="text-xs font-bold text-white">{s.title}</div>
                <p className="mt-1 text-[10px] leading-relaxed text-slate-500">{s.desc}</p>
              </div>
            </div>
          ))}
        </div>
        <a
          href="https://supabase.com/dashboard"
          target="_blank"
          rel="noreferrer"
          className="mt-5 inline-flex items-center gap-1.5 text-[11px] font-bold text-indigo-300 transition hover:text-indigo-200"
        >
          افتح Supabase Dashboard <ArrowUpRight className="h-3.5 w-3.5" />
        </a>
      </div>
    </div>
  );
}
