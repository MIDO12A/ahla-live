import { useContext, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { I18nContext, langs } from '../lib/i18n';
import { getCloudinaryStatus, saveCloudinaryConfig } from '../lib/storage';
import { supabase, isAdminConnected } from '../lib/supabase';
import { useDashboardMode } from '../lib/dashboardMode';
import { Save, Crown, Database, Mic, ArrowLeft, Wand2, Palette, Eye, Phone, SlidersHorizontal, Image, Sparkles } from 'lucide-react';

export default function Settings() {
  const navigate = useNavigate();
  const { t, lang, setLang } = useContext(I18nContext);
  const { isDesigner, toggleMode, setMode } = useDashboardMode();
  const [cloudName, setCloudName] = useState('');
  const [apiKey, setApiKey] = useState('');
  const [apiSecret, setApiSecret] = useState('');
  const [saving, setSaving] = useState(false);
  const [vipUrl, setVipUrl] = useState('');
  const [vipSaving, setVipSaving] = useState(false);
  const [supabaseServiceKey, setSupabaseServiceKey] = useState('');
  const [supabaseSaving, setSupabaseSaving] = useState(false);

  useEffect(() => {
    const status = getCloudinaryStatus();
    setCloudName(status.cloudName);
    const raw = localStorage.getItem('cloudinary_config');
    if (raw) {
      try {
        const cfg = JSON.parse(raw);
        setApiKey(cfg.apiKey || '');
        setApiSecret(cfg.apiSecret || '');
      } catch {}
    } else {
      setApiKey(localStorage.getItem('cloudinary_api_key') || '');
      setApiSecret(localStorage.getItem('cloudinary_api_secret') || '');
    }
    supabase.from('app_config').select('value').eq('key', 'vip_url').maybeSingle().then(res => {
      if (res?.data?.value) setVipUrl(String(res.data.value));
    });
  }, []);

  const handleSaveCloudinary = () => {
    setSaving(true);
    saveCloudinaryConfig(cloudName, apiKey, apiSecret);
    setSaving(false);
    alert(t('cloudinary.save') + ' ✓');
  };

  const handleSaveVipUrl = async () => {
    setVipSaving(true);
    try {
      const { error } = await supabase.from('app_config').upsert(
        { key: 'vip_url', value: vipUrl },
        { onConflict: 'key' }
      );
      if (error) throw error;
      alert('VIP URL saved ✓');
    } catch (e) {
      alert('Save failed: ' + (e as Error).message);
    }
    setVipSaving(false);
  };

  const status = getCloudinaryStatus();

  return (
    <div className="space-y-6 max-w-3xl">
      <div>
        <h2 className="text-white text-lg font-semibold">{t('settings.title')}</h2>
        <p className="text-slate-500 text-xs mt-0.5">{t('settings.description')}</p>
      </div>

      <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-6">
        {/* Designer Mode Switcher Card */}
        <div className={`rounded-xl border p-5 transition-all ${
          isDesigner
            ? 'bg-gradient-to-br from-amber-500/10 via-pink-500/5 to-purple-500/10 border-amber-500/30 shadow-lg shadow-amber-500/5'
            : 'bg-[#18181c] border-white/10'
        }`}>
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
            <div className="space-y-1">
              <div className="flex items-center gap-2">
                <span className="p-2 rounded-lg bg-amber-500/20 text-amber-400">
                  <Palette className="w-5 h-5" />
                </span>
                <div>
                  <h3 className="text-sm font-bold text-white flex items-center gap-2">
                    <span>{lang === 'ar' ? 'وضع لوحة المصمم (Designer Dashboard)' : 'Designer Dashboard Mode'}</span>
                    <span className={`text-[10px] px-2 py-0.5 rounded-full font-bold uppercase ${
                      isDesigner ? 'bg-amber-500/20 text-amber-300 border border-amber-500/40' : 'bg-slate-700 text-slate-300'
                    }`}>
                      {isDesigner ? (lang === 'ar' ? 'مفعل الآن 🎨' : 'Active') : (lang === 'ar' ? 'لوحة الإدارة 🏢' : 'Standard')}
                    </span>
                  </h3>
                  <p className="text-xs text-slate-400 mt-0.5">
                    {lang === 'ar'
                      ? 'عند تفعيل هذا الخيار، تتحول القائمة الجانبية لعرض أدوات تصميم الواجهات والألوان والخلفيات والأصول.'
                      : 'Switch between standard admin panel and visual designer tools for screens, assets, and themes.'}
                  </p>
                </div>
              </div>
            </div>

            <button
              onClick={toggleMode}
              className={`px-4 py-2.5 rounded-xl font-bold text-xs flex items-center justify-center gap-2 transition-all shadow-md shrink-0 active:scale-95 ${
                isDesigner
                  ? 'bg-gradient-to-r from-amber-500 to-pink-600 hover:from-amber-600 hover:to-pink-700 text-white shadow-amber-500/20'
                  : 'bg-indigo-600 hover:bg-indigo-500 text-white shadow-indigo-600/20'
              }`}
            >
              {isDesigner ? <Wand2 className="w-4 h-4" /> : <Palette className="w-4 h-4" />}
              <span>
                {isDesigner
                  ? (lang === 'ar' ? 'التبديل إلى لوحة الإدارة 🏢' : 'Switch to Admin')
                  : (lang === 'ar' ? 'التبديل إلى لوحة المصمم 🎨' : 'Switch to Designer Mode')}
              </span>
            </button>
          </div>

          {/* Quick Access to Designer Tools */}
          <div className="mt-4 pt-4 border-t border-white/10">
            <span className="text-[10px] uppercase font-bold text-slate-400 block mb-2">
              {lang === 'ar' ? 'الوصول المباشر لأدوات المصمم والشاشات:' : 'Direct Access to Designer Tools:'}
            </span>
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2">
              <button
                onClick={() => { setMode('designer'); navigate('/visual-manager'); }}
                className="p-2.5 rounded-lg bg-black/30 hover:bg-white/5 border border-white/5 hover:border-amber-500/30 flex items-center gap-2 text-right transition-all group"
              >
                <Eye className="w-4 h-4 text-amber-400 shrink-0 group-hover:scale-110 transition-transform" />
                <div className="min-w-0">
                  <div className="text-xs font-semibold text-white truncate">{lang === 'ar' ? 'المظهر الشامل' : 'Visual Manager'}</div>
                  <div className="text-[10px] text-slate-400 truncate">/visual-manager</div>
                </div>
              </button>

              <button
                onClick={() => { setMode('designer'); navigate('/app-visual-designer'); }}
                className="p-2.5 rounded-lg bg-black/30 hover:bg-white/5 border border-white/5 hover:border-amber-500/30 flex items-center gap-2 text-right transition-all group"
              >
                <Phone className="w-4 h-4 text-indigo-400 shrink-0 group-hover:scale-110 transition-transform" />
                <div className="min-w-0">
                  <div className="text-xs font-semibold text-white truncate">{lang === 'ar' ? 'مصمم الواجهات' : 'App Designer'}</div>
                  <div className="text-[10px] text-slate-400 truncate">/app-visual-designer</div>
                </div>
              </button>

              <button
                onClick={() => { setMode('designer'); navigate('/screen-customization'); }}
                className="p-2.5 rounded-lg bg-black/30 hover:bg-white/5 border border-white/5 hover:border-amber-500/30 flex items-center gap-2 text-right transition-all group"
              >
                <SlidersHorizontal className="w-4 h-4 text-emerald-400 shrink-0 group-hover:scale-110 transition-transform" />
                <div className="min-w-0">
                  <div className="text-xs font-semibold text-white truncate">{lang === 'ar' ? 'تخصيص الشاشات' : 'Screen Custom'}</div>
                  <div className="text-[10px] text-slate-400 truncate">/screen-customization</div>
                </div>
              </button>

              <button
                onClick={() => { setMode('designer'); navigate('/app-assets'); }}
                className="p-2.5 rounded-lg bg-black/30 hover:bg-white/5 border border-white/5 hover:border-amber-500/30 flex items-center gap-2 text-right transition-all group"
              >
                <Image className="w-4 h-4 text-pink-400 shrink-0 group-hover:scale-110 transition-transform" />
                <div className="min-w-0">
                  <div className="text-xs font-semibold text-white truncate">{lang === 'ar' ? 'أصول التطبيق' : 'App Assets'}</div>
                  <div className="text-[10px] text-slate-400 truncate">/app-assets</div>
                </div>
              </button>

              <button
                onClick={() => { setMode('designer'); navigate('/gift-banner-configs'); }}
                className="p-2.5 rounded-lg bg-black/30 hover:bg-white/5 border border-white/5 hover:border-amber-500/30 flex items-center gap-2 text-right transition-all group sm:col-span-2 md:col-span-1"
              >
                <Sparkles className="w-4 h-4 text-amber-300 shrink-0 group-hover:scale-110 transition-transform" />
                <div className="min-w-0">
                  <div className="text-xs font-semibold text-white truncate">{lang === 'ar' ? 'بانرات الهدايا' : 'Gift Banners'}</div>
                  <div className="text-[10px] text-slate-400 truncate">/gift-banner-configs</div>
                </div>
              </button>
            </div>
          </div>
        </div>
        <div>
          <label className="block text-[10px] uppercase text-slate-400 font-bold mb-2">Language / اللغة</label>
          <div className="flex gap-2">
            {langs.map(l => (
              <button
                key={l.code}
                onClick={() => setLang(l.code)}
                className={`px-4 py-2 rounded-lg text-xs font-semibold border transition-all ${
                  lang === l.code
                    ? 'bg-indigo-500/10 text-indigo-300 border-indigo-500/20'
                    : 'text-slate-400 border-white/5 hover:bg-white/5 hover:text-white'
                }`}
              >
                {l.label}
              </button>
            ))}
          </div>
          <p className="text-[9px] text-slate-600 mt-1.5">Change dashboard interface language</p>
        </div>

        <div>
          <label className="block text-[10px] uppercase text-slate-400 font-bold mb-2">Zego Audio & Voice Engine / محرك الصوت</label>
          <div className="bg-[#161618] rounded-lg border border-amber-500/20 p-4 space-y-3">
            <div className="flex items-center justify-between">
              <p className="text-xs text-slate-300 flex items-center gap-2">
                <Mic className="w-4 h-4 text-amber-400" />
                <span>إدارة مفاتيح Zego AppID و AppSign وجودة ومزود الصوت في الغرف</span>
              </p>
              <button
                onClick={() => navigate('/audio-settings')}
                className="px-3 py-1.5 bg-gradient-to-r from-amber-500 to-amber-600 hover:from-amber-600 hover:to-amber-700 text-[11px] text-black font-bold rounded-lg flex items-center gap-1.5 shadow"
              >
                <span>فتح لوحة تحكم الصوت</span>
                <ArrowLeft className="w-3.5 h-3.5" />
              </button>
            </div>
            <p className="text-[10px] text-slate-500">
              يتم حفظ المفاتيح سحابياً في Firebase Firestore ليتم تطبيقها فورياً على جميع مستخدمي التطبيق.
            </p>
          </div>
        </div>

        <div>
          <label className="block text-[10px] uppercase text-slate-400 font-bold mb-2">VIP URL</label>
          <div className="bg-[#161618] rounded-lg border border-white/5 p-4 space-y-3">
            <p className="text-xs text-slate-400 flex items-center gap-1.5">
              <Crown className="w-3.5 h-3.5 text-amber-400" />
              VIP Web App URL — التطبيق هيفتح الرابط ده في WebView
            </p>
            <input
              type="url"
              value={vipUrl}
              onChange={e => setVipUrl(e.target.value)}
              className="w-full bg-[#1c1c1f] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono"
              placeholder="https://your-domain.com/vip"
            />
            <button onClick={handleSaveVipUrl} disabled={vipSaving} className="px-3 py-1.5 bg-amber-600 hover:bg-amber-700 disabled:opacity-50 text-[10px] text-white font-semibold rounded-lg flex items-center gap-1">
              <Save className="w-3 h-3" /> {vipSaving ? t('saving') : 'Save VIP URL'}
            </button>
          </div>
        </div>

        <div>
          <label className="block text-[10px] uppercase text-slate-400 font-bold mb-2 flex items-center gap-1"><Database className="w-3 h-3" /> Supabase Service Role Key</label>
          <div className="bg-[#161618] rounded-lg border border-white/5 p-4 space-y-3">
            <p className="text-xs text-slate-400">
              {isAdminConnected()
                ? <><span className="text-green-400">✓</span> Service role configured — RLS bypass active</>
                : <><span className="text-rose-400">✗</span> Not configured — some features may not show all data</>
              }
            </p>
            <input
              type="password"
              value={supabaseServiceKey}
              onChange={e => setSupabaseServiceKey(e.target.value)}
              className="w-full bg-[#1c1c1f] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono"
              placeholder="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
            />
            <p className="text-[9px] text-slate-600">Paste your Supabase service_role key to bypass RLS and see all users/data</p>
            <button onClick={() => {
              setSupabaseSaving(true);
              localStorage.setItem('supabase_admin_config', JSON.stringify({
                supabaseUrl: 'https://mnpoiobmargjlnxwczgi.supabase.co',
                serviceRoleKey: supabaseServiceKey,
              }));
              setSupabaseSaving(false);
              alert('Supabase key saved! Page will refresh to apply changes.');
              setTimeout(() => window.location.reload(), 500);
            }} disabled={supabaseSaving} className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-[10px] text-white font-semibold rounded-lg flex items-center gap-1">
              <Save className="w-3 h-3" /> {supabaseSaving ? t('saving') : 'Save Supabase Key'}
            </button>
          </div>
        </div>

        <div>
          <label className="block text-[10px] uppercase text-slate-400 font-bold mb-2">{t('settings.cloudinary')}</label>
          <div className="bg-[#161618] rounded-lg border border-white/5 p-4 space-y-3">
            <p className="text-xs">
              {status.configured
                ? <><span className="text-green-400">✓</span> {lang === 'ar' ? 'مفعل' : 'Active'} ({status.cloudName})</>
                : <><span className="text-rose-400">✗</span> {lang === 'ar' ? 'غير مفعل' : 'Not configured'}</>
              }
            </p>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
              <div>
                <label className="block text-[9px] uppercase text-slate-500 font-bold mb-1">{t('cloudinary.cloudName')}</label>
                <input type="text" value={cloudName} onChange={e => setCloudName(e.target.value)} className="w-full bg-[#1c1c1f] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" placeholder="dl30muiuc" />
              </div>
              <div>
                <label className="block text-[9px] uppercase text-slate-500 font-bold mb-1">{t('cloudinary.apiKey')}</label>
                <input type="text" value={apiKey} onChange={e => setApiKey(e.target.value)} className="w-full bg-[#1c1c1f] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" placeholder="865669713469485" />
              </div>
              <div>
                <label className="block text-[9px] uppercase text-slate-500 font-bold mb-1">{t('cloudinary.apiSecret')}</label>
                <input type="password" value={apiSecret} onChange={e => setApiSecret(e.target.value)} className="w-full bg-[#1c1c1f] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" placeholder="API Secret" />
              </div>
            </div>
            <p className="text-[9px] text-slate-600">{t('cloudinary.description')}</p>
            <button onClick={handleSaveCloudinary} disabled={saving} className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-[10px] text-white font-semibold rounded-lg flex items-center gap-1">
              <Save className="w-3 h-3" /> {saving ? t('saving') : t('cloudinary.save')}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
