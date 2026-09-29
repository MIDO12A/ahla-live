import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';
import '../models/user_model.dart';

class AppAuthUser {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final String? phoneNumber;

  const AppAuthUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.phoneNumber,
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'phoneNumber': phoneNumber,
      };

  factory AppAuthUser.fromMap(Map<String, dynamic> map) => AppAuthUser(
        uid: map['uid'] as String,
        email: map['email'] as String?,
        displayName: map['displayName'] as String?,
        photoUrl: map['photoUrl'] as String?,
        phoneNumber: map['phoneNumber'] as String?,
      );
}

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

  AppAuthUser? _currentUser;
  AppAuthUser? get currentUser => _currentUser;
  String? get currentUid => _currentUser?.uid;
  bool get isSignedIn => _currentUser != null && _currentUser!.uid.isNotEmpty;

  final StreamController<String?> _authController = StreamController<String?>.broadcast();
  Stream<String?> get authStateChanges => _authController.stream;

  /// Initialize local session from SharedPreferences
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString('supabase_auth_uid');
      if (uid != null && uid.isNotEmpty) {
        _currentUser = AppAuthUser(
          uid: uid,
          email: prefs.getString('supabase_auth_email'),
          displayName: prefs.getString('supabase_auth_name'),
          photoUrl: prefs.getString('supabase_auth_photo'),
          phoneNumber: prefs.getString('supabase_auth_phone'),
        );
        debugPrint('[SupabaseAuth] Restored local session for uid: $uid');
        _authController.add(uid);
      } else {
        _authController.add(null);
      }
    } catch (e) {
      debugPrint('[SupabaseAuth] init error: $e');
    }
  }

  /// Save session locally
  Future<void> saveSession({
    required String uid,
    String? email,
    String? name,
    String? photoUrl,
    String? phone,
    String? token,
  }) async {
    _currentUser = AppAuthUser(
      uid: uid,
      email: email,
      displayName: name,
      photoUrl: photoUrl,
      phoneNumber: phone,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('supabase_auth_uid', uid);
      if (email != null) await prefs.setString('supabase_auth_email', email);
      if (name != null) await prefs.setString('supabase_auth_name', name);
      if (photoUrl != null) await prefs.setString('supabase_auth_photo', photoUrl);
      if (phone != null) await prefs.setString('supabase_auth_phone', phone);
      if (token != null) await prefs.setString('supabase_auth_token', token);
    } catch (e) {
      debugPrint('[SupabaseAuth] saveSession error: $e');
    }
    _authController.add(uid);
  }

  /// Sign out and clear local session
  Future<void> signOut() async {
    _currentUser = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('supabase_auth_uid');
      await prefs.remove('supabase_auth_email');
      await prefs.remove('supabase_auth_name');
      await prefs.remove('supabase_auth_photo');
      await prefs.remove('supabase_auth_phone');
      await prefs.remove('supabase_auth_token');
    } catch (_) {}
    _authController.add(null);
  }

  String _hashPin(String pin) {
    return sha256.convert(utf8.encode('ahla_pin_salt_$pin')).toString();
  }

  /// Sign in or register with Phone and PIN directly on Supabase (No Firebase required)
  Future<AppAuthUser> signInOrRegisterWithPhone({
    required String phone,
    required String pin,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '');
    final pinHash = _hashPin(pin);

    // 1. Check if user already exists with this phone number
    final queryUrl = Uri.parse('$_baseUrl/rest/v1/users?phone=eq.$cleanPhone&select=*');
    final queryRes = await http.get(queryUrl, headers: _headers);

    if (queryRes.statusCode == 200) {
      final list = jsonDecode(queryRes.body) as List;
      if (list.isNotEmpty) {
        final userData = Map<String, dynamic>.from(list.first);
        final uid = userData['uid'] as String;
        final storedPinHash = (userData['last_ip'] ?? '').toString();

        // Check PIN if previously configured
        if (storedPinHash.startsWith('pin:') && storedPinHash != 'pin:$pinHash') {
          throw Exception('رمز الدخول (PIN) غير صحيح لهذا الرقم');
        }

        // Save PIN if not previously set
        if (!storedPinHash.startsWith('pin:')) {
          await http.patch(
            Uri.parse('$_baseUrl/rest/v1/users?uid=eq.$uid'),
            headers: _headers,
            body: jsonEncode({'last_ip': 'pin:$pinHash'}),
          );
        }

        final authUser = AppAuthUser(
          uid: uid,
          phoneNumber: cleanPhone,
          displayName: userData['name'] as String?,
          photoUrl: userData['photo_url'] as String?,
          email: userData['email'] as String?,
        );

        await saveSession(
          uid: uid,
          phone: cleanPhone,
          name: userData['name'],
          photoUrl: userData['photo_url'],
          email: userData['email'],
        );

        return authUser;
      }
    }

    // 2. New user registration
    final rng = Random();
    final newUid = 'p_${DateTime.now().millisecondsSinceEpoch}_${(1000 + rng.nextInt(9000))}';
    final createUrl = Uri.parse('$_baseUrl/rest/v1/users');
    final headers = {
      ..._headers,
      'Prefer': 'resolution=merge-duplicates',
    };

    final newUserData = {
      'uid': newUid,
      'phone': cleanPhone,
      'name': 'مستخدم ${cleanPhone.length >= 4 ? cleanPhone.substring(cleanPhone.length - 4) : ""}',
      'last_ip': 'pin:$pinHash',
      'coins': 10000,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    final res = await http.post(
      createUrl,
      headers: headers,
      body: jsonEncode(newUserData),
    );

    debugPrint('[SupabaseAuth] New phone user created status: ${res.statusCode}');

    final authUser = AppAuthUser(
      uid: newUid,
      phoneNumber: cleanPhone,
      displayName: newUserData['name'] as String?,
    );

    await saveSession(
      uid: newUid,
      phone: cleanPhone,
      name: newUserData['name'] as String?,
    );

    return authUser;
  }

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

  /// Fetch user directly from Supabase database `public.users`
  Future<UserModel?> getUserFromSupabase(String uid) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/users?uid=eq.$uid&select=*');
      final response = await http.get(url, headers: _headers);
      debugPrint('[SupabaseAuth] getUser status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List;
        if (list.isNotEmpty) {
          final data = Map<String, dynamic>.from(list.first);
          return UserModel.fromMap(data);
        }
      }
      return null;
    } catch (e) {
      debugPrint('[SupabaseAuth] getUserFromSupabase error: $e');
      return null;
    }
  }

  /// Save full user model directly to Supabase database `public.users`
  Future<bool> saveUserToSupabase(UserModel user) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/users');
      final headers = {
        ..._headers,
        'Prefer': 'resolution=merge-duplicates',
      };
      final data = user.toMap();
      data['uid'] = user.uid;
      data['updated_at'] = DateTime.now().toUtc().toIso8601String();

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(data),
      );
      debugPrint('[SupabaseAuth] saveUser status: ${response.statusCode}');
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('[SupabaseAuth] saveUserToSupabase error: $e');
      return false;
    }
  }
}
