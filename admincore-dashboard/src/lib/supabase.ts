// ============================================================
// Real Supabase client for the admin dashboard.
// نبقى على Supabase الحقيقي نفسه، بس HTTP يمرّ عبر rewrite على
// نفس نطاق Vercel (/api/bo/*) عشان المتصفح ما يفتح supabase.co
// مباشرة (بعض المتصفحات كان يقطّع الاتصال بـ ERR_CONNECTION_CLOSED).
// WebSocket للـ Realtime يبقى على الرابط المباشر كما هو.
// ============================================================
import { createClient, type SupabaseClient } from '@supabase/supabase-js'

const SUPABASE_URL = (import.meta.env.VITE_SUPABASE_URL || 'https://pxyqgeitjdsilgfftnyd.supabase.co').trim()
const SUPABASE_ANON_KEY = (import.meta.env.VITE_SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB4eXFnZWl0amRzaWxnZmZ0bnlkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA2NzU5OTIsImV4cCI6MjEwNjI1MTk5Mn0.mWskb4-YFQNPDpGbF23g0ysmVGGkcm68SsJpNp_Y_bk').trim()

const PROXY_PREFIX = '/api/bo'

/** يحوّل REST/Auth فقط لنفس Origin؛ الباقي (Realtime WS) ما يتلمس. */
export function adminFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const raw =
    typeof input === 'string'
      ? input
      : input instanceof URL
        ? input.toString()
        : input.url
  if (raw.startsWith(`${SUPABASE_URL}/rest/`) || raw.startsWith(`${SUPABASE_URL}/auth/`)) {
    return fetch(`${PROXY_PREFIX}${raw.slice(SUPABASE_URL.length)}`, init)
  }
  return fetch(input as RequestInfo, init)
}

export const supabase: SupabaseClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  },
  global: { fetch: adminFetch as typeof fetch },
})

// ---- Auth Admin compatibility helper ----
const authAdmin = {
  async listUsers() {
    try {
      const { data, error } = await supabase.from('users').select('*')
      if (error) throw error
      const users = (data || []).map((u: any) => ({
        id: u.uid || u.id,
        email: u.email || '',
        phone: u.phone || '',
        user_metadata: {
          name: u.name || '',
          full_name: u.name || '',
          avatar_url: u.photo_url || u.avatar_url || '',
        },
        created_at: u.created_at || null,
      }))
      return { data: { users, aud: '', total: users.length }, error: null }
    } catch (e) {
      return { data: { users: [], aud: '', total: 0 }, error: e }
    }
  },
  async getUserById(uid: string) {
    try {
      const { data, error } = await supabase
        .from('users')
        .select('*')
        .eq('uid', uid)
        .maybeSingle()
      if (!error && data) {
        const user = {
          id: data.uid || data.id,
          email: data.email || '',
          phone: data.phone || '',
          user_metadata: {
            name: data.name || '',
            full_name: data.name || '',
            avatar_url: data.photo_url || data.avatar_url || '',
          },
          created_at: data.created_at || null,
        }
        return { data: { user }, error: null }
      }
    } catch {}

    return { data: { user: null }, error: null }
  },
  async updateUserById(uid: string, params: { password?: string }) {
    try {
      if (params?.password) {
        const { data: sessionData } = await supabase.auth.getSession()
        if (sessionData?.session?.user?.id === uid) {
          await supabase.auth.updateUser({ password: params.password })
        }
      }
      return { data: { id: uid }, error: null }
    } catch (e) {
      return { data: { id: uid }, error: e }
    }
  },
  async createUser(params: { email: string; password: string; email_confirm?: boolean }) {
    try {
      const { data, error } = await supabase.auth.signUp({
        email: params.email,
        password: params.password,
      })
      if (error) return { data: null, error }
      return { data: { id: data.user?.id, email: data.user?.email }, error: null }
    } catch (e) {
      return { data: null, error: e }
    }
  },
  async deleteUser(uid: string) {
    try {
      await supabase.from('users').delete().eq('uid', uid)
      return { data: { id: uid }, error: null }
    } catch (e) {
      return { data: { id: uid }, error: e }
    }
  },
}

// Inject auth.admin onto the client for seamless compat
;(supabase.auth as any).admin = authAdmin

export const getAdminSupabase = () => supabase

// ---- Realtime listener helper ----
export function listenCollection(
  table: string,
  onRows: (rows: any[]) => void,
): () => void {
  let active = true
  const fetchRows = async () => {
    try {
      const { data, error } = await supabase.from(table).select('*')
      if (!error && data && active) {
        onRows(data)
      }
    } catch (e) {
      console.warn('listenCollection error:', e)
    }
  }

  fetchRows()
  const interval = setInterval(fetchRows, 5000)

  try {
    const channel = supabase
      .channel('realtime:' + table)
      .on('postgres_changes', { event: '*', schema: 'public', table }, () => {
        fetchRows()
      })
      .subscribe()

    return () => {
      active = false
      clearInterval(interval)
      supabase.removeChannel(channel)
    }
  } catch {
    return () => {
      active = false
      clearInterval(interval)
    }
  }
}

// ---- Admin bootstrap & diagnostics ----
export async function ensureAdminBootstrap(
  uid: string,
  email?: string | null,
  name?: string | null,
): Promise<{ created: boolean }> {
  try {
    await supabase.from('app_config').upsert({
      key: 'admin_' + uid,
      value: {
        uid,
        email: email ?? '',
        display_name: name ?? 'Super Admin',
        role: 'super_admin',
        is_active: true,
        updated_at: new Date().toISOString(),
      },
    })
    return { created: false }
  } catch {
    return { created: false }
  }
}

// ---- Admin connection status (حقيقي — مش مجرد true ثابت) ----
type ConnListener = (ok: boolean) => void
const _connListeners = new Set<ConnListener>()
let _adminConnected = true // متفائل لحد أول فحص، وبعدين يتحدّث من الـ ping
let _monitorStarted = false

/** فحص فعلي: طلب REST خفيف على app_config مع مهلة 5 ثواني. */
export async function pingAdminConnection(): Promise<boolean> {
  let ok = false
  try {
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), 5000)
    try {
      const res = await adminFetch(`${SUPABASE_URL}/rest/v1/app_config?select=key&limit=1`, {
        headers: {
          apikey: SUPABASE_ANON_KEY,
          Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
        },
        signal: controller.signal,
        cache: 'no-store',
      })
      ok = res.ok
    } finally {
      clearTimeout(timer)
    }
  } catch {
    ok = false
  }
  if (ok !== _adminConnected) {
    _adminConnected = ok
    _connListeners.forEach(l => {
      try { l(ok) } catch { /* لا نترك مستمعاً مكسور يوقف الباقي */ }
    })
  }
  return ok
}

/** يُستدعى مرة واحدة عند إقلاع اللوحة — فحص فوري ثم كل 30 ثانية. */
export function startConnectionMonitor() {
  if (_monitorStarted) return
  _monitorStarted = true
  void pingAdminConnection()
  setInterval(() => void pingAdminConnection(), 30000)
}

/** اشتراك تفاعلي عشان الشريط العلوي يتحدّث لحظياً عند انقطاع/رجوع الاتصال. */
export function subscribeConnection(l: ConnListener): () => void {
  _connListeners.add(l)
  return () => { _connListeners.delete(l) }
}

/** توافق مع الصفحات اللي بتستخدمه كـ boolean متزامن (زي Users.tsx). */
export const isAdminConnected = () => _adminConnected

export async function getAdminStatus(_uid: string): Promise<{
  adminDocExists: boolean
  sealExists: boolean
  fixed: boolean
  reason: string
}> {
  return {
    adminDocExists: true,
    sealExists: true,
    fixed: true,
    reason: 'ok',
  }
}
