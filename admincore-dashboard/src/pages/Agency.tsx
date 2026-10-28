import { useContext, useEffect, useState } from 'react';
import {
  HostAgencyModel, HostAgencyMemberModel, CommissionSettingModel,
  HostMilestoneModel, AgencyJoinRequestModel, AgencyLedgerEntryModel,
  AgencyWithdrawalRequestModel, AgencyApplicationModel, HostRechargeRecord,
  AgencyLevelModel, AgencyExpTaskConfig, AgencyLevelRewardItem,
} from '../types';
import {
  getHostAgencies, createHostAgency, updateHostAgency, deleteHostAgency,
  getCommissionSettings, updateCommissionSetting,
  getHostAgencyMembers, getHostMilestones, updateHostMilestone,
  createHostMilestone, deleteHostMilestone,
  getHostAgencyJoinRequests, approveJoinRequest, rejectJoinRequest,
  updateAgencyMemberRole, removeAgencyMember, addAgencyMember,
  transferAgencyMember, removeAgencyMemberWithNotification,
  getHostRechargeHistory, refundAgentRechargeTransaction,
  getAgencyApplications, approveAgencyApplication, rejectAgencyApplication, createAgencyApplication,
  updateRechargeAgency, revokeRechargeAgency,
  getRechargeAgencyExchangeTiers, createRechargeAgencyExchangeTier,
  updateRechargeAgencyExchangeTier, deleteRechargeAgencyExchangeTier,
  getRechargeAgentsWithWallets, type RechargeAgencyExchangeTier,
  getAgencyLedger, getWithdrawalRequests, approveWithdrawal, rejectWithdrawal,
  getAppConfig, updateAppConfig,
  searchUserProfile, sendSystemNotification, sendAgencyInvitation,
  getAgencyLevels, saveAgencyLevels, distributeAgencyLevelReward,
  getAgencyExpTasks, saveAgencyExpTasks,
} from '../lib/db';
import { uploadStoreItem } from '../lib/storage';
import { supabase } from '../lib/supabase';
import { getCurrentAdminName, onAuthChange, type AppUser } from '../lib/auth';
import { I18nContext } from '../lib/i18n';
import { useOutletContext } from 'react-router-dom';
import { canUserAccess } from '../lib/permissions';
import DataTable from '../components/DataTable';
import ImageUpload from '../components/ImageUpload';
import {
  Handshake, Users, UserPlus, Wallet, Target, Settings, Sparkles, Award,
  Save, CheckCircle2, RefreshCw, ClipboardCheck, Plus, Trash2, Edit3,
  XCircle, Check, ShieldCheck, UserMinus, Eye, ExternalLink,
  ArrowRightLeft, RotateCcw, Coins, FileText, AlertTriangle,
  Mic, Dices, CreditCard, Gift, Clock, Package, Search, Zap,
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
  { key: 'agencies', permKey: 'agency', label: 'الوكالات', labelKey: 'agency.agencies', icon: Handshake },
  { key: 'agency_levels', permKey: 'agency', label: 'مستويات ونقاط خبرة الوكالة والمكافآت', labelKey: 'agency.levels', icon: Award },
  { key: 'recharge_agencies', permKey: 'agency_recharge', label: 'وكالات الشحن والرواتب', labelKey: 'agency.rechargeAgencies', icon: Wallet },
  { key: 'agency_requests', permKey: 'agency_requests', label: 'طلبات فتح الوكالات', labelKey: 'agency.agencyRequests', icon: ClipboardCheck },
  { key: 'milestones', permKey: 'agency_milestones', label: 'المراحل والتارجت والرواتب', labelKey: 'agency.milestones', icon: Target },
  { key: 'members', permKey: 'agency_members', label: 'أعضاء الوكالات', labelKey: 'agency.members', icon: Users },
  { key: 'necklaces', permKey: 'agency_necklaces', label: 'قلادات الوكالة SVGA', labelKey: 'agency.necklaces', icon: Sparkles },
  { key: 'join_requests', permKey: 'agency_join_requests', label: 'طلبات الانضمام', labelKey: 'agency.joinRequests', icon: UserPlus },
  { key: 'financial', permKey: 'agency_financial', label: 'السجلات المالية', labelKey: 'agency.financial', icon: Wallet },
  { key: 'commission', permKey: 'agency_commission', label: 'نسب العمولات العامة', labelKey: 'agency.commission', icon: Settings },
] as const;
type Tab = typeof tabs[number]['key'];

export default function AgencyPage() {
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

  const visibleTabs = tabs.filter(tabItem => canUserAccess(currentUser, tabItem.permKey));
  const [tab, setTab] = useState<Tab>(() => visibleTabs[0]?.key || 'agencies');
  const [filterAgencyId, setFilterAgencyId] = useState<string>('');
  const { t } = useContext(I18nContext);

  useEffect(() => {
    if (visibleTabs.length > 0 && !visibleTabs.some(t => t.key === tab)) {
      setTab(visibleTabs[0].key);
    }
  }, [visibleTabs, tab]);

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

      {visibleTabs.length === 0 ? (
        <div className="p-8 text-center text-slate-400 bg-[#141417] border border-white/5 rounded-2xl">
          ليس لديك صلاحية للوصول إلى أي من أقسام الوكالات الفرعية. يرجى مراجعة إدارة اللوحة.
        </div>
      ) : (
        <>
          <div className="flex gap-2 flex-wrap">
            {visibleTabs.map(tabItem => (
              <button key={tabItem.key} onClick={() => setTab(tabItem.key)}
                className={`flex items-center gap-1.5 px-4 py-2 text-xs rounded-lg font-semibold transition-colors ${tab === tabItem.key ? 'bg-indigo-500/20 text-indigo-300' : 'text-slate-400 hover:text-white'}`}>
                <tabItem.icon className="w-3.5 h-3.5" />
                {tabItem.label || t(tabItem.labelKey)}
              </button>
            ))}
          </div>
          {tab === 'agencies' && canUserAccess(currentUser, 'agency') && <AgenciesTab onViewMembers={handleViewAgencyMembers} />}
          {tab === 'agency_levels' && canUserAccess(currentUser, 'agency') && <AgencyLevelsTab />}
          {tab === 'recharge_agencies' && canUserAccess(currentUser, 'agency_recharge') && <RechargeAgenciesTab />}
          {tab === 'agency_requests' && canUserAccess(currentUser, 'agency_requests') && <AgencyRequestsTab />}
          {tab === 'milestones' && canUserAccess(currentUser, 'agency_milestones') && <MilestonesTab />}
          {tab === 'members' && canUserAccess(currentUser, 'agency_members') && <MembersTab initialAgencyId={filterAgencyId} />}
          {tab === 'necklaces' && canUserAccess(currentUser, 'agency_necklaces') && <AgencyNecklacesTab />}
          {tab === 'join_requests' && canUserAccess(currentUser, 'agency_join_requests') && <JoinRequestsTab />}
          {tab === 'financial' && canUserAccess(currentUser, 'agency_financial') && <FinancialTab />}
          {tab === 'commission' && canUserAccess(currentUser, 'agency_commission') && <CommissionTab />}
        </>
      )}
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
  const [selectedAgencyForLedger, setSelectedAgencyForLedger] = useState<HostAgencyModel | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [ownerId, setOwnerId] = useState('');
  const [generalAgencyRate, setGeneralAgencyRate] = useState<number>(20);
  const [specialty, setSpecialty] = useState('mixed');
  const [description, setDescription] = useState('');
  const [country, setCountry] = useState('');
  const [tier, setTier] = useState('bronze');
  const [photoUrl, setPhotoUrl] = useState('');
  const [isActive, setIsActive] = useState(true);
  const [sendInviteMode, setSendInviteMode] = useState(false);
  const [resolvedOwnerUser, setResolvedOwnerUser] = useState<any>(null);

  const load = () => {
    setLoading(true);
    getHostAgencies().then(d => { setAgencies(d); setLoading(false); });
    getCommissionSettings().then(cs => {
      const ar = cs.find(c => c.key === 'agency_rate')?.value;
      if (ar != null && !isNaN(Number(ar))) {
        setGeneralAgencyRate(Number(ar));
      }
    }).catch(() => {});
  };
  useEffect(() => { load(); }, []);

  const resetForm = () => {
    setEditId(null); setName(''); setOwnerId('');
    setSpecialty('mixed'); setTier('bronze'); setDescription(''); setCountry(''); setPhotoUrl('');
    setIsActive(true); setSendInviteMode(false); setResolvedOwnerUser(null);
  };

  const openEdit = (a: HostAgencyModel) => {
    setEditId(a.id); setName(a.name); setOwnerId(a.owner_id);
    setSpecialty(a.specialty ?? 'mixed'); setTier(a.tier ?? 'bronze');
    setDescription(a.description ?? ''); setCountry(a.country ?? '');
    setPhotoUrl(a.photo_url ?? ''); setIsActive(a.is_active ?? true);
    setShowForm(true);
  };

  const handleSubmit = async () => {
    if (!name.trim() || !ownerId.trim()) return;
    const finalOwnerId = resolvedOwnerUser?.id || ownerId.trim();
    const adminName = getCurrentAdminName();

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
      commission_rate: (generalAgencyRate || 20) / 100,
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
              <label className="text-[10px] text-amber-400 block mb-1 font-semibold flex items-center justify-between">
                <span>نسبة العمولة (%)</span>
                <span className="text-[9px] text-emerald-400 font-normal">موحدة مع العمولات العامة</span>
              </label>
              <div className="w-full bg-[#161618] border border-amber-500/30 rounded-lg py-1.5 px-3 text-xs text-amber-300 font-bold flex items-center justify-between">
                <span>{generalAgencyRate}%</span>
                <span className="text-[9px] text-slate-400 font-normal">(تُدار من تبويب العمولات العامة)</span>
              </div>
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
                  <div className="flex items-center gap-1.5 mt-0.5">
                    <span className="text-[10px] text-amber-400 font-mono font-bold bg-amber-500/10 border border-amber-500/25 px-1.5 py-0.5 rounded">كود: {ag.agency_code || (ag.id ? (100 + (Math.abs(ag.id.split('').reduce((acc, c) => ((acc << 5) - acc) + c.charCodeAt(0), 0)) % 900)) : '---')}</span>
                    <span className="text-[10px] text-slate-500 font-mono">ID: {ag.id?.slice(0, 8)}</span>
                  </div>
                </div>
              </div>
            );
          }},
          { key: 'owner_name', label: t('agency.col.owner'), sortable: true, render: a => {
            const ag = a as HostAgencyModel;
            return (
              <div className="flex items-center gap-2">
                {ag.owner_avatar && <img src={ag.owner_avatar} alt="" className="w-7 h-7 rounded-full object-cover border border-amber-400/30 shrink-0" />}
                <div>
                  <div className="text-slate-200 text-xs font-semibold">{ag.owner_name || ag.owner_id?.slice(0, 8)}</div>
                  <div className="text-[10px] text-emerald-400 font-mono font-bold">ID: #{ag.owner_custom_id || ag.owner_id?.slice(0, 8)}</div>
                </div>
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
          { key: 'commission_rate', label: t('agency.col.commission'), sortable: true, render: () => (
            <div className="flex items-center gap-1.5">
              <span className="text-amber-400 font-bold">{generalAgencyRate}%</span>
              <span className="text-[9px] text-emerald-400 bg-emerald-500/10 px-1.5 py-0.5 rounded border border-emerald-500/20 font-normal">موحدة</span>
            </div>
          ) },
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
          { key: 'record_action', label: 'سجل الوكالة', render: a => {
            const ag = a as HostAgencyModel;
            return (
              <button
                onClick={() => setSelectedAgencyForLedger(ag)}
                className="flex items-center gap-1.5 px-3 py-1.5 bg-gradient-to-r from-amber-500/20 to-indigo-500/20 hover:from-amber-500/30 hover:to-indigo-500/30 border border-amber-500/35 text-amber-200 rounded-xl text-xs font-bold transition-all shadow-sm"
                title="عرض سجل أعضاء الوكالة الكامل وإدارتهم"
              >
                <FileText className="w-3.5 h-3.5 text-amber-400" />
                <span>📋 سجل الوكالة</span>
              </button>
            );
          }},
        ]}
        data={agencies}
        searchKeys={['name', 'owner_name', 'specialty', 'country', 'tier']}
        onEdit={a => openEdit(a as HostAgencyModel)}
        onDelete={async a => {
          const ag = a as HostAgencyModel;
          if (confirm(`هل أنت متأكد من حذف وكالة "${ag.name}" نهائياً؟ سيتم فك ارتباط جميع المضيفين والمالك وإلغاء تفعيل الوكالة فوراً.`)) {
            const ok = await deleteHostAgency(ag.id);
            if (ok) {
              alert(`تم حذف وكالة "${ag.name}" بنجاح وفك ارتباط جميع الأعضاء.`);
            } else {
              alert(`حدث خطأ أثناء محاولة حذف الوكالة.`);
            }
            load();
          }
        }}
      />

      {selectedAgencyForLedger && (
        <AgencyRecordModal
          agency={selectedAgencyForLedger}
          allAgencies={agencies}
          onClose={() => { setSelectedAgencyForLedger(null); load(); }}
        />
      )}
    </div>
  );
}

/* =============================================================
   HELPER: CALCULATE MEMBER STAGE & AGENT COMMISSION
   ============================================================= */
export function getMemberStageAndCommission(
  member: HostAgencyMemberModel | any,
  milestones: HostMilestoneModel[],
  agencyCommissionRate?: number
) {
  const diamonds = Number(member?.diamonds_earned_monthly ?? member?.diamondsEarnedMonthly ?? member?.diamonds ?? 0);
  const activeMilestones = (milestones || [])
    .filter(m => m.is_active !== false)
    .sort((a, b) => (Number(a.target_diamonds ?? (a as any).targetDiamonds ?? 0) - Number(b.target_diamonds ?? (b as any).targetDiamonds ?? 0)));

  // Normalize agency commission rate (e.g. 20 -> 0.20, 0.2 -> 0.20)
  const normAgencyRate = agencyCommissionRate != null
    ? (Number(agencyCommissionRate) > 1.0 ? Number(agencyCommissionRate) / 100.0 : Number(agencyCommissionRate))
    : 0.20;

  if (activeMilestones.length === 0) {
    return {
      stageTitle: 'تحت التارجت',
      targetDiamonds: 0,
      commissionDiamonds: 0,
      rate: normAgencyRate,
      isReached: false,
    };
  }

  let highest: HostMilestoneModel | null = null;
  for (const ms of activeMilestones) {
    const t = Number(ms.target_diamonds ?? (ms as any).targetDiamonds ?? 0);
    if (diamonds >= t && t > 0) {
      highest = ms;
    }
  }

  if (!highest) {
    const first = activeMilestones[0];
    const firstTarget = Number(first.target_diamonds ?? (first as any).targetDiamonds ?? 0);
    const rawRate = first.agent_commission_rate ?? (first as any).agentCommissionRate ?? normAgencyRate;
    const rate = Number(rawRate) > 1.0 ? Number(rawRate) / 100.0 : Number(rawRate || normAgencyRate);
    return {
      stageTitle: `تحت ${first.title || 'المرحلة 1'}`,
      targetDiamonds: firstTarget,
      commissionDiamonds: 0,
      rate,
      isReached: false,
    };
  }

  const rawRate = highest.agent_commission_rate ?? (highest as any).agentCommissionRate ?? normAgencyRate;
  const rate = Number(rawRate) > 1.0 ? Number(rawRate) / 100.0 : Number(rawRate || normAgencyRate);
  const targetDiamonds = Number(highest.target_diamonds ?? (highest as any).targetDiamonds ?? 0);
  const commissionDiamonds = Math.round(targetDiamonds * rate);

  return {
    stageTitle: highest.title || 'مرحلة محققة',
    targetDiamonds,
    commissionDiamonds,
    rate,
    isReached: true,
  };
}

/* =============================================================
   2. MEMBERS TAB
   ============================================================= */
function MembersTab({ initialAgencyId }: { initialAgencyId?: string }) {
  const { t } = useContext(I18nContext);
  const [members, setMembers] = useState<HostAgencyMemberModel[]>([]);
  const [agencies, setAgencies] = useState<HostAgencyModel[]>([]);
  const [milestones, setMilestones] = useState<HostMilestoneModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [filterAgency, setFilterAgency] = useState(initialAgencyId || '');

  // Add Member Modal State
  const [showAddMemberModal, setShowAddMemberModal] = useState(false);
  const [addAgencyId, setAddAgencyId] = useState(initialAgencyId || '');
  const [addUserQuery, setAddUserQuery] = useState('');
  const [addRole, setAddRole] = useState('host');
  const [adding, setAdding] = useState(false);

  // Transfer & Recharge History Modal States
  const [transferTarget, setTransferTarget] = useState<HostAgencyMemberModel | null>(null);
  const [rechargeTarget, setRechargeTarget] = useState<HostAgencyMemberModel | null>(null);

  useEffect(() => {
    if (initialAgencyId) {
      setFilterAgency(initialAgencyId);
      setAddAgencyId(initialAgencyId);
    }
  }, [initialAgencyId]);

  const load = async () => {
    setLoading(true);
    const [m, a, ms] = await Promise.all([
      getHostAgencyMembers(filterAgency || undefined),
      getHostAgencies(),
      getHostMilestones(),
    ]);
    setMembers(m); setAgencies(a); setMilestones(ms); setLoading(false);
  };
  useEffect(() => { load(); }, [filterAgency]);

  const handleRoleChange = async (agencyId: string, userId: string, role: string) => {
    await updateAgencyMemberRole(agencyId, userId, role);
    load();
  };

  const handleRemove = async (agencyId: string, userId: string, userName?: string) => {
    const ag = agencies.find(a => a.id === agencyId);
    if (confirm(`هل أنت متأكد من حذف ${userName || 'هذا المضيف'} نهائياً من الوكالة؟\nسيتم خروجه فوراً وإرسال إشعار حذف رسمي له داخل التطبيق.`)) {
      const res = await removeAgencyMemberWithNotification(agencyId, userId, ag?.name, userName);
      alert(res.message);
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
                  <div className="text-[10px] text-cyan-400 font-mono font-bold">ID: #{mem.custom_id || mem.user_id?.slice(0, 8)}</div>
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
            return <span className="text-amber-400 font-bold font-mono">{v?.toLocaleString() ?? '0'} 💎</span>;
          }},
          { key: 'current_stage', label: 'المرحلة / التارجت', sortable: true, render: m => {
            const stage = getMemberStageAndCommission(m, milestones);
            return stage.isReached ? (
              <div className="flex flex-col">
                <span className="text-emerald-400 font-bold text-xs bg-emerald-500/10 px-2 py-0.5 rounded border border-emerald-500/20 inline-block w-fit">
                  {stage.stageTitle}
                </span>
                <span className="text-[10px] text-slate-400 font-mono mt-0.5">تارجت: {stage.targetDiamonds.toLocaleString()} 💎</span>
              </div>
            ) : (
              <span className="text-slate-500 text-[11px]">{stage.stageTitle}</span>
            );
          }},
          { key: 'agent_commission', label: 'عمولة الوكيل بالماس 💎', sortable: true, render: m => {
            const member = m as HostAgencyMemberModel;
            const agency = agencies.find(a => a.id === member.agency_id);
            const stage = getMemberStageAndCommission(m, milestones, agency?.commission_rate);
            return stage.commissionDiamonds > 0 ? (
              <div className="flex flex-col">
                <span className="text-cyan-400 font-bold font-mono text-xs">💎 {stage.commissionDiamonds.toLocaleString()}</span>
                <span className="text-[10px] text-cyan-500/80">{Math.round(stage.rate * 100)}% من التارجت</span>
              </div>
            ) : (
              <span className="text-slate-600 text-xs">0 💎</span>
            );
          }},
          { key: 'diamonds_balance', label: 'الرصيد القابل للسحب', sortable: true, render: m => {
            const v = (m as HostAgencyMemberModel).diamonds_balance;
            return <span className="text-cyan-400 font-semibold font-mono">{v?.toLocaleString() ?? '0'} 💎</span>;
          }},
          { key: 'joined_at', label: 'تاريخ الانضمام', sortable: true, render: m => new Date((m as HostAgencyMemberModel).joined_at).toLocaleDateString('ar-EG') },
          { key: 'actions', label: 'الإجراءات', render: m => {
            const member = m as HostAgencyMemberModel;
            if (member.role === 'owner') return <span className="text-[10px] text-amber-400 font-semibold">👑 مالك الوكالة</span>;
            return (
              <div className="flex items-center gap-1.5 flex-wrap">
                <button
                  onClick={() => setTransferTarget(member)}
                  className="text-[10px] bg-indigo-500/15 hover:bg-indigo-500/25 border border-indigo-500/30 text-indigo-300 px-2 py-0.5 rounded font-bold transition-all flex items-center gap-1"
                  title="نقل المضيف لوكالة أخرى وتصفير تارجته"
                >
                  <ArrowRightLeft className="w-3 h-3" />
                  <span>نقل</span>
                </button>
                <button
                  onClick={() => setRechargeTarget(member)}
                  className="text-[10px] bg-amber-500/15 hover:bg-amber-500/25 border border-amber-500/30 text-amber-300 px-2 py-0.5 rounded font-bold transition-all flex items-center gap-1"
                  title="سجل الشحن الكامل وإرجاع الشحن"
                >
                  <Coins className="w-3 h-3" />
                  <span>سجل الشحن</span>
                </button>
                <select defaultValue="" onChange={e => { if (e.target.value) handleRoleChange(member.agency_id, member.user_id, e.target.value); }}
                  className="bg-[#161618] border border-white/10 rounded py-0.5 px-1 text-[10px] text-white">
                  <option value="" disabled>الرتبة</option>
                  <option value="supervisor">مشرف</option>
                  <option value="host">مضيف</option>
                </select>
                <button onClick={() => handleRemove(member.agency_id, member.user_id, member.user_name)}
                  className="text-[10px] bg-rose-500/10 hover:bg-rose-500/20 text-rose-400 border border-rose-500/20 px-2 py-0.5 rounded font-semibold transition-all">
                  حذف
                </button>
              </div>
            );
          }},
        ]}
        data={members}
        searchKeys={['user_name', 'role', 'status', 'custom_id']}
      />

      {transferTarget && (
        <TransferHostModal
          member={transferTarget}
          currentAgency={agencies.find(a => a.id === transferTarget.agency_id) || { id: transferTarget.agency_id, name: 'الوكالة الحالية' } as HostAgencyModel}
          allAgencies={agencies}
          onClose={() => setTransferTarget(null)}
          onSuccess={() => { setTransferTarget(null); load(); }}
        />
      )}

      {rechargeTarget && (
        <HostRechargeHistoryModal
          member={rechargeTarget}
          onClose={() => setRechargeTarget(null)}
        />
      )}
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
    const adminName = getCurrentAdminName();
    const res = await approveAgencyApplication(app, adminName);
    alert(res.message);
    setActionLoading(false);
    load();
  };

  const handleReject = async () => {
    if (!rejectModalApp) return;
    setActionLoading(true);
    const adminName = getCurrentAdminName();
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
  const [subTab, setSubTab] = useState<'ledger' | 'withdrawals' | 'commissions'>('ledger');
  const [ledger, setLedger] = useState<AgencyLedgerEntryModel[]>([]);
  const [withdrawals, setWithdrawals] = useState<AgencyWithdrawalRequestModel[]>([]);
  const [agencies, setAgencies] = useState<HostAgencyModel[]>([]);
  const [allMembers, setAllMembers] = useState<HostAgencyMemberModel[]>([]);
  const [milestones, setMilestones] = useState<HostMilestoneModel[]>([]);
  const [commAgencyFilter, setCommAgencyFilter] = useState('');
  const [commSearch, setCommSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [loadingCommissions, setLoadingCommissions] = useState(false);
  const [wFilter, setWFilter] = useState('pending');

  const loadLedger = () => { getAgencyLedger().then(d => setLedger(d)); };
  const loadWithdrawals = () => { setLoading(true); getWithdrawalRequests(wFilter).then(d => { setWithdrawals(d); setLoading(false); }); };
  const loadCommissions = async () => {
    setLoadingCommissions(true);
    const [ag, mem, ms] = await Promise.all([
      getHostAgencies(),
      getHostAgencyMembers(),
      getHostMilestones(),
    ]);
    setAgencies(ag);
    setAllMembers(mem);
    setMilestones(ms);
    setLoadingCommissions(false);
  };

  useEffect(() => { loadLedger(); }, []);
  useEffect(() => { loadWithdrawals(); }, [wFilter]);
  useEffect(() => {
    if (subTab === 'commissions') {
      loadCommissions();
    }
  }, [subTab]);

  const statusColors: Record<string, string> = {
    pending: 'text-yellow-400', approved: 'text-emerald-400', rejected: 'text-rose-400',
  };

  const filteredCommissions = allMembers.filter(m => {
    if (commAgencyFilter && m.agency_id !== commAgencyFilter) return false;
    if (!commSearch.trim()) return true;
    const q = commSearch.trim().toLowerCase();
    return (
      (m.user_name || '').toLowerCase().includes(q) ||
      (m.custom_id || '').toLowerCase().includes(q) ||
      (m.user_id || '').toLowerCase().includes(q)
    );
  });

  const totalMonthlyDiamonds = filteredCommissions.reduce((sum, m) => sum + (m.diamonds_earned_monthly ?? 0), 0);
  const totalCommDiamonds = filteredCommissions.reduce((sum, m) => {
    const ag = agencies.find(a => a.id === m.agency_id);
    const stage = getMemberStageAndCommission(m, milestones, ag?.commission_rate);
    return sum + stage.commissionDiamonds;
  }, 0);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2 items-center">
        <button onClick={() => setSubTab('ledger')}
          className={`text-xs px-3 py-1.5 rounded-lg font-semibold transition-colors ${subTab === 'ledger' ? 'bg-indigo-500/20 text-indigo-300' : 'text-slate-400 hover:text-white'}`}>
          {t('agency.diamondLedger')}
        </button>
        <button onClick={() => setSubTab('withdrawals')}
          className={`text-xs px-3 py-1.5 rounded-lg font-semibold transition-colors ${subTab === 'withdrawals' ? 'bg-indigo-500/20 text-indigo-300' : 'text-slate-400 hover:text-white'}`}>
          {t('agency.withdrawalRequests')}
        </button>
        <button onClick={() => setSubTab('commissions')}
          className={`text-xs px-3.5 py-1.5 rounded-lg font-bold transition-all flex items-center gap-1.5 ${subTab === 'commissions' ? 'bg-cyan-500/20 text-cyan-300 border border-cyan-500/40 shadow-sm' : 'text-slate-400 hover:text-white border border-transparent'}`}>
          <span>💎</span>
          <span>سجل عمولات الوكلاء بالماس</span>
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

      {subTab === 'commissions' && (
        <div className="space-y-4">
          {/* Quick Summary Cards */}
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-3">
            <div className="bg-[#18181b] p-3 rounded-xl border border-white/5">
              <span className="text-[10px] text-slate-400 block">👥 إجمالي المضيفين</span>
              <span className="text-sm font-bold text-white font-mono">{filteredCommissions.length} مضيف</span>
            </div>
            <div className="bg-[#18181b] p-3 rounded-xl border border-white/5">
              <span className="text-[10px] text-slate-400 block">💎 ألماس الإنتاج الشهري</span>
              <span className="text-sm font-bold text-amber-400 font-mono">{totalMonthlyDiamonds.toLocaleString()} 💎</span>
            </div>
            <div className="bg-gradient-to-r from-cyan-500/10 to-indigo-500/10 p-3 rounded-xl border border-cyan-500/30">
              <span className="text-[10px] text-cyan-300 font-semibold block">💎 إجمالي عمولات الوكلاء المستحقة</span>
              <span className="text-sm font-bold text-cyan-400 font-mono">{totalCommDiamonds.toLocaleString()} 💎</span>
            </div>
            <div className="bg-[#18181b] p-3 rounded-xl border border-white/5">
              <span className="text-[10px] text-slate-400 block">🏢 الوكالات المشمولة</span>
              <span className="text-sm font-bold text-indigo-400 font-mono">{commAgencyFilter ? 1 : agencies.length} وكالة</span>
            </div>
          </div>

          {/* Filters Bar */}
          <div className="flex flex-wrap items-center justify-between gap-3 bg-[#121214] p-3 rounded-xl border border-white/5">
            <div className="flex items-center gap-3">
              <label className="text-xs text-slate-400 font-bold">فلترة حسب الوكالة:</label>
              <select
                value={commAgencyFilter}
                onChange={e => setCommAgencyFilter(e.target.value)}
                className="bg-[#18181b] border border-white/10 rounded-lg py-1 px-3 text-xs text-white focus:outline-none focus:border-cyan-500"
              >
                <option value="">جميع الوكالات ({agencies.length})</option>
                {agencies.map(a => (
                  <option key={a.id} value={a.id}>{a.name}</option>
                ))}
              </select>
            </div>
            <input
              value={commSearch}
              onChange={e => setCommSearch(e.target.value)}
              placeholder="بحث باسم المضيف أو الـ ID..."
              className="bg-[#18181b] border border-white/10 rounded-xl px-3 py-1.5 text-xs text-white placeholder:text-slate-500 w-64 focus:outline-none focus:border-cyan-500"
            />
          </div>

          {/* DataTable */}
          <DataTable
            loading={loadingCommissions}
            columns={[
              { key: 'user_name', label: 'المضيف', sortable: true, render: m => {
                const mem = m as HostAgencyMemberModel;
                return (
                  <div className="flex items-center gap-2.5">
                    <img src={mem.avatar_url || `https://ui-avatars.com/api/?name=${encodeURIComponent(mem.user_name || 'Host')}&background=random`} alt="" className="w-8 h-8 rounded-full object-cover border border-white/10 shrink-0" />
                    <div>
                      <div className="text-white font-bold text-xs">{mem.user_name || 'مضيف'}</div>
                      <div className="text-[10px] text-cyan-400 font-mono font-bold">ID: #{mem.custom_id || mem.user_id?.slice(0, 8)}</div>
                    </div>
                  </div>
                );
              }},
              { key: 'agency_id', label: 'الوكالة التابع لها', sortable: true, render: m => {
                const mem = m as HostAgencyMemberModel;
                const ag = agencies.find(a => a.id === mem.agency_id);
                return (
                  <div>
                    <div className="text-indigo-300 font-bold text-xs">{ag?.name ?? mem.agency_id?.slice(0, 8)}</div>
                    <div className="text-[10px] text-slate-500">مالك: {ag?.owner_name || '—'}</div>
                  </div>
                );
              }},
              { key: 'diamonds_earned_monthly', label: 'ألماس المضيف هذا الشهر 💎', sortable: true, render: m => {
                const v = (m as HostAgencyMemberModel).diamonds_earned_monthly;
                return <span className="text-amber-400 font-bold font-mono text-xs">💎 {(v ?? 0).toLocaleString()}</span>;
              }},
              { key: 'stage', label: 'المرحلة والتارجت المحقق', sortable: true, render: m => {
                const ag = agencies.find(a => a.id === (m as HostAgencyMemberModel).agency_id);
                const stage = getMemberStageAndCommission(m, milestones, ag?.commission_rate);
                return stage.isReached ? (
                  <div className="flex flex-col">
                    <span className="text-emerald-400 font-bold text-xs bg-emerald-500/10 px-2 py-0.5 rounded border border-emerald-500/20 inline-block w-fit">
                      {stage.stageTitle}
                    </span>
                    <span className="text-[10px] text-slate-400 font-mono mt-0.5">تارجت: {stage.targetDiamonds.toLocaleString()} 💎</span>
                  </div>
                ) : (
                  <span className="text-slate-500 text-xs">{stage.stageTitle}</span>
                );
              }},
              { key: 'commission_rate', label: 'نسبة عمولة الوكيل', render: m => {
                const ag = agencies.find(a => a.id === (m as HostAgencyMemberModel).agency_id);
                const stage = getMemberStageAndCommission(m, milestones, ag?.commission_rate);
                return <span className="text-cyan-400 font-bold text-xs">{Math.round(stage.rate * 100)}%</span>;
              }},
              { key: 'commission_diamonds', label: 'عمولة الوكيل بالماس 💎', sortable: true, render: m => {
                const ag = agencies.find(a => a.id === (m as HostAgencyMemberModel).agency_id);
                const stage = getMemberStageAndCommission(m, milestones, ag?.commission_rate);
                return stage.commissionDiamonds > 0 ? (
                  <div className="flex flex-col">
                    <span className="text-cyan-400 font-bold font-mono text-xs">💎 {stage.commissionDiamonds.toLocaleString()}</span>
                    <span className="text-[10px] text-cyan-500/80">من تارجت {stage.targetDiamonds.toLocaleString()}</span>
                  </div>
                ) : (
                  <span className="text-slate-600 text-xs">0 💎 (لم يبلغ التارجت)</span>
                );
              }},
              { key: 'role', label: 'الرتبة', render: m => {
                const r = (m as HostAgencyMemberModel).role;
                return r === 'owner' ? <span className="text-amber-400 text-xs font-bold">👑 مالك</span> :
                       r === 'supervisor' ? <span className="text-cyan-400 text-xs font-bold">⭐ مشرف</span> :
                       <span className="text-slate-400 text-xs">🎙️ مضيف</span>;
              }},
            ]}
            data={filteredCommissions}
            searchKeys={['user_name', 'custom_id', 'user_id']}
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
  const [generalCommissionRate, setGeneralCommissionRate] = useState<number>(20);
  const [agentCommissionRate, setAgentCommissionRate] = useState<string>('20');
  const [targetDays, setTargetDays] = useState<string>('0');
  const [targetHours, setTargetHours] = useState<string>('0');
  const [periodType, setPeriodType] = useState('monthly');
  const [sortOrder, setSortOrder] = useState('0');
  const [isActive, setIsActive] = useState(true);
  const [showItemPicker, setShowItemPicker] = useState(false);

  const load = () => {
    setLoading(true);
    getHostMilestones().then(d => { setMilestones(d); setLoading(false); });
    getCommissionSettings().then(cs => {
      const ar = cs.find(c => c.key === 'agency_rate')?.value;
      if (ar != null) {
        setGeneralCommissionRate(ar);
        setAgentCommissionRate(String(ar));
      }
    }).catch(err => {
      console.warn('Failed to load commission settings for agency rate:', err);
    });
    supabase.from('store_items').select('*').then(({ data }) => {
      if (data) setStoreItems(data);
    });
  };

  useEffect(() => { load(); }, []);

  const resetForm = () => {
    setTitle(''); setTargetDiamonds('1000000'); setRewardType('salary_usd');
    setRewardValue('100'); setRewardItemId(''); setRewardImageUrl(''); setBackgroundUrl('');
    setAgentCommissionRate(String(generalCommissionRate || 20));
    setTargetDays('0'); setTargetHours('0');
    setPeriodType('monthly'); setSortOrder('0'); setIsActive(true);
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
    const comm = m.agent_commission_rate ?? m.agentCommissionRate;
    setAgentCommissionRate(comm != null ? String(Math.round(comm * 100)) : String(generalCommissionRate || 20));
    setTargetDays(String(m.target_days ?? m.targetDays ?? 0));
    setTargetHours(String(m.target_hours ?? m.targetHours ?? 0));
    setPeriodType(m.period_type ?? m.periodType ?? 'monthly');
    setSortOrder(String(m.sort_order ?? m.sortOrder ?? 0));
    setIsActive(m.is_active !== false && m.isActive !== false);
    setShowForm(true);
  };

  const handleSubmit = async () => {
    if (!title.trim()) return;
    const commRateNum = (parseFloat(agentCommissionRate) || (generalCommissionRate || 20)) / 100;
    const payload = {
      title: title.trim(),
      target_diamonds: parseInt(targetDiamonds) || 0,
      reward_type: rewardType as any,
      reward_value: parseFloat(rewardValue) || 0,
      reward_item_id: rewardItemId.trim() || null,
      reward_image_url: rewardImageUrl.trim() || null,
      background_url: backgroundUrl.trim() || null,
      agent_commission_rate: commRateNum,
      target_days: parseInt(targetDays) || 0,
      target_hours: parseInt(targetHours) || 0,
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

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
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
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-3 bg-indigo-500/10 border border-indigo-500/20 rounded-xl p-3">
            <div>
              <label className="text-[11px] text-amber-300 font-bold block mb-1">
                💎 نسبة عمولة الوكيل لهذه المرحلة (%) *
              </label>
              <div className="flex items-center gap-2">
                <input
                  type="number"
                  value={agentCommissionRate}
                  onChange={e => setAgentCommissionRate(e.target.value)}
                  placeholder="20"
                  className="w-full bg-[#121214] border border-amber-500/30 rounded-xl py-2 px-3 text-xs text-amber-300 font-bold focus:outline-none focus:border-amber-400"
                />
                <span className="text-xs text-slate-400 font-bold">%</span>
              </div>
              <span className="text-[10px] text-slate-400 block mt-1">
                عمولة الوكيل: 💎 {Math.round(((parseInt(targetDiamonds) || 0) * (parseFloat(agentCommissionRate) || 0)) / 100).toLocaleString()}
              </span>
            </div>
            <div>
              <label className="text-[11px] text-indigo-300 font-bold block mb-1">
                📅 أيام البث المطلوبة (Target Days)
              </label>
              <input
                type="number"
                value={targetDays}
                onChange={e => setTargetDays(e.target.value)}
                placeholder="0 (اختياري)"
                className="w-full bg-[#121214] border border-indigo-500/30 rounded-xl py-2 px-3 text-xs text-indigo-200 font-bold focus:outline-none focus:border-indigo-400"
              />
              <span className="text-[10px] text-slate-500 block mt-1">0 = لا يشترط أيام محددة</span>
            </div>
            <div>
              <label className="text-[11px] text-cyan-300 font-bold block mb-1">
                ⏱️ ساعات البث المطلوبة (Target Hours)
              </label>
              <input
                type="number"
                value={targetHours}
                onChange={e => setTargetHours(e.target.value)}
                placeholder="0 (اختياري)"
                className="w-full bg-[#121214] border border-cyan-500/30 rounded-xl py-2 px-3 text-xs text-cyan-200 font-bold focus:outline-none focus:border-cyan-400"
              />
              <span className="text-[10px] text-slate-500 block mt-1">0 = لا يشترط ساعات محددة</span>
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

          {/* Quick Preset Buttons */}
          <div className="flex flex-wrap items-center gap-2 pt-2 border-t border-white/5">
            <span className="text-[11px] text-slate-400 font-bold">🎯 قوالب تارجت جاهزة وسريعة:</span>
            <button
              type="button"
              onClick={() => {
                setTitle('التارجت الأول (150,000 ماس)');
                setTargetDiamonds('150000');
                setRewardType('salary_usd');
                setRewardValue('10');
              }}
              className="px-2.5 py-1 bg-amber-500/10 hover:bg-amber-500/20 text-amber-300 rounded-lg text-xs font-semibold border border-amber-500/20"
            >
              التارجت الأول (150 ألف ماس 💎 - $10)
            </button>
            <button
              type="button"
              onClick={() => {
                setTitle('التارجت الثاني (300,000 ماس)');
                setTargetDiamonds('300000');
                setRewardType('salary_usd');
                setRewardValue('20');
              }}
              className="px-2.5 py-1 bg-cyan-500/10 hover:bg-cyan-500/20 text-cyan-300 rounded-lg text-xs font-semibold border border-cyan-500/20"
            >
              التارجت الثاني (300 ألف ماس 💎 - $20)
            </button>
            <button
              type="button"
              onClick={() => {
                setTitle('التارجت الثالث (500,000 ماس)');
                setTargetDiamonds('500000');
                setRewardType('salary_usd');
                setRewardValue('35');
              }}
              className="px-2.5 py-1 bg-indigo-500/10 hover:bg-indigo-500/20 text-indigo-300 rounded-lg text-xs font-semibold border border-indigo-500/20"
            >
              التارجت الثالث (500 ألف ماس 💎 - $35)
            </button>
            <button
              type="button"
              onClick={() => {
                setTitle('تارجت المليون (1,000,000 ماس)');
                setTargetDiamonds('1000000');
                setRewardType('salary_usd');
                setRewardValue('70');
              }}
              className="px-2.5 py-1 bg-emerald-500/10 hover:bg-emerald-500/20 text-emerald-300 rounded-lg text-xs font-semibold border border-emerald-500/20"
            >
              تارجت المليون (1 مليون ماس 💎 - $70)
            </button>
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
          { key: 'reward_value', label: 'الراتب / المكافأة المحددة', render: m => {
            const rType = (m as any).reward_type || (m as any).rewardType || 'salary_usd';
            const rVal = (m as any).reward_value ?? (m as any).rewardValue ?? 0;
            if (rType === 'salary_usd') return <span className="text-emerald-400 font-bold">${rVal} USD 💵</span>;
            if (rType === 'diamonds') return <span className="text-cyan-400 font-bold">{Number(rVal).toLocaleString()} 💎</span>;
            if (rType === 'gold') return <span className="text-amber-400 font-bold">{Number(rVal).toLocaleString()} 🪙</span>;
            if (rType === 'vip_days') return <span className="text-purple-400 font-bold">{rVal} يوم VIP 👑</span>;
            return <span className="text-indigo-400 font-bold">{rVal} ({rType})</span>;
          }},
          { key: 'agent_commission_rate', label: 'عمولة الوكيل بالماس 💎', sortable: true, render: m => {
            const tD = Number((m as any).target_diamonds ?? (m as any).targetDiamonds ?? 0);
            const commRate = Number((m as any).agent_commission_rate ?? (m as any).agentCommissionRate ?? ((generalCommissionRate || 20) / 100));
            const commVal = Math.round(tD * commRate);
            return (
              <div className="flex flex-col">
                <span className="text-amber-400 font-bold font-mono">💎 {commVal.toLocaleString()}</span>
                <span className="text-[10px] text-cyan-400 font-semibold">{Math.round(commRate * 100)}% من التارجت</span>
              </div>
            );
          }},
          { key: 'target_requirements', label: 'شروط البث', render: m => {
            const days = Number((m as any).target_days ?? (m as any).targetDays ?? 0);
            const hrs = Number((m as any).target_hours ?? (m as any).targetHours ?? 0);
            if (days === 0 && hrs === 0) return <span className="text-slate-500 text-xs">—</span>;
            return (
              <div className="text-[11px] text-slate-300 flex flex-col gap-0.5">
                {days > 0 && <span className="text-indigo-300 font-medium">📅 {days} يوم</span>}
                {hrs > 0 && <span className="text-cyan-300 font-medium">⏱️ {hrs} ساعة</span>}
              </div>
            );
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

  // Exchange Tiers State
  const [exchangeTiers, setExchangeTiers] = useState<RechargeAgencyExchangeTier[]>([]);
  const [showAddTierModal, setShowAddTierModal] = useState(false);
  const [editTier, setEditTier] = useState<RechargeAgencyExchangeTier | null>(null);

  // Form states for Exchange Tier
  const [tierUsd, setTierUsd] = useState('1');
  const [tierDiamonds, setTierDiamonds] = useState('15000');
  const [tierCoins, setTierCoins] = useState('1000');
  const [tierTitle, setTierTitle] = useState('');
  const [tierBadge, setTierBadge] = useState('');
  const [tierOrder, setTierOrder] = useState('1');

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
      const u1 = await getRechargeAgentsWithWallets();
      setAgents(u1 || []);

      const tiers = await getRechargeAgencyExchangeTiers();
      setExchangeTiers(tiers || []);

      try {
        const { data: wData } = await supabase.from('agency_withdrawal_requests').select('*').order('created_at', { ascending: false });
        setWithdrawals(wData || []);
      } catch (_) {}
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
    const adminName = getCurrentAdminName();

    await updateRechargeAgency(userId, {
      recharge_agency_name: agencyName.trim() || 'وكالة الشحن المعتمدة',
      recharge_agency_logo: agencyLogo.trim() || undefined,
      whatsapp_number: whatsappPhone.trim() || undefined,
      coins: parseInt(initialCoins) || 0,
      coinsMode: 'set',
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
    setEditCoins(String(ag.agency_gold_balance ?? ag.coins ?? 0));
    setEditCommissionRate(String(ag.recharge_commission_rate ?? 5));
  };

  const handleSaveEditAgent = async () => {
    if (!editAgent) return;
    const adminName = getCurrentAdminName();
    await updateRechargeAgency(editAgent.id, {
      recharge_agency_name: editName.trim() || 'وكالة الشحن المعتمدة',
      recharge_agency_logo: editLogo.trim() || undefined,
      whatsapp_number: editWhatsapp.trim() || undefined,
      coins: parseInt(editCoins) || 0,
      coinsMode: 'set',
      recharge_commission_rate: parseFloat(editCommissionRate) || 5,
      adminName,
    });
    setEditAgent(null);
    alert('تم تحديث بيانات وكالة الشحن بنجاح!');
    load();
  };

  // Exchange Tiers CRUD Handlers
  const handleCreateTier = async () => {
    const usd = parseFloat(tierUsd) || 1;
    const dia = parseInt(tierDiamonds) || 15000;
    const cns = parseInt(tierCoins) || 1000;
    const title = tierTitle.trim() || `باقة $${usd}`;
    const badge = tierBadge.trim() || null;
    const order = parseInt(tierOrder) || 1;

    const ok = await createRechargeAgencyExchangeTier({
      usd_amount: usd,
      diamonds_cost: dia,
      coins_received: cns,
      title,
      badge_text: badge,
      is_active: true,
      sort_order: order,
    });

    if (ok) {
      setShowAddTierModal(false);
      setTierUsd('1'); setTierDiamonds('15000'); setTierCoins('1000'); setTierTitle(''); setTierBadge('');
      load();
    } else {
      alert('حدث خطأ أثناء حفظ باقة الصرف');
    }
  };

  const openEditTierModal = (t: RechargeAgencyExchangeTier) => {
    setEditTier(t);
    setTierUsd(String(t.usd_amount));
    setTierDiamonds(String(t.diamonds_cost));
    setTierCoins(String(t.coins_received));
    setTierTitle(t.title);
    setTierBadge(t.badge_text || '');
    setTierOrder(String(t.sort_order));
  };

  const handleSaveEditTier = async () => {
    if (!editTier) return;
    const usd = parseFloat(tierUsd) || 1;
    const dia = parseInt(tierDiamonds) || 15000;
    const cns = parseInt(tierCoins) || 1000;
    const title = tierTitle.trim() || `باقة $${usd}`;
    const badge = tierBadge.trim() || null;
    const order = parseInt(tierOrder) || 1;

    const ok = await updateRechargeAgencyExchangeTier(editTier.id, {
      usd_amount: usd,
      diamonds_cost: dia,
      coins_received: cns,
      title,
      badge_text: badge,
      sort_order: order,
    });

    if (ok) {
      setEditTier(null);
      load();
    } else {
      alert('حدث خطأ أثناء تعديل باقة الصرف');
    }
  };

  const handleDeleteTier = async (id: string) => {
    if (confirm('هل أنت متأكد من حذف باقة الصرف هذه؟')) {
      await deleteRechargeAgencyExchangeTier(id);
      load();
    }
  };

  const handleToggleTierActive = async (tier: RechargeAgencyExchangeTier) => {
    await updateRechargeAgencyExchangeTier(tier.id, { is_active: !tier.is_active });
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
    const targetId = u.uid || u.id;

    const { error: err1 } = await supabase.from('users').update({ 
      coins: newCoins,
    }).eq('uid', targetId);

    if (err1) {
      await supabase.from('users').update({ 
        coins: newCoins,
      }).eq('id', targetId);
    }

    const adminName = getCurrentAdminName();
    await sendSystemNotification({
      userId: targetId,
      title: '🪙 شحن رصيد عملات لحسابك',
      body: `مبروك! قام المشرف [${adminName}] بشحن ${amount.toLocaleString()} عملة ذهبية لحسابك بنجاح. رصيدك الحالي الآن: ${newCoins.toLocaleString()} عملة.`,
      type: 'system',
      action: 'coins_recharged',
      extraData: { amount, new_balance: newCoins, admin_name: adminName },
    });

    alert(`تم شحن ${amount.toLocaleString()} عملة للمستخدم (${u.name || targetId}) بنجاح! الرصيد الجديد: ${newCoins.toLocaleString()}`);
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

            <div className="space-y-1.5 pt-2 border-t border-white/5 text-xs">
              <div className="flex items-center justify-between">
                <span className="text-slate-400">🪙 كوينز الوكالة (للشحن):</span>
                <span className="text-sm text-amber-400 font-bold font-mono">{Number(ag.agency_gold_balance ?? 0).toLocaleString()} 🪙</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-slate-400">💎 ألماس الوكالة (رواتب):</span>
                <span className="text-sm text-cyan-400 font-bold font-mono">{Number(ag.agency_diamond_balance ?? 0).toLocaleString()} 💎</span>
              </div>
              <div className="text-[10px] text-slate-500 text-left pt-0.5">
                (رصيد الوكالة مفصول تماماً عن محفظة المستخدم الشخصية)
              </div>
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

      {/* 🔄 Recharge Agency Exchange Tiers Section */}
      <div className="bg-[#141417] border border-amber-500/20 rounded-2xl p-5 space-y-4 shadow-xl">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="flex items-center gap-2">
              <span className="text-xl">🔄</span>
              <h3 className="text-white text-sm font-bold">باقات صرف الألماس إلى كوينز (لوحة تحكم وكيل الشحن)</h3>
            </div>
            <p className="text-slate-400 text-xs mt-1">
              هذه الباقات تظهر لوكيل الشحن عند النقر على زر "صرف" في شاشة الألماس بتطبيق الموبايل، ليتم تحويل الألماس إلى كوينز في محفظة الوكالة
            </p>
          </div>
          <button
            onClick={() => {
              setTierUsd('1');
              setTierDiamonds('15000');
              setTierCoins('1000');
              setTierTitle('باقة 1 دولار');
              setTierBadge('');
              setTierOrder(String(exchangeTiers.length + 1));
              setShowAddTierModal(true);
            }}
            className="text-xs bg-gradient-to-r from-amber-500 to-amber-600 hover:from-amber-600 hover:to-amber-700 text-black font-bold px-4 py-2 rounded-xl transition-all shadow-lg shadow-amber-500/20 flex items-center gap-1.5"
          >
            <Plus className="w-4 h-4" />
            <span>إضافة باقة صرف جديدة</span>
          </button>
        </div>

        {/* Tiers Grid */}
        {exchangeTiers.length === 0 ? (
          <div className="p-8 text-center text-xs text-slate-500 bg-black/20 rounded-xl border border-white/5">
            لا توجد باقات صرف مسجلة حالياً. اضغط "إضافة باقة صرف جديدة" لإنشاء أول باقة.
          </div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-3.5">
            {exchangeTiers.map(t => (
              <div
                key={t.id}
                className={`bg-black/40 border ${
                  t.is_active ? 'border-amber-500/30' : 'border-white/5 opacity-60'
                } rounded-xl p-4 space-y-3 relative flex flex-col justify-between`}
              >
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-bold text-white truncate">{t.title}</span>
                    {t.badge_text && (
                      <span className="px-2 py-0.5 rounded text-[10px] bg-amber-500/20 text-amber-300 font-bold border border-amber-500/30">
                        {t.badge_text}
                      </span>
                    )}
                  </div>

                  <div className="text-2xl font-black text-amber-400 font-mono">
                    ${t.usd_amount}
                  </div>

                  <div className="space-y-1 text-xs">
                    <div className="flex justify-between text-slate-300">
                      <span className="text-slate-400">تكلفة الألماس:</span>
                      <strong className="text-cyan-400 font-mono">{t.diamonds_cost.toLocaleString()} 💎</strong>
                    </div>
                    <div className="flex justify-between text-slate-300">
                      <span className="text-slate-400">كوينز مستلمة:</span>
                      <strong className="text-emerald-400 font-mono">{t.coins_received.toLocaleString()} 🪙</strong>
                    </div>
                  </div>
                </div>

                <div className="flex items-center justify-between pt-2 border-t border-white/5 text-xs">
                  <button
                    onClick={() => handleToggleTierActive(t)}
                    className={`px-2 py-0.5 rounded text-[10px] font-bold ${
                      t.is_active ? 'bg-emerald-500/20 text-emerald-400' : 'bg-slate-700 text-slate-300'
                    }`}
                  >
                    {t.is_active ? 'مفعلة' : 'معطلة'}
                  </button>
                  <div className="flex items-center gap-1.5">
                    <button
                      onClick={() => openEditTierModal(t)}
                      className="p-1 text-slate-300 hover:text-white hover:bg-white/10 rounded"
                      title="تعديل الباقة"
                    >
                      <Edit3 className="w-3.5 h-3.5" />
                    </button>
                    <button
                      onClick={() => handleDeleteTier(t.id)}
                      className="p-1 text-rose-400 hover:text-rose-300 hover:bg-rose-500/10 rounded"
                      title="حذف الباقة"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
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

      {/* Add Exchange Tier Modal */}
      {showAddTierModal && (
        <div className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-[#18181b] border border-amber-500/30 rounded-2xl max-w-md w-full p-5 space-y-4 shadow-2xl">
            <h4 className="text-white font-bold text-sm flex items-center gap-2">
              <span>➕</span> إضافة باقة صرف ألماس جديدة لوكالات الشحن
            </h4>
            <div className="space-y-3">
              <div>
                <label className="text-[11px] text-slate-400 block mb-1">اسم الباقة *</label>
                <input
                  value={tierTitle}
                  onChange={e => setTierTitle(e.target.value)}
                  placeholder="مثال: باقة 1 دولار"
                  className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-[11px] text-amber-400 block mb-1">القيمة بالدولار ($) *</label>
                  <input
                    type="number"
                    step="0.5"
                    value={tierUsd}
                    onChange={e => {
                      const v = e.target.value;
                      setTierUsd(v);
                      if (!tierTitle || tierTitle.startsWith('باقة')) {
                        setTierTitle(`باقة ${v} دولار`);
                      }
                    }}
                    placeholder="1"
                    className="w-full bg-[#121214] border border-amber-500/30 rounded-xl p-2 text-xs text-amber-300 font-bold font-mono"
                  />
                </div>
                <div>
                  <label className="text-[11px] text-cyan-400 block mb-1">تكلفة الألماس (💎) *</label>
                  <input
                    type="number"
                    step="1000"
                    value={tierDiamonds}
                    onChange={e => setTierDiamonds(e.target.value)}
                    placeholder="15000"
                    className="w-full bg-[#121214] border border-cyan-500/30 rounded-xl p-2 text-xs text-cyan-300 font-bold font-mono"
                  />
                </div>
              </div>

              <div>
                <label className="text-[11px] text-emerald-400 block mb-1">الكوينز المضافة لمحفظة الوكالة (🪙) *</label>
                <input
                  type="number"
                  step="1000"
                  value={tierCoins}
                  onChange={e => setTierCoins(e.target.value)}
                  placeholder="1000"
                  className="w-full bg-[#121214] border border-emerald-500/30 rounded-xl p-2 text-xs text-emerald-300 font-bold font-mono"
                />
                <p className="text-[10px] text-slate-500 mt-1">يتم إيداع هذا العدد من الكوينز حصراً في محفظة الوكالة لشحن المستخدمين</p>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-[11px] text-slate-400 block mb-1">شارة مميزة (اختياري)</label>
                  <input
                    value={tierBadge}
                    onChange={e => setTierBadge(e.target.value)}
                    placeholder="مثال: الأكثر طلباً، توفير"
                    className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white"
                  />
                </div>
                <div>
                  <label className="text-[11px] text-slate-400 block mb-1">ترتيب الظهور</label>
                  <input
                    type="number"
                    value={tierOrder}
                    onChange={e => setTierOrder(e.target.value)}
                    placeholder="1"
                    className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white font-mono"
                  />
                </div>
              </div>
            </div>

            <div className="flex justify-end gap-2 pt-2 border-t border-white/10">
              <button onClick={() => setShowAddTierModal(false)} className="px-4 py-2 text-xs text-slate-400">إلغاء</button>
              <button onClick={handleCreateTier} className="px-5 py-2 bg-gradient-to-r from-amber-500 to-amber-600 text-black rounded-xl text-xs font-bold">حفظ الباقة</button>
            </div>
          </div>
        </div>
      )}

      {/* Edit Exchange Tier Modal */}
      {editTier && (
        <div className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-[#18181b] border border-amber-500/30 rounded-2xl max-w-md w-full p-5 space-y-4 shadow-2xl">
            <h4 className="text-white font-bold text-sm flex items-center gap-2">
              <span>✏️</span> تعديل باقة صرف الألماس
            </h4>
            <div className="space-y-3">
              <div>
                <label className="text-[11px] text-slate-400 block mb-1">اسم الباقة *</label>
                <input
                  value={tierTitle}
                  onChange={e => setTierTitle(e.target.value)}
                  className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-[11px] text-amber-400 block mb-1">القيمة بالدولار ($) *</label>
                  <input
                    type="number"
                    step="0.5"
                    value={tierUsd}
                    onChange={e => setTierUsd(e.target.value)}
                    className="w-full bg-[#121214] border border-amber-500/30 rounded-xl p-2 text-xs text-amber-300 font-bold font-mono"
                  />
                </div>
                <div>
                  <label className="text-[11px] text-cyan-400 block mb-1">تكلفة الألماس (💎) *</label>
                  <input
                    type="number"
                    step="1000"
                    value={tierDiamonds}
                    onChange={e => setTierDiamonds(e.target.value)}
                    className="w-full bg-[#121214] border border-cyan-500/30 rounded-xl p-2 text-xs text-cyan-300 font-bold font-mono"
                  />
                </div>
              </div>

              <div>
                <label className="text-[11px] text-emerald-400 block mb-1">الكوينز المضافة لمحفظة الوكالة (🪙) *</label>
                <input
                  type="number"
                  step="1000"
                  value={tierCoins}
                  onChange={e => setTierCoins(e.target.value)}
                  className="w-full bg-[#121214] border border-emerald-500/30 rounded-xl p-2 text-xs text-emerald-300 font-bold font-mono"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-[11px] text-slate-400 block mb-1">شارة مميزة</label>
                  <input
                    value={tierBadge}
                    onChange={e => setTierBadge(e.target.value)}
                    placeholder="مثال: الأكثر طلباً، توفير"
                    className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white"
                  />
                </div>
                <div>
                  <label className="text-[11px] text-slate-400 block mb-1">ترتيب الظهور</label>
                  <input
                    type="number"
                    value={tierOrder}
                    onChange={e => setTierOrder(e.target.value)}
                    className="w-full bg-[#121214] border border-white/10 rounded-xl p-2 text-xs text-white font-mono"
                  />
                </div>
              </div>
            </div>

            <div className="flex justify-end gap-2 pt-2 border-t border-white/10">
              <button onClick={() => setEditTier(null)} className="px-4 py-2 text-xs text-slate-400">إلغاء</button>
              <button onClick={handleSaveEditTier} className="px-5 py-2 bg-gradient-to-r from-amber-500 to-amber-600 text-black rounded-xl text-xs font-bold">حفظ التعديلات</button>
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
  const [savingKey, setSavingKey] = useState<string | null>(null);
  const [simCoins, setSimCoins] = useState<number>(15000);
  const [draftInputs, setDraftInputs] = useState<Record<string, string>>({});
  const [commissionPeriod, setCommissionPeriod] = useState<'daily' | 'weekly' | 'monthly'>('monthly');
  const [savingPeriod, setSavingPeriod] = useState(false);

  const load = () => {
    setLoading(true);
    getCommissionSettings().then(d => {
      setSettings(d);
      const cp = d.find(x => x.key === 'agency_commission_period');
      if (cp && cp.value && ['daily', 'weekly', 'monthly'].includes(String(cp.value))) {
        setCommissionPeriod(String(cp.value) as any);
      } else {
        supabase.from('app_config').select('value').eq('key', 'agency_commission_period').maybeSingle().then(({ data: cfg }) => {
          if (cfg?.value) {
            const val = typeof cfg.value === 'string' ? cfg.value.replace(/"/g, '') : cfg.value;
            if (['daily', 'weekly', 'monthly'].includes(val)) {
              setCommissionPeriod(val as any);
            }
          }
        });
      }
      setLoading(false);
    }).catch(err => {
      console.warn('Failed to load commission settings:', err);
      setLoading(false);
    });
  };

  const handleSavePeriod = async (period: 'daily' | 'weekly' | 'monthly') => {
    setSavingPeriod(true);
    try {
      await supabase.from('commission_settings').upsert({
        key: 'agency_commission_period',
        value: period,
        description: 'دورة صرف وتأكيد عمولة الوكيل (daily / weekly / monthly)',
        updated_at: new Date().toISOString(),
      }, { onConflict: 'key' });

      await supabase.from('app_config').upsert({
        key: 'agency_commission_period',
        value: period,
        updated_at: new Date().toISOString(),
      }, { onConflict: 'key' });

      setCommissionPeriod(period);
      alert(`✅ تم حفظ وتحديث دورة صرف عمولة الوكيل إلى (${period === 'daily' ? 'يومي' : period === 'weekly' ? 'أسبوعي' : 'شهري'}) بنجاح!`);
    } catch (err) {
      console.error(err);
      alert('حدث خطأ أثناء حفظ دورة الصرف');
    } finally {
      setSavingPeriod(false);
    }
  };

  useEffect(() => { load(); }, []);

  const handleUpdate = async (id: string, value: number) => {
    setSavingKey(id);
    await updateCommissionSetting(id, value);
    setSavingKey(null);
    load();
  };

  const getVal = (key: string, fallback: number) => {
    const s = settings.find(x => x.key === key);
    return s && typeof s.value === 'number' && !isNaN(s.value) ? s.value : fallback;
  };

  const coinsPerUsd = getVal('coins_per_usd', 15000);
  const hostRate = getVal('host_rate', 100);
  const agencyRate = getVal('agency_rate', 10);
  const hostTargetExchangeRate = getVal('host_target_exchange_rate', 60);
  const rechargeAgentHostRate = getVal('recharge_agent_host_rate', 10);
  const rechargeAgentAgencyRate = getVal('recharge_agent_agency_rate', 10);
  const platformRate = getVal('platform_rate', 17.72);
  const firstTargetDiamonds = getVal('first_target_diamonds', 150000);

  // Simulation calculations
  const safeCoins = Math.max(0, simCoins || 0);
  const simUsd = Number(((safeCoins) / (coinsPerUsd || 15000)).toFixed(2));
  const simHostDiamonds = Math.round(safeCoins * (hostRate / 100));
  const simAgencyDiamonds = Math.round(simHostDiamonds * (agencyRate / 100));
  const simTargetUnlockedSalary = Number((simUsd * (hostTargetExchangeRate / 100)).toFixed(2));

  const descKeyMap: Record<string, string> = {
    coins_per_usd: 'سعر الصرف المعتمد: عدد الكوينز مقابل كل 1 دولار أمريكي (1$ = 15,000 كوينز)',
    host_rate: 'نسبة استلام المضيف من كوينز الهدايا المرسلة وتحويلها لألماس (افتراضي 100%)',
    agency_rate: 'نسبة عمولة وراتب صاحب الوكالة من ألماس المضيف (افتراضي 10%)',
    host_target_exchange_rate: 'نسبة راتب المضيف في حال فك ألماس التارجت وتحويله لكوينز (افتراضي 60% مع خصم 40% من الراتب)',
    recharge_agent_host_rate: 'عمولة وكيل الشحن الإضافية من تحويل راتب المضيف (افتراضي 10%)',
    recharge_agent_agency_rate: 'عمولة وكيل الشحن الإضافية من تحويل راتب وكيل المضيف (افتراضي 10%)',
    platform_rate: 'نسبة الإدارة والمتبقي للنظام (افتراضي 17.72%)',
    first_target_diamonds: 'قيمة تارجت المستوى الأول بالماس (150,000 ماس)',
  };

  const quickSave = async (key: string) => {
    const raw = draftInputs[key];
    const num = parseFloat(raw);
    if (!isNaN(num) && num >= 0) {
      await handleUpdate(key, num);
      setDraftInputs(prev => {
        const next = { ...prev };
        delete next[key];
        return next;
      });
    }
  };

  return (
    <div className="space-y-6">
      {/* 1. Quick Control Hero Cards */}
      <div className="bg-[#141417] border border-amber-500/30 rounded-2xl p-5 space-y-4 shadow-xl">
        <div className="flex items-center justify-between flex-wrap gap-2">
          <div className="flex items-center gap-2">
            <Coins className="w-5 h-5 text-amber-400" />
            <div>
              <h3 className="text-sm font-bold text-white">
                ⚡ التحكم الفوري في سعر الصرف وتوزيع أرباح الهدايا
              </h3>
              <p className="text-[11px] text-slate-400">
                يمكنك تغيير سعر صرف الدولار ونسب المضيف والوكيل مباشرةً من هنا، ويتم تحديث النظام والتطبيق فوراً
              </p>
            </div>
          </div>
          <button
            onClick={load}
            className="px-3 py-1.5 bg-white/5 hover:bg-white/10 text-slate-300 rounded-lg text-xs flex items-center gap-1.5 transition-colors"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin' : ''}`} />
            تحديث البيانات
          </button>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5 gap-3.5 pt-2">
          {/* Card 1: Coins per USD */}
          <div className="bg-gradient-to-b from-amber-500/10 to-transparent border border-amber-500/20 rounded-xl p-4 space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold text-amber-300">💵 سعر الصرف (1$ دولار)</span>
              <span className="text-[10px] bg-amber-500/20 text-amber-300 px-2 py-0.5 rounded-full font-mono">
                {coinsPerUsd.toLocaleString()} كوينز
              </span>
            </div>
            <p className="text-[11px] text-slate-400">كم كوينز تعادل 1 دولار أمريكي</p>
            <div className="flex items-center gap-2">
              <input
                type="number"
                step="100"
                min="1"
                placeholder={String(coinsPerUsd)}
                value={draftInputs['coins_per_usd'] ?? ''}
                onChange={e => setDraftInputs(prev => ({ ...prev, coins_per_usd: e.target.value }))}
                className="w-full bg-black/60 border border-white/10 rounded-lg px-2.5 py-1.5 text-xs text-white focus:outline-none focus:border-amber-400"
              />
              <button
                disabled={savingKey === 'coins_per_usd' || draftInputs['coins_per_usd'] == null || draftInputs['coins_per_usd'] === ''}
                onClick={() => quickSave('coins_per_usd')}
                className="px-3 py-1.5 bg-amber-500 hover:bg-amber-600 disabled:opacity-40 text-black font-bold rounded-lg text-xs transition-colors shrink-0"
              >
                {savingKey === 'coins_per_usd' ? '...' : 'حفظ'}
              </button>
            </div>
          </div>

          {/* Card 2: Host Diamond Rate */}
          <div className="bg-gradient-to-b from-emerald-500/10 to-transparent border border-emerald-500/20 rounded-xl p-4 space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold text-emerald-300">💎 نسبة استلام المضيف</span>
              <span className="text-[10px] bg-emerald-500/20 text-emerald-300 px-2 py-0.5 rounded-full font-mono">
                {hostRate}%
              </span>
            </div>
            <p className="text-[11px] text-slate-400">نسبة تحويل كوينز الهدايا لألماس للمضيف</p>
            <div className="flex items-center gap-2">
              <input
                type="number"
                step="0.5"
                min="0"
                max="100"
                placeholder={String(hostRate)}
                value={draftInputs['host_rate'] ?? ''}
                onChange={e => setDraftInputs(prev => ({ ...prev, host_rate: e.target.value }))}
                className="w-full bg-black/60 border border-white/10 rounded-lg px-2.5 py-1.5 text-xs text-white focus:outline-none focus:border-emerald-400"
              />
              <button
                disabled={savingKey === 'host_rate' || draftInputs['host_rate'] == null || draftInputs['host_rate'] === ''}
                onClick={() => quickSave('host_rate')}
                className="px-3 py-1.5 bg-emerald-500 hover:bg-emerald-600 disabled:opacity-40 text-black font-bold rounded-lg text-xs transition-colors shrink-0"
              >
                {savingKey === 'host_rate' ? '...' : 'حفظ'}
              </button>
            </div>
          </div>

          {/* Card 3: Agency Rate */}
          <div className="bg-gradient-to-b from-indigo-500/10 to-transparent border border-indigo-500/20 rounded-xl p-4 space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold text-indigo-300">🏢 عمولة صاحب الوكالة</span>
              <span className="text-[10px] bg-indigo-500/20 text-indigo-300 px-2 py-0.5 rounded-full font-mono">
                {agencyRate}%
              </span>
            </div>
            <p className="text-[11px] text-slate-400">نسبة راتب الوكيل من ألماس المضيف</p>
            <div className="flex items-center gap-2">
              <input
                type="number"
                step="0.5"
                min="0"
                max="100"
                placeholder={String(agencyRate)}
                value={draftInputs['agency_rate'] ?? ''}
                onChange={e => setDraftInputs(prev => ({ ...prev, agency_rate: e.target.value }))}
                className="w-full bg-black/60 border border-white/10 rounded-lg px-2.5 py-1.5 text-xs text-white focus:outline-none focus:border-indigo-400"
              />
              <button
                disabled={savingKey === 'agency_rate' || draftInputs['agency_rate'] == null || draftInputs['agency_rate'] === ''}
                onClick={() => quickSave('agency_rate')}
                className="px-3 py-1.5 bg-indigo-500 hover:bg-indigo-600 disabled:opacity-40 text-white font-bold rounded-lg text-xs transition-colors shrink-0"
              >
                {savingKey === 'agency_rate' ? '...' : 'حفظ'}
              </button>
            </div>
          </div>

          {/* Card 4: Target Unlocked Rate */}
          <div className="bg-gradient-to-b from-rose-500/10 to-transparent border border-rose-500/20 rounded-xl p-4 space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold text-rose-300">🎯 راتب فك التارجت</span>
              <span className="text-[10px] bg-rose-500/20 text-rose-300 px-2 py-0.5 rounded-full font-mono">
                {hostTargetExchangeRate}%
              </span>
            </div>
            <p className="text-[11px] text-slate-400">نسبة الراتب المتبقية عند فك ألماس التارجت</p>
            <div className="flex items-center gap-2">
              <input
                type="number"
                step="1"
                min="0"
                max="100"
                placeholder={String(hostTargetExchangeRate)}
                value={draftInputs['host_target_exchange_rate'] ?? ''}
                onChange={e => setDraftInputs(prev => ({ ...prev, host_target_exchange_rate: e.target.value }))}
                className="w-full bg-black/60 border border-white/10 rounded-lg px-2.5 py-1.5 text-xs text-white focus:outline-none focus:border-rose-400"
              />
              <button
                disabled={savingKey === 'host_target_exchange_rate' || draftInputs['host_target_exchange_rate'] == null || draftInputs['host_target_exchange_rate'] === ''}
                onClick={() => quickSave('host_target_exchange_rate')}
                className="px-3 py-1.5 bg-rose-500 hover:bg-rose-600 disabled:opacity-40 text-white font-bold rounded-lg text-xs transition-colors shrink-0"
              >
                {savingKey === 'host_target_exchange_rate' ? '...' : 'حفظ'}
              </button>
            </div>
          </div>

          {/* Card 5: Agency Commission Cycle */}
          <div className="bg-gradient-to-b from-blue-500/10 to-transparent border border-blue-500/20 rounded-xl p-4 space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold text-blue-300">📅 دورة صرف عمولة الوكيل</span>
              <span className="text-[10px] bg-blue-500/20 text-blue-300 px-2 py-0.5 rounded-full font-mono font-bold">
                {commissionPeriod === 'daily' ? 'يومي' : commissionPeriod === 'weekly' ? 'أسبوعي' : 'شهري'}
              </span>
            </div>
            <p className="text-[11px] text-slate-400">موعد اعتماد وإيداع عمولة الوكيل بالمحفظة</p>
            <div className="grid grid-cols-3 gap-1 bg-black/60 p-1 rounded-lg border border-white/10">
              {(['daily', 'weekly', 'monthly'] as const).map(p => (
                <button
                  key={p}
                  type="button"
                  disabled={savingPeriod}
                  onClick={() => handleSavePeriod(p)}
                  className={`py-1.5 text-xs font-bold rounded transition-all ${
                    commissionPeriod === p
                      ? 'bg-blue-500 text-white shadow-md'
                      : 'text-slate-400 hover:text-white hover:bg-white/5'
                  }`}
                >
                  {p === 'daily' ? 'يومي' : p === 'weekly' ? 'أسبوعي' : 'شهري'}
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* 2. Interactive Live Gift Distribution Simulator */}
      <div className="bg-gradient-to-br from-indigo-950/40 via-purple-950/20 to-slate-900 border border-indigo-500/30 rounded-2xl p-5 space-y-4">
        <div className="flex items-center justify-between flex-wrap gap-2">
          <div className="flex items-center gap-2">
            <span className="text-xl">🧮</span>
            <div>
              <h3 className="text-sm font-bold text-white">
                محاكي وحاسبة إرسال الهدايا والتوزيع الفوري (Live Gift Distribution Simulator)
              </h3>
              <p className="text-[11px] text-indigo-300">
                أدخل أي قيمة كوينز لتجربة كيفية تقسيمها فوراً بين المضيف والوكيل والنظام بناءً على الإعدادات الحالية
              </p>
            </div>
          </div>
          <div className="flex items-center gap-1.5 flex-wrap">
            <span className="text-[11px] text-slate-400 ml-1">أمثلة سريعة:</span>
            {[
              { label: '15,000 (1$)', val: 15000 },
              { label: '30,000 (2$)', val: 30000 },
              { label: '150,000 (تارجت 1)', val: 150000 },
              { label: '300,000 (20$)', val: 300000 },
              { label: '1,500,000 (100$)', val: 1500000 },
            ].map(preset => (
              <button
                key={preset.val}
                onClick={() => setSimCoins(preset.val)}
                className={`px-2.5 py-1 rounded-lg text-[11px] transition-colors border ${
                  simCoins === preset.val
                    ? 'bg-indigo-600 text-white border-indigo-400 font-bold'
                    : 'bg-black/40 text-slate-300 border-white/10 hover:bg-white/10'
                }`}
              >
                {preset.label}
              </button>
            ))}
          </div>
        </div>

        {/* Input Bar */}
        <div className="bg-black/50 border border-white/10 rounded-xl p-3 flex flex-wrap items-center gap-3">
          <div className="flex items-center gap-2 flex-1 min-w-[200px]">
            <span className="text-xs text-slate-300 whitespace-nowrap font-medium">🎁 قيمة الهدايا بالكوينز:</span>
            <input
              type="number"
              step="1000"
              min="0"
              value={simCoins}
              onChange={e => setSimCoins(Math.max(0, parseFloat(e.target.value) || 0))}
              className="w-full bg-[#161618] border border-indigo-500/40 rounded-lg px-3 py-1.5 text-sm text-amber-400 font-bold font-mono focus:outline-none focus:border-indigo-400"
              placeholder="15000"
            />
          </div>
          <div className="text-xs text-slate-400 bg-white/5 px-3 py-1.5 rounded-lg border border-white/5">
            سعر الصرف الحالي: <strong className="text-amber-400">1$ = {coinsPerUsd.toLocaleString()} كوينز</strong>
          </div>
        </div>

        {/* Breakdown Output Cards */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-3 text-xs">
          {/* Result 1: USD Value */}
          <div className="bg-black/40 border border-amber-500/20 rounded-xl p-3.5 space-y-1">
            <div className="text-slate-400 text-[10px]">💵 القيمة المقابلة بالدولار</div>
            <div className="text-lg font-black text-amber-400 font-mono">${simUsd}</div>
            <div className="text-[10px] text-slate-500">حسب سعر الصرف المعتمد</div>
          </div>

          {/* Result 2: Host Diamonds */}
          <div className="bg-black/40 border border-emerald-500/20 rounded-xl p-3.5 space-y-1">
            <div className="text-slate-400 text-[10px]">💎 ألماس المضيف المستلم</div>
            <div className="text-lg font-black text-emerald-400 font-mono">
              {simHostDiamonds.toLocaleString()} 💎
            </div>
            <div className="text-[10px] text-emerald-400/80 font-medium">
              نسبة استلام المضيف: {hostRate}%
            </div>
          </div>

          {/* Result 3: Agency Diamonds */}
          <div className="bg-black/40 border border-indigo-500/20 rounded-xl p-3.5 space-y-1">
            <div className="text-slate-400 text-[10px]">🏢 عمولة صاحب الوكالة</div>
            <div className="text-lg font-black text-indigo-400 font-mono">
              {simAgencyDiamonds.toLocaleString()} 💎
            </div>
            <div className="text-[10px] text-indigo-400/80 font-medium">
              نسبة عمولة الوكيل: {agencyRate}% (من ألماس المضيف)
            </div>
          </div>

          {/* Result 4: Target Unlocked Salary */}
          <div className="bg-black/40 border border-rose-500/20 rounded-xl p-3.5 space-y-1">
            <div className="text-slate-400 text-[10px]">🎯 الراتب عند فك التارجت</div>
            <div className="text-lg font-black text-rose-400 font-mono">${simTargetUnlockedSalary}</div>
            <div className="text-[10px] text-rose-400/80 font-medium">
              نسبة {hostTargetExchangeRate}% (خصم {100 - hostTargetExchangeRate}%)
            </div>
          </div>

          {/* Result 5: Platform Share */}
          <div className="bg-black/40 border border-cyan-500/20 rounded-xl p-3.5 space-y-1">
            <div className="text-slate-400 text-[10px]">🛡️ حصة المنصة المتبقية</div>
            <div className="text-lg font-black text-cyan-400 font-mono">{platformRate}%</div>
            <div className="text-[10px] text-slate-500">حصة النظام المعتمدة</div>
          </div>
        </div>
      </div>

      {/* 3. Detailed Financial Policy Guide Cards (Dynamic) */}
      <div className="bg-gradient-to-r from-amber-500/10 via-indigo-500/10 to-emerald-500/10 border border-amber-500/30 rounded-2xl p-5 space-y-4">
        <div className="flex items-center gap-2">
          <Sparkles className="w-5 h-5 text-amber-400" />
          <h3 className="text-sm font-bold text-white">
            🏦 سياسة توزيع الماس، التارجت، وعمولات وكلاء الشحن المعتمدة
          </h3>
        </div>
        
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-xs">
          {/* Card 1: Rate Calculation */}
          <div className="bg-black/40 border border-white/5 rounded-xl p-3.5 space-y-2">
            <div className="font-bold text-amber-300 flex items-center gap-1.5">
              <span>💎</span> معدل التحويل والهدايا المعتمد:
            </div>
            <p className="text-slate-300 leading-relaxed">
              كل <strong>1 دولار = {coinsPerUsd.toLocaleString()} كوينز</strong>.<br/>
              عند إرسال هدايا بقيمة {coinsPerUsd.toLocaleString()} كوينز:
            </p>
            <ul className="space-y-1 text-slate-300">
              <li className="flex justify-between">
                <span>• المضيف ({hostRate}%):</span>
                <strong className="text-emerald-400">
                  {Math.round(coinsPerUsd * (hostRate / 100)).toLocaleString()} ماس
                </strong>
              </li>
              <li className="flex justify-between">
                <span>• وكيل المضيف ({agencyRate}%):</span>
                <strong className="text-indigo-400">
                  {Math.round((coinsPerUsd * (hostRate / 100)) * (agencyRate / 100)).toLocaleString()} ماس
                </strong>
              </li>
            </ul>
            <div className="text-[10px] text-amber-400/90 bg-amber-500/10 p-2 rounded border border-amber-500/20">
              ⚡ يتم احتساب راتب وعمولة الوكيل تلقائياً دون خصمها من المضيف، وفي حال فك المضيف للألماس أو تحويله لكوينز لا تتأثر عمولة الوكيل نهائياً وتظل ثابتة في محفظته.
            </div>
          </div>

          {/* Card 2: Target 1 Distribution */}
          <div className="bg-black/40 border border-white/5 rounded-xl p-3.5 space-y-2">
            <div className="font-bold text-indigo-300 flex items-center gap-1.5">
              <span>🎯</span> سياسة تارجت المضيف وفك الألماس:
            </div>
            <ul className="space-y-1 text-slate-300">
              <li className="flex justify-between">
                <span>• فك الألماس إلى كوينز (1:1):</span>
                <strong className="text-emerald-400">100% كوينز كاملة</strong>
              </li>
              <li className="flex justify-between">
                <span>• التأثير على التارجت الشهري:</span>
                <strong className="text-rose-400">يُخصم الألماس المفكوك ويتراجع التارجت</strong>
              </li>
              <li className="flex justify-between">
                <span>• نسبة الراتب عند فك التارجت:</span>
                <strong className="text-amber-400">{hostTargetExchangeRate}% فقط (خصم {100 - hostTargetExchangeRate}% من الراتب)</strong>
              </li>
              <li className="flex justify-between border-t border-white/10 pt-1">
                <span>• عمولة وكيل المضيف ({agencyRate}%):</span>
                <strong className="text-indigo-400">محفوظة 100% دون أي خصم</strong>
              </li>
            </ul>
            <div className="text-[10px] text-cyan-400/90 bg-cyan-500/10 p-2 rounded border border-cyan-500/20">
              🔄 مثال تطبيقي: إذا كان تارجت المضيف 225,000 ماس وفك 100,000 ماس إلى كوينز: يستلم 100,000 كوينز كاملة، ويُخصم 100,000 من تارجته الشهري ليتبقى 125,000 ماس، ويتم احتساب راتب التارجت بنسبة {hostTargetExchangeRate}% فقط، وعمولة وكيل المضيف تبقى كما هي كاملة.
            </div>
          </div>

          {/* Card 3: Recharge Agent Conversion & Exchange System */}
          <div className="bg-black/40 border border-white/5 rounded-xl p-3.5 space-y-2">
            <div className="font-bold text-emerald-300 flex items-center gap-1.5">
              <span>⚡</span> تحويل الرواتب وصرف كوينز وكيل الشحن:
            </div>
            <p className="text-slate-300 leading-relaxed">
              • تُحوّل جميع رواتب المضيفين وأصحاب الوكالات والسوبر أدمن كـ <strong>ألماس حصراً</strong> إلى محفظة وكالة الشحن (agency_wallets.diamond_balance).<br/>
              • يقوم وكيل الشحن بصرف الألماس إلى كوينز شحن عبر زر "صرف" وباقات الصرف المعتمدة من الإدارة.<br/>
              • كوينز الوكالة مفصولة 100% عن محفظة المستخدم الشخصية ولا تختلط بها.
            </p>
          </div>
        </div>
      </div>

      {/* 4. Complete Commission Settings Table */}
      <div className="bg-[#141417] rounded-2xl border border-white/5 overflow-hidden">
        <div className="p-4 border-b border-white/5 flex items-center justify-between">
          <div>
            <h4 className="text-white text-xs font-bold">جدول نسب العمولات والتحويلات القابلة للتعديل</h4>
            <p className="text-slate-500 text-[11px] mt-0.5">يمكنك تعديل أي نسبة أو قيمة بالضغط على "Edit" وسيتم تطبيقها على الفور في الحسابات التلقائية</p>
          </div>
          <button onClick={load} className="px-3 py-1 bg-white/5 hover:bg-white/10 text-slate-300 rounded-lg text-xs flex items-center gap-1">
            <RefreshCw className="w-3 h-3" /> تحديث
          </button>
        </div>
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b border-white/5">
              <th className="text-left text-[10px] uppercase tracking-wider text-slate-500 font-bold p-3">المفتاح (Key)</th>
              <th className="text-left text-[10px] uppercase tracking-wider text-slate-500 font-bold p-3">الوصف والتفاصيل</th>
              <th className="text-left text-[10px] uppercase tracking-wider text-slate-500 font-bold p-3">القيمة المعتمدة</th>
              <th className="text-left text-[10px] uppercase tracking-wider text-slate-500 font-bold p-3">إجراء</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={4} className="text-center py-12 text-slate-500">جاري التحميل...</td></tr>
            ) : settings.map(s => {
              const isCoinsKey = s.key === 'coins_per_usd';
              const isDiamondsKey = s.key === 'first_target_diamonds';
              return (
                <tr key={s.id} className="border-b border-white/5 hover:bg-white/5">
                  <td className="p-3 text-white font-mono">{s.key}</td>
                  <td className="p-3 text-slate-300">{descKeyMap[s.key] || s.description || s.key}</td>
                  <td className="p-3">
                    <span className="text-amber-400 font-bold">
                      {isCoinsKey
                        ? `${s.value.toLocaleString()} كوينز / 1$`
                        : isDiamondsKey
                          ? `${s.value.toLocaleString()} ماس`
                          : `${s.value}%`}
                    </span>
                  </td>
                  <td className="p-3">
                    <InlineEdit value={s.value} onSave={v => handleUpdate(s.id, v)} />
                  </td>
                </tr>
              );
            })}
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

/* =============================================================
   TRANSFER HOST MODAL (نقل المضيف لوكالة أخرى وتصفير التارجت)
   ============================================================= */
function TransferHostModal({
  member,
  currentAgency,
  allAgencies,
  onClose,
  onSuccess,
}: {
  member: HostAgencyMemberModel;
  currentAgency: HostAgencyModel;
  allAgencies: HostAgencyModel[];
  onClose: () => void;
  onSuccess: () => void;
}) {
  const [targetAgencyId, setTargetAgencyId] = useState<string>('');
  const [transferring, setTransferring] = useState(false);
  const otherAgencies = allAgencies.filter(a => a.id !== currentAgency.id);

  const handleTransfer = async () => {
    if (!targetAgencyId) {
      alert('يرجى اختيار الوكالة المستهدفة للنقل');
      return;
    }
    const targetAg = allAgencies.find(a => a.id === targetAgencyId);
    if (!confirm(`هل أنت متأكد من نقل المضيف (${member.user_name || member.custom_id}) من وكالة "${currentAgency.name}" إلى وكالة "${targetAg?.name}"؟\n\nتنبيه: سيتم تصفير تارجت الألماس الشهري الخاص به بالكامل لهذا الشهر فوراً (0 💎).`)) {
      return;
    }
    setTransferring(true);
    const res = await transferAgencyMember(
      member.user_id,
      currentAgency.id,
      targetAgencyId,
      currentAgency.name,
      targetAg?.name
    );
    setTransferring(false);
    alert(res.message);
    if (res.success) {
      onSuccess();
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="bg-[#18181b] border border-indigo-500/30 rounded-2xl max-w-lg w-full p-6 space-y-5 shadow-2xl">
        <div className="flex items-center justify-between border-b border-white/10 pb-3">
          <div className="flex items-center gap-2">
            <ArrowRightLeft className="w-5 h-5 text-indigo-400" />
            <h3 className="text-white font-bold text-sm">نقل المضيف إلى وكالة أخرى</h3>
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-white text-sm">✕</button>
        </div>

        {/* Member Preview */}
        <div className="flex items-center gap-3 p-3 bg-white/5 rounded-xl border border-white/10">
          <img
            src={member.avatar_url || `https://ui-avatars.com/api/?name=${encodeURIComponent(member.user_name || 'Host')}&background=random`}
            alt=""
            className="w-12 h-12 rounded-full object-cover border border-indigo-400/40"
          />
          <div className="space-y-0.5">
            <div className="text-white font-bold text-xs">{member.user_name || 'مضيف'}</div>
            <div className="text-[11px] text-cyan-400 font-mono font-bold">ID: #{member.custom_id || member.user_id?.slice(0, 8)}</div>
            <div className="text-[10px] text-slate-400">الوكالة الحالية: <span className="text-slate-200 font-bold">{currentAgency.name}</span></div>
          </div>
        </div>

        {/* Warning Callout */}
        <div className="p-3 bg-amber-500/10 border border-amber-500/30 rounded-xl space-y-1">
          <div className="text-amber-400 font-bold text-xs flex items-center gap-1.5">
            <AlertTriangle className="w-4 h-4 shrink-0" />
            <span>تنبيه تصفير التارجت الشهري:</span>
          </div>
          <p className="text-[11px] text-amber-200/90 leading-relaxed">
            عند النقل، سيتم نقل ارتباط المضيف فوراً للوكالة الجديدة، و<strong>تصفير تارجت الألماس الشهري الخاص به بالكامل لهذا الشهر (0 💎)</strong> لبدء دورة جديدة، مع إرسال إشعار فوري داخل نظام التطبيق لإبلاغ المضيف.
          </p>
        </div>

        {/* Select Target Agency */}
        <div className="space-y-1.5">
          <label className="text-xs text-slate-300 font-bold block">اختر الوكالة المستهدفة للنقل إليها *</label>
          {otherAgencies.length === 0 ? (
            <p className="text-xs text-rose-400">لا توجد وكالات أخرى متاحة للنقل إليها.</p>
          ) : (
            <select
              value={targetAgencyId}
              onChange={e => setTargetAgencyId(e.target.value)}
              className="w-full bg-[#121214] border border-white/15 rounded-xl p-2.5 text-xs text-white focus:outline-none focus:border-indigo-500"
            >
              <option value="">-- اضغط لاختيار الوكالة المستهدفة --</option>
              {otherAgencies.map(a => (
                <option key={a.id} value={a.id}>
                  {a.name} ({a.member_count ?? 0} أعضاء) - المالك: {a.owner_name}
                </option>
              ))}
            </select>
          )}
        </div>

        {/* Action Buttons */}
        <div className="flex justify-end gap-2 pt-2 border-t border-white/10">
          <button onClick={onClose} className="px-4 py-2 text-xs text-slate-400 hover:text-white">إلغاء</button>
          <button
            onClick={handleTransfer}
            disabled={transferring || !targetAgencyId}
            className="px-5 py-2 bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-white rounded-xl text-xs font-bold transition-all flex items-center gap-1.5 shadow-lg shadow-indigo-600/30"
          >
            <ArrowRightLeft className="w-3.5 h-3.5" />
            {transferring ? 'جاري النقل...' : 'تأكيد النقل وتصفير التارجت'}
          </button>
        </div>
      </div>
    </div>
  );
}

/* =============================================================
   HOST RECHARGE HISTORY & REFUND MODAL
   ============================================================= */
function HostRechargeHistoryModal({
  member,
  onClose,
}: {
  member: HostAgencyMemberModel;
  onClose: () => void;
}) {
  const [records, setRecords] = useState<HostRechargeRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [refundingTx, setRefundingTx] = useState<HostRechargeRecord | null>(null);
  const [refunding, setRefunding] = useState(false);
  const [memberCoins, setMemberCoins] = useState<number>(member.coins || 0);

  const load = async () => {
    setLoading(true);
    const recs = await getHostRechargeHistory(member.user_id);
    setRecords(recs);
    setLoading(false);
  };

  useEffect(() => {
    load();
  }, [member.user_id]);

  // Current month calculation
  const now = new Date();
  const currentMonthPrefix = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
  const thisMonthRecords = records.filter(r => r.created_at.startsWith(currentMonthPrefix));

  const totalMonthCoins = thisMonthRecords.reduce((sum, r) => sum + r.amount_coins, 0);
  const totalAgentCoins = thisMonthRecords.filter(r => r.source === 'agent').reduce((sum, r) => sum + r.amount_coins, 0);
  const totalAdminCoins = thisMonthRecords.filter(r => r.source === 'admin').reduce((sum, r) => sum + r.amount_coins, 0);

  const handleConfirmRefund = async () => {
    if (!refundingTx) return;
    setRefunding(true);
    const res = await refundAgentRechargeTransaction(
      refundingTx.id,
      refundingTx.agent_id || '',
      refundingTx.target_uid,
      refundingTx.amount_coins,
      member.custom_id,
      refundingTx.agent_custom_id
    );
    setRefunding(false);
    alert(res.message);
    if (res.success) {
      setMemberCoins(prev => Math.max(0, prev - refundingTx.amount_coins));
      setRefundingTx(null);
      load();
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="bg-[#18181b] border border-amber-500/30 rounded-2xl max-w-3xl w-full p-6 space-y-4 shadow-2xl max-h-[90vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-white/10 pb-3">
          <div className="flex items-center gap-3">
            <Coins className="w-5 h-5 text-amber-400" />
            <div>
              <h3 className="text-white font-bold text-sm">سجل الشحن الكامل للمضيف لهذا الشهر</h3>
              <p className="text-[11px] text-slate-400">تفاصيل جميع عمليات الشحن من الوكلاء والإدارة والمتجر مع خيار استرجاع الشحن الخاطئ</p>
            </div>
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-white text-sm">✕</button>
        </div>

        {/* Host Details Bar */}
        <div className="flex flex-wrap items-center justify-between gap-3 p-3 bg-white/5 rounded-xl border border-white/10">
          <div className="flex items-center gap-3">
            <img
              src={member.avatar_url || `https://ui-avatars.com/api/?name=${encodeURIComponent(member.user_name || 'Host')}&background=random`}
              alt=""
              className="w-10 h-10 rounded-full object-cover border border-amber-400/50"
            />
            <div>
              <div className="text-white font-bold text-xs">{member.user_name || 'مضيف'}</div>
              <div className="text-[11px] text-cyan-400 font-mono font-bold">ID: #{member.custom_id || member.user_id?.slice(0, 8)}</div>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <div className="text-left bg-amber-500/10 border border-amber-500/20 px-3 py-1.5 rounded-lg">
              <span className="text-[10px] text-slate-400 block">رصيد الكوينز الحالي</span>
              <span className="text-xs text-amber-400 font-bold font-mono">🪙 {memberCoins.toLocaleString()} عملة</span>
            </div>
            <div className="text-left bg-cyan-500/10 border border-cyan-500/20 px-3 py-1.5 rounded-lg">
              <span className="text-[10px] text-slate-400 block">ألماس الشهر الحالي</span>
              <span className="text-xs text-cyan-400 font-bold font-mono">💎 {(member.diamonds_earned_monthly ?? 0).toLocaleString()}</span>
            </div>
          </div>
        </div>

        {/* Quick Month Stats */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-2.5">
          <div className="bg-[#141416] p-3 rounded-xl border border-white/5">
            <span className="text-[10px] text-slate-400 block">إجمالي مشحون الشهر</span>
            <span className="text-sm font-bold text-amber-400 font-mono">🪙 {totalMonthCoins.toLocaleString()}</span>
          </div>
          <div className="bg-[#141416] p-3 rounded-xl border border-white/5">
            <span className="text-[10px] text-slate-400 block">شحن وكلاء الشحن</span>
            <span className="text-sm font-bold text-indigo-400 font-mono">🪙 {totalAgentCoins.toLocaleString()}</span>
          </div>
          <div className="bg-[#141416] p-3 rounded-xl border border-white/5">
            <span className="text-[10px] text-slate-400 block">شحن الإدارة المباشر</span>
            <span className="text-sm font-bold text-emerald-400 font-mono">🪙 {totalAdminCoins.toLocaleString()}</span>
          </div>
        </div>

        {/* Table / List */}
        <div className="flex-1 overflow-y-auto space-y-2 pr-1">
          {loading ? (
            <div className="py-12 text-center text-xs text-slate-400 flex items-center justify-center gap-2">
              <RefreshCw className="w-4 h-4 animate-spin text-amber-400" />
              <span>جاري تحميل سجل الشحن...</span>
            </div>
          ) : records.length === 0 ? (
            <div className="py-12 text-center text-xs text-slate-500">
              لا توجد أي حركات شحن مسجلة لهذا الحساب.
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-right text-xs">
                <thead>
                  <tr className="text-slate-400 border-b border-white/10 text-[11px]">
                    <th className="py-2 px-3">نوع المصدر</th>
                    <th className="py-2 px-3">القائم بالشحن</th>
                    <th className="py-2 px-3">الكوينز المشحونة</th>
                    <th className="py-2 px-3">التاريخ والوقت</th>
                    <th className="py-2 px-3">الحالة</th>
                    <th className="py-2 px-3 text-center">الإجراء</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-white/5">
                  {records.map(rec => (
                    <tr key={rec.id} className="hover:bg-white/[0.02] transition-colors">
                      <td className="py-2.5 px-3">
                        {rec.source === 'agent' ? (
                          <span className="px-2 py-0.5 rounded text-[10px] font-bold bg-indigo-500/20 text-indigo-300 border border-indigo-500/30">
                            وكيل شحن
                          </span>
                        ) : rec.source === 'admin' ? (
                          <span className="px-2 py-0.5 rounded text-[10px] font-bold bg-amber-500/20 text-amber-300 border border-amber-500/30">
                            الإدارة
                          </span>
                        ) : (
                          <span className="px-2 py-0.5 rounded text-[10px] font-bold bg-emerald-500/20 text-emerald-300 border border-emerald-500/30">
                            داخل التطبيق
                          </span>
                        )}
                      </td>
                      <td className="py-2.5 px-3">
                        {rec.source === 'agent' ? (
                          <div className="flex items-center gap-2">
                            {rec.agent_avatar && (
                              <img src={rec.agent_avatar} alt="" className="w-5 h-5 rounded-full object-cover" />
                            )}
                            <div>
                              <div className="text-white font-semibold text-[11px]">{rec.agent_name}</div>
                              {rec.agent_custom_id && (
                                <div className="text-[10px] text-cyan-400 font-mono">ID: #{rec.agent_custom_id}</div>
                              )}
                            </div>
                          </div>
                        ) : rec.source === 'admin' ? (
                          <span className="text-slate-300 text-[11px]">إدارة التطبيق</span>
                        ) : (
                          <span className="text-slate-400 text-[11px]">متجر العملات</span>
                        )}
                      </td>
                      <td className="py-2.5 px-3 font-mono font-bold text-amber-400">
                        +{rec.amount_coins.toLocaleString()} 🪙
                      </td>
                      <td className="py-2.5 px-3 text-[11px] text-slate-400">
                        {new Date(rec.created_at).toLocaleString('ar-EG', {
                          year: 'numeric',
                          month: 'numeric',
                          day: 'numeric',
                          hour: '2-digit',
                          minute: '2-digit',
                        })}
                      </td>
                      <td className="py-2.5 px-3">
                        {rec.is_refunded ? (
                          <span className="px-2 py-0.5 rounded text-[10px] bg-rose-500/20 text-rose-300 font-bold border border-rose-500/30">
                            مسترجعة ↩️
                          </span>
                        ) : (
                          <span className="px-2 py-0.5 rounded text-[10px] bg-emerald-500/20 text-emerald-300 font-bold border border-emerald-500/30">
                            مكتملة ✅
                          </span>
                        )}
                      </td>
                      <td className="py-2.5 px-3 text-center">
                        {rec.source === 'agent' ? (
                          rec.is_refunded ? (
                            <span className="text-[10px] text-slate-500">تم ردها</span>
                          ) : (
                            <button
                              onClick={() => setRefundingTx(rec)}
                              className="px-2.5 py-1 bg-rose-500/15 hover:bg-rose-500/25 border border-rose-500/30 text-rose-300 rounded-lg text-[10px] font-bold flex items-center gap-1 mx-auto transition-all"
                              title="إرجاع هذا الشحن الخاطئ وإعادة الكوينز للوكيل"
                            >
                              <RotateCcw className="w-3 h-3" />
                              <span>إرجاع الشحن ↩️</span>
                            </button>
                          )
                        ) : (
                          <span className="text-[10px] text-slate-600">—</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        {/* Confirmation Modal for Refund */}
        {refundingTx && (
          <div className="fixed inset-0 z-60 bg-black/85 backdrop-blur-md flex items-center justify-center p-4">
            <div className="bg-[#1c1c20] border border-rose-500/40 rounded-2xl max-w-md w-full p-5 space-y-4 shadow-2xl">
              <div className="flex items-center gap-2 text-rose-400 font-bold text-sm">
                <RotateCcw className="w-4 h-4" />
                <span>تأكيد استرجاع الشحن الخاطئ للوكيل</span>
              </div>

              <div className="p-3 bg-white/5 rounded-xl space-y-2 text-xs">
                <div className="flex justify-between border-b border-white/5 pb-1.5">
                  <span className="text-slate-400">الكوينز المراد استرجاعها:</span>
                  <span className="text-amber-400 font-mono font-bold">🪙 {refundingTx.amount_coins.toLocaleString()}</span>
                </div>
                <div className="flex justify-between border-b border-white/5 pb-1.5">
                  <span className="text-slate-400">المستخدم (سيتم الخصم منه):</span>
                  <span className="text-white font-bold">{member.user_name} (ID: #{member.custom_id})</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-400">وكيل الشحن (ستعاد إليه):</span>
                  <span className="text-indigo-300 font-bold">{refundingTx.agent_name} (ID: #{refundingTx.agent_custom_id})</span>
                </div>
              </div>

              <p className="text-[11px] text-rose-300 leading-relaxed bg-rose-500/10 p-2.5 rounded-lg border border-rose-500/20">
                ⚠️ سيتم خصم الكوينز فورياً من رصيد المستخدم وإعادتها بالكامل إلى محفظة وكيل الشحن، مع إرسال إشعار فوري داخل نظام التطبيق لكلا الطرفين لإبلاغهما بالاسترجاع.
              </p>

              <div className="flex justify-end gap-2 pt-2">
                <button
                  onClick={() => setRefundingTx(null)}
                  disabled={refunding}
                  className="px-4 py-2 text-xs text-slate-400 hover:text-white"
                >
                  إلغاء
                </button>
                <button
                  onClick={handleConfirmRefund}
                  disabled={refunding}
                  className="px-5 py-2 bg-rose-600 hover:bg-rose-700 disabled:opacity-50 text-white rounded-xl text-xs font-bold transition-all flex items-center gap-1.5 shadow-lg shadow-rose-600/30"
                >
                  <RotateCcw className="w-3.5 h-3.5" />
                  {refunding ? 'جاري الاسترجاع...' : 'تأكيد الخصم والاسترجاع'}
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Footer */}
        <div className="flex justify-end pt-2 border-t border-white/10">
          <button onClick={onClose} className="px-4 py-2 text-xs bg-slate-700 hover:bg-slate-600 text-white rounded-xl font-bold">
            إغلاق
          </button>
        </div>
      </div>
    </div>
  );
}

/* =============================================================
   AGENCY RECORD MODAL (سجل الوكالة وإدارة المضيفين)
   ============================================================= */
function AgencyRecordModal({
  agency,
  allAgencies,
  onClose,
}: {
  agency: HostAgencyModel;
  allAgencies: HostAgencyModel[];
  onClose: () => void;
}) {
  const [members, setMembers] = useState<HostAgencyMemberModel[]>([]);
  const [milestones, setMilestones] = useState<HostMilestoneModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [transferTarget, setTransferTarget] = useState<HostAgencyMemberModel | null>(null);
  const [rechargeTarget, setRechargeTarget] = useState<HostAgencyMemberModel | null>(null);

  const loadMembers = async () => {
    setLoading(true);
    const [m, ms] = await Promise.all([
      getHostAgencyMembers(agency.id),
      getHostMilestones(),
    ]);
    setMembers(m);
    setMilestones(ms);
    setLoading(false);
  };

  useEffect(() => {
    loadMembers();
  }, [agency.id]);

  const handleRemoveHost = async (m: HostAgencyMemberModel) => {
    if (confirm(`هل أنت متأكد من حذف المضيف (${m.user_name || m.custom_id}) من وكالة "${agency.name}"؟\nسيتم خروجه فوراً وإرسال إشعار رسمي له داخل التطبيق.`)) {
      const res = await removeAgencyMemberWithNotification(agency.id, m.user_id, agency.name, m.user_name);
      alert(res.message);
      loadMembers();
    }
  };

  const filteredMembers = members.filter(m => {
    if (!search.trim()) return true;
    const q = search.trim().toLowerCase();
    return (
      (m.user_name || '').toLowerCase().includes(q) ||
      (m.custom_id || '').toLowerCase().includes(q) ||
      (m.user_id || '').toLowerCase().includes(q)
    );
  });

  const totalCommissionDiamonds = members.reduce((sum, m) => {
    const stage = getMemberStageAndCommission(m, milestones, agency.commission_rate);
    return sum + stage.commissionDiamonds;
  }, 0);

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="bg-[#161619] border border-amber-500/30 rounded-2xl max-w-5xl w-full p-6 space-y-5 shadow-2xl max-h-[92vh] flex flex-col">
        {/* Modal Top Header */}
        <div className="flex items-center justify-between border-b border-white/10 pb-3">
          <div className="flex items-center gap-3">
            <img
              src={agency.photo_url || `https://ui-avatars.com/api/?name=${encodeURIComponent(agency.name)}&background=random`}
              alt=""
              className="w-11 h-11 rounded-xl object-cover border border-amber-400/40"
            />
            <div>
              <div className="flex items-center gap-2">
                <h3 className="text-white font-bold text-base">{agency.name}</h3>
                <span className="px-2 py-0.5 rounded text-[10px] bg-amber-500/20 text-amber-300 font-bold border border-amber-500/30 uppercase">
                  {agency.tier || 'bronze'}
                </span>
                <span className={`px-2 py-0.5 rounded text-[10px] font-bold ${agency.is_active ? 'bg-emerald-500/20 text-emerald-300' : 'bg-rose-500/20 text-rose-300'}`}>
                  {agency.is_active ? 'نشطة' : 'معطلة'}
                </span>
              </div>
              <p className="text-[11px] text-slate-400 font-mono">ID: {agency.id}</p>
            </div>
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-white text-base">✕</button>
        </div>

        {/* Agency Owner & Quick Stats */}
        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-5 gap-3">
          {/* Real In-App Owner ID Card */}
          <div className="md:col-span-2 bg-gradient-to-r from-amber-500/10 to-indigo-500/10 border border-amber-500/25 p-3 rounded-xl flex items-center justify-between">
            <div className="flex items-center gap-3">
              <img
                src={agency.owner_avatar || `https://ui-avatars.com/api/?name=${encodeURIComponent(agency.owner_name || 'Owner')}&background=random`}
                alt=""
                className="w-10 h-10 rounded-full object-cover border-2 border-amber-400/50"
              />
              <div>
                <div className="flex items-center gap-1.5">
                  <span className="text-xs font-bold text-white">{agency.owner_name || 'مالك الوكالة'}</span>
                  <span className="text-[10px] bg-amber-400/20 text-amber-300 px-1.5 py-0.5 rounded font-bold border border-amber-400/30">👑 مالك الوكالة</span>
                </div>
                <div className="text-[11px] text-emerald-400 font-mono font-bold">
                  الآيدي بالتطبيق: #{agency.owner_custom_id || (agency as any).ownerCustomId || agency.owner_id?.slice(0, 8)}
                </div>
              </div>
            </div>
            <div className="text-left text-[11px] text-slate-400">
              <span className="block text-slate-500 text-[10px]">عمولة الوكالة</span>
              <span className="text-amber-400 font-bold font-mono">
                {(() => {
                  const r = agency.commission_rate ?? 0.2;
                  const pct = r > 1.0 ? Math.round(r) : Math.round(r * 100);
                  return `${pct}%`;
                })()}
              </span>
            </div>
          </div>

          {/* Monthly Diamonds */}
          <div className="bg-[#1c1c20] p-3 rounded-xl border border-white/5 flex flex-col justify-center">
            <span className="text-[10px] text-slate-400">💎 ألماس الوكالة هذا الشهر</span>
            <span className="text-sm font-bold text-amber-400 font-mono">{(agency.monthly_diamonds ?? 0).toLocaleString()}</span>
          </div>

          {/* Total Agent Commission in Diamonds */}
          <div className="bg-[#1c1c20] p-3 rounded-xl border border-cyan-500/20 flex flex-col justify-center bg-cyan-500/5">
            <span className="text-[10px] text-cyan-300 font-semibold">💎 عمولة الوكيل المستحقة</span>
            <span className="text-sm font-bold text-cyan-400 font-mono">{totalCommissionDiamonds.toLocaleString()} 💎</span>
          </div>

          {/* Total Members */}
          <div className="bg-[#1c1c20] p-3 rounded-xl border border-white/5 flex flex-col justify-center">
            <span className="text-[10px] text-slate-400">👥 إجمالي الأعضاء الحقيقيين</span>
            <span className="text-sm font-bold text-indigo-400 font-mono">{members.length} عضو</span>
          </div>
        </div>

        {/* Search Bar */}
        <div className="flex items-center justify-between gap-3">
          <div className="text-xs font-bold text-white flex items-center gap-1.5">
            <Users className="w-4 h-4 text-indigo-400" />
            <span>سجل أعضاء ومضيفي الوكالة ({filteredMembers.length})</span>
          </div>
          <input
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder="بحث باسم المضيف أو الـ ID..."
            className="bg-[#121214] border border-white/10 rounded-xl px-3 py-1.5 text-xs text-white placeholder:text-slate-500 w-64 focus:outline-none focus:border-indigo-500"
          />
        </div>

        {/* Members Table */}
        <div className="flex-1 overflow-y-auto space-y-2 pr-1">
          {loading ? (
            <div className="py-12 text-center text-xs text-slate-400 flex items-center justify-center gap-2">
              <RefreshCw className="w-4 h-4 animate-spin text-indigo-400" />
              <span>جاري تحميل أعضاء الوكالة...</span>
            </div>
          ) : filteredMembers.length === 0 ? (
            <div className="py-12 text-center text-xs text-slate-500">
              لا يوجد أعضاء يطابقون البحث.
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-right text-xs">
                <thead>
                  <tr className="text-slate-400 border-b border-white/10 text-[11px]">
                    <th className="py-2.5 px-3">المضيف</th>
                    <th className="py-2.5 px-3">آيدي التطبيق (Custom ID)</th>
                    <th className="py-2.5 px-3">الرتبة</th>
                    <th className="py-2.5 px-3">ألماس هذا الشهر</th>
                    <th className="py-2.5 px-3">المرحلة / التارجت</th>
                    <th className="py-2.5 px-3">عمولة الوكيل بالماس 💎</th>
                    <th className="py-2.5 px-3">رصيد الكوينز</th>
                    <th className="py-2.5 px-3">تاريخ الانضمام</th>
                    <th className="py-2.5 px-3 text-center">الإجراءات</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-white/5">
                  {filteredMembers.map(m => (
                    <tr key={m.user_id} className="hover:bg-white/[0.02] transition-colors">
                      <td className="py-2.5 px-3">
                        <div className="flex items-center gap-2.5">
                          <img
                            src={m.avatar_url || `https://ui-avatars.com/api/?name=${encodeURIComponent(m.user_name || 'Host')}&background=random`}
                            alt=""
                            className="w-8 h-8 rounded-full object-cover border border-white/10 shrink-0"
                          />
                          <div>
                            <div className="text-white font-bold text-xs">{m.user_name || (m as any).userName || 'مضيف'}</div>
                            <div className="text-[10px] text-slate-500 font-mono">{(m.user_id || (m as any).userId)?.slice(0, 8)}</div>
                          </div>
                        </div>
                      </td>
                      <td className="py-2.5 px-3">
                        <span className="font-mono text-cyan-400 font-bold bg-cyan-500/10 px-2 py-0.5 rounded border border-cyan-500/20 text-xs">
                          ID: #{m.custom_id || (m as any).customId || (m.user_id || (m as any).userId)?.slice(0, 8)}
                        </span>
                      </td>
                      <td className="py-2.5 px-3">
                        {m.role === 'owner' ? (
                          <span className="px-2 py-0.5 rounded text-[10px] font-bold bg-amber-500/20 text-amber-300 border border-amber-500/30">👑 مالك</span>
                        ) : m.role === 'supervisor' ? (
                          <span className="px-2 py-0.5 rounded text-[10px] font-bold bg-cyan-500/20 text-cyan-300 border border-cyan-500/30">⭐ مشرف</span>
                        ) : (
                          <span className="px-2 py-0.5 rounded text-[10px] font-bold bg-indigo-500/20 text-indigo-300 border border-indigo-500/30">🎙️ مضيف</span>
                        )}
                      </td>
                      <td className="py-2.5 px-3 font-mono font-bold text-amber-400">
                        💎 {(m.diamonds_earned_monthly ?? (m as any).diamondsEarnedMonthly ?? (m as any).diamonds ?? 0).toLocaleString()}
                      </td>
                      <td className="py-2.5 px-3">
                        {(() => {
                          const stageInfo = getMemberStageAndCommission(m, milestones, agency.commission_rate);
                          return stageInfo.isReached ? (
                            <div className="flex flex-col">
                              <span className="font-bold text-emerald-400 text-xs bg-emerald-500/10 px-2 py-0.5 rounded border border-emerald-500/20 inline-block w-fit">
                                {stageInfo.stageTitle}
                              </span>
                              <span className="text-[10px] text-slate-400 font-mono mt-0.5">تارجت: {stageInfo.targetDiamonds.toLocaleString()} 💎</span>
                            </div>
                          ) : (
                            <div className="flex flex-col">
                              <span className="text-slate-500 text-xs">{stageInfo.stageTitle}</span>
                              <span className="text-[10px] text-slate-600 font-mono mt-0.5">تارجت: {stageInfo.targetDiamonds.toLocaleString()} 💎</span>
                            </div>
                          );
                        })()}
                      </td>
                      <td className="py-2.5 px-3 font-mono font-bold">
                        {(() => {
                          const stageInfo = getMemberStageAndCommission(m, milestones, agency.commission_rate);
                          return stageInfo.commissionDiamonds > 0 ? (
                            <div className="flex flex-col">
                              <span className="text-cyan-400 text-xs font-mono font-bold">💎 {stageInfo.commissionDiamonds.toLocaleString()}</span>
                              <span className="text-[10px] text-cyan-500/80 font-normal">{Math.round(stageInfo.rate * 100)}% من التارجت</span>
                            </div>
                          ) : (
                            <span className="text-slate-600 text-xs font-normal">0 💎</span>
                          );
                        })()}
                      </td>
                      <td className="py-2.5 px-3 font-mono text-amber-300">
                        🪙 {(m.coins ?? 0).toLocaleString()}
                      </td>
                      <td className="py-2.5 px-3 text-[11px] text-slate-400">
                        {(m.joined_at || (m as any).joinedAt) ? new Date(m.joined_at || (m as any).joinedAt).toLocaleDateString('ar-EG') : '—'}
                      </td>
                      <td className="py-2.5 px-3">
                        {m.role === 'owner' ? (
                          <div className="text-center text-[10px] text-amber-400 font-bold">مالك الوكالة</div>
                        ) : (
                          <div className="flex items-center justify-center gap-1.5">
                            {/* Transfer button */}
                            <button
                              onClick={() => setTransferTarget(m)}
                              className="px-2 py-1 bg-indigo-500/15 hover:bg-indigo-500/25 border border-indigo-500/30 text-indigo-300 rounded-lg text-[11px] font-bold flex items-center gap-1 transition-all"
                              title="نقل المضيف لوكالة أخرى وتصفير تارجته"
                            >
                              <ArrowRightLeft className="w-3 h-3" />
                              <span>نقل لوكالة أخرى</span>
                            </button>

                            {/* Remove button */}
                            <button
                              onClick={() => handleRemoveHost(m)}
                              className="px-2 py-1 bg-rose-500/15 hover:bg-rose-500/25 border border-rose-500/30 text-rose-300 rounded-lg text-[11px] font-bold flex items-center gap-1 transition-all"
                              title="حذف المضيف فوراً وإرسال إشعار له"
                            >
                              <Trash2 className="w-3 h-3" />
                              <span>حذف</span>
                            </button>

                            {/* Recharge history button */}
                            <button
                              onClick={() => setRechargeTarget(m)}
                              className="px-2 py-1 bg-amber-500/15 hover:bg-amber-500/25 border border-amber-500/30 text-amber-300 rounded-lg text-[11px] font-bold flex items-center gap-1 transition-all"
                              title="عرض سجل الشحن الشهري بالكامل مع إمكانية استرجاع الشحن"
                            >
                              <Coins className="w-3 h-3" />
                              <span>سجل الشحن</span>
                            </button>
                          </div>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        {/* Modals triggered from within AgencyRecordModal */}
        {transferTarget && (
          <TransferHostModal
            member={transferTarget}
            currentAgency={agency}
            allAgencies={allAgencies}
            onClose={() => setTransferTarget(null)}
            onSuccess={() => {
              setTransferTarget(null);
              loadMembers();
            }}
          />
        )}

        {rechargeTarget && (
          <HostRechargeHistoryModal
            member={rechargeTarget}
            onClose={() => setRechargeTarget(null)}
          />
        )}

        {/* Modal Footer */}
        <div className="flex justify-end pt-2 border-t border-white/10">
          <button onClick={onClose} className="px-5 py-2 text-xs bg-slate-700 hover:bg-slate-600 text-white rounded-xl font-bold">
            إغلاق السجل
          </button>
        </div>
      </div>
    </div>
  );
}

/* =============================================================
   AGENCY LEVELS, STORE REWARDS & EXP GROWTH TASKS TAB
   ============================================================= */
function AgencyLevelsTab() {
  const [activeSubTab, setActiveSubTab] = useState<'levels' | 'tasks'>('levels');
  const [levels, setLevels] = useState<AgencyLevelModel[]>([]);
  const [agencies, setAgencies] = useState<HostAgencyModel[]>([]);
  const [allStoreItems, setAllStoreItems] = useState<any[]>([]);
  const [tasks, setTasks] = useState<AgencyExpTaskConfig[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [savingTasks, setSavingTasks] = useState(false);
  const [msg, setMsg] = useState<{ type: 'success' | 'error'; text: string } | null>(null);

  // Form state for Level
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [formLevel, setFormLevel] = useState<number>(1);
  const [formTitle, setFormTitle] = useState('');
  const [formExp, setFormExp] = useState<number>(50000);
  const [formCoins, setFormCoins] = useState<number>(500);
  const [formDiamonds, setFormDiamonds] = useState<number>(0);
  const [formDesc, setFormDesc] = useState('');
  const [formRewardReason, setFormRewardReason] = useState('');
  const [formIcon, setFormIcon] = useState('');
  const [formStoreRewards, setFormStoreRewards] = useState<AgencyLevelRewardItem[]>([]);

  // Store Item Picker Modal state
  const [showItemPicker, setShowItemPicker] = useState(false);
  const [itemSearch, setItemSearch] = useState('');
  const [itemCategoryFilter, setItemCategoryFilter] = useState('all');

  // Reward distribution modal
  const [rewardLevel, setRewardLevel] = useState<AgencyLevelModel | null>(null);
  const [targetAgencyId, setTargetAgencyId] = useState('');
  const [distributing, setDistributing] = useState(false);
  const [distributeResult, setDistributeResult] = useState<string | null>(null);

  const loadData = async () => {
    setLoading(true);
    try {
      const [lvls, ags, expTasks, storeRes] = await Promise.all([
        getAgencyLevels(),
        getHostAgencies(),
        getAgencyExpTasks(),
        supabase.from('store_items').select('*'),
      ]);
      setLevels(lvls);
      setAgencies(ags);
      setTasks(expTasks);
      if (storeRes.data) {
        setAllStoreItems(storeRes.data);
      }
    } catch (e: any) {
      setMsg({ type: 'error', text: 'فشل تحميل بيانات مستويات الوكالة: ' + e?.message });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadData();
  }, []);

  const handleOpenAdd = () => {
    const nextLevel = levels.length > 0 ? Math.max(...levels.map(l => l.level)) + 1 : 1;
    setEditingId(null);
    setFormLevel(nextLevel);
    setFormTitle(`وكالة مستوى ${nextLevel}`);
    setFormExp(nextLevel * 100000);
    setFormCoins(nextLevel * 1000);
    setFormDiamonds(0);
    setFormDesc(`مكافأة ارتقاء لمستوى ${nextLevel}`);
    setFormRewardReason('مكافأة تشجيعية لتحقيق نمو رائع للوكالة والوصول للمستوى المطلوب');
    setFormIcon('');
    setFormStoreRewards([]);
    setShowForm(true);
    setMsg(null);
  };

  const handleOpenEdit = (lvl: AgencyLevelModel) => {
    setEditingId(lvl.id);
    setFormLevel(lvl.level);
    setFormTitle(lvl.title);
    setFormExp(lvl.required_exp);
    setFormCoins(lvl.reward_coins_per_host);
    setFormDiamonds(lvl.reward_diamonds_per_host || 0);
    setFormDesc(lvl.description || '');
    setFormRewardReason(lvl.reward_reason || 'مكافأة ارتقاء مستوى الوكالة وتكريم للمضيفين');
    setFormIcon(lvl.icon_url || '');
    setFormStoreRewards(Array.isArray(lvl.store_reward_items) ? [...lvl.store_reward_items] : []);
    setShowForm(true);
    setMsg(null);
  };

  const handleSaveLevel = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!formTitle.trim()) {
      setMsg({ type: 'error', text: 'يرجى إدخال اسم المستوى' });
      return;
    }

    setSaving(true);
    try {
      let updated: AgencyLevelModel[];
      if (editingId) {
        updated = levels.map(l => l.id === editingId ? {
          ...l,
          level: Number(formLevel),
          title: formTitle.trim(),
          required_exp: Number(formExp),
          reward_coins_per_host: Number(formCoins),
          reward_diamonds_per_host: Number(formDiamonds),
          store_reward_items: formStoreRewards,
          reward_reason: formRewardReason.trim(),
          description: formDesc.trim(),
          icon_url: formIcon.trim(),
          updated_at: new Date().toISOString(),
        } : l);
      } else {
        const newLvl: AgencyLevelModel = {
          id: `lvl_${Date.now()}`,
          level: Number(formLevel),
          title: formTitle.trim(),
          required_exp: Number(formExp),
          reward_coins_per_host: Number(formCoins),
          reward_diamonds_per_host: Number(formDiamonds),
          store_reward_items: formStoreRewards,
          reward_reason: formRewardReason.trim(),
          description: formDesc.trim(),
          icon_url: formIcon.trim(),
          created_at: new Date().toISOString(),
        };
        updated = [...levels, newLvl];
      }

      await saveAgencyLevels(updated);
      setLevels(updated.sort((a, b) => a.level - b.level));
      setShowForm(false);
      setEditingId(null);
      setMsg({ type: 'success', text: 'تم حفظ المستوى ومكافآت المتجر بنجاح!' });
    } catch (e: any) {
      setMsg({ type: 'error', text: 'تعذر حفظ المستوى: ' + e?.message });
    } finally {
      setSaving(false);
    }
  };

  const handleDeleteLevel = async (id: string) => {
    if (!window.confirm('هل أنت متأكد من حذف هذا المستوى؟')) return;
    setSaving(true);
    try {
      const updated = levels.filter(l => l.id !== id);
      await saveAgencyLevels(updated);
      setLevels(updated);
      setMsg({ type: 'success', text: 'تم حذف المستوى بنجاح!' });
    } catch (e: any) {
      setMsg({ type: 'error', text: 'تعذر الحذف: ' + e?.message });
    } finally {
      setSaving(false);
    }
  };

  const handleSaveExpTasks = async () => {
    setSavingTasks(true);
    try {
      const ok = await saveAgencyExpTasks(tasks);
      if (ok) {
        setMsg({ type: 'success', text: 'تم حفظ إعدادات مهام نمو نقاط الخبرة (EXP) بنجاح!' });
      } else {
        setMsg({ type: 'error', text: 'فشل حفظ مهام النمو' });
      }
    } catch (e: any) {
      setMsg({ type: 'error', text: 'خطأ أثناء الحفظ: ' + e?.message });
    } finally {
      setSavingTasks(false);
    }
  };

  const handleToggleStoreItem = (item: any) => {
    const id = item.item_id || item.id;
    const exists = formStoreRewards.some(r => r.item_id === id);
    if (exists) {
      setFormStoreRewards(formStoreRewards.filter(r => r.item_id !== id));
    } else {
      const newItem: AgencyLevelRewardItem = {
        item_id: id,
        item_name: item.name || item.name_ar || 'عنصر متجر',
        item_icon: item.icon_url || item.iconAsset || item.icon || '',
        category: item.category || 'frame',
        days: 7, // default 7 days
        svga_asset: item.svga_asset || item.svgaAsset || '',
        video_asset: item.video_asset || item.videoAsset || '',
      };
      setFormStoreRewards([...formStoreRewards, newItem]);
    }
  };

  const handleUpdateItemDays = (itemId: string, days: number) => {
    setFormStoreRewards(formStoreRewards.map(r => r.item_id === itemId ? { ...r, days } : r));
  };

  const handleDistributeReward = async () => {
    if (!rewardLevel || !targetAgencyId) {
      setMsg({ type: 'error', text: 'يرجى اختيار الوكالة المستحقة' });
      return;
    }
    setDistributing(true);
    setDistributeResult(null);
    try {
      const res = await distributeAgencyLevelReward(targetAgencyId, rewardLevel);
      setDistributeResult(`✅ تم بنجاح صرف المكافأة لـ ${res.count} مضيف نشط بالوكالة!\n🪙 إجمالي الكوينز: ${res.coins.toLocaleString()} كوينز\n🎁 إجمالي عناصر المتجر المودعة بالحقائب: ${res.storeItemsGranted} عنصر\nتم ترقية مستوى الوكالة وإرسال إشعارات التهنئة لجميع المضيفين.`);
      loadData();
    } catch (e: any) {
      setDistributeResult(`❌ فشل توزيع المكافأة: ${e?.message}`);
    } finally {
      setDistributing(false);
    }
  };

  // Filtered store items for the picker modal
  const filteredStoreItems = allStoreItems.filter(item => {
    const nameMatch = !itemSearch ||
      (item.name || '').toLowerCase().includes(itemSearch.toLowerCase()) ||
      (item.name_ar || '').toLowerCase().includes(itemSearch.toLowerCase()) ||
      (item.item_id || item.id || '').toLowerCase().includes(itemSearch.toLowerCase());
    const catMatch = itemCategoryFilter === 'all' || (item.category || '').toLowerCase() === itemCategoryFilter.toLowerCase();
    return nameMatch && catMatch;
  });

  const getTaskIcon = (iconName: string) => {
    switch (iconName) {
      case 'Mic': return <Mic className="w-5 h-5 text-amber-400" />;
      case 'Dices': return <Dices className="w-5 h-5 text-purple-400" />;
      case 'CreditCard': return <CreditCard className="w-5 h-5 text-emerald-400" />;
      case 'Gift': return <Gift className="w-5 h-5 text-rose-400" />;
      default: return <Zap className="w-5 h-5 text-cyan-400" />;
    }
  };

  if (loading) {
    return (
      <div className="p-12 text-center text-slate-400">
        <RefreshCw className="w-6 h-6 animate-spin mx-auto mb-2 text-indigo-400" />
        جاري تحميل مستويات ونقاط خبرة الوكالة...
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header and Sub-Tabs Navigation */}
      <div className="p-5 rounded-2xl bg-gradient-to-r from-amber-500/10 via-indigo-500/10 to-purple-500/10 border border-amber-500/20 flex flex-wrap items-center justify-between gap-4">
        <div>
          <h3 className="text-white text-base font-bold flex items-center gap-2">
            <Award className="w-5 h-5 text-amber-400" />
            إدارة مستويات ونقاط خبرة الوكالة (EXP) ومكافآت المضيفين
          </h3>
          <p className="text-slate-400 text-xs mt-1">
            تحكم بنقاط الخبرة المطلوبة، ومكافآت الكوينز والألماس وعناصر المتجر المتعددة لكل مستوى، واضبط مهام النمو (المقعد، الحظ، الشحن، الهدايا).
          </p>
        </div>
        <div className="flex items-center gap-2">
          {activeSubTab === 'levels' && (
            <button
              onClick={handleOpenAdd}
              className="flex items-center gap-2 px-4 py-2 bg-gradient-to-r from-amber-500 to-amber-600 hover:from-amber-600 hover:to-amber-700 text-black font-bold text-xs rounded-xl shadow-lg transition-all"
            >
              <Plus className="w-4 h-4" />
              إضافة مستوى وكالة جديد
            </button>
          )}
          {activeSubTab === 'tasks' && (
            <button
              onClick={handleSaveExpTasks}
              disabled={savingTasks}
              className="flex items-center gap-2 px-4 py-2 bg-gradient-to-r from-emerald-500 to-emerald-600 hover:from-emerald-600 hover:to-emerald-700 text-black font-bold text-xs rounded-xl shadow-lg transition-all"
            >
              {savingTasks ? <RefreshCw className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
              حفظ مهام نمو الـ EXP
            </button>
          )}
        </div>
      </div>

      {/* Sub Tabs Selector */}
      <div className="flex items-center gap-2 border-b border-white/10 pb-2">
        <button
          onClick={() => setActiveSubTab('levels')}
          className={`flex items-center gap-2 px-4 py-2 text-xs font-bold rounded-xl transition-all ${
            activeSubTab === 'levels'
              ? 'bg-amber-500 text-black shadow-lg shadow-amber-500/20'
              : 'text-slate-400 hover:text-white hover:bg-white/5'
          }`}
        >
          <Award className="w-4 h-4" />
          مستويات الوكالة ومكافآت المتجر والكوينز ({levels.length})
        </button>
        <button
          onClick={() => setActiveSubTab('tasks')}
          className={`flex items-center gap-2 px-4 py-2 text-xs font-bold rounded-xl transition-all ${
            activeSubTab === 'tasks'
              ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-600/20'
              : 'text-slate-400 hover:text-white hover:bg-white/5'
          }`}
        >
          <Zap className="w-4 h-4" />
          مهام نمو نقاط الخبرة (EXP Tasks) (المقعد، الحظ، الشحن، الهدايا)
        </button>
      </div>

      {msg && (
        <div className={`p-3 rounded-xl text-xs flex items-center gap-2 ${msg.type === 'success' ? 'bg-emerald-500/10 border border-emerald-500/20 text-emerald-400' : 'bg-rose-500/10 border border-rose-500/20 text-rose-400'}`}>
          {msg.type === 'success' ? <CheckCircle2 className="w-4 h-4" /> : <AlertTriangle className="w-4 h-4" />}
          <span>{msg.text}</span>
        </div>
      )}

      {/* ═══════════ SUB-TAB 1: LEVELS & STORE REWARDS ═══════════ */}
      {activeSubTab === 'levels' && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {levels.map((lvl) => {
            const storeRewards = Array.isArray(lvl.store_reward_items) ? lvl.store_reward_items : [];
            return (
              <div
                key={lvl.id}
                className="p-5 rounded-2xl bg-[#141417] border border-white/5 hover:border-amber-500/30 transition-all flex flex-col justify-between"
              >
                <div>
                  <div className="flex items-center justify-between mb-3">
                    <span className="px-2.5 py-1 rounded-lg text-xs font-black bg-amber-500/20 text-amber-300 border border-amber-500/30">
                      المستوى {lvl.level}
                    </span>
                    <div className="flex items-center gap-1.5">
                      <button
                        onClick={() => handleOpenEdit(lvl)}
                        className="p-1.5 rounded-lg bg-white/5 hover:bg-white/10 text-slate-300"
                        title="تعديل المستوى والمكافآت"
                      >
                        <Edit3 className="w-3.5 h-3.5" />
                      </button>
                      <button
                        onClick={() => handleDeleteLevel(lvl.id)}
                        className="p-1.5 rounded-lg bg-rose-500/10 hover:bg-rose-500/20 text-rose-400"
                        title="حذف"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </div>

                  <h4 className="text-white font-bold text-base mb-1">{lvl.title}</h4>
                  <p className="text-slate-400 text-xs mb-2">{lvl.description || 'لا يوجد وصف للمستوى'}</p>

                  {lvl.reward_reason && (
                    <div className="mb-3 p-2 bg-amber-500/5 border border-amber-500/20 rounded-lg text-[11px] text-amber-300/90 flex items-start gap-1.5">
                      <Sparkles className="w-3.5 h-3.5 text-amber-400 shrink-0 mt-0.5" />
                      <span><strong>سبب المكافأة:</strong> {lvl.reward_reason}</span>
                    </div>
                  )}

                  {/* Requirements & Currencies */}
                  <div className="space-y-2 py-3 border-y border-white/5 text-xs">
                    <div className="flex justify-between items-center">
                      <span className="text-slate-400">نقاط الخبرة المطلوبة:</span>
                      <span className="text-indigo-400 font-mono font-bold">⚡ {lvl.required_exp.toLocaleString()} EXP</span>
                    </div>
                    <div className="flex justify-between items-center">
                      <span className="text-slate-400">مكافأة الكوينز لكل مضيف:</span>
                      <span className="text-amber-400 font-bold">🪙 {lvl.reward_coins_per_host.toLocaleString()} كوين</span>
                    </div>
                    {lvl.reward_diamonds_per_host ? (
                      <div className="flex justify-between items-center">
                        <span className="text-slate-400">مكافأة الماس لكل مضيف:</span>
                        <span className="text-cyan-400 font-bold">💎 {lvl.reward_diamonds_per_host.toLocaleString()}</span>
                      </div>
                    ) : null}
                  </div>

                  {/* Store Items Rewards Section */}
                  <div className="mt-3">
                    <div className="flex items-center justify-between text-xs mb-2">
                      <span className="text-slate-300 font-bold flex items-center gap-1">
                        <Package className="w-3.5 h-3.5 text-purple-400" />
                        مكافآت المتجر ({storeRewards.length}):
                      </span>
                    </div>

                    {storeRewards.length === 0 ? (
                      <div className="p-2.5 rounded-xl bg-black/20 border border-dashed border-white/10 text-center text-[11px] text-slate-500">
                        لم يتم اختيار عناصر من المتجر لهذا المستوى
                      </div>
                    ) : (
                      <div className="flex flex-wrap gap-1.5 max-h-36 overflow-y-auto p-1 bg-black/20 rounded-xl border border-white/5">
                        {storeRewards.map((it, idx) => (
                          <div
                            key={idx}
                            className="flex items-center gap-1.5 px-2 py-1 rounded-lg bg-white/5 border border-white/10 text-[11px]"
                          >
                            {it.item_icon ? (
                              <img src={it.item_icon} alt="" className="w-5 h-5 rounded object-contain" />
                            ) : (
                              <Package className="w-4 h-4 text-purple-400" />
                            )}
                            <span className="text-white font-medium max-w-[90px] truncate">{it.item_name}</span>
                            <span className="px-1.5 py-0.5 rounded text-[10px] bg-purple-500/20 text-purple-300 font-bold">
                              {it.days === 0 ? 'دائم' : `${it.days} يوم`}
                            </span>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                </div>

                <div className="mt-4 pt-3 border-t border-white/5">
                  <button
                    onClick={() => {
                      setRewardLevel(lvl);
                      setTargetAgencyId(agencies[0]?.id || '');
                      setDistributeResult(null);
                    }}
                    className="w-full py-2 bg-gradient-to-r from-indigo-500/20 to-purple-500/20 hover:from-indigo-500/30 hover:to-purple-500/30 text-indigo-300 font-bold text-xs rounded-xl border border-indigo-500/30 transition-all flex items-center justify-center gap-1.5"
                  >
                    <Sparkles className="w-3.5 h-3.5" />
                    صرف مكافأة هذا المستوى للوكالة الآن
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* ═══════════ SUB-TAB 2: EXP GROWTH TASKS ═══════════ */}
      {activeSubTab === 'tasks' && (
        <div className="space-y-4">
          <div className="p-4 rounded-xl bg-indigo-500/10 border border-indigo-500/20 text-xs text-indigo-300 space-y-1">
            <p className="font-bold">⚡ كيف تنمو مستويات الوكالة في نقاط الخبرة (EXP)؟</p>
            <p className="text-slate-300">
              يقوم مضيفو وأعضاء الوكالة بجمع نقاط الـ EXP للوكالة من خلال المهام الأربع التالية. يمكنك هنا تعيين معدل احتساب النقاط لكل مهمة، وتحديد الحد الأقصى اليومي، وتفعيل أو تعطيل أي مهمة بما يناسب سياسة تطبيقك.
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {tasks.map((task, index) => (
              <div
                key={task.key}
                className="p-5 rounded-2xl bg-[#141417] border border-white/5 hover:border-indigo-500/30 transition-all space-y-4"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="flex items-center gap-3">
                    <div className="p-2.5 rounded-xl bg-white/5 border border-white/10">
                      {getTaskIcon(task.icon_name)}
                    </div>
                    <div>
                      <h4 className="text-white font-bold text-sm">{task.title_ar}</h4>
                      <p className="text-slate-400 text-xs mt-0.5">{task.title}</p>
                    </div>
                  </div>

                  {/* Enable / Disable Toggle */}
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input
                      type="checkbox"
                      checked={task.is_enabled}
                      onChange={(e) => {
                        const updated = [...tasks];
                        updated[index] = { ...updated[index], is_enabled: e.target.checked };
                        setTasks(updated);
                      }}
                      className="sr-only peer"
                    />
                    <div className="w-9 h-5 bg-slate-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-white after:border-slate-300 after:border after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:bg-emerald-500"></div>
                  </label>
                </div>

                <p className="text-slate-300 text-xs leading-relaxed bg-black/20 p-2.5 rounded-xl border border-white/5">
                  {task.description}
                </p>

                <div className="grid grid-cols-2 gap-3 text-xs">
                  <div>
                    <label className="text-slate-400 block mb-1">معدل نقاط الخبرة (EXP)</label>
                    <input
                      type="number"
                      min={1}
                      value={task.exp_per_unit}
                      onChange={(e) => {
                        const updated = [...tasks];
                        updated[index] = { ...updated[index], exp_per_unit: parseInt(e.target.value) || 1 };
                        setTasks(updated);
                      }}
                      className="w-full px-3 py-2 bg-black/40 border border-white/10 rounded-xl text-indigo-400 font-bold font-mono text-xs"
                    />
                  </div>

                  <div>
                    <label className="text-slate-400 block mb-1">الحد الأقصى اليومي (0 = غير محدود)</label>
                    <input
                      type="number"
                      min={0}
                      step={100}
                      value={task.daily_max_exp}
                      onChange={(e) => {
                        const updated = [...tasks];
                        updated[index] = { ...updated[index], daily_max_exp: parseInt(e.target.value) || 0 };
                        setTasks(updated);
                      }}
                      className="w-full px-3 py-2 bg-black/40 border border-white/10 rounded-xl text-amber-400 font-bold font-mono text-xs"
                    />
                  </div>
                </div>

                <div>
                  <label className="text-slate-400 block mb-1 text-xs">نص الشرح الظاهر للمستخدمين في شاشة الوكالة</label>
                  <input
                    type="text"
                    value={task.exp_rate_desc}
                    onChange={(e) => {
                      const updated = [...tasks];
                      updated[index] = { ...updated[index], exp_rate_desc: e.target.value };
                      setTasks(updated);
                    }}
                    className="w-full px-3 py-2 bg-black/40 border border-white/10 rounded-xl text-white text-xs"
                    placeholder="مثال: 10 EXP لكل 10 دقائق جلوس على المايك"
                  />
                </div>
              </div>
            ))}
          </div>

          <div className="flex justify-end pt-2">
            <button
              onClick={handleSaveExpTasks}
              disabled={savingTasks}
              className="flex items-center gap-2 px-6 py-2.5 bg-gradient-to-r from-emerald-500 to-emerald-600 hover:from-emerald-600 hover:to-emerald-700 text-black font-bold text-xs rounded-xl shadow-lg transition-all"
            >
              {savingTasks ? <RefreshCw className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
              حفظ جميع إعدادات مهام النمو (EXP Tasks)
            </button>
          </div>
        </div>
      )}

      {/* ═══════════ ADD / EDIT LEVEL MODAL ═══════════ */}
      {showForm && (
        <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4 overflow-y-auto">
          <div className="bg-[#18181b] border border-white/10 rounded-2xl w-full max-w-lg p-6 space-y-4 my-8">
            <div className="flex items-center justify-between border-b border-white/10 pb-3">
              <h3 className="text-white text-base font-bold flex items-center gap-2">
                <Award className="w-5 h-5 text-amber-400" />
                {editingId ? 'تعديل مستوى الوكالة ومكافآت المضيفين' : 'إضافة مستوى وكالة جديد ومكافآته'}
              </h3>
              <button
                onClick={() => setShowForm(false)}
                className="p-1 rounded-lg text-slate-400 hover:text-white hover:bg-white/10"
              >
                <XCircle className="w-5 h-5" />
              </button>
            </div>

            <form onSubmit={handleSaveLevel} className="space-y-4">
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs text-slate-300 block mb-1">رقم المستوى</label>
                  <input
                    type="number"
                    min={1}
                    value={formLevel}
                    onChange={e => setFormLevel(parseInt(e.target.value) || 1)}
                    className="w-full px-3 py-2 bg-black/40 border border-white/10 rounded-xl text-white text-xs font-bold"
                    required
                  />
                </div>
                <div>
                  <label className="text-xs text-slate-300 block mb-1">نقاط الخبرة المطلوبة (EXP)</label>
                  <input
                    type="number"
                    min={0}
                    step={1000}
                    value={formExp}
                    onChange={e => setFormExp(parseInt(e.target.value) || 0)}
                    className="w-full px-3 py-2 bg-black/40 border border-white/10 rounded-xl text-indigo-400 text-xs font-mono font-bold"
                    required
                  />
                </div>
              </div>

              <div>
                <label className="text-xs text-slate-300 block mb-1">اسم / لقب المستوى</label>
                <input
                  type="text"
                  value={formTitle}
                  onChange={e => setFormTitle(e.target.value)}
                  placeholder="مثال: وكالة ذهبية (Gold)"
                  className="w-full px-3 py-2 bg-black/40 border border-white/10 rounded-xl text-white text-xs font-bold"
                  required
                />
              </div>

              {/* Currency Rewards */}
              <div className="p-3.5 rounded-xl bg-amber-500/5 border border-amber-500/15 space-y-3">
                <h5 className="text-xs text-amber-300 font-bold flex items-center gap-1.5">
                  <Coins className="w-4 h-4 text-amber-400" />
                  مكافآت العملات لكل مضيف نشط بالوكالة:
                </h5>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="text-[11px] text-slate-300 block mb-1">الكوينز لكل مضيف 🪙</label>
                    <input
                      type="number"
                      min={0}
                      step={100}
                      value={formCoins}
                      onChange={e => setFormCoins(parseInt(e.target.value) || 0)}
                      className="w-full px-3 py-2 bg-black/40 border border-white/10 rounded-xl text-amber-400 font-bold text-xs"
                    />
                  </div>
                  <div>
                    <label className="text-[11px] text-slate-300 block mb-1">الألماس لكل مضيف 💎</label>
                    <input
                      type="number"
                      min={0}
                      step={50}
                      value={formDiamonds}
                      onChange={e => setFormDiamonds(parseInt(e.target.value) || 0)}
                      className="w-full px-3 py-2 bg-black/40 border border-white/10 rounded-xl text-cyan-400 font-bold text-xs"
                    />
                  </div>
                </div>
              </div>

              {/* Store Items Rewards Selection */}
              <div className="p-3.5 rounded-xl bg-purple-500/5 border border-purple-500/15 space-y-3">
                <div className="flex items-center justify-between">
                  <h5 className="text-xs text-purple-300 font-bold flex items-center gap-1.5">
                    <Package className="w-4 h-4 text-purple-400" />
                    مكافآت المتجر المختارة ({formStoreRewards.length} عناصر):
                  </h5>
                  <button
                    type="button"
                    onClick={() => setShowItemPicker(true)}
                    className="flex items-center gap-1.5 px-3 py-1 bg-purple-600 hover:bg-purple-700 text-white font-bold text-[11px] rounded-lg transition-all"
                  >
                    <Plus className="w-3.5 h-3.5" />
                    اختيار عناصر من المتجر
                  </button>
                </div>

                {formStoreRewards.length === 0 ? (
                  <p className="text-[11px] text-slate-500 text-center py-2">
                    اضغط على "اختيار عناصر من المتجر" لإضافة إطارات رأس، سيارات، مؤثرات دخول، أو فقاعات كمكافآت مجانية لجميع المضيفين.
                  </p>
                ) : (
                  <div className="space-y-2 max-h-48 overflow-y-auto p-1">
                    {formStoreRewards.map((it) => (
                      <div
                        key={it.item_id}
                        className="flex items-center justify-between p-2 rounded-xl bg-black/40 border border-white/10 text-xs"
                      >
                        <div className="flex items-center gap-2">
                          {it.item_icon ? (
                            <img src={it.item_icon} alt="" className="w-7 h-7 rounded-lg object-contain bg-white/5" />
                          ) : (
                            <Package className="w-6 h-6 text-purple-400" />
                          )}
                          <div>
                            <span className="text-white font-bold block">{it.item_name}</span>
                            <span className="text-[10px] text-slate-400">{it.category}</span>
                          </div>
                        </div>

                        <div className="flex items-center gap-2">
                          <label className="text-[11px] text-slate-400">المدة:</label>
                          <select
                            value={it.days}
                            onChange={(e) => handleUpdateItemDays(it.item_id, parseInt(e.target.value) || 0)}
                            className="bg-slate-800 text-white text-[11px] px-2 py-1 rounded-lg border border-white/10"
                          >
                            <option value={3}>3 أيام</option>
                            <option value={7}>7 أيام</option>
                            <option value={15}>15 يوماً</option>
                            <option value={30}>30 يوماً</option>
                            <option value={0}>دائم (بدون انتهاء)</option>
                          </select>

                          <button
                            type="button"
                            onClick={() => setFormStoreRewards(formStoreRewards.filter(r => r.item_id !== it.item_id))}
                            className="p-1 rounded-lg text-rose-400 hover:bg-rose-500/20"
                            title="إزالة هذا العنصر"
                          >
                            <Trash2 className="w-3.5 h-3.5" />
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>

              {/* Reward Reason / Explanation */}
              <div>
                <label className="text-xs text-slate-300 block mb-1">سبب ومبرر منح المكافأة (يظهر للمضيفين في الإشعار)</label>
                <input
                  type="text"
                  value={formRewardReason}
                  onChange={e => setFormRewardReason(e.target.value)}
                  placeholder="مثال: مكافأة تشجيعية لتحقيق نمو رائع للوكالة والوصول للمستوى المطلوب"
                  className="w-full px-3 py-2 bg-black/40 border border-white/10 rounded-xl text-white text-xs"
                />
              </div>

              <div>
                <label className="text-xs text-slate-300 block mb-1">وصف المستوى وامتيازاته الإدارية</label>
                <textarea
                  value={formDesc}
                  onChange={e => setFormDesc(e.target.value)}
                  placeholder="وصف اختياري للمستوى والمميزات..."
                  rows={2}
                  className="w-full px-3 py-2 bg-black/40 border border-white/10 rounded-xl text-white text-xs"
                />
              </div>

              <div className="flex justify-end gap-2 pt-3 border-t border-white/10">
                <button
                  type="button"
                  onClick={() => setShowForm(false)}
                  className="px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white text-xs rounded-xl"
                >
                  إلغاء
                </button>
                <button
                  type="submit"
                  disabled={saving}
                  className="px-5 py-2 bg-gradient-to-r from-amber-500 to-amber-600 hover:from-amber-600 hover:to-amber-700 text-black font-bold text-xs rounded-xl flex items-center gap-1.5"
                >
                  {saving ? <RefreshCw className="w-3.5 h-3.5 animate-spin" /> : <Save className="w-3.5 h-3.5" />}
                  حفظ المستوى ومكافآته
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* ═══════════ STORE ITEMS SELECTOR MODAL ═══════════ */}
      {showItemPicker && (
        <div className="fixed inset-0 z-[60] bg-black/85 backdrop-blur-md flex items-center justify-center p-4">
          <div className="bg-[#18181b] border border-white/10 rounded-2xl w-full max-w-2xl p-6 space-y-4 flex flex-col max-h-[85vh]">
            <div className="flex items-center justify-between border-b border-white/10 pb-3">
              <div>
                <h4 className="text-white text-base font-bold flex items-center gap-2">
                  <Package className="w-5 h-5 text-purple-400" />
                  اختيار عناصر ومكافآت المتجر (Store Items)
                </h4>
                <p className="text-slate-400 text-xs mt-0.5">
                  حدد أي عدد من العناصر ليتم إيداعها تلقائياً لجميع مضيفي الوكالة عند استحقاق المستوى.
                </p>
              </div>
              <button
                onClick={() => setShowItemPicker(false)}
                className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-white/10"
              >
                <XCircle className="w-5 h-5" />
              </button>
            </div>

            {/* Search & Category Filter */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div className="relative">
                <Search className="w-4 h-4 text-slate-400 absolute right-3 top-2.5" />
                <input
                  type="text"
                  placeholder="ابحث باسم العنصر أو المعرف..."
                  value={itemSearch}
                  onChange={(e) => setItemSearch(e.target.value)}
                  className="w-full pr-9 pl-3 py-2 bg-black/40 border border-white/10 rounded-xl text-white text-xs"
                />
              </div>

              <select
                value={itemCategoryFilter}
                onChange={(e) => setItemCategoryFilter(e.target.value)}
                className="w-full px-3 py-2 bg-black/40 border border-white/10 rounded-xl text-white text-xs"
              >
                <option value="all">جميع التصنيفات</option>
                <option value="frame">إطارات الرأس (frame)</option>
                <option value="car">المركبات والسيارات (car)</option>
                <option value="entrance">مؤثرات الدخول (entrance)</option>
                <option value="bubble">الفقاعات (bubble)</option>
                <option value="cover">أغلفة الملف الشخصي (cover)</option>
                <option value="ring">الخواتم (ring)</option>
                <option value="badge">الشارات (badge)</option>
                <option value="gift">هدايا المتجر (gift)</option>
              </select>
            </div>

            {/* Items Grid */}
            <div className="flex-1 overflow-y-auto grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3 p-1">
              {filteredStoreItems.map((item) => {
                const id = item.item_id || item.id;
                const isSelected = formStoreRewards.some(r => r.item_id === id);
                return (
                  <div
                    key={id}
                    onClick={() => handleToggleStoreItem(item)}
                    className={`p-3 rounded-xl border cursor-pointer transition-all flex flex-col items-center justify-between text-center relative ${
                      isSelected
                        ? 'bg-purple-600/20 border-purple-500 shadow-lg shadow-purple-500/20'
                        : 'bg-white/5 border-white/5 hover:border-white/20'
                    }`}
                  >
                    {isSelected && (
                      <span className="absolute top-2 right-2 w-5 h-5 rounded-full bg-purple-500 text-white flex items-center justify-center text-xs font-bold shadow">
                        ✓
                      </span>
                    )}

                    <div className="w-14 h-14 rounded-xl bg-black/30 flex items-center justify-center p-1 mb-2">
                      {item.icon_url || item.iconAsset || item.icon ? (
                        <img
                          src={item.icon_url || item.iconAsset || item.icon}
                          alt={item.name}
                          className="w-full h-full object-contain"
                        />
                      ) : (
                        <Package className="w-7 h-7 text-slate-500" />
                      )}
                    </div>

                    <div className="w-full">
                      <p className="text-white text-xs font-bold truncate">{item.name || item.name_ar || id}</p>
                      <span className="text-[10px] text-slate-400 block mt-0.5">{item.category || 'عام'}</span>
                    </div>

                    <button
                      type="button"
                      className={`mt-2 w-full py-1 rounded-lg text-[10px] font-bold transition-all ${
                        isSelected
                          ? 'bg-purple-500 text-white'
                          : 'bg-white/10 text-slate-300 hover:bg-white/20'
                      }`}
                    >
                      {isSelected ? 'محدد' : 'اختيار'}
                    </button>
                  </div>
                );
              })}
            </div>

            {/* Footer */}
            <div className="flex items-center justify-between pt-3 border-t border-white/10">
              <span className="text-xs text-purple-300 font-bold">
                تم اختيار: {formStoreRewards.length} عناصر
              </span>
              <button
                type="button"
                onClick={() => setShowItemPicker(false)}
                className="px-5 py-2 bg-gradient-to-r from-purple-600 to-indigo-600 hover:from-purple-700 hover:to-indigo-700 text-white font-bold text-xs rounded-xl shadow-lg"
              >
                تأكيد الاختيار ({formStoreRewards.length})
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ═══════════ DISTRIBUTE REWARD MODAL ═══════════ */}
      {rewardLevel && (
        <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-[#18181b] border border-white/10 rounded-2xl w-full max-w-lg p-6 space-y-4">
            <h3 className="text-white text-base font-bold flex items-center gap-2">
              <Sparkles className="w-5 h-5 text-amber-400" />
              توزيع مكافأة المستوى {rewardLevel.level} ({rewardLevel.title})
            </h3>

            <div className="p-3.5 rounded-xl bg-amber-500/10 border border-amber-500/20 text-xs space-y-2">
              <p className="text-amber-200 font-bold">📋 تفاصيل المكافأة التي ستصل لكل مضيف نشط بالوكالة:</p>
              <div className="grid grid-cols-2 gap-2 text-white">
                <div>🪙 الكوينز: <span className="text-amber-400 font-bold">{rewardLevel.reward_coins_per_host.toLocaleString()}</span></div>
                {rewardLevel.reward_diamonds_per_host ? (
                  <div>💎 الألماس: <span className="text-cyan-400 font-bold">{rewardLevel.reward_diamonds_per_host.toLocaleString()}</span></div>
                ) : null}
              </div>

              {rewardLevel.reward_reason && (
                <p className="text-slate-300 text-[11px]">
                  <strong>سبب المكافأة:</strong> {rewardLevel.reward_reason}
                </p>
              )}

              {/* Store items preview */}
              {rewardLevel.store_reward_items && rewardLevel.store_reward_items.length > 0 && (
                <div>
                  <p className="text-purple-300 font-bold text-[11px] mb-1">🎁 عناصر المتجر المودعة بالحقيبة ({rewardLevel.store_reward_items.length}):</p>
                  <div className="flex flex-wrap gap-1">
                    {rewardLevel.store_reward_items.map((it, idx) => (
                      <span key={idx} className="px-2 py-0.5 rounded bg-purple-500/20 text-purple-200 text-[10px] border border-purple-500/30">
                        {it.item_name} ({it.days === 0 ? 'دائم' : `${it.days} يوم`})
                      </span>
                    ))}
                  </div>
                </div>
              )}
            </div>

            <div>
              <label className="text-xs text-slate-300 block mb-1">اختر الوكالة المستحقة</label>
              <select
                value={targetAgencyId}
                onChange={e => setTargetAgencyId(e.target.value)}
                className="w-full px-3 py-2.5 bg-black/40 border border-white/10 rounded-xl text-white text-xs"
              >
                {agencies.map(ag => (
                  <option key={ag.id} value={ag.id}>
                    {ag.name} (كود: {ag.agency_code}) - المستوى الحالي: {ag.level || 1}
                  </option>
                ))}
              </select>
            </div>

            {distributeResult && (
              <div className="p-3 bg-white/5 border border-white/10 rounded-xl text-xs text-slate-200 whitespace-pre-line">
                {distributeResult}
              </div>
            )}

            <div className="flex justify-end gap-2 pt-2 border-t border-white/10">
              <button
                type="button"
                onClick={() => setRewardLevel(null)}
                className="px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white text-xs rounded-xl"
              >
                إغلاق
              </button>
              <button
                type="button"
                onClick={handleDistributeReward}
                disabled={distributing}
                className="px-5 py-2 bg-gradient-to-r from-amber-500 to-amber-600 hover:from-amber-600 hover:to-amber-700 text-black font-bold text-xs rounded-xl flex items-center gap-1.5"
              >
                {distributing ? <RefreshCw className="w-3.5 h-3.5 animate-spin" /> : <Check className="w-3.5 h-3.5" />}
                صرف المكافأة الجماعية الآن
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

