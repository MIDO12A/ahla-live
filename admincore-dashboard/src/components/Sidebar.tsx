import { NavLink } from 'react-router-dom';
import {
  LayoutDashboard, Users, Gift, Store, DoorOpen,
  Building2, Crown, BarChart3, Award, Handshake,
  TrendingUp, Palette, Bug,
  Bell, Settings, Shield, ChevronLeft, LogOut, SlidersHorizontal, Gift as GiftIcon,
  Tag, Sparkles, ImageIcon, Calendar, Rocket, CheckSquare, Volume2, Mic, User, Zap, X, Coins, Trophy,
  Gamepad2,
} from 'lucide-react';
import { logout, type AppUser } from '../lib/auth';
import { useContext } from 'react';
import { I18nContext } from '../lib/i18n';
import { canUserAccess } from '../lib/permissions';

const navItems = [
  { to: '/', icon: LayoutDashboard, label: 'nav.dashboard', end: true, permKey: 'dashboard' },
  { to: '/recharge-settings', icon: Coins, label: 'nav.rechargeSettings', permKey: 'recharge_settings' },
  { to: '/recharge-event', icon: Zap, label: 'nav.rechargeEvent', permKey: 'recharge_event' },
  { to: '/users', icon: Users, label: 'nav.users', permKey: 'users' },
  { to: '/gifts', icon: Gift, label: 'nav.gifts', permKey: 'gifts' },
  { to: '/store', icon: Store, label: 'nav.store', permKey: 'store' },
  { to: '/user-gifting', icon: GiftIcon, label: 'nav.userGifting', permKey: 'user_gifting' },
  { to: '/rooms', icon: DoorOpen, label: 'nav.rooms', permKey: 'rooms' },
  { to: '/room-cup', icon: Trophy, label: 'nav.roomCup', permKey: 'rooms' },
  { to: '/game-pool', icon: Gamepad2, label: 'nav.gamePool', permKey: 'rooms' },
  { to: '/lucky-gifts', icon: Sparkles, label: 'nav.luckyGifts', permKey: 'lucky_gifts' },
  { to: '/red-packets', icon: Gift, label: 'nav.redPackets', permKey: 'red_packets' },
  { to: '/tasks-manager', icon: CheckSquare, label: 'nav.tasksManager', permKey: 'tasks_manager' },
  { to: '/unions', icon: Building2, label: 'nav.unions', permKey: 'unions' },
  { to: '/vip', icon: Crown, label: 'nav.vip', permKey: 'vip' },
  { to: '/vip-gifting', icon: GiftIcon, label: 'nav.vipGifting', permKey: 'vip_gifting' },
  { to: '/levels', icon: BarChart3, label: 'nav.levels', permKey: 'levels' },
  { to: '/badges', icon: Award, label: 'nav.badges', permKey: 'badges' },
  { to: '/necklaces', icon: Crown, label: 'nav.necklaces', permKey: 'necklaces' },
  { to: '/badge-necklace-gifts', icon: GiftIcon, label: 'nav.badgeNecklaceGifts', permKey: 'badge_necklace_gifts' },
  { to: '/design-center', icon: Palette, label: 'nav.designCenter', permKey: 'visual_manager' },
  { to: '/app-sounds', icon: Volume2, label: 'nav.appSounds', permKey: 'app_sounds' },
  { to: '/audio-settings', icon: Mic, label: 'nav.audioSettings', permKey: 'audio_settings' },
  { to: '/gift-items', icon: Gift, label: 'nav.giftItems', permKey: 'gift_items' },
  { to: '/gift-categories', icon: Tag, label: 'nav.giftCategories', permKey: 'gift_categories' },
  { to: '/banners', icon: SlidersHorizontal, label: 'nav.banners', permKey: 'banners' },
  { to: '/agency', icon: Handshake, label: 'nav.agency', permKey: 'agency' },
  { to: '/cp-features', icon: Gift, label: 'nav.cpFeatures', permKey: 'cp_features' },
  { to: '/signin-features', icon: Calendar, label: 'nav.signin', permKey: 'signin_features' },
  { to: '/app-updates', icon: Rocket, label: 'nav.appUpdates', permKey: 'app_updates' },
  { to: '/super-admin-management', icon: Crown, label: 'nav.superAdminMgmt', permKey: 'super_admin_mgmt' },
  { to: '/bd', icon: TrendingUp, label: 'nav.bd', permKey: 'bd' },
  { to: '/profile-customize', icon: User, label: 'nav.profileCustomize', permKey: 'profile_customize' },
  { to: '/error-analysis', icon: Bug, label: 'nav.errors', permKey: 'error_analysis' },
  { to: '/admins', icon: Shield, label: 'nav.admins', permKey: 'admins' },
  { to: '/notifications', icon: Bell, label: 'nav.notifications', permKey: 'notifications' },
  { to: '/reports', icon: Shield, label: 'nav.reports', permKey: 'reports' },
  { to: '/emojis', icon: ImageIcon, label: 'nav.emojis', permKey: 'emojis' },
  { to: '/room-backgrounds', icon: ImageIcon, label: 'nav.roomBackgrounds', permKey: 'room_backgrounds' },
  { to: '/settings', icon: Settings, label: 'nav.settings', permKey: 'settings' },
];

function Brand({ collapsed = false, lang }: { collapsed?: boolean; lang: string }) {
  return (
    <div className="flex items-center gap-2.5 min-w-0">
      <div className="relative w-9 h-9 rounded-xl bg-gradient-to-tr from-indigo-600 via-violet-600 to-fuchsia-500 flex items-center justify-center text-white font-black text-sm shadow-lg shadow-indigo-600/30 ring-1 ring-white/20">
        Z
        <span className="absolute inset-0 rounded-xl bg-gradient-to-b from-white/25 to-transparent opacity-60" />
      </div>
      {!collapsed && (
        <div className="min-w-0">
          <span className="text-white font-bold text-sm block leading-tight truncate" style={{ fontFamily: lang === 'ar' ? 'system-ui' : 'inherit' }}>
            {lang === 'ar' ? 'لوحة التحكم' : 'Control Panel'}
          </span>
          <span className="text-[10px] text-indigo-300/60 font-mono tracking-wider">ADMIN · 3D</span>
        </div>
      )}
    </div>
  );
}

export default function Sidebar({
  collapsed,
  onToggle,
  mobileOpen,
  onMobileClose,
  currentUser,
}: {
  collapsed: boolean;
  onToggle: () => void;
  mobileOpen?: boolean;
  onMobileClose?: () => void;
  currentUser?: AppUser | null;
}) {
  const { t, lang } = useContext(I18nContext);
  const visibleNavItems = navItems.filter(item => canUserAccess(currentUser, item.permKey));

  return (
    <>
      {/* Mobile overlay sidebar drawer */}
      <aside
        className={`fixed inset-y-0 z-50 lg:hidden transition-transform duration-300 ease-in-out glass-strong shadow-2xl shadow-black/60 flex flex-col w-72 max-w-[85vw] ${
          lang === 'ar'
            ? `right-0 border-l border-white/10 ${mobileOpen ? 'translate-x-0' : 'translate-x-full'}`
            : `left-0 border-r border-white/10 ${mobileOpen ? 'translate-x-0' : '-translate-x-full'}`
        }`}
      >
        <div className="p-4 flex items-center justify-between border-b border-white/8 h-16 shrink-0">
          <Brand lang={lang} />
          <button
            onClick={onMobileClose}
            className="p-2 rounded-lg text-slate-400 hover:text-white hover:bg-white/10 transition-colors"
            aria-label="Close menu"
          >
            <X className="w-5 h-5" />
          </button>
        </div>
        <nav className="flex-1 overflow-y-auto px-2.5 py-3 space-y-1 custom-scrollbar">
          {visibleNavItems.map(item => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.end}
              onClick={onMobileClose}
              className={({ isActive }) =>
                `group flex items-center gap-3 px-3 py-2.5 rounded-xl text-xs font-medium transition-all duration-200 ${
                  isActive
                    ? 'sidebar-item-active text-white'
                    : 'text-slate-400 border border-transparent hover:bg-white/5 hover:text-white hover:translate-x-0.5 rtl:hover:-translate-x-0.5'
                }`
              }
            >
              <item.icon className="w-4 h-4 shrink-0 transition-transform group-hover:scale-110" />
              <span className="truncate">{t(item.label)}</span>
            </NavLink>
          ))}
        </nav>
        <div className="p-3 border-t border-white/8 shrink-0">
          <button
            onClick={() => logout()}
            className="flex items-center gap-3 px-3 py-2.5 rounded-xl text-xs text-rose-400 hover:bg-rose-500/10 hover:text-rose-300 w-full transition-all active:scale-[0.98]"
          >
            <LogOut className="w-4 h-4 shrink-0" />
            <span>{t('sign.out')}</span>
          </button>
        </div>
      </aside>

      {/* Desktop sidebar */}
      <aside
        className={`${collapsed ? 'w-[76px]' : 'w-60'} transition-[width] duration-300 ease-out glass border-white/8 flex flex-col shrink-0 ${
          lang === 'ar' ? 'border-l border-r-0' : 'border-r'
        } hidden lg:flex h-screen sticky top-0`}
      >
        <div className={`flex items-center border-b border-white/8 h-16 shrink-0 ${collapsed ? 'justify-center px-2' : 'justify-between px-4'}`}>
          <Brand collapsed={collapsed} lang={lang} />
          {!collapsed && (
            <button
              onClick={onToggle}
              className="p-1.5 rounded-lg text-slate-500 hover:text-white hover:bg-white/10 transition-colors"
              aria-label="Collapse sidebar"
            >
              <ChevronLeft className={`w-4 h-4 transition-transform ${lang === 'ar' ? 'rotate-180' : ''}`} />
            </button>
          )}
        </div>

        {collapsed && (
          <button
            onClick={onToggle}
            className="mx-auto mt-3 p-1.5 rounded-lg text-slate-500 hover:text-white hover:bg-white/10 transition-colors"
            aria-label="Expand sidebar"
          >
            <ChevronLeft className="w-4 h-4 rotate-180" />
          </button>
        )}

        <nav className="flex-1 overflow-y-auto px-2 py-3 space-y-1 custom-scrollbar">
          {visibleNavItems.map(item => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.end}
              className={({ isActive }) =>
                `group flex items-center gap-3 rounded-xl text-xs font-medium transition-all duration-200 ${
                  collapsed ? 'justify-center px-2 py-2.5' : 'px-3 py-2.5'
                } ${
                  isActive
                    ? 'sidebar-item-active text-white'
                    : 'text-slate-400 border border-transparent hover:bg-white/5 hover:text-white hover:translate-x-0.5 rtl:hover:-translate-x-0.5'
                }`
              }
              title={collapsed ? t(item.label) : undefined}
            >
              <item.icon className="w-4 h-4 shrink-0 transition-transform group-hover:scale-110" />
              {!collapsed && <span className="truncate">{t(item.label)}</span>}
            </NavLink>
          ))}
        </nav>

        <div className="p-3 border-t border-white/8 shrink-0">
          <button
            onClick={() => logout()}
            className={`flex items-center gap-3 rounded-xl text-xs text-slate-500 hover:text-rose-400 hover:bg-rose-500/10 w-full transition-all ${
              collapsed ? 'justify-center px-2 py-2.5' : 'px-3 py-2.5'
            }`}
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
