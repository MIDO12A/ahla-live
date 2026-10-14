import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/ui/in_app_toast.dart';
import '../../../services/supabase_auth_service.dart';
import '../../../services/supabase_data_service.dart';

// ═══════════════════════════════════════════════════════════════════
//  AgencyNotificationHandler — يستمع لإشعارات الوكالة في الوقت الفعلي
//  يُستخدم كـ InheritedWidget أو يُلف حول الـ MaterialApp
//  الإشعارات المدعومة:
//    - agency_recharge_approved → "مبروك! تم تفعيل وكالة الشحن 🎉"
//    - recharge_agency_approved → "مبروك! تم تفعيل وكالة الشحن 🎉"
//    - agency_target_80pct     → "اقتربت من هدفك!"
//    - agency_target_achieved  → "أكملت الهدف! 🎉"
//    - agency_month_host       → "مضيف الشهر 🏆"
//    - agency_war_won          → "فزنا في الحرب! ⚔️"
//    - agency_month_host_announce → "إعلان مضيف الشهر"
// ═══════════════════════════════════════════════════════════════════
class AgencyNotificationHandler extends StatefulWidget {
  final Widget child;
  const AgencyNotificationHandler({super.key, required this.child});

  @override
  State<AgencyNotificationHandler> createState() => _AgencyNotificationHandlerState();
}

class _AgencyNotificationHandlerState extends State<AgencyNotificationHandler> {
  Timer? _pollTimer;
  final Set<String> _seenNotificationIds = {};
  final DateTime _startedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _subscribe() {
    final uid = SupabaseAuthService().currentUid;
    if (uid == null) return;

    _pollTimer?.cancel();
    _checkNotifications(uid, isFirstRun: true);
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkNotifications(uid);
    });
  }

  Future<void> _checkNotifications(String uid, {bool isFirstRun = false}) async {
    try {
      final list = await SupabaseDataService().getNotifications(uid: uid);
      for (final n in list) {
        if (_seenNotificationIds.contains(n.id)) continue;
        _seenNotificationIds.add(n.id);

        if (isFirstRun) {
          // On first run, ignore notifications created before app launch
          continue;
        }

        if (n.sentAt.isBefore(_startedAt.subtract(const Duration(seconds: 30)))) {
          continue;
        }

        final type = n.type;
        final title = n.title;
        final body = n.body;

        if (title.isEmpty && body.isEmpty) continue;

        switch (type) {
          case 'agency_recharge_approved':
          case 'recharge_agency_approved':
            KayanInAppToast.agency('🎉 $title\n$body');
            break;
          case 'agency_target_80pct':
          case 'agency_host_target_80pct':
            KayanInAppToast.agency('🎯 $title\n$body');
            break;
          case 'agency_target_achieved':
            KayanInAppToast.agency('🎉 $title\n$body');
            break;
          case 'agency_month_host':
            KayanInAppToast.agency('🏆 $title\n$body');
            break;
          case 'agency_war_won':
            KayanInAppToast.agency('⚔️ $title\n$body');
            break;
          case 'agency_month_host_announce':
            KayanInAppToast.agency('🎖️ $title\n$body');
            break;
          default:
            if (type.startsWith('agency_') || type == 'system') {
              KayanInAppToast.agency('🔔 $title\n$body');
            }
        }
      }
    } catch (e) {
      debugPrint('[AgencyNotificationHandler] check error: $e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

