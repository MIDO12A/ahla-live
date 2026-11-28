import { useEffect, useState } from 'react';
import { getReports, updateReportStatus, updateUser } from '../lib/db';
import { supabase } from '../lib/supabase';
import { ReportModel } from '../types';
import { ShieldAlert, Ban, CheckCircle, Clock, Trash2, ExternalLink, RefreshCw, MessageSquare, AlertTriangle, Home, User } from 'lucide-react';

export default function Reports() {
  const [reports, setReports] = useState<ReportModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [filterType, setFilterType] = useState<'all' | 'feedback' | 'users' | 'rooms'>('all');

  const loadReports = async () => {
    try {
      setLoading(true);
      const res = await getReports();
      setReports(res);
    } catch (err) {
      console.error('Error loading reports:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadReports();
  }, []);

  const handleBan = async (report: ReportModel) => {
    if (!confirm(`هل أنت متأكد من حظر المستخدم (${report.reportedName || report.reportedUid})؟`)) return;
    try {
      await updateUser(report.reportedUid, { banned: true, banReason: `Reported: ${report.reason}` });
      await updateReportStatus(report.id, 'banned');
      await loadReports();
    } catch (err) {
      alert('فشل حظر المستخدم: ' + (err as Error).message);
    }
  };

  const handleDismiss = async (report: ReportModel) => {
    if (!confirm('هل تريد بالتأكيد تجاهل هذا البلاغ؟')) return;
    try {
      await updateReportStatus(report.id, 'dismissed');
      await loadReports();
    } catch (err) {
      alert('فشل تجاهل البلاغ: ' + (err as Error).message);
    }
  };

  const handleResolve = async (reportId: string) => {
    try {
      await updateReportStatus(reportId, 'resolved');
      await loadReports();
    } catch (err) {
      alert('حدث خطأ أثناء معالجة البلاغ: ' + (err as Error).message);
    }
  };

  const handleDelete = async (reportId: string) => {
    if (!confirm('هل تريد حذف هذا البلاغ نهائياً من قاعدة البيانات؟')) return;
    try {
      const { error } = await supabase.from('reports').delete().eq('id', reportId);
      if (error) throw error;
      setReports(prev => prev.filter(r => r.id !== reportId));
    } catch (err: any) {
      alert('فشل حذف البلاغ: ' + (err?.message || err));
    }
  };

  const extractScreenshot = (report: ReportModel): string | null => {
    if (report.screenshot && report.screenshot.startsWith('http')) return report.screenshot;
    const text = (report.description || report.details || '') as string;
    const match = text.match(/صورة الإثبات:\s*(https?:\/\/[^\s]+)/i) || text.match(/(https?:\/\/[^\s]+(?:\.png|\.jpg|\.jpeg|\.webp|\.gif|[^\s]*cloudinary[^\s]*|[^\s]*supabase[^\s]*))/i);
    return match ? match[1] : null;
  };

  const isFeedbackReport = (r: ReportModel) => {
    const reason = (r.reason || '').toLowerCase();
    const desc = (r.description || r.details || '').toLowerCase();
    return reason.includes('شكوى') || reason.includes('اقتراح') || desc.includes('شكوى') || desc.includes('اقتراح') || r.reportedUid === 'ADMIN_FEEDBACK' || (r.reporterUid && r.reportedUid && r.reporterUid === r.reportedUid && !reason.includes('غرفة'));
  };

  const isRoomReport = (r: ReportModel) => {
    const reason = (r.reason || '');
    const desc = (r.description || r.details || '');
    return reason.includes('غرفة') || desc.includes('الغرفة:');
  };

  const filteredReports = reports.filter(r => {
    const feedback = isFeedbackReport(r);
    const room = isRoomReport(r);
    if (filterType === 'feedback') return feedback;
    if (filterType === 'rooms') return room;
    if (filterType === 'users') return !feedback && !room;
    return true;
  });

  return (
    <div className="space-y-6" dir="rtl">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h2 className="text-white text-lg font-bold flex items-center gap-2">
            <ShieldAlert className="w-5 h-5 text-rose-500" />
            البلاغات والشكاوى والاقتراحات (Reports & Feedback)
          </h2>
          <p className="text-slate-400 text-xs mt-0.5">
            متابعة شكاوى المستخدمين، مقترحات التطوير، وبلاغات المخالفين على الغرف والأعضاء مع اتخاذ الإجراءات الفورية.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={loadReports}
            className="flex items-center gap-1.5 bg-[#141417] hover:bg-white/10 text-slate-300 text-xs px-3 py-2 rounded-lg border border-white/10 transition"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin' : ''}`} />
            تحديث
          </button>
        </div>
      </div>

      {/* Tabs Filter */}
      <div className="flex bg-[#141417] border border-white/10 rounded-xl p-1 text-xs gap-1 overflow-x-auto">
        <button
          onClick={() => setFilterType('all')}
          className={`px-4 py-2 rounded-lg font-bold transition flex items-center gap-1.5 shrink-0 ${
            filterType === 'all' ? 'bg-amber-500 text-black shadow-md' : 'text-slate-400 hover:text-white'
          }`}
        >
          <AlertTriangle className="w-3.5 h-3.5" />
          الكل ({reports.length})
        </button>
        <button
          onClick={() => setFilterType('feedback')}
          className={`px-4 py-2 rounded-lg font-bold transition flex items-center gap-1.5 shrink-0 ${
            filterType === 'feedback' ? 'bg-amber-500 text-black shadow-md' : 'text-slate-400 hover:text-white'
          }`}
        >
          <MessageSquare className="w-3.5 h-3.5" />
          الشكاوى والاقتراحات ({reports.filter(isFeedbackReport).length})
        </button>
        <button
          onClick={() => setFilterType('users')}
          className={`px-4 py-2 rounded-lg font-bold transition flex items-center gap-1.5 shrink-0 ${
            filterType === 'users' ? 'bg-amber-500 text-black shadow-md' : 'text-slate-400 hover:text-white'
          }`}
        >
          <User className="w-3.5 h-3.5" />
          بلاغات الأعضاء ({reports.filter(r => !isFeedbackReport(r) && !isRoomReport(r)).length})
        </button>
        <button
          onClick={() => setFilterType('rooms')}
          className={`px-4 py-2 rounded-lg font-bold transition flex items-center gap-1.5 shrink-0 ${
            filterType === 'rooms' ? 'bg-amber-500 text-black shadow-md' : 'text-slate-400 hover:text-white'
          }`}
        >
          <Home className="w-3.5 h-3.5" />
          بلاغات الغرف ({reports.filter(isRoomReport).length})
        </button>
      </div>

      {loading ? (
        <div className="text-slate-400 text-sm text-center py-16 flex flex-col items-center gap-3">
          <RefreshCw className="w-6 h-6 animate-spin text-amber-500" />
          <span>جاري تحميل البلاغات والشكاوى...</span>
        </div>
      ) : filteredReports.length === 0 ? (
        <div className="text-slate-500 text-sm text-center py-16 bg-[#141417] rounded-2xl border border-white/5">
          <CheckCircle className="w-8 h-8 text-slate-600 mx-auto mb-2" />
          لا توجد بلاغات أو شكاوى حالياً في هذا القسم.
        </div>
      ) : (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {filteredReports.map(r => {
            const screenshotUrl = extractScreenshot(r);
            const isFeedback = isFeedbackReport(r);
            const isRoom = isRoomReport(r);
            const detailsText = (r.description || r.details || 'لا توجد تفاصيل إضافية.').replace(/صورة الإثبات:\s*https?:\/\/[^\s]+/i, '').trim();

            return (
              <div key={r.id} className="bg-[#141417] rounded-2xl border border-white/10 p-5 flex flex-col gap-3 shadow-lg hover:border-white/20 transition">
                <div className="flex justify-between items-start gap-2">
                  <div>
                    <div className="flex items-center gap-2">
                      <span className={`text-[10px] px-2.5 py-0.5 rounded-full font-bold ${
                        r.status === 'pending' ? 'bg-amber-500/20 text-amber-400 border border-amber-500/30' :
                        r.status === 'banned' ? 'bg-red-500/20 text-red-400 border border-red-500/30' :
                        r.status === 'resolved' ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30' :
                        'bg-slate-700/50 text-slate-300'
                      }`}>
                        {r.status === 'pending' ? 'قيد المراجعة' :
                         r.status === 'banned' ? 'تم الحظر' :
                         r.status === 'resolved' ? 'تمت المعالجة' : 'مرفوض'}
                      </span>
                      <span className="text-[10px] px-2 py-0.5 rounded-md bg-white/5 text-slate-400">
                        {isFeedback ? 'شكوى/اقتراح' : isRoom ? 'إبلاغ غرفة' : 'إبلاغ عضو'}
                      </span>
                    </div>

                    <div className="mt-2 text-white font-bold text-sm leading-snug">
                      {r.reason}
                    </div>

                    <div className="text-[11px] text-slate-500 mt-1 flex items-center gap-1 font-mono">
                      <Clock className="w-3 h-3 text-slate-400" />
                      {new Date(r.createdAt || r.created_at || Date.now()).toLocaleString('ar')}
                    </div>
                  </div>

                  <button
                    onClick={() => handleDelete(r.id)}
                    title="حذف البلاغ نهائياً"
                    className="p-1.5 rounded-lg text-slate-500 hover:text-rose-400 hover:bg-rose-500/10 transition"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>

                <div className="text-xs text-slate-300 bg-black/40 p-3 rounded-xl border border-white/5 space-y-1">
                  <span className="text-slate-400 font-bold block text-[11px]">نص وتفاصيل الشكوى/البلاغ:</span>
                  <p className="whitespace-pre-wrap leading-relaxed text-slate-200">
                    {detailsText || 'لا توجد تفاصيل.'}
                  </p>
                </div>

                {screenshotUrl && (
                  <div className="space-y-1">
                    <span className="text-slate-400 font-bold block text-[11px] flex items-center justify-between">
                      <span>صورة الإثبات المرفقة:</span>
                      <a href={screenshotUrl} target="_blank" rel="noreferrer" className="text-amber-400 hover:underline flex items-center gap-1 text-[10px]">
                        فتح بحجم كامل <ExternalLink className="w-3 h-3" />
                      </a>
                    </span>
                    <a href={screenshotUrl} target="_blank" rel="noreferrer" className="block overflow-hidden rounded-xl border border-white/10 group">
                      <img
                        src={screenshotUrl}
                        alt="Screenshot"
                        className="w-full h-36 object-cover rounded-xl group-hover:scale-105 transition duration-300"
                        onError={(e) => {
                          (e.target as HTMLElement).style.display = 'none';
                        }}
                      />
                    </a>
                  </div>
                )}

                <div className="bg-[#1a1a1e] rounded-xl p-3 text-[11px] space-y-1.5 border border-white/5">
                  <div className="flex justify-between items-center border-b border-white/5 pb-1">
                    <span className="text-slate-400">المُرسِل (Reporter UID):</span>
                    <span className="text-amber-300 font-mono select-all text-[10px]">{r.reporterUid}</span>
                  </div>
                  {!isFeedback && (
                    <div className="flex justify-between items-center">
                      <span className="text-slate-400">المُبلَغ عنه (Reported UID):</span>
                      <span className="text-rose-300 font-mono select-all text-[10px]">{r.reportedName || r.reportedUid}</span>
                    </div>
                  )}
                </div>

                {r.status === 'pending' && (
                  <div className="flex gap-2 mt-auto pt-2">
                    <button
                      onClick={() => handleResolve(r.id)}
                      className="flex-1 bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-bold py-2 px-2 rounded-xl flex justify-center items-center gap-1.5 transition shadow-md shadow-emerald-600/20"
                    >
                      <CheckCircle className="w-3.5 h-3.5" /> تمت المعالجة
                    </button>

                    {!isFeedback && !isRoom && (
                      <button
                        onClick={() => handleBan(r)}
                        className="flex-1 bg-red-600 hover:bg-red-700 text-white text-xs font-bold py-2 px-2 rounded-xl flex justify-center items-center gap-1.5 transition shadow-md shadow-red-600/20"
                      >
                        <Ban className="w-3.5 h-3.5" /> حظر المستخدم
                      </button>
                    )}

                    <button
                      onClick={() => handleDismiss(r)}
                      className="bg-slate-700 hover:bg-slate-600 text-white text-xs font-bold py-2 px-3 rounded-xl flex justify-center items-center gap-1.5 transition"
                    >
                      تجاهل
                    </button>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
