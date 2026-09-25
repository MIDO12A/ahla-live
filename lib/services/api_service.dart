import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class ApiService {
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;
  ApiService._();

  String _baseUrl = 'https://ahla-live-api.vercel.app/api/v1';

  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  String get baseUrl => _baseUrl;

  Future<String?> _getToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  Future<Map<String, String>> _headers() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final headers = await _headers();
    final url = Uri.parse('$_baseUrl$path');
    final response = await http.get(url, headers: headers);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw ApiException(response.statusCode, body['error']?.toString() ?? 'Unknown error');
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final headers = await _headers();
    final url = Uri.parse('$_baseUrl$path');
    final response = await http.post(url, headers: headers, body: jsonEncode(body));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    final resBody = jsonDecode(response.body) as Map<String, dynamic>;
    throw ApiException(response.statusCode, resBody['error']?.toString() ?? 'Unknown error');
  }

  Future<Map<String, dynamic>> _put(String path, Map<String, dynamic> body) async {
    final headers = await _headers();
    final url = Uri.parse('$_baseUrl$path');
    final response = await http.put(url, headers: headers, body: jsonEncode(body));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    final resBody = jsonDecode(response.body) as Map<String, dynamic>;
    throw ApiException(response.statusCode, resBody['error']?.toString() ?? 'Unknown error');
  }

  // ===== Rankings =====
  Future<List<Map<String, dynamic>>> getRankings(String type) async {
    final data = await _get('/rankings/$type');
    return (data['rankings'] as List).cast<Map<String, dynamic>>();
  }

  // ===== Users =====
  Future<Map<String, dynamic>> generateCustomId() async {
    return await _post('/users/generate-id', {});
  }

  Future<Map<String, dynamic>?> searchByCustomId(String customId) async {
    try {
      final data = await _get('/users/by-custom/$customId');
      return data['user'] as Map<String, dynamic>?;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final data = await _get('/users/search?q=$query');
    return (data['users'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    try {
      final data = await _get('/users/$uid/profile');
      return data['user'] as Map<String, dynamic>?;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> updateProfile(Map<String, dynamic> updates) async {
    await _put('/users/profile', updates);
  }

  // ===== Levels =====
  Future<List<Map<String, dynamic>>> getLevelConfig() async {
    final data = await _get('/levels/config');
    return (data['levels'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getUserLevels(String uid) async {
    final data = await _get('/levels/$uid');
    return data;
  }

  // ===== VIP =====
  Future<List<Map<String, dynamic>>> getVipTiers() async {
    final data = await _get('/vip/tiers');
    return (data['tiers'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getUserVip(String uid) async {
    final data = await _get('/vip/$uid');
    return data;
  }

  // ===== Recharge =====
  Future<List<Map<String, dynamic>>> getRechargePlans() async {
    final data = await _get('/recharge/plans');
    return (data['plans'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createOrder(int planId) async {
    return await _post('/recharge/create-order', {'planId': planId});
  }

  Future<List<Map<String, dynamic>>> getMyOrders() async {
    final data = await _get('/recharge/orders');
    return (data['orders'] as List).cast<Map<String, dynamic>>();
  }

  // ===== Gifts (server-authoritative send) =====
  Future<Map<String, dynamic>> sendGift({
    required String giftId,
    required String receiverId,
    required String roomId,
    int count = 1,
  }) async {
    final body = {
      'giftId': giftId,
      'receiverId': receiverId,
      'roomId': roomId,
      'count': count,
    };
    final data = await _post('/gifts/send', body);
    if (data['success'] == true) return data;
    throw ApiException(400, data['error']?.toString() ?? 'Gift send failed');
  }

  // ===== Lucky Gift (server-authoritative draw) =====
  Future<Map<String, dynamic>> drawLuckyGift({
    required String giftId,
    required String receiverId,
    required String roomId,
    int count = 1,
    int comboCount = 1,
    String? comboId,
  }) async {
    final body = {
      'giftId': giftId,
      'receiverId': receiverId,
      'roomId': roomId,
      'count': count,
      'comboCount': comboCount,
      if (comboId != null) 'comboId': comboId,
    };
    final data = await _post('/lucky/draw', body);
    if (data['success'] == true) return data;
    throw ApiException(400, data['error']?.toString() ?? 'Lucky draw failed');
  }

  // ===== Agencies =====
  Future<Map<String, dynamic>> createAgency(String name) async {
    return await _post('/agencies/create', {'name': name});
  }

  Future<Map<String, dynamic>> getMyAgency() async {
    final data = await _get('/agencies/my');
    return data;
  }

  Future<Map<String, dynamic>> joinAgency(String code) async {
    return await _post('/agencies/join', {'code': code});
  }

  // ===== Auth =====
  Future<Map<String, dynamic>> login(String email, String password) async {
    return await _post('/auth/login', {'email': email, 'password': password});
  }

  Future<Map<String, dynamic>> signup(String email, String password, String name) async {
    return await _post('/auth/signup', {'email': email, 'password': password, 'name': name});
  }

  Future<Map<String, dynamic>> getMe() async {
    return await _get('/auth/me');
  }

  Future<void> deleteAccount() async {
    final headers = await _headers();
    final url = Uri.parse('$_baseUrl/auth/account');
    final response = await http.delete(url, headers: headers);
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw ApiException(response.statusCode, body['error']?.toString() ?? 'Unknown error');
  }

  // ===== Lucky Bags / Red Envelopes =====
  Future<Map<String, dynamic>> sendLuckyBag({
    required String roomId,
    String type = 'coins',
    String scope = 'room',
    int? value,
    int? count,
    int? totalCoins,
    String? greetingText,
    bool isSuper = false,
  }) async {
    return await _post('/lucky-bags/send', {
      'roomId': roomId,
      'type': type,
      'scope': scope,
      'value': value,
      'count': count,
      'totalCoins': totalCoins,
      'greetingText': greetingText,
      'isSuper': isSuper,
    });
  }

  Future<Map<String, dynamic>> grabLuckyBag({
    required String roomId,
    String? bagId,
  }) async {
    return await _post('/lucky-bags/grab', {
      'roomId': roomId,
      if (bagId != null) 'bagId': bagId,
    });
  }

  Future<Map<String, dynamic>> getLuckyBagDetails(String bagId) async {
    return await _get('/lucky-bags/details/$bagId');
  }

  Future<List<dynamic>> getActiveLuckyBags(String roomId) async {
    final res = await _get('/lucky-bags/active/$roomId');
    return res['bags'] as List<dynamic>? ?? [];
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
