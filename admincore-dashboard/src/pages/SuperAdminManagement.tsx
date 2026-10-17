import React, { useEffect, useState, useContext } from 'react';
import { I18nContext } from '../lib/i18n';
import { useOutletContext } from 'react-router-dom';
import { onAuthChange, type AppUser } from '../lib/auth';
import {
  Crown, Shield, Briefcase, Eye, EyeOff, Copy, Percent, ArrowLeftRight, UserPlus,
  Search, Save, X, Edit3, Trash2, CheckCircle, AlertTriangle, RefreshCw,
  Building, Users, DollarSign, Award, Sparkles, CheckSquare, Square, PlusCircle, Check
} from 'lucide-react';
import {
  getSuperAdmins, assignSuperAdmin, updateSuperAdmin, revokeSuperAdmin,
  getAdmins, assignAdmin, updateAdminStaff, revokeAdminStaff,
  getBDManagers, assignBDManager, updateBDManager, revokeBDManager,
  getStaffCommissionConfigs, saveStaffCommissionConfigs, getSalaryTransfers, getHostAgencies, updateHostAgency,
  getBadges, getNecklaces, getStoreItems, searchUserProfile,
  type SuperAdminModel, type AdminStaffModel, type SalaryTransferRequest
} from '../lib/db';
import { PERMISSION_CATEGORIES, ALL_PERMISSIONS } from '../lib/permissions';
import type { BDModel, BadgeConfig, NecklaceConfig, StoreItemModel, HostAgencyModel } from '../types';

export default function SuperAdminManagement() {
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

  const [activeTab, setActiveTab] = useState<'super_admins' | 'admins' | 'bds' | 'commissions' | 'transfers'>('super_admins');
  const [loading, setLoading] = useState(true);

  // Data lists
  const [superAdmins, setSuperAdmins] = useState<SuperAdminModel[]>([]);
  const [admins, setAdmins] = useState<AdminStaffModel[]>([]);
  const [bds, setBds] = useState<BDModel[]>([]);
  const [transfers, setTransfers] = useState<SalaryTransferRequest[]>([]);
  const [hostAgencies, setHostAgencies] = useState<HostAgencyModel[]>([]);
  const [agencySearchQ, setAgencySearchQ] = useState('');
  const [agencyRates, setAgencyRates] = useState<Record<string, number>>({});
  const [savingAgencyId, setSavingAgencyId] = useState<string | null>(null);
  const [agencySaveSuccess, setAgencySaveSuccess] = useState<string | null>(null);
  const [commConfigs, setCommConfigs] = useState({
    superAdminRate: 15,
    adminRate: 10,
    bdRate: 10,
    tiers: [
      { targetDiamonds: 10000000, bonusPercentage: 2, description: '10M Target Milestone' },
      { targetDiamonds: 50000000, bonusPercentage: 5, description: '50M Target Milestone' },
      { targetDiamonds: 100000000, bonusPercentage: 10, description: '100M Super Target Milestone' },
    ],
  });

  // Cosmetics
  const [badges, setBadges] = useState<BadgeConfig[]>([]);
  const [necklaces, setNecklaces] = useState<NecklaceConfig[]>([]);
  const [frames, setFrames] = useState<StoreItemModel[]>([]);

  // Search
  const [searchQ, setSearchQ] = useState('');

  // Modals state
  const [showAssignModal, setShowAssignModal] = useState(false);
  const [assignRole, setAssignRole] = useState<'super_admin' | 'admin' | 'bd'>('super_admin');
  const [assignForm, setAssignForm] = useState({
    uid: '',
    appId: '',
    name: '',
    email: '',
    password: '',
    supervisorId: '',
    salary: 0,
    commissionRate: 15,
    specialId: '',
    frameId: '',
    badgeId: '',
    necklaceId: '',
    permissions: {} as Record<string, boolean>,
  });
  const [searchedUser, setSearchedUser] = useState<any>(null);
  const [searchingUser, setSearchingUser] = useState(false);
  const [assignSaving, setAssignSaving] = useState(false);
  const [showAssignPass, setShowAssignPass] = useState(false);
  const [revealedPass, setRevealedPass] = useState<Record<string, boolean>>({});
  const [copiedPass, setCopiedPass] = useState<string | null>(null);
  const [assignError, setAssignError] = useState('');

  // Edit Staff Modal
  const [editingStaff, setEditingStaff] = useState<any>(null);
  const [editRole, setEditRole] = useState<'super_admin' | 'admin' | 'bd'>('super_admin');
  const [editForm, setEditForm] = useState({
    salary: 0,
    commissionRate: 15,
    supervisorId: '',
    permissions: {} as Record<string, boolean>,
  });
  const [editSaving, setEditSaving] = useState(false);

  const [savingComms, setSavingComms] = useState(false);
  const [commSuccess, setCommSuccess] = useState(false);

  const fetchAllData = async () => {
    setLoading(true);
    try {
      const [saData, admData, bdData, commData, transData, bdgData, nckData, stData, agData] = await Promise.all([
        getSuperAdmins(),
        getAdmins(),
        getBDManagers(),
        getStaffCommissionConfigs(),
        getSalaryTransfers(),
        getBadges(),
        getNecklaces(),
        getStoreItems(),
        getHostAgencies().catch(() => []),
      ]);
      setSuperAdmins(saData);
      setAdmins(admData);
      setBds(bdData);
      setCommConfigs(commData);
      setTransfers(transData);
      setBadges(bdgData || []);
      setNecklaces(nckData || []);
      setFrames((stData || []).filter(i => i.category === 'frame'));
      setHostAgencies(agData || []);
      const initialRates: Record<string, number> = {};
      (agData || []).forEach((a: any) => {
        initialRates[a.id] = a.data?.commission_rate ?? a.commission_rate ?? 10;
      });
      setAgencyRates(initialRates);
    } catch (e) {
      console.error('SuperAdminManagement fetch error:', e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchAllData();
  }, []);

  const handleSearchUser = async () => {
    const q = assignForm.appId.trim();
    if (!q) return;
    setSearchingUser(true);
    setAssignError('');
    try {
      const u = await searchUserProfile(q);
      if (u) {
        setSearchedUser(u);
        setAssignForm(prev => ({
          ...prev,
          uid: u.uid || u.id,
          name: u.name || '',
          email: u.email || (u.custom_id ? `admin_${u.custom_id}` : `${u.uid}@staff.ahla.live`),
          password: prev.password || ('Ahla@' + Math.floor(100000 + Math.random() * 900000)),
        }));
      } else {
        setSearchedUser(null);
        setAssignError(isAr ? 'لم يتم العثور على المستخدم' : 'User not found');
      }
    } catch (e: any) {
      setAssignError(e.message || 'Search failed');
    } finally {
      setSearchingUser(false);
    }
  };

  const handleOpenAssignModal = (role: 'super_admin' | 'admin' | 'bd') => {
    setAssignRole(role);
    const defaultPerms: Record<string, boolean> = {};
    ALL_PERMISSIONS.forEach(k => {
      defaultPerms[k] = role === 'super_admin';
    });
    setAssignForm({
      uid: '',
      appId: '',
      name: '',
      email: '',
      password: 'Ahla@' + Math.floor(100000 + Math.random() * 900000),
      supervisorId: '',
      salary: role === 'super_admin' ? 1000 : role === 'admin' ? 500 : 200,
      commissionRate: role === 'super_admin' ? 15 : 10,
      specialId: '',
      frameId: '',
      badgeId: '',
      necklaceId: '',
      permissions: defaultPerms,
    });
    setSearchedUser(null);
    setAssignError('');
    setShowAssignModal(true);
  };

  const handleSaveAssign = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!assignForm.uid) {
      setAssignError(isAr ? 'يرجى البحث وتحديد المستخدم أولاً' : 'Please select a user first');
      return;
    }
    setAssignSaving(true);
    setAssignError('');
    try {
      if (assignRole === 'super_admin') {
        await assignSuperAdmin(assignForm);
      } else if (assignRole === 'admin') {
        await assignAdmin(assignForm);
      } else {
        await assignBDManager({
          uid: assignForm.uid,
          appId: assignForm.appId,
          name: assignForm.name,
          supervisorId: assignForm.supervisorId,
          salary: assignForm.salary,
          commissionRate: assignForm.commissionRate,
          specialId: assignForm.specialId,
          frameId: assignForm.frameId,
          badgeId: assignForm.badgeId,
          necklaceId: assignForm.necklaceId,
        });
      }
      setShowAssignModal(false);
      fetchAllData();
    } catch (err: any) {
      setAssignError(err.message || 'Operation failed');
    } finally {
      setAssignSaving(false);
    }
  };

  const handleSaveEdit = async () => {
    if (!editingStaff) return;
    setEditSaving(true);
    try {
      if (editRole === 'super_admin') {
        await updateSuperAdmin({
          uid: editingStaff.uid,
          salary: editForm.salary,
          commissionRate: editForm.commissionRate,
          permissions: editForm.permissions,
          password: (editForm as any).password || undefined,
        });
      } else if (editRole === 'admin') {
        await updateAdminStaff({
          uid: editingStaff.uid,
          salary: editForm.salary,
          commissionRate: editForm.commissionRate,
          supervisorId: editForm.supervisorId,
          permissions: editForm.permissions,
          password: (editForm as any).password || undefined,
        });
      } else {
        await updateBDManager({
          uid: editingStaff.uid,
          salary: editForm.salary,
          commissionRate: editForm.commissionRate,
          supervisorId: editForm.supervisorId,
        });
      }
      setEditingStaff(null);
      fetchAllData();
    } catch (err) {
      console.error(err);
    } finally {
      setEditSaving(false);
    }
  };

  const handleRevoke = async (uid: string, role: 'super_admin' | 'admin' | 'bd') => {
    if (!confirm(isAr ? 'هل أنت متأكد من سحب هذه الصلاحيات؟' : 'Are you sure you want to revoke this role?')) return;
    try {
      if (role === 'super_admin') await revokeSuperAdmin(uid);
      else if (role === 'admin') await revokeAdminStaff(uid);
      else await revokeBDManager(uid);
      fetchAllData();
    } catch (e) {
      console.error(e);
    }
  };

  
  const handleAddTier = () => {
    setCommConfigs(prev => ({
      ...prev,
      tiers: [
        ...(prev.tiers || []),
        { targetDiamonds: 100000000, bonusPercentage: 10, description: isAr ? 'تارجت 100M' : '100M Target' }
      ]
    }));
  };

  const handleRemoveTier = (idx: number) => {
    setCommConfigs(prev => ({
      ...prev,
      tiers: (prev.tiers || []).filter((_, i) => i !== idx)
    }));
  };

  const handleUpdateTier = (idx: number, field: string, val: any) => {
    setCommConfigs(prev => {
      const updated = [...(prev.tiers || [])];
      updated[idx] = { ...updated[idx], [field]: val };
      return { ...prev, tiers: updated };
    });
  };

  const handleSaveAgencyRate = async (agencyId: string) => {
    setSavingAgencyId(agencyId);
    try {
      const rate = agencyRates[agencyId] ?? 10;
      await updateHostAgency(agencyId, { commission_rate: rate });
      setAgencySaveSuccess(agencyId);
      setTimeout(() => setAgencySaveSuccess(null), 3000);
    } catch (err) {
      console.error(err);
    } finally {
      setSavingAgencyId(null);
    }
  };

  const handleSaveCommissions = async () => {
    setSavingComms(true);
    setCommSuccess(false);
    try {
      await saveStaffCommissionConfigs(commConfigs);
      setCommSuccess(true);
      setTimeout(() => setCommSuccess(false), 3000);
    } catch (e) {
      console.error(e);
    } finally {
      setSavingComms(false);
    }
  };

  return (
    <div className="p-4 md:p-8 space-y-6 max-w-7xl mx-auto" dir={isAr ? 'rtl' : 'ltr'}>
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 bg-gradient-to-r from-amber-950/40 via-purple-950/30 to-slate-900 border border-amber-500/20 rounded-2xl p-6 shadow-xl backdrop-blur-md">
        <div className="flex items-center gap-4">
          <div className="w-14 h-14 rounded-2xl bg-gradient-to-tr from-amber-500 to-amber-300 flex items-center justify-center text-slate-950 shadow-lg shadow-amber-500/20">
            <Crown size={32} />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-white flex items-center gap-2">
              {isAr ? 'إدارة Super Admin والطاقم الإداري' : 'Super Admin & Staff Management'}
              <span className="text-xs bg-amber-500/20 text-amber-300 border border-amber-500/30 px-2 py-0.5 rounded-full font-mono">
                CENTRAL HUB
              </span>
            </h1>
            <p className="text-sm text-slate-400 mt-1">
              {isAr
                ? 'إدارة وتعيين السوبر أدمن، الأدمن، مسؤولي الـ BD، إعدادات عمولة التارجت، وسجلات صرف الرواتب'
                : 'Appoint & manage Super Admins, Admins, BDs, target commissions, and salary disbursements'}
            </p>
          </div>
        </div>
        <button
          onClick={fetchAllData}
          disabled={loading}
          className="flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-slate-800/80 hover:bg-slate-700 text-slate-300 hover:text-white border border-slate-700/50 transition-all text-sm font-medium"
        >
          <RefreshCw size={16} className={loading ? 'animate-spin' : ''} />
          {isAr ? 'تحديث البيانات' : 'Refresh'}
        </button>
      </div>

      {/* Navigation Tabs */}
      <div className="flex overflow-x-auto gap-2 p-1.5 bg-slate-900/80 border border-slate-800 rounded-xl">
        <button
          onClick={() => setActiveTab('super_admins')}
          className={`flex items-center gap-2 px-5 py-3 rounded-lg text-sm font-bold transition-all whitespace-nowrap ${
            activeTab === 'super_admins'
              ? 'bg-gradient-to-r from-amber-500 to-amber-600 text-slate-950 shadow-lg shadow-amber-500/25'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/50'
          }`}
        >
          <Crown size={18} />
          {isAr ? 'السوبر أدمن (Super Admin)' : 'Super Admins'}
          <span className="text-xs bg-black/20 px-2 py-0.5 rounded-full">{superAdmins.length}</span>
        </button>
        <button
          onClick={() => setActiveTab('admins')}
          className={`flex items-center gap-2 px-5 py-3 rounded-lg text-sm font-bold transition-all whitespace-nowrap ${
            activeTab === 'admins'
              ? 'bg-gradient-to-r from-rose-500 to-rose-600 text-white shadow-lg shadow-rose-500/25'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/50'
          }`}
        >
          <Shield size={18} />
          {isAr ? 'الأدمن (Admins)' : 'Admins'}
          <span className="text-xs bg-black/20 px-2 py-0.5 rounded-full">{admins.length}</span>
        </button>
        <button
          onClick={() => setActiveTab('bds')}
          className={`flex items-center gap-2 px-5 py-3 rounded-lg text-sm font-bold transition-all whitespace-nowrap ${
            activeTab === 'bds'
              ? 'bg-gradient-to-r from-indigo-500 to-indigo-600 text-white shadow-lg shadow-indigo-500/25'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/50'
          }`}
        >
          <Briefcase size={18} />
          {isAr ? 'مسؤولو الـ BD' : 'BD Managers'}
          <span className="text-xs bg-black/20 px-2 py-0.5 rounded-full">{bds.length}</span>
        </button>
        <button
          onClick={() => setActiveTab('commissions')}
          className={`flex items-center gap-2 px-5 py-3 rounded-lg text-sm font-bold transition-all whitespace-nowrap ${
            activeTab === 'commissions'
              ? 'bg-gradient-to-r from-emerald-500 to-emerald-600 text-white shadow-lg shadow-emerald-500/25'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/50'
          }`}
        >
          <Percent size={18} />
          {isAr ? 'عمولات تارجت الوكالات' : 'Target Commissions'}
        </button>
        <button
          onClick={() => setActiveTab('transfers')}
          className={`flex items-center gap-2 px-5 py-3 rounded-lg text-sm font-bold transition-all whitespace-nowrap ${
            activeTab === 'transfers'
              ? 'bg-gradient-to-r from-cyan-500 to-cyan-600 text-slate-950 shadow-lg shadow-cyan-500/25'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/50'
          }`}
        >
          <ArrowLeftRight size={18} />
          {isAr ? 'سجل صرف الرواتب' : 'Salary Transfers'}
          <span className="text-xs bg-black/20 px-2 py-0.5 rounded-full">{transfers.length}</span>
        </button>
      </div>

      {/* Tab 1: Super Admins */}
      {activeTab === 'super_admins' && (
        <div className="space-y-4">
          <div className="flex flex-col sm:flex-row justify-between items-stretch sm:items-center gap-3">
            <div className="relative flex-1 max-w-md">
              <Search className="absolute top-1/2 -translate-y-1/2 left-3 text-slate-400" size={18} />
              <input
                type="text"
                placeholder={isAr ? 'بحث بالاسم أو ID...' : 'Search Super Admin...'}
                value={searchQ}
                onChange={e => setSearchQ(e.target.value)}
                className="w-full pl-10 pr-4 py-2.5 bg-slate-900 border border-slate-800 rounded-xl text-white text-sm focus:outline-none focus:border-amber-500"
              />
            </div>
            <button
              onClick={() => handleOpenAssignModal('super_admin')}
              className="flex items-center justify-center gap-2 px-5 py-2.5 bg-gradient-to-r from-amber-500 to-amber-600 hover:from-amber-600 hover:to-amber-700 text-slate-950 font-bold rounded-xl shadow-lg shadow-amber-500/20 text-sm transition-all"
            >
              <UserPlus size={18} />
              {isAr ? 'تعيين Super Admin جديد' : 'Appoint Super Admin'}
            </button>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {superAdmins
              .filter(s => (s.name || '').toLowerCase().includes(searchQ.toLowerCase()) || (s.appId || '').includes(searchQ))
              .map(sa => (
                <div
                  key={sa.uid}
                  className="bg-slate-900/90 border border-amber-500/20 rounded-2xl p-5 hover:border-amber-500/40 transition-all shadow-lg flex flex-col justify-between"
                >
                  <div className="space-y-4">
                    <div className="flex items-center gap-3.5">
                      <div className="w-13 h-13 rounded-2xl bg-amber-500/20 border border-amber-500/30 flex items-center justify-center overflow-hidden shrink-0">
                        {sa.avatar ? (
                          <img src={sa.avatar} alt="" className="w-full h-full object-cover" />
                        ) : (
                          <Crown size={24} className="text-amber-400" />
                        )}
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <h3 className="font-bold text-white truncate">{sa.name || 'Super Admin'}</h3>
                          <span className="text-[10px] bg-amber-500/20 text-amber-300 font-bold px-2 py-0.5 rounded-md border border-amber-500/30">
                            SUPER
                          </span>
                        </div>
                        <p className="text-xs text-cyan-400 font-mono mt-0.5">ID: {sa.appId || sa.uid}</p>
                      </div>
                    </div>

                    <div className="p-3 bg-slate-950/80 border border-amber-500/20 rounded-xl space-y-1.5 text-xs font-mono">
                      <div className="flex items-center justify-between">
                        <span className="text-[10px] text-slate-500 font-sans">{isAr ? 'اسم الدخول للوحة:' : 'Login:'}</span>
                        <span className="text-cyan-300 font-bold truncate max-w-[170px]">{sa.loginUsername || sa.email || sa.appId || sa.uid}</span>
                      </div>
                      <div className="flex items-center justify-between">
                        <span className="text-[10px] text-slate-500 font-sans">{isAr ? 'كلمة المرور:' : 'Password:'}</span>
                        <div className="flex items-center gap-1.5">
                          <span className="text-amber-400 font-bold">
                            {revealedPass[sa.uid] ? (sa.password || '••••••') : '••••••••'}
                          </span>
                          <button
                            type="button"
                            onClick={() => setRevealedPass(p => ({ ...p, [sa.uid]: !p[sa.uid] }))}
                            className="text-slate-400 hover:text-white p-0.5"
                            title={isAr ? 'إظهار / إخفاء' : 'Show / Hide'}
                          >
                            {revealedPass[sa.uid] ? <EyeOff size={13} /> : <Eye size={13} />}
                          </button>
                          {sa.password && (
                            <button
                              type="button"
                              onClick={() => {
                                navigator.clipboard.writeText(sa.password!);
                                setCopiedPass(sa.uid);
                                setTimeout(() => setCopiedPass(null), 2000);
                              }}
                              className="text-emerald-400 hover:text-emerald-300 p-0.5 text-[10px] flex items-center gap-0.5"
                              title={isAr ? 'نسخ كلمة المرور' : 'Copy'}
                            >
                              {copiedPass === sa.uid ? <Check size={13} /> : <Copy size={13} />}
                            </button>
                          )}
                        </div>
                      </div>
                    </div>

                    <div className="grid grid-cols-2 gap-2 bg-slate-950/60 p-3 rounded-xl border border-slate-800/80">
                      <div>
                        <span className="text-[11px] text-slate-500 block">{isAr ? 'الراتب المعتمد' : 'Salary'}</span>
                        <span className="text-amber-400 font-bold text-sm font-mono">{sa.salary} ماسة / $</span>
                      </div>
                      <div>
                        <span className="text-[11px] text-slate-500 block">{isAr ? 'نسبة العمولة' : 'Commission'}</span>
                        <span className="text-emerald-400 font-bold text-sm font-mono">{sa.commissionRate}%</span>
                      </div>
                      <div className="mt-1">
                        <span className="text-[11px] text-slate-500 block">{isAr ? 'الوكالات التابعة' : 'Agencies'}</span>
                        <span className="text-cyan-400 font-bold text-sm font-mono">{sa.agenciesCount || 0}</span>
                      </div>
                      <div className="mt-1">
                        <span className="text-[11px] text-slate-500 block">{isAr ? 'مدراء BD تحت إشرافه' : 'BDs'}</span>
                        <span className="text-purple-400 font-bold text-sm font-mono">{sa.bdsCount || 0}</span>
                      </div>
                    </div>
                  </div>

                  <div className="flex items-center justify-end gap-2 mt-4 pt-3 border-t border-slate-800">
                    <button
                      onClick={() => {
                        setEditingStaff(sa);
                        setEditRole('super_admin');
                        setEditForm({
                          salary: sa.salary,
                          commissionRate: sa.commissionRate,
                          supervisorId: '',
                          permissions: {},
                        });
                      }}
                      className="px-3 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 hover:text-white text-xs font-medium flex items-center gap-1.5"
                    >
                      <Edit3 size={14} />
                      {isAr ? 'تعديل' : 'Edit'}
                    </button>
                    <button
                      onClick={() => handleRevoke(sa.uid, 'super_admin')}
                      className="px-3 py-1.5 rounded-lg bg-rose-500/10 hover:bg-rose-500/20 text-rose-400 text-xs font-medium flex items-center gap-1.5"
                    >
                      <Trash2 size={14} />
                      {isAr ? 'سحب' : 'Revoke'}
                    </button>
                  </div>
                </div>
              ))}
          </div>
        </div>
      )}

      {/* Tab 2: Admins */}
      {activeTab === 'admins' && (
        <div className="space-y-4">
          <div className="flex flex-col sm:flex-row justify-between items-stretch sm:items-center gap-3">
            <div className="relative flex-1 max-w-md">
              <Search className="absolute top-1/2 -translate-y-1/2 left-3 text-slate-400" size={18} />
              <input
                type="text"
                placeholder={isAr ? 'بحث بالاسم أو ID...' : 'Search Admin...'}
                value={searchQ}
                onChange={e => setSearchQ(e.target.value)}
                className="w-full pl-10 pr-4 py-2.5 bg-slate-900 border border-slate-800 rounded-xl text-white text-sm focus:outline-none focus:border-rose-500"
              />
            </div>
            <button
              onClick={() => handleOpenAssignModal('admin')}
              className="flex items-center justify-center gap-2 px-5 py-2.5 bg-gradient-to-r from-rose-500 to-rose-600 hover:from-rose-600 hover:to-rose-700 text-white font-bold rounded-xl shadow-lg shadow-rose-500/20 text-sm transition-all"
            >
              <UserPlus size={18} />
              {isAr ? 'تعيين Admin جديد' : 'Appoint Admin'}
            </button>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {admins
              .filter(a => (a.name || '').toLowerCase().includes(searchQ.toLowerCase()) || (a.appId || '').includes(searchQ))
              .map(adm => (
                <div
                  key={adm.uid}
                  className="bg-slate-900/90 border border-rose-500/20 rounded-2xl p-5 hover:border-rose-500/40 transition-all shadow-lg flex flex-col justify-between"
                >
                  <div className="space-y-4">
                    <div className="flex items-center gap-3.5">
                      <div className="w-13 h-13 rounded-2xl bg-rose-500/20 border border-rose-500/30 flex items-center justify-center overflow-hidden shrink-0">
                        {adm.avatar ? (
                          <img src={adm.avatar} alt="" className="w-full h-full object-cover" />
                        ) : (
                          <Shield size={24} className="text-rose-400" />
                        )}
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <h3 className="font-bold text-white truncate">{adm.name || 'Admin'}</h3>
                          <span className="text-[10px] bg-rose-500/20 text-rose-300 font-bold px-2 py-0.5 rounded-md border border-rose-500/30">
                            ADMIN
                          </span>
                        </div>
                        <p className="text-xs text-cyan-400 font-mono mt-0.5">ID: {adm.appId || adm.uid}</p>
                      </div>
                    </div>

                    <div className="p-3 bg-slate-950/80 border border-rose-500/20 rounded-xl space-y-1.5 text-xs font-mono">
                      <div className="flex items-center justify-between">
                        <span className="text-[10px] text-slate-500 font-sans">{isAr ? 'اسم الدخول للوحة:' : 'Login:'}</span>
                        <span className="text-cyan-300 font-bold truncate max-w-[170px]">{adm.loginUsername || adm.email || adm.appId || adm.uid}</span>
                      </div>
                      <div className="flex items-center justify-between">
                        <span className="text-[10px] text-slate-500 font-sans">{isAr ? 'كلمة المرور:' : 'Password:'}</span>
                        <div className="flex items-center gap-1.5">
                          <span className="text-rose-400 font-bold">
                            {revealedPass[adm.uid] ? (adm.password || '••••••') : '••••••••'}
                          </span>
                          <button
                            type="button"
                            onClick={() => setRevealedPass(p => ({ ...p, [adm.uid]: !p[adm.uid] }))}
                            className="text-slate-400 hover:text-white p-0.5"
                            title={isAr ? 'إظهار / إخفاء' : 'Show / Hide'}
                          >
                            {revealedPass[adm.uid] ? <EyeOff size={13} /> : <Eye size={13} />}
                          </button>
                          {adm.password && (
                            <button
                              type="button"
                              onClick={() => {
                                navigator.clipboard.writeText(adm.password!);
                                setCopiedPass(adm.uid);
                                setTimeout(() => setCopiedPass(null), 2000);
                              }}
                              className="text-emerald-400 hover:text-emerald-300 p-0.5 text-[10px] flex items-center gap-0.5"
                              title={isAr ? 'نسخ كلمة المرور' : 'Copy'}
                            >
                              {copiedPass === adm.uid ? <Check size={13} /> : <Copy size={13} />}
                            </button>
                          )}
                        </div>
                      </div>
                    </div>

                    <div className="grid grid-cols-2 gap-2 bg-slate-950/60 p-3 rounded-xl border border-slate-800/80">
                      <div>
                        <span className="text-[11px] text-slate-500 block">{isAr ? 'الراتب' : 'Salary'}</span>
                        <span className="text-amber-400 font-bold text-sm font-mono">{adm.salary}</span>
                      </div>
                      <div>
                        <span className="text-[11px] text-slate-500 block">{isAr ? 'نسبة العمولة' : 'Commission'}</span>
                        <span className="text-emerald-400 font-bold text-sm font-mono">{adm.commissionRate}%</span>
                      </div>
                      <div className="mt-1">
                        <span className="text-[11px] text-slate-500 block">{isAr ? 'الوكالات التابعة' : 'Agencies'}</span>
                        <span className="text-cyan-400 font-bold text-sm font-mono">{adm.agenciesCount || 0}</span>
                      </div>
                      <div className="mt-1">
                        <span className="text-[11px] text-slate-500 block">{isAr ? 'المشرف (سوبر أدمن)' : 'Supervisor'}</span>
                        <span className="text-purple-400 font-bold text-xs truncate block">{adm.supervisorId ? `SA: ${adm.supervisorId}` : 'مستقل'}</span>
                      </div>
                    </div>
                  </div>

                  <div className="flex items-center justify-end gap-2 mt-4 pt-3 border-t border-slate-800">
                    <button
                      onClick={() => {
                        setEditingStaff(adm);
                        setEditRole('admin');
                        setEditForm({
                          salary: adm.salary,
                          commissionRate: adm.commissionRate,
                          supervisorId: adm.supervisorId || '',
                          permissions: {},
                        });
                      }}
                      className="px-3 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 hover:text-white text-xs font-medium flex items-center gap-1.5"
                    >
                      <Edit3 size={14} />
                      {isAr ? 'تعديل' : 'Edit'}
                    </button>
                    <button
                      onClick={() => handleRevoke(adm.uid, 'admin')}
                      className="px-3 py-1.5 rounded-lg bg-rose-500/10 hover:bg-rose-500/20 text-rose-400 text-xs font-medium flex items-center gap-1.5"
                    >
                      <Trash2 size={14} />
                      {isAr ? 'سحب' : 'Revoke'}
                    </button>
                  </div>
                </div>
              ))}
          </div>
        </div>
      )}

      {/* Tab 3: BD Managers */}
      {activeTab === 'bds' && (
        <div className="space-y-4">
          <div className="flex flex-col sm:flex-row justify-between items-stretch sm:items-center gap-3">
            <div className="relative flex-1 max-w-md">
              <Search className="absolute top-1/2 -translate-y-1/2 left-3 text-slate-400" size={18} />
              <input
                type="text"
                placeholder={isAr ? 'بحث بالاسم أو ID...' : 'Search BD Manager...'}
                value={searchQ}
                onChange={e => setSearchQ(e.target.value)}
                className="w-full pl-10 pr-4 py-2.5 bg-slate-900 border border-slate-800 rounded-xl text-white text-sm focus:outline-none focus:border-indigo-500"
              />
            </div>
            <button
              onClick={() => handleOpenAssignModal('bd')}
              className="flex items-center justify-center gap-2 px-5 py-2.5 bg-gradient-to-r from-indigo-500 to-indigo-600 hover:from-indigo-600 hover:to-indigo-700 text-white font-bold rounded-xl shadow-lg shadow-indigo-500/20 text-sm transition-all"
            >
              <UserPlus size={18} />
              {isAr ? 'تعيين مسؤول BD جديد' : 'Appoint BD Manager'}
            </button>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {bds
              .filter(b => (b.name || '').toLowerCase().includes(searchQ.toLowerCase()) || (b.appId || '').includes(searchQ))
              .map(bd => (
                <div
                  key={bd.uid}
                  className="bg-slate-900/90 border border-indigo-500/20 rounded-2xl p-5 hover:border-indigo-500/40 transition-all shadow-lg flex flex-col justify-between"
                >
                  <div className="space-y-4">
                    <div className="flex items-center gap-3.5">
                      <div className="w-13 h-13 rounded-2xl bg-indigo-500/20 border border-indigo-500/30 flex items-center justify-center overflow-hidden shrink-0">
                        <Briefcase size={24} className="text-indigo-400" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <h3 className="font-bold text-white truncate">{bd.name || 'BD Manager'}</h3>
                          <span className="text-[10px] bg-indigo-500/20 text-indigo-300 font-bold px-2 py-0.5 rounded-md border border-indigo-500/30">
                            BD
                          </span>
                        </div>
                        <p className="text-xs text-cyan-400 font-mono mt-0.5">ID: {bd.appId || bd.uid}</p>
                      </div>
                    </div>

                    <div className="grid grid-cols-2 gap-2 bg-slate-950/60 p-3 rounded-xl border border-slate-800/80">
                      <div>
                        <span className="text-[11px] text-slate-500 block">{isAr ? 'الراتب' : 'Salary'}</span>
                        <span className="text-amber-400 font-bold text-sm font-mono">${bd.salary}</span>
                      </div>
                      <div>
                        <span className="text-[11px] text-slate-500 block">{isAr ? 'نسبة العمولة' : 'Commission'}</span>
                        <span className="text-emerald-400 font-bold text-sm font-mono">{bd.commissionRate}%</span>
                      </div>
                      <div className="mt-1">
                        <span className="text-[11px] text-slate-500 block">{isAr ? 'الوكالات' : 'Agencies'}</span>
                        <span className="text-cyan-400 font-bold text-sm font-mono">{bd.agenciesCount || 0}</span>
                      </div>
                      <div className="mt-1">
                        <span className="text-[11px] text-slate-500 block">{isAr ? 'المشرف' : 'Supervisor'}</span>
                        <span className="text-purple-400 font-bold text-xs truncate block">{bd.supervisorId || 'إدارة عامة'}</span>
                      </div>
                    </div>
                  </div>

                  <div className="flex items-center justify-end gap-2 mt-4 pt-3 border-t border-slate-800">
                    <button
                      onClick={() => {
                        setEditingStaff(bd);
                        setEditRole('bd');
                        setEditForm({
                          salary: bd.salary,
                          commissionRate: bd.commissionRate,
                          supervisorId: bd.supervisorId || '',
                          permissions: {},
                        });
                      }}
                      className="px-3 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 hover:text-white text-xs font-medium flex items-center gap-1.5"
                    >
                      <Edit3 size={14} />
                      {isAr ? 'تعديل' : 'Edit'}
                    </button>
                    <button
                      onClick={() => handleRevoke(bd.uid, 'bd')}
                      className="px-3 py-1.5 rounded-lg bg-rose-500/10 hover:bg-rose-500/20 text-rose-400 text-xs font-medium flex items-center gap-1.5"
                    >
                      <Trash2 size={14} />
                      {isAr ? 'سحب' : 'Revoke'}
                    </button>
                  </div>
                </div>
              ))}
          </div>
        </div>
      )}

      {/* Tab 4: Target Commissions Config */}
      {activeTab === 'commissions' && (
        <div className="space-y-6">
          {/* Section 1: Staff Supervision Commissions from Total Agency Target */}
          <div className="bg-slate-900 border border-slate-800 rounded-2xl p-6 space-y-6 shadow-xl">
            <div>
              <h2 className="text-lg font-bold text-white flex items-center gap-2">
                <Percent className="text-emerald-400" size={20} />
                {isAr ? 'نسب عمولات أرباح وتارجت الوكالات للطاقم الإداري' : 'Staff Commission Rates from Agency Target'}
              </h2>
              <p className="text-sm text-slate-400 mt-1">
                {isAr
                  ? 'حدد النسبة المئوية التي يحصل عليها السوبر أدمن، الأدمن، والـ BD من إجمالي تارجت وأرباح الوكالات التي يقومون بتفعيلها وإدارتها بالكامل (مثال: 12% أو 20% من إجمالي أرباح الوكالة)'
                  : 'Configure the percentage of total agency target earnings that Super Admins, Admins, and BDs receive as commission'}
              </p>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
              <div className="bg-slate-950 p-5 rounded-2xl border border-amber-500/30 shadow-lg">
                <div className="flex items-center justify-between mb-3">
                  <span className="text-xs font-bold text-amber-400">
                    {isAr ? 'عمولة Super Admin (%)' : 'Super Admin Commission (%)'}
                  </span>
                  <span className="text-[10px] bg-amber-500/20 text-amber-300 px-2 py-0.5 rounded-full font-mono font-bold">
                    سوبر أدمن
                  </span>
                </div>
                <div className="relative">
                  <input
                    type="number"
                    step="0.5"
                    value={commConfigs.superAdminRate}
                    onChange={e => setCommConfigs({ ...commConfigs, superAdminRate: Number(e.target.value) })}
                    placeholder="مثال: 20 أو 15"
                    className="w-full px-3.5 py-2.5 bg-slate-900 border border-amber-500/40 rounded-xl text-white font-mono font-bold text-lg focus:outline-none focus:border-amber-400"
                  />
                  <span className="absolute right-3 top-1/2 -translate-y-1/2 text-amber-400 font-bold text-base">%</span>
                </div>
                <p className="text-[11px] text-slate-400 mt-2">
                  {isAr ? 'يحصل على هذه النسبة من إجمالي تارجت كل وكالة تابعة له' : 'Earns this % from total targets of recruited agencies'}
                </p>
              </div>

              <div className="bg-slate-950 p-5 rounded-2xl border border-rose-500/30 shadow-lg">
                <div className="flex items-center justify-between mb-3">
                  <span className="text-xs font-bold text-rose-400">
                    {isAr ? 'عمولة Admin (%)' : 'Admin Commission (%)'}
                  </span>
                  <span className="text-[10px] bg-rose-500/20 text-rose-300 px-2 py-0.5 rounded-full font-mono font-bold">
                    أدمن
                  </span>
                </div>
                <div className="relative">
                  <input
                    type="number"
                    step="0.5"
                    value={commConfigs.adminRate}
                    onChange={e => setCommConfigs({ ...commConfigs, adminRate: Number(e.target.value) })}
                    placeholder="مثال: 12 أو 10"
                    className="w-full px-3.5 py-2.5 bg-slate-900 border border-rose-500/40 rounded-xl text-white font-mono font-bold text-lg focus:outline-none focus:border-rose-400"
                  />
                  <span className="absolute right-3 top-1/2 -translate-y-1/2 text-rose-400 font-bold text-base">%</span>
                </div>
                <p className="text-[11px] text-slate-400 mt-2">
                  {isAr ? 'يحصل على هذه النسبة من إجمالي تارجت كل وكالة تابعة له' : 'Earns this % from total targets of recruited agencies'}
                </p>
              </div>

              <div className="bg-slate-950 p-5 rounded-2xl border border-indigo-500/30 shadow-lg">
                <div className="flex items-center justify-between mb-3">
                  <span className="text-xs font-bold text-indigo-400">
                    {isAr ? 'عمولة مسؤولي الـ BD (%)' : 'BD Commission (%)'}
                  </span>
                  <span className="text-[10px] bg-indigo-500/20 text-indigo-300 px-2 py-0.5 rounded-full font-mono font-bold">
                    مسؤول BD
                  </span>
                </div>
                <div className="relative">
                  <input
                    type="number"
                    step="0.5"
                    value={commConfigs.bdRate}
                    onChange={e => setCommConfigs({ ...commConfigs, bdRate: Number(e.target.value) })}
                    placeholder="مثال: 10 أو 8"
                    className="w-full px-3.5 py-2.5 bg-slate-900 border border-indigo-500/40 rounded-xl text-white font-mono font-bold text-lg focus:outline-none focus:border-indigo-400"
                  />
                  <span className="absolute right-3 top-1/2 -translate-y-1/2 text-indigo-400 font-bold text-base">%</span>
                </div>
                <p className="text-[11px] text-slate-400 mt-2">
                  {isAr ? 'يحصل على هذه النسبة من إجمالي تارجت كل وكالة تابعة له' : 'Earns this % from total targets of recruited agencies'}
                </p>
              </div>
            </div>

            <div className="border-t border-slate-800 pt-4 flex items-center justify-between">
              {commSuccess && (
                <span className="text-sm text-emerald-400 flex items-center gap-1.5 font-bold">
                  <CheckCircle size={16} />
                  {isAr ? 'تم حفظ نسب عمولات الإدارة بنجاح!' : 'Commission settings saved successfully!'}
                </span>
              )}
              <div className="flex-1" />
              <button
                onClick={handleSaveCommissions}
                disabled={savingComms}
                className="px-6 py-2.5 bg-gradient-to-r from-emerald-500 to-emerald-600 hover:from-emerald-600 hover:to-emerald-700 text-white font-bold rounded-xl shadow-lg shadow-emerald-500/20 text-sm transition-all"
              >
                {savingComms ? (isAr ? 'جارٍ الحفظ...' : 'Saving...') : isAr ? 'حفظ نسب عمولات الإدارة' : 'Save Default Commissions'}
              </button>
            </div>
          </div>

          </div>
      )}

      {/* Tab 5: Salary Transfers */}
      {activeTab === 'transfers' && (
        <div className="bg-slate-900 border border-slate-800 rounded-2xl overflow-hidden shadow-xl">
          <div className="p-4 border-b border-slate-800 flex items-center justify-between">
            <h2 className="text-base font-bold text-white flex items-center gap-2">
              <ArrowLeftRight className="text-cyan-400" size={18} />
              {isAr ? 'سجل طلبات تحويل وصرف الرواتب إلى وكلاء الشحن' : 'Salary Disburse Requests to Recharge Agents'}
            </h2>
            <span className="text-xs text-slate-400 font-mono">Total: {transfers.length}</span>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full text-right text-sm">
              <thead className="bg-slate-950/60 text-slate-400 text-xs uppercase font-mono">
                <tr>
                  <th className="p-3.5">{isAr ? 'التاريخ والوقت' : 'Date'}</th>
                  <th className="p-3.5">{isAr ? 'المرسل (صاحب الراتب)' : 'Sender'}</th>
                  <th className="p-3.5">{isAr ? 'الرتبة' : 'Role'}</th>
                  <th className="p-3.5">{isAr ? 'وكيل الشحن المستلم' : 'Recharge Agent'}</th>
                  <th className="p-3.5">{isAr ? 'المبلغ المحول' : 'Amount'}</th>
                  <th className="p-3.5">{isAr ? 'حالة الطلب' : 'Status'}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800 text-slate-300">
                {transfers.length === 0 ? (
                  <tr>
                    <td colSpan={6} className="text-center py-10 text-slate-500">
                      {isAr ? 'لا توجد طلبات تحويل رواتب مسجلة حتى الآن' : 'No salary transfer records found'}
                    </td>
                  </tr>
                ) : (
                  transfers.map(tr => (
                    <tr key={tr.id} className="hover:bg-slate-800/40 transition-colors">
                      <td className="p-3.5 text-xs text-slate-400 font-mono">
                        {new Date(tr.created_at).toLocaleString('ar-EG')}
                      </td>
                      <td className="p-3.5 font-bold text-white">
                        {tr.sender_name || tr.sender_custom_id || tr.sender_uid}
                      </td>
                      <td className="p-3.5">
                        <span className="text-xs px-2 py-0.5 rounded font-bold uppercase bg-slate-800 text-cyan-300">
                          {tr.sender_role || 'staff'}
                        </span>
                      </td>
                      <td className="p-3.5 font-mono text-amber-300">
                        {tr.recharge_agent_custom_id || tr.recharge_agent_uid}
                      </td>
                      <td className="p-3.5 font-bold text-amber-400 font-mono">
                        {tr.amount} {isAr ? 'ماسة ➔ كوينز' : 'Diamonds'}
                      </td>
                      <td className="p-3.5">
                        {tr.status === 'accepted' ? (
                          <span className="text-xs bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 px-2.5 py-1 rounded-full font-bold inline-flex items-center gap-1">
                            <CheckCircle size={12} />
                            {isAr ? 'مقبول وتم الإيداع' : 'Accepted'}
                          </span>
                        ) : tr.status === 'rejected' ? (
                          <span className="text-xs bg-rose-500/20 text-rose-400 border border-rose-500/30 px-2.5 py-1 rounded-full font-bold">
                            {isAr ? 'مرفوض' : 'Rejected'}
                          </span>
                        ) : (
                          <span className="text-xs bg-amber-500/20 text-amber-300 border border-amber-500/30 px-2.5 py-1 rounded-full font-bold">
                            {isAr ? 'قيد الانتظار' : 'Pending'}
                          </span>
                        )}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Assign Modal (Super Admin / Admin / BD) */}
      {showAssignModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-sm overflow-y-auto">
          <div className="bg-slate-900 border border-slate-800 rounded-2xl w-full max-w-2xl my-8 p-6 space-y-5 shadow-2xl">
            <div className="flex items-center justify-between border-b border-slate-800 pb-3">
              <h3 className="text-lg font-bold text-white flex items-center gap-2">
                {assignRole === 'super_admin' ? (
                  <>
                    <Crown className="text-amber-400" />
                    {isAr ? 'تعيين Super Admin جديد' : 'Appoint New Super Admin'}
                  </>
                ) : assignRole === 'admin' ? (
                  <>
                    <Shield className="text-rose-400" />
                    {isAr ? 'تعيين Admin جديد' : 'Appoint New Admin'}
                  </>
                ) : (
                  <>
                    <Briefcase className="text-indigo-400" />
                    {isAr ? 'تعيين مسؤول BD جديد' : 'Appoint BD Manager'}
                  </>
                )}
              </h3>
              <button onClick={() => setShowAssignModal(false)} className="text-slate-400 hover:text-white">
                <X size={20} />
              </button>
            </div>

            <form onSubmit={handleSaveAssign} className="space-y-4">
              {/* Search User Input */}
              <div>
                <label className="text-xs font-bold text-slate-300 block mb-1.5">
                  {isAr ? 'معرف المستخدم في التطبيق (App ID / Custom ID / UID)' : 'App User ID'}
                </label>
                <div className="flex gap-2">
                  <input
                    type="text"
                    required
                    value={assignForm.appId}
                    onChange={e => setAssignForm({ ...assignForm, appId: e.target.value })}
                    placeholder={isAr ? 'أدخل آيدي الحساب...' : 'Enter App ID...'}
                    className="flex-1 px-3 py-2 bg-slate-950 border border-slate-800 rounded-xl text-white text-sm"
                  />
                  <button
                    type="button"
                    onClick={handleSearchUser}
                    disabled={searchingUser}
                    className="px-4 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl text-sm font-bold"
                  >
                    {searchingUser ? (isAr ? 'بحث...' : '...') : isAr ? 'تحقق' : 'Verify'}
                  </button>
                </div>
              </div>

              {searchedUser && (
                <div className="p-3 bg-emerald-500/10 border border-emerald-500/20 rounded-xl flex items-center gap-3">
                  <div className="w-10 h-10 rounded-full bg-slate-800 overflow-hidden">
                    {searchedUser.photo_url ? (
                      <img src={searchedUser.photo_url} alt="" className="w-full h-full object-cover" />
                    ) : (
                      <Users className="p-2 text-slate-400" />
                    )}
                  </div>
                  <div>
                    <span className="font-bold text-white text-sm block">{searchedUser.name}</span>
                    <span className="text-xs text-emerald-400 font-mono">ID: {searchedUser.custom_id || searchedUser.uid}</span>
                  </div>
                </div>
              )}

              {/* Dashboard Login Credentials (Username/Email & Password) */}
              <div className="p-4 bg-slate-950 border border-amber-500/30 rounded-xl space-y-3">
                <span className="text-xs font-bold text-amber-400 flex items-center gap-1.5">
                  <Shield size={14} />
                  {isAr ? 'بيانات تسجيل الدخول للوحة التحكم (Dashboard Login Credentials):' : 'Dashboard Login Credentials:'}
                </span>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div>
                    <label className="text-[11px] font-bold text-slate-300 block mb-1">
                      {isAr ? 'اسم المستخدم / البريد للدخول' : 'Username / Email for Login'}
                    </label>
                    <input
                      type="text"
                      required
                      value={assignForm.email}
                      onChange={e => setAssignForm({ ...assignForm, email: e.target.value })}
                      placeholder="e.g. admin_100234 or email"
                      className="w-full px-3 py-2 bg-slate-900 border border-slate-700 rounded-xl text-white font-mono text-xs focus:border-amber-500"
                    />
                  </div>

                  <div>
                    <div className="flex items-center justify-between mb-1">
                      <label className="text-[11px] font-bold text-slate-300">
                        {isAr ? 'كلمة المرور للوحة' : 'Dashboard Password'}
                      </label>
                      <button
                        type="button"
                        onClick={() => {
                          const randPass = 'AhlaStaff@' + Math.floor(1000 + Math.random() * 9000);
                          setAssignForm(prev => ({ ...prev, password: randPass }));
                        }}
                        className="text-[10px] text-amber-400 hover:underline"
                      >
                        {isAr ? 'توليد تلقائي 🎲' : 'Auto Generate 🎲'}
                      </button>
                    </div>
                    <div className="relative">
                      <input
                        type={showAssignPass ? 'text' : 'password'}
                        required
                        value={assignForm.password}
                        onChange={e => setAssignForm({ ...assignForm, password: e.target.value })}
                        placeholder={isAr ? 'كلمة المرور للدخول...' : 'Password...'}
                        className="w-full pl-3 pr-8 py-2 bg-slate-900 border border-slate-700 rounded-xl text-white font-mono text-xs focus:border-amber-500"
                      />
                      <button
                        type="button"
                        onClick={() => setShowAssignPass(!showAssignPass)}
                        className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-white"
                      >
                        {showAssignPass ? <EyeOff size={14} /> : <Eye size={14} />}
                      </button>
                    </div>
                  </div>
                </div>
              </div>

              {/* Salary & Commission Rate */}
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs font-bold text-slate-300 block mb-1">
                    {isAr ? 'الراتب المعتمد (ماسة / $)' : 'Salary'}
                  </label>
                  <input
                    type="number"
                    value={assignForm.salary}
                    onChange={e => setAssignForm({ ...assignForm, salary: Number(e.target.value) })}
                    className="w-full px-3 py-2 bg-slate-950 border border-slate-800 rounded-xl text-white font-mono"
                  />
                </div>
                <div>
                  <label className="text-xs font-bold text-slate-300 block mb-1">
                    {isAr ? 'نسبة العمولة (%)' : 'Commission Rate (%)'}
                  </label>
                  <input
                    type="number"
                    value={assignForm.commissionRate}
                    onChange={e => setAssignForm({ ...assignForm, commissionRate: Number(e.target.value) })}
                    className="w-full px-3 py-2 bg-slate-950 border border-slate-800 rounded-xl text-white font-mono"
                  />
                </div>
              </div>

              {/* Supervisor Selector (if Admin or BD) */}
              {assignRole !== 'super_admin' && (
                <div>
                  <label className="text-xs font-bold text-slate-300 block mb-1">
                    {isAr ? 'المشرف المسؤول (السوبر أدمن)' : 'Supervisor (Super Admin)'}
                  </label>
                  <select
                    value={assignForm.supervisorId}
                    onChange={e => setAssignForm({ ...assignForm, supervisorId: e.target.value })}
                    className="w-full px-3 py-2 bg-slate-950 border border-slate-800 rounded-xl text-white text-sm"
                  >
                    <option value="">{isAr ? 'بدون مشرف (إشراف عام من الإدارة)' : 'No Supervisor'}</option>
                    {superAdmins.map(sa => (
                      <option key={sa.uid} value={sa.uid}>
                        {sa.name} (ID: {sa.appId})
                      </option>
                    ))}
                  </select>
                </div>
              )}

              {/* Dashboard Permissions Matrix with Checkboxes (Super Admin & Admin) */}
              {assignRole !== 'bd' && (
                <div className="space-y-3">
                  <label className="text-xs font-bold text-amber-300 block border-b border-slate-800 pb-1">
                    {isAr
                      ? 'صلاحيات لوحة الإدارة (اختر الأقسام التي تظهر في اللوحة):'
                      : 'Dashboard Page Permissions:'}
                  </label>
                  <div className="max-h-52 overflow-y-auto space-y-3 pr-2">
                    {PERMISSION_CATEGORIES.map(cat => (
                      <div key={cat.id} className="bg-slate-950/60 p-3 rounded-xl border border-slate-800/80">
                        <span className="text-xs font-bold text-slate-300 block mb-2">{isAr ? cat.ar : cat.en}</span>
                        <div className="grid grid-cols-2 gap-2">
                          {cat.items.map(item => {
                            const checked = !!assignForm.permissions[item.key];
                            return (
                              <label
                                key={item.key}
                                className="flex items-center gap-2 cursor-pointer text-xs text-slate-300 hover:text-white"
                              >
                                <input
                                  type="checkbox"
                                  checked={checked}
                                  onChange={e => {
                                    setAssignForm({
                                      ...assignForm,
                                      permissions: {
                                        ...assignForm.permissions,
                                        [item.key]: e.target.checked,
                                      },
                                    });
                                  }}
                                  className="w-4 h-4 rounded text-amber-500 focus:ring-0 bg-slate-900 border-slate-700"
                                />
                                <span className="truncate">{isAr ? item.ar : item.en}</span>
                              </label>
                            );
                          })}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {assignError && <p className="text-xs text-rose-400 font-bold">{assignError}</p>}

              <div className="flex justify-end gap-2 pt-2 border-t border-slate-800">
                <button
                  type="button"
                  onClick={() => setShowAssignModal(false)}
                  className="px-4 py-2 text-slate-400 hover:text-white text-sm"
                >
                  {isAr ? 'إلغاء' : 'Cancel'}
                </button>
                <button
                  type="submit"
                  disabled={assignSaving}
                  className="px-6 py-2 bg-gradient-to-r from-amber-500 to-amber-600 text-slate-950 font-bold rounded-xl text-sm"
                >
                  {assignSaving ? (isAr ? 'جارٍ الحفظ...' : 'Saving...') : isAr ? 'اعتماد وتعيين' : 'Appoint Staff'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Edit Modal */}
      {editingStaff && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-sm">
          <div className="bg-slate-900 border border-slate-800 rounded-2xl w-full max-w-md p-6 space-y-4 shadow-2xl">
            <div className="flex items-center justify-between border-b border-slate-800 pb-3">
              <h3 className="font-bold text-white text-base">
                {isAr ? `تعديل بيانات: ${editingStaff.name}` : `Edit: ${editingStaff.name}`}
              </h3>
              <button onClick={() => setEditingStaff(null)} className="text-slate-400 hover:text-white">
                <X size={18} />
              </button>
            </div>

            <div className="space-y-3">
              <div>
                <label className="text-xs text-slate-400 block mb-1">{isAr ? 'الراتب' : 'Salary'}</label>
                <input
                  type="number"
                  value={editForm.salary}
                  onChange={e => setEditForm({ ...editForm, salary: Number(e.target.value) })}
                  className="w-full px-3 py-2 bg-slate-950 border border-slate-800 rounded-xl text-white font-mono"
                />
              </div>
              <div>
                <label className="text-xs text-slate-400 block mb-1">{isAr ? 'نسبة العمولة (%)' : 'Commission (%)'}</label>
                <input
                  type="number"
                  value={editForm.commissionRate}
                  onChange={e => setEditForm({ ...editForm, commissionRate: Number(e.target.value) })}
                  className="w-full px-3 py-2 bg-slate-950 border border-slate-800 rounded-xl text-white font-mono"
                />
              </div>
            </div>

            <div>
                <label className="text-xs text-slate-400 block mb-1">
                  {isAr ? 'تغيير كلمة المرور للوحة (اختياري)' : 'Change Dashboard Password (Optional)'}
                </label>
                <input
                  type="text"
                  value={(editForm as any).password || ''}
                  onChange={e => setEditForm({ ...editForm, password: e.target.value } as any)}
                  placeholder={isAr ? 'اتركه فارغاً للإبقاء على الحالية' : 'Leave empty to keep current'}
                  className="w-full px-3 py-2 bg-slate-950 border border-slate-800 rounded-xl text-white font-mono text-xs"
                />
              </div>

            <div className="flex justify-end gap-2 pt-3 border-t border-slate-800">
              <button onClick={() => setEditingStaff(null)} className="px-4 py-2 text-slate-400 text-sm">
                {isAr ? 'إلغاء' : 'Cancel'}
              </button>
              <button
                onClick={handleSaveEdit}
                disabled={editSaving}
                className="px-5 py-2 bg-indigo-600 hover:bg-indigo-700 text-white font-bold rounded-xl text-sm"
              >
                {editSaving ? (isAr ? 'حفظ...' : 'Saving...') : isAr ? 'حفظ التعديلات' : 'Save'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
