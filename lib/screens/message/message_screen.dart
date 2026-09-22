import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../services/supabase_service.dart';
import '../../providers/user_provider.dart';
import '../../services/dynamic_config_service.dart';
import '../../models/notification_model.dart';
import 'message_reply_detail_screen.dart';
import '../notifications/notifications_screen.dart';
import 'event_info_screen.dart';
import '../follow/follow_recent_screen.dart';

class MessageScreen extends StatefulWidget {
  const MessageScreen({super.key});

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  final SupabaseService _firebaseService = SupabaseService();
  List<Map<String, dynamic>> _conversations = [];
  StreamSubscription? _conversationsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadConversations());
  }

  void _loadConversations() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user == null) return;

    _conversationsSub = _firebaseService.conversationsStream(user.uid).listen((convos) {
      if (mounted) {
        setState(() => _conversations = convos);
      }
    });
  }

  @override
  void dispose() {
    _conversationsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final user = Provider.of<UserProvider>(context).currentUser;
    final bgImg = DynamicConfigService().messageBackgroundImage;
    final isCustomBg = bgImg.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isCustomBg
            ? DynamicConfigService().messageBackgroundColor
            : Colors.white,
        image: isCustomBg
            ? DecorationImage(
                image: R.cachedImage(bgImg),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Top background arch from frag_msg.xml (bg_pager_top.png)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Image.asset(
                'assets/drawable/bg_pager_top.png',
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  // Header Bar (Title: 24sp #333333 bold matching TabLayout selected text in frag_msg.xml)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isAr ? 'الرسائل' : 'Messages',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF333333),
                            letterSpacing: -0.5,
                          ),
                        ),
                        // Mark all as read action
                        IconButton(
                          icon: const Icon(
                            Icons.done_all_rounded,
                            color: Color(0xFF666666),
                            size: 22,
                          ),
                          tooltip: isAr ? 'تحديد الكل كمقروء' : 'Mark all read',
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isAr
                                      ? 'تم تحديد جميع المحادثات كمقروءة'
                                      : 'All conversations marked as read',
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  // Top 3 Stat Buttons: flTop (flVisitor, flFollower, flFollowing from frag_msg.xml)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        // 1. Visitors (flVisitor)
                        _buildTopStatButton(
                          imageAsset: 'assets/mipmap-xxhdpi/visitor.png',
                          label: isAr ? 'الزوار' : 'Visitors',
                          count: user?.visitors ?? 0,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const FollowRecentScreen(initialTab: 2),
                              ),
                            );
                          },
                        ),

                        // 2. Followers (flFollower)
                        _buildTopStatButton(
                          imageAsset: 'assets/mipmap-xxhdpi/follower.png',
                          label: isAr ? 'المتابعون' : 'Followers',
                          count: user?.followers ?? 0,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const FollowRecentScreen(initialTab: 1),
                              ),
                            );
                          },
                        ),

                        // 3. Following (flFollowing)
                        _buildTopStatButton(
                          imageAsset: 'assets/mipmap-xxhdpi/following.png',
                          label: isAr ? 'أتابع' : 'Following',
                          count: user?.following ?? 0,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const FollowRecentScreen(initialTab: 0),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Session List (Pinned System Messages + Pinned Event Info + User Conversations)
                  Expanded(
                    child: StreamBuilder<List<NotificationModel>>(
                      stream: _firebaseService.notificationsStream(uid: user?.uid),
                      builder: (context, notifSnapshot) {
                        final notifications = notifSnapshot.data ?? [];
                        final unreadNotifs = notifications.where((n) => !n.isRead).length;
                        final latestNotif = notifications.isNotEmpty ? notifications.first : null;

                        return ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            // Pinned Item 1: System Messages (item_session_systeom.xml)
                            _buildSystemSessionItem(
                              title: isAr ? 'رسائل النظام' : 'System Messages',
                              subtitle: latestNotif != null
                                  ? (latestNotif.body.isNotEmpty
                                      ? latestNotif.body
                                      : latestNotif.title)
                                  : (isAr
                                      ? 'مرحبًا بك في التطبيق! تفقد إشعاراتك وتحديثاتك هنا.'
                                      : 'Welcome! Check your latest updates and notifications.'),
                              iconAsset: 'assets/mipmap-xxhdpi/ic_system_msg.png',
                              timeStr: latestNotif != null
                                  ? _formatDateTime(latestNotif.createdAt)
                                  : _formatCurrentDay(),
                              unreadCount: unreadNotifs,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const NotificationsScreen(),
                                  ),
                                );
                              },
                            ),

                            // Pinned Item 2: Event Information (item_session_systeom.xml / rc_official_msg_item.xml)
                            _buildSystemSessionItem(
                              title: isAr ? 'معلومات الحدث' : 'Event Information',
                              subtitle: isAr
                                  ? 'مسابقة الصيف الكبرى لعام 2026 - جوائز وهدايا ذهبية حصرية'
                                  : 'Grand Summer Championship 2026 - Exclusive Gold Rewards',
                              iconAsset: 'assets/mipmap-xxhdpi/ic_official_msg.png',
                              timeStr: _formatCurrentDay(),
                              unreadCount: 0,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const EventInfoScreen(),
                                  ),
                                );
                              },
                            ),

                            // User Conversations (item_session.xml)
                            if (_conversations.isEmpty)
                              _buildEmptyPlaceholder(isAr)
                            else
                              ..._conversations.map((conv) {
                                return _buildConversationSessionItem(
                                  conversationId: conv['conversationId'] as String? ?? '',
                                  otherUid: conv['otherUid'] as String? ?? '',
                                  otherName: conv['otherName'] as String? ?? '',
                                  otherPhotoUrl: conv['otherPhotoUrl'] as String? ?? '',
                                  lastMessage: conv['lastMessage'] as String? ?? '',
                                  lastMessageTime: conv['lastMessageTime'] as int? ?? 0,
                                  unread: conv['unreadCount'] as int? ?? 0,
                                  isOnline: conv['isOnline'] as bool? ?? false,
                                );
                              }),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Top Stat Button (flVisitor, flFollower, flFollowing from frag_msg.xml)
  Widget _buildTopStatButton({
    required String imageAsset,
    required String label,
    required int count,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // FrameLayout containing Image 86x50 + top-end unread badge
          SizedBox(
            width: 86,
            height: 52,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Image.asset(
                  imageAsset,
                  width: 86,
                  height: 50,
                  fit: BoxFit.contain,
                ),
                if (count > 0)
                  Positioned(
                    top: 0,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF6060), Color(0xFFFF6DC9)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF333333),
            ),
          ),
        ],
      ),
    );
  }

  /// Pinned System Session Item matching item_session_systeom.xml
  Widget _buildSystemSessionItem({
    required String title,
    required String subtitle,
    required String iconAsset,
    required String timeStr,
    required int unreadCount,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 86,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFF3F4F6), width: 1),
          ),
        ),
        child: Row(
          children: [
            // 60x60 Circular Portrait (rc_conversation_portrait)
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: Image.asset(
                  iconAsset,
                  width: 58,
                  height: 58,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.notifications_active,
                    size: 40,
                    color: Color(0xFFFF8A00),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Middle Column: Title & Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF333333),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF8B8B8B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF555555),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (unreadCount > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF6060), Color(0xFFFF6DC9)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// User Conversation Item matching item_session.xml
  Widget _buildConversationSessionItem({
    required String conversationId,
    required String otherUid,
    required String otherName,
    required String otherPhotoUrl,
    required String lastMessage,
    required int lastMessageTime,
    required int unread,
    required bool isOnline,
  }) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MessageReplyDetailScreen(
              conversationId: conversationId,
              otherUid: otherUid,
              otherName: otherName,
              otherPhotoUrl: otherPhotoUrl,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFF3F4F6), width: 0.8),
          ),
        ),
        child: Row(
          children: [
            // 48x48 Avatar + online lineState
            Stack(
              clipBehavior: Clip.none,
              children: [
                ClipOval(
                  child: otherPhotoUrl.isNotEmpty
                      ? Image(
                          image: R.cachedImage(otherPhotoUrl),
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Image.asset(
                            R.avaBoy,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Image.asset(
                          R.avaBoy,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ),
                ),
                // lineState: 10x10 green dot
                if (isOnline)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3AFF92),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),

            // Middle Column: Title & Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          otherName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF222222),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatTime(lastMessageTime),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8B8B8B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lastMessage,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF777777),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (unread > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF4D4F),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Center(
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPlaceholder(bool isAr) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Image.asset(
              'assets/mipmap-xxhdpi/ic_official_msg.png',
              width: 56,
              height: 56,
              color: Colors.grey.shade300,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 48,
                color: Color(0xFFCCCCCC),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isAr ? 'لا توجد محادثات شخصية حالياً' : 'No personal chats yet',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF999999),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int timestamp) {
    if (timestamp <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day}';
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day}';
  }

  String _formatCurrentDay() {
    final now = DateTime.now();
    return '${now.month}/${now.day}';
  }
}

