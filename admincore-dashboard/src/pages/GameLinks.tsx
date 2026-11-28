import { useEffect, useState } from 'react';
import { GameLink, GameProtocolSettings } from '../types';
import {
  getGameLinks, addGameLink, updateGameLink, deleteGameLink,
  getGameProtocolSettings, saveGameProtocolSettings,
} from '../lib/db';
import { uploadToCloudinary } from '../lib/storage';
import { Plus, Save, Trash2, Gamepad2, Link2, ShieldCheck, Pencil, X, Upload, RefreshCw, Eye, EyeOff } from 'lucide-react';

const EMPTY_GAME: GameLink = {
  id: '', gameKey: '', nameAr: '', nameEn: '', gameId: '',
  platform: 'alfanexso', host: 'alfanexso.tech',
  appKey: 'alfa_key_app_ahal_377', urlTemplate: '', imageUrl: '',
  viewMode: 'half', poolId: '', isHot: false, sortOrder: 0, isActive: true,
};

const PLACEHOLDERS = [
  '{STYEPARTY_USER_ID} → معرّف المستخدم (UUID)',
  '{PLAYER_ID} → معرّف اللاعب (playerId / customId)',
  '{CUSTOM_ID} → رقم الحساب (customId)',
  '{COINS} → رصيد الكوينز',
  '{NICKNAME} → اسم اللاعب',
  '{PLAYER_TOKEN} → توكن جلسة اللاعب',
  '{ROOM_ID} → معرّف الغرفة',
  '{GAME_ID} → معرّف اللعبة',
  '{VIEW_MODE} → وضع العرض (half / full)',
];

export default function GameLinksPage() {
  const [games, setGames] = useState<GameLink[]>([]);
  const [protocol, setProtocol] = useState<GameProtocolSettings | null>(null);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<GameLink | null>(null);
  const [showAdd, setShowAdd] = useState(false);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [protoForm, setProtoForm] = useState({ appKey: '', callbackBaseUrl: '', providerName: '', signRules: '' });
  const [protoSaved, setProtoSaved] = useState(false);

  const load = async () => {
    setLoading(true);
    const [g, p] = await Promise.all([getGameLinks(), getGameProtocolSettings()]);
    setGames(g);
    setProtocol(p);
    if (p) {
      setProtoForm({
        appKey: p.appKey ?? '',
        callbackBaseUrl: p.callbackBaseUrl ?? '',
        providerName: p.providerName ?? '',
        signRules: p.signRules ?? '',
      });
    }
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const startAdd = () => { setEditing({ ...EMPTY_GAME }); setShowAdd(true); };
  const startEdit = (g: GameLink) => { setEditing({ ...g }); setShowAdd(true); };

  const handleSave = async () => {
    if (!editing) return;
    setSaving(true);
    const id = editing.id || `gl_${Date.now()}`;
    const payload = { ...editing, id };
    await addGameLink(id, payload);
    setSaving(false);
    setEditing(null);
    setShowAdd(false);
    load();
  };

  const [syncing, setSyncing] = useState(false);

  const handleDelete = async (id: string) => {
    if (!confirm('حذف هذه اللعبة نهائياً؟')) return;
    await deleteGameLink(id);
    load();
  };

  const handleToggleActive = async (g: GameLink) => {
    const nextState = !g.isActive;
    await updateGameLink(g.id, { isActive: nextState });
    setGames(prev => prev.map(item => item.id === g.id ? { ...item, isActive: nextState } : item));
  };

  const handleSyncProviderGames = async () => {
    setSyncing(true);
    try {
      const appKey = protoForm.appKey || 'alfa_key_app_ahal_377';
      const res = await fetch(`https://alfanexso.tech/api/v1/games?app_key=${encodeURIComponent(appKey)}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      if (data && Array.isArray(data.games)) {
        let addedCount = 0;
        const existingKeys = new Set(games.map(g => g.gameKey));
        const existingGameIds = new Set(games.map(g => g.gameId));

        for (const g of data.games) {
          const gId = String(g.id || '').trim();
          if (!gId) continue;
          const key = gId.replace(/^fe-game-/, '').replace(/-/g, '_');
          if (existingKeys.has(key) || existingGameIds.has(gId)) continue;

          const newGame: GameLink = {
            id: `gl_${key}`,
            gameKey: key,
            nameAr: g.name_ar || key,
            nameEn: g.name_en || key,
            gameId: gId,
            platform: 'alfanexso',
            host: 'alfanexso.tech',
            appKey: appKey,
            urlTemplate: g.template_url || `https://alfanexso.tech/play/${appKey}/${gId}?gameId=${gId}&uid={STYEPARTY_USER_ID}&token={PLAYER_TOKEN}&roomId={ROOM_ID}&view_mode=${g.orientation === 'landscape' ? 'full' : 'half'}`,
            imageUrl: g.icon_url || '',
            viewMode: g.orientation === 'landscape' ? 'full' : 'half',
            poolId: key,
            isHot: false,
            sortOrder: (games.length + addedCount + 1),
            isActive: true,
          };
          await addGameLink(newGame.id, newGame);
          addedCount++;
        }
        alert(addedCount > 0 ? `تم استيراد ${addedCount} لعبة جديدة بنجاح!` : 'جميع ألعاب المزوّد متزامنة ومسجلة بالفعل.');
        await load();
      }
    } catch (e) {
      alert('فشل استيراد ألعاب المزوّد: ' + (e as Error).message);
    } finally {
      setSyncing(false);
    }
  };

  const handleImageUpload = async (file: File) => {
    if (!editing) return;
    setUploading(true);
    try {
      const url = await uploadToCloudinary(file, 'games');
      setEditing({ ...editing, imageUrl: url });
    } catch (e) {
      alert('فشل رفع الصورة: ' + (e as Error).message);
    } finally {
      setUploading(false);
    }
  };

  const handleSaveProtocol = async () => {
    setSaving(true);
    const ok = await saveGameProtocolSettings(protoForm);
    setSaving(false);
    if (ok) {
      setProtoSaved(true);
      setTimeout(() => setProtoSaved(false), 2000);
      load();
    }
  };

  const upd = (patch: Partial<GameLink>) => editing && setEditing({ ...editing, ...patch });

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold text-white flex items-center gap-2">
            <Gamepad2 className="w-6 h-6 text-indigo-400" /> ربط الألعاب / الطرف الثالث
          </h1>
          <p className="text-xs text-slate-400 mt-1">
            إدارة ألعاب WebView: رابط التشغيل + صورة + بروتوكول StyeParty Callback — تظهر داخل مركز الألعاب في التطبيق
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={handleSyncProviderGames}
            disabled={syncing}
            className="px-3.5 py-2 bg-emerald-600/90 hover:bg-emerald-600 disabled:opacity-50 text-white text-xs font-semibold rounded-lg flex items-center gap-1.5 transition-colors"
            title="جلب أي ألعاب جديدة من سيرفر alfanexso وإضافتها تلقائياً"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${syncing ? 'animate-spin' : ''}`} />
            {syncing ? 'جارٍ المزامنة...' : 'مزامنة ألعاب المزوّد'}
          </button>
          <button onClick={startAdd} className="px-4 py-2 bg-indigo-600 hover:bg-indigo-700 text-white text-sm font-semibold rounded-lg flex items-center gap-2">
            <Plus className="w-4 h-4" /> إضافة لعبة
          </button>
        </div>
      </div>

      {/* ── بروتوكول Callback ── */}
      <div className="bg-[#141417] rounded-2xl border border-white/5 p-5">
        <h2 className="text-sm font-bold text-white flex items-center gap-2 mb-4">
          <ShieldCheck className="w-4 h-4 text-emerald-400" /> بروتوكول StyeParty Callback API
        </h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3 mb-4">
          <div>
            <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">APP_KEY</label>
            <input value={protoForm.appKey} onChange={e => setProtoForm({ ...protoForm, appKey: e.target.value })}
              className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white font-mono" dir="ltr" />
          </div>
          <div>
            <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Callback Base URL</label>
            <input value={protoForm.callbackBaseUrl} onChange={e => setProtoForm({ ...protoForm, callbackBaseUrl: e.target.value })}
              className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white font-mono" dir="ltr" />
          </div>
          <div>
            <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">اسم المزوّد</label>
            <input value={protoForm.providerName} onChange={e => setProtoForm({ ...protoForm, providerName: e.target.value })}
              className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white" />
          </div>
          <div className="flex items-end">
            <button onClick={handleSaveProtocol} disabled={saving}
              className="px-4 py-2 bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 text-white text-xs font-semibold rounded-lg flex items-center gap-1">
              <Save className="w-3 h-3" /> {protoSaved ? 'تم الحفظ ✓' : 'حفظ البروتوكول'}
            </button>
          </div>
        </div>
        <div className="bg-[#0d0d0f] rounded-xl border border-white/5 p-3 text-[11px] text-slate-400 font-mono leading-6" dir="ltr">
          <div>POST {'{base}'}/get-user-info &nbsp;→&nbsp; sign = md5(gameId+uid+token+roomId+APP_KEY)</div>
          <div>POST {'{base}'}/change-balance &nbsp;→&nbsp; sign = md5(orderId+gameId+roundId+uid+coin+type+rewardType+token+winId+roomId+APP_KEY)</div>
          <div>POST {'{base}'}/make-up-orders &nbsp;→&nbsp; sign = md5(orderId+gameId+roundId+uid+coin+rewardType+winId+roomId+APP_KEY)</div>
        </div>
        {protocol?.signRules && (
          <p className="mt-2 text-[10px] text-slate-500">القواعد المحفوظة: {protocol.signRules}</p>
        )}
      </div>

      {/* ── نموذج إضافة/تعديل ── */}
      {showAdd && editing && (
        <div className="bg-[#141417] rounded-2xl border border-indigo-500/30 p-5 space-y-4">
          <h2 className="text-sm font-bold text-white flex items-center gap-2">
            <Link2 className="w-4 h-4 text-indigo-400" /> {editing.id ? 'تعديل اللعبة' : 'لعبة جديدة'}
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">الاسم بالعربية *</label>
              <input value={editing.nameAr} onChange={e => upd({ nameAr: e.target.value })}
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white" />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">الاسم بالإنجليزية</label>
              <input value={editing.nameEn} onChange={e => upd({ nameEn: e.target.value })}
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white" />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">game_key (مفتاح داخلي) *</label>
              <input value={editing.gameKey} onChange={e => upd({ gameKey: e.target.value })} dir="ltr"
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white font-mono" />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">game_id (id المزوّد)</label>
              <input value={editing.gameId} onChange={e => upd({ gameId: e.target.value })} dir="ltr" placeholder="fe-game-greedy-lion"
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white font-mono" />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">platform</label>
              <select value={editing.platform} onChange={e => upd({ platform: e.target.value })}
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white">
                <option value="alfanexso">alfanexso (StyeParty)</option>
                <option value="custom">custom</option>
              </select>
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">view_mode</label>
              <select value={editing.viewMode} onChange={e => upd({ viewMode: e.target.value })}
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white">
                <option value="half">half (نصف الشاشة)</option>
                <option value="full">full (ملء الشاشة)</option>
              </select>
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">host</label>
              <input value={editing.host} onChange={e => upd({ host: e.target.value })} dir="ltr"
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white font-mono" />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">app_key</label>
              <input value={editing.appKey} onChange={e => upd({ appKey: e.target.value })} dir="ltr"
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white font-mono" />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">pool_id</label>
              <input value={editing.poolId} onChange={e => upd({ poolId: e.target.value })} dir="ltr"
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white font-mono" />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">sort_order</label>
              <input type="number" value={editing.sortOrder} onChange={e => upd({ sortOrder: Number(e.target.value) })}
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white" />
            </div>
            <div className="md:col-span-3">
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">رابط التشغيل (URL Template) - اختياري (اتركه فارغاً للاستخدام التلقائي)</label>
              <input value={editing.urlTemplate} onChange={e => upd({ urlTemplate: e.target.value })} dir="ltr"
                placeholder="https://alfanexso.tech/play/{APP_KEY}/{GAME_ID}?gameId={GAME_ID}&uid={STYEPARTY_USER_ID}&token={PLAYER_TOKEN}&roomId={ROOM_ID}&view_mode=half"
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white font-mono" />
              <div className="mt-1 flex flex-wrap gap-2">
                {PLACEHOLDERS.map(p => (
                  <span key={p} className="text-[9px] text-indigo-300/80 bg-indigo-500/10 border border-indigo-500/20 rounded px-1.5 py-0.5 font-mono" dir="ltr">{p}</span>
                ))}
              </div>
            </div>
            <div className="md:col-span-2">
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">صورة اللعبة (URL أو رفع)</label>
              <div className="flex gap-2">
                <input value={editing.imageUrl} onChange={e => upd({ imageUrl: e.target.value })} dir="ltr"
                  placeholder="https://... أو ارفع من الجهاز"
                  className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white font-mono" />
                <label className={`px-3 py-2 rounded-lg border text-xs flex items-center gap-1 cursor-pointer ${uploading ? 'opacity-50' : 'border-white/10 text-slate-300 hover:bg-white/5'}`}>
                  {uploading ? <span className="animate-spin">⏳</span> : <Upload className="w-3.5 h-3.5" />}
                  <input type="file" accept="image/*" className="hidden" disabled={uploading}
                    onChange={e => { const f = e.target.files?.[0]; if (f) handleImageUpload(f); e.target.value = ''; }} />
                </label>
              </div>
              {editing.imageUrl && (
                <img src={editing.imageUrl} className="mt-2 h-14 rounded-lg border border-white/10 object-cover" alt="" />
              )}
            </div>
            <div className="flex items-end gap-4">
              <label className="flex items-center gap-2 text-xs text-slate-300 cursor-pointer">
                <input type="checkbox" checked={editing.isHot} onChange={e => upd({ isHot: e.target.checked })} className="accent-indigo-500" />
                hot 🔥
              </label>
              <label className="flex items-center gap-2 text-xs text-slate-300 cursor-pointer">
                <input type="checkbox" checked={editing.isActive} onChange={e => upd({ isActive: e.target.checked })} className="accent-emerald-500" />
                مفعّلة
              </label>
            </div>
          </div>
          <div className="flex gap-2">
            <button onClick={handleSave} disabled={saving || !editing.nameAr?.trim() || !editing.gameKey?.trim()}
              className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-700 disabled:opacity-40 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
              <Save className="w-3 h-3" /> {saving ? '...' : 'حفظ'}
            </button>
            <button onClick={() => { setEditing(null); setShowAdd(false); }} className="px-4 py-1.5 bg-slate-700 hover:bg-slate-600 text-xs text-white rounded-lg flex items-center gap-1">
              <X className="w-3 h-3" /> إلغاء
            </button>
          </div>
        </div>
      )}

      {/* ── القائمة ── */}
      {loading ? (
        <div className="text-center py-12 text-slate-500 text-xs">Loading...</div>
      ) : games.length === 0 ? (
        <div className="text-center py-12 text-slate-500 text-xs">لا توجد ألعاب مضافة بعد — اضغط «إضافة لعبة」</div>
      ) : (
        <div className="space-y-2">
          {games.map(g => (
            <div key={g.id} className={`bg-[#141417] rounded-xl border p-3 flex items-center gap-4 ${g.isActive ? 'border-white/5' : 'border-white/5 opacity-50'}`}>
              {g.imageUrl ? (
                <img src={g.imageUrl} className="w-14 h-14 rounded-lg object-cover border border-white/10" alt="" />
              ) : (
                <div className="w-14 h-14 rounded-lg bg-slate-800 flex items-center justify-center text-slate-600"><Gamepad2 className="w-6 h-6" /></div>
              )}
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-bold text-white">{g.nameAr || g.nameEn}</span>
                  {g.isHot && <span className="text-[9px] bg-orange-500/20 text-orange-400 border border-orange-500/30 rounded px-1.5 py-0.5">HOT</span>}
                  {!g.isActive && <span className="text-[9px] bg-slate-500/20 text-slate-400 rounded px-1.5 py-0.5">معطّلة</span>}
                </div>
                <div className="text-[10px] text-slate-500 font-mono truncate" dir="ltr">
                  {g.gameKey} · {g.gameId} · {g.host} · {g.viewMode}
                </div>
                <div className="text-[10px] text-slate-600 font-mono truncate" dir="ltr">{g.urlTemplate}</div>
              </div>
              <div className="flex items-center gap-1">
                <button
                  onClick={() => handleToggleActive(g)}
                  className={`p-2 rounded-lg flex items-center gap-1 text-xs font-medium transition-colors ${
                    g.isActive
                      ? 'text-emerald-400 hover:bg-emerald-500/10'
                      : 'text-amber-400 hover:bg-amber-500/10'
                  }`}
                  title={g.isActive ? 'إخفاء اللعبة من التطبيق' : 'إظهار اللعبة في التطبيق'}
                >
                  {g.isActive ? <Eye className="w-4 h-4" /> : <EyeOff className="w-4 h-4" />}
                  <span className="text-[10px] hidden sm:inline">{g.isActive ? 'مفعّلة' : 'مخفية'}</span>
                </button>
                <button onClick={() => startEdit(g)} className="p-2 text-indigo-400 hover:bg-indigo-500/10 rounded-lg" title="تعديل">
                  <Pencil className="w-4 h-4" />
                </button>
                <button onClick={() => handleDelete(g.id)} className="p-2 text-rose-400 hover:bg-rose-500/10 rounded-lg" title="حذف">
                  <Trash2 className="w-4 h-4" />
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
