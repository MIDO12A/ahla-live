import { useEffect, useState } from 'react';
import { RoomModel } from '../types';
import { getRooms, deleteRoom, updateRoom } from '../lib/db';
import { uploadRoomPhoto } from '../lib/storage';
import DataTable from '../components/DataTable';
import ImageUpload from '../components/ImageUpload';
import { Lock, Unlock, Users, Save, X } from 'lucide-react';

export default function RoomsPage() {
  const [rooms, setRooms] = useState<RoomModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<RoomModel | null>(null);

  useEffect(() => {
    getRooms().then(data => { setRooms(data); setLoading(false); });
  }, []);

  const handleEdit = (room: RoomModel) => setEditing(room);
  const handleDelete = async (room: RoomModel) => { if (confirm(`Delete room "${room.name}"?`)) { await deleteRoom(room.roomId); setRooms(prev => prev.filter(r => r.roomId !== room.roomId)); } };

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

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-white text-lg font-semibold">Room Management</h2>
          <p className="text-slate-500 text-xs mt-0.5">{rooms.length} total rooms</p>
        </div>
      </div>

      {editing && (
        <div className="bg-[#141417] rounded-2xl border border-indigo-500/20 p-6 space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-white font-semibold text-sm">Editing: {editing.name}</h3>
            <button onClick={() => setEditing(null)} className="text-slate-400 hover:text-white"><X className="w-4 h-4" /></button>
          </div>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <ImageUpload
              currentUrl={editing.roomPhotoUrl}
              onUpload={file => uploadRoomPhoto(file, editing.roomId)}
              onUrlChange={url => handleUpdate('roomPhotoUrl', url)}
              label="Room Photo"
            />
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Name</label>
              <input type="text" value={editing.name} onChange={e => handleUpdate('name', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Category</label>
              <input type="text" value={editing.category} onChange={e => handleUpdate('category', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Max Members</label>
              <input type="number" value={editing.maxMembers} onChange={e => handleUpdate('maxMembers', Number(e.target.value))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Password</label>
              <input type="text" value={editing.password} onChange={e => handleUpdate('password', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Locked</label>
              <label className="flex items-center gap-2 text-xs text-slate-400 mt-1">
                <input type="checkbox" checked={editing.isLocked} onChange={e => handleUpdate('isLocked', e.target.checked)} className="accent-indigo-500" />
                {editing.isLocked ? 'Locked' : 'Unlocked'}
              </label>
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Description</label>
              <textarea value={editing.description} onChange={e => handleUpdate('description', e.target.value)} rows={2} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white resize-none" />
            </div>
          </div>
          <div className="flex gap-2">
            <button onClick={handleSaveAll} className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1"><Save className="w-3 h-3" /> Save</button>
            <button onClick={() => setEditing(null)} className="px-4 py-1.5 border border-white/10 text-xs text-slate-400 rounded-lg">Close</button>
          </div>
        </div>
      )}

      <DataTable
        loading={loading}
        columns={[
          { key: 'roomPhotoUrl', label: '', width: '40px', render: r => r.roomPhotoUrl ? <img src={r.roomPhotoUrl} className="w-6 h-6 rounded object-cover" /> : <div className="w-6 h-6 rounded bg-slate-800" /> },
          { key: 'name', label: 'Name', sortable: true },
          { key: 'hostName', label: 'Host', sortable: true },
          { key: 'memberCount', label: 'Members', sortable: true, render: r => <span className="flex items-center gap-1"><Users className="w-3 h-3 text-slate-500" />{r.memberCount}/{r.maxMembers}</span> },
          { key: 'category', label: 'Category', sortable: true },
          { key: 'isLocked', label: '', render: r => r.isLocked ? <Lock className="w-3 h-3 text-rose-400" /> : <Unlock className="w-3 h-3 text-emerald-400" /> },
          { key: 'totalGifts', label: 'Gifts', sortable: true },
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
