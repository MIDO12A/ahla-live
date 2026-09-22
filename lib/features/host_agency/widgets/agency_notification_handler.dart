import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/ui/in_app_toast.dart';

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
  StreamSubscription? _sub;
  final DateTime _startedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _subscribe() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _sub?.cancel();
    final col = FirebaseFirestore.instance.collection('notifications');
    _sub = col.where('uid', isEqualTo: uid).snapshots().listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() ?? {};
          final createdAtStr = data['created_at']?.toString() ?? data['sent_at']?.toString();
          final createdAt = createdAtStr != null ? DateTime.tryParse(createdAtStr) : null;
          // Only show toast for fresh notifications (received since started or within 30s)
          if (createdAt != null && createdAt.isBefore(_startedAt.subtract(const Duration(seconds: 30)))) {
            continue;
          }

          final type = data['type'] as String? ?? '';
          final title = data['title'] as String? ?? '';
          final body = data['body'] as String? ?? data['message'] as String? ?? '';

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
      }
    }, onError: (e) {
      debugPrint('[AgencyNotificationHandler] snapshot error: $e');
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

