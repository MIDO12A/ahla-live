import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/r.dart';
import '../../../services/supabase_service.dart';
import '../../../providers/user_provider.dart';
import '../../message/message_reply_detail_screen.dart';
import '../../message/event_info_screen.dart';
import '../../notifications/notifications_screen.dart';

/// Authentic Room Message & Notification Bottom Sheet
/// Matches: chat_message_info_fragment.xml & layout_message_recyclerview_header.xml
class RoomMessageBottomSheet extends StatefulWidget {
  const RoomMessageBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const RoomMessageBottomSheet(),
    );
  }

  @override
  State<RoomMessageBottomSheet> createState() => _RoomMessageBottomSheetState();
}

class _RoomMessageBottomSheetState extends State<RoomMessageBottomSheet> {
  final SupabaseService _firebaseService = SupabaseService();
  List<Map<String, dynamic>> _conversations = [];
  StreamSubscription? _conversationsSub;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  void _loadConversations() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    _conversationsSub = _firebaseService.conversationsStream(user.uid).listen(
      (convos) {
        if (mounted) {
          setState(() {
            _conversations = convos;
            _isLoading = false;
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isLoading = false);
      },
    );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isLoading) setState(() => _isLoading = false);
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
    final double screenH = MediaQuery.of(context).size.height;

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        height: screenH * 0.72,
        decoration: const BoxDecoration(
          color: Color(0xFF191823),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 16,
              offset: Offset(0, -4),
            )
          ],
        ),
        child: Column(
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    isAr ? 'الرسائل' : 'Messages',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white12,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white70, size: 18),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // ── Top Action Cards: chat_message_info_fragment.xml ──
            // Card 1: System Notification (chat_message_system_bg)
            // Card 2: Event Information (chat_message_information_bg)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: _buildBannerCard(
                      bgAsset: R.chatMessageSystemBg,
                      title: isAr ? 'إشعارات\nالنظام' : 'System\nnotification',
                      badgeCount: 0,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildBannerCard(
                      bgAsset: R.chatMessageInformationBg,
                      title: isAr ? 'معلومات\nالحدث' : 'Event\ninformation',
                      badgeCount: 0,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const EventInfoScreen()),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            const Divider(color: Colors.white10, height: 1),

            // ── Conversations List: message_fl ──
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF4081)))
                  : _conversations.isEmpty
                      ? _buildEmptyState(isAr)
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _conversations.length,
                          separatorBuilder: (_, __) => const Divider(
                            color: Colors.white10,
                            height: 1,
                            indent: 68,
                            endIndent: 16,
                          ),
                          itemBuilder: (ctx, index) {
                            final conv = _conversations[index];
                            return _buildConversationItem(conv, isAr);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerCard({
    required String bgAsset,
    required String title,
    required int badgeCount,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              image: DecorationImage(
                image: AssetImage(bgAsset),
                fit: BoxFit.fill,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                height: 1.25,
              ),
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE82323),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isAr) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mark_chat_unread_outlined, size: 56, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          Text(
            isAr ? 'لا توجد رسائل حالياً' : 'No messages yet',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationItem(Map<String, dynamic> conv, bool isAr) {
    final otherName = (conv['otherName'] ?? conv['other_user_name'] ?? (isAr ? 'مستخدم' : 'User')).toString();
    final otherAvatar = (conv['otherPhotoUrl'] ?? conv['other_user_avatar'] ?? '').toString();
    final otherUid = (conv['otherUid'] ?? conv['other_user_id'] ?? '').toString();
    final conversationId = (conv['conversationId'] ?? conv['id'] ?? '').toString();
    final lastMessage = (conv['lastMessage'] ?? conv['last_message'] ?? '').toString();
    final unreadCount = (conv['unreadCount'] ?? conv['unread_count'] as num?)?.toInt() ?? 0;
    final updatedAt = (conv['updated_at'] ?? '').toString();
    final lastMessageTime = (conv['lastMessageTime'] as num?)?.toInt() ?? 0;

    String timeStr = '';
    if (lastMessageTime > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(lastMessageTime);
      timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (updatedAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(updatedAt);
        timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    return ListTile(
      onTap: () {
        if (otherUid.isNotEmpty) {
          final myUid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid ?? '';
          final convId = conversationId.isNotEmpty
              ? conversationId
              : ((myUid.compareTo(otherUid) < 0) ? '${myUid}_$otherUid' : '${otherUid}_$myUid');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MessageReplyDetailScreen(
                conversationId: convId,
                otherUid: otherUid,
                otherName: otherName,
                otherPhotoUrl: otherAvatar,
              ),
            ),
          );
        }
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white12,
            backgroundImage: otherAvatar.isNotEmpty
                ? (otherAvatar.startsWith('http')
                    ? NetworkImage(otherAvatar) as ImageProvider
                    : AssetImage(otherAvatar))
                : null,
            child: otherAvatar.isEmpty
                ? const Icon(Icons.person, color: Colors.white54)
                : null,
          ),
          if (unreadCount > 0)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFE82323),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      title: Text(
        otherName,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        lastMessage,
        style: TextStyle(
          color: unreadCount > 0 ? Colors.white70 : Colors.white38,
          fontSize: 13,
          fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (timeStr.isNotEmpty)
            Text(
              timeStr,
              style: const TextStyle(color: Colors.white30, fontSize: 11),
            ),
          const SizedBox(height: 4),
          if (unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE82323),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                unreadCount > 99 ? '99+' : unreadCount.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
