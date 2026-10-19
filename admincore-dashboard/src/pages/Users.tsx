import { useEffect, useState } from 'react';
import { UserModel } from '../types';
import { getUsers, deleteUser, updateUser, updateUserPassword, getAuthUsers, getAuthUser, syncAllAuthUsersToDB } from '../lib/db';
import { uploadUserPhoto } from '../lib/storage';
import DataTable from '../components/DataTable';
import ImageUpload from '../components/ImageUpload';
import { Coins, Gem, X, Save, Search, Ban, Shield, Phone, Globe, Key, Ruler, ChevronDown, RefreshCw, AlertTriangle, CheckCircle, ArrowRightCircle } from 'lucide-react';
import { supabase, isAdminConnected } from '../lib/supabase';

export default function UsersPage() {
  const [users, setUsers] = useState<UserModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [syncing, setSyncing] = useState(false);
  const [editing, setEditing] = useState<UserModel | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [showPasswordField, setShowPasswordField] = useState(false);
  const [newPassword, setNewPassword] = useState('');
  const [passwordMsg, setPasswordMsg] = useState('');
  const [showBanDialog, setShowBanDialog] = useState(false);
  const [banReason, setBanReason] = useState('');
  const [activeTab, setActiveTab] = useState<'info' | 'levels' | 'currency' | 'network'>('info');
  const [msg, setMsg] = useState('');

  const loadUsers = async () => {
    setLoading(true);
    try {
      const data = await getUsers();
      setUsers(data);
    } catch (e) {
      console.error('Error loading users:', e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadUsers();
  }, []);

  const showMsg = (text: string) => { setMsg(text); setTimeout(() => setMsg(''), 3000); };

  const handleSyncUsers = async () => {
    if (!confirm('This will create user records in database for all auth users who don\'t have them yet. Continue?')) return;
    setSyncing(true);
    try {
      const result = await syncAllAuthUsersToDB();
      showMsg(`Synced ${result.synced} users out of ${result.total} total auth users`);
      await loadUsers();
    } catch (e: unknown) {
      const err = e as { message?: string };
      showMsg('Error syncing: ' + (err?.message || 'unknown'));
    } finally {
      setSyncing(false);
    }
  };

  const handleDelete = async (user: UserModel) => {
    if (confirm(`Delete user ${user.name}?`)) {
      try {
        await deleteUser(user.uid);
        setUsers(prev => prev.filter(u => u.uid !== user.uid));
        showMsg('User deleted successfully');
      } catch (e: unknown) {
        console.error('Error deleting user:', e);
        const err = e as { message?: string };
        showMsg('Failed to delete user: ' + (err?.message || 'Unknown error'));
      }
    }
  };

  const handleUpdate = async (field: string, value: unknown) => {
    if (!editing) return;
    const updated = { ...editing, [field]: value };
    setEditing(updated);
    try {
      await updateUser(editing.uid, { [field]: value });
      setUsers(prev => prev.map(u => u.uid === editing.uid ? updated : u));
    } catch (e: unknown) {
      const err = e as { message?: string };
      showMsg('Error: ' + (err?.message || 'Update failed'));
    }
  };

  const handleSaveAll = async () => {
    if (!editing) return;
    try {
      await updateUser(editing.uid, editing);
      setUsers(prev => prev.map(u => u.uid === editing.uid ? editing : u));
      showMsg('Saved!');
    } catch (e: unknown) {
      const err = e as { message?: string };
      showMsg('Error: ' + (err?.message || 'Save failed'));
    }
  };

  const handlePasswordChange = async () => {
    if (!editing || !newPassword) return;
    try {
      await updateUserPassword(editing.uid, newPassword);
      setPasswordMsg('Password updated successfully');
      setNewPassword('');
      setShowPasswordField(false);
      setTimeout(() => setPasswordMsg(''), 3000);
    } catch (e: unknown) {
      const err = e as { message?: string };
      setPasswordMsg('Error: ' + (err?.message || 'unknown'));
    }
  };

  const handleBan = async () => {
    if (!editing) return;
    const nowBanned = !editing.banned;
    await updateUser(editing.uid, { banned: nowBanned, banReason: nowBanned ? banReason : '' });
    const updated = { ...editing, banned: nowBanned, banReason: nowBanned ? banReason : '' };
    setEditing(updated);
    setUsers(prev => prev.map(u => u.uid === editing.uid ? updated : u));
    setShowBanDialog(false);
    setBanReason('');
    showMsg(nowBanned ? 'User banned' : 'User unbanned');
  };

  const visibleUsers = searchTerm
    ? users.filter(u =>
        u.name?.toLowerCase().includes(searchTerm.toLowerCase()) ||
        u.email?.toLowerCase().includes(searchTerm.toLowerCase()) ||
        u.uid?.includes(searchTerm) ||
        u.customId?.includes(searchTerm)
      )
    : users;

  const levelFields = [
    { key: 'level', label: 'General Level' },
    { key: 'wealthLevel', label: 'Wealth Level' },
    { key: 'rechargeLevel', label: 'Recharge Level' },
    { key: 'gemsLevel', label: 'Gems Level' },
  ] as const;

  const expFields = [
    { key: 'experience', label: 'XP' },
    { key: 'wealthExp', label: 'Wealth XP' },
    { key: 'rechargeExp', label: 'Recharge XP' },
    { key: 'gemsExp', label: 'Gems XP' },
  ] as const;

  const tabs = [
    { id: 'info' as const, label: 'Basic Info', icon: '👤' },
    { id: 'levels' as const, label: 'Levels', icon: '📊' },
    { id: 'currency' as const, label: 'Coins & Dia', icon: '💰' },
    { id: 'network' as const, label: 'Network & Ban', icon: '🔒' },
  ];

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-white text-lg font-semibold">User Management</h2>
          <p className="text-slate-500 text-xs mt-0.5">{users.length} total users</p>
        </div>
        <div className="flex items-center gap-2">
          {isAdminConnected() && (
            <button 
              onClick={handleSyncUsers} 
              disabled={syncing}
              className="px-3 py-1.5 bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 text-white text-xs rounded-lg flex items-center gap-1"
            >
              <ArrowRightCircle className="w-3 h-3" /> {syncing ? 'Syncing...' : 'Sync All Users'}
            </button>
          )}
          <button 
            onClick={loadUsers} 
            className="px-3 py-1.5 bg-slate-700 hover:bg-slate-600 text-white text-xs rounded-lg flex items-center gap-1"
          >
            <RefreshCw className="w-3 h-3" /> Refresh
          </button>
          <div className="relative">
            <Search className="w-3.5 h-3.5 absolute left-3 top-1/2 -translate-y-1/2 text-slate-500 pointer-events-none" />
            <input
              type="text" value={searchTerm} onChange={e => setSearchTerm(e.target.value)}
              placeholder="Search users..."
              className="bg-[#161618] border border-white/10 rounded-lg py-1.5 pl-9 pr-3 text-xs text-white w-48 focus:outline-none focus:border-indigo-500"
            />
          </div>
        </div>
      </div>

      {isAdminConnected() ? (
        <div className="bg-emerald-500/10 border border-emerald-500/20 rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <CheckCircle className="w-4 h-4 text-emerald-400" />
            <h3 className="text-emerald-400 text-sm font-semibold">Admin connection is active</h3>
          </div>
          <p className="text-xs text-slate-400">
            You're seeing all registered users from both the public users table and Supabase Auth. You have full access to manage users.
          </p>
        </div>
      ) : (
        <div className="bg-amber-500/10 border border-amber-500/20 rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <AlertTriangle className="w-4 h-4 text-amber-400" />
            <h3 className="text-amber-400 text-sm font-semibold">Admin connection not configured</h3>
          </div>
          <p className="text-xs text-slate-400">
            You're only seeing users from the public users table. To see <strong>ALL registered users</strong> including auth users,
            please go to <strong>Settings</strong> and add your Supabase <strong>service_role</strong> key.
          </p>
        </div>
      )}

      {msg && (
        <div className="bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs px-4 py-2 rounded-lg">
          {msg}
        </div>
      )}

      {editing && (
        <div className="bg-[#141417] rounded-2xl border border-indigo-500/20">
          {/* Header */}
          <div className="flex items-center justify-between p-6 pb-4 border-b border-white/5">
            <div className="flex items-center gap-3">
              <div className="relative">
                {editing.photoUrl ? (
                  <img src={editing.photoUrl} className="w-10 h-10 rounded-full object-cover border border-white/10" onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }} />
                ) : (
                  <div className="w-10 h-10 rounded-full bg-indigo-500/20 flex items-center justify-center text-sm text-indigo-400 font-bold">
                    {editing.name?.[0] || '?'}
                  </div>
                )}
                {editing.banned && (
                  <div className="absolute -top-1 -right-1 bg-red-500 rounded-full p-0.5">
                    <Ban className="w-3 h-3 text-white" />
                  </div>
                )}
              </div>
              <div>
                <h3 className="text-white font-semibold text-sm">{editing.name || 'Unnamed'}</h3>
                <p className="text-[10px] text-slate-500 font-mono">#{editing.customId} · {editing.uid.slice(0, 8)}</p>
              </div>
            </div>
            <button onClick={() => { setEditing(null); setShowPasswordField(false); setNewPassword(''); }} className="text-slate-400 hover:text-white"><X className="w-4 h-4" /></button>
          </div>

          {/* Tabs */}
          <div className="flex border-b border-white/5">
            {tabs.map(t => (
              <button key={t.id} onClick={() => setActiveTab(t.id)}
                className={`px-4 py-2.5 text-xs font-medium transition-colors flex items-center gap-1.5 ${activeTab === t.id ? 'text-indigo-400 border-b-2 border-indigo-400' : 'text-slate-500 hover:text-slate-300'}`}>
                <span>{t.icon}</span> {t.label}
              </button>
            ))}
          </div>

          <div className="p-6 space-y-4">
            {/* Tab: Basic Info */}
            {activeTab === 'info' && (
              <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
                <ImageUpload currentUrl={editing.photoUrl} onUpload={file => uploadUserPhoto(file, editing.uid)} onUrlChange={url => handleUpdate('photoUrl', url)} label="Profile Photo" />
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Name</label>
                  <input type="text" value={editing.name || ''} onChange={e => handleUpdate('name', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                </div>
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Custom ID</label>
                  <input type="text" value={editing.customId || ''} onChange={e => handleUpdate('customId', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                </div>
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Email</label>
                  <input type="email" value={editing.email || ''} onChange={e => handleUpdate('email', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                </div>
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Gender</label>
                  <select value={editing.gender || 'male'} onChange={e => handleUpdate('gender', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
                    <option value="male">Male</option>
                    <option value="female">Female</option>
                  </select>
                </div>
                <div className="flex items-end pb-1">
                  <button onClick={() => { setShowPasswordField(!showPasswordField); setNewPassword(''); setPasswordMsg(''); }} className={`px-3 py-1.5 border text-xs rounded-lg flex items-center gap-1 ${showPasswordField ? 'bg-indigo-500/20 border-indigo-500/30 text-indigo-400' : 'border-white/10 text-slate-400'}`}>
                    <Key className="w-3 h-3" /> Change Password
                  </button>
                </div>
                {showPasswordField && (
                  <div className="col-span-2 md:col-span-3 bg-[#161618] rounded-lg p-3 border border-white/5">
                    <div className="flex gap-2 items-end">
                      <div className="flex-1">
                        <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">New Password</label>
                        <input type="text" value={newPassword} onChange={e => setNewPassword(e.target.value)} placeholder="Enter new password..." className="w-full bg-[#141417] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" />
                      </div>
                      <button onClick={handlePasswordChange} className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1"><Key className="w-3 h-3" /> Update</button>
                    </div>
                    {passwordMsg && <p className={`text-[10px] mt-1 ${passwordMsg.includes('Error') ? 'text-red-400' : 'text-emerald-400'}`}>{passwordMsg}</p>}
                  </div>
                )}
              </div>
            )}

            {/* Tab: Levels */}
            {activeTab === 'levels' && (
              <div className="space-y-4">
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  {levelFields.map(f => (
                    <div key={f.key}>
                      <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{f.label}</label>
                      <input type="number" value={String((editing as unknown as Record<string, number>)[f.key] ?? 1)} onChange={e => handleUpdate(f.key, Number(e.target.value))}
                          className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" />
                    </div>
                  ))}
                </div>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  {expFields.map(f => (
                    <div key={f.key}>
                      <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{f.label}</label>
                      <input type="number" value={String((editing as unknown as Record<string, number>)[f.key] ?? 0)} onChange={e => handleUpdate(f.key, Number(e.target.value))}
                          className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" />
                    </div>
                  ))}
                </div>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <div>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Followers</label>
                    <input type="number" value={editing.followers ?? 0} onChange={e => handleUpdate('followers', Number(e.target.value))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" />
                  </div>
                  <div>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Following</label>
                    <input type="number" value={editing.following ?? 0} onChange={e => handleUpdate('following', Number(e.target.value))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" />
                  </div>
                  <div>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Charm</label>
                    <input type="number" value={editing.charm ?? 0} onChange={e => handleUpdate('charm', Number(e.target.value))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" />
                  </div>
                  <div>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Total Gifts</label>
                    <input type="number" value={editing.totalGiftsReceived ?? 0} onChange={e => handleUpdate('totalGiftsReceived', Number(e.target.value))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" />
                  </div>
                </div>
              </div>
            )}

            {/* Tab: Currency */}
            {activeTab === 'currency' && (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label className="block text-[10px] uppercase text-amber-400 font-bold mb-1 flex items-center gap-1"><Coins className="w-3 h-3" /> Coins</label>
                  <div className="flex gap-1 mb-1">
                    <button onClick={() => handleUpdate('coins', editing.coins + 100)} className="px-2 py-1 bg-amber-500/10 text-amber-400 text-[10px] rounded hover:bg-amber-500/20">+100</button>
                    <button onClick={() => handleUpdate('coins', editing.coins + 1000)} className="px-2 py-1 bg-amber-500/10 text-amber-400 text-[10px] rounded hover:bg-amber-500/20">+1K</button>
                    <button onClick={() => handleUpdate('coins', editing.coins + 10000)} className="px-2 py-1 bg-amber-500/10 text-amber-400 text-[10px] rounded hover:bg-amber-500/20">+10K</button>
                    <button onClick={() => handleUpdate('coins', editing.coins + 100000)} className="px-2 py-1 bg-amber-500/10 text-amber-400 text-[10px] rounded hover:bg-amber-500/20">+100K</button>
                    <button onClick={() => handleUpdate('coins', editing.coins + 1000000)} className="px-2 py-1 bg-amber-500/10 text-amber-400 text-[10px] rounded hover:bg-amber-500/20">+1M</button>
                  </div>
                  <input type="number" value={String(editing.coins ?? 0)} onChange={e => handleUpdate('coins', Number(e.target.value))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" />
                </div>
                <div>
                  <label className="block text-[10px] uppercase text-cyan-400 font-bold mb-1 flex items-center gap-1"><Gem className="w-3 h-3" /> Diamonds</label>
                  <div className="flex gap-1 mb-1">
                    <button onClick={() => handleUpdate('diamonds', editing.diamonds + 10)} className="px-2 py-1 bg-cyan-500/10 text-cyan-400 text-[10px] rounded hover:bg-cyan-500/20">+10</button>
                    <button onClick={() => handleUpdate('diamonds', editing.diamonds + 100)} className="px-2 py-1 bg-cyan-500/10 text-cyan-400 text-[10px] rounded hover:bg-cyan-500/20">+100</button>
                    <button onClick={() => handleUpdate('diamonds', editing.diamonds + 1000)} className="px-2 py-1 bg-cyan-500/10 text-cyan-400 text-[10px] rounded hover:bg-cyan-500/20">+1K</button>
                    <button onClick={() => handleUpdate('diamonds', editing.diamonds + 10000)} className="px-2 py-1 bg-cyan-500/10 text-cyan-400 text-[10px] rounded hover:bg-cyan-500/20">+10K</button>
                  </div>
                  <input type="number" value={String(editing.diamonds ?? 0)} onChange={e => handleUpdate('diamonds', Number(e.target.value))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" />
                </div>
              </div>
            )}

            {/* Tab: Network & Ban */}
            {activeTab === 'network' && (
              <div className="space-y-6">
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1 flex items-center gap-1"><Phone className="w-3 h-3" /> Phone Number</label>
                    <input type="text" value={editing.phone || ''} onChange={e => handleUpdate('phone', e.target.value)} placeholder="e.g. +20123456789" className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  </div>
                  <div>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1 flex items-center gap-1"><Globe className="w-3 h-3" /> Last IP / Network</label>
                    <input type="text" value={editing.lastIp || ''} onChange={e => handleUpdate('lastIp', e.target.value)} placeholder="e.g. 192.168.1.1" className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  </div>
                </div>

                <div className="border-t border-white/5 pt-4">
                  <div className="flex items-center justify-between mb-3">
                    <h4 className="text-white text-xs font-semibold flex items-center gap-1.5"><Shield className="w-3.5 h-3.5" /> Ban Status</h4>
                    <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${editing.banned ? 'bg-red-500/20 text-red-400' : 'bg-emerald-500/20 text-emerald-400'}`}>
                      {editing.banned ? 'BANNED' : 'ACTIVE'}
                    </span>
                  </div>
                  {editing.banned && editing.banReason && (
                    <div className="mb-3 bg-red-500/5 border border-red-500/10 rounded-lg px-3 py-2">
                      <span className="text-[10px] text-red-400 font-semibold">Reason: </span>
                      <span className="text-[10px] text-slate-400">{editing.banReason}</span>
                    </div>
                  )}
                  <button onClick={() => { setShowBanDialog(true); setBanReason(editing.banReason || ''); }}
                    className={`px-4 py-1.5 text-xs font-semibold rounded-lg flex items-center gap-1.5 ${editing.banned ? 'bg-emerald-600 hover:bg-emerald-700 text-white' : 'bg-red-600 hover:bg-red-700 text-white'}`}>
                    <Ban className="w-3 h-3" /> {editing.banned ? 'Unban User' : 'Ban User'}
                  </button>
                </div>
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="flex gap-2 p-6 pt-4 border-t border-white/5">
            <button onClick={handleSaveAll} className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1"><Save className="w-3 h-3" /> Save All</button>
            <button onClick={() => { setEditing(null); setShowPasswordField(false); setNewPassword(''); }} className="px-4 py-1.5 border border-white/10 text-xs text-slate-400 rounded-lg">Close</button>
          </div>
        </div>
      )}

      {/* Ban Dialog */}
      {showBanDialog && editing && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50">
          <div className="bg-[#141417] rounded-2xl border border-white/10 p-6 w-full max-w-md mx-4">
            <h3 className="text-white font-semibold text-sm mb-3 flex items-center gap-2"><Ban className="w-4 h-4" /> {editing.banned ? 'Unban User' : 'Ban User'}</h3>
            {!editing.banned && (
              <div className="mb-4">
                <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Ban Reason</label>
                <input type="text" value={banReason} onChange={e => setBanReason(e.target.value)} placeholder="Enter reason for ban..." className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
              </div>
            )}
            <div className="flex gap-2">
              <button onClick={handleBan} className={`px-4 py-1.5 text-xs font-semibold rounded-lg ${editing.banned ? 'bg-emerald-600 hover:bg-emerald-700' : 'bg-red-600 hover:bg-red-700'} text-white`}>
                {editing.banned ? 'Yes, Unban' : 'Yes, Ban'}
              </button>
              <button onClick={() => setShowBanDialog(false)} className="px-4 py-1.5 border border-white/10 text-xs text-slate-400 rounded-lg">Cancel</button>
            </div>
          </div>
        </div>
      )}

      <DataTable
        loading={loading}
        columns={[
          { key: 'customId', label: 'ID', width: '70px', render: u => <span className="font-mono text-[10px] text-slate-400">{u.customId}</span> },
          { key: 'name', label: 'Name', sortable: true, render: u => (
            <div className="flex items-center gap-2">
              <div className="relative">
                {u.photoUrl ? <img src={u.photoUrl} className="w-6 h-6 rounded-full object-cover" onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }} /> : <div className="w-6 h-6 rounded-full bg-indigo-500/20 flex items-center justify-center text-[10px] text-indigo-400 font-bold">{u.name?.[0] || '?'}</div>}
                {u.banned && <div className="absolute -top-0.5 -right-0.5 w-2 h-2 bg-red-500 rounded-full" />}
              </div>
              <div>
                <div className="text-white text-xs">{u.name || 'Unnamed'}</div>
                <div className="text-[10px] text-slate-500">{u.email}</div>
              </div>
            </div>
          )},
          { key: 'level', label: 'Lv', sortable: true, width: '35px' },
          { key: 'coins', label: 'Coins', sortable: true, render: u => <span className="flex items-center gap-1 text-amber-400"><Coins className="w-3 h-3" />{u.coins?.toLocaleString()}</span> },
          { key: 'diamonds', label: 'Dia', sortable: true, render: u => <span className="flex items-center gap-1 text-cyan-400"><Gem className="w-3 h-3" />{u.diamonds?.toLocaleString()}</span> },
          { key: 'totalGiftsReceived', label: 'Gifts', sortable: true },
          { key: 'followers', label: 'Followers', sortable: true },
          { key: 'charm', label: 'Charm', sortable: true },
          { key: 'banned', label: 'Status', width: '60px', render: u => u.banned ? <span className="text-red-400 text-[10px] font-bold">BANNED</span> : <span className="text-emerald-400 text-[10px]">Active</span> },
        ]}
        data={visibleUsers}
        searchKeys={['name', 'email', 'uid', 'customId']}
        onEdit={(u) => setEditing(u)}
        onDelete={handleDelete}
      />
    </div>
  );
}
