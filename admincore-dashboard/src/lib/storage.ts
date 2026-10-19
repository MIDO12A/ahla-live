// Uploads go to Cloudinary (same account + preset as the Flutter app), because
// Firebase Storage is not enabled on this project (no billing account linked).
// The returned URL is a secure_url that the app reads normally via R.cachedImage().

const CLOUD_NAME = 'dl30muiuc';
// Uploads are unsigned (upload_preset only) — no API secret is needed or stored.
// Configure cloudName/apiKey/apiSecret per-browser from the Settings page if needed.
const UPLOAD_PRESET = 'zero_app';

interface CloudinaryConfig {
  cloudName: string;
  apiKey: string;
  apiSecret: string;
}

function getCloudinaryConfig(): CloudinaryConfig {
  let config: CloudinaryConfig | null = null;
  try {
    const raw = localStorage.getItem('cloudinary_config');
    if (raw) config = JSON.parse(raw);
  } catch {}
  if (config && config.cloudName && config.apiKey && config.apiSecret) {
    return config;
  }
  return {
    cloudName: localStorage.getItem('cloudinary_cloud_name') || CLOUD_NAME,
    apiKey: localStorage.getItem('cloudinary_api_key') || '',
    apiSecret: localStorage.getItem('cloudinary_api_secret') || '',
  };
}

export function getCloudinaryStatus(): { configured: boolean; cloudName: string } {
  const cfg = getCloudinaryConfig();
  return { configured: !!cfg.cloudName, cloudName: cfg.cloudName || '' };
}

export function saveCloudinaryConfig(cloudName: string, apiKey: string, apiSecret: string): void {
  const cfg = { cloudName, apiKey, apiSecret };
  localStorage.setItem('cloudinary_config', JSON.stringify(cfg));
  localStorage.setItem('cloudinary_cloud_name', cloudName);
  localStorage.setItem('cloudinary_api_key', apiKey);
  localStorage.setItem('cloudinary_api_secret', apiSecret);
}

export function detectAssetType(fileName: string): string {
  const match = fileName.match(/[?&]assetType=(\w+)/i);
  if (match) {
    const val = match[1].toLowerCase();
    if (['svga', 'vap', 'mp4', 'webp', 'gif', 'png', 'jpg', 'zip', 'json', 'mp3', 'wav', 'ogg', 'm4a', 'aac', 'audio', 'other'].includes(val)) return val;
  }
  const withoutParams = fileName.includes('?') ? fileName.slice(0, fileName.indexOf('?')) : fileName;
  const lower = withoutParams.toLowerCase();
  if (lower.endsWith('.svga')) return 'svga';
  if (lower.endsWith('.vap')) return 'vap';
  if (lower.endsWith('.mp4')) return 'mp4';
  if (lower.endsWith('.webp')) return 'webp';
  if (lower.endsWith('.gif')) return 'gif';
  if (lower.endsWith('.png')) return 'png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'jpg';
  if (lower.endsWith('.zip')) return 'zip';
  if (lower.endsWith('.json')) return 'json';
  if (lower.endsWith('.mp3')) return 'mp3';
  if (lower.endsWith('.wav')) return 'wav';
  if (lower.endsWith('.ogg')) return 'ogg';
  if (lower.endsWith('.m4a')) return 'm4a';
  if (lower.endsWith('.aac')) return 'aac';
  return 'other';
}

const FOLDERS = {
  giftIcon: 'gift_icons',
  giftAnim: 'gift_animations',
  storeIcon: 'store_icons',
  storeFile: 'store_files',
  appAsset: 'app_assets',
  appSound: 'app_sounds',
  config: 'app_config',
  userPhoto: 'user_photos',
  roomPhoto: 'room_photos',
  banner: 'banners',
  levelIcon: 'level_icons',
} as const;

// ---- Cloudinary signed upload (mirrors CloudinaryService in the Flutter app) ----

function resourceTypeFor(file: File): 'auto' | 'image' | 'video' | 'raw' {
  const t = detectAssetType(file.name);
  if (t === 'svga' || t === 'vap' || t === 'zip' || t === 'json') return 'raw';
  if (t === 'mp4' || t === 'webm' || t === 'mov' || t === 'mp3' || t === 'wav' || t === 'ogg' || t === 'm4a' || t === 'aac' || t === 'audio') return 'video';
  return 'auto';
}

function cloudinaryUploadUrl(cloudName: string, resourceType: string): string {
  return `https://api.cloudinary.com/v1_1/${cloudName}/${resourceType}/upload`;
}

// Unsigned upload via `upload_preset` only. Signed uploads are rejected by the
// browser because Cloudinary does not send CORS headers for signed requests;
// the unsigned flow returns `Access-Control-Allow-Origin` for any browser origin
// and never exposes the API secret. (The Flutter app signs on-device instead.)
async function uploadToCloudinaryUnsigned(
  file: File,
  folder: string,
  onProgress?: (pct: number) => void,
): Promise<string> {
  const cfg = getCloudinaryConfig();
  const publicId = `${folder}/${Date.now()}_${file.name.replace(/[^a-zA-Z0-9._-]/g, '_')}`;

  const form = new FormData();
  form.append('file', file);
  form.append('upload_preset', UPLOAD_PRESET);
  form.append('public_id', publicId);

  const resourceType = resourceTypeFor(file);
  const url = cloudinaryUploadUrl(cfg.cloudName, resourceType);

  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('POST', url);
    xhr.upload.onprogress = e => {
      if (onProgress && e.lengthComputable) {
        onProgress(Math.round((e.loaded / e.total) * 100));
      }
    };
    xhr.onload = () => {
      try {
        if (xhr.status >= 200 && xhr.status < 300) {
          const data = JSON.parse(xhr.responseText);
          resolve(data.secure_url || data.url);
        } else {
          reject(new Error(`Cloudinary upload failed: ${xhr.status} ${xhr.responseText}`));
        }
      } catch (e) {
        reject(e);
      }
    };
    xhr.onerror = () => reject(new Error('Cloudinary upload network error'));
    xhr.send(form);
  });
}

// ---- Signed upload fallback ----
// If the `zero_app` preset is set to "Signed" mode on Cloudinary, unsigned
// browser uploads are rejected with "Upload preset must be whitelisted".
// In that case we sign the request with the API key/secret saved from the
// Settings page (localStorage) and post it directly — Cloudinary's upload
// endpoint returns CORS headers for both signed and unsigned browser uploads.

async function sha1Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest('SHA-1', data);
  return Array.from(new Uint8Array(digest))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

function cloudinaryApiSecret(): string {
  const cfg = getCloudinaryConfig();
  return cfg.apiSecret || '';
}

function xhrPostForm(
  url: string,
  form: FormData,
  onProgress?: (pct: number) => void,
): Promise<string> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('POST', url);
    xhr.upload.onprogress = e => {
      if (onProgress && e.lengthComputable) {
        onProgress(Math.round((e.loaded / e.total) * 100));
      }
    };
    xhr.onload = () => {
      try {
        if (xhr.status >= 200 && xhr.status < 300) {
          const data = JSON.parse(xhr.responseText);
          resolve(data.secure_url || data.url);
        } else {
          reject(new Error(`Cloudinary upload failed: ${xhr.status} ${xhr.responseText}`));
        }
      } catch (e) {
        reject(e);
      }
    };
    xhr.onerror = () => reject(new Error('Cloudinary upload network error'));
    xhr.send(form);
  });
}

async function uploadToCloudinarySigned(
  file: File,
  folder: string,
  onProgress?: (pct: number) => void,
): Promise<string> {
  const cfg = getCloudinaryConfig();
  if (!cfg.apiKey || !cfg.apiSecret) {
    throw new Error(
      'الـ Cloudinary preset متظبط Signed. إما خلّيه Unsigned من لوحة Cloudinary (Settings → Upload → zero_app)، أو حط الـ API Key والـ API Secret من صفحة Settings.'
    );
  }

  const publicId = `${folder}/${Date.now()}_${file.name.replace(/[^a-zA-Z0-9._-]/g, '_')}`;
  const timestamp = Math.floor(Date.now() / 1000);

  const params: Record<string, string | number> = { folder, public_id: publicId, timestamp };
  const toSign = Object.keys(params)
    .sort()
    .map(k => `${k}=${params[k]}`)
    .join('&');
  const signature = await sha1Hex(`${toSign}${cfg.apiSecret}`);

  const form = new FormData();
  form.append('file', file);
  form.append('api_key', cfg.apiKey);
  form.append('timestamp', String(timestamp));
  form.append('signature', signature);
  form.append('public_id', publicId);
  form.append('folder', folder);

  const resourceType = resourceTypeFor(file);
  return xhrPostForm(cloudinaryUploadUrl(cfg.cloudName, resourceType), form, onProgress);
}

async function uploadAny(file: File, folder: string, onProgress?: (pct: number) => void): Promise<string> {
  try {
    return await uploadToCloudinaryUnsigned(file, folder, onProgress);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (/whitelisted|upload preset/i.test(msg)) {
      // Preset is Signed-mode → retry with a signed request.
      return uploadToCloudinarySigned(file, folder, onProgress);
    }
    throw e;
  }
}

// ---- Public upload functions (same signatures as before) ----

export async function uploadToCloudinary(file: File, folder: string, onProgress?: (pct: number) => void): Promise<string> {
  return uploadAny(file, folder || FOLDERS.appAsset, onProgress);
}

export async function uploadGiftIcon(file: File, giftId: string, onProgress?: (pct: number) => void): Promise<string> {
  return uploadAny(file, FOLDERS.giftIcon, onProgress);
}

export async function uploadGiftAnimation(file: File, giftId: string, onProgress?: (pct: number) => void): Promise<string> {
  return uploadAny(file, FOLDERS.giftAnim, onProgress);
}

export async function uploadStoreItem(file: File, itemId: string, onProgress?: (pct: number) => void): Promise<string> {
  const type = detectAssetType(file.name);
  const isAnimOrFile = type === 'svga' || type === 'json' || type === 'zip' || type === 'mp4' || type === 'vap';
  const folder = isAnimOrFile ? FOLDERS.storeFile : FOLDERS.storeIcon;
  return uploadAny(file, folder, onProgress);
}

export async function uploadAppAsset(file: File, assetKey: string, onProgress?: (pct: number) => void): Promise<string> {
  return uploadAny(file, FOLDERS.appAsset, onProgress);
}

export async function uploadUserPhoto(file: File, uid: string, onProgress?: (pct: number) => void): Promise<string> {
  return uploadAny(file, FOLDERS.userPhoto, onProgress);
}

export async function uploadLevelImage(file: File, levelType: string, levelNum: number, onProgress?: (pct: number) => void): Promise<string> {
  return uploadAny(file, FOLDERS.levelIcon, onProgress);
}

export async function uploadRoomPhoto(file: File, roomId: string, onProgress?: (pct: number) => void): Promise<string> {
  return uploadAny(file, FOLDERS.roomPhoto, onProgress);
}

export async function uploadBanner(file: File, bannerId: string, onProgress?: (pct: number) => void): Promise<string> {
  return uploadAny(file, FOLDERS.banner, onProgress);
}

export async function uploadBadgeIcon(file: File, badgeId: string, onProgress?: (pct: number) => void): Promise<string> {
  return uploadAny(file, FOLDERS.giftIcon, onProgress);
}

export async function uploadBadgeSvga(file: File, badgeId: string, onProgress?: (pct: number) => void): Promise<string> {
  return uploadAny(file, FOLDERS.giftAnim, onProgress);
}

export async function uploadGiftBannerSvga(file: File, bannerId: string, onProgress?: (pct: number) => void): Promise<string> {
  return uploadAny(file, FOLDERS.banner, onProgress);
}

export async function uploadSplash(file: File, splashId: string, onProgress?: (pct: number) => void): Promise<string> {
  return uploadAny(file, 'splash', onProgress);
}

export async function uploadSound(file: File, soundId: string, onProgress?: (pct: number) => void): Promise<string> {
  return uploadAny(file, FOLDERS.appSound, onProgress);
}
