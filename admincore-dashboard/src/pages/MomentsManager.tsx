import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { Camera, Trash2, Ban, MessageCircle, Heart, Gift, Eye, RefreshCw, Save, Image as ImageIcon, Video, Search, ExternalLink } from 'lucide-react';

interface Moment {
  id: string;
  user_id: string;
  user_name: string;
  user_avatar: string;
  user_custom_id: string;
  content: string;
  media_url?: string;
  media_type: 'none' | 'image' | 'video';
  thumbnail_url?: string;
  likes_count: number;
  comments_count: number;
  gifts_count: number;
  gifts_total_value: number;
  views_count: number;
  created_at: string;
  is_deleted: boolean;
}

interface MomentComment {
  id: string;
  moment_id: string;
  user_id: string;
  user_name: string;
  user_avatar: string;
  user_custom_id: string;
  content: string;
  created_at: string;
}

export default function MomentsManager() {
  const [activeTab, setActiveTab] = useState<'moments' | 'config'>('moments');
  const [moments, setMoments] = useState<Moment[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');

  // Comments Modal State
  const [selectedMomentForComments, setSelectedMomentForComments] = useState<Moment | null>(null);
  const [comments, setComments] = useState<MomentComment[]>([]);
  const [commentsLoading, setCommentsLoading] = useState(false);

  // Customization Form State
  const [tabTitle, setTabTitle] = useState('اللحظات');
  const [tabIconNor, setTabIconNor] = useState('');
  const [tabIconPre, setTabIconPre] = useState('');
  const [savingConfig, setSavingConfig] = useState(false);

  const loadMoments = async () => {
    try {
      setLoading(true);
      const { data, error } = await supabase
        .from('moments')
        .select('*')
        .eq('is_deleted', false)
        .order('created_at', { ascending: false })
        .limit(100);

      if (error) throw error;
      setMoments((data as Moment[]) || []);
    } catch (e: any) {
      console.error('Error fetching moments:', e.message);
    } finally {
      setLoading(false);
    }
  };

  const loadTabConfig = async () => {
    try {
      const { data } = await supabase
        .from('app_config')
        .select('value')
        .eq('key', 'moments_tab_config')
        .maybeSingle();

      if (data && data.value) {
        setTabTitle(data.value.title || 'اللحظات');
        setTabIconNor(data.value.iconNor || '');
        setTabIconPre(data.value.iconPre || '');
      }
    } catch (e) {
      console.error('Error fetching config:', e);
    }
  };

  useEffect(() => {
    loadMoments();
    loadTabConfig();
  }, []);

  const handleDeleteMoment = async (id: string) => {
    if (!confirm('هل أنت متأكد من حذف هذا المنشور نهائياً من اللحظات؟')) return;
    try {
      const { error } = await supabase
        .from('moments')
        .update({ is_deleted: true })
        .eq('id', id);

      if (error) throw error;
      setMoments(prev => prev.filter(m => m.id !== id));
      alert('تم حذف المنشور بنجاح ✅');
    } catch (e: any) {
      alert('تعذر حذف المنشور: ' + e.message);
    }
  };

  const handleBanUser = async (userId: string, userName: string) => {
    if (!confirm(`هل أنت متأكد من حظر المستخدم (${userName}) نهائياً من التطبيق؟`)) return;
    try {
      const { error } = await supabase
        .from('users')
        .update({
          banned: true,
          ban_reason: 'نشر محتوى أو تعليق غير لائق في شاشة اللحظات',
          is_blocked: true,
        })
        .or(`id.eq.${userId},uid.eq.${userId}`);

      if (error) throw error;
      alert(`تم حظر المستخدم (${userName}) بنجاح 🚫`);
      loadMoments();
    } catch (e: any) {
      alert('تعذر حظر المستخدم: ' + e.message);
    }
  };

  const handleOpenComments = async (moment: Moment) => {
    setSelectedMomentForComments(moment);
    setCommentsLoading(true);
    try {
      const { data, error } = await supabase
        .from('moment_comments')
        .select('*')
        .eq('moment_id', moment.id)
        .eq('is_deleted', false)
        .order('created_at', { ascending: true });

      if (error) throw error;
      setComments((data as MomentComment[]) || []);
    } catch (e: any) {
      console.error(e);
    } finally {
      setCommentsLoading(false);
    }
  };

  const handleDeleteComment = async (commentId: string) => {
    if (!confirm('حذف هذا التعليق؟')) return;
    try {
      const { error } = await supabase
        .from('moment_comments')
        .update({ is_deleted: true })
        .eq('id', commentId);

      if (error) throw error;
      setComments(prev => prev.filter(c => c.id !== commentId));
      if (selectedMomentForComments) {
        setMoments(prev =>
          prev.map(m =>
            m.id === selectedMomentForComments.id
              ? { ...m, comments_count: Math.max(0, m.comments_count - 1) }
              : m
          )
        );
      }
    } catch (e: any) {
      alert('فشل حذف التعليق: ' + e.message);
    }
  };

  const handleSaveConfig = async (e: React.FormEvent) => {
    e.preventDefault();
    setSavingConfig(true);
    try {
      const { error } = await supabase
        .from('app_config')
        .upsert({
          key: 'moments_tab_config',
          value: {
            title: tabTitle.trim() || 'اللحظات',
            iconNor: tabIconNor.trim(),
            iconPre: tabIconPre.trim(),
          },
        });

      if (error) throw error;
      alert('تم حفظ إعدادات أيقونة واسم الشاشة بنجاح! ستظهر في التطبيق فوراً ✨');
    } catch (e: any) {
      alert('تعذر الحفظ: ' + e.message);
    } finally {
      setSavingConfig(false);
    }
  };

  const filteredMoments = moments.filter(m => {
    if (!search.trim()) return true;
    const q = search.toLowerCase();
    return (
      (m.user_name || '').toLowerCase().includes(q) ||
      (m.user_custom_id || '').toLowerCase().includes(q) ||
      (m.content || '').toLowerCase().includes(q)
    );
  });

  return (
    <div className="space-y-6" dir="rtl">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h2 className="text-white text-lg font-semibold flex items-center gap-2">
            <Camera className="w-5 h-5 text-pink-500" />
            إدارة شاشة اللحظات (Moments Feed)
          </h2>
          <p className="text-slate-500 text-xs mt-0.5">
            الرقابة على المنشورات، حذف الفيديوهات والصور غير اللائقة، حظر المخالفين، وتخصيص أيقونة واسم التاب.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <div className="flex bg-[#141417] border border-white/10 rounded-lg p-1 text-xs">
            <button
              onClick={() => setActiveTab('moments')}
              className={`px-3 py-1.5 rounded-md font-bold transition-colors ${
                activeTab === 'moments' ? 'bg-pink-600 text-white shadow-md' : 'text-slate-400 hover:text-white'
              }`}
            >
              المنشورات ({moments.length})
            </button>
            <button
              onClick={() => setActiveTab('config')}
              className={`px-3 py-1.5 rounded-md font-bold transition-colors ${
                activeTab === 'config' ? 'bg-pink-600 text-white shadow-md' : 'text-slate-400 hover:text-white'
              }`}
            >
              تخصيص الأيقونة والاسم
            </button>
          </div>

          <button
            onClick={loadMoments}
            className="p-2 rounded-lg bg-[#141417] border border-white/10 text-slate-300 hover:text-white hover:bg-white/5 transition-colors"
            title="تحديث البيانات"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin text-pink-500' : ''}`} />
          </button>
        </div>
      </div>

      {activeTab === 'moments' && (
        <div className="space-y-4">
          {/* Search Bar */}
          <div className="relative max-w-md">
            <Search className="w-4 h-4 text-slate-400 absolute right-3 top-1/2 -translate-y-1/2" />
            <input
              type="text"
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="بحث باسم المستخدم، الآيدي، أو نص المنشور..."
              className="w-full bg-[#141417] border border-white/10 rounded-lg pr-9 pl-3 py-2 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-pink-500/50"
            />
          </div>

          {loading ? (
            <div className="text-slate-500 text-sm text-center py-16">جاري جلب المنشورات...</div>
          ) : filteredMoments.length === 0 ? (
            <div className="text-slate-500 text-sm text-center py-16 bg-[#141417] rounded-xl border border-white/5">
              لا توجد منشورات مطابقة حالياً.
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {filteredMoments.map(m => (
                <div
                  key={m.id}
                  className="bg-[#141417] rounded-xl border border-white/10 p-4 flex flex-col justify-between hover:border-pink-500/30 transition-all shadow-lg"
                >
                  <div className="space-y-3">
                    {/* User Header */}
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2.5">
                        <img
                          src={m.user_avatar || 'https://via.placeholder.com/40'}
                          alt={m.user_name}
                          className="w-10 h-10 rounded-full object-cover border border-amber-500/40"
                          onError={e => {
                            (e.target as HTMLElement).setAttribute('src', 'https://via.placeholder.com/40');
                          }}
                        />
                        <div>
                          <div className="text-white text-xs font-bold truncate max-w-[150px]">{m.user_name}</div>
                          <div className="text-amber-400 text-[11px] font-mono">ID: {m.user_custom_id}</div>
                        </div>
                      </div>

                      <div className="flex items-center gap-1">
                        <button
                          onClick={() => handleBanUser(m.user_id, m.user_name)}
                          className="p-1.5 rounded-lg bg-red-500/10 text-red-400 hover:bg-red-500 hover:text-white transition-colors"
                          title="حظر المستخدم نهائياً"
                        >
                          <Ban className="w-3.5 h-3.5" />
                        </button>
                        <button
                          onClick={() => handleDeleteMoment(m.id)}
                          className="p-1.5 rounded-lg bg-rose-500/10 text-rose-400 hover:bg-rose-500 hover:text-white transition-colors"
                          title="حذف المنشور"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    </div>

                    {/* Content Text */}
                    {m.content && (
                      <p className="text-slate-200 text-xs leading-relaxed break-words line-clamp-3 bg-black/20 p-2.5 rounded-lg border border-white/5">
                        {m.content}
                      </p>
                    )}

                    {/* Media Preview */}
                    {m.media_type === 'image' && m.media_url && (
                      <div className="relative rounded-lg overflow-hidden border border-white/10 bg-black/40 h-44 flex items-center justify-center">
                        <img
                          src={m.media_url}
                          alt="Moment media"
                          className="w-full h-full object-cover cursor-pointer hover:scale-105 transition-transform"
                          onClick={() => window.open(m.media_url, '_blank')}
                        />
                        <span className="absolute bottom-2 left-2 px-2 py-0.5 rounded bg-black/60 text-[10px] text-white flex items-center gap-1">
                          <ImageIcon className="w-3 h-3 text-pink-400" /> صورة
                        </span>
                      </div>
                    )}

                    {m.media_type === 'video' && m.media_url && (
                      <div className="relative rounded-lg overflow-hidden border border-white/10 bg-black/60 h-44 flex items-center justify-center">
                        <video
                          src={m.media_url}
                          controls
                          className="w-full h-full object-contain"
                        />
                        <span className="absolute top-2 left-2 px-2 py-0.5 rounded bg-black/60 text-[10px] text-white flex items-center gap-1 pointer-events-none">
                          <Video className="w-3 h-3 text-cyan-400" /> فيديو
                        </span>
                      </div>
                    )}
                  </div>

                  {/* Footer Stats & Actions */}
                  <div className="mt-4 pt-3 border-t border-white/5 flex items-center justify-between text-[11px] text-slate-400">
                    <div className="flex items-center gap-3">
                      <span className="flex items-center gap-1 text-red-400" title="الإعجابات">
                        <Heart className="w-3.5 h-3.5 fill-red-400/20" /> {m.likes_count}
                      </span>
                      <button
                        onClick={() => handleOpenComments(m)}
                        className="flex items-center gap-1 text-blue-400 hover:underline"
                        title="عرض التعليقات"
                      >
                        <MessageCircle className="w-3.5 h-3.5" /> {m.comments_count}
                      </button>
                      <span className="flex items-center gap-1 text-amber-400" title="الهدايا">
                        <Gift className="w-3.5 h-3.5" /> {m.gifts_count}
                      </span>
                      <span className="flex items-center gap-1 text-slate-400" title="المشاهدات">
                        <Eye className="w-3.5 h-3.5" /> {m.views_count}
                      </span>
                    </div>

                    <span className="text-[10px] text-slate-500">
                      {new Date(m.created_at).toLocaleDateString('ar-EG', {
                        month: 'short',
                        day: 'numeric',
                        hour: '2-digit',
                        minute: '2-digit',
                      })}
                    </span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Config Customization Tab */}
      {activeTab === 'config' && (
        <div className="max-w-xl bg-[#141417] rounded-xl border border-white/10 p-6 space-y-6">
          <div>
            <h3 className="text-white text-sm font-bold flex items-center gap-2">
              <Camera className="w-4 h-4 text-pink-500" />
              تخصيص أيقونة واسم زر اللحظات في شريط التنقل السفلي (Bottom Bar)
            </h3>
            <p className="text-slate-400 text-xs mt-1">
              يتم حفظ هذا التخصيص في السيرفر ويتحدث تلقائياً وفورياً لجميع المستخدمين داخل التطبيق.
            </p>
          </div>

          <form onSubmit={handleSaveConfig} className="space-y-4 text-xs">
            <div>
              <label className="block text-slate-300 font-semibold mb-1">اسم الشاشة في الشريط السفلي:</label>
              <input
                type="text"
                value={tabTitle}
                onChange={e => setTabTitle(e.target.value)}
                placeholder="مثال: اللحظات"
                className="w-full bg-[#1c1c22] border border-white/10 rounded-lg px-3 py-2 text-white focus:outline-none focus:border-pink-500/50"
              />
            </div>

            <div>
              <label className="block text-slate-300 font-semibold mb-1">
                رابط أيقونة الحالة العادية (Normal Icon URL):
              </label>
              <input
                type="url"
                value={tabIconNor}
                onChange={e => setTabIconNor(e.target.value)}
                placeholder="https://.../moments_nor.png"
                className="w-full bg-[#1c1c22] border border-white/10 rounded-lg px-3 py-2 text-white font-mono focus:outline-none focus:border-pink-500/50"
              />
              <span className="text-[10px] text-slate-500 mt-0.5 block">اتركه فارغاً لاستخدام الأيقونة الافتراضية للتطبيق</span>
            </div>

            <div>
              <label className="block text-slate-300 font-semibold mb-1">
                رابط أيقونة الحالة النشطة (Selected/Active Icon URL):
              </label>
              <input
                type="url"
                value={tabIconPre}
                onChange={e => setTabIconPre(e.target.value)}
                placeholder="https://.../moments_pre.png"
                className="w-full bg-[#1c1c22] border border-white/10 rounded-lg px-3 py-2 text-white font-mono focus:outline-none focus:border-pink-500/50"
              />
              <span className="text-[10px] text-slate-500 mt-0.5 block">اتركه فارغاً لاستخدام الأيقونة الافتراضية للتطبيق</span>
            </div>

            {/* Live Preview */}
            <div className="bg-black/30 p-4 rounded-xl border border-white/5 flex items-center justify-around">
              <div className="text-center">
                <span className="text-[10px] text-slate-400 block mb-2">معاينة العادية</span>
                {tabIconNor ? (
                  <img src={tabIconNor} alt="Normal" className="w-8 h-8 object-contain mx-auto" />
                ) : (
                  <div className="w-8 h-8 rounded-full bg-white/10 flex items-center justify-center mx-auto text-slate-400">
                    <Camera className="w-4 h-4" />
                  </div>
                )}
                <span className="text-[10px] text-slate-400 mt-1 block">{tabTitle || 'اللحظات'}</span>
              </div>

              <div className="text-center">
                <span className="text-[10px] text-pink-400 block mb-2">معاينة النشطة (المحددة)</span>
                {tabIconPre ? (
                  <img src={tabIconPre} alt="Selected" className="w-8 h-8 object-contain mx-auto" />
                ) : (
                  <div className="w-8 h-8 rounded-full bg-pink-500/20 flex items-center justify-center mx-auto text-pink-400">
                    <Camera className="w-4 h-4" />
                  </div>
                )}
                <span className="text-[10px] text-pink-400 font-bold mt-1 block">{tabTitle || 'اللحظات'}</span>
              </div>
            </div>

            <button
              type="submit"
              disabled={savingConfig}
              className="w-full py-2.5 rounded-lg bg-pink-600 hover:bg-pink-500 text-white font-bold transition-colors flex items-center justify-center gap-2 shadow-lg shadow-pink-600/30 disabled:opacity-50"
            >
              <Save className="w-4 h-4" />
              {savingConfig ? 'جاري الحفظ...' : 'حفظ الإعدادات'}
            </button>
          </form>
        </div>
      )}

      {/* Comments Moderation Modal */}
      {selectedMomentForComments && (
        <div className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-[#141417] border border-white/10 rounded-2xl w-full max-w-lg p-5 space-y-4 max-h-[85vh] flex flex-col">
            <div className="flex items-center justify-between pb-3 border-b border-white/10">
              <h3 className="text-white text-sm font-bold flex items-center gap-2">
                <MessageCircle className="w-4 h-4 text-pink-400" />
                تعليقات المنشور ({comments.length})
              </h3>
              <button
                onClick={() => setSelectedMomentForComments(null)}
                className="text-slate-400 hover:text-white text-sm px-2 py-1 rounded"
              >
                إغلاق
              </button>
            </div>

            <div className="flex-1 overflow-y-auto space-y-3 pr-1">
              {commentsLoading ? (
                <div className="text-slate-500 text-xs text-center py-8">جاري تحميل التعليقات...</div>
              ) : comments.length === 0 ? (
                <div className="text-slate-500 text-xs text-center py-8">لا توجد أي تعليقات على هذا المنشور.</div>
              ) : (
                comments.map(c => (
                  <div key={c.id} className="bg-black/30 p-3 rounded-lg border border-white/5 flex items-start justify-between gap-3">
                    <div className="flex items-start gap-2.5">
                      <img
                        src={c.user_avatar || 'https://via.placeholder.com/32'}
                        alt={c.user_name}
                        className="w-7 h-7 rounded-full object-cover border border-white/10"
                      />
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="text-white text-xs font-bold">{c.user_name}</span>
                          <span className="text-amber-400 text-[10px] font-mono">ID: {c.user_custom_id}</span>
                        </div>
                        <p className="text-slate-200 text-xs mt-1 leading-relaxed">{c.content}</p>
                        <span className="text-[10px] text-slate-500 mt-1 block">
                          {new Date(c.created_at).toLocaleDateString('ar-EG', {
                            hour: '2-digit',
                            minute: '2-digit',
                          })}
                        </span>
                      </div>
                    </div>

                    <div className="flex items-center gap-1 flex-shrink-0">
                      <button
                        onClick={() => handleBanUser(c.user_id, c.user_name)}
                        className="p-1 rounded bg-red-500/10 text-red-400 hover:bg-red-500 hover:text-white transition-colors"
                        title="حظر كاتب التعليق"
                      >
                        <Ban className="w-3 h-3" />
                      </button>
                      <button
                        onClick={() => handleDeleteComment(c.id)}
                        className="p-1 rounded bg-rose-500/10 text-rose-400 hover:bg-rose-500 hover:text-white transition-colors"
                        title="حذف التعليق"
                      >
                        <Trash2 className="w-3 h-3" />
                      </button>
                    </div>
                  </div>
                ))
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
