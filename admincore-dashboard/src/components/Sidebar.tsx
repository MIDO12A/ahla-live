import { NavLink, useLocation } from 'react-router-dom';
import {
  LayoutDashboard, Users, Gift, Store, DoorOpen,
  Building2, Crown, BarChart3, Award, Handshake,
  TrendingUp, Image, Palette, Bug,
  Bell, Settings, Shield, ChevronLeft, LogOut, SlidersHorizontal, Grid, Gift as GiftIcon,
  Tag, Sparkles, Eye, ImageIcon, Calendar, Rocket, Phone, CheckSquare, Volume2, Mic, User, Zap, X,
  Wand2, ArrowRightLeft,
} from 'lucide-react';
import { logout } from '../lib/auth';
import { useContext } from 'react';
import { I18nContext } from '../lib/i18n';
import { useDashboardMode } from '../lib/dashboardMode';

const adminNavItems = [
  { to: '/', icon: LayoutDashboard, label: 'nav.dashboard', end: true },
  { to: '/recharge-event', icon: Zap, label: 'nav.rechargeEvent' },
  { to: '/users', icon: Users, label: 'nav.users' },
  { to: '/gifts', icon: Gift, label: 'nav.gifts' },
  { to: '/store', icon: Store, label: 'nav.store' },
  { to: '/rooms', icon: DoorOpen, label: 'nav.rooms' },
  { to: '/lucky-gifts', icon: Sparkles, label: 'nav.luckyGifts' },
  { to: '/red-packets', icon: Gift, label: 'المظاريف وصناديق الحظ 🧧' },
  { to: '/tasks-manager', icon: CheckSquare, label: 'مركز المهام والمكافآت' },
  { to: '/unions', icon: Building2, label: 'nav.unions' },
  { to: '/vip', icon: Crown, label: 'nav.vip' },
  { to: '/vip-gifting', icon: GiftIcon, label: 'nav.vipGifting' },
  { to: '/levels', icon: BarChart3, label: 'nav.levels' },
  { to: '/badges', icon: Award, label: 'nav.badges' },
  { to: '/necklaces', icon: Crown, label: 'nav.necklaces' },
  { to: '/badge-necklace-gifts', icon: GiftIcon, label: 'Badge & Necklace Gifts' },
  { to: '/agency', icon: Handshake, label: 'nav.agency' },
  { to: '/cp-features', icon: Gift, label: 'CP Features' },
  { to: '/signin-features', icon: Calendar, label: 'nav.signin' },
  { to: '/app-updates', icon: Rocket, label: 'App Updates' },
  { to: '/bd', icon: TrendingUp, label: 'nav.bd' },
  { to: '/profile-customize', icon: User, label: 'nav.profileCustomize' },
  { to: '/error-analysis', icon: Bug, label: 'nav.errors' },
  { to: '/admins', icon: Shield, label: 'nav.admins' },
  { to: '/notifications', icon: Bell, label: 'nav.notifications' },
  { to: '/reports', icon: Shield, label: 'البلاغات' },
  { to: '/settings', icon: Settings, label: 'nav.settings' },
];

const designerNavItems = [
  { to: '/visual-manager', icon: Eye, label: 'المظهر الشامل والألوان 🎨', isCustom: true },
  { to: '/app-visual-designer', icon: Phone, label: 'مصمم الواجهات والأيقونات 📱', isCustom: true },
  { to: '/screen-customization', icon: SlidersHorizontal, label: 'تخصيص وتعديل الشاشات والخلفيات 🛠️', isCustom: true },
  { to: '/app-assets', icon: Image, label: 'مكتبة أصول وتصاميم التطبيق 🖼️', isCustom: true },
  { to: '/gift-banner-configs', icon: Sparkles, label: 'لافتات وبانرات الهدايا 🎁', isCustom: true },
  { to: '/app-icons', icon: Grid, label: 'أيقونات التطبيق 🏷️', isCustom: true },
  { to: '/image-customize', icon: ImageIcon, label: 'الصور وتصاميم الصفحات 🖼️', isCustom: true },
  { to: '/color-customize', icon: Palette, label: 'لوحة الألوان المخصصة 🎨', isCustom: true },
  { to: '/room-backgrounds', icon: ImageIcon, label: 'خلفيات الغرف 🏞️', isCustom: true },
  { to: '/app-sounds', icon: Volume2, label: 'الأصوات والمؤثرات 🎵', isCustom: true },
  { to: '/audio-settings', icon: Mic, label: 'إعدادات Zego ومحرك الصوت 🎙️', isCustom: true },
  { to: '/banners', icon: SlidersHorizontal, label: 'البانرات الترويجية 📢', isCustom: true },
  { to: '/emojis', icon: ImageIcon, label: 'الإيموجي والتعبيرات 😀', isCustom: true },
  { to: '/settings', icon: Settings, label: 'nav.settings', isCustom: false },
];

export default function Sidebar({ collapsed, onToggle, mobileOpen, onMobileClose }: { collapsed: boolean; onToggle: () => void; mobileOpen?: boolean; onMobileClose?: () => void }) {
  const location = useLocation();
  const { t, lang } = useContext(I18nContext);
  const { isDesigner, toggleMode } = useDashboardMode();

  const currentNavItems = isDesigner ? designerNavItems : adminNavItems;

  return (
    <>
    {/* Mobile overlay sidebar drawer */}
    <aside
      className={`fixed inset-y-0 z-50 lg:hidden transition-transform duration-300 ease-in-out bg-[#0D0D0E] shadow-2xl flex flex-col w-72 max-w-[85vw] ${
        lang === 'ar'
          ? `right-0 border-l border-white/10 ${mobileOpen ? 'translate-x-0' : 'translate-x-full'}`
          : `left-0 border-r border-white/10 ${mobileOpen ? 'translate-x-0' : '-translate-x-full'}`
      }`}
    >
      <div className="p-4 flex items-center justify-between border-b border-white/5 h-14 shrink-0">
        <div className={`flex items-center gap-2.5 ${lang === 'ar' ? 'flex-row-reverse' : ''}`}>
          <div className={`w-8 h-8 rounded-lg flex items-center justify-center text-white font-bold text-sm shadow-md ${isDesigner ? 'bg-gradient-to-tr from-pink-600 to-amber-500 shadow-amber-500/20' : 'bg-indigo-600 shadow-indigo-600/20'}`}>
            {isDesigner ? '🎨' : 'Z'}
          </div>
          <div>
            <span className="text-white font-bold text-sm block leading-tight" style={{ fontFamily: lang === 'ar' ? 'system-ui' : 'inherit' }}>{t('app.name')}</span>
            <span className={`text-[10px] font-mono ${isDesigner ? 'text-amber-400 font-bold' : 'text-slate-500'}`}>
              {isDesigner ? (lang === 'ar' ? 'لوحة المصمم 🎨' : 'Designer Mode 🎨') : (lang === 'ar' ? 'لوحة الإدارة 🏢' : 'Admin Panel 🏢')}
            </span>
          </div>
        </div>
        <button
          onClick={onMobileClose}
          className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-white/10 transition-colors"
          aria-label="Close menu"
        >
          <X className="w-5 h-5" />
        </button>
      </div>

      {/* Mode Switcher Banner */}
      <div className="p-3 border-b border-white/5 bg-white/[0.02]">
        <button
          onClick={() => {
            toggleMode();
            if (onMobileClose) onMobileClose();
          }}
          className={`w-full p-2.5 rounded-xl border flex items-center justify-between transition-all ${
            isDesigner
              ? 'bg-amber-500/10 border-amber-500/30 text-amber-300 hover:bg-amber-500/20'
              : 'bg-indigo-600/10 border-indigo-500/30 text-indigo-300 hover:bg-indigo-600/20'
          } ${lang === 'ar' ? 'flex-row-reverse' : ''}`}
        >
          <div className={`flex items-center gap-2 ${lang === 'ar' ? 'flex-row-reverse' : ''}`}>
            {isDesigner ? <Wand2 className="w-4 h-4 text-amber-400" /> : <Palette className="w-4 h-4 text-indigo-400" />}
            <span className="text-xs font-bold">
              {isDesigner ? (lang === 'ar' ? 'العودة للوحة الإدارة 🏢' : 'Switch to Admin') : (lang === 'ar' ? 'لوحة المصمم 🎨' : 'Designer Mode')}
            </span>
          </div>
          <ArrowRightLeft className="w-3.5 h-3.5 opacity-70" />
        </button>
      </div>

      <nav className="flex-1 overflow-y-auto px-2.5 py-3 space-y-1 custom-scrollbar">
        {currentNavItems.map(item => (
          <NavLink key={item.to} to={item.to} end={'end' in item ? item.end : false} onClick={onMobileClose}
            className={({ isActive }) =>
              `flex items-center gap-3 px-3 py-2.5 rounded-xl text-xs font-medium transition-all ${
                isActive
                  ? isDesigner
                    ? 'bg-gradient-to-r from-amber-600 to-pink-600 text-white shadow-lg shadow-amber-600/30'
                    : 'bg-indigo-600 text-white shadow-lg shadow-indigo-600/30'
                  : 'text-slate-400 hover:bg-white/5 hover:text-white'
              } ${lang === 'ar' ? 'flex-row-reverse' : ''}`
            }
          >
            <item.icon className="w-4 h-4 shrink-0" />
            <span className="truncate">{('isCustom' in item && item.isCustom) ? item.label : t(item.label)}</span>
          </NavLink>
        ))}
      </nav>
      <div className="p-3 border-t border-white/5 shrink-0">
        <button onClick={() => logout()} className={`flex items-center gap-3 px-3 py-2.5 rounded-xl text-xs text-rose-400 hover:bg-rose-500/10 w-full transition-all ${lang === 'ar' ? 'flex-row-reverse' : ''}`}>
          <LogOut className="w-4 h-4 shrink-0" />
          <span>{t('sign.out')}</span>
        </button>
      </div>
    </aside>

    {/* Desktop sidebar */}
    <aside className={`${collapsed ? 'w-16' : 'w-60'} transition-all duration-300 border-r border-white/5 bg-[#0D0D0E] flex flex-col shrink-0 ${lang === 'ar' ? 'border-l border-r-0' : ''} hidden lg:flex h-screen sticky top-0`}>
      <div className="p-4 flex items-center justify-between border-b border-white/5 h-14 shrink-0">
        {!collapsed && (
          <div className={`flex items-center gap-2 ${lang === 'ar' ? 'flex-row-reverse' : ''}`}>
            <div className={`w-7 h-7 rounded-lg flex items-center justify-center text-white font-bold text-xs shadow-md ${isDesigner ? 'bg-gradient-to-tr from-pink-600 to-amber-500 shadow-amber-500/20' : 'bg-indigo-600'}`}>
              {isDesigner ? '🎨' : 'Z'}
            </div>
            <div>
              <span className="text-white font-semibold text-sm block leading-tight" style={{ fontFamily: lang === 'ar' ? 'system-ui' : 'inherit' }}>{t('app.name')}</span>
              <span className={`text-[9px] font-mono ${isDesigner ? 'text-amber-400 font-bold' : 'text-slate-500'}`}>
                {isDesigner ? (lang === 'ar' ? 'لوحة المصمم 🎨' : 'Designer') : (lang === 'ar' ? 'لوحة الإدارة 🏢' : 'Admin')}
              </span>
            </div>
          </div>
        )}
        <button onClick={onToggle} className="p-1 rounded text-slate-500 hover:text-white hover:bg-white/5">
          <ChevronLeft className={`w-4 h-4 transition-transform ${collapsed ? 'rotate-180' : ''} ${lang === 'ar' ? 'rotate-180' : ''}`} />
        </button>
      </div>

      {/* Mode Switcher Banner in Desktop */}
      {!collapsed && (
        <div className="p-2.5 border-b border-white/5">
          <button
            onClick={toggleMode}
            className={`w-full p-2 rounded-xl border flex items-center justify-between transition-all group ${
              isDesigner
                ? 'bg-amber-500/10 border-amber-500/30 text-amber-300 hover:bg-amber-500/20'
                : 'bg-indigo-600/10 border-indigo-500/30 text-indigo-300 hover:bg-indigo-600/20'
            } ${lang === 'ar' ? 'flex-row-reverse' : ''}`}
            title={isDesigner ? 'العودة للوحة الإدارة العامة' : 'التبديل إلى لوحة المصمم'}
          >
            <div className={`flex items-center gap-2 ${lang === 'ar' ? 'flex-row-reverse' : ''}`}>
              {isDesigner ? <Wand2 className="w-3.5 h-3.5 text-amber-400" /> : <Palette className="w-3.5 h-3.5 text-indigo-400" />}
              <span className="text-[11px] font-bold">
                {isDesigner ? (lang === 'ar' ? 'لوحة الإدارة 🏢' : 'Admin Mode') : (lang === 'ar' ? 'لوحة المصمم 🎨' : 'Designer Mode')}
              </span>
            </div>
            <ArrowRightLeft className="w-3 h-3 opacity-60 group-hover:opacity-100 transition-opacity" />
          </button>
        </div>
      )}

      {collapsed && (
        <div className="p-2 border-b border-white/5 flex justify-center">
          <button
            onClick={toggleMode}
            className={`p-2 rounded-lg border transition-all ${
              isDesigner ? 'bg-amber-500/20 border-amber-500/40 text-amber-300' : 'bg-indigo-600/20 border-indigo-500/40 text-indigo-300'
            }`}
            title={isDesigner ? 'العودة للوحة الإدارة العامة' : 'التبديل إلى لوحة المصمم'}
          >
            {isDesigner ? <Wand2 className="w-4 h-4" /> : <Palette className="w-4 h-4" />}
          </button>
        </div>
      )}

      <nav className="flex-1 overflow-y-auto px-2 py-3 space-y-0.5 custom-scrollbar">
        {currentNavItems.map(item => (
          <NavLink
            key={item.to}
            to={item.to}
            end={'end' in item ? item.end : false}
            className={({ isActive }) =>
              `flex items-center gap-3 px-2.5 py-2 rounded-lg text-xs font-medium transition-all ${
                isActive
                  ? isDesigner
                    ? 'bg-amber-500/15 text-amber-300 border border-amber-500/25 font-bold shadow-sm'
                    : 'bg-indigo-500/10 text-indigo-300 border border-indigo-500/10'
                  : 'text-slate-400 border border-transparent hover:bg-white/5 hover:text-white'
              } ${lang === 'ar' ? 'flex-row-reverse' : ''}`
            }
            title={collapsed ? (('isCustom' in item && item.isCustom) ? item.label : t(item.label)) : undefined}
          >
            <item.icon className="w-4 h-4 shrink-0" />
            {!collapsed && <span className="truncate">{('isCustom' in item && item.isCustom) ? item.label : t(item.label)}</span>}
          </NavLink>
        ))}
      </nav>
      <div className="p-3 border-t border-white/5 shrink-0">
        <button
          onClick={() => logout()}
          className={`flex items-center gap-3 px-2.5 py-2 rounded-lg text-xs text-slate-500 hover:text-rose-400 hover:bg-rose-500/5 w-full transition-all ${lang === 'ar' ? 'flex-row-reverse' : ''}`}
          title={t('sign.out')}
        >
          <LogOut className="w-4 h-4 shrink-0" />
          {!collapsed && <span>{t('sign.out')}</span>}
        </button>
      </div>
    </aside>
    </>
  );
}
