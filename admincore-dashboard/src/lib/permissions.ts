export interface PermissionItem {
  key: string;
  ar: string;
  en: string;
}

export interface PermissionCategory {
  id: string;
  ar: string;
  en: string;
  items: PermissionItem[];
}

export const PERMISSION_CATEGORIES: PermissionCategory[] = [
  {
    id: 'users_moderation',
    ar: 'المستخدمون والرقابة',
    en: 'Users & Moderation',
    items: [
      { key: 'users', ar: 'إدارة المستخدمين والحسابات', en: 'Users Management' },
      { key: 'reports', ar: 'البلاغات والتقارير', en: 'Reports & Moderation' },
      { key: 'dashboard_bans', ar: 'الحظر من لوحة الإدارة', en: 'Dashboard Bans' },
    ],
  },
  {
    id: 'gifts_group',
    ar: 'الهدايا وصناديق الحظ (جميع الأقسام الداخلية)',
    en: 'Gifts & Lucky Boxes (All Sub-sections)',
    items: [
      { key: 'gifts', ar: 'صفحة الهدايا الرئيسية', en: 'Main Gifts Page' },
      { key: 'gift_items', ar: 'عناصر وتفاصيل الهدايا', en: 'Gift Items' },
      { key: 'gift_categories', ar: 'تصنيفات وأقسام الهدايا', en: 'Gift Categories' },
      { key: 'gift_banners', ar: 'بانرات وإعلانات الهدايا', en: 'Gift Banner Configs' },
      { key: 'lucky_gifts', ar: 'الهدايا المحظوظة ونسب الربح', en: 'Lucky Gifts' },
      { key: 'red_packets', ar: 'المظاريف وصناديق الحظ 🧧', en: 'Red Packets & Boxes' },
      { key: 'vip_gifting', ar: 'هدايا VIP الحصرية', en: 'VIP Gifting' },
      { key: 'badge_necklace_gifts', ar: 'هدايا الشارات والقلائد', en: 'Badge & Necklace Gifts' },
    ],
  },
  {
    id: 'agency_group',
    ar: 'الوكالات والرواتب وإدارة BD (جميع الأقسام الداخلية)',
    en: 'Agencies, Salaries & BD (All Sub-sections)',
    items: [
      { key: 'agency', ar: 'الوكالات المضيفة (الصفحة الرئيسية)', en: 'Host Agencies' },
      { key: 'agency_recharge', ar: 'وكالات الشحن والرواتب', en: 'Recharge Agencies & Salaries' },
      { key: 'agency_requests', ar: 'طلبات فتح الوكالات', en: 'Agency Requests' },
      { key: 'agency_milestones', ar: 'المراحل والتارجت والرواتب', en: 'Milestones & Targets' },
      { key: 'agency_members', ar: 'أعضاء ومضيفو الوكالات', en: 'Agency Members' },
      { key: 'agency_necklaces', ar: 'قلادات الوكالة SVGA', en: 'Agency Necklaces SVGA' },
      { key: 'agency_join_requests', ar: 'طلبات الانضمام للوكالات', en: 'Agency Join Requests' },
      { key: 'agency_financial', ar: 'السجلات المالية وسحوبات الوكالات', en: 'Agency Financial & Ledger' },
      { key: 'agency_commission', ar: 'نسب العمولات العامة', en: 'Agency Commissions' },
      { key: 'bd', ar: 'إدارة وكلاء الأعمال BD', en: 'BD Management' },
    ],
  },
  {
    id: 'rooms_group',
    ar: 'الغرف والمحادثات ومحرك الصوت',
    en: 'Rooms, Chat & Voice Engine',
    items: [
      { key: 'rooms', ar: 'إدارة الغرف الصوتية', en: 'Rooms Management' },
      { key: 'room_backgrounds', ar: 'خلفيات الغرف', en: 'Room Backgrounds' },
      { key: 'audio_settings', ar: 'إعدادات ومحرك الصوت Zego', en: 'Voice Engine & Zego' },
      { key: 'app_sounds', ar: 'المؤثرات الصوتية للتطبيق', en: 'App Sounds & Effects' },
    ],
  },
  {
    id: 'store_vip_group',
    ar: 'المتجر والاشتراكات والمستويات',
    en: 'Store, VIP & Levels',
    items: [
      { key: 'store', ar: 'متجر العناصر والدخوليات', en: 'Store & Items' },
      { key: 'vip', ar: 'باقات واشتراكات VIP', en: 'VIP Subscriptions' },
      { key: 'unions', ar: 'العائلات والتحالفات', en: 'Unions & Families' },
      { key: 'levels', ar: 'المستويات وتدرج الشحن', en: 'Levels' },
      { key: 'badges', ar: 'الشارات والأوسمة', en: 'Badges' },
      { key: 'necklaces', ar: 'القلائد SVGA', en: 'Necklaces SVGA' },
    ],
  },
  {
    id: 'events_tasks_group',
    ar: 'الفعاليات والمهام والمكافآت',
    en: 'Events, Tasks & Rewards',
    items: [
      { key: 'recharge_event', ar: 'فعاليات وعروض الشحن', en: 'Recharge Events' },
      { key: 'tasks_manager', ar: 'مركز المهام والمكافآت', en: 'Tasks & Daily Rewards' },
      { key: 'signin_features', ar: 'مكافآت تسجيل الدخول اليومي', en: 'Daily Sign-in Rewards' },
      { key: 'cp_features', ar: 'ميزات وعلاقات الـ CP', en: 'CP Features & Rings' },
    ],
  },
  {
    id: 'visuals_design_group',
    ar: 'المظهر والتصميم والتخصيص',
    en: 'Design & Visual Customization',
    items: [
      { key: 'visual_manager', ar: 'المظهر الشامل للواجهات', en: 'Visual Manager' },
      { key: 'screen_customization', ar: 'تخصيص الشاشات والواجهات', en: 'Screen Customization' },
      { key: 'app_visual_designer', ar: 'مصمم الواجهات المرئي', en: 'Visual App Designer' },
      { key: 'app_assets', ar: 'ملفات ووسائط التطبيق', en: 'App Assets' },
      { key: 'app_icons', ar: 'أيقونات التطبيق', en: 'App Icons' },
      { key: 'image_customize', ar: 'تخصيص الصور', en: 'Images Customization' },
      { key: 'color_customize', ar: 'تخصيص الألوان', en: 'Colors Customization' },
      { key: 'emojis', ar: 'إدارة الإيموجي', en: 'Emojis Management' },
      { key: 'banners', ar: 'البانرات الإعلانية العامة', en: 'General Banners' },
      { key: 'profile_customize', ar: 'تخصيص البروفايل والملف الشخصي', en: 'Profile Customization' },
    ],
  },
  {
    id: 'system_admin_group',
    ar: 'إدارة النظام والمشرفين',
    en: 'System & Admin Management',
    items: [
      { key: 'admins', ar: 'إدارة المشرفين والصلاحيات', en: 'Admins & Permissions' },
      { key: 'notifications', ar: 'إرسال الإشعارات العامة', en: 'Push Notifications' },
      { key: 'app_updates', ar: 'إصدارات وتحديثات التطبيق', en: 'App Updates' },
      { key: 'error_analysis', ar: 'تحليل وسجلات الأخطاء', en: 'Error Analysis' },
      { key: 'settings', ar: 'إعدادات اللوحة ومفاتيح الربط', en: 'Settings' },
    ],
  },
];

export const ALL_PERMISSIONS: PermissionItem[] = PERMISSION_CATEGORIES.flatMap(c => c.items);
export const ALL_PERMISSION_KEYS: string[] = ALL_PERMISSIONS.map(p => p.key);

export function getAllPermissionsMap(): Record<string, boolean> {
  const map: Record<string, boolean> = {};
  for (const k of ALL_PERMISSION_KEYS) {
    map[k] = true;
  }
  return map;
}

export function getDefaultPermissionsForRole(role: string): Record<string, boolean> {
  if (role === 'super_admin' || role === 'superadmin' || role === 'admin') {
    return getAllPermissionsMap();
  }
  // Standard moderator permissions
  const modKeys = [
    'users',
    'reports',
    'rooms',
    'room_backgrounds',
    'notifications',
    'gifts',
    'store',
  ];
  const map: Record<string, boolean> = {};
  for (const k of ALL_PERMISSION_KEYS) {
    map[k] = modKeys.includes(k);
  }
  return map;
}

export function canUserAccess(
  user: { role?: string; permissions?: string[] } | null | undefined,
  permKey: string
): boolean {
  if (!user) return true;
  const role = user.role || '';
  if (role === 'owner') return true;

  const perms = user.permissions || [];
  if (perms.includes('all') || perms.includes('*')) return true;
  if (!permKey || permKey === 'dashboard') return true;

  // Exact permission match
  if (perms.includes(permKey)) return true;

  // Top-level route fallbacks (allow sidebar navigation if user holds ANY child permission)
  if (permKey === 'agency' && perms.some(p => p.startsWith('agency_') || p === 'agency')) return true;
  if (permKey === 'gifts' && perms.some(p => p.startsWith('gift_') || p === 'gifts')) return true;

  return false;
}
