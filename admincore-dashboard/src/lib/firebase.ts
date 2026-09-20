import { initializeApp, type FirebaseApp } from 'firebase/app'
import { getFirestore, type Firestore } from 'firebase/firestore'
import { getAnalytics, isSupported, type Analytics } from 'firebase/analytics'
import {
  getAuth,
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
  sendPasswordResetEmail,
  onAuthStateChanged,
  signOut,
  type Auth,
  type User as FirebaseUser,
} from 'firebase/auth'

const firebaseConfig = {
  apiKey: 'AIzaSyDP0bNjlUFU38F5HLWqJARdtrUWyc7R3gg',
  authDomain: 'ahla-live.firebaseapp.com',
  databaseURL: 'https://ahla-live-default-rtdb.firebaseio.com',
  projectId: 'ahla-live',
  storageBucket: 'ahla-live.firebasestorage.app',
  messagingSenderId: '183199730954',
  appId: '1:183199730954:web:a169a64cda908c51383ef3',
  measurementId: 'G-ZYK2BGX5X3',
}

export const firebaseApp: FirebaseApp = initializeApp(firebaseConfig)
export const firebaseAuth: Auth = getAuth(firebaseApp)
export const firestoreDb: Firestore = getFirestore(firebaseApp)

export async function loginWithFirebaseEmail(email: string, password: string) {
  await signInWithEmailAndPassword(firebaseAuth, email, password)
}

export async function registerWithFirebaseEmail(email: string, password: string) {
  await createUserWithEmailAndPassword(firebaseAuth, email, password)
}

export async function resetFirebasePassword(email: string) {
  await sendPasswordResetEmail(firebaseAuth, email)
}

export function onFirebaseAuthChange(callback: (user: FirebaseUser | null) => void) {
  return onAuthStateChanged(firebaseAuth, callback)
}

export async function firebaseLogout() {
  await signOut(firebaseAuth)
}

let analytics: Analytics | null = null

export const initFirebaseAnalytics = async (): Promise<Analytics | null> => {
  if (analytics) return analytics
  if (!(await isSupported())) return null
  analytics = getAnalytics(firebaseApp)
  return analytics
}
