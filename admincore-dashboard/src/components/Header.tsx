import { useLocation } from 'react-router-dom';
import { Search, X, Languages, Menu } from 'lucide-react';
import { useState, useContext } from 'react';
import { I18nContext, langs } from '../lib/i18n';

const pageTitles: Record<string, string> = {
  '/': 'nav.dashboard',
  '/users': 'nav.users',
  '/gifts': 'nav.gifts',
  '/store': 'nav.store',
  '/rooms': 'nav.rooms',
  '/unions': 'nav.unions',
  '/vip': 'nav.vip',
  '/vip-gifting': 'nav.vipGifting',
  '/levels': 'nav.levels',
  '/badges': 'nav.badges',
  '/necklaces': 'nav.necklaces',
  '/badge-necklace-gifts': 'Badge & Necklace Gifts',
  '/banners': 'nav.banners',
  '/agency': 'nav.agency',
  '/cp': 'nav.cp',
  '/cp-features': 'CP Features',
  '/bd': 'nav.bd',
  '/app-assets': 'nav.appAssets',
  '/app-sounds': 'nav.appSounds',
  '/audio-settings': 'nav.audioSettings',
  '/app-icons': 'nav.appIcons',
  '/visual-manager': 'المظهر الشامل',
  '/image-customize': 'nav.images',
  '/color-customize': 'nav.colors',
  '/screen-customization': 'nav.screenVisuals',
  '/app-visual-designer': 'nav.appVisualDesigner',
  '/recharge-event': 'nav.rechargeEvent',
  '/lucky-gifts': 'nav.luckyGifts',
  '/red-packets': 'المظاريف وصناديق الحظ 🧧',
  '/tasks-manager': 'مركز المهام والمكافآت',
  '/gift-items': 'nav.giftItems',
  '/gift-categories': 'nav.giftCategories',
  '/gift-banner-configs': 'nav.giftBannerConfigs',
  '/signin-features': 'nav.signin',
  '/app-updates': 'App Updates',
  '/profile-customize': 'nav.profileCustomize',
  '/error-analysis': 'nav.errors',
  '/admins': 'nav.admins',
  '/notifications': 'nav.notifications',
  '/reports': 'البلاغات',
  '/emojis': 'الإيموجي',
  '/room-backgrounds': 'خلفيات الغرف',
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
    <header className={`h-14 shrink-0 border-b border-white/5 flex items-center justify-between px-2.5 sm:px-4 lg:px-6 bg-[#0D0D0E] z-30 ${lang === 'ar' ? 'flex-row-reverse' : ''}`}>
      <div className={`flex items-center gap-1.5 sm:gap-2.5 min-w-0 ${lang === 'ar' ? 'flex-row-reverse' : ''}`}>
        <button
          onClick={onMenuClick}
          aria-label="Open menu"
          className="lg:hidden p-2 rounded-lg text-slate-300 hover:text-white hover:bg-white/10 active:scale-95 transition-all shrink-0"
        >
          <Menu className="w-5 h-5" />
        </button>
        <div className={`flex items-center gap-1.5 sm:gap-2.5 min-w-0 ${lang === 'ar' ? 'flex-row-reverse' : ''}`}>
          <span className="text-slate-500 text-xs uppercase tracking-wider font-bold hidden md:inline">Zero</span>
          <span className="text-slate-600 text-sm hidden md:inline">/</span>
          <span className="text-white text-xs sm:text-sm font-bold truncate max-w-[120px] xs:max-w-[160px] sm:max-w-none">{title}</span>
        </div>
      </div>
      <div className={`flex items-center gap-2 sm:gap-4 shrink-0 ${lang === 'ar' ? 'flex-row-reverse' : ''}`}>
        <div className="relative">
          <Search className={`w-3.5 h-3.5 absolute top-1/2 -translate-y-1/2 text-slate-500 pointer-events-none ${lang === 'ar' ? 'right-2.5' : 'left-2.5'}`} />
          <input
            type="text"
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder={t('search')}
            className={`bg-[#161618] border border-white/10 rounded-full py-1.5 ${lang === 'ar' ? 'pr-8 pl-3' : 'pl-8 pr-3'} text-xs w-24 xs:w-32 sm:w-48 text-white focus:outline-none focus:border-indigo-500 placeholder:text-slate-600 transition-all`}
          />
          {search && (
            <button onClick={() => setSearch('')} className={`absolute top-1/2 -translate-y-1/2 text-slate-400 hover:text-white ${lang === 'ar' ? 'left-2.5' : 'right-2.5'}`}>
              <X className="w-3 h-3" />
            </button>
          )}
        </div>
        <div className="relative">
          <button onClick={() => setShowLang(!showLang)} className="p-1.5 sm:p-2 rounded-full border border-white/5 bg-[#141417] text-slate-400 hover:text-white hover:bg-white/10 transition-colors">
            <Languages className="w-3.5 h-3.5 sm:w-4 sm:h-4" />
          </button>
          {showLang && (
            <div className={`absolute top-full mt-1.5 ${lang === 'ar' ? 'left-0' : 'right-0'} bg-[#1c1c1f] border border-white/10 rounded-xl py-1 min-w-[110px] z-50 shadow-2xl animate-fade-in`}>
              {langs.map(l => (
                <button key={l.code} onClick={() => { setLang(l.code); setShowLang(false); }} className={`w-full text-left px-3 py-2 text-xs transition-colors ${lang === l.code ? 'text-indigo-400 bg-indigo-500/10 font-bold' : 'text-slate-400 hover:text-white hover:bg-white/5'}`}>
                  {l.label}
                </button>
              ))}
            </div>
          )}
        </div>
        <div className={`flex items-center gap-2 pl-1 sm:pl-2 border-l border-white/5 ${lang === 'ar' ? 'flex-row-reverse border-r border-l-0 pr-1 sm:pr-2' : ''}`}>
          <div className="w-7 h-7 sm:w-8 sm:h-8 rounded-full bg-gradient-to-tr from-indigo-600 to-rose-500 flex items-center justify-center font-bold text-[11px] sm:text-xs text-white select-none shadow-md">
            A
          </div>
          <div className={`hidden lg:flex flex-col ${lang === 'ar' ? 'text-right' : ''}`}>
            <span className="text-xs text-white font-medium leading-tight">Admin</span>
            <span className="text-[9px] text-slate-500 font-mono leading-none">Super Admin</span>
          </div>
        </div>
      </div>
    </header>
  );
}
