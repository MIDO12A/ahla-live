import { useState, useEffect } from 'react';
import { Bell, Send, Image as ImageIcon, Link as LinkIcon, Trash2, Globe, Eye, RefreshCw, CheckCircle2, AlertCircle } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { uploadStoreItem } from '../lib/storage';
import ImageUpload from '../components/ImageUpload';

interface SentNotification {
  id: string;
  title: string;
  body: string;
  target?: string;
  image_url?: string;
  link_url?: string;
  data?: any;
  sent_at?: string;
  created_at?: string;
}

export default function NotificationsPage() {
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [linkUrl, setLinkUrl] = useState('');
  const [targetUsers, setTargetUsers] = useState<'all' | 'specific' | 'level'>('all');
  const [specificUserId, setSpecificUserId] = useState('');
  const [targetLevel, setTargetLevel] = useState('1');
  const [sending, setSending] = useState(false);
  const [sentList, setSentList] = useState<SentNotification[]>([]);
  const [loadingList, setLoadingList] = useState(false);
  const [successMsg, setSuccessMsg] = useState('');
  const [errorMsg, setErrorMsg] = useState('');

  const fetchSentNotifications = async () => {
    setLoadingList(true);
    try {
      const { data, error } = await supabase
        .from('notifications')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(20);

      if (!error && data) {
        setSentList(data as SentNotification[]);
      }
    } catch (e) {
      console.error('Error fetching notifications:', e);
    } finally {
      setLoadingList(false);
    }
  };

  useEffect(() => {
    fetchSentNotifications();
  }, []);

  const handleSend = async () => {
    if (!title.trim() || !body.trim()) {
      setErrorMsg('يرجى كتابة عنوان الإشعار ونص الرسالة');
      return;
    }

    setSending(true);
    setErrorMsg('');
    setSuccessMsg('');

    try {
      const cleanImg = imageUrl.trim();
      const cleanLink = linkUrl.trim();

      const notificationData = {
        title: title.trim(),
        body: body.trim(),
        target: targetUsers === 'specific' ? specificUserId.trim() : (targetUsers === 'level' ? `level_${targetLevel}` : 'all'),
        image_url: cleanImg || null,
        link_url: cleanLink || null,
        data: {
          image_url: cleanImg || null,
          img: cleanImg || null,
          link_url: cleanLink || null,
          url: cleanLink || null,
          action_url: cleanLink || null,
          action: cleanLink ? 'open_url' : 'view',
          target_type: targetUsers,
          level: targetUsers === 'level' ? targetLevel : undefined,
        },
        sent_at: new Date().toISOString(),
        created_at: new Date().toISOString(),
      };

      const { error } = await supabase.from('notifications').insert(notificationData);

      if (error) {
        // Fallback: If image_url / link_url columns don't exist yet, insert without them and rely on data JSON
        if (error.message.includes('column') || error.code === '42703') {
          const { error: fallbackErr } = await supabase.from('notifications').insert({
            title: title.trim(),
            body: body.trim(),
            target: notificationData.target,
            data: notificationData.data,
            sent_at: notificationData.sent_at,
          });
          if (fallbackErr) throw fallbackErr;
        } else {
          throw error;
        }
      }

      setSuccessMsg('تم إرسال الإشعار لجميع المستخدمين بنجاح ✓');
      setTitle('');
      setBody('');
      setImageUrl('');
      setLinkUrl('');
      fetchSentNotifications();
    } catch (e: any) {
      setErrorMsg('فشل الإرسال: ' + (e.message || e));
    } finally {
      setSending(false);
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm('هل أنت متأكد من حذف هذا الإشعار من السجل؟')) return;
    try {
      await supabase.from('notifications').delete().eq('id', id);
      setSentList(prev => prev.filter(item => item.id !== id));
    } catch (e: any) {
      alert('فشل الحذف: ' + e.message);
    }
  };

  return (
    <div className="space-y-6 max-w-5xl mx-auto pb-12">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-white text-xl font-bold flex items-center gap-2">
            <Bell className="w-5 h-5 text-amber-400" /> إرسال إشعارات النظام والمستخدمين (Push Notifications)
          </h2>
          <p className="text-slate-400 text-xs mt-1">
            إرسال إشعارات لحظية مدعومة بالصور وروابط التوجيه لمتصفح التطبيق المدمج (In-App Web Viewer).
          </p>
        </div>
      </div>

      {/* Messages */}
      {successMsg && (
        <div className="bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 px-4 py-3 rounded-xl text-xs flex items-center gap-2">
          <CheckCircle2 className="w-4 h-4 shrink-0" /> {successMsg}
        </div>
      )}
      {errorMsg && (
        <div className="bg-red-500/10 border border-red-500/20 text-red-400 px-4 py-3 rounded-xl text-xs flex items-center gap-2">
          <AlertCircle className="w-4 h-4 shrink-0" /> {errorMsg}
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Form Controls */}
        <div className="lg:col-span-7 bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-5">
          {/* Target Audience */}
          <div>
            <label className="block text-[11px] uppercase text-slate-300 font-bold mb-2">
              الجمهور المستهدف (Target Audience)
            </label>
            <div className="flex flex-wrap gap-2">
              {(['all', 'specific', 'level'] as const).map(t => (
                <button
                  key={t}
                  type="button"
                  onClick={() => setTargetUsers(t)}
                  className={`px-3.5 py-2 text-xs font-semibold rounded-xl transition-all cursor-pointer ${
                    targetUsers === t
                      ? 'bg-amber-500 text-black shadow-lg shadow-amber-500/20'
                      : 'bg-[#1a1a1e] text-slate-400 border border-white/5 hover:border-white/10'
                  }`}
                >
                  {t === 'all' ? '📢 جميع المستخدمين (All Users)' : t === 'specific' ? '👤 مستخدم محدد (Specific UID)' : '⭐ حسب المستوى (By Level)'}
                </button>
              ))}
            </div>

            {targetUsers === 'specific' && (
              <div className="mt-3">
                <input
                  type="text"
                  value={specificUserId}
                  onChange={e => setSpecificUserId(e.target.value)}
                  className="w-full bg-[#18181b] border border-white/10 rounded-xl py-2 px-3 text-xs text-white placeholder-slate-500 focus:border-amber-400 outline-none"
                  placeholder="أدخل معرّف المستخدم (UID)..."
                />
              </div>
            )}

            {targetUsers === 'level' && (
              <div className="mt-3 flex items-center gap-2">
                <span className="text-xs text-slate-400">الحد الأدنى لمستوى المستخدم:</span>
                <input
                  type="number"
                  min="1"
                  max="100"
                  value={targetLevel}
                  onChange={e => setTargetLevel(e.target.value)}
                  className="w-24 bg-[#18181b] border border-white/10 rounded-xl py-2 px-3 text-xs text-white text-center focus:border-amber-400 outline-none"
                />
              </div>
            )}
          </div>

          {/* Title */}
          <div>
            <label className="block text-[11px] uppercase text-slate-300 font-bold mb-1.5">
              عنوان الإشعار (Notification Title) *
            </label>
            <input
              type="text"
              value={title}
              onChange={e => setTitle(e.target.value)}
              className="w-full bg-[#18181b] border border-white/10 rounded-xl py-2.5 px-3.5 text-xs text-white placeholder-slate-500 focus:border-amber-400 outline-none"
              placeholder="اكتب عنواناً جذاباً للإشعار..."
            />
          </div>

          {/* Body */}
          <div>
            <label className="block text-[11px] uppercase text-slate-300 font-bold mb-1.5">
              نص الإشعار (Notification Body) *
            </label>
            <textarea
              value={body}
              onChange={e => setBody(e.target.value)}
              rows={3}
              className="w-full bg-[#18181b] border border-white/10 rounded-xl py-2.5 px-3.5 text-xs text-white placeholder-slate-500 focus:border-amber-400 outline-none resize-none leading-relaxed"
              placeholder="اكتب تفاصيل الإشعار أو العرض أو المناسبة..."
            />
          </div>

          {/* Image Attachment (Upload or URL) */}
          <div className="bg-[#18181b] p-4 rounded-xl border border-white/5 space-y-3">
            <label className="text-[11px] uppercase text-amber-400 font-bold flex items-center gap-1.5">
              <ImageIcon className="w-3.5 h-3.5" /> صورة الإشعار (Attached Image)
            </label>
            <div className="space-y-3">
              <ImageUpload
                currentUrl={imageUrl}
                onUpload={async file => {
                  const url = await uploadStoreItem(file, 'notification_images');
                  setImageUrl(url);
                  return url;
                }}
                onUrlChange={url => setImageUrl(url)}
                onClear={() => setImageUrl('')}
                label="رفع صورة للإشعار (JPG, PNG, WebP)"
                accept="image/*"
              />
              <div className="flex items-center gap-2">
                <span className="text-[10px] text-slate-500 shrink-0">أو رابط مباشر:</span>
                <input
                  type="text"
                  value={imageUrl}
                  onChange={e => setImageUrl(e.target.value)}
                  className="w-full bg-[#121214] border border-white/10 rounded-lg py-1.5 px-2.5 text-xs text-white placeholder-slate-600 focus:border-amber-400 outline-none"
                  placeholder="https://.../banner.png"
                />
              </div>
            </div>
          </div>

          {/* Action Link / Web Viewer URL */}
          <div className="bg-[#18181b] p-4 rounded-xl border border-white/5 space-y-2">
            <label className="text-[11px] uppercase text-indigo-400 font-bold flex items-center gap-1.5">
              <LinkIcon className="w-3.5 h-3.5" /> رابط التوجيه / الويب فيور (Target Link / Web Viewer)
            </label>
            <div className="space-y-1.5">
              <input
                type="text"
                value={linkUrl}
                onChange={e => setLinkUrl(e.target.value)}
                className="w-full bg-[#121214] border border-white/10 rounded-lg py-2 px-3 text-xs text-white placeholder-slate-600 focus:border-indigo-400 outline-none"
                placeholder="https://example.com/event-page أو رابط خارجي..."
              />
              <p className="text-[11px] text-slate-400 leading-normal">
                💡 <span className="text-amber-400 font-semibold">ملاحظة هامة:</span> عند ضغط المستخدم على الإشعار أو الصورة، سيتم توجيهه مباشرة إلى متصفح التطبيق المدمج (<span className="text-white font-mono text-[10px]">In-App Web Viewer</span>) لتصفح الصفحة بسلاسة دون مغادرة التطبيق.
              </p>
            </div>
          </div>

          {/* Submit Button */}
          <button
            onClick={handleSend}
            disabled={sending}
            className="w-full py-3 bg-gradient-to-r from-amber-500 to-amber-600 hover:from-amber-400 hover:to-amber-500 disabled:opacity-50 text-black font-bold text-xs rounded-xl flex items-center justify-center gap-2 shadow-lg shadow-amber-500/20 cursor-pointer transition-all"
          >
            {sending ? (
              <>
                <RefreshCw className="w-4 h-4 animate-spin" /> جاري إرسال الإشعار...
              </>
            ) : (
              <>
                <Send className="w-4 h-4" /> إرسال الإشعار لجميع المستخدمين الآن
              </>
            )}
          </button>
        </div>

        {/* Live Mobile Preview */}
        <div className="lg:col-span-5 space-y-4">
          <div className="bg-[#141417] rounded-2xl border border-white/5 p-5">
            <h3 className="text-white text-xs font-bold uppercase tracking-wider mb-3 flex items-center gap-1.5">
              <Eye className="w-3.5 h-3.5 text-amber-400" /> معاينة الإشعار على هاتف المستخدم (Live Preview)
            </h3>

            {/* Mobile Simulation Frame */}
            <div className="bg-[#1E1528] rounded-2xl p-4 border border-white/10 shadow-2xl space-y-3">
              <div className="flex items-center gap-2 border-b border-white/5 pb-2">
                <div className="w-8 h-8 rounded-full bg-gradient-to-tr from-amber-400 to-orange-500 flex items-center justify-center text-black font-bold text-xs">
                  🔔
                </div>
                <div>
                  <div className="text-white text-xs font-bold">إشعارات النظام</div>
                  <div className="text-slate-400 text-[10px]">الآن • أحلى لايف</div>
                </div>
              </div>

              {/* Notification Bubble */}
              <div className="bg-white rounded-xl p-3 shadow-md space-y-2">
                {title ? (
                  <div className="text-slate-900 font-bold text-xs">{title}</div>
                ) : (
                  <div className="text-slate-400 italic text-xs">عنوان الإشعار يظهر هنا...</div>
                )}

                <div className="h-[0.5px] bg-slate-200" />

                {body ? (
                  <div className="text-slate-700 text-[11px] leading-relaxed whitespace-pre-line">{body}</div>
                ) : (
                  <div className="text-slate-400 italic text-[11px]">نص وتفاصيل الإشعار تظهر هنا للمستخدمين...</div>
                )}

                {/* Attached Image Preview */}
                {imageUrl && (
                  <div className="relative rounded-lg overflow-hidden border border-slate-200 max-h-40 bg-slate-100">
                    <img src={imageUrl} alt="preview" className="w-full h-full object-cover" />
                    {linkUrl && (
                      <div className="absolute bottom-1.5 right-1.5 bg-black/70 text-amber-300 text-[9px] px-2 py-0.5 rounded-full font-bold flex items-center gap-1">
                        👆 اضغط لفتح الرابط
                      </div>
                    )}
                  </div>
                )}

                {/* Action Link Button Preview */}
                {linkUrl && (
                  <div className="pt-1">
                    <div className="w-full bg-gradient-to-r from-[#2C1947] to-[#1B112B] text-amber-300 border border-amber-400/50 rounded-lg py-2 px-3 text-[10px] font-bold flex items-center justify-center gap-1.5 shadow-sm">
                      <Globe className="w-3 h-3" /> فتح الرابط في متصفح التطبيق (In-App Viewer)
                    </div>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Sent Notifications History */}
      <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-4">
        <div className="flex items-center justify-between">
          <h3 className="text-white text-sm font-bold flex items-center gap-2">
            سجل آخر الإشعارات المرسلة (Sent Notifications Log)
          </h3>
          <button
            onClick={fetchSentNotifications}
            disabled={loadingList}
            className="text-xs text-amber-400 hover:text-amber-300 flex items-center gap-1 cursor-pointer"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${loadingList ? 'animate-spin' : ''}`} /> تحديث السجل
          </button>
        </div>

        {sentList.length === 0 ? (
          <div className="text-center py-8 text-slate-500 text-xs">
            لا توجد إشعارات سابقة مسجلة.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-right text-xs">
              <thead>
                <tr className="border-b border-white/5 text-slate-400">
                  <th className="py-2.5 px-3">التاريخ</th>
                  <th className="py-2.5 px-3">الجمهور</th>
                  <th className="py-2.5 px-3">العنوان والنص</th>
                  <th className="py-2.5 px-3">الصورة</th>
                  <th className="py-2.5 px-3">الرابط المرفق</th>
                  <th className="py-2.5 px-3 text-center">إجراءات</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-white/5">
                {sentList.map(item => {
                  const img = item.image_url || item.data?.image_url || item.data?.img;
                  const link = item.link_url || item.data?.link_url || item.data?.url || item.data?.action_url;
                  return (
                    <tr key={item.id} className="hover:bg-white/[0.02] text-slate-300">
                      <td className="py-3 px-3 text-[11px] text-slate-400 font-mono">
                        {item.created_at || item.sent_at ? new Date(item.created_at || item.sent_at!).toLocaleDateString('ar-EG', { hour: '2-digit', minute: '2-digit' }) : '—'}
                      </td>
                      <td className="py-3 px-3">
                        <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${item.target === 'all' ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20' : 'bg-indigo-500/10 text-indigo-400 border border-indigo-500/20'}`}>
                          {item.target === 'all' ? 'جميع المستخدمين' : item.target}
                        </span>
                      </td>
                      <td className="py-3 px-3 max-w-xs">
                        <div className="font-bold text-white text-xs">{item.title}</div>
                        <div className="text-slate-400 text-[11px] truncate mt-0.5">{item.body}</div>
                      </td>
                      <td className="py-3 px-3">
                        {img ? (
                          <a href={img} target="_blank" rel="noreferrer">
                            <img src={img} alt="thumbnail" className="w-12 h-8 rounded object-cover border border-white/10 hover:opacity-80 transition-opacity" />
                          </a>
                        ) : (
                          <span className="text-slate-600 text-[11px]">بدون صورة</span>
                        )}
                      </td>
                      <td className="py-3 px-3 max-w-[180px]">
                        {link ? (
                          <a
                            href={link}
                            target="_blank"
                            rel="noreferrer"
                            className="text-amber-400 hover:underline flex items-center gap-1 text-[11px] truncate"
                          >
                            <Globe className="w-3 h-3 shrink-0" />
                            <span className="truncate">{link}</span>
                          </a>
                        ) : (
                          <span className="text-slate-600 text-[11px]">بدون رابط</span>
                        )}
                      </td>
                      <td className="py-3 px-3 text-center">
                        <button
                          onClick={() => handleDelete(item.id)}
                          className="p-1.5 hover:bg-red-500/20 text-red-400 rounded-lg transition-colors cursor-pointer"
                          title="حذف الإشعار"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
