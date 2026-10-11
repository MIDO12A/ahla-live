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

  Future<void> saveDeviceRegistration(
    String uid, {
    String? email,
    DeviceInfoData? info,
  }) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return;

    try {
      final dev = info ?? await getDeviceInfo();
      final cleanEmail = (email ?? '').trim().toLowerCase();
      final nowIso = DateTime.now().toUtc().toIso8601String();

      // 1. Save user device info to Supabase app_config: key 'user_device_$cleanUid'
      final userDevicePayload = {
        'uid': cleanUid,
        'email': cleanEmail,
        'device_id': dev.deviceId,
        'device_model': dev.deviceModel,
        'mac_address': dev.macAddress,
        'network_id': dev.networkId,
        'ip_address': dev.ipAddress,
        'updated_at': nowIso,
      };

      final userDevUrl = Uri.parse('${SupabaseConfig.projectUrl}/rest/v1/app_config');
      await http.post(
        userDevUrl,
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates',
        },
        body: jsonEncode({
          'key': 'user_device_$cleanUid',
          'value': userDevicePayload,
        }),
      );

      // 2. Maintain device accounts list in Supabase app_config: key 'dev_accounts_${dev.deviceId}'
      final devAccUrl = Uri.parse('${SupabaseConfig.projectUrl}/rest/v1/app_config?key=eq.dev_accounts_${dev.deviceId}&select=*');
      final devAccRes = await http.get(devAccUrl, headers: {
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
      });

      List<dynamic> uidsList = [];
      List<dynamic> emailsList = [];
      if (devAccRes.statusCode == 200) {
        final List list = jsonDecode(devAccRes.body);
        if (list.isNotEmpty) {
          final val = list.first['value'];
          if (val is Map) {
            uidsList = List.from(val['uids'] ?? []);
            emailsList = List.from(val['emails'] ?? []);
          }
        }
      }

      if (!uidsList.contains(cleanUid)) uidsList.add(cleanUid);
      if (cleanEmail.isNotEmpty && !emailsList.contains(cleanEmail)) emailsList.add(cleanEmail);

      await http.post(
        userDevUrl,
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates',
        },
        body: jsonEncode({
          'key': 'dev_accounts_${dev.deviceId}',
          'value': {
            'device_id': dev.deviceId,
            'device_model': dev.deviceModel,
            'mac_address': dev.macAddress,
            'network_id': dev.networkId,
            'uids': uidsList,
            'emails': emailsList,
            'count': uidsList.length,
            'updated_at': nowIso,
          },
        }),
      );

      // 3. Sync to Firestore (both users and device_registrations)
      try {
        await FirebaseFirestore.instance.collection('users').doc(cleanUid).set({
          'device_id': dev.deviceId,
          'device_model': dev.deviceModel,
          'mac_address': dev.macAddress,
          'network_id': dev.networkId,
          'ip_address': dev.ipAddress,
          'device_updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await FirebaseFirestore.instance.collection('device_registrations').doc(dev.deviceId).set({
          'device_id': dev.deviceId,
          'device_model': dev.deviceModel,
          'mac_address': dev.macAddress,
          'network_id': dev.networkId,
          'uids': FieldValue.arrayUnion([cleanUid]),
          'emails': cleanEmail.isNotEmpty ? FieldValue.arrayUnion([cleanEmail]) : FieldValue.arrayUnion([]),
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (fsErr) {
        debugPrint('[DeviceService] Firestore device sync error: $fsErr');
      }

      debugPrint('[DeviceService] Successfully registered device ${dev.deviceId} for user $cleanUid');
    } catch (e) {
      debugPrint('[DeviceService] saveDeviceRegistration error: $e');
    }
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

    // 1. Check Supabase app_config for 'dev_accounts_$cleanDevice'
    try {
      final devAccUrl = Uri.parse('${SupabaseConfig.projectUrl}/rest/v1/app_config?key=eq.dev_accounts_$cleanDevice&select=*');
      final res = await http.get(devAccUrl, headers: {
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
      });

      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        if (list.isNotEmpty) {
          final val = list.first['value'];
          if (val is Map) {
            final uids = val['uids'];
            final emails = val['emails'];
            if (uids is List) {
              for (final u in uids) {
                final s = u.toString().trim();
                if (s.isNotEmpty) registeredUids.add(s);
              }
            }
            if (emails is List) {
              for (final em in emails) {
                final s = em.toString().trim().toLowerCase();
                if (s.isNotEmpty) registeredEmails.add(s);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[DeviceService] Supabase app_config check error: $e');
    }

    // 2. Check Firestore device_registrations
    try {
      final devDoc = await FirebaseFirestore.instance
          .collection('device_registrations')
          .doc(cleanDevice)
          .get();

      if (devDoc.exists) {
        final data = devDoc.data() ?? {};
        final uids = data['uids'];
        final emails = data['emails'];
        if (uids is List) {
          for (final u in uids) {
            final s = u.toString().trim();
            if (s.isNotEmpty) registeredUids.add(s);
          }
        }
        if (emails is List) {
          for (final em in emails) {
            final s = em.toString().trim().toLowerCase();
            if (s.isNotEmpty) registeredEmails.add(s);
          }
        }
      }
    } catch (e) {
      debugPrint('[DeviceService] Firestore device_registrations check error: $e');
    }

    // 3. Fallback Firestore users query
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

    // If current email is already one of the registered accounts, ALLOW!
    if (normalizedCurrentEmail.isNotEmpty && registeredEmails.contains(normalizedCurrentEmail)) {
      return true;
    }
    // If current UID is already registered, ALLOW!
    if (currentUid != null && currentUid.isNotEmpty && registeredUids.contains(currentUid)) {
      return true;
    }

    final totalAccounts = registeredUids.isNotEmpty ? registeredUids.length : registeredEmails.length;
    if (totalAccounts >= 2) {
      debugPrint('[DeviceService] Device $cleanDevice has $totalAccounts registered accounts ($registeredUids / $registeredEmails). Limit reached!');
      return false;
    }

    return true;
  }
}
