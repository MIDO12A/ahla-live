import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Users, DoorOpen, Gift, DollarSign, TrendingUp, Activity, ArrowUpRight, Database, ShieldCheck, Server } from 'lucide-react';
import { getStats } from '../lib/db';

const quickActions = [
  { label: 'Browse Users', icon: Users, color: 'text-indigo-300', bg: 'from-indigo-500/20 to-indigo-500/5', to: '/users' },
  { label: 'View Rooms', icon: DoorOpen, color: 'text-emerald-300', bg: 'from-emerald-500/20 to-emerald-500/5', to: '/rooms' },
  { label: 'Manage Gifts', icon: Gift, color: 'text-rose-300', bg: 'from-rose-500/20 to-rose-500/5', to: '/gifts' },
  { label: 'Revenue Report', icon: TrendingUp, color: 'text-amber-300', bg: 'from-amber-500/20 to-amber-500/5', to: '/reports' },
];

const SUPABASE_PROJECT_REF = (import.meta.env.VITE_SUPABASE_URL || 'https://pxyqgeitjdsilgfftnyd.supabase.co')
  .replace(/^https?:\/\//, '')
  .split('.')[0];

const systemInfo = [
  { label: 'Supabase Project', value: SUPABASE_PROJECT_REF, icon: Database },
  { label: 'DB Region', value: 'auto (Supabase)', icon: Server },
  { label: 'Auth Provider', value: 'Supabase Auth', icon: ShieldCheck },
  { label: 'Storage', value: 'Cloudinary + Supabase', icon: Database },
];

export default function Dashboard() {
  const [stats, setStats] = useState({ totalUsers: 0, totalRooms: 0, totalGifts: 0, totalRevenue: 0 });

  useEffect(() => {
    getStats().then(setStats);
  }, []);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-white text-xl font-bold tracking-tight">Dashboard</h2>
          <p className="text-slate-500 text-xs mt-1">Real-time overview of your app</p>
        </div>
        <div className="flex items-center gap-2 px-3 py-1.5 rounded-full glass text-[10px] font-bold uppercase tracking-wider text-emerald-300">
          <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 shadow-[0_0_8px_rgba(52,211,153,0.9)] animate-pulse" />
          Live
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {[
          { label: 'Total Users', value: stats.totalUsers.toLocaleString(), icon: Users, gradient: 'from-indigo-500 to-violet-600', glow: 'shadow-indigo-600/30' },
          { label: 'Total Rooms', value: stats.totalRooms.toLocaleString(), icon: DoorOpen, gradient: 'from-emerald-500 to-teal-600', glow: 'shadow-emerald-600/30' },
          { label: 'Gift Types', value: stats.totalGifts.toLocaleString(), icon: Gift, gradient: 'from-rose-500 to-pink-600', glow: 'shadow-rose-600/30' },
          { label: 'Total Gift Value', value: `$${stats.totalRevenue.toLocaleString()}`, icon: DollarSign, gradient: 'from-amber-500 to-orange-600', glow: 'shadow-amber-600/30' },
        ].map(card => (
          <div key={card.label} className="card-3d rounded-2xl p-5 group">
            <div className="flex items-start justify-between">
              <div className={`w-11 h-11 rounded-xl bg-gradient-to-br ${card.gradient} flex items-center justify-center text-white shadow-lg ${card.glow} ring-1 ring-white/20 transition-transform group-hover:scale-110`}>
                <card.icon className="w-5 h-5" />
              </div>
              <TrendingUp className="w-4 h-4 text-emerald-400/60" />
            </div>
            <div className="text-2xl font-bold font-mono text-white mt-4 tracking-tight">{card.value}</div>
            <div className="text-[10px] text-slate-500 font-bold uppercase tracking-wider mt-1">{card.label}</div>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="card-3d rounded-2xl p-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-white text-sm font-semibold flex items-center gap-2">
              <Activity className="w-4 h-4 text-indigo-400" />
              Quick Actions
            </h3>
          </div>
          <div className="grid grid-cols-1 xs:grid-cols-2 gap-3">
            {quickActions.map(action => (
              <Link
                key={action.label}
                to={action.to}
                className={`group bg-gradient-to-br ${action.bg} border border-white/8 rounded-xl p-4 flex items-center gap-3 transition-all duration-200 hover:border-white/15 hover:translate-y-[-2px]`}
              >
                <div className="w-9 h-9 rounded-lg bg-black/20 border border-white/8 flex items-center justify-center">
                  <action.icon className={`w-4 h-4 ${action.color} transition-transform group-hover:scale-110`} />
                </div>
                <span className="text-xs text-white font-medium flex-1">{action.label}</span>
                <ArrowUpRight className="w-3.5 h-3.5 text-slate-500 group-hover:text-white transition-colors" />
              </Link>
            ))}
          </div>
        </div>

        <div className="card-3d rounded-2xl p-6">
          <h3 className="text-white text-sm font-semibold mb-4 flex items-center gap-2">
            <Server className="w-4 h-4 text-violet-400" />
            System Info
          </h3>
          <div className="space-y-1">
            {systemInfo.map(info => (
              <div key={info.label} className="flex items-center justify-between gap-4 border-b border-white/5 last:border-0 py-2.5">
                <span className="flex items-center gap-2 text-slate-500 text-xs">
                  <info.icon className="w-3.5 h-3.5 text-slate-600" />
                  {info.label}
                </span>
                <span className="text-white font-mono text-[11px] truncate">{info.value}</span>
              </div>
            ))}
          </div>
          <div className="mt-4 flex items-center gap-2 px-3 py-2 rounded-lg bg-emerald-500/8 border border-emerald-500/15">
            <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
            <span className="text-[10px] text-emerald-300 font-medium">All systems operational</span>
          </div>
        </div>
      </div>
    </div>
  );
}
