import { useContext, useEffect, useState, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { I18nContext, langs } from '../lib/i18n';
import { getCloudinaryStatus, saveCloudinaryConfig, uploadLoginMedia, uploadLoginLogo } from '../lib/storage';
import { supabase, isAdminConnected } from '../lib/supabase';
import { Save, Crown, Database, Mic, ArrowLeft, Sparkles, Flame, Palette, ShieldAlert, ShieldCheck, CheckCircle2, Upload, Film, Image as ImageIcon, Trash2, Eye, Play, Check, FileCode, Video } from 'lucide-react';


export default function Settings() {
  const navigate = useNavigate();
  const { t, lang, setLang } = useContext(I18nContext);
  const [cloudName, setCloudName] = useState('');
  const [apiKey, setApiKey] = useState('');
  const [apiSecret, setApiSecret] = useState('');
  const [saving, setSaving] = useState(false);
  const [vipUrl, setVipUrl] = useState('');
  const [vipSaving, setVipSaving] = useState(false);
  const [supabaseServiceKey, setSupabaseServiceKey] = useState('');
  const [supabaseSaving, setSupabaseSaving] = useState(false);

  // Google Play Review Mode State
  const [reviewModeEnabled, setReviewModeEnabled] = useState<boolean>(false);
  const [reviewModeSaving, setReviewModeSaving] = useState<boolean>(false);
  const [reviewModeLoaded, setReviewModeLoaded] = useState<boolean>(false);

  const [luckyGiftTargetPct, setLuckyGiftTargetPct] = useState<number>(10.0);
  const [luckySaving, setLuckySaving] = useState(false);

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

    // تحميل نسبة هدايا الحظ للتارجت
    supabase.from('app_config').select('value').eq('key', 'lucky_gift_target_percentage').maybeSingle().then(res => {
      if (res?.data?.value !== undefined && res?.data?.value !== null) {
        const val = Number(res.data.value);
        if (!isNaN(val)) setLuckyGiftTargetPct(val);
      } else {
        // Fallback from lucky_box_config
        supabase.from('app_config').select('value').eq('key', 'lucky_box_config').maybeSingle().then(r2 => {
          if (r2?.data?.value) {
            const parsed = typeof r2.data.value === 'string' ? JSON.parse(r2.data.value) : r2.data.value;
            if (parsed?.targetPercentage !== undefined) {
              setLuckyGiftTargetPct(Number(parsed.targetPercentage) || 10.0);
            }
          }
        });
      }
    });

    // تحميل إعدادات عن التطبيق
    supabase.from('app_config').select('value').eq('key', 'about_app_config').maybeSingle().then(res => {
      if (res?.data?.value) {
        const val = typeof res.data.value === 'string' ? JSON.parse(res.data.value) : res.data.value;
        if (val.title) setAboutTitle(val.title);
        if (val.description) setAboutDescription(val.description);
        if (val.copyright) setAboutCopyright(val.copyright);
      }
    });

    // تحميل سياسة الخصوصية
    supabase.from('app_config').select('value').eq('key', 'privacy_policy_config').maybeSingle().then(res => {
      if (res?.data?.value) {
        const val = typeof res.data.value === 'string' ? JSON.parse(res.data.value) : res.data.value;
        if (typeof val === 'string') setPrivacyPolicyContent(val);
        else if (val.content) setPrivacyPolicyContent(val.content);
      }
    });

    // تحميل إعدادات شاشة تسجيل الدخول
    supabase.from('app_config').select('value').eq('key', 'login_screen_config').maybeSingle().then(res => {
      if (res?.data?.value) {
        const val = typeof res.data.value === 'string' ? JSON.parse(res.data.value) : res.data.value;
        if (val.bgUrl) setLoginBgUrl(val.bgUrl);
        if (val.bgType) setLoginBgType(val.bgType);
        if (val.welcomeTitle !== undefined) setLoginWelcomeTitle(val.welcomeTitle);
        if (val.welcomeSubtitle !== undefined) setLoginWelcomeSubtitle(val.welcomeSubtitle);
        if (val.welcomeLogoUrl !== undefined) setLoginWelcomeLogoUrl(val.welcomeLogoUrl);
        if (val.showWelcome !== undefined) setLoginShowWelcome(val.showWelcome !== false);
      }
    });

    // تحميل وضع مراجعة Google Play
    supabase.from('app_config').select('value').eq('key', 'google_review_mode').maybeSingle().then(res => {
      if (res?.data?.value !== undefined && res?.data?.value !== null) {
        let val = res.data.value;
        if (typeof val === 'string') {
          try { val = JSON.parse(val); } catch (_) {}
        }
        if (typeof val === 'boolean') {
          setReviewModeEnabled(val);
        } else if (typeof val === 'object' && val !== null) {
          setReviewModeEnabled((val as any).enabled === true || (val as any).enabled === 'true');
        } else if (typeof val === 'string') {
          setReviewModeEnabled(val === 'true' || val === '1');
        }
      }
      setReviewModeLoaded(true);
    });
  }, []);

  const handleToggleReviewMode = async (nextState: boolean) => {
    setReviewModeSaving(true);
    try {
      const payload = {
        enabled: nextState,
        hide_external_contacts: nextState,
        hide_recharge_agents: nextState,
        hide_unofficial_gateways: nextState,
        updated_at: new Date().toISOString(),
      };
      const { error } = await supabase.from('app_config').upsert(
        { key: 'google_review_mode', value: payload },
        { onConflict: 'key' }
      );
      if (error) throw error;
      setReviewModeEnabled(nextState);
      alert(nextState 
        ? 'تم تفعيل وضع مراجعة Google Play بنجاح 🛡️\nالتطبيق الآن يخفي جميع أرقام الواتساب ووكلاء الشحن وبوابات الدفع غير الرسمية ويظهر باقات جوجل الرسمية فقط.' 
        : 'تم إيقاف وضع المراجعة وتفعيل الوضع الحي (Live) 🚀\nتظهر الآن لجميع المستخدمين شاشات الوكلاء وقنوات الشحن والتواصل بشكل طبيعي.');
    } catch (e) {
      alert('فشل حفظ حالة وضع المراجعة: ' + (e as Error).message);
    }
    setReviewModeSaving(false);
  };

  // حالات صفحات التطبيق وسياسة الخصوصية وخلفية الدخول
  const [aboutTitle, setAboutTitle] = useState('أحلى لايف - Ahla Live');
  const [aboutDescription, setAboutDescription] = useState('تطبيق أحلى لايف هو منصة تواصل اجتماعي رائدة تتيح لك التعرف على أصدقاء جدد، وإنشاء غرف صوتية ممتعة ومميزة.');
  const [aboutCopyright, setAboutCopyright] = useState('جميع الحقوق محفوظة © 2026');
  const [aboutSaving, setAboutSaving] = useState(false);

  const [privacyPolicyContent, setPrivacyPolicyContent] = useState('مرحباً بك في تطبيق أحلى لايف (Ahla Live). نحن نحرص بشدة على حماية خصوصيتك وبياناتك الشخصية وتقديم بيئة آمنة لجميع المستخدمين وفقاً لمعايير Google Play الدولية.');
  const [privacySaving, setPrivacySaving] = useState(false);

  const [loginBgUrl, setLoginBgUrl] = useState('');
  const [loginBgType, setLoginBgType] = useState<'image' | 'video' | 'vap' | 'gif'>('image');
  const [loginWelcomeTitle, setLoginWelcomeTitle] = useState('Welcome');
  const [loginWelcomeSubtitle, setLoginWelcomeSubtitle] = useState('AHLA LIVE');
  const [loginWelcomeLogoUrl, setLoginWelcomeLogoUrl] = useState('');
  const [loginShowWelcome, setLoginShowWelcome] = useState(true);
  const [loginUploading, setLoginUploading] = useState(false);
  const [loginProgress, setLoginProgress] = useState(0);
  const [logoUploading, setLogoUploading] = useState(false);
  const [logoProgress, setLogoProgress] = useState(0);
  const [loginSaving, setLoginSaving] = useState(false);
  const mediaFileInputRef = useRef<HTMLInputElement>(null);
  const logoFileInputRef = useRef<HTMLInputElement>(null);

  const handleMediaFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setLoginUploading(true);
    setLoginProgress(0);
    try {
      const res = await uploadLoginMedia(file, pct => setLoginProgress(pct));
      setLoginBgUrl(res.url);
      setLoginBgType(res.type);
    } catch (err: any) {
      alert('فشل رفع الملف من جهازك: ' + (err?.message || err));
    } finally {
      setLoginUploading(false);
      e.target.value = '';
    }
  };

  const handleLogoFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setLogoUploading(true);
    setLogoProgress(0);
    try {
      const url = await uploadLoginLogo(file, pct => setLogoProgress(pct));
      setLoginWelcomeLogoUrl(url);
    } catch (err: any) {
      alert('فشل رفع الشعار من جهازك: ' + (err?.message || err));
    } finally {
      setLogoUploading(false);
      e.target.value = '';
    }
  };

  const handleSaveAboutApp = async () => {
    setAboutSaving(true);
    try {
      await supabase.from('app_config').upsert({
        key: 'about_app_config',
        value: {
          title: aboutTitle,
          description: aboutDescription,
          copyright: aboutCopyright,
          updated_at: new Date().toISOString(),
        }
      }, { onConflict: 'key' });
      alert('تم حفظ بيانات شاشة عن التطبيق بنجاح ✓');
    } catch (e) {
      alert('فشل الحفظ: ' + (e as Error).message);
    }
    setAboutSaving(false);
  };

  const handleSavePrivacyPolicy = async () => {
    setPrivacySaving(true);
    try {
      await supabase.from('app_config').upsert({
        key: 'privacy_policy_config',
        value: {
          content: privacyPolicyContent,
          updated_at: new Date().toISOString(),
        }
      }, { onConflict: 'key' });
      alert('تم حفظ نص سياسة الخصوصية بنجاح ✓');
    } catch (e) {
      alert('فشل الحفظ: ' + (e as Error).message);
    }
    setPrivacySaving(false);
  };

  const handleSaveLoginConfig = async () => {
    setLoginSaving(true);
    try {
      await supabase.from('app_config').upsert({
        key: 'login_screen_config',
        value: {
          bgUrl: loginBgUrl.trim(),
          bgType: loginBgType,
          welcomeTitle: loginWelcomeTitle.trim(),
          welcomeSubtitle: loginWelcomeSubtitle.trim(),
          welcomeLogoUrl: loginWelcomeLogoUrl.trim(),
          showWelcome: loginShowWelcome,
          updated_at: new Date().toISOString(),
        }
      }, { onConflict: 'key' });
      alert('تم حفظ إعدادات شاشة الدخول وشعار Welcome Ahla Live بنجاح ✓');
    } catch (e) {
      alert('فشل الحفظ: ' + (e as Error).message);
    }
    setLoginSaving(false);
  };

  const handleSaveCloudinary = () => {
    setSaving(true);
    saveCloudinaryConfig(cloudName, apiKey, apiSecret);
    setSaving(false);
    alert(t('cloudinary.save') + ' ✓');
  };

  const handleSaveLuckyTargetPct = async () => {
    setLuckySaving(true);
    try {
      // 1. حفظ في lucky_gift_target_percentage
      await supabase.from('app_config').upsert(
        { key: 'lucky_gift_target_percentage', value: luckyGiftTargetPct },
        { onConflict: 'key' }
      );

      // 2. تحديث داخل lucky_box_config أيضاً للتوافق التام
      const { data: curBox } = await supabase
        .from('app_config')
        .select('value')
        .eq('key', 'lucky_box_config')
        .maybeSingle();

      const existing = curBox?.value
        ? (typeof curBox.value === 'string' ? JSON.parse(curBox.value) : curBox.value)
        : {};

      await supabase.from('app_config').upsert(
        {
          key: 'lucky_box_config',
          value: {
            ...existing,
            targetPercentage: luckyGiftTargetPct,
            updated_at: new Date().toISOString(),
          },
        },
        { onConflict: 'key' }
      );

      alert('تم حفظ نسبة هدايا الحظ في التارجت بنجاح ✓ (' + luckyGiftTargetPct + '%)');
    } catch (e) {
      alert('فشل الحفظ: ' + (e as Error).message);
    }
    setLuckySaving(false);
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
    <div className="space-y-6 max-w-2xl">
      <div>
        <h2 className="text-white text-lg font-semibold">{t('settings.title')}</h2>
        <p className="text-slate-500 text-xs mt-0.5">{t('settings.description')}</p>
      </div>

      <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-6">
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

        {/* Google Play Review Mode Switch Card */}
        <div>
          <div className="flex items-center justify-between mb-2">
            <label className="text-[11px] uppercase tracking-wider font-bold flex items-center gap-2 text-amber-400">
              <ShieldAlert className="w-4 h-4 text-amber-400" />
              <span>وضع مراجعة متجر Google Play (Google Play Review Mode)</span>
            </label>
            <span className={`text-[10px] font-bold px-2.5 py-0.5 rounded-full border ${
              reviewModeEnabled 
                ? 'bg-amber-500/20 text-amber-300 border-amber-500/40 animate-pulse' 
                : 'bg-emerald-500/20 text-emerald-300 border-emerald-500/40'
            }`}>
              {reviewModeEnabled ? '🟡 وضع المراجعة مفعّل (Review Active)' : '🟢 الوضع الحي شغال (Live Active)'}
            </span>
          </div>

          <div className={`rounded-xl border p-5 transition-all shadow-xl ${
            reviewModeEnabled 
              ? 'bg-gradient-to-r from-amber-950/40 via-yellow-950/20 to-[#161618] border-amber-500/40 shadow-amber-500/10' 
              : 'bg-gradient-to-r from-emerald-950/30 via-slate-900 to-[#161618] border-emerald-500/30 shadow-emerald-500/10'
          }`}>
            <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-5">
              <div className="flex items-start gap-4">
                <div className={`w-12 h-12 rounded-xl flex items-center justify-center text-2xl flex-shrink-0 border shadow-lg ${
                  reviewModeEnabled 
                    ? 'bg-amber-500/20 border-amber-500/40 text-amber-400 shadow-amber-500/20' 
                    : 'bg-emerald-500/20 border-emerald-500/40 text-emerald-400 shadow-emerald-500/20'
                }`}>
                  {reviewModeEnabled ? '🛡️' : '🚀'}
                </div>
                <div className="space-y-1">
                  <h4 className="text-sm font-bold text-white flex items-center gap-2">
                    <span>{reviewModeEnabled ? 'وضع المراجعة مفعّل حالياً' : 'وضع التطبيق الحي (Live Mode)'}</span>
                    <span className="text-xs text-slate-400">
                      {reviewModeEnabled ? '(Google Play Reviewing)' : '(Public Live App)'}
                    </span>
                  </h4>
                  <p className="text-xs text-slate-300 leading-relaxed max-w-2xl">
                    {reviewModeEnabled ? (
                      <>
                        <strong className="text-amber-300">أثناء المراجعة:</strong> يتم إخفاء أرقام الواتساب وروابط التواصل الخارجي، وتخفى شاشات وكلاء الشحن وبوابات فودافون كاش وبينانس باي عن مراجع متجر جوجل. يرى المراجع تطبيقاً ترفيهياً نظيفاً يحتوي فقط على شحن Google Play الرسمي أو نظام الصرف الداخلي.
                      </>
                    ) : (
                      <>
                        <strong className="text-emerald-300">التطبيق الحي:</strong> يظهر لجميع المستخدمين شاشات وكلاء الشحن المعتمدين، وقنوات صرف الأرباح إلى الوكلاء، وأرقام الواتساب المعتمدة، وبوابات الدفع بالكامل بدون أي قيود.
                      </>
                    )}
                  </p>
                  <div className="flex flex-wrap items-center gap-2 pt-1 text-[11px] text-slate-400">
                    <span className="inline-flex items-center gap-1 bg-white/5 px-2.5 py-1 rounded-md border border-white/5">
                      <span>واتساب الوكلاء:</span>
                      <strong className={reviewModeEnabled ? 'text-amber-400' : 'text-emerald-400'}>
                        {reviewModeEnabled ? 'مخفي 🔒' : 'ظاهر ✓'}
                      </strong>
                    </span>
                    <span className="inline-flex items-center gap-1 bg-white/5 px-2.5 py-1 rounded-md border border-white/5">
                      <span>شاشات وكلاء الشحن:</span>
                      <strong className={reviewModeEnabled ? 'text-amber-400' : 'text-emerald-400'}>
                        {reviewModeEnabled ? 'مخفية 🔒' : 'ظاهرة ✓'}
                      </strong>
                    </span>
                    <span className="inline-flex items-center gap-1 bg-white/5 px-2.5 py-1 rounded-md border border-white/5">
                      <span>بوابات الدفع غير الرسمية:</span>
                      <strong className={reviewModeEnabled ? 'text-amber-400' : 'text-emerald-400'}>
                        {reviewModeEnabled ? 'معطلة 🔒' : 'مفعلة ✓'}
                      </strong>
                    </span>
                  </div>
                </div>
              </div>

              <div className="flex flex-col sm:flex-row items-center gap-3 self-end lg:self-center flex-shrink-0">
                <button
                  type="button"
                  disabled={reviewModeSaving}
                  onClick={() => handleToggleReviewMode(!reviewModeEnabled)}
                  className={`px-5 py-3 rounded-xl font-bold text-xs flex items-center gap-2.5 shadow-lg transition-all cursor-pointer whitespace-nowrap ${
                    reviewModeEnabled
                      ? 'bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-500 hover:to-teal-500 text-white shadow-emerald-600/30'
                      : 'bg-gradient-to-r from-amber-600 to-yellow-600 hover:from-amber-500 hover:to-yellow-500 text-white shadow-amber-600/30'
                  }`}
                >
                  {reviewModeSaving ? (
                    <span>جاري التحديث...</span>
                  ) : reviewModeEnabled ? (
                    <>
                      <CheckCircle2 className="w-4 h-4" />
                      <span>إيقاف وضع المراجعة وتفعيل التطبيق الحي (Live) 🚀</span>
                    </>
                  ) : (
                    <>
                      <ShieldAlert className="w-4 h-4" />
                      <span>تفعيل وضع مراجعة Google Play 🛡️</span>
                    </>
                  )}
                </button>
              </div>
            </div>
          </div>
        </div>

        {/* Unified Design & Customization Center Card */}
        <div>
          <label className="block text-[10px] uppercase text-purple-400 font-bold mb-2">
            🎨 App Design & Customization Center / مركز التصميم والمظهر الشامل
          </label>
          <div className="bg-gradient-to-r from-purple-950/40 via-indigo-950/30 to-[#161618] rounded-xl border border-purple-500/30 p-5 space-y-4 shadow-xl">
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
              <div className="flex items-center gap-3.5">
                <div className="w-12 h-12 rounded-xl bg-purple-500/20 text-purple-300 border border-purple-500/30 flex items-center justify-center text-2xl shadow-lg shadow-purple-500/20 flex-shrink-0">
                  🎨
                </div>
                <div>
                  <h4 className="text-sm font-bold text-white flex items-center gap-2">
                    <span>مركز التصميم والمظهر وتخصيص النصوص والألوان</span>
                    <span className="text-[10px] bg-purple-500/20 text-purple-300 border border-purple-500/40 font-semibold px-2 py-0.5 rounded-full">
                      مُوحد 5 في 1
                    </span>
                  </h4>
                  <p className="text-xs text-slate-400 mt-1">
                    المظهر الشامل والألوان، مصمم الواجهات والأيقونات، تخصيص الشاشات والخلفيات، مكتبة أصول التطبيق، بانرات الهدايا، وتعديل كافة كتابات ونصوص التطبيق ومستهدف الوكالات وألوان النصوص بالكامل.
                  </p>
                </div>
              </div>
              <button
                onClick={() => navigate('/design-center')}
                className="px-5 py-2.5 bg-gradient-to-r from-purple-600 to-indigo-600 hover:from-purple-500 hover:to-indigo-500 text-white font-bold text-xs rounded-xl flex items-center justify-center gap-2 shadow-lg shadow-purple-600/30 cursor-pointer whitespace-nowrap self-start md:self-auto transition-all"
              >
                <span>فتح مركز التصميم 🎨</span>
                <ArrowLeft className="w-4 h-4" />
              </button>
            </div>

            {/* Quick Links to sub-tabs */}
            <div className="flex items-center gap-2 pt-2 border-t border-white/5 overflow-x-auto pb-1 text-[11px]">
              <button
                onClick={() => navigate('/design-center?tab=texts_colors')}
                className="px-3 py-1.5 rounded-lg bg-white/5 hover:bg-white/10 text-slate-300 border border-white/5 transition whitespace-nowrap cursor-pointer"
              >
                ✍️ نصوص التطبيق وألوانها
              </button>
              <button
                onClick={() => navigate('/design-center?tab=visual_manager')}
                className="px-3 py-1.5 rounded-lg bg-white/5 hover:bg-white/10 text-slate-300 border border-white/5 transition whitespace-nowrap cursor-pointer"
              >
                🎨 المظهر الشامل
              </button>
              <button
                onClick={() => navigate('/design-center?tab=app_visual_designer')}
                className="px-3 py-1.5 rounded-lg bg-white/5 hover:bg-white/10 text-slate-300 border border-white/5 transition whitespace-nowrap cursor-pointer"
              >
                📱 مصمم الواجهات
              </button>
              <button
                onClick={() => navigate('/design-center?tab=screen_customization')}
                className="px-3 py-1.5 rounded-lg bg-white/5 hover:bg-white/10 text-slate-300 border border-white/5 transition whitespace-nowrap cursor-pointer"
              >
                🛠️ تخصيص الشاشات
              </button>
              <button
                onClick={() => navigate('/design-center?tab=app_assets')}
                className="px-3 py-1.5 rounded-lg bg-white/5 hover:bg-white/10 text-slate-300 border border-white/5 transition whitespace-nowrap cursor-pointer"
              >
                🖼️ مكتبة الأصول
              </button>
              <button
                onClick={() => navigate('/design-center?tab=gift_banners')}
                className="px-3 py-1.5 rounded-lg bg-white/5 hover:bg-white/10 text-slate-300 border border-white/5 transition whitespace-nowrap cursor-pointer"
              >
                🎁 بانرات الهدايا
              </button>
            </div>
          </div>
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
              يتم حفظ المفاتيح سحابياً في Supabase ليتم تطبيقها فورياً على جميع مستخدمي التطبيق.
            </p>
          </div>
        </div>

        <div>
          <label className="block text-[10px] uppercase text-slate-400 font-bold mb-2">
            نسبة هدايا الحظ في تارجت وماسات المستلم (Lucky Gifts Target Rate)
          </label>
          <div className="bg-[#161618] rounded-lg border border-amber-500/30 p-4 space-y-4">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
              <div className="flex items-center gap-2.5">
                <div className="p-2 rounded-lg bg-amber-500/20 text-amber-400">
                  <Sparkles className="w-5 h-5" />
                </div>
                <div>
                  <h4 className="text-xs font-bold text-white flex items-center gap-2">
                    <span>نسبة الماس المحسوبة للمستلم</span>
                    <span className="text-[11px] bg-amber-500 text-black font-extrabold px-2 py-0.5 rounded-full">
                      {luckyGiftTargetPct}%
                    </span>
                  </h4>
                  <p className="text-[11px] text-slate-400 mt-0.5">
                    النسبة المئوية التي تدخل في محفظة المستلم وتارجت الوكالة عند استلام هدايا الحظ (مثلاً 10 كوينز تمنح {((10 * luckyGiftTargetPct) / 100).toFixed(1)} ماسة).
                  </p>
                </div>
              </div>

              <div className="flex items-center gap-1 flex-wrap">
                {[0, 5, 10, 15, 20, 50, 100].map(pct => (
                  <button
                    key={pct}
                    onClick={() => setLuckyGiftTargetPct(pct)}
                    className={`px-2.5 py-1 rounded text-[11px] font-bold border transition ${
                      luckyGiftTargetPct === pct
                        ? 'bg-amber-500 text-black border-amber-400'
                        : 'bg-black/30 text-slate-400 border-white/5 hover:text-white'
                    }`}
                  >
                    {pct}%
                  </button>
                ))}
              </div>
            </div>

            <div className="flex items-center gap-3 pt-2 border-t border-white/5">
              <input
                type="range"
                min="0"
                max="100"
                step="1"
                value={luckyGiftTargetPct}
                onChange={e => setLuckyGiftTargetPct(Number(e.target.value))}
                className="flex-1 accent-amber-500 cursor-pointer"
              />
              <div className="flex items-center gap-2 shrink-0">
                <input
                  type="number"
                  min="0"
                  max="100"
                  step="0.5"
                  value={luckyGiftTargetPct}
                  onChange={e => setLuckyGiftTargetPct(Math.max(0, Math.min(100, parseFloat(e.target.value) || 0)))}
                  className="w-20 bg-[#1c1c1f] border border-white/10 rounded-lg py-1 px-2 text-xs text-white text-center font-bold font-mono"
                />
                <button
                  onClick={handleSaveLuckyTargetPct}
                  disabled={luckySaving}
                  className="px-3 py-1.5 bg-gradient-to-r from-amber-500 to-amber-600 hover:from-amber-600 hover:to-amber-700 disabled:opacity-50 text-[11px] text-black font-bold rounded-lg flex items-center gap-1 shadow"
                >
                  <Save className="w-3 h-3" />
                  {luckySaving ? 'جارٍ الحفظ...' : 'حفظ النسبة'}
                </button>
              </div>
            </div>
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

        {/* About App Configuration */}
        <div>
          <label className="block text-[10px] uppercase text-sky-400 font-bold mb-2 flex items-center gap-1">
            📱 معلومات التطبيق (شاشة عن التطبيق) / About App Screen
          </label>
          <div className="bg-[#161618] rounded-xl border border-sky-500/20 p-4 space-y-3">
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">اسم وعنوان التطبيق</label>
              <input
                type="text"
                value={aboutTitle}
                onChange={e => setAboutTitle(e.target.value)}
                className="w-full bg-[#1c1c1f] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                placeholder="أحلى لايف - Ahla Live"
              />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">نص وتفاصيل عن التطبيق</label>
              <textarea
                rows={4}
                value={aboutDescription}
                onChange={e => setAboutDescription(e.target.value)}
                className="w-full bg-[#1c1c1f] border border-white/10 rounded-lg py-2 px-3 text-xs text-white leading-relaxed"
                placeholder="اكتب نبذة عن التطبيق ومميزاته ورؤيته..."
              />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">حقوق الملكية والنشر</label>
              <input
                type="text"
                value={aboutCopyright}
                onChange={e => setAboutCopyright(e.target.value)}
                className="w-full bg-[#1c1c1f] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                placeholder="جميع الحقوق محفوظة © 2026"
              />
            </div>
            <button
              onClick={handleSaveAboutApp}
              disabled={aboutSaving}
              className="px-4 py-2 bg-sky-600 hover:bg-sky-500 disabled:opacity-50 text-xs text-white font-bold rounded-lg flex items-center gap-1.5 transition-colors cursor-pointer"
            >
              <Save className="w-3.5 h-3.5" /> {aboutSaving ? 'جاري الحفظ...' : 'حفظ بيانات عن التطبيق'}
            </button>
          </div>
        </div>

        {/* Privacy Policy Configuration */}
        <div>
          <label className="block text-[10px] uppercase text-emerald-400 font-bold mb-2 flex items-center gap-1">
            📜 سياسة الخصوصية وشروط الاستخدام / Privacy Policy
          </label>
          <div className="bg-[#161618] rounded-xl border border-emerald-500/20 p-4 space-y-3">
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">نص بنود سياسة الخصوصية والشروط</label>
              <textarea
                rows={6}
                value={privacyPolicyContent}
                onChange={e => setPrivacyPolicyContent(e.target.value)}
                className="w-full bg-[#1c1c1f] border border-white/10 rounded-lg py-2 px-3 text-xs text-white font-sans leading-relaxed"
                placeholder="اكتب بنود سياسة الخصوصية وحماية بيانات المستخدمين..."
              />
            </div>
            <button
              onClick={handleSavePrivacyPolicy}
              disabled={privacySaving}
              className="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 text-xs text-white font-bold rounded-lg flex items-center gap-1.5 transition-colors cursor-pointer"
            >
              <Save className="w-3.5 h-3.5" /> {privacySaving ? 'جاري الحفظ...' : 'حفظ سياسة الخصوصية'}
            </button>
          </div>
        </div>

        {/* Login Screen Customization (Background & Welcome Header) */}
        <div>
          <label className="block text-[10px] uppercase text-amber-400 font-bold mb-2 flex items-center gap-1.5">
            <Film className="w-3.5 h-3.5" />
            <span>خلفية وتخصيص شاشة تسجيل الدخول وشعار الترحيب (Login Screen & Welcome Ahla Live)</span>
          </label>
          <div className="bg-[#161618] rounded-xl border border-amber-500/30 p-5 space-y-5 shadow-lg">
            
            {/* القسم الأول: رفع ملف الخلفية من جهاز الكمبيوتر */}
            <div className="space-y-3 pb-4 border-b border-white/5">
              <div className="flex items-center justify-between">
                <div>
                  <h5 className="text-xs font-bold text-white flex items-center gap-2">
                    <Video className="w-4 h-4 text-amber-400" />
                    <span>خلفية شاشة الدخول (فيديو MP4، صورة، GIF، أو VAP)</span>
                  </h5>
                  <p className="text-[11px] text-slate-400 mt-0.5">
                    يمكنك رفع فيديو MP4 متحرك أو صورة عالية الدقة أو GIF أو VAP مباشرة من جهازك لتعمل كخلفية تفاعلية.
                  </p>
                </div>
                {loginBgUrl && (
                  <button
                    type="button"
                    onClick={() => {
                      setLoginBgUrl('');
                      setLoginBgType('image');
                    }}
                    className="text-[11px] text-rose-400 hover:text-rose-300 flex items-center gap-1 px-2.5 py-1 rounded bg-rose-500/10 border border-rose-500/20 cursor-pointer"
                  >
                    <Trash2 className="w-3 h-3" />
                    <span>مسح الخلفية والرجوع للافتراضي</span>
                  </button>
                )}
              </div>

              {/* منطقة الرفع المباشر من الجهاز */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <input
                    type="file"
                    ref={mediaFileInputRef}
                    onChange={handleMediaFileUpload}
                    accept="video/mp4,video/webm,video/quicktime,image/*,.vap,.svga,.gif,.webp"
                    className="hidden"
                  />
                  <button
                    type="button"
                    disabled={loginUploading}
                    onClick={() => mediaFileInputRef.current?.click()}
                    className="w-full h-32 border-2 border-dashed border-amber-500/40 hover:border-amber-400 rounded-xl bg-amber-500/5 hover:bg-amber-500/10 flex flex-col items-center justify-center gap-2 transition-all cursor-pointer group"
                  >
                    <div className="w-10 h-10 rounded-full bg-amber-500/20 text-amber-400 flex items-center justify-center group-hover:scale-110 transition-transform">
                      {loginUploading ? (
                        <div className="w-5 h-5 border-2 border-amber-400 border-t-transparent rounded-full animate-spin" />
                      ) : (
                        <Upload className="w-5 h-5" />
                      )}
                    </div>
                    <div className="text-center">
                      <span className="text-xs font-bold text-white block">
                        {loginUploading ? `جاري الرفع من جهازك... (${loginProgress}%)` : 'اضغط لاختيار فيديو أو صورة من جهازك'}
                      </span>
                      <span className="text-[10px] text-slate-400 mt-0.5 block font-sans">
                        يدعم: MP4, MOV, WEBM, GIF, PNG, JPG, VAP, SVGA
                      </span>
                    </div>
                  </button>

                  {/* شريط تقدم الرفع */}
                  {loginUploading && (
                    <div className="mt-2 space-y-1">
                      <div className="flex justify-between text-[10px] text-amber-400 font-mono">
                        <span>جاري معالجة ورفع الملف...</span>
                        <span>{loginProgress}%</span>
                      </div>
                      <div className="w-full h-1.5 bg-black/40 rounded-full overflow-hidden">
                        <div
                          className="h-full bg-gradient-to-r from-amber-500 to-yellow-400 transition-all duration-200"
                          style={{ width: `${loginProgress}%` }}
                        />
                      </div>
                    </div>
                  )}

                  {/* خيار إدخال الرابط يدوياً */}
                  <div className="mt-3 space-y-1">
                    <label className="block text-[10px] uppercase text-slate-400 font-bold">
                      أو أدخل رابط الملف مباشرة (URL):
                    </label>
                    <input
                      type="url"
                      value={loginBgUrl}
                      onChange={e => {
                        const val = e.target.value;
                        setLoginBgUrl(val);
                        if (val.toLowerCase().endsWith('.mp4') || val.toLowerCase().endsWith('.mov')) {
                          setLoginBgType('video');
                        } else if (val.toLowerCase().endsWith('.vap')) {
                          setLoginBgType('vap');
                        } else if (val.toLowerCase().endsWith('.gif')) {
                          setLoginBgType('gif');
                        }
                      }}
                      className="w-full bg-[#1c1c1f] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white font-mono"
                      placeholder="https://res.cloudinary.com/.../login_bg.mp4"
                    />
                  </div>

                  <div className="mt-2">
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">نوع الملف المحدد</label>
                    <select
                      value={loginBgType}
                      onChange={e => setLoginBgType(e.target.value as any)}
                      className="w-full bg-[#1c1c1f] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                    >
                      <option value="video">فيديو متحرك (MP4 Video)</option>
                      <option value="image">صورة ثابتة عالية الدقة (Image)</option>
                      <option value="gif">صورة متحركة (GIF Animation)</option>
                      <option value="vap">مؤثر متحرك شفاف (VAP)</option>
                    </select>
                  </div>
                </div>

                {/* صندوق المعاينة الحية */}
                <div className="bg-black/30 rounded-xl border border-white/5 p-3 flex flex-col items-center justify-center min-h-[160px] text-center relative overflow-hidden">
                  <span className="text-[10px] uppercase text-slate-500 font-bold absolute top-2 right-3">
                    معاينة الخلفية الحالية
                  </span>

                  {loginBgUrl ? (
                    <div className="w-full h-full flex flex-col items-center justify-center gap-2">
                      {loginBgType === 'video' || loginBgUrl.toLowerCase().endsWith('.mp4') ? (
                        <div className="relative w-full max-h-44 rounded-lg overflow-hidden border border-amber-500/30">
                          <video
                            src={loginBgUrl}
                            autoPlay
                            loop
                            muted
                            playsInline
                            className="w-full max-h-44 object-cover"
                          />
                          <span className="absolute bottom-2 left-2 bg-black/70 backdrop-blur text-amber-400 text-[10px] px-2 py-0.5 rounded-full font-bold flex items-center gap-1">
                            <Play className="w-3 h-3 fill-amber-400" /> فيديو شغال تلقائياً
                          </span>
                        </div>
                      ) : loginBgType === 'vap' ? (
                        <div className="p-4 rounded-lg bg-pink-500/10 border border-pink-500/30 text-pink-300">
                          <Film className="w-8 h-8 mx-auto mb-1 text-pink-400" />
                          <span className="text-xs font-bold block">ملف VAP شفاف</span>
                          <span className="text-[10px] text-slate-400 font-mono truncate max-w-xs block mt-1">
                            {loginBgUrl}
                          </span>
                        </div>
                      ) : (
                        <div className="relative max-h-44 rounded-lg overflow-hidden border border-white/10">
                          <img
                            src={loginBgUrl}
                            alt="Login BG"
                            className="max-h-44 object-cover rounded-lg"
                          />
                          <span className="absolute bottom-2 left-2 bg-black/70 backdrop-blur text-emerald-400 text-[10px] px-2 py-0.5 rounded-full font-bold">
                            {loginBgType === 'gif' ? 'GIF متحرك' : 'صورة ثابتة'}
                          </span>
                        </div>
                      )}
                    </div>
                  ) : (
                    <div className="text-slate-500 space-y-1 py-4">
                      <Film className="w-8 h-8 mx-auto opacity-40 text-slate-400" />
                      <p className="text-xs">يتم استخدام الخلفية الافتراضية للتطبيق</p>
                      <p className="text-[10px] text-slate-600">ارفع فيديو أو صورة لعرض المعاينة هنا فوراً</p>
                    </div>
                  )}
                </div>
              </div>
            </div>

            {/* القسم الثاني: شعار وترويسة الترحيب (Welcome Ahla Live - إزالة YOPPO نهائياً) */}
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <h5 className="text-xs font-bold text-white flex items-center gap-2">
                    <Sparkles className="w-4 h-4 text-yellow-400" />
                    <span>نص وشعار الترحيب (Welcome Ahla Live - بديل YOPPO)</span>
                  </h5>
                  <p className="text-[11px] text-slate-400 mt-0.5">
                    تم إزالة شعار (Welcome YOPPO) القديم. يمكنك الآن تعديل عبارة الترحيب، أو رفع شعار مخصص لتطبيقك.
                  </p>
                </div>

                <label className="flex items-center gap-2 text-xs font-bold text-slate-300 cursor-pointer bg-white/5 px-3 py-1.5 rounded-lg border border-white/10 hover:bg-white/10 transition">
                  <input
                    type="checkbox"
                    checked={loginShowWelcome}
                    onChange={e => setLoginShowWelcome(e.target.checked)}
                    className="accent-amber-500 w-4 h-4 rounded"
                  />
                  <span>إظهار الترحيب في الشاشة</span>
                </label>
              </div>

              {loginShowWelcome && (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 bg-black/20 p-4 rounded-xl border border-white/5">
                  <div className="space-y-3">
                    <div className="grid grid-cols-2 gap-2">
                      <div>
                        <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">
                          عنوان الترحيب الأول (Title)
                        </label>
                        <input
                          type="text"
                          value={loginWelcomeTitle}
                          onChange={e => setLoginWelcomeTitle(e.target.value)}
                          className="w-full bg-[#1c1c1f] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                          placeholder="Welcome"
                        />
                      </div>
                      <div>
                        <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">
                          عنوان التطبيق الرئيسي (Subtitle)
                        </label>
                        <input
                          type="text"
                          value={loginWelcomeSubtitle}
                          onChange={e => setLoginWelcomeSubtitle(e.target.value)}
                          className="w-full bg-[#1c1c1f] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-amber-300 font-bold"
                          placeholder="AHLA LIVE"
                        />
                      </div>
                    </div>

                    {/* خيار رفع صورة لوجو بديلة من الجهاز */}
                    <div>
                      <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">
                        أو ارفع صورة شعار مخصص من جهازك (PNG شفاف / WEBP):
                      </label>
                      <input
                        type="file"
                        ref={logoFileInputRef}
                        onChange={handleLogoFileUpload}
                        accept="image/*,.png,.webp,.svg"
                        className="hidden"
                      />
                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          disabled={logoUploading}
                          onClick={() => logoFileInputRef.current?.click()}
                          className="px-3 py-1.5 bg-amber-600/20 hover:bg-amber-600/30 text-amber-300 border border-amber-500/30 text-xs font-semibold rounded-lg flex items-center gap-1.5 cursor-pointer"
                        >
                          <Upload className="w-3.5 h-3.5" />
                          <span>{logoUploading ? `جاري الرفع... (${logoProgress}%)` : 'رفع شعار من جهازك 🖼️'}</span>
                        </button>
                        {loginWelcomeLogoUrl && (
                          <button
                            type="button"
                            onClick={() => setLoginWelcomeLogoUrl('')}
                            className="text-[11px] text-rose-400 hover:text-rose-300 px-2 py-1"
                          >
                            إلغاء الشعار المرفوع
                          </button>
                        )}
                      </div>
                      {loginWelcomeLogoUrl && (
                        <input
                          type="url"
                          value={loginWelcomeLogoUrl}
                          onChange={e => setLoginWelcomeLogoUrl(e.target.value)}
                          className="w-full bg-[#1c1c1f] border border-white/10 rounded-lg py-1 px-2 text-[11px] text-slate-400 font-mono mt-1.5"
                          placeholder="https://..."
                        />
                      )}
                    </div>
                  </div>

                  {/* معاينة ترويسة الترحيب المباشرة كما تظهر في التطبيق */}
                  <div className="bg-gradient-to-b from-slate-900/90 to-black/95 rounded-xl border border-white/10 p-5 flex flex-col items-center justify-center text-center relative shadow-inner">
                    <span className="text-[9px] uppercase tracking-wider text-slate-500 font-bold absolute top-2 right-3">
                      معاينة في شاشة الدخول
                    </span>

                    {loginWelcomeLogoUrl ? (
                      <div className="py-2">
                        <img
                          src={loginWelcomeLogoUrl}
                          alt="Welcome Logo"
                          className="max-h-16 object-contain drop-shadow-[0_4px_12px_rgba(0,0,0,0.8)]"
                        />
                      </div>
                    ) : (
                      <div className="py-2 space-y-1">
                        <div className="text-lg font-light tracking-[0.25em] text-white/90 drop-shadow-[0_2px_8px_rgba(0,0,0,0.8)]">
                          {loginWelcomeTitle || 'Welcome'}
                        </div>
                        <div className="text-2xl font-black tracking-[0.2em] text-white drop-shadow-[0_3px_12px_rgba(255,179,0,0.6)]">
                          {loginWelcomeSubtitle || 'AHLA LIVE'}
                        </div>
                      </div>
                    )}
                    <span className="text-[10px] text-emerald-400 bg-emerald-500/10 px-2 py-0.5 rounded-full border border-emerald-500/20 mt-1">
                      ✓ تظهر فوق الفيديو/الصورة بنقاء فائق
                    </span>
                  </div>
                </div>
              )}
            </div>

            {/* زر حفظ إعدادات شاشة الدخول */}
            <div className="flex items-center justify-between pt-2">
              <p className="text-[10px] text-slate-400">
                التغييرات تنعكس فورياً في تطبيق جميع المستخدمين دون الحاجة لإعادة رفع التطبيق.
              </p>
              <button
                onClick={handleSaveLoginConfig}
                disabled={loginSaving}
                className="px-5 py-2.5 bg-gradient-to-r from-amber-600 to-yellow-600 hover:from-amber-500 hover:to-yellow-500 disabled:opacity-50 text-xs text-white font-bold rounded-xl flex items-center gap-2 shadow-lg shadow-amber-600/30 transition-all cursor-pointer"
              >
                <Save className="w-4 h-4" />
                <span>{loginSaving ? 'جاري الحفظ...' : 'حفظ إعدادات شاشة الدخول وشعار الترحيب 💾'}</span>
              </button>
            </div>

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
                <input type="text" value={cloudName} onChange={e => setCloudName(e.target.value)} className="w-full bg-[#1c1c1f] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" placeholder="r5kohqhd" />
              </div>
              <div>
                <label className="block text-[9px] uppercase text-slate-500 font-bold mb-1">{t('cloudinary.apiKey')}</label>
                <input type="text" value={apiKey} onChange={e => setApiKey(e.target.value)} className="w-full bg-[#1c1c1f] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" placeholder="183298827798548" />
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
