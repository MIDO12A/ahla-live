import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../services/supabase_service.dart';
import '../../models/notification_model.dart';
import '../../providers/user_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../features/cp/cp_service.dart';
import '../../features/cp/cp_detail_full_screen.dart';
import '../../features/financial/agent_recharge_portal_screen.dart';

/// Replicates [chat_activity_system_notification.xml] and [chat_adapter_activity_item.xml]
/// from the original decompiled app (F:\Medal\New folder\nu).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final SupabaseService _firebaseService = SupabaseService();
  late Stream<List<NotificationModel>> _notificationsStream;

  @override
  void initState() {
    super.initState();
    final uid =
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    _notificationsStream = _firebaseService.notificationsStream(uid: uid);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF16151A),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          isAr ? 'إشعارات النظام' : 'System Notifications',
          style: const TextStyle(
            color: Color(0xFF16151A),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.done_all_rounded,
              color: Color(0xFF9BA1B6),
              size: 22,
            ),
            tooltip: isAr ? 'تحديد الكل كمقروء' : 'Mark all read',
            onPressed: () async {
              final uid = Provider.of<UserProvider>(context, listen: false)
                  .currentUser
                  ?.uid;
              if (uid != null) {
                final snap = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
                    .collection('notifications')
                    .where('uid', isEqualTo: uid)
                    .where('is_read', isEqualTo: false)
                    .get();
                for (final doc in snap.docs) {
                  await doc.reference.update({'is_read': true});
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isAr
                          ? 'تم تحديد جميع الرسائل كمقروءة'
                          : 'All notifications marked as read'),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<List<NotificationModel>>(
        stream: _notificationsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)),
            );
          }
          final notifications = snapshot.data ?? [];
          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/mipmap-xxhdpi/chat_system_ic.webp',
                    width: 60,
                    height: 60,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.notifications_off_outlined,
                      size: 56,
                      color: Color(0xFF9BA1B6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isAr
                        ? 'لا توجد إشعارات نظام حالياً'
                        : 'No system notifications yet',
                    style: const TextStyle(
                      color: Color(0xFF9BA1B6),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notif = notifications[index];
              return _buildNotificationItem(notif, isAr);
            },
          );
        },
      ),
    );
  }

  /// List item matching [chat_adapter_activity_item.xml]
  Widget _buildNotificationItem(NotificationModel notif, bool isAr) {
    final formattedTime = _formatTime(notif.sentAt);
    final isGift = notif.type == 'gift';
    final action = notif.data?['action'] as String?;
    final giftImage = notif.data?['gift_image']?.toString() ?? '';
    final notifImg = notif.data?['img']?.toString() ??
        notif.data?['image_url']?.toString() ??
        '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // tv_notification_time: 11sp, color #9BA1B6, paddingTop 16dp
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 10),
            child: Text(
              formattedTime,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF9BA1B6),
              ),
            ),
          ),

          // Horizontal layout: iv_system_icon + chat_notification_shape_bg bubble
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // iv_system_icon: 45x45dp, marginTop 16dp, @mipmap/chat_system_ic
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Image.asset(
                  'assets/mipmap-xxhdpi/chat_system_ic.webp',
                  width: 45,
                  height: 45,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 45,
                    height: 45,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E90FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.notifications,
                        color: Colors.white, size: 24),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Bubble: chat_notification_shape_bg (White #FFFFFF, radius 16dp, padding 12dp)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // tv_title: 15sp, sans-serif-medium, color #16151A
                      if (notif.title.isNotEmpty) ...[
                        Text(
                          notif.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF16151A),
                          ),
                        ),
                        // view_line: 0.5dp, #FFEDEDED, marginVertical 6dp
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Divider(
                            height: 0.5,
                            thickness: 0.5,
                            color: Color(0xFFEDEDED),
                          ),
                        ),
                      ],

                      // tv_notification_content: 13sp, color #16151A
                      if (notif.body.isNotEmpty)
                        Text(
                          notif.body,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF16151A),
                            height: 1.4,
                          ),
                        ),

                      // iv_notification_img: ratio 262:74, round corner radius 8dp, marginTop 6dp
                      if (notifImg.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AspectRatio(
                              aspectRatio: 262 / 74,
                              child: Image(
                                image: R.cachedImage(notifImg),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),

                      // Gift Preview if gift
                      if (isGift && giftImage.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF7F8FA),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: _giftThumb(giftImage),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${notif.data?['gift_name'] ?? ''} x${notif.data?['count'] ?? 1}',
                                  style: const TextStyle(
                                    color: Color(0xFFFF9500),
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Recharge Agency Action Button
                      if (action == 'recharge_agency_approved' ||
                          notif.type == 'agency_recharge_approved' ||
                          notif.title.contains('تفعيل وكالة الشحن') ||
                          notif.title.contains('وكالة الشحن'))
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const AgentRechargePortalScreen()),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF2B2005), Color(0xFF1E1703)],
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: const Color(0xFFFFD700)
                                        .withValues(alpha: 0.6)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('💼', style: TextStyle(fontSize: 16)),
                                  SizedBox(width: 8),
                                  Text(
                                    'دخول لوحة تحكم وكالة الشحن',
                                    style: TextStyle(
                                      color: Color(0xFFFFD700),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.arrow_forward_ios_rounded,
                                      size: 12, color: Color(0xFFFFD700)),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Agency Invitation Actions (Accept/Reject)
                      if (action == 'agency_invite')
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            children: [
                              _actionButton(
                                label: isAr ? 'قبول ✅' : 'Accept ✅',
                                color: const Color(0xFF10B981),
                                onTap: () async {
                                  final currentUid = Provider.of<UserProvider>(
                                          context,
                                          listen: false)
                                      .currentUser
                                      ?.uid;
                                  final agencyName = notif.data?['agency_name']
                                          ?.toString() ??
                                      'وكالة جديدة';
                                  final adminName = notif.data?['admin_name']
                                          ?.toString() ??
                                      'إدارة التطبيق';
                                  final agencyType = notif.data?['agency_type']
                                          ?.toString() ??
                                      'host';

                                  if (currentUid != null) {
                                    if (agencyType == 'recharge') {
                                      await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
                                          .collection('users')
                                          .doc(currentUid)
                                          .set({
                                        'is_recharge_agent': true,
                                        'isRechargeAgent': true,
                                        'recharge_agency_name': agencyName,
                                      }, SetOptions(merge: true));
                                    } else {
                                      final agDoc = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
                                          .collection('host_agencies')
                                          .doc();
                                      await agDoc.set({
                                        'name': agencyName,
                                        'owner_id': currentUid,
                                        'is_active': true,
                                        'member_count': 1,
                                        'created_at': DateTime.now()
                                            .toUtc()
                                            .toIso8601String(),
                                      });
                                      await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
                                          .collection('host_agency_members')
                                          .doc('${agDoc.id}_$currentUid')
                                          .set({
                                        'agency_id': agDoc.id,
                                        'user_id': currentUid,
                                        'role': 'owner',
                                        'status': 'active',
                                        'joined_at': DateTime.now()
                                            .toUtc()
                                            .toIso8601String(),
                                      });
                                      await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
                                          .collection('users')
                                          .doc(currentUid)
                                          .set({
                                        'agency_id': agDoc.id,
                                      }, SetOptions(merge: true));
                                    }

                                    await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
                                        .collection('notifications')
                                        .add({
                                      'user_id': currentUid,
                                      'uid': currentUid,
                                      'title': 'مبروك! تم فتح وكالتك بنجاح 🎉',
                                      'body':
                                          'مبروك! تم فتح وتفعيل وكالتك [$agencyName] بنجاح بواسطة المشرف [$adminName]. يمكنك الآن البدء بإدارتها.',
                                      'type': 'system',
                                      'sent_at':
                                          DateTime.now().toUtc().toIso8601String(),
                                      'data': {
                                        'action': 'agency_created',
                                        'admin_name': adminName
                                      },
                                    });

                                    if (notif.id.isNotEmpty) {
                                      await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
                                          .collection('notifications')
                                          .doc(notif.id)
                                          .delete();
                                    }

                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'مبروك! تم قبول وتفعيل وكالة $agencyName بنجاح! 🎉'),
                                          backgroundColor:
                                              const Color(0xFF10B981),
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              _actionButton(
                                label: isAr ? 'رفض ❌' : 'Reject ❌',
                                color: const Color(0xFFEF4444),
                                onTap: () async {
                                  if (notif.id.isNotEmpty) {
                                    await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
                                        .collection('notifications')
                                        .doc(notif.id)
                                        .delete();
                                  }
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(isAr
                                            ? 'تم رفض دعوة الوكالة'
                                            : 'Agency invitation rejected'),
                                        backgroundColor:
                                            const Color(0xFFEF4444),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),

                      // CP Relationship Request Action
                      if (action == 'cp_request' || notif.type == 'cp_invite')
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            children: [
                              _actionButton(
                                label: isAr ? 'قبول CP 💕' : 'Accept CP 💕',
                                color: const Color(0xFFFF2D78),
                                onTap: () async {
                                  final reqId = notif.data?['request_id']?.toString();
                                  if (reqId != null && reqId.isNotEmpty) {
                                    await CpService.respondRequest(reqId, true);
                                  }
                                  if (notif.id.isNotEmpty) {
                                    await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
                                        .collection('notifications')
                                        .doc(notif.id)
                                        .delete();
                                  }
                                  if (mounted) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const CPDetailFullScreen(),
                                      ),
                                    );
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              _actionButton(
                                label: isAr ? 'رفض' : 'Reject',
                                color: const Color(0xFF9BA1B6),
                                onTap: () async {
                                  if (notif.id.isNotEmpty) {
                                    await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
                                        .collection('notifications')
                                        .doc(notif.id)
                                        .delete();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _giftThumb(String giftUrl) {
    if (giftUrl.startsWith('http')) {
      return Image(
        image: R.cachedImage(giftUrl),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.card_giftcard, size: 24, color: Color(0xFFFF9500)),
      );
    }
    return Image.asset(
      giftUrl,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          const Icon(Icons.card_giftcard, size: 24, color: Color(0xFFFF9500)),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

