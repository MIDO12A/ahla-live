import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';

class SupabaseAuthService {
  static final SupabaseAuthService _instance = SupabaseAuthService._internal();
  factory SupabaseAuthService() => _instance;
  SupabaseAuthService._internal();

  static const String _baseUrl = SupabaseConfig.projectUrl;
  static const String _anonKey = SupabaseConfig.anonKey;

  static Map<String, String> get _headers => {
        'apikey': _anonKey,
        'Authorization': 'Bearer $_anonKey',
        'Content-Type': 'application/json',
      };

  /// Sign in to Supabase Auth directly using Google ID Token
  Future<Map<String, dynamic>?> signInWithGoogleIdToken({
    required String idToken,
    String? accessToken,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/auth/v1/token?grant_type=id_token');
      final body = jsonEncode({
        'provider': 'google',
        'id_token': idToken,
        if (accessToken != null) 'access_token': accessToken,
      });

      final response = await http.post(url, headers: _headers, body: body);
      debugPrint('[SupabaseAuth] Google login status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('[SupabaseAuth] Successfully signed in to Supabase Auth via Google!');
        return data;
      } else {
        debugPrint('[SupabaseAuth] Google login failed: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[SupabaseAuth] Google login error: $e');
      return null;
    }
  }

  /// Sync user profile directly into Supabase database `public.users`
  Future<bool> syncUserToSupabase({
    required String uid,
    String? customId,
    String? name,
    String? email,
    String? photoUrl,
    String? phone,
    String? gender,
    int? coins,
    String? country,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/users');
      final headers = {
        ..._headers,
        'Prefer': 'resolution=merge-duplicates',
      };

      final Map<String, dynamic> data = {
        'uid': uid,
        if (customId != null && customId.isNotEmpty) 'custom_id': customId,
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (photoUrl != null) 'photo_url': photoUrl,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (gender != null) 'gender': gender,
        if (coins != null) 'coins': coins,
        if (country != null) 'country': country,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(data),
      );

      debugPrint('[SupabaseAuth] Sync user status: ${response.statusCode}');
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('[SupabaseAuth] Sync user error: $e');
      return false;
    }
  }
}
