import { useEffect, useState } from 'react';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { firestoreDb } from '../lib/firebase';
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
} from 'lucide-react';

export default function ZegoAudioSettings() {
  const [appId, setAppId] = useState<string>('2088500186');
  const [appSign, setAppSign] = useState<string>('');
  const [provider, setProvider] = useState<string>('zego');
  const [scenario, setScenario] = useState<number>(0);
  const [audioEnabled, setAudioEnabled] = useState<boolean>(true);

  const [loading, setLoading] = useState<boolean>(true);
  const [saving, setSaving] = useState<boolean>(false);
  const [showAppSign, setShowAppSign] = useState<boolean>(false);
  const [statusMessage, setStatusMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);

  useEffect(() => {
    fetchConfig();
  }, []);

  const fetchConfig = async () => {
    setLoading(true);
    setStatusMessage(null);
    try {
      // 1. Try reading from Firestore app_config
      const idDoc = await getDoc(doc(firestoreDb, 'app_config', 'zego_app_id'));
      const signDoc = await getDoc(doc(firestoreDb, 'app_config', 'zego_app_sign'));
      const provDoc = await getDoc(doc(firestoreDb, 'app_config', 'audio_provider'));
      const scenDoc = await getDoc(doc(firestoreDb, 'app_config', 'zego_scenario'));
      const enDoc = await getDoc(doc(firestoreDb, 'app_config', 'zego_audio_enabled'));

      if (idDoc.exists() && idDoc.data()?.value) {
        setAppId(String(idDoc.data()?.value));
      }
      if (signDoc.exists() && signDoc.data()?.value) {
        setAppSign(String(signDoc.data()?.value));
      }
      if (provDoc.exists() && provDoc.data()?.value) {
        setProvider(String(provDoc.data()?.value));
      }
      if (scenDoc.exists() && scenDoc.data()?.value !== undefined) {
        setScenario(Number(scenDoc.data()?.value));
      }
      if (enDoc.exists() && enDoc.data()?.value !== undefined) {
        setAudioEnabled(enDoc.data()?.value !== false);
      }
    } catch (e: any) {
      console.warn('Firestore fetch fallback, trying Supabase...', e);
      try {
        const { data } = await supabase
          .from('app_config')
          .select('key, value')
          .in('key', ['zego_app_id', 'zego_app_sign', 'audio_provider', 'zego_scenario', 'zego_audio_enabled']);

        if (data) {
          for (const item of data) {
            if (item.key === 'zego_app_id' && item.value) setAppId(String(item.value));
            if (item.key === 'zego_app_sign' && item.value) setAppSign(String(item.value));
            if (item.key === 'audio_provider' && item.value) setProvider(String(item.value));
            if (item.key === 'zego_scenario' && item.value !== undefined) setScenario(Number(item.value));
            if (item.key === 'zego_audio_enabled' && item.value !== undefined) setAudioEnabled(item.value !== false && item.value !== 'false');
          }
        }
      } catch (err) {
        console.error('Failed to load audio config:', err);
      }
    } finally {
      setLoading(false);
    }
  };

  const handleSave = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
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

    setSaving(true);
    setStatusMessage(null);

    try {
      const parsedAppId = parseInt(appId.trim(), 10) || 2088500186;

      // 1. Save directly to Cloud Firestore (app_config collection)
      await setDoc(doc(firestoreDb, 'app_config', 'zego_app_id'), { value: parsedAppId }, { merge: true });
      await setDoc(doc(firestoreDb, 'app_config', 'zego_app_sign'), { value: cleanSign }, { merge: true });
      await setDoc(doc(firestoreDb, 'app_config', 'audio_provider'), { value: provider }, { merge: true });
      await setDoc(doc(firestoreDb, 'app_config', 'zego_scenario'), { value: scenario }, { merge: true });
      await setDoc(doc(firestoreDb, 'app_config', 'zego_audio_enabled'), { value: audioEnabled }, { merge: true });

      // 2. Also save to Supabase app_config for dual compatibility
      try {
        await supabase.from('app_config').upsert([
          { key: 'zego_app_id', value: parsedAppId },
          { key: 'zego_app_sign', value: cleanSign },
          { key: 'audio_provider', value: provider },
          { key: 'zego_scenario', value: scenario },
          { key: 'zego_audio_enabled', value: audioEnabled },
        ], { onConflict: 'key' });
      } catch (err) {
        console.warn('Supabase sync skipped:', err);
      }

      setStatusMessage({
        type: 'success',
        text: 'تم حفظ وتطبيق إعدادات Zego ومحرك الصوت بنجاح! يتم الآن تفعيل المفاتيح فورياً في تطبيق الموبايل لجميع المستخدمين.',
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

  const isConfigured = Boolean(appSign.trim().length === 64);

  return (
    <div className="space-y-6 max-w-4xl pb-12">
      {/* Top Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-lg bg-amber-500/10 border border-amber-500/20 flex items-center justify-center text-amber-400">
              <Mic className="w-4 h-4" />
            </div>
            <h2 className="text-white text-lg font-semibold">إعدادات Zego ومحرك الصوت 🎙️</h2>
          </div>
          <p className="text-slate-400 text-xs mt-1">
            إدارة مفاتيح Zego AppID و AppSign السحابية وتعيين جودة ومزود الصوت في الغرف
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

      {/* Live Status Banner */}
      <div
        className={`p-4 rounded-xl border flex items-start gap-3.5 ${
          !audioEnabled
            ? 'bg-rose-500/10 border-rose-500/20 text-rose-300'
            : isConfigured
            ? 'bg-emerald-500/10 border-emerald-500/20 text-emerald-300'
            : 'bg-amber-500/10 border-amber-500/20 text-amber-300'
        }`}
      >
        {!audioEnabled ? (
          <AlertTriangle className="w-5 h-5 shrink-0 text-rose-400 mt-0.5" />
        ) : isConfigured ? (
          <CheckCircle2 className="w-5 h-5 shrink-0 text-emerald-400 mt-0.5" />
        ) : (
          <Info className="w-5 h-5 shrink-0 text-amber-400 mt-0.5" />
        )}
        <div className="flex-1 text-xs">
          <div className="font-semibold text-sm">
            {!audioEnabled
              ? 'محرك الصوت معطل حالياً'
              : isConfigured
              ? 'محرك Zego جاهز ومفعل سحابياً'
              : 'ينقص إدخال مفتاح AppSign'}
          </div>
          <div className="text-slate-400 mt-0.5 leading-relaxed">
            {!audioEnabled
              ? 'تم تعطيل المايكات والصوت في الغرف مؤقتاً من لوحة التحكم.'
              : isConfigured
              ? `معرف التطبيق النشط: ${appId} | مفتاح AppSign مكون من 64 رمز ومسجل في قاعدة البيانات.`
              : 'يرجى نسخ مفتاح AppSign من Zego Console ولصقه أدناه والضغط على "حفظ" ليعمل الصوت في غرف التطبيق.'}
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
        {/* Card 1: Credentials */}
        <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-5">
          <div className="flex items-center gap-2 border-b border-white/5 pb-3">
            <Key className="w-4 h-4 text-amber-400" />
            <h3 className="text-sm font-semibold text-white">بيانات اعتماد Zego (Credentials)</h3>
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
                المعرف الرقمي للمشروع المسجل في Zego Cloud Console.
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
                مفتاح التوقيع المخصص لحسابك (64 رمز سداسي عشري)، يتم ربطه مباشرة بتطبيق الموبايل بدون كشفه للمستخدمين.
              </p>
            </div>
          </div>
        </div>

        {/* Card 2: Engine & Quality Options */}
        <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-5">
          <div className="flex items-center gap-2 border-b border-white/5 pb-3">
            <Sliders className="w-4 h-4 text-indigo-400" />
            <h3 className="text-sm font-semibold text-white">إعدادات الجودة ومزود الخدمة</h3>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
            {/* Audio Provider */}
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1.5">مزود الخدمة الصوتي</label>
              <select
                value={provider}
                onChange={e => setProvider(e.target.value)}
                className="w-full bg-[#1A1A1E] border border-white/10 rounded-xl px-3.5 py-2.5 text-xs text-white focus:border-amber-400 focus:outline-none transition"
              >
                <option value="zego">🎙️ Zego Express Audio (الافتراضي والموصى به للغرف)</option>
                <option value="agora">📡 Agora RTC Engine</option>
              </select>
            </div>

            {/* Audio Scenario */}
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
          </div>

          {/* Master Switch */}
          <div className="pt-3 border-t border-white/5 flex items-center justify-between">
            <div>
              <div className="text-xs font-medium text-white flex items-center gap-2">
                <Radio className="w-3.5 h-3.5 text-amber-400" />
                تفعيل محرك الصوت في الغرف
              </div>
              <div className="text-[11px] text-slate-500 mt-0.5">
                إيقاف هذا المفتاح يعطل تشغيل المايكات مؤقتاً في التطبيق عند الحاجة للصيانة
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

        {/* Card 3: Architecture Info */}
        <div className="bg-[#141417] rounded-2xl border border-white/5 p-5 flex items-start gap-3">
          <Shield className="w-5 h-5 text-indigo-400 shrink-0 mt-0.5" />
          <div className="text-xs text-slate-400 space-y-1">
            <div className="font-semibold text-white">كيف يستقبل تطبيق الموبايل هذه التعديلات؟</div>
            <p className="leading-relaxed">
              يقوم تطبيق Flutter بالاستماع المباشر للتعديلات في <code className="text-amber-300 font-mono">app_config</code> عبر Firebase Firestore.
              بمجرد الضغط على زر الحفظ، يتم تحديث المفتاح وتفعيله فوراً على هواتف جميع المستخدمين بدون الحاجة لإعادة رفع أو إصدار نسخة جديدة من التطبيق.
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
