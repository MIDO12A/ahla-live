import { useContext, useEffect, useState } from 'react';
import {
  HostAgencyModel, HostAgencyMemberModel, CommissionSettingModel,
  HostMilestoneModel, AgencyJoinRequestModel, AgencyLedgerEntryModel,
  AgencyWithdrawalRequestModel, AgencyApplicationModel,
} from '../types';
import {
  getHostAgencies, createHostAgency, updateHostAgency, deleteHostAgency,
  getCommissionSettings, updateCommissionSetting,
  getHostAgencyMembers, getHostMilestones, updateHostMilestone,
  createHostMilestone, deleteHostMilestone,
  getHostAgencyJoinRequests, approveJoinRequest, rejectJoinRequest,
  updateAgencyMemberRole, removeAgencyMember, addAgencyMember,
  getAgencyApplications, approveAgencyApplication, rejectAgencyApplication, createAgencyApplication,
  updateRechargeAgency, revokeRechargeAgency,
  getAgencyLedger, getWithdrawalRequests, approveWithdrawal, rejectWithdrawal,
  getAppConfig, updateAppConfig,
  searchUserProfile, sendSystemNotification, sendAgencyInvitation,
} from '../lib/db';
import { uploadStoreItem } from '../lib/storage';
import { supabase } from '../lib/supabase';
import { firebaseAuth, firestoreDb } from '../lib/firebase';
import { doc, setDoc, increment } from 'firebase/firestore';
import { I18nContext } from '../lib/i18n';
import DataTable from '../components/DataTable';
import ImageUpload from '../components/ImageUpload';
import {
  Handshake, Users, UserPlus, Wallet, Target, Settings, Sparkles,
  Save, CheckCircle2, RefreshCw, ClipboardCheck, Plus, Trash2, Edit3,
  XCircle, Check, ShieldCheck, UserMinus, Eye, ExternalLink,
} from 'lucide-react';

/* =============================================================
   LIVE USER SEARCH & PREVIEW COMPONENT
   ============================================================= */
function UserSearchPreview({ query, onSelect }: { query?: string | null; onSelect?: (user: any) => void }) {
  const [user, setUser] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const [searched, setSearched] = useState(false);

  useEffect(() => {
    const q = (typeof query === 'string' ? query : '').trim();
    if (!q || q.length < 2) {
      setUser(null);
      setSearched(false);
      return;
    }
    const timer = setTimeout(async () => {
      setLoading(true);
      try {
        const u = await searchUserProfile(q);
        setUser(u);
        setSearched(true);
        if (u && onSelect) onSelect(u);
      } catch {
        setUser(null);
      } finally {
        setLoading(false);
      }
    }, 300);
    return () => clearTimeout(timer);
  }, [query]);

  const cleanQuery = (typeof query === 'string' ? query : '').trim();
  if (!cleanQuery || cleanQuery.length < 2) return null;

  if (loading) {
    return (
      <div className="mt-1.5 flex items-center gap-2 text-xs text-amber-400 bg-amber-500/10 p-2 rounded-lg border border-amber-500/20">
        <RefreshCw className="w-3.5 h-3.5 animate-spin" />
        <span>جاري البحث عن بيانات المستخدم بالـ ID...</span>
      </div>
    );
  }

  if (searched && !user) {
    return (
      <div className="mt-1.5 flex items-center gap-2 text-xs text-rose-400 bg-rose-500/10 p-2 rounded-lg border border-rose-500/20">
        <XCircle className="w-3.5 h-3.5" />
        <span>لم يتم العثور على مستخدم مسجل بهذا المعرف (UID / ID)</span>
      </div>
    );
  }

  if (user) {
    return (
      <div className="mt-1.5 flex items-center justify-between p-2.5 rounded-xl bg-emerald-500/10 border border-emerald-500/30">
        <div className="flex items-center gap-2.5">
          <img
            src={user.photo_url || `https://ui-avatars.com/api/?name=${encodeURIComponent(user.name || 'User')}&background=random`}
            alt={user.name}
            className="w-9 h-9 rounded-full object-cover border border-emerald-400/50"
            onError={e => { (e.currentTarget as any).src = 'https://ui-avatars.com/api/?name=' + encodeURIComponent(user.name || 'User'); }}
          />
          <div>
            <div className="text-xs font-bold text-white flex items-center gap-1.5">
              <span>{user.name}</span>
              {user.is_recharge_agent && (
                <span className="px-1.5 py-0.5 rounded text-[9px] bg-amber-500/20 text-amber-300 font-bold border border-amber-500/30">وكيل شحن</span>
              )}
            </div>
            <div className="text-[11px] text-slate-400 flex items-center gap-2">
              <span className="text-emerald-400 font-mono font-bold">ID: #{user.custom_id}</span>
              <span>•</span>
              <span className="text-amber-400 font-bold">🪙 {user.coins.toLocaleString()} عملة</span>
            </div>
          </div>
        </div>
        <div className="text-[11px] text-emerald-400 font-bold bg-emerald-500/20 px-2 py-0.5 rounded-md flex items-center gap-1">
          <Check className="w-3 h-3" /> تم التعرف
        </div>
      </div>
    );
  }
  return null;
}

const tabs = [
  { key: 'agencies', label: 'الوكالات', labelKey: 'agency.agencies', icon: Handshake },
  { key: 'recharge_agencies', label: 'وكالات الشحن والرواتب', labelKey: 'agency.rechargeAgencies', icon: Wallet },
  { key: 'agency_requests', label: 'طلبات فتح الوكالات', labelKey: 'agency.agencyRequests', icon: ClipboardCheck },
  { key: 'milestones', label: 'المراحل والتارجت والرواتب', labelKey: 'agency.milestones', icon: Target },
  { key: 'members', label: 'أعضاء الوكالات', labelKey: 'agency.members', icon: Users },
  { key: 'necklaces', label: 'قلادات الوكالة SVGA', labelKey: 'agency.necklaces', icon: Sparkles },
  { key: 'join_requests', label: 'طلبات الانضمام', labelKey: 'agency.joinRequests', icon: UserPlus },
  { key: 'financial', label: 'السجلات المالية', labelKey: 'agency.financial', icon: Wallet },
  { key: 'commission', label: 'نسب العمولات العامة', labelKey: 'agency.commission', icon: Settings },
] as const;
type Tab = typeof tabs[number]['key'];

export default function AgencyPage() {
  const [tab, setTab] = useState<Tab>('agencies');
  const [filterAgencyId, setFilterAgencyId] = useState<string>('');
  const { t } = useContext(I18nContext);

  const handleViewAgencyMembers = (agencyId: string) => {
    setFilterAgencyId(agencyId);
    setTab('members');
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <Handshake className="w-5 h-5 text-indigo-400" />
        <h2 className="text-white text-lg font-semibold">{t('agency.title')}</h2>
      </div>
      <div className="flex gap-2 flex-wrap">
        {tabs.map(tabItem => (
          <button key={tabItem.key} onClick={() => setTab(tabItem.key)}
            className={`flex items-center gap-1.5 px-4 py-2 text-xs rounded-lg font-semibold transition-colors ${tab === tabItem.key ? 'bg-indigo-500/20 text-indigo-300' : 'text-slate-400 hover:text-white'}`}>
            <tabItem.icon className="w-3.5 h-3.5" />
            {tabItem.label || t(tabItem.labelKey)}
          </button>
        ))}
      </div>
      {tab === 'agencies' && <AgenciesTab onViewMembers={handleViewAgencyMembers} />}
      {tab === 'recharge_agencies' && <RechargeAgenciesTab />}
      {tab === 'agency_requests' && <AgencyRequestsTab />}
      {tab === 'milestones' && <MilestonesTab />}
      {tab === 'members' && <MembersTab initialAgencyId={filterAgencyId} />}
      {tab === 'necklaces' && <AgencyNecklacesTab />}
      {tab === 'join_requests' && <JoinRequestsTab />}
      {tab === 'financial' && <FinancialTab />}
      {tab === 'commission' && <CommissionTab />}
    </div>
  );
}

/* =============================================================
   1. AGENCIES TAB
   ============================================================= */
function AgenciesTab({ onViewMembers }: { onViewMembers: (agencyId: string) => void }) {
  const { t } = useContext(I18nContext);
  const [agencies, setAgencies] = useState<HostAgencyModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [ownerId, setOwnerId] = useState('');
  const [commissionRate, setCommissionRate] = useState('10');
  const [specialty, setSpecialty] = useState('mixed');
  const [description, setDescription] = useState('');
  const [country, setCountry] = useState('');
  const [tier, setTier] = useState('bronze');
  const [photoUrl, setPhotoUrl] = useState('');
  const [isActive, setIsActive] = useState(true);
  const [sendInviteMode, setSendInviteMode] = useState(false);
  const [resolvedOwnerUser, setResolvedOwnerUser] = useState<any>(null);

  const load = () => { setLoading(true); getHostAgencies().then(d => { setAgencies(d); setLoading(false); }); };
  useEffect(() => { load(); }, []);

  const resetForm = () => {
    setEditId(null); setName(''); setOwnerId(''); setCommissionRate('10');
    setSpecialty('mixed'); setTier('bronze'); setDescription(''); setCountry(''); setPhotoUrl('');
    setIsActive(true); setSendInviteMode(false); setResolvedOwnerUser(null);
  };

  const openEdit = (a: HostAgencyModel) => {
    setEditId(a.id); setName(a.name); setOwnerId(a.owner_id);
    setCommissionRate(String((a.commission_rate ?? 0.1) * 100));
    setSpecialty(a.specialty ?? 'mixed'); setTier(a.tier ?? 'bronze');
    setDescription(a.description ?? ''); setCountry(a.country ?? '');
    setPhotoUrl(a.photo_url ?? ''); setIsActive(a.is_active ?? true);
    setShowForm(true);
  };

  const handleSubmit = async () => {
    if (!name.trim() || !ownerId.trim()) return;
    const finalOwnerId = resolvedOwnerUser?.id || ownerId.trim();
    const adminName = firebaseAuth.currentUser?.displayName || firebaseAuth.currentUser?.email || 'إدارة التطبيق';

    if (!editId && sendInviteMode) {
      await sendAgencyInvitation({
        userId: finalOwnerId,
        agencyName: name.trim(),
        adminName,
        agencyLogo: photoUrl.trim() || undefined,
        type: 'host',
      });
      alert(`تم إرسال دعوة فتح الوكالة للمستخدم (${resolvedOwnerUser?.name || finalOwnerId}) بنجاح! سيصل إشعار للنظام بالتطبيق للتأكيد والقبول أو الرفض.`);
      resetForm(); setShowForm(false); load();
      return;
    }

    const payload = {
      name: name.trim(),
      owner_id: finalOwnerId,
      commission_rate: (parseFloat(commissionRate) || 10) / 100,
      specialty: specialty as any,
      description: description.trim() || null,
      country: country.trim() || null,
      tier: tier as HostAgencyModel['tier'],
      photo_url: photoUrl.trim() || null,
      is_active: isActive,
      adminName,
    };
    if (editId) {
      await updateHostAgency(editId, payload);
    } else {
      await createHostAgency(payload.name, payload.owner_id, payload.commission_rate, payload.specialty, payload);
      alert(`تم فتح وكالة (${payload.name}) وتفعيلها بنجاح، وتم إرسال إشعار تهنئة للمستخدم!`);
    }
    resetForm(); setShowForm(false); load();
  };

  const tierColors: Record<string, string> = {
    bronze: 'text-amber-600', silver: 'text-slate-300', gold: 'text-yellow-400',
    platinum: 'text-cyan-300', diamond: 'text-blue-400',
  };

  const tierKey = (v: string) => `agency.tier.${v}` as const;

  return (
    <div>
      <div className="flex items-center justify-between mb-3">
        <p className="text-slate-500 text-xs">{agencies.length} {t('agency.agenciesCount')}</p>
        <button onClick={() => { resetForm(); setShowForm(!showForm); }}
          className="text-xs bg-indigo-500 hover:bg-indigo-600 text-white px-3 py-1.5 rounded-lg font-semibold transition-colors flex items-center gap-1.5">
          <Plus className="w-3.5 h-3.5" />
          {showForm ? t('cancel') : t('agency.newAgency')}
        </button>
      </div>

      {showForm && (
        <div className="bg-[#141417] rounded-2xl border border-white/5 p-4 mb-4 space-y-3">
          <div className="text-white font-bold text-xs">{editId ? '✏️ تعديل بيانات الوكالة' : '✨ إضافة وكالة مضيفين جديدة'}</div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <input value={name} onChange={e => setName(e.target.value)} placeholder={t('agency.name')}
              className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500 placeholder:text-slate-600" />
            <div>
              <input value={ownerId} onChange={e => setOwnerId(e.target.value)} placeholder="معرف المالك (UID أو ID المخصص)"
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500 placeholder:text-slate-600" />
              <UserSearchPreview query={ownerId} onSelect={setResolvedOwnerUser} />
            </div>
            <input value={country} onChange={e => setCountry(e.target.value)} placeholder={t('agency.country')}
              className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500 placeholder:text-slate-600" />
          </div>

          {!editId && (
            <label className="flex items-center gap-2 cursor-pointer bg-indigo-500/10 border border-indigo-500/20 p-2.5 rounded-xl">
              <input
                type="checkbox"
                checked={sendInviteMode}
                onChange={e => setSendInviteMode(e.target.checked)}
                className="w-4 h-4 rounded bg-[#161618] border-white/20 text-indigo-500 focus:ring-0"
              />
              <span className="text-xs text-indigo-300 font-bold">إرسال دعوة فتح الوكالة للمستخدم (يحتاج موافقة المالك من التطبيق)</span>
            </label>
          )}

          <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
            <div>
              <label className="text-[10px] text-slate-400 block mb-1">نسبة العمولة (%)</label>
              <input type="number" value={commissionRate} onChange={e => setCommissionRate(e.target.value)} placeholder="10"
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500 placeholder:text-slate-600" />
            </div>
            <div>
              <label className="text-[10px] text-slate-400 block mb-1">التخصص</label>
              <select value={specialty} onChange={e => setSpecialty(e.target.value)}
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500">
                <option value="mixed">{t('agency.specialty.mixed')}</option>
                <option value="singing">{t('agency.specialty.singing')}</option>
                <option value="gaming">{t('agency.specialty.gaming')}</option>
                <option value="talk">{t('agency.specialty.talk')}</option>
              </select>
            </div>
            <div>
              <label className="text-[10px] text-slate-400 block mb-1">الفئة (Tier)</label>
              <select value={tier} onChange={e => setTier(e.target.value)}
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500">
                {['bronze', 'silver', 'gold', 'platinum', 'diamond'].map(v => (
                  <option key={v} value={v}>{t(tierKey(v))}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="text-[10px] text-slate-400 block mb-1">حالة الوكالة</label>
              <select value={isActive ? 'true' : 'false'} onChange={e => setIsActive(e.target.value === 'true')}
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500">
                <option value="true">نشطة (Active)</option>
                <option value="false">معطلة (Inactive)</option>
              </select>
            </div>
          </div>

          <div>
            <label className="text-[10px] text-slate-400 block mb-1">شعار / صورة الوكالة</label>
            <ImageUpload
              currentUrl={photoUrl}
              onUpload={file => uploadStoreItem(file, 'agency_logos')}
              onUrlChange={url => setPhotoUrl(url)}
              label="رفع شعار الوكالة"
              accept="image/*"
            />
          </div>

          <textarea value={description} onChange={e => setDescription(e.target.value)} placeholder={t('agency.description')}
            className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500 placeholder:text-slate-600 resize-none h-16" />

          <div className="flex gap-2">
            <button onClick={handleSubmit}
              className="text-xs bg-emerald-500 hover:bg-emerald-600 text-white px-4 py-1.5 rounded-lg font-semibold transition-colors">
              {editId ? t('agency.updateAgency') : t('agency.createAgency')}
            </button>
            {editId && (
              <button onClick={() => { resetForm(); setShowForm(false); }}
                className="text-xs bg-slate-600 hover:bg-slate-700 text-white px-3 py-1.5 rounded-lg font-semibold transition-colors">
                {t('agency.cancelEdit')}
              </button>
            )}
          </div>
        </div>
      )}

      <DataTable
        loading={loading}
        columns={[
          { key: 'name', label: t('agency.col.name'), sortable: true, render: a => {
            const ag = a as HostAgencyModel;
            return (
              <div className="flex items-center gap-2.5">
                <img src={ag.photo_url || `https://ui-avatars.com/api/?name=${encodeURIComponent(ag.name || 'Agency')}&background=random`} alt="" className="w-8 h-8 rounded-xl object-cover border border-amber-500/30" />
                <div>
                  <div className="text-white font-bold text-xs">{ag.name}</div>
                  <div className="text-[10px] text-slate-500 font-mono">ID: {ag.id?.slice(0, 8)}</div>
                </div>
              </div>
            );
          }},
          { key: 'owner_name', label: t('agency.col.owner'), sortable: true, render: a => {
            const ag = a as HostAgencyModel;
            return (
              <div className="flex items-center gap-2">
                {ag.owner_avatar && <img src={ag.owner_avatar} alt="" className="w-6 h-6 rounded-full object-cover border border-white/10" />}
                <span className="text-slate-200 text-xs font-semibold">{ag.owner_name || ag.owner_id?.slice(0, 8)}</span>
              </div>
            );
          }},
          { key: 'tier', label: t('agency.col.tier'), sortable: true, render: a => {
            const h = a as HostAgencyModel;
            const tierT = t(tierKey(h.tier ?? 'bronze'));
            return <span className={tierColors[h.tier ?? 'bronze'] + ' font-semibold'}>{tierT}</span>;
          }},
          { key: 'specialty', label: t('agency.col.specialty'), sortable: true, render: a => {
            const s = (a as HostAgencyModel).specialty;
            return <span className="text-slate-400">{t(`agency.specialty.${s}` as any)}</span>;
          }},
          { key: 'commission_rate', label: t('agency.col.commission'), sortable: true, render: a => <span className="text-amber-400 font-semibold">{((a as HostAgencyModel).commission_rate ?? 0.1) * 100}%</span> },
          { key: 'member_count', label: t('agency.col.members'), sortable: true, render: a => {
            const h = a as HostAgencyModel;
            return (
              <button onClick={() => onViewMembers(h.id)}
                className="flex items-center gap-1.5 px-2.5 py-1 bg-indigo-500/15 hover:bg-indigo-500/25 border border-indigo-500/30 text-indigo-300 rounded-lg text-xs font-bold transition-all"
                title="عرض أعضاء هذه الوكالة">
                <Users className="w-3.5 h-3.5" />
                <span>{h.member_count ?? 0} عضو</span>
              </button>
            );
          }},
          { key: 'total_diamonds_earned', label: t('agency.col.totalDiamonds'), sortable: true, render: a => <span className="text-cyan-400">{(a as HostAgencyModel).total_diamonds_earned?.toLocaleString() ?? '0'}</span> },
          { key: 'monthly_diamonds', label: t('agency.col.monthlyDiamonds'), sortable: true, render: a => <span className="text-amber-400">{(a as HostAgencyModel).monthly_diamonds?.toLocaleString() ?? '0'}</span> },
          { key: 'country', label: t('agency.col.country'), sortable: true, render: a => <span className="text-slate-500 uppercase">{(a as HostAgencyModel).country || '—'}</span> },
          { key: 'is_active', label: t('agency.col.active'), sortable: true, render: a => {
            const active = (a as HostAgencyModel).is_active;
            return <span className={active ? 'text-emerald-400' : 'text-rose-400'}>{active ? t('agency.yes') : t('agency.no')}</span>;
          }},
        ]}
        data={agencies}
        searchKeys={['name', 'owner_name', 'specialty', 'country', 'tier']}
        onEdit={a => openEdit(a as HostAgencyModel)}
        onDelete={async a => {
          if (confirm(t('agency.deleteConfirm'))) { await deleteHostAgency((a as HostAgencyModel).id); load(); }
        }}
      />
    </div>
  );
}

/* =============================================================
   2. MEMBERS TAB
   ============================================================= */
/* =============================================================
   2. MEMBERS TAB
   ============================================================= */
function MembersTab({ initialAgencyId }: { initialAgencyId?: string }) {
  const { t } = useContext(I18nContext);
  const [members, setMembers] = useState<HostAgencyMemberModel[]>([]);
  const [agencies, setAgencies] = useState<HostAgencyModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [filterAgency, setFilterAgency] = useState(initialAgencyId || '');

  // Add Member Modal State
  const [showAddMemberModal, setShowAddMemberModal] = useState(false);
  const [addAgencyId, setAddAgencyId] = useState(initialAgencyId || '');
  const [addUserQuery, setAddUserQuery] = useState('');
  const [addRole, setAddRole] = useState('host');
  const [adding, setAdding] = useState(false);

  useEffect(() => {
    if (initialAgencyId) {
      setFilterAgency(initialAgencyId);
      setAddAgencyId(initialAgencyId);
    }
  }, [initialAgencyId]);

  const load = async () => {
    setLoading(true);
    const [m, a] = await Promise.all([getHostAgencyMembers(filterAgency || undefined), getHostAgencies()]);
    setMembers(m); setAgencies(a); setLoading(false);
  };
  useEffect(() => { load(); }, [filterAgency]);

  const handleRoleChange = async (agencyId: string, userId: string, role: string) => {
    await updateAgencyMemberRole(agencyId, userId, role);
    load();
  };

  const handleRemove = async (agencyId: string, userId: string, userName?: string) => {
    if (confirm(`هل أنت متأكد من إزالة ${userName || 'هذا العضو'} من الوكالة؟ سيتم فصله وتحديث عدد أعضاء الوكالة فوراً.`)) {
      await removeAgencyMember(agencyId, userId);
      load();
    }
  };

  const handleAddMember = async () => {
    if (!addAgencyId || !addUserQuery.trim()) {
      alert('يرجى اختيار الوكالة وإدخال رقم المعرف (ID) للمستخدم');
      return;
    }
    setAdding(true);
    const res = await addAgencyMember(addAgencyId, addUserQuery.trim(), addRole);
    alert(res.message);
    setAdding(false);
    if (res.success) {
      setShowAddMemberModal(false);
      setAddUserQuery('');
      load();
    }
  };

  const roleColors: Record<string, string> = {
    owner: 'text-amber-400 bg-amber-400/10',
    supervisor: 'text-cyan-400 bg-cyan-400/10',
    host: 'text-indigo-400 bg-indigo-400/10',
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <p className="text-slate-500 text-xs">{members.length} {t('agency.membersCount')}</p>
          <select value={filterAgency} onChange={e => setFilterAgency(e.target.value)}
            className="bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500">
            <option value="">جميع الوكالات ({agencies.length})</option>
            {agencies.map(a => <option key={a.id} value={a.id}>{a.name} ({a.member_count ?? 0} عضو)</option>)}
          </select>
        </div>

        <button onClick={() => { setAddAgencyId(filterAgency || (agencies[0]?.id ?? '')); setShowAddMemberModal(true); }}
          className="text-xs bg-indigo-600 hover:bg-indigo-700 text-white font-bold px-3.5 py-1.5 rounded-lg transition-all flex items-center gap-1.5 shadow-lg shadow-indigo-600/20">
          <Plus className="w-3.5 h-3.5" />
          ➕ إضافة عضو للوكالة بالـ ID
        </button>
      </div>

      {showAddMemberModal && (
        <div className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-[#18181b] border border-white/10 rounded-2xl max-w-md w-full p-5 space-y-4 shadow-2xl">
            <h4 className="text-white font-bold text-sm">➕ إضافة عضو جديد لوكالة مضيفين</h4>
            <div className="space-y-3">
              <div>
                <label className="text-[11px] text-slate-400 block mb-1">اختر الوكالة *</label>
                <select value={addAgencyId} onChange={e => setAddAgencyId(e.target.value)}
                  className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white">
                  {agencies.map(a => <option key={a.id} value={a.id}>{a.name}</option>)}
                </select>
              </div>
              <div>
                <label className="text-[11px] text-slate-400 block mb-1">UID المستخدم أو رقم المعرف (Custom ID) *</label>
                <input value={addUserQuery} onChange={e => setAddUserQuery(e.target.value)} placeholder="مثال: 123456 أو UID"
                  className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white placeholder:text-slate-600" />
                <UserSearchPreview query={addUserQuery} />
              </div>
              <div>
                <label className="text-[11px] text-slate-400 block mb-1">الرتبة في الوكالة</label>
                <select value={addRole} onChange={e => setAddRole(e.target.value)}
                  className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white">
                  <option value="host">مضيف (Host)</option>
                  <option value="supervisor">مشرف (Supervisor)</option>
                </select>
              </div>
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <button onClick={() => setShowAddMemberModal(false)} className="px-4 py-2 text-xs text-slate-400 hover:text-white">إلغاء</button>
              <button onClick={handleAddMember} disabled={adding}
                className="px-5 py-2 bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-white rounded-xl text-xs font-bold transition-all">
                {adding ? 'جاري الإضافة...' : 'تأكيد الإضافة'}
              </button>
            </div>
          </div>
        </div>
      )}

      <DataTable
        loading={loading}
        columns={[
          { key: 'user_name', label: 'العضو', sortable: true, render: m => {
            const mem = m as HostAgencyMemberModel;
            return (
              <div className="flex items-center gap-2.5">
                <img src={mem.avatar_url || `https://ui-avatars.com/api/?name=${encodeURIComponent(mem.user_name || 'User')}&background=random`} alt="" className="w-8 h-8 rounded-full object-cover border border-white/10 shrink-0" />
                <div>
                  <div className="text-white font-bold text-xs">{mem.user_name || 'مستخدم'}</div>
                  <div className="text-[10px] text-slate-400 font-mono">ID: {mem.custom_id || mem.user_id?.slice(0, 8)}</div>
                </div>
              </div>
            );
          }},
          { key: 'agency_id', label: 'الوكالة', sortable: true, render: m => {
            const member = m as HostAgencyMemberModel;
            const agency = agencies.find(a => a.id === member.agency_id);
            return <span className="text-indigo-300 font-semibold">{agency?.name ?? member.agency_id?.slice(0, 8)}</span>;
          }},
          { key: 'role', label: 'الرتبة', sortable: true, render: m => {
            const member = m as HostAgencyMemberModel;
            const roleT = member.role === 'owner' ? '👑 مالك' : member.role === 'supervisor' ? '⭐ مشرف' : '🎙️ مضيف';
            return <span className={`text-[10px] font-semibold px-2 py-0.5 rounded-full ${roleColors[member.role] ?? 'text-slate-400'}`}>{roleT}</span>;
          }},
          { key: 'status', label: 'الحالة', sortable: true, render: m => {
            const st = (m as HostAgencyMemberModel).status;
            return <span className={st === 'active' ? 'text-emerald-400 font-semibold' : 'text-slate-500'}>{st === 'active' ? 'نشط' : st}</span>;
          }},
          { key: 'diamonds_earned_monthly', label: 'ألماس الشهر', sortable: true, render: m => {
            const v = (m as HostAgencyMemberModel).diamonds_earned_monthly;
            return <span className="text-amber-400 font-semibold">{v?.toLocaleString() ?? '0'} 💎</span>;
          }},
          { key: 'diamonds_balance', label: 'الرصيد القابل للسحب', sortable: true, render: m => {
            const v = (m as HostAgencyMemberModel).diamonds_balance;
            return <span className="text-cyan-400 font-semibold">{v?.toLocaleString() ?? '0'} 💎</span>;
          }},
          { key: 'joined_at', label: 'تاريخ الانضمام', sortable: true, render: m => new Date((m as HostAgencyMemberModel).joined_at).toLocaleDateString('ar-EG') },
          { key: 'actions', label: 'الإجراءات', render: m => {
            const member = m as HostAgencyMemberModel;
            if (member.role === 'owner') return <span className="text-[10px] text-amber-400 font-semibold">مالك الوكالة</span>;
            return (
              <div className="flex items-center gap-2">
                <select defaultValue="" onChange={e => { if (e.target.value) handleRoleChange(member.agency_id, member.user_id, e.target.value); }}
                  className="bg-[#161618] border border-white/10 rounded py-0.5 px-1 text-[10px] text-white">
                  <option value="" disabled>تغيير الرتبة</option>
                  <option value="supervisor">مشرف</option>
                  <option value="host">مضيف</option>
                </select>
                <button onClick={() => handleRemove(member.agency_id, member.user_id, member.user_name)}
                  className="text-[10px] bg-rose-500/10 hover:bg-rose-500/20 text-rose-400 border border-rose-500/20 px-2 py-0.5 rounded font-semibold transition-all">
                  إزالة من الوكالة
                </button>
              </div>
            );
          }},
        ]}
        data={members}
        searchKeys={['user_name', 'role', 'status', 'custom_id']}
      />
    </div>
  );
}

/* =============================================================
   AGENCY REQUESTS TAB (طلبات فتح الوكالات: قبول ورفض)
   ============================================================= */
function AgencyRequestsTab() {
  const [requests, setRequests] = useState<AgencyApplicationModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState('pending');
  const [typeFilter, setTypeFilter] = useState('');
  const [rejectModalApp, setRejectModalApp] = useState<AgencyApplicationModel | null>(null);
  const [rejectionReason, setRejectionReason] = useState('');
  const [actionLoading, setActionLoading] = useState(false);

  // Manual Creation Modal
  const [showAddModal, setShowAddModal] = useState(false);
  const [newUserId, setNewUserId] = useState('');
  const [newAgencyName, setNewAgencyName] = useState('');
  const [newAgencyType, setNewAgencyType] = useState<'host' | 'recharge'>('host');
  const [newWhatsapp, setNewWhatsapp] = useState('');
  const [newCountry, setNewCountry] = useState('');

  const load = () => {
    setLoading(true);
    getAgencyApplications(statusFilter || undefined, typeFilter || undefined).then(d => {
      setRequests(d);
      setLoading(false);
    });
  };

  useEffect(() => { load(); }, [statusFilter, typeFilter]);

  const handleApprove = async (app: AgencyApplicationModel) => {
    if (!confirm(`هل أنت متأكد من قبول طلب فتح ${app.agency_type === 'host' ? 'وكالة المضيفين' : 'وكالة الشحن'} (${app.agency_name})؟ سيتم تفعيل الوكالة فوراً.`)) return;
    setActionLoading(true);
    const adminName = firebaseAuth?.currentUser?.displayName || firebaseAuth?.currentUser?.email || 'المشرف العام';
    const res = await approveAgencyApplication(app, adminName);
    alert(res.message);
    setActionLoading(false);
    load();
  };

  const handleReject = async () => {
    if (!rejectModalApp) return;
    setActionLoading(true);
    const adminName = firebaseAuth?.currentUser?.displayName || firebaseAuth?.currentUser?.email || 'المشرف العام';
    const res = await rejectAgencyApplication(rejectModalApp.id, rejectModalApp.user_id, rejectionReason, adminName);
    alert(res.message);
    setRejectModalApp(null);
    setRejectionReason('');
    setActionLoading(false);
    load();
  };

  const handleCreateManual = async () => {
    if (!newUserId.trim() || !newAgencyName.trim()) {
      alert('يرجى ملء UID واسم الوكالة');
      return;
    }
    await createAgencyApplication({
      user_id: newUserId.trim(),
      agency_name: newAgencyName.trim(),
      agency_type: newAgencyType,
      whatsapp: newWhatsapp.trim(),
      country: newCountry.trim(),
    });
    setShowAddModal(false);
    setNewUserId(''); setNewAgencyName(''); setNewWhatsapp(''); setNewCountry('');
    load();
  };

  const statusColors: Record<string, string> = {
    pending: 'text-yellow-400 bg-yellow-400/10 border-yellow-400/20',
    approved: 'text-emerald-400 bg-emerald-400/10 border-emerald-400/20',
    rejected: 'text-rose-400 bg-rose-400/10 border-rose-400/20',
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <p className="text-slate-500 text-xs">{requests.length} طلب</p>
          <select value={statusFilter} onChange={e => setStatusFilter(e.target.value)}
            className="bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500">
            <option value="pending">⏳ قيد الانتظار (معلقة)</option>
            <option value="approved">✅ المقبولة</option>
            <option value="rejected">❌ المرفوضة</option>
            <option value="">جميع الحالات</option>
          </select>
          <select value={typeFilter} onChange={e => setTypeFilter(e.target.value)}
            className="bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500">
            <option value="">جميع أنواع الوكالات</option>
            <option value="host">🎙️ وكالات المضيفين</option>
            <option value="recharge">🪙 وكالات الشحن</option>
          </select>
        </div>

        <button onClick={() => setShowAddModal(true)}
          className="text-xs bg-indigo-600 hover:bg-indigo-700 text-white font-bold px-3.5 py-1.5 rounded-lg transition-all flex items-center gap-1.5 shadow-lg shadow-indigo-600/20">
          <Plus className="w-3.5 h-3.5" />
          ➕ إضافة طلب فتح وكالة يدوي
        </button>
      </div>

      {showAddModal && (
        <div className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-[#18181b] border border-white/10 rounded-2xl max-w-md w-full p-5 space-y-4 shadow-2xl">
            <h4 className="text-white font-bold text-sm">✨ تسجيل طلب فتح وكالة جديد</h4>
            <div className="space-y-3">
              <div>
                <label className="text-[11px] text-slate-400 block mb-1">نوع الوكالة</label>
                <select value={newAgencyType} onChange={e => setNewAgencyType(e.target.value as any)}
                  className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white">
                  <option value="host">وكالة مضيفين (Host Agency)</option>
                  <option value="recharge">وكالة شحن ورواتب (Recharge Agency)</option>
                </select>
              </div>
              <div>
                <label className="text-[11px] text-slate-400 block mb-1">UID المستخدم أو رقم المعرف *</label>
                <input value={newUserId} onChange={e => setNewUserId(e.target.value)} placeholder="اكتب UID أو ID المستخدم"
                  className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white" />
                <UserSearchPreview query={newUserId} />
              </div>
              <div>
                <label className="text-[11px] text-slate-400 block mb-1">اسم الوكالة المقترحة *</label>
                <input value={newAgencyName} onChange={e => setNewAgencyName(e.target.value)} placeholder="مثال: وكالة النجوم"
                  className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white" />
              </div>
              <div>
                <label className="text-[11px] text-slate-400 block mb-1">رقم الواتساب</label>
                <input value={newWhatsapp} onChange={e => setNewWhatsapp(e.target.value)} placeholder="+2010..."
                  className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white" />
              </div>
              <div>
                <label className="text-[11px] text-slate-400 block mb-1">الدولة</label>
                <input value={newCountry} onChange={e => setNewCountry(e.target.value)} placeholder="مصر، السعودية..."
                  className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white" />
              </div>
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <button onClick={() => setShowAddModal(false)} className="px-4 py-2 text-xs text-slate-400 hover:text-white">إلغاء</button>
              <button onClick={handleCreateManual} className="px-5 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl text-xs font-bold">تسجيل الطلب</button>
            </div>
          </div>
        </div>
      )}

      {rejectModalApp && (
        <div className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-[#18181b] border border-rose-500/30 rounded-2xl max-w-md w-full p-5 space-y-4 shadow-2xl">
            <h4 className="text-white font-bold text-sm flex items-center gap-2">
              <XCircle className="w-4 h-4 text-rose-400" />
              رفض طلب فتح الوكالة: {rejectModalApp.agency_name}
            </h4>
            <p className="text-slate-400 text-xs">
              يرجى كتابة سبب الرفض لتوضيحه لمقدم الطلب:
            </p>
            <textarea
              value={rejectionReason}
              onChange={e => setRejectionReason(e.target.value)}
              placeholder="مثال: المستندات غير واضحة، لا يستوفي الشروط..."
              className="w-full bg-[#121214] border border-white/10 rounded-xl p-3 text-xs text-white resize-none h-24 focus:outline-none focus:border-rose-500"
            />
            <div className="flex justify-end gap-2 pt-2">
              <button onClick={() => setRejectModalApp(null)} className="px-4 py-2 text-xs text-slate-400">إلغاء</button>
              <button onClick={handleReject} disabled={actionLoading}
                className="px-5 py-2 bg-rose-600 hover:bg-rose-700 disabled:opacity-50 text-white rounded-xl text-xs font-bold">
                {actionLoading ? 'جاري التنفيذ...' : 'تأكيد الرفض'}
              </button>
            </div>
          </div>
        </div>
      )}

      <DataTable
        loading={loading}
        columns={[
          { key: 'user_name', label: 'مقدم الطلب', sortable: true, render: r => {
            const req = r as AgencyApplicationModel;
            return (
              <div className="flex items-center gap-2.5">
                <img src={req.user_avatar || `https://ui-avatars.com/api/?name=${encodeURIComponent(req.user_name || 'User')}&background=random`} alt="" className="w-8 h-8 rounded-full object-cover border border-white/10 shrink-0" />
                <div>
                  <div className="text-white font-bold text-xs">{req.user_name || 'مستخدم'}</div>
                  <div className="text-[10px] text-slate-400 font-mono">ID: {req.custom_id || req.user_id?.slice(0, 8)}</div>
                </div>
              </div>
            );
          }},
          { key: 'agency_type', label: 'نوع الوكالة', sortable: true, render: r => {
            const isHost = (r as AgencyApplicationModel).agency_type === 'host';
            return (
              <span className={`px-2.5 py-1 rounded-lg text-[10px] font-bold border ${isHost ? 'bg-indigo-500/10 text-indigo-300 border-indigo-500/20' : 'bg-amber-500/10 text-amber-300 border-amber-500/20'}`}>
                {isHost ? '🎙️ وكالة مضيفين' : '🪙 وكالة شحن'}
              </span>
            );
          }},
          { key: 'agency_name', label: 'اسم الوكالة', sortable: true, render: r => (
            <span className="text-white font-bold text-xs">{(r as AgencyApplicationModel).agency_name}</span>
          )},
          { key: 'whatsapp', label: 'التواصل والدولة', render: r => {
            const req = r as AgencyApplicationModel;
            return (
              <div className="text-[11px] space-y-0.5">
                {req.whatsapp && <div className="text-emerald-400">📱 {req.whatsapp}</div>}
                {req.country && <div className="text-slate-400">🌍 {req.country}</div>}
              </div>
            );
          }},
          { key: 'doc_number', label: 'الوثائق والإثباتات', render: r => {
            const req = r as AgencyApplicationModel;
            return (
              <div className="flex items-center gap-1.5 flex-wrap">
                {req.doc_front_url && (
                  <a href={req.doc_front_url} target="_blank" rel="noreferrer"
                    className="text-[10px] bg-white/5 hover:bg-white/10 px-2 py-0.5 rounded border border-white/10 text-cyan-300 flex items-center gap-1">
                    <Eye className="w-3 h-3" /> الوثيقة
                  </a>
                )}
                {req.video_url && (
                  <a href={req.video_url} target="_blank" rel="noreferrer"
                    className="text-[10px] bg-white/5 hover:bg-white/10 px-2 py-0.5 rounded border border-white/10 text-amber-300 flex items-center gap-1">
                    <Eye className="w-3 h-3" /> الفيديو
                  </a>
                )}
                {!req.doc_front_url && !req.video_url && <span className="text-[10px] text-slate-500">—</span>}
              </div>
            );
          }},
          { key: 'status', label: 'الحالة', sortable: true, render: r => {
            const st = (r as AgencyApplicationModel).status;
            return (
              <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold border ${statusColors[st] ?? 'text-slate-400'}`}>
                {st === 'approved' ? '✅ مقبول' : st === 'rejected' ? '❌ مرفوض' : '⏳ قيد المراجعة'}
              </span>
            );
          }},
          { key: 'created_at', label: 'التاريخ', sortable: true, render: r => new Date((r as AgencyApplicationModel).created_at).toLocaleDateString('ar-EG') },
          { key: 'actions', label: 'الإجراءات', render: r => {
            const req = r as AgencyApplicationModel;
            if (req.status === 'pending') {
              return (
                <div className="flex items-center gap-1.5">
                  <button onClick={() => handleApprove(req)} disabled={actionLoading}
                    className="text-[10px] bg-emerald-500/20 text-emerald-400 hover:bg-emerald-500/30 border border-emerald-500/30 px-2.5 py-1 rounded-lg font-bold transition-all flex items-center gap-1">
                    <Check className="w-3 h-3" /> قبول
                  </button>
                  <button onClick={() => { setRejectModalApp(req); setRejectionReason(''); }} disabled={actionLoading}
                    className="text-[10px] bg-rose-500/20 text-rose-400 hover:bg-rose-500/30 border border-rose-500/30 px-2.5 py-1 rounded-lg font-bold transition-all flex items-center gap-1">
                    <XCircle className="w-3 h-3" /> رفض
                  </button>
                </div>
              );
            }
            if (req.status === 'approved') {
              return <span className="text-[10px] text-emerald-400 font-bold">تم القبول والتفعيل</span>;
            }
            return (
              <div className="text-[10px] text-rose-400">
                مرفوض {req.rejection_reason ? `(${req.rejection_reason})` : ''}
              </div>
            );
          }},
        ]}
        data={requests}
        searchKeys={['user_name', 'agency_name', 'custom_id', 'country', 'whatsapp']}
      />
    </div>
  );
}

/* =============================================================
   3. JOIN REQUESTS TAB
   ============================================================= */
function JoinRequestsTab() {
  const { t } = useContext(I18nContext);
  const [requests, setRequests] = useState<AgencyJoinRequestModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('pending');

  const load = () => { setLoading(true); getHostAgencyJoinRequests(filter).then(d => { setRequests(d); setLoading(false); }); };
  useEffect(() => { load(); }, [filter]);

  const statusColors: Record<string, string> = {
    pending: 'text-yellow-400', approved: 'text-emerald-400', rejected: 'text-rose-400',
  };

  return (
    <div>
      <div className="flex items-center gap-3 mb-3">
        <p className="text-slate-500 text-xs">{requests.length} {t('agency.requestsCount')}</p>
        <select value={filter} onChange={e => setFilter(e.target.value)}
          className="bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500">
          <option value="pending">{t('agency.pending')}</option>
          <option value="approved">{t('agency.approved')}</option>
          <option value="rejected">{t('agency.rejected')}</option>
          <option value="">{t('agency.all')}</option>
        </select>
      </div>
      <DataTable
        loading={loading}
        columns={[
          { key: 'user_name', label: t('agency.col.name'), sortable: true },
          { key: 'agency_name', label: t('agency.col.name'), sortable: true },
          { key: 'status', label: t('agency.col.status'), sortable: true, render: r => {
            const st = (r as AgencyJoinRequestModel).status;
            return <span className={`font-semibold ${statusColors[st] ?? 'text-slate-400'}`}>{t(`agency.${st}` as any)}</span>;
          }},
          { key: 'created_at', label: t('agency.col.date'), sortable: true, render: r => new Date((r as AgencyJoinRequestModel).created_at).toLocaleDateString() },
          { key: 'actions', label: t('agency.col.actions'), render: r => {
            const req = r as AgencyJoinRequestModel;
            if (req.status !== 'pending') return <span className="text-[10px] text-slate-500">—</span>;
            return (
              <div className="flex items-center gap-2">
                <button onClick={async () => { await approveJoinRequest(req.id); load(); }}
                  className="text-[10px] bg-emerald-500/20 text-emerald-400 hover:bg-emerald-500/30 px-2 py-0.5 rounded font-semibold">{t('agency.approve')}</button>
                <button onClick={async () => { await rejectJoinRequest(req.id); load(); }}
                  className="text-[10px] bg-rose-500/20 text-rose-400 hover:bg-rose-500/30 px-2 py-0.5 rounded font-semibold">{t('agency.reject')}</button>
              </div>
            );
          }},
        ]}
        data={requests}
        searchKeys={['user_name', 'agency_name', 'status']}
      />
    </div>
  );
}

/* =============================================================
   4. FINANCIAL TAB (Ledger + Withdrawals)
   ============================================================= */
function FinancialTab() {
  const { t } = useContext(I18nContext);
  const [subTab, setSubTab] = useState<'ledger' | 'withdrawals'>('ledger');
  const [ledger, setLedger] = useState<AgencyLedgerEntryModel[]>([]);
  const [withdrawals, setWithdrawals] = useState<AgencyWithdrawalRequestModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [wFilter, setWFilter] = useState('pending');

  const loadLedger = () => { getAgencyLedger().then(d => setLedger(d)); };
  const loadWithdrawals = () => { setLoading(true); getWithdrawalRequests(wFilter).then(d => { setWithdrawals(d); setLoading(false); }); };

  useEffect(() => { loadLedger(); }, []);
  useEffect(() => { loadWithdrawals(); }, [wFilter]);

  const statusColors: Record<string, string> = {
    pending: 'text-yellow-400', approved: 'text-emerald-400', rejected: 'text-rose-400',
  };

  return (
    <div className="space-y-4">
      <div className="flex gap-2">
        <button onClick={() => setSubTab('ledger')}
          className={`text-xs px-3 py-1.5 rounded-lg font-semibold transition-colors ${subTab === 'ledger' ? 'bg-indigo-500/20 text-indigo-300' : 'text-slate-400 hover:text-white'}`}>
          {t('agency.diamondLedger')}
        </button>
        <button onClick={() => setSubTab('withdrawals')}
          className={`text-xs px-3 py-1.5 rounded-lg font-semibold transition-colors ${subTab === 'withdrawals' ? 'bg-indigo-500/20 text-indigo-300' : 'text-slate-400 hover:text-white'}`}>
          {t('agency.withdrawalRequests')}
        </button>
      </div>

      {subTab === 'ledger' && (
        <div>
          <p className="text-slate-500 text-xs mb-3">{ledger.length} {t('agency.entriesCount')}</p>
          <DataTable
            loading={false}
            columns={[
              { key: 'user_name', label: t('agency.col.name'), sortable: true },
              { key: 'agency_name', label: t('agency.col.name'), sortable: true },
              { key: 'txn_type', label: t('agency.col.type'), sortable: true, render: e => <span className="text-indigo-300">{(e as AgencyLedgerEntryModel).txn_type}</span> },
              { key: 'amount', label: t('agency.col.amount'), sortable: true, render: e => {
                const entry = e as AgencyLedgerEntryModel;
                return <span className={entry.direction === 'in' ? 'text-emerald-400' : 'text-rose-400'}>
                  {entry.direction === 'in' ? '+' : '-'}{entry.amount?.toLocaleString() ?? '0'} 💎
                </span>;
              }},
              { key: 'balance_after', label: t('agency.col.balance'), sortable: true, render: e => <span className="text-cyan-400">{(e as AgencyLedgerEntryModel).balance_after?.toLocaleString() ?? '0'}</span> },
              { key: 'note', label: t('agency.col.note'), render: e => <span className="text-slate-500">{(e as AgencyLedgerEntryModel).note ?? '—'}</span> },
              { key: 'created_at', label: t('agency.col.date'), sortable: true, render: e => new Date((e as AgencyLedgerEntryModel).created_at).toLocaleDateString() },
            ]}
            data={ledger}
            searchKeys={['user_name', 'agency_name', 'txn_type', 'note']}
          />
        </div>
      )}

      {subTab === 'withdrawals' && (
        <div>
          <div className="flex items-center gap-3 mb-3">
            <p className="text-slate-500 text-xs">{withdrawals.length} {t('agency.requestsCount')}</p>
            <select value={wFilter} onChange={e => setWFilter(e.target.value)}
              className="bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none focus:border-indigo-500">
              <option value="pending">{t('agency.pending')}</option>
              <option value="approved">{t('agency.approved')}</option>
              <option value="rejected">{t('agency.rejected')}</option>
              <option value="">{t('agency.all')}</option>
            </select>
          </div>
          <DataTable
            loading={loading}
            columns={[
              { key: 'user_name', label: t('agency.col.name'), sortable: true },
              { key: 'agency_name', label: t('agency.col.name'), sortable: true },
              { key: 'amount', label: t('agency.col.amount'), sortable: true, render: w => <span className="text-amber-400 font-semibold">{(w as AgencyWithdrawalRequestModel).amount?.toLocaleString() ?? '0'} 💎</span> },
              { key: 'status', label: t('agency.col.status'), sortable: true, render: w => {
                const st = (w as AgencyWithdrawalRequestModel).status;
                return <span className={`font-semibold ${statusColors[st] ?? 'text-slate-400'}`}>{t(`agency.${st}` as any)}</span>;
              }},
              { key: 'payment_method', label: t('agency.col.payment'), render: w => <span className="text-slate-400">{(w as AgencyWithdrawalRequestModel).payment_method ?? '—'}</span> },
              { key: 'created_at', label: t('agency.col.date'), sortable: true, render: w => new Date((w as AgencyWithdrawalRequestModel).created_at).toLocaleDateString() },
              { key: 'actions', label: t('agency.col.actions'), render: w => {
                const req = w as AgencyWithdrawalRequestModel;
                if (req.status !== 'pending') return <span className="text-[10px] text-slate-500">—</span>;
                return (
                  <div className="flex items-center gap-2">
                    <button onClick={async () => { await approveWithdrawal(req.id); loadWithdrawals(); }}
                      className="text-[10px] bg-emerald-500/20 text-emerald-400 hover:bg-emerald-500/30 px-2 py-0.5 rounded font-semibold">{t('agency.approve')}</button>
                    <button onClick={async () => { await rejectWithdrawal(req.id); loadWithdrawals(); }}
                      className="text-[10px] bg-rose-500/20 text-rose-400 hover:bg-rose-500/30 px-2 py-0.5 rounded font-semibold">{t('agency.reject')}</button>
                  </div>
                );
              }},
            ]}
            data={withdrawals}
            searchKeys={['user_name', 'agency_name', 'status', 'payment_method']}
          />
        </div>
      )}
    </div>
  );
}

/* =============================================================
   5. MILESTONES TAB (المراحل وتحديد الرواتب والمكافآت والعمولات)
   ============================================================= */
function MilestonesTab() {
  const { t } = useContext(I18nContext);
  const [milestones, setMilestones] = useState<HostMilestoneModel[]>([]);
  const [storeItems, setStoreItems] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);

  const [title, setTitle] = useState('');
  const [targetDiamonds, setTargetDiamonds] = useState('1000000');
  const [rewardType, setRewardType] = useState('salary_usd');
  const [rewardValue, setRewardValue] = useState('100');
  const [rewardItemId, setRewardItemId] = useState('');
  const [rewardImageUrl, setRewardImageUrl] = useState('');
  const [backgroundUrl, setBackgroundUrl] = useState('');
  const [agentCommissionRate, setAgentCommissionRate] = useState('10');
  const [periodType, setPeriodType] = useState('monthly');
  const [sortOrder, setSortOrder] = useState('0');
  const [isActive, setIsActive] = useState(true);
  const [showItemPicker, setShowItemPicker] = useState(false);

  const load = () => {
    setLoading(true);
    getHostMilestones().then(d => { setMilestones(d); setLoading(false); });
    supabase.from('store_items').select('*').then(({ data }) => {
      if (data) setStoreItems(data);
    });
  };

  useEffect(() => { load(); }, []);

  const resetForm = () => {
    setTitle(''); setTargetDiamonds('1000000'); setRewardType('salary_usd');
    setRewardValue('100'); setRewardItemId(''); setRewardImageUrl(''); setBackgroundUrl('');
    setAgentCommissionRate('10'); setPeriodType('monthly'); setSortOrder('0'); setIsActive(true);
    setEditId(null); setShowItemPicker(false);
  };

  const openEdit = (m: any) => {
    setEditId(m.id);
    setTitle(m.title ?? '');
    setTargetDiamonds(String(m.target_diamonds ?? m.targetDiamonds ?? 1000000));
    setRewardType(m.reward_type ?? m.rewardType ?? 'salary_usd');
    setRewardValue(String(m.reward_value ?? m.rewardValue ?? 100));
    setRewardItemId(m.reward_item_id ?? m.rewardItemId ?? '');
    setRewardImageUrl(m.reward_image_url ?? m.rewardImageUrl ?? m.image_url ?? '');
    setBackgroundUrl(m.background_url ?? m.backgroundUrl ?? '');
    const rate = Number(m.agent_commission_rate ?? m.agentCommissionRate ?? 0.1);
    setAgentCommissionRate(String((rate * 100).toFixed(0)));
    setPeriodType(m.period_type ?? m.periodType ?? 'monthly');
    setSortOrder(String(m.sort_order ?? m.sortOrder ?? 0));
    setIsActive(m.is_active !== false && m.isActive !== false);
    setShowForm(true);
  };

  const handleSubmit = async () => {
    if (!title.trim()) return;
    const payload = {
      title: title.trim(),
      target_diamonds: parseInt(targetDiamonds) || 0,
      reward_type: rewardType as any,
      reward_value: parseFloat(rewardValue) || 0,
      reward_item_id: rewardItemId.trim() || null,
      reward_image_url: rewardImageUrl.trim() || null,
      background_url: backgroundUrl.trim() || null,
      agent_commission_rate: (parseFloat(agentCommissionRate) || 0) / 100,
      period_type: periodType as any,
      is_active: isActive,
      sort_order: parseInt(sortOrder) || 0,
    };

    if (editId) {
      await updateHostMilestone(editId, payload);
    } else {
      await createHostMilestone(payload as any);
    }
    resetForm();
    setShowForm(false);
    load();
  };

  const selectedItem = storeItems.find(i => i.item_id === rewardItemId || i.id === rewardItemId);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-white text-sm font-bold">🎯 مراحل وتارجت المضيفين والرواتب والعمولات</h3>
          <p className="text-slate-400 text-xs mt-0.5">حدد الهدف بالماسات والراتب الفعلي ونسبة عمولة الوكيل والجوائز التلقائية فور تحقيق الهدف</p>
        </div>
        <button onClick={() => { if (showForm) resetForm(); setShowForm(!showForm); }}
          className="text-xs bg-indigo-600 hover:bg-indigo-700 text-white px-4 py-2 rounded-xl font-bold transition-all shadow-lg shadow-indigo-600/30 flex items-center gap-1.5">
          {showForm ? t('cancel') : '➕ إضافة مرحلة / تارجت جديد'}
        </button>
      </div>

      {showForm && (
        <div className="bg-[#18181b] rounded-2xl border border-indigo-500/30 p-5 space-y-4 shadow-xl">
          <div className="flex items-center justify-between border-b border-white/5 pb-3">
            <span className="text-white font-bold text-xs">{editId ? '✏️ تعديل المرحلة والتارجت' : '✨ إضافة مرحلة جديدة'}</span>
            <div className="flex items-center gap-2">
              <label className="text-xs text-slate-300">مفعلة ونشطة:</label>
              <input type="checkbox" checked={isActive} onChange={e => setIsActive(e.target.checked)} className="w-4 h-4 accent-indigo-500 cursor-pointer" />
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div>
              <label className="text-[11px] text-slate-400 block mb-1">اسم المرحلة / التارجت *</label>
              <input value={title} onChange={e => setTitle(e.target.value)} placeholder="مثال: الهدف الفضي (1M)"
                className="w-full bg-[#121214] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-indigo-500" />
            </div>
            <div>
              <label className="text-[11px] text-cyan-400 block mb-1">الهدف المطلوب بالماسات 💎 *</label>
              <input type="number" value={targetDiamonds} onChange={e => setTargetDiamonds(e.target.value)} placeholder="1000000"
                className="w-full bg-[#121214] border border-cyan-500/30 rounded-xl py-2 px-3 text-xs text-cyan-300 font-bold focus:outline-none focus:border-cyan-400" />
            </div>
            <div>
              <label className="text-[11px] text-amber-400 block mb-1">عمولة الوكيل من أرباح المضيف (%) *</label>
              <div className="flex items-center gap-1.5">
                <input type="number" step="0.5" value={agentCommissionRate} onChange={e => setAgentCommissionRate(e.target.value)} placeholder="10"
                  className="w-full bg-[#121214] border border-amber-500/30 rounded-xl py-2 px-3 text-xs text-amber-300 font-bold focus:outline-none focus:border-amber-400" />
                <span className="text-xs text-amber-400 font-bold">%</span>
                <button type="button" onClick={() => setAgentCommissionRate('5')} className="px-2 py-1 bg-amber-500/10 hover:bg-amber-500/20 text-amber-300 rounded text-[10px]">5%</button>
                <button type="button" onClick={() => setAgentCommissionRate('10')} className="px-2 py-1 bg-amber-500/10 hover:bg-amber-500/20 text-amber-300 rounded text-[10px]">10%</button>
                <button type="button" onClick={() => setAgentCommissionRate('20')} className="px-2 py-1 bg-amber-500/10 hover:bg-amber-500/20 text-amber-300 rounded text-[10px]">20%</button>
              </div>
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div>
              <label className="text-[11px] text-slate-400 block mb-1">نوع المكافأة / الراتب *</label>
              <select value={rewardType} onChange={e => {
                const val = e.target.value;
                setRewardType(val);
                if (['frame', 'entry_effect', 'badge', 'gift_item'].includes(val)) {
                  setShowItemPicker(true);
                }
              }}
                className="w-full bg-[#121214] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-indigo-500">
                <option value="salary_usd">💵 راتب نقدي بالدولار (USD)</option>
                <option value="gold">🪙 عملات ذهبية (Coins)</option>
                <option value="diamonds">💎 ماسات (Diamonds)</option>
                <option value="vip_days">👑 أيام عضوية VIP</option>
                <option value="frame">🖼️ إطار أفاتار</option>
                <option value="entry_effect">🚗 مؤثر دخول / سيارة</option>
                <option value="badge">🏅 وسام / شارة</option>
                <option value="gift_item">🎁 هدية من المتجر</option>
              </select>
            </div>
            <div>
              <label className="text-[11px] text-emerald-400 block mb-1">
                {rewardType === 'salary_usd' ? 'قيمة الراتب بالدولار ($) *' :
                 rewardType === 'gold' ? 'عدد العملات الذهبية 🪙 *' :
                 rewardType === 'diamonds' ? 'عدد الماسات 💎 *' :
                 rewardType === 'vip_days' ? 'عدد أيام عضوية VIP 👑 *' :
                 'قيمة / مدة المكافأة بالايام أو العدد *'}
              </label>
              <input type="number" value={rewardValue} onChange={e => setRewardValue(e.target.value)}
                placeholder={rewardType === 'salary_usd' ? '100$' : rewardType === 'vip_days' ? '30 يوم' : '1000'}
                className="w-full bg-[#121214] border border-emerald-500/30 rounded-xl py-2 px-3 text-xs text-emerald-300 font-bold focus:outline-none focus:border-emerald-400" />
            </div>
            <div>
              <label className="text-[11px] text-slate-400 block mb-1">الفترة الزمنية للهدف</label>
              <select value={periodType} onChange={e => setPeriodType(e.target.value)}
                className="w-full bg-[#121214] border border-white/10 rounded-xl py-2 px-3 text-xs text-white focus:outline-none focus:border-indigo-500">
                <option value="monthly">شهري (Monthly)</option>
                <option value="weekly">أسبوعي (Weekly)</option>
                <option value="daily">يومي (Daily)</option>
                <option value="all_time">تراكمي دائم (All Time)</option>
              </select>
            </div>
          </div>

          {/* Dynamic Item Picker adapting to selected rewardType */}
          <div className="bg-[#121214] rounded-xl border border-white/5 p-3 space-y-2">
            <div className="flex items-center justify-between">
              <label className="text-xs text-slate-300 font-bold flex items-center gap-1.5">
                {rewardType === 'frame' ? '🖼️ اختيار إطار الأفاتار الممنوح للمضيف' :
                 rewardType === 'entry_effect' ? '🚗 اختيار سيارة / مؤثر الدخول الممنوح للمضيف' :
                 rewardType === 'badge' ? '🏅 اختيار الوسام / الشارة الممنوحة للمضيف' :
                 rewardType === 'gift_item' ? '🎁 اختيار الهدية الممنوحة للمضيف من المتجر' :
                 '🎁 إضافة هدية / إطار / ميزة إضافية للمضيف (اختياري)'}
              </label>
              <button type="button" onClick={() => setShowItemPicker(!showItemPicker)}
                className="text-[11px] bg-indigo-500/20 text-indigo-300 hover:bg-indigo-500/30 px-3 py-1 rounded-lg font-semibold transition-all">
                {showItemPicker ? 'إغلاق القائمة' : '🔍 فتح قائمة الاختيار من المتجر'}
              </button>
            </div>

            {selectedItem && (
              <div className="flex items-center gap-3 p-2 bg-indigo-500/10 border border-indigo-500/20 rounded-lg">
                {selectedItem.icon_asset && (
                  <img src={selectedItem.icon_asset} alt="" className="w-10 h-10 object-contain rounded" />
                )}
                <div>
                  <div className="text-xs text-white font-bold">{selectedItem.name || selectedItem.item_id}</div>
                  <div className="text-[10px] text-indigo-300">القسم: {selectedItem.category || selectedItem.type || 'عنصر متجر'} | المعرف: {selectedItem.item_id || selectedItem.id}</div>
                </div>
                <button type="button" onClick={() => setRewardItemId('')} className="ml-auto text-rose-400 hover:text-rose-300 text-xs font-bold">✕ إزالة</button>
              </div>
            )}

            {showItemPicker && (
              <div className="space-y-2">
                <div className="text-[10px] text-slate-400">
                  {rewardType === 'frame' ? 'عرض إطارات الأفاتار المتاحة في المتجر:' :
                   rewardType === 'entry_effect' ? 'عرض سيارات ومؤثرات الدخول المتاحة في المتجر:' :
                   rewardType === 'badge' ? 'عرض الأوسمة والشارات والقلادات المتاحة:' :
                   'عرض عناصر وهدايا المتجر المتاحة:'}
                </div>
                <div className="grid grid-cols-2 sm:grid-cols-4 md:grid-cols-6 gap-2 max-h-56 overflow-y-auto p-2 bg-[#18181b] rounded-lg border border-white/10">
                  {storeItems
                    .filter(item => {
                      if (rewardType === 'frame') return item.category === 'frame' || item.type === 'frame' || (item.name && item.name.includes('إطار'));
                      if (rewardType === 'entry_effect') return item.category === 'entry_effect' || item.category === 'car' || (item.name && (item.name.includes('سيارة') || item.name.includes('دخول')));
                      if (rewardType === 'badge') return item.category === 'badge' || item.category === 'necklace' || (item.name && (item.name.includes('وسام') || item.name.includes('شارة') || item.name.includes('قلادة')));
                      if (rewardType === 'gift_item') return item.category === 'gift' || item.type === 'gift' || (!['frame', 'car', 'entry_effect'].includes(item.category));
                      return true;
                    })
                    .map(item => {
                      const itemId = item.item_id || item.id;
                      const isSel = rewardItemId === itemId;
                      return (
                        <div key={itemId} onClick={() => { setRewardItemId(itemId); setShowItemPicker(false); }}
                          className={`p-2 rounded-lg border cursor-pointer flex flex-col items-center gap-1 transition-all ${isSel ? 'border-indigo-500 bg-indigo-500/20' : 'border-white/5 bg-[#121214] hover:border-white/20'}`}>
                          <img src={item.icon_asset || item.svga_asset || item.video_asset} alt="" className="w-8 h-8 object-contain" />
                          <span className="text-[10px] text-white truncate max-w-full text-center font-medium">{item.name || itemId}</span>
                          <span className="text-[8px] text-indigo-300">{item.category || item.type || ''}</span>
                        </div>
                      );
                    })}
                </div>
              </div>
            )}
          </div>

          {/* Image and Background Upload for the Milestone */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3 bg-[#121214] p-3 rounded-xl border border-white/5">
            <div>
              <label className="text-[11px] text-indigo-400 font-bold block mb-1">🖼️ صورة / أيقونة / SVGA المرحلة</label>
              <ImageUpload
                currentUrl={rewardImageUrl}
                onUpload={async (file) => {
                  const url = await uploadStoreItem(file, 'milestones');
                  setRewardImageUrl(url);
                  return url;
                }}
                onClear={() => setRewardImageUrl('')}
              />
            </div>
            <div>
              <label className="text-[11px] text-purple-400 font-bold block mb-1">🎨 صورة خلفية كرت المرحلة (اختياري)</label>
              <ImageUpload
                currentUrl={backgroundUrl}
                onUpload={async (file) => {
                  const url = await uploadStoreItem(file, 'milestones_bg');
                  setBackgroundUrl(url);
                  return url;
                }}
                onClear={() => setBackgroundUrl('')}
              />
            </div>
          </div>

          <div className="flex items-center justify-end gap-2 pt-2 border-t border-white/5">
            <button type="button" onClick={() => { resetForm(); setShowForm(false); }}
              className="text-xs text-slate-400 hover:text-white px-4 py-2 rounded-xl transition-all">
              إلغاء
            </button>
            <button type="button" onClick={handleSubmit}
              className="text-xs bg-emerald-600 hover:bg-emerald-700 text-white font-bold px-6 py-2 rounded-xl shadow-lg shadow-emerald-600/30 transition-all flex items-center gap-1.5">
              <CheckCircle2 className="w-4 h-4" /> {editId ? 'حفظ التعديلات' : 'إنشاء المرحلة الآن'}
            </button>
          </div>
        </div>
      )}

      <DataTable
        loading={loading}
        columns={[
          { key: 'reward_image_url', label: 'الأيقونة', render: m => {
            const img = (m as any).reward_image_url || (m as any).rewardImageUrl || (m as any).image_url;
            return img ? (
              <img src={img} alt="" className="w-8 h-8 rounded-lg object-contain bg-white/5 p-1 border border-white/10" />
            ) : <span className="text-slate-600 text-xs">—</span>;
          }},
          { key: 'title', label: 'المرحلة / التارجت', sortable: true, render: m => <span className="font-bold text-white">{(m as any).title}</span> },
          { key: 'target_diamonds', label: 'الهدف 💎', sortable: true, render: m => {
            const val = Number((m as any).target_diamonds ?? (m as any).targetDiamonds ?? 0);
            return <span className="text-cyan-400 font-bold">{val.toLocaleString()} 💎</span>;
          }},
          { key: 'reward_type', label: 'نوع المكافأة', sortable: true, render: m => {
            const rt = (m as any).reward_type ?? (m as any).rewardType;
            return <span className="text-amber-400 font-semibold">{rt === 'salary_usd' ? '💵 راتب USD' : rt === 'gold' ? '🪙 عملات' : rt === 'diamonds' ? '💎 ألماس' : rt === 'frame' ? '🖼️ إطار' : rt === 'badge' ? '🏅 وسام' : rt === 'entry_effect' ? '🚗 مؤثر دخول' : rt === 'vip_days' ? '👑 أيام VIP' : rt || '—'}</span>;
          }},
          { key: 'reward_value', label: 'قيمة الراتب / المكافأة', sortable: true, render: m => {
            const val = (m as any).reward_value ?? (m as any).rewardValue ?? '';
            const rt = (m as any).reward_type ?? (m as any).rewardType;
            return <span className="text-emerald-400 font-bold">{val} {rt === 'salary_usd' ? '$' : rt === 'gold' ? '🪙' : rt === 'diamonds' ? '💎' : rt === 'vip_days' ? 'يوم' : ''}</span>;
          }},
          { key: 'agent_commission_rate', label: 'عمولة الوكيل (%)', sortable: true, render: m => {
            const rate = Number((m as any).agent_commission_rate ?? (m as any).agentCommissionRate ?? 0.1);
            return <span className="text-amber-400 font-bold">{(rate * 100).toFixed(0)}%</span>;
          }},
          { key: 'period_type', label: 'الفترة', sortable: true, render: m => {
            const pt = (m as any).period_type ?? (m as any).periodType;
            return <span className="text-slate-400">{pt === 'monthly' ? 'شهري' : pt === 'weekly' ? 'أسبوعي' : pt === 'all_time' ? 'تراكمي' : pt === 'daily' ? 'يومي' : pt || '—'}</span>;
          }},
          { key: 'is_active', label: 'نشط', sortable: true, render: m => {
            const active = (m as any).is_active !== false && (m as any).isActive !== false;
            return <span className={`px-2 py-0.5 rounded text-[10px] font-bold ${active ? 'bg-emerald-500/20 text-emerald-400' : 'bg-rose-500/20 text-rose-400'}`}>{active ? 'نعم' : 'لا'}</span>;
          }},
        ]}
        data={milestones}
        searchKeys={['title', 'reward_type', 'period_type']}
        onEdit={m => openEdit(m)}
        onDelete={async m => {
          if (confirm('هل أنت متأكد من حذف هذه المرحلة؟')) { await deleteHostMilestone((m as any).id); load(); }
        }}
      />
    </div>
  );
}

/* =============================================================
   6. RECHARGE AGENCIES TAB (وكالات الشحن وإدارة الرواتب والتحويلات)
   ============================================================= */
function RechargeAgenciesTab() {
  const { t } = useContext(I18nContext);
  const [agents, setAgents] = useState<any[]>([]);
  const [withdrawals, setWithdrawals] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAddModal, setShowAddModal] = useState(false);

  // New Agent Form
  const [targetUid, setTargetUid] = useState('');
  const [agencyName, setAgencyName] = useState('');
  const [agencyLogo, setAgencyLogo] = useState('');
  const [whatsappPhone, setWhatsappPhone] = useState('');
  const [initialCoins, setInitialCoins] = useState('0');
  const [rechargeCommissionRate, setRechargeCommissionRate] = useState('5');

  // Edit Agent Modal
  const [editAgent, setEditAgent] = useState<any | null>(null);
  const [editName, setEditName] = useState('');
  const [editLogo, setEditLogo] = useState('');
  const [editWhatsapp, setEditWhatsapp] = useState('');
  const [editCoins, setEditCoins] = useState('0');
  const [editCommissionRate, setEditCommissionRate] = useState('5');

  // Recharge User Form
  const [rechargeUserUid, setRechargeUserUid] = useState('');
  const [rechargeCoinsAmount, setRechargeCoinsAmount] = useState('1000');
  const [showRechargeModal, setShowRechargeModal] = useState(false);

  // Transfer Proof Modal
  const [selectedWithdrawal, setSelectedWithdrawal] = useState<any | null>(null);
  const [proofUrl, setProofUrl] = useState('');

  const load = async () => {
    setLoading(true);
    try {
      const [u1, u2, raSnap] = await Promise.all([
        supabase.from('users').select('*').eq('is_recharge_agent', true),
        supabase.from('users').select('*').eq('isRechargeAgent', true),
        supabase.from('recharge_agents').select('*'),
      ]);
      const map = new Map<string, any>();
      (u1.data || []).forEach((u: any) => map.set(u.id || u.uid, u));
      (u2.data || []).forEach((u: any) => map.set(u.id || u.uid, { ...(map.get(u.id || u.uid) || {}), ...u }));
      (raSnap.data || []).forEach((r: any) => {
        const key = r.id || r.uid || r.owner_id;
        const prev = map.get(key) || {};
        map.set(key, { ...prev, ...r, id: key, uid: key, is_recharge_agent: true });
      });
      setAgents(Array.from(map.values()));

      const { data: wData } = await supabase.from('agency_withdrawal_requests').select('*').order('created_at', { ascending: false });
      setWithdrawals(wData || []);
    } catch (_) {}
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const handleCreateRechargeAgent = async () => {
    const q = targetUid.trim();
    if (!q) { alert('يرجى كتابة UID أو رقم المعرف (ID) للمستخدم'); return; }

    // Resolve user
    const u = await searchUserProfile(q);
    if (!u) {
      alert(`لم يتم العثور على أي مستخدم بالمعرف "${q}". يرجى التأكد من كتابة الـ ID أو الـ UID الصحيح.`);
      return;
    }
    const userId = u.uid || u.id;
    const adminName = firebaseAuth?.currentUser?.displayName || firebaseAuth?.currentUser?.email || 'المشرف العام';

    await updateRechargeAgency(userId, {
      recharge_agency_name: agencyName.trim() || 'وكالة الشحن المعتمدة',
      recharge_agency_logo: agencyLogo.trim() || undefined,
      whatsapp_number: whatsappPhone.trim() || undefined,
      coins: parseInt(initialCoins) || 0,
      recharge_commission_rate: parseFloat(rechargeCommissionRate) || 5,
      adminName,
    });

    setShowAddModal(false);
    setTargetUid(''); setAgencyName(''); setAgencyLogo(''); setWhatsappPhone(''); setInitialCoins('0');
    setRechargeCommissionRate('5');
    alert(`تم تعيين وتفعيل وكيل الشحن (${u.name}) بنجاح وإرسال إشعار تهنئة وافتتاح له!`);
    load();
  };

  const openEditModal = (ag: any) => {
    setEditAgent(ag);
    setEditName(ag.recharge_agency_name || ag.name || '');
    setEditLogo(ag.recharge_agency_logo || '');
    setEditWhatsapp(ag.whatsapp_number || '');
    setEditCoins(String(ag.coins || 0));
    setEditCommissionRate(String(ag.recharge_commission_rate ?? 5));
  };

  const handleSaveEditAgent = async () => {
    if (!editAgent) return;
    const adminName = firebaseAuth?.currentUser?.displayName || firebaseAuth?.currentUser?.email || 'المشرف العام';
    await updateRechargeAgency(editAgent.id, {
      recharge_agency_name: editName.trim() || 'وكالة الشحن المعتمدة',
      recharge_agency_logo: editLogo.trim() || undefined,
      whatsapp_number: editWhatsapp.trim() || undefined,
      coins: parseInt(editCoins) || 0,
      recharge_commission_rate: parseFloat(editCommissionRate) || 5,
      adminName,
    });
    setEditAgent(null);
    alert('تم تحديث بيانات وكالة الشحن بنجاح!');
    load();
  };

  const handleRevokeAgent = async (ag: any) => {
    if (confirm(`هل أنت متأكد من سحب صفة وكيل الشحن من "${ag.recharge_agency_name || ag.name}"؟`)) {
      await revokeRechargeAgency(ag.id);
      alert('تم سحب صفة وكيل الشحن بنجاح');
      load();
    }
  };

  const handleRechargeUser = async () => {
    const q = rechargeUserUid.trim();
    if (!q || !rechargeCoinsAmount) return;
    const amount = parseInt(rechargeCoinsAmount) || 0;
    if (amount <= 0) return;

    // Resolve user by id or custom_id
    const u = await searchUserProfile(q);
    if (!u) {
      alert('لم يتم العثور على مستخدم بهذا الـ ID أو المعرف');
      return;
    }

    const currentCoins = Number(u.coins || 0);
    const newCoins = currentCoins + amount;
    await supabase.from('users').update({ 
      coins: newCoins,
      recharged_coins: Number(u.recharged_coins || 0) + amount,
      total_recharge: Number(u.total_recharge || 0) + amount,
    }).eq('id', u.id);

    // مزامنة فورية مع Firestore لكي يظهر الشحن فوراً داخل حدث الشحن ويستلم المستخدم المكافأة
    try {
      const now = new Date();
      const eventId = `recharge_${now.getFullYear()}_${String(now.getMonth() + 1).padStart(2, '0')}`;
      const userRef = doc(firestoreDb, 'users', u.id);
      await setDoc(userRef, {
        coins: increment(amount),
        recharged_coins: increment(amount),
        total_recharge: increment(amount),
      }, { merge: true });

      const progressRef = doc(firestoreDb, 'recharge_event_progress', `${eventId}_${u.id}`);
      await setDoc(progressRef, {
        event_id: eventId,
        user_id: u.id,
        total_recharged_coins: increment(amount),
        updated_at: now.toISOString(),
      }, { merge: true });
    } catch (err) {
      console.warn('Firestore agency recharge sync:', err);
    }

    const adminName = firebaseAuth?.currentUser?.displayName || firebaseAuth?.currentUser?.email || 'المشرف العام';
    await sendSystemNotification({
      userId: u.id,
      title: '🪙 شحن رصيد عملات لحسابك',
      body: `مبروك! قام المشرف [${adminName}] بشحن ${amount.toLocaleString()} عملة ذهبية لحسابك بنجاح. رصيدك الحالي الآن: ${newCoins.toLocaleString()} عملة.`,
      type: 'system',
      action: 'coins_recharged',
      extraData: { amount, new_balance: newCoins, admin_name: adminName },
    });

    alert(`تم شحن ${amount.toLocaleString()} عملة للمستخدم (${u.name || u.id}) بنجاح! الرصيد الجديد: ${newCoins.toLocaleString()}`);
    setShowRechargeModal(false);
    setRechargeUserUid('');
    setRechargeCoinsAmount('');
    load();
  };

  const handleConfirmCoinsReceipt = async (wId: string) => {
    await supabase.from('agency_withdrawal_requests').update({
      status: 'coins_received',
      coins_received_at: new Date().toISOString(),
    }).eq('id', wId);
    load();
  };

  const handleCompleteTransferWithProof = async () => {
    if (!selectedWithdrawal || !proofUrl.trim()) {
      alert('يرجى رفع إثبات / سكرين التحويل أولاً لحماية حقوق المضيف');
      return;
    }
    await supabase.from('agency_withdrawal_requests').update({
      status: 'completed',
      transfer_screenshot_url: proofUrl.trim(),
      completed_at: new Date().toISOString(),
    }).eq('id', selectedWithdrawal.id);

    setSelectedWithdrawal(null);
    setProofUrl('');
    load();
  };

  return (
    <div className="space-y-6">
      {/* Header with actions */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h3 className="text-white text-sm font-bold">⚡ إدارة وكالات الشحن وتحويلات الرواتب</h3>
          <p className="text-slate-400 text-xs mt-0.5">فتح وكالات الشحن، التحكم بنسب العمولة والرصيد، واستقبال طلبات سحب الرواتب مع إثبات التحويل</p>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={() => setShowRechargeModal(true)}
            className="text-xs bg-amber-600 hover:bg-amber-700 text-white font-bold px-3.5 py-2 rounded-xl transition-all shadow-lg shadow-amber-600/20">
            🪙 شحن رصيد مستخدم بالـ ID
          </button>
          <button onClick={() => setShowAddModal(true)}
            className="text-xs bg-indigo-600 hover:bg-indigo-700 text-white font-bold px-3.5 py-2 rounded-xl transition-all shadow-lg shadow-indigo-600/20">
            ➕ فتح وكالة شحن جديدة
          </button>
        </div>
      </div>

      {/* Recharge Agents Grid */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {agents.map(ag => (
          <div key={ag.id} className="bg-[#18181b] border border-white/5 rounded-2xl p-4 space-y-3 relative overflow-hidden shadow-lg">
            <div className="flex items-center gap-3">
              <img src={ag.recharge_agency_logo || ag.photo_url || ag.avatar || `https://ui-avatars.com/api/?name=${encodeURIComponent(ag.recharge_agency_name || ag.name || 'Agent')}&background=random`} alt="" className="w-12 h-12 rounded-xl object-cover border border-amber-500/30 shrink-0" />
              <div className="min-w-0 flex-1">
                <div className="text-white text-xs font-bold truncate">{ag.recharge_agency_name || ag.name}</div>
                <div className="text-[11px] text-slate-400 font-mono">ID: {ag.custom_id || ag.id?.slice(0, 8)}</div>
                {ag.whatsapp_number && <div className="text-[10px] text-emerald-400">📱 واتساب: {ag.whatsapp_number}</div>}
              </div>
            </div>

            <div className="flex items-center justify-between pt-2 border-t border-white/5 text-xs">
              <span className="text-slate-400">نسبة العمولة:</span>
              <span className="text-amber-300 font-bold">{ag.recharge_commission_rate ?? 5}%</span>
            </div>

            <div className="flex items-center justify-between text-xs">
              <span className="text-slate-400">رصيد الوكالة:</span>
              <span className="text-sm text-amber-400 font-bold">{Number(ag.coins || 0).toLocaleString()} 🪙</span>
            </div>

            <div className="flex items-center gap-2 pt-2 border-t border-white/5">
              <button onClick={() => openEditModal(ag)}
                className="flex-1 py-1 text-center bg-indigo-600/10 hover:bg-indigo-600/20 text-indigo-300 border border-indigo-500/20 rounded-lg text-[10px] font-bold transition-all">
                ✏️ تعديل البيانات
              </button>
              <button onClick={() => handleRevokeAgent(ag)}
                className="py-1 px-2.5 text-center bg-rose-500/10 hover:bg-rose-500/20 text-rose-400 border border-rose-500/20 rounded-lg text-[10px] font-bold transition-all">
                ⛔ سحب الوكالة
              </button>
            </div>
          </div>
        ))}
      </div>

      {/* Withdrawal & Transfer Requests Table */}
      <div className="space-y-3">
        <h4 className="text-white text-xs font-bold">📋 طلبات سحب الرواتب وتحويل العملات</h4>
        <DataTable
          loading={loading}
          columns={[
            { key: 'id', label: 'المعرف', render: r => <span className="font-mono text-[10px] text-slate-400">{(r as any).id?.slice(0, 8)}</span> },
            { key: 'user_id', label: 'المضيف', render: r => <span className="text-xs text-white font-bold">{(r as any).user_name || (r as any).user_id}</span> },
            { key: 'amount', label: 'المبلغ / العملات', render: r => <span className="text-xs text-amber-400 font-bold">{(r as any).amount?.toLocaleString()} 🪙 / {(r as any).usd_amount ?? (r as any).amount / 100}$</span> },
            { key: 'payment_method', label: 'طريقة الاستلام', render: r => <span className="text-xs text-slate-300">{(r as any).payment_method || 'تحويل مباشر'}</span> },
            { key: 'status', label: 'الحالة', render: r => {
              const st = (r as any).status;
              return <span className={`px-2 py-0.5 rounded text-[10px] font-bold ${st === 'completed' ? 'bg-emerald-500/20 text-emerald-400' : st === 'coins_received' ? 'bg-cyan-500/20 text-cyan-400' : 'bg-amber-500/20 text-amber-400'}`}>
                {st === 'completed' ? '✅ تم التحويل' : st === 'coins_received' ? '📥 استلمت العملات' : '⏳ معلق'}
              </span>;
            }},
            { key: 'actions', label: 'الإجراءات', render: r => {
              const req = r as any;
              return (
                <div className="flex items-center gap-1.5">
                  {req.status === 'pending' && (
                    <button onClick={() => handleConfirmCoinsReceipt(req.id)}
                      className="text-[10px] bg-cyan-600 hover:bg-cyan-700 text-white font-bold px-2 py-1 rounded transition-all">
                      📥 تأكيد استلام العملات
                    </button>
                  )}
                  {req.status !== 'completed' && (
                    <button onClick={() => { setSelectedWithdrawal(req); setProofUrl(req.transfer_screenshot_url || ''); }}
                      className="text-[10px] bg-emerald-600 hover:bg-emerald-700 text-white font-bold px-2 py-1 rounded transition-all">
                      💵 إتمام تحويل الراتب مع السكرين
                    </button>
                  )}
                  {req.transfer_screenshot_url && (
                    <a href={req.transfer_screenshot_url} target="_blank" rel="noreferrer"
                      className="text-[10px] text-indigo-400 underline font-semibold flex items-center gap-1">
                      <Eye className="w-3 h-3" /> إثبات التحويل
                    </a>
                  )}
                </div>
              );
            }},
          ]}
          data={withdrawals}
          searchKeys={['user_id', 'status', 'payment_method']}
        />
      </div>

      {/* Add Recharge Agency Modal */}
      {showAddModal && (
        <div className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-[#18181b] border border-white/10 rounded-2xl max-w-md w-full p-5 space-y-4 shadow-2xl">
            <h4 className="text-white font-bold text-sm">✨ تعيين وكيل شحن معتمد جديد</h4>
            <div className="space-y-3">
              <div>
                <label className="text-[11px] text-slate-400 block mb-1">UID المستخدم أو رقم المعرف (Custom ID) *</label>
                <input value={targetUid} onChange={e => setTargetUid(e.target.value)} placeholder="اكتب UID أو ID المستخدم"
                  className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white" />
                <UserSearchPreview query={targetUid} />
              </div>
              <div>
                <label className="text-[11px] text-slate-400 block mb-1">اسم وكالة الشحن</label>
                <input value={agencyName} onChange={e => setAgencyName(e.target.value)} placeholder="مثال: وكالة الأهرام للشحن"
                  className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white" />
              </div>
              <div>
                <label className="text-[11px] text-slate-400 block mb-1">رقم الواتساب للتواصل</label>
                <input value={whatsappPhone} onChange={e => setWhatsappPhone(e.target.value)} placeholder="+2010..."
                  className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white" />
              </div>
              <div>
                <label className="text-[11px] text-amber-400 block mb-1">نسبة عمولة وكيل الشحن (%)</label>
                <input type="number" value={rechargeCommissionRate} onChange={e => setRechargeCommissionRate(e.target.value)} placeholder="5"
                  className="w-full bg-[#121214] border border-amber-500/30 rounded-xl p-2 text-xs text-amber-300 font-bold" />
              </div>
              <div>
                <label className="text-[11px] text-slate-400 block mb-1">شعار / صورة الوكالة</label>
                <ImageUpload
                  currentUrl={agencyLogo}
                  onUpload={file => uploadStoreItem(file, 'agency_logos')}
                  onUrlChange={url => setAgencyLogo(url)}
                  label="رفع شعار الوكالة"
                  accept="image/*"
                />
              </div>
              <div>
                <label className="text-[11px] text-amber-400 block mb-1">الرصيد الافتتاحي للوكالة (عملات)</label>
                <input type="number" value={initialCoins} onChange={e => setInitialCoins(e.target.value)} placeholder="100000"
                  className="w-full bg-[#121214] border border-amber-500/30 rounded-xl p-2 text-xs text-amber-300 font-bold" />
              </div>
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <button onClick={() => setShowAddModal(false)} className="px-4 py-2 text-xs text-slate-400">إلغاء</button>
              <button onClick={handleCreateRechargeAgent} className="px-5 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl text-xs font-bold">تأكيد التعيين</button>
            </div>
          </div>
        </div>
      )}

      {/* Edit Recharge Agency Modal */}
      {editAgent && (
        <div className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-[#18181b] border border-indigo-500/30 rounded-2xl max-w-md w-full p-5 space-y-4 shadow-2xl">
            <h4 className="text-white font-bold text-sm">✏️ تعديل بيانات وكالة الشحن</h4>
            <div className="space-y-3">
              <div>
                <label className="text-[11px] text-slate-400 block mb-1">اسم وكالة الشحن</label>
                <input value={editName} onChange={e => setEditName(e.target.value)}
                  className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white" />
              </div>
              <div>
                <label className="text-[11px] text-slate-400 block mb-1">رقم الواتساب للتواصل</label>
                <input value={editWhatsapp} onChange={e => setEditWhatsapp(e.target.value)}
                  className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white" />
              </div>
              <div>
                <label className="text-[11px] text-amber-400 block mb-1">نسبة العمولة (%)</label>
                <input type="number" value={editCommissionRate} onChange={e => setEditCommissionRate(e.target.value)}
                  className="w-full bg-[#121214] border border-amber-500/30 rounded-xl p-2 text-xs text-amber-300 font-bold" />
              </div>
              <div>
                <label className="text-[11px] text-amber-400 block mb-1">رصيد العملات 🪙</label>
                <input type="number" value={editCoins} onChange={e => setEditCoins(e.target.value)}
                  className="w-full bg-[#121214] border border-amber-500/30 rounded-xl p-2 text-xs text-amber-300 font-bold" />
              </div>
              <div>
                <label className="text-[11px] text-slate-400 block mb-1">شعار / صورة الوكالة</label>
                <ImageUpload
                  currentUrl={editLogo}
                  onUpload={file => uploadStoreItem(file, 'agency_logos')}
                  onUrlChange={url => setEditLogo(url)}
                  label="تغيير شعار الوكالة"
                  accept="image/*"
                />
              </div>
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <button onClick={() => setEditAgent(null)} className="px-4 py-2 text-xs text-slate-400">إلغاء</button>
              <button onClick={handleSaveEditAgent} className="px-5 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl text-xs font-bold">حفظ التغييرات</button>
            </div>
          </div>
        </div>
      )}

      {/* Recharge User Modal */}
      {showRechargeModal && (
        <div className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-[#18181b] border border-white/10 rounded-2xl max-w-md w-full p-5 space-y-4 shadow-2xl">
            <h4 className="text-white font-bold text-sm">🪙 شحن رصيد عملات لمستخدم بالـ ID</h4>
            <div className="space-y-3">
              <div>
                <label className="text-[11px] text-slate-400 block mb-1">UID المستخدم أو رقم المعرف (ID) *</label>
                <input value={rechargeUserUid} onChange={e => setRechargeUserUid(e.target.value)} placeholder="مثال: 123456 أو UID"
                  className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white" />
                <UserSearchPreview query={rechargeUserUid} />
              </div>
              <div>
                <label className="text-[11px] text-amber-400 block mb-1">عدد العملات للشحن 🪙 *</label>
                <input type="number" value={rechargeCoinsAmount} onChange={e => setRechargeCoinsAmount(e.target.value)} placeholder="1000"
                  className="w-full bg-[#121214] border border-amber-500/30 rounded-xl p-2 text-xs text-amber-300 font-bold" />
              </div>
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <button onClick={() => setShowRechargeModal(false)} className="px-4 py-2 text-xs text-slate-400">إلغاء</button>
              <button onClick={handleRechargeUser} className="px-5 py-2 bg-amber-600 hover:bg-amber-700 text-white rounded-xl text-xs font-bold">تأكيد الشحن فوراً</button>
            </div>
          </div>
        </div>
      )}

      {/* Proof Screenshot Upload Modal */}
      {selectedWithdrawal && (
        <div className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-[#18181b] border border-emerald-500/30 rounded-2xl max-w-md w-full p-5 space-y-4 shadow-2xl">
            <h4 className="text-white font-bold text-sm">🛡️ إتمام تحويل الراتب وإرفاق إثبات التحويل</h4>
            <p className="text-[11px] text-slate-300 leading-relaxed">
              لحماية حقوق المستخدم والمضيف، يرجى إرفاق رابط أو صورة سكرين شوت تثبت تحويل الراتب بنجاح:
            </p>
            <div>
              <label className="text-[11px] text-emerald-400 block mb-1">رفع صورة إثبات التحويل (Screenshot) *</label>
              <ImageUpload
                currentUrl={proofUrl}
                onUpload={async (file) => {
                  const url = await uploadStoreItem(file, 'proofs');
                  setProofUrl(url);
                  return url;
                }}
                onClear={() => setProofUrl('')}
              />
            </div>
            {proofUrl && (
              <div className="flex justify-center p-2 bg-black/40 rounded-lg">
                <img src={proofUrl} alt="Proof" className="max-h-40 rounded object-contain" />
              </div>
            )}
            <div className="flex justify-end gap-2 pt-2">
              <button onClick={() => setSelectedWithdrawal(null)} className="px-4 py-2 text-xs text-slate-400">إلغاء</button>
              <button onClick={handleCompleteTransferWithProof} className="px-5 py-2 bg-emerald-600 hover:bg-emerald-700 text-white rounded-xl text-xs font-bold">تأكيد اكتمال التحويل</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

/* =============================================================
   7. COMMISSION TAB
   ============================================================= */
function CommissionTab() {
  const { t } = useContext(I18nContext);
  const [settings, setSettings] = useState<CommissionSettingModel[]>([]);
  const [loading, setLoading] = useState(true);

  const load = () => { setLoading(true); getCommissionSettings().then(d => { setSettings(d); setLoading(false); }); };
  useEffect(() => { load(); }, []);

  const handleUpdate = async (id: string, value: number) => {
    await updateCommissionSetting(id, value);
    load();
  };

  const descKeyMap: Record<string, string> = {
    host_rate: 'agency.commission.hostRate',
    agency_rate: 'agency.commission.agencyRate',
    platform_rate: 'agency.commission.platformRate',
    gold_to_diamond: 'agency.commission.goldToDiamond',
    diamonds_per_usd: 'agency.commission.diamondsPerUsd',
  };

  return (
    <div>
      <p className="text-slate-500 text-xs mb-3">{t('agency.commission')}</p>
      <div className="bg-[#141417] rounded-2xl border border-white/5 overflow-hidden">
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b border-white/5">
              <th className="text-left text-[10px] uppercase tracking-wider text-slate-500 font-bold p-3">{t('agency.col.key')}</th>
              <th className="text-left text-[10px] uppercase tracking-wider text-slate-500 font-bold p-3">{t('agency.col.desc')}</th>
              <th className="text-left text-[10px] uppercase tracking-wider text-slate-500 font-bold p-3">{t('agency.col.value')}</th>
              <th className="text-left text-[10px] uppercase tracking-wider text-slate-500 font-bold p-3">{t('agency.col.actions')}</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={4} className="text-center py-12 text-slate-500">{t('agency.loading')}</td></tr>
            ) : settings.map(s => (
              <tr key={s.id} className="border-b border-white/5 hover:bg-white/5">
                <td className="p-3 text-white font-mono">{s.key}</td>
                <td className="p-3 text-slate-400">{t(descKeyMap[s.key] as any) || s.description}</td>
                <td className="p-3"><span className="text-amber-400 font-semibold">{s.value}</span></td>
                <td className="p-3">
                  <InlineEdit value={s.value} onSave={v => handleUpdate(s.id, v)} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function InlineEdit({ value, onSave }: { value: number; onSave: (v: number) => void }) {
  const { t } = useContext(I18nContext);
  const [editing, setEditing] = useState(false);
  const [val, setVal] = useState(value != null ? String(value) : '0');
  if (!editing) return (
    <button onClick={() => { setVal(value != null ? String(value) : '0'); setEditing(true); }}
      className="text-[10px] text-indigo-400 hover:text-indigo-300 font-semibold">{t('edit')}</button>
  );
  return (
    <div className="flex items-center gap-1">
      <input type="number" step="0.01" value={val} onChange={e => setVal(e.target.value)}
        className="w-20 bg-[#161618] border border-white/10 rounded py-1 px-2 text-xs text-white" autoFocus
        onKeyDown={e => { if (e.key === 'Enter') { onSave(parseFloat(val) || 0); setEditing(false); } if (e.key === 'Escape') setEditing(false); }} />
      <button onClick={() => { onSave(parseFloat(val) || 0); setEditing(false); }}
        className="text-[10px] text-emerald-400 font-semibold">{t('save')}</button>
      <button onClick={() => setEditing(false)}
        className="text-[10px] text-slate-500 font-semibold">X</button>
    </div>
  );
}

/* =============================================================
   7. AGENCY SVGA NECKLACES TAB (قلادات وشارات الوكالة SVGA)
   ============================================================= */
function AgencyNecklacesTab() {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [msg, setMsg] = useState('');
  const [config, setConfig] = useState({
    leaderNecklaceName: 'قلادة الوكيل (Agency Owner)',
    leaderNecklaceImg: '',
    leaderNecklaceSvga: '',
    hostNecklaceName: 'قلادة المضيف (Agency Host)',
    hostNecklaceImg: '',
    hostNecklaceSvga: '',
  });

  const showMsg = (txt: string) => {
    setMsg(txt);
    setTimeout(() => setMsg(''), 4000);
  };

  useEffect(() => {
    getAppConfig().then((appCfg: any) => {
      const data = appCfg?.screenVisuals?.agency || appCfg?.agencyVisuals || {};
      setConfig({
        leaderNecklaceName: data.leaderNecklaceName || 'قلادة الوكيل (Agency Owner)',
        leaderNecklaceImg: data.leaderNecklaceImg || '',
        leaderNecklaceSvga: data.leaderNecklaceSvga || '',
        hostNecklaceName: data.hostNecklaceName || 'قلادة المضيف (Agency Host)',
        hostNecklaceImg: data.hostNecklaceImg || '',
        hostNecklaceSvga: data.hostNecklaceSvga || '',
      });
      setLoading(false);
    });
  }, []);

  const handleSave = async () => {
    setSaving(true);
    try {
      const appCfg: any = await getAppConfig();
      const currentVisuals = appCfg?.screenVisuals || {};
      const updatedVisuals = {
        ...currentVisuals,
        agency: {
          ...(currentVisuals.agency || {}),
          ...config,
        },
      };
      await updateAppConfig({
        screenVisuals: updatedVisuals,
        agencyVisuals: config,
      } as any);
      showMsg('تم حفظ وتطبيق إعدادات قلادات الوكالة بنجاح!');
    } catch (err) {
      showMsg('فشل الحفظ: ' + (err as Error).message);
    }
    setSaving(false);
  };

  const handleSyncToUsers = async () => {
    if (!confirm('هل تريد مزامنة ومنح قلادات الوكالة (الوكيل والمضيف) لجميع أصحاب الوكالات والأعضاء الحاليين فوراً؟')) return;
    setSyncing(true);
    try {
      // 1. Get all agencies & their owners
      const agencies = await getHostAgencies();
      let syncedOwners = 0;
      let syncedHosts = 0;

      for (const agency of agencies) {
        if (agency.owner_id) {
          // Grant agency leader necklace to owner
          const { data: user } = await supabase.from('users').select('owned_necklaces').eq('id', agency.owner_id).single();
          const owned = Array.isArray(user?.owned_necklaces) ? user.owned_necklaces : [];
          if (!owned.includes('agency_leader_necklace')) {
            await supabase.from('users').update({
              owned_necklaces: [...owned, 'agency_leader_necklace']
            }).eq('id', agency.owner_id);
            syncedOwners++;
          }
        }
      }

      // 2. Get all agency members
      const members = await getHostAgencyMembers();
      for (const m of members) {
        if (m.user_id) {
          const { data: user } = await supabase.from('users').select('owned_necklaces').eq('id', m.user_id).single();
          const owned = Array.isArray(user?.owned_necklaces) ? user.owned_necklaces : [];
          if (!owned.includes('agency_host_necklace')) {
            await supabase.from('users').update({
              owned_necklaces: [...owned, 'agency_host_necklace']
            }).eq('id', m.user_id);
            syncedHosts++;
          }
        }
      }

      showMsg(`تمت المزامنة بنجاح! تم تعيين القلادات لـ ${syncedOwners} رئيس وكالة و ${syncedHosts} مضيف وكالة.`);
    } catch (err) {
      showMsg('فشل المزامنة: ' + (err as Error).message);
    }
    setSyncing(false);
  };

  if (loading) {
    return <div className="text-center py-12 text-slate-500">جاري التحميل...</div>;
  }

  return (
    <div className="space-y-6">
      {msg && (
        <div className="bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs px-4 py-3 rounded-xl flex items-center gap-2">
          <CheckCircle2 className="w-4 h-4 shrink-0" />
          <span>{msg}</span>
        </div>
      )}

      {/* Overview Info Card */}
      <div className="bg-gradient-to-r from-amber-500/10 via-purple-500/10 to-indigo-500/10 border border-amber-500/20 rounded-2xl p-4">
        <h3 className="text-white font-bold text-sm flex items-center gap-2">
          <Sparkles className="w-4 h-4 text-amber-400" />
          نظام قلادات وشارات الوكالات الحصرية (SVGA)
        </h3>
        <p className="text-slate-400 text-xs mt-1 leading-relaxed">
          هنا يمكنك تعيين وتصميم قلادة الوكيل الحصرية (لأصحاب الوكالات) وقلادة المضيف الحصرية (للأعضاء المنضمين للوكالات). يتم عرض هذه القلادات كرسوم متحركة SVGA فائقة الجودة في وسم الهوية والبروفايل.
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* 1. Agency Leader / Owner Necklace */}
        <div className="bg-[#141417] rounded-2xl border border-amber-500/20 p-5 space-y-4">
          <div className="flex items-center justify-between border-b border-white/5 pb-3">
            <h4 className="text-white font-bold text-sm flex items-center gap-2">
              <span>👑</span> قلادة رئيس الوكالة / الوكيل (Agency Leader)
            </h4>
            <span className="text-[10px] bg-amber-500/20 text-amber-300 font-bold px-2 py-0.5 rounded-full">
              للوكلاء فقط
            </span>
          </div>

          <div className="space-y-1.5">
            <label className="block text-[10px] uppercase text-slate-400 font-bold">اسم القلادة</label>
            <input
              type="text"
              value={config.leaderNecklaceName || ''}
              onChange={e => setConfig(p => ({ ...p, leaderNecklaceName: e.target.value }))}
              className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
            />
          </div>

          <div className="grid grid-cols-1 gap-3">
            <ImageUpload
              currentUrl={config.leaderNecklaceSvga}
              onUpload={file => uploadStoreItem(file, 'agency_leader_svga')}
              onUrlChange={url => setConfig(p => ({ ...p, leaderNecklaceSvga: url }))}
              label="ملف قلادة الوكيل (SVGA متحرك)"
              accept=".svga,.webp,.png,.mp4,.vap"
            />
            <ImageUpload
              currentUrl={config.leaderNecklaceImg}
              onUpload={file => uploadStoreItem(file, 'agency_leader_img')}
              onUrlChange={url => setConfig(p => ({ ...p, leaderNecklaceImg: url }))}
              label="صورة المعاينة الثابتة (PNG / WebP)"
              accept="image/*"
            />
          </div>
        </div>

        {/* 2. Agency Host Member Necklace */}
        <div className="bg-[#141417] rounded-2xl border border-indigo-500/20 p-5 space-y-4">
          <div className="flex items-center justify-between border-b border-white/5 pb-3">
            <h4 className="text-white font-bold text-sm flex items-center gap-2">
              <span>🎙️</span> قلادة مضيف الوكالة (Agency Host Member)
            </h4>
            <span className="text-[10px] bg-indigo-500/20 text-indigo-300 font-bold px-2 py-0.5 rounded-full">
              للمضيفين فقط
            </span>
          </div>

          <div className="space-y-1.5">
            <label className="block text-[10px] uppercase text-slate-400 font-bold">اسم القلادة</label>
            <input
              type="text"
              value={config.hostNecklaceName || ''}
              onChange={e => setConfig(p => ({ ...p, hostNecklaceName: e.target.value }))}
              className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
            />
          </div>

          <div className="grid grid-cols-1 gap-3">
            <ImageUpload
              currentUrl={config.hostNecklaceSvga}
              onUpload={file => uploadStoreItem(file, 'agency_host_svga')}
              onUrlChange={url => setConfig(p => ({ ...p, hostNecklaceSvga: url }))}
              label="ملف قلادة المضيف (SVGA متحرك)"
              accept=".svga,.webp,.png,.mp4,.vap"
            />
            <ImageUpload
              currentUrl={config.hostNecklaceImg}
              onUpload={file => uploadStoreItem(file, 'agency_host_img')}
              onUrlChange={url => setConfig(p => ({ ...p, hostNecklaceImg: url }))}
              label="صورة المعاينة الثابتة (PNG / WebP)"
              accept="image/*"
            />
          </div>
        </div>
      </div>

      {/* Action Buttons */}
      <div className="flex flex-wrap items-center gap-3 pt-2">
        <button
          onClick={handleSave}
          disabled={saving}
          className="px-5 py-2.5 bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 text-xs text-white font-bold rounded-xl flex items-center gap-2 transition-all shadow-lg shadow-emerald-900/30"
        >
          <Save className="w-4 h-4" />
          {saving ? 'جارٍ الحفظ...' : '💾 حفظ وتطبيق قلادات الوكالة'}
        </button>

        <button
          onClick={handleSyncToUsers}
          disabled={syncing}
          className="px-5 py-2.5 bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-xs text-white font-bold rounded-xl flex items-center gap-2 transition-all shadow-lg shadow-indigo-900/30"
        >
          <RefreshCw className={`w-4 h-4 ${syncing ? 'animate-spin' : ''}`} />
          {syncing ? 'جارٍ المزامنة...' : '⚡ مزامنة القلادات لجميع أصحاب الوكالات والمضيفين الآن'}
        </button>
      </div>
    </div>
  );
}
