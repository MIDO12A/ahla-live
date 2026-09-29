class SupabaseConfig {
  static const String projectUrl = 'https://pxyqgeitjdsilgfftnyd.supabase.co';
  
  // قم بلصق مفتاح anon / public من صفحة:
  // https://supabase.com/dashboard/project/pxyqgeitjdsilgfftnyd/settings/api
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );
}
