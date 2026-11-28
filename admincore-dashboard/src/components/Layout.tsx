import { useState, useEffect, useCallback } from 'react';
import { Outlet, useLocation } from 'react-router-dom';
import Sidebar from './Sidebar';
import Header from './Header';
import { onAuthChange, type AppUser } from '../lib/auth';
import {
  ensureAdminBootstrap,
  getAdminStatus,
  isAdminConnected,
  subscribeConnection,
  pingAdminConnection,
} from '../lib/supabase';

export default function Layout() {
  const [collapsed, setCollapsed] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const [currentUser, setCurrentUser] = useState<AppUser | null>(null);
  const [uid, setUid] = useState<string | null>(null);
  const [status, setStatus] = useState<{ fixed: boolean; reason: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [connected, setConnected] = useState(isAdminConnected());
  const location = useLocation();

  // ✅ حالة الاتصال حقيقية (ping على Supabase) — تتحدّث لحظياً
  useEffect(() => subscribeConnection(setConnected), []);

  // Automatically close mobile menu on page navigation
  useEffect(() => {
    setMobileOpen(false);
  }, [location.pathname]);

  const check = useCallback(async (u: string) => {
    const s = await getAdminStatus(u);
    setStatus({ fixed: s.fixed, reason: s.reason });
  }, []);

  useEffect(() => {
    const unsub = onAuthChange(u => {
      setCurrentUser(u);
      setUid(u?.id ?? null);
      setStatus(null);
      if (u) check(u.id);
    });
    return unsub;
  }, [check]);

  const runBootstrap = async () => {
    if (!uid) return;
    setBusy(true);
    try {
      const r = await ensureAdminBootstrap(uid);
      if (r.created) setStatus({ fixed: true, reason: 'ok' });
      else await check(uid);
    } finally {
      setBusy(false);
    }
  };

  useEffect(() => {
    const mq = window.matchMedia('(max-width: 1023px)');
    const handler = (e: MediaQueryListEvent | MediaQueryList) => {
      if (e.matches) setCollapsed(true);
    };
    handler(mq);
    mq.addEventListener('change', handler);
    return () => mq.removeEventListener('change', handler);
  }, []);

  // Lock body scroll on mobile when menu drawer is open
  useEffect(() => {
    if (mobileOpen) {
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.overflow = '';
    }
    return () => {
      document.body.style.overflow = '';
    };
  }, [mobileOpen]);

  return (
    <div className="h-screen bg-[#0A0A0B] text-slate-300 flex overflow-hidden w-full relative">
      {/* Ambient depth glows + professional grid */}
      <div className="pointer-events-none fixed inset-0 overflow-hidden">
        <div className="pro-grid absolute inset-0 opacity-60" />
        <div className="absolute -top-40 -left-40 w-[32rem] h-[32rem] rounded-full bg-indigo-600/10 blur-[140px]" />
        <div className="absolute top-1/3 -right-40 w-[28rem] h-[28rem] rounded-full bg-violet-600/8 blur-[130px]" />
        <div className="absolute -bottom-40 left-1/3 w-[26rem] h-[26rem] rounded-full bg-rose-600/5 blur-[120px]" />
      </div>

      <Sidebar
        collapsed={collapsed}
        onToggle={() => setCollapsed(c => !c)}
        mobileOpen={mobileOpen}
        onMobileClose={() => setMobileOpen(false)}
        currentUser={currentUser}
      />

      {/* Mobile overlay backdrop */}
      {mobileOpen && (
        <div
          className="fixed inset-0 bg-black/75 backdrop-blur-sm z-40 lg:hidden transition-opacity duration-300"
          onClick={() => setMobileOpen(false)}
          aria-hidden="true"
        />
      )}

      <div className="relative z-10 flex-1 flex flex-col min-w-0 h-full overflow-hidden w-full">
        <Header onMenuClick={() => setMobileOpen(true)} />

        {/* حالة الاتصال الفعلية بالسيرفر (بدل مؤشر كان بيعرض true دايماً) */}
        <div
          className={`mx-3 mt-3 lg:mx-6 lg:mt-4 rounded-lg border px-3 py-1.5 text-[11px] flex items-center gap-2 shrink-0 ${
            connected
              ? 'border-emerald-500/25 bg-emerald-500/10 text-emerald-200'
              : 'border-red-500/35 bg-red-500/10 text-red-200'
          }`}
        >
          <span
            className={`h-1.5 w-1.5 rounded-full ${connected ? 'bg-emerald-400' : 'bg-red-400'}`}
          />
          <span className="flex-1">
            {connected
              ? 'متصل بسيرفر Supabase — التطبيق واللوحة على نفس قاعدة البيانات'
              : 'غير متصل بالسيرفر — تحقّق من الإنترنت'}
          </span>
          {!connected && (
            <button
              onClick={() => void pingAdminConnection()}
              className="px-2 py-0.5 rounded border border-red-400/40 hover:bg-red-400/15 whitespace-nowrap"
            >
              إعادة الفحص
            </button>
          )}
        </div>

        {status && !status.fixed && (
          <div className="mx-3 mt-3 lg:mx-6 lg:mt-4 rounded-xl border border-red-500/30 bg-red-500/10 px-3.5 py-2.5 text-xs text-red-200 flex flex-wrap items-center gap-2 shrink-0 shadow-lg shadow-red-950/20 backdrop-blur-md">
            <span className="font-bold">⚠️ Admin write access blocked</span>
            <span className="opacity-80 break-all flex-1 min-w-[200px]">{status.reason}</span>
            <button
              onClick={runBootstrap}
              disabled={busy}
              className="px-3 py-1.5 rounded-lg bg-red-500/20 hover:bg-red-500/30 border border-red-500/40 disabled:opacity-50 whitespace-nowrap transition-all active:scale-[0.98]"
            >
              {busy ? 'Running...' : 'Run bootstrap'}
            </button>
            {uid && <code className="opacity-60 whitespace-nowrap">uid: {uid}</code>}
          </div>
        )}

        <main className="flex-1 overflow-y-auto p-3 sm:p-5 lg:p-7 custom-scrollbar w-full max-w-full bg-[#08080a]/40 rounded-t-2xl border-t border-white/5">
          <div className="animate-fade-in">
            <Outlet context={{ currentUser }} />
          </div>
        </main>
      </div>
    </div>
  );
}
