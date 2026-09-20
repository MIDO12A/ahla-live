import { useState, FormEvent, useContext } from 'react';
import { loginWithEmail, registerWithEmail, resetPassword } from '../lib/auth';
import { I18nContext } from '../lib/i18n';
import { Eye, EyeOff, KeyRound, Mail, AlertCircle, CheckCircle2, ShieldCheck } from 'lucide-react';

type AuthMode = 'login' | 'register' | 'forgot';

function parseFirebaseError(err: unknown, lang: 'ar' | 'en'): string {
  const code = (err as { code?: string })?.code || '';
  const rawMsg = (err as { message?: string })?.message || '';

  if (lang === 'ar') {
    switch (code) {
      case 'auth/invalid-credential':
      case 'auth/wrong-password':
        return 'البريد الإلكتروني أو كلمة المرور غير صحيحة. يرجى التأكد من البيانات أو إنشاء حساب جديد إذا لم تكن قد سجلت بعد.';
      case 'auth/user-not-found':
        return 'هذا البريد الإلكتروني غير مسجل في Firebase. اضغط على "إنشاء حساب جديد" لإنشاء الحساب لأول مرة.';
      case 'auth/email-already-in-use':
        return 'هذا البريد الإلكتروني مسجل بالفعل. يرجى تسجيل الدخول مباشرة.';
      case 'auth/weak-password':
        return 'كلمة المرور ضعيفة جداً. يجب أن تحتوي على 6 أحرف على الأقل.';
      case 'auth/invalid-email':
        return 'صيغة البريد الإلكتروني غير صحيحة.';
      case 'auth/operation-not-allowed':
        return 'تسجيل الدخول بالبريد غير مفعل في Firebase Console. يرجى تفعيل "Email/Password" من Firebase Console > Authentication > Sign-in method.';
      case 'auth/too-many-requests':
        return 'تم حظر الطلبات مؤقتاً بسبب تكرار المحاولات غير الناجحة. يرجى الانتظار دقيقتين ثم المحاولة مجدداً.';
      case 'auth/network-request-failed':
        return 'تعذر الاتصال بخوادم Firebase. يرجى التحقق من اتصال الإنترنت.';
      default:
        return rawMsg || 'حدث خطأ أثناء المصادقة.';
    }
  } else {
    switch (code) {
      case 'auth/invalid-credential':
      case 'auth/wrong-password':
        return 'Invalid email or password. Check your credentials or create an account if you have not registered yet.';
      case 'auth/user-not-found':
        return 'No user found with this email. Click "Create New Account" to register.';
      case 'auth/email-already-in-use':
        return 'This email is already registered. Please sign in instead.';
      case 'auth/weak-password':
        return 'Password is too weak. It must be at least 6 characters.';
      case 'auth/invalid-email':
        return 'Invalid email format.';
      case 'auth/operation-not-allowed':
        return 'Email/Password sign-in is not enabled in Firebase Console (Authentication > Sign-in method).';
      case 'auth/too-many-requests':
        return 'Access temporarily disabled due to many failed attempts. Try again later.';
      case 'auth/network-request-failed':
        return 'Network connection failed. Please check your internet connection.';
      default:
        return rawMsg || 'An error occurred during authentication.';
    }
  }
}

export default function Login() {
  const [mode, setMode] = useState<AuthMode>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [loading, setLoading] = useState(false);

  const { t, lang, setLang } = useContext(I18nContext);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setSuccess('');

    if (mode === 'register') {
      if (password.length < 6) {
        setError(t('login.passwordLength'));
        return;
      }
      if (password !== confirmPassword) {
        setError(t('login.passwordMismatch'));
        return;
      }
    }

    setLoading(true);
    try {
      if (mode === 'login') {
        await loginWithEmail(email.trim(), password);
      } else if (mode === 'register') {
        await registerWithEmail(email.trim(), password);
      } else if (mode === 'forgot') {
        await resetPassword(email.trim());
        setSuccess(t('login.resetSent'));
      }
    } catch (err: unknown) {
      setError(parseFirebaseError(err, lang));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-[#0A0A0B] flex flex-col items-center justify-center p-4 relative selection:bg-indigo-500/30">
      {/* Background subtle glow */}
      <div className="absolute top-1/3 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96 bg-indigo-600/10 rounded-full blur-[100px] pointer-events-none" />

      {/* Language Switcher */}
      <div className="absolute top-5 right-5 flex items-center gap-2 bg-[#141416] border border-white/10 rounded-xl p-1 text-xs">
        <button
          type="button"
          onClick={() => setLang('ar')}
          className={`px-3 py-1 rounded-lg transition-colors font-medium ${
            lang === 'ar' ? 'bg-indigo-600 text-white' : 'text-slate-400 hover:text-white'
          }`}
        >
          العربية
        </button>
        <button
          type="button"
          onClick={() => setLang('en')}
          className={`px-3 py-1 rounded-lg transition-colors font-medium ${
            lang === 'en' ? 'bg-indigo-600 text-white' : 'text-slate-400 hover:text-white'
          }`}
        >
          English
        </button>
      </div>

      <div className="w-full max-w-md">
        <form
          onSubmit={handleSubmit}
          className="bg-[#0D0D0E]/90 backdrop-blur-xl border border-white/10 rounded-2xl p-8 space-y-5 shadow-2xl relative"
        >
          {/* Header */}
          <div className="text-center">
            <div className="w-14 h-14 rounded-2xl bg-gradient-to-tr from-indigo-600 to-violet-500 flex items-center justify-center text-white font-black text-2xl mx-auto mb-3 shadow-lg shadow-indigo-600/25">
              Z
            </div>
            <h1 className="text-white text-xl font-bold tracking-tight">{t('app.name')}</h1>
            <p className="text-slate-400 text-xs mt-1 font-medium">{t('login.subtitle')}</p>
          </div>

          {/* First Admin Notice */}
          <div className="flex items-start gap-2 bg-indigo-950/40 border border-indigo-500/20 text-indigo-300 text-[11px] p-3 rounded-xl leading-relaxed">
            <ShieldCheck className="w-4 h-4 shrink-0 mt-0.5 text-indigo-400" />
            <span>{t('login.firstAdminNotice')}</span>
          </div>

          {/* Error Message Banner */}
          {error && (
            <div className="flex items-start gap-2.5 bg-rose-500/10 border border-rose-500/30 text-rose-300 text-xs p-3.5 rounded-xl leading-relaxed">
              <AlertCircle className="w-4 h-4 shrink-0 mt-0.5 text-rose-400" />
              <span>{error}</span>
            </div>
          )}

          {/* Success Message Banner */}
          {success && (
            <div className="flex items-start gap-2.5 bg-emerald-500/10 border border-emerald-500/30 text-emerald-300 text-xs p-3.5 rounded-xl leading-relaxed">
              <CheckCircle2 className="w-4 h-4 shrink-0 mt-0.5 text-emerald-400" />
              <span>{success}</span>
            </div>
          )}

          {/* Mode Tabs */}
          {mode !== 'forgot' && (
            <div className="grid grid-cols-2 bg-[#161618] p-1 rounded-xl border border-white/5 text-xs font-semibold">
              <button
                type="button"
                onClick={() => {
                  setMode('login');
                  setError('');
                }}
                className={`py-2 rounded-lg transition-all ${
                  mode === 'login'
                    ? 'bg-indigo-600 text-white shadow-md'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                {t('login.submit')}
              </button>
              <button
                type="button"
                onClick={() => {
                  setMode('register');
                  setError('');
                }}
                className={`py-2 rounded-lg transition-all ${
                  mode === 'register'
                    ? 'bg-indigo-600 text-white shadow-md'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                {t('login.register')}
              </button>
            </div>
          )}

          {/* Input Fields */}
          <div className="space-y-4">
            {/* Email Field */}
            <div>
              <label className="block text-[11px] uppercase text-slate-400 font-bold mb-1.5 tracking-wider">
                {t('login.email')}
              </label>
              <div className="relative">
                <Mail className="absolute left-3 top-2.5 text-slate-500 w-4 h-4 rtl:left-auto rtl:right-3" />
                <input
                  type="email"
                  value={email}
                  onChange={e => setEmail(e.target.value)}
                  placeholder="admin@example.com"
                  className="w-full bg-[#161618] border border-white/10 rounded-xl py-2.5 px-9 text-xs text-white placeholder-slate-600 focus:outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 transition-colors"
                  required
                />
              </div>
            </div>

            {/* Password Field */}
            {mode !== 'forgot' && (
              <div>
                <div className="flex items-center justify-between mb-1.5">
                  <label className="block text-[11px] uppercase text-slate-400 font-bold tracking-wider">
                    {t('login.password')}
                  </label>
                  {mode === 'login' && (
                    <button
                      type="button"
                      onClick={() => {
                        setMode('forgot');
                        setError('');
                        setSuccess('');
                      }}
                      className="text-[11px] text-indigo-400 hover:text-indigo-300 transition-colors"
                    >
                      {t('login.forgotPassword')}
                    </button>
                  )}
                </div>
                <div className="relative">
                  <KeyRound className="absolute left-3 top-2.5 text-slate-500 w-4 h-4 rtl:left-auto rtl:right-3" />
                  <input
                    type={showPassword ? 'text' : 'password'}
                    value={password}
                    onChange={e => setPassword(e.target.value)}
                    placeholder="••••••••"
                    className="w-full bg-[#161618] border border-white/10 rounded-xl py-2.5 px-9 text-xs text-white placeholder-slate-600 focus:outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 transition-colors"
                    required
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-3 top-2.5 text-slate-500 hover:text-slate-300 w-4 h-4 rtl:right-auto rtl:left-3 transition-colors"
                  >
                    {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </button>
                </div>
              </div>
            )}

            {/* Confirm Password (Register Mode) */}
            {mode === 'register' && (
              <div>
                <label className="block text-[11px] uppercase text-slate-400 font-bold mb-1.5 tracking-wider">
                  {t('login.confirmPassword')}
                </label>
                <div className="relative">
                  <KeyRound className="absolute left-3 top-2.5 text-slate-500 w-4 h-4 rtl:left-auto rtl:right-3" />
                  <input
                    type={showPassword ? 'text' : 'password'}
                    value={confirmPassword}
                    onChange={e => setConfirmPassword(e.target.value)}
                    placeholder="••••••••"
                    className="w-full bg-[#161618] border border-white/10 rounded-xl py-2.5 px-9 text-xs text-white placeholder-slate-600 focus:outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 transition-colors"
                    required
                  />
                </div>
              </div>
            )}
          </div>

          {/* Submit Button */}
          <button
            type="submit"
            disabled={loading}
            className="w-full py-2.5 bg-gradient-to-r from-indigo-600 to-indigo-500 hover:from-indigo-500 hover:to-indigo-600 disabled:opacity-50 text-xs text-white font-bold rounded-xl transition-all shadow-lg shadow-indigo-600/20 active:scale-[0.99] flex items-center justify-center gap-2 cursor-pointer"
          >
            {loading ? (
              <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
            ) : mode === 'login' ? (
              t('login.submit')
            ) : mode === 'register' ? (
              t('login.register')
            ) : (
              t('login.sendResetLink')
            )}
          </button>

          {/* Back to Login link in forgot password mode */}
          {mode === 'forgot' && (
            <div className="text-center pt-2">
              <button
                type="button"
                onClick={() => {
                  setMode('login');
                  setError('');
                  setSuccess('');
                }}
                className="text-xs text-indigo-400 hover:text-indigo-300 font-medium transition-colors"
              >
                {t('login.backToLogin')}
              </button>
            </div>
          )}
        </form>
      </div>
    </div>
  );
}
