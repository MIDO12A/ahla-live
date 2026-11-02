import { useState, FormEvent, useContext } from 'react';
import { loginWithEmail } from '../lib/auth';
import { I18nContext } from '../lib/i18n';
import { Eye, EyeOff, KeyRound, Mail, AlertCircle, ShieldCheck } from 'lucide-react';

function parseAuthError(err: unknown, lang: 'ar' | 'en'): string {
  const code = (err as { code?: string })?.code || '';
  const rawMsg = (err as { message?: string })?.message || String(err || '');
  const lower = rawMsg.toLowerCase();

  if (lang === 'ar') {
    if (
      code === 'auth/invalid-credential' ||
      code === 'auth/wrong-password' ||
      code === 'auth/user-not-found' ||
      lower.includes('invalid login credentials') ||
      lower.includes('invalid credentials')
    ) {
      return 'البريد الإلكتروني أو كلمة المرور غير صحيحة. يرجى التأكد من بيانات الحساب.';
    }
    if (code === 'auth/invalid-email' || lower.includes('invalid email')) {
      return 'صيغة البريد الإلكتروني غير صحيحة.';
    }
    if (lower.includes('email not confirmed')) {
      return 'البريد الإلكتروني لم يتم تأكيده بعد.';
    }
    if (code === 'auth/too-many-requests' || lower.includes('rate limit') || lower.includes('too many requests')) {
      return 'تم حظر الطلبات مؤقتاً لكثرة المحاولات. يرجى الانتظار دقيقة والمحاولة مجدداً.';
    }
    if (code === 'auth/network-request-failed' || lower.includes('network') || lower.includes('fetch')) {
      return 'تعذر الاتصال بالخادم. يرجى التحقق من اتصال الإنترنت.';
    }
    return rawMsg || 'فشل تسجيل الدخول. يرجى التأكد من البيانات.';
  } else {
    if (
      code === 'auth/invalid-credential' ||
      code === 'auth/wrong-password' ||
      code === 'auth/user-not-found' ||
      lower.includes('invalid login credentials') ||
      lower.includes('invalid credentials')
    ) {
      return 'Invalid email or password. Please verify your credentials.';
    }
    if (code === 'auth/invalid-email' || lower.includes('invalid email')) {
      return 'Invalid email format.';
    }
    if (lower.includes('email not confirmed')) {
      return 'Email not confirmed yet.';
    }
    if (code === 'auth/too-many-requests' || lower.includes('rate limit') || lower.includes('too many requests')) {
      return 'Access temporarily disabled due to many failed attempts. Try again later.';
    }
    if (code === 'auth/network-request-failed' || lower.includes('network') || lower.includes('fetch')) {
      return 'Network error. Please check your internet connection.';
    }
    return rawMsg || 'Login failed. Please check your credentials.';
  }
}

export default function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const { t, lang, setLang } = useContext(I18nContext);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      await loginWithEmail(email.trim(), password);
    } catch (err: unknown) {
      setError(parseAuthError(err, lang));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-[#0A0A0B] flex flex-col items-center justify-center p-4 relative overflow-hidden selection:bg-indigo-500/30">
      {/* Ambient depth */}
      <div className="pointer-events-none absolute inset-0">
        <div className="absolute top-1/4 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[30rem] h-[30rem] bg-indigo-600/15 rounded-full blur-[130px]" />
        <div className="absolute bottom-0 right-0 w-[24rem] h-[24rem] bg-violet-600/10 rounded-full blur-[120px]" />
        <div
          className="absolute inset-0 opacity-[0.035]"
          style={{
            backgroundImage:
              'linear-gradient(rgba(255,255,255,0.6) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.6) 1px, transparent 1px)',
            backgroundSize: '52px 52px',
            maskImage: 'radial-gradient(ellipse at center, black 20%, transparent 75%)',
            WebkitMaskImage: 'radial-gradient(ellipse at center, black 20%, transparent 75%)',
          }}
        />
      </div>

      {/* Language Switcher */}
      <div className="absolute top-5 right-5 z-20 flex items-center gap-1 glass-strong rounded-xl p-1 text-xs shadow-xl shadow-black/40">
        <button
          type="button"
          onClick={() => setLang('ar')}
          className={`px-3 py-1.5 rounded-lg transition-all font-medium cursor-pointer ${
            lang === 'ar' ? 'btn-3d text-white' : 'text-slate-400 hover:text-white'
          }`}
        >
          العربية
        </button>
        <button
          type="button"
          onClick={() => setLang('en')}
          className={`px-3 py-1.5 rounded-lg transition-all font-medium cursor-pointer ${
            lang === 'en' ? 'btn-3d text-white' : 'text-slate-400 hover:text-white'
          }`}
        >
          English
        </button>
      </div>

      <div className="w-full max-w-sm relative z-10 animate-fade-in">
        <form
          onSubmit={handleSubmit}
          className="glass-strong rounded-3xl p-8 space-y-5 shadow-2xl shadow-black/60 relative overflow-hidden"
        >
          {/* Top highlight */}
          <div className="absolute inset-x-8 top-0 h-px bg-gradient-to-r from-transparent via-indigo-400/60 to-transparent" />

          {/* Header */}
          <div className="text-center">
            <div className="relative w-16 h-16 rounded-2xl bg-gradient-to-tr from-indigo-600 via-violet-600 to-fuchsia-500 flex items-center justify-center text-white font-black text-2xl mx-auto mb-4 shadow-xl shadow-indigo-600/30 ring-1 ring-white/20">
              Z
              <span className="absolute inset-0 rounded-2xl bg-gradient-to-b from-white/30 to-transparent opacity-60" />
            </div>
            <h1 className="text-white text-xl font-bold tracking-tight">{t('app.name')}</h1>
            <p className="text-slate-400 text-xs mt-1 font-medium">{t('login.subtitle')}</p>
          </div>

          {/* Error Message Banner */}
          {error && (
            <div className="flex items-start gap-2.5 bg-rose-500/10 border border-rose-500/30 text-rose-300 text-xs p-3.5 rounded-xl leading-relaxed animate-fade-in">
              <AlertCircle className="w-4 h-4 shrink-0 mt-0.5 text-rose-400" />
              <span>{error}</span>
            </div>
          )}

          {/* Input Fields */}
          <div className="space-y-4">
            <div>
              <label className="block text-[11px] uppercase text-slate-400 font-bold mb-1.5 tracking-wider">
                {lang === 'ar' ? 'البريد الإلكتروني أو الآيدي (App ID)' : 'Email or App ID'}
              </label>
              <div className="relative">
                <Mail className="absolute left-3.5 top-3 text-slate-500 w-4 h-4 rtl:left-auto rtl:right-3.5" />
                <input
                  type="text"
                  value={email}
                  onChange={e => setEmail(e.target.value)}
                  placeholder={lang === 'ar' ? 'البريد أو الآيدي داخل التطبيق...' : 'Email or App ID...'}
                  className="input-3d w-full rounded-xl py-2.5 pl-10 pr-4 text-xs text-white placeholder-slate-600 focus:outline-none font-sans rtl:pl-4 rtl:pr-10"
                  required
                />
              </div>
            </div>

            <div>
              <label className="block text-[11px] uppercase text-slate-400 font-bold mb-1.5 tracking-wider">
                {t('login.password')}
              </label>
              <div className="relative">
                <KeyRound className="absolute left-3.5 top-3 text-slate-500 w-4 h-4 rtl:left-auto rtl:right-3.5" />
                <input
                  type={showPassword ? 'text' : 'password'}
                  value={password}
                  onChange={e => setPassword(e.target.value)}
                  placeholder="••••••••"
                  className="input-3d w-full rounded-xl py-2.5 pl-10 pr-10 text-xs text-white placeholder-slate-600 focus:outline-none rtl:pl-10 rtl:pr-10"
                  required
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3.5 top-3 text-slate-500 hover:text-slate-300 w-4 h-4 rtl:right-auto rtl:left-3.5 transition-colors cursor-pointer"
                >
                  {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>
            </div>
          </div>

          <button
            type="submit"
            disabled={loading}
            className="btn-3d w-full py-3 disabled:opacity-50 disabled:transform-none text-xs text-white font-bold rounded-xl flex items-center justify-center gap-2 cursor-pointer"
          >
            {loading ? (
              <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
            ) : (
              t('login.submit')
            )}
          </button>

          <div className="flex items-center justify-center gap-1.5 text-[10px] text-slate-500 pt-1">
            <ShieldCheck className="w-3 h-3 text-emerald-400/70" />
            <span>{lang === 'ar' ? 'اتصال مشفّر وآمن' : 'Secure encrypted connection'}</span>
          </div>
        </form>
      </div>
    </div>
  );
}
