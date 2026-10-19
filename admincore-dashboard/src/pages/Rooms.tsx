import { useEffect, useState } from 'react';
import { RoomModel } from '../types';
import { getRooms, deleteRoom, updateRoom } from '../lib/db';
import { uploadRoomPhoto, uploadRoomCover, detectAssetType } from '../lib/storage';
import DataTable from '../components/DataTable';
import ImageUpload from '../components/ImageUpload';
import { Lock, Unlock, Users, Save, X, Sparkles, Upload, Image as ImageIcon } from 'lucide-react';

export default function RoomsPage() {
  const [rooms, setRooms] = useState<RoomModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<RoomModel | null>(null);
  const [uploadingCover, setUploadingCover] = useState(false);

  useEffect(() => {
    getRooms().then(data => { setRooms(data); setLoading(false); });
  }, []);

  const handleEdit = (room: RoomModel) => setEditing(room);
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

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-white text-lg font-semibold">إدارة الغرف الصوتية (Room Management)</h2>
          <p className="text-slate-500 text-xs mt-0.5">{rooms.length} إجمالي الغرف</p>
        </div>
      </div>

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
          { key: 'category', label: 'التصنيف', sortable: true },
          { key: 'isLocked', label: '', render: r => r.isLocked ? <Lock className="w-3 h-3 text-rose-400" /> : <Unlock className="w-3 h-3 text-emerald-400" /> },
          { key: 'totalGifts', label: 'الهدايا', sortable: true },
          { key: 'hotValue', label: 'Hot', sortable: true },
        ]}
        data={rooms}
        searchKeys={['name', 'hostName', 'roomId', 'category']}
        onEdit={handleEdit}
        onDelete={handleDelete}
      />
    </div>
  );
}
