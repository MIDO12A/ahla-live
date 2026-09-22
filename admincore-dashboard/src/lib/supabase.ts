// ============================================================
// Firestore backend for the admin dashboard.
// This module replaces the old Supabase client with a Firestore
// drop-in that mimics the PostgREST query API (`.from().select()...`)
// used across db.ts and the pages, so the whole dashboard now reads
// and writes the SAME Firestore collections the Flutter app uses.
// ============================================================
import {
  collection,
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
  deleteDoc,
  addDoc,
  onSnapshot,
  query,
  where,
  type QueryConstraint,
} from 'firebase/firestore'
import { getFirestore, type Firestore } from 'firebase/firestore'
import { sendPasswordResetEmail } from 'firebase/auth'
import { firebaseApp, firebaseAuth } from './firebase'

const db: Firestore = getFirestore(firebaseApp)

// Which document field is the document ID for each collection.
const KEY_FIELDS: Record<string, string> = {
  users: 'uid',
  rooms: 'room_id',
  store_items: 'item_id',
  app_config: 'key',
  cp_settings: 'key',
  commission_settings: 'key',
  admin_users: 'uid',
  app_assets: 'id',
  level_config: 'id',
  store_categories: 'id',
}

function docKeyFor(table: string, values: Record<string, unknown>): string | undefined {
  if (values['key'] != null) return String(values['key'])
  if (values['id'] != null) return String(values['id'])
  if (values['item_id'] != null) return String(values['item_id'])
  if (values['room_id'] != null) return String(values['room_id'])
  if (values['uid'] != null) return String(values['uid'])
  if (table === 'level_config' && values['type'] != null && values['level'] != null) {
    return `${values['type']}_${values['level']}`
  }
  if (table === 'vip_config' && values['tier'] != null) return `tier_${values['tier']}`
  return undefined
}

export interface FbResult {
  data: any
  count?: number
  error: any
}

type Mode = 'select' | 'insert' | 'upsert' | 'update' | 'delete'

class FbQuery {
  private table: string
  private filters: { field: string; value: unknown }[] = []
  private orders: { field: string; dir: 'asc' | 'desc' }[] = []
  private limitN?: number
  private offset = 0
  private orExpr?: { field: string; value: string }[]
  private notNulls: string[] = []
  private countOnly = false
  private headOnly = false
  private mode: Mode = 'select'
  private mutationValues: Record<string, unknown> = {}

  constructor(table: string) {
    this.table = table
  }

  select(_cols = '*', opts?: { count?: 'exact'; head?: boolean }) {
    if (opts?.count === 'exact') {
      this.countOnly = true
      this.headOnly = opts.head ?? false
    }
    return this
  }

  eq(field: string, value: unknown) {
    this.filters.push({ field, value })
    return this
  }

  is(field: string, value: unknown) {
    this.filters.push({ field, value })
    return this
  }

  order(field: string, opts?: { ascending?: boolean }) {
    this.orders.push({ field, dir: opts?.ascending === false ? 'desc' : 'asc' })
    return this
  }

  limit(n: number) {
    this.limitN = n
    return this
  }

  range(start: number, end: number) {
    this.offset = start
    this.limitN = end - start + 1
    return this
  }

  not(field: string, op: string, value: unknown) {
    if (op === 'is' && value === null) this.notNulls.push(field)
    return this
  }

  or(expr: string) {
    this.orExpr = expr
      .split(',')
      .map(part => {
        const m = part.match(/^([^.]+)\.ilike\.%(.+)%$/)
        if (m) return { field: m[1], value: m[2].toLowerCase() }
        const m2 = part.match(/^([^.]+)\.ilike\.(.+)$/)
        if (m2) return { field: m2[1], value: m2[2].replace(/%/g, '').toLowerCase() }
        return null
      })
      .filter((x): x is { field: string; value: string } => !!x)
    return this
  }

  insert(values: Record<string, unknown>) {
    this.mode = 'insert'
    this.mutationValues = values
    return this
  }

  upsert(values: Record<string, unknown>, _opts?: unknown) {
    this.mode = 'upsert'
    this.mutationValues = values
    return this
  }

  update(values: Record<string, unknown>) {
    this.mode = 'update'
    this.mutationValues = values
    return this
  }

  delete() {
    this.mode = 'delete'
    return this
  }

  private async _execute(): Promise<FbResult> {
    try {
      switch (this.mode) {
        case 'select':
          return await this._runSelect()
        case 'insert':
          return await this._runInsert(false)
        case 'upsert':
          return await this._runInsert(true)
        case 'update':
          return await this._runUpdate()
        case 'delete':
          return await this._runDelete()
      }
    } catch (e) {
      return { data: null, count: 0, error: e }
    }
  }

  private keyField(): string {
    return KEY_FIELDS[this.table] ?? 'id'
  }

  private async _runSelect(): Promise<FbResult> {
    const keyField = this.keyField()
    // Look for keyField, 'id', or 'uid' filter
    const directFilter = this.filters.find(f => f.field === keyField || f.field === 'id' || f.field === 'uid')
    if (directFilter && this.filters.length === 1 && typeof directFilter.value === 'string' && directFilter.value) {
      const snap = await getDoc(doc(db, this.table, String(directFilter.value)))
      if (snap.exists()) {
        const row = { ...snap.data(), id: snap.id, uid: snap.id }
        return { data: [row], count: this.countOnly ? 1 : undefined, error: null }
      }
    }

    const constraints: QueryConstraint[] = this.filters.map(f => where(f.field, '==', f.value))
    let snap
    try {
      snap = await getDocs(query(collection(db, this.table), ...constraints))
    } catch {
      snap = await getDocs(collection(db, this.table))
    }
    let rows = snap.docs.map(d => ({ ...d.data(), id: d.id, uid: d.id }))

    if (this.orExpr) {
      rows = rows.filter(r =>
        this.orExpr!.some(o => {
          const val = r[o.field]
          return typeof val === 'string' && val.toLowerCase().includes(o.value)
        }),
      )
    }
    if (this.notNulls.length) {
      rows = rows.filter(r => this.notNulls.every(f => r[f] != null))
    }
    if (this.orders.length) {
      rows.sort((a, b) => {
        for (const o of this.orders) {
          const av = a[o.field] ?? 0
          const bv = b[o.field] ?? 0
          if (av < bv) return o.dir === 'asc' ? -1 : 1
          if (av > bv) return o.dir === 'asc' ? 1 : -1
        }
        return 0
      })
    }
    if (this.offset) rows = rows.slice(this.offset)
    if (this.limitN != null) rows = rows.slice(0, this.limitN)
    return { data: rows, count: this.countOnly ? rows.length : undefined, error: null }
  }

  private async _runInsert(merge: boolean): Promise<FbResult> {
    const values = this.mutationValues
    const key = docKeyFor(this.table, values)
    if (key) {
      if (merge) {
        await setDoc(doc(db, this.table, key), values, { merge: true })
      } else {
        await setDoc(doc(db, this.table, key), values)
      }
      const item = { ...values, id: key, uid: key }
      return { data: [item], error: null }
    }
    const r = await addDoc(collection(db, this.table), values)
    const item = { ...values, id: r.id, uid: r.id }
    return { data: [item], error: null }
  }

  private async _runUpdate(): Promise<FbResult> {
    const keyField = this.keyField()
    const directFilter = this.filters.find(f => f.field === keyField || f.field === 'id' || f.field === 'uid')
    if (directFilter && typeof directFilter.value === 'string' && directFilter.value) {
      try {
        await setDoc(doc(db, this.table, String(directFilter.value)), this.mutationValues, { merge: true })
        return { data: [], error: null }
      } catch (e) {
        console.error(`_runUpdate on ${this.table}/${directFilter.value} failed:`, e)
      }
    }
    const snap = await getDocs(
      query(collection(db, this.table), ...this.filters.map(f => where(f.field, '==', f.value))),
    )
    for (const d of snap.docs) {
      await setDoc(d.ref, this.mutationValues, { merge: true })
    }
    return { data: [], error: null }
  }

  private async _runDelete(): Promise<FbResult> {
    const keyField = this.keyField()
    const directFilter = this.filters.find(f => f.field === keyField || f.field === 'id' || f.field === 'uid')
    if (directFilter && typeof directFilter.value === 'string' && directFilter.value) {
      await deleteDoc(doc(db, this.table, String(directFilter.value)))
      return { data: [], error: null }
    }
    const snap = await getDocs(
      query(collection(db, this.table), ...this.filters.map(f => where(f.field, '==', f.value))),
    )
    for (const d of snap.docs) await deleteDoc(d.ref)
    return { data: [], error: null }
  }

  async maybeSingle() {
    const r = await this._execute()
    const item = Array.isArray(r.data) ? (r.data[0] ?? null) : (r.data ?? null)
    return { data: item, error: r.error }
  }

  async single() {
    const r = await this._execute()
    const item = Array.isArray(r.data) ? (r.data[0] ?? null) : (r.data ?? null)
    return {
      data: item,
      error: r.error || (item ? null : new Error('No rows found')),
    }
  }

  then<TResult1 = FbResult, TResult2 = never>(
    onfulfilled?: ((value: FbResult) => TResult1 | PromiseLike<TResult1>) | null,
    onrejected?: ((reason: any) => TResult2 | PromiseLike<TResult2>) | null,
  ): Promise<TResult1 | TResult2> {
    return this._execute().then(onfulfilled, onrejected)
  }
}

class FbChannel {
  private table = ''
  private cb: (() => void) | null = null
  private unsub: (() => void) | null = null

  on(_event: string, filter: { table?: string; event?: string; schema?: string }, cb: () => void) {
    this.table = filter?.table ?? ''
    this.cb = cb
    return this
  }

  subscribe(statusCb?: (status: string) => void) {
    if (this.table && this.cb) {
      this.unsub = onSnapshot(collection(db, this.table), () => this.cb?.())
    }
    statusCb?.('SUBSCRIBED')
    return this
  }

  removeChannel() {
    try {
      this.unsub?.()
    } catch {}
  }
}

// ---- Firebase Auth "admin" compat (browser-safe subset) ----

const API_KEY = firebaseApp.options?.apiKey ?? ''

async function getFirestoreUser(uid: string) {
  const snap = await getDoc(doc(db, 'users', uid))
  if (!snap.exists()) return null
  const d = snap.data()
  return {
    id: uid,
    email: d.email ?? '',
    phone: d.phone ?? '',
    user_metadata: { name: d.name ?? '', full_name: d.name ?? '', avatar_url: d.photo_url ?? '' },
    created_at: d.created_at ?? null,
  }
}

const authAdmin = {
  async listUsers() {
    try {
      const snap = await getDocs(collection(db, 'users'))
      const users = snap.docs.map(d => {
        const data = d.data()
        return {
          id: d.id,
          email: data.email ?? '',
          phone: data.phone ?? '',
          user_metadata: {
            name: data.name ?? '',
            full_name: data.name ?? '',
            avatar_url: data.photo_url ?? '',
          },
          created_at: data.created_at ?? null,
        }
      })
      return { data: { users, aud: '', total: users.length }, error: null }
    } catch (e) {
      return { data: { users: [], aud: '', total: 0 }, error: e }
    }
  },
  async getUserById(uid: string) {
    try {
      const user = await getFirestoreUser(uid)
      return { data: { user }, error: null }
    } catch (e) {
      return { data: { user: null }, error: e }
    }
  },
  async updateUserById(uid: string, params: { password?: string }) {
    try {
      if (params?.password) {
        const user = await getFirestoreUser(uid)
        if (user?.email) {
          await sendPasswordResetEmail(firebaseAuth, user.email)
        }
      }
      return { data: { id: uid }, error: null }
    } catch (e) {
      return { data: { id: uid }, error: e }
    }
  },
  async createUser(params: { email: string; password: string; email_confirm?: boolean }) {
    try {
      const res = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: params.email,
          password: params.password,
          returnSecureToken: false,
        }),
      })
      const json = await res.json()
      if (json.error) return { data: null, error: new Error(json.error.message) }
      return { data: { id: json.localId, email: json.email }, error: null }
    } catch (e) {
      return { data: null, error: e }
    }
  },
  async deleteUser(uid: string) {
    try {
      await deleteDoc(doc(db, 'users', uid))
      return { data: { id: uid }, error: null }
    } catch (e) {
      return { data: { id: uid }, error: e }
    }
  },
}

// ---- Public compat client ----

export const supabase = {
  from: (table: string) => new FbQuery(table),
  channel: (_name: string) => new FbChannel(),
  removeChannel: (ch: FbChannel) => ch?.removeChannel(),
  auth: { admin: authAdmin },
  // storage kept as a stub — uploads now go to Firebase Storage (see storage.ts)
  storage: {
    from: () => ({
      upload: async () => ({ error: new Error('Supabase storage is no longer used') }),
      getPublicUrl: () => ({ data: { publicUrl: '' } }),
    }),
  },
}

export const getAdminSupabase = () => supabase

// ---- Realtime helper (onSnapshot) ----
// للصفحات اللي تطلب تحديث لحظي لمجموعة (مثل مكافآت CP في CpFeatures).
// ترجع دالة إلغاء الاشتراك.
export function listenCollection(
  table: string,
  onRows: (rows: any[]) => void,
): () => void {
  const unsub = onSnapshot(
    query(collection(db, table)),
    snap => onRows(snap.docs.map(d => ({ ...d.data(), id: d.id }))),
    err => console.warn(`listenCollection(${table}) error:`, err),
  )
  return () => unsub()
}

// ---- First-admin bootstrap ----
// Firestore rules gate every admin write on `admin_users/{authUid}` existing
// (see firestore.rules `isAdmin()`). This runs right after login: if no admin
// has ever been created (the `admin_users/_config` seal is missing), the first
// signed-in user is promoted to super_admin automatically. After that the seal
// blocks any further self-elevation.
export async function ensureAdminBootstrap(
  uid: string,
  email?: string | null,
  name?: string | null,
): Promise<{ created: boolean }> {
  try {
    const sealRef = doc(db, 'admin_users', '_config')
    const seal = await getDoc(sealRef)
    if (seal.exists()) return { created: false }

    // Order matters: the admin doc must exist BEFORE the seal, because the
    // create rule allows a self-elevation only while `_config` is missing.
    await setDoc(doc(db, 'admin_users', uid), {
      uid,
      email: email ?? '',
      display_name: name ?? 'Super Admin',
      role: 'super_admin',
      permissions: { all: true },
      is_active: true,
      created_at: new Date().toISOString(),
    })
    await setDoc(sealRef, { sealed: true, sealed_at: new Date().toISOString() })
    console.log('✅ First admin bootstrapped:', uid)
    return { created: true }
  } catch {
    // Another admin was already bootstrapped (seal exists) or rules changed.
    return { created: false }
  }
}

export const isAdminConnected = () => true

// ---- Admin bootstrap status (diagnostics) ----
// Returns the exact reason why writes (e.g. adding coins) fail with
// "Missing or insufficient permissions": the Firestore `isAdmin()` rule needs
// `admin_users/{authUid}` to exist, which itself needs the updated
// `firestore.rules` to be DEPLOYED (the create rule for admin_users).
export async function getAdminStatus(uid: string): Promise<{
  adminDocExists: boolean
  sealExists: boolean
  fixed: boolean
  reason: string
}> {
  try {
    const [adminDoc, seal] = await Promise.all([
      getDoc(doc(db, 'admin_users', uid)),
      getDoc(doc(db, 'admin_users', '_config')),
    ])
    if (adminDoc.exists()) return { adminDocExists: true, sealExists: seal.exists(), fixed: true, reason: 'ok' }
    if (seal.exists()) {
      return {
        adminDocExists: false,
        sealExists: true,
        fixed: false,
        reason: `Your account is NOT an admin. The first admin has already been bootstrapped. Fix: ask the current admin to promote you from the Admins page, or delete the \`admin_users/_config\` seal in Firestore and log out/in.`,
      }
    }
    return {
      adminDocExists: false,
      sealExists: false,
      fixed: false,
      reason: `No admin has been bootstrapped yet. Click "Run bootstrap" below. If it fails with a permissions error, the updated firestore.rules are NOT deployed yet — run: firebase deploy --only firestore:rules`,
    }
  } catch (e: any) {
    return {
      adminDocExists: false,
      sealExists: false,
      fixed: false,
      reason: `Failed to check admin status: ${e?.message ?? e}`,
    }
  }
}
