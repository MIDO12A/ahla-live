import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/mall/mall_screen.dart';
import '../screens/level/level_screen.dart';
import '../screens/backpack/backpack_screen.dart';
import '../screens/rank/rank_screen.dart';
import '../features/cp/cp_detail_full_screen.dart';
import '../features/cp/cp_space_screen.dart';
import '../screens/vip/vip_center_screen.dart';
import '../features/tasks/screens/daily_tasks_screen.dart';
import '../features/signin/weekly_signin_screen.dart';
import '../features/host_agency/host_agency_screen.dart';
import '../features/events/screens/recharge_event_screen.dart';
import '../screens/wallet/wallet_main_screen.dart';
import '../screens/room/room_screen.dart';
import '../services/supabase_service.dart';

class AppActionNavigator {
  /// Navigate based on actionType and actionValue or raw link
  static Future<void> handleAction(
    BuildContext context, {
    String? actionType,
    String? actionValue,
    String? rawLink,
  }) async {
    final value = (actionValue != null && actionValue.isNotEmpty)
        ? actionValue.trim()
        : (rawLink != null ? rawLink.trim() : '');

    if (value.isEmpty) return;

    // Check for direct scheme or keywords
    final lower = value.toLowerCase();

    // 1. In-App Screens
    // حدث الشحن الملكي الأسطوري
    if (lower == '/recharge_event' ||
        lower == 'recharge_event' ||
        lower == '/recharge' ||
        lower == 'recharge' ||
        lower.contains('حدث الشحن') ||
        lower.contains('شحن ملكي')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const RechargeEventScreen()));
      return;
    }

    if (lower == '/wallet' || lower == 'wallet' || lower.contains('محفظة')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletMainScreen()));
      return;
    }

    if (lower == '/mall' || lower == 'mall' || lower.contains('متجر') || lower.contains('store')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MallScreen()));
      return;
    }

    if (lower == '/cp_ranking' ||
        lower == 'cp_ranking' ||
        lower.contains('ترتيب cp') ||
        lower.contains('ترتيب العلاقات') ||
        lower.contains('مساحة الترتيب') ||
        lower.contains('مكافآت cp') ||
        lower.contains('مكافات cp')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const CPDetailFullScreen()));
      return;
    }

    if (lower == '/cp_space' ||
        lower == 'cp_space' ||
        lower == '/cp' ||
        lower == 'cp' ||
        lower.contains('مساحة cp') ||
        lower.contains('مساحة العلاقات') ||
        lower.contains('ارتباط') ||
        lower.contains('علاقات')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const CpSpaceScreen()));
      return;
    }

    if (lower == '/vip' || lower == 'vip') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const VipCenterScreen()));
      return;
    }

    if (lower == '/tasks' || lower == 'tasks' || lower.contains('مهام')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const DailyTasksScreen()));
      return;
    }

    if (lower == '/levels' || lower == 'levels' || lower.contains('مستويات')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const LevelScreen()));
      return;
    }

    if (lower == '/signin' || lower == 'signin' || lower.contains('تسجيل')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const WeeklySigninScreen()));
      return;
    }

    if (lower == '/agency' || lower == 'agency' || lower.contains('وكالة')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const HostAgencyScreen()));
      return;
    }

    if (lower == '/rank' || lower == 'rank' || lower.contains('ترتيب') || lower.contains('رتب')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const RankScreen()));
      return;
    }

    if (lower == '/backpack' || lower == 'backpack' || lower.contains('حقيبة')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const BackpackScreen()));
      return;
    }

    // 2. Room by ID (e.g. "room:12345" or actionType == "room" or "12345" if numeric)
    if (actionType == 'room' || lower.startsWith('room:') || lower.startsWith('room/')) {
      final roomId = value.replaceAll(RegExp(r'^room[:/]', caseSensitive: false), '').trim();
      if (roomId.isNotEmpty) {
        _joinRoom(context, roomId);
        return;
      }
    }

    // 3. External HTTP / HTTPS link
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      final uri = Uri.tryParse(value);
      if (uri != null) {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e) {
          debugPrint('Failed to launch URL: $e');
        }
      }
      return;
    }

    // Fallback: If numeric, treat as room ID
    if (RegExp(r'^\d+$').hasMatch(value)) {
      _joinRoom(context, value);
      return;
    }
  }

  static Future<void> _joinRoom(BuildContext context, String roomId) async {
    try {
      final room = await SupabaseService().getRoom(roomId);
      if (room != null && context.mounted) {
        await navigateToRoom(
          context,
          roomId: room.roomId,
          roomName: room.name,
          hostName: room.hostName.isNotEmpty ? room.hostName : 'Host',
          roomPassword: room.password,
          gameDesc: room.description,
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('الغرفة غير موجودة أو تم إغلاقها: $roomId')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الدخول إلى الغرفة: $e')),
        );
      }
    }
  }
}
