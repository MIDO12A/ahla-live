import { useLocation } from 'react-router-dom';
import { Search, X, Languages, Menu, Bell } from 'lucide-react';
import { useState, useContext } from 'react';
import { I18nContext, langs } from '../lib/i18n';

const pageTitles: Record<string, string> = {
  '/': 'nav.dashboard',
  '/recharge-settings': 'nav.rechargeSettings',
  '/users': 'nav.users',
  '/gifts': 'nav.gifts',
  '/store': 'nav.store',
  '/user-gifting': 'nav.userGifting',
  '/rooms': 'nav.rooms',
  '/room-cup': 'nav.roomCup',
  '/game-pool': 'nav.gamePool',
  '/unions': 'nav.unions',
  '/vip': 'nav.vip',
  '/vip-gifting': 'nav.vipGifting',
  '/levels': 'nav.levels',
  '/badges': 'nav.badges',
  '/necklaces': 'nav.necklaces',
  '/badge-necklace-gifts': 'nav.badgeNecklaceGifts',
  '/banners': 'nav.banners',
  '/agency': 'nav.agency',
  '/cp': 'nav.cp',
  '/cp-features': 'nav.cpFeatures',
  '/bd': 'nav.bd',
  '/app-assets': 'nav.appAssets',
  '/app-sounds': 'nav.appSounds',
  '/audio-settings': 'nav.audioSettings',
  '/app-icons': 'nav.appIcons',
  '/design-center': 'nav.designCenter',
  '/visual-manager': 'nav.visualManager',
  '/image-customize': 'nav.images',
  '/color-customize': 'nav.colors',
  '/screen-customization': 'nav.screenVisuals',
  '/app-visual-designer': 'nav.appVisualDesigner',
  '/recharge-event': 'nav.rechargeEvent',
  '/lucky-gifts': 'nav.luckyGifts',
  '/red-packets': 'nav.redPackets',
  '/tasks-manager': 'nav.tasksManager',
  '/gift-items': 'nav.giftItems',
  '/gift-categories': 'nav.giftCategories',
  '/gift-banner-configs': 'nav.giftBannerConfigs',
  '/signin-features': 'nav.signin',
  '/app-updates': 'nav.appUpdates',
  '/super-admin-management': 'nav.superAdminMgmt',
  '/profile-customize': 'nav.profileCustomize',
  '/error-analysis': 'nav.errors',
  '/admins': 'nav.admins',
  '/notifications': 'nav.notifications',
  '/reports': 'nav.reports',
  '/emojis': 'nav.emojis',
  '/room-backgrounds': 'nav.roomBackgrounds',
  '/settings': 'nav.settings',
};

export default function Header({ onMenuClick }: { onMenuClick?: () => void }) {
  const location = useLocation();
  const { t, lang, setLang } = useContext(I18nContext);
  const [search, setSearch] = useState('');
  const [showLang, setShowLang] = useState(false);
  const titleKey = pageTitles[location.pathname] || '';
  const title = titleKey ? (titleKey.startsWith('nav.') ? t(titleKey) : titleKey) : 'Admin';

  return (
    <header className="h-16 shrink-0 glass border-b border-white/8 flex items-center justify-between px-2.5 sm:px-4 lg:px-6 z-30 relative">
      <div className="flex items-center gap-1.5 sm:gap-2.5 min-w-0">
        <button
          onClick={onMenuClick}
          aria-label="Open menu"
          className="lg:hidden p-2 rounded-xl text-slate-300 hover:text-white hover:bg-white/10 active:scale-95 transition-all shrink-0"
        >
          <Menu className="w-5 h-5" />
        </button>
        <div className="flex items-center gap-1.5 sm:gap-2.5 min-w-0">
          <span className="text-indigo-300/60 text-[10px] uppercase tracking-[0.18em] font-bold hidden md:inline">Ahla Live</span>
          <span className="text-slate-700 text-sm hidden md:inline">/</span>
          <span className="text-white text-xs sm:text-sm font-bold truncate max-w-[120px] xs:max-w-[160px] sm:max-w-none">{title}</span>
        </div>
      </div>

      <div className="flex items-center gap-2 sm:gap-3 shrink-0">
        <div className="relative hidden sm:block">
          <Search className={`w-3.5 h-3.5 absolute top-1/2 -translate-y-1/2 text-slate-500 pointer-events-none ${lang === 'ar' ? 'right-3' : 'left-3'}`} />
          <input
            type="text"
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder={t('search')}
            className={`input-3d rounded-full py-2 ${lang === 'ar' ? 'pr-9 pl-3' : 'pl-9 pr-3'} text-xs w-36 sm:w-56 text-white focus:outline-none placeholder:text-slate-600`}
          />
          {search && (
            <button onClick={() => setSearch('')} className={`absolute top-1/2 -translate-y-1/2 text-slate-400 hover:text-white ${lang === 'ar' ? 'left-3' : 'right-3'}`}>
              <X className="w-3 h-3" />
            </button>
          )}
        </div>

        <button className="relative p-2 rounded-xl border border-white/8 bg-white/5 text-slate-400 hover:text-white hover:bg-white/10 transition-colors active:scale-95">
          <Bell className="w-4 h-4" />
          <span className="absolute top-1.5 right-1.5 w-1.5 h-1.5 rounded-full bg-rose-500 shadow-[0_0_6px_rgba(244,63,94,0.8)]" />
        </button>

        <div className="relative">
          <button
            onClick={() => setShowLang(!showLang)}
            className="p-2 rounded-xl border border-white/8 bg-white/5 text-slate-400 hover:text-white hover:bg-white/10 transition-colors active:scale-95"
          >
            <Languages className="w-4 h-4" />
          </button>
          {showLang && (
            <div className={`absolute top-full mt-2 ${lang === 'ar' ? 'left-0' : 'right-0'} glass-strong rounded-xl py-1.5 min-w-[120px] z-50 shadow-2xl shadow-black/50 animate-fade-in`}>
              {langs.map(l => (
                <button
                  key={l.code}
                  onClick={() => { setLang(l.code); setShowLang(false); }}
                  className={`w-full text-left px-3 py-2 text-xs transition-colors ${
                    lang === l.code ? 'text-indigo-300 bg-indigo-500/10 font-bold' : 'text-slate-400 hover:text-white hover:bg-white/5'
                  }`}
                >
                  {l.label}
                </button>
              ))}
            </div>
          )}
        </div>

        <div className={`flex items-center gap-2.5 ${lang === 'ar' ? 'border-r pr-2 sm:pr-3' : 'border-l pl-2 sm:pl-3'} border-white/8`}>
          <div className="relative w-8 h-8 rounded-full bg-gradient-to-tr from-indigo-600 to-rose-500 flex items-center justify-center font-bold text-xs text-white select-none shadow-lg shadow-indigo-600/30 ring-2 ring-white/10">
            A
          </div>
          <div className="hidden lg:flex flex-col">
            <span className="text-xs text-white font-semibold leading-tight">Admin</span>
            <span className="text-[9px] text-indigo-300/50 font-mono leading-none tracking-wider">SUPER ADMIN</span>
          </div>
        </div>
      </div>
    </header>
  );
}
