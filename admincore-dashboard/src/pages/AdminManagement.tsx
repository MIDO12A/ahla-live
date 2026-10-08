import { useEffect, useState, useContext } from 'react';
import { I18nContext } from '../lib/i18n';
import { getAdminSupabase } from '../lib/supabase';
import type { AppUser } from '../lib/auth';
import {
  Shield, ShieldOff, UserPlus, Trash2, Ban, CheckCircle, XCircle,
  Search, Save, X, RefreshCw,
  Camera, AlertTriangle, FileText, CheckSquare, Square, Check,
} from 'lucide-react';
import {
  getAdminUsers, createAdminUser, updateAdminUser, deleteAdminUser,
  getAdminActionLogs, clearActionLogs, logAdminAction,
  getDashboardBans, banFromDashboard, unbanFromDashboard, searchUserProfile,
  getBadges, getNecklaces,
} from '../lib/db';
import {
  PERMISSION_CATEGORIES, ALL_PERMISSIONS,
  getAllPermissionsMap, getDefaultPermissionsForRole,
} from '../lib/permissions';
import type { AdminUser, AdminActionLog, DashboardBan } from '../types';

export default function AdminManagement({ currentUser }: { currentUser: AppUser | null }) {
  const { t, lang } = useContext(I18nContext);
  const isAr = lang === 'ar';
  const [tab, setTab] = useState<'admins' | 'logs' | 'bans' | 'profile'>('admins');
  const [admins, setAdmins] = useState<AdminUser[]>([]);
  const [logs, setLogs] = useState<AdminActionLog[]>([]);
  const [bans, setBans] = useState<DashboardBan[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQ, setSearchQ] = useState('');

  const [availableBadges, setAvailableBadges] = useState<any[]>([]);
  const [availableNecklaces, setAvailableNecklaces] = useState<any[]>([]);

  const [showAddModal, setShowAddModal] = useState(false);
  const [addForm, setAddForm] = useState({
    uid: '',
    appId: '',
    email: '',
    password: '',
    displayName: '',
    role: 'moderator' as AdminUser['role'],
    permissions: getDefaultPermissionsForRole('moderator'),
    giftNecklaceId: '',
    giftBadgeId: '',
  });
  const [searchedUser, setSearchedUser] = useState<any>(null);
  const [searchingUser, setSearchingUser] = useState(false);
  const [addError, setAddError] = useState('');
  const [addSaving, setAddSaving] = useState(false);
  const [addPermSearch, setAddPermSearch] = useState('');

  const [editingAdmin, setEditingAdmin] = useState<AdminUser | null>(null);
  const [editForm, setEditForm] = useState({
    displayName: '',
    appId: '',
    password: '',
    role: '' as string,
    permissions: {} as Record<string, boolean>,
    giftNecklaceId: '',
    giftBadgeId: '',
  });
  const [editPermSearch, setEditPermSearch] = useState('');

  const [confirmDelete, setConfirmDelete] = useState<string | null>(null);
  const [logFilter, setLogFilter] = useState('');

  const [banForm, setBanForm] = useState({ uid: '', email: '', reason: '' });
  const [banError, setBanError] = useState('');

  const [profileForm, setProfileForm] = useState({ displayName: '', photoUrl: '' });
  const [profilePass, setProfilePass] = useState('');
  const [profileSaving, setProfileSaving] = useState(false);
  const [profileMsg, setProfileMsg] = useState('');

  const load = async () => {
    setLoading(true);
    const [a, l, b, badgesData, necklacesData] = await Promise.all([
      getAdminUsers(),
      getAdminActionLogs(),
      getDashboardBans(),
      getBadges().catch(() => []),
      getNecklaces().catch(() => []),
    ]);
    setAdmins(a);
    setLogs(l);
    setBans(b);
    setAvailableBadges(badgesData || []);
    setAvailableNecklaces(necklacesData || []);
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const resetAddForm = () => {
    setAddForm({
      uid: '',
      appId: '',
      email: '',
      password: '',
      displayName: '',
      role: 'moderator',
      permissions: getDefaultPermissionsForRole('moderator'),
      giftNecklaceId: '',
      giftBadgeId: '',
    });
    setSearchedUser(null);
    setSearchingUser(false);
    setAddError('');
    setAddPermSearch('');
  };

  // Live lookup when owner types App ID
  const handleAppIdChange = async (val: string) => {
    setAddForm(p => ({ ...p, appId: val }));
    const term = val.trim();
    if (!term || term.length < 2) {
      setSearchedUser(null);
      return;
    }
    setSearchingUser(true);
    try {
      const u = await searchUserProfile(term);
      setSearchedUser(u);
      if (u) {
        setAddForm(p => ({
          ...p,
          uid: u.uid || u.id,
          displayName: p.displayName || u.name,
          email: p.email || (u.custom_id ? `${u.custom_id}@admin.zero.app` : ''),
        }));
      }
    } catch {}
    setSearchingUser(false);
  };

  const handleRoleChangeAdd = (newRole: AdminUser['role']) => {
    setAddForm(prev => ({
      ...prev,
      role: newRole,
      permissions: getDefaultPermissionsForRole(newRole),
    }));
  };

  const handleRoleChangeEdit = (newRole: string) => {
    setEditForm(prev => {
      let nextPerms = { ...prev.permissions };
      if (newRole === 'super_admin' && Object.values(nextPerms).filter(Boolean).length === 0) {
        nextPerms = getAllPermissionsMap();
      }
      return {
        ...prev,
        role: newRole,
        permissions: nextPerms,
      };
    });
  };

  const selectAllAdd = () => {
    setAddForm(prev => ({ ...prev, permissions: getAllPermissionsMap() }));
  };

  const deselectAllAdd = () => {
    setAddForm(prev => ({ ...prev, permissions: {} }));
  };

  const toggleCategoryAdd = (categoryId: string) => {
    const category = PERMISSION_CATEGORIES.find(c => c.id === categoryId);
    if (!category) return;
    const allSelected = category.items.every(item => !!addForm.permissions[item.key]);
    setAddForm(prev => {
      const updated = { ...prev.permissions };
      for (const item of category.items) {
        updated[item.key] = !allSelected;
      }
      return { ...prev, permissions: updated };
    });
  };

  const selectAllEdit = () => {
    setEditForm(prev => ({ ...prev, permissions: getAllPermissionsMap() }));
  };

  const deselectAllEdit = () => {
    setEditForm(prev => ({ ...prev, permissions: {} }));
  };

  const toggleCategoryEdit = (categoryId: string) => {
    const category = PERMISSION_CATEGORIES.find(c => c.id === categoryId);
    if (!category) return;
    const allSelected = category.items.every(item => !!editForm.permissions[item.key]);
    setEditForm(prev => {
      const updated = { ...prev.permissions };
      for (const item of category.items) {
        updated[item.key] = !allSelected;
      }
      return { ...prev, permissions: updated };
    });
  };

  const handleCreate = async () => {
    setAddError('');
    let finalEmail = addForm.email.trim();
    if (!finalEmail && addForm.appId) {
      finalEmail = `${addForm.appId.trim()}@admin.zero.app`;
    }
    if (!finalEmail) {
      setAddError(isAr ? 'يرجى إدخال البريد الإلكتروني أو الآيدي الخاص بالمشرف' : 'Email or App ID required');
      return;
    }
    if (!addForm.password || addForm.password.length < 6) {
      setAddError(isAr ? 'كلمة المرور يجب أن تكون 6 أحرف على الأقل' : 'Password must be at least 6 characters');
      return;
    }
    setAddSaving(true);
    try {
      const uid = addForm.uid || searchedUser?.uid || searchedUser?.id || `admin_${Date.now()}`;
      await createAdminUser(uid, {
        email: finalEmail,
        appId: addForm.appId.trim() || searchedUser?.custom_id || '',
        displayName: addForm.displayName || searchedUser?.name || finalEmail.split('@')[0],
        role: addForm.role,
        permissions: addForm.permissions,
        createdBy: currentUser?.id || '',
        giftNecklaceId: addForm.giftNecklaceId || undefined,
        giftBadgeId: addForm.giftBadgeId || undefined,
      } as any, addForm.password);

      await logAdminAction(
        currentUser?.id || '',
        currentUser?.displayName || currentUser?.email || 'Admin',
        'create_admin',
        'admin',
        uid,
        { email: finalEmail, appId: addForm.appId, role: addForm.role, giftNecklaceId: addForm.giftNecklaceId, giftBadgeId: addForm.giftBadgeId }
      );
      setShowAddModal(false);
      resetAddForm();
      await load();
    } catch (e: any) {
      setAddError(e?.message || (isAr ? 'حدث خطأ أثناء إضافة المشرف' : 'Error creating admin'));
    }
    setAddSaving(false);
  };

  const startEdit = (admin: AdminUser) => {
    setEditingAdmin(admin);
    const perms = { ...admin.permissions };
    if (perms['all']) {
      Object.assign(perms, getAllPermissionsMap());
    } else if (Object.keys(perms).length === 0) {
      Object.assign(perms, getDefaultPermissionsForRole(admin.role));
    }
    setEditForm({
      displayName: admin.displayName || '',
      appId: admin.appId || '',
      password: '',
      role: admin.role,
      permissions: perms,
      giftNecklaceId: '',
      giftBadgeId: '',
    });
    setEditPermSearch('');
  };

  const handleEditSave = async () => {
    if (!editingAdmin) return;
    try {
      await updateAdminUser(editingAdmin.uid, {
        displayName: editForm.displayName,
        appId: editForm.appId.trim(),
        role: editForm.role as AdminUser['role'],
        permissions: editForm.permissions,
        ...(editForm.password ? { password: editForm.password } : {}),
        giftNecklaceId: editForm.giftNecklaceId || undefined,
        giftBadgeId: editForm.giftBadgeId || undefined,
      } as any);
      await logAdminAction(
        currentUser?.id || '',
        currentUser?.displayName || currentUser?.email || 'Admin',
        'update_admin',
        'admin',
        editingAdmin.uid,
        { role: editForm.role, appId: editForm.appId }
      );
      setEditingAdmin(null);
      await load();
    } catch (e: any) {
      alert(e?.message || (isAr ? 'حدث خطأ أثناء تعديل المشرف' : 'Error updating admin'));
    }
  };

  const toggleActive = async (admin: AdminUser) => {
    try {
      await updateAdminUser(admin.uid, { isActive: !admin.isActive });
      await logAdminAction(
        currentUser?.id || '',
        currentUser?.displayName || currentUser?.email || 'Admin',
        admin.isActive ? 'disable_admin' : 'enable_admin',
        'admin',
        admin.uid
      );
      await load();
    } catch (e: any) {
      alert(e?.message || (isAr ? 'حدث خطأ في تحديث الحالة' : 'Error toggling admin'));
    }
  };

  const handleDelete = async (uid: string) => {
    try {
      await deleteAdminUser(uid);
      await logAdminAction(
        currentUser?.id || '',
        currentUser?.displayName || currentUser?.email || 'Admin',
        'delete_admin',
        'admin',
        uid
      );
      setConfirmDelete(null);
      await load();
    } catch (e: any) {
      alert(e?.message || (isAr ? 'حدث خطأ أثناء حذف المشرف' : 'Error deleting admin'));
    }
  };

  const handleBan = async () => {
    setBanError('');
    if (!banForm.uid || !banForm.reason) {
      setBanError(isAr ? 'المعرف والسبب مطلوبان' : 'UID and reason required');
      return;
    }
    try {
      await banFromDashboard(banForm.uid, banForm.email, banForm.reason, currentUser?.id || '');
      await logAdminAction(
        currentUser?.id || '',
        currentUser?.displayName || currentUser?.email || 'Admin',
        'ban_dashboard',
        'user',
        banForm.uid,
        { reason: banForm.reason }
      );
      setBanForm({ uid: '', email: '', reason: '' });
      await load();
    } catch (e: any) {
      setBanError(e?.message || (isAr ? 'حدث خطأ أثناء الحظر' : 'Error banning user'));
    }
  };

  const handleUnban = async (uid: string) => {
    try {
      await unbanFromDashboard(uid);
      await logAdminAction(
        currentUser?.id || '',
        currentUser?.displayName || currentUser?.email || 'Admin',
        'unban_dashboard',
        'user',
        uid
      );
      await load();
    } catch {}
  };

  const handleProfileSave = async () => {
    if (!currentUser) return;
    setProfileSaving(true);
    setProfileMsg('');
    try {
      await updateAdminUser(currentUser.id, {
        displayName: profileForm.displayName,
        photoUrl: profileForm.photoUrl,
      });
      if (profilePass) {
        const adminClient = getAdminSupabase();
        if (adminClient) {
          await adminClient.auth.admin.updateUserById(currentUser.id, { password: profilePass });
        }
      }
      setProfileMsg(isAr ? 'تم الحفظ بنجاح' : 'Saved successfully');
      setProfilePass('');
      await load();
    } catch (e: any) {
      setProfileMsg(e?.message || 'Error saving profile');
    }
    setProfileSaving(false);
  };

  const handleClearLogs = async () => {
    if (!confirm(isAr ? 'مسح جميع السجلات؟' : 'Clear all logs?')) return;
    await clearActionLogs();
    await load();
  };

  const isOwner = currentUser?.role === 'owner' ||
    (currentUser?.role === 'super_admin' && (currentUser?.permissions?.includes('all') || currentUser?.permissions?.includes('*'))) ||
    currentUser?.email?.toLowerCase() === 'admin@zero.app' ||
    currentUser?.email?.toLowerCase() === 'm3290556@gmail.com' ||
    currentUser?.email?.toLowerCase() === 'admin@ahlalive.com';

  const visibleAdmins = isOwner
    ? admins
    : admins.filter(a =>
        a.uid === currentUser?.id ||
        (currentUser?.email && a.email?.toLowerCase() === currentUser.email.toLowerCase())
      );

  const filteredAdmins = visibleAdmins.filter(a => {
    if (!searchQ) return true;
    const q = searchQ.toLowerCase();
    const email = (a.email || '').toLowerCase();
    const name = (a.displayName || '').toLowerCase();
    const appId = (a.appId || '').toLowerCase();
    return email.includes(q) || name.includes(q) || appId.includes(q);
  });

  const visibleLogs = isOwner
    ? logs
    : logs.filter(l =>
        l.adminUid === currentUser?.id ||
        (currentUser?.displayName && l.adminName.toLowerCase().includes(currentUser.displayName.toLowerCase()))
      );

  const filteredLogs = visibleLogs.filter(l =>
    !logFilter ||
    l.adminName.toLowerCase().includes(logFilter.toLowerCase()) ||
    l.action.toLowerCase().includes(logFilter.toLowerCase())
  );

  const tabs = [
    { key: 'admins' as const, ar: isOwner ? 'المشرفين والصلاحيات' : 'حسابي وصلاحياتي', en: isOwner ? 'Admins & Permissions' : 'My Account & Permissions', icon: Shield },
    { key: 'logs' as const, ar: 'سجل الإجراءات', en: 'Action Logs', icon: FileText },
    ...(isOwner ? [{ key: 'bans' as const, ar: 'الحظر من اللوحة', en: 'Dashboard Bans', icon: Ban }] : []),
    { key: 'profile' as const, ar: 'ملفي الشخصي', en: 'My Profile', icon: Camera },
  ];

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-white text-lg font-semibold">{isOwner ? (isAr ? 'إدارة المشرفين والصلاحيات' : 'Admin & Permissions Management') : (isAr ? 'بيانات المشرف والصلاحيات' : 'My Supervisor Account & Permissions')}</h2>
          <p className="text-slate-500 text-xs mt-0.5">
            {isOwner
              ? `${admins.length} ${isAr ? 'مشرف مسجل' : 'registered admins'}`
              : (isAr ? 'بيانات حسابك الإداري وصلاحيات الأقسام الممنوحة لك' : 'Your administrative account details and assigned permissions')}
          </p>
        </div>
        <button onClick={load} className="px-3 py-1.5 bg-[#141417] border border-white/5 hover:border-white/10 text-xs text-slate-300 font-semibold rounded-lg flex items-center gap-1">
          <RefreshCw className="w-3.5 h-3.5" /> {isAr ? 'تحديث' : 'Refresh'}
        </button>
      </div>

      {/* Tabs */}
      <div className={`flex gap-1 p-1 bg-[#141417] rounded-xl border border-white/5 w-fit ${isAr ? 'flex-row-reverse' : ''}`}>
        {tabs.map(tItem => {
          const Icon = tItem.icon;
          return (
            <button key={tItem.key} onClick={() => setTab(tItem.key)}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all ${tab === tItem.key ? 'bg-indigo-500/10 text-indigo-300 border border-indigo-500/20' : 'text-slate-400 hover:text-white'}`}>
              <Icon className="w-3.5 h-3.5" />
              <span>{isAr ? tItem.ar : tItem.en}</span>
            </button>
          );
        })}
      </div>

      {loading ? (
        <div className="text-center py-20 text-slate-500 text-xs">{t('loading')}</div>
      ) : (
        <>
          {/* === ADMINS TAB === */}
          {tab === 'admins' && (
            <div className="space-y-4">
              <div className={`flex items-center justify-between gap-3 ${isAr ? 'flex-row-reverse' : ''}`}>
                <div className="relative flex-1 max-w-xs">
                  <Search className={`w-3.5 h-3.5 absolute top-1/2 -translate-y-1/2 text-slate-500 pointer-events-none ${isAr ? 'right-3' : 'left-3'}`} />
                  <input type="text" value={searchQ} onChange={e => setSearchQ(e.target.value)}
                    placeholder={isAr ? 'بحث عن مشرف بالاسم، البريد، أو الآيدي...' : 'Search admin by name, email, or ID...'}
                    className={`w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 ${isAr ? 'pr-9 pl-3' : 'pl-9 pr-3'} text-xs text-white focus:outline-none focus:border-indigo-500 placeholder:text-slate-600`} />
                </div>
                {isOwner && (
                  <button onClick={() => { setShowAddModal(true); resetAddForm(); }} className="px-3.5 py-2 bg-gradient-to-r from-indigo-600 to-indigo-700 hover:from-indigo-500 hover:to-indigo-600 text-xs text-white font-semibold rounded-xl flex items-center gap-1.5 shadow-lg shadow-indigo-600/20 transition-all">
                    <UserPlus className="w-4 h-4" /> {isAr ? 'إضافة مشرف جديد' : 'Add New Admin'}
                  </button>
                )}
              </div>

              <div className="bg-[#141417] rounded-2xl border border-white/5 overflow-hidden">
                <div className="overflow-x-auto">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b border-white/5 text-slate-500">
                        <th className="text-right p-3 font-medium">{isAr ? 'المشرف' : 'Admin'}</th>
                        <th className="text-right p-3 font-medium">{isAr ? 'البريد الإلكتروني' : 'Email'}</th>
                        <th className="text-right p-3 font-medium">{isAr ? 'آيدي التطبيق' : 'App ID'}</th>
                        <th className="text-right p-3 font-medium">{isAr ? 'الرتبة والدور' : 'Role'}</th>
                        <th className="text-right p-3 font-medium">{isAr ? 'الأقسام المتاحة' : 'Sections'}</th>
                        <th className="text-right p-3 font-medium">{isAr ? 'الحالة' : 'Status'}</th>
                        <th className="text-right p-3 font-medium">{isAr ? 'الإجراءات' : 'Actions'}</th>
                      </tr>
                    </thead>
                    <tbody>
                      {filteredAdmins.map(admin => {
                        const nameOrEmail = admin.displayName || admin.email || admin.uid || 'Admin';
                        const initialChar = nameOrEmail.trim().charAt(0).toUpperCase() || 'A';
                        const isSuper = admin.role === 'super_admin' || admin.role === 'superadmin';
                        const activePermCount = isSuper ? ALL_PERMISSIONS.length : Object.values(admin.permissions || {}).filter(Boolean).length;

                        return (
                          <tr key={admin.uid} className="border-b border-white/5 hover:bg-white/[0.02] transition-colors">
                            <td className="p-3">
                              <div className={`flex items-center gap-2.5 ${isAr ? 'flex-row-reverse' : ''}`}>
                                {admin.photoUrl ? (
                                  <img src={admin.photoUrl} alt="" className="w-8 h-8 rounded-full object-cover border border-white/10" />
                                ) : (
                                  <div className="w-8 h-8 rounded-full bg-gradient-to-br from-indigo-600 to-rose-500 flex items-center justify-center text-[11px] font-bold text-white shadow-sm">
                                    {initialChar}
                                  </div>
                                )}
                                <div>
                                  <span className="text-white font-medium block leading-tight">{nameOrEmail}</span>
                                  <span className="text-[10px] text-slate-500 font-mono">UID: {admin.uid.slice(0, 10)}...</span>
                                </div>
                              </div>
                            </td>
                            <td className="p-3 text-slate-400 font-mono">{admin.email || '—'}</td>
                            <td className="p-3">
                              {admin.appId ? (
                                <span className="px-2 py-0.5 rounded text-[10px] font-mono font-bold bg-indigo-500/10 text-indigo-300 border border-indigo-500/20">
                                  #{admin.appId}
                                </span>
                              ) : (
                                <span className="text-slate-600 text-[10px]">—</span>
                              )}
                            </td>
                            <td className="p-3">
                              <span className={`px-2.5 py-1 rounded-full text-[10px] font-semibold border ${
                                isSuper ? 'bg-rose-500/10 text-rose-300 border-rose-500/20' :
                                admin.role === 'admin' ? 'bg-indigo-500/10 text-indigo-300 border-indigo-500/20' :
                                'bg-emerald-500/10 text-emerald-300 border-emerald-500/20'
                              }`}>
                                {isSuper ? (isAr ? 'سوبر أدمن (المدير العام)' : 'Super Admin') :
                                 admin.role === 'admin' ? (isAr ? 'مسؤول (Admin)' : 'Admin') :
                                 (isAr ? 'مشرف (Moderator)' : 'Moderator')}
                              </span>
                            </td>
                            <td className="p-3">
                              {isSuper ? (
                                <span className="text-[10px] text-rose-300 font-semibold bg-rose-500/10 px-2 py-0.5 rounded-md border border-rose-500/20">
                                  {isAr ? 'جميع أقسام اللوحة (شامل)' : 'All Sections (Full)'}
                                </span>
                              ) : (
                                <span className="text-[10px] text-indigo-300 font-semibold bg-indigo-500/10 px-2 py-0.5 rounded-md border border-indigo-500/20">
                                  {activePermCount} / {ALL_PERMISSIONS.length} {isAr ? 'قسم متاح' : 'sections'}
                                </span>
                              )}
                            </td>
                            <td className="p-3">
                              {admin.isActive ? (
                                <span className="inline-flex items-center gap-1 text-emerald-400 text-[11px] font-medium"><CheckCircle className="w-3.5 h-3.5" /> {isAr ? 'نشط' : 'Active'}</span>
                              ) : (
                                <span className="inline-flex items-center gap-1 text-rose-400 text-[11px] font-medium"><XCircle className="w-3.5 h-3.5" /> {isAr ? 'معطل' : 'Disabled'}</span>
                              )}
                            </td>
                            <td className="p-3">
                              <div className={`flex items-center gap-1.5 ${isAr ? 'flex-row-reverse' : ''}`}>
                                <button onClick={() => startEdit(admin)} title={isAr ? (isOwner ? 'تعديل الصلاحيات' : 'عرض الصلاحيات') : (isOwner ? 'Edit permissions' : 'View permissions')} className="p-1.5 rounded-lg bg-indigo-500/10 text-indigo-300 hover:bg-indigo-500/20 transition-colors">
                                  <Shield className="w-3.5 h-3.5" />
                                </button>
                                {isOwner && (
                                  <>
                                    <button onClick={() => toggleActive(admin)} title={admin.isActive ? (isAr ? 'تعطيل' : 'Disable') : (isAr ? 'تفعيل' : 'Enable')} className="p-1.5 rounded-lg bg-slate-500/10 text-slate-400 hover:bg-slate-500/20 transition-colors">
                                      {admin.isActive ? <ShieldOff className="w-3.5 h-3.5" /> : <Shield className="w-3.5 h-3.5" />}
                                    </button>
                                    {!isSuper && (
                                      <button onClick={() => setConfirmDelete(admin.uid)} title={isAr ? 'حذف' : 'Delete'} className="p-1.5 rounded-lg bg-rose-500/10 text-rose-300 hover:bg-rose-500/20 transition-colors">
                                        <Trash2 className="w-3.5 h-3.5" />
                                      </button>
                                    )}
                                  </>
                                )}
                              </div>
                            </td>
                          </tr>
                        );
                      })}
                      {filteredAdmins.length === 0 && (
                        <tr><td colSpan={7} className="p-8 text-center text-slate-500">{isAr ? 'لا يوجد مشرفين مطابقين' : 'No admins found'}</td></tr>
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          )}

          {/* === LOGS TAB === */}
          {tab === 'logs' && (
            <div className="space-y-4">
              <div className={`flex items-center justify-between gap-3 ${isAr ? 'flex-row-reverse' : ''}`}>
                <div className="relative flex-1 max-w-xs">
                  <Search className={`w-3.5 h-3.5 absolute top-1/2 -translate-y-1/2 text-slate-500 pointer-events-none ${isAr ? 'right-3' : 'left-3'}`} />
                  <input type="text" value={logFilter} onChange={e => setLogFilter(e.target.value)}
                    placeholder={isAr ? 'بحث في السجلات...' : 'Search logs...'}
                    className={`w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 ${isAr ? 'pr-9 pl-3' : 'pl-9 pr-3'} text-xs text-white focus:outline-none focus:border-indigo-500 placeholder:text-slate-600`} />
                </div>
                {isOwner && (
                  <button onClick={handleClearLogs} className="px-3 py-1.5 bg-rose-500/10 hover:bg-rose-500/20 text-rose-300 text-xs font-semibold rounded-lg flex items-center gap-1 transition-colors">
                    <Trash2 className="w-3.5 h-3.5" /> {isAr ? 'مسح كل السجلات' : 'Clear All'}
                  </button>
                )}
              </div>

              <div className="bg-[#141417] rounded-2xl border border-white/5 overflow-hidden">
                <div className="overflow-x-auto">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b border-white/5 text-slate-500">
                        <th className="text-right p-3 font-medium">{isAr ? 'التاريخ' : 'Date'}</th>
                        <th className="text-right p-3 font-medium">{isAr ? 'المشرف' : 'Admin'}</th>
                        <th className="text-right p-3 font-medium">{isAr ? 'الإجراء' : 'Action'}</th>
                        <th className="text-right p-3 font-medium">{isAr ? 'النوع' : 'Target'}</th>
                        <th className="text-right p-3 font-medium">{isAr ? 'التفاصيل' : 'Details'}</th>
                      </tr>
                    </thead>
                    <tbody>
                      {filteredLogs.slice(0, 200).map(log => (
                        <tr key={log.id} className="border-b border-white/5 hover:bg-white/[0.02]">
                          <td className="p-3 text-slate-400 whitespace-nowrap">
                            {new Date(log.createdAt).toLocaleString(isAr ? 'ar-SA' : 'en-US', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}
                          </td>
                          <td className="p-3 text-white font-medium">{log.adminName}</td>
                          <td className="p-3">
                            <span className="px-2 py-0.5 rounded-full bg-indigo-500/10 text-indigo-300 text-[10px] font-mono border border-indigo-500/20">{log.action}</span>
                          </td>
                          <td className="p-3 text-slate-400">{log.targetType}/{log.targetId?.slice(0, 12)}</td>
                          <td className="p-3 text-slate-500 max-w-[200px] truncate">
                            {JSON.stringify(log.details).slice(0, 60)}
                          </td>
                        </tr>
                      ))}
                      {filteredLogs.length === 0 && (
                        <tr><td colSpan={5} className="p-8 text-center text-slate-500">{isAr ? 'لا توجد سجلات' : 'No logs found'}</td></tr>
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          )}

          {/* === BANS TAB === */}
          {tab === 'bans' && (
            <div className="space-y-4">
              <div className="bg-[#141417] rounded-2xl border border-white/5 p-4 space-y-3 max-w-lg">
                <h3 className="text-white text-xs font-semibold flex items-center gap-1.5">
                  <Ban className="w-4 h-4 text-rose-400" />
                  {isAr ? 'حظر مستخدم من لوحة الإدارة' : 'Ban User from Dashboard'}
                </h3>
                <div className="space-y-2">
                  <input type="text" value={banForm.uid} onChange={e => setBanForm(p => ({ ...p, uid: e.target.value }))}
                    placeholder={isAr ? 'معرف المستخدم (UID)...' : 'User UID...'}
                    className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500" />
                  <input type="email" value={banForm.email} onChange={e => setBanForm(p => ({ ...p, email: e.target.value }))}
                    placeholder={isAr ? 'البريد الإلكتروني (اختياري)...' : 'Email (optional)...'}
                    className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500" />
                  <input type="text" value={banForm.reason} onChange={e => setBanForm(p => ({ ...p, reason: e.target.value }))}
                    placeholder={isAr ? 'سبب الحظر...' : 'Ban reason...'}
                    className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500" />
                </div>
                {banError && <p className="text-rose-400 text-[10px]">{banError}</p>}
                <button onClick={handleBan} className="px-3.5 py-1.5 bg-rose-600 hover:bg-rose-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
                  <Ban className="w-3.5 h-3.5" /> {isAr ? 'حظر' : 'Ban'}
                </button>
              </div>

              <div className="bg-[#141417] rounded-2xl border border-white/5 overflow-hidden">
                <table className="w-full text-xs">
                  <thead>
                    <tr className="border-b border-white/5 text-slate-500">
                      <th className="text-right p-3 font-medium">UID</th>
                      <th className="text-right p-3 font-medium">{isAr ? 'البريد' : 'Email'}</th>
                      <th className="text-right p-3 font-medium">{isAr ? 'السبب' : 'Reason'}</th>
                      <th className="text-right p-3 font-medium">{isAr ? 'تاريخ الحظر' : 'Banned At'}</th>
                      <th className="text-right p-3 font-medium">{isAr ? 'الإجراء' : 'Action'}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {bans.map(b => (
                      <tr key={b.uid} className="border-b border-white/5 hover:bg-white/[0.02]">
                        <td className="p-3 text-white font-mono">{b.uid}</td>
                        <td className="p-3 text-slate-400">{b.email || '—'}</td>
                        <td className="p-3 text-rose-300">{b.reason}</td>
                        <td className="p-3 text-slate-500">{new Date(b.bannedAt).toLocaleString(isAr ? 'ar-SA' : 'en-US')}</td>
                        <td className="p-3">
                          <button onClick={() => handleUnban(b.uid)} className="px-2.5 py-1 bg-emerald-500/10 hover:bg-emerald-500/20 text-emerald-300 text-[10px] font-semibold rounded-lg">
                            {isAr ? 'إلغاء الحظر' : 'Unban'}
                          </button>
                        </td>
                      </tr>
                    ))}
                    {bans.length === 0 && (
                      <tr><td colSpan={5} className="p-8 text-center text-slate-500">{isAr ? 'لا يوجد محظورين' : 'No banned users'}</td></tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* === PROFILE TAB === */}
          {tab === 'profile' && (
            <div className="max-w-lg mx-auto space-y-6">
              <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-5">
                <div className={`flex items-center gap-4 ${isAr ? 'flex-row-reverse' : ''}`}>
                  <div className="w-16 h-16 rounded-full bg-gradient-to-br from-indigo-600 to-rose-500 flex items-center justify-center text-xl font-bold text-white shrink-0 overflow-hidden">
                    {profileForm.photoUrl ? (
                      <img src={profileForm.photoUrl} alt="" className="w-full h-full object-cover" />
                    ) : (
                      (currentUser?.email?.[0]?.toUpperCase() || 'A')
                    )}
                  </div>
                  <div>
                    <h3 className="text-white font-semibold">{currentUser?.displayName || currentUser?.email}</h3>
                    <p className="text-slate-500 text-[11px]">{currentUser?.email}</p>
                    <span className="inline-block mt-1 text-[10px] px-2 py-0.5 rounded-full bg-rose-500/10 text-rose-300 border border-rose-500/20 font-semibold">
                      {currentUser?.role === 'super_admin' ? (isAr ? 'سوبر أدمن' : 'Super Admin') : (currentUser?.role || 'Admin')}
                    </span>
                  </div>
                </div>

                <div>
                  <label className="block text-[10px] text-slate-500 mb-1">{isAr ? 'الاسم المعروض' : 'Display Name'}</label>
                  <input type="text" value={profileForm.displayName} onChange={e => setProfileForm(p => ({ ...p, displayName: e.target.value }))}
                    className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500 placeholder:text-slate-600"
                    placeholder={currentUser?.email || ''} />
                </div>

                <div>
                  <label className="block text-[10px] text-slate-500 mb-1">{isAr ? 'رابط الصورة' : 'Photo URL'}</label>
                  <input type="text" value={profileForm.photoUrl} onChange={e => setProfileForm(p => ({ ...p, photoUrl: e.target.value }))}
                    className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500 placeholder:text-slate-600"
                    placeholder="https://..." />
                </div>

                <div>
                  <label className="block text-[10px] text-slate-500 mb-1">{isAr ? 'كلمة المرور الجديدة' : 'New Password'} {isAr ? '(اتركها فارغة لعدم التغيير)' : '(leave empty to keep)'}</label>
                  <input type="password" value={profilePass} onChange={e => setProfilePass(e.target.value)}
                    className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500 placeholder:text-slate-600"
                    placeholder="••••••" />
                </div>

                {profileMsg && <p className={`text-xs ${profileMsg.includes('نجاح') || profileMsg.includes('Saved') ? 'text-emerald-400' : 'text-rose-400'}`}>{profileMsg}</p>}

                <button onClick={handleProfileSave} disabled={profileSaving}
                  className="px-4 py-2 bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
                  <Save className="w-3.5 h-3.5" /> {profileSaving ? t('saving') : t('save')}
                </button>
              </div>
            </div>
          )}
        </>
      )}

      {/* === ADD ADMIN MODAL === */}
      {showAddModal && (
        <div className="fixed inset-0 bg-black/70 z-50 flex items-center justify-center p-3 sm:p-4 backdrop-blur-sm" onClick={() => setShowAddModal(false)}>
          <div className="bg-[#141417] border border-white/10 rounded-2xl w-full max-w-3xl max-h-[92vh] flex flex-col shadow-2xl overflow-hidden" onClick={e => e.stopPropagation()}>
            <div className={`p-4 border-b border-white/10 flex items-center justify-between shrink-0 bg-[#17171B] ${isAr ? 'flex-row-reverse' : ''}`}>
              <div className="flex items-center gap-2">
                <div className="p-2 rounded-lg bg-indigo-500/10 text-indigo-400">
                  <UserPlus className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="text-white font-bold text-sm">
                    {isAr ? 'إضافة مشرف جديد وتحديد الصلاحيات' : 'Add New Admin & Permissions'}
                  </h3>
                  <p className="text-[11px] text-slate-400">
                    {isAr ? 'يمكنك ربط المشرف بالآيدي في التطبيق أو البريد وتحديد كلمة المرور والصلاحيات' : 'Link admin via App ID or Email with custom password & permissions'}
                  </p>
                </div>
              </div>
              <button onClick={() => setShowAddModal(false)} className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-white/5 transition-colors">
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="p-4 sm:p-6 overflow-y-auto space-y-4 flex-1 custom-scrollbar">
              {/* App ID Linking Card */}
              <div className="bg-[#18181C] p-3.5 rounded-xl border border-indigo-500/25 space-y-2.5">
                <div className={`flex items-center justify-between ${isAr ? 'flex-row-reverse' : ''}`}>
                  <label className="block text-[11px] font-bold text-indigo-300">
                    {isAr ? 'الآيدي الخاص به داخل التطبيق (App ID / User ID)' : 'App ID / User ID in Application'}
                  </label>
                  <span className="text-[10px] text-slate-400">
                    {isAr ? 'يتيح للمشرف تسجيل الدخول بالآيدي مباشرة' : 'Enables direct login via App ID'}
                  </span>
                </div>
                <div className="relative">
                  <input
                    type="text"
                    value={addForm.appId}
                    onChange={e => handleAppIdChange(e.target.value)}
                    placeholder={isAr ? 'أدخل آيدي الحساب في التطبيق (مثال: 100123)...' : 'Enter User ID or custom_id...'}
                    className="w-full bg-[#141417] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-indigo-500 font-mono"
                  />
                  {searchingUser && (
                    <div className="absolute left-3 top-2.5 text-[10px] text-indigo-400 rtl:left-auto rtl:right-3">
                      {isAr ? 'جارٍ التعرف...' : 'Searching...'}
                    </div>
                  )}
                </div>

                {/* Searched user preview */}
                {searchedUser && (
                  <div className={`flex items-center justify-between p-2.5 rounded-xl bg-emerald-500/10 border border-emerald-500/30 ${isAr ? 'flex-row-reverse' : ''}`}>
                    <div className={`flex items-center gap-2.5 ${isAr ? 'flex-row-reverse' : ''}`}>
                      <img
                        src={searchedUser.photo_url || `https://ui-avatars.com/api/?name=${encodeURIComponent(searchedUser.name || 'User')}&background=random`}
                        alt=""
                        className="w-9 h-9 rounded-full object-cover border border-emerald-400/40"
                      />
                      <div>
                        <div className="text-xs font-bold text-white flex items-center gap-1.5">
                          <span>{searchedUser.name}</span>
                          <span className="text-[10px] text-emerald-400 font-mono font-bold bg-emerald-500/20 px-1.5 py-0.5 rounded">
                            ID: #{searchedUser.custom_id}
                          </span>
                        </div>
                        <div className="text-[10px] text-slate-400">
                          {isAr ? 'تم التعرف على حساب المستخدم وسيتم ربطه كمشرف' : 'User profile recognized'}
                        </div>
                      </div>
                    </div>
                    <span className="text-[10px] text-emerald-400 font-bold bg-emerald-500/20 px-2 py-0.5 rounded-md flex items-center gap-1">
                      <Check className="w-3.5 h-3.5" /> {isAr ? 'تم التعرف' : 'Linked'}
                    </span>
                  </div>
                )}
              </div>

              {/* Login Credentials Grid */}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label className="block text-[11px] font-semibold text-slate-300 mb-1">
                    {isAr ? 'البريد الإلكتروني للدخول' : 'Login Email'} *
                  </label>
                  <input type="text" value={addForm.email} onChange={e => setAddForm(p => ({ ...p, email: e.target.value }))}
                    placeholder="admin@example.com"
                    className="w-full bg-[#18181C] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-indigo-500 font-mono" />
                </div>
                <div>
                  <label className="block text-[11px] font-semibold text-slate-300 mb-1">
                    {isAr ? 'كلمة المرور المحددة له' : 'Assigned Password'} *
                  </label>
                  <input type="password" value={addForm.password} onChange={e => setAddForm(p => ({ ...p, password: e.target.value }))}
                    placeholder="••••••••"
                    className="w-full bg-[#18181C] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-indigo-500" />
                </div>
                <div>
                  <label className="block text-[11px] font-semibold text-slate-300 mb-1">{isAr ? 'الاسم المعروض' : 'Display Name'}</label>
                  <input type="text" value={addForm.displayName} onChange={e => setAddForm(p => ({ ...p, displayName: e.target.value }))}
                    placeholder={isAr ? 'مثال: مشرف الوكالات والهدايا' : 'e.g. Host Manager'}
                    className="w-full bg-[#18181C] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-indigo-500" />
                </div>
                <div>
                  <label className="block text-[11px] font-semibold text-slate-300 mb-1">{isAr ? 'الرتبة والدور' : 'Role'} *</label>
                  <select value={addForm.role} onChange={e => handleRoleChangeAdd(e.target.value as AdminUser['role'])}
                    className="w-full bg-[#18181C] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-indigo-500">
                    <option value="moderator">{isAr ? 'مشرف (صلاحيات مخصصة)' : 'Moderator (Custom Permissions)'}</option>
                    <option value="admin">{isAr ? 'مسؤول (جميع الأقسام افتراضياً)' : 'Admin (All Sections by default)'}</option>
                    <option value="super_admin">{isAr ? 'سوبر أدمن (المدير العام - وصول شامل لكافة الأقسام)' : 'Super Admin (Full Root Access)'}</option>
                  </select>
                </div>
              </div>

              {/* Direct In-App Gifting (Necklace & Badge) */}
              <div className="bg-[#18181C] p-3.5 rounded-xl border border-amber-500/25 space-y-3">
                <div className={`flex items-center justify-between ${isAr ? 'flex-row-reverse' : ''}`}>
                  <label className="block text-[11px] font-bold text-amber-300 flex items-center gap-1.5">
                    <span>👑</span>
                    <span>{isAr ? 'إهداء قلادة ووسام للمشرف مباشرة في التطبيق' : 'Gift Necklace & Badge in Application'}</span>
                  </label>
                  <span className="text-[10px] text-amber-400/80">
                    {isAr ? 'تُمنح تلقائياً لحسابه فور الحفظ' : 'Granted directly upon save'}
                  </span>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div>
                    <label className="block text-[10px] text-slate-400 mb-1">{isAr ? 'اختيار القلادة الإدارية' : 'Select Necklace'}</label>
                    <select
                      value={addForm.giftNecklaceId}
                      onChange={e => setAddForm(p => ({ ...p, giftNecklaceId: e.target.value }))}
                      className="w-full bg-[#141417] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500"
                    >
                      <option value="">{isAr ? '-- بدون قلادة --' : '-- No Necklace --'}</option>
                      {availableNecklaces.map((n: any) => (
                        <option key={n.id} value={n.id}>{n.name || n.id}</option>
                      ))}
                    </select>
                  </div>

                  <div>
                    <label className="block text-[10px] text-slate-400 mb-1">{isAr ? 'اختيار الوسام الإداري' : 'Select Badge'}</label>
                    <select
                      value={addForm.giftBadgeId}
                      onChange={e => setAddForm(p => ({ ...p, giftBadgeId: e.target.value }))}
                      className="w-full bg-[#141417] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500"
                    >
                      <option value="">{isAr ? '-- بدون وسام --' : '-- No Badge --'}</option>
                      {availableBadges.map((b: any) => (
                        <option key={b.id} value={b.id}>{b.name || b.id}</option>
                      ))}
                    </select>
                  </div>
                </div>
              </div>

              {/* Informational tip */}
              <div className="p-2.5 rounded-xl bg-indigo-500/10 border border-indigo-500/20 text-[11px] text-indigo-300 flex items-center gap-2">
                <span className="font-bold shrink-0">💡 {isAr ? 'ملاحظة للدخول:' : 'Login info:'}</span>
                <span>
                  {isAr
                    ? 'المشرف سيتمكن من تسجيل الدخول إلى اللوحة باستخدام كلمة المرور وإما بريده الإلكتروني أو الآيدي الخاص به في التطبيق.'
                    : 'The admin can log in using their assigned password along with either their email or app ID.'}
                </span>
              </div>

              {/* Permissions Control Header */}
              <div className="pt-2 border-t border-white/10">
                <div className={`flex flex-col sm:flex-row sm:items-center justify-between gap-2.5 mb-3 ${isAr ? 'sm:flex-row-reverse' : ''}`}>
                  <div>
                    <h4 className="text-white font-bold text-xs flex items-center gap-1.5">
                      <Shield className="w-4 h-4 text-indigo-400" />
                      {isAr ? 'تحديد أقسام ولوحات التحكم المسموح بها' : 'Permissions & Sections Checklist'}
                    </h4>
                    <p className="text-[10px] text-slate-400">
                      {isAr
                        ? `تم تحديد (${Object.values(addForm.permissions).filter(Boolean).length} من ${ALL_PERMISSIONS.length}) قسم`
                        : `(${Object.values(addForm.permissions).filter(Boolean).length} / ${ALL_PERMISSIONS.length}) selected`}
                    </p>
                  </div>
                  <div className="flex items-center gap-1.5 flex-wrap">
                    <button type="button" onClick={selectAllAdd}
                      className="px-2.5 py-1 rounded-lg text-[11px] font-bold bg-indigo-600/20 text-indigo-300 hover:bg-indigo-600/30 border border-indigo-500/30 flex items-center gap-1 transition-colors">
                      <CheckSquare className="w-3.5 h-3.5" />
                      {isAr ? 'تحديد كل أقسام اللوحة (الكل)' : 'Select All'}
                    </button>
                    <button type="button" onClick={deselectAllAdd}
                      className="px-2.5 py-1 rounded-lg text-[11px] font-medium bg-white/5 text-slate-400 hover:text-white hover:bg-white/10 transition-colors">
                      <Square className="w-3.5 h-3.5" />
                      {isAr ? 'إلغاء التحديد' : 'Deselect All'}
                    </button>
                  </div>
                </div>

                {/* Filter input */}
                <div className="mb-3">
                  <input type="text" value={addPermSearch} onChange={e => setAddPermSearch(e.target.value)}
                    placeholder={isAr ? 'تصفية الأقسام (مثال: هدايا، وكالات، غرف)...' : 'Filter sections...'}
                    className="w-full bg-[#18181C] border border-white/10 rounded-xl py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500 placeholder:text-slate-600" />
                </div>

                {/* Categories */}
                <div className="space-y-3">
                  {PERMISSION_CATEGORIES.map(category => {
                    const filteredItems = category.items.filter(item =>
                      !addPermSearch ||
                      item.ar.toLowerCase().includes(addPermSearch.toLowerCase()) ||
                      item.en.toLowerCase().includes(addPermSearch.toLowerCase()) ||
                      item.key.toLowerCase().includes(addPermSearch.toLowerCase())
                    );
                    if (filteredItems.length === 0) return null;

                    const catSelectedCount = category.items.filter(i => !!addForm.permissions[i.key]).length;
                    const allCatSelected = catSelectedCount === category.items.length;

                    return (
                      <div key={category.id} className="bg-[#18181C] border border-white/5 rounded-xl p-3 space-y-2">
                        <div className={`flex items-center justify-between pb-2 border-b border-white/5 ${isAr ? 'flex-row-reverse' : ''}`}>
                          <div className={`flex items-center gap-2 ${isAr ? 'flex-row-reverse' : ''}`}>
                            <span className="text-xs font-bold text-slate-200">{isAr ? category.ar : category.en}</span>
                            <span className="text-[10px] px-1.5 py-0.5 rounded-md font-mono bg-indigo-500/10 text-indigo-300 border border-indigo-500/20">
                              {catSelectedCount} / {category.items.length}
                            </span>
                          </div>
                          <button type="button" onClick={() => toggleCategoryAdd(category.id)}
                            className="text-[10px] font-semibold text-indigo-400 hover:text-indigo-300 transition-colors">
                            {allCatSelected ? (isAr ? 'إلغاء تحديد القسم' : 'Deselect') : (isAr ? 'تحديد كل القسم' : 'Select Category')}
                          </button>
                        </div>
                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
                          {filteredItems.map(item => (
                            <label key={item.key}
                              className={`flex items-center gap-2 px-2.5 py-1.5 rounded-lg cursor-pointer text-[11px] transition-all ${
                                addForm.permissions[item.key]
                                  ? 'bg-indigo-500/15 text-indigo-200 border border-indigo-500/30'
                                  : 'bg-black/20 text-slate-400 hover:bg-white/5 hover:text-slate-300 border border-transparent'
                              } ${isAr ? 'flex-row-reverse' : ''}`}>
                              <input type="checkbox" checked={!!addForm.permissions[item.key]}
                                onChange={e => setAddForm(prev => ({
                                  ...prev,
                                  permissions: { ...prev.permissions, [item.key]: e.target.checked }
                                }))}
                                className="accent-indigo-500 rounded" />
                              <span className="flex-1 select-none">{isAr ? item.ar : item.en}</span>
                            </label>
                          ))}
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>

            {addError && (
              <div className="px-6 py-2 bg-rose-500/10 border-t border-rose-500/20 text-rose-300 text-xs">
                {addError}
              </div>
            )}

            <div className="p-4 border-t border-white/10 bg-[#17171B] flex items-center justify-end gap-2 shrink-0">
              <button type="button" onClick={() => setShowAddModal(false)}
                className="px-4 py-2 rounded-xl text-xs font-semibold bg-white/5 hover:bg-white/10 text-slate-300 transition-colors">
                {t('cancel')}
              </button>
              <button type="button" onClick={handleCreate} disabled={addSaving}
                className="px-5 py-2 rounded-xl text-xs font-bold bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-white shadow-lg shadow-indigo-600/25 flex items-center gap-1.5 transition-all">
                <Save className="w-3.5 h-3.5" />
                {addSaving ? t('saving') : (isAr ? 'حفظ وإضافة المشرف' : 'Save & Add Admin')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* === EDIT PERMISSIONS MODAL === */}
      {editingAdmin && (
        <div className="fixed inset-0 bg-black/70 z-50 flex items-center justify-center p-3 sm:p-4 backdrop-blur-sm" onClick={() => setEditingAdmin(null)}>
          <div className="bg-[#141417] border border-white/10 rounded-2xl w-full max-w-3xl max-h-[92vh] flex flex-col shadow-2xl overflow-hidden" onClick={e => e.stopPropagation()}>
            <div className={`p-4 border-b border-white/10 flex items-center justify-between shrink-0 bg-[#17171B] ${isAr ? 'flex-row-reverse' : ''}`}>
              <div className="flex items-center gap-2">
                <div className="p-2 rounded-lg bg-indigo-500/10 text-indigo-400">
                  <Shield className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="text-white font-bold text-sm">
                    {isAr ? 'تعديل المشرف وتخصيص الصلاحيات' : 'Edit Admin & Permissions'}
                  </h3>
                  <p className="text-[11px] text-slate-400">
                    {editingAdmin.displayName || editingAdmin.email}
                  </p>
                </div>
              </div>
              <button onClick={() => setEditingAdmin(null)} className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-white/5 transition-colors">
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="p-4 sm:p-6 overflow-y-auto space-y-4 flex-1 custom-scrollbar">
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label className="block text-[11px] font-semibold text-slate-300 mb-1">{isAr ? 'الاسم المعروض' : 'Display Name'}</label>
                  <input type="text" value={editForm.displayName} onChange={e => setEditForm(p => ({ ...p, displayName: e.target.value }))}
                    className="w-full bg-[#18181C] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-indigo-500" />
                </div>
                <div>
                  <label className="block text-[11px] font-semibold text-slate-300 mb-1">{isAr ? 'الآيدي الخاص به في التطبيق' : 'App ID'}</label>
                  <input type="text" value={editForm.appId} onChange={e => setEditForm(p => ({ ...p, appId: e.target.value }))}
                    placeholder="100123"
                    className="w-full bg-[#18181C] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-indigo-500 font-mono" />
                </div>
                <div>
                  <label className="block text-[11px] font-semibold text-slate-300 mb-1">{isAr ? 'كلمة المرور الجديدة' : 'New Password (leave empty to keep)'}</label>
                  <input type="password" value={editForm.password} onChange={e => setEditForm(p => ({ ...p, password: e.target.value }))}
                    placeholder={isAr ? 'اتركها فارغة لعدم التغيير' : '••••••••'}
                    className="w-full bg-[#18181C] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-indigo-500" />
                </div>
                <div>
                  <label className="block text-[11px] font-semibold text-slate-300 mb-1">{isAr ? 'الرتبة والدور' : 'Role'}</label>
                  <select value={editForm.role} onChange={e => handleRoleChangeEdit(e.target.value)}
                    className="w-full bg-[#18181C] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-indigo-500">
                    <option value="moderator">{isAr ? 'مشرف (صلاحيات مخصصة)' : 'Moderator (Custom Permissions)'}</option>
                    <option value="admin">{isAr ? 'مسؤول (جميع الأقسام افتراضياً)' : 'Admin (All Sections by default)'}</option>
                    <option value="super_admin">{isAr ? 'سوبر أدمن (المدير العام - وصول شامل لكافة الأقسام)' : 'Super Admin (Full Root Access)'}</option>
                  </select>
                </div>
              </div>

              {/* Direct In-App Gifting (Necklace & Badge) */}
              <div className="bg-[#18181C] p-3.5 rounded-xl border border-amber-500/25 space-y-3">
                <div className={`flex items-center justify-between ${isAr ? 'flex-row-reverse' : ''}`}>
                  <label className="block text-[11px] font-bold text-amber-300 flex items-center gap-1.5">
                    <span>👑</span>
                    <span>{isAr ? 'إهداء قلادة أو وسام للمشرف في التطبيق' : 'Gift Necklace or Badge in Application'}</span>
                  </label>
                  <span className="text-[10px] text-amber-400/80">
                    {isAr ? 'تُمنح تلقائياً لحسابه فور الحفظ' : 'Granted directly upon save'}
                  </span>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div>
                    <label className="block text-[10px] text-slate-400 mb-1">{isAr ? 'إهداء قلادة إدارية' : 'Gift Necklace'}</label>
                    <select
                      value={editForm.giftNecklaceId}
                      onChange={e => setEditForm(p => ({ ...p, giftNecklaceId: e.target.value }))}
                      className="w-full bg-[#141417] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500"
                    >
                      <option value="">{isAr ? '-- بدون تغيير القلادة --' : '-- No Change / None --'}</option>
                      {availableNecklaces.map((n: any) => (
                        <option key={n.id} value={n.id}>{n.name || n.id}</option>
                      ))}
                    </select>
                  </div>

                  <div>
                    <label className="block text-[10px] text-slate-400 mb-1">{isAr ? 'إهداء وسام إداري' : 'Gift Badge'}</label>
                    <select
                      value={editForm.giftBadgeId}
                      onChange={e => setEditForm(p => ({ ...p, giftBadgeId: e.target.value }))}
                      className="w-full bg-[#141417] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500"
                    >
                      <option value="">{isAr ? '-- بدون تغيير الوسام --' : '-- No Change / None --'}</option>
                      {availableBadges.map((b: any) => (
                        <option key={b.id} value={b.id}>{b.name || b.id}</option>
                      ))}
                    </select>
                  </div>
                </div>
              </div>

              {/* Permissions Control Header */}
              <div className="pt-2 border-t border-white/10">
                <div className={`flex flex-col sm:flex-row sm:items-center justify-between gap-2.5 mb-3 ${isAr ? 'sm:flex-row-reverse' : ''}`}>
                  <div>
                    <h4 className="text-white font-bold text-xs flex items-center gap-1.5">
                      <Shield className="w-4 h-4 text-indigo-400" />
                      {isAr ? 'أقسام ولوحات التحكم المسموح بها' : 'Allowed Dashboard Sections'}
                    </h4>
                    <p className="text-[10px] text-slate-400">
                      {isAr
                        ? `تم تحديد (${Object.values(editForm.permissions).filter(Boolean).length} من ${ALL_PERMISSIONS.length}) قسم`
                        : `(${Object.values(editForm.permissions).filter(Boolean).length} / ${ALL_PERMISSIONS.length}) selected`}
                    </p>
                  </div>
                  <div className="flex items-center gap-1.5 flex-wrap">
                    <button type="button" onClick={selectAllEdit}
                      className="px-2.5 py-1 rounded-lg text-[11px] font-bold bg-indigo-600/20 text-indigo-300 hover:bg-indigo-600/30 border border-indigo-500/30 flex items-center gap-1 transition-colors">
                      <CheckSquare className="w-3.5 h-3.5" />
                      {isAr ? 'تحديد كل أقسام اللوحة (الكل)' : 'Select All'}
                    </button>
                    <button type="button" onClick={deselectAllEdit}
                      className="px-2.5 py-1 rounded-lg text-[11px] font-medium bg-white/5 text-slate-400 hover:text-white hover:bg-white/10 transition-colors">
                      <Square className="w-3.5 h-3.5" />
                      {isAr ? 'إلغاء التحديد' : 'Deselect All'}
                    </button>
                    <button type="button" onClick={() => setEditForm(p => ({ ...p, permissions: getDefaultPermissionsForRole(p.role) }))}
                      className="px-2.5 py-1 rounded-lg text-[11px] font-medium bg-amber-500/10 text-amber-300 hover:bg-amber-500/20 border border-amber-500/20 transition-colors">
                      {isAr ? 'استعادة افتراضي الرتبة' : 'Role Defaults'}
                    </button>
                  </div>
                </div>

                {/* Filter input */}
                <div className="mb-3">
                  <input type="text" value={editPermSearch} onChange={e => setEditPermSearch(e.target.value)}
                    placeholder={isAr ? 'تصفية الأقسام (مثال: هدايا، وكالات، غرف)...' : 'Filter sections...'}
                    className="w-full bg-[#18181C] border border-white/10 rounded-xl py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500 placeholder:text-slate-600" />
                </div>

                {/* Categories */}
                <div className="space-y-3">
                  {PERMISSION_CATEGORIES.map(category => {
                    const filteredItems = category.items.filter(item =>
                      !editPermSearch ||
                      item.ar.toLowerCase().includes(editPermSearch.toLowerCase()) ||
                      item.en.toLowerCase().includes(editPermSearch.toLowerCase()) ||
                      item.key.toLowerCase().includes(editPermSearch.toLowerCase())
                    );
                    if (filteredItems.length === 0) return null;

                    const catSelectedCount = category.items.filter(i => !!editForm.permissions[i.key]).length;
                    const allCatSelected = catSelectedCount === category.items.length;

                    return (
                      <div key={category.id} className="bg-[#18181C] border border-white/5 rounded-xl p-3 space-y-2">
                        <div className={`flex items-center justify-between pb-2 border-b border-white/5 ${isAr ? 'flex-row-reverse' : ''}`}>
                          <div className={`flex items-center gap-2 ${isAr ? 'flex-row-reverse' : ''}`}>
                            <span className="text-xs font-bold text-slate-200">{isAr ? category.ar : category.en}</span>
                            <span className="text-[10px] px-1.5 py-0.5 rounded-md font-mono bg-indigo-500/10 text-indigo-300 border border-indigo-500/20">
                              {catSelectedCount} / {category.items.length}
                            </span>
                          </div>
                          <button type="button" onClick={() => toggleCategoryEdit(category.id)}
                            className="text-[10px] font-semibold text-indigo-400 hover:text-indigo-300 transition-colors">
                            {allCatSelected ? (isAr ? 'إلغاء تحديد القسم' : 'Deselect') : (isAr ? 'تحديد كل القسم' : 'Select Category')}
                          </button>
                        </div>
                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
                          {filteredItems.map(item => (
                            <label key={item.key}
                              className={`flex items-center gap-2 px-2.5 py-1.5 rounded-lg cursor-pointer text-[11px] transition-all ${
                                editForm.permissions[item.key]
                                  ? 'bg-indigo-500/15 text-indigo-200 border border-indigo-500/30'
                                  : 'bg-black/20 text-slate-400 hover:bg-white/5 hover:text-slate-300 border border-transparent'
                              } ${isAr ? 'flex-row-reverse' : ''}`}>
                              <input type="checkbox" checked={!!editForm.permissions[item.key]}
                                onChange={e => setEditForm(prev => ({
                                  ...prev,
                                  permissions: { ...prev.permissions, [item.key]: e.target.checked }
                                }))}
                                className="accent-indigo-500 rounded" />
                              <span className="flex-1 select-none">{isAr ? item.ar : item.en}</span>
                            </label>
                          ))}
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>

            <div className="p-4 border-t border-white/10 bg-[#17171B] flex items-center justify-end gap-2 shrink-0">
              <button type="button" onClick={() => setEditingAdmin(null)}
                className="px-4 py-2 rounded-xl text-xs font-semibold bg-white/5 hover:bg-white/10 text-slate-300 transition-colors">
                {t('cancel')}
              </button>
              <button type="button" onClick={handleEditSave}
                className="px-5 py-2 rounded-xl text-xs font-bold bg-indigo-600 hover:bg-indigo-700 text-white shadow-lg shadow-indigo-600/25 flex items-center gap-1.5 transition-all">
                <Save className="w-3.5 h-3.5" />
                {t('save')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* === DELETE CONFIRMATION === */}
      {confirmDelete && (
        <div className="fixed inset-0 bg-black/60 z-50 flex items-center justify-center p-4 backdrop-blur-sm" onClick={() => setConfirmDelete(null)}>
          <div className="bg-[#141417] border border-white/10 rounded-2xl p-6 w-full max-w-sm space-y-4 shadow-2xl" onClick={e => e.stopPropagation()}>
            <div className="flex items-center gap-2 text-rose-400">
              <AlertTriangle className="w-5 h-5" />
              <h3 className="text-white font-semibold text-sm">{isAr ? 'تأكيد الحذف' : 'Confirm Delete'}</h3>
            </div>
            <p className="text-slate-400 text-xs">{isAr ? 'هل أنت متأكد من حذف هذا المشرف؟ لا يمكن التراجع عن هذا الإجراء.' : 'Are you sure you want to delete this admin? This cannot be undone.'}</p>
            <div className={`flex gap-2 ${isAr ? 'flex-row-reverse' : ''}`}>
              <button onClick={() => setConfirmDelete(null)} className="flex-1 py-2 bg-white/5 hover:bg-white/10 text-xs text-slate-300 font-semibold rounded-lg">{t('cancel')}</button>
              <button onClick={() => handleDelete(confirmDelete)} className="flex-1 py-2 bg-rose-600 hover:bg-rose-700 text-xs text-white font-semibold rounded-lg">{t('delete')}</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
