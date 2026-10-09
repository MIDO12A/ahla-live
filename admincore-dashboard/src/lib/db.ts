import { supabase, getAdminSupabase } from './supabase'
import { getCurrentAdminName } from './auth'
import type {
  UserModel, RoomModel, GiftModel, SentGiftModel,
  StoreItemModel, UnionModel, BugReport, AppConfig,
  LevelConfig, VIPConfig, BadgeConfig, AgencyModel,
  CPModel, BDModel, GiftedItem, UserVIP, NecklaceConfig,
  AdminUser, AdminActionLog, DashboardBan, AppAssetRecord,
  HostAgencyMemberModel, HostMilestoneModel, CommissionSettingModel,
  AgencyJoinRequestModel, AgencyLedgerEntryModel, AgencyWithdrawalRequestModel,
  HostAgencyModel, CpGiftModel, CpCarModel, CpEventSettings, CpRankRewardModel,
  SigninRewardModel, AgencyApplicationModel, HostRechargeRecord,
} from '../types'

// ---- Auth Admin ----

export async function updateUserPassword(uid: string, password: string) {
  try {
    const adminClient = getAdminSupabase()
    if (!adminClient) throw new Error('Admin client not available')
    const { error } = await adminClient.auth.admin.updateUserById(uid, { password })
    if (error) throw error
  } catch (e) {
    console.warn('updateUserPassword failed:', e)
    throw e
  }
}

export async function getAuthUsers() {
  try {
    const adminClient = getAdminSupabase()
    if (!adminClient) return []
    const { data, error } = await adminClient.auth.admin.listUsers()
    if (error) throw error
    return data.users
  } catch (e) {
    console.warn('getAuthUsers failed:', e)
    return []
  }
}

export async function getAuthUser(uid: string) {
  try {
    const adminClient = getAdminSupabase()
    if (!adminClient) return null
    const { data, error } = await adminClient.auth.admin.getUserById(uid)
    if (error) throw error
    return data.user
  } catch (e) {
    console.warn('getAuthUser failed:', e)
    return null
  }
}

// ---- Helpers ----

function toCamelCase(record: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {}
  for (const [key, value] of Object.entries(record)) {
    const camelKey = key.replace(/_([a-z])/g, (_, c) => c.toUpperCase())
    result[camelKey] = value
  }
  return result
}

function toSnakeCase(record: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {}
  for (const [key, value] of Object.entries(record)) {
    const snakeKey = key.replace(/[A-Z]/g, c => `_${c.toLowerCase()}`)
    result[snakeKey] = value
  }
  return result
}

function mapList<T>(list: Record<string, unknown>[]): T[] {
  return list.map(item => toCamelCase(item) as unknown as T)
}

function mapSingle<T>(item: Record<string, unknown> | null): T | null {
  if (!item) return null
  return toCamelCase(item) as unknown as T
}

// ---- Users ----

export async function syncAllAuthUsersToDB() {
  const adminClient = getAdminSupabase()
  if (!adminClient) throw new Error('Admin client not available')

  try {
    // 1. Get all auth users
    const { data: authData, error: authError } = await adminClient.auth.admin.listUsers()
    if (authError) throw authError
    if (!authData?.users) return { total: 0, synced: 0 }

    // 2. Get existing users in DB
    const { data: existingUsers, error: fetchError } = await adminClient.from('users').select('uid')
    if (fetchError) throw fetchError
    const existingUids = new Set((existingUsers || []).map((u: any) => u.uid))

    // 3. Create missing users
    let syncedCount = 0
    for (const au of authData.users) {
      if (!existingUids.has(au.id)) {
        const metadata = au.user_metadata || {}
        const name = metadata.name || metadata.full_name || metadata.display_name || au.email?.split('@')[0] || 'Unknown'
        const photoUrl = metadata.avatar_url || metadata.picture || metadata.photoUrl || metadata.image || ''
        const email = au.email || ''
        const phone = au.phone || metadata.phone || ''

        const newUser: Partial<UserModel> = {
          uid: au.id,
          customId: (100000 + Math.floor(Math.random() * 900000)).toString(), // 6-digit numeric ID
          name,
          photoUrl,
          email,
          phone,
          coins: 0,
          diamonds: 0,
          level: 1,
          experience: 0,
          followers: 0,
          following: 0,
          charm: 0,
          totalGiftsReceived: 0,
          wealthLevel: 1,
          wealthExp: 0,
          rechargeLevel: 1,
          rechargeExp: 0,
          gemsLevel: 1,
          gemsExp: 0,
          gender: 'male',
          banned: false,
          activeFrame: null,
          activeBubble: null,
          activeEntrance: null,
          activeCar: null,
          activeCover: null,
          activeNecklace: null,
          ownedItems: [],
          ownedBadges: [],
          ownedNecklaces: [],
          ownedLevelFrames: [],
          ownedLevelBadges: [],
        }

        const { error: insertError } = await adminClient.from('users').insert(toSnakeCase(newUser as Record<string, unknown>) as any)
        if (!insertError) {
          syncedCount++
        }
      }
    }
    return { total: authData.users.length, synced: syncedCount }
  } catch (e) {
    console.error('syncAllAuthUsersToDB failed:', e)
    throw e
  }
}

// ---- Reports ----
export async function getReports() {
  const { data, error } = await supabase.from('reports').select('*').order('created_at', { ascending: false });
  if (error) throw error;
  return mapList<any>(data || []);
}

export async function updateReportStatus(id: string, status: string) {
  const { error } = await supabase.from('reports').update({ status }).eq('id', id);
  if (error) throw error;
}

export async function getUsers(): Promise<UserModel[]> {
  const adminClient = getAdminSupabase()
  const results: UserModel[] = []

  // 1. Fetch ONLY from public users table (this is our source of truth!)
  try {
    const client = adminClient || supabase
    const { data } = await client.from('users').select('*').order('uid')
    if (data) results.push(...mapList<UserModel>(data))
  } catch (e) {
    console.warn('getUsers: public table failed', e)
  }

  return results.sort((a, b) => (Number(a.customId) || 0) - (Number(b.customId) || 0))
}

export function subscribeUsers(cb: (users: UserModel[]) => void) {
  const client = getAdminSupabase() || supabase
  const sub = client.channel('users-db').on('postgres_changes', { event: '*', schema: 'public', table: 'users' }, () => {
    getUsers().then(cb)
  }).subscribe((status) => {
    if (status !== 'SUBSCRIBED') {
      console.warn('subscribeUsers: channel status', status)
    }
  })
  return () => { try { client.removeChannel(sub) } catch {} }
}

export async function getUser(uid: string): Promise<UserModel | null> {
  try {
    const client = getAdminSupabase() || supabase
    const { data } = await client.from('users').select('*').eq('uid', uid).maybeSingle()
    return mapSingle<UserModel>(data)
  } catch (e) {
    console.warn('getUser failed:', e)
    return null
  }
}

export function cleanFirestoreData<T extends Record<string, any>>(obj: T): Record<string, any> {
  const result: Record<string, any> = {};
  for (const [key, value] of Object.entries(obj)) {
    if (value !== undefined) {
      if (value !== null && typeof value === 'object' && !Array.isArray(value) && !(value instanceof Date)) {
        result[key] = cleanFirestoreData(value);
      } else {
        result[key] = value;
      }
    }
  }
  return result;
}

export async function checkCustomIdAvailable(
  customId: string,
  excludeUid?: string,
  excludeItemId?: string,
  isStoreItem = false
): Promise<{ available: boolean; reason?: string }> {
  const cleanId = String(customId || '').trim();
  if (!cleanId) return { available: false, reason: 'يرجى إدخال الآيدي' };

  const client = getAdminSupabase() || supabase;

  // 1. Check if taken by another user (only when assigning ID to a user directly, NOT when adding to store)
  if (!isStoreItem) {
    let userQuery = client.from('users').select('uid, name, custom_id').eq('custom_id', cleanId);
    if (excludeUid) {
      userQuery = userQuery.neq('uid', excludeUid);
    }
    const { data: userMatch } = await userQuery.maybeSingle();
    if (userMatch) {
      return {
        available: false,
        reason: `هذا الآيدي (${cleanId}) مستخدم بالفعل من قبل المستخدم "${userMatch.name || userMatch.uid}"!`,
      };
    }
  }

  // 2. Check if already for sale in store
  try {
    let storeQuery = client
      .from('store_items')
      .select('*')
      .eq('category', 'special_id');
    if (excludeItemId) {
      storeQuery = storeQuery.neq('item_id', excludeItemId);
    }
    const { data: storeItems, error: storeErr } = await storeQuery;
    if (!storeErr && storeItems) {
      const match = storeItems.find((it: any) => {
        const idVal = String(it.custom_id || it.customId || '').trim();
        if (idVal && idVal === cleanId) return true;
        if (it.name_key && typeof it.name_key === 'string' && it.name_key === `custom_id:${cleanId}`) return true;
        const nameVal = String(it.name || '').trim();
        if (nameVal === cleanId || nameVal === `آيدي مميز ${cleanId}`) return true;
        return false;
      });
      if (match) {
        return {
          available: false,
          reason: `هذا الآيدي (${cleanId}) معروض بالفعل للبيع في المتجر!`,
        };
      }
    }
  } catch (err) {
    console.warn('Store check error (ignored):', err);
  }

  // 3. Check if taken by another room
  try {
    let roomQuery = client.from('rooms').select('room_id, name, host_uid').eq('room_id', cleanId);
    if (excludeUid) {
      roomQuery = roomQuery.neq('host_uid', excludeUid);
    }
    const { data: roomMatch } = await roomQuery.maybeSingle();
    if (roomMatch) {
      return {
        available: false,
        reason: `هذا الآيدي (${cleanId}) مستخدم بالفعل كآيدي لغرفة أخرى ("${roomMatch.name || roomMatch.room_id}")!`,
      };
    }
  } catch (err) {
    console.warn('Room check error (ignored):', err);
  }

  return { available: true };
}

export async function updateUser(uid: string, data: Partial<UserModel>) {
  const client = getAdminSupabase() || supabase

  let customIdUpdated: string | null = null;
  // Check custom ID uniqueness if updating customId
  if (data.customId !== undefined || (data as Record<string, unknown>).custom_id !== undefined) {
    const rawId = String(data.customId ?? (data as Record<string, unknown>).custom_id ?? '').trim();
    if (rawId) {
      const check = await checkCustomIdAvailable(rawId, uid);
      if (!check.available) {
        throw new Error(check.reason);
      }
      customIdUpdated = rawId;
      (data as any).customId = rawId;
      (data as any).custom_id = rawId;
      (data as any).hosted_room_id = rawId;
      (data as any).hostedRoomId = rawId;
    }
  }
  
  // First try to update
  try {
    const { data: existingUser, error: fetchError } = await client.from('users').select('uid').eq('uid', uid).maybeSingle()
    
    if (fetchError) {
      console.error('Error checking for existing user:', fetchError)
      throw fetchError
    }
    
    if (!existingUser) {
      // User doesn't exist - create new record
      const userData: Partial<UserModel> = {
        uid,
        coins: 0,
        diamonds: 0,
        level: 1,
        experience: 0,
        followers: 0,
        following: 0,
        charm: 0,
        totalGiftsReceived: 0,
        wealthLevel: 1,
        wealthExp: 0,
        rechargeLevel: 1,
        rechargeExp: 0,
        gemsLevel: 1,
        gemsExp: 0,
        gender: 'male',
        banned: false,
        activeFrame: null,
        activeBubble: null,
        activeEntrance: null,
        activeCar: null,
        activeCover: null,
        activeNecklace: null,
        ownedItems: [],
        ownedBadges: [],
        ownedNecklaces: [],
        ownedLevelFrames: [],
        ownedLevelBadges: [],
        ...data,
      }
      
      const snakeData = toSnakeCase(userData as Record<string, unknown>)
      console.log('Inserting new user with data:', snakeData)
      
      const { error: insertError } = await client.from('users').insert(snakeData)
      if (insertError) {
        console.error('Error inserting user:', insertError)
        throw insertError
      }
    } else {
      // User exists - update
      const snakeData = toSnakeCase(data as Record<string, unknown>)
      const { error } = await client.from('users').update(snakeData).eq('uid', uid)
      if (error) {
        console.error('Error updating user:', error)
        throw error
      }
    }

    // Automatically sync/migrate room to match new custom_id
    if (customIdUpdated) {
      try {
        const { data: hostRoom } = await client
          .from('rooms')
          .select('*')
          .eq('host_uid', uid)
          .maybeSingle();

        if (hostRoom && hostRoom.room_id !== customIdUpdated) {
          const oldRoomId = hostRoom.room_id;
          const newRoomData = {
            ...hostRoom,
            room_id: customIdUpdated,
          };
          await client.from('rooms').upsert(newRoomData);

          await client.from('room_seats').update({ room_id: customIdUpdated }).eq('room_id', oldRoomId);
          await client.from('room_members').update({ room_id: customIdUpdated }).eq('room_id', oldRoomId);
          await client.from('room_messages').update({ room_id: customIdUpdated }).eq('room_id', oldRoomId);
          await client.from('sent_gifts').update({ room_id: customIdUpdated }).eq('room_id', oldRoomId);

          await client.from('rooms').delete().eq('room_id', oldRoomId);
        }
      } catch (rErr) {
        console.warn('Error migrating user room to custom ID in Supabase:', rErr);
      }
    }
  } catch (e) {
    console.error('updateUser failed:', e)
    throw e
  }
}

export async function deleteUser(uid: string) {
  console.log('Starting complete user deletion for:', uid)

  // Step 1: Clean up related collections (best-effort, mirror of old FK-safe RPC)
  const related: { col: string; field: string }[] = [
    { col: 'user_wallets', field: 'user_id' },
    { col: 'user_wallets', field: 'uid' },
    { col: 'notifications', field: 'target' },
    { col: 'notifications', field: 'uid' },
    { col: 'sent_gifts', field: 'sender_id' },
    { col: 'sent_gifts', field: 'receiver_id' },
    { col: 'gifted_items', field: 'uid' },
    { col: 'follows', field: 'follower_uid' },
    { col: 'follows', field: 'following_uid' },
    { col: 'blocks', field: 'blocker_uid' },
    { col: 'blocks', field: 'blocked_uid' },
    { col: 'room_blocks', field: 'blocked_uid' },
    { col: 'room_blocks', field: 'blocker_uid' },
    { col: 'room_blocks', field: 'user_id' },
    { col: 'room_members', field: 'uid' },
    { col: 'room_seats', field: 'uid' },
    { col: 'room_messages', field: 'sender_uid' },
    { col: 'room_messages', field: 'uid' },
    { col: 'profile_visits', field: 'visited_uid' },
    { col: 'profile_visits', field: 'visitor_uid' },
    { col: 'private_messages', field: 'sender_uid' },
    { col: 'private_messages', field: 'receiver_uid' },
  ]
  for (const { col, field } of related) {
    try {
      await supabase.from(col).delete().eq(field, uid)
    } catch { /* ignore */ }
  }

  // Step 2: Delete the user document itself
  const { error } = await supabase.from('users').delete().eq('uid', uid)
  if (error) throw new Error(`Delete error: ${error.message}`)

  // Step 3: Revoke/delete the auth account (browser-safe compat)
  try {
    await getAdminSupabase().auth.admin.deleteUser(uid)
  } catch (e) {
    console.warn('Auth API deletion non-fatal:', e)
  }

  console.log('✅ USER DELETED COMPLETELY!')
}

// ---- Gifts ----

export async function getGifts(): Promise<GiftModel[]> {
  try {
    const { data, error } = await supabase.from('gifts').select('*')
    if (!error && data && data.length > 0) {
      return mapList<GiftModel>(data)
    }
  } catch (e) {
    console.warn('getGifts supabase error, trying firestore fallback:', e)
  }
  return []
}

export function subscribeGifts(cb: (gifts: GiftModel[]) => void) {
  const sub = supabase.channel('gifts').on('postgres_changes', { event: '*', schema: 'public', table: 'gifts' }, () => {
    getGifts().then(cb)
  }).subscribe()
  return () => { try { supabase.removeChannel(sub) } catch {} }
}

const BASE_GIFT_COLUMNS = new Set([
  'id', 'name', 'value', 'icon_asset', 'animation_asset',
  'is_vap', 'is_lucky', 'is_star', 'is_music',
  'package_count', 'sort_order', 'name_key', 'photo_key',
  'default_image', 'wealth_xp', 'gems_xp',
  'category_id', 'category', 'type', 'is_cp_gift',
  'cp_gift_duration_hours',
  'lucky_rtp', 'lucky_max_multiplier', 'lucky_burst', 'lucky_display_mode',
  'receiver_name_key', 'receiver_photo_key', 'count_key'
]);

function sanitizeGiftData(data: Partial<GiftModel>): Record<string, unknown> {
  const raw = { ...data };
  const name = String(raw.name || (raw as any).name_ar || (raw as any).nameAr || '').trim();
  const nameAr = String((raw as any).name_ar || (raw as any).nameAr || raw.name || '').trim();
  let cpDuration = Number(raw.cpGiftDurationHours ?? (raw as any).cp_gift_duration_hours ?? 0) || 0;
  if (!cpDuration) {
    const dType = (raw as any).duration_type ?? (raw as any).durationType;
    const dVal = Number((raw as any).duration_value ?? (raw as any).durationValue ?? 0) || 0;
    if (dType === 'days' && dVal > 0) {
      cpDuration = dVal * 24;
    } else if (dType === 'hours' && dVal > 0) {
      cpDuration = dVal;
    }
  }
  const clean: Record<string, unknown> = {
    ...raw,
    name: name || 'هدية',
    name_ar: nameAr || name || 'هدية',
    value: Number(raw.value ?? (raw as any).price ?? 0) || 0,
    price: Number(raw.value ?? (raw as any).price ?? 0) || 0,
    type: Number(raw.type ?? 1) || 1,
    package_count: Number(raw.packageCount ?? (raw as any).package_count ?? 0) || 0,
    sort_order: Number(raw.sortOrder ?? (raw as any).sort_order ?? 0) || 0,
    wealth_xp: Number(raw.wealthXp ?? (raw as any).wealth_xp ?? 0) || 0,
    gems_xp: Number(raw.gemsXp ?? (raw as any).gems_xp ?? 0) || 0,
    cp_gift_duration_hours: cpDuration,
    lucky_rtp: Number(raw.luckyRtp ?? (raw as any).lucky_rtp ?? 85) || 85,
    lucky_max_multiplier: Number(raw.luckyMaxMultiplier ?? (raw as any).lucky_max_multiplier ?? 100) || 100,
    is_vap: Boolean(raw.isVap ?? (raw as any).is_vap ?? false),
    is_lucky: Boolean(raw.isLucky ?? (raw as any).is_lucky ?? false),
    is_star: Boolean(raw.isStar ?? (raw as any).is_star ?? false),
    is_music: Boolean(raw.isMusic ?? (raw as any).is_music ?? false),
    is_cp_gift: Boolean(raw.isCpGift ?? (raw as any).is_cp_gift ?? false),
    lucky_burst: (raw.luckyBurst !== false && (raw as any).lucky_burst !== false),
  };
  return clean;
}

export async function updateGift(id: string, data: Partial<GiftModel>) {
  const sanitized = sanitizeGiftData(data);

  // 2. Write to Supabase (only send valid columns)
  try {
    const fullPayload = toSnakeCase(sanitized);
    const validPayload: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(fullPayload)) {
      if (BASE_GIFT_COLUMNS.has(k)) {
        validPayload[k] = v;
      }
    }
    const { error } = await supabase.from('gifts').update(validPayload).eq('id', id);
    if (error) {
      console.warn('updateGift supabase error:', error);
    }
  } catch (e) {
    console.warn('updateGift supabase failed:', e);
  }
}

export async function addGift(id: string, data: GiftModel) {
  const sanitized = sanitizeGiftData(data);

  // 2. Write to Supabase (only send valid columns)
  try {
    const fullPayload = { id, ...toSnakeCase(sanitized) };
    const validPayload: Record<string, unknown> = { id };
    for (const [k, v] of Object.entries(fullPayload)) {
      if (BASE_GIFT_COLUMNS.has(k)) {
        validPayload[k] = v;
      }
    }
    const { error } = await supabase.from('gifts').upsert(validPayload);
    if (error) {
      console.warn('addGift supabase error:', error);
    }
  } catch (e) {
    console.warn('addGift supabase failed:', e);
  }
}

export async function deleteGift(id: string) {

  try {
    await supabase.from('gifts').delete().eq('id', id);
  } catch (e) {
    console.warn('deleteGift failed:', e);
  }
}

// ---- Store Items ----

export async function getStoreItems(): Promise<StoreItemModel[]> {
  try {
    const { data } = await supabase.from('store_items').select('*').order('item_id');
    const items = mapList<StoreItemModel>(data ?? []);
    return items.map((it: any) => {
      let customId = it.customId || it.custom_id;
      let colorEffect = it.colorEffect || it.color_effect;
      if (!customId && it.nameKey && typeof it.nameKey === 'string' && it.nameKey.startsWith('custom_id:')) {
        customId = it.nameKey.replace('custom_id:', '');
      }
      if (!customId && it.name_key && typeof it.name_key === 'string' && it.name_key.startsWith('custom_id:')) {
        customId = it.name_key.replace('custom_id:', '');
      }
      if (!colorEffect && it.photoKey && typeof it.photoKey === 'string' && it.photoKey.startsWith('color_effect:')) {
        colorEffect = it.photoKey.replace('color_effect:', '');
      }
      if (!colorEffect && it.photo_key && typeof it.photo_key === 'string' && it.photo_key.startsWith('color_effect:')) {
        colorEffect = it.photo_key.replace('color_effect:', '');
      }
      if (it.category === 'special_id' && !customId && it.name) {
        const num = it.name.replace(/\D/g, '');
        if (num) customId = num;
      }
      return {
        ...it,
        customId: customId || undefined,
        colorEffect: colorEffect || 'golden',
        isAvailable: it.isAvailable ?? it.is_available ?? true,
        isSold: it.isSold ?? it.is_sold ?? false,
      };
    });
  } catch {
    return [];
  }
}

export function subscribeStoreItems(cb: (items: StoreItemModel[]) => void) {
  const sub = supabase.channel('store_items').on('postgres_changes', { event: '*', schema: 'public', table: 'store_items' }, () => {
    getStoreItems().then(cb);
  }).subscribe();
  return () => { try { supabase.removeChannel(sub); } catch {} };
}

export async function updateStoreItem(id: string, data: Partial<StoreItemModel>) {
  try {
    const client = getAdminSupabase() || supabase;
    if (data.category === 'special_id' || data.customId) {
      const rawId = String(data.customId ?? '').trim();
      if (rawId) {
        const check = await checkCustomIdAvailable(rawId, undefined, id, true);
        if (!check.available) {
          throw new Error(check.reason);
        }
      }
    }

    // Try standard upsert with all snake_case fields
    const fullPayload = toSnakeCase(data as Record<string, unknown>);
    const { error } = await client.from('store_items').update(fullPayload).eq('item_id', id);

    if (error) {
      console.warn('Supabase updateStoreItem full payload failed, falling back to base schema:', error);
      // Fallback if custom_id column is missing in PostgreSQL
      const basePayload: Record<string, unknown> = {
        name: data.name,
        category: data.category,
        icon_asset: data.iconAsset,
        price: data.price,
        svga_asset: data.svgaAsset,
        is_premium: data.isPremium,
        default_image: data.defaultImage,
      };
      if (data.customId) {
        basePayload.name_key = `custom_id:${data.customId.trim()}`;
      }
      if (data.colorEffect) {
        basePayload.photo_key = `color_effect:${data.colorEffect}`;
      }
      const cleanedBase = Object.fromEntries(Object.entries(basePayload).filter(([_, v]) => v !== undefined));
      const res = await client.from('store_items').update(cleanedBase).eq('item_id', id);
      if (res.error) throw res.error;
    }


  } catch (e) {
    console.error('updateStoreItem failed:', e);
    throw e;
  }
}

export async function addStoreItem(id: string, data: StoreItemModel) {
  try {
    const client = getAdminSupabase() || supabase;
    if (data.category === 'special_id' || data.customId) {
      const rawId = String(data.customId ?? '').trim();
      if (!rawId) {
        throw new Error('يرجى تحديد الآيدي المميز للسلعة!');
      }
      const check = await checkCustomIdAvailable(rawId, undefined, id, true);
      if (!check.available) {
        throw new Error(check.reason);
      }
    }

    // Try standard upsert with all snake_case fields
    const fullPayload = { item_id: id, ...toSnakeCase(data as unknown as Record<string, unknown>) };
    const { error } = await client.from('store_items').upsert(fullPayload);

    if (error) {
      console.warn('Supabase addStoreItem full payload failed, falling back to base schema:', error);
      // Fallback if custom_id column is missing in PostgreSQL table
      const fallbackPayload: Record<string, unknown> = {
        item_id: id,
        name: data.name || (data.customId ? `آيدي مميز ${data.customId}` : 'عنصر متجر'),
        category: data.category,
        icon_asset: data.iconAsset || '',
        price: Number(data.price) || 0,
        svga_asset: data.svgaAsset || null,
        is_premium: !!data.isPremium,
        name_key: data.customId ? `custom_id:${data.customId.trim()}` : (data.nameKey || null),
        photo_key: data.colorEffect ? `color_effect:${data.colorEffect}` : (data.photoKey || null),
        default_image: data.defaultImage || null,
      };
      const res = await client.from('store_items').upsert(fallbackPayload);
      if (res.error) throw res.error;
    }


  } catch (e) {
    console.error('addStoreItem failed:', e);
    throw e;
  }
}

export async function deleteStoreItem(id: string) {
  try {
    await supabase.from('store_items').delete().eq('item_id', id);

  } catch (e) {
    console.warn('deleteStoreItem failed:', e);
  }
}

// ---- Store Categories ----

export async function getStoreCategories(): Promise<import('../types').StoreCategory[]> {
  try {
    const { data } = await supabase.from('store_categories').select('*').order('sort_order')
    return mapList<import('../types').StoreCategory>(data ?? [])
  } catch {
    return []
  }
}

export async function addStoreCategory(id: string, data: import('../types').StoreCategory) {
  try {
    await supabase.from('store_categories').upsert({ id, ...toSnakeCase(data as unknown as Record<string, unknown>) })
  } catch (e) {
    console.warn('addStoreCategory failed:', e)
  }
}

export async function updateStoreCategory(id: string, data: Partial<import('../types').StoreCategory>) {
  try {
    await supabase.from('store_categories').update(toSnakeCase(data as Record<string, unknown>)).eq('id', id)
  } catch (e) {
    console.warn('updateStoreCategory failed:', e)
  }
}

export async function deleteStoreCategory(id: string) {
  try {
    await supabase.from('store_categories').delete().eq('id', id)
  } catch (e) {
    console.warn('deleteStoreCategory failed:', e)
  }
}


// ---- Rooms ----

export async function getRooms(): Promise<RoomModel[]> {
  try {
    const { data } = await supabase.from('rooms').select('*').order('created_at', { ascending: false })
    return mapList<RoomModel>(data ?? [])
  } catch {
    return []
  }
}

export function subscribeRooms(cb: (rooms: RoomModel[]) => void) {
  const sub = supabase.channel('rooms').on('postgres_changes', { event: '*', schema: 'public', table: 'rooms' }, () => {
    getRooms().then(cb)
  }).subscribe()
  return () => { try { supabase.removeChannel(sub) } catch {} }
}

export async function updateRoom(id: string, data: Partial<RoomModel>) {
  try {
    await supabase.from('rooms').update(toSnakeCase(data as Record<string, unknown>)).eq('room_id', id)
  } catch (e) {
    console.warn('updateRoom failed:', e)
  }
}

export async function deleteRoom(id: string) {
  try {
    await supabase.from('rooms').delete().eq('room_id', id)
  } catch (e) {
    console.warn('deleteRoom failed:', e)
  }
}

// ---- Unions ----

export async function getUnions(): Promise<UnionModel[]> {
  return [];
}

export function subscribeUnions(cb: (unions: UnionModel[]) => void) {
  cb([]);
  return () => {};
}

// ---- Sent Gifts ----

export async function getSentGifts(): Promise<SentGiftModel[]> {
  try {
    const { data } = await supabase.from('sent_gifts').select('*').order('created_at', { ascending: false })
    return mapList<SentGiftModel>(data ?? [])
  } catch {
    return []
  }
}

// ---- Bug Reports ----

export async function getBugReports(): Promise<BugReport[]> {
  try {
    const { data } = await supabase.from('bug_reports').select('*').order('created_at', { ascending: false })
    return mapList<BugReport>(data ?? [])
  } catch {
    return []
  }
}

export function subscribeBugReports(cb: (reports: BugReport[]) => void) {
  const sub = supabase.channel('bug_reports').on('postgres_changes', { event: '*', schema: 'public', table: 'bug_reports' }, () => {
    getBugReports().then(cb)
  }).subscribe()
  return () => { try { supabase.removeChannel(sub) } catch {} }
}

// ---- App Config (key-value store, merged into single object) ----

export async function getAppConfig(): Promise<AppConfig | null> {
  try {
    const { data } = await supabase.from('app_config').select('*')
    if (!data || data.length === 0) return null
    const merged: Record<string, unknown> = {}
    for (const row of data) {
      const raw = row.value
      if (typeof raw === 'string') {
        try { merged[row.key as string] = JSON.parse(raw) } catch { merged[row.key as string] = raw }
      } else {
        merged[row.key as string] = raw
      }
    }
    return merged as unknown as AppConfig
  } catch {
    return null
  }
}

export async function updateAppConfig(updates: Partial<AppConfig>) {
  try {
    for (const [key, value] of Object.entries(updates)) {
      if (value === undefined || value === null) continue
      const stored = typeof value === 'object' ? JSON.stringify(value) : value
      await supabase.from('app_config').upsert({ key, value: stored })
    }
  } catch (e) {
    console.warn('updateAppConfig failed:', e)
  }
}

export function subscribeAppConfig(cb: (config: AppConfig | null) => void) {
  const handler = () => getAppConfig().then(cb)
  const sub = supabase.channel('app_config').on('postgres_changes',
    { event: '*', schema: 'public', table: 'app_config' }, handler
  ).subscribe()
  handler()
  return () => { try { supabase.removeChannel(sub) } catch {} }
}

// ---- Level Config ----

export async function getLevels(type?: string): Promise<LevelConfig[]> {
  try {
    let query = supabase.from('level_config').select('*')
    if (type) query = query.eq('type', type)
    const { data } = await query.order('level')
    return mapList<LevelConfig>(data ?? [])
  } catch {
    return []
  }
}

export function subscribeLevels(cb: (levels: LevelConfig[]) => void) {
  const sub = supabase.channel('level_config').on('postgres_changes', { event: '*', schema: 'public', table: 'level_config' }, () => {
    getLevels().then(cb)
  }).subscribe()
  return () => { try { supabase.removeChannel(sub) } catch {} }
}

export async function updateLevel(type: string, level: number, data: Partial<LevelConfig>) {


  // 2. Safe write to Supabase
  try {
    const payload = toSnakeCase(data as Record<string, unknown>)
    const { error } = await supabase.from('level_config').upsert({ type, level, ...payload }, { onConflict: 'type,level' })
    if (error) {
      await supabase.from('level_config').update(payload).eq('type', type).eq('level', level)
    }
  } catch (e) {
    console.warn('updateLevel Supabase failed:', e)
  }
}

// ---- VIP Config ----

export async function getVIPConfig(): Promise<VIPConfig[]> {
  try {
    const client = getAdminSupabase() || supabase
    const { data, error } = await client.from('vip_config').select('*').order('tier')
    if (!error && data && data.length > 0) {
      return mapList<VIPConfig>(data)
    }
  } catch {}
  return []
}

export function subscribeVIPConfig(cb: (configs: VIPConfig[]) => void) {
  const sub = supabase.channel('vip_config').on('postgres_changes', { event: '*', schema: 'public', table: 'vip_config' }, () => {
    getVIPConfig().then(cb)
  }).subscribe()
  return () => { try { supabase.removeChannel(sub) } catch {} }
}

export async function updateVIPConfig(tier: number, data: Partial<VIPConfig>) {
  const payload = { tier, ...toSnakeCase(data as Record<string, unknown>) }
  console.log('VIP save payload keys:', Object.keys(payload))

  // 2. Write to Supabase
  try {
    const client = getAdminSupabase() || supabase
    const { error } = await client.from('vip_config').upsert(payload)
    if (error) console.warn('Supabase vip_config upsert warning:', error.message)
  } catch (e) {
    console.warn('Supabase vip_config upsert error:', e)
  }
}

export async function deleteVIPConfig(tier: number) {
  try {
    const client = getAdminSupabase() || supabase
    const { error } = await client.from('vip_config').delete().eq('tier', tier)
    if (error) {
      console.warn('Supabase vip_config delete warning:', error.message)
      throw error
    }
  } catch (e) {
    console.warn('Supabase vip_config delete error:', e)
    throw e
  }
}

// ---- Badges ----

export async function getBadges(): Promise<BadgeConfig[]> {
  try {
    const client = getAdminSupabase() || supabase
    const { data } = await client.from('badges').select('*').order('id')
    return (data ?? []).map((item: any): BadgeConfig => ({
      id: item.id,
      name: item.name || '',
      name_ar: item.name_ar || '',
      name_en: item.name_en || '',
      iconAsset: item.icon_asset || item.iconAsset || '',
      description: item.description || '',
      description_ar: item.description_ar || '',
      description_en: item.description_en || '',
      unlockCondition: item.unlock_condition || item.unlockCondition || '',
      svgaUrl: item.svga_url || item.svgaUrl || undefined,
      imageUrl: item.image_url || item.imageUrl || undefined,
      sortOrder: item.sort_order ?? item.sortOrder ?? 0,
      isActive: item.is_active ?? item.isActive ?? true,
      type: item.type || 'admin',
      levelType: item.level_type || item.levelType || 'wealth',
      levelNumber: item.level_number || item.levelNumber || undefined,
    }))
  } catch (e) {
    console.warn('getBadges failed:', e)
    return []
  }
}

export function subscribeBadges(cb: (badges: BadgeConfig[]) => void) {
  const sub = supabase.channel('badges').on('postgres_changes', { event: '*', schema: 'public', table: 'badges' }, () => {
    getBadges().then(cb)
  }).subscribe()
  return () => { try { supabase.removeChannel(sub) } catch {} }
}

export async function updateBadge(id: string, data: Partial<BadgeConfig>) {
  try {
    const client = getAdminSupabase() || supabase
    await client.from('badges').update(toSnakeCase(data as Record<string, unknown>)).eq('id', id)
  } catch (e) {
    console.warn('updateBadge failed:', e)
    throw e
  }
}

export async function addBadge(id: string, data: BadgeConfig) {
  try {
    const client = getAdminSupabase() || supabase
    const { error } = await client.from('badges').insert({ id, ...toSnakeCase(data as unknown as Record<string, unknown>) })
    if (error) throw error
  } catch (e) {
    console.warn('addBadge failed:', e)
    throw e
  }
}

export async function deleteBadge(id: string) {
  try {
    const client = getAdminSupabase() || supabase
    await client.from('badges').delete().eq('id', id)
  } catch (e) {
    console.warn('deleteBadge failed:', e)
    throw e
  }
}

// ---- Agencies ----

export async function getAgencies(): Promise<AgencyModel[]> {
  try {
    const { data } = await supabase.from('agencies').select('*').order('id')
    return mapList<AgencyModel>(data ?? [])
  } catch {
    return []
  }
}

export function subscribeAgencies(cb: (agencies: AgencyModel[]) => void) {
  const sub = supabase.channel('agencies').on('postgres_changes', { event: '*', schema: 'public', table: 'agencies' }, () => {
    getAgencies().then(cb)
  }).subscribe()
  return () => { try { supabase.removeChannel(sub) } catch {} }
}

// ---- Host Agencies ----

export async function getHostAgencies(): Promise<HostAgencyModel[]> {
  try {
    const agencies: any[] = [];
    const existingIds = new Set<string>();
    const existingOwnerIds = new Set<string>();
    const existingNames = new Set<string>();

    // 1. Fetch from Supabase host_agencies
    try {
      const { data: sbData } = await supabase.from('host_agencies').select('*');
      for (const a of sbData ?? []) {
        const ownerId = a.owner_uid || a.owner_id || '';
        const mapped = {
          ...a,
          id: a.id,
          name: a.name || 'وكالة مضيفين',
          owner_id: ownerId,
          owner_uid: ownerId,
          photo_url: a.logo_url || a.photo_url || '',
          logo_url: a.logo_url || a.photo_url || '',
          description: a.description || '',
          specialty: a.data?.specialty || a.specialty || 'mixed',
          tier: a.data?.tier || a.tier || 'bronze',
          country: a.data?.country || a.country || '',
          commission_rate: typeof a.data?.commission_rate === 'number' ? a.data.commission_rate : (a.commission_rate ?? 0.10),
          is_active: a.is_active !== false && a.status !== 'inactive',
          member_count: a.member_count ?? 1,
          total_diamonds_monthly: a.total_diamonds_monthly ?? 0,
          monthly_diamonds: a.total_diamonds_monthly ?? 0,
          total_diamonds_earned: a.total_diamonds_cumulative ?? 0,
          created_at: a.created_at || new Date().toISOString(),
        };
        agencies.push(mapped);
        existingIds.add(mapped.id);
        if (ownerId) existingOwnerIds.add(ownerId);
        if (mapped.name) existingNames.add(mapped.name);
      }
    } catch (sbErr) {
      console.warn('getHostAgencies supabase error:', sbErr);
    }


    if (agencies.length === 0) return [];

    // Fetch members to compute real active member counts
    const memberCounts: Record<string, number> = {};
    try {
      const { data: membersData } = await supabase.from('host_agency_members').select('agency_id, status');
      (membersData ?? []).forEach((m: any) => {
        if (m.status === 'active') {
          memberCounts[m.agency_id] = (memberCounts[m.agency_id] || 0) + 1;
        }
      });
    } catch (_) {}

    // Fetch owner details
    const ownerIds = Array.from(new Set(agencies.map((a: any) => a.owner_id || a.owner_uid).filter(Boolean)));
    const ownersMap: Record<string, any> = {};
    if (ownerIds.length > 0) {
      try {
        const { data: usersData } = await supabase.from('users').select('*').in('uid', ownerIds);
        (usersData ?? []).forEach((u: any) => {
          const resolvedId = u.uid || u.id;
          const mapped = { ...u, id: resolvedId, avatar: u.avatar || u.photo_url };
          ownersMap[resolvedId] = mapped;
          if (u.custom_id) ownersMap[u.custom_id] = mapped;
        });
      } catch (_) {}

      // Fallback for any missing owner
      for (const oid of ownerIds) {
        if (!ownersMap[oid]) {
          try {
            const u = await searchUserProfile(oid);
            if (u) {
              const mapped = { ...u, id: u.uid || u.id, avatar: u.avatar || u.photo_url };
              ownersMap[oid] = mapped;
              if (u.custom_id) ownersMap[u.custom_id] = mapped;
            }
          } catch (_) {}
        }
      }
    }

    return mapList<HostAgencyModel>(agencies.map((a: any) => {
      const owner = ownersMap[a.owner_id];
      const realCount = memberCounts[a.id] ?? a.member_count ?? 1;
      return {
        ...a,
        member_count: Math.max(1, realCount),
        owner_name: owner?.name || owner?.displayName || a.owner_id?.slice(0, 8),
        owner_avatar: owner?.photo_url || owner?.avatar || '',
        owner_custom_id: owner?.custom_id || '',
      };
    }));
  } catch { return []; }
}

export async function createHostAgency(name: string, ownerId: string, commissionRate: number, specialty: string, extra?: Partial<HostAgencyModel>): Promise<HostAgencyModel | null> {
  try {
    // 0. Resolve owner ID (whether custom_id, email, or uid was entered)
    let resolvedUid = ownerId.trim();
    const u = await searchUserProfile(resolvedUid);
    if (u) {
      resolvedUid = u.uid || u.id;
    }

    const agencyId = extra?.id || `ag_${Date.now()}`;
    const commRate = typeof commissionRate === 'number' ? commissionRate : (parseFloat(String(commissionRate)) || 0.1);
    const photoUrl = extra?.photo_url || '';
    const nowIso = new Date().toISOString();

    // 1. Supabase insert into host_agencies
    // Schema columns: id, name, owner_uid, logo_url, description, status, is_active, data
    const sbPayload = {
      id: agencyId,
      name: name.trim(),
      owner_uid: resolvedUid,
      logo_url: photoUrl,
      description: extra?.description || '',
      status: 'active',
      is_active: true,
      member_count: 1,
      data: {
        commission_rate: commRate,
        specialty: specialty || 'mixed',
        tier: extra?.tier || 'bronze',
        country: extra?.country || '',
      },
      created_at: nowIso,
      updated_at: nowIso,
    };

    const { error: sbErr } = await supabase.from('host_agencies').upsert(sbPayload);
    if (sbErr) {
      console.warn('createHostAgency supabase host_agencies upsert warning:', sbErr);
    }

    // 2. Add owner to Supabase host_agency_members (column is host_uid, id is UUID)
    try {
      const memberUuid = (typeof crypto !== 'undefined' && crypto.randomUUID)
        ? crypto.randomUUID()
        : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
            const r = Math.random() * 16 | 0;
            return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
          });
      await supabase.from('host_agency_members').upsert({
        id: memberUuid,
        agency_id: agencyId,
        host_uid: resolvedUid,
        role: 'owner',
        status: 'active',
        joined_at: nowIso,
      });
    } catch (mErr) {
      console.warn('createHostAgency supabase host_agency_members warning:', mErr);
    }

    // 3. Update owner in Supabase users table
    try {
      await supabase.from('users').update({ agency_id: agencyId, is_host_agent: true }).eq('uid', resolvedUid);
      await supabase.from('users').update({ agency_id: agencyId, is_host_agent: true }).eq('id', resolvedUid);
      if (u?.custom_id) {
        await supabase.from('users').update({ agency_id: agencyId, is_host_agent: true }).eq('custom_id', u.custom_id);
      }
    } catch (uErr) {
      console.warn('createHostAgency supabase user update warning:', uErr);
    }

    

    // 7. Send notification to owner
    const adminLabel = extra?.adminName || 'إدارة التطبيق';
    await sendSystemNotification({
      userId: resolvedUid,
      title: 'مبروك! تم فتح وكالتك وتفعيلها بنجاح 🎉',
      body: `مبروك! تم فتح وكالة [${name}] وتفعيلها بنجاح بواسطة المشرف [${adminLabel}]. يمكنك الآن الدخول إلى مركز إدارة الوكالة وإضافة المضيفين.`,
      type: 'system',
      action: 'agency_created',
      extraData: { agency_id: agencyId, agency_name: name, admin_name: adminLabel },
    });

    return {
      id: agencyId,
      name: name.trim(),
      owner_id: resolvedUid,
      owner_uid: resolvedUid,
      commission_rate: commRate,
      specialty: specialty as any,
      tier: extra?.tier || 'bronze',
      is_active: true,
      member_count: 1,
      photo_url: photoUrl,
      created_at: nowIso,
    } as HostAgencyModel;
  } catch (e) {
    console.error('createHostAgency error:', e);
    return null;
  }
}

export async function updateHostAgency(id: string, updates: Partial<HostAgencyModel>): Promise<boolean> {
  try {
    const sbUpdates: Record<string, any> = {
      updated_at: new Date().toISOString(),
    };
    if (updates.name !== undefined) sbUpdates.name = updates.name;
    if (updates.photo_url !== undefined) sbUpdates.logo_url = updates.photo_url;
    if (updates.description !== undefined) sbUpdates.description = updates.description;
    if (updates.is_active !== undefined) {
      sbUpdates.is_active = updates.is_active;
      sbUpdates.status = updates.is_active ? 'active' : 'inactive';
    }

    // Read current data to preserve nested data fields
    try {
      const { data: curr } = await supabase.from('host_agencies').select('data').eq('id', id).maybeSingle();
      const existingData = curr?.data || {};
      sbUpdates.data = {
        ...existingData,
        ...(updates.commission_rate !== undefined ? { commission_rate: updates.commission_rate } : {}),
        ...(updates.specialty !== undefined ? { specialty: updates.specialty } : {}),
        ...(updates.tier !== undefined ? { tier: updates.tier } : {}),
        ...(updates.country !== undefined ? { country: updates.country } : {}),
      };
    } catch (_) {}

    await supabase.from('host_agencies').update(sbUpdates).eq('id', id);


    return true;
  } catch {
    return false;
  }
}

export async function deleteHostAgency(id: string): Promise<boolean> {
  try {
    const userIds = new Set<string>();

    // Step 1: Collect member and owner IDs from Supabase
    try {
      const { data: members } = await supabase.from('host_agency_members').select('host_uid').eq('agency_id', id);
      (members ?? []).forEach((m: any) => { if (m.host_uid) userIds.add(m.host_uid); });
    } catch (_) {}
    try {
      const { data: ag } = await supabase.from('host_agencies').select('owner_uid').eq('id', id).maybeSingle();
      if (ag?.owner_uid) userIds.add(ag.owner_uid);
    } catch (_) {}



    // Step 3: Delete child records in Supabase (FK constraints)
    try { await supabase.from('host_agency_members').delete().eq('agency_id', id); } catch (_) {}
    try { await supabase.from('agency_achieved_targets').delete().eq('agency_id', id); } catch (_) {}
    try { await supabase.from('agency_join_requests').delete().eq('agency_id', id); } catch (_) {}
    try { await supabase.from('agency_diamond_ledger').delete().eq('agency_id', id); } catch (_) {}
    try { await supabase.from('agency_withdrawal_requests').delete().eq('agency_id', id); } catch (_) {}
    try { await supabase.from('agency_applications').delete().eq('agency_id', id); } catch (_) {}

    // Step 4: Delete host agency from Supabase
    const { error: delErr } = await supabase.from('host_agencies').delete().eq('id', id);
    if (delErr) {
      console.warn('deleteHostAgency supabase error:', delErr);
    }



    // Step 6: Unlink users in Supabase
    try {
      await supabase.from('users').update({
        agency_id: null,
        is_host_agent: false,
      }).eq('agency_id', id);
    } catch (_) {}

    // Step 7: Unlink users in Firestore & Supabase by UID
    for (const uid of Array.from(userIds)) {
      try {
        await supabase.from('users').update({ agency_id: null, is_host_agent: false }).eq('uid', uid);
      } catch (_) {}

    }

    return true;
  } catch (e) {
    console.error('deleteHostAgency critical error:', e);
    return false;
  }
}

export async function getCommissionSettings(): Promise<CommissionSettingModel[]> {
  try {
    const { data } = await supabase.from('commission_settings').select('*').order('key');
    return mapList<CommissionSettingModel>(data ?? []);
  } catch { return []; }
}

export async function updateCommissionSetting(id: string, value: number): Promise<boolean> {
  try {
    await supabase.from('commission_settings').upsert({
      key: id, value, updated_at: new Date().toISOString(),
    });
    return true;
  } catch { return false; }
}

export async function getHostAgencyMembers(agencyId?: string): Promise<HostAgencyMemberModel[]> {
  try {
    let query = supabase.from('host_agency_members').select('*');
    if (agencyId) query = query.eq('agency_id', agencyId);
    const { data } = await query;
    let members: any[] = (data ?? []).map((m: any) => ({ ...m }));

    // Fetch agencies to ensure owners are included in the members list
    try {
      let agQuery = supabase.from('host_agencies').select('*');
      if (agencyId) agQuery = agQuery.eq('id', agencyId);
      const { data: agList } = await agQuery;

      for (const ag of agList ?? []) {
        const ownerUid = ag.owner_uid || ag.owner_id;
        if (!ownerUid) continue;
        const exists = members.some((m: any) => m.agency_id === ag.id && ((m.user_id || m.host_uid) === ownerUid || m.role === 'owner'));
        if (!exists) {
          members.unshift({
            id: `owner_${ag.id}_${ownerUid}`,
            agency_id: ag.id,
            user_id: ownerUid,
            host_uid: ownerUid,
            role: 'owner',
            status: 'active',
            joined_at: ag.created_at || new Date().toISOString(),
            diamonds_earned_monthly: ag.total_diamonds_monthly ?? ag.monthly_diamonds ?? 0,
            diamonds_balance: 0,
          });
        }
      }
    } catch (_) {}

    if (members.length === 0) return [];

    // Fetch user details for each member (support both user_id and host_uid)
    const userIds = Array.from(new Set(members.map((m: any) => m.user_id || m.host_uid).filter(Boolean)));
    const usersMap: Record<string, any> = {};
    if (userIds.length > 0) {
      try {
        const { data: usersData } = await supabase.from('users').select('*').in('uid', userIds);
        (usersData ?? []).forEach((u: any) => {
          const resolvedId = u.uid || u.id;
          const mapped = { ...u, id: resolvedId, avatar: u.avatar || u.photo_url };
          usersMap[resolvedId] = mapped;
          if (u.custom_id) usersMap[u.custom_id] = mapped;
        });
      } catch (_) {}

      // Fallback for any missing users
      for (const uid of userIds) {
        if (!usersMap[uid]) {
          try {
            const u = await searchUserProfile(uid);
            if (u) {
              const mapped = { ...u, id: u.uid || u.id, avatar: u.avatar || u.photo_url };
              usersMap[uid] = mapped;
              if (u.custom_id) usersMap[u.custom_id] = mapped;
            }
          } catch (_) {}
        }
      }
    }

    return mapList<HostAgencyMemberModel>(members.map((m: any) => {
      const uid = m.user_id || m.host_uid;
      const u = usersMap[uid];
      return {
        ...m,
        id: m.id || `${m.agency_id}_${uid}`,
        user_id: uid,
        user_name: u?.name || u?.displayName || uid?.slice(0, 8),
        custom_id: u?.custom_id || m.custom_id || '',
        avatar_url: u?.photo_url || u?.avatar || '',
        coins: Number(u?.coins || 0),
        diamonds_earned_monthly: Number(m.diamonds_earned_monthly || 0),
        diamonds_balance: Number(m.diamonds_balance || m.diamonds || 0),
        joined_at: m.joined_at || m.created_at || new Date().toISOString(),
      };
    }));
  } catch { return []; }
}

export async function addAgencyMember(agencyId: string, userQuery: string, role: string = 'host'): Promise<{ success: boolean; message: string }> {
  try {
    const q = userQuery.trim();
    if (!q) return { success: false, message: 'يرجى كتابة UID أو رقم المعرف (ID)' };

    // Search in users table
    const { data: users } = await supabase.from('users').select('*');
    const targetUser = (users || []).find((u: any) => (u.id || u.uid) === q || u.custom_id === q);

    if (!targetUser) {
      return { success: false, message: 'لم يتم العثور على مستخدم بهذا المعرف أو الـ ID' };
    }

    const userId = targetUser.uid || targetUser.id;

    // Check if already a member in this agency
    const { data: existing } = await supabase.from('host_agency_members')
      .select('*')
      .eq('agency_id', agencyId)
      .eq('user_id', userId)
      .maybeSingle();

    if (existing && existing.status === 'active') {
      return { success: false, message: 'المستخدم منضم بالفعل لهذه الوكالة' };
    }

    await supabase.from('host_agency_members').upsert({
      agency_id: agencyId,
      user_id: userId,
      role,
      status: 'active',
      joined_at: new Date().toISOString(),
    });

    await supabase.from('users').update({ agency_id: agencyId }).eq('id', userId);
    await adjustAgencyMemberCount(agencyId, 1);

    // Send system notification
    const roleLabel = role === 'supervisor' ? 'مشرف' : 'مضيف';
    await sendSystemNotification({
      userId,
      title: '🎙️ انضمام إلى وكالة مضيفين',
      body: `تمت إضافتك بنجاح إلى الوكالة برتبة [${roleLabel}] بواسطة الإدارة. يمكنك الآن تصفح لوحة تحكم الوكالة من ملفك الشخصي.`,
      type: 'system',
      action: 'agency_member_added',
      extraData: { agency_id: agencyId, role },
    });

    return { success: true, message: `تمت إضافة ${targetUser.name || 'المستخدم'} للوكالة بنجاح!` };
  } catch (err: any) {
    return { success: false, message: err?.message || 'حدث خطأ أثناء إضافة العضو' };
  }
}

// ---- Agency Applications (طلبات فتح الوكالات: قبول / رفض) ----

export async function getAgencyApplications(statusFilter?: string, typeFilter?: string): Promise<AgencyApplicationModel[]> {
  try {
    const applications: AgencyApplicationModel[] = [];

    // 1. Fetch from agency_applications
    let appQuery = supabase.from('agency_applications').select('*').order('created_at', { ascending: false });
    if (statusFilter) appQuery = appQuery.eq('status', statusFilter);
    if (typeFilter) appQuery = appQuery.eq('agency_type', typeFilter);
    const { data: appData } = await appQuery;

    if (appData && Array.isArray(appData)) {
      applications.push(...appData.map((d: any) => ({
        id: d.id,
        user_id: d.user_id,
        user_name: d.user_name || d.user_id?.slice(0, 8),
        custom_id: d.custom_id || '',
        user_avatar: d.user_avatar || '',
        agency_type: d.agency_type || 'host',
        agency_name: d.agency_name || 'وكالة جديدة',
        agency_logo: d.agency_logo || '',
        country: d.country || '',
        whatsapp: d.whatsapp || '',
        description: d.description || '',
        doc_type: d.doc_type || '',
        doc_number: d.doc_number || '',
        doc_front_url: d.doc_front_url || '',
        doc_back_url: d.doc_back_url || '',
        video_url: d.video_url || '',
        status: d.status || 'pending',
        rejection_reason: d.rejection_reason || '',
        created_at: d.created_at || new Date().toISOString(),
        reviewed_at: d.reviewed_at,
      })));
    }



    // Fetch user details to enrich with real names and avatars
    const userIds = Array.from(new Set(applications.map(a => a.user_id).filter(Boolean)));
    if (userIds.length > 0) {
      const { data: usersData } = await supabase.from('users').select('*');
      const uMap: Record<string, any> = {};
      (usersData ?? []).forEach((u: any) => {
        const resolvedId = u.id || u.uid;
        uMap[resolvedId] = { ...u, id: resolvedId, avatar: u.avatar || u.photo_url };
        if (u.custom_id) uMap[u.custom_id] = uMap[resolvedId];
      });
      applications.forEach(a => {
        const u = uMap[a.user_id];
        if (u) {
          if (!a.user_name || a.user_name.length < 3) a.user_name = u.name;
          a.custom_id = u.custom_id || a.custom_id;
          if (!a.user_avatar) a.user_avatar = u.photo_url || u.avatar || '';
        }
      });
    }

    let result = applications;
    if (statusFilter) result = result.filter(a => a.status === statusFilter);
    if (typeFilter) result = result.filter(a => a.agency_type === typeFilter);

    return result.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
  } catch { return []; }
}

export async function approveAgencyApplication(app: AgencyApplicationModel, adminName: string = 'إدارة التطبيق'): Promise<{ success: boolean; message: string }> {
  try {
    const now = new Date().toISOString();

    if (app.agency_type === 'host') {
      // 1. Create Host Agency
      const agencyData = {
        name: app.agency_name || `وكالة ${app.user_name}`,
        owner_id: app.user_id,
        description: app.description || 'وكالة مضيفين معتمدة',
        photo_url: app.agency_logo || app.user_avatar || null,
        country: app.country || null,
        commission_rate: 0.1, // 10%
        specialty: 'mixed',
        tier: 'bronze',
        is_active: true,
        member_count: 1,
        total_diamonds_earned: 0,
        monthly_diamonds: 0,
        created_at: now,
      };

      const { data: createdAgency, error: agErr } = await supabase.from('host_agencies').insert(agencyData).select('*').single();
      const agencyId = (createdAgency as any)?.id;

      if (agencyId) {
        // 2. Add owner to host_agency_members
        await supabase.from('host_agency_members').upsert({
          agency_id: agencyId,
          user_id: app.user_id,
          role: 'owner',
          status: 'active',
          joined_at: now,
        });

        // 3. Set user's agency_id
        await supabase.from('users').update({ agency_id: agencyId, is_host_agent: true }).eq('id', app.user_id);
      }

      await sendSystemNotification({
        userId: app.user_id,
        title: 'مبروك! تم قبول طلب فتح الوكالة 🎉',
        body: `مبروك! تم قبول طلبك وفتح وكالة [${app.agency_name}] بنجاح بواسطة المشرف [${adminName}]. يمكنك الآن الدخول لإدارة وكالتك.`,
        type: 'system',
        action: 'agency_approved',
        extraData: { agency_name: app.agency_name, admin_name: adminName },
      });
    } else if (app.agency_type === 'recharge') {
      // Set user as recharge agent
      await supabase.from('users').update({
        is_recharge_agent: true,
        recharge_agency_name: app.agency_name || 'وكالة الشحن المعتمدة',
        recharge_agency_logo: app.agency_logo || null,
        whatsapp_number: app.whatsapp || null,
      }).eq('id', app.user_id);

      await sendSystemNotification({
        userId: app.user_id,
        title: 'مبروك! تم تفعيل وكالة الشحن 🎉',
        body: `مبروك! تم قبول طلبك واعتمادك كوكيل شحن رسمي [${app.agency_name}] بواسطة المشرف [${adminName}].`,
        type: 'system',
        action: 'recharge_agency_approved',
        extraData: { agency_name: app.agency_name, admin_name: adminName },
      });
    }

    // Update application record
    await supabase.from('agency_applications').update({
      status: 'approved',
      reviewed_at: now,
    }).eq('id', app.id);

    return { success: true, message: `تم قبول طلب فتح الوكالة بنجاح وتم تفعيل الوكالة!` };
  } catch (err: any) {
    return { success: false, message: err?.message || 'حدث خطأ أثناء قبول الطلب' };
  }
}

export async function rejectAgencyApplication(appId: string, userId: string, reason: string = '', adminName: string = 'إدارة التطبيق'): Promise<{ success: boolean; message: string }> {
  try {
    const now = new Date().toISOString();
    await supabase.from('agency_applications').update({
      status: 'rejected',
      rejection_reason: reason.trim() || 'لم تستوفِ متطلبات فتح الوكالة',
      reviewed_at: now,
    }).eq('id', appId);

    await sendSystemNotification({
      userId: userId,
      title: 'إشعار بخصوص طلب فتح الوكالة ⚠️',
      body: `تم رفض طلب فتح الوكالة من قبل المشرف [${adminName}]. سبب الرفض: ${reason.trim() || 'لم يتم استيفاء الشروط المطلوبة'}.`,
      type: 'system',
      action: 'agency_rejected',
      extraData: { reason, admin_name: adminName },
    });

    return { success: true, message: 'تم رفض الطلب بنجاح' };
  } catch (err: any) {
    return { success: false, message: err?.message || 'حدث خطأ أثناء رفض الطلب' };
  }
}

export async function createAgencyApplication(payload: Partial<AgencyApplicationModel>): Promise<boolean> {
  try {
    await supabase.from('agency_applications').insert({
      user_id: payload.user_id,
      user_name: payload.user_name || '',
      agency_type: payload.agency_type || 'host',
      agency_name: payload.agency_name || '',
      agency_logo: payload.agency_logo || '',
      country: payload.country || '',
      whatsapp: payload.whatsapp || '',
      description: payload.description || '',
      doc_type: payload.doc_type || '',
      doc_number: payload.doc_number || '',
      doc_front_url: payload.doc_front_url || '',
      doc_back_url: payload.doc_back_url || '',
      video_url: payload.video_url || '',
      status: 'pending',
      created_at: new Date().toISOString(),
    });
    return true;
  } catch { return false; }
}

export async function getHostMilestones(): Promise<HostMilestoneModel[]> {
  try {
    const { data, error } = await supabase.from('host_milestones').select('*');
    if (!error && data && data.length > 0) {
      return (data ?? []).map((m: any) => ({
        id: m.id,
        title: m.title ?? '',
        target_diamonds: Number(m.target_diamonds ?? m.targetDiamonds ?? 0),
        targetDiamonds: Number(m.target_diamonds ?? m.targetDiamonds ?? 0),
        reward_type: m.reward_type ?? m.rewardType ?? 'salary_usd',
        rewardType: m.reward_type ?? m.rewardType ?? 'salary_usd',
        reward_value: Number(m.reward_value ?? m.rewardValue ?? 0),
        rewardValue: Number(m.reward_value ?? m.rewardValue ?? 0),
        reward_item_id: m.reward_item_id ?? m.rewardItemId ?? null,
        rewardItemId: m.reward_item_id ?? m.rewardItemId ?? null,
        reward_image_url: m.reward_image_url ?? m.rewardImageUrl ?? m.image_url ?? m.imageUrl ?? null,
        rewardImageUrl: m.reward_image_url ?? m.rewardImageUrl ?? m.image_url ?? m.imageUrl ?? null,
        background_url: m.background_url ?? m.backgroundUrl ?? null,
        backgroundUrl: m.background_url ?? m.backgroundUrl ?? null,
        agent_commission_rate: Number(m.agent_commission_rate ?? m.agentCommissionRate ?? 0.1),
        agentCommissionRate: Number(m.agent_commission_rate ?? m.agentCommissionRate ?? 0.1),
        period_type: m.period_type ?? m.periodType ?? 'monthly',
        periodType: m.period_type ?? m.periodType ?? 'monthly',
        is_active: m.is_active !== false && m.isActive !== false,
        isActive: m.is_active !== false && m.isActive !== false,
        sort_order: Number(m.sort_order ?? m.sortOrder ?? 0),
        sortOrder: Number(m.sort_order ?? m.sortOrder ?? 0),
      })) as any;
    }
  } catch {}
  return [];
}

export async function updateHostMilestone(id: string, updates: Partial<HostMilestoneModel>): Promise<boolean> {
  const raw: any = updates;
  const targetDiamonds = Number(raw.target_diamonds ?? raw.targetDiamonds ?? 0);
  const rewardValue = Number(raw.reward_value ?? raw.rewardValue ?? 0);
  const agentCommissionRate = Number(raw.agent_commission_rate ?? raw.agentCommissionRate ?? 0.1);
  const sortOrder = Number(raw.sort_order ?? raw.sortOrder ?? 0);
  const rewardType = raw.reward_type ?? raw.rewardType ?? 'salary_usd';
  const periodType = raw.period_type ?? raw.periodType ?? 'monthly';
  const isActive = raw.is_active !== false && raw.isActive !== false;
  const rewardItemId = raw.reward_item_id ?? raw.rewardItemId ?? null;
  const rewardImageUrl = raw.reward_image_url ?? raw.rewardImageUrl ?? null;
  const backgroundUrl = raw.background_url ?? raw.backgroundUrl ?? null;
  const title = raw.title ?? '';

  const normalized = {
    title,
    target_diamonds: targetDiamonds,
    targetDiamonds,
    reward_type: rewardType,
    rewardType,
    reward_value: rewardValue,
    rewardValue,
    agent_commission_rate: agentCommissionRate,
    agentCommissionRate,
    sort_order: sortOrder,
    sortOrder,
    period_type: periodType,
    periodType,
    is_active: isActive,
    isActive,
    reward_item_id: rewardItemId,
    rewardItemId,
    reward_image_url: rewardImageUrl,
    rewardImageUrl,
    background_url: backgroundUrl,
    backgroundUrl,
    updated_at: new Date().toISOString(),
  };



  // 2. Write to Supabase
  try {
    await supabase.from('host_milestones').update(normalized).eq('id', id);
  } catch (e) {
    console.warn('updateHostMilestone Supabase warning:', e);
  }
  return true;
}

export async function createHostMilestone(milestone: Omit<HostMilestoneModel, 'id'>): Promise<boolean> {
  const raw: any = milestone;
  const targetDiamonds = Number(raw.target_diamonds ?? raw.targetDiamonds ?? 0);
  const rewardValue = Number(raw.reward_value ?? raw.rewardValue ?? 0);
  const agentCommissionRate = Number(raw.agent_commission_rate ?? raw.agentCommissionRate ?? 0.1);
  const sortOrder = Number(raw.sort_order ?? raw.sortOrder ?? 0);
  const rewardType = raw.reward_type ?? raw.rewardType ?? 'salary_usd';
  const periodType = raw.period_type ?? raw.periodType ?? 'monthly';
  const isActive = raw.is_active !== false && raw.isActive !== false;
  const rewardItemId = raw.reward_item_id ?? raw.rewardItemId ?? null;
  const rewardImageUrl = raw.reward_image_url ?? raw.rewardImageUrl ?? null;
  const backgroundUrl = raw.background_url ?? raw.backgroundUrl ?? null;
  const title = raw.title ?? '';
  const newId = `hm_${Date.now()}`;

  const normalized = {
    id: newId,
    title,
    target_diamonds: targetDiamonds,
    targetDiamonds,
    reward_type: rewardType,
    rewardType,
    reward_value: rewardValue,
    rewardValue,
    agent_commission_rate: agentCommissionRate,
    agentCommissionRate,
    sort_order: sortOrder,
    sortOrder,
    period_type: periodType,
    periodType,
    is_active: isActive,
    isActive,
    reward_item_id: rewardItemId,
    rewardItemId,
    reward_image_url: rewardImageUrl,
    rewardImageUrl,
    background_url: backgroundUrl,
    backgroundUrl,
    created_at: new Date().toISOString(),
  };



  // 2. Write to Supabase
  try {
    await supabase.from('host_milestones').insert(normalized);
  } catch (e) {
    console.warn('createHostMilestone Supabase warning:', e);
  }
  return true;
}

export async function deleteHostMilestone(id: string): Promise<boolean> {

  try { await supabase.from('host_milestones').delete().eq('id', id) } catch {}
  return true;
}

// ---- Agency Join Requests ----

async function adjustAgencyMemberCount(agencyId: string, delta: number) {
  try {
    const { data } = await supabase.from('host_agencies').select('member_count').eq('id', agencyId).single()
    const count = Number((data as any)?.member_count ?? 0) + delta
    await supabase.from('host_agencies').update({ member_count: Math.max(0, count) }).eq('id', agencyId)
  } catch { /* ignore */ }
}

export async function getHostAgencyJoinRequests(status?: string): Promise<AgencyJoinRequestModel[]> {
  try {
    let query = supabase.from('host_agency_join_requests').select('*, host_agencies!agency_id(name)').order('created_at', { ascending: false })
    if (status) query = query.eq('status', status)
    const { data } = await query
    return mapList<AgencyJoinRequestModel>((data ?? []).map((r: any) => ({
      ...r,
      user_name: r.user_id?.slice(0, 8),
      agency_name: r.host_agencies?.name ?? r.agency_id?.slice(0, 8),
    })))
  } catch { return [] }
}

export async function approveJoinRequest(id: string): Promise<boolean> {
  try {
    const { data: req } = await supabase.from('host_agency_join_requests').select('*').eq('id', id).single()
    if (!req) return false
    await supabase.from('host_agency_members').insert({
      agency_id: req.agency_id, user_id: req.user_id, role: 'host', status: 'active',
    })
    await supabase.from('host_agency_join_requests').update({ status: 'approved' }).eq('id', id)
    await adjustAgencyMemberCount(req.agency_id, 1)
    return true
  } catch { return false }
}

export async function rejectJoinRequest(id: string): Promise<boolean> {
  try { await supabase.from('host_agency_join_requests').update({ status: 'rejected' }).eq('id', id); return true } catch { return false }
}

// ---- Agency Members ----

export async function updateAgencyMemberRole(agencyId: string, userId: string, role: string): Promise<boolean> {
  try {
    await supabase.from('host_agency_members').update({ role }).eq('agency_id', agencyId).eq('user_id', userId)
    return true
  } catch { return false }
}

export async function removeAgencyMember(agencyId: string, userId: string): Promise<boolean> {
  try {
    await supabase.from('host_agency_members').delete().eq('agency_id', agencyId).eq('user_id', userId);
    await supabase.from('host_agency_members').delete().eq('agency_id', agencyId).eq('host_uid', userId);
    await supabase.from('users').update({ agency_id: null }).eq('id', userId);
    await supabase.from('users').update({ agency_id: null }).eq('uid', userId);
    await adjustAgencyMemberCount(agencyId, -1);
    return true;
  } catch { return false; }
}

export async function removeAgencyMemberWithNotification(
  agencyId: string,
  userId: string,
  agencyName?: string,
  userName?: string
): Promise<{ success: boolean; message: string }> {
  try {
    const client = getAdminSupabase() || supabase;

    // 1. Delete from host_agency_members
    await client.from('host_agency_members').delete().eq('agency_id', agencyId).eq('user_id', userId);
    await client.from('host_agency_members').delete().eq('agency_id', agencyId).eq('host_uid', userId);

    // 2. Reset agency_id in users
    await client.from('users').update({ agency_id: null }).eq('id', userId);
    await client.from('users').update({ agency_id: null }).eq('uid', userId);

    // 3. Adjust member count
    await adjustAgencyMemberCount(agencyId, -1);

    // 4. Send official in-app system notification
    const aName = agencyName || 'الوكالة';
    await sendSystemNotification({
      userId,
      title: '❌ تم إنهاء عضويتك في الوكالة',
      body: `تم إنهاء عضويتك وإزالتك من وكالة [${aName}] بواسطة إدارة التطبيق.`,
      type: 'system',
      action: 'agency_member_removed',
      extraData: { agency_id: agencyId },
    });

    return { success: true, message: `تم إزالة ${userName || 'المضيف'} من الوكالة بنجاح وإرسال إشعار فوري له!` };
  } catch (err: any) {
    return { success: false, message: err?.message || 'فشل إزالة العضو من الوكالة' };
  }
}

export async function transferAgencyMember(
  userId: string,
  fromAgencyId: string,
  toAgencyId: string,
  fromAgencyName?: string,
  toAgencyName?: string
): Promise<{ success: boolean; message: string }> {
  try {
    if (!userId || !toAgencyId) {
      return { success: false, message: 'معرف المستخدم والوكالة الجديدة مطلوبان' };
    }
    if (fromAgencyId === toAgencyId) {
      return { success: false, message: 'لا يمكن نقل العضو إلى نفس الوكالة الحالية' };
    }

    const client = getAdminSupabase() || supabase;
    const nowIso = new Date().toISOString();

    // 1. Update member row in host_agency_members: reset monthly diamonds and target to 0
    await client.from('host_agency_members')
      .update({
        agency_id: toAgencyId,
        diamonds_earned_monthly: 0,
        daily_target: 0,
        monthly_target: 0,
        joined_at: nowIso,
      })
      .eq('agency_id', fromAgencyId)
      .eq('user_id', userId);

    await client.from('host_agency_members')
      .update({
        agency_id: toAgencyId,
        diamonds_earned_monthly: 0,
        daily_target: 0,
        monthly_target: 0,
        joined_at: nowIso,
      })
      .eq('agency_id', fromAgencyId)
      .eq('host_uid', userId);

    // 2. Update user agency_id in users table
    await client.from('users').update({ agency_id: toAgencyId }).eq('id', userId);
    await client.from('users').update({ agency_id: toAgencyId }).eq('uid', userId);

    // 3. Adjust member counts for both agencies
    if (fromAgencyId) {
      await adjustAgencyMemberCount(fromAgencyId, -1);
    }
    await adjustAgencyMemberCount(toAgencyId, 1);

    // 4. Send official system notification to host
    const fromLabel = fromAgencyName || 'الوكالة السابقة';
    const toLabel = toAgencyName || 'الوكالة الجديدة';
    await sendSystemNotification({
      userId,
      title: '🔄 نقل إلى وكالة جديدة',
      body: `تم نقلك بنجاح من وكالة [${fromLabel}] إلى وكالة [${toLabel}] بواسطة الإدارة، وتم تصفير تارجت الألماس الشهري لبدء دورة تارجت جديدة في الوكالة الجديدة.`,
      type: 'system',
      action: 'agency_transferred',
      extraData: { from_agency_id: fromAgencyId, to_agency_id: toAgencyId },
    });

    return { success: true, message: `تم نقل العضو بنجاح إلى وكالة [${toLabel}] وتصفير تارجته الشهري وإرسال إشعار له!` };
  } catch (err: any) {
    return { success: false, message: err?.message || 'حدث خطأ أثناء نقل العضو' };
  }
}

export async function getHostRechargeHistory(userId: string): Promise<HostRechargeRecord[]> {
  try {
    const client = getAdminSupabase() || supabase;
    const records: HostRechargeRecord[] = [];

    // 1. Fetch agent recharge transactions where target_uid == userId
    const { data: agentTxs } = await client
      .from('agent_recharge_transactions')
      .select('*')
      .eq('target_uid', userId)
      .order('created_at', { ascending: false });

    // 2. Fetch refunded status from app_config
    const { data: refundedConfigs } = await client
      .from('app_config')
      .select('key, value')
      .ilike('key', 'refunded_agent_tx_%');

    const refundedMap: Record<string, any> = {};
    (refundedConfigs ?? []).forEach((c: any) => {
      const txId = c.key.replace('refunded_agent_tx_', '');
      refundedMap[txId] = c.value;
    });

    // 3. Fetch agent users to get their name, custom_id, avatar
    const agentIds = Array.from(new Set((agentTxs ?? []).map((t: any) => t.agent_id).filter(Boolean)));
    const agentsMap: Record<string, any> = {};
    if (agentIds.length > 0) {
      const { data: agentUsers } = await client.from('users').select('*');
      (agentUsers ?? []).forEach((u: any) => {
        const uid = u.id || u.uid;
        if (agentIds.includes(uid) || (u.custom_id && agentIds.includes(u.custom_id))) {
          agentsMap[uid] = u;
          if (u.custom_id) agentsMap[u.custom_id] = u;
        }
      });
    }

    for (const t of agentTxs ?? []) {
      const agent = agentsMap[t.agent_id];
      const isRefunded = Boolean(t.is_refunded || refundedMap[t.id]?.is_refunded);
      const refundedInfo = refundedMap[t.id] || {};
      records.push({
        id: t.id,
        source: 'agent',
        source_label: 'وكيل شحن',
        amount_coins: Number(t.amount_coins || 0),
        amount_usd: t.amount_usd ? Number(t.amount_usd) : undefined,
        agent_id: t.agent_id,
        agent_name: agent?.name || agent?.displayName || 'وكيل شحن معتمد',
        agent_custom_id: agent?.custom_id || '',
        agent_avatar: agent?.photo_url || agent?.avatar || '',
        target_uid: t.target_uid,
        target_custom_id: t.target_custom_id || '',
        created_at: t.created_at || new Date().toISOString(),
        is_refunded: isRefunded,
        refunded_at: refundedInfo.refunded_at || t.refunded_at,
        refunded_by: refundedInfo.refunded_by || t.refunded_by,
      });
    }

    // 4. Fetch admin recharge logs from notifications table
    try {
      const { data: notifs } = await client
        .from('notifications')
        .select('*')
        .or(`uid.eq.${userId},target.eq.${userId}`)
        .order('sent_at', { ascending: false });

      for (const n of notifs ?? []) {
        const isCoinsRecharge = n.data?.action === 'coins_recharged' || n.action === 'coins_recharged' || (n.title && n.title.includes('شحن رصيد'));
        if (isCoinsRecharge) {
          const coinsAmt = n.data?.amount || n.data?.coins || 0;
          if (coinsAmt > 0) {
            records.push({
              id: `notif_${n.id}`,
              source: 'admin',
              source_label: 'شحن إداري',
              amount_coins: Number(coinsAmt),
              target_uid: userId,
              created_at: n.sent_at || n.created_at || new Date().toISOString(),
            });
          }
        }
      }
    } catch (_) {}

    // Sort descending by date
    records.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
    return records;
  } catch (err) {
    console.warn('getHostRechargeHistory error:', err);
    return [];
  }
}

export async function refundAgentRechargeTransaction(
  transactionId: string,
  agentId: string,
  targetUid: string,
  amountCoins: number,
  targetCustomId?: string,
  agentCustomId?: string
): Promise<{ success: boolean; message: string }> {
  try {
    const client = getAdminSupabase() || supabase;
    const adminName = getCurrentAdminName() || 'إدارة التطبيق';
    const nowIso = new Date().toISOString();

    // 1. Fetch current balances of target user and agent
    const { data: users } = await client.from('users').select('*').in('id', [targetUid, agentId]);
    let targetUser = (users ?? []).find((u: any) => (u.id || u.uid) === targetUid);
    let agentUser = (users ?? []).find((u: any) => (u.id || u.uid) === agentId);

    // Fallback if searched by uid
    if (!targetUser) {
      const { data: tU } = await client.from('users').select('*').eq('uid', targetUid).maybeSingle();
      targetUser = tU;
    }
    if (!agentUser) {
      const { data: aU } = await client.from('users').select('*').eq('uid', agentId).maybeSingle();
      agentUser = aU;
    }

    if (!targetUser) {
      return { success: false, message: 'لم يتم العثور على بيانات المستخدم المستلم للعملات' };
    }
    if (!agentUser) {
      return { success: false, message: 'لم يتم العثور على بيانات وكيل الشحن' };
    }

    const currentTargetCoins = Number(targetUser.coins || 0);
    const newTargetCoins = Math.max(0, currentTargetCoins - amountCoins);

    const currentAgentCoins = Number(agentUser.coins || 0);
    const newAgentCoins = currentAgentCoins + amountCoins;

    // 2. Update target user coins (deduct)
    await client.from('users').update({ coins: newTargetCoins }).eq('id', targetUid);
    await client.from('users').update({ coins: newTargetCoins }).eq('uid', targetUid);

    // 3. Update agent user coins (credit back)
    await client.from('users').update({ coins: newAgentCoins }).eq('id', agentId);
    await client.from('users').update({ coins: newAgentCoins }).eq('uid', agentId);

    // 4. Mark transaction as refunded in app_config
    await client.from('app_config').upsert({
      key: `refunded_agent_tx_${transactionId}`,
      value: {
        is_refunded: true,
        transaction_id: transactionId,
        amount_coins: amountCoins,
        agent_id: agentId,
        target_uid: targetUid,
        refunded_at: nowIso,
        refunded_by: adminName,
      },
    });

    // Also attempt updating agent_recharge_transactions table if column exists
    try {
      await client.from('agent_recharge_transactions').update({
        is_refunded: true,
        refunded_at: nowIso,
        refunded_by: adminName,
      }).eq('id', transactionId);
    } catch (_) {}

    // 5. Send notification to Agent
    const targetDisplayId = targetCustomId || targetUser.custom_id || targetUid.slice(0, 8);
    await sendSystemNotification({
      userId: agentId,
      title: '↩️ تم استرجاع شحن كوينز خاطئ لمحفظتك',
      body: `قامت الإدارة باسترجاع الشحن الخاطئ بقيمة ${amountCoins.toLocaleString()} كوينز من المستخدم (ID: ${targetDisplayId}) وإعادة الرصيد إلى محفظتك بنجاح. رصيدك الآن: ${newAgentCoins.toLocaleString()} عملة.`,
      type: 'system',
      action: 'agent_recharge_refunded',
      extraData: { transaction_id: transactionId, amount_coins: amountCoins, target_uid: targetUid },
    });

    // 6. Send notification to Target User
    await sendSystemNotification({
      userId: targetUid,
      title: '↩️ تنبيه استرجاع شحن كوينز خاطئ',
      body: `قامت الإدارة باسترجاع ${amountCoins.toLocaleString()} كوينز تم شحنها لحسابك بالخطأ وإعادتها إلى وكيل الشحن. رصيدك الحالي الآن: ${newTargetCoins.toLocaleString()} عملة.`,
      type: 'system',
      action: 'user_recharge_reverted',
      extraData: { transaction_id: transactionId, amount_coins: amountCoins },
    });

    return {
      success: true,
      message: `تم بنجاح خصم ${amountCoins.toLocaleString()} كوينز من المستخدم وإعادتها لرصيد وكيل الشحن، مع إرسال إشعار فوري للطرفين!`,
    };
  } catch (err: any) {
    return { success: false, message: err?.message || 'فشلت عملية استرجاع الشحن' };
  }
}

export async function sendSystemNotification(data: {
  userId: string;
  title: string;
  body: string;
  type?: string;
  action?: string;
  extraData?: Record<string, unknown>;
}): Promise<boolean> {
  try {
    const client = getAdminSupabase() || supabase;
    const payload: Record<string, unknown> = {
      title: data.title || 'إشعار من الإدارة',
      body: data.body || '',
      target: data.userId || 'all',
      uid: data.userId && data.userId !== 'all' ? data.userId : null,
      type: data.type || (data.action ? data.action : 'system'),
      data: {
        ...(data.extraData || {}),
        action: data.action || data.type || 'system',
      },
      sent_at: new Date().toISOString(),
    };
    await client.from('notifications').insert(payload);
    return true;
  } catch (e) {
    console.warn('sendSystemNotification failed:', e);
    return false;
  }
}

export async function getUserOriginalCustomId(uid: string): Promise<string> {
  const client = getAdminSupabase() || supabase;
  try {
    const { data: user } = await client.from('users').select('custom_id, original_custom_id').eq('uid', uid).maybeSingle();
    if (user?.original_custom_id) {
      return String(user.original_custom_id).trim();
    }
    const { data: cfg } = await client.from('app_config').select('value').eq('key', `orig_cid_${uid}`).maybeSingle();
    if (cfg?.value?.originalId) {
      return String(cfg.value.originalId).trim();
    }
    if (typeof cfg?.value === 'string' && cfg.value.trim()) {
      return cfg.value.trim();
    }
  } catch (e) {
    console.warn('getUserOriginalCustomId error:', e);
  }
  return '';
}

export async function setUserOriginalCustomId(uid: string, originalId: string): Promise<void> {
  if (!uid || !originalId) return;
  const client = getAdminSupabase() || supabase;
  const cleanId = String(originalId).trim();
  try {
    await client.from('users').update({ original_custom_id: cleanId }).eq('uid', uid);
  } catch {
    // If column missing in users table, ignore error
  }
  try {
    await client.from('app_config').upsert({
      key: `orig_cid_${uid}`,
      value: { originalId: cleanId, savedAt: Date.now() },
    });
  } catch (err) {
    console.warn('setUserOriginalCustomId app_config error:', err);
  }
}

async function mapFoundUserProfile(u: any) {
  if (!u) return null;
  const uid = String(u.uid || u.id || '');
  const customId = String(u.custom_id || u.customId || u.display_id || (uid ? uid.slice(0, 8) : ''));
  let origId = String(u.original_custom_id || u.originalCustomId || '').trim();
  if (!origId && uid) {
    origId = await getUserOriginalCustomId(uid);
  }
  const isSpecial = Boolean(
    (origId && origId !== customId) ||
    (customId && !isNaN(Number(customId)) && customId.length <= 6)
  );

  return {
    id: uid,
    uid: uid,
    name: u.name || u.display_name || 'بدون اسم',
    custom_id: customId,
    original_custom_id: origId || undefined,
    is_special_id: isSpecial,
    photo_url: u.photo_url || u.photoUrl || u.avatar || '',
    coins: Number(u.coins || 0),
    diamonds: Number(u.diamonds || 0),
    agency_id: u.agency_id || undefined,
    is_recharge_agent: Boolean(u.is_recharge_agent || u.isRechargeAgent || u.is_agent),
  };
}

export async function searchUserProfile(queryStr: string): Promise<{
  id: string;
  uid: string;
  name: string;
  custom_id: string;
  original_custom_id?: string;
  is_special_id?: boolean;
  photo_url: string;
  coins: number;
  diamonds?: number;
  agency_id?: string;
  is_recharge_agent?: boolean;
} | null> {
  const q = queryStr.trim();
  if (!q) return null;
  const qLower = q.toLowerCase();

  const client = getAdminSupabase() || supabase;

  try {
    // 1. Check custom_id directly (both string and numeric)
    const { data: byCid, error: errCid } = await client
      .from('users')
      .select('*')
      .eq('custom_id', q)
      .limit(1);

    if (!errCid && byCid && byCid.length > 0) {
      return await mapFoundUserProfile(byCid[0]);
    }

    if (!isNaN(Number(q))) {
      const { data: byNumCid } = await client
        .from('users')
        .select('*')
        .eq('custom_id', Number(q))
        .limit(1);
      if (byNumCid && byNumCid.length > 0) {
        return await mapFoundUserProfile(byNumCid[0]);
      }
    }

    // 2. Check by uid
    const { data: byUid, error: errUid } = await client
      .from('users')
      .select('*')
      .eq('uid', q)
      .limit(1);

    if (!errUid && byUid && byUid.length > 0) {
      return await mapFoundUserProfile(byUid[0]);
    }

    // 3. Check by id (uuid)
    const { data: byId } = await client
      .from('users')
      .select('*')
      .eq('id', q)
      .limit(1);

    if (byId && byId.length > 0) {
      return await mapFoundUserProfile(byId[0]);
    }

    // 4. Check by name (ilike search)
    const { data: byName } = await client
      .from('users')
      .select('*')
      .ilike('name', `%${q}%`)
      .limit(1);

    if (byName && byName.length > 0) {
      return await mapFoundUserProfile(byName[0]);
    }

    // 5. Fallback in-memory search over top users
    const { data: allUsers } = await client
      .from('users')
      .select('*')
      .limit(300);

    if (allUsers && Array.isArray(allUsers)) {
      const found = allUsers.find((u: any) => {
        const uid = String(u.id || u.uid || '').toLowerCase();
        const cid = String(u.custom_id || u.customId || u.display_id || '').toLowerCase();
        const name = String(u.name || u.display_name || '').toLowerCase();
        return uid === qLower || cid === qLower || (name && name.includes(qLower));
      });
      if (found) {
        return await mapFoundUserProfile(found);
      }
    }
  } catch (e) {
    console.warn('searchUserProfile failed:', e);
  }
  return null;
}

export async function sendAgencyInvitation(params: {
  userId: string;
  agencyName: string;
  agencyId?: string;
  adminName?: string;
  agencyLogo?: string;
  type?: 'host' | 'recharge';
}): Promise<boolean> {
  const adminName = params.adminName || 'إدارة التطبيق';
  return await sendSystemNotification({
    userId: params.userId,
    title: 'دعوة لفتح وكالة جديدة 🏢',
    body: `دعاك المشرف [${adminName}] لتكون رئيساً لوكالة [${params.agencyName}]. هل تود قبول فتح الوكالة؟`,
    type: 'agency_invite',
    action: 'agency_invite',
    extraData: {
      agency_name: params.agencyName,
      agency_id: params.agencyId || '',
      agency_logo: params.agencyLogo || '',
      admin_name: adminName,
      agency_type: params.type || 'host',
      invited_at: new Date().toISOString(),
    },
  });
}

export async function updateRechargeAgency(userId: string, data: {
  recharge_agency_name?: string;
  recharge_agency_logo?: string;
  whatsapp_number?: string;
  coins?: number;
  coinsMode?: 'set' | 'add';
  recharge_commission_rate?: number;
  adminName?: string;
}): Promise<boolean> {
  try {
    const client = getAdminSupabase() || supabase;
    let resolvedUid = userId.trim();
    // Resolve user if userId is a custom numeric/string ID or UID
    const u = await searchUserProfile(resolvedUid);
    if (u) {
      resolvedUid = u.uid || u.id;
    }

    const adminName = data.adminName || 'إدارة التطبيق';
    const nowIso = new Date().toISOString();
    const agencyName = data.recharge_agency_name || 'وكالة الشحن المعتمدة';

    // 1. Prepare user update payload
    const userUpdate: Record<string, any> = {
      is_recharge_agent: true,
      recharge_agency_name: agencyName,
      recharge_agency_logo: data.recharge_agency_logo || '',
      whatsapp_number: data.whatsapp_number || '',
      updated_at: nowIso,
    };

    if (data.coins !== undefined && data.coins >= 0) {
      if (data.coinsMode === 'add') {
        const currentCoins = u ? u.coins : 0;
        userUpdate.coins = currentCoins + data.coins;
      } else {
        userUpdate.coins = data.coins;
      }
    }

    // Write to users in Supabase
    try {
      await client.from('users').update(userUpdate).eq('uid', resolvedUid);
      await client.from('users').update(userUpdate).eq('id', resolvedUid);
      if (u?.custom_id) {
        await client.from('users').update(userUpdate).eq('custom_id', u.custom_id);
      }
    } catch (sbErr) {
      console.warn('updateRechargeAgency supabase warning:', sbErr);
    }



    // Send official opening notification
    await sendSystemNotification({
      userId: resolvedUid,
      title: 'مبروك! تم تفعيل وكالة الشحن 🎉',
      body: `مبروك! تم تفعيل وكالة الشحن المعتمدة [${agencyName}] لحسابك بنجاح بواسطة المشرف [${adminName}]. يمكنك الآن البدء بشحن العملات للمستخدمين وإدارة الرصيد.`,
      type: 'agency_recharge_approved',
      action: 'recharge_agency_approved',
      extraData: {
        admin_name: adminName,
        agency_name: agencyName,
        whatsapp_number: data.whatsapp_number || '',
        commission_rate: data.recharge_commission_rate ?? 5,
        activated_at: nowIso,
      },
    });

    return true;
  } catch (e) {
    console.error('updateRechargeAgency failed:', e);
    return false;
  }
}

export async function revokeRechargeAgency(userId: string): Promise<boolean> {
  try {
    const client = getAdminSupabase() || supabase;
    let resolvedUid = userId.trim();
    const u = await searchUserProfile(resolvedUid);
    if (u) resolvedUid = u.uid || u.id;

    const userUpdate = {
      is_recharge_agent: false,
      updated_at: new Date().toISOString(),
    };

    try {
      await client.from('users').update(userUpdate).eq('uid', resolvedUid);
      await client.from('users').update(userUpdate).eq('id', resolvedUid);
      if (u?.custom_id) {
        await client.from('users').update(userUpdate).eq('custom_id', u.custom_id);
      }
    } catch (_) {}



    await sendSystemNotification({
      userId: resolvedUid,
      title: 'إلغاء صفة وكيل الشحن',
      body: 'تم إلغاء صفة وكيل الشحن لحسابك من قبل الإدارة.',
      type: 'system',
      action: 'recharge_agency_revoked',
    });

    return true;
  } catch (e) {
    console.error('revokeRechargeAgency failed:', e);
    return false;
  }
}

// ---- Agency Ledger ----

export async function getAgencyLedger(agencyId?: string, limit = 100): Promise<AgencyLedgerEntryModel[]> {
  try {
    let query = supabase.from('agency_diamond_ledger').select('*').order('created_at', { ascending: false }).limit(limit)
    if (agencyId) query = query.eq('agency_id', agencyId)
    const { data } = await query
    return mapList<AgencyLedgerEntryModel>((data ?? []).map((e: any) => ({
      ...e,
      user_name: e.user_id?.slice(0, 8),
      agency_name: e.agency_name ?? e.agency_id?.slice(0, 8),
    })))
  } catch { return [] }
}

// ---- Withdrawal Requests ----

export async function getWithdrawalRequests(status?: string): Promise<AgencyWithdrawalRequestModel[]> {
  try {
    let query = supabase.from('agency_withdrawal_requests').select('*').order('created_at', { ascending: false })
    if (status) query = query.eq('status', status)
    const { data, error } = await query
    if (!error && data && data.length > 0) {
      return mapList<AgencyWithdrawalRequestModel>((data ?? []).map((w: any) => ({
        ...w,
        user_name: w.user_id?.slice(0, 8),
        agency_name: w.agency_name ?? w.agency_id?.slice(0, 8),
      })))
    }
  } catch (e) {
    console.warn('getWithdrawalRequests supabase error, trying firestore fallback:', e)
  }
  return []
}

export async function approveWithdrawal(id: string): Promise<boolean> {

  try {
    await supabase.from('agency_withdrawal_requests').update({ status: 'approved' }).eq('id', id)
    return true
  } catch { return false }
}

export async function rejectWithdrawal(id: string): Promise<boolean> {

  try {
    await supabase.from('agency_withdrawal_requests').update({ status: 'rejected' }).eq('id', id)
    return true
  } catch { return false }
}

// ---- CPs ----

export async function getCPs(): Promise<CPModel[]> {
  try {
    const { data } = await supabase.from('cps').select('*').order('id')
    return mapList<CPModel>(data ?? [])
  } catch {
    return []
  }
}

export function subscribeCPs(cb: (cps: CPModel[]) => void) {
  const sub = supabase.channel('cps').on('postgres_changes', { event: '*', schema: 'public', table: 'cps' }, () => {
    getCPs().then(cb)
  }).subscribe()
  return () => { try { supabase.removeChannel(sub) } catch {} }
}

// ---- Gift User Items (Necklace, Badge, Frame, Special ID) ----

export async function giftUserItems(uid: string, items: {
  necklaceId?: string;
  badgeId?: string;
  frameId?: string;
  specialId?: string;
}) {
  const client = getAdminSupabase() || supabase;
  try {
    const { data: user } = await client
      .from('users')
      .select('owned_necklaces, owned_badges, owned_items, active_necklace, active_frame, custom_id')
      .eq('uid', uid)
      .maybeSingle();

    if (!user) return;

    const updates: Record<string, any> = {};

    if (items.necklaceId && items.necklaceId.trim()) {
      const cur = Array.isArray(user.owned_necklaces) ? user.owned_necklaces : [];
      updates.owned_necklaces = Array.from(new Set([...cur, items.necklaceId.trim()]));
      updates.active_necklace = items.necklaceId.trim();
    }

    if (items.badgeId && items.badgeId.trim()) {
      const cur = Array.isArray(user.owned_badges) ? user.owned_badges : [];
      updates.owned_badges = Array.from(new Set([...cur, items.badgeId.trim()]));
    }

    if (items.frameId && items.frameId.trim()) {
      const cur = Array.isArray(user.owned_items) ? user.owned_items : [];
      updates.owned_items = Array.from(new Set([...cur, items.frameId.trim()]));
      updates.active_frame = items.frameId.trim();
    }

    if (items.specialId && items.specialId.trim()) {
      updates.custom_id = items.specialId.trim();
    }

    if (Object.keys(updates).length > 0) {
      await client.from('users').update(updates).eq('uid', uid);
    }
  } catch (err) {
    console.warn('giftUserItems error:', err);
  }
}

// ---- BD Management ----

export async function getBDManagers(): Promise<BDModel[]> {
  const client = getAdminSupabase() || supabase;
  try {
    // 1. Fetch all metadata from app_config (where key starts with bd_meta_)
    const { data: configs } = await client
      .from('app_config')
      .select('key, value')
      .like('key', 'bd_meta_%');

    const configMap: Record<string, any> = {};
    (configs || []).forEach(c => {
      const u = c.key.replace('bd_meta_', '');
      configMap[u] = c.value;
    });

    const bdUids = Object.keys(configMap).filter(Boolean);

    // 2. Fetch corresponding users with safe standard columns only
    let bdUsers: any[] = [];
    if (bdUids.length > 0) {
      const { data: uData } = await client
        .from('users')
        .select('uid, custom_id, name, email, photo_url, created_at')
        .in('uid', bdUids);
      if (uData) bdUsers = uData;
    }

    // 3. Fetch all host_agencies to compute statistics
    const { data: agencies } = await client
      .from('host_agencies')
      .select('id, name, owner_uid, member_count, total_diamonds_monthly, total_diamonds_cumulative, data, created_at');

    // 4. Fetch admin users for supervisor names
    const admins = await getAdminUsers();
    const adminMap: Record<string, string> = {};
    admins.forEach(a => { adminMap[a.uid] = a.displayName || a.email; });

    const allBds: Map<string, BDModel> = new Map();

    // Map each BD
    bdUids.forEach(uid => {
      if (configMap[uid]?.status === 'revoked') return;
      const meta = configMap[uid] || {};
      const u = bdUsers.find((user: any) => user.uid === uid);
      const supId = meta.supervisorId || '';

      allBds.set(uid, {
        id: uid,
        uid: uid,
        appId: meta.appId || u?.custom_id || '',
        name: meta.name || u?.name || 'BD Manager',
        email: meta.email || u?.email || '',
        photoUrl: meta.photoUrl || u?.photo_url || '',
        supervisorId: supId,
        supervisorName: adminMap[supId] || meta.supervisorName || supId,
        agencyCount: 0,
        totalHosts: 0,
        totalEarnings: 0,
        salary: Number(meta.salary ?? 0),
        commissionRate: Number(meta.commissionRate ?? 10),
        specialId: meta.specialId || u?.custom_id || '',
        giftedFrame: meta.giftedFrame,
        giftedBadge: meta.giftedBadge,
        giftedNecklace: meta.giftedNecklace,
        status: 'active',
        createdAt: u?.created_at || meta.createdAt,
      });
    });

    // Aggregate agency statistics for each BD
    (agencies || []).forEach(ag => {
      const bdUid = ag.data?.bd_uid || ag.data?.bdUid || ag.owner_uid;
      if (bdUid && allBds.has(bdUid)) {
        const bd = allBds.get(bdUid)!;
        bd.agencyCount += 1;
        bd.totalHosts += Number(ag.member_count || 1);
        bd.totalEarnings += Number(ag.total_diamonds_monthly || ag.total_diamonds_cumulative || 0);
      }
    });

    return Array.from(allBds.values());
  } catch (err) {
    console.error('getBDManagers error:', err);
    return [];
  }
}

export const getBDs = getBDManagers;

export async function assignBDManager(params: {
  uid: string;
  appId?: string;
  name?: string;
  supervisorId?: string;
  salary?: number;
  commissionRate?: number;
  specialId?: string;
  frameId?: string;
  badgeId?: string;
  necklaceId?: string;
}) {
  const client = getAdminSupabase() || supabase;
  const { uid, appId, name, supervisorId, salary = 0, commissionRate = 10, specialId, frameId, badgeId, necklaceId } = params;

  // 1. Update public.users
  const updates: Record<string, any> = {
    is_bd: true,
    bd_supervisor_id: supervisorId || null,
    bd_salary: salary,
    bd_commission_rate: commissionRate,
  };
  if (specialId && specialId.trim()) {
    updates.custom_id = specialId.trim();
  }
  try {
    await client.from('users').update(updates).eq('uid', uid);
  } catch (e) {
    console.warn('Update user for BD error:', e);
  }

  // 2. Gift Items (Frame, Badge, Necklace, Special ID)
  await giftUserItems(uid, {
    necklaceId,
    badgeId,
    frameId,
    specialId,
  });

  // 3. Save meta in app_config
  const meta = {
    uid,
    appId: specialId || appId || '',
    name: name || '',
    supervisorId: supervisorId || '',
    salary,
    commissionRate,
    specialId: specialId || '',
    giftedFrame: frameId || '',
    giftedBadge: badgeId || '',
    giftedNecklace: necklaceId || '',
    status: 'active',
    createdAt: new Date().toISOString(),
  };

  try {
    await client.from('app_config').upsert({
      key: 'bd_meta_' + uid,
      value: meta,
    });
  } catch (e) {
    console.warn('Save bd_meta error:', e);
  }
}

export async function updateBDManager(params: {
  uid: string;
  appId?: string;
  supervisorId?: string;
  salary?: number;
  commissionRate?: number;
  specialId?: string;
  frameId?: string;
  badgeId?: string;
  necklaceId?: string;
}) {
  const client = getAdminSupabase() || supabase;
  const { uid, appId, supervisorId, salary = 0, commissionRate = 10, specialId, frameId, badgeId, necklaceId } = params;

  // 1. Update public.users
  const updates: Record<string, any> = {
    is_bd: true,
    bd_supervisor_id: supervisorId || null,
    bd_salary: salary,
    bd_commission_rate: commissionRate,
  };
  if (specialId && specialId.trim()) {
    updates.custom_id = specialId.trim();
  }
  try {
    await client.from('users').update(updates).eq('uid', uid);
  } catch (e) {
    console.warn('Update user for BD error:', e);
  }

  // 2. Gift in-app items if specified
  if (necklaceId || badgeId || frameId || specialId) {
    await giftUserItems(uid, {
      necklaceId,
      badgeId,
      frameId,
      specialId,
    });
  }

  // 3. Update bd_meta in app_config
  try {
    const { data: curMeta } = await client.from('app_config').select('value').eq('key', 'bd_meta_' + uid).maybeSingle();
    const cur = (curMeta?.value as any) || {};
    const meta = {
      ...cur,
      uid,
      appId: specialId || appId || cur.appId || '',
      supervisorId: supervisorId !== undefined ? supervisorId : (cur.supervisorId || ''),
      salary: salary !== undefined ? salary : (cur.salary ?? 0),
      commissionRate: commissionRate !== undefined ? commissionRate : (cur.commissionRate ?? 10),
      specialId: specialId !== undefined ? specialId : (cur.specialId || ''),
      giftedFrame: frameId || cur.giftedFrame || '',
      giftedBadge: badgeId || cur.giftedBadge || '',
      giftedNecklace: necklaceId || cur.giftedNecklace || '',
      status: 'active',
      updatedAt: new Date().toISOString(),
    };

    await client.from('app_config').upsert({
      key: 'bd_meta_' + uid,
      value: meta,
    });
  } catch (e) {
    console.warn('Update bd_meta error:', e);
  }
}

export async function revokeBDManager(uid: string) {
  const client = getAdminSupabase() || supabase;
  // 1. Clear is_bd in users
  try {
    await client.from('users').update({
      is_bd: false,
      bd_supervisor_id: null,
      bd_salary: 0,
      bd_commission_rate: 0,
    }).eq('uid', uid);
  } catch (e) {
    console.warn('Revoke user is_bd error:', e);
  }

  // 2. Delete / update meta in app_config
  try {
    await client.from('app_config').delete().eq('key', 'bd_meta_' + uid);
  } catch (e) {
    console.warn('Delete bd_meta error:', e);
  }
}

export async function getBDAgencies(bdUid: string): Promise<BDAgencyDetail[]> {
  const client = getAdminSupabase() || supabase;
  try {
    const { data } = await client
      .from('host_agencies')
      .select('*')
      .order('created_at', { ascending: false });

    if (!data) return [];

    const filtered = data.filter(a => {
      const assignedBd = a.data?.bd_uid || a.data?.bdUid;
      return assignedBd === bdUid || a.owner_uid === bdUid;
    });

    return filtered.map(a => ({
      id: a.id,
      name: a.name || 'Agency',
      ownerUid: a.owner_uid,
      ownerName: a.name || '',
      memberCount: a.member_count || 1,
      monthlyDiamonds: a.total_diamonds_monthly || 0,
      totalDiamonds: a.total_diamonds_cumulative || 0,
      status: a.status || 'active',
      createdAt: a.created_at,
    }));
  } catch (e) {
    console.error('getBDAgencies error:', e);
    return [];
  }
}

export async function linkAgencyToBD(agencyId: string, bdUid: string) {
  const client = getAdminSupabase() || supabase;
  try {
    const { data: ag } = await client.from('host_agencies').select('data').eq('id', agencyId).maybeSingle();
    const curData = ag?.data || {};
    await client.from('host_agencies').update({
      data: { ...curData, bd_uid: bdUid },
    }).eq('id', agencyId);
  } catch (e) {
    console.error('linkAgencyToBD error:', e);
  }
}

export function subscribeBDs(cb: (bds: BDModel[]) => void) {
  const sub = supabase.channel('bds_sync').on('postgres_changes', { event: '*', schema: 'public', table: 'users' }, () => {
    getBDManagers().then(cb)
  }).subscribe()
  return () => { try { supabase.removeChannel(sub) } catch {} }
}

// ---- Gifted Items ----

export async function getGiftedItems(): Promise<GiftedItem[]> {
  try {
    const { data } = await supabase.from('gifted_items').select('*').order('sent_at', { ascending: false })
    return mapList<GiftedItem>(data ?? [])
  } catch {
    return []
  }
}

export function subscribeGiftedItems(cb: (items: GiftedItem[]) => void) {
  const sub = supabase.channel('gifted_items').on('postgres_changes', { event: '*', schema: 'public', table: 'gifted_items' }, () => {
    getGiftedItems().then(cb)
  }).subscribe()
  return () => { try { supabase.removeChannel(sub) } catch {} }
}

export async function sendGiftedItem(uid: string, item: StoreItemModel, sentBy: string, sentByName: string, expiryDays: number): Promise<string> {
  try {
    const id = `gi_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`
    const now = Date.now()
    await supabase.from('gifted_items').insert({
      id,
      uid,
      item_id: item.itemId,
      item_category: item.category,
      item_name: item.name,
      item_icon: item.iconAsset,
      svga_asset: item.svgaAsset,
      video_asset: item.videoAsset,
      sent_by: sentBy,
      sent_by_name: sentByName,
      sent_at: now,
      expires_at: now + expiryDays * 86400000,
    })
    return id
  } catch (e) {
    console.warn('sendGiftedItem failed:', e)
    throw e
  }
}

export async function revokeGiftedItem(id: string) {
  try {
    await supabase.from('gifted_items').delete().eq('id', id)
  } catch (e) {
    console.warn('revokeGiftedItem failed:', e)
  }
}

// ---- Necklaces ----

export async function getNecklaces(): Promise<NecklaceConfig[]> {
  try {
    const client = getAdminSupabase() || supabase
    const { data, error } = await client.from('necklaces').select('*')
    if (!error && data && data.length > 0) {
      return (data ?? []).map((item: any): NecklaceConfig => ({
        id: item.id,
        name: item.name || '',
        name_ar: item.name_ar || '',
        name_en: item.name_en || '',
        description_ar: item.description_ar || '',
        description_en: item.description_en || '',
        svgaUrl: item.svga_url || item.svgaUrl || undefined,
        imageUrl: item.image_url || item.imageUrl || undefined,
        price: item.price || 0,
        sortOrder: item.sort_order ?? item.sortOrder ?? 0,
        isActive: item.is_active ?? item.isActive ?? true,
        type: item.type || 'admin',
        requiredRechargeLevel: item.required_recharge_level || item.requiredRechargeLevel || 0,
      }))
    }
  } catch (e) {
    console.warn('getNecklaces supabase error, trying firestore fallback:', e)
  }
  return []
}

export async function updateNecklace(id: string, data: Partial<NecklaceConfig>) {
  

  // 2. Write to Supabase
  try {
    const client = getAdminSupabase() || supabase
    const payload = toSnakeCase(data as Record<string, unknown>)
    await client.from('necklaces').upsert({ id, ...payload })
  } catch (e) {
    console.warn('Supabase updateNecklace warning:', e)
  }
}

export async function deleteNecklace(id: string) {

  try {
    const client = getAdminSupabase() || supabase
    await client.from('necklaces').delete().eq('id', id)
  } catch (e) {
    console.warn('deleteNecklace failed:', e)
  }
}

// ---- User VIPs ----

export async function getUserVIPs(): Promise<UserVIP[]> {
  try {
    const client = getAdminSupabase() || supabase
    const { data: vips } = await client.from('user_vips').select('*, user:users(*)').order('purchased_at', { ascending: false })
    const rows = vips ?? []
    const uids = [...new Set(rows.map(r => (r as any).uid).filter(Boolean))] as string[]
    const usersMap: Record<string, any> = {}
    for (const uid of uids) {
      const { data: u } = await supabase.from('users').select('*').eq('uid', uid).single()
      if (u) usersMap[uid] = u
    }
    const enriched = rows.map((r: any) => ({ ...r, user: usersMap[r.uid] ?? null }))
    return mapList<UserVIP>(enriched)
  } catch {
    return []
  }
}

export async function giftVIP(uid: string, tier: number, giftedBy: string, expiryDays?: number): Promise<void> {
  try {
    const expiresAt = expiryDays ? new Date(Date.now() + expiryDays * 86400000).toISOString() : null
    await supabase.from('user_vips').upsert({
      uid,
      tier,
      purchased_at: new Date().toISOString(),
      expires_at: expiresAt,
      gifted_by: giftedBy,
    })
  } catch (e) {
    console.warn('giftVIP failed:', e)
  }
}

export async function revokeUserVIP(uid: string, tier: number) {
  try {
    await supabase.from('user_vips').delete().eq('uid', uid).eq('tier', tier)
  } catch (e) {
    console.warn('revokeUserVIP failed:', e)
  }
}

// ---- Unified User Gifting (Store, Special IDs, VIP, Badges & Necklaces) ----

export async function getUnifiedGiftedItems(): Promise<GiftedItem[]> {
  const client = getAdminSupabase() || supabase;
  try {
    const { data: gifts, error } = await client
      .from('gifted_items')
      .select('*')
      .order('sent_at', { ascending: false });

    if (error) {
      console.warn('getUnifiedGiftedItems error:', error);
      return [];
    }
    const rows = gifts || [];
    if (rows.length === 0) return [];

    const uids = [...new Set(rows.map((r: any) => r.uid).filter(Boolean))];
    const { data: users } = await client
      .from('users')
      .select('uid, name, custom_id, original_custom_id, photo_url')
      .in('uid', uids);

    const userMap: Record<string, any> = {};
    (users || []).forEach((u: any) => {
      userMap[u.uid] = u;
    });

    return rows.map((r: any) => ({
      id: String(r.id),
      uid: String(r.uid),
      item_id: String(r.item_id || ''),
      item_category: String(r.item_category || ''),
      item_name: String(r.item_name || ''),
      item_icon: String(r.item_icon || ''),
      svga_asset: r.svga_asset || null,
      video_asset: r.video_asset || null,
      sent_by: String(r.sent_by || 'admin'),
      sent_by_name: String(r.sent_by_name || 'الإدارة'),
      sent_at: Number(r.sent_at || 0),
      expires_at: Number(r.expires_at || 0),
      user: userMap[r.uid] ? {
        uid: userMap[r.uid].uid,
        name: userMap[r.uid].name || 'بدون اسم',
        custom_id: userMap[r.uid].custom_id || '',
        original_custom_id: userMap[r.uid].original_custom_id || '',
        photo_url: userMap[r.uid].photo_url || '',
      } : undefined,
    }));
  } catch (err) {
    console.error('getUnifiedGiftedItems error:', err);
    return [];
  }
}

export async function sendUnifiedGift(params: {
  uid: string;
  type: 'store' | 'special_id' | 'vip' | 'badge' | 'necklace';
  itemId: string;
  itemName: string;
  itemCategory: string;
  itemIcon?: string;
  svgaAsset?: string;
  videoAsset?: string;
  expiryDays?: number; // 0 or undefined for permanent
  sentBy?: string;
  sentByName?: string;
}): Promise<{ success: boolean; message?: string }> {
  const client = getAdminSupabase() || supabase;
  const { uid, type, itemId, itemName, itemCategory, itemIcon, svgaAsset, videoAsset, expiryDays = 0, sentBy = 'admin', sentByName = 'الإدارة' } = params;

  try {
    // 1. Verify user exists
    const { data: user, error: uErr } = await client
      .from('users')
      .select('*')
      .eq('uid', uid)
      .maybeSingle();

    if (uErr || !user) {
      return { success: false, message: 'المستخدم غير موجود' };
    }

    const giftId = 'gi_' + Date.now() + '_' + Math.random().toString(36).substring(2, 6);
    const sentAt = Date.now();
    const expiresAt = expiryDays > 0 ? Date.now() + (expiryDays * 86400000) : 0;

    if (type === 'special_id') {
      const specialIdClean = itemId.trim();
      if (!specialIdClean) {
        return { success: false, message: 'يرجى إدخال الآيدي المميز' };
      }
      // Check availability
      const avail = await checkCustomIdAvailable(specialIdClean, uid);
      if (!avail.available) {
        return { success: false, message: avail.reason || 'هذا الآيدي مستخدم بالفعل' };
      }

      // Check if user already has an original custom ID saved
      const existingOrig = await getUserOriginalCustomId(uid);
      if (!existingOrig) {
        const currentCid = String(user.custom_id || user.customId || '').trim();
        if (currentCid && currentCid !== specialIdClean) {
          await setUserOriginalCustomId(uid, currentCid);
        }
      }

      // Update user custom_id
      await updateUser(uid, { customId: specialIdClean });

      // Save to gifted_items
      await client.from('gifted_items').insert({
        id: giftId,
        uid,
        item_id: specialIdClean,
        item_category: 'special_id',
        item_name: itemName || `آيدي مميز: ${specialIdClean}`,
        item_icon: itemIcon || 'assets/mipmap-xxhdpi/ic_id_card_prop.png',
        sent_by: sentBy,
        sent_by_name: sentByName,
        sent_at: sentAt,
        expires_at: expiresAt,
      });

      // Send notification
      await sendGiftSystemNotification({
        client, uid,
        title: 'هدية جديدة من الإدارة 🎁',
        body: `قام المشرف ${sentByName} بإهدائك: آيدي مميز (${specialIdClean})`,
        itemIcon: itemIcon || 'assets/mipmap-xxhdpi/ic_id_card_prop.png',
        itemName: itemName || `آيدي مميز: ${specialIdClean}`,
        sentByName,
      });

      return { success: true, message: `تم إهداء الآيدي المميز (${specialIdClean}) بنجاح والاحتفاظ بالآيدي القديم!` };
    }

    if (type === 'store') {
      // Add to owned_items in users table
      const currentOwned = Array.isArray(user.owned_items) ? user.owned_items : [];
      if (!currentOwned.includes(itemId)) {
        await client.from('users').update({
          owned_items: [...currentOwned, itemId],
        }).eq('uid', uid);
      }

      // Add to user_backpack
      try {
        await client.from('user_backpack').upsert({
          user_id: uid,
          item_id: itemId,
          item_type: itemCategory || 'store',
          expires_at: expiresAt > 0 ? new Date(expiresAt).toISOString() : null,
        });
      } catch (bpErr) {
        console.warn('user_backpack insert warning:', bpErr);
      }

      // Add to gifted_items
      await client.from('gifted_items').insert({
        id: giftId,
        uid,
        item_id: itemId,
        item_category: itemCategory || 'frame',
        item_name: itemName,
        item_icon: itemIcon || '',
        svga_asset: svgaAsset || null,
        video_asset: videoAsset || null,
        sent_by: sentBy,
        sent_by_name: sentByName,
        sent_at: sentAt,
        expires_at: expiresAt,
      });

      // Send notification
      await sendGiftSystemNotification({
        client, uid,
        title: 'هدية جديدة من الإدارة 🎁',
        body: `قام المشرف ${sentByName} بإهدائك: ${itemName}`,
        itemIcon: itemIcon || '',
        itemName,
        sentByName,
      });

      return { success: true, message: `تم إهداء العنصر (${itemName}) بنجاح!` };
    }

    if (type === 'vip') {
      const tierNum = Number(itemId) || 1;
      await giftVIP(uid, tierNum, sentByName, expiryDays > 0 ? expiryDays : undefined);

      await client.from('gifted_items').insert({
        id: giftId,
        uid,
        item_id: String(tierNum),
        item_category: 'vip',
        item_name: itemName || `VIP ${tierNum}`,
        item_icon: itemIcon || 'assets/mipmap-xxhdpi/mine_mall_tab_vip_ic.webp',
        sent_by: sentBy,
        sent_by_name: sentByName,
        sent_at: sentAt,
        expires_at: expiresAt,
      });

      // Send notification
      await sendGiftSystemNotification({
        client, uid,
        title: 'هدية جديدة من الإدارة 🎁',
        body: `قام المشرف ${sentByName} بإهدائك رتبة: ${itemName || 'VIP ' + tierNum}`,
        itemIcon: itemIcon || 'assets/mipmap-xxhdpi/mine_mall_tab_vip_ic.webp',
        itemName: itemName || `VIP ${tierNum}`,
        sentByName,
      });

      return { success: true, message: `تم إهداء رتبة (${itemName || 'VIP ' + tierNum}) بنجاح!` };
    }

    if (type === 'badge') {
      const currentBadges = Array.isArray(user.owned_badges) ? user.owned_badges : [];
      if (!currentBadges.includes(itemId)) {
        await client.from('users').update({
          owned_badges: [...currentBadges, itemId],
        }).eq('uid', uid);
      }

      await client.from('gifted_items').insert({
        id: giftId,
        uid,
        item_id: itemId,
        item_category: 'badge',
        item_name: itemName,
        item_icon: itemIcon || 'assets/mipmap-xxhdpi/ic_new_user_badge.png',
        sent_by: sentBy,
        sent_by_name: sentByName,
        sent_at: sentAt,
        expires_at: expiresAt,
      });

      // Send notification
      await sendGiftSystemNotification({
        client, uid,
        title: 'هدية جديدة من الإدارة 🎁',
        body: `قام المشرف ${sentByName} بإهدائك شارة: ${itemName}`,
        itemIcon: itemIcon || 'assets/mipmap-xxhdpi/ic_new_user_badge.png',
        itemName,
        sentByName,
      });

      return { success: true, message: `تم إهداء الشارة (${itemName}) بنجاح!` };
    }

    if (type === 'necklace') {
      const currentNecklaces = Array.isArray(user.owned_necklaces) ? user.owned_necklaces : [];
      const updates: Record<string, any> = {
        active_necklace: itemId,
      };
      if (!currentNecklaces.includes(itemId)) {
        updates.owned_necklaces = [...currentNecklaces, itemId];
      }
      await client.from('users').update(updates).eq('uid', uid);

      await client.from('gifted_items').insert({
        id: giftId,
        uid,
        item_id: itemId,
        item_category: 'necklace',
        item_name: itemName,
        item_icon: itemIcon || '',
        svga_asset: svgaAsset || null,
        sent_by: sentBy,
        sent_by_name: sentByName,
        sent_at: sentAt,
        expires_at: expiresAt,
      });

      // Send system notification
      await sendGiftSystemNotification({
        client,
        uid,
        title: 'هدية جديدة من الإدارة 🎁',
        body: `قام المشرف ${sentByName} بإهدائك: ${itemName || 'عنصر جديد'}`,
        itemIcon: itemIcon || '',
        itemName: itemName || '',
        sentByName,
      });

      return { success: true, message: `تم إهداء القلادة (${itemName}) بنجاح!` };
    }

    return { success: false, message: 'نوع إهداء غير معروف' };
  } catch (err: any) {
    console.error('sendUnifiedGift error:', err);
    return { success: false, message: err?.message || 'حدث خطأ أثناء الإهداء' };
  }
}

async function sendGiftSystemNotification(params: {
  client: any;
  uid: string;
  title: string;
  body: string;
  itemIcon: string;
  itemName: string;
  sentByName: string;
}) {
  try {
    const notifId = 'notif_' + Date.now() + '_' + Math.random().toString(36).substring(2, 6);
    await params.client.from('notifications').insert({
      id: notifId,
      uid: params.uid,
      target: params.uid,
      type: 'system',
      title: params.title,
      body: params.body,
      actor_uid: 'admin',
      is_read: false,
      sent_at: new Date().toISOString(),
      created_at: new Date().toISOString(),
      data: {
        action: 'gift_received',
        item_name: params.itemName,
        gift_name: params.itemName,
        gift_image: params.itemIcon,
        image_url: params.itemIcon,
        sent_by_name: params.sentByName,
      },
    });
  } catch (err) {
    console.warn('sendGiftSystemNotification failed:', err);
  }
}

export async function revokeUnifiedGift(giftId: string): Promise<{ success: boolean; message?: string }> {
  const client = getAdminSupabase() || supabase;
  try {
    const { data: gift, error } = await client
      .from('gifted_items')
      .select('*')
      .eq('id', giftId)
      .maybeSingle();

    if (error || !gift) {
      return { success: false, message: 'الهدية غير موجودة أو تم حذفها مسبقاً' };
    }

    const { uid, item_category, item_id } = gift;

    // 1. Fetch user
    const { data: user } = await client.from('users').select('*').eq('uid', uid).maybeSingle();

    if (item_category === 'special_id') {
      // Revert custom_id to original_custom_id
      const origCid = await getUserOriginalCustomId(uid);
      if (origCid && user?.custom_id === item_id) {
        await updateUser(uid, { customId: origCid });
      }
    } else if (item_category === 'vip') {
      await revokeUserVIP(uid, Number(item_id));
    } else if (item_category === 'badge') {
      if (user && Array.isArray(user.owned_badges)) {
        const updated = user.owned_badges.filter((b: string) => b !== item_id);
        await client.from('users').update({ owned_badges: updated }).eq('uid', uid);
      }
    } else if (item_category === 'necklace') {
      if (user) {
        const currentNecklaces = Array.isArray(user.owned_necklaces) ? user.owned_necklaces : [];
        const updated = currentNecklaces.filter((n: string) => n !== item_id);
        const updates: Record<string, any> = { owned_necklaces: updated };
        if (user.active_necklace === item_id) {
          updates.active_necklace = null;
        }
        await client.from('users').update(updates).eq('uid', uid);
      }
    } else {
      // Store items: frame, car, entrance, bubble, etc.
      if (user) {
        const currentOwned = Array.isArray(user.owned_items) ? user.owned_items : [];
        const updated = currentOwned.filter((it: string) => it !== item_id);
        const updates: Record<string, any> = { owned_items: updated };
        if (user.active_frame === item_id) updates.active_frame = null;
        if (user.active_headwear === item_id) updates.active_headwear = null;
        if (user.active_bubble === item_id) updates.active_bubble = null;
        if (user.active_entrance === item_id) updates.active_entrance = null;
        if (user.active_car === item_id) updates.active_car = null;
        if (user.active_cover === item_id) updates.active_cover = null;
        await client.from('users').update(updates).eq('uid', uid);
      }
      try {
        await client.from('user_backpack').delete().eq('user_id', uid).eq('item_id', item_id);
      } catch (_) {}
    }

    // Delete record from gifted_items
    await client.from('gifted_items').delete().eq('id', giftId);

    return { success: true, message: 'تم سحب الهدية بنجاح واسترجاع الحالة السابقة!' };
  } catch (err: any) {
    console.error('revokeUnifiedGift error:', err);
    return { success: false, message: err?.message || 'فشل سحب الهدية' };
  }
}

// ---- Stats ----

export async function getStats(): Promise<{
  totalUsers: number;
  totalRooms: number;
  totalGifts: number;
  totalRevenue: number;
}> {
  try {
    const { count: totalUsers } = await supabase.from('users').select('*', { count: 'exact', head: true })
    const { count: totalRooms } = await supabase.from('rooms').select('*', { count: 'exact', head: true })
    const { data: gifts } = await supabase.from('gifts').select('value')

    let totalRevenue = 0
    if (gifts) {
      gifts.forEach(g => { totalRevenue += (g.value as number) || 0 })
    }
    return {
      totalUsers: totalUsers ?? 0,
      totalRooms: totalRooms ?? 0,
      totalGifts: gifts?.length ?? 0,
      totalRevenue,
    }
  } catch {
    return {
      totalUsers: 0,
      totalRooms: 0,
      totalGifts: 0,
      totalRevenue: 0,
    }
  }
}

// ---- Admin Management ----

export async function getAdminUsers(): Promise<AdminUser[]> {
  try {
    const client = getAdminSupabase() || supabase
    const { data: rows } = await client.from('admin_users').select('*').order('created_at', { ascending: false })
    if (!rows) return []

    // Fetch display names and photo URLs stored in app_config
    const { data: configs } = await client.from('app_config').select('*').like('key', 'admin_meta_%')
    const configMap: Record<string, any> = {}
    if (configs) {
      for (const c of configs) {
        if (c.key && c.value) {
          const uid = c.key.replace('admin_meta_', '')
          configMap[uid] = c.value
        }
      }
    }

    return rows.map((r: any) => {
      const uid = r.uid || r.id
      const meta = configMap[uid] || {}
      const role = r.role === 'superadmin' ? 'super_admin' : (r.role || 'moderator')

      const permsMap: Record<string, boolean> = {}
      if (Array.isArray(r.permissions)) {
        const isAll = r.permissions.includes('all') || r.permissions.includes('*')
        if (isAll) {
          permsMap['all'] = true
          for (const k of ALL_PERMISSION_KEYS) {
            permsMap[k] = true
          }
        }
        for (const p of r.permissions) {
          permsMap[p] = true
        }
      } else if (typeof r.permissions === 'object' && r.permissions !== null) {
        Object.assign(permsMap, r.permissions)
      } else if (meta.permissions && Array.isArray(meta.permissions)) {
        const isAll = meta.permissions.includes('all') || meta.permissions.includes('*')
        if (isAll) {
          permsMap['all'] = true
          for (const k of ALL_PERMISSION_KEYS) {
            permsMap[k] = true
          }
        }
        for (const p of meta.permissions) {
          permsMap[p] = true
        }
      }

      return {
        uid,
        email: r.email || '',
        role: role as any,
        displayName: meta.displayName || meta.display_name || r.display_name || (r.email ? r.email.split('@')[0] : 'Admin'),
        permissions: permsMap,
        photoUrl: meta.photoUrl || meta.photo_url || r.photo_url || '',
        isActive: meta.isActive !== false && r.is_active !== false,
        createdBy: meta.createdBy || r.created_by || '',
        appId: meta.appId || meta.customId || '',
        createdAt: r.created_at || new Date().toISOString(),
        updatedAt: r.updated_at || new Date().toISOString(),
      }
    })
  } catch (err) {
    console.warn('getAdminUsers error:', err)
    return []
  }
}

export async function getAdminUser(uid: string): Promise<AdminUser | null> {
  try {
    const users = await getAdminUsers()
    return users.find(u => u.uid === uid) || null
  } catch { return null }
}

export async function createAdminUser(
  uid: string,
  data: Partial<AdminUser> & { appId?: string; customId?: string },
  password: string
) {
  const client = getAdminSupabase() || supabase
  const cleanEmail = (data.email || '').trim().toLowerCase()
  const role = data.role === 'superadmin' ? 'super_admin' : (data.role || 'moderator')
  const appId = (data.appId || data.customId || '').trim()

  // 1. Prepare permissions array
  let permsArray: string[] = []
  if (data.permissions) {
    if (data.permissions['all']) {
      permsArray = ['all', ...ALL_PERMISSION_KEYS]
    } else {
      permsArray = Object.keys(data.permissions).filter(k => data.permissions![k])
    }
  } else if (role === 'super_admin') {
    permsArray = ['all', ...ALL_PERMISSION_KEYS]
  }

  // 2. Try Supabase Auth signUp safely (ignore rate-limit / 429)
  try {
    const { error: signUpError } = await client.auth.signUp({
      email: cleanEmail,
      password,
    })
    if (signUpError) {
      console.warn('Supabase auth signUp warning (ignoring 429/rate-limit):', signUpError.message)
    }
  } catch (authErr: any) {
    console.warn('Supabase auth signUp caught error:', authErr?.message)
  }

  const authPayload = {
    uid,
    email: cleanEmail,
    appId: appId || undefined,
    password,
    displayName: data.displayName || cleanEmail.split('@')[0],
    role,
    permissions: permsArray,
    updatedAt: new Date().toISOString(),
  }

  // 3. Save credentials in app_config so admin can log in with Email
  try {
    await client.from('app_config').upsert({
      key: 'admin_auth_' + cleanEmail,
      value: authPayload,
    })
  } catch (e) {
    console.warn('Saving admin_auth error:', e)
  }

  // 4. If appId provided, save credentials under appId so admin can log in with App ID
  if (appId) {
    try {
      await client.from('app_config').upsert({
        key: 'admin_auth_' + appId.toLowerCase(),
        value: authPayload,
      })
      await client.from('app_config').upsert({
        key: 'admin_appid_' + appId.toLowerCase(),
        value: { uid, email: cleanEmail, appId },
      })
    } catch (e) {
      console.warn('Saving admin_auth for appId error:', e)
    }
  }

  // 5. Save metadata in app_config
  try {
    await client.from('app_config').upsert({
      key: 'admin_meta_' + uid,
      value: {
        uid,
        email: cleanEmail,
        appId: appId || undefined,
        displayName: data.displayName || '',
        photoUrl: data.photoUrl || '',
        role,
        isActive: data.isActive !== false,
        createdBy: data.createdBy || '',
        updatedAt: new Date().toISOString(),
      },
    })
  } catch (e) {
    console.warn('Saving admin_meta error:', e)
  }

  // 6. Insert/upsert into admin_users table with ONLY the actual DB columns
  const payload = {
    id: uid,
    uid,
    email: cleanEmail,
    role,
    permissions: permsArray,
    updated_at: new Date().toISOString(),
  }
  const { error } = await client.from('admin_users').upsert(payload)
  if (error) {
    console.error('Error inserting admin_users:', error)
    throw error
  }

  // 7. If this admin is an app user in the users table, update their role in the app as well
  try {
    const userRole = role === 'super_admin' ? 'admin' : role
    await client.from('users').update({ role: userRole }).eq('uid', uid)
  } catch (_) {}

  // 8. If giftNecklaceId or giftBadgeId provided, gift them directly into app account
  const giftNecklace = (data as any).giftNecklaceId;
  const giftBadge = (data as any).giftBadgeId;
  if (giftNecklace || giftBadge) {
    await giftUserItems(uid, {
      necklaceId: giftNecklace,
      badgeId: giftBadge,
    });
  }
}

export async function updateAdminUser(
  uid: string,
  data: Partial<AdminUser> & { appId?: string; customId?: string; password?: string }
) {
  const client = getAdminSupabase() || supabase
  const role = data.role ? (data.role === 'superadmin' ? 'super_admin' : data.role) : undefined
  const appId = (data.appId || data.customId || '').trim()

  // 1. Fetch existing admin record to know current email / appId / password
  let existingEmail = (data.email || '').trim().toLowerCase()
  let existingAppId = appId
  let existingPassword = data.password || ''

  try {
    const { data: currentAdmin } = await client.from('admin_users').select('*').eq('uid', uid).maybeSingle()
    if (currentAdmin && currentAdmin.email) {
      if (!existingEmail) existingEmail = currentAdmin.email.toLowerCase()
    }
  } catch (_) {}

  try {
    const { data: existingMeta } = await client.from('app_config').select('value').eq('key', 'admin_meta_' + uid).maybeSingle()
    const metaVal = (existingMeta?.value as any) || {}
    if (!existingAppId && metaVal.appId) existingAppId = metaVal.appId
    if (!existingEmail && metaVal.email) existingEmail = metaVal.email
  } catch (_) {}

  // 2. Prepare permissions array
  let permsArray: string[] | undefined = undefined
  if (data.permissions) {
    if (data.permissions['all']) {
      permsArray = ['all', ...ALL_PERMISSION_KEYS]
    } else {
      permsArray = Object.keys(data.permissions).filter(k => data.permissions![k])
    }
  }

  // 3. Update metadata in app_config
  try {
    const { data: existingMeta } = await client.from('app_config').select('value').eq('key', 'admin_meta_' + uid).maybeSingle()
    const metaVal = (existingMeta?.value as any) || {}
    if (data.displayName !== undefined) metaVal.displayName = data.displayName
    if (data.photoUrl !== undefined) metaVal.photoUrl = data.photoUrl
    if (data.isActive !== undefined) metaVal.isActive = data.isActive
    if (role !== undefined) metaVal.role = role
    if (existingAppId) metaVal.appId = existingAppId
    if (existingEmail) metaVal.email = existingEmail
    if (permsArray !== undefined) metaVal.permissions = permsArray
    metaVal.updatedAt = new Date().toISOString()
    await client.from('app_config').upsert({
      key: 'admin_meta_' + uid,
      value: metaVal,
    })
  } catch (e) {
    console.warn('Updating admin_meta error:', e)
  }

  // 4. Update credentials in app_config under admin_auth_*
  const keysToCheck = [
    existingEmail ? 'admin_auth_' + existingEmail : '',
    existingAppId ? 'admin_auth_' + existingAppId.toLowerCase() : '',
    'admin_auth_' + uid.toLowerCase(),
  ].filter(Boolean)

  let currentStoredAuth: any = null
  for (const k of keysToCheck) {
    try {
      const { data: row } = await client.from('app_config').select('value').eq('key', k).maybeSingle()
      if (row?.value) {
        currentStoredAuth = row.value
        if (!existingPassword && currentStoredAuth.password) {
          existingPassword = currentStoredAuth.password
        }
        break
      }
    } catch (_) {}
  }

  const authPayload = {
    uid,
    email: existingEmail,
    appId: existingAppId || undefined,
    password: existingPassword || data.password || 'admin123',
    displayName: data.displayName || currentStoredAuth?.displayName || existingEmail.split('@')[0],
    role: role || currentStoredAuth?.role || 'moderator',
    permissions: permsArray !== undefined ? permsArray : (currentStoredAuth?.permissions || []),
    updatedAt: new Date().toISOString(),
  }

  if (existingEmail) {
    try {
      await client.from('app_config').upsert({
        key: 'admin_auth_' + existingEmail,
        value: authPayload,
      })
    } catch (_) {}
  }
  if (existingAppId) {
    try {
      await client.from('app_config').upsert({
        key: 'admin_auth_' + existingAppId.toLowerCase(),
        value: authPayload,
      })
      await client.from('app_config').upsert({
        key: 'admin_appid_' + existingAppId.toLowerCase(),
        value: { uid, email: existingEmail, appId: existingAppId },
      })
    } catch (_) {}
  }

  // 5. Update admin_users table
  const payload: Record<string, any> = {
    updated_at: new Date().toISOString(),
  }
  if (role) payload.role = role
  if (existingEmail) payload.email = existingEmail
  if (permsArray !== undefined) payload.permissions = permsArray
  if (data.displayName) payload.display_name = data.displayName
  if (data.isActive !== undefined) payload.is_active = data.isActive

  const { error } = await client.from('admin_users').update(payload).eq('uid', uid)
  if (error) {
    console.error('Error updating admin_users:', error)
    throw error
  }

  // 6. If user exists in users table, sync role
  try {
    const userRole = role === 'super_admin' ? 'admin' : (role || 'moderator')
    await client.from('users').update({ role: userRole }).eq('uid', uid)
  } catch (_) {}

  // 7. Gift necklace or badge if specified
  const giftNecklace = (data as any).giftNecklaceId
  const giftBadge = (data as any).giftBadgeId
  if (giftNecklace || giftBadge) {
    await giftUserItems(uid, {
      necklaceId: giftNecklace,
      badgeId: giftBadge,
    })
  }
}

export async function deleteAdminUser(uid: string) {
  const client = getAdminSupabase() || supabase
  await client.from('admin_users').delete().eq('uid', uid)
  try { await client.from('app_config').delete().eq('key', 'admin_meta_' + uid) } catch {}
}

export async function logAdminAction(
  adminUid: string,
  adminName: string,
  action: string,
  targetType: string,
  targetId: string,
  details: Record<string, unknown> = {}
) {
  try {
    const client = getAdminSupabase() || supabase
    await client.from('admin_action_logs').insert({
      admin_uid: adminUid,
      admin_name: adminName,
      action,
      target_type: targetType,
      target_id: targetId,
      details,
    })
  } catch (e) { console.warn('logAdminAction failed:', e) }
}

export async function getAdminActionLogs(limit = 200): Promise<AdminActionLog[]> {
  try {
    const client = getAdminSupabase() || supabase
    const { data } = await client.from('admin_action_logs').select('*').order('created_at', { ascending: false }).limit(limit)
    return mapList<AdminActionLog>(data ?? [])
  } catch { return [] }
}

export async function clearActionLogs(adminUid?: string) {
  try {
    const client = getAdminSupabase() || supabase
    let query = client.from('admin_action_logs').delete()
    if (adminUid) query = query.eq('admin_uid', adminUid)
    await query
  } catch (e) { console.warn('clearActionLogs failed:', e) }
}

export async function getDashboardBans(): Promise<DashboardBan[]> {
  try {
    const client = getAdminSupabase() || supabase
    const { data } = await client.from('dashboard_bans').select('*').order('banned_at', { ascending: false })
    return mapList<DashboardBan>(data ?? [])
  } catch { return [] }
}

export async function banFromDashboard(uid: string, email: string, reason: string, bannedBy: string) {
  const client = getAdminSupabase() || supabase
  // First flag the `users` doc (what the Flutter splash screen reads) — this
  // is the actual enforcement point. Sync the record afterwards.
  await updateUser(uid, { banned: true, banReason: reason })
  try {
    const { error } = await client.from('dashboard_bans').upsert({ uid, email, reason, banned_by: bannedBy })
    if (error) console.warn('dashboard_bans record failed:', error)
  } catch (e) {
    console.warn('dashboard_bans record failed:', e)
  }
}

export async function unbanFromDashboard(uid: string) {
  const client = getAdminSupabase() || supabase
  await updateUser(uid, { banned: false, banReason: '' })
  try {
    await client.from('dashboard_bans').delete().eq('uid', uid)
  } catch (e) {
    console.warn('dashboard_bans delete failed:', e)
  }
}

export async function isBannedFromDashboard(uid: string): Promise<boolean> {
  try {
    const client = getAdminSupabase() || supabase
    const { data } = await client.from('dashboard_bans').select('uid').eq('uid', uid).maybeSingle()
    return !!data
  } catch { return false }
}

// ---- App Assets (unified catalog) ----

export async function getAppAssets(options?: {
  type?: string;
  category?: string;
  isActive?: boolean;
  search?: string;
  limit?: number;
  offset?: number;
}): Promise<{ data: AppAssetRecord[]; total: number }> {
  try {
    let query = supabase.from('app_assets').select('*', { count: 'exact' });

    if (options?.type) query = query.eq('type', options.type);
    if (options?.search) {
      query = query.ilike('key', `%${options.search}%`);
    }

    query = query.order('key', { ascending: true });

    if (options?.limit) query = query.range(options.offset || 0, (options.offset || 0) + options.limit - 1);

    const { data, count, error } = await query;
    if (error) throw error;
    const list: AppAssetRecord[] = (data ?? []).map((row: any) => ({
      id: row.key,
      key: row.key,
      name: row.name || row.key,
      type: row.type || 'image',
      category: row.category || '',
      subcategory: row.subcategory || '',
      localPath: row.local_path || '',
      remoteUrl: row.remote_url || row.url || '',
      defaultValue: '',
      mimeType: row.mime_type || '',
      fileSize: row.file_size || 0,
      width: row.width || null,
      height: row.height || null,
      sortOrder: row.sort_order || 0,
      isActive: row.is_active !== false,
      createdAt: row.updated_at || new Date().toISOString(),
      updatedAt: row.updated_at || new Date().toISOString(),
    }));
    if (list.length > 0) {
      return { data: list, total: count ?? list.length };
    }
  } catch (e) {
    console.warn('getAppAssets supabase error, trying firestore fallback:', e);
  }

  return { data: [], total: 0 };
}

export async function getAppAssetByKey(key: string): Promise<AppAssetRecord | null> {
  try {
    const { data } = await supabase.from('app_assets').select('*').eq('key', key).maybeSingle();
    if (data) {
      return {
        id: data.key,
        key: data.key,
        name: data.name || data.key,
        type: data.type || 'image',
        category: data.category || '',
        subcategory: data.subcategory || '',
        localPath: data.local_path || '',
        remoteUrl: data.remote_url || data.url || '',
        defaultValue: '',
        mimeType: data.mime_type || '',
        fileSize: data.file_size || 0,
        width: data.width || null,
        height: data.height || null,
        sortOrder: data.sort_order || 0,
        isActive: data.is_active !== false,
        createdAt: data.updated_at || new Date().toISOString(),
        updatedAt: data.updated_at || new Date().toISOString(),
      };
    }
  } catch {}
  return null;
}

function getAppAssetsClient() {
  return getAdminSupabase() || supabase;
}

export async function updateAppAsset(idOrKey: string, data: Partial<AppAssetRecord>) {
  const assetUrl = data.remoteUrl || (data as any).url;

  // 2. Write to Supabase
  try {
    const client = getAppAssetsClient();
    const payload: Record<string, any> = {
      updated_at: new Date().toISOString(),
    };
    if (assetUrl !== undefined) {
      payload.url = assetUrl;
      payload.remote_url = assetUrl;
    }
    if (data.type !== undefined) payload.type = data.type;
    if (data.name !== undefined) payload.name = data.name;
    if (data.category !== undefined) payload.category = data.category;
    if (data.isActive !== undefined) payload.is_active = data.isActive;
    await client.from('app_assets').update(payload).eq('key', idOrKey);
  } catch (e) {
    console.warn('updateAppAsset Supabase failed:', e);
  }
}

export async function upsertAppAsset(data: AppAssetRecord) {
  const assetUrl = data.remoteUrl || (data as any).url || '';
  const assetType = data.type || 'image';

  // 2. Write to Supabase
  try {
    const client = getAppAssetsClient();
    const payload = {
      key: data.key,
      name: data.name || data.key,
      url: assetUrl,
      remote_url: assetUrl,
      type: assetType,
      category: data.category || 'other',
      subcategory: data.subcategory || '',
      is_active: data.isActive !== false,
      updated_at: new Date().toISOString(),
    };
    await client.from('app_assets').upsert(payload, { onConflict: 'key' });
  } catch (e) {
    console.warn('Supabase app_assets upsert warning:', e);
  }
}

export async function deleteAppAsset(idOrKey: string) {

  try {
    const client = getAppAssetsClient();
    await client.from('app_assets').delete().eq('key', idOrKey);
  } catch (e) {
    console.warn('deleteAppAsset failed:', e);
  }
}

export async function getAppAssetCategories(): Promise<string[]> {
  try {
    const { data } = await supabase.from('app_assets').select('category').not('category', 'is', null);
    if (!data) return [];
    const cats = new Set<string>(data.map((r: any) => r.category as string).filter(Boolean));
    return Array.from(cats).sort();
  } catch {
    return [];
  }
}

export async function getAppAssetTypes(): Promise<string[]> {
  try {
    const { data } = await supabase.from('app_assets').select('type').not('type', 'is', null);
    if (!data) return [];
    const types = new Set<string>(data.map((r: any) => r.type as string).filter(Boolean));
    return Array.from(types).sort();
  } catch {
    return [];
  }
}

// Migrate existing assetsOverrides from app_config to app_assets.remote_url
export async function migrateAssetOverridesFromConfig(config: Record<string, any>) {
  try {
    const overrides = config.assetsOverrides as Record<string, string> | undefined;
    if (!overrides) return;

    for (const [key, remoteUrl] of Object.entries(overrides)) {
      if (!remoteUrl) continue;
      const existing = await getAppAssetByKey(key);
      if (existing) {
        await updateAppAsset(existing.id, { remoteUrl } as Partial<AppAssetRecord>);
      }
    }
  } catch (e) {
    console.warn('migrateAssetOverridesFromConfig failed:', e);
  }
}

// ---- Gift Categories ----

export async function getGiftCategories(): Promise<import('../types').GiftCategory[]> {
  const catMap = new Map<string, import('../types').GiftCategory>();
  try {
    const { data } = await supabase.from('gift_categories').select('*').order('sort_order');
    if (data) {
      mapList<import('../types').GiftCategory>(data).forEach(c => {
        if (c.id) catMap.set(c.id, c);
      });
    }
  } catch {}
  
  return Array.from(catMap.values()).sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0));
}

export async function addGiftCategory(id: string, data: import('../types').GiftCategory) {
  
  try {
    await supabase.from('gift_categories').upsert({ id, ...toSnakeCase(data as unknown as Record<string, unknown>) });
  } catch (e) {
    console.warn('addGiftCategory failed:', e);
  }
}

export async function updateGiftCategory(id: string, data: Partial<import('../types').GiftCategory>) {
  
  try {
    await supabase.from('gift_categories').update(toSnakeCase(data as Record<string, unknown>)).eq('id', id);
  } catch (e) {
    console.warn('updateGiftCategory failed:', e);
  }
}

export async function deleteGiftCategory(id: string) {
  
  try {
    await supabase.from('gift_categories').delete().eq('id', id);
  } catch (e) {
    console.warn('deleteGiftCategory failed:', e);
  }
}

// ---- Gift Banner Configs ----

export async function getGiftBannerConfigs(): Promise<import('../types').GiftBannerConfig[]> {
  try {
    const { data } = await supabase.from('gift_banner_configs').select('*').order('threshold_coins')
    return mapList<import('../types').GiftBannerConfig>(data ?? [])
  } catch { return [] }
}

export async function addGiftBannerConfig(id: string, data: import('../types').GiftBannerConfig) {
  try {
    await supabase.from('gift_banner_configs').upsert({ id, ...toSnakeCase(data as unknown as Record<string, unknown>) })
  } catch (e) {
    console.warn('addGiftBannerConfig failed:', e)
  }
}

export async function updateGiftBannerConfig(id: string, data: Partial<import('../types').GiftBannerConfig>) {
  try {
    await supabase.from('gift_banner_configs').update(toSnakeCase(data as Record<string, unknown>)).eq('id', id)
  } catch (e) {
    console.warn('updateGiftBannerConfig failed:', e)
  }
}

export async function deleteGiftBannerConfig(id: string) {
  try {
    await supabase.from('gift_banner_configs').delete().eq('id', id)
  } catch (e) {
    console.warn('deleteGiftBannerConfig failed:', e)
  }
}

// ---- CP Features ----

export async function getCpGifts(): Promise<CpGiftModel[]> {
  try {
    const { data, error } = await supabase.from('cp_gifts').select('*').order('sort_order')
    if (!error && data && data.length > 0) {
      return mapList<CpGiftModel>(data)
    }
  } catch {}
  try {
    // Select all gifts and filter in-memory to prevent PostgREST 400 error on non-existent column
    const { data, error } = await supabase.from('gifts').select('*')
    if (!error && data && data.length > 0) {
      const filtered = data.filter((g: any) =>
        g.is_cp_gift === true ||
        g.isCpGift === true ||
        g.category === 'cp' ||
        g.category_id === 'cp' ||
        g.categoryId === 'cp'
      );
      if (filtered.length > 0) {
        return mapList<CpGiftModel>(filtered);
      }
    }
  } catch {}
  
  return [];
}

export async function addCpGift(id: string, data: CpGiftModel) {
  try {
    await supabase.from('cp_gifts').upsert({ id, ...toSnakeCase(data as unknown as Record<string, unknown>) })
  } catch {
    try {
      const basePayload: Record<string, unknown> = {
        id,
        name: data.name,
        value: data.value,
        icon_asset: data.iconAsset,
        animation_asset: data.animationAsset,
      };
      await supabase.from('gifts').upsert(basePayload);
    } catch (e) {
      console.warn('addCpGift failed:', e);
    }
  }
}

export async function updateCpGift(id: string, data: Partial<CpGiftModel>) {
  try {
    await supabase.from('cp_gifts').update(toSnakeCase(data as Record<string, unknown>)).eq('id', id);
  } catch {
    try {
      const basePayload: Record<string, unknown> = {};
      if (data.name !== undefined) basePayload.name = data.name;
      if (data.value !== undefined) basePayload.value = data.value;
      if (data.iconAsset !== undefined) basePayload.icon_asset = data.iconAsset;
      if (data.animationAsset !== undefined) basePayload.animation_asset = data.animationAsset;
      await supabase.from('gifts').update(basePayload).eq('id', id);
    } catch (e) {
      console.warn('updateCpGift failed:', e);
    }
  }
}

export async function deleteCpGift(id: string) {
  try { await supabase.from('cp_gifts').delete().eq('id', id) } catch {}
  try { await supabase.from('gifts').delete().eq('id', id) } catch {}
}

export async function getCpCars(): Promise<CpCarModel[]> {
  try {
    const { data, error } = await supabase.from('cp_cars').select('*').order('sort_order')
    if (!error && data && data.length > 0) {
      return mapList<CpCarModel>(data)
    }
  } catch {}
  try {
    const { data } = await supabase.from('store_items').select('*').eq('category', 'car')
    if (data && data.length > 0) {
      return mapList<CpCarModel>(data)
    }
  } catch {}
  return []
}

export async function addCpCar(id: string, data: CpCarModel) {
  try {
    await supabase.from('cp_cars').upsert({ id, ...toSnakeCase(data as unknown as Record<string, unknown>) })
  } catch {
    try {
      await supabase.from('store_items').upsert({
        id,
        ...toSnakeCase(data as unknown as Record<string, unknown>),
        category: 'car',
      })
    } catch (e) {
      console.warn('addCpCar failed:', e)
    }
  }
}

export async function updateCpCar(id: string, data: Partial<CpCarModel>) {
  try {
    await supabase.from('cp_cars').update(toSnakeCase(data as Record<string, unknown>)).eq('id', id)
  } catch {
    try {
      await supabase.from('store_items').update(toSnakeCase(data as Record<string, unknown>)).eq('id', id)
    } catch (e) {
      console.warn('updateCpCar failed:', e)
    }
  }
}

export async function deleteCpCar(id: string) {
  try { await supabase.from('cp_cars').delete().eq('id', id) } catch {}
  try { await supabase.from('store_items').delete().eq('id', id) } catch {}
}

export async function getCpSettings(): Promise<Record<string, string>> {
  try {
    const { data, error } = await supabase.from('cp_settings').select('key, value')
    if (!error && data && data.length > 0) {
      const map: Record<string, string> = {}
      for (const row of data) map[row.key] = row.value
      return map
    }
  } catch {}
  try {
    const { data } = await supabase.from('app_config').select('key, value').like('key', 'cp_%')
    const map: Record<string, string> = {}
    for (const row of data ?? []) map[row.key] = typeof row.value === 'string' ? row.value : JSON.stringify(row.value)
    return map
  } catch { return {} }
}

export async function updateCpSetting(key: string, value: string) {
  try {
    await supabase.from('cp_settings').upsert({ key, value, updated_at: new Date().toISOString() })
  } catch {
    try {
      await supabase.from('app_config').upsert({ key, value, updated_at: new Date().toISOString() })
    } catch (e) { console.warn('updateCpSetting failed:', e) }
  }
}

// ---- Weekly Sign-In Rewards (7-day daily login) ----

export async function getSigninRewards(): Promise<SigninRewardModel[]> {
  try {
    const { data, error } = await supabase.from('signin_rewards').select('*').order('day_number')
    if (!error && data && data.length > 0) {
      return mapList<SigninRewardModel>(data)
    }
  } catch {}
  try {
    const { data } = await supabase.from('app_config').select('value').eq('key', 'signin_rewards').maybeSingle()
    if (data && data.value && Array.isArray(data.value)) {
      return data.value as SigninRewardModel[]
    }
  } catch {}
  return []
}

export async function upsertSigninReward(id: string, data: Partial<SigninRewardModel>) {
  try {
    await supabase.from('signin_rewards').upsert({ id, ...toSnakeCase(data as unknown as Record<string, unknown>) })
  } catch {
    try {
      const current = await getSigninRewards()
      const idx = current.findIndex(x => x.id === id)
      if (idx >= 0) current[idx] = { ...current[idx], ...data }
      else current.push({ id, ...data } as SigninRewardModel)
      await supabase.from('app_config').upsert({ key: 'signin_rewards', value: current, updated_at: new Date().toISOString() })
    } catch (e) { console.warn('upsertSigninReward failed:', e) }
  }
}

export async function updateSigninReward(id: string, data: Partial<SigninRewardModel>) {
  try {
    await supabase.from('signin_rewards').update(toSnakeCase(data as Record<string, unknown>)).eq('id', id)
  } catch {
    try {
      const current = await getSigninRewards()
      const idx = current.findIndex(x => x.id === id)
      if (idx >= 0) {
        current[idx] = { ...current[idx], ...data }
        await supabase.from('app_config').upsert({ key: 'signin_rewards', value: current, updated_at: new Date().toISOString() })
      }
    } catch (e) { console.warn('updateSigninReward failed:', e) }
  }
}

export async function deleteSigninReward(id: string) {
  try { await supabase.from('signin_rewards').delete().eq('id', id) } catch {}
  try {
    const current = await getSigninRewards()
    const filtered = current.filter(x => x.id !== id)
    await supabase.from('app_config').upsert({ key: 'signin_rewards', value: filtered, updated_at: new Date().toISOString() })
  } catch {}
}

// ---- CP Rank Rewards (بمجموعة Firestore cp_rank_rewards مباشرة) ----
// FIX: التعديلات تذهب الآن وثيقة-بـ-وثيقة إلى مجموعة `cp_rank_rewards`
//      — نفس المجموعة التي يقرأ منها تطبيق Flutter — بدلاً من JSON blob
//      في cp_settings["cp_rank_rewards_data"] (كانت سبب عدم ظهور التعديلات).
const CP_RANK_REWARDS = 'cp_rank_rewards';

function _rewardDocId(id: unknown, data: Partial<CpRankRewardModel>): string {
  if (id != null && String(id).length > 0) return String(id);
  const p = data.period || 'weekly';
  const r = data.rank_position ?? 1;
  const s = data.slot_index ?? 0;
  return `${p}_rank${r}_slot${s}`;
}

function _normalizeRewardRow(d: any): CpRankRewardModel {
  return {
    id: d.id ?? d.docId ?? '',
    period: d.period ?? 'weekly',
    rank_position: Number(d.rank_position ?? 1),
    slot_index: Number(d.slot_index ?? 0),
    reward_type: d.reward_type ?? 'frame_svga',
    label_ar: d.label_ar ?? '',
    label_en: d.label_en ?? '',
    svga_url: d.svga_url ?? '',
    image_url: d.image_url ?? '',
    isActive: d.isActive !== false,
  } as CpRankRewardModel;
}

export async function getCpRankRewards(period?: string): Promise<CpRankRewardModel[]> {
  try {
    const { data } = await supabase.from(CP_RANK_REWARDS).select();
    let rows: CpRankRewardModel[] = (Array.isArray(data) ? data : []).map(_normalizeRewardRow);

    // Fallback قديم: لو المجموعة فارغة نقرأ الـ JSON blob القديم حتى لا يضيع التكوين.
    if (rows.length === 0) {
      const { data: legacy } = await supabase.from('cp_settings').select('value').eq('key', 'cp_rank_rewards_data').maybeSingle();
      if (legacy?.value) {
        const parsed = JSON.parse(legacy.value);
        if (Array.isArray(parsed)) rows = parsed.map(_normalizeRewardRow);
      }
    }

    const filtered = period ? rows.filter(r => r.period === period) : rows;
    return filtered.sort((a, b) => a.rank_position - b.rank_position || a.slot_index - b.slot_index);
  } catch (e) {
    console.warn('getCpRankRewards failed:', e);
    return [];
  }
}

export async function upsertCpRankReward(id: string | number | null, data: Partial<CpRankRewardModel>) {
  try {
    const docId = _rewardDocId(id, data);
    const values = {
      id: docId,
      period: data.period ?? 'weekly',
      rank_position: Number(data.rank_position ?? 1),
      slot_index: Number(data.slot_index ?? 0),
      reward_type: data.reward_type ?? 'frame_svga',
      label_ar: data.label_ar ?? '',
      label_en: data.label_en ?? '',
      svga_url: data.svga_url ?? '',
      image_url: data.image_url ?? '',
      isActive: data.isActive !== false,
      updated_at: new Date().toISOString(),
    };
    await supabase.from(CP_RANK_REWARDS).upsert(values, { onConflict: 'id' });
  } catch (e) { console.warn('upsertCpRankReward failed:', e); }
}

export async function deleteCpRankReward(id: string | number) {
  try {
    await supabase.from(CP_RANK_REWARDS).delete().eq('id', id);
  } catch (e) { console.warn('deleteCpRankReward failed:', e); }
}

// ─── CP Auto-Distribution Functions ───

interface ActiveRewardEntry {
  user_uid: string;
  couple_id: string;
  rank: number;
  period: string;
  period_start: string;
  period_end: string;
  rewards: {
    type: string;
    label_ar: string;
    label_en: string;
    svga_url: string;
    image_url: string;
    slot_index: number;
    expires_at: string;
  }[];
  awarded_at: string;
}

export async function getCpRewardConfig(): Promise<{
  period_type: string;
  custom_days: number;
  reward_duration_days: number;
  last_distribution: string;
  next_distribution: string;
  last_period_start: string;
}> {
  try {
    const { data } = await supabase.from('cp_settings').select('value').eq('key', 'cp_reward_period_config').maybeSingle();
    if (data?.value) return JSON.parse(data.value);
  } catch { /* */ }
  return { period_type: 'weekly', custom_days: 0, reward_duration_days: 7, last_distribution: '', next_distribution: '', last_period_start: '' };
}

export async function saveCpRewardConfig(cfg: any) {
  await supabase.from('cp_settings').upsert({ key: 'cp_reward_period_config', value: JSON.stringify(cfg), updated_at: new Date().toISOString() }, { onConflict: 'key' });
}

export async function getActiveRewards(): Promise<ActiveRewardEntry[]> {
  try {
    const { data } = await supabase.from('cp_settings').select('value').eq('key', 'cp_active_rewards').maybeSingle();
    if (data?.value) return JSON.parse(data.value);
  } catch { /* */ }
  return [];
}

export async function getDistributionHistory(): Promise<any[]> {
  try {
    const { data } = await supabase.from('cp_settings').select('value').eq('key', 'cp_distribution_history').maybeSingle();
    if (data?.value) return JSON.parse(data.value);
  } catch { /* */ }
  return [];
}

export async function distributeCpRewards(): Promise<{ success: boolean; message: string; details?: any }> {
  try {
    const { data: cfgData } = await supabase.from('cp_settings').select('value').eq('key', 'cp_reward_period_config').maybeSingle();
    const cfg = cfgData?.value ? JSON.parse(cfgData.value) : { period_type: 'weekly', custom_days: 0, reward_duration_days: 7, last_distribution: '', next_distribution: '', last_period_start: '' };

    // FIX: تُقرأ قوالب المكافآت من مجموعة cp_rank_rewards مباشرة (نفس مصدر تطبيق Flutter).
    const rankRewards: any[] = await getCpRankRewards();

    const periodKey = cfg.period_type === 'monthly' ? 'month_score' : 'week_score';
    const periodCol = cfg.period_type === 'monthly' ? 'month_score' : 'week_score';

    const { data: couples, error: couplesError } = await supabase
      .from('cp_couples')
      .select('id, user1_uid, user2_uid, week_score, month_score, total_score')
      .is('ended_at', null)
      .order(periodCol, { ascending: false })
      .limit(3);

    if (couplesError) return { success: false, message: couplesError.message };

    if (!couples || couples.length === 0) {
      const now = new Date().toISOString();
      cfg.last_distribution = now;
      cfg.last_period_start = now;
      cfg.next_distribution = calcNext(cfg);
      await saveCpRewardConfig(cfg);
      return { success: true, message: 'No couples to reward. Period advanced.' };
    }

    const { data: existingActive } = await supabase.from('cp_settings').select('value').eq('key', 'cp_active_rewards').maybeSingle();
    const activeRewards: ActiveRewardEntry[] = existingActive?.value ? JSON.parse(existingActive.value) : [];

    const now = new Date();
    const nowStr = now.toISOString();
    const expiresAt = new Date(now.getTime() + (cfg.reward_duration_days || 7) * 86400000).toISOString();
    const details: any[] = [];

    for (let rank = 1; rank <= Math.min(couples.length, 3); rank++) {
      const couple = couples[rank - 1];
      const slotRewards = rankRewards.filter((r: any) => r.rank_position === rank);

      const entries = slotRewards.map((sr: any) => ({
        type: sr.label_ar?.includes('إطار') || sr.label_ar?.includes('frame') || sr.label_ar?.includes('ايطار') ? 'frame'
          : sr.label_ar?.includes('وسام') || sr.label_ar?.includes('badge') ? 'badge'
          : sr.label_ar?.includes('قلادة') || sr.label_ar?.includes('necklace') ? 'necklace'
          : 'frame',
        label_ar: sr.label_ar || '',
        label_en: sr.label_en || '',
        svga_url: sr.svga_url || '',
        image_url: sr.image_url || '',
        slot_index: sr.slot_index || 0,
        expires_at: expiresAt,
      }));

      for (const uid of [couple.user1_uid, couple.user2_uid]) {
        activeRewards.push({
          user_uid: uid,
          couple_id: couple.id,
          rank,
          period: cfg.period_type || 'weekly',
          period_start: nowStr,
          period_end: expiresAt,
          rewards: entries,
          awarded_at: nowStr,
        });
        await _assignToUser(uid, entries);
      }

      details.push({
        rank,
        user1: couple.user1_uid,
        user2: couple.user2_uid,
        score: couple[periodCol] || 0,
        rewards: slotRewards.length,
      });
    }

    await supabase.from('cp_settings').upsert({ key: 'cp_active_rewards', value: JSON.stringify(activeRewards), updated_at: nowStr }, { onConflict: 'key' });

    await supabase.from('cp_couples').update({ [periodCol]: 0 }).is('ended_at', null);

    cfg.last_distribution = nowStr;
    cfg.last_period_start = nowStr;
    cfg.next_distribution = calcNext(cfg);
    await saveCpRewardConfig(cfg);

    const { data: histData } = await supabase.from('cp_settings').select('value').eq('key', 'cp_distribution_history').maybeSingle();
    const history = histData?.value ? JSON.parse(histData.value) : [];
    history.push({ timestamp: nowStr, details });
    if (history.length > 100) history.splice(0, history.length - 100);
    await supabase.from('cp_settings').upsert({ key: 'cp_distribution_history', value: JSON.stringify(history), updated_at: nowStr }, { onConflict: 'key' });

    return { success: true, message: `تم توزيع المكافآت على ${couples.length} زوج/أزواج`, details };
  } catch (err: any) {
    return { success: false, message: err.message };
  }
}

async function _assignToUser(userUid: string, rewards: ActiveRewardEntry['rewards']) {
  const { data: user } = await supabase.from('users').select('owned_level_frames, owned_level_badges, owned_level_necklaces').eq('uid', userUid).single();
  if (!user) return;

  let frames: any[] = user.owned_level_frames || [];
  let badges: any[] = user.owned_level_badges || [];
  let necklaces: any[] = user.owned_level_necklaces || [];
  let changed = false;

  for (const r of rewards) {
    const entry = { id: `cp_rank_${r.slot_index}_${Date.now()}`, name_ar: r.label_ar, name_en: r.label_en, svga_url: r.svga_url, image_url: r.image_url, source: 'cp_reward', expires_at: r.expires_at };
    if (r.type === 'frame') { frames.push({ ...entry, type: 'frame' }); changed = true; }
    else if (r.type === 'badge') { badges.push({ ...entry, type: 'badge' }); changed = true; }
    else if (r.type === 'necklace') { necklaces.push({ ...entry, type: 'necklace' }); changed = true; }
  }

  if (changed) {
    const updates: any = {};
    if (frames.length > 0) updates.owned_level_frames = frames;
    if (badges.length > 0) updates.owned_level_badges = badges;
    if (necklaces.length > 0) updates.owned_level_necklaces = necklaces;
    await supabase.from('users').update(updates).eq('uid', userUid);
  }

  // سجل منح المكافأة لكل مستخدم (مجموعة user_rewards): مصدر موحّد للوحة والتطبيق.
  try {
    for (const r of rewards) {
      await supabase.from('user_rewards').add({
        user_uid: userUid,
        reward_type: r.type,
        label_ar: r.label_ar,
        label_en: r.label_en,
        svga_url: r.svga_url,
        image_url: r.image_url,
        source: 'cp_rank_reward',
        expires_at: r.expires_at,
        created_at: new Date().toISOString(),
      });
    }
  } catch { /* ignore */ }
}

export async function expireCpRewards(): Promise<{ removed: number }> {
  try {
    const { data: activeData } = await supabase.from('cp_settings').select('value').eq('key', 'cp_active_rewards').maybeSingle();
    if (!activeData?.value) return { removed: 0 };

    const activeRewards: ActiveRewardEntry[] = JSON.parse(activeData.value);
    const now = new Date();
    const before = activeRewards.length;

    const expiredUids = new Set<string>();
    const valid = activeRewards.filter(ar => {
      if (new Date(ar.period_end) <= now) { expiredUids.add(ar.user_uid); return false; }
      return true;
    });

    await supabase.from('cp_settings').upsert({ key: 'cp_active_rewards', value: JSON.stringify(valid), updated_at: now.toISOString() }, { onConflict: 'key' });

    for (const uid of expiredUids) {
      const { data: user } = await supabase.from('users').select('owned_level_frames, owned_level_badges, owned_level_necklaces, active_frame').eq('uid', uid).single();
      if (!user) continue;
      const updates: any = {};
      for (const col of ['owned_level_frames', 'owned_level_badges', 'owned_level_necklaces'] as const) {
        const items: any[] = (user as any)[col] || [];
        const filtered = items.filter((i: any) => !i.expires_at || new Date(i.expires_at) > now);
        if (filtered.length !== items.length) updates[col] = filtered;
      }
      if (Object.keys(updates).length > 0) {
        if (user.active_frame && !(updates.owned_level_frames || user.owned_level_frames).some((f: any) => f.id === user.active_frame)) {
          updates.active_frame = null;
        }
        await supabase.from('users').update(updates).eq('uid', uid);
      }
    }

    return { removed: before - valid.length };
  } catch (e) {
    return { removed: 0 };
  }
}

function calcNext(cfg: any): string {
  const now = new Date();
  const next = new Date(now);
  switch (cfg.period_type) {
    case 'daily': next.setDate(next.getDate() + 1); next.setHours(0, 0, 0, 0); break;
    case 'weekly': next.setDate(next.getDate() + (7 - next.getDay())); next.setHours(0, 0, 0, 0); break;
    case 'monthly': next.setMonth(next.getMonth() + 1); next.setDate(1); next.setHours(0, 0, 0, 0); break;
    default: next.setDate(next.getDate() + (cfg.custom_days > 0 ? cfg.custom_days : 7)); next.setHours(0, 0, 0, 0); break;
  }
  return next.toISOString();
}

export { supabase };

// ============================================================
// In-app updates: published as app_config/app_update doc.
// The Flutter app reads this same document on startup.
// ============================================================
export interface AppUpdateConfig {
  latest_version: string
  build_number: number
  apk_url: string
  notes_ar: string
  notes_en: string
  force_update: boolean
  published_at?: string
}

export async function getAppUpdate(): Promise<AppUpdateConfig | null> {
  try {
    const { data } = await supabase.from('app_config').select('*').eq('key', 'app_update').maybeSingle()
    if (!data) return null
    return data as unknown as AppUpdateConfig
  } catch {
    return null
  }
}

export async function publishAppUpdate(cfg: Omit<AppUpdateConfig, 'published_at'>): Promise<string | null> {
  try {
    await supabase.from('app_config').upsert({ key: 'app_update', ...cfg, published_at: new Date().toISOString() })
    return null
  } catch (e) {
    return e instanceof Error ? e.message : String(e)
  }
}

export async function unpublishAppUpdate(): Promise<string | null> {
  try {
    await supabase.from('app_config').delete().eq('key', 'app_update')
    return null
  } catch (e) {
    return e instanceof Error ? e.message : String(e)
  }
}

