import { useEffect, useState, useContext } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Users, DoorOpen, Gift, DollarSign, Crown, Wand2, Phone, Image,
  Sparkles, SlidersHorizontal, Handshake, Zap, Activity, ArrowRightLeft,
  ChevronRight, ShieldCheck, Database
} from 'lucide-react';
import { getStats } from '../lib/db';
import { I18nContext } from '../lib/i18n';
import { useDashboardMode } from '../lib/dashboardMode';

export default function Dashboard() {
  const navigate = useNavigate();
  const { lang } = useContext(I18nContext);
  const isAr = lang === 'ar';
  const { isDesigner, toggleMode } = useDashboardMode();

  const [stats, setStats] = useState({ totalUsers: 0, totalRooms: 0, totalGifts: 0, totalRevenue: 0 });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getStats()
      .then(s => setStats(s))
      .catch(console.error)
      .finally(() => setLoading(false));
  }, []);

  const modernHubs = [
    {
      title: isAr ? 'لوحة السوبر أدمن المركزية' : 'Super Admin Central Hub',
      desc: isAr ? 'إدارة المشرفين، الرواتب، نسب العمولات، وصرف الأرباح' : 'Staff, salaries, commission rates & payouts',
      icon: Crown,
      color: 'from-amber-500 to-yellow-600',
      badge: isAr ? 'تحكم كامل 👑' : 'Full Control',
      badgeColor: 'bg-amber-500/20 text-amber-300 border-amber-500/30',
      to: '/super-admin',
    },
    {
      title: isAr ? 'المظهر الشامل والألوان' : 'Visual Manager & Colors',
      desc: isAr ? 'ربط الألوان والصور وتحويل المظهر العام للتطبيق' : 'Brand colors, images, theme presets & assets',
      icon: Wand2,
      color: 'from-pink-500 to-rose-600',
      badge: isAr ? 'لوحة المصمم 🎨' : 'Designer Hub',
      badgeColor: 'bg-pink-500/20 text-pink-300 border-pink-500/30',
      to: '/visual-manager',
    },
    {
      title: isAr ? 'مصمم الواجهات والأيقونات' : 'App Visual Designer',
      desc: isAr ? 'تخصيص الواجهات البصرية والأيقونات وأشكال الشاشات' : 'UI elements, icons & interactive components',
      icon: Phone,
      color: 'from-indigo-500 to-blue-600',
      badge: isAr ? 'تخصيص فوري 📱' : 'Interactive UI',
      badgeColor: 'bg-indigo-500/20 text-indigo-300 border-indigo-500/30',
      to: '/app-visual-designer',
    },
    {
      title: isAr ? 'تخصيص الشاشات والخلفيات' : 'Screen Customization',
      desc: isAr ? 'تعديل نصوص الشاشات، صور الخلفيات، والروابط السريعة' : 'Screen text overrides, backgrounds & custom links',
      icon: SlidersHorizontal,
      color: 'from-purple-500 to-violet-600',
      badge: isAr ? 'تعديل مباشر 🛠️' : 'Live Config',
      badgeColor: 'bg-purple-500/20 text-purple-300 border-purple-500/30',
      to: '/screen-customization',
    },
    {
      title: isAr ? 'مكتبة أصول التطبيق' : 'App Assets & Media',
      desc: isAr ? 'رفع وإدارة صور الأقسام، الشارات، والأيقونات الرسمية' : 'Manage uploaded media, SVGs, badges & frames',
      icon: Image,
      color: 'from-emerald-500 to-teal-600',
      badge: isAr ? 'مكتبة وسائط 🖼️' : 'Asset Media',
      badgeColor: 'bg-emerald-500/20 text-emerald-300 border-emerald-500/30',
      to: '/app-assets',
    },
    {
      title: isAr ? 'لافتات وبانرات الهدايا' : 'Gift Banner Configs',
      desc: isAr ? 'تخصيص إعلانات ولافتات وبانرات الهدايا المميزة' : 'Banner popups, gift animations & tier highlights',
      icon: Sparkles,
      color: 'from-cyan-500 to-blue-600',
      badge: isAr ? 'هدايا وبانرات 🎁' : 'Gift Media',
      badgeColor: 'bg-cyan-500/20 text-cyan-300 border-cyan-500/30',
      to: '/gift-banner-configs',
    },
    {
      title: isAr ? 'الوكالات وصرف الأرباح' : 'Agencies & Disbursements',
      desc: isAr ? 'إدارة الوكلاء، المستهدفات، والتحويلات المالية المباشرة' : 'Agency targets, host earnings & instant withdrawals',
      icon: Handshake,
      color: 'from-emerald-600 to-green-700',
      badge: isAr ? 'محرك مالي 💵' : 'Financial Engine',
      badgeColor: 'bg-emerald-500/20 text-emerald-300 border-emerald-500/30',
      to: '/agency',
    },
    {
      title: isAr ? 'شحن الكوينز والفعاليات' : 'Recharge & Events',
      desc: isAr ? 'باقات الشحن، مضاعفات الكوينز، وفعاليات الهدايا' : 'Coin packages, multipliers & seasonal campaigns',
      icon: Zap,
      color: 'from-amber-600 to-orange-600',
      badge: isAr ? 'باقات كوينز ⚡' : 'Recharge Store',
      badgeColor: 'bg-amber-500/20 text-amber-300 border-amber-500/30',
      to: '/recharge-event',
    },
  ];

  return (
    <div className={`space-y-6 ${isAr ? 'text-right' : ''}`}>
      {/* Hero Welcome Banner with Mode Switcher */}
      <div className="relative overflow-hidden rounded-3xl bg-gradient-to-r from-indigo-900/60 via-purple-900/40 to-slate-900/80 border border-white/10 p-6 sm:p-8 backdrop-blur-xl shadow-2xl">
        <div className="absolute top-0 right-0 -translate-y-12 translate-x-12 w-96 h-96 bg-indigo-500/10 rounded-full blur-3xl pointer-events-none" />
        <div className="absolute bottom-0 left-0 translate-y-12 -translate-x-12 w-96 h-96 bg-pink-500/10 rounded-full blur-3xl pointer-events-none" />

        <div className="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-6">
          <div className="space-y-2">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-indigo-500/20 border border-indigo-400/30 text-indigo-300 text-xs font-semibold">
              <ShieldCheck className="w-3.5 h-3.5" />
              <span>{isAr ? 'لوحة التحكم المركزية المحدثة 2026' : 'Zero Unified Control Center 2026'}</span>
            </div>
            <h1 className="text-2xl sm:text-3xl font-black text-white tracking-tight">
              {isAr ? 'أهلاً بك في لوحة تحكم Zero' : 'Welcome to Zero Dashboard'}
            </h1>
            <p className="text-slate-300 text-xs sm:text-sm max-w-xl">
              {isAr
                ? 'تحكم كامل في التطبيق، إدارة المشرفين والرواتب، وتخصيص الواجهات والألوان والصور بكل سهولة.'
                : 'Complete control of your application, staff salaries, commissions, visual styles and live customization.'}
            </p>
          </div>

          {/* Quick Switch Buttons */}
          <div className="flex flex-wrap items-center gap-3 shrink-0">
            <button
              onClick={toggleMode}
              className={`flex items-center gap-2.5 px-4 py-3 rounded-2xl font-bold text-xs sm:text-sm border transition-all shadow-lg active:scale-95 ${
                isDesigner
                  ? 'bg-gradient-to-r from-amber-500 to-pink-600 text-white border-amber-400/40 shadow-amber-500/25'
                  : 'bg-white/10 hover:bg-white/15 text-white border-white/20'
              }`}
            >
              <ArrowRightLeft className="w-4 h-4" />
              <span>
                {isDesigner
                  ? (isAr ? 'وضع المصمم مفعل 🎨 (انقر للعودة للإدارة)' : 'Designer Active 🎨 (Click for Admin)')
                  : (isAr ? 'التبديل إلى لوحة المصمم 🎨' : 'Switch to Designer Mode 🎨')}
              </span>
            </button>

            <button
              onClick={() => navigate('/super-admin')}
              className="flex items-center gap-2 px-4 py-3 rounded-2xl font-bold text-xs sm:text-sm bg-gradient-to-r from-amber-600 to-yellow-500 text-white border border-amber-400/30 shadow-lg shadow-amber-600/20 hover:brightness-110 active:scale-95 transition-all"
            >
              <Crown className="w-4 h-4" />
              <span>{isAr ? 'لوحة السوبر أدمن 👑' : 'Super Admin 👑'}</span>
            </button>
          </div>
        </div>
      </div>

      {/* Live Stats Section */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div
          onClick={() => navigate('/users')}
          className="bg-[#141417] p-5 rounded-2xl border border-white/5 hover:border-indigo-500/40 hover:bg-[#18181c] transition-all cursor-pointer group shadow-sm"
        >
          <div className="flex items-center justify-between mb-3">
            <div className="w-10 h-10 rounded-xl bg-indigo-500/10 flex items-center justify-center text-indigo-400 group-hover:scale-110 transition-transform">
              <Users className="w-5 h-5" />
            </div>
            <span className="text-[10px] text-indigo-400 font-bold bg-indigo-500/10 px-2 py-0.5 rounded-full">
              {isAr ? 'مستخدمين' : 'Users'}
            </span>
          </div>
          <div className="text-3xl font-extrabold font-mono text-white">
            {loading ? '...' : stats.totalUsers.toLocaleString()}
          </div>
          <div className="text-xs text-slate-400 font-medium mt-1">
            {isAr ? 'إجمالي الحسابات المسجلة' : 'Total Registered Users'}
          </div>
        </div>

        <div
          onClick={() => navigate('/rooms')}
          className="bg-[#141417] p-5 rounded-2xl border border-white/5 hover:border-emerald-500/40 hover:bg-[#18181c] transition-all cursor-pointer group shadow-sm"
        >
          <div className="flex items-center justify-between mb-3">
            <div className="w-10 h-10 rounded-xl bg-emerald-500/10 flex items-center justify-center text-emerald-400 group-hover:scale-110 transition-transform">
              <DoorOpen className="w-5 h-5" />
            </div>
            <span className="text-[10px] text-emerald-400 font-bold bg-emerald-500/10 px-2 py-0.5 rounded-full">
              {isAr ? 'غرف صوتية' : 'Rooms'}
            </span>
          </div>
          <div className="text-3xl font-extrabold font-mono text-white">
            {loading ? '...' : stats.totalRooms.toLocaleString()}
          </div>
          <div className="text-xs text-slate-400 font-medium mt-1">
            {isAr ? 'إجمالي غرف البث النشطة' : 'Active Voice Rooms'}
          </div>
        </div>

        <div
          onClick={() => navigate('/gifts')}
          className="bg-[#141417] p-5 rounded-2xl border border-white/5 hover:border-rose-500/40 hover:bg-[#18181c] transition-all cursor-pointer group shadow-sm"
        >
          <div className="flex items-center justify-between mb-3">
            <div className="w-10 h-10 rounded-xl bg-rose-500/10 flex items-center justify-center text-rose-400 group-hover:scale-110 transition-transform">
              <Gift className="w-5 h-5" />
            </div>
            <span className="text-[10px] text-rose-400 font-bold bg-rose-500/10 px-2 py-0.5 rounded-full">
              {isAr ? 'هدايا' : 'Gifts'}
            </span>
          </div>
          <div className="text-3xl font-extrabold font-mono text-white">
            {loading ? '...' : stats.totalGifts.toLocaleString()}
          </div>
          <div className="text-xs text-slate-400 font-medium mt-1">
            {isAr ? 'أنواع وتصنيفات الهدايا' : 'Configured Gift Types'}
          </div>
        </div>

        <div
          onClick={() => navigate('/agency')}
          className="bg-[#141417] p-5 rounded-2xl border border-white/5 hover:border-amber-500/40 hover:bg-[#18181c] transition-all cursor-pointer group shadow-sm"
        >
          <div className="flex items-center justify-between mb-3">
            <div className="w-10 h-10 rounded-xl bg-amber-500/10 flex items-center justify-center text-amber-400 group-hover:scale-110 transition-transform">
              <DollarSign className="w-5 h-5" />
            </div>
            <span className="text-[10px] text-amber-400 font-bold bg-amber-500/10 px-2 py-0.5 rounded-full">
              {isAr ? 'كوينز' : 'Coins Value'}
            </span>
          </div>
          <div className="text-3xl font-extrabold font-mono text-white">
            {loading ? '...' : stats.totalRevenue.toLocaleString()}
          </div>
          <div className="text-xs text-slate-400 font-medium mt-1">
            {isAr ? 'إجمالي قيمة الهدايا والكوينز' : 'Total Gift Coin Value'}
          </div>
        </div>
      </div>

      {/* Modern Hubs Grid */}
      <div>
        <div className="flex items-center justify-between mb-4">
          <div>
            <h2 className="text-white text-lg font-bold">
              {isAr ? 'الأقسام والمراكز الحديثة' : 'Modern Centers & Tools'}
            </h2>
            <p className="text-slate-400 text-xs">
              {isAr
                ? 'انقر على أي قسم للدخول المباشر والبدء في التعديل والإدارة'
                : 'Click any center for instant access and management'}
            </p>
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {modernHubs.map(hub => {
            const Icon = hub.icon;
            return (
              <div
                key={hub.to}
                onClick={() => navigate(hub.to)}
                className="group relative bg-[#131316] hover:bg-[#18181d] border border-white/5 hover:border-white/20 rounded-2xl p-5 cursor-pointer transition-all duration-200 flex flex-col justify-between shadow-lg hover:shadow-xl hover:-translate-y-0.5"
              >
                <div>
                  <div className="flex items-center justify-between mb-3">
                    <div className={`w-10 h-10 rounded-xl bg-gradient-to-tr ${hub.color} flex items-center justify-center text-white shadow-md group-hover:scale-105 transition-transform`}>
                      <Icon className="w-5 h-5" />
                    </div>
                    <span className={`text-[10px] font-bold px-2.5 py-0.5 rounded-full border ${hub.badgeColor}`}>
                      {hub.badge}
                    </span>
                  </div>
                  <h3 className="text-white font-bold text-sm mb-1 group-hover:text-indigo-300 transition-colors">
                    {hub.title}
                  </h3>
                  <p className="text-slate-400 text-xs leading-relaxed line-clamp-2">
                    {hub.desc}
                  </p>
                </div>

                <div className={`mt-4 pt-3 border-t border-white/5 flex items-center justify-between text-xs font-semibold text-slate-400 group-hover:text-white transition-colors ${isAr ? 'flex-row-reverse' : ''}`}>
                  <span>{isAr ? 'دخول القسم' : 'Open Page'}</span>
                  <ChevronRight className={`w-4 h-4 group-hover:translate-x-1 transition-transform ${isAr ? 'rotate-180 group-hover:-translate-x-1' : ''}`} />
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Quick Diagnostics & System Status */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-4">
          <h3 className="text-white text-sm font-bold flex items-center gap-2">
            <Activity className="w-4 h-4 text-emerald-400" />
            <span>{isAr ? 'حالة النظام والاتصال المباشر' : 'System & Connection Status'}</span>
          </h3>

          <div className="space-y-3 text-xs">
            <div className={`flex justify-between items-center border-b border-white/5 pb-2 ${isAr ? 'flex-row-reverse' : ''}`}>
              <span className="text-slate-400">{isAr ? 'خادم قاعدة البيانات' : 'Database Server'}</span>
              <span className="text-emerald-400 font-mono font-bold flex items-center gap-1.5">
                <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
                Supabase Connected (pxyqgeitjdsilgfftnyd)
              </span>
            </div>

            <div className={`flex justify-between items-center border-b border-white/5 pb-2 ${isAr ? 'flex-row-reverse' : ''}`}>
              <span className="text-slate-400">{isAr ? 'نظام المصادقة والصلاحيات' : 'Auth & Roles'}</span>
              <span className="text-white font-mono">App ID / Email / Password</span>
            </div>

            <div className={`flex justify-between items-center border-b border-white/5 pb-2 ${isAr ? 'flex-row-reverse' : ''}`}>
              <span className="text-slate-400">{isAr ? 'محرك الصوت والميكروفونات' : 'Audio Engine'}</span>
              <span className="text-indigo-300 font-mono">ZEGO Cloud SDK</span>
            </div>

            <div className={`flex justify-between items-center ${isAr ? 'flex-row-reverse' : ''}`}>
              <span className="text-slate-400">{isAr ? 'إصدار لوحة التحكم' : 'Dashboard Version'}</span>
              <span className="text-slate-300 font-mono font-bold">v1.0.2142 (Modern UI 2026)</span>
            </div>
          </div>
        </div>

        <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-4">
          <h3 className="text-white text-sm font-bold flex items-center gap-2">
            <Database className="w-4 h-4 text-indigo-400" />
            <span>{isAr ? 'روابط التخصيص والمظهر السريع' : 'Quick Designer Links'}</span>
          </h3>

          <div className="grid grid-cols-2 gap-2.5">
            {[
              { label: isAr ? 'المظهر الشامل 🎨' : 'Visual Manager', path: '/visual-manager' },
              { label: isAr ? 'مصمم الواجهات 📱' : 'Visual Designer', path: '/app-visual-designer' },
              { label: isAr ? 'تخصيص الشاشات 🛠️' : 'Screen Custom', path: '/screen-customization' },
              { label: isAr ? 'أصول التطبيق 🖼️' : 'App Assets', path: '/app-assets' },
              { label: isAr ? 'بانرات الهدايا 🎁' : 'Gift Banners', path: '/gift-banner-configs' },
              { label: isAr ? 'لوحة السوبر أدمن 👑' : 'Super Admin', path: '/super-admin' },
            ].map(item => (
              <button
                key={item.path}
                onClick={() => navigate(item.path)}
                className="bg-[#1c1c20] hover:bg-indigo-600/20 hover:border-indigo-500/40 border border-white/5 rounded-xl p-3 text-xs font-bold text-slate-300 hover:text-white transition-all text-center"
              >
                {item.label}
              </button>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
