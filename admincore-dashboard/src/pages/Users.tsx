import { useEffect, useState } from 'react';
import { UserModel } from '../types';
import { getUsers, deleteUser, updateUser, updateUserPassword, getAuthUsers, getAuthUser, syncAllAuthUsersToDB, sendSystemNotification, adjustUserDiamonds, getUserDiamondLogs } from '../lib/db';
import { uploadUserPhoto } from '../lib/storage';
import DataTable from '../components/DataTable';
import ImageUpload from '../components/ImageUpload';
import { Coins, Gem, X, Save, Search, Ban, Shield, Phone, Globe, Key, Ruler, ChevronDown, RefreshCw, AlertTriangle, CheckCircle, ArrowRightCircle, PlusCircle, MinusCircle, History } from 'lucide-react';
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
  const [rechargeInput, setRechargeInput] = useState('1');

  // Diamond Management States
  const [diamondMode, setDiamondMode] = useState<'add' | 'deduct'>('add');
  const [diamondAmount, setDiamondAmount] = useState<string>('10000');
  const [diamondReason, setDiamondReason] = useState<string>('');
  const [diamondLogs, setDiamondLogs] = useState<any[]>([]);
  const [loadingDiamondLogs, setLoadingDiamondLogs] = useState<boolean>(false);
  const [diamondConfirmOpen, setDiamondConfirmOpen] = useState<boolean>(false);
  const [diamondSubmitting, setDiamondSubmitting] = useState<boolean>(false);

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

  const handleRechargeUserCoins = async (amount: number) => {
    if (!editing || amount <= 0) return;
    try {
      const currentCoins = Number(editing.coins || 0);
      const newCoins = currentCoins + amount;
      await updateUser(editing.uid, { coins: newCoins });
      const updated = { ...editing, coins: newCoins };
      setEditing(updated);
      setUsers(prev => prev.map(u => u.uid === editing.uid ? updated : u));
      await sendSystemNotification({
        userId: editing.uid,
        title: '🪙 شحن رصيد عملات لحسابك',
        body: `مبروك! تم شحن ${amount.toLocaleString()} عملة ذهبية لحسابك بنجاح من قبل الإدارة. رصيدك الحالي الآن: ${newCoins.toLocaleString()} عملة.`,
        type: 'system',
        action: 'coins_recharged',
        extraData: { amount, new_balance: newCoins },
      });
      showMsg(`✅ تم شحن ${amount.toLocaleString()} كوينز للمستخدم وإرسال إشعار فوري له بنجاح!`);
    } catch (e: any) {
      showMsg('⚠️ فشل الشحن: ' + (e?.message || e));
    }
  };

  useEffect(() => {
    if (editing?.uid && activeTab === 'currency') {
      setLoadingDiamondLogs(true);
      getUserDiamondLogs(editing.uid).then(logs => {
        setDiamondLogs(logs);
        setLoadingDiamondLogs(false);
      });
    }
  }, [editing?.uid, activeTab]);

  const handleExecuteDiamondAdjustment = async () => {
    if (!editing) return;
    const amt = parseInt(diamondAmount) || 0;
    if (amt <= 0) {
      alert('الرجاء إدخال كمية صالحة أكبر من صفر');
      return;
    }
    setDiamondSubmitting(true);
    try {
      const res = await adjustUserDiamonds(
        editing.uid,
        amt,
        diamondMode,
        diamondReason,
        'المدير العام'
      );
      if (res.success) {
        const updated = { ...editing, diamonds: res.newDiamonds };
        setEditing(updated);
        setUsers(prev => prev.map(u => u.uid === editing.uid ? updated : u));
        showMsg(`✅ تم ${diamondMode === 'add' ? 'إضافة' : 'خصم'} ${amt.toLocaleString()} ماسة بنجاح وتحديث بيانات الوكالة!`);
        setDiamondConfirmOpen(false);
        setDiamondReason('');
        getUserDiamondLogs(editing.uid).then(logs => setDiamondLogs(logs));
      } else {
        alert('⚠️ فشلت العملية: ' + (res.error || 'خطأ غير معروف'));
      }
    } catch (err: any) {
      alert('⚠️ خطأ: ' + (err?.message || err));
    } finally {
      setDiamondSubmitting(false);
    }
  };

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
      showMsg('تم الحفظ بنجاح!');
    } catch (e: unknown) {
      const err = e as { message?: string };
      const errMsg = err?.message || 'Update failed';
      alert('⚠️ ' + errMsg);
      showMsg('⚠️ ' + errMsg);
      // Reload user data to revert uncommitted change
      loadUsers();
    }
  };

  const handleSaveAll = async () => {
    if (!editing) return;
    try {
      await updateUser(editing.uid, editing);
      setUsers(prev => prev.map(u => u.uid === editing.uid ? editing : u));
      showMsg('تم الحفظ بنجاح!');
    } catch (e: unknown) {
      const err = e as { message?: string };
      const errMsg = err?.message || 'Save failed';
      alert('⚠️ ' + errMsg);
      showMsg('⚠️ ' + errMsg);
      loadUsers();
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

  const [banDurationDays, setBanDurationDays] = useState<number>(7);

  const handleBan = async () => {
    if (!editing) return;
    const nowBanned = !editing.banned;
    let bannedUntil: string | null = null;
    let bannedAt: string | null = null;
    const duration = banDurationDays;

    if (nowBanned) {
      bannedAt = new Date().toISOString();
      if (duration > 0) {
        bannedUntil = new Date(Date.now() + duration * 24 * 60 * 60 * 1000).toISOString();
      } else {
        bannedUntil = null; // Permanent
      }
    }

    const banPayload = {
      banned: nowBanned,
      banReason: nowBanned ? (banReason || 'انتهاك شروط الاستخدام') : '',
      banDurationDays: nowBanned ? duration : 0,
      bannedAt: bannedAt ?? undefined,
      bannedUntil: bannedUntil,
    };

    await updateUser(editing.uid, banPayload);
    const updated = { ...editing, ...banPayload };
    setEditing(updated);
    setUsers(prev => prev.map(u => u.uid === editing.uid ? updated : u));
    setShowBanDialog(false);
    setBanReason('');
    showMsg(nowBanned ? (duration > 0 ? `تم حظر المستخدم لمدة ${duration} يوماً` : 'تم حظر المستخدم بشكل دائم') : 'تم إلغاء حظر المستخدم');
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
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Custom ID (الآيدي المميز)</label>
                  <div className="flex gap-1.5">
                    <input
                      type="text"
                      value={editing.customId || ''}
                      onChange={e => setEditing({ ...editing, customId: e.target.value })}
                      onKeyDown={e => { if (e.key === 'Enter') handleUpdate('customId', editing.customId); }}
                      placeholder="e.g. 1, 100, 777"
                      className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono"
                    />
                    <button
                      type="button"
                      onClick={() => handleUpdate('customId', editing.customId)}
                      className="px-2.5 py-1 bg-indigo-600 hover:bg-indigo-700 text-[11px] text-white rounded-lg whitespace-nowrap"
                    >
                      تحديث
                    </button>
                  </div>
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
              <div className="space-y-6">
                {/* Recharge Box */}
                <div className="bg-amber-500/10 border border-amber-500/20 rounded-xl p-4 space-y-3">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-bold text-amber-400 flex items-center gap-1.5">
                      <Coins className="w-4 h-4" /> شحن رصيد كوينز للمستخدم مع إرسال إشعار فوري (1 عملة = 1 عملة)
                    </span>
                    <span className="text-[11px] text-slate-400">
                      الرصيد الحالي: <strong className="text-amber-300 font-mono">{(editing.coins ?? 0).toLocaleString()}</strong> 🪙
                    </span>
                  </div>
                  <div className="flex flex-wrap items-center gap-2">
                    {[1, 10, 100, 1000, 10000, 50000, 100000].map(val => (
                      <button
                        key={val}
                        onClick={() => handleRechargeUserCoins(val)}
                        className="px-2.5 py-1 bg-amber-500/20 hover:bg-amber-500/30 text-amber-300 text-xs font-semibold rounded-lg transition-colors"
                      >
                        +{val >= 1000 ? `${val / 1000}K` : val}
                      </button>
                    ))}
                  </div>
                  <div className="flex items-center gap-2 pt-1">
                    <input
                      type="number"
                      min="1"
                      value={rechargeInput}
                      onChange={e => setRechargeInput(e.target.value)}
                      placeholder="كمية الشحن المخصصة (مثال: 1)"
                      className="w-48 bg-[#161618] border border-amber-500/30 rounded-lg py-1.5 px-3 text-xs text-white font-mono"
                    />
                    <button
                      onClick={() => {
                        const amt = parseInt(rechargeInput) || 0;
                        if (amt > 0) handleRechargeUserCoins(amt);
                      }}
                      className="px-4 py-1.5 bg-amber-600 hover:bg-amber-700 text-white text-xs font-bold rounded-lg shadow-md transition-colors"
                    >
                      تأكيد الشحن فوراً 🪙
                    </button>
                  </div>
                </div>

                {/* Diamond Management & History Section */}
                <div className="bg-[#121215] border border-cyan-500/20 rounded-2xl p-5 space-y-4 shadow-xl">
                  <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-white/5 pb-3">
                    <div className="flex items-center gap-2">
                      <div className="p-2 bg-cyan-500/10 text-cyan-400 rounded-xl">
                        <Gem className="w-5 h-5" />
                      </div>
                      <div>
                        <h4 className="text-sm font-bold text-white flex items-center gap-2">
                          إدارة وشحن ألماس المستخدم والوكالة
                        </h4>
                        <p className="text-[11px] text-slate-400">
                          يتم مزامنة أي إضافة أو خصم تلقائياً مع وكالة المضيف وتوثيقها في السجل
                        </p>
                      </div>
                    </div>
                    <div className="flex items-center gap-2 bg-black/40 border border-white/5 px-3 py-1.5 rounded-xl self-start sm:self-auto">
                      <span className="text-[11px] text-slate-400">الرصيد الحالي:</span>
                      <span className="text-cyan-300 font-bold font-mono text-sm flex items-center gap-1">
                        {(editing.diamonds ?? 0).toLocaleString()} 💎
                      </span>
                    </div>
                  </div>

                  <div className="grid grid-cols-1 lg:grid-cols-12 gap-5">
                    {/* Left: Adjustment Controls */}
                    <div className="lg:col-span-7 space-y-4">
                      {/* Operation Type Toggle */}
                      <div>
                        <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1.5">
                          نوع العملية
                        </label>
                        <div className="grid grid-cols-2 gap-2">
                          <button
                            type="button"
                            onClick={() => setDiamondMode('add')}
                            className={`py-2 px-3 rounded-xl text-xs font-bold flex items-center justify-center gap-2 transition-all ${
                              diamondMode === 'add'
                                ? 'bg-emerald-600 text-white shadow-lg shadow-emerald-600/30 border border-emerald-500'
                                : 'bg-white/5 text-slate-400 hover:bg-white/10 border border-white/5'
                            }`}
                          >
                            <PlusCircle className="w-4 h-4" />
                            إضافة ألماس (+)
                          </button>
                          <button
                            type="button"
                            onClick={() => setDiamondMode('deduct')}
                            className={`py-2 px-3 rounded-xl text-xs font-bold flex items-center justify-center gap-2 transition-all ${
                              diamondMode === 'deduct'
                                ? 'bg-red-600 text-white shadow-lg shadow-red-600/30 border border-red-500'
                                : 'bg-white/5 text-slate-400 hover:bg-white/10 border border-white/5'
                            }`}
                          >
                            <MinusCircle className="w-4 h-4" />
                            خصم / سحب ألماس (-)
                          </button>
                        </div>
                      </div>

                      {/* Quick Amount Buttons */}
                      <div>
                        <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1.5 flex items-center justify-between">
                          <span>مبالغ سريعة (10K إلى 100M)</span>
                          <span className="text-[10px] text-cyan-400 font-mono">
                            المحدد: {Number(diamondAmount || 0).toLocaleString()} 💎
                          </span>
                        </label>
                        <div className="flex flex-wrap gap-1.5">
                          {[
                            { label: '10K', value: 10000 },
                            { label: '50K', value: 50000 },
                            { label: '100K', value: 100000 },
                            { label: '500K', value: 500000 },
                            { label: '1M', value: 1000000 },
                            { label: '10M', value: 10000000 },
                            { label: '100M', value: 100000000 },
                          ].map(item => (
                            <button
                              key={item.label}
                              type="button"
                              onClick={() => setDiamondAmount(String(item.value))}
                              className={`px-3 py-1.5 rounded-lg text-xs font-mono font-bold transition-all ${
                                diamondAmount === String(item.value)
                                  ? 'bg-cyan-500 text-black shadow-md shadow-cyan-500/20'
                                  : 'bg-white/5 text-cyan-300 hover:bg-cyan-500/20 border border-cyan-500/20'
                              }`}
                            >
                              {diamondMode === 'add' ? `+${item.label}` : `-${item.label}`}
                            </button>
                          ))}
                        </div>
                      </div>

                      {/* Custom Amount Input */}
                      <div>
                        <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">
                          كمية الألماس المخصصة
                        </label>
                        <div className="relative">
                          <input
                            type="number"
                            min="1"
                            value={diamondAmount}
                            onChange={e => setDiamondAmount(e.target.value)}
                            placeholder="أدخل كمية الألماس..."
                            className="w-full bg-[#161618] border border-cyan-500/30 rounded-xl py-2 px-3 pl-16 text-sm text-white font-mono focus:border-cyan-400 focus:outline-none"
                          />
                          <div className="absolute left-3 top-2.5 text-xs text-cyan-400 font-bold">
                            ماسة 💎
                          </div>
                        </div>
                      </div>

                      {/* Reason & Presets */}
                      <div>
                        <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">
                          سبب العملية وملاحظات (تظهر في السجل)
                        </label>
                        <div className="flex flex-wrap gap-1 mb-2">
                          {[
                            'شحن ماس إداري',
                            'مكافأة تارجت مضيف',
                            'تصحيح رصيد بالوكالة',
                            'خصم مخالفة إدارية',
                            'تسوية حساب الوكالة',
                          ].map(r => (
                            <button
                              key={r}
                              type="button"
                              onClick={() => setDiamondReason(r)}
                              className="px-2 py-0.5 rounded-md bg-white/5 hover:bg-white/10 text-[10px] text-slate-300 border border-white/5"
                            >
                              {r}
                            </button>
                          ))}
                        </div>
                        <input
                          type="text"
                          value={diamondReason}
                          onChange={e => setDiamondReason(e.target.value)}
                          placeholder="اكتب سبب العملية أو اختر من الأعلى..."
                          className="w-full bg-[#161618] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:border-white/20 focus:outline-none"
                        />
                      </div>

                      {/* Confirmation Trigger Button */}
                      <div className="pt-2">
                        <button
                          type="button"
                          onClick={() => {
                            const amt = parseInt(diamondAmount) || 0;
                            if (amt <= 0) {
                              alert('يرجى تحديد كمية ألماس صالحة أكبر من 0');
                              return;
                            }
                            setDiamondConfirmOpen(true);
                          }}
                          className={`w-full py-2.5 px-4 rounded-xl text-xs font-bold text-white shadow-lg transition-all flex items-center justify-center gap-2 ${
                            diamondMode === 'add'
                              ? 'bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-500 hover:to-teal-500 shadow-emerald-600/30'
                              : 'bg-gradient-to-r from-red-600 to-rose-600 hover:from-red-500 hover:to-rose-500 shadow-red-600/30'
                          }`}
                        >
                          <Gem className="w-4 h-4" />
                          <span>
                            زر تأكيد الإرسال ({diamondMode === 'add' ? 'إضافة' : 'خصم'}{' '}
                            {Number(diamondAmount || 0).toLocaleString()} 💎)
                          </span>
                        </button>
                      </div>
                    </div>

                    {/* Right: Transaction History Log Table */}
                    <div className="lg:col-span-5 flex flex-col bg-black/40 border border-white/5 rounded-xl p-3.5">
                      <div className="flex items-center justify-between border-b border-white/5 pb-2 mb-2.5">
                        <div className="flex items-center gap-1.5 text-xs font-bold text-slate-200">
                          <History className="w-4 h-4 text-cyan-400" />
                          <span>سجل إضافة وخصم الماس</span>
                          <span className="text-[10px] bg-white/10 text-slate-400 px-1.5 py-0.5 rounded-full font-mono">
                            {diamondLogs.length}
                          </span>
                        </div>
                        <button
                          type="button"
                          onClick={() => {
                            if (editing?.uid) {
                              setLoadingDiamondLogs(true);
                              getUserDiamondLogs(editing.uid).then(logs => {
                                setDiamondLogs(logs);
                                setLoadingDiamondLogs(false);
                              });
                            }
                          }}
                          className="p-1 hover:bg-white/10 text-slate-400 hover:text-white rounded transition-colors"
                          title="تحديث السجل"
                        >
                          <RefreshCw className={`w-3.5 h-3.5 ${loadingDiamondLogs ? 'animate-spin text-cyan-400' : ''}`} />
                        </button>
                      </div>

                      <div className="flex-1 overflow-y-auto max-h-[340px] space-y-2 pr-1">
                        {loadingDiamondLogs ? (
                          <div className="py-8 text-center text-xs text-slate-500 flex flex-col items-center gap-2">
                            <RefreshCw className="w-5 h-5 animate-spin text-cyan-400" />
                            <span>جاري تحميل سجل الألماس...</span>
                          </div>
                        ) : diamondLogs.length === 0 ? (
                          <div className="py-8 text-center text-xs text-slate-500">
                            لا توجد عمليات ماس مسجلة لهذا الحساب حتى الآن
                          </div>
                        ) : (
                          diamondLogs.map(log => {
                            const isAdd = log.type === 'add' || log.type === 'admin_add' || log.type === 'credit' || log.type === 'deposit' || Number(log.amount) > 0;
                            const absAmount = Math.abs(Number(log.amount || 0));
                            return (
                              <div
                                key={log.id}
                                className="bg-white/5 hover:bg-white/[0.07] border border-white/5 rounded-lg p-2.5 text-xs transition-colors space-y-1"
                              >
                                <div className="flex items-center justify-between">
                                  <span
                                    className={`px-1.5 py-0.5 rounded text-[10px] font-bold font-mono ${
                                      isAdd
                                        ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                                        : 'bg-red-500/20 text-red-300 border border-red-500/30'
                                    }`}
                                  >
                                    {isAdd ? '+' : '-'}{absAmount.toLocaleString()} 💎
                                  </span>
                                  <span className="text-[10px] text-slate-500">
                                    {new Date(log.created_at).toLocaleDateString('ar-EG', {
                                      month: 'short',
                                      day: 'numeric',
                                      hour: '2-digit',
                                      minute: '2-digit',
                                    })}
                                  </span>
                                </div>
                                <div className="flex items-center justify-between text-[11px] text-slate-300">
                                  <span className="truncate max-w-[150px] text-slate-300">
                                    {log.reason || log.notes || 'تعديل رصيد'}
                                  </span>
                                  {log.balance_after != null && (
                                    <span className="text-[10px] text-slate-400 font-mono">
                                      بعد: {Number(log.balance_after).toLocaleString()}
                                    </span>
                                  )}
                                </div>
                                {log.created_by && (
                                  <div className="text-[9px] text-slate-500 text-left font-mono">
                                    بواسطة: {log.created_by}
                                  </div>
                                )}
                              </div>
                            );
                          })
                        )}
                      </div>
                    </div>
                  </div>
                </div>

                {/* Manual Coins Edit Box */}
                <div className="bg-white/5 border border-white/10 rounded-xl p-4">
                  <label className="block text-[10px] uppercase text-amber-400 font-bold mb-1.5 flex items-center gap-1.5">
                    <Coins className="w-3.5 h-3.5" /> تعديل الرصيد الإجمالي للعملات يدوياً (Coins)
                  </label>
                  <div className="flex gap-2">
                    <input
                      type="number"
                      value={String(editing.coins ?? 0)}
                      onChange={e => {
                        const val = Number(e.target.value);
                        setEditing(prev => prev ? { ...prev, coins: val } : null);
                      }}
                      onKeyDown={e => {
                        if (e.key === 'Enter') {
                          handleUpdate('coins', Number(editing.coins ?? 0));
                        }
                      }}
                      className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white font-mono focus:border-amber-500/40 focus:outline-none"
                    />
                    <button
                      type="button"
                      onClick={() => handleUpdate('coins', Number(editing.coins ?? 0))}
                      className="px-3 py-1.5 bg-amber-600 hover:bg-amber-700 text-white text-xs font-semibold rounded-lg whitespace-nowrap"
                    >
                      حفظ العملات
                    </button>
                  </div>
                </div>
              </div>
            )}

            {/* Tab: Network & Ban */}
            {activeTab === 'network' && (
              <div className="space-y-5">
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                  <div>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1 flex items-center gap-1"><Phone className="w-3 h-3" /> Phone Number</label>
                    <input type="text" value={editing.phone || ''} onChange={e => handleUpdate('phone', e.target.value)} placeholder="e.g. +20123456789" className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  </div>
                  <div>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1 flex items-center gap-1"><Globe className="w-3 h-3" /> Last IP / Network</label>
                    <input type="text" value={editing.lastIp || ''} onChange={e => handleUpdate('lastIp', e.target.value)} placeholder="e.g. 192.168.1.1" className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  </div>
                </div>

                {/* Device & Hardware Info */}
                <div className="bg-black/30 border border-white/10 rounded-xl p-3.5 space-y-3">
                  <h4 className="text-xs font-bold text-slate-300 flex items-center gap-1.5">
                    📱 بيانات الهاتف والشبكة (Device Fingerprint)
                  </h4>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5 text-xs">
                    <div className="bg-white/5 p-2 rounded-lg">
                      <div className="text-[10px] text-slate-400">موديل الهاتف (Device Model):</div>
                      <div className="text-white font-medium truncate">{editing.deviceModel || 'غير متوفر'}</div>
                    </div>
                    <div className="bg-white/5 p-2 rounded-lg">
                      <div className="text-[10px] text-slate-400">معرف الهاتف (Device ID):</div>
                      <div className="text-white font-mono text-[11px] truncate">{editing.deviceId || 'غير مربوط'}</div>
                    </div>
                    <div className="bg-white/5 p-2 rounded-lg">
                      <div className="text-[10px] text-slate-400">المعرف الفيزيائي (Hardware MAC):</div>
                      <div className="text-white font-mono text-[11px] truncate">{editing.macAddress || 'غير متوفر'}</div>
                    </div>
                    <div className="bg-white/5 p-2 rounded-lg">
                      <div className="text-[10px] text-slate-400">معرف الشبكة والاتصال (Network ID):</div>
                      <div className="text-white font-mono text-[11px] truncate">{editing.networkId || editing.lastIp || 'غير متوفر'}</div>
                    </div>
                  </div>

                  {/* Device Accounts Count & Listing */}
                  {(() => {
                    const dId = editing.deviceId;
                    const sameDeviceUsers = dId ? users.filter(u => u.deviceId === dId) : [];
                    return (
                      <div className="pt-2 border-t border-white/5 space-y-2">
                        <div className="flex items-center justify-between">
                          <span className="text-xs font-bold text-white flex items-center gap-1.5">
                            👥 عدد الحسابات المسجلة من نفس هذا الهاتف:
                          </span>
                          {!dId ? (
                            <span className="text-[11px] font-medium px-2 py-0.5 rounded-full bg-slate-500/20 text-slate-400 border border-slate-500/30">
                              بانتظار تسجيل البصمة عند فتح التطبيق
                            </span>
                          ) : (
                            <span className={`text-[11px] font-bold px-2 py-0.5 rounded-full ${sameDeviceUsers.length >= 2 ? 'bg-amber-500/20 text-amber-400 border border-amber-500/30' : 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'}`}>
                              {sameDeviceUsers.length > 0 ? `${sameDeviceUsers.length} / 2 حسابات` : 'حساب واحد'}
                            </span>
                          )}
                        </div>
                        {sameDeviceUsers.length > 0 ? (
                          <div className="space-y-1.5">
                            {sameDeviceUsers.map(du => (
                              <div key={du.uid} className="flex items-center justify-between text-xs p-2 rounded-lg bg-white/5 border border-white/5">
                                <div className="flex items-center gap-2">
                                  <span className="text-white font-medium">{du.name}</span>
                                  <span className="text-slate-400 font-mono text-[11px]">({du.email || 'بدون بريد'})</span>
                                </div>
                                {du.uid === editing.uid ? (
                                  <span className="text-[10px] text-amber-400 font-bold bg-amber-500/10 px-2 py-0.5 rounded">الحساب الحالي</span>
                                ) : (
                                  <span className="text-[10px] text-slate-400 bg-white/5 px-2 py-0.5 rounded">حساب مرتبط بنفس الهاتف</span>
                                )}
                              </div>
                            ))}
                          </div>
                        ) : null}
                      </div>
                    );
                  })()}
                </div>

                <div className="border-t border-white/5 pt-4">
                  <div className="flex items-center justify-between mb-3">
                    <h4 className="text-white text-xs font-semibold flex items-center gap-1.5"><Shield className="w-3.5 h-3.5" /> حالة الحظر (Ban Status)</h4>
                    <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${editing.banned ? 'bg-red-500/20 text-red-400 border border-red-500/30' : 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'}`}>
                      {editing.banned ? 'محظور (BANNED)' : 'نشط (ACTIVE)'}
                    </span>
                  </div>
                  {editing.banned && (
                    <div className="mb-3 bg-red-500/5 border border-red-500/20 rounded-xl p-3 space-y-1.5 text-xs">
                      <div>
                        <span className="text-red-400 font-bold">سبب الحظر: </span>
                        <span className="text-slate-300">{editing.banReason || 'غير محدد'}</span>
                      </div>
                      <div>
                        <span className="text-red-400 font-bold">المدة: </span>
                        <span className="text-slate-300">
                          {editing.banDurationDays && editing.banDurationDays > 0 ? `${editing.banDurationDays} يوماً` : 'حظر دائم ونهائي'}
                        </span>
                      </div>
                      {editing.bannedUntil && (
                        <div>
                          <span className="text-red-400 font-bold">تاريخ انتهاء الحظر: </span>
                          <span className="text-slate-300 font-mono">{new Date(editing.bannedUntil).toLocaleDateString('ar-EG', { dateStyle: 'full' })}</span>
                        </div>
                      )}
                    </div>
                  )}
                  <button onClick={() => { setShowBanDialog(true); setBanReason(editing.banReason || ''); setBanDurationDays(editing.banDurationDays || 7); }}
                    className={`px-4 py-2 text-xs font-semibold rounded-lg flex items-center gap-1.5 ${editing.banned ? 'bg-emerald-600 hover:bg-emerald-700 text-white' : 'bg-red-600 hover:bg-red-700 text-white'}`}>
                    <Ban className="w-3 h-3" /> {editing.banned ? 'إلغاء حظر المستخدم (Unban)' : 'حظر المستخدم وتحديد المدة (Ban)'}
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
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center z-50">
          <div className="bg-[#141417] rounded-2xl border border-white/10 p-6 w-full max-w-lg mx-4 space-y-4">
            <h3 className="text-white font-semibold text-sm flex items-center gap-2">
              <Ban className="w-4 h-4 text-red-400" />
              {editing.banned ? 'إلغاء حظر المستخدم' : 'حظر المستخدم وتحديد المدة والسبب'}
            </h3>

            {!editing.banned ? (
              <div className="space-y-4">
                {/* Duration Presets */}
                <div>
                  <label className="block text-[11px] uppercase text-slate-400 font-bold mb-1.5">
                    مدة الحظر بالأيام (Ban Duration):
                  </label>
                  <div className="grid grid-cols-4 gap-2">
                    {[
                      { days: 1, label: '24 ساعة' },
                      { days: 3, label: '3 أيام' },
                      { days: 7, label: 'أسبوع' },
                      { days: 15, label: '15 يوماً' },
                      { days: 30, label: 'شهر' },
                      { days: 90, label: '3 أشهر' },
                      { days: 0, label: 'حظر دائم' },
                    ].map(p => (
                      <button
                        key={p.days}
                        type="button"
                        onClick={() => setBanDurationDays(p.days)}
                        className={`p-2 rounded-xl text-xs font-bold border transition-all ${
                          banDurationDays === p.days
                            ? 'bg-red-500/20 border-red-500 text-red-400'
                            : 'bg-white/5 border-white/5 text-slate-400 hover:text-white'
                        }`}
                      >
                        {p.label}
                      </button>
                    ))}
                  </div>

                  <div className="mt-2 flex items-center gap-2">
                    <span className="text-[11px] text-slate-400">أو عدد أيام مخصص:</span>
                    <input
                      type="number"
                      min="0"
                      value={banDurationDays}
                      onChange={e => setBanDurationDays(parseInt(e.target.value) || 0)}
                      className="w-24 bg-[#161618] border border-white/10 rounded-lg py-1 px-2 text-xs text-white font-mono"
                    />
                    <span className="text-[11px] text-slate-500">(0 = دائم)</span>
                  </div>
                </div>

                {/* Reason Presets */}
                <div>
                  <label className="block text-[11px] uppercase text-slate-400 font-bold mb-1.5">
                    سبب الحظر (Ban Reason):
                  </label>
                  <div className="flex flex-wrap gap-1.5 mb-2">
                    {[
                      'انتهاك شروط الاستخدام',
                      'محاولة شحن احتيالية',
                      'سلوك غير لائق أو سب وقذف',
                      'حساب متعدد مخالف لنفس الهاتف',
                    ].map(r => (
                      <button
                        key={r}
                        type="button"
                        onClick={() => setBanReason(r)}
                        className="px-2 py-1 rounded-lg bg-white/5 hover:bg-white/10 text-[10px] text-slate-300 border border-white/5"
                      >
                        {r}
                      </button>
                    ))}
                  </div>
                  <input
                    type="text"
                    value={banReason}
                    onChange={e => setBanReason(e.target.value)}
                    placeholder="اكتب سبب الحظر المخصص..."
                    className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white"
                  />
                </div>
              </div>
            ) : (
              <p className="text-xs text-slate-300">
                هل أنت متأكد من إلغاء الحظر عن هذا المستخدم وإعادة تفعيل حسابه فوراً؟
              </p>
            )}

            <div className="flex justify-end gap-2 pt-2 border-t border-white/5">
              <button
                onClick={() => setShowBanDialog(false)}
                className="px-4 py-1.5 border border-white/10 text-xs text-slate-400 rounded-lg hover:bg-white/5"
              >
                إلغاء
              </button>
              <button
                onClick={handleBan}
                className={`px-5 py-1.5 text-xs font-bold rounded-lg ${editing.banned ? 'bg-emerald-600 hover:bg-emerald-700' : 'bg-red-600 hover:bg-red-700'} text-white shadow-lg`}
              >
                {editing.banned ? 'تأكيد إلغاء الحظر' : 'تأكيد الحظر'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Diamond Adjustment Confirmation Modal */}
      {diamondConfirmOpen && editing && (
        <div className="fixed inset-0 bg-black/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-[#18181b] border border-cyan-500/30 rounded-2xl max-w-md w-full p-6 space-y-4 shadow-2xl">
            <div className="flex items-center justify-between border-b border-white/10 pb-3">
              <div className="flex items-center gap-2">
                <div className={`p-2 rounded-xl ${diamondMode === 'add' ? 'bg-emerald-500/20 text-emerald-400' : 'bg-red-500/20 text-red-400'}`}>
                  <Gem className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="text-sm font-bold text-white">تأكيد عملية الألماس</h3>
                  <p className="text-[11px] text-slate-400">يرجى مراجعة تفاصيل العملية قبل التأكيد</p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setDiamondConfirmOpen(false)}
                className="text-slate-400 hover:text-white"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="bg-black/40 border border-white/5 rounded-xl p-3.5 space-y-2 text-xs">
              <div className="flex justify-between items-center py-1 border-b border-white/5">
                <span className="text-slate-400">المستخدم:</span>
                <span className="text-white font-medium">{editing.name} (#{editing.customId})</span>
              </div>
              <div className="flex justify-between items-center py-1 border-b border-white/5">
                <span className="text-slate-400">نوع العملية:</span>
                <span className={`font-bold px-2 py-0.5 rounded text-[10px] ${
                  diamondMode === 'add' ? 'bg-emerald-500/20 text-emerald-300' : 'bg-red-500/20 text-red-300'
                }`}>
                  {diamondMode === 'add' ? '➕ إضافة رصيد ألماس' : '➖ خصم / سحب ألماس'}
                </span>
              </div>
              <div className="flex justify-between items-center py-1 border-b border-white/5">
                <span className="text-slate-400">الكمية:</span>
                <span className="text-cyan-300 font-bold font-mono text-sm">
                  {Number(diamondAmount || 0).toLocaleString()} 💎
                </span>
              </div>
              <div className="flex justify-between items-center py-1 border-b border-white/5">
                <span className="text-slate-400">الرصيد الحالي:</span>
                <span className="text-slate-300 font-mono">
                  {(editing.diamonds ?? 0).toLocaleString()} 💎
                </span>
              </div>
              <div className="flex justify-between items-center py-1 border-b border-white/5">
                <span className="text-slate-400">الرصيد بعد التنفيذ:</span>
                <span className="text-emerald-300 font-bold font-mono">
                  {(diamondMode === 'add'
                    ? (editing.diamonds ?? 0) + (parseInt(diamondAmount) || 0)
                    : Math.max(0, (editing.diamonds ?? 0) - (parseInt(diamondAmount) || 0))
                  ).toLocaleString()} 💎
                </span>
              </div>
              {diamondReason && (
                <div className="flex justify-between items-center py-1">
                  <span className="text-slate-400">السبب / الملاحظة:</span>
                  <span className="text-slate-200">{diamondReason}</span>
                </div>
              )}
            </div>

            <div className="p-2.5 rounded-lg bg-cyan-500/10 border border-cyan-500/20 text-[11px] text-cyan-300 flex items-start gap-2">
              <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5 text-cyan-400" />
              <span>
                سيتم حفظ العملية في السجل وتحديث رصيد المضيف، ومزامنة إجماليات وكالة المضيف التابع لها المستخدم تلقائياً.
              </span>
            </div>

            <div className="flex justify-end gap-2 pt-2 border-t border-white/5">
              <button
                type="button"
                disabled={diamondSubmitting}
                onClick={() => setDiamondConfirmOpen(false)}
                className="px-4 py-2 border border-white/10 text-xs text-slate-400 rounded-xl hover:bg-white/5 disabled:opacity-50"
              >
                إلغاء
              </button>
              <button
                type="button"
                disabled={diamondSubmitting}
                onClick={handleExecuteDiamondAdjustment}
                className={`px-5 py-2 text-xs font-bold rounded-xl text-white shadow-lg flex items-center gap-1.5 disabled:opacity-50 ${
                  diamondMode === 'add'
                    ? 'bg-emerald-600 hover:bg-emerald-700 shadow-emerald-600/30'
                    : 'bg-red-600 hover:bg-red-700 shadow-red-600/30'
                }`}
              >
                {diamondSubmitting && <RefreshCw className="w-3.5 h-3.5 animate-spin" />}
                {diamondSubmitting ? 'جاري التنفيذ...' : 'تأكيد الإرسال الآن'}
              </button>
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
