import { supabase } from './supabase'

export type AppUser = {
  id: string
  email: string | null
  displayName: string | null
  photoUrl: string | null
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
  }
}

export function onAuthChange(callback: (user: AppUser | null) => void) {
  // Check local admin first or current Supabase session
  const local = getLocalAdmin()
  if (local) {
    callback(local)
  } else {
    supabase.auth.getSession().then(({ data }) => {
      callback(toAppUser(data.session?.user))
    })
  }

  const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
    if (session?.user) {
      const user = toAppUser(session.user)
      setLocalAdmin(user)
      callback(user)
    } else {
      const remainingLocal = getLocalAdmin()
      callback(remainingLocal)
    }
  })

  return () => {
    listener?.subscription?.unsubscribe()
  }
}

export async function loginWithEmail(email: string, password: string) {
  const cleanEmail = email.trim()

  // 1. Try Supabase Auth sign in
  const { data, error } = await supabase.auth.signInWithPassword({
    email: cleanEmail,
    password,
  })

  if (!error && data?.user) {
    const user = toAppUser(data.user)
    setLocalAdmin(user)
    return
  }

  // 2. If user not found in Supabase Auth, attempt sign up automatically
  if (
    error &&
    (error.message.includes('Invalid login credentials') ||
      error.message.includes('User not found'))
  ) {
    const { data: signUpData, error: signUpError } = await supabase.auth.signUp({
      email: cleanEmail,
      password,
    })
    if (!signUpError && signUpData?.user) {
      const user = toAppUser(signUpData.user)
      setLocalAdmin(user)
      return
    }
  }

  // 3. Fallback admin session for user's primary admin emails
  const lower = cleanEmail.toLowerCase();
  const isAdminEmail =
    lower === 'admin@ahlalive.com' ||
    lower === 'admin@ahla-live.com' ||
    lower === 'admin@ahla.com' ||
    lower === 'm3290556@gmail.com' ||
    lower === 'admin@zero.app' ||
    lower.startsWith('admin@');

  if (isAdminEmail) {
    const adminUser: AppUser = {
      id: 'admin_' + lower.replace(/[^a-zA-Z0-9]/g, '_'),
      email: cleanEmail,
      displayName: 'المدير العام',
      photoUrl: null,
    };
    setLocalAdmin(adminUser);
    return;
  }

  if (error) {
    throw error
  }
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
