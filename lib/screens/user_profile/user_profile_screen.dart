import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../config/r.dart';
import '../../core/supabase_compat.dart';
import '../../core/widgets/cached_image.dart';
import '../../models/gift_model.dart' as gm;
import '../../models/message_model.dart';
import '../../models/store_item_model.dart';
import '../../models/user_model.dart';
import '../../providers/user_provider.dart';
import '../../services/cloudinary_service.dart';
import '../../services/dynamic_config_service.dart';
import '../../services/supabase_service.dart';
import '../../services/level_service.dart';
import '../follow/follow_recent_screen.dart';
import '../login/edit_profile_screen.dart';
import '../level/level_screen.dart';
import '../room/room_screen.dart';
import '../room/widgets/svga_frame.dart';
import '../room/widgets/svga_player.dart';
import '../room/widgets/vap_player.dart';
import '../../features/cp/cp_service.dart';
import '../../features/cp/cp_space_screen.dart';
import '../../features/host_agency/screens/agency_profile_screen.dart';
import '../../features/host_agency/host_agency_screen.dart';

/// Helper data structure for aggregated gifts on wall
class AggregatedGift {
  final String giftId;
  final String giftName;
  final String iconUrl;
  final String? animationAsset;
  final int totalCount;
  final int totalValue;
  final List<GiftSenderInfo> senders;

  AggregatedGift({
    required this.giftId,
    required this.giftName,
    required this.iconUrl,
    this.animationAsset,
    required this.totalCount,
    required this.totalValue,
    required this.senders,
  });
}

class GiftSenderInfo {
  final String senderId;
  final String senderName;
  final String senderPhoto;
  final int count;

  GiftSenderInfo({
    required this.senderId,
    required this.senderName,
    required this.senderPhoto,
    required this.count,
  });
}

class SupporterRankInfo {
  final String senderId;
  final String senderName;
  final String senderPhoto;
  final int totalGiftsCount;
  final int totalCoins;

  SupporterRankInfo({
    required this.senderId,
    required this.senderName,
    required this.senderPhoto,
    required this.totalGiftsCount,
    required this.totalCoins,
  });
}

/// User Profile Screen matching 100% with native Android layout_userinfo.xml
/// and UserInfoActivity.java from reference codebase.
class UserProfileScreen extends StatefulWidget {
  final String? targetUid;

  const UserProfileScreen({super.key, this.targetUid});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final SupabaseService _supabase = SupabaseService();
  UserModel? _user;
  bool _loading = true;
  bool _isFollowing = false;
  int _currentBannerIndex = 0;
  // 0: Gifts Wall, 1: Headwear, 2: Rides, 3: Supporters, 4: CP Wall
  int _selectedWallTab = 0;

  // Data collections
  List<AggregatedGift> _aggregatedGifts = [];
  List<StoreItemModel> _ownedFrames = [];
  List<StoreItemModel> _ownedRides = [];
  List<SupporterRankInfo> _topSupporters = [];
  String? _resolvedFramePath;
  String? _resolvedNecklacePath;
  Map<String, Map<String, dynamic>> _badgesMap = {};
  Map<String, Map<String, dynamic>> _necklacesMap = {};

  // Stats
  int _followingCount = 0;
  int _fansCount = 0;
  int _visitorsCount = 0;

  // Active room ID if live
  String? _currentRoomId;

  // CP / Relationship info
  Map<String, dynamic>? _cpData;

  // Agency info
  Map<String, dynamic>? _agencyData;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final currentUser = userProvider.currentUser;
      final uid = widget.targetUid ?? currentUser?.uid;

      if (uid == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      UserModel? targetUser;
      if (widget.targetUid != null && widget.targetUid != currentUser?.uid) {
        targetUser = await _supabase.getUser(uid);
        if (currentUser != null) {
          final following = await _supabase.isFollowing(currentUser.uid, uid);
          if (mounted) setState(() => _isFollowing = following);
          _supabase.recordProfileVisit(
            visitedUid: uid,
            visitorUid: currentUser.uid,
            visitorName: currentUser.name,
            visitorPhoto: currentUser.photoUrl,
          );
        }
      } else {
        targetUser = currentUser ?? await _supabase.getUser(uid);
      }

      if (targetUser != null) {
        // Fetch all store items
        List<StoreItemModel> allStoreItems = [];
        try {
          allStoreItems = await _supabase.getStoreItems();
        } catch (_) {}

        // Resolve activeFrame path
        String? resolvedFrame = targetUser.activeFrame;
        if (resolvedFrame != null && resolvedFrame.isNotEmpty) {
          if (!resolvedFrame.startsWith('http') && !resolvedFrame.startsWith('assets/')) {
            final match = allStoreItems.where((i) => i.itemId == resolvedFrame || i.svgaAsset == resolvedFrame).firstOrNull;
            if (match != null) {
              final anim = (match.svgaAsset != null && match.svgaAsset!.isNotEmpty)
                  ? match.svgaAsset
                  : (match.videoAsset != null && match.videoAsset!.isNotEmpty)
                      ? match.videoAsset
                      : (match.animationUrl != null && match.animationUrl!.isNotEmpty)
                          ? match.animationUrl
                          : match.iconAsset;
              resolvedFrame = (anim != null && anim.isNotEmpty) ? anim : null;
            } else {
              resolvedFrame = null;
            }
          }
        }

        // Fetch Badges & Necklaces Catalogs
        Map<String, Map<String, dynamic>> badgesMap = {};
        try {
          final bList = await _supabase.getBadgesCatalog();
          for (final b in bList) {
            final id = b['id']?.toString() ?? '';
            if (id.isNotEmpty) badgesMap[id] = b;
          }
        } catch (_) {}

        Map<String, Map<String, dynamic>> necklacesMap = {};
        try {
          final nList = await _supabase.getNecklacesCatalog();
          for (final n in nList) {
            final id = n['id']?.toString() ?? '';
            if (id.isNotEmpty) necklacesMap[id] = n;
          }
        } catch (_) {}

        // Resolve activeNecklace path
        String? resolvedNecklace = targetUser.activeNecklace;
        if (resolvedNecklace != null && resolvedNecklace.isNotEmpty) {
          if (necklacesMap.containsKey(resolvedNecklace)) {
            final n = necklacesMap[resolvedNecklace]!;
            resolvedNecklace = n['svga_url']?.toString() ?? n['image_url']?.toString() ?? resolvedNecklace;
          }
        }
        // If no active necklace, but user has VIP item of type necklace
        if (resolvedNecklace == null || resolvedNecklace.isEmpty) {
          final vipNecklace = targetUser.ownedVipItems.where((m) => m['type'] == 'necklace').firstOrNull;
          if (vipNecklace != null && (vipNecklace['url'] ?? '').isNotEmpty) {
            resolvedNecklace = vipNecklace['url'];
          }
        }

        // Fetch store items to match owned frames & rides
        final ownedSet = targetUser.ownedItems.toSet();
        final frames = allStoreItems.where((i) => i.category == 'frame' && (ownedSet.contains(i.itemId) || i.svgaAsset == targetUser?.activeFrame)).toList();
        final rides = allStoreItems.where((i) => (i.category == 'car' || i.category == 'entrance') && (ownedSet.contains(i.itemId) || i.svgaAsset == targetUser?.activeCar || i.svgaAsset == targetUser?.activeEntrance)).toList();

        // Fetch gifts catalog
        Map<String, gm.GiftModel> giftCatalog = {};
        try {
          giftCatalog = await _supabase.getGiftsCatalog();
        } catch (_) {}

        // Fetch received gifts
        final gifts = await _supabase.getReceivedGifts(uid);
        final aggList = _aggregateGifts(gifts, giftCatalog);
        final supporters = _extractSupporters(gifts);

        // Fetch counts
        int followings = targetUser.following;
        int fans = targetUser.followers;
        int visitors = targetUser.visitors;
        try {
          final fList = await _supabase.getFollowing(uid);
          followings = fList.length;
        } catch (_) {}
        try {
          final fansList = await _supabase.getFans(uid);
          fans = fansList.length;
        } catch (_) {}
        try {
          final vList = await _supabase.getVisitors(uid);
          visitors = vList.length;
        } catch (_) {}

        // Check if user is in an active room
        String? activeRoomId;
        try {
          final client = Supabase.instance.client;
          final roomMember = await client
              .from('room_members')
              .select('room_id')
              .eq('user_id', uid)
              .maybeSingle();
          if (roomMember != null && roomMember['room_id'] != null) {
            activeRoomId = roomMember['room_id'].toString();
          }
        } catch (_) {}

        // Fetch CP / Relationship Data
        Map<String, dynamic>? cpInfo;
        try {
          final cpResult = await CpService.getMyData(uid);
          if (cpResult['has_cp'] == true) {
            cpInfo = cpResult['couple'] as Map<String, dynamic>?;
          }
        } catch (_) {}

        // Fetch Agency Data
        Map<String, dynamic>? agencyInfo;
        try {
          final memberRow = await Supabase.instance.client
              .from('host_agency_members')
              .select('agency_id, role, status')
              .eq('user_id', uid)
              .eq('status', 'active')
              .maybeSingle();
          if (memberRow != null && memberRow['agency_id'] != null) {
            final agRow = await Supabase.instance.client
                .from('host_agencies')
                .select('id, name, photo_url, tier')
                .eq('id', memberRow['agency_id'])
                .maybeSingle();
            if (agRow != null) {
              agencyInfo = {
                'agency_id': agRow['id'],
                'name': agRow['name'],
                'photo_url': agRow['photo_url'],
                'tier': agRow['tier'],
                'role': memberRow['role'],
              };
            }
          }
        } catch (_) {}

        if (mounted) {
          setState(() {
            _user = targetUser;
            _resolvedFramePath = resolvedFrame;
            _resolvedNecklacePath = resolvedNecklace;
            _badgesMap = badgesMap;
            _necklacesMap = necklacesMap;
            _aggregatedGifts = aggList;
            _topSupporters = supporters;
            _ownedFrames = frames;
            _ownedRides = rides;
            _followingCount = followings;
            _fansCount = fans;
            _visitorsCount = visitors;
            _currentRoomId = activeRoomId;
            _cpData = cpInfo;
            _agencyData = agencyInfo;
            _loading = false;
          });
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('[UserProfile] loadData error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<AggregatedGift> _aggregateGifts(
    List<gm.SentGiftModel> gifts,
    Map<String, gm.GiftModel> catalog,
  ) {
    final Map<String, List<gm.SentGiftModel>> map = {};
    for (final g in gifts) {
      final key = g.giftId.isNotEmpty ? g.giftId : g.giftName;
      map.putIfAbsent(key, () => []).add(g);
    }

    final List<AggregatedGift> result = [];
    map.forEach((key, list) {
      final first = list.first;
      int count = 0;
      int value = 0;
      final Map<String, GiftSenderInfo> sendersMap = {};

      for (final item in list) {
        count += item.count;
        value += item.totalValue;
        final sId = item.senderId;
        if (sendersMap.containsKey(sId)) {
          final old = sendersMap[sId]!;
          sendersMap[sId] = GiftSenderInfo(
            senderId: sId,
            senderName: old.senderName,
            senderPhoto: old.senderPhoto,
            count: old.count + item.count,
          );
        } else {
          sendersMap[sId] = GiftSenderInfo(
            senderId: sId,
            senderName: item.senderName.isNotEmpty ? item.senderName : 'مستخدم',
            senderPhoto: item.senderPhotoUrl ?? '',
            count: item.count,
          );
        }
      }

      final sortedSenders = sendersMap.values.toList()
        ..sort((a, b) => b.count.compareTo(a.count));

      final cat = catalog[first.giftId] ?? catalog[key];
      String icon = '';
      if (cat != null && cat.iconAsset.isNotEmpty) {
        icon = cat.iconAsset;
      } else if (first.iconAsset != null && first.iconAsset!.isNotEmpty) {
        icon = first.iconAsset!;
      } else if (first.defaultImage != null && first.defaultImage!.isNotEmpty) {
        icon = first.defaultImage!;
      }

      String anim = '';
      if (cat != null && (cat.animationAsset ?? '').isNotEmpty) {
        anim = cat.animationAsset!;
      } else if ((first.animationAsset ?? '').isNotEmpty) {
        anim = first.animationAsset!;
      }

      String gName = first.giftName;
      if (gName.isEmpty && cat != null) {
        gName = cat.nameAr.isNotEmpty ? cat.nameAr : cat.name;
      }
      if (gName.isEmpty) gName = 'هدية';

      result.add(AggregatedGift(
        giftId: first.giftId,
        giftName: gName,
        iconUrl: icon,
        animationAsset: anim.isNotEmpty ? anim : null,
        totalCount: count,
        totalValue: value,
        senders: sortedSenders,
      ));
    });

    result.sort((a, b) => b.totalCount.compareTo(a.totalCount));
    return result;
  }

  List<SupporterRankInfo> _extractSupporters(List<gm.SentGiftModel> gifts) {
    final Map<String, SupporterRankInfo> map = {};
    for (final g in gifts) {
      final sId = g.senderId;
      if (sId.isEmpty) continue;
      final prev = map[sId];
      if (prev != null) {
        map[sId] = SupporterRankInfo(
          senderId: sId,
          senderName: prev.senderName.isNotEmpty ? prev.senderName : g.senderName,
          senderPhoto: prev.senderPhoto.isNotEmpty ? prev.senderPhoto : (g.senderPhotoUrl ?? ''),
          totalGiftsCount: prev.totalGiftsCount + g.count,
          totalCoins: prev.totalCoins + g.totalValue,
        );
      } else {
        map[sId] = SupporterRankInfo(
          senderId: sId,
          senderName: g.senderName.isNotEmpty ? g.senderName : 'مستخدم',
          senderPhoto: g.senderPhotoUrl ?? '',
          totalGiftsCount: g.count,
          totalCoins: g.totalValue,
        );
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => b.totalCoins.compareTo(a.totalCoins));
    return list;
  }

  bool get _isMe {
    final currentUser = Provider.of<UserProvider>(context, listen: false).currentUser;
    if (_user == null || currentUser == null) return false;
    return _user!.uid == currentUser.uid;
  }

  Color _getNickNameColor(int vipLevel) {
    switch (vipLevel) {
      case 3:
        return const Color(0xFF217BEE);
      case 4:
        return const Color(0xFF8B3EFF);
      case 5:
        return const Color(0xFFE13A23);
      case 6:
        return const Color(0xFFEAA22B);
      default:
        return Colors.white;
    }
  }

  void _onBack() {
    Navigator.of(context).maybePop();
  }

  void _onMoreOperation() {
    if (_isMe) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EditProfileScreen()),
      ).then((_) => _loadData());
    } else {
      _showMoreOptionsDialog();
    }
  }

  void _showMoreOptionsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF25252B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.share, color: Colors.white),
                title: const Text('مشاركة الملف الشخصي', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: _user?.customId ?? _user?.uid ?? ''));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ رابط الملف الشخصي')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.report_problem_outlined, color: Colors.amber),
                title: const Text('إبلاغ', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم إرسال البلاغ بنجاح')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.redAccent),
                title: const Text('حظر المستخدم', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حظر المستخدم')),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleFollow() async {
    final currentUser = Provider.of<UserProvider>(context, listen: false).currentUser;
    if (currentUser == null || _user == null) return;

    final targetUid = _user!.uid;
    final currentlyFollowing = _isFollowing;
    setState(() => _isFollowing = !currentlyFollowing);

    try {
      if (currentlyFollowing) {
        await _supabase.unfollowUser(currentUser.uid, targetUid);
        if (mounted) setState(() => _fansCount = (_fansCount > 0) ? _fansCount - 1 : 0);
      } else {
        await _supabase.followUser(currentUser.uid, targetUid);
        if (mounted) setState(() => _fansCount += 1);
      }
    } catch (e) {
      if (mounted) setState(() => _isFollowing = currentlyFollowing);
      debugPrint('[UserProfile] toggleFollow error: $e');
    }
  }

  void _navigateToChat() {
    if (_user == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          targetUid: _user!.uid,
          targetName: _user!.name,
          targetPhotoUrl: _user!.photoUrl,
        ),
      ),
    );
  }

  void _openGiftSheet() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('يرجى إرسال الهدايا من داخل الغرفة الصوتية')),
    );
  }

  void _joinLiveRoom() {
    if (_currentRoomId != null) {
      navigateToRoom(
        context,
        roomName: 'غرفة صوتية',
        hostName: _user?.name ?? '',
        roomId: _currentRoomId!,
      );
    }
  }

  void _copyUserId() {
    final idText = _user?.customId ?? _user?.uid ?? '';
    Clipboard.setData(ClipboardData(text: idText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ الآيدي بنجاح')),
    );
  }

  // ── Transparent Dialogs ─────────────────────────────────────────────────────

  /// Preview Headwear without background box
  void _previewHeadwear(StoreItemModel frame) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) {
        return GestureDetector(
          onTap: () => Navigator.pop(ctx),
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 170,
                    height: 170,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ClipOval(
                          child: CachedImg(
                            _user?.photoUrl ?? '',
                            width: 110,
                            height: 110,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: Colors.white10),
                            error: (_, __, ___) => const Icon(Icons.person, size: 60, color: Colors.white38),
                          ),
                        ),
                        if (frame.svgaAsset != null && frame.svgaAsset!.isNotEmpty)
                          Positioned.fill(
                            child: SvgaFrame(
                              svgaPath: frame.svgaAsset!,
                              size: 170,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0x40FAE9B5)),
                    ),
                    child: Text(
                      frame.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFAE9B5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'اضغط في أي مكان للإغلاق',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Preview Ride full-screen entrance animation
  void _previewRide(StoreItemModel ride) {
    final assetPath = (ride.videoAsset != null && ride.videoAsset!.isNotEmpty)
        ? ride.videoAsset!
        : (ride.svgaAsset ?? '');

    final isVap = assetPath.toLowerCase().endsWith('.mp4');

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) {
        return GestureDetector(
          onTap: () => Navigator.pop(ctx),
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: isVap
                      ? VapPlayer(
                          url: assetPath,
                          loops: true,
                          fit: BoxFit.contain,
                        )
                      : SvgaPlayer(
                          assetPath: assetPath,
                          loops: true,
                          fit: BoxFit.contain,
                        ),
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Transparent Gift Details Dialog showing total count, effect, and supporters
  void _showGiftDetailDialog(AggregatedGift gift) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF222028).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0x33FFD770)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Gift Icon + Animated Effect (SVGA / VAP)
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16151A),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFFFD770), width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFFD770).withValues(alpha: 0.3),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: CachedImg(
                          gift.iconUrl,
                          width: 68,
                          height: 68,
                          fit: BoxFit.contain,
                          error: (_, __, ___) => const Icon(Icons.card_giftcard, color: Colors.amber, size: 50),
                        ),
                      ),
                      if (gift.animationAsset != null && gift.animationAsset!.isNotEmpty)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: SvgaFrame(
                              svgaPath: gift.animationAsset!,
                              size: 120,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  gift.giftName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFAE9B5),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0x33FFD770),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'العدد الإجمالي المُستلم: x${gift.totalCount}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFFD770),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white12),
                const SizedBox(height: 8),

                // Top Supporters / Senders Title
                Row(
                  children: [
                    const Icon(Icons.favorite, color: Colors.pinkAccent, size: 16),
                    const SizedBox(width: 6),
                    const Text(
                      'أبرز الداعمين لهذه الهدية',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${gift.senders.length} داعم',
                      style: const TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Senders List
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: gift.senders.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد معلومات داعمين مسجلة',
                            style: TextStyle(fontSize: 11, color: Colors.white38),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: gift.senders.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (c, idx) {
                            final sender = gift.senders[idx];
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundImage: sender.senderPhoto.isNotEmpty
                                        ? cachedImgProvider(sender.senderPhoto)
                                        : null,
                                    child: sender.senderPhoto.isEmpty
                                        ? const Icon(Icons.person, size: 16, color: Colors.white54)
                                        : null,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      sender.senderName,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'x${sender.count}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 16),

                // Close Button
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E2D36),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: Colors.white12),
                      ),
                    ),
                    child: const Text('إغلاق', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Build Methods ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF16151A),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFAE9B5)),
        ),
      );
    }

    final user = _user;
    if (user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF16151A),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: Text('المستخدم غير موجود', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final List<String> photos = [];
    if (user.album.isNotEmpty) {
      photos.addAll(user.album);
    } else {
      if (user.profileBgUrl != null && user.profileBgUrl!.isNotEmpty) {
        photos.add(user.profileBgUrl!);
      }
      if (user.photoUrl.isNotEmpty && !photos.contains(user.photoUrl)) {
        photos.add(user.photoUrl);
      }
    }
    if (photos.isEmpty) {
      photos.add('');
    }

    final hasVip = user.ownedVipItems.isNotEmpty ||
        (_resolvedNecklacePath != null && _resolvedNecklacePath!.isNotEmpty) ||
        (user.activeNecklace != null && user.activeNecklace!.isNotEmpty) ||
        (user.rechargeLevel > 1) ||
        (user.rechargeExp > 0);

    return Scaffold(
      backgroundColor: const Color(0xFF16151A),
      body: Stack(
        children: [
          // ── Top 1:1 Banner Carousel ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: screenWidth,
            child: Stack(
              children: [
                // Banner PageView
                PageView.builder(
                  itemCount: photos.length,
                  onPageChanged: (index) => setState(() => _currentBannerIndex = index),
                  itemBuilder: (context, index) {
                    final photo = photos[index];
                    return CachedImg(
                      photo,
                      fit: BoxFit.cover,
                      width: screenWidth,
                      height: screenWidth,
                      placeholder: (_, __) => Container(color: const Color(0xFF16151A)),
                      error: (_, __, ___) => Container(
                        color: const Color(0xFF16151A),
                        child: const Icon(Icons.person, size: 80, color: Colors.white24),
                      ),
                    );
                  },
                ),

                // Dark gradient overlay for status bar & contrast
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.5),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.6),
                        ],
                        stops: const [0.0, 0.4, 1.0],
                      ),
                    ),
                  ),
                ),

                // Dot Indicator at margin 40dp from bottom
                if (photos.length > 1)
                  Positioned(
                    bottom: 40,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(photos.length, (idx) {
                        final isSel = idx == _currentBannerIndex;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: isSel ? 12 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isSel ? Colors.white : Colors.white54,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                  ),
              ],
            ),
          ),

          // ── Collapsible Body (CoordinatorLayout equivalent) ──
          Positioned.fill(
            child: CustomScrollView(
              physics: const ClampingScrollPhysics(),
              slivers: [
                // Space for Banner minus overlap
                SliverToBoxAdapter(
                  child: SizedBox(height: screenWidth - 44),
                ),

                // Overlapping Rounded Card (#16151A, rounded top 12dp)
                SliverToBoxAdapter(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF16151A),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 70dp spacer for Avatar overlap
                            const SizedBox(height: 70),

                            // Signature (hidden if empty)
                            if (user.signature.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  children: [
                                    Image.asset(
                                      'assets/images/profile/mine_user_sign_ic.webp',
                                      width: 14,
                                      height: 14,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        Icons.edit_note,
                                        size: 14,
                                        color: Color(0x80FFFFFF),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        user.signature.trim(),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0x80FFFFFF),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Level badges row (RankLevelView)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: _buildRankLevelView(user),
                            ),

                            // Active Necklace (القلادة تحت المستويات - لا تظهر هنا إذا كان لديه VIP لمنع التكرار)
                            if (!hasVip &&
                                ((_resolvedNecklacePath != null && _resolvedNecklacePath!.isNotEmpty) ||
                                 (user.activeNecklace != null && user.activeNecklace!.isNotEmpty)))
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                                child: _buildNecklaceView(_resolvedNecklacePath ?? user.activeNecklace!),
                              ),

                            // Medals & Badges row (UserMedalView تحت القلادات مباشرة)
                            if (user.ownedBadges.isNotEmpty || user.ownedLevelBadges.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                                child: _buildUserMedalView(user),
                              ),

                            // CP / Relationship Card (جدار العلاقات)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                              child: _buildCpRelationshipCard(),
                            ),

                            // Agency Card if user belongs to an agency
                            if (_agencyData != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                                child: _buildAgencyCard(),
                              ),

                            // Stats Box (mine_user_info_shape_2_bg: #25252B, height 68dp, rounded 8dp)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: _buildStatsBox(),
                            ),

                            // Tabs Bar (recyclerview_tab: 5 tabs)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 20, 8, 0),
                              child: _buildWallTabBar(),
                            ),

                            // Wall Grid Content
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                              child: _buildWallGrid(),
                            ),
                          ],
                        ),

                        // Avatar Stack (UserAvatarView: 116x116dp, top -30dp, left 16dp)
                        Positioned(
                          top: -30,
                          left: 16,
                          child: _buildAvatarView(user),
                        ),

                        // Nickname + Gender + Country + ID row (cl_user_info)
                        Positioned(
                          top: 10,
                          left: 142,
                          right: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  // Nickname (14sp bold, color by VIP)
                                  Flexible(
                                    child: Text(
                                      user.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: _getNickNameColor(user.rechargeLevel),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Gender icon
                                  Image.asset(
                                    user.gender == 'female'
                                        ? 'assets/images/profile/sex_female_ic.webp'
                                        : 'assets/images/profile/sex_male_ic.webp',
                                    width: 18,
                                    height: 16,
                                    errorBuilder: (_, __, ___) => Icon(
                                      user.gender == 'female' ? Icons.female : Icons.male,
                                      size: 16,
                                      color: user.gender == 'female' ? Colors.pink : Colors.blue,
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Country flag / badge
                                  if (user.country.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(2),
                                        color: Colors.white12,
                                      ),
                                      child: Text(
                                        user.country.toUpperCase(),
                                        style: const TextStyle(fontSize: 9, color: Colors.white70, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),

                              // ID View with Copy icon
                              GestureDetector(
                                onTap: _copyUserId,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black26,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Image.asset(
                                        'assets/images/profile/common_user_id_ic.webp',
                                        width: 14,
                                        height: 14,
                                        errorBuilder: (_, __, ___) => const Icon(
                                          Icons.tag,
                                          size: 12,
                                          color: Colors.white70,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        user.customId.isNotEmpty ? user.customId : user.uid.substring(0, 8),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Image.asset(
                                        'assets/images/profile/common_id_copy_ic.webp',
                                        width: 14,
                                        height: 14,
                                        errorBuilder: (_, __, ___) => const Icon(
                                          Icons.copy,
                                          size: 12,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Live Room Pill Badge (mine_live_shape: mine_live_label + "غرفة صوتية")
                        if (_currentRoomId != null)
                          Positioned(
                            top: 10,
                            right: 16,
                            child: GestureDetector(
                              onTap: _joinLiveRoom,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFF6036), Color(0xFFFF8960)],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Image.asset(
                                      'assets/images/profile/mine_live_label.webp',
                                      height: 16,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        Icons.volume_up,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'غرفة صوتية',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Top Navigation Bar (Status Bar overlay) ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back button
                    GestureDetector(
                      onTap: _onBack,
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        child: Image.asset(
                          'assets/images/profile/ic_back_white.webp',
                          width: 28,
                          height: 28,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.arrow_back_ios_new,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),

                    // More / Edit button
                    GestureDetector(
                      onTap: _onMoreOperation,
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        child: Image.asset(
                          _isMe
                              ? 'assets/images/profile/mine_user_edit_ic.webp'
                              : 'assets/images/profile/mine_user_info_more_ic.webp',
                          width: 28,
                          height: 28,
                          errorBuilder: (_, __, ___) => Icon(
                            _isMe ? Icons.edit : Icons.more_vert,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom Action Bar (idPartBottom: 58dp, background #16151A) ──
          if (!_isMe)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 58,
              child: Container(
                color: const Color(0xFF16151A),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // Follow Button (idFollow)
                    GestureDetector(
                      onTap: _toggleFollow,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              _isFollowing
                                  ? 'assets/images/profile/mine_follow_pre_ic.webp'
                                  : 'assets/images/profile/mine_follow_nor_ic.webp',
                              width: 24,
                              height: 24,
                              errorBuilder: (_, __, ___) => Icon(
                                _isFollowing ? Icons.check_circle : Icons.add_circle_outline,
                                color: const Color(0xFFFAE9B5),
                                size: 22,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isFollowing ? 'تمت المتابعة' : 'متابعة',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFFFAE9B5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Chat Button (cl_chat: mine_user_info_chat_bg)
                    GestureDetector(
                      onTap: _navigateToChat,
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        decoration: BoxDecoration(
                          color: const Color(0xFF25252B),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0x33FFFAE9)),
                        ),
                        child: Row(
                          children: [
                            Image.asset(
                              'assets/images/profile/mine_chat_ic.webp',
                              width: 19,
                              height: 17,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.chat_bubble_outline,
                                color: Color(0xFFFAE9B5),
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'محادثة',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFFFAE9B5),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Gift Button (idPartGift: shape_gift_bg)
                    GestureDetector(
                      onTap: _openGiftSheet,
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFD770), Color(0xFFFFAE19)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Image.asset(
                              'assets/images/profile/ic_gift_2.webp',
                              width: 18,
                              height: 18,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.card_giftcard,
                                color: Color(0xFF16151A),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'هدية',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF16151A),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Avatar with resolved SvgaFrame
  Widget _buildAvatarView(UserModel user) {
    final frame = _resolvedFramePath ?? user.activeFrame;
    final hasFrame = frame != null && frame.isNotEmpty;
    return SizedBox(
      width: 122,
      height: 122,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Circular Avatar (iv_avatar 92dp with 4dp white border)
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              color: Colors.white,
            ),
            clipBehavior: Clip.antiAlias,
            child: user.photoUrl.isNotEmpty
                ? CachedImg(
                    user.photoUrl,
                    width: 92,
                    height: 92,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: Colors.white12),
                    error: (_, __, ___) => Image.asset(
                      'assets/images/default_header.png',
                      width: 92,
                      height: 92,
                      fit: BoxFit.cover,
                    ),
                  )
                : Image.asset(
                    'assets/images/default_header.png',
                    width: 92,
                    height: 92,
                    fit: BoxFit.cover,
                  ),
          ),

          // Outer frame: active SVGA frame or default mine_avatar_ic.webp
          if (hasFrame)
            Positioned.fill(
              child: IgnorePointer(
                child: SvgaFrame(
                  svgaPath: frame,
                  size: 122,
                ),
              ),
            )
          else
            Positioned.fill(
              child: IgnorePointer(
                child: Image.asset(
                  'assets/mipmap-xxhdpi/mine_avatar_ic.webp',
                  width: 122,
                  height: 122,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// RankLevelView: VIP, Wealth, Charm levels using LevelService configs
  Widget _buildRankLevelView(UserModel user) {
    final lvlService = LevelService();
    final wealthCfg = lvlService.getLevelConfig('wealth', user.wealthLevel);
    final gemsCfg = lvlService.getLevelConfig('gems', user.gemsLevel);

    final hasVip = user.ownedVipItems.isNotEmpty ||
        (_resolvedNecklacePath != null && _resolvedNecklacePath!.isNotEmpty) ||
        (user.activeNecklace != null && user.activeNecklace!.isNotEmpty) ||
        (user.rechargeLevel > 1) ||
        (user.rechargeExp > 0);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LevelScreen()),
        );
      },
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // VIP / Necklace Badge - Only if user has VIP!
          if (hasVip)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _buildVipNecklaceBadge(user),
            ),

          // Wealth Level Badge
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: wealthCfg?.imageUrl != null && wealthCfg!.imageUrl!.isNotEmpty
                ? SizedBox(
                    height: 24,
                    child: R.loadAsset(wealthCfg.imageUrl!, fit: BoxFit.contain),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2979FF), Color(0xFF1565C0)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.diamond, color: Colors.white, size: 10),
                        const SizedBox(width: 2),
                        Text(
                          'Lv.${user.wealthLevel}',
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          // Charm Level Badge
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: gemsCfg?.imageUrl != null && gemsCfg!.imageUrl!.isNotEmpty
                ? SizedBox(
                    height: 24,
                    child: R.loadAsset(gemsCfg.imageUrl!, fit: BoxFit.contain),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF4081), Color(0xFFC2185B)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite, color: Colors.white, size: 10),
                        const SizedBox(width: 2),
                        Text(
                          'Lv.${user.gemsLevel}',
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// VIP Necklace badge beside the level (قلادة VIP SVGA فقط بدون صندوق برتقالي وبدون نص VIP)
  Widget _buildVipNecklaceBadge(UserModel user) {
    String necklace = _resolvedNecklacePath ?? user.activeNecklace ?? '';
    if (necklace.isEmpty) {
      final lvl = user.rechargeLevel.clamp(1, 5);
      necklace = 'assets/svga/v${lvl}_left_bottom.svga';
    } else if (_necklacesMap.containsKey(necklace)) {
      final item = _necklacesMap[necklace]!;
      necklace = item['svga_url']?.toString() ?? item['image_url']?.toString() ?? necklace;
    }

    return SizedBox(
      width: 28,
      height: 28,
      child: SvgaFrame(
        svgaPath: necklace,
        size: 28,
        fit: BoxFit.contain,
      ),
    );
  }

  /// Active Necklace (القلادات تحت المستويات)
  Widget _buildNecklaceView(String necklaceAsset) {
    String path = necklaceAsset;
    if (_necklacesMap.containsKey(path)) {
      final item = _necklacesMap[path]!;
      path = item['svga_url']?.toString() ?? item['image_url']?.toString() ?? path;
    }

    return Container(
      height: 48,
      width: 140,
      decoration: BoxDecoration(
        color: const Color(0xFF222028),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x33FFD770)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SvgaFrame(
          svgaPath: path,
          size: 48,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  /// UserMedalView: horizontal row of user medals and badges (مكبرة 7+ درجات ودعم تشغيل SVGA)
  Widget _buildUserMedalView(UserModel user) {
    final Set<String> badgeIds = {...user.ownedBadges, ...user.ownedLevelBadges};
    if (badgeIds.isEmpty) return const SizedBox.shrink();

    final List<Map<String, String>> resolvedMedals = [];
    for (final id in badgeIds) {
      if (id.startsWith('http') || id.startsWith('assets/')) {
        resolvedMedals.add({'url': id, 'name': 'شارة'});
      } else if (_badgesMap.containsKey(id)) {
        final b = _badgesMap[id]!;
        // الأولوية لملف SVGA المتحرك إذا توفر
        final svga = b['svga_url']?.toString() ?? '';
        final img = b['image_url']?.toString() ?? '';
        final url = svga.isNotEmpty ? svga : img;
        final name = b['name_ar']?.toString() ?? b['name']?.toString() ?? 'شارة';
        if (url.isNotEmpty) {
          resolvedMedals.add({'url': url, 'name': name});
        }
      }
    }

    if (resolvedMedals.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: resolvedMedals.length.clamp(0, 10),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final m = resolvedMedals[index];
          final url = m['url'] ?? '';
          final isSvga = url.toLowerCase().endsWith('.svga') || url.startsWith('assets/svga/');

          return Tooltip(
            message: m['name'] ?? '',
            child: SizedBox(
              width: 46,
              height: 46,
              child: isSvga
                  ? SvgaFrame(
                      svgaPath: url,
                      size: 46,
                      fit: BoxFit.contain,
                    )
                  : CachedImg(
                      url,
                      width: 46,
                      height: 46,
                      fit: BoxFit.contain,
                      error: (_, __, ___) => const SizedBox.shrink(),
                    ),
            ),
          );
        },
      ),
    );
  }

  /// CP / Relationship Card (جدار العلاقات باستخدام cp1.svga والمفاتيح avatar1, avatar2, test)
  Widget _buildCpRelationshipCard() {
    final cp = _cpData;
    final partner = cp?['partner'] as Map<String, dynamic>?;
    final daysTogether = cp?['days_together'] ?? 0;
    final myPhoto = _user?.photoUrl ?? '';
    final partnerPhoto = partner?['avatar']?.toString() ?? '';

    final imageMap = <String, String>{};
    if (myPhoto.isNotEmpty) {
      imageMap['avatar1'] = myPhoto;
    } else {
      imageMap['avatar1'] = 'assets/mipmap-xxhdpi/ava_boy.webp';
    }

    if (partnerPhoto.isNotEmpty) {
      imageMap['avatar2'] = partnerPhoto;
    } else {
      imageMap['avatar2'] = 'assets/cp/ic_add_cp.webp';
    }

    final textMap = <String, String>{
      'test': '$daysTogether',
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CpSpaceScreen()),
        );
      },
      child: Container(
        height: 126,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: SvgaPlayer(
          assetPath: 'assets/svga/cp1.svga',
          height: 126,
          fit: BoxFit.fill,
          imageReplacement: imageMap,
          textReplacement: textMap,
          loops: true,
        ),
      ),
    );
  }

    /// User Agency Card
  Widget _buildAgencyCard() {
    final ag = _agencyData!;
    final name = ag['name']?.toString() ?? 'وكالة';
    final photo = ag['photo_url']?.toString() ?? '';
    final aid = ag['agency_id']?.toString() ?? '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (aid.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AgencyProfileScreen(agencyId: aid)),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const HostAgencyScreen()),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF222028),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x33FFD770)),
        ),
        child: Row(
          children: [
            Image.asset(
              'assets/mipmap-xxhdpi/union_ic.webp',
              width: 24,
              height: 24,
              errorBuilder: (_, __, ___) => const Icon(Icons.business_center, color: Colors.amber, size: 22),
            ),
            const SizedBox(width: 10),
            if (photo.isNotEmpty)
              ClipOval(
                child: CachedImg(
                  photo,
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'وكالة رسمية معتمدة',
                    style: TextStyle(fontSize: 10, color: Color(0xFF9BA1B6)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 14),
          ],
        ),
      ),
    );
  }

  /// 3-Column Stats Box (#FF25252B, height 68dp, rounded 8dp)
  Widget _buildStatsBox() {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: const Color(0xFF25252B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Following (ll_follow)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_user != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FollowRecentScreen(
                        initialTab: 0,
                        targetUid: _user!.uid,
                      ),
                    ),
                  );
                }
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$_followingCount',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'متابعة',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9BA1B6),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Fans (ll_fan)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_user != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FollowRecentScreen(
                        initialTab: 1,
                        targetUid: _user!.uid,
                      ),
                    ),
                  );
                }
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$_fansCount',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'معجبين',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9BA1B6),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Visitors (ll_visitor)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_user != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FollowRecentScreen(
                        initialTab: 2,
                        targetUid: _user!.uid,
                      ),
                    ),
                  );
                }
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$_visitorsCount',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'الزوار',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9BA1B6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Wall Tab Bar (5 tabs: Gifts Wall, Headwear, Rides, Supporters, CP Wall)
  Widget _buildWallTabBar() {
    final tabs = ['حائط الهدايا', 'أغطية الرأس', 'المطايا', 'الداعمين', 'العلاقات'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(tabs.length, (idx) {
          final isSel = idx == _selectedWallTab;
          return GestureDetector(
            onTap: () => setState(() => _selectedWallTab = idx),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSel ? const Color(0xFFFAE9B5) : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                tabs[idx],
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  color: isSel ? Colors.white : const Color(0x80FFFFFF),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Wall Grid Content
  Widget _buildWallGrid() {
    if (_selectedWallTab == 0) {
      // Gifts Wall (Aggregated xN count, tap opens transparent supporters dialog)
      if (_aggregatedGifts.isEmpty) {
        return _buildEmptyWall(
          _isMe ? 'لم يتم استلام أي هدايا بعد~' : 'لم يستلم أي هدايا بعد~',
        );
      }
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _aggregatedGifts.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 11,
          childAspectRatio: 0.8,
        ),
        itemBuilder: (context, index) {
          final item = _aggregatedGifts[index];
          return GestureDetector(
            onTap: () => _showGiftDetailDialog(item),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1F1E24),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CachedImg(
                    item.iconUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.contain,
                    error: (_, __, ___) => const Icon(Icons.card_giftcard, color: Colors.amber, size: 36),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'x${item.totalCount}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    item.giftName,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFF9BA1B6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else if (_selectedWallTab == 1) {
      // Headwear Wall (Tap opens transparent SVGA preview without box)
      if (_ownedFrames.isEmpty) {
        return _buildEmptyWall(
          _isMe ? 'لم يتم استلام أي غطاء رأس بعد~' : 'لم يستلم أي غطاء رأس بعد~',
        );
      }
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _ownedFrames.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 11,
          childAspectRatio: 0.8,
        ),
        itemBuilder: (context, index) {
          final frame = _ownedFrames[index];
          return GestureDetector(
            onTap: () => _previewHeadwear(frame),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1F1E24),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CachedImg(
                    frame.iconAsset,
                    width: 44,
                    height: 44,
                    fit: BoxFit.contain,
                    error: (_, __, ___) => const Icon(Icons.circle_outlined, color: Colors.blue, size: 36),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    frame.name,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF9BA1B6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else if (_selectedWallTab == 2) {
      // Rides / Mounts Wall (Tap opens full-screen transparent entrance preview)
      if (_ownedRides.isEmpty) {
        return _buildEmptyWall(
          _isMe ? 'لم يتم استلام أي مطية بعد~' : 'لم يستلم أي مطية بعد~',
        );
      }
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _ownedRides.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 11,
          childAspectRatio: 0.8,
        ),
        itemBuilder: (context, index) {
          final ride = _ownedRides[index];
          return GestureDetector(
            onTap: () => _previewRide(ride),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1F1E24),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CachedImg(
                    ride.iconAsset,
                    width: 44,
                    height: 44,
                    fit: BoxFit.contain,
                    error: (_, __, ___) => const Icon(Icons.directions_car, color: Colors.purple, size: 36),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ride.name,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF9BA1B6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else if (_selectedWallTab == 3) {
      // Supporters Wall (Top Supporters with Podium Top 3)
      return _buildSupportersWall();
    } else {
      // CP Wall (العلاقات)
      return Column(
        children: [
          _buildCpRelationshipCard(),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CpSpaceScreen()),
              );
            },
            icon: const Icon(Icons.favorite, color: Colors.pinkAccent),
            label: const Text('دخول مساحة الـ CP والترتيب الكامل', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E1928),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: const BorderSide(color: Color(0x44FF4081)),
              ),
            ),
          ),
        ],
      );
    }
  }

  /// Authentic Supporters Podium + List (مطابق تماماً لترتيب داخل الغرفة room_rank_bottom_sheet)
  Widget _buildSupportersWall() {
    if (_topSupporters.isEmpty) {
      return _buildEmptyWall('لا يوجد داعمين مسجلين بعد~');
    }

    final top1 = _topSupporters.isNotEmpty ? _topSupporters[0] : null;
    final top2 = _topSupporters.length > 1 ? _topSupporters[1] : null;
    final top3 = _topSupporters.length > 2 ? _topSupporters[2] : null;
    final restList = _topSupporters.length > 3 ? _topSupporters.sublist(3) : <SupporterRankInfo>[];

    return Column(
      children: [
        // Top 3 Podium matching room_rank_bottom_sheet
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1F1E24),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x22FFD770)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Rank 2 (Left)
              Expanded(
                flex: 3,
                child: _buildPodiumSupporter(
                  item: top2,
                  rank: 2,
                  avatarSize: 56,
                  frameSize: 96,
                  frameAsset: 'assets/images/rank_top_avatar_2.webp',
                  baseAsset: 'assets/images/rank_top_bg_2.webp',
                ),
              ),
              const SizedBox(width: 4),

              // Rank 1 (Center - Elevated)
              Expanded(
                flex: 4,
                child: _buildPodiumSupporter(
                  item: top1,
                  rank: 1,
                  avatarSize: 70,
                  frameSize: 114,
                  frameAsset: 'assets/images/rank_top_avatar_1.webp',
                  baseAsset: 'assets/images/rank_top_bg_1.webp',
                  isCenter: true,
                ),
              ),
              const SizedBox(width: 4),

              // Rank 3 (Right)
              Expanded(
                flex: 3,
                child: _buildPodiumSupporter(
                  item: top3,
                  rank: 3,
                  avatarSize: 56,
                  frameSize: 96,
                  frameAsset: 'assets/images/rank_top_avatar_3.webp',
                  baseAsset: 'assets/images/rank_top_bg_3.webp',
                ),
              ),
            ],
          ),
        ),

        // Rest of ranking list (Rank 4+)
        if (restList.isNotEmpty) ...[
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: restList.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final s = restList[index];
              final rank = index + 4;
              return GestureDetector(
                onTap: () {
                  if (s.senderId.isNotEmpty && s.senderId != _user?.uid) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => UserProfileScreen(targetUid: s.senderId)),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F1E24),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          '#$rank',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF9BA1B6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        radius: 18,
                        backgroundImage: s.senderPhoto.isNotEmpty ? cachedImgProvider(s.senderPhoto) : null,
                        child: s.senderPhoto.isEmpty ? const Icon(Icons.person, color: Colors.white54, size: 18) : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.senderName,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'إجمالي الهدايا: ${s.totalGiftsCount}',
                              style: const TextStyle(fontSize: 10, color: Color(0xFF9BA1B6)),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0x22FFAE19),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0x44FFAE19)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.monetization_on, color: Color(0xFFFFAE19), size: 13),
                            const SizedBox(width: 3),
                            Text(
                              '${s.totalCoins}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFFAE19)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildPodiumSupporter({
    required SupporterRankInfo? item,
    required int rank,
    required double avatarSize,
    required double frameSize,
    required String frameAsset,
    required String baseAsset,
    bool isCenter = false,
  }) {
    final photoUrl = item?.senderPhoto ?? '';
    final name = item?.senderName ?? (item != null ? 'داعم' : 'شاغر');
    final coins = item?.totalCoins ?? 0;

    return GestureDetector(
      onTap: () {
        if (item != null && item.senderId.isNotEmpty && item.senderId != _user?.uid) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => UserProfileScreen(targetUid: item.senderId)),
          );
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar + Authentic Frame (rank_top_avatar_1..3)
          SizedBox(
            width: frameSize,
            height: frameSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipOval(
                  child: SizedBox(
                    width: avatarSize,
                    height: avatarSize,
                    child: photoUrl.isNotEmpty
                        ? CachedImg(photoUrl, width: avatarSize, height: avatarSize, fit: BoxFit.cover)
                        : Container(
                            color: Colors.white10,
                            child: Icon(Icons.person, color: Colors.white38, size: avatarSize * 0.5),
                          ),
                  ),
                ),
                Image.asset(
                  frameAsset,
                  width: frameSize,
                  height: frameSize,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),

          // Podium Base Image (rank_top_bg_1..3)
          Transform.translate(
            offset: const Offset(0, -10),
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Image.asset(
                  baseAsset,
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  errorBuilder: (_, __, ___) => const SizedBox(height: 20),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12, left: 4, right: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: isCenter ? 12 : 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      if (item != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.monetization_on, color: Color(0xFFFFD54F), size: 11),
                            const SizedBox(width: 2),
                            Text(
                              '$coins',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFFD54F),
                              ),
                            ),
                          ],
                        )
                      else
                        const Text(
                          'شاغر',
                          style: TextStyle(fontSize: 10, color: Colors.white38),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Empty state matching mine_layout_user_wall_empty
  Widget _buildEmptyWall(String tips) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/profile/mine_wallet_empty_ic.webp',
            width: 80,
            height: 80,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.inbox,
              size: 60,
              color: Colors.white24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tips,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF9BA1B6),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Existing ChatScreen & EditProfileScreenPlaceholder preserved below
// ─────────────────────────────────────────────────────────────────────────────
class EditProfileScreenPlaceholder extends StatelessWidget {
  const EditProfileScreenPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تعديل الملف الشخصي')),
      body: const Center(child: Text('شاشة تعديل الملف الشخصي')),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String targetUid;
  final String targetName;
  final String? targetPhotoUrl;

  const ChatScreen({
    super.key,
    required this.targetUid,
    required this.targetName,
    this.targetPhotoUrl,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SupabaseService _firebaseService = SupabaseService();
  List<MessageModel> _messages = [];
  bool _sendingImage = false;
  StreamSubscription? _messagesSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initConversation());
  }

  Future<void> _initConversation() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user == null) return;
    final sorted = [user.uid, widget.targetUid]..sort();
    final convId = '${sorted[0]}_${sorted[1]}';
    _messagesSub = _firebaseService.privateMessagesStream(convId).listen((msgs) {
      if (mounted) {
        setState(() => _messages = msgs);
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    });
    _firebaseService.markConversationRead(user.uid, convId);
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user == null) return;

    try {
      await _firebaseService.sendPrivateMessage(
        senderId: user.uid,
        senderName: user.name,
        senderPhotoUrl: user.photoUrl,
        receiverId: widget.targetUid,
        receiverName: widget.targetName,
        receiverPhotoUrl: widget.targetPhotoUrl ?? '',
        text: text,
      );
    } catch (e) {
      debugPrint('sendPrivateMessage error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message')),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (image == null) return;

    setState(() => _sendingImage = true);
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.currentUser;
      if (user == null) return;

      final imageUrl = await CloudinaryService().uploadImage(
        File(image.path),
        publicId: 'chat_${DateTime.now().millisecondsSinceEpoch}',
      );

      await _firebaseService.sendPrivateMessage(
        senderId: user.uid,
        senderName: user.name,
        senderPhotoUrl: user.photoUrl,
        receiverId: widget.targetUid,
        receiverName: widget.targetName,
        receiverPhotoUrl: widget.targetPhotoUrl ?? '',
        text: '',
        imageUrl: imageUrl,
        type: 'image',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingImage = false);
    }
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgImg = DynamicConfigService().chatBackgroundImage;
    return Container(
      decoration: BoxDecoration(
        color: DynamicConfigService().chatBackgroundColor,
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
          backgroundColor: Colors.white,
          elevation: 0,
          leading: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: R.image(R.backIc, width: 24, height: 24),
            ),
          ),
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: widget.targetPhotoUrl != null && widget.targetPhotoUrl!.isNotEmpty
                    ? cachedImgProvider(widget.targetPhotoUrl!)
                    : null,
                child: widget.targetPhotoUrl == null || widget.targetPhotoUrl!.isEmpty
                    ? const Icon(Icons.person, size: 18)
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                widget.targetName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF16151A),
                ),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? const Center(
                      child: Text(
                        'No messages yet',
                        style: TextStyle(color: Color(0xFF9BA1B6)),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final userProvider = Provider.of<UserProvider>(context, listen: false);
                        final isMe = msg.senderUid == userProvider.currentUser?.uid;
                        return _buildMessageBubble(msg, isMe);
                      },
                    ),
            ),
            if (_sendingImage)
              const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              ),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(MessageModel msg, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text(
                  msg.senderName,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9BA1B6)),
                ),
              ),
            if (msg.type == 'image' && msg.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GestureDetector(
                  onTap: () => _showImagePreview(msg.imageUrl!),
                  child: CachedImg(
                    msg.imageUrl!,
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    error: (_, __, ___) => Container(
                      width: 200,
                      height: 200,
                      color: Colors.white54,
                      child: const Icon(Icons.broken_image),
                    ),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isMe
                      ? DynamicConfigService().chatBubbleSelfBg
                      : DynamicConfigService().chatBubbleOtherBg,
                  borderRadius: BorderRadius.circular(12).copyWith(
                    bottomRight: isMe ? const Radius.circular(0) : null,
                    bottomLeft: !isMe ? const Radius.circular(0) : null,
                  ),
                ),
                child: Text(
                  msg.text,
                  style: TextStyle(
                    fontSize: 14,
                    color: isMe
                        ? Colors.white
                        : DynamicConfigService().chatTextColor,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _formatTime(msg.timestamp),
                style: const TextStyle(fontSize: 10, color: Color(0xFF9BA1B6)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8E8E8), width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F5FC),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.image, size: 20, color: Color(0xFF9BA1B6)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F5FC),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: _msgController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendMessage,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E90FF),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.send, size: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImagePreview(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: InteractiveViewer(
          child: CachedImg(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  String _formatTime(int? timestamp) {
    if (timestamp == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
