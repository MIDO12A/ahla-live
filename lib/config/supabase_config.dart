import '../core/supabase_compat.dart';

class SupabaseConfig {
  static const String projectUrl = 'https://pxyqgeitjdsilgfftnyd.supabase.co';
  
  /// Supabase disabled the legacy `anon` JWT for this project; the publishable
  /// key is now the only valid public API key. Keep the old JWT for reference.
  static const String publishableKey =
      'sb_publishable_q1Vtqddl7IZazMfLLbYuAw_Qi6NMFrv';

  static const String anonKey = publishableKey;

  static const String legacyAnonJwt =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB4eXF5Z2VpdGpkc2lsZ2ZmdG55ZCIsInJvbGUiOiJhbm9uIiwiaWF0IjoxNzkwNjc1OTkyLCJleHAiOjIxMDYyNTE5OTJ9.mWskb4-YFQNPDpGbF23g0ysmVGGkcm68SsJpNp_Y_bk';

  static SupabaseClient get client => Supabase.instance.client;
}
