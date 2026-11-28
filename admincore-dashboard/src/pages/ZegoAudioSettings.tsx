import { useEffect, useState, type FormEvent } from 'react';
import { supabase } from '../lib/supabase';
import {
  Mic,
  Key,
  Shield,
  Radio,
  Sliders,
  Save,
  CheckCircle2,
  AlertTriangle,
  Eye,
  EyeOff,
  Copy,
  Info,
  RefreshCw,
  Cpu,
} from 'lucide-react';

export default function ZegoAudioSettings() {
  const [provider, setProvider] = useState<'zego' | 'agora'>('zego');

  // Zego Credentials
  const [appId, setAppId] = useState<string>('2088500186');
  const [appSign, setAppSign] = useState<string>('');
  const [scenario, setScenario] = useState<number>(0);

  // Agora Credentials
  const [agoraAppId, setAgoraAppId] = useState<string>('');
  const [agoraCertificate, setAgoraCertificate] = useState<string>('');
  const [agoraToken, setAgoraToken] = useState<string>('');

  const [audioEnabled, setAudioEnabled] = useState<boolean>(true);
  const [loading, setLoading] = useState<boolean>(true);
  const [saving, setSaving] = useState<boolean>(false);
  const [showAppSign, setShowAppSign] = useState<boolean>(false);
  const [showAgoraCert, setShowAgoraCert] = useState<boolean>(false);
  const [statusMessage, setStatusMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);

  useEffect(() => {
    fetchConfig();
  }, []);

  const fetchConfig = async () => {
    setLoading(true);
    setStatusMessage(null);
    try {
      const { data, error } = await supabase
        .from('app_config')
        .select('key, value')
        .in('key', [
          'audio_provider',
          'zego_app_id',
          'zego_app_sign',
          'zego_scenario',
          'zego_audio_enabled',
          'agora_app_id',
          'agora_app_certificate',
          'agora_token',
        ]);

      if (!error && data) {
        for (const item of data) {
          if (item.key === 'audio_provider' && item.value) {
            const prov = String(item.value).toLowerCase();
            setProvider(prov === 'agora' ? 'agora' : 'zego');
          }
          if (item.key === 'zego_app_id' && item.value) setAppId(String(item.value));
          if (item.key === 'zego_app_sign' && item.value) setAppSign(String(item.value));
          if (item.key === 'agora_app_id' && item.value) setAgoraAppId(String(item.value));
          if (item.key === 'agora_app_certificate' && item.value) setAgoraCertificate(String(item.value));
          if (item.key === 'agora_token' && item.value) setAgoraToken(String(item.value));
          if (item.key === 'zego_scenario' && item.value !== undefined) setScenario(Number(item.value));
          if (item.key === 'zego_audio_enabled' && item.value !== undefined) setAudioEnabled(item.value !== false && item.value !== 'false');
        }
      }
    } catch (err) {
      console.error('Failed to load audio config:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleSave = async (e?: FormEvent) => {
    if (e) e.preventDefault();

    if (provider === 'zego') {
      if (!appId.trim()) {
        alert('يرجى إدخال Zego App ID');
        return;
      }
      const cleanSign = appSign.trim();
      if (cleanSign && cleanSign.length !== 64) {
        if (!confirm(`تنبيه: طول مفتاح AppSign الحالي (${cleanSign.length} حرف) ليس 64 رمزاً سداسياً عشرياً (Hex) كما هو معتاد في Zego.\nهل تريد المتابعة والحفظ على أية حال؟`)) {
          return;
        }
      }
    } else {
      if (!agoraAppId.trim()) {
        alert('يرجى إدخال Agora App ID');
        return;
      }
    }

    setSaving(true);
    setStatusMessage(null);

    try {
      const parsedZegoAppId = parseInt(appId.trim(), 10) || 2088500186;

      const { error } = await supabase.from('app_config').upsert([
        { key: 'audio_provider', value: provider },
        { key: 'zego_app_id', value: parsedZegoAppId },
        { key: 'zego_app_sign', value: appSign.trim() },
        { key: 'agora_app_id', value: agoraAppId.trim() },
        { key: 'agora_app_certificate', value: agoraCertificate.trim() },
        { key: 'agora_token', value: agoraToken.trim() },
        { key: 'zego_scenario', value: scenario },
        { key: 'zego_audio_enabled', value: audioEnabled },
      ], { onConflict: 'key' });

      if (error) throw error;

      setStatusMessage({
        type: 'success',
        text: `تم حفظ وتفعيل إعدادات محرك الصوت (${provider === 'agora' ? 'Agora RTC' : 'Zego Express'}) بنجاح في Supabase! يتم الآن تفعيل المفاتيح فورياً في تطبيق الموبايل لكافة المستخدمين.`,
      });
    } catch (err: any) {
      console.error('Error saving config:', err);
      setStatusMessage({
        type: 'error',
        text: 'فشل حفظ الإعدادات: ' + (err.message || 'خطأ غير متوقع'),
      });
    } finally {
      setSaving(false);
    }
  };

  const copyToClipboard = (val: string, label: string) => {
    navigator.clipboard.writeText(val);
    alert(`تم نسخ ${label} إلى الحافظة ✓`);
  };

  const isZegoConfigured = Boolean(appSign.trim().length === 64);
  const isAgoraConfigured = Boolean(agoraAppId.trim().length > 0);
  const isCurrentConfigured = provider === 'zego' ? isZegoConfigured : isAgoraConfigured;

  return (
    <div className="space-y-6 max-w-4xl pb-12">
      {/* Top Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-lg bg-amber-500/10 border border-amber-500/20 flex items-center justify-center text-amber-400">
              <Mic className="w-4 h-4" />
            </div>
            <h2 className="text-white text-lg font-semibold">إعدادات محركات الصوت (Zego & Agora) 🎙️</h2>
          </div>
          <p className="text-slate-400 text-xs mt-1">
            إدارة مفاتيح مزودي الصوت السحابية والتبديل المرن بين Agora و Zego بدون تعديل في كود التطبيق
          </p>
        </div>

        <button
          onClick={fetchConfig}
          disabled={loading}
          className="self-start sm:self-auto px-3.5 py-1.5 rounded-lg border border-white/10 hover:bg-white/5 text-xs text-slate-300 flex items-center gap-2 transition"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin' : ''}`} />
          تحديث البيانات
        </button>
      </div>

      {/* Provider Switcher Selector */}
      <div className="bg-[#141417] rounded-2xl border border-white/5 p-4">
        <label className="block text-xs font-semibold text-slate-300 mb-3">
          اختر المزود النشط للصوت في الغرف (Active Voice Engine):
        </label>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          {/* Zego Option Card */}
          <button
            type="button"
            onClick={() => setProvider('zego')}
            className={`p-4 rounded-xl border text-right transition flex items-center justify-between ${
              provider === 'zego'
                ? 'bg-amber-500/10 border-amber-500/50 text-white shadow-lg'
                : 'bg-[#1A1A1E] border-white/5 text-slate-400 hover:border-white/20'
            }`}
          >
            <div className="flex items-center gap-3">
              <div
                className={`w-9 h-9 rounded-lg flex items-center justify-center font-bold text-sm ${
                  provider === 'zego' ? 'bg-amber-500 text-black' : 'bg-white/5 text-slate-400'
                }`}
              >
                Z
              </div>
              <div>
                <div className="text-sm font-bold text-white flex items-center gap-2">
                  Zego Express Audio
                  {provider === 'zego' && (
                    <span className="text-[10px] bg-amber-500/20 text-amber-400 border border-amber-500/30 px-2 py-0.5 rounded-full">
                      النشط حالياً
                    </span>
                  )}
                </div>
                <div className="text-[11px] text-slate-400 mt-0.5">
                  AppID رقمي + AppSign سداسي عشري (64 حرف)
                </div>
              </div>
            </div>
            <div
              className={`w-4 h-4 rounded-full border flex items-center justify-center ${
                provider === 'zego' ? 'border-amber-400 bg-amber-400' : 'border-slate-600'
              }`}
            >
              {provider === 'zego' && <div className="w-1.5 h-1.5 rounded-full bg-black" />}
            </div>
          </button>

          {/* Agora Option Card */}
          <button
            type="button"
            onClick={() => setProvider('agora')}
            className={`p-4 rounded-xl border text-right transition flex items-center justify-between ${
              provider === 'agora'
                ? 'bg-indigo-500/10 border-indigo-500/50 text-white shadow-lg'
                : 'bg-[#1A1A1E] border-white/5 text-slate-400 hover:border-white/20'
            }`}
          >
            <div className="flex items-center gap-3">
              <div
                className={`w-9 h-9 rounded-lg flex items-center justify-center font-bold text-sm ${
                  provider === 'agora' ? 'bg-indigo-500 text-white' : 'bg-white/5 text-slate-400'
                }`}
              >
                <Cpu className="w-4 h-4" />
              </div>
              <div>
                <div className="text-sm font-bold text-white flex items-center gap-2">
                  Agora RTC Engine
                  {provider === 'agora' && (
                    <span className="text-[10px] bg-indigo-500/20 text-indigo-300 border border-indigo-500/30 px-2 py-0.5 rounded-full">
                      النشط حالياً
                    </span>
                  )}
                </div>
                <div className="text-[11px] text-slate-400 mt-0.5">
                  AppID نصي (32 حرف) + الشهادة/التوكن الاختياري
                </div>
              </div>
            </div>
            <div
              className={`w-4 h-4 rounded-full border flex items-center justify-center ${
                provider === 'agora' ? 'border-indigo-400 bg-indigo-400' : 'border-slate-600'
              }`}
            >
              {provider === 'agora' && <div className="w-1.5 h-1.5 rounded-full bg-black" />}
            </div>
          </button>
        </div>
      </div>

      {/* Live Status Banner */}
      <div
        className={`p-4 rounded-xl border flex items-start gap-3.5 ${
          !audioEnabled
            ? 'bg-rose-500/10 border-rose-500/20 text-rose-300'
            : isCurrentConfigured
            ? 'bg-emerald-500/10 border-emerald-500/20 text-emerald-300'
            : 'bg-amber-500/10 border-amber-500/20 text-amber-300'
        }`}
      >
        {!audioEnabled ? (
          <AlertTriangle className="w-5 h-5 shrink-0 text-rose-400 mt-0.5" />
        ) : isCurrentConfigured ? (
          <CheckCircle2 className="w-5 h-5 shrink-0 text-emerald-400 mt-0.5" />
        ) : (
          <Info className="w-5 h-5 shrink-0 text-amber-400 mt-0.5" />
        )}
        <div className="flex-1 text-xs">
          <div className="font-semibold text-sm">
            {!audioEnabled
              ? 'محرك الصوت معطل حالياً'
              : isCurrentConfigured
              ? `محرك ${provider === 'agora' ? 'Agora RTC' : 'Zego Express'} جاهز ومفعل سحابياً`
              : `ينقص إدخال مفاتيح ${provider === 'agora' ? 'Agora' : 'Zego'}`}
          </div>
          <div className="text-slate-400 mt-0.5 leading-relaxed">
            {!audioEnabled
              ? 'تم تعطيل المايكات والصوت في الغرف مؤقتاً من لوحة التحكم.'
              : isCurrentConfigured
              ? provider === 'agora'
                ? `معرف Agora AppID المسجل: ${agoraAppId.slice(0, 8)}... ويتم تشغيل الصوت عبر شبكة Agora العالمية.`
                : `معرف Zego AppID النشط: ${appId} ومفتاح AppSign مسجل بالكامل.`
              : `يرجى إدخال مفتاح ${provider === 'agora' ? 'Agora App ID' : 'Zego AppSign'} والضغط على "حفظ" لتفعيل الصوت.`}
          </div>
        </div>
      </div>

      {statusMessage && (
        <div
          className={`p-4 rounded-xl text-xs flex items-center gap-2 ${
            statusMessage.type === 'success'
              ? 'bg-emerald-500/15 text-emerald-300 border border-emerald-500/30'
              : 'bg-rose-500/15 text-rose-300 border border-rose-500/30'
          }`}
        >
          {statusMessage.type === 'success' ? <CheckCircle2 className="w-4 h-4 shrink-0" /> : <AlertTriangle className="w-4 h-4 shrink-0 text-rose-400" />}
          <span>{statusMessage.text}</span>
        </div>
      )}

      {/* Main Settings Form */}
      <form onSubmit={handleSave} className="space-y-6">
        {/* Card 1: Zego Credentials */}
        <div className={`bg-[#141417] rounded-2xl border ${provider === 'zego' ? 'border-amber-500/30' : 'border-white/5 opacity-80'} p-6 space-y-5 transition`}>
          <div className="flex items-center justify-between border-b border-white/5 pb-3">
            <div className="flex items-center gap-2">
              <Key className="w-4 h-4 text-amber-400" />
              <h3 className="text-sm font-semibold text-white">بيانات اعتماد Zego (Zego Credentials)</h3>
            </div>
            {provider === 'zego' && (
              <span className="text-[11px] font-semibold text-amber-400 bg-amber-500/10 px-2.5 py-1 rounded-full border border-amber-500/20">
                المحرك النشط الآن
              </span>
            )}
          </div>

          <div className="grid grid-cols-1 gap-5">
            {/* App ID */}
            <div>
              <div className="flex items-center justify-between mb-1.5">
                <label className="text-xs font-medium text-slate-300">معرف التطبيق (Zego App ID)</label>
                <button
                  type="button"
                  onClick={() => copyToClipboard(appId, 'App ID')}
                  className="text-[10px] text-slate-400 hover:text-white flex items-center gap-1"
                >
                  <Copy className="w-3 h-3" /> نسخ
                </button>
              </div>
              <input
                type="number"
                value={appId}
                onChange={e => setAppId(e.target.value)}
                placeholder="2088500186"
                className="w-full bg-[#1A1A1E] border border-white/10 rounded-xl px-3.5 py-2.5 text-xs text-white font-mono focus:border-amber-400 focus:outline-none transition"
              />
              <p className="text-[10px] text-slate-500 mt-1">
                المعرف الرقمي للمشروع في Zego Cloud Console.
              </p>
            </div>

            {/* App Sign */}
            <div>
              <div className="flex items-center justify-between mb-1.5">
                <label className="text-xs font-medium text-slate-300">مفتاح التوقيع (Zego App Sign)</label>
                <div className="flex items-center gap-2">
                  <span
                    className={`text-[10px] font-mono px-2 py-0.5 rounded ${
                      appSign.trim().length === 64
                        ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                        : appSign.trim().length > 0
                        ? 'bg-amber-500/20 text-amber-300'
                        : 'bg-slate-800 text-slate-500'
                    }`}
                  >
                    {appSign.trim().length} / 64 حرف
                  </span>
                  <button
                    type="button"
                    onClick={() => setShowAppSign(!showAppSign)}
                    className="text-[10px] text-slate-400 hover:text-white flex items-center gap-1"
                  >
                    {showAppSign ? <EyeOff className="w-3 h-3" /> : <Eye className="w-3 h-3" />}
                    {showAppSign ? 'إخفاء' : 'إظهار'}
                  </button>
                </div>
              </div>
              <div className="relative">
                <input
                  type={showAppSign ? 'text' : 'password'}
                  value={appSign}
                  onChange={e => setAppSign(e.target.value)}
                  placeholder="أدخل 64 رمز سداسي عشري (Hex AppSign)..."
                  className="w-full bg-[#1A1A1E] border border-white/10 rounded-xl px-3.5 py-2.5 text-xs text-white font-mono focus:border-amber-400 focus:outline-none transition"
                />
              </div>
              <p className="text-[10px] text-slate-500 mt-1">
                مفتاح التوقيع المخصص لحساب Zego (64 رمز Hex).
              </p>
            </div>
          </div>
        </div>

        {/* Card 2: Agora Credentials */}
        <div className={`bg-[#141417] rounded-2xl border ${provider === 'agora' ? 'border-indigo-500/30' : 'border-white/5 opacity-80'} p-6 space-y-5 transition`}>
          <div className="flex items-center justify-between border-b border-white/5 pb-3">
            <div className="flex items-center gap-2">
              <Key className="w-4 h-4 text-indigo-400" />
              <h3 className="text-sm font-semibold text-white">بيانات اعتماد Agora (Agora Credentials)</h3>
            </div>
            {provider === 'agora' && (
              <span className="text-[11px] font-semibold text-indigo-300 bg-indigo-500/10 px-2.5 py-1 rounded-full border border-indigo-500/20">
                المحرك النشط الآن
              </span>
            )}
          </div>

          <div className="grid grid-cols-1 gap-5">
            {/* Agora App ID */}
            <div>
              <div className="flex items-center justify-between mb-1.5">
                <label className="text-xs font-medium text-slate-300">معرف تطبيق Agora (Agora App ID)</label>
                <div className="flex items-center gap-2">
                  <span
                    className={`text-[10px] font-mono px-2 py-0.5 rounded ${
                      agoraAppId.trim().length === 32
                        ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                        : agoraAppId.trim().length > 0
                        ? 'bg-indigo-500/20 text-indigo-300'
                        : 'bg-slate-800 text-slate-500'
                    }`}
                  >
                    {agoraAppId.trim().length} حرف (المعتاد 32)
                  </span>
                  <button
                    type="button"
                    onClick={() => copyToClipboard(agoraAppId, 'Agora App ID')}
                    className="text-[10px] text-slate-400 hover:text-white flex items-center gap-1"
                  >
                    <Copy className="w-3 h-3" /> نسخ
                  </button>
                </div>
              </div>
              <input
                type="text"
                value={agoraAppId}
                onChange={e => setAgoraAppId(e.target.value)}
                placeholder="مثال: eb1f5fe3800f430582a3e07140c27143"
                className="w-full bg-[#1A1A1E] border border-white/10 rounded-xl px-3.5 py-2.5 text-xs text-white font-mono focus:border-indigo-400 focus:outline-none transition"
              />
              <p className="text-[10px] text-slate-500 mt-1">
                المعرف النصي المكون من 32 حرفاً المستخرج من Agora Console.
              </p>
            </div>

            {/* Agora App Certificate / Secret */}
            <div>
              <div className="flex items-center justify-between mb-1.5">
                <label className="text-xs font-medium text-slate-300">شهادة التطبيق (Agora App Certificate / Secret)</label>
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => setShowAgoraCert(!showAgoraCert)}
                    className="text-[10px] text-slate-400 hover:text-white flex items-center gap-1"
                  >
                    {showAgoraCert ? <EyeOff className="w-3 h-3" /> : <Eye className="w-3 h-3" />}
                    {showAgoraCert ? 'إخفاء' : 'إظهار'}
                  </button>
                </div>
              </div>
              <div className="relative">
                <input
                  type={showAgoraCert ? 'text' : 'password'}
                  value={agoraCertificate}
                  onChange={e => setAgoraCertificate(e.target.value)}
                  placeholder="أدخل Agora App Certificate (اختياري في وضع No-Certificate)..."
                  className="w-full bg-[#1A1A1E] border border-white/10 rounded-xl px-3.5 py-2.5 text-xs text-white font-mono focus:border-indigo-400 focus:outline-none transition"
                />
              </div>
              <p className="text-[10px] text-slate-500 mt-1">
                شهادة المشروع في Agora لتأمين التوكن. إذا كان مشروعك في Agora بدون شهادة (App ID Only)، يمكنك ترك هذا الحقل فارغاً.
              </p>
            </div>

            {/* Agora RTC Token (Optional / Static) */}
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1.5">توكن اتصال الغرف (RTC Token - اختياري)</label>
              <input
                type="text"
                value={agoraToken}
                onChange={e => setAgoraToken(e.target.value)}
                placeholder="أدخل Token اختياري إذا كان المشروع يتطلب توكن مسبقاً..."
                className="w-full bg-[#1A1A1E] border border-white/10 rounded-xl px-3.5 py-2.5 text-xs text-white font-mono focus:border-indigo-400 focus:outline-none transition"
              />
              <p className="text-[10px] text-slate-500 mt-1">
                اتركه فارغاً إذا كان مشروع Agora يعمل بوضع App ID فقط بدون تشفير التوكن.
              </p>
            </div>
          </div>
        </div>

        {/* Card 3: Quality & Master Switch */}
        <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-5">
          <div className="flex items-center gap-2 border-b border-white/5 pb-3">
            <Sliders className="w-4 h-4 text-indigo-400" />
            <h3 className="text-sm font-semibold text-white">إعدادات الجودة والتشغيل العام</h3>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
            {/* Scenario */}
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1.5">سيناريو معالجة الصوت (Scenario)</label>
              <select
                value={scenario}
                onChange={e => setScenario(Number(e.target.value))}
                className="w-full bg-[#1A1A1E] border border-white/10 rounded-xl px-3.5 py-2.5 text-xs text-white focus:border-amber-400 focus:outline-none transition"
              >
                <option value={0}>🔊 Default (الوضع التفاعلي القياسي لغرف الدردشة)</option>
                <option value={2}>🎵 HighQualityChatroom (صوت نقي عالي الجودة والموسيقى)</option>
                <option value={1}>📞 StandardVoiceCall (مكالمة عادية موفرة لاستهلاك البيانات)</option>
              </select>
            </div>

            {/* Master Switch */}
            <div className="flex flex-col justify-center">
              <div className="flex items-center justify-between">
                <div>
                  <div className="text-xs font-medium text-white flex items-center gap-2">
                    <Radio className="w-3.5 h-3.5 text-amber-400" />
                    تفعيل محرك الصوت في الغرف
                  </div>
                  <div className="text-[11px] text-slate-500 mt-0.5">
                    إيقاف هذا المفتاح يعطل تشغيل المايكات مؤقتاً في التطبيق
                  </div>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    checked={audioEnabled}
                    onChange={e => setAudioEnabled(e.target.checked)}
                    className="sr-only peer"
                  />
                  <div className="w-11 h-6 bg-slate-800 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-amber-500"></div>
                </label>
              </div>
            </div>
          </div>
        </div>

        {/* Card 4: Architecture Info */}
        <div className="bg-[#141417] rounded-2xl border border-white/5 p-5 flex items-start gap-3">
          <Shield className="w-5 h-5 text-emerald-400 shrink-0 mt-0.5" />
          <div className="text-xs text-slate-400 space-y-1">
            <div className="font-semibold text-white">كيف يعمل التبديل السحابي الفوري بين Agora و Zego؟</div>
            <p className="leading-relaxed">
              يقوم تطبيق Flutter بالاستماع المباشر للتعديلات في <code className="text-amber-300 font-mono">app_config</code> عبر Supabase.
              عندما تختار Agora أو Zego وتضغط "حفظ"، يستقبل التطبيق فوراً نوع المزود والمفاتيح الخاصة به ويهيئ المحرك المختار تلقائياً، دون أي تعارض في البنية!
            </p>
          </div>
        </div>

        {/* Save Button */}
        <div className="flex justify-end">
          <button
            type="submit"
            disabled={saving || loading}
            className="px-6 py-2.5 bg-gradient-to-r from-amber-500 to-amber-600 hover:from-amber-600 hover:to-amber-700 disabled:opacity-50 text-black font-bold text-xs rounded-xl shadow-lg flex items-center gap-2 transition"
          >
            <Save className="w-4 h-4" />
            {saving ? 'جارٍ الحفظ والتطبيق...' : 'حفظ وتطبيق التغييرات لجميع المستخدمين'}
          </button>
        </div>
      </form>
    </div>
  );
}
