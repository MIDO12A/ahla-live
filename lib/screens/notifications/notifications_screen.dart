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
    final isCustomBg = bgImg.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isCustomBg ? DynamicConfigService().notificationsBackgroundColor : const Color(0xFFF7F8FA),
        image: isCustomBg
            ? DecorationImage(
                image: R.cachedImage(bgImg),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: isCustomBg ? Colors.transparent : Colors.white,
          elevation: isCustomBg ? 0 : 0.5,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: isCustomBg ? Colors.white : const Color(0xFF1E2022),
              size: 20,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          centerTitle: true,
          title: Text(
            'رسائل النظام',
            style: TextStyle(
              color: isCustomBg ? Colors.white : const Color(0xFF1E2022),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(
                Icons.done_all_rounded,
                color: isCustomBg ? Colors.white70 : const Color(0xFF8B8B8B),
                size: 22,
              ),
              tooltip: 'تحديد الكل كمقروء',
              onPressed: () async {
                final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
                if (uid != null) {
                  final snap = await FirebaseFirestore.instance
                      .collection('notifications')
                      .where('uid', isEqualTo: uid)
                      .where('is_read', isEqualTo: false)
                      .get();
                  for (final doc in snap.docs) {
                    await doc.reference.update({'is_read': true});
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم تحديد جميع الرسائل كمقروءة')),
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
                      'assets/mipmap-xxhdpi/ic_system_msg.png',
                      width: 80,
                      height: 80,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.notifications_off_outlined,
                        size: 64,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'لا توجد رسائل نظام حالياً',
                      style: TextStyle(
                        color: Color(0xFF8B8B8B),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final notif = notifications[index];
                final formattedTime = _formatTime(notif.sentAt);
                final isCpGift = notif.type == 'cp_gift';
                final isGift = notif.type == 'gift';
                final action = notif.data?['action'] as String?;
                final senderPhoto = notif.data?['sender_photo']?.toString() ?? '';
                final giftImage = notif.data?['gift_image']?.toString() ?? '';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    children: [
                      // Centered Timestamp matching rc_time in item_system.xml
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          formattedTime,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8B8B8B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      // Message Row matching item_system.xml
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // System Avatar imgHeader 50dp
                          ClipOval(
                            child: Image.asset(
                              'assets/mipmap-xxhdpi/ic_system_msg.png',
                              width: 46,
                              height: 46,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 46,
                                height: 46,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF6C5CE7),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.notifications, color: Colors.white, size: 24),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Bubble matching bubble_left in item_system.xml
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(16),
                                  topRight: Radius.circular(16),
                                  bottomLeft: Radius.circular(4),
                                  bottomRight: Radius.circular(16),
                                ),
                                border: Border.all(color: const Color(0xFFECEFF1), width: 0.8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Title
                                  if (notif.title.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Text(
                                        notif.title,
                                        style: const TextStyle(
                                          color: Color(0xFF1E2022),
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  // Body
                                  Text(
                                    notif.body,
                                    style: const TextStyle(
                                      color: Color(0xFF4A4A4A),
                                      fontSize: 13.5,
                                      height: 1.45,
                                    ),
                                  ),

                                  // Gift Preview
                                  if (isGift && giftImage.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF7F8FA),
                                              borderRadius: BorderRadius.circular(10),
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

                                  // Recharge Agency Approval Action Button
                                  if (action == 'recharge_agency_approved' ||
                                      notif.type == 'agency_recharge_approved' ||
                                      notif.title.contains('تفعيل وكالة الشحن') ||
                                      notif.title.contains('وكالة الشحن'))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(builder: (_) => const AgentRechargePortalScreen()),
                                          );
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [Color(0xFF2B2005), Color(0xFF1E1703)],
                                            ),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.6)),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text('💼', style: TextStyle(fontSize: 18)),
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
                                              Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFFFFD700)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),

                                  // Agency Invitation Actions
                                  if (action == 'agency_invite')
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Row(
                                        children: [
                                          _actionButton(
                                            label: 'قبول فتح الوكالة ✅',
                                            color: const Color(0xFF10B981),
                                            onTap: () async {
                                              final currentUid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
                                              final agencyName = notif.data?['agency_name']?.toString() ?? 'وكالة جديدة';
                                              final adminName = notif.data?['admin_name']?.toString() ?? 'إدارة التطبيق';
                                              final agencyType = notif.data?['agency_type']?.toString() ?? 'host';

                                              if (currentUid != null) {
                                                if (agencyType == 'recharge') {
                                                  await FirebaseFirestore.instance.collection('users').doc(currentUid).set({
                                                    'is_recharge_agent': true,
                                                    'isRechargeAgent': true,
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

                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text('مبروك! تم قبول وتفعيل وكالة $agencyName بنجاح! 🎉'),
                                                      backgroundColor: const Color(0xFF10B981),
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                          ),
                                          const SizedBox(width: 8),
                                          _actionButton(
                                            label: 'رفض ❌',
                                            color: const Color(0xFFEF4444),
                                            onTap: () async {
                                              if (notif.id.isNotEmpty) {
                                                await FirebaseFirestore.instance.collection('notifications').doc(notif.id).delete();
                                              }
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text('تم رفض دعوة الوكالة'),
                                                    backgroundColor: Color(0xFFEF4444),
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ),

                                  // CP Relationship Request Action
                                  if (isCpGift && action == 'cp_relationship_request')
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Row(
                                        children: [
                                          _actionButton(
                                            label: 'قبول 💕',
                                            color: const Color(0xFF10B981),
                                            onTap: () async {
                                              final requestId = notif.data?['request_id']?.toString();
                                              if (requestId != null) {
                                                await CpService.respondRequest(requestId, true);
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('تم قبول طلب CP بنجاح! 🎉')),
                                                  );
                                                }
                                              }
                                            },
                                          ),
                                          const SizedBox(width: 8),
                                          _actionButton(
                                            label: 'رفض',
                                            color: const Color(0xFFEF4444),
                                            onTap: () async {
                                              final requestId = notif.data?['request_id']?.toString();
                                              if (requestId != null) {
                                                await CpService.respondRequest(requestId, false);
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
              },
            );
          },
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    if (isToday) {
      return 'اليوم $hour:$minute';
    }
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}  $hour:$minute';
  }
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
