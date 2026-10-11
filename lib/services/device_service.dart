import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../config/supabase_config.dart';

class DeviceInfoData {
  final String deviceId;
  final String deviceModel;
  final String macAddress;
  final String networkId;
  final String ipAddress;

  DeviceInfoData({
    required this.deviceId,
    required this.deviceModel,
    required this.macAddress,
    required this.networkId,
    required this.ipAddress,
  });

  Map<String, dynamic> toMap() => {
        'device_id': deviceId,
        'device_model': deviceModel,
        'mac_address': macAddress,
        'network_id': networkId,
        'ip_address': ipAddress,
      };
}

class DeviceService {
  static final DeviceService _instance = DeviceService._internal();
  factory DeviceService() => _instance;
  DeviceService._internal();

  static const String _prefKeyDeviceId = 'app_persistent_device_id';
  static const String _prefKeyNetworkId = 'app_persistent_network_id';

  DeviceInfoData? _cachedInfo;

  Future<DeviceInfoData> getDeviceInfo() async {
    if (_cachedInfo != null) return _cachedInfo!;

    final prefs = await SharedPreferences.getInstance();
    String? persistentId = prefs.getString(_prefKeyDeviceId);
    String? networkId = prefs.getString(_prefKeyNetworkId);

    String model = 'Unknown Device';
    String hardwareId = '';

    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        model = '${android.brand} ${android.model} (${android.device})';
        hardwareId = android.id;
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        model = '${ios.name} ${ios.model}';
        hardwareId = ios.identifierForVendor ?? '';
      }
    } catch (e) {
      debugPrint('[DeviceService] Error getting platform device info: $e');
    }

    if (persistentId == null || persistentId.isEmpty) {
      if (hardwareId.isNotEmpty) {
        persistentId = hardwareId;
      } else {
        persistentId = const Uuid().v4();
      }
      await prefs.setString(_prefKeyDeviceId, persistentId);
    }

    if (networkId == null || networkId.isEmpty) {
      final sub = persistentId.length > 8 ? persistentId.substring(0, 8) : persistentId;
      networkId = 'NET_' + sub.toUpperCase();
      await prefs.setString(_prefKeyNetworkId, networkId);
    }

    String ipAddress = '127.0.0.1';
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: false);
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        ipAddress = interfaces.first.addresses.first.address;
      }
    } catch (_) {}

    final cleanHex = persistentId.replaceAll(RegExp(r'[^a-fA-F0-9]'), '').padRight(8, '0').substring(0, 8).toUpperCase();
    final macAddress = '02:00:' + cleanHex.replaceAllMapped(RegExp(r'.{2}'), (m) => '${m.group(0)}:').substring(0, 11);

    _cachedInfo = DeviceInfoData(
      deviceId: persistentId,
      deviceModel: model,
      macAddress: macAddress,
      networkId: networkId,
      ipAddress: ipAddress,
    );

    return _cachedInfo!;
  }

  Future<bool> canRegisterAccount({
    required String deviceId,
    required String currentEmail,
    String? currentUid,
  }) async {
    final cleanDevice = deviceId.trim();
    if (cleanDevice.isEmpty) return true;

    final registeredEmails = <String>{};
    final registeredUids = <String>{};

    try {
      final url = Uri.parse('${SupabaseConfig.projectUrl}/rest/v1/users?device_id=eq.$cleanDevice&select=uid,email');
      final res = await http.get(url, headers: {
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
      });

      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        for (final item in list) {
          final email = (item['email'] ?? '').toString().trim().toLowerCase();
          final uid = (item['uid'] ?? '').toString().trim();
          if (email.isNotEmpty) registeredEmails.add(email);
          if (uid.isNotEmpty) registeredUids.add(uid);
        }
      }
    } catch (e) {
      debugPrint('[DeviceService] Supabase limit check error: $e');
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('device_id', isEqualTo: cleanDevice)
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        final email = (data['email'] ?? '').toString().trim().toLowerCase();
        final uid = (data['uid'] ?? doc.id).toString().trim();
        if (email.isNotEmpty) registeredEmails.add(email);
        if (uid.isNotEmpty) registeredUids.add(uid);
      }
    } catch (e) {
      debugPrint('[DeviceService] Firestore limit check error: $e');
    }

    final normalizedCurrentEmail = currentEmail.trim().toLowerCase();

    if (normalizedCurrentEmail.isNotEmpty && registeredEmails.contains(normalizedCurrentEmail)) {
      return true;
    }
    if (currentUid != null && currentUid.isNotEmpty && registeredUids.contains(currentUid)) {
      return true;
    }

    final totalAccounts = registeredEmails.isNotEmpty ? registeredEmails.length : registeredUids.length;
    if (totalAccounts >= 2) {
      debugPrint('[DeviceService] Device $cleanDevice has $totalAccounts registered accounts. Limit reached!');
      return false;
    }

    return true;
  }
}
