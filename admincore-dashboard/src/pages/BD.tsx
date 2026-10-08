import { useEffect, useState, useContext } from 'react';
import { I18nContext } from '../lib/i18n';
import { useOutletContext } from 'react-router-dom';
import { onAuthChange, type AppUser } from '../lib/auth';
import {
  Briefcase, UserPlus, Trash2, Building, Users, DollarSign,
  Award, Crown, Sparkles, Search, Save, X, Eye, Shield,
  CheckCircle, AlertTriangle, RefreshCw, ChevronRight, Layers, Percent, Edit3
} from 'lucide-react';
import {
  getBDManagers, assignBDManager, updateBDManager, revokeBDManager, getBDAgencies,
  getAdminUsers, getBadges, getNecklaces, getStoreItems, searchUserProfile
} from '../lib/db';
import type { BDModel, BDAgencyDetail, AdminUser, BadgeConfig, NecklaceConfig, StoreItemModel } from '../types';

export default function BDPage() {
  const { t, lang } = useContext(I18nContext);
  const isAr = lang === 'ar';

  const outletCtx = useOutletContext<{ currentUser?: AppUser | null }>();
  const [currentUser, setCurrentUser] = useState<AppUser | null>(() => outletCtx?.currentUser || null);

  useEffect(() => {
    if (outletCtx?.currentUser) {
      setCurrentUser(outletCtx.currentUser);
    } else {
      const unsub = onAuthChange(u => setCurrentUser(u));
      return unsub;
    }
  }, [outletCtx?.currentUser]);

  const [bds, setBds] = useState<BDModel[]>([]);
  const [admins, setAdmins] = useState<AdminUser[]>([]);
  const [badges, setBadges] = useState<BadgeConfig[]>([]);
  const [necklaces, setNecklaces] = useState<NecklaceConfig[]>([]);
  const [frames, setFrames] = useState<StoreItemModel[]>([]);
  const [loading, setLoading] = useState(true);

  const [searchQ, setSearchQ] = useState('');
  const [supervisorFilter, setSupervisorFilter] = useState('');

  // Assign Modal
  const [showAssignModal, setShowAssignModal] = useState(false);
  const [assignForm, setAssignForm] = useState({
    appId: '',
    uid: '',
    name: '',
    supervisorId: '',
    salary: 0,
    commissionRate: 10,
    specialId: '',
    frameId: '',
    badgeId: '',
    necklaceId: '',
  });
  const [searchedUser, setSearchedUser] = useState<any>(null);
  const [searchingUser, setSearchingUser] = useState(false);
  const [assignSaving, setAssignSaving] = useState(false);
  const [assignError, setAssignError] = useState('');

  // Edit BD Modal
  const [editingBd, setEditingBd] = useState<BDModel | null>(null);
  const [editForm, setEditForm] = useState({
    supervisorId: '',
    salary: 0,
    commissionRate: 10,
    specialId: '',
    frameId: '',
    badgeId: '',
    necklaceId: '',
  });
  const [editSaving, setEditSaving] = useState(false);
  const [editError, setEditError] = useState('');

  // Viewing Agencies Modal
  const [activeBdAgencies, setActiveBdAgencies] = useState<{ bd: BDModel; agencies: BDAgencyDetail[] } | null>(null);
  const [loadingAgencies, setLoadingAgencies] = useState(false);

  // Revoke Dialog
  const [confirmRevoke, setConfirmRevoke] = useState<BDModel | null>(null);
  const [revoking, setRevoking] = useState(false);

  const isOwner = currentUser?.role === 'owner' ||
    (currentUser?.role === 'super_admin' && (currentUser?.permissions?.includes('all') || currentUser?.permissions?.includes('*'))) ||
    currentUser?.email?.toLowerCase() === 'admin@zero.app' ||
    currentUser?.email?.toLowerCase() === 'm3290556@gmail.com' ||
    currentUser?.email?.toLowerCase() === 'admin@ahlalive.com';

  const myAdminRecord = admins.find(a =>
    a.uid === currentUser?.id ||
    (currentUser?.email && a.email.toLowerCase() === currentUser.email.toLowerCase())
  );

  const openEditModal = (bd: BDModel) => {
    setEditingBd(bd);
    setEditForm({
      supervisorId: isOwner ? (bd.supervisorId || '') : (myAdminRecord?.uid || currentUser?.id || bd.supervisorId || ''),
      salary: bd.salary || 0,
      commissionRate: bd.commissionRate || 10,
      specialId: bd.specialId || bd.appId || '',
      frameId: bd.giftedFrame || '',
      badgeId: bd.giftedBadge || '',
      necklaceId: bd.giftedNecklace || '',
    });
    setEditError('');
  };

  const handleSaveEdit = async () => {
    if (!editingBd) return;
    setEditSaving(true);
    setEditError('');
    try {
      await updateBDManager({
        uid: editingBd.uid,
        appId: editForm.specialId || editingBd.appId,
        supervisorId: editForm.supervisorId || undefined,
        salary: Number(editForm.salary || 0),
        commissionRate: Number(editForm.commissionRate || 10),
        specialId: editForm.specialId.trim() || undefined,
        frameId: editForm.frameId || undefined,
        badgeId: editForm.badgeId || undefined,
        necklaceId: editForm.necklaceId || undefined,
      });
      setEditingBd(null);
      await loadData();
    } catch (e: any) {
      setEditError(e?.message || (isAr ? 'فشل تعديل بيانات مسؤول الـ BD' : 'Failed to update BD manager'));
    } finally {
      setEditSaving(false);
    }
  };

  const loadData = async () => {
    setLoading(true);
    try {
      const [bdList, adminList, badgeList, necklaceList, storeList] = await Promise.all([
        getBDManagers(),
        getAdminUsers(),
        getBadges().catch(() => []),
        getNecklaces().catch(() => []),
        getStoreItems().catch(() => []),
      ]);
      setBds(bdList);
      setAdmins(adminList);
      setBadges(badgeList || []);
      setNecklaces(necklaceList || []);
      setFrames((storeList || []).filter(item => item.category === 'frame' || (item as any).type === 'frame'));
    } catch (e) {
      console.error('Error loading BD data:', e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadData();
  }, []);

  const resetAssignForm = () => {
    setAssignForm({
      appId: '',
      uid: '',
      name: '',
      supervisorId: isOwner ? '' : (myAdminRecord?.uid || currentUser?.id || ''),
      salary: 0,
      commissionRate: 10,
      specialId: '',
      frameId: '',
      badgeId: '',
      necklaceId: '',
    });
    setSearchedUser(null);
    setSearchingUser(false);
    setAssignError('');
  };

  const handleAppIdChange = async (val: string) => {
    setAssignForm(p => ({ ...p, appId: val }));
    const term = val.trim();
    if (!term || term.length < 2) {
      setSearchedUser(null);
      return;
    }
    setSearchingUser(true);
    try {
      const profile = await searchUserProfile(term);
      if (profile) {
        setSearchedUser(profile);
        setAssignForm(p => ({
          ...p,
          uid: profile.uid || profile.id,
          name: profile.name || '',
          appId: profile.custom_id || profile.customId || term,
        }));
      } else {
        setSearchedUser(null);
      }
    } catch {
      setSearchedUser(null);
    } finally {
      setSearchingUser(false);
    }
  };

  const handleAssignSubmit = async () => {
    setAssignError('');
    const targetUid = assignForm.uid || searchedUser?.uid || searchedUser?.id;
    if (!targetUid) {
      setAssignError(isAr ? 'يرجى إدخال آيدي حساب صحيح في التطبيق للتعيين' : 'Please provide a valid App ID');
      return;
    }

    setAssignSaving(true);
    try {
      await assignBDManager({
        uid: targetUid,
        appId: assignForm.appId.trim(),
        name: assignForm.name || searchedUser?.name || 'BD Manager',
        supervisorId: assignForm.supervisorId || undefined,
        salary: Number(assignForm.salary || 0),
        commissionRate: Number(assignForm.commissionRate || 10),
        specialId: assignForm.specialId.trim() || undefined,
        frameId: assignForm.frameId || undefined,
        badgeId: assignForm.badgeId || undefined,
        necklaceId: assignForm.necklaceId || undefined,
      });

      setShowAssignModal(false);
      resetAssignForm();
      await loadData();
    } catch (e: any) {
      setAssignError(e?.message || (isAr ? 'فشل تعيين مسؤول الـ BD' : 'Failed to assign BD manager'));
    } finally {
      setAssignSaving(false);
    }
  };

  const handleRevokeConfirm = async () => {
    if (!confirmRevoke) return;
    setRevoking(true);
    try {
      await revokeBDManager(confirmRevoke.uid);
      setConfirmRevoke(null);
      await loadData();
    } catch (e: any) {
      alert(e?.message || (isAr ? 'فشل سحب صلاحيات الـ BD' : 'Failed to revoke BD'));
    } finally {
      setRevoking(false);
    }
  };

  const openAgenciesModal = async (bd: BDModel) => {
    setLoadingAgencies(true);
    setActiveBdAgencies({ bd, agencies: [] });
    try {
      const agencies = await getBDAgencies(bd.uid);
      setActiveBdAgencies({ bd, agencies });
    } catch (e) {
      console.error('Error fetching BD agencies:', e);
    } finally {
      setLoadingAgencies(false);
    }
  };

  const mySupervisorIdentifiers = new Set([
    currentUser?.id,
    myAdminRecord?.uid,
    myAdminRecord?.appId,
    currentUser?.email?.toLowerCase(),
    myAdminRecord?.email?.toLowerCase(),
  ].filter(Boolean));

  // If not owner, filter strictly to this supervisor's BDs!
  const scopedBds = isOwner
    ? bds
    : bds.filter(b =>
        (b.supervisorId && mySupervisorIdentifiers.has(b.supervisorId)) ||
        (b.supervisorName && (
          b.supervisorName === currentUser?.displayName ||
          b.supervisorName === myAdminRecord?.displayName ||
          b.supervisorName === currentUser?.email
        )) ||
        (currentUser?.id && b.supervisorId === currentUser.id)
      );

  // Filtered BDs
  const filteredBds = scopedBds.filter(b => {
    const matchSearch = !searchQ ||
      b.name.toLowerCase().includes(searchQ.toLowerCase()) ||
      (b.appId && b.appId.includes(searchQ)) ||
      (b.supervisorName && b.supervisorName.toLowerCase().includes(searchQ.toLowerCase()));
    const matchSup = !isOwner || !supervisorFilter || b.supervisorId === supervisorFilter;
    return matchSearch && matchSup;
  });

  // Summary Metrics calculated from scopedBds
  const totalAgencies = scopedBds.reduce((sum, b) => sum + (b.agencyCount || 0), 0);
  const totalHosts = scopedBds.reduce((sum, b) => sum + (b.totalHosts || 0), 0);
  const totalEarnings = scopedBds.reduce((sum, b) => sum + (b.totalEarnings || 0), 0);
  const totalSalaries = scopedBds.reduce((sum, b) => sum + (b.salary || 0), 0);

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className={`flex flex-col sm:flex-row sm:items-center justify-between gap-4 ${isAr ? 'sm:flex-row-reverse' : ''}`}>
        <div>
          <div className="flex items-center gap-2">
            <div className="p-2 bg-gradient-to-tr from-amber-500/20 to-orange-500/20 rounded-xl border border-amber-500/30 text-amber-400">
              <Briefcase className="w-5 h-5" />
            </div>
            <h2 className="text-white text-lg font-bold">
              {isOwner
                ? (isAr ? 'إدارة مسؤولي الـ BD والوكالات (BD Management)' : 'Business Development (BD) Management')
                : (isAr ? 'مركز الـ BD والوكالات التابعة لي' : 'My BD Center & Agencies')}
            </h2>
          </div>
          <p className="text-slate-400 text-xs mt-1">
            {isOwner
              ? (isAr ? 'تعيين مدراء الـ BD للمشرفين، مراقبة وكالاتهم، الأرباح، الرواتب، وإهداء المزايا الخاصة.' : 'Appoint BD managers under supervisors, monitor recruited agencies, profits, and manage rewards.')
              : (isAr ? `متابعة مسؤولي الـ BD التابعين لك، الوكالات المنضمة، الأرباح، والرواتب (${currentUser?.displayName || myAdminRecord?.displayName || 'مشرفك'})` : `Manage your assigned BD managers, their agencies, earnings, and salaries`)}
          </p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={loadData}
            className="p-2 rounded-xl bg-white/5 hover:bg-white/10 text-slate-300 border border-white/10 transition-colors"
            title={isAr ? 'تحديث' : 'Refresh'}
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
          </button>
          <button
            onClick={() => { resetAssignForm(); setShowAssignModal(true); }}
            className="px-4 py-2 bg-gradient-to-r from-amber-600 to-orange-600 hover:from-amber-700 hover:to-orange-700 text-white text-xs font-bold rounded-xl flex items-center gap-1.5 shadow-lg shadow-amber-600/20 transition-all"
          >
            <UserPlus className="w-4 h-4" />
            {isAr ? 'تعيين مسؤول BD جديد' : 'Assign New BD'}
          </button>
        </div>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 sm:gap-4">
        <div className="bg-[#141417] p-4 rounded-2xl border border-white/5 space-y-1">
          <div className="flex items-center justify-between text-slate-400 text-xs">
            <span>{isAr ? 'مسؤولي الـ BD' : 'Total BDs'}</span>
            <Briefcase className="w-4 h-4 text-amber-400" />
          </div>
          <div className="text-xl font-bold text-white font-mono">{scopedBds.length}</div>
        </div>

        <div className="bg-[#141417] p-4 rounded-2xl border border-white/5 space-y-1">
          <div className="flex items-center justify-between text-slate-400 text-xs">
            <span>{isAr ? 'إجمالي الوكالات التابعة' : 'Recruited Agencies'}</span>
            <Building className="w-4 h-4 text-indigo-400" />
          </div>
          <div className="text-xl font-bold text-indigo-400 font-mono">{totalAgencies}</div>
        </div>

        <div className="bg-[#141417] p-4 rounded-2xl border border-white/5 space-y-1">
          <div className="flex items-center justify-between text-slate-400 text-xs">
            <span>{isAr ? 'إجمالي المضيفين' : 'Total Hosts'}</span>
            <Users className="w-4 h-4 text-emerald-400" />
          </div>
          <div className="text-xl font-bold text-emerald-400 font-mono">{totalHosts}</div>
        </div>

        <div className="bg-[#141417] p-4 rounded-2xl border border-white/5 space-y-1">
          <div className="flex items-center justify-between text-slate-400 text-xs">
            <span>{isAr ? 'أرباح الوكالات (ماسات)' : 'Agencies Revenue'}</span>
            <DollarSign className="w-4 h-4 text-purple-400" />
          </div>
          <div className="text-xl font-bold text-purple-300 font-mono">💎 {totalEarnings.toLocaleString()}</div>
        </div>
      </div>

      {/* Filter and Search Bar */}
      <div className={`flex flex-col sm:flex-row items-center justify-between gap-3 ${isAr ? 'sm:flex-row-reverse' : ''}`}>
        <div className="relative flex-1 w-full sm:max-w-xs">
          <Search className={`w-3.5 h-3.5 absolute top-1/2 -translate-y-1/2 text-slate-500 pointer-events-none ${isAr ? 'right-3' : 'left-3'}`} />
          <input
            type="text"
            value={searchQ}
            onChange={e => setSearchQ(e.target.value)}
            placeholder={isAr ? 'بحث بالاسم أو الآيدي...' : 'Search by name or App ID...'}
            className={`w-full bg-[#161618] border border-white/10 rounded-xl py-2 ${isAr ? 'pr-9 pl-3' : 'pl-9 pr-3'} text-xs text-white focus:outline-none focus:border-amber-500 placeholder:text-slate-600`}
          />
        </div>

        {/* Supervisor Filter */}
        {isOwner ? (
          <div className="flex items-center gap-2 w-full sm:w-auto">
            <span className="text-xs text-slate-400 whitespace-nowrap">{isAr ? 'المشرف المسؤول:' : 'Supervisor:'}</span>
            <select
              value={supervisorFilter}
              onChange={e => setSupervisorFilter(e.target.value)}
              className="bg-[#161618] border border-white/10 rounded-xl py-1.5 px-3 text-xs text-white focus:outline-none focus:border-amber-500"
            >
              <option value="">{isAr ? 'جميع المشرفين' : 'All Supervisors'}</option>
              {admins.map(a => (
                <option key={a.uid} value={a.uid}>{a.displayName || a.email}</option>
              ))}
            </select>
          </div>
        ) : (
          <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-indigo-500/10 border border-indigo-500/20 text-indigo-300 text-xs font-semibold">
            <Shield className="w-3.5 h-3.5 text-indigo-400" />
            <span>{isAr ? 'المشرف المسؤول:' : 'Supervisor:'}</span>
            <span className="text-white font-bold">{currentUser?.displayName || myAdminRecord?.displayName || currentUser?.email}</span>
          </div>
        )}
      </div>

      {/* BD List Table */}
      <div className="bg-[#141417] rounded-2xl border border-white/5 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-white/5 text-slate-500 bg-[#161618]">
                <th className="text-right p-3 font-medium">{isAr ? 'مسؤول الـ BD' : 'BD Manager'}</th>
                <th className="text-right p-3 font-medium">{isAr ? 'آيدي الحساب' : 'App ID'}</th>
                <th className="text-right p-3 font-medium">{isAr ? 'المشرف المسؤول عنه' : 'Supervisor'}</th>
                <th className="text-center p-3 font-medium">{isAr ? 'الوكالات التابعة' : 'Agencies'}</th>
                <th className="text-center p-3 font-medium">{isAr ? 'المضيفين' : 'Hosts'}</th>
                <th className="text-right p-3 font-medium">{isAr ? 'أرباح الوكالات' : 'Agency Earnings'}</th>
                <th className="text-right p-3 font-medium">{isAr ? 'الراتب / العمولة' : 'Salary / Comm.'}</th>
                <th className="text-center p-3 font-medium">{isAr ? 'الإجراءات' : 'Actions'}</th>
              </tr>
            </thead>
            <tbody>
              {filteredBds.map(bd => (
                <tr key={bd.uid} className="border-b border-white/5 hover:bg-white/[0.02] transition-colors">
                  {/* BD Avatar & Name */}
                  <td className="p-3">
                    <div className="flex items-center gap-2.5">
                      <img
                        src={bd.photoUrl || `https://ui-avatars.com/api/?name=${encodeURIComponent(bd.name)}&background=random`}
                        alt=""
                        className="w-8 h-8 rounded-full object-cover border border-amber-500/40"
                      />
                      <div>
                        <div className="font-bold text-white flex items-center gap-1.5">
                          <span>{bd.name}</span>
                          <span className="px-1.5 py-0.5 rounded text-[9px] font-bold bg-amber-500/20 text-amber-300 border border-amber-500/30">
                            BD
                          </span>
                        </div>
                        {bd.email && <div className="text-[10px] text-slate-500">{bd.email}</div>}
                      </div>
                    </div>
                  </td>

                  {/* App ID */}
                  <td className="p-3 font-mono font-bold text-slate-300">
                    <span className="bg-white/5 px-2 py-1 rounded-lg border border-white/10">
                      #{bd.appId || '---'}
                    </span>
                  </td>

                  {/* Supervisor */}
                  <td className="p-3 text-slate-300">
                    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-indigo-500/10 text-indigo-300 text-[11px] border border-indigo-500/20 font-medium">
                      <Shield className="w-3 h-3 text-indigo-400" />
                      {bd.supervisorName || isAr ? 'غير محدد' : 'None'}
                    </span>
                  </td>

                  {/* Agencies Count */}
                  <td className="p-3 text-center">
                    <button
                      onClick={() => openAgenciesModal(bd)}
                      className="inline-flex items-center gap-1 font-bold font-mono px-2 py-0.5 rounded-lg bg-indigo-500/20 text-indigo-300 hover:bg-indigo-500/30 border border-indigo-500/30 transition-colors"
                      title={isAr ? 'عرض الوكالات التابعة' : 'View Agencies'}
                    >
                      <Building className="w-3 h-3" />
                      {bd.agencyCount}
                    </button>
                  </td>

                  {/* Hosts Count */}
                  <td className="p-3 text-center font-mono font-semibold text-slate-300">
                    {bd.totalHosts}
                  </td>

                  {/* Earnings */}
                  <td className="p-3 font-mono font-bold text-purple-300">
                    💎 {bd.totalEarnings.toLocaleString()}
                  </td>

                  {/* Salary & Commission */}
                  <td className="p-3">
                    <div className="font-mono text-[11px] text-emerald-400 font-bold">
                      ${bd.salary.toLocaleString()}
                    </div>
                    <div className="text-[10px] text-slate-500 font-mono">
                      عمولة: {bd.commissionRate}%
                    </div>
                  </td>

                  {/* Actions */}
                  <td className="p-3">
                    <div className="flex items-center justify-center gap-1.5">
                      <button
                        onClick={() => openAgenciesModal(bd)}
                        className="p-1.5 rounded-lg bg-indigo-500/10 hover:bg-indigo-500/20 text-indigo-300 border border-indigo-500/20 transition-colors"
                        title={isAr ? 'عرض الوكالات التابعة' : 'View Agencies'}
                      >
                        <Eye className="w-3.5 h-3.5" />
                      </button>

                      <button
                        onClick={() => openEditModal(bd)}
                        className="p-1.5 rounded-lg bg-amber-500/10 hover:bg-amber-500/20 text-amber-300 border border-amber-500/20 transition-colors"
                        title={isAr ? 'تعديل بيانات وصلاحيات BD' : 'Edit BD Details'}
                      >
                        <Edit3 className="w-3.5 h-3.5" />
                      </button>

                      <button
                        onClick={() => setConfirmRevoke(bd)}
                        className="p-1.5 rounded-lg bg-rose-500/10 hover:bg-rose-500/20 text-rose-300 border border-rose-500/20 transition-colors"
                        title={isAr ? 'تجريد وحذف صلاحيات الـ BD' : 'Revoke BD privileges'}
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}

              {filteredBds.length === 0 && (
                <tr>
                  <td colSpan={8} className="p-8 text-center text-slate-500">
                    {isAr ? 'لا يوجد مسؤولي BD مسجلين حالياً' : 'No BD managers found'}
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* === ASSIGN BD MODAL === */}
      {showAssignModal && (
        <div className="fixed inset-0 bg-black/75 z-50 flex items-center justify-center p-3 sm:p-4 backdrop-blur-sm" onClick={() => setShowAssignModal(false)}>
          <div className="bg-[#141417] border border-white/10 rounded-2xl w-full max-w-2xl max-h-[92vh] flex flex-col shadow-2xl overflow-hidden" onClick={e => e.stopPropagation()}>
            {/* Modal Header */}
            <div className={`p-4 border-b border-white/10 flex items-center justify-between shrink-0 bg-[#17171B] ${isAr ? 'flex-row-reverse' : ''}`}>
              <div className="flex items-center gap-2">
                <div className="p-2 rounded-xl bg-amber-500/10 text-amber-400 border border-amber-500/20">
                  <Briefcase className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="text-white font-bold text-sm">
                    {isAr ? 'تعيين مسؤول BD جديد ومنح الصلاحيات' : 'Assign New BD Manager & Rewards'}
                  </h3>
                  <p className="text-[11px] text-slate-400">
                    {isAr ? 'ربط الحساب بالمشرف وتخصيص الراتب والعمولة والهدايا التلقائية' : 'Link BD to supervisor, configure compensation, and gift in-app items'}
                  </p>
                </div>
              </div>
              <button onClick={() => setShowAssignModal(false)} className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-white/5 transition-colors">
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Modal Body */}
            <div className="p-4 sm:p-6 overflow-y-auto space-y-4 flex-1 custom-scrollbar">
              {/* App ID Lookup */}
              <div className="bg-[#18181C] p-3.5 rounded-xl border border-amber-500/25 space-y-2.5">
                <label className="block text-[11px] font-bold text-amber-300">
                  {isAr ? 'آيدي الحساب في التطبيق (App ID) *' : 'App ID in Application *'}
                </label>
                <div className="relative">
                  <input
                    type="text"
                    value={assignForm.appId}
                    onChange={e => handleAppIdChange(e.target.value)}
                    placeholder={isAr ? 'اكتب الآيدي (مثال: 5000 أو 100234)...' : 'Enter User ID or custom_id...'}
                    className="w-full bg-[#141417] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500 font-mono"
                  />
                  {searchingUser && (
                    <div className="absolute left-3 top-2.5 text-[10px] text-amber-400 rtl:left-auto rtl:right-3">
                      {isAr ? 'جارٍ البحث...' : 'Searching...'}
                    </div>
                  )}
                </div>

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
                            #{searchedUser.custom_id || searchedUser.customId}
                          </span>
                        </div>
                        <div className="text-[10px] text-slate-400 font-mono">{searchedUser.uid || searchedUser.id}</div>
                      </div>
                    </div>
                    <span className="text-[11px] font-bold text-emerald-400 flex items-center gap-1">
                      <CheckCircle className="w-3.5 h-3.5" /> {isAr ? 'تم التحقق' : 'Verified'}
                    </span>
                  </div>
                )}
              </div>

              {/* Supervisor & Compensation */}
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                {/* Supervisor Selection */}
                <div>
                  <label className="block text-[11px] font-semibold text-slate-300 mb-1">
                    {isAr ? 'المشرف التابع له *' : 'Assigned Supervisor *'}
                  </label>
                  {isOwner ? (
                    <select
                      value={assignForm.supervisorId}
                      onChange={e => setAssignForm(p => ({ ...p, supervisorId: e.target.value }))}
                      className="w-full bg-[#18181C] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500"
                    >
                      <option value="">{isAr ? '-- اختر المشرف --' : '-- Select Supervisor --'}</option>
                      {admins.map(a => (
                        <option key={a.uid} value={a.uid}>{a.displayName || a.email} ({a.role})</option>
                      ))}
                    </select>
                  ) : (
                    <div className="w-full bg-[#141417] border border-white/10 rounded-xl py-2 px-3 text-xs text-slate-300 flex items-center gap-2">
                      <Shield className="w-3.5 h-3.5 text-indigo-400" />
                      <span className="font-semibold text-white">{currentUser?.displayName || myAdminRecord?.displayName || currentUser?.email}</span>
                      <span className="text-[10px] text-emerald-400 bg-emerald-500/10 px-1.5 py-0.5 rounded font-mono">
                        {isAr ? 'حسابك' : 'You'}
                      </span>
                    </div>
                  )}
                </div>

                {/* Monthly Salary */}
                <div>
                  <label className="block text-[11px] font-semibold text-slate-300 mb-1">
                    {isAr ? 'الراتب الشهري ($)' : 'Monthly Salary ($)'}
                  </label>
                  <input
                    type="number"
                    value={assignForm.salary}
                    onChange={e => setAssignForm(p => ({ ...p, salary: Number(e.target.value) }))}
                    className="w-full bg-[#18181C] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500 font-mono"
                  />
                </div>

                {/* Commission Rate */}
                <div>
                  <label className="block text-[11px] font-semibold text-slate-300 mb-1">
                    {isAr ? 'نسبة العمولة (%)' : 'Commission Rate (%)'}
                  </label>
                  <input
                    type="number"
                    value={assignForm.commissionRate}
                    onChange={e => setAssignForm(p => ({ ...p, commissionRate: Number(e.target.value) }))}
                    className="w-full bg-[#18181C] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500 font-mono"
                  />
                </div>
              </div>

              {/* Automatic Gifts Section */}
              <div className="bg-[#18181C] p-3.5 rounded-xl border border-amber-500/25 space-y-3">
                <div className={`flex items-center justify-between ${isAr ? 'flex-row-reverse' : ''}`}>
                  <label className="block text-[11px] font-bold text-amber-300 flex items-center gap-1.5">
                    <span>🎁</span>
                    <span>{isAr ? 'إهداء مزايا الـ BD التلقائية (آيدي مميز، إطار، وسام، قلادة)' : 'Automatic BD Gifts (Special ID, Frame, Badge, Necklace)'}</span>
                  </label>
                  <span className="text-[10px] text-amber-400/80">
                    {isAr ? 'تُمنح فور التعيين' : 'Granted on assignment'}
                  </span>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  {/* Special ID */}
                  <div>
                    <label className="block text-[10px] text-slate-400 mb-1 flex items-center gap-1">
                      <Sparkles className="w-3 h-3 text-amber-400" />
                      {isAr ? 'إهداء آيدي مميز جديد (اختياري)' : 'Gift Special ID (Optional)'}
                    </label>
                    <input
                      type="text"
                      value={assignForm.specialId}
                      onChange={e => setAssignForm(p => ({ ...p, specialId: e.target.value }))}
                      placeholder={isAr ? 'مثال: 7777 أو 888' : 'e.g. 7777'}
                      className="w-full bg-[#141417] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500 font-mono"
                    />
                  </div>

                  {/* Frame */}
                  <div>
                    <label className="block text-[10px] text-slate-400 mb-1 flex items-center gap-1">
                      <Crown className="w-3 h-3 text-amber-400" />
                      {isAr ? 'إهداء إطار' : 'Gift Frame'}
                    </label>
                    <select
                      value={assignForm.frameId}
                      onChange={e => setAssignForm(p => ({ ...p, frameId: e.target.value }))}
                      className="w-full bg-[#141417] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500"
                    >
                      <option value="">{isAr ? '-- بدون إطار --' : '-- No Frame --'}</option>
                      {frames.map((f: any) => (
                        <option key={f.id} value={f.id}>{f.name || f.id}</option>
                      ))}
                    </select>
                  </div>

                  {/* Badge */}
                  <div>
                    <label className="block text-[10px] text-slate-400 mb-1 flex items-center gap-1">
                      <Award className="w-3 h-3 text-amber-400" />
                      {isAr ? 'إهداء وسام' : 'Gift Badge'}
                    </label>
                    <select
                      value={assignForm.badgeId}
                      onChange={e => setAssignForm(p => ({ ...p, badgeId: e.target.value }))}
                      className="w-full bg-[#141417] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500"
                    >
                      <option value="">{isAr ? '-- بدون وسام --' : '-- No Badge --'}</option>
                      {badges.map((b: any) => (
                        <option key={b.id} value={b.id}>{b.name || b.id}</option>
                      ))}
                    </select>
                  </div>

                  {/* Necklace */}
                  <div>
                    <label className="block text-[10px] text-slate-400 mb-1 flex items-center gap-1">
                      <Layers className="w-3 h-3 text-amber-400" />
                      {isAr ? 'إهداء قلادة' : 'Gift Necklace'}
                    </label>
                    <select
                      value={assignForm.necklaceId}
                      onChange={e => setAssignForm(p => ({ ...p, necklaceId: e.target.value }))}
                      className="w-full bg-[#141417] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500"
                    >
                      <option value="">{isAr ? '-- بدون قلادة --' : '-- No Necklace --'}</option>
                      {necklaces.map((n: any) => (
                        <option key={n.id} value={n.id}>{n.name || n.id}</option>
                      ))}
                    </select>
                  </div>
                </div>
              </div>

              {assignError && (
                <div className="p-3 bg-rose-500/10 border border-rose-500/20 text-rose-300 text-xs rounded-xl flex items-center gap-2">
                  <AlertTriangle className="w-4 h-4 shrink-0" />
                  <span>{assignError}</span>
                </div>
              )}
            </div>

            {/* Modal Footer */}
            <div className="p-4 border-t border-white/10 bg-[#17171B] flex items-center justify-end gap-2 shrink-0">
              <button
                type="button"
                onClick={() => setShowAssignModal(false)}
                className="px-4 py-2 rounded-xl text-xs font-semibold bg-white/5 hover:bg-white/10 text-slate-300 transition-colors"
              >
                {t('cancel')}
              </button>
              <button
                type="button"
                onClick={handleAssignSubmit}
                disabled={assignSaving}
                className="px-5 py-2 rounded-xl text-xs font-bold bg-gradient-to-r from-amber-600 to-orange-600 hover:from-amber-700 hover:to-orange-700 disabled:opacity-50 text-white shadow-lg shadow-amber-600/25 flex items-center gap-1.5 transition-all"
              >
                <Save className="w-3.5 h-3.5" />
                {assignSaving ? t('saving') : (isAr ? 'حفظ وتعيين مسؤول الـ BD' : 'Save & Assign BD')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* === EDIT BD MODAL === */}
      {editingBd && (
        <div className="fixed inset-0 bg-black/75 z-50 flex items-center justify-center p-3 sm:p-4 backdrop-blur-sm" onClick={() => setEditingBd(null)}>
          <div className="bg-[#141417] border border-white/10 rounded-2xl w-full max-w-2xl max-h-[92vh] flex flex-col shadow-2xl overflow-hidden" onClick={e => e.stopPropagation()}>
            {/* Modal Header */}
            <div className={`p-4 border-b border-white/10 flex items-center justify-between shrink-0 bg-[#17171B] ${isAr ? 'flex-row-reverse' : ''}`}>
              <div className="flex items-center gap-2">
                <div className="p-2 rounded-xl bg-amber-500/10 text-amber-400 border border-amber-500/20">
                  <Edit3 className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="text-white font-bold text-sm">
                    {isAr ? `تعديل بيانات وصلاحيات BD (${editingBd.name})` : `Edit BD Manager (${editingBd.name})`}
                  </h3>
                  <p className="text-[11px] text-slate-400">
                    {isAr ? 'تعديل المشرف التابع له، الراتب، العمولة، أو إهداء مزايا إضافية' : 'Modify assigned supervisor, salary, commission, and items'}
                  </p>
                </div>
              </div>
              <button onClick={() => setEditingBd(null)} className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-white/5 transition-colors">
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Modal Body */}
            <div className="p-4 sm:p-6 overflow-y-auto space-y-4 flex-1 custom-scrollbar">
              {/* Account Info Banner */}
              <div className={`flex items-center justify-between p-3 rounded-xl bg-[#18181C] border border-white/10 ${isAr ? 'flex-row-reverse' : ''}`}>
                <div className={`flex items-center gap-2.5 ${isAr ? 'flex-row-reverse' : ''}`}>
                  <img
                    src={editingBd.photoUrl || `https://ui-avatars.com/api/?name=${encodeURIComponent(editingBd.name || 'BD')}&background=random`}
                    alt=""
                    className="w-10 h-10 rounded-full object-cover border border-amber-500/30"
                  />
                  <div>
                    <div className="text-xs font-bold text-white flex items-center gap-1.5">
                      <span>{editingBd.name}</span>
                      <span className="text-[10px] text-amber-400 font-mono font-bold bg-amber-500/10 px-1.5 py-0.5 rounded border border-amber-500/20">
                        #{editingBd.appId}
                      </span>
                    </div>
                    <div className="text-[10px] text-slate-400 font-mono">{editingBd.uid}</div>
                  </div>
                </div>
                <div className="text-right">
                  <div className="text-[11px] text-slate-400">{isAr ? 'الوكالات التابعة' : 'Agencies'}: <span className="font-bold text-indigo-400">{editingBd.agencyCount}</span></div>
                  <div className="text-[11px] text-slate-400">{isAr ? 'إجمالي المضيفين' : 'Hosts'}: <span className="font-bold text-purple-400">{editingBd.totalHosts}</span></div>
                </div>
              </div>

              {/* Supervisor & Compensation */}
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                {/* Supervisor Selection */}
                <div>
                  <label className="block text-[11px] font-semibold text-slate-300 mb-1">
                    {isAr ? 'المشرف التابع له *' : 'Assigned Supervisor *'}
                  </label>
                  {isOwner ? (
                    <select
                      value={editForm.supervisorId}
                      onChange={e => setEditForm(p => ({ ...p, supervisorId: e.target.value }))}
                      className="w-full bg-[#18181C] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500"
                    >
                      <option value="">{isAr ? '-- غير محدد / بدون مشرف --' : '-- None / No Supervisor --'}</option>
                      {admins.map(a => (
                        <option key={a.uid} value={a.uid}>{a.displayName || a.email} ({a.role})</option>
                      ))}
                    </select>
                  ) : (
                    <div className="w-full bg-[#141417] border border-white/10 rounded-xl py-2 px-3 text-xs text-slate-300 flex items-center gap-2">
                      <Shield className="w-3.5 h-3.5 text-indigo-400" />
                      <span className="font-semibold text-white">{currentUser?.displayName || myAdminRecord?.displayName || currentUser?.email}</span>
                      <span className="text-[10px] text-emerald-400 bg-emerald-500/10 px-1.5 py-0.5 rounded font-mono">
                        {isAr ? 'حسابك' : 'You'}
                      </span>
                    </div>
                  )}
                </div>

                {/* Monthly Salary */}
                <div>
                  <label className="block text-[11px] font-semibold text-slate-300 mb-1">
                    {isAr ? 'الراتب الشهري ($)' : 'Monthly Salary ($)'}
                  </label>
                  <input
                    type="number"
                    value={editForm.salary}
                    onChange={e => setEditForm(p => ({ ...p, salary: Number(e.target.value) }))}
                    className="w-full bg-[#18181C] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500 font-mono"
                  />
                </div>

                {/* Commission Rate */}
                <div>
                  <label className="block text-[11px] font-semibold text-slate-300 mb-1">
                    {isAr ? 'نسبة العمولة (%)' : 'Commission Rate (%)'}
                  </label>
                  <input
                    type="number"
                    value={editForm.commissionRate}
                    onChange={e => setEditForm(p => ({ ...p, commissionRate: Number(e.target.value) }))}
                    className="w-full bg-[#18181C] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500 font-mono"
                  />
                </div>
              </div>

              {/* Automatic Gifts Section */}
              <div className="bg-[#18181C] p-3.5 rounded-xl border border-amber-500/25 space-y-3">
                <div className={`flex items-center justify-between ${isAr ? 'flex-row-reverse' : ''}`}>
                  <label className="block text-[11px] font-bold text-amber-300 flex items-center gap-1.5">
                    <span>🎁</span>
                    <span>{isAr ? 'تعديل أو إهداء مزايا إضافية للـ BD' : 'Modify or Gift In-App Items'}</span>
                  </label>
                  <span className="text-[10px] text-amber-400/80">
                    {isAr ? 'تُطبق على الحساب' : 'Applied to account'}
                  </span>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  {/* Special ID */}
                  <div>
                    <label className="block text-[10px] text-slate-400 mb-1 flex items-center gap-1">
                      <Sparkles className="w-3 h-3 text-amber-400" />
                      {isAr ? 'الآيدي المميز' : 'Special ID'}
                    </label>
                    <input
                      type="text"
                      value={editForm.specialId}
                      onChange={e => setEditForm(p => ({ ...p, specialId: e.target.value }))}
                      placeholder={isAr ? 'مثال: 7777 أو 888' : 'e.g. 7777'}
                      className="w-full bg-[#141417] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500 font-mono"
                    />
                  </div>

                  {/* Frame */}
                  <div>
                    <label className="block text-[10px] text-slate-400 mb-1 flex items-center gap-1">
                      <Crown className="w-3 h-3 text-amber-400" />
                      {isAr ? 'إهداء إطار' : 'Gift Frame'}
                    </label>
                    <select
                      value={editForm.frameId}
                      onChange={e => setEditForm(p => ({ ...p, frameId: e.target.value }))}
                      className="w-full bg-[#141417] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500"
                    >
                      <option value="">{isAr ? '-- بدون تغيير الإطار --' : '-- No Change / None --'}</option>
                      {frames.map((f: any) => (
                        <option key={f.id || f.itemId} value={f.itemId || f.id}>{f.name}</option>
                      ))}
                    </select>
                  </div>

                  {/* Badge */}
                  <div>
                    <label className="block text-[10px] text-slate-400 mb-1 flex items-center gap-1">
                      <Award className="w-3 h-3 text-amber-400" />
                      {isAr ? 'إهداء وسام' : 'Gift Badge'}
                    </label>
                    <select
                      value={editForm.badgeId}
                      onChange={e => setEditForm(p => ({ ...p, badgeId: e.target.value }))}
                      className="w-full bg-[#141417] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500"
                    >
                      <option value="">{isAr ? '-- بدون تغيير الوسام --' : '-- No Change / None --'}</option>
                      {badges.map((b: any) => (
                        <option key={b.id} value={b.id}>{b.name || b.id}</option>
                      ))}
                    </select>
                  </div>

                  {/* Necklace */}
                  <div>
                    <label className="block text-[10px] text-slate-400 mb-1 flex items-center gap-1">
                      <Layers className="w-3 h-3 text-amber-400" />
                      {isAr ? 'إهداء قلادة' : 'Gift Necklace'}
                    </label>
                    <select
                      value={editForm.necklaceId}
                      onChange={e => setEditForm(p => ({ ...p, necklaceId: e.target.value }))}
                      className="w-full bg-[#141417] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-amber-500"
                    >
                      <option value="">{isAr ? '-- بدون تغيير القلادة --' : '-- No Change / None --'}</option>
                      {necklaces.map((n: any) => (
                        <option key={n.id} value={n.id}>{n.name || n.id}</option>
                      ))}
                    </select>
                  </div>
                </div>
              </div>

              {editError && (
                <div className="p-3 bg-rose-500/10 border border-rose-500/20 text-rose-300 text-xs rounded-xl flex items-center gap-2">
                  <AlertTriangle className="w-4 h-4 shrink-0" />
                  <span>{editError}</span>
                </div>
              )}
            </div>

            {/* Modal Footer */}
            <div className="p-4 border-t border-white/10 bg-[#17171B] flex items-center justify-end gap-2 shrink-0">
              <button
                type="button"
                onClick={() => setEditingBd(null)}
                className="px-4 py-2 rounded-xl text-xs font-semibold bg-white/5 hover:bg-white/10 text-slate-300 transition-colors"
              >
                {t('cancel')}
              </button>
              <button
                type="button"
                onClick={handleSaveEdit}
                disabled={editSaving}
                className="px-5 py-2 rounded-xl text-xs font-bold bg-gradient-to-r from-amber-600 to-orange-600 hover:from-amber-700 hover:to-orange-700 disabled:opacity-50 text-white shadow-lg shadow-amber-600/25 flex items-center gap-1.5 transition-all"
              >
                <Save className="w-3.5 h-3.5" />
                {editSaving ? t('saving') : (isAr ? 'حفظ التعديلات' : 'Save Changes')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* === VIEW BD AGENCIES MODAL === */}
      {activeBdAgencies && (
        <div className="fixed inset-0 bg-black/75 z-50 flex items-center justify-center p-3 sm:p-4 backdrop-blur-sm" onClick={() => setActiveBdAgencies(null)}>
          <div className="bg-[#141417] border border-white/10 rounded-2xl w-full max-w-3xl max-h-[90vh] flex flex-col shadow-2xl overflow-hidden" onClick={e => e.stopPropagation()}>
            <div className={`p-4 border-b border-white/10 flex items-center justify-between shrink-0 bg-[#17171B] ${isAr ? 'flex-row-reverse' : ''}`}>
              <div className="flex items-center gap-2.5">
                <div className="p-2 rounded-xl bg-indigo-500/10 text-indigo-400 border border-indigo-500/20">
                  <Building className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="text-white font-bold text-sm">
                    {isAr ? `الوكالات التابعة لـ: ${activeBdAgencies.bd.name}` : `Agencies under: ${activeBdAgencies.bd.name}`}
                  </h3>
                  <p className="text-[11px] text-slate-400">
                    {isAr ? `إجمالي الوكالات: ${activeBdAgencies.agencies.length}` : `Total Agencies: ${activeBdAgencies.agencies.length}`}
                  </p>
                </div>
              </div>
              <button onClick={() => setActiveBdAgencies(null)} className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-white/5 transition-colors">
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="p-4 sm:p-6 overflow-y-auto flex-1 custom-scrollbar">
              {loadingAgencies ? (
                <div className="p-12 text-center text-slate-500 flex items-center justify-center gap-2">
                  <RefreshCw className="w-4 h-4 animate-spin text-indigo-400" />
                  <span>{isAr ? 'جارٍ تحميل الوكالات...' : 'Loading agencies...'}</span>
                </div>
              ) : activeBdAgencies.agencies.length === 0 ? (
                <div className="p-12 text-center text-slate-500">
                  {isAr ? 'لا توجد وكالات منضمة عن طريق مسؤول الـ BD هذا حتى الآن' : 'No agencies recruited under this BD yet'}
                </div>
              ) : (
                <div className="bg-[#18181C] rounded-xl border border-white/5 overflow-hidden">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b border-white/5 text-slate-500 bg-[#141417]">
                        <th className="text-right p-3 font-medium">{isAr ? 'اسم الوكالة' : 'Agency Name'}</th>
                        <th className="text-center p-3 font-medium">{isAr ? 'عدد المضيفين' : 'Hosts'}</th>
                        <th className="text-right p-3 font-medium">{isAr ? 'أرباح الشهر' : 'Monthly Diamonds'}</th>
                        <th className="text-right p-3 font-medium">{isAr ? 'إجمالي الأرباح' : 'Total Diamonds'}</th>
                        <th className="text-center p-3 font-medium">{isAr ? 'الحالة' : 'Status'}</th>
                      </tr>
                    </thead>
                    <tbody>
                      {activeBdAgencies.agencies.map(ag => (
                        <tr key={ag.id} className="border-b border-white/5 hover:bg-white/[0.02]">
                          <td className="p-3">
                            <div className="font-bold text-white">{ag.name}</div>
                            <div className="text-[10px] text-slate-500 font-mono">ID: {ag.id}</div>
                          </td>
                          <td className="p-3 text-center font-mono font-semibold text-slate-300">
                            {ag.memberCount}
                          </td>
                          <td className="p-3 font-mono font-bold text-purple-300">
                            💎 {ag.monthlyDiamonds.toLocaleString()}
                          </td>
                          <td className="p-3 font-mono text-slate-400">
                            💎 {ag.totalDiamonds.toLocaleString()}
                          </td>
                          <td className="p-3 text-center">
                            <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
                              {ag.status}
                            </span>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>

            <div className="p-4 border-t border-white/10 bg-[#17171B] flex justify-end shrink-0">
              <button
                onClick={() => setActiveBdAgencies(null)}
                className="px-4 py-2 rounded-xl text-xs font-semibold bg-white/5 hover:bg-white/10 text-slate-300 transition-colors"
              >
                {t('close') || (isAr ? 'إغلاق' : 'Close')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* === REVOKE BD PRIVILEGES DIALOG === */}
      {confirmRevoke && (
        <div className="fixed inset-0 bg-black/80 z-50 flex items-center justify-center p-4 backdrop-blur-sm" onClick={() => setConfirmRevoke(null)}>
          <div className="bg-[#141417] border border-rose-500/30 rounded-2xl w-full max-w-md p-6 space-y-4 shadow-2xl" onClick={e => e.stopPropagation()}>
            <div className="flex items-center gap-3">
              <div className="p-3 rounded-full bg-rose-500/10 text-rose-400 border border-rose-500/20 shrink-0">
                <Trash2 className="w-6 h-6" />
              </div>
              <div>
                <h3 className="text-white font-bold text-sm">
                  {isAr ? 'تجريد وحذف صلاحيات الـ BD فوراً؟' : 'Revoke BD Privileges?'}
                </h3>
                <p className="text-slate-400 text-xs mt-0.5">
                  {confirmRevoke.name} (#{confirmRevoke.appId})
                </p>
              </div>
            </div>

            <div className="p-3 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-300 text-xs space-y-1">
              <p className="font-bold">⚠️ {isAr ? 'ما الذي سيحدث عند الحذف:' : 'What happens upon deletion:'}</p>
              <ul className="list-disc list-inside space-y-0.5 text-[11px] text-rose-300/90">
                <li>{isAr ? 'سيتم تجريد المستخدم من رتبة الـ BD فوراً.' : 'User will be stripped of BD role immediately.'}</li>
                <li>{isAr ? 'ستختفي شاشة «مركز الـ BD» من حسابه داخل التطبيق مباشرة.' : 'In-App BD Center will be instantly hidden from their profile.'}</li>
                <li>{isAr ? 'إلغاء ربطه بالمشرف وإيقاف الراتب والعمولات.' : 'Supervisor link, salary, and commissions will be revoked.'}</li>
              </ul>
            </div>

            <div className="flex items-center justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setConfirmRevoke(null)}
                className="px-4 py-2 rounded-xl text-xs font-semibold bg-white/5 hover:bg-white/10 text-slate-300 transition-colors"
              >
                {t('cancel')}
              </button>
              <button
                type="button"
                onClick={handleRevokeConfirm}
                disabled={revoking}
                className="px-5 py-2 rounded-xl text-xs font-bold bg-rose-600 hover:bg-rose-700 disabled:opacity-50 text-white shadow-lg shadow-rose-600/30 flex items-center gap-1.5 transition-all"
              >
                <Trash2 className="w-3.5 h-3.5" />
                {revoking ? (isAr ? 'جارٍ الحذف...' : 'Revoking...') : (isAr ? 'تأكيد الحذف والتجريد' : 'Confirm Revoke')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
