import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/user_provider.dart';
import '../screens/main_screen/main_screen.dart';
import 'supabase_auth_service.dart';

class AccountSwitchService {
  static const String _storageKey = 'saved_user_accounts';

  /// Get list of saved accounts
  static Future<List<Map<String, dynamic>>> getSavedAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_storageKey);
      if (str != null && str.isNotEmpty) {
        final list = jsonDecode(str);
        if (list is List) {
          return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (e) {
      debugPrint('[AccountSwitchService] getSavedAccounts error: ');
    }
    return [];
  }

  /// Save or update an account in the saved list
  static Future<void> saveAccount({
    required String uid,
    String? name,
    String? photoUrl,
    String? customId,
    String? email,
    String? phone,
    String? loginType,
  }) async {
    if (uid.isEmpty) return;
    try {
      final accounts = await getSavedAccounts();
      final existingIndex = accounts.indexWhere((a) => a['uid'] == uid);

      final accountData = <String, dynamic>{
        'uid': uid,
        'name': name ?? '',
        'photoUrl': photoUrl ?? '',
        'customId': customId ?? '',
        'email': email ?? '',
        'phone': phone ?? '',
        'loginType': loginType ?? 'default',
        'lastUsed': DateTime.now().millisecondsSinceEpoch,
      };

      if (existingIndex >= 0) {
        final old = accounts[existingIndex];
        if ((accountData['name'] as String).isEmpty) accountData['name'] = old['name'] ?? '';
        if ((accountData['photoUrl'] as String).isEmpty) accountData['photoUrl'] = old['photoUrl'] ?? '';
        if ((accountData['customId'] as String).isEmpty) accountData['customId'] = old['customId'] ?? '';
        if ((accountData['email'] as String).isEmpty) accountData['email'] = old['email'] ?? '';
        if ((accountData['phone'] as String).isEmpty) accountData['phone'] = old['phone'] ?? '';
        accounts[existingIndex] = accountData;
      } else {
        accounts.add(accountData);
      }

      accounts.sort((a, b) => ((b['lastUsed'] as num?) ?? 0).compareTo((a['lastUsed'] as num?) ?? 0));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(accounts));
    } catch (e) {
      debugPrint('[AccountSwitchService] saveAccount error: ');
    }
  }

  /// Remove account from saved list
  static Future<void> removeAccount(String uid) async {
    try {
      final accounts = await getSavedAccounts();
      accounts.removeWhere((a) => a['uid'] == uid);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(accounts));
    } catch (e) {
      debugPrint('[AccountSwitchService] removeAccount error: ');
    }
  }

  /// Switch directly to a saved account
  static Future<void> switchToAccount(BuildContext context, Map<String, dynamic> targetAccount) async {
    final uid = targetAccount['uid'] as String?;
    if (uid == null || uid.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFD700)),
      ),
    );

    try {
      // 1. Update session in SupabaseAuthService
      await SupabaseAuthService().saveSession(
        uid: uid,
        email: targetAccount['email'] as String?,
        name: targetAccount['name'] as String?,
        photoUrl: targetAccount['photoUrl'] as String?,
        phone: targetAccount['phone'] as String?,
      );

      // 2. Touch lastUsed
      await saveAccount(
        uid: uid,
        name: targetAccount['name'] as String?,
        photoUrl: targetAccount['photoUrl'] as String?,
        customId: targetAccount['customId'] as String?,
        email: targetAccount['email'] as String?,
        phone: targetAccount['phone'] as String?,
      );

      // 3. Clear existing UserProvider and load new user
      if (context.mounted) {
        final up = Provider.of<UserProvider>(context, listen: false);
        up.clearUser();
        await up.loadUser(uid);
      }

      // 4. Pop loader and navigate to MainScreen
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('[AccountSwitchService] switchToAccount error: ');
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر التبديل إلى الحساب: '),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}
