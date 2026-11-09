import { useEffect, useState, useContext } from 'react';
import { I18nContext } from '../lib/i18n';
import { getSigninRewards, upsertSigninReward, updateSigninReward, deleteSigninReward, getAppConfig, updateAppConfig, getStoreItems, getVIPConfig } from '../lib/db';
import { uploadAppAsset } from '../lib/storage';
import type { SigninRewardModel } from '../types';
import DataTable from '../components/DataTable';
import ImageUpload from '../components/ImageUpload';
import { Plus, Save, X, Calendar, Trash2 } from 'lucide-react';

const rewardTypes = [
  { key: 'coins', labelAr: 'عملات (Coins)', labelEn: 'Coins' },
  { key: 'diamonds', labelAr: 'ألماس (Diamonds)', labelEn: 'Diamonds' },
  { key: 'item', labelAr: 'عنصر من المتجر', labelEn: 'Store Item' },
  { key: 'vip_item', labelAr: 'عنصر VIP', labelEn: 'VIP Item' },
  { key: 'vip_tier', labelAr: 'مستوى VIP', labelEn: 'VIP Tier' },
];

const emptyReward = { type: 'coins', amount: 100, item_id: '', days: 0 };

const defaultForm = {
  id: '',
  day_number: 1,
  label_ar: '',
  label_en: '',
  icon_url: '',
  svga_url: '',
  value: 100,
  value_type: 'coins',
  gift_id: '',
  is_double: false,
  is_active: true,
};

const valueTypes = [
  { key: 'coins', labelAr: 'عملات', labelEn: 'Coins' },
  { key: 'diamonds', labelAr: 'ماس', labelEn: 'Diamonds' },
  { key: 'xp', labelAr: 'نقاط خبرة', labelEn: 'XP' },
  { key: 'gift', labelAr: 'هدية (عنصر)', labelEn: 'Gift (Item)' },
  { key: 'custom', labelAr: 'مخصص', labelEn: 'Custom' },
];

export default function SigninFeaturesPage() {
  const { lang } = useContext(I18nContext);
  const isAr = lang === 'ar';

  const [rewards, setRewards] = useState<SigninRewardModel[]>([]);
  const [form, setForm] = useState({ ...defaultForm });
  const [editingId, setEditingId] = useState<string | null>(null);
  const [showAdd, setShowAdd] = useState(false);
  const [loading, setLoading] = useState(true);
  const [msg, setMsg] = useState('');

  // ── Daily reward popup + invite rewards config (app_config) ──
  const [dailyCfg, setDailyCfg] = useState<any>({ enabled: false, reward: { ...emptyReward }, title: '', description: '' });
  const [inviteCfg, setInviteCfg] = useState<any>({});
  const [storeItems, setStoreItems] = useState<any[]>([]);
  const [vipTiers, setVipTiers] = useState<any[]>([]);
  const [savingCfg, setSavingCfg] = useState(false);

  const showMsg = (m: string) => {
    setMsg(m);
    setTimeout(() => setMsg(''), 3000);
  };

  const load = () => {
    getSigninRewards().then(r => setRewards(r)).catch(e => console.warn('load signin rewards error:', e)).finally(() => setLoading(false));
  };

  useEffect(() => { load(); }, []);

  useEffect(() => {
    getAppConfig<any>('daily_reward_settings').then(v => {
      if (v) setDailyCfg({ enabled: false, title: '', description: '', ...v, reward: { ...emptyReward, ...(v.reward || {}) } });
    }).catch(() => {});
    getAppConfig<any>('invite_settings').then(v => { if (v) setInviteCfg(v); }).catch(() => {});
    getStoreItems().then(items => setStoreItems(items as any[])).catch(() => {});
    getVIPConfig().then(tiers => setVipTiers(tiers as any[])).catch(() => {});
  }, []);

  const updateReward = (cfg: any, side: 'daily' | 'inviter' | 'invitee', field: string, value: any) => {
    if (side === 'daily') {
      setDailyCfg((p: any) => ({ ...p, reward: { ...p.reward, [field]: value } }));
    } else {
      const key = side === 'inviter' ? 'inviter_reward' : 'invitee_reward';
      setInviteCfg((p: any) => ({ ...p, [key]: { ...(p[key] || emptyReward), [field]: value } }));
    }
  };

  const saveDailyCfg = async () => {
    setSavingCfg(true);
    await updateAppConfig('daily_reward_settings', dailyCfg);
    setSavingCfg(false);
    showMsg(isAr ? 'تم حفظ المكافأة اليومية' : 'Daily reward saved');
  };

  const saveInviteCfg = async () => {
    setSavingCfg(true);
    await updateAppConfig('invite_settings', inviteCfg);
    setSavingCfg(false);
    showMsg(isAr ? 'تم حفظ إعدادات الدعوة' : 'Invite settings saved');
  };

  const RewardEditor = ({ reward, onChange }: { reward: any; onChange: (field: string, value: any) => void }) => (
    <div className="grid grid-cols-2 md:grid-cols-4 gap-3 items-end">
      <div>
        <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'نوع المكافأة' : 'Type'}</label>
        <select value={reward?.type || 'coins'} onChange={e => onChange('type', e.target.value)}
          className="w-full bg-[#0f0f11] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
          {rewardTypes.map(t => <option key={t.key} value={t.key}>{isAr ? t.labelAr : t.labelEn}</option>)}
        </select>
      </div>
      {(reward?.type === 'coins' || reward?.type === 'diamonds' || reward?.type === 'vip_tier') && (
        <div>
          <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">
            {reward?.type === 'vip_tier' ? (isAr ? 'رقم المستوى (Tier)' : 'Tier #') : (isAr ? 'القيمة' : 'Amount')}
          </label>
          {reward?.type === 'vip_tier' ? (
            <select value={reward?.amount ?? ''} onChange={e => onChange('amount', Number(e.target.value))}
              className="w-full bg-[#0f0f11] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
              <option value="">—</option>
              {vipTiers.map((t: any) => <option key={t.tier} value={t.tier}>VIP {t.tier}</option>)}
            </select>
          ) : (
            <input type="number" min={0} value={reward?.amount ?? 0} onChange={e => onChange('amount', Number(e.target.value) || 0)}
              className="w-full bg-[#0f0f11] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
          )}
        </div>
      )}
      {(reward?.type === 'item' || reward?.type === 'vip_item') && (
        <div>
          <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'العنصر' : 'Item'}</label>
          <select value={reward?.item_id || ''} onChange={e => onChange('item_id', e.target.value)}
            className="w-full bg-[#0f0f11] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
            <option value="">—</option>
            {storeItems.map((it: any) => <option key={it.itemId || it.item_id || it.id} value={it.itemId || it.item_id || it.id}>{it.name} ({it.category})</option>)}
          </select>
        </div>
      )}
      {reward?.type === 'vip_tier' && (
        <div>
          <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'المدة بالأيام (0=دائم)' : 'Days (0=forever)'}</label>
          <input type="number" min={0} value={reward?.days ?? 0} onChange={e => onChange('days', Number(e.target.value) || 0)}
            className="w-full bg-[#0f0f11] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
        </div>
      )}
    </div>
  );

  const resetForm = () => { setForm({ ...defaultForm }); setEditingId(null); setShowAdd(false); };

  const updateForm = (field: string, value: any) => setForm(p => ({ ...p, [field]: value }));

  const handleEdit = (r: SigninRewardModel) => {
    setEditingId(r.id);
    setShowAdd(false);
    setForm({
      id: r.id,
      day_number: r.day_number,
      label_ar: r.label_ar || '',
      label_en: r.label_en || '',
      icon_url: r.icon_url || '',
      svga_url: r.svga_url || '',
      value: r.value ?? 0,
      value_type: r.value_type || 'coins',
      gift_id: r.gift_id || '',
      is_double: r.is_double,
      is_active: r.is_active,
    });
  };

  const handleSave = async () => {
    if (!editingId) return;
    if (!form.label_ar) { showMsg(isAr ? 'أدخل الاسم العربي' : 'Enter Arabic label'); return; }
    await updateSigninReward(editingId, { ...form, gift_id: form.gift_id || null } as any);
    resetForm();
    load();
    showMsg(isAr ? 'تم الحفظ' : 'Saved!');
  };

  const handleAdd = async () => {
    if (!form.label_ar) { showMsg(isAr ? 'أدخل الاسم العربي' : 'Enter Arabic label'); return; }
    const id = 'signin_day_' + form.day_number;
    await upsertSigninReward(id, { ...form, id, gift_id: form.gift_id || null } as any);
    resetForm();
    load();
    showMsg(isAr ? 'تمت الإضافة' : 'Added!');
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h2 className="text-white text-lg font-semibold">{isAr ? '📅 المكافآت اليومية' : '📅 Weekly Sign-In Rewards'}</h2>
      </div>

      {msg && <div className="bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs px-4 py-2 rounded-lg">{msg}</div>}

      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <p className="text-slate-500 text-xs">{rewards.length} {isAr ? 'مكافأة (7 أيام)' : 'rewards (7 days)'}</p>
          <button onClick={() => { resetForm(); setShowAdd(!showAdd); }}
            className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
            <Plus className="w-3.5 h-3.5" /> {showAdd ? (isAr ? 'إلغاء' : 'Cancel') : (isAr ? 'إضافة مكافأة' : 'Add Reward')}
          </button>
        </div>

        {(editingId || showAdd) && (
          <div className="bg-[#141417] rounded-2xl border border-indigo-500/20 p-6 space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-white font-semibold text-sm">
                {editingId ? (isAr ? 'تعديل مكافأة اليوم ' : 'Edit Day ') + form.day_number : (isAr ? 'مكافأة جديدة' : 'New Reward')}
              </h3>
              <button onClick={resetForm} className="text-slate-400 hover:text-white"><X className="w-4 h-4" /></button>
            </div>
            <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
              <div>
                <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'رقم اليوم (1-7)' : 'Day Number (1-7)'}</label>
                <input type="number" min={1} max={7} value={form.day_number}
                  onChange={e => updateForm('day_number', Math.min(7, Math.max(1, Number(e.target.value) || 1)))}
                  className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
              </div>
              <div>
                <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'الاسم (عربي)' : 'Label (Arabic)'}</label>
                <input value={form.label_ar} onChange={e => updateForm('label_ar', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
              </div>
              <div>
                <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'الاسم (إنجليزي)' : 'Label (English)'}</label>
                <input value={form.label_en} onChange={e => updateForm('label_en', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
              </div>
              <div>
                <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'القيمة' : 'Value'}</label>
                <input type="number" min={0} value={form.value} onChange={e => updateForm('value', Number(e.target.value) || 0)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
              </div>
              <div>
                <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'نوع المكافأة' : 'Reward Type'}</label>
                <select value={form.value_type} onChange={e => updateForm('value_type', e.target.value)}
                  className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
                  {valueTypes.map(t => <option key={t.key} value={t.key}>{isAr ? t.labelAr : t.labelEn}</option>)}
                </select>
              </div>
              {form.value_type === 'gift' && (
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Gift ID</label>
                  <input value={form.gift_id} onChange={e => updateForm('gift_id', e.target.value)} placeholder="item_id" className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                </div>
              )}
              <div>
                <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'مضاعف' : 'Double Reward'}</label>
                <label className="flex items-center gap-2 mt-1">
                  <input type="checkbox" checked={form.is_double} onChange={e => updateForm('is_double', e.target.checked)} className="w-4 h-4" />
                  <span className="text-xs text-slate-400">{isAr ? 'مضاعف (نجمة)' : 'Double (star)'}</span>
                </label>
              </div>
              <div>
                <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'نشط' : 'Active'}</label>
                <label className="flex items-center gap-2 mt-1">
                  <input type="checkbox" checked={form.is_active} onChange={e => updateForm('is_active', e.target.checked)} className="w-4 h-4" />
                  <span className="text-xs text-slate-400">{form.is_active ? (isAr ? 'مفعل' : 'Enabled') : (isAr ? 'معطل' : 'Disabled')}</span>
                </label>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <ImageUpload currentUrl={form.icon_url} onUpload={file => uploadAppAsset(file, `signin_icon_${Date.now()}`)} onUrlChange={url => updateForm('icon_url', url)} label={isAr ? 'أيقونة المكافأة (PNG/WebP)' : 'Reward Icon (PNG/WebP)'} accept="image/*,.webp,.png,.svg" />
              <ImageUpload currentUrl={form.svga_url} onUpload={file => uploadAppAsset(file, `signin_svga_${Date.now()}`)} onUrlChange={url => updateForm('svga_url', url)} label={isAr ? 'ملف الأنميشن (SVGA)' : 'Animation (SVGA)'} accept=".svga,.zip,.mp4,.vap" />
            </div>
            <button onClick={editingId ? handleSave : handleAdd} className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
              <Save className="w-3 h-3" /> {editingId ? (isAr ? 'حفظ' : 'Save') : (isAr ? 'إضافة' : 'Add')}
            </button>
          </div>
        )}

        <DataTable loading={loading} searchKeys={['label_ar', 'label_en']}
          columns={[
            { key: 'day_number', label: isAr ? 'اليوم' : 'Day', sortable: true },
            { key: 'icon_url', label: '', render: (r: SigninRewardModel) => r.icon_url ? <img src={r.icon_url} className="w-8 h-8 object-contain rounded" /> : <div className="w-8 h-8 rounded bg-slate-800 flex items-center justify-center text-lg">🎁</div> },
            { key: 'label_ar', label: isAr ? 'الاسم' : 'Name', sortable: true },
            { key: 'value', label: isAr ? 'القيمة' : 'Value', sortable: true, render: (r: SigninRewardModel) => <span>{r.value} {r.is_double && <span className="text-amber-400 ml-1">★</span>}</span> },
            { key: 'value_type', label: isAr ? 'النوع' : 'Type', render: (r: SigninRewardModel) => <span className="text-indigo-300">{valueTypes.find(t => t.key === r.value_type) ? (isAr ? valueTypes.find(t => t.key === r.value_type)!.labelAr : valueTypes.find(t => t.key === r.value_type)!.labelEn) : r.value_type}</span> },
            { key: 'is_active', label: isAr ? 'نشط' : 'Active', render: (r: SigninRewardModel) => <span className={r.is_active ? 'text-emerald-400' : 'text-rose-400'}>{r.is_active ? (isAr ? 'نعم' : 'Yes') : (isAr ? 'لا' : 'No')}</span> },
          ]}
          data={rewards} onEdit={handleEdit} onDelete={async (r) => { if (confirm(isAr ? `حذف مكافأة اليوم ${r.day_number}؟` : `Delete day ${r.day_number} reward?`)) { await deleteSigninReward(r.id); load(); } }} />
      </div>

      {/* ═══ المكافأة اليومية البسيطة (تظهر مرة واحدة يومياً عند فتح التطبيق) ═══ */}
      <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-4">
        <div className="flex items-center justify-between">
          <div>
            <h3 className="text-white text-sm font-semibold">{isAr ? '🎁 المكافأة اليومية (نافذة بداية التطبيق)' : '🎁 Daily Reward Popup'}</h3>
            <p className="text-[10px] text-slate-500 mt-0.5">
              {isAr ? 'تظهر مرة واحدة يومياً لكل مستخدم — لا يمكن استلامها مرتين في نفس اليوم' : 'Shows once per day per user — cannot be claimed twice'}
            </p>
          </div>
          <label className="flex items-center gap-2">
            <input type="checkbox" checked={!!dailyCfg.enabled} onChange={e => setDailyCfg((p: any) => ({ ...p, enabled: e.target.checked }))} className="w-4 h-4" />
            <span className="text-xs text-slate-300">{dailyCfg.enabled ? (isAr ? 'مفعّلة' : 'Enabled') : (isAr ? 'معطّلة' : 'Disabled')}</span>
          </label>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'العنوان' : 'Title'}</label>
            <input value={dailyCfg.title || ''} onChange={e => setDailyCfg((p: any) => ({ ...p, title: e.target.value }))} placeholder={isAr ? 'مكافأة اليوم' : 'Daily Reward'} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
          </div>
          <div>
            <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'الوصف' : 'Description'}</label>
            <input value={dailyCfg.description || ''} onChange={e => setDailyCfg((p: any) => ({ ...p, description: e.target.value }))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
          </div>
        </div>

        <RewardEditor reward={dailyCfg.reward} onChange={(f, v) => updateReward(dailyCfg, 'daily', f, v)} />

        {/* شكل نافذة المكافأة */}
        <div className="border-t border-white/5 pt-3 grid grid-cols-1 md:grid-cols-2 gap-3">
          <div>
            <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'صورة خلفية النافذة (رابط)' : 'Dialog BG Image URL'}</label>
            <input value={dailyCfg.bg_image || ''} onChange={e => setDailyCfg((p: any) => ({ ...p, bg_image: e.target.value }))} placeholder="https://... (فارغ = التدرج الافتراضي)" className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
          </div>
          <div>
            <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'أيقونة/صورة المكافأة (رابط)' : 'Reward Icon URL'}</label>
            <input value={dailyCfg.icon_url || ''} onChange={e => setDailyCfg((p: any) => ({ ...p, icon_url: e.target.value }))} placeholder="https://... (فارغ = أيقونة الهدية الافتراضية)" className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
          </div>
          <div>
            <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'لون البداية (hex)' : 'Gradient Start (hex)'}</label>
            <input value={dailyCfg.color1 || ''} onChange={e => setDailyCfg((p: any) => ({ ...p, color1: e.target.value }))} placeholder="#1DB954" className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" />
          </div>
          <div>
            <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'لون النهاية (hex)' : 'Gradient End (hex)'}</label>
            <input value={dailyCfg.color2 || ''} onChange={e => setDailyCfg((p: any) => ({ ...p, color2: e.target.value }))} placeholder="#0B3D2E" className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" />
          </div>
          <div>
            <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'لون الزر (hex)' : 'Button Color (hex)'}</label>
            <input value={dailyCfg.button_color || ''} onChange={e => setDailyCfg((p: any) => ({ ...p, button_color: e.target.value }))} placeholder="#FFD700" className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" />
          </div>
          <div>
            <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'نص زر الاستلام' : 'Claim Button Text'}</label>
            <input value={dailyCfg.claim_text || ''} onChange={e => setDailyCfg((p: any) => ({ ...p, claim_text: e.target.value }))} placeholder={isAr ? 'استلام' : 'Claim'} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
          </div>
        </div>

        <button onClick={saveDailyCfg} disabled={savingCfg} className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
          <Save className="w-3 h-3" /> {isAr ? 'حفظ المكافأة اليومية' : 'Save Daily Reward'}
        </button>
      </div>

      {/* ═══ مكافآت كود الدعوة (inviter + invitee) ═══ */}
      <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-4">
        <div>
          <h3 className="text-white text-sm font-semibold">{isAr ? '🤝 مكافآت كود الدعوة' : '🤝 Invite Code Rewards'}</h3>
          <p className="text-[10px] text-slate-500 mt-0.5">
            {isAr ? 'مكافأة المدعو تُصرف فور ربط الكود — مكافأة الداعي تُصرف عند ضغط "استلام المكافأة" عن كل صديق' : 'Invitee reward granted on bind — inviter reward claimed per friend'}
          </p>
        </div>

        <div className="space-y-3">
          <div>
            <label className="block text-[10px] uppercase text-amber-400 font-bold mb-1">{isAr ? 'مكافأة الداعي (عن كل مدعو)' : 'Inviter Reward (per invitee)'}</label>
            <RewardEditor reward={inviteCfg.inviter_reward} onChange={(f, v) => updateReward(inviteCfg, 'inviter', f, v)} />
          </div>
          <div>
            <label className="block text-[10px] uppercase text-emerald-400 font-bold mb-1">{isAr ? 'مكافأة المدعو (عند ربط الكود)' : 'Invitee Reward (on bind)'}</label>
            <RewardEditor reward={inviteCfg.invitee_reward} onChange={(f, v) => updateReward(inviteCfg, 'invitee', f, v)} />
          </div>
        </div>

        {/* شكل شاشة كود الدعوة */}
        <div className="border-t border-white/5 pt-4 space-y-3">
          <h4 className="text-white text-xs font-semibold">{isAr ? '🎨 شكل شاشة كود الدعوة' : '🎨 Invite Screen Theme'}</h4>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'عنوان الشاشة' : 'Screen Title'}</label>
              <input value={inviteCfg.screen?.title || ''} onChange={e => setInviteCfg((p: any) => ({ ...p, screen: { ...(p.screen || {}), title: e.target.value } }))} placeholder="كود الدعوة" className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'لون الخلفية الأساسي (hex)' : 'Primary Color (hex)'}</label>
              <input value={inviteCfg.screen?.primary_color || ''} onChange={e => setInviteCfg((p: any) => ({ ...p, screen: { ...(p.screen || {}), primary_color: e.target.value } }))} placeholder="#0B3D2E" className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'صورة الخلفية (رابط — فارغ = الافتراضي)' : 'BG Image URL (empty = default)'}</label>
              <input value={inviteCfg.screen?.bg_image || ''} onChange={e => setInviteCfg((p: any) => ({ ...p, screen: { ...(p.screen || {}), bg_image: e.target.value } }))} placeholder="https://..." className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
            </div>
          </div>
        </div>

        <button onClick={saveInviteCfg} disabled={savingCfg} className="px-4 py-1.5 bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
          <Save className="w-3 h-3" /> {isAr ? 'حفظ إعدادات الدعوة' : 'Save Invite Settings'}
        </button>
      </div>
    </div>
  );
}


