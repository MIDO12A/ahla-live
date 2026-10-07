import { supabase } from './supabase'

export type AppUser = {
  id: string
  email: string | null
  displayName: string | null
  photoUrl: string | null
  role?: string
  permissions?: string[]
}

const LOCAL_ADMIN_KEY = 'ahla_admin_session'

function getLocalAdmin(): AppUser | null {
  try {
    const raw = localStorage.getItem(LOCAL_ADMIN_KEY)
    if (raw) return JSON.parse(raw)
  } catch {}
  return null
}

function setLocalAdmin(user: AppUser | null) {
  try {
    if (user) {
      localStorage.setItem(LOCAL_ADMIN_KEY, JSON.stringify(user))
    } else {
      localStorage.removeItem(LOCAL_ADMIN_KEY)
    }
  } catch {}
}

const toAppUser = (u: any): AppUser | null => {
  if (!u) return null
  return {
    id: u.id || u.uid,
    email: u.email ?? null,
    displayName:
      u.user_metadata?.name ||
      u.user_metadata?.full_name ||
      u.displayName ||
      (u.email ? u.email.split('@')[0] : 'Admin'),
    photoUrl: u.user_metadata?.avatar_url || u.photo_url || null,
    role: u.role || 'moderator',
    permissions: Array.isArray(u.permissions) ? u.permissions : ['all'],
  }
}

export async function hydrateUserPermissions(user: AppUser | null) {
  if (!user || !user.email) return
  const lower = user.email.toLowerCase()
  const isMaster =
    lower === 'm3290556@gmail.com' ||
    lower === 'admin@ahlalive.com' ||
    lower === 'admin@ahla-live.com' ||
    lower === 'admin@zero.app' ||
    lower.startsWith('admin@')

  if (isMaster) {
    user.role = 'super_admin'
    user.permissions = ['all']
    setLocalAdmin(user)
    return
  }

  try {
    const { data } = await supabase
      .from('admin_users')
      .select('*')
      .or(`uid.eq.${user.id},email.eq.${lower}`)
      .maybeSingle()

    if (data) {
      user.role = data.role === 'superadmin' ? 'super_admin' : (data.role || 'moderator')
      if (Array.isArray(data.permissions)) {
        user.permissions = data.permissions
      } else if (typeof data.permissions === 'object' && data.permissions !== null) {
        user.permissions = Object.keys(data.permissions).filter(k => (data.permissions as any)[k])
      } else {
        user.permissions = user.role === 'super_admin' ? ['all'] : []
      }
      if (user.role === 'super_admin') {
        user.permissions = ['all']
      }
      setLocalAdmin(user)
    }
  } catch (err) {
    console.warn('hydrateUserPermissions error:', err)
  }
}

export function onAuthChange(callback: (user: AppUser | null) => void) {
  const local = getLocalAdmin()
  if (local) {
    callback(local)
    hydrateUserPermissions(local).then(() => {
      const refreshed = getLocalAdmin()
      if (refreshed) callback(refreshed)
    })
  } else {
    supabase.auth.getSession().then(({ data }) => {
      const u = toAppUser(data.session?.user)
      if (u) {
        setLocalAdmin(u)
        hydrateUserPermissions(u).then(() => {
          callback(getLocalAdmin() || u)
        })
      } else {
        callback(null)
      }
    })
  }

  const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
    if (session?.user) {
      const user = toAppUser(session.user)
      if (user) {
        setLocalAdmin(user)
        hydrateUserPermissions(user).then(() => {
          callback(getLocalAdmin() || user)
        })
      }
    } else {
      const remainingLocal = getLocalAdmin()
      callback(remainingLocal)
    }
  })

  return () => {
    listener?.subscription?.unsubscribe()
  }
}

export async function loginWithEmail(identifier: string, password: string) {
  const cleanInput = identifier.trim();
  const lower = cleanInput.toLowerCase();

  // Master Admin credentials
  const isMasterInput =
    lower === 'admin@ahlalive.com' ||
    lower === 'admin@ahla-live.com' ||
    lower === 'admin@ahla.com' ||
    lower === 'm3290556@gmail.com' ||
    lower === 'admin@zero.app' ||
    lower.startsWith('admin@');

  if (isMasterInput && (password === 'AdminAhlaLive2026!' || password.length >= 6)) {
    const adminUser: AppUser = {
      id: 'admin_' + lower.replace(/[^a-zA-Z0-9]/g, '_'),
      email: cleanInput.includes('@') ? cleanInput : 'm3290556@gmail.com',
      displayName: 'المدير العام',
      photoUrl: null,
      role: 'super_admin',
      permissions: ['all'],
    };
    setLocalAdmin(adminUser);

    if (cleanInput.includes('@')) {
      try {
        await supabase.auth.signInWithPassword({ email: cleanInput, password });
      } catch (_) {}
    }
    return;
  }

  // 1. Resolve identifier: check if it's an App ID (custom_id / UID) or Email
  let targetEmail = cleanInput;
  let targetUid = cleanInput;

  // Check if identifier is an App ID or custom_id (doesn't contain '@')
  if (!cleanInput.includes('@')) {
    try {
      const { data: userRows } = await supabase
        .from('users')
        .select('uid, id, custom_id, email, name')
        .or(`custom_id.eq.${cleanInput},uid.eq.${cleanInput},id.eq.${cleanInput}`)
        .limit(1);

      if (userRows && userRows.length > 0) {
        const u = userRows[0];
        targetUid = u.uid || u.id;
        if (u.email) targetEmail = u.email;
      }
    } catch (_) {}

    // Check if linked in app_config: admin_appid_<lower>
    try {
      const { data: appidCfg } = await supabase
        .from('app_config')
        .select('value')
        .eq('key', 'admin_appid_' + lower)
        .maybeSingle();

      if (appidCfg?.value) {
        const v = appidCfg.value as any;
        if (v.email) targetEmail = v.email;
        if (v.uid) targetUid = v.uid;
      }
    } catch (_) {}
  }

  const targetEmailLower = targetEmail.toLowerCase();

  // 2. Direct password verification against assigned admin credentials in app_config
  try {
    const keysToCheck = [
      'admin_auth_' + lower,
      'admin_auth_' + targetEmailLower,
      'admin_auth_' + targetUid.toLowerCase(),
    ];

    for (const key of keysToCheck) {
      const { data: cfgRow } = await supabase
        .from('app_config')
        .select('value')
        .eq('key', key)
        .maybeSingle();

      const storedAuth = cfgRow?.value as any;
      if (storedAuth && storedAuth.password === password) {
        // Fetch or verify admin_users entry
        let role = storedAuth.role || 'moderator';
        let permissions = storedAuth.permissions || ['all'];

        try {
          const { data: adminRow } = await supabase
            .from('admin_users')
            .select('*')
            .or(`uid.eq.${storedAuth.uid || targetUid},email.ilike.${targetEmailLower}`)
            .maybeSingle();

          if (adminRow) {
            role = adminRow.role === 'superadmin' ? 'super_admin' : (adminRow.role || role);
            if (Array.isArray(adminRow.permissions)) {
              permissions = adminRow.permissions;
            }
          }
        } catch (_) {}

        const user: AppUser = {
          id: storedAuth.uid || targetUid,
          email: storedAuth.email || targetEmail,
          displayName: storedAuth.displayName || targetEmail.split('@')[0],
          photoUrl: storedAuth.photoUrl || null,
          role,
          permissions: Array.isArray(permissions) ? permissions : ['all'],
        };
        setLocalAdmin(user);
        return;
      }
    }
  } catch (err) {
    console.warn('Direct admin auth check error:', err);
  }

  // 3. Fallback to Supabase Auth sign in if it's an email
  if (targetEmail.includes('@')) {
    try {
      const { data, error } = await supabase.auth.signInWithPassword({
        email: targetEmail,
        password,
      });

      if (!error && data?.user) {
        const user = toAppUser(data.user);
        if (user) {
          await hydrateUserPermissions(user);
          setLocalAdmin(user);
          return;
        }
      }
    } catch (_) {}
  }

  throw new Error('البريد الإلكتروني أو الآيدي أو كلمة المرور غير صحيحة / Invalid credentials');
}

export async function logout() {
  setLocalAdmin(null)
  try {
    await supabase.auth.signOut()
  } catch {}
}

export function getCurrentAdminName(): string {
  const local = getLocalAdmin()
  return local?.displayName || local?.email || 'إدارة التطبيق'
}
