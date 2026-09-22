import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../services/supabase_service.dart';
import '../../providers/user_provider.dart';
import '../../models/notification_model.dart';
import '../../models/banner_config.dart';
import 'message_reply_detail_screen.dart';
import '../notifications/notifications_screen.dart';
import 'event_info_screen.dart';
import '../user_profile/user_profile_screen.dart';

/// Replicates [fragment_message_copy.xml] and [chat_message_info_fragment.xml]
/// from the original decompiled app (F:\Medal\New folder\nu).
class MessageScreen extends StatefulWidget {
  const MessageScreen({super.key});

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  final FirebaseService _firebaseService = FirebaseService();

  late PageController _pageController;
  int _selectedTabIndex = 0;

  List<Map<String, dynamic>> _conversations = [];
  StreamSubscription? _conversationsSub;

  List<Map<String, dynamic>> _friends = [];
  bool _loadingFriends = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadConversations();
      _loadFriends();
    });
  }

  void _loadConversations() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user == null) return;

    _conversationsSub =
        _supabaseService.conversationsStream(user.uid).listen((convos) {
      if (mounted) {
        setState(() => _conversations = convos);
      }
    });
  }

  Future<void> _loadFriends() async {
    final user = Provider.of<UserProvider>(context, listen: false).currentUser;
    if (user == null) return;
    setState(() => _loadingFriends = true);
    try {
      final list = await _supabaseService.getFollowing(user.uid);
      if (mounted) {
        setState(() {
          _friends = list;
          _loadingFriends = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingFriends = false);
    }
  }

  @override
  void dispose() {
    _conversationsSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final user = Provider.of<UserProvider>(context).currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // 1. Top Header: part_switch (fragment_message_copy.xml)
          // Height: 110dp, background: @mipmap/discover_header_bg
          _buildHeader(isAr),

          // 2. ViewPager2 / PageView (id_vp)
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() => _selectedTabIndex = index);
              },
              children: [
                // Tab 0: Messages (MessageInfoFragment / chat_message_info_fragment.xml)
                _buildMessageInfoTab(user?.uid, isAr),

                // Tab 1: Friends (Friends List)
                _buildFriendsTab(isAr),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Header container matching part_switch in fragment_message_copy.xml
  /// Background: @mipmap/discover_header_bg, Height: 110dp
  /// Centered TabLayout: width 300dp, height 50dp, marginTop 40dp
  Widget _buildHeader(bool isAr) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final headerHeight = 110.0 + (statusBarHeight > 0 ? statusBarHeight - 24 : 0);

    return Container(
      width: double.infinity,
      height: headerHeight,
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/mipmap-xxhdpi/discover_header_bg.webp'),
          fit: BoxFit.fill,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 300,
            height: 50,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Tab 0: Message (الرسائل)
                _buildNavTabItem(
                  index: 0,
                  title: isAr ? 'الرسائل' : 'Message',
                  isSelected: _selectedTabIndex == 0,
                ),

                const SizedBox(width: 40),

                // Tab 1: Friends (الأصدقاء)
                _buildNavTabItem(
                  index: 1,
                  title: isAr ? 'الأصدقاء' : 'Friends',
                  isSelected: _selectedTabIndex == 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Custom Tab Item matching tablayout_nav_view.xml
  /// TextView: tv_title, ImageView: iv_smallPic (@mipmap/tab_pre: 20x10dp)
  Widget _buildNavTabItem({
    required int index,
    required String title,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() => _selectedTabIndex = index);
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                color: const Color(0xFF16151A),
                fontSize: isSelected ? 18 : 15,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              width: 20,
              height: 10,
              child: isSelected
                  ? Image.asset(
                      'assets/mipmap-xxhdpi/tab_pre.webp',
                      width: 20,
                      height: 10,
                      fit: BoxFit.contain,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  /// Tab 0: MessageInfoFragment matching chat_message_info_fragment.xml
  Widget _buildMessageInfoTab(String? myUid, bool isAr) {
    return StreamBuilder<List<NotificationModel>>(
      stream: _supabaseService.notificationsStream(uid: myUid),
      builder: (context, notifSnap) {
        final notifications = notifSnap.data ?? [];
        final unreadSystemCount =
            notifications.where((n) => !n.isRead && n.type != 'event').length;

        return StreamBuilder<List<BannerConfig>>(
          stream: _firebaseService.bannersStream(),
          builder: (context, bannerSnap) {
            final banners = bannerSnap.data ?? [];
            final unreadEventCount = banners.length;

            return ListView(
              padding: EdgeInsets.zero,
              children: [
                // cl_msg_info: 2 banner cards side-by-side
                _buildMessageBanners(
                  unreadSystemCount: unreadSystemCount,
                  unreadEventCount: unreadEventCount,
                  isAr: isAr,
                ),

                const SizedBox(height: 8),

                // Conversation List matching conversation_list_item_layout.xml
                if (_conversations.isEmpty)
                  _buildEmptyConversationView(isAr)
                else
                  ..._conversations.map((conv) {
                    return _buildConversationItem(
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
        );
      },
    );
  }

  /// Side-by-side banner cards matching cl_msg_info in chat_message_info_fragment.xml
  /// iv_system_msg: @mipmap/chat_message_system_bg (ratio 164:64)
  /// iv_information_msg: @mipmap/chat_message_information_bg (ratio 164:64)
  Widget _buildMessageBanners({
    required int unreadSystemCount,
    required int unreadEventCount,
    required bool isAr,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 8),
      child: Row(
        children: [
          // Banner 1: System Messages (iv_system_msg)
          Expanded(
            child: _buildBannerCard(
              bgAsset: 'assets/mipmap-xxhdpi/chat_message_system_bg.webp',
              title: isAr ? 'رسائل\nالنظام' : 'System\nNotice',
              unreadCount: unreadSystemCount,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                );
              },
            ),
          ),

          const SizedBox(width: 12),

          // Banner 2: Event Information (iv_information_msg)
          Expanded(
            child: _buildBannerCard(
              bgAsset: 'assets/mipmap-xxhdpi/chat_message_information_bg.webp',
              title: isAr ? 'معلومات\nالحدث' : 'Event\nInformation',
              unreadCount: unreadEventCount,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const EventInfoScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Individual banner card with 164:64 aspect ratio & unread badge
  Widget _buildBannerCard({
    required String bgAsset,
    required String title,
    required int unreadCount,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AspectRatio(
        aspectRatio: 164 / 64,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Background image
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  bgAsset,
                  fit: BoxFit.fill,
                ),
              ),
            ),

            // Card text (12sp, white, bold, marginStart: 12dp)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.25,
                  ),
                ),
              ),
            ),

            // BadgeView (bv_system_count / bv_event_count)
            // Color: @color/color_E82323, TextSize: 12sp
            if (unreadCount > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE82323),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
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
    );
  }

  /// Conversation item matching conversation_list_item_layout.xml
  Widget _buildConversationItem({
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
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                // Avatar (ConversationIconView: 48x48) + user_status (online dot)
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
                    if (isOnline)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3AFF92),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(width: 16),

                // Details (conversation_title, conversation_time, conversation_last_msg, conversation_unread)
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
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF3D3D3D),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            _formatTime(lastMessageTime),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9BA1B6),
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
                                fontSize: 12,
                                color: Color(0xFF9BA1B6),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (unread > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              constraints: const BoxConstraints(
                                  minWidth: 18, minHeight: 18),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE82323),
                                borderRadius: BorderRadius.circular(9),
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
            const SizedBox(height: 10),
            // Divider line (view_line)
            const Divider(
              height: 0.5,
              thickness: 0.5,
              color: Color(0xFFEDEDED),
              indent: 64,
            ),
          ],
        ),
      ),
    );
  }

  /// Empty conversation placeholder
  Widget _buildEmptyConversationView(bool isAr) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 52,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              isAr ? 'لا توجد رسائل حالياً' : 'No messages yet',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF9BA1B6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tab 1: Friends Tab
  Widget _buildFriendsTab(bool isAr) {
    if (_loadingFriends) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFD700)),
      );
    }

    if (_friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 56,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 14),
            Text(
              isAr ? 'لا يوجد أصدقاء حالياً' : 'No friends yet',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF9BA1B6),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _friends.length,
      separatorBuilder: (_, __) => const Divider(
        height: 0.5,
        thickness: 0.5,
        color: Color(0xFFEDEDED),
        indent: 72,
      ),
      itemBuilder: (context, index) {
        final friend = _friends[index];
        final uid = friend['uid'] as String? ?? '';
        final name = friend['name'] as String? ?? 'User';
        final photo = friend['photo_url'] as String? ?? '';
        final bio = friend['bio'] as String? ?? '';

        return ListTile(
          onTap: () {
            if (uid.isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(targetUid: uid),
                ),
              );
            }
          },
          leading: ClipOval(
            child: photo.isNotEmpty
                ? Image(
                    image: R.cachedImage(photo),
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
          title: Text(
            name,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3D3D3D),
            ),
          ),
          subtitle: bio.isNotEmpty
              ? Text(
                  bio,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9BA1B6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          trailing: IconButton(
            icon: const Icon(
              Icons.chat_outlined,
              color: Color(0xFF1E90FF),
              size: 20,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MessageReplyDetailScreen(
                    conversationId: '',
                    otherUid: uid,
                    otherName: name,
                    otherPhotoUrl: photo,
                  ),
                ),
              );
            },
          ),
        );
      },
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
}

