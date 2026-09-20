import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../providers/user_provider.dart';
import '../../../config/r.dart';
import '../../../config/app_colors.dart';
import '../../../services/level_service.dart';
import '../../../services/supabase_service.dart';
import '../../../services/dynamic_config_service.dart';
import '../../../core/supabase_compat.dart';
import '../../../core/widgets/cached_image.dart';
import '../../../models/gift_model.dart' as gm;
import '../../user_profile/user_profile_screen.dart';
import '../../message/message_reply_detail_screen.dart';
import 'svga_frame.dart';
import 'svga_player.dart';
import 'vap_player.dart';
import 'vip_cover_animator.dart';
import '../../../widgets/user_id_widget.dart';

class UserProfile extends StatefulWidget {
  final Map<String, dynamic> user;
  final bool showMicControls;
  final bool isCurrentUser;
  final bool isFollowed;
  final bool isModerator;
  final bool isRoomOwner;
  final bool isTargetModerator;
  final bool isBlocked;
  final String? currentUserId;
  final VoidCallback? onClose;
  final VoidCallback? onViewProfile;
  final VoidCallback? onFollow;
  final VoidCallback? onChat;
  final VoidCallback? onMention;
  final VoidCallback? onGift;
  final VoidCallback? onMicDown;
  final VoidCallback? onMicMute;
  final VoidCallback? onReport;
  final VoidCallback? onBlock;
  final VoidCallback? onUnblock;
  final VoidCallback? onKick;
  final VoidCallback? onMute;
  final VoidCallback? onToggleAdmin;

  const UserProfile({
    super.key,
    required this.user,
    this.showMicControls = false,
    this.isCurrentUser = false,
    this.isFollowed = false,
    this.isModerator = false,
    this.isRoomOwner = false,
    this.isTargetModerator = false,
    this.isBlocked = false,
    this.currentUserId,
    this.onClose,
    this.onViewProfile,
    this.onFollow,
    this.onChat,
    this.onMention,
    this.onGift,
    this.onMicDown,
    this.onMicMute,
    this.onReport,
    this.onBlock,
    this.onUnblock,
    this.onKick,
    this.onMute,
    this.onToggleAdmin,
  });

  static final Map<String, String> customIdCache = {};

  @override
  State<UserProfile> createState() => _UserProfileState();
}

final Map<String, String> customIdCache = UserProfile.customIdCache;

class _UserProfileState extends State<UserProfile> {
  Map<String, dynamic> _extraUserData = {};
  Map<String, dynamic>? _userAgency;
  bool _dataLoaded = false;
  final Map<String, String> _storeSvgaMap = {}; // itemId -> svgaAsset URL
  
  List<gm.SentGiftModel> _receivedGifts = [];
  Map<String, gm.GiftModel> _giftsCatalog = {};
  int _totalReceivedGiftCount = 0;

  int _followersCount = 0;
  int _fansCount = 0;
  int _visitorsCount = 0;

  @override
  void initState() {
    super.initState();
    _extraUserData = Map<String, dynamic>.from(widget.user);
    final uid = widget.user['id']?.toString() ?? widget.user['uid']?.toString() ?? '';
    final cid = widget.user['custom_id']?.toString() ?? widget.user['customId']?.toString();
    if (cid != null && cid.isNotEmpty) {
      customIdCache[uid] = cid;
      _extraUserData['custom_id'] = cid;
    } else if (customIdCache.containsKey(uid)) {
      _extraUserData['custom_id'] = customIdCache[uid];
    }
    _fetchData();
  }

  @override
  void didUpdateWidget(UserProfile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUid = oldWidget.user['id']?.toString() ?? oldWidget.user['uid']?.toString();
    final newUid = widget.user['id']?.toString() ?? widget.user['uid']?.toString();
    if (oldUid != newUid) {
      final cid = widget.user['custom_id']?.toString() ?? widget.user['customId']?.toString() ?? (newUid != null ? customIdCache[newUid] : null);
      setState(() {
        _extraUserData = Map<String, dynamic>.from(widget.user);
        if (cid != null && cid.isNotEmpty) {
          _extraUserData['custom_id'] = cid;
        }
        _dataLoaded = false;
      });
      _fetchData();
    }
  }

  Future<void> _fetchData() async {
    final uid = widget.user['id']?.toString() ?? widget.user['uid']?.toString();
    if (uid == null || uid.isEmpty) return;
    try {
      final svc = SupabaseService();
      // 1. Fetch user model directly from service
      final userObj = await svc.getUser(uid);
      if (userObj != null) {
        _extraUserData.addAll(userObj.toMap());
        if (userObj.customId.isNotEmpty) {
          customIdCache[uid] = userObj.customId;
          _extraUserData['custom_id'] = userObj.customId;
        }
      }
      try {
        final userData = await Supabase.instance.client
            .from('users')
            .select('custom_id, active_frame, active_cover, profile_bg_url, owned_badges, owned_level_badges, wealth_level, recharge_level, gems_level, owned_level_frames, owned_level_badges, owned_items, owned_necklaces, country, country_code, is_host, is_agent, role')
            .eq('uid', uid)
            .maybeSingle();
        if (userData != null) {
          _extraUserData.addAll(userData);
          final cId = userData['custom_id']?.toString();
          if (cId != null && cId.isNotEmpty) {
            customIdCache[uid] = cId;
            _extraUserData['custom_id'] = cId;
          }
        }
      } catch (_) {}

      // Fetch agency membership
      try {
        final memberRes = await Supabase.instance.client
            .from('host_agency_members')
            .select('agency_id, role, status')
            .eq('user_id', uid)
            .maybeSingle();
        if (memberRes != null && memberRes['agency_id'] != null) {
          final agencyId = memberRes['agency_id'].toString();
          final agencyRes = await Supabase.instance.client
              .from('host_agencies')
              .select('*')
              .eq('id', agencyId)
              .maybeSingle();
          if (agencyRes != null && mounted) {
            setState(() => _userAgency = agencyRes);
          }
        }
      } catch (_) {}

      // Load received gifts
      try {
        final gifts = await svc.getReceivedGifts(uid);
        final giftsCat = await svc.getGiftsCatalog();
        int total = 0;
        for (final g in gifts) {
          total += g.count;
        }
        _receivedGifts = gifts;
        _giftsCatalog = giftsCat;
        _totalReceivedGiftCount = total;
      } catch (_) {}

      // Load stats counts
      try {
        final followingList = await svc.getFollowing(uid);
        final fansList = await svc.getFans(uid);
        final visitorsList = await svc.getVisitors(uid);
        _followersCount = followingList.length;
        _fansCount = fansList.length;
        _visitorsCount = visitorsList.length;
      } catch (_) {}

      // Load store items to resolve itemId -> svgaAsset / videoAsset URL
      try {
        final storeList = await svc.getStoreItems();
        for (final item in storeList) {
          final anim = (item.videoAsset != null && item.videoAsset!.isNotEmpty)
              ? item.videoAsset!
              : (item.svgaAsset != null && item.svgaAsset!.isNotEmpty)
                  ? item.svgaAsset!
                  : item.iconAsset;
          if (anim.isNotEmpty) {
            _storeSvgaMap[item.itemId] = anim;
          }
        }
      } catch (_) {}
      try {
        final storeItems = await Supabase.instance.client
            .from('store_items')
            .select('item_id, id, svga_asset, video_asset, icon_asset');
        if (storeItems != null) {
          for (final item in (storeItems as List)) {
            final id = item['item_id']?.toString() ?? item['id']?.toString();
            final docId = item['id']?.toString();
            final asset = (item['video_asset']?.toString().isNotEmpty == true)
                ? item['video_asset'].toString()
                : (item['svga_asset']?.toString().isNotEmpty == true)
                    ? item['svga_asset'].toString()
                    : item['icon_asset']?.toString();
            if (asset != null && asset.isNotEmpty) {
              if (id != null) _storeSvgaMap[id] = asset;
              if (docId != null) _storeSvgaMap[docId] = asset;
            }
          }
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('[UserProfile Mini] Error loading data: $e');
    }
    if (mounted) setState(() => _dataLoaded = true);
  }

  String _resolveSvga(String itemId) {
    if (itemId.isEmpty) return '';
    if (itemId.startsWith('http://') || itemId.startsWith('https://') || itemId.startsWith('assets/')) {
      return itemId;
    }
    if (_storeSvgaMap.containsKey(itemId)) {
      return _storeSvgaMap[itemId]!;
    }
    final storeItem = SupabaseService().getStoreItemSync(itemId);
    if (storeItem != null) {
      final anim = (storeItem.videoAsset != null && storeItem.videoAsset!.isNotEmpty)
          ? storeItem.videoAsset!
          : (storeItem.svgaAsset != null && storeItem.svgaAsset!.isNotEmpty)
              ? storeItem.svgaAsset!
              : storeItem.iconAsset;
      if (anim.isNotEmpty) {
        _storeSvgaMap[itemId] = anim;
        return anim;
      }
    }
    return itemId;
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return '$count';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onClose,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: _buildCompactSheet(),
        ),
      ),
    );
  }

  Widget _buildCompactSheet() {
    final config = DynamicConfigService();
    final avatar = widget.user['avatar']?.toString() ?? widget.user['photo_url']?.toString() ?? widget.user['photoUrl']?.toString() ?? R.avaBoy;
    final name = widget.user['name']?.toString() ?? 'User';
    final gender = widget.user['gender']?.toString() ?? 'male';
    final country = _extraUserData['country_code']?.toString() ?? _extraUserData['country']?.toString() ?? widget.user['country']?.toString() ?? 'EG';
    final activeFrame = _extraUserData['active_frame']?.toString() ?? widget.user['active_frame']?.toString() ?? '';
    final isHost = widget.user['is_host'] == true || widget.user['role'] == 'host' || widget.user['role'] == 'owner' || widget.isModerator;

    final fbUid = widget.user['id']?.toString() ?? widget.user['uid']?.toString() ?? '';
    final idText = _extraUserData['custom_id']?.toString() ??
        widget.user['custom_id']?.toString() ??
        widget.user['customId']?.toString() ??
        customIdCache[fbUid] ??
        '...';

    final cardBgColor = config.miniprofileBgColor;
    final cardBorderColor = config.miniprofileBorderColor;
    final textColor = config.miniprofileTextColor;
    final subTextColor = config.miniprofileSubTextColor;
    final btnColor = config.miniprofileButtonColor;
    final currentUser = Provider.of<UserProvider>(context, listen: false).currentUser;
    final isMe = widget.isCurrentUser || (currentUser != null && (widget.user['uid'] == currentUser.uid || widget.user['id'] == currentUser.uid));

    final rawUserCover = (isMe && currentUser?.activeCover != null && currentUser!.activeCover!.isNotEmpty)
        ? currentUser.activeCover!
        : _extraUserData['active_cover']?.toString() ??
            widget.user['active_cover']?.toString() ??
            '';
    final userCover = _resolveSvga(rawUserCover);
    final hasUserCover = userCover.isNotEmpty;
    final coverWidth = MediaQuery.of(context).size.width;
    final coverHeight = config.miniprofileCoverHeight > 0
        ? config.miniprofileCoverHeight
        : coverWidth / config.miniprofileCoverAspectRatio;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        // Full Background User Cover (extends high above the avatar and spans the entire area)
        if (hasUserCover)
          Positioned(
            top: -config.miniprofileCoverHeight > 0
                ? -config.miniprofileCoverHeight * 0.22
                : -160,
            left: 0,
            right: 0,
            height: coverHeight,
            child: IgnorePointer(
              child: SizedBox(
                width: coverWidth,
                height: coverHeight,
                child: (isVideoType(userCover) || detectAssetType(userCover) == AssetType.vap || detectAssetType(userCover) == AssetType.mp4)
                    ? VapPlayer(
                        url: userCover,
                        width: coverWidth,
                        height: coverHeight,
                        fit: BoxFit.cover,
                        loops: true,
                      )
                    : detectAssetType(userCover) == AssetType.svga
                        ? SvgaPlayer(
                            assetPath: userCover,
                            width: coverWidth,
                            height: coverHeight,
                            fit: BoxFit.cover,
                            loops: true,
                          )
                        : Image(
                            image: R.cachedImage(userCover),
                            fit: BoxFit.cover,
                            width: coverWidth,
                            height: coverHeight,
                            errorBuilder: (_, __, ___) => const SizedBox(),
                          ),
              ),
            ),
          ),

        // Main bottom card
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 48),
          decoration: BoxDecoration(
            color: hasUserCover ? Colors.transparent : cardBgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: hasUserCover ? null : Border.all(color: cardBorderColor, width: 1),
            boxShadow: hasUserCover
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Stack(
              children: [
                if (!hasUserCover && config.miniprofileBgImage.isNotEmpty)
                  Positioned.fill(
                    child: Image(
                      image: R.cachedImage(config.miniprofileBgImage),
                      fit: BoxFit.cover,
                    ),
                  ),

                // Card Content
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 54, 16, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. User Name & Gender & VIP Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: gender == 'female' ? const Color(0xFFE91E63) : const Color(0xFF1E88E5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      gender == 'female' ? Icons.female : Icons.male,
                      color: Colors.white,
                      size: 13,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF42351A),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.amber, width: 0.8),
                    ),
                    child: const Icon(Icons.person, color: Colors.amber, size: 12),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // 2. ID (مطابق تماماً للأصل مع المعرف المميز والعادي) & Flag
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  UserIdWidget(
                    idText: idText,
                    countryCode: country,
                  ),
                ],
              ),

              // 3. Badges, Medals, Host & Agent Medals (الشارات والقلادات التلقائية)
              _buildBadgesAndMedals(config),
              const SizedBox(height: 10),

              // 4. Received Gifts Gallery Bar (شريط استلام الهدايا)
              GestureDetector(
                onTap: () {
                  if (widget.onViewProfile != null) {
                    widget.onViewProfile!();
                  } else {
                    final targetId = widget.user['id']?.toString() ?? widget.user['uid']?.toString();
                    if (targetId != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => UserProfileScreen(targetUid: targetId)),
                      );
                    }
                  }
                },
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF221A11),
                    image: config.miniprofileGiftBarBg.isNotEmpty
                        ? DecorationImage(image: R.cachedImage(config.miniprofileGiftBarBg), fit: BoxFit.cover)
                        : null,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: config.miniprofileGiftBarBorder, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.chevron_left, color: Colors.white54, size: 20),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _getAggregatedReceivedGifts().isEmpty
                            ? const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'لا توجد هدايا بعد',
                                  style: TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                              )
                            : Builder(
                                builder: (ctx) {
                                  final aggGifts = _getAggregatedReceivedGifts();
                                  return ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: aggGifts.length.clamp(0, 6),
                                    itemBuilder: (ctx, i) {
                                      final g = aggGifts[i];
                                      final giftDef = _giftsCatalog[g['giftId']];
                                      final icon = giftDef?.iconAsset ?? '';
                                      final isSvga = icon.isNotEmpty && detectAssetType(icon) == AssetType.svga;
                                      final count = g['count'] as int? ?? 1;

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        child: Stack(
                                          alignment: Alignment.center,
                                          clipBehavior: Clip.none,
                                          children: [
                                            Container(
                                              width: 38,
                                              height: 38,
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.05),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: icon.isNotEmpty
                                                  ? (isSvga
                                                      ? SvgaPlayer(assetPath: icon, width: 36, height: 36)
                                                      : CachedImg(icon, width: 36, height: 36, fit: BoxFit.contain))
                                                  : const Icon(Icons.card_giftcard, color: Colors.amber, size: 24),
                                            ),
                                            Positioned(
                                              bottom: -2,
                                              right: -2,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF4A3419),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: Colors.amber.withOpacity(0.5), width: 0.5),
                                                ),
                                                child: Text(
                                                  'x$count',
                                                  style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                                                ),
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
                      const SizedBox(width: 8),
                      // "استلام" label & count
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$_totalReceivedGiftCount',
                                style: const TextStyle(color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 2),
                              const Text(
                                'استلام',
                                style: TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // 5. Stats Row: الزائر | المحبون | متابعون
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatColumn('$_visitorsCount', 'الزائر', textColor, subTextColor),
                  _buildStatDivider(),
                  _buildStatColumn('$_fansCount', 'المحبون', textColor, subTextColor),
                  _buildStatDivider(),
                  _buildStatColumn('$_followersCount', 'متابعون', textColor, subTextColor),
                ],
              ),
              const SizedBox(height: 16),

              // 6. Mic Controls (Strictly for Room Owner / Room Moderator or user on their own mic)
              if (widget.showMicControls && (widget.isModerator || widget.isRoomOwner || widget.isCurrentUser)) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.isModerator || widget.isRoomOwner || widget.isCurrentUser)
                      GestureDetector(
                        onTap: widget.onMicDown,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: R.loadAsset(
                              DynamicConfigService.instance.roomUserMicDownIcon.isNotEmpty
                                  ? DynamicConfigService.instance.roomUserMicDownIcon
                                  : R.roomMicDown,
                              width: 24,
                              height: 24,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 24),
                    if (widget.isModerator || widget.isRoomOwner || widget.isCurrentUser)
                      GestureDetector(
                        onTap: widget.onMicMute,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: R.loadAsset(
                              DynamicConfigService.instance.roomUserMicMuteIcon.isNotEmpty
                                  ? DynamicConfigService.instance.roomUserMicMuteIcon
                                  : R.roomMicOff,
                              width: 24,
                              height: 24,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // 7. Bottom Action Buttons Bar (Frameless 52x52 icons, 100% transparent, customizable from control panel)
              if (!widget.isCurrentUser) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 1. Gift Button (هدية - 52x52 icon)
                    _buildRoundActionBtn(
                      customBgImg: config.miniprofileGiftBtnBg,
                      icon: config.miniprofileGiftIcon.isNotEmpty
                          ? Image(image: R.cachedImage(config.miniprofileGiftIcon), width: 52, height: 52, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Text('🎁', style: TextStyle(fontSize: 36)))
                          : const Text('🎁', style: TextStyle(fontSize: 36)),
                      onTap: () {
                        widget.onClose?.call();
                        widget.onGift?.call();
                      },
                    ),

                    // 2. @ Mention Button (52x52 icon)
                    _buildRoundActionBtn(
                      customBgImg: config.miniprofileMentionBtnBg,
                      icon: config.miniprofileMentionIcon.isNotEmpty
                          ? Image(image: R.cachedImage(config.miniprofileMentionIcon), width: 52, height: 52, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Text('@', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)))
                          : const Text('@', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                      onTap: () {
                        widget.onClose?.call();
                        widget.onMention?.call();
                      },
                    ),

                    // 3. Chat/Message Button (Direct 1-on-1 private chat, 52x52 icon)
                    _buildRoundActionBtn(
                      customBgImg: config.miniprofileChatBtnBg,
                      icon: config.miniprofileChatIcon.isNotEmpty
                          ? Image(image: R.cachedImage(config.miniprofileChatIcon), width: 52, height: 52, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 38))
                          : const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 38),
                      onTap: () {
                        widget.onClose?.call();
                        if (widget.onChat != null) {
                          widget.onChat!();
                        } else {
                          final myUid = currentUser?.uid ?? '';
                          final targetUid = widget.user['id']?.toString() ?? widget.user['uid']?.toString() ?? '';
                          final targetName = widget.user['name']?.toString() ?? 'User';
                          final targetPhoto = widget.user['avatar']?.toString() ?? widget.user['photo_url']?.toString() ?? widget.user['photoUrl']?.toString() ?? '';
                          if (targetUid.isNotEmpty && myUid.isNotEmpty) {
                            final convId = (myUid.compareTo(targetUid) < 0) ? '${myUid}_$targetUid' : '${targetUid}_$myUid';
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MessageReplyDetailScreen(
                                  conversationId: convId,
                                  otherUid: targetUid,
                                  otherName: targetName,
                                  otherPhotoUrl: targetPhoto,
                                ),
                              ),
                            );
                          }
                        }
                      },
                    ),

                    // 4. Follow Button (متابعة - 52x52 icon)
                    _buildRoundActionBtn(
                      customBgImg: config.miniprofileFollowBtnBg,
                      icon: config.miniprofileFollowIcon.isNotEmpty && !widget.isFollowed
                          ? Image(image: R.cachedImage(config.miniprofileFollowIcon), width: 52, height: 52, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(widget.isFollowed ? Icons.favorite : Icons.favorite_border_rounded, color: widget.isFollowed ? Colors.pinkAccent : Colors.white, size: 38))
                          : Icon(
                              widget.isFollowed ? Icons.favorite : Icons.favorite_border_rounded,
                              color: widget.isFollowed ? Colors.pinkAccent : Colors.white,
                              size: 38,
                            ),
                      onTap: widget.onFollow,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  ),
),

        // Centered Avatar (Raised high with ample breathing room above user name)
        Positioned(
          top: 4,
          child: GestureDetector(
            onTap: () {
              if (widget.onViewProfile != null) {
                widget.onViewProfile!();
              } else {
                final targetId = widget.user['id']?.toString() ?? widget.user['uid']?.toString();
                if (targetId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => UserProfileScreen(targetUid: targetId)),
                  );
                }
              }
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: cardBorderColor, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: R.loadImage(avatar, width: 72, height: 72, fit: BoxFit.cover),
                  ),
                ),
                if (activeFrame.isNotEmpty)
                  SvgaFrame(
                    svgaPath: _resolveSvga(activeFrame),
                    size: 92,
                  ),
              ],
            ),
          ),
        ),

        // Top-Right Three-Dot Options Button (...)
        Positioned(
          top: 58,
          right: 20,
          child: GestureDetector(
            onTap: () => _showOptionsMenu(),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: config.miniprofileMoreIcon.isNotEmpty
                  ? Image(image: R.cachedImage(config.miniprofileMoreIcon), width: 18, height: 18, errorBuilder: (_, __, ___) => const Icon(Icons.more_horiz, color: Colors.white70, size: 20))
                  : const Icon(Icons.more_horiz, color: Colors.white70, size: 20),
            ),
          ),
        ),
        // Decorative Card Frame Image Overlay
        if (config.miniprofileCardFrameImg.isNotEmpty)
          Positioned(
            top: 36,
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: Image(
                  image: R.cachedImage(config.miniprofileCardFrameImg),
                  fit: BoxFit.fill,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatColumn(String count, String label, Color textColor, Color subTextColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count,
          style: TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: subTextColor,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      height: 20,
      color: Colors.white10,
    );
  }

  Widget _buildRoundActionBtn({
    required Widget icon,
    required VoidCallback? onTap,
    String customBgImg = '',
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: customBgImg.isNotEmpty
            ? BoxDecoration(
                image: DecorationImage(image: R.cachedImage(customBgImg), fit: BoxFit.contain),
              )
            : null,
        alignment: Alignment.center,
        child: icon,
      ),
    );
  }

  Widget _buildBadgesAndMedals(DynamicConfigService config) {
    final List<Widget> badgeWidgets = [];

    final isHost = widget.user['is_host'] == true ||
        widget.user['role'] == 'host' ||
        widget.user['role'] == 'owner' ||
        widget.isModerator ||
        _extraUserData['is_host'] == true ||
        _userAgency != null;

    final isAgent = widget.user['is_agent'] == true ||
        widget.user['role'] == 'agent' ||
        _extraUserData['is_agent'] == true ||
        (_userAgency != null && _userAgency!['owner_id']?.toString() == (widget.user['uid'] ?? widget.user['id']));

    // 1. Host Medal / Badge (Auto-injected if Host)
    if (isHost) {
      final hostImg = config.agencyHostNecklaceImg.isNotEmpty
          ? config.agencyHostNecklaceImg
          : (config.miniprofileHostBadgeImg.isNotEmpty ? config.miniprofileHostBadgeImg : '');
      final hostSvga = config.agencyHostNecklaceSvga;

      badgeWidgets.add(
        _buildBadgeItem(
          svgaUrl: hostSvga,
          imageUrl: hostImg,
          fallbackText: 'مضيف',
          fallbackColor: const Color(0xFF1E5BB5),
        ),
      );
    }

    // 2. Agent Medal / Badge (Auto-injected if Agent / Agency Leader)
    if (isAgent) {
      final agentImg = config.agencyLeaderNecklaceImg.isNotEmpty
          ? config.agencyLeaderNecklaceImg
          : (config.miniprofileAgentBadgeImg.isNotEmpty ? config.miniprofileAgentBadgeImg : '');
      final agentSvga = config.agencyLeaderNecklaceSvga;

      badgeWidgets.add(
        _buildBadgeItem(
          svgaUrl: agentSvga,
          imageUrl: agentImg,
          fallbackText: 'وكيل',
          fallbackColor: const Color(0xFF8E24AA),
        ),
      );
    }

    // Active Equipped Necklace (from backpack / store)
    final activeNecklace = _extraUserData['active_necklace']?.toString() ??
        widget.user['active_necklace']?.toString() ??
        '';
    if (activeNecklace.isNotEmpty) {
      final resolved = _resolveSvga(activeNecklace);
      if (resolved.isNotEmpty) {
        badgeWidgets.add(
          _buildBadgeItem(
            svgaUrl: detectAssetType(resolved) == AssetType.svga ? resolved : '',
            imageUrl: resolved,
          ),
        );
      }
    }

    // 3. Owned Necklaces / Medals
    final ownedNecklaces = _extraUserData['owned_necklaces'];
    if (ownedNecklaces is List) {
      for (final n in ownedNecklaces) {
        if (n is String && n.isNotEmpty) {
          final item = _storeSvgaMap[n];
          if (item != null && item.isNotEmpty) {
            badgeWidgets.add(_buildBadgeItem(imageUrl: item, svgaUrl: detectAssetType(item) == AssetType.svga ? item : ''));
          }
        } else if (n is Map) {
          final svga = n['svga_url']?.toString() ?? '';
          final img = n['image_url']?.toString() ?? n['icon_asset']?.toString() ?? '';
          if (svga.isNotEmpty || img.isNotEmpty) {
            badgeWidgets.add(_buildBadgeItem(svgaUrl: svga, imageUrl: img));
          }
        }
      }
    }

    // 4. Owned Level Badges
    final ownedLevelBadges = _extraUserData['owned_level_badges'];
    if (ownedLevelBadges is List) {
      for (final b in ownedLevelBadges) {
        if (b is String && b.isNotEmpty) {
          badgeWidgets.add(_buildBadgeItem(imageUrl: b));
        }
      }
    }

    // 5. Owned Badges
    final ownedBadges = _extraUserData['owned_badges'];
    if (ownedBadges is List) {
      for (final b in ownedBadges) {
        if (b is String && b.isNotEmpty) {
          final item = _storeSvgaMap[b];
          if (item != null && item.isNotEmpty) {
            badgeWidgets.add(_buildBadgeItem(imageUrl: item, svgaUrl: detectAssetType(item) == AssetType.svga ? item : ''));
          }
        }
      }
    }

    if (badgeWidgets.isEmpty) return const SizedBox.shrink();

    // Show up to 3 necklaces side by side
    final displayBadges = badgeWidgets.take(3).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < displayBadges.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            displayBadges[i],
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getAggregatedReceivedGifts() {
    final Map<String, Map<String, dynamic>> map = {};
    for (final g in _receivedGifts) {
      final key = g.giftId.isNotEmpty ? g.giftId : (g.giftName.isNotEmpty ? g.giftName : 'gift');
      if (map.containsKey(key)) {
        map[key]!['count'] = (map[key]!['count'] as int) + g.count;
      } else {
        map[key] = {
          'giftId': g.giftId,
          'giftName': g.giftName,
          'count': g.count,
        };
      }
    }
    return map.values.toList();
  }

  Widget _buildBadgeItem({
    String svgaUrl = '',
    String imageUrl = '',
    String fallbackText = '',
    Color fallbackColor = const Color(0xFF1E5BB5),
  }) {
    const double badgeSize = 100;
    if (svgaUrl.isNotEmpty && detectAssetType(svgaUrl) == AssetType.svga) {
      return SizedBox(
        width: badgeSize,
        height: badgeSize,
        child: SvgaPlayer(assetPath: svgaUrl, fit: BoxFit.contain, loops: true),
      );
    }
    if (imageUrl.isNotEmpty) {
      return SizedBox(
        width: badgeSize,
        height: badgeSize,
        child: Image(
          image: R.cachedImage(imageUrl),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildFallbackBadge(fallbackText, fallbackColor),
        ),
      );
    }
    return _buildFallbackBadge(fallbackText, fallbackColor);
  }

  Widget _buildFallbackBadge(String text, Color color) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showOptionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1B26),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.isCurrentUser) ...[
              // 1. Assign / Remove Admin/Moderator (تعيين كأدمن / مشرف)
              if (widget.isRoomOwner || widget.isModerator)
                ListTile(
                  leading: Icon(
                    widget.isTargetModerator ? Icons.admin_panel_settings : Icons.admin_panel_settings_outlined,
                    color: Colors.amber,
                  ),
                  title: Text(
                    widget.isTargetModerator ? 'إلغاء الإشراف في الغرفة' : 'تعيين كأدمن / مشرف في الغرفة',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onToggleAdmin?.call();
                  },
                ),

              // 2. Mute in Room (كتم في الغرفة)
              if (widget.isModerator)
                ListTile(
                  leading: const Icon(Icons.volume_off_outlined, color: Colors.amberAccent),
                  title: const Text('كتم في الغرفة', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onMute?.call();
                  },
                ),

              // 3. Kick from Room (طرد من الغرفة)
              if (widget.isModerator)
                ListTile(
                  leading: const Icon(Icons.exit_to_app, color: Colors.redAccent),
                  title: const Text('طرد من الغرفة', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onKick?.call();
                  },
                ),

              // 4. Block / Unblock User (حظر / إلغاء حظر)
              ListTile(
                leading: Icon(
                  widget.isBlocked ? Icons.lock_open : Icons.block,
                  color: Colors.redAccent,
                ),
                title: Text(
                  widget.isBlocked ? 'إلغاء حظر المستخدم' : 'حظر المستخدم',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  if (widget.isBlocked) {
                    widget.onUnblock?.call();
                  } else {
                    widget.onBlock?.call();
                  }
                },
              ),

              // 5. Report User (إبلاغ عن المستخدم)
              ListTile(
                leading: const Icon(Icons.report_problem_outlined, color: Colors.orangeAccent),
                title: const Text('إبلاغ عن المستخدم', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showReportDialog();
                },
              ),
            ] else ...[
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('خيارات المستخدم', style: TextStyle(color: Colors.white54, fontSize: 13)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showReportDialog() {
    final descCtrl = TextEditingController();
    String? selectedReason;
    final reasons = ['Spam', 'Harassment', 'Inappropriate content', 'Fake account', 'Other'];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1B26),
        title: const Text('إبلاغ عن المستخدم', style: TextStyle(fontSize: 16, color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('سبب الإبلاغ', style: TextStyle(fontSize: 12, color: Colors.white54)),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                value: selectedReason,
                dropdownColor: const Color(0xFF2A2634),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                hint: const Text('اختر السبب', style: TextStyle(fontSize: 13, color: Colors.white38)),
                items: reasons.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13, color: Colors.white)))).toList(),
                onChanged: (v) => selectedReason = v,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              const Text('تفاصيل إضافية (اختياري)', style: TextStyle(fontSize: 12, color: Colors.white54)),
              const SizedBox(height: 4),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                maxLength: 500,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'اكتب التفاصيل هنا...',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(8),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () {
              if (selectedReason == null) return;
              SupabaseService().reportUser(
                reporterUid: widget.currentUserId ?? '',
                reportedUid: widget.user['id']?.toString() ?? '',
                reason: selectedReason!,
                description: descCtrl.text,
              );
              Navigator.pop(ctx);
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(content: Text('تم إرسال البلاغ بنجاح'), duration: Duration(seconds: 2)),
              );
            },
            child: const Text('إرسال', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

