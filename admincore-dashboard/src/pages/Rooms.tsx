import { useEffect, useState } from 'react';
import { RoomModel } from '../types';
import { getRooms, deleteRoom, updateRoom, getRoomBlocks, deleteRoomBlock, getUsersByUids, getAppConfig, updateAppConfig, type RoomBlockRow } from '../lib/db';
import { uploadRoomPhoto, uploadRoomCover, detectAssetType } from '../lib/storage';
import DataTable from '../components/DataTable';
import ImageUpload from '../components/ImageUpload';
import { Lock, Unlock, Users, Save, X, Sparkles, Upload, Image as ImageIcon, Filter, Globe, Armchair, Plus, Trash2, CheckCircle2 } from 'lucide-react';

interface SeatTier {
  seats: number;
  coins: number;
  name_ar: string;
  name_en: string;
  enabled: boolean;
}

interface SeatUpgradeConfig {
  enabled: boolean;
  default_seats: number;
  tiers: SeatTier[];
}

const defaultSeatUpgradeConfig: SeatUpgradeConfig = {
  enabled: true,
  default_seats: 10,
  tiers: [
    { seats: 10, coins: 0, name_ar: '10 مقاعد (افتراضي)', name_en: '10 Seats (Default)', enabled: true },
    { seats: 12, coins: 5000, name_ar: '12 مقعد', name_en: '12 Seats', enabled: true },
    { seats: 13, coins: 7500, name_ar: '13 مقعد', name_en: '13 Seats', enabled: true },
    { seats: 15, coins: 10000, name_ar: '15 مقعد', name_en: '15 Seats', enabled: true },
    { seats: 20, coins: 20000, name_ar: '20 مقعد', name_en: '20 Seats', enabled: true },
  ],
};

const countryOptions = [
  { code: '', label: '🌍 الكل (All)' },
  { code: 'EG', label: '🇪🇬 مصر (EG)' },
  { code: 'SA', label: '🇸🇦 السعودية (SA)' },
  { code: 'AE', label: '🇦🇪 الإمارات (AE)' },
  { code: 'KW', label: '🇰🇼 الكويت (KW)' },
  { code: 'QA', label: '🇶🇦 قطر (QA)' },
  { code: 'BH', label: '🇧🇭 البحرين (BH)' },
  { code: 'OM', label: '🇴🇲 عمان (OM)' },
  { code: 'IQ', label: '🇮🇶 العراق (IQ)' },
  { code: 'JO', label: '🇯🇴 الأردن (JO)' },
  { code: 'SY', label: '🇸🇾 سوريا (SY)' },
  { code: 'LB', label: '🇱🇧 لبنان (LB)' },
  { code: 'PS', label: '🇵🇸 فلسطين (PS)' },
  { code: 'YE', label: '🇾🇪 اليمن (YE)' },
  { code: 'SD', label: '🇸🇩 السودان (SD)' },
  { code: 'LY', label: '🇱🇾 ليبيا (LY)' },
  { code: 'TN', label: '🇹🇳 تونس (TN)' },
  { code: 'DZ', label: '🇩🇿 الجزائر (DZ)' },
  { code: 'MA', label: '🇲🇦 المغرب (MA)' },
  { code: 'MR', label: '🇲🇷 موريتانيا (MR)' },
  { code: 'SO', label: '🇸🇴 الصومال (SO)' },
  { code: 'DJ', label: '🇩🇯 جيبوتي (DJ)' },
  { code: 'KM', label: '🇰🇲 جزر القمر (KM)' },
  { code: 'TR', label: '🇹🇷 تركيا (TR)' },
  { code: 'US', label: '🇺🇸 أمريكا (US)' },
  { code: 'GB', label: '🇬🇧 بريطانيا (GB)' },
  { code: 'DE', label: '🇩🇪 ألمانيا (DE)' },
  { code: 'FR', label: '🇫🇷 فرنسا (FR)' },
  { code: 'IT', label: '🇮🇹 إيطاليا (IT)' },
  { code: 'ES', label: '🇪🇸 إسبانيا (ES)' },
  { code: 'CA', label: '🇨🇦 كندا (CA)' },
  { code: 'RU', label: '🇷🇺 روسيا (RU)' },
  { code: 'CN', label: '🇨🇳 الصين (CN)' },
  { code: 'IN', label: '🇮🇳 الهند (IN)' },
  { code: 'PK', label: '🇵🇰 باكستان (PK)' },
  { code: 'ID', label: '🇮🇩 إندونيسيا (ID)' },
  { code: 'MY', label: '🇲🇾 ماليزيا (MY)' },
  { code: 'BR', label: '🇧🇷 البرازيل (BR)' },
  { code: 'SE', label: '🇸🇪 السويد (SE)' },
  { code: 'NL', label: '🇳🇱 هولندا (NL)' },
  { code: 'AU', label: '🇦🇺 أستراليا (AU)' },
];

export default function RoomsPage() {
  const [rooms, setRooms] = useState<RoomModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<RoomModel | null>(null);
  const [uploadingCover, setUploadingCover] = useState(false);
  const [roomBlocks, setRoomBlocks] = useState<RoomBlockRow[]>([]);
  const [blockUsers, setBlockUsers] = useState<Map<string, { name: string; custom_id: string }>>(new Map());
  const [loadingBlocks, setLoadingBlocks] = useState(false);
  const [countryFilter, setCountryFilter] = useState<string>('');

  // إعدادات ترقية المقاعد وأسعارها بالعملات
  const [seatConfig, setSeatConfig] = useState<SeatUpgradeConfig>(defaultSeatUpgradeConfig);
  const [savingSeatConfig, setSavingSeatConfig] = useState(false);
  const [showSeatSettings, setShowSeatSettings] = useState(false);

  useEffect(() => {
    getAppConfig<SeatUpgradeConfig>('room_seat_upgrade_config').then(cfg => {
      if (cfg && Array.isArray(cfg.tiers)) {
        setSeatConfig(cfg);
      }
    });
  }, []);

  const handleSaveSeatConfig = async () => {
    setSavingSeatConfig(true);
    try {
      await updateAppConfig('room_seat_upgrade_config', seatConfig);
      alert('تم حفظ إعدادات وأسعار ترقية المقاعد بنجاح!');
    } catch (e) {
      alert('فشل حفظ الإعدادات: ' + (e as Error).message);
    } finally {
      setSavingSeatConfig(false);
    }
  };

  const handleAddTier = () => {
    setSeatConfig(prev => ({
      ...prev,
      tiers: [
        ...prev.tiers,
        {
          seats: (prev.tiers[prev.tiers.length - 1]?.seats || 10) + 2,
          coins: 10000,
          name_ar: 'مقاعد جديدة',
          name_en: 'New Seats',
          enabled: true,
        },
      ],
    }));
  };

  const handleRemoveTier = (index: number) => {
    setSeatConfig(prev => ({
      ...prev,
      tiers: prev.tiers.filter((_, i) => i !== index),
    }));
  };

  const handleUpdateTier = (index: number, field: keyof SeatTier, val: any) => {
    setSeatConfig(prev => {
      const copy = [...prev.tiers];
      copy[index] = { ...copy[index], [field]: val };
      return { ...prev, tiers: copy };
    });
  };

  const loadBlocks = async (roomId: string) => {
    setLoadingBlocks(true);
    const blocks = await getRoomBlocks(roomId);
    setRoomBlocks(blocks);
    const uids = [...new Set(blocks.map(b => b.blocked_uid).filter(Boolean))];
    const users = await getUsersByUids(uids);
    setBlockUsers(users);
    setLoadingBlocks(false);
  };

  const handleEdit = (room: RoomModel) => {
    setEditing(room);
    loadBlocks(room.roomId);
  };

  const handleUnblock = async (blockId: string) => {
    await deleteRoomBlock(blockId);
    setRoomBlocks(prev => prev.filter(b => b.id !== blockId));
  };

  useEffect(() => {
    getRooms().then(data => { setRooms(data); setLoading(false); });
  }, []);

  const handleDelete = async (room: RoomModel) => {
    if (confirm(`Delete room "${room.name}"?`)) {
      await deleteRoom(room.roomId);
      setRooms(prev => prev.filter(r => r.roomId !== room.roomId));
    }
  };

  const handleUpdate = async (field: string, value: unknown) => {
    if (!editing) return;
    const updated = { ...editing, [field]: value };
    setEditing(updated);
    await updateRoom(editing.roomId, { [field]: value });
    setRooms(prev => prev.map(r => r.roomId === editing.roomId ? updated : r));
  };

  const handleSaveAll = async () => {
    if (!editing) return;
    await updateRoom(editing.roomId, editing);
    setRooms(prev => prev.map(r => r.roomId === editing.roomId ? editing : r));
    setEditing(null);
  };

  const handleCoverUpload = async () => {
    if (!editing) return;
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.svga,.vap,.mp4,.webp,.png,.jpg,.jpeg,.gif';
    input.onchange = async () => {
      const file = input.files?.[0];
      if (!file) return;
      setUploadingCover(true);
      try {
        const url = await uploadRoomCover(file, editing.roomId);
        await handleUpdate('bgImage', url);
      } catch (err) {
        alert('فشل رفع غلاف الغرفة: ' + (err as Error).message);
      } finally {
        setUploadingCover(false);
      }
    };
    input.click();
  };

  const isSpecialId = (id?: string) => {
    if (!id) return false;
    const clean = id.trim();
    return clean.length <= 6 && !isNaN(Number(clean));
  };

  const getFormatBadge = (url?: string) => {
    if (!url) return null;
    const type = detectAssetType(url).toUpperCase();
    const color = type === 'SVGA'
      ? 'bg-amber-500/20 text-amber-300 border-amber-500/30'
      : type === 'VAP' || type === 'MP4'
      ? 'bg-purple-500/20 text-purple-300 border-purple-500/30'
      : 'bg-emerald-500/20 text-emerald-300 border-emerald-500/30';
    return (
      <span className={`px-1.5 py-0.5 text-[9px] font-bold rounded border ${color}`}>
        {type}
      </span>
    );
  };

  const filteredRooms = countryFilter
    ? rooms.filter(r => r.country?.toUpperCase() === countryFilter.toUpperCase())
    : rooms;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between flex-wrap gap-4">
        <div>
          <h2 className="text-white text-lg font-semibold">إدارة الغرف الصوتية (Room Management)</h2>
          <p className="text-slate-500 text-xs mt-0.5">{filteredRooms.length} / {rooms.length} غرفة</p>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={() => setShowSeatSettings(prev => !prev)}
            className={`px-3 py-1.5 rounded-lg text-xs font-semibold flex items-center gap-1.5 transition-colors ${
              showSeatSettings
                ? 'bg-amber-500 text-black shadow-lg shadow-amber-500/20'
                : 'bg-[#161618] border border-amber-500/30 text-amber-300 hover:bg-amber-500/10'
            }`}
          >
            <Armchair className="w-3.5 h-3.5" />
            إعدادات وأسعار ترقية المقاعد
          </button>
          <div className="relative">
            <Globe className="w-3.5 h-3.5 absolute left-3 top-1/2 -translate-y-1/2 text-slate-500 pointer-events-none" />
            <select
              value={countryFilter}
              onChange={e => setCountryFilter(e.target.value)}
              className="w-48 bg-[#161618] border border-white/10 rounded-lg py-1.5 pl-9 pr-2 text-xs text-white appearance-none"
            >
              {countryOptions.map(opt => (
                <option key={opt.code} value={opt.code}>{opt.label}</option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {/* لوحة تحكم ترقية مقاعد الغرف وأسعارها بالعملات */}
      {showSeatSettings && (
        <div className="bg-[#141417] rounded-2xl border border-amber-500/30 p-5 space-y-4 shadow-xl shadow-black/40">
          <div className="flex items-center justify-between flex-wrap gap-3 border-b border-white/10 pb-3">
            <div className="flex items-center gap-2">
              <div className="w-8 h-8 rounded-lg bg-amber-500/20 border border-amber-500/30 flex items-center justify-center text-amber-300">
                <Armchair className="w-4 h-4" />
              </div>
              <div>
                <h3 className="text-white text-sm font-bold flex items-center gap-2">
                  نظام ترقية مقاعد الغرف بالعملات
                  <span className="text-[10px] bg-amber-500/20 text-amber-300 px-2 py-0.5 rounded border border-amber-500/30">
                    Live Room Seat Pricing
                  </span>
                </h3>
                <p className="text-[11px] text-slate-400">
                  حدد المقاعد الافتراضية للغرف الجديدة (10 مقاعد) وحدد سعر كل ترقية بالكوينز
                </p>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <label className="flex items-center gap-2 text-xs text-white cursor-pointer bg-black/30 px-3 py-1.5 rounded-lg border border-white/10">
                <input
                  type="checkbox"
                  checked={seatConfig.enabled}
                  onChange={e => setSeatConfig(prev => ({ ...prev, enabled: e.target.checked }))}
                  className="accent-amber-500 w-4 h-4"
                />
                <span className="font-semibold">{seatConfig.enabled ? 'النظام مفعل' : 'النظام معطل'}</span>
              </label>
              <button
                onClick={handleSaveSeatConfig}
                disabled={savingSeatConfig}
                className="px-4 py-1.5 bg-gradient-to-r from-amber-500 to-amber-600 hover:from-amber-600 hover:to-amber-700 disabled:opacity-50 text-black font-bold text-xs rounded-lg flex items-center gap-1.5 shadow-lg shadow-amber-500/20 transition-all"
              >
                <Save className="w-3.5 h-3.5" />
                {savingSeatConfig ? 'جارٍ الحفظ...' : 'حفظ الأسعار'}
              </button>
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-4 gap-4 items-center bg-black/20 p-3 rounded-xl border border-white/5">
            <div>
              <label className="block text-[11px] font-bold text-slate-300 mb-1">
                عدد المقاعد الافتراضي لجميع الغرف:
              </label>
              <input
                type="number"
                min={8}
                max={20}
                value={seatConfig.default_seats}
                onChange={e => setSeatConfig(prev => ({ ...prev, default_seats: Number(e.target.value) }))}
                className="w-full bg-[#161618] border border-amber-500/40 rounded-lg py-1.5 px-3 text-sm text-amber-300 font-bold"
              />
              <span className="text-[10px] text-slate-500">بداية الغرف بالكامل تبدأ بهذا العدد (10 مقاعد)</span>
            </div>
          </div>

          {/* جدول باقات ومستويات المقاعد */}
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <h4 className="text-xs font-bold text-slate-200">مستويات وأسعار المقاعد (Tiers):</h4>
              <button
                type="button"
                onClick={handleAddTier}
                className="px-2.5 py-1 bg-white/5 hover:bg-white/10 border border-white/10 text-white text-xs rounded-lg flex items-center gap-1 transition-colors"
              >
                <Plus className="w-3 h-3 text-amber-400" />
                إضافة مستوى مقاعد
              </button>
            </div>

            <div className="overflow-x-auto border border-white/10 rounded-xl">
              <table className="w-full text-xs text-right">
                <thead className="bg-[#1a1a1e] text-slate-400 font-bold border-b border-white/10">
                  <tr>
                    <th className="py-2.5 px-3">عدد المقاعد</th>
                    <th className="py-2.5 px-3">السعر بالكوينز 🪙</th>
                    <th className="py-2.5 px-3">الاسم بالعربية</th>
                    <th className="py-2.5 px-3">الاسم بالإنجليزية</th>
                    <th className="py-2.5 px-3 text-center">مفعل</th>
                    <th className="py-2.5 px-3 text-center">إجراء</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-white/5">
                  {seatConfig.tiers.map((tier, idx) => (
                    <tr key={idx} className="hover:bg-white/5 transition-colors">
                      <td className="py-2 px-3">
                        <div className="flex items-center gap-1.5">
                          <input
                            type="number"
                            value={tier.seats}
                            onChange={e => handleUpdateTier(idx, 'seats', Number(e.target.value))}
                            className="w-20 bg-black/40 border border-white/10 rounded px-2 py-1 text-xs text-amber-300 font-bold"
                          />
                          <span className="text-slate-500">مقعد</span>
                        </div>
                      </td>
                      <td className="py-2 px-3">
                        <input
                          type="number"
                          step={500}
                          value={tier.coins}
                          onChange={e => handleUpdateTier(idx, 'coins', Number(e.target.value))}
                          className="w-28 bg-black/40 border border-amber-500/30 rounded px-2 py-1 text-xs text-amber-400 font-mono font-bold"
                        />
                      </td>
                      <td className="py-2 px-3">
                        <input
                          type="text"
                          value={tier.name_ar}
                          onChange={e => handleUpdateTier(idx, 'name_ar', e.target.value)}
                          className="w-full bg-black/40 border border-white/10 rounded px-2 py-1 text-xs text-white"
                        />
                      </td>
                      <td className="py-2 px-3">
                        <input
                          type="text"
                          value={tier.name_en}
                          onChange={e => handleUpdateTier(idx, 'name_en', e.target.value)}
                          className="w-full bg-black/40 border border-white/10 rounded px-2 py-1 text-xs text-white"
                        />
                      </td>
                      <td className="py-2 px-3 text-center">
                        <input
                          type="checkbox"
                          checked={tier.enabled}
                          onChange={e => handleUpdateTier(idx, 'enabled', e.target.checked)}
                          className="accent-amber-500"
                        />
                      </td>
                      <td className="py-2 px-3 text-center">
                        <button
                          type="button"
                          onClick={() => handleRemoveTier(idx)}
                          className="p-1 hover:bg-rose-500/20 text-slate-500 hover:text-rose-400 rounded transition-colors"
                          title="حذف"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {editing && (
        <div className="bg-[#141417] rounded-2xl border border-indigo-500/20 p-6 space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-white font-semibold text-sm flex items-center gap-2">
              تعديل الغرفة: {editing.name}
              {isSpecialId(editing.roomId) && (
                <span className="px-2 py-0.5 text-[10px] bg-amber-500/20 text-amber-300 border border-amber-500/40 rounded-full flex items-center gap-1 font-bold">
                  <Sparkles className="w-3 h-3 text-amber-400" /> آيدي مميز: {editing.roomId}
                </span>
              )}
            </h3>
            <button onClick={() => setEditing(null)} className="text-slate-400 hover:text-white"><X className="w-4 h-4" /></button>
          </div>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <ImageUpload
              currentUrl={editing.roomPhotoUrl}
              onUpload={file => uploadRoomPhoto(file, editing.roomId)}
              onUrlChange={url => handleUpdate('roomPhotoUrl', url)}
              label="شعار / صورة الغرفة"
            />

            {/* غلاف وخلفية الغرفة SVGA / VAP / WEBP / PNG */}
            <div className="space-y-2">
              <label className="block text-[10px] uppercase text-slate-400 font-bold">
                غلاف / خلفية الغرفة (SVGA / VAP / PNG / WEBP)
              </label>
              <div className="flex items-center gap-2">
                <input
                  type="text"
                  value={editing.bgImage || ''}
                  onChange={e => handleUpdate('bgImage', e.target.value)}
                  placeholder="رابط غلاف الغرفة أو ارفعه..."
                  className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
                />
                <button
                  type="button"
                  onClick={handleCoverUpload}
                  disabled={uploadingCover}
                  className="px-2.5 py-1.5 bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-white text-xs rounded-lg flex items-center gap-1 transition-colors"
                  title="رفع ملف SVGA أو VAP أو صورة"
                >
                  <Upload className="w-3.5 h-3.5" />
                  {uploadingCover ? '...' : 'رفع'}
                </button>
              </div>
              {editing.bgImage && (
                <div className="flex items-center gap-2 mt-1">
                  {getFormatBadge(editing.bgImage)}
                  <span className="text-[10px] text-slate-400 truncate max-w-[200px]" title={editing.bgImage}>
                    {editing.bgImage}
                  </span>
                </div>
              )}
            </div>

            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">معرف الغرفة (Room ID)</label>
              <input
                type="text"
                value={editing.roomId}
                onChange={e => handleUpdate('roomId', e.target.value)}
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono"
              />
            </div>

            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">الدولة (Country Code)</label>
              <input
                type="text"
                value={editing.country || ''}
                onChange={e => handleUpdate('country', e.target.value)}
                placeholder="مثال: EG, SA, AE"
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
              />
            </div>

            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">اسم الغرفة</label>
              <input type="text" value={editing.name} onChange={e => handleUpdate('name', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">التصنيف (Category)</label>
              <input type="text" value={editing.category} onChange={e => handleUpdate('category', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">الحد الأقصى للأعضاء</label>
              <input type="number" value={editing.maxMembers} onChange={e => handleUpdate('maxMembers', Number(e.target.value))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-amber-400 font-bold mb-1">عدد مقاعد الغرفة (Seats)</label>
              <input
                type="number"
                min={8}
                max={20}
                value={editing.seatCount || 10}
                onChange={e => handleUpdate('seatCount', Number(e.target.value))}
                className="w-full bg-[#161618] border border-amber-500/40 rounded-lg py-1.5 px-2 text-xs text-amber-300 font-bold"
              />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">كلمة المرور (إن وجدت)</label>
              <input type="text" value={editing.password} onChange={e => handleUpdate('password', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">حالة القفل</label>
              <label className="flex items-center gap-2 text-xs text-slate-400 mt-1">
                <input type="checkbox" checked={editing.isLocked} onChange={e => handleUpdate('isLocked', e.target.checked)} className="accent-indigo-500" />
                {editing.isLocked ? 'مقفلة (Locked)' : 'مفتوحة (Unlocked)'}
              </label>
            </div>
            <div className="col-span-2">
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">الوصف والإعلان</label>
              <textarea value={editing.description} onChange={e => handleUpdate('description', e.target.value)} rows={2} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white resize-none" />
            </div>
          </div>
          {/* قائمة الحظر الخاصة بالغرفة */}
          <div className="border-t border-white/10 pt-3">
            <h4 className="text-xs font-bold text-rose-300 mb-2">🚫 المحظورون من هذه الغرفة ({roomBlocks.length})</h4>
            {loadingBlocks ? (
              <p className="text-[11px] text-slate-500">جارٍ التحميل...</p>
            ) : roomBlocks.length === 0 ? (
              <p className="text-[11px] text-slate-500">لا يوجد محظورون — من يُطرد مع تفعيل "القائمة السوداء" يُمنع من إعادة الدخول حتى تفك الحظر من هنا</p>
            ) : (
              <div className="space-y-1.5 max-h-40 overflow-y-auto">
                {roomBlocks.map(b => {
                  const u = blockUsers.get(b.blocked_uid);
                  return (
                    <div key={b.id} className="flex items-center justify-between gap-2 bg-black/40 border border-white/10 rounded-lg px-3 py-2">
                      <div className="min-w-0">
                        <p className="text-xs text-white font-bold truncate">
                          {u?.name || b.blocked_uid}
                          {u?.custom_id ? <span className="text-slate-400 font-mono mr-1">#{u.custom_id}</span> : null}
                        </p>
                        <p className="text-[10px] text-slate-500 truncate">
                          {b.reason ? `السبب: ${b.reason} • ` : ''}
                          {b.created_at ? new Date(b.created_at).toLocaleString('ar-EG') : ''}
                        </p>
                      </div>
                      <button
                        onClick={() => handleUnblock(b.id)}
                        className="shrink-0 px-2.5 py-1 bg-emerald-600 hover:bg-emerald-700 text-white text-[11px] font-bold rounded-lg transition-colors"
                      >
                        فك الحظر
                      </button>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
          <div className="flex gap-2">
            <button onClick={handleSaveAll} className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1"><Save className="w-3 h-3" /> حفظ التعديلات</button>
            <button onClick={() => setEditing(null)} className="px-4 py-1.5 border border-white/10 text-xs text-slate-400 rounded-lg">إلغاء</button>
          </div>
        </div>
      )}

<DataTable
        loading={loading}
        columns={[
          { key: 'roomPhotoUrl', label: '', width: '40px', render: r => r.roomPhotoUrl ? <img src={r.roomPhotoUrl} className="w-6 h-6 rounded object-cover" /> : <div className="w-6 h-6 rounded bg-slate-800" /> },
          {
            key: 'roomId',
            label: 'ID',
            sortable: true,
            render: r => isSpecialId(r.roomId) ? (
              <span className="px-2 py-0.5 text-[10px] bg-amber-500/20 text-amber-300 border border-amber-500/40 rounded font-bold font-mono">
                ⭐ {r.roomId}
              </span>
            ) : (
              <span className="text-slate-300 font-mono text-xs">{r.roomId}</span>
            )
          },
          { key: 'name', label: 'اسم الغرفة', sortable: true },
          { key: 'hostName', label: 'المالك (Host)', sortable: true },
          {
            key: 'bgImage',
            label: 'الغلاف / الخلفية',
            render: r => (
              <div className="flex items-center gap-1.5">
                {getFormatBadge(r.bgImage)}
                {r.bgImage ? (
                  <span className="text-[10px] text-slate-400 truncate max-w-[120px]" title={r.bgImage}>
                    {r.bgImage.split('/').pop()}
                  </span>
                ) : (
                  <span className="text-[10px] text-slate-600">افتراضي</span>
                )}
              </div>
            )
          },
          { key: 'memberCount', label: 'الأعضاء', sortable: true, render: r => <span className="flex items-center gap-1"><Users className="w-3 h-3 text-slate-500" />{r.memberCount}/{r.maxMembers}</span> },
          {
            key: 'seatCount',
            label: 'المقاعد',
            sortable: true,
            render: r => (
              <span className="px-2 py-0.5 text-xs bg-amber-500/15 text-amber-300 border border-amber-500/30 rounded font-bold flex items-center gap-1 w-fit">
                <Armchair className="w-3 h-3 text-amber-400" /> {r.seatCount || 10}
              </span>
            ),
          },
          { key: 'category', label: 'التصنيف', sortable: true },
          { key: 'country', label: 'الدولة', sortable: true, width: '60px', render: r => r.country ? <span className="text-xs font-mono uppercase">{r.country}</span> : <span className="text-slate-600 text-xs">—</span> },
          { key: 'isLocked', label: '', render: r => r.isLocked ? <Lock className="w-3 h-3 text-rose-400" /> : <Unlock className="w-3 h-3 text-emerald-400" /> },
          { key: 'totalGifts', label: 'الهدايا', sortable: true },
          { key: 'hotValue', label: 'Hot', sortable: true },
        ]}
        data={filteredRooms}
        searchKeys={['name', 'hostName', 'roomId', 'category', 'country']}
        onEdit={handleEdit}
        onDelete={handleDelete}
      />
    </div>
  );
}
