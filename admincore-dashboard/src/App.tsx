import { useEffect, useState } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { onAuthChange, type AppUser } from './lib/auth';
import { I18nContext } from './lib/i18n';
import type { Lang } from './lib/i18n';
import Layout from './components/Layout';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import Users from './pages/Users';
import Gifts from './pages/Gifts';
import Store from './pages/Store';
import Rooms from './pages/Rooms';
import Unions from './pages/Unions';
import VIP from './pages/VIP';
import VIPGifting from './pages/VIPGifting';
import Levels from './pages/Levels';
import Badges from './pages/Badges';
import Necklaces from './pages/Necklaces';
import BadgeNecklaceGifts from './pages/BadgeNecklaceGifts';
import Agency from './pages/Agency';
import BD from './pages/BD';
import ImageCustomize from './pages/ImageCustomize';
import ColorCustomize from './pages/ColorCustomize';
import ErrorAnalysis from './pages/ErrorAnalysis';
import Notifications from './pages/Notifications';
import Settings from './pages/Settings';
import Banners from './pages/Banners';
import GiftItems from './pages/GiftItems';
import GiftCategories from './pages/GiftCategories';
import GiftBannerConfigs from './pages/GiftBannerConfigs';
import AppAssets from './pages/AppAssets';
import ProfileCustomize from './pages/ProfileCustomize';
import AdminManagement from './pages/AdminManagement';
import VisualManager from './pages/VisualManager';
import ScreenCustomization from './pages/ScreenCustomization';
import AppVisualDesigner from './pages/AppVisualDesigner';
import AppIcons from './pages/AppIcons';
import CpFeatures from './pages/CpFeatures';
import SigninFeatures from './pages/SigninFeatures';
import AppUpdates from './pages/AppUpdates';
import Reports from './pages/Reports';
import Emojis from './pages/Emojis';
import RoomBackgrounds from './pages/RoomBackgrounds';
import LuckyGiftsManager from './pages/LuckyGiftsManager';
import RedPacketsManager from './pages/RedPacketsManager';
import TasksManager from './pages/TasksManager';
import AppSounds from './pages/AppSounds';
import ZegoAudioSettings from './pages/ZegoAudioSettings';
import RechargeEventManager from './pages/RechargeEventManager';
import t from './lib/i18n';

export default function App() {
  const [user, setUser] = useState<AppUser | null>(null);
  const [loading, setLoading] = useState(true);
  const [lang, setLang] = useState<Lang>('ar');

  useEffect(() => {
    const stored = localStorage.getItem('admin_lang');
    if (stored === 'ar' || stored === 'en') setLang(stored);
    const unsub = onAuthChange(u => {
      setUser(u);
      setLoading(false);
      if (u) {
        import('./lib/supabase').then(({ ensureAdminBootstrap }) => {
          ensureAdminBootstrap(u.id, u.email, u.displayName).then(r => {
            if (r.created) window.location.reload();
          });
        });
      }
    });
    return unsub;
  }, []);

  useEffect(() => {
    localStorage.setItem('admin_lang', lang);
    document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
    document.documentElement.lang = lang;
  }, [lang]);

  if (loading) {
    return (
      <div className="min-h-screen bg-[#0A0A0B] flex items-center justify-center">
        <div className="text-slate-500 text-xs">Loading...</div>
      </div>
    );
  }

  const ctx = {
    lang,
    setLang: (l: Lang) => setLang(l),
    t: (key: string) => t(key, lang),
  };

  return (
    <I18nContext.Provider value={ctx}>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={user ? <Navigate to="/" replace /> : <Login />} />
          <Route element={user ? <Layout /> : <Navigate to="/login" replace />}>
            <Route path="/" element={<Dashboard />} />
            <Route path="/users" element={<Users />} />
            <Route path="/gifts" element={<Gifts />} />
            <Route path="/store" element={<Store />} />
            <Route path="/rooms" element={<Rooms />} />
            <Route path="/lucky-gifts" element={<LuckyGiftsManager />} />
            <Route path="/red-packets" element={<RedPacketsManager />} />
            <Route path="/tasks-manager" element={<TasksManager />} />
            <Route path="/unions" element={<Unions />} />
            <Route path="/vip" element={<VIP />} />
            <Route path="/vip-gifting" element={<VIPGifting />} />
            <Route path="/levels" element={<Levels />} />
            <Route path="/badges" element={<Badges />} />
            <Route path="/necklaces" element={<Necklaces />} />
            <Route path="/badge-necklace-gifts" element={<BadgeNecklaceGifts />} />
            <Route path="/agency" element={<Agency />} />
            <Route path="/bd" element={<BD />} />
            <Route path="/app-assets" element={<AppAssets />} />
            <Route path="/image-customize" element={<ImageCustomize />} />
            <Route path="/color-customize" element={<ColorCustomize />} />
            <Route path="/error-analysis" element={<ErrorAnalysis />} />
            <Route path="/gift-items" element={<GiftItems />} />
            <Route path="/gift-categories" element={<GiftCategories />} />
            <Route path="/gift-banner-configs" element={<GiftBannerConfigs />} />
            <Route path="/banners" element={<Banners />} />
            <Route path="/notifications" element={<Notifications />} />
            <Route path="/profile-customize" element={<ProfileCustomize />} />
            <Route path="/admins" element={<AdminManagement currentUser={user} />} />
            <Route path="/settings" element={<Settings />} />
            <Route path="/visual-manager" element={<VisualManager />} />
            <Route path="/screen-customization" element={<ScreenCustomization />} />
            <Route path="/app-visual-designer" element={<AppVisualDesigner />} />
            <Route path="/app-icons" element={<AppIcons />} />
            <Route path="/cp-features" element={<CpFeatures />} />
            <Route path="/signin-features" element={<SigninFeatures />} />
            <Route path="/app-updates" element={<AppUpdates />} />
            <Route path="/reports" element={<Reports />} />
            <Route path="/emojis" element={<Emojis />} />
            <Route path="/room-backgrounds" element={<RoomBackgrounds />} />
            <Route path="/app-sounds" element={<AppSounds />} />
            <Route path="/audio-settings" element={<ZegoAudioSettings />} />
            <Route path="/zego-audio" element={<ZegoAudioSettings />} />
            <Route path="/recharge-event" element={<RechargeEventManager />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </I18nContext.Provider>
  );
}
