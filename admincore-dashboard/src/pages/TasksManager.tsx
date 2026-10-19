import React, { useState, useEffect } from 'react';
import {
  CheckSquare,
  Sparkles,
  Plus,
  Trash2,
  Edit,
  Save,
  X,
  Gift,
  Coins,
  Star,
  Image as ImageIcon,
  Flame,
  ArrowRight,
  TrendingUp,
} from 'lucide-react';
import { firestoreDb } from '../lib/firebase';
import { collection, getDocs, doc, setDoc, deleteDoc } from 'firebase/firestore';
import ImageUpload from '../components/ImageUpload';
import { uploadGiftIcon } from '../lib/storage';

interface TaskAdminItem {
  id: string;
  title_ar: string;
  title_en: string;
  description_ar: string;
  description_en: string;
  group: 'daily' | 'growth' | 'lucky';
  target_count: number;
  coins_reward: number;
  exp_reward: number;
  store_item_id?: string;
  store_item_name?: string;
  store_item_icon?: string;
  action_route: string;
}

interface StoreItemOption {
  id: string;
  name: string;
  icon: string;
  type: string;
}

export default function TasksManager() {
  const [activeTab, setActiveTab] = useState<'daily' | 'growth' | 'lucky' | 'banner'>('daily');
  const [tasks, setTasks] = useState<TaskAdminItem[]>([]);
  const [storeItems, setStoreItems] = useState<StoreItemOption[]>([]);
  const [loading, setLoading] = useState(true);
  const [editingTask, setEditingTask] = useState<TaskAdminItem | null>(null);
  const [showAddModal, setShowAddModal] = useState(false);
  const [bannerUrl, setBannerUrl] = useState('');
  const [saveSuccess, setSaveSuccess] = useState(false);

  // نموذج المهمة
  const [form, setForm] = useState<TaskAdminItem>({
    id: '',
    title_ar: '',
    title_en: '',
    description_ar: '',
    description_en: '',
    group: 'daily',
    target_count: 1,
    coins_reward: 200,
    exp_reward: 20,
    store_item_id: '',
    store_item_name: '',
    store_item_icon: '',
    action_route: 'room',
  });

  const loadData = async () => {
    setLoading(true);
    try {
      // 1. جلب قائمة المهام
      const tasksSnap = await getDocs(collection(firestoreDb, 'tasks_config'));
      const tasksList: TaskAdminItem[] = [];
      tasksSnap.forEach(d => {
        tasksList.push({ id: d.id, ...d.data() } as TaskAdminItem);
      });
      setTasks(tasksList);

      // 2. جلب عناصر المتجر لاختيار المكافآت
      const storeSnap = await getDocs(collection(firestoreDb, 'store_items'));
      const itemsList: StoreItemOption[] = [];
      storeSnap.forEach(d => {
        const data = d.data();
        itemsList.push({
          id: d.id,
          name: data.name || data.name_ar || d.id,
          icon: data.icon_url || data.iconAsset || '',
          type: data.type || 'item',
        });
      });
      setStoreItems(itemsList);

      // 3. جلب بانر الفعالية
      const bannerSnap = await getDocs(collection(firestoreDb, 'settings'));
      bannerSnap.forEach(d => {
        if (d.id === 'tasks_event_config') {
          setBannerUrl(d.data().banner_url || '');
        }
      });
    } catch (e) {
      console.error(e);
    }
    setLoading(false);
  };

  useEffect(() => {
    loadData();
  }, []);

  const handleSaveBanner = async () => {
    try {
      await setDoc(doc(firestoreDb, 'settings', 'tasks_event_config'), {
        banner_url: bannerUrl,
        updated_at: new Date().toISOString(),
      });
      setSaveSuccess(true);
      setTimeout(() => setSaveSuccess(false), 3000);
    } catch (e) {
      alert('فشل حفظ البانر');
    }
  };

  const handleSaveTask = async () => {
    if (!form.id || !form.title_ar) {
      alert('يرجى كتابة معرّف المهمة والعنوان بالعربي');
      return;
    }

    try {
      const taskDocRef = doc(firestoreDb, 'tasks_config', form.id);
      await setDoc(taskDocRef, form, { merge: true });
      setShowAddModal(false);
      setEditingTask(null);
      loadData();
    } catch (e) {
      alert('فشل حفظ المهمة');
    }
  };

  const handleDeleteTask = async (id: string) => {
    if (confirm('هل أنت متأكد من حذف هذه المهمة؟')) {
      try {
        await deleteDoc(doc(firestoreDb, 'tasks_config', id));
        loadData();
      } catch (e) {
        alert('فشل الحذف');
      }
    }
  };

  const openEdit = (task: TaskAdminItem) => {
    setEditingTask(task);
    setForm(task);
    setShowAddModal(true);
  };

  const openNew = () => {
    setEditingTask(null);
    setForm({
      id: `task_${Date.now()}`,
      title_ar: '',
      title_en: '',
      description_ar: '',
      description_en: '',
      group: activeTab === 'banner' ? 'daily' : activeTab,
      target_count: 1,
      coins_reward: 500,
      exp_reward: 50,
      store_item_id: '',
      store_item_name: '',
      store_item_icon: '',
      action_route: 'room',
    });
    setShowAddModal(true);
  };

  const filteredTasks = tasks.filter(t => t.group === activeTab);

  return (
    <div className="space-y-6">
      {/* الهيدر */}
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-xl font-bold text-white flex items-center gap-2">
            <CheckSquare className="w-6 h-6 text-amber-400" />
            مركز المهام اليومية والمكافآت (Tasks & Reward Center)
          </h1>
          <p className="text-slate-400 text-xs mt-1">
            إدارة مهام النشاط اليومي، مهام النمو، فعاليات الحظ، وربط المكافآت بالمتجر والكوينز والـ EXP.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={openNew}
            className="px-3.5 py-2 bg-amber-500 hover:bg-amber-600 text-black font-bold text-xs rounded-xl flex items-center gap-1.5 shadow-lg shadow-amber-500/20 transition"
          >
            <Plus className="w-4 h-4" />
            إضافة مهمة جديدة
          </button>
        </div>
      </div>

      {/* تبويبات الإدارة */}
      <div className="flex items-center gap-2 border-b border-white/5 pb-3">
        <button
          onClick={() => setActiveTab('daily')}
          className={`flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-bold transition ${
            activeTab === 'daily'
              ? 'bg-amber-500/20 text-amber-400 border border-amber-500/30'
              : 'text-slate-400 hover:text-white hover:bg-white/5'
          }`}
        >
          <Sparkles className="w-4 h-4" />
          🌟 مهام النشاط اليومي ({tasks.filter(t => t.group === 'daily').length})
        </button>

        <button
          onClick={() => setActiveTab('growth')}
          className={`flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-bold transition ${
            activeTab === 'growth'
              ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'
              : 'text-slate-400 hover:text-white hover:bg-white/5'
          }`}
        >
          <TrendingUp className="w-4 h-4" />
          🌱 مهام النمو والمستوى ({tasks.filter(t => t.group === 'growth').length})
        </button>

        <button
          onClick={() => setActiveTab('lucky')}
          className={`flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-bold transition ${
            activeTab === 'lucky'
              ? 'bg-purple-500/20 text-purple-400 border border-purple-500/30'
              : 'text-slate-400 hover:text-white hover:bg-white/5'
          }`}
        >
          <Flame className="w-4 h-4" />
          🍀 فعاليات الحظ ({tasks.filter(t => t.group === 'lucky').length})
        </button>

        <button
          onClick={() => setActiveTab('banner')}
          className={`flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-bold transition ${
            activeTab === 'banner'
              ? 'bg-sky-500/20 text-sky-400 border border-sky-500/30'
              : 'text-slate-400 hover:text-white hover:bg-white/5'
          }`}
        >
          <ImageIcon className="w-4 h-4" />
          🖼️ بانر هيدر الفعالية
        </button>
      </div>

      {/* قسم رافع البانر */}
      {activeTab === 'banner' && (
        <div className="bg-[#121214] border border-white/5 rounded-2xl p-6 space-y-4 max-w-2xl">
          <h3 className="text-sm font-bold text-white flex items-center gap-2">
            <ImageIcon className="w-4 h-4 text-sky-400" />
            بانر حدث مركز المهام (Header Event Banner)
          </h3>
          <p className="text-xs text-slate-400">
            صورة البانر التي تظهر أعلى واجهة مركز المهام في التطبيق. يمكنك رفعها مباشرة من جهازك.
          </p>

          <ImageUpload
            currentUrl={bannerUrl}
            onUpload={async file => uploadGiftIcon(file, `task_banner_${Date.now()}`)}
            onUrlChange={url => setBannerUrl(url)}
            label="رفع صورة البانر من الجهاز"
          />

          <button
            onClick={handleSaveBanner}
            className="px-5 py-2.5 bg-sky-600 hover:bg-sky-700 text-white font-bold text-xs rounded-xl flex items-center gap-2 transition"
          >
            <Save className="w-4 h-4" />
            حفظ وتطبيق البانر في التطبيق
          </button>
          {saveSuccess && <span className="text-emerald-400 text-xs font-bold block">✓ تم حفظ البانر بنجاح!</span>}
        </div>
      )}

      {/* جدول المهام */}
      {activeTab !== 'banner' && (
        <div className="bg-[#121214] border border-white/5 rounded-2xl overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-right text-xs">
              <thead className="bg-white/[0.02] text-slate-400 border-b border-white/5">
                <tr>
                  <th className="p-3.5 font-bold">المهمة (عربي / English)</th>
                  <th className="p-3.5 font-bold">الهدف المطلوب</th>
                  <th className="p-3.5 font-bold text-amber-400">🪙 العملات</th>
                  <th className="p-3.5 font-bold text-sky-400">⭐ نقاط EXP</th>
                  <th className="p-3.5 font-bold text-rose-400">🎁 مكافأة المتجر</th>
                  <th className="p-3.5 font-bold">التوجيه (Route)</th>
                  <th className="p-3.5 font-bold text-center">الإجراءات</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-white/5 text-slate-300">
                {filteredTasks.map(t => (
                  <tr key={t.id} className="hover:bg-white/[0.01] transition">
                    <td className="p-3.5">
                      <div className="font-bold text-white">{t.title_ar}</div>
                      <div className="text-[10px] text-slate-500">{t.title_en}</div>
                    </td>
                    <td className="p-3.5 font-bold text-slate-200">
                      {t.target_count} مرة
                    </td>
                    <td className="p-3.5 font-bold text-amber-400">
                      +{t.coins_reward}
                    </td>
                    <td className="p-3.5 font-bold text-sky-400">
                      +{t.exp_reward}
                    </td>
                    <td className="p-3.5">
                      {t.store_item_name ? (
                        <span className="px-2 py-0.5 rounded bg-rose-500/20 text-rose-300 text-[10px] font-bold border border-rose-500/30">
                          🎁 {t.store_item_name}
                        </span>
                      ) : (
                        <span className="text-slate-600">-</span>
                      )}
                    </td>
                    <td className="p-3.5">
                      <span className="px-2 py-0.5 rounded bg-white/5 text-slate-300 text-[10px] border border-white/10">
                        {t.action_route}
                      </span>
                    </td>
                    <td className="p-3.5 text-center">
                      <div className="flex items-center justify-center gap-1.5">
                        <button
                          onClick={() => openEdit(t)}
                          className="p-1.5 text-amber-400 hover:text-amber-300 hover:bg-amber-500/10 rounded-lg transition"
                          title="تعديل"
                        >
                          <Edit className="w-3.5 h-3.5" />
                        </button>
                        <button
                          onClick={() => handleDeleteTask(t.id)}
                          className="p-1.5 text-rose-400 hover:text-rose-300 hover:bg-rose-500/10 rounded-lg transition"
                          title="حذف"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
                {filteredTasks.length === 0 && (
                  <tr>
                    <td colSpan={7} className="p-8 text-center text-slate-500">
                      لا توجد مهام في هذا القسم. اضغط "إضافة مهمة جديدة" للبدء.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* نافذة إضافة / تعديل المهمة */}
      {showAddModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm p-4">
          <div className="bg-[#141417] border border-white/10 rounded-2xl w-full max-w-lg p-6 space-y-4 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between border-b border-white/5 pb-3">
              <h3 className="text-sm font-bold text-white flex items-center gap-2">
                <CheckSquare className="w-4 h-4 text-amber-400" />
                {editingTask ? 'تعديل المهمة' : 'إضافة مهمة جديدة'}
              </h3>
              <button onClick={() => setShowAddModal(false)} className="text-slate-400 hover:text-white">
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="space-y-3 text-xs">
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-slate-300 font-bold block mb-1">معرّف المهمة (Unique ID)</label>
                  <input
                    type="text"
                    disabled={!!editingTask}
                    value={form.id}
                    onChange={e => setForm({ ...form, id: e.target.value })}
                    className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-white outline-none focus:border-amber-500"
                    placeholder="e.g. daily_mic_10m"
                  />
                </div>

                <div>
                  <label className="text-slate-300 font-bold block mb-1">المجموعة (Group)</label>
                  <select
                    value={form.group}
                    onChange={e => setForm({ ...form, group: e.target.value as any })}
                    className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-white outline-none focus:border-amber-500"
                  >
                    <option value="daily">🌟 نشاط يومي (Daily)</option>
                    <option value="growth">🌱 نمو ومستوى (Growth)</option>
                    <option value="lucky">🍀 فعاليات الحظ (Lucky)</option>
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-slate-300 font-bold block mb-1">عنوان المهمة (بالعربي)</label>
                  <input
                    type="text"
                    value={form.title_ar}
                    onChange={e => setForm({ ...form, title_ar: e.target.value })}
                    className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-white outline-none focus:border-amber-500"
                    placeholder="مثال: التحدث على المايك 10 دقائق"
                  />
                </div>

                <div>
                  <label className="text-slate-300 font-bold block mb-1">العنوان (English)</label>
                  <input
                    type="text"
                    value={form.title_en}
                    onChange={e => setForm({ ...form, title_en: e.target.value })}
                    className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-white outline-none focus:border-amber-500"
                    placeholder="e.g. Speak on mic 10m"
                  />
                </div>
              </div>

              <div>
                <label className="text-slate-300 font-bold block mb-1">الوصف (بالعربي)</label>
                <input
                  type="text"
                  value={form.description_ar}
                  onChange={e => setForm({ ...form, description_ar: e.target.value })}
                  className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-white outline-none focus:border-amber-500"
                  placeholder="وصف مختصر للشرط المطلوب"
                />
              </div>

              <div className="grid grid-cols-3 gap-3 pt-2">
                <div>
                  <label className="text-slate-300 font-bold block mb-1">الهدف المطلوب (Count)</label>
                  <input
                    type="number"
                    min={1}
                    value={form.target_count}
                    onChange={e => setForm({ ...form, target_count: parseInt(e.target.value) || 1 })}
                    className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-white outline-none font-bold text-center"
                  />
                </div>

                <div>
                  <label className="text-amber-400 font-bold block mb-1">🪙 مكافأة الكوينز</label>
                  <input
                    type="number"
                    min={0}
                    value={form.coins_reward}
                    onChange={e => setForm({ ...form, coins_reward: parseInt(e.target.value) || 0 })}
                    className="w-full bg-black/40 border border-amber-500/30 rounded-xl px-3 py-2 text-amber-400 outline-none font-bold text-center"
                  />
                </div>

                <div>
                  <label className="text-sky-400 font-bold block mb-1">⭐ نقاط EXP</label>
                  <input
                    type="number"
                    min={0}
                    value={form.exp_reward}
                    onChange={e => setForm({ ...form, exp_reward: parseInt(e.target.value) || 0 })}
                    className="w-full bg-black/40 border border-sky-500/30 rounded-xl px-3 py-2 text-sky-400 outline-none font-bold text-center"
                  />
                </div>
              </div>

              <div className="pt-2">
                <label className="text-rose-400 font-bold block mb-1">🎁 مكافأة عنصر من المتجر (اختياري)</label>
                <select
                  value={form.store_item_id || ''}
                  onChange={e => {
                    const selected = storeItems.find(i => i.id === e.target.value);
                    setForm({
                      ...form,
                      store_item_id: selected?.id || '',
                      store_item_name: selected?.name || '',
                      store_item_icon: selected?.icon || '',
                    });
                  }}
                  className="w-full bg-black/40 border border-rose-500/30 rounded-xl px-3 py-2 text-white outline-none"
                >
                  <option value="">-- بدون عنصر متجر (عملات ونقاط فقط) --</option>
                  {storeItems.map(item => (
                    <option key={item.id} value={item.id}>
                      [{item.type}] {item.name}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="text-slate-300 font-bold block mb-1">التوجيه عند الضغط على "اذهب" (Action Route)</label>
                <select
                  value={form.action_route}
                  onChange={e => setForm({ ...form, action_route: e.target.value })}
                  className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-white outline-none"
                >
                  <option value="room">🎙️ فتح الرومات الصوتية</option>
                  <option value="gift">🎁 إرسال هدية في الروم</option>
                  <option value="lucky_gift">🍀 إرسال هدية حظ</option>
                  <option value="recharge">💳 صفحة شحن العملات</option>
                  <option value="store">🛍️ فتح المتجر</option>
                  <option value="profile">👤 تعديل الملف الشخصي</option>
                  <option value="none">بدون توجيه</option>
                </select>
              </div>
            </div>

            <div className="flex items-center justify-end gap-2 pt-3 border-t border-white/5">
              <button
                onClick={() => setShowAddModal(false)}
                className="px-4 py-2 bg-white/5 hover:bg-white/10 text-slate-300 rounded-xl font-bold text-xs"
              >
                إلغاء
              </button>
              <button
                onClick={handleSaveTask}
                className="px-5 py-2 bg-amber-500 hover:bg-amber-600 text-black font-bold text-xs rounded-xl flex items-center gap-1.5 shadow-lg shadow-amber-500/20"
              >
                <Save className="w-4 h-4" />
                حفظ المهمة
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
