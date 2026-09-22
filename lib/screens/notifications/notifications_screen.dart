import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/supabase_service.dart';
import '../../config/r.dart';
import '../../services/dynamic_config_service.dart';
import '../../models/notification_model.dart';
import '../../providers/user_provider.dart';
import '../../core/widgets/cached_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../features/cp/cp_service.dart';
import '../../features/cp/cp_detail_full_screen.dart';
import '../../features/financial/agent_recharge_portal_screen.dart';

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
    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    _notificationsStream = _firebaseService.notificationsStream(uid: uid);
  }

  @override
  Widget build(BuildContext context) {
    final bgImg = DynamicConfigService().notificationsBackgroundImage;
    return Container(
      decoration: BoxDecoration(
        color: DynamicConfigService().notificationsBackgroundColor,
        image: bgImg.isNotEmpty
            ? DecorationImage(
                image: R.cachedImage(bgImg),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: const Text(
          'Notifications',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<List<NotificationModel>>(
        stream: _notificationsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white24),
            );
          }
          final notifications = snapshot.data ?? [];
          if (notifications.isEmpty) {
            return const Center(
              child: Text(
                'No notifications yet',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notif = notifications[index];
              final timeAgo = _timeAgo(notif.sentAt);
              final isCpGift = notif.type == 'cp_gift';
              final isGift = notif.type == 'gift';
              final action = notif.data?['action'] as String?;
              final senderPhoto =
                  notif.data?['sender_photo']?.toString() ?? '';
              final giftImage = notif.data?['gift_image']?.toString() ?? '';

              return Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.05),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isCpGift
                            ? Colors.pink.withValues(alpha: 0.2)
                            : Colors.indigo.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: isGift && senderPhoto.isNotEmpty
                          ? CachedNetImage(
                              senderPhoto,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                            )
                          : Icon(
                              isCpGift
                                  ? Icons.favorite
                                  : isGift
                                      ? Icons.card_giftcard
                                      : Icons.notifications_outlined,
                              color: isCpGift
                                  ? Colors.pinkAccent
                                  : Colors.indigoAccent,
                              size: 20,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notif.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            notif.body,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          if (isGift && giftImage.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: _giftThumb(giftImage),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${notif.data?['gift_name'] ?? ''} x${notif.data?['count'] ?? 1}',
                                      style: const TextStyle(
                                        color: Colors.amberAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (action == 'agency_invite')
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  _actionButton(
                                    label: 'قبول فتح الوكالة ✅',
                                    color: Colors.green,
                                    onTap: () async {
                                      final currentUid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
                                      final agencyName = notif.data?['agency_name']?.toString() ?? 'وكالة جديدة';
                                      final adminName = notif.data?['admin_name']?.toString() ?? 'إدارة التطبيق';
                                      final agencyType = notif.data?['agency_type']?.toString() ?? 'host';

                                      if (currentUid != null) {
                                        if (agencyType == 'recharge') {
                                          await FirebaseFirestore.instance.collection('users').doc(currentUid).set({
                                            'is_recharge_agent': true,
                                            'recharge_agency_name': agencyName,
                                          }, SetOptions(merge: true));
                                        } else {
                                          final agDoc = FirebaseFirestore.instance.collection('host_agencies').doc();
                                          await agDoc.set({
                                            'name': agencyName,
                                            'owner_id': currentUid,
                                            'is_active': true,
                                            'member_count': 1,
                                            'created_at': DateTime.now().toUtc().toIso8601String(),
                                          });
                                          await FirebaseFirestore.instance.collection('host_agency_members').doc('${agDoc.id}_$currentUid').set({
                                            'agency_id': agDoc.id,
                                            'user_id': currentUid,
                                            'role': 'owner',
                                            'status': 'active',
                                            'joined_at': DateTime.now().toUtc().toIso8601String(),
                                          });
                                          await FirebaseFirestore.instance.collection('users').doc(currentUid).set({
                                            'agency_id': agDoc.id,
                                          }, SetOptions(merge: true));
                                        }

                                        // Send congratulation follow-up notification
                                        await FirebaseFirestore.instance.collection('notifications').add({
                                          'user_id': currentUid,
                                          'uid': currentUid,
                                          'title': 'مبروك! تم فتح وكالتك بنجاح 🎉',
                                          'body': 'مبروك! تم فتح وتفعيل وكالتك [$agencyName] بنجاح بواسطة المشرف [$adminName]. يمكنك الآن البدء بإدارتها.',
                                          'type': 'system',
                                          'sent_at': DateTime.now().toUtc().toIso8601String(),
                                          'data': {'action': 'agency_created', 'admin_name': adminName},
                                        });

                                        if (notif.id.isNotEmpty) {
                                          await FirebaseFirestore.instance.collection('notifications').doc(notif.id).delete();
                                        }

                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('مبروك! تم قبول وتفعيل وكالة $agencyName بنجاح! 🎉'),
                                              backgroundColor: Colors.green,
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  _actionButton(
                                    label: 'رفض ❌',
                                    color: Colors.red,
                                    onTap: () async {
                                      if (notif.id.isNotEmpty) {
                                        await FirebaseFirestore.instance.collection('notifications').doc(notif.id).delete();
                                      }
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('تم رفض دعوة الوكالة'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          if (action == 'recharge_agency_approved' ||
                              notif.type == 'agency_recharge_approved' ||
                              notif.title.contains('تفعيل وكالة الشحن') ||
                              notif.title.contains('وكالة الشحن'))
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  _actionButton(
                                    label: 'دخول لوحة تحكم وكالة الشحن 💼',
                                    color: const Color(0xFFFFD700),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const AgentRechargePortalScreen()),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          if (isCpGift && action == 'cp_relationship_request')
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  _actionButton(
                                    label: 'Accept',
                                    color: Colors.green,
                                    onTap: () async {
                                      final requestId = notif.data?['request_id']?.toString();
                                      if (requestId != null) {
                                        await CpService.respondRequest(requestId, true);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('تم قبول طلب CP!'),
                                              backgroundColor: Colors.green,
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  _actionButton(
                                    label: 'Decline',
                                    color: Colors.red,
                                    onTap: () async {
                                      final requestId = notif.data?['request_id']?.toString();
                                      if (requestId != null) {
                                        await CpService.respondRequest(requestId, false);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('تم رفض طلب CP'),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  _actionButton(
                                    label: 'View',
                                    color: Colors.amber,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const CPDetailFullScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeAgo,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _giftThumb(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return CachedNetImage(url, width: 48, height: 48, fit: BoxFit.cover);
    }
    if (url.endsWith('.svg') || url.endsWith('.svga')) {
      return Image.asset(url, width: 48, height: 48, fit: BoxFit.contain);
    }
    return Image.asset(url, width: 48, height: 48, fit: BoxFit.cover);
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}
