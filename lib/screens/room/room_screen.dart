import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'widgets/nine_patch_image.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/r.dart';
import '../../config/app_colors.dart';
import '../../models/room_model.dart';
import '../../models/message_model.dart';
import '../message/message_screen.dart';
import '../../models/user_model.dart' as app;
import '../../models/gift_model.dart' as gm;
import '../../models/gift_banner_config_model.dart';
import '../../models/store_item_model.dart';
import '../../services/supabase_service.dart';
import '../../services/media_prefetch_service.dart';
import '../../services/media_cache_service.dart';
import '../../services/dynamic_config_service.dart';
import '../../services/cloudinary_service.dart';
import '../../services/room_audio_service.dart';
import '../../services/room_state_service.dart';
import 'package:uuid/uuid.dart';
import '../../core/supabase_compat.dart';
import '../../providers/user_provider.dart';
import 'models/seat_model.dart' hide SeatStyle;
import 'models/seat_model.dart' as seat_model;
import 'room_settings_screen.dart';
import 'widgets/room_header.dart';
import 'widgets/seat_area.dart';
import 'widgets/room_rank_bottom_sheet.dart';

import 'widgets/room_background_bottom_sheet.dart';
import 'widgets/seat_dialogs.dart';
import 'widgets/seat_style_panel.dart';
import 'widgets/volume_panel.dart';
import 'widgets/mixer_panel.dart';
import 'widgets/bottom_bar.dart';
import 'widgets/gift_panel.dart';
import 'widgets/user_profile.dart';
import 'widgets/function_panel.dart';
import 'widgets/room_marquee_broadcast.dart';
import 'widgets/room_rocket_widget.dart';
import 'widgets/room_member_enter_banner.dart';
import 'widgets/room_message_bottom_sheet.dart';
import 'widgets/room_game_bottom_sheet.dart';
import 'widgets/room_music_bottom_sheet.dart';
import '../../features/lucky_gift/widgets/room_burst_settlement_dialog.dart';
import 'widgets/svga_player.dart'; // ✅ لاستخدام SvgaPlayer.prefetch قبل عرض الأنيميشن
import 'widgets/vap_player.dart'; // ✅ لاستخدام VapPlayer.prefetch قبل عرض الأنيميشن
import '../rank/rank_screen.dart';
import '../game/game_teaming_screen.dart';
import '../music/music_screen.dart';
import '../notifications/notifications_screen.dart';
import '../user_profile/user_profile_screen.dart';
import '../report/report_room_screen.dart';
import '../report/report_user_screen.dart';
import '../../features/lucky_gift/services/lucky_gift_service.dart';
import '../../features/lucky_gift/models/lucky_gift_model.dart';
import '../../features/lucky_gift/widgets/gift_seat_flight_overlay.dart';
import '../../features/lucky_bag/models/lucky_bag_model.dart';
import '../../features/lucky_bag/services/lucky_bag_service.dart';
import '../../features/lucky_bag/widgets/lucky_bag_send_dialog.dart';
import '../../features/lucky_bag/widgets/lucky_bag_claim_dialog.dart';
import '../../features/lucky_bag/widgets/lucky_bag_floating_widget.dart';
import '../../core/widgets/user_id_display_widget.dart';
import '../../widgets/user_id_widget.dart';
import 'package:just_audio/just_audio.dart';

/// Helper to navigate to a room, exiting any minimized room first
Future<void> navigateToRoom(
  BuildContext context, {
  required String roomName,
  required String hostName,
  required String roomId,
  String? hostUid,
  String roomPassword = '',
  String hotValue = '0',
  String gameDesc = '',
  bool replace = false,
}) async {
  // Double-tap guard: pushing two RoomScreens concurrently initializes the
  // audio engine twice and crashes natively (SIGSEGV in Zego engineInitJni).
  if (!RoomScreen.pushGuard(roomId)) return;
  final svc = MinimizedRoomService();
  final userProvider = Provider.of<UserProvider>(context, listen: false);
  final uid = userProvider.currentUser?.uid;
  bool isReentry = false;
  if (svc.isActive) {
    if (svc.roomId == roomId) {
      // Same room – don't exit, mark as re-entry
      isReentry = true;
      svc.deactivate();
    } else {
      // Different room – exit the old one
      if (uid != null) svc.exitRoom(uid);
    }
  }

  if (roomPassword.isNotEmpty && hostUid != uid) {
    String inputPassword = '';
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF211211),
          title: const Text('كلمة المرور مطلوبة', style: TextStyle(color: Colors.white)),
          content: TextField(
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'أدخل كلمة مرور الغرفة',
              hintStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFD3A350))),
            ),
            onChanged: (v) => inputPassword = v,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                if (inputPassword == roomPassword) {
                  Navigator.pop(ctx, true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('كلمة المرور غير صحيحة')));
                }
              },
              child: const Text('دخول', style: TextStyle(color: Color(0xFFD3A350))),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
  }

  if (!context.mounted) return;
  final route = MaterialPageRoute(
    builder: (_) => RoomScreen(
      roomName: roomName,
      hostName: hostName,
      roomId: roomId,
      roomPassword: roomPassword,
      hotValue: hotValue,
      gameDesc: gameDesc,
      isReentry: isReentry,
    ),
  );
  if (replace) {
    Navigator.pushReplacement(context, route);
  } else {
    Navigator.push(context, route);
  }
}

class _RoomGiftNotice {
  final String senderName;
  final String senderAvatar;
  final String receiverName;
  final String giftName;
  final int giftCount;
  final String iconAsset;
  final String defaultImage;

  _RoomGiftNotice({
    this.senderName = '',
    this.senderAvatar = '',
    this.receiverName = '',
    this.giftName = '',
    this.giftCount = 1,
    this.iconAsset = '',
    this.defaultImage = '',
  });
}

// fragment_chat_room.xml
class RoomScreen extends StatefulWidget {
  static DateTime _lastPushAt = DateTime.fromMillisecondsSinceEpoch(0);
  static String? _lastPushRoomId;

  /// Returns true if this push is allowed (debounces double-taps on the same
  /// room within 800ms, which would stack two RoomScreens and double-init Zego).
  static bool pushGuard(String roomId) {
    final now = DateTime.now();
    final dup = identical(_lastPushRoomId, roomId) &&
        now.difference(_lastPushAt).inMilliseconds < 800;
    if (dup) return false;
    _lastPushAt = now;
    _lastPushRoomId = roomId;
    return true;
  }

  final String roomName;
  final String hostName;
  final String roomId;
  final String roomPassword;
  final String hotValue;
  final String gameDesc;
  final bool isReentry;

  const RoomScreen({
    super.key,
    required this.roomName,
    required this.hostName,
    required this.roomId,
    this.roomPassword = '',
    this.hotValue = '0',
    this.gameDesc = '',
    this.isReentry = false,
  });

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> with WidgetsBindingObserver {
  // ── UI state ──────────────────────────────────────────────────
  bool _isMicOn = true;
  bool _showGift = false;
  final ValueNotifier<Map<String, dynamic>?> _giftAnimNotifier = ValueNotifier<Map<String, dynamic>?>(null);
  String? _giftAnimAsset;
  Timer? _giftAnimWatchdog;

  void _clearGiftAnim() {
    _giftAnimWatchdog?.cancel();
    _giftAnimWatchdog = null;
    if (_giftAnimNotifier.value != null) {
      _giftAnimNotifier.value = null;
      _giftAnimAsset = null; // ✅ نُصفِّر تماماً لضمان إعادة بناء SvgaPlayer عند الكومبو
      _giftTextReplacement = null;
      _giftImageReplacement = null;
      _giftDefaultImage = null;
    }
  }

  final Map<String, int> _recentGiftTimestamps = {};

  bool _isDuplicateGiftEvent(String senderId, String giftId) {
    if (senderId.isEmpty || giftId.isEmpty) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final key = '${senderId}_$giftId';
    if (_recentGiftTimestamps.containsKey(key)) {
      final last = _recentGiftTimestamps[key]!;
      if (now - last < 2500) {
        return true;
      }
    }
    _recentGiftTimestamps[key] = now;
    if (_recentGiftTimestamps.length > 200) {
      _recentGiftTimestamps.removeWhere((_, ts) => now - ts > 10000);
    }
    return false;
  }

  String? _resolveFrameAsset(String? activeFrame) {
    if (activeFrame == null || activeFrame.isEmpty) return null;
    if (activeFrame.startsWith('http://') || activeFrame.startsWith('https://') || activeFrame.startsWith('assets/')) {
      return activeFrame;
    }
    final item = _storeItemsIndex[activeFrame] ?? SupabaseService().getStoreItemSync(activeFrame);
    if (item != null) {
      if (item.svgaAsset != null && item.svgaAsset!.isNotEmpty) return item.svgaAsset;
      if (item.videoAsset != null && item.videoAsset!.isNotEmpty) return item.videoAsset;
      if (item.animationUrl != null && item.animationUrl!.isNotEmpty) return item.animationUrl;
      if (item.iconAsset.isNotEmpty) return item.iconAsset;
    }
    return null;
  }

  void _triggerGiftAnim(String asset, {Map<String, String>? textReplacement, Map<String, String>? imageReplacement, String? defaultImage}) {
    if (!_giftEffectsEnabled) return;
    _giftAnimWatchdog?.cancel();
    // ✅ مثل التطبيق الأصلي تماماً:
    // إذا كانت نفس الهدية قيد العرض بالفعل (مثل نقرات الكومبو السريعة)،
    // نترك الأنيميشن يكمل تشغيله بسلاسة ونمدد فقط مؤقت الأمان دون وميض أو تجميد الشاشة
    if (_giftAnimAsset == asset && _giftAnimNotifier.value != null) {
      _giftAnimWatchdog = Timer(const Duration(seconds: 12), () {
        _clearGiftAnim();
      });
      return;
    }
    // صمام أمان للروم: في حال تعطل ملف VAP/SVGA لا تعلق الغرفة أبداً
    _giftAnimWatchdog = Timer(const Duration(seconds: 12), () {
      _clearGiftAnim();
    });
    _giftAnimAsset = asset;
    _giftTextReplacement = textReplacement;
    _giftImageReplacement = imageReplacement;
    _giftDefaultImage = defaultImage;
    _giftAnimNotifier.value = {
      'asset': asset,
      'textReplacement': textReplacement,
      'imageReplacement': imageReplacement,
      'defaultImage': defaultImage,
    };
  }

  Map<String, String>? _buildTextReplacements({
    String? nameKeys,
    String? receiverNameKeys,
    String? countKeys,
    required String senderName,
    String receiverName = '',
    int count = 1,
  }) {
    final map = <String, String>{};
    void addKeys(String? raw, String val) {
      if (val.isEmpty) return;
      if (raw != null && raw.isNotEmpty) {
        for (final k in raw.split(',')) {
          final trimmed = k.trim();
          if (trimmed.isNotEmpty) {
            map[trimmed] = val;
            final clean = trimmed.replaceAll(RegExp(r'[\[\]\(\)]'), '');
            map[clean] = val;
            map['[$clean]'] = val;
          }
        }
      }
    }

    addKeys(nameKeys, senderName);
    if (senderName.isNotEmpty) {
      for (final def in ['txt_name', 'name', 'userName', 'sender_name', 'senderName', 'nickname', 'user_name', 'txt_username', 'txt_sender']) {
        map[def] = senderName;
        map['[$def]'] = senderName;
      }
    }

    addKeys(receiverNameKeys, receiverName);
    if (receiverName.isNotEmpty) {
      for (final def in ['receiver_name', 'target_name', 'txt_to', 'to_name', 'to_user', 'receiverName', 'targetName', 'txt_receiver']) {
        map[def] = receiverName;
        map['[$def]'] = receiverName;
      }
    }

    final countStr = count.toString();
    addKeys(countKeys, countStr);
    for (final def in ['count', 'gift_count', 'num', 'quantity', 'times', 'txt_count']) {
      map[def] = countStr;
      map['[$def]'] = countStr;
    }

    return map.isNotEmpty ? map : null;
  }

  Map<String, String>? _buildImageReplacements({
    String? photoKeys,
    String? receiverPhotoKeys,
    required String senderPhoto,
    String receiverPhoto = '',
  }) {
    final map = <String, String>{};
    void addKeys(String? raw, String val) {
      if (val.isEmpty) return;
      if (raw != null && raw.isNotEmpty) {
        for (final k in raw.split(',')) {
          final trimmed = k.trim();
          if (trimmed.isNotEmpty) {
            map[trimmed] = val;
            final clean = trimmed.replaceAll(RegExp(r'[\[\]\(\)]'), '');
            map[clean] = val;
            map['[$clean]'] = val;
          }
        }
      }
    }

    addKeys(photoKeys, senderPhoto);
    if (senderPhoto.isNotEmpty) {
      for (final def in ['img_avatar', 'avatar', 'user_avatar', 'sender_avatar', 'head', 'icon', 'senderAvatar', 'userAvatar', 'img_sender', 'photo']) {
        map[def] = senderPhoto;
        map['[$def]'] = senderPhoto;
      }
    }

    addKeys(receiverPhotoKeys, receiverPhoto);
    if (receiverPhoto.isNotEmpty) {
      for (final def in ['receiver_avatar', 'target_avatar', 'to_avatar', 'receiverAvatar', 'targetAvatar', 'img_receiver', 'img_to']) {
        map[def] = receiverPhoto;
        map['[$def]'] = receiverPhoto;
      }
    }

    return map.isNotEmpty ? map : null;
  }

  bool _showEntranceAnim = false;
  String? _entranceAnimAsset;

  // Dynamic SVGA data for entrance/car
  Map<String, String>? _entranceTextReplacement;
  Map<String, String>? _entranceImageReplacement;
  String? _entranceDefaultImage;

  // Dynamic SVGA data for entrance item (category 'entrance' above car)
  bool _showEntranceItemAnim = false;
  String? _entranceItemAnimAsset;
  Map<String, String>? _entranceItemTextReplacement;
  Map<String, String>? _entranceItemImageReplacement;
  String? _entranceItemDefaultImage;

  // Dynamic SVGA data for gift
  Map<String, String>? _giftTextReplacement;
  Map<String, String>? _giftImageReplacement;
  String? _giftDefaultImage;

  // Gift banner overlay state
  bool _showGiftBanner = false;
  String? _giftBannerAsset;
  String? _giftBannerSenderPhoto;
  String? _giftBannerReceiverPhoto;
  String? _giftBannerGiftImage;
  int _giftBannerCount = 1;
  String _giftBannerUserRKey = 'user_r';
  String _giftBannerUserLKey = 'user_l';
  String _giftBannerNumberKey = 'number';
  String _giftBannerGiftKey = 'gift';
  List<GiftBannerConfig> _bannerConfigs = [];

  // Flight overlay state for animated gifts arriving at seats
  bool _showGiftFlight = false;
  String _giftFlightIconUrl = '';
  List<Offset> _giftFlightTargets = [];
  Map<String, dynamic>? _pendingBannerData;

  // ── Floating Combo Button state ──
  Timer? _roomComboTimer;
  int _roomComboSeconds = 0;
  int _roomComboMultiplier = 0;
  bool _roomComboFiring = false;
  Map<String, dynamic>? _lastGiftComboData;
  // ✅ ValueNotifier للكومبو — يُعيد رسم زر الكومبو فقط دون لمس شجرة الـ Widget الكاملة
  final ValueNotifier<_ComboState> _comboNotifier = ValueNotifier(_ComboState(0, 0, false));

  // سجل إشعارات الهدايا للغرفة
  final List<_RoomGiftNotice> _sentGifts = [];

  // مشغل صوت الهدية والدخوليات والاهتزاز اللمسي
  AudioPlayer? _giftAudioPlayer;
  AudioPlayer? _entranceAudioPlayer;

  Future<void> _playGiftArrivalSound() async {
    try {
      HapticFeedback.lightImpact();
      _giftAudioPlayer ??= AudioPlayer();

      final remoteUrl = DynamicConfigService().getAssetUrl('gift_sound') ??
          DynamicConfigService().getAssetUrl('gift') ??
          DynamicConfigService().getAssetOverride('assets/sounds/key_music.mp3');

      if (remoteUrl != null && remoteUrl.isNotEmpty) {
        await _giftAudioPlayer!.setUrl(remoteUrl);
      } else {
        await _giftAudioPlayer!.setAsset('assets/sounds/key_music.mp3');
      }
      await _giftAudioPlayer!.setVolume(1.0);
      await _giftAudioPlayer!.seek(Duration.zero);
      await _giftAudioPlayer!.play();
    } catch (e) {
      debugPrint('[RoomScreen] gift sound error: $e');
      try {
        final player = AudioPlayer();
        await player.setAsset('assets/sounds/key_music.mp3');
        await player.setVolume(1.0);
        await player.play();
        player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            player.dispose();
          }
        });
      } catch (_) {}
    }
  }

  Future<void> _playEntranceSound({String? animAsset}) async {
    // إذا كان أنيميشن الدخول أو السيارة عبارة عن فيديو VAP / MP4، فإن VapPlayer يقوم بتشغيل الصوت المدمج في الفيديو نفسه
    // ولا نقوم بتشغيل أي صوت خارجي إطلاقاً حتى لا يتداخل صوت غريب لا ينتمي إلى الفيديو
    final checkAsset = animAsset ?? _entranceAnimAsset ?? _entranceItemAnimAsset;
    if (checkAsset != null && isVideoType(checkAsset)) {
      return;
    }

    try {
      final remoteUrl = DynamicConfigService().getAssetUrl('entrance_sound') ??
          DynamicConfigService().getAssetUrl('entrance') ??
          DynamicConfigService().getAssetUrl('car_sound');

      // إذا لم يكن هناك صوت مخصص محدد بشكل صريح، لا نشغل موسيقى عشوائية
      if (remoteUrl == null || remoteUrl.isEmpty) {
        return;
      }

      _entranceAudioPlayer ??= AudioPlayer();
      await _entranceAudioPlayer!.setUrl(remoteUrl);
      await _entranceAudioPlayer!.setVolume(1.0);
      await _entranceAudioPlayer!.seek(Duration.zero);
      await _entranceAudioPlayer!.play();
    } catch (e) {
      debugPrint('[RoomScreen] entrance sound error: $e');
    }
  }

  void _stopEntranceSound() {
    try {
      _entranceAudioPlayer?.stop();
    } catch (_) {}
  }

  // المعرف الرقمي لصاحب الغرفة
  String? _hostCustomId;
  void _resolveHostCustomId(String hostUid) {
    if (hostUid.isEmpty) return;
    if (UserProfile.customIdCache.containsKey(hostUid)) {
      _hostCustomId = UserProfile.customIdCache[hostUid];
      return;
    }
    for (final s in _seats) {
      if (s.user?.id == hostUid && s.user?.customId != null && s.user!.customId!.isNotEmpty) {
        _hostCustomId = s.user!.customId;
        UserProfile.customIdCache[hostUid] = _hostCustomId!;
        return;
      }
    }
    SupabaseService().getUser(hostUid).then((u) {
      if (u != null && u.customId.isNotEmpty && mounted) {
        UserProfile.customIdCache[hostUid] = u.customId;
        setState(() {
          _hostCustomId = u.customId;
        });
      }
    }).catchError((_) {});
  }

  void _startRoomComboTimer(Map<String, dynamic> giftData) {
    _lastGiftComboData = giftData;
    _roomComboTimer?.cancel();
    _roomComboMultiplier = (_roomComboSeconds > 0) ? _roomComboMultiplier + 1 : 1;
    _roomComboSeconds = 10;
    // ✅ بدلاً من setState كامل — نُعلم ValueNotifier فقط لإعادة رسم زر الكومبو وحده
    _comboNotifier.value = _ComboState(_roomComboSeconds, _roomComboMultiplier, _roomComboFiring);
    // مؤقت واحد بعد 10 ثوانٍ لإخفاء الزر
    _roomComboTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      _roomComboSeconds = 0;
      _roomComboMultiplier = 0;
      _lastGiftComboData = null;
      _comboNotifier.value = _ComboState(0, 0, false);
    });
  }

  void _onRoomComboTap() {
    if (_lastGiftComboData == null || _currentUserId == null) return;

    // ✅ إعادة ضبط مؤقت الـ 10 ثوانٍ مع كل ضغطة كومبو (مثل التطبيق الأصلي تماماً restartCountdown)
    // حتى لا يختفي الزر أثناء الضغط المتتالي
    _roomComboTimer?.cancel();
    _roomComboSeconds = 10;
    _roomComboMultiplier++;
    _roomComboFiring = true;
    _comboNotifier.value = _ComboState(_roomComboSeconds, _roomComboMultiplier, true);

    _roomComboTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      _roomComboSeconds = 0;
      _roomComboMultiplier = 0;
      _lastGiftComboData = null;
      _comboNotifier.value = _ComboState(0, 0, false);
    });

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _roomComboFiring = false;
        _comboNotifier.value = _ComboState(_roomComboSeconds, _roomComboMultiplier, false);
      }
    });

    final data = _lastGiftComboData!;
    final iconUrl = data['defaultImage']?.toString() ?? data['animationAsset']?.toString() ?? '';
    if (iconUrl.isNotEmpty) {
      _triggerGiftFlight(
        iconUrl: iconUrl,
        receiverId: data['receiverId']?.toString(),
        receiverIds: (data['receiverIds'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      );
    }

    // ✅ تشغيل أو تمديد أنيميشن الهدية فوراً دون حظر واجهة المستخدم
    final animAsset = data['animationAsset']?.toString() ?? '';
    final defImg    = data['defaultImage']?.toString();
    final senderPhoto = data['senderPhotoUrl']?.toString();
    final nameKey   = data['nameKey']?.toString();
    final photoKey  = data['photoKey']?.toString();
    final senderName = data['senderName']?.toString() ?? '';
    final textRepl = _buildTextReplacements(
      nameKeys: nameKey,
      senderName: senderName,
      count: data['giftCount'] as int? ?? 1,
    );
    final imgRepl = _buildImageReplacements(
      photoKeys: photoKey,
      senderPhoto: senderPhoto ?? '',
    );

    if (animAsset.isNotEmpty && mounted) {
      _triggerGiftAnim(
        animAsset,
        textReplacement: textRepl,
        imageReplacement: imgRepl,
        defaultImage: defImg,
      );
    }

    // ✅ إرسال الهدية عبر الشبكة بشكل غير متزامن تماماً (fire-and-forget background coroutine)
    // مثل الأصل (Dispatchers.IO) دون حظر الواجهة لسرعة إرسال فائقة
    final gift = data['gift'] as gm.GiftModel?;
    final selectedTargets = (data['selectedTargets'] as List<dynamic>?) ?? [];
    if (gift != null && widget.roomId.isNotEmpty) {
      final roomId = widget.roomId;
      final comboMultiplier = _roomComboMultiplier;
      final count = data['giftCount'] as int? ?? 1;
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.currentUser;
      final totalCost = gift.value * count * (selectedTargets.isNotEmpty ? selectedTargets.length : 1);

      if ((user?.coins ?? 0) < totalCost) {
        return; // رصيد غير كافٍ للكومبو
      }

      // خصم فوري في الذاكرة لسرعة استجابة فائقة
      userProvider.deductCoinsLocally(totalCost);

      unawaited(Future.microtask(() async {
        final fb = SupabaseService();
        await Future.wait(selectedTargets.map((r) async {
          final receiverId = r['id']?.toString() ?? '';
          final receiverName = r['name']?.toString() ?? '';
          if (gift.isLucky || gift.type == 3) {
            final cover = gift.defaultImage ?? gift.iconAsset;
            final cardCount = count.clamp(1, 10);
            final drawn = fb.drawLuckyMultipliers(cardCount);
            final totalWon = drawn.fold<int>(0, (total, m) => total + (gift.value * m));
            final maxMult = drawn.isEmpty ? 0 : drawn.reduce((a, b) => a > b ? a : b);
            final cards = List.generate(drawn.length, (i) => LuckyCardResult(
              index: i,
              multiplier: drawn[i],
              wonCoins: gift.value * drawn[i],
              giftName: gift.name,
              giftIcon: gift.iconAsset,
            ));
            final luckyModel = LuckyGiftModel(
              id: gift.id,
              giftName: gift.name,
              giftNameAr: gift.name,
              coinPrice: gift.value,
              giftIconUrl: gift.iconAsset,
              giftCoverUrl: cover,
              giftBgUrl: cover,
              svgaAnimUrl: gift.animationAsset,
            );
            final comboId = 'combo_${DateTime.now().millisecondsSinceEpoch}';
            final localData = LuckyGiftBroadcastData(
              roomId: roomId,
              senderName: user?.name ?? '',
              senderAvatar: user?.photoUrl ?? '',
              receiverName: receiverName,
              gift: luckyModel,
              cards: cards,
              totalWonCoins: totalWon,
              maxMultiplier: maxMult,
              isBigWin: maxMult >= 50,
              comboId: comboId,
              comboCount: comboMultiplier,
            );

            // عرض فوري لحظي للمرسل بدون أي تأخير في الشبكة (0ms latency)
            if (mounted) {
              LuckyGiftService().enqueueLuckyGift(context, localData);
            }

            await fb.sendLuckyGift(
              roomId: roomId,
              giftId: gift.id,
              giftName: gift.name,
              giftNameAr: gift.name,
              giftIconUrl: gift.iconAsset,
              giftCoverUrl: cover,
              giftBgUrl: cover,
              svgaAnimUrl: gift.animationAsset,
              senderId: user?.uid ?? '',
              senderName: user?.name ?? '',
              senderPhotoUrl: user?.photoUrl ?? '',
              receiverId: receiverId,
              receiverName: receiverName,
              value: gift.value,
              count: count,
              comboId: comboId,
              comboCount: comboMultiplier,
              preDrawnMultipliers: drawn,
            );
          } else {
            final cover = gift.defaultImage ?? gift.iconAsset;
            await fb.sendGift(
              roomId: roomId,
              giftId: gift.id,
              giftName: gift.name,
              animationAsset: gift.animationAsset,
              defaultImage: cover,
              senderId: user?.uid ?? '',
              senderName: user?.name ?? '',
              senderPhotoUrl: user?.photoUrl ?? '',
              receiverId: receiverId,
              receiverName: receiverName,
              value: gift.value,
              count: count,
            );
          }
        }));
      }));
    }
  }

  void _triggerGiftFlight({
    required String iconUrl,
    String? receiverId,
    List<String>? receiverIds,
  }) {
    final screenSize = MediaQuery.of(context).size;
    final statusH = MediaQuery.of(context).padding.top;
    final startOffset = Offset(screenSize.width * 0.8, screenSize.height - 60);
    final targets = <Offset>[];

    final headerH = statusH + 50.0;
    final colWidth = (screenSize.width - 16.0) / 5.0;
    const rowHeight = 94.0;

    final targetIds = <String>{};
    if (receiverIds != null && receiverIds.isNotEmpty) {
      targetIds.addAll(receiverIds.where((id) => id.isNotEmpty));
    } else if (receiverId != null && receiverId.isNotEmpty) {
      targetIds.add(receiverId);
    }

    if (targetIds.isNotEmpty) {
      for (final id in targetIds) {
        final seatIdx = _seats.indexWhere((s) => s.user?.id == id);
        if (seatIdx >= 0) {
          final row = seatIdx ~/ 5;
          final col = seatIdx % 5;
          final targetX = 8.0 + (col * colWidth) + (colWidth / 2.0);
          final targetY = headerH + 6.0 + (row * rowHeight) + 38.0;
          targets.add(Offset(targetX, targetY));
        }
      }
    } else {
      // All occupied seats
      for (int i = 0; i < _seats.length; i++) {
        if (_seats[i].isOccupied && _seats[i].user != null) {
          final row = i ~/ 5;
          final col = i % 5;
          final targetX = 8.0 + (col * colWidth) + (colWidth / 2.0);
          final targetY = headerH + 6.0 + (row * rowHeight) + 38.0;
          targets.add(Offset(targetX, targetY));
        }
      }
    }

    if (targets.isEmpty) {
      targets.add(Offset(screenSize.width / 2.0, headerH + 60.0));
    }

    if (mounted) {
      setState(() {
        _giftFlightIconUrl = iconUrl;
        _giftFlightTargets = targets;
        _showGiftFlight = true;
      });
    }
  }

  // Cached gift definitions for looking up dynamic keys
  final Map<String, gm.GiftModel> _cachedGiftItems = {};
  bool _hasPlayedEntryAnimations = false;
  bool _showFunction = false;
  bool _showEmoj = false;
  bool _showChatInput = false;
  bool _showProfile = false;
  bool _showRoomInfo = false;
  bool _showExit = false;
  bool _showNotifications = false;
  bool _showShare = false;
  bool _isMinimized = false;
  bool _isFollowed = false;
  int _msgCount = 0;
  final List<MessageModel> _chatMessages = [];
  int _giftCount = 1;
  int _onlineCount = 0;

  final SupabaseService _firebaseService = SupabaseService();

  // Store items index for resolving frame/bubble/car assets
  Map<String, StoreItemModel> _storeItemsIndex = {};
  StreamSubscription? _storeSub;

  // Cache of user data for frame asset resolution
  final Map<String, app.UserModel> _cachedUsers = {};

  // currently selected seat index for profile/actions
  int? _selectedSeatIdx;
  UserModel? _selectedUser;

  final Map<int, String> _seatEmojis = {};
  bool _showCharmValues = true;
  bool _giftEffectsEnabled = true;
  // Track followed users
  final Set<String> _followedUsers = {};
  // Track blocked users
  final Set<String> _blockedUsers = {};

  final _chatCtrl = TextEditingController();
  final _chatScroll = ScrollController();
  DateTime? _joinedAt;

  // ── 20 seats: index 0 = owner, 1-19 = regular ─────────────────
  late List<SeatModel> _seats;

  // Current user is owner
  bool _isOwner = false;
  final Set<String> _moderators = {};
  String? _currentUserId;
  String? _currentUserName;
  bool get _isOwnerOrModerator => _isOwner || _moderators.contains(_currentUserId);
  seat_model.SeatStyle _roomSeatStyle = seat_model.SeatStyle.circle;

  // Current room data
  RoomModel? _currentRoom;

  // Track seen entrance message IDs to avoid replaying
  final Set<String> _seenEntranceIds = {};

  // Track total gifts received per seat user ID
  final Map<String?, int> _giftReceiverTotals = {};
  StreamSubscription? _giftSub;
  StreamSubscription? _seatsSub;
  StreamSubscription? _roomSub;
  StreamSubscription? _giftCacheSub;
  StreamSubscription? _bannerConfigSub;
  StreamSubscription? _msgSub;
  StreamSubscription? _entranceSub;
  StreamSubscription? _userBanSub;
  StreamSubscription? _broadcastSub;
  Map<String, dynamic>? _currentBroadcast;
  final ValueNotifier<Map<String, dynamic>?> _broadcastNotifier = ValueNotifier<Map<String, dynamic>?>(null);
  final ValueNotifier<Map<String, dynamic>?> _giftBannerNotifier = ValueNotifier<Map<String, dynamic>?>(null);
  final ValueNotifier<int> _chatUpdateNotifier = ValueNotifier<int>(0);
  Map<String, dynamic>? _currentEnterMember;
  Timer? _seatsRefreshTimer;
  Timer? _bannerHideTimer;
  Timer? _presencePingTimer; // ✅ ping دوري للـ presence — يكتشف الخروج الصامت
  final RoomAudioService _roomAudio = RoomAudioService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
    _seats = _buildInitialSeats();
    // ✅ تأجيل العمليات الثقيلة (Firestore، Audio، Zombie cleanup) إلى ما بعد
    //    أول إطار مكتمل — يمنع "Skipped N frames!" عند فتح الغرفة.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadRoomData();
      _startPresencePing();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Pause resource-heavy animation/audio when the app is in the background
    // (SIGSEGV / battery drain protection). Animations are re-triggered via
    // the gift/message subscriptions when the room becomes active again.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _roomAudio.pauseForBackground();
      // ✅ تحديث ping عند التوقف — الـ TTL checker سيرى آخر ping
      _updatePresencePing();
    } else if (state == AppLifecycleState.resumed) {
      _roomAudio.resumeFromBackground();
      // ✅ تجديد الـ ping عند العودة
      _updatePresencePing();
    } else if (state == AppLifecycleState.detached) {
      // ✅ التطبيق يُغلق كلياً — نظّف المستخدم فوراً من الغرفة
      if (!_isMinimized) {
        _cleanupUserSession();
      }
    }
  }

  void _loadRoomData() {
    _joinedAt = DateTime.now();
    LuckyGiftService().disposeAllOverlays();
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentUser = userProvider.currentUser;
    if (currentUser != null) {
      _currentUserId = currentUser.uid;
      _currentUserName = currentUser.name;
      _isOwner = false;
      _isFollowed = currentUser.followedRooms.contains(widget.roomId);
      _checkRoomBan(currentUser.uid);
      _userBanSub?.cancel();
      _userBanSub = _firebaseService.userRoomBanStream(widget.roomId, currentUser.uid).listen((isBanned) {
        if (isBanned && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حظرك من هذه الغرفة بواسطة المشرف'),
              duration: Duration(seconds: 4),
              backgroundColor: Colors.red,
            ),
          );
          _exitRoom();
        }
      });
      // Clear any stale seats for this user before registering (await to avoid race)
      // Only on fresh joins – on minimized-room re-entry the current seat must survive.
      if (!widget.isReentry) {
        Future(() async {
          await _firebaseService.leaveSeatForUser(widget.roomId, currentUser.uid);
        });
      }
      // Register in Firebase so others see this user
      _firebaseService.joinRoom(widget.roomId, currentUser);
      // ✅ تنظيف المستخدمين الصامتين (Zombie) عند الانضمام
      // أي مستخدم آخر لم يرسل ping منذ أكثر من 5 دقائق يُعتبر خارجاً
      _cleanupZombieUsers();
      if (!widget.isReentry) {
        try {
          // Log entrance effect for other users to see
          _firebaseService.logEntrance(
            widget.roomId,
            currentUser.uid,
            currentUser.name,
            currentUser.photoUrl,
            currentUser.activeEntrance,
            carItem: currentUser.activeCar,
          );
        } catch (e) {
          debugPrint('logEntrance error: $e');
        }
      } else {
        _hasPlayedEntryAnimations = true;
      }
      // Load blocked users list
      _firebaseService.getBlockedUids(currentUser.uid).then((list) {
        if (mounted) setState(() { _blockedUsers.clear(); _blockedUsers.addAll(list); });
      });
    }
    // Initialize audio service (use customId for Zego, not real uid)
    final audioUid = (Provider.of<UserProvider>(context, listen: false).currentUser?.customId)
        ?? _currentUserId?.replaceAll('-', '').substring(0, 7) ?? '0';
    _roomAudio.initialize().then((ok) {
      if (ok) _roomAudio.joinChannel(widget.roomId, audioUid);
    });
    // Cache gift definitions for dynamic SVGA key lookup
    _giftCacheSub = _firebaseService.giftsStream().listen((gifts) {
      if (!mounted) return;
      for (final g in gifts) {
        _cachedGiftItems[g.id] = g;
      }
      MediaPrefetchService().prefetchGifts(gifts);
    });

    // Load gift banner configs
    _bannerConfigSub = _firebaseService.giftBannerConfigsStream().listen((configs) {
      if (mounted) {
        setState(() => _bannerConfigs = configs.where((c) => c.isActive).toList());
      }
      // Pre-cache the banner SVGA/VAP files so the first play is instant
      MediaPrefetchService()
          .prefetchUrls(configs.where((c) => c.isActive).map((c) => c.svgaUrl));
    });

    _roomSub = _firebaseService.roomStream(widget.roomId).listen((room) {
      if (room != null && mounted) {
        setState(() {
          _currentRoom = room;
          _isOwner = _currentUserId == room.hostUid;
          _onlineCount = room.memberCount;
          _moderators
            ..clear()
            ..addAll(room.moderators);
          if (room.seatCount != _seats.length) {
            _seats = List.generate(room.seatCount, (i) => SeatModel(index: i));
          }
          _roomSeatStyle = room.seatStyle;
        });
        _resolveHostCustomId(room.hostUid);
      }
    });

    final joinedMs = _joinedAt?.millisecondsSinceEpoch ?? 0;
    final seenMsgIds = <String>{};
    bool _msgStreamInitial = true;

    _broadcastSub = _firebaseService.globalBroadcastStream().listen((broadcasts) {
      if (!mounted || broadcasts.isEmpty) return;
      final latest = broadcasts.first;
      final createdAt = DateTime.tryParse(latest['created_at']?.toString() ?? '');
      if (createdAt != null && DateTime.now().difference(createdAt).inSeconds < 15) {
        final bId = latest['id']?.toString() ?? '${createdAt.millisecondsSinceEpoch}_${latest['sender_uid']}';
        if (!seenMsgIds.contains(bId)) {
          seenMsgIds.add(bId);
          _currentBroadcast = latest;
          _broadcastNotifier.value = latest;

          // ✅ عرض الهدية/الفوز مباشرة في شات وتعليقات الغرفة تزامناً مع البانر
          final isLucky = latest['is_lucky'] == true || (latest['multiplier'] != null && (latest['multiplier'] as num) > 0);
          _chatMessages.add(MessageModel(
            msgId: bId,
            roomId: widget.roomId,
            senderUid: latest['sender_uid']?.toString() ?? '',
            senderName: latest['sender_name']?.toString() ?? 'مستخدم',
            senderPhotoUrl: latest['sender_photo_url']?.toString() ?? '',
            text: latest['content']?.toString() ?? '',
            type: isLucky ? 'lucky_gift' : 'gift',
            timestamp: DateTime.now().millisecondsSinceEpoch,
            imageUrl: latest['gift_icon']?.toString() ?? '',
            giftPayload: {
              'gift_name': latest['gift_name'] ?? '',
              'gift_icon': latest['gift_icon'] ?? '',
              'count': latest['count'] ?? 1,
              'receiver_name': latest['receiver_name'] ?? '',
              'results': {
                'totalWonCoins': latest['won_coins'] ?? latest['coins'] ?? 0,
                'maxMultiplier': latest['multiplier'] ?? 0,
              },
              'gift': {
                'giftName': latest['gift_name'] ?? '',
                'giftNameAr': latest['gift_name'] ?? '',
              },
            },
          ));
          _msgCount = _chatMessages.length;
          _chatUpdateNotifier.value++;
          if (_chatScroll.hasClients) {
            _chatScroll.animateTo(
              _chatScroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        }
      }
    });

    _msgSub = _firebaseService.messagesStream(widget.roomId).listen((msgs) {
      if (mounted) {
        final clearedAt = _currentRoom?.chatClearedAt ?? 0;
        final filterTime = max(joinedMs - 5000, clearedAt);
        final currentSessionMsgs = msgs.where((m) => m.timestamp >= filterTime).toList();
        _chatMessages
          ..clear()
          ..addAll(currentSessionMsgs);
        _msgCount = _chatMessages.length;
        _chatUpdateNotifier.value++;

        // إذا كانت هذه المرة الأولى عند دخول الغرفة، نعتبر كافة الرسائل السابقة شوهدت بالفعل
        // لمنع تشغيل مضاعفات الحظ أو مؤثرات الهدايا القديمة إطلاقاً
        if (_msgStreamInitial) {
          for (final m in msgs) {
            final mId = m.msgId.isNotEmpty ? m.msgId : '${m.timestamp}_${m.senderUid}';
            seenMsgIds.add(mId);
          }
          _msgStreamInitial = false;
          return;
        }

        // عرض هدايا الحظ (lucky_gift) والهدايا العادية (gift) والمظاريف الحمراء (lucky_bag) لكافة أعضاء الغرفة لحظياً للرسائل الجديدة فقط
        for (final m in currentSessionMsgs) {
          if (m.timestamp < joinedMs) continue;
          final mId = m.msgId.isNotEmpty ? m.msgId : '${m.timestamp}_${m.senderUid}';
          if (seenMsgIds.contains(mId)) continue;
          seenMsgIds.add(mId);

          if (m.type == 'gift') {
            if (m.senderUid != _currentUserId) {
              final payload = m.giftPayload ?? {};
              final giftId = payload['gift_id']?.toString() ?? '';
              final giftDef = _cachedGiftItems[giftId];
              final isLucky = giftDef?.isLucky == true || giftDef?.type == 3 || giftDef?.categoryId == 'lucky';

              if (!isLucky && (giftId.isEmpty || !_isDuplicateGiftEvent(m.senderUid, giftId))) {
                final flyIcon = (payload['default_image']?.toString().isNotEmpty == true)
                    ? payload['default_image'].toString()
                    : ((payload['gift_icon']?.toString().isNotEmpty == true)
                        ? payload['gift_icon'].toString()
                        : (giftDef?.defaultImage ?? giftDef?.iconAsset ?? ''));
                final receiverId = payload['receiver_id']?.toString();
                if (flyIcon.isNotEmpty && receiverId != null && receiverId.isNotEmpty) {
                  _triggerGiftFlight(
                    iconUrl: flyIcon,
                    receiverId: receiverId,
                  );
                }

                final animAsset = (payload['animation_asset']?.toString().isNotEmpty == true)
                    ? payload['animation_asset'].toString()
                    : (giftDef?.animationAsset ?? giftDef?.defaultImage ?? giftDef?.iconAsset);

                if (animAsset != null && animAsset.isNotEmpty) {
                  final textRepl = _buildTextReplacements(
                    nameKeys: giftDef?.nameKey ?? payload['name_key']?.toString() ?? payload['nameKey']?.toString(),
                    receiverNameKeys: giftDef?.receiverNameKey ?? payload['receiver_name_key']?.toString(),
                    countKeys: giftDef?.countKey ?? payload['count_key']?.toString(),
                    senderName: m.senderName,
                    receiverName: payload['receiver_name']?.toString() ?? '',
                    count: (payload['count'] as num?)?.toInt() ?? 1,
                  );

                  final imgRepl = _buildImageReplacements(
                    photoKeys: giftDef?.photoKey ?? payload['photo_key']?.toString() ?? payload['photoKey']?.toString(),
                    receiverPhotoKeys: giftDef?.receiverPhotoKey ?? payload['receiver_photo_key']?.toString(),
                    senderPhoto: m.senderPhotoUrl,
                    receiverPhoto: payload['receiver_photo_url']?.toString() ?? '',
                  );

                  _triggerGiftAnim(
                    animAsset,
                    textReplacement: textRepl,
                    imageReplacement: imgRepl,
                    defaultImage: flyIcon,
                  );
                }

                _playGiftArrivalSound();

                final coinVal = (payload['coin_value'] as num?)?.toInt() ?? (giftDef?.value ?? 0);
                final count = (payload['count'] as num?)?.toInt() ?? 1;
                _checkGiftBanner({
                  'giftValue': coinVal,
                  'giftCount': count,
                  'categoryId': giftDef?.categoryId,
                  'senderPhotoUrl': m.senderPhotoUrl,
                  'defaultImage': flyIcon,
                  'receiverId': receiverId,
                  'isLucky': false,
                });
              }
            }
          } else if (m.type == 'lucky_gift' && m.giftPayload != null) {
            try {
              if (m.senderUid != _currentUserId) {
                final data = LuckyGiftBroadcastData.fromJson(m.giftPayload!);
                LuckyGiftService().enqueueLuckyGift(context, data);
              }
            } catch (_) {}
          } else if (m.type == 'lucky_bag' && m.luckyBagPayload != null) {
            try {
              final bag = LuckyBagModel.fromJson(m.luckyBagPayload!);
              LuckyBagService().showGrabBanner(
                context,
                roomId: widget.roomId,
                bag: bag,
                onOpenDialog: () {
                  LuckyBagClaimDialog.show(context, bag: bag, roomId: widget.roomId);
                },
              );
            } catch (_) {}
          } else if (m.type == 'entrance') {
            final isExit = m.text.contains('left') || m.text.contains('غادر');
            if (!isExit && m.senderUid != _currentUserId) {
              _showMemberEnterBanner(m.senderName, m.senderPhotoUrl);
            }
          } else if (m.type == 'room_kick' && m.giftPayload != null) {
            final kickedUid = m.giftPayload!['kickedUid']?.toString();
            if (kickedUid == _currentUserId && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(m.text.isNotEmpty ? m.text : 'تم طردك من الغرفة من قبل المشرف'),
                  duration: const Duration(seconds: 4),
                  backgroundColor: Colors.red,
                ),
              );
              _exitRoom();
              return;
            }
          }
        }
        if (_chatScroll.hasClients) {
          _chatScroll.animateTo(
            _chatScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      }
    });
    // Track gifts to update seat charm values
    final seenGiftIds = <String>{};
    bool _giftStreamInitial = true;
    _giftSub = _firebaseService.sentGiftsStream(widget.roomId).listen((gifts) {
      final totals = <String?, int>{};
      gm.SentGiftModel? latestNewGift;
      for (final g in gifts) {
        totals[g.receiverId] = (totals[g.receiverId] ?? 0) + g.totalValue.toInt();
        if (!seenGiftIds.contains(g.id)) {
          seenGiftIds.add(g.id);
          if (!_giftStreamInitial) latestNewGift = g;
        }
      }
      _giftStreamInitial = false;
      // Show gift animation for the newest unseen gift
      // FIX: Only show normal gift animation for non-lucky gifts
      // Lucky gifts are handled separately by LuckyGiftService via messages stream
      if (latestNewGift != null) {
        final latest = latestNewGift;
        final giftDef = _cachedGiftItems[latest.giftId];
        
        // TODO: Critical fix - Check if gift is lucky before showing normal animation
        // Lucky gifts (isLucky == true or type == 3) should NOT trigger normal gift animation
        // They are handled by LuckyGiftService through the messages stream
        final isLuckyGift = giftDef != null && (giftDef.isLucky || giftDef.type == 3);
        
        if (!isLuckyGift && !_isDuplicateGiftEvent(latest.senderId, latest.giftId)) {
          // ── طيران الهدية إلى مقعد المستلم لكافة المتواجدين في الغرفة ──
          final flyIcon = (latest.defaultImage != null && latest.defaultImage!.isNotEmpty)
              ? latest.defaultImage!
              : ((latest.iconAsset != null && latest.iconAsset!.isNotEmpty)
                  ? latest.iconAsset!
                  : (giftDef?.defaultImage ?? giftDef?.iconAsset ?? ''));
          if (flyIcon.isNotEmpty && mounted && latest.senderId != _currentUserId) {
            _triggerGiftFlight(
              iconUrl: flyIcon,
              receiverId: latest.receiverId,
            );
          }

          // ── أنيميشن الهدية أو صورتها الكبيرة ──
          final effectiveAsset = (latest.animationAsset != null && latest.animationAsset!.isNotEmpty)
              ? latest.animationAsset
              : ((latest.defaultImage != null && latest.defaultImage!.isNotEmpty)
                  ? latest.defaultImage
                  : ((latest.iconAsset != null && latest.iconAsset!.isNotEmpty)
                      ? latest.iconAsset
                      : (giftDef?.iconAsset ?? giftDef?.defaultImage)));

          if (effectiveAsset != null && effectiveAsset.isNotEmpty) {
            final nameKey = giftDef?.nameKey;
            final photoKey = giftDef?.photoKey;
            final defaultImage = latest.defaultImage ?? latest.iconAsset ?? giftDef?.defaultImage ?? giftDef?.iconAsset;
            final textReplacement = nameKey != null && nameKey.isNotEmpty && latest.senderName.isNotEmpty
                ? <String, String>{nameKey: latest.senderName}
                : null;
            final imageReplacement = photoKey != null && photoKey.isNotEmpty && latest.senderPhotoUrl != null && latest.senderPhotoUrl!.isNotEmpty
                ? <String, String>{photoKey: latest.senderPhotoUrl!}
                : null;
            if (mounted && latest.senderId != _currentUserId) {
              _triggerGiftAnim(
                effectiveAsset,
                textReplacement: textReplacement,
                imageReplacement: imageReplacement,
                defaultImage: defaultImage,
              );
            }
          }

          // ── تشغيل صوت الهدية والاهتزاز اللمسي لتأكيد الاستلام لدى الجميع ──
          _playGiftArrivalSound();
        }
        // If isLuckyGift == true, we skip normal animation here
        // Lucky gift animations are handled by LuckyGiftService through messages stream
      }
      // Show gift banner strip for ALL users (not just sender), regardless of animation
      // Important: Lucky gifts have their own multiplier strip and MUST NOT trigger normal gift banner!
      if (latestNewGift != null && mounted) {
        final giftDef = _cachedGiftItems[latestNewGift.giftId];
        final isLucky = giftDef?.isLucky == true || giftDef?.type == 3 || giftDef?.categoryId == 'lucky';
        if (!isLucky) {
          _checkGiftBanner({
            'giftValue': latestNewGift.value,
            'giftCount': latestNewGift.count,
            'categoryId': giftDef?.categoryId,
            'senderPhotoUrl': latestNewGift.senderPhotoUrl,
            'defaultImage': giftDef?.defaultImage,
            'receiverId': latestNewGift.receiverId,
            'isLucky': false,
          });
        }
      }
      // Update charm totals for all seats
      if (mounted) {
        setState(() {
          _giftReceiverTotals.clear();
          _giftReceiverTotals.addAll(totals);
          // Update seat charm values
          for (final seat in _seats) {
            if (seat.user != null && _giftReceiverTotals.containsKey(seat.user!.id)) {
              seat.user = seat.user!.copyWith(
                giftCount: _giftReceiverTotals[seat.user!.id]!,
                totalGiftsReceived: _giftReceiverTotals[seat.user!.id]!,
                charm: _giftReceiverTotals[seat.user!.id].toString(),
              );
            }
          }
        });
      }
    });
    // Sync seats from Firebase in real time
    _seatsSub = _firebaseService.seatsStream(widget.roomId).listen((seatMap) {
      _processSeatMap(seatMap);
    });

    // Periodic refresh as fallback in case Realtime misses updates
    _seatsRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted) return;
      try {
        final list = await Supabase.instance.client
            .from('room_seats')
            .select()
            .eq('room_id', widget.roomId);
        final seatMap = <int, Map<String, dynamic>>{};
        for (final e in list) {
          seatMap[(e['seat_index'] as int?) ?? 0] = Map<String, dynamic>.from(e);
        }
        if (!mounted) return;
        _processSeatMap(seatMap);
      } catch (_) {}
    });

    // Buffer for entrance animations that arrive before store items are loaded
    final _pendingEntrances = <Map<String, dynamic>>[];

    // Index store items for resolving frame/bubble/entrance assets
    _storeSub = _firebaseService.storeItemsStream().listen((items) {
      MediaPrefetchService().prefetchStoreItems(items);
      final index = <String, StoreItemModel>{};
      for (final item in items) {
        index[item.itemId] = item;
      }
      _storeItemsIndex = index;
      // Re-derive assets for all occupied seats (live updates from dashboard)
      for (int i = 0; i < _seats.length; i++) {
        final seat = _seats[i];
        if (seat.state == SeatState.occupied && seat.user?.id != null) {
          final cachedUser = _cachedUsers[seat.user!.id!];
          if (cachedUser != null) {
            final af = cachedUser.activeFrame;
            final frameAsset = _resolveFrameAsset(af);
            final carVal = cachedUser.activeCar;
            final carStoreItem = carVal != null && !carVal.startsWith('http')
                ? index[carVal]
                : null;
            final carAsset = carVal != null && carVal.startsWith('http')
                ? carVal
                : carStoreItem?.svgaAsset;
            _seats[i] = seat.copyWith(
              hasFrame: frameAsset != null && frameAsset.isNotEmpty,
              frameAsset: frameAsset,
              carAsset: carAsset,
            );
          }
        }
      }
      // Resolve & play entry animation (car OR entrance item — never both at once to prevent duplicates)
      if (!_hasPlayedEntryAnimations && _currentUserId != null) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final u = userProvider.currentUser;
        if (u != null) {
          bool playedAny = false;
          // Car SVGA (highest priority)
          if (u.activeCar != null) {
            final carValue = u.activeCar!;
            final carItem = carValue.startsWith('http') ? null : index[carValue];
            final carAssetUrl = carItem != null && carItem.animationUrl != null
                ? carItem.animationUrl
                : (carValue.startsWith('http') ? carValue : null);
            if (carAssetUrl != null) {
              playedAny = true;
              final textReplacement = _buildTextReplacements(
                nameKeys: carItem?.nameKey,
                senderName: u.name,
              );
              final imageReplacement = _buildImageReplacements(
                photoKeys: carItem?.photoKey,
                senderPhoto: u.photoUrl,
              );
              setState(() {
                _entranceAnimAsset = carAssetUrl;
                _showEntranceAnim = true;
                _entranceTextReplacement = textReplacement;
                _entranceImageReplacement = imageReplacement;
                _entranceDefaultImage = carItem?.defaultImage;
              });
            }
          } else if (u.activeEntrance != null) {
            // Entrance item plays only if user has no car
            final entValue = u.activeEntrance!;
            final entranceItem = entValue.startsWith('http') ? null : index[entValue];
            final entranceAssetUrl = entranceItem != null && entranceItem.animationUrl != null
                ? entranceItem.animationUrl
                : (entValue.startsWith('http') ? entValue : null);
            if (entranceAssetUrl != null) {
              playedAny = true;
              final textReplacement = _buildTextReplacements(
                nameKeys: entranceItem?.nameKey,
                senderName: u.name,
              );
              final imageReplacement = _buildImageReplacements(
                photoKeys: entranceItem?.photoKey,
                senderPhoto: u.photoUrl,
              );
              setState(() {
                _entranceItemAnimAsset = entranceAssetUrl;
                _showEntranceItemAnim = true;
                _entranceItemTextReplacement = textReplacement;
                _entranceItemImageReplacement = imageReplacement;
                _entranceItemDefaultImage = entranceItem?.defaultImage;
              });
            }
          }
          if (playedAny) {
            _hasPlayedEntryAnimations = true;
            final isVap = (_entranceAnimAsset != null && isVideoType(_entranceAnimAsset!)) ||
                          (_entranceItemAnimAsset != null && isVideoType(_entranceItemAnimAsset!));
            if (!isVap) {
              _playEntranceSound();
            }
          }
        }
      }
      // Process any entrance animations that were buffered while store items were loading
      if (_pendingEntrances.isNotEmpty) {
        for (final entry in _pendingEntrances) {
          final uid = entry['uid']?.toString();
          final entranceItemId = entry['entranceItem']?.toString();
          if (entranceItemId != null) {
            final storeItem = index[entranceItemId];
            if (storeItem?.animationUrl != null) {
              _playEntranceEffect(entry, storeItem!, uid);
            }
          }
        }
        _pendingEntrances.clear();
      }
      if (mounted) setState(() {});
    });

    // Listen for other users' entrance/car effects
    bool _entranceStreamInitial = true;
    _entranceSub = _firebaseService.entrancesStream(widget.roomId).listen((entrances) {
      if (!mounted || entrances.isEmpty) return;
      final joinedMs = _joinedAt?.millisecondsSinceEpoch ?? 0;
      if (_entranceStreamInitial) {
        for (final entry in entrances) {
          final uid = entry['uid']?.toString();
          final entranceItemId = entry['entranceItem']?.toString() ?? '';
          if (uid != null && entranceItemId.isNotEmpty) {
            _seenEntranceIds.add('${uid}_$entranceItemId');
          }
        }
        _entranceStreamInitial = false;
        return;
      }
      for (final entry in entrances) {
        final uid = entry['uid']?.toString();
        if (uid == null || uid == _currentUserId) continue;
        final entranceItemId = entry['entranceItem']?.toString() ?? '';
        if (entranceItemId.isEmpty) continue;
        final entryTs = entry['timestamp']?.toString() ?? '';
        final entryMs = DateTime.tryParse(entryTs)?.millisecondsSinceEpoch ?? 0;
        if (entryMs < joinedMs) continue;
        final entranceKey = '${uid}_$entranceItemId';
        if (_seenEntranceIds.contains(entranceKey)) continue;
        _seenEntranceIds.add(entranceKey);
        final storeItem = _storeItemsIndex[entranceItemId];
        if (storeItem == null || storeItem.animationUrl == null) {
          if (_storeItemsIndex.isEmpty) {
            _pendingEntrances.add(entry);
            continue;
          }
          // Fallback: raw URL entrance (VIP-purchased) -> play directly
          final rawUrl = entranceItemId.startsWith('http') ? entranceItemId : null;
          if (rawUrl == null) continue;
          _playEntranceEffectRaw(entry, rawUrl);
          continue;
        }
        _playEntranceEffect(entry, storeItem, uid);
      }
    });
  }

  void _showMemberEnterBanner(String name, String photoUrl, [int level = 1]) {
    if (!mounted || name.isEmpty) return;
    setState(() {
      _currentEnterMember = {
        'name': name,
        'photoUrl': photoUrl,
        'level': level,
      };
    });
  }



  void _clearMessages() {
    // Persist a chat_cleared_at stamp so every user's stream filter hides old messages
    final now = DateTime.now().millisecondsSinceEpoch;
    _firebaseService.updateRoom(widget.roomId, {'chat_cleared_at': now});
    setState(() {
      _chatMessages.clear();
    });
  }

  seat_model.SeatModel? get _currentUserSeat {
    if (_currentUserId == null) return null;
    for (final seat in _seats) {
      if (seat.user?.id == _currentUserId) return seat;
    }
    return null;
  }

  void _processSeatMap(Map<int, Map<String, dynamic>> seatMap) {
    if (!mounted) return;
    // Preserve locked state before reset
    final lockedIndices = <int>{};
    for (int i = 0; i < _seats.length; i++) {
      if (_seats[i].isLocked) lockedIndices.add(i);
    }
    // Reset ALL seats to empty first to clear vacated seats
    for (int i = 0; i < _seats.length; i++) {
      _seats[i] = SeatModel(index: i);
    }
    // Restore locked seats
    for (final i in lockedIndices) {
      _seats[i] = SeatModel(index: i, state: SeatState.locked, isLocked: true);
    }
    // Apply seatMap data from Firebase
    bool isCurrentUserOnSeatNow = false;
    bool currentUserMuted = false;
    for (final entry in seatMap.entries) {
      final idx = entry.key;
      if (idx < 0 || idx >= _seats.length) continue;
      final data = entry.value;
      final uid = data['uid']?.toString();
      if (uid != null) {
        if (uid == _currentUserId) {
          isCurrentUserOnSeatNow = true;
          currentUserMuted = data['is_muted'] == true;
        }
        // Fetch full user data for frame asset resolution
        if (!_cachedUsers.containsKey(uid)) {
          _firebaseService.getUser(uid).then((user) {
            if (user != null && mounted) {
              setState(() {
                _cachedUsers[uid] = user;
                _processSeatMap(seatMap);
              });
            }
          });
        }
        final cachedUser = _cachedUsers[uid];
        final activeFrame = data['active_frame']?.toString() ?? cachedUser?.activeFrame;
        final frameAsset = _resolveFrameAsset(activeFrame);
        final activeCar = data['active_car']?.toString() ?? cachedUser?.activeCar;
        final carStoreItem = activeCar != null && !activeCar.startsWith('http')
            ? _storeItemsIndex[activeCar]
            : null;
        final carAsset = activeCar != null && activeCar.startsWith('http')
            ? activeCar
            : carStoreItem?.svgaAsset;

        final giftTotal = _giftReceiverTotals[uid] ?? 0;
        final isMuted = data['is_muted'] == true;
        _seats[idx] = SeatModel(
          index: idx,
          state: SeatState.occupied,
          user: UserModel(
            name: data['name']?.toString() ?? '',
            avatar: data['photo_url']?.toString(),
            id: uid,
            customId: cachedUser?.customId ?? data['custom_id']?.toString(),
            giftCount: giftTotal,
            totalGiftsReceived: giftTotal,
            charm: giftTotal.toString(),
          ),
          isMuted: isMuted,
          hasFrame: frameAsset != null && frameAsset.isNotEmpty,
          frameAsset: frameAsset,
          carAsset: carAsset,
        );
      } else {
        _seats[idx] = SeatModel(index: idx);
      }
    }
    // Only allow publishing when the current user is actually on a seat
    if (isCurrentUserOnSeatNow) {
      _roomAudio.startPublishing();
      _roomAudio.toggleMic(!currentUserMuted);
    } else if (_roomAudio.isPublishing) {
      _roomAudio.stopPublishingIfActive();
      _roomAudio.resetPublishingState();
    }
    if (mounted) setState(() {});
  }

  void _playEntranceEffectRaw(Map<String, dynamic> data, String url) {
    if (!mounted) return;
    if (!isVideoType(url)) {
      _playEntranceSound(animAsset: url);
    }
    final userName = data['name']?.toString() ?? '';
    final userPhoto = data['photoUrl']?.toString() ?? '';
    setState(() {
      _entranceItemAnimAsset = url;
      _showEntranceItemAnim = true;
      _entranceItemTextReplacement = userName.isNotEmpty ? {'test': userName, 'name': userName, 'nickname': userName} : null;
      _entranceItemImageReplacement = userPhoto.isNotEmpty ? {'Avatar': userPhoto, 'avatar': userPhoto, 'user_head': userPhoto, 'img_head': userPhoto} : null;
      _entranceItemDefaultImage = null;
    });
  }

  void _playEntranceEffect(Map<String, dynamic> data, StoreItemModel storeItem, String? uid) {
    if (!mounted) return;
    final animUrl = storeItem.animationUrl ?? '';
    if (!isVideoType(animUrl)) {
      _playEntranceSound(animAsset: animUrl);
    }
    final nameKey = storeItem.nameKey;
    final photoKey = storeItem.photoKey;
    final enteringUser = uid != null ? _cachedUsers[uid] : null;
    final userName = (enteringUser != null && enteringUser.name.isNotEmpty)
        ? enteringUser.name
        : (data['name']?.toString() ?? '');
    final userPhoto = (enteringUser != null && enteringUser.photoUrl.isNotEmpty)
        ? enteringUser.photoUrl
        : (data['photoUrl']?.toString() ?? '');

    final Map<String, String> textReplacement = {
      if (nameKey != null && nameKey.isNotEmpty && userName.isNotEmpty) nameKey: userName,
      if (userName.isNotEmpty) ...{
        'test': userName,
        'name': userName,
        'nickname': userName,
        'user_name': userName,
        'user': userName,
      },
    };
    final Map<String, String> imageReplacement = {
      if (photoKey != null && photoKey.isNotEmpty && userPhoto.isNotEmpty) photoKey: userPhoto,
      if (userPhoto.isNotEmpty) ...{
        'Avatar': userPhoto,
        'user_r': userPhoto,
        'user_l': userPhoto,
        'user_head': userPhoto,
        'img_head': userPhoto,
        'head_img': userPhoto,
        'avatar': userPhoto,
        'photo': userPhoto,
        'user_img': userPhoto,
        'user': userPhoto,
      },
    };

    final isCar = storeItem.category == 'car';
    setState(() {
      if (isCar) {
        _entranceAnimAsset = storeItem.animationUrl;
        _showEntranceAnim = true;
        _entranceTextReplacement = textReplacement.isNotEmpty ? textReplacement : null;
        _entranceImageReplacement = imageReplacement.isNotEmpty ? imageReplacement : null;
        _entranceDefaultImage = storeItem.defaultImage;
      } else {
        _entranceItemAnimAsset = storeItem.animationUrl;
        _showEntranceItemAnim = true;
        _entranceItemTextReplacement = textReplacement.isNotEmpty ? textReplacement : null;
        _entranceItemImageReplacement = imageReplacement.isNotEmpty ? imageReplacement : null;
        _entranceItemDefaultImage = storeItem.defaultImage;
      }
    });
  }

  // Future<void> _initAgora() async {
  //   // Request microphone permission
  //   await [Permission.microphone].request();

  //   // Create the engine
  //   _engine = createAgoraRtcEngine();

  //   // Initialize the engine
  //   await _engine!.initialize(RtcEngineContext(appId: AgoraConfig.appId));

  //   // Register event handlers
  //   _engine!.registerEventHandler(RtcEngineEventHandler(
  //     onJoinChannelSuccess: (connection, elapsed) {
  //       print('onJoinChannelSuccess: ${connection.channelId}, uid: ${connection.localUid}');
  //       setState(() {
  //         _localUid = connection.localUid;
  //       });
  //     },
  //     onUserJoined: (connection, remoteUid, elapsed) {
  //       print('onUserJoined: $remoteUid');
  //     },
  //     onUserOffline: (connection, remoteUid, reason) {
  //       print('onUserOffline: $remoteUid, reason: $reason');
  //     },
  //   ));

  //   // Join channel with token (or empty string if no token)
  //   await _engine!.joinChannel(
  //     token: AgoraConfig.token,
  //     channelId: widget.roomId,
  //     uid: 0,
  //     options: const ChannelMediaOptions(
  //       channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
  //       clientRoleType: ClientRoleType.clientRoleAudience,
  //     ),
  //   );
  // }

  List<SeatModel> _buildInitialSeats() {
    final seats = <SeatModel>[];
    for (int i = 0; i < 20; i++) {
      seats.add(SeatModel(index: i));
    }
    return seats;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // FIX: تنظيف كل طبقات/أنيميشن هدايا الحظ فوراً عند الخروج من الغرفة
    LuckyGiftService().disposeAllOverlays();
    LuckyBagService().dispose();
    // تفريغ الـ caches المؤقتة للغرفة
    _cachedUsers.clear();
    _cachedGiftItems.clear();
    _pendingBannerData = null;
    _lastGiftComboData = null;
    _seenEntranceIds.clear();
    _storeItemsIndex.clear();
    if (!_isMinimized) {
      _leaveRoomSession();
      _roomAudio.dispose();
    }
    _chatCtrl.dispose();
    _chatScroll.dispose();
    _giftSub?.cancel();
    _seatsSub?.cancel();
    _seatsRefreshTimer?.cancel();
    _presencePingTimer?.cancel();
    _giftAnimWatchdog?.cancel();
    _giftAudioPlayer?.dispose();
    _giftAudioPlayer = null;
    _stopEntranceSound();
    _entranceAudioPlayer?.dispose();
    _entranceAudioPlayer = null;
    _roomComboTimer?.cancel();
    _bannerHideTimer?.cancel();
    _roomSub?.cancel();
    _storeSub?.cancel();
    _giftCacheSub?.cancel();
    _bannerConfigSub?.cancel();
    _msgSub?.cancel();
    _entranceSub?.cancel();
    _userBanSub?.cancel();
    _broadcastSub?.cancel();
    _broadcastNotifier.dispose();
    _giftBannerNotifier.dispose();
    _giftAnimNotifier.dispose();
    _chatUpdateNotifier.dispose();
    super.dispose();
  }

  void _closeAllPanels() => setState(() {
        _showGift = false;
        _showFunction = false;
        _showEmoj = false;
        _showChatInput = false;
        _showNotifications = false;
        _showProfile = false;
      });

  void _openMessageSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF211211),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final isLocked = _currentRoom?.isChatLocked ?? false;
            final isAr = Localizations.localeOf(context).languageCode == 'ar';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isAr ? 'إعدادات الرسائل' : 'Message Settings',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isAr ? 'قفل الدردشة' : 'Lock Chat',
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      Switch(
                        value: isLocked,
                        activeColor: const Color(0xFFD3A350),
                        onChanged: (val) {
                          setModalState(() {});
                          _firebaseService.updateRoom(widget.roomId, {
                            'is_chat_locked': val,
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openGiftPanel() {
    final hasSeatedUsers = _seats.any((s) => s.isOccupied && s.user != null);
    if (!hasSeatedUsers) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد مستخدم على المقعد لإرسال الهدية')),
      );
      return;
    }
    _closeAllPanels();
    setState(() => _showGift = true);
  }

  void _checkGiftBanner(Map<String, dynamic> data) {
    // لا نستبدل شريطة ما زالت تُعرض بشريطة جديدة (يمنع تبادل الشرائط
    // المتتالي الذي سبب تشوه العرض). تُستبدل فقط بعد انتهاء العرض.
    if (_showGiftBanner) return;

    // شريط الهدايا العادية مخصص فقط للهدايا العادية ولا يعرض هدايا الحظ إطلاقاً
    if (data['isLucky'] == true || data['categoryId'] == 'lucky' || data['categoryId'] == 'حظ') return;

    final giftValue = data['giftValue'] as int? ?? 0;
    final giftCount = data['giftCount'] as int? ?? 1;
    final categoryId = data['categoryId'] as String?;
    final totalCost = giftValue * giftCount;

    // Get receiver photo from data, seat, or cached users
    String? receiverPhoto = data['receiverPhotoUrl']?.toString();
    final receiverId = data['receiverId']?.toString();
    if (receiverPhoto == null || receiverPhoto.isEmpty) {
      if (_selectedSeatIdx != null &&
          _selectedSeatIdx! < _seats.length &&
          _seats[_selectedSeatIdx!].isOccupied &&
          _seats[_selectedSeatIdx!].user != null) {
        receiverPhoto = _seats[_selectedSeatIdx!].user!.avatar;
      } else if (receiverId != null) {
        final seat = _seats.where((s) => s.user?.id == receiverId).firstOrNull;
        receiverPhoto = seat?.user?.avatar ?? _cachedUsers[receiverId]?.photoUrl;
      }
    }

    // Find matching banner config by category, or fallback to any active
    GiftBannerConfig? config;
    if (categoryId != null) {
      config = _bannerConfigs.where((c) => c.categoryId == categoryId).firstOrNull;
    }
    config ??= _bannerConfigs.isNotEmpty ? _bannerConfigs.first : null;

    if (config != null && totalCost >= config.thresholdCoins) {
      final cfg = config;
      _showGiftBanner = true;
      _giftBannerNotifier.value = {
        'animationAsset': cfg.svgaUrl,
        'senderPhotoUrl': data['senderPhotoUrl']?.toString(),
        'receiverPhotoUrl': receiverPhoto,
        'defaultImage': data['defaultImage']?.toString(),
        'giftCount': giftCount,
        'userRKey': cfg.userRKey,
        'userLKey': cfg.userLKey,
        'numberKey': cfg.numberKey,
        'giftKey': cfg.giftKey,
      };
      // إخفاء إجباري حتى لو لم يُستدع onFinished (حماية من شريطة عالقة)
      _bannerHideTimer?.cancel();
      _bannerHideTimer = Timer(const Duration(seconds: 8), () {
        _showGiftBanner = false;
        _giftBannerNotifier.value = null;
      });
      return;
    }

    // لا نظهر شريط البانر للهدايا العادية الصغيرة (يظهر فقط للهدايا الكبيرة 500+ عملة)
    if (totalCost >= 500) {
      _showGiftBanner = true;
      _giftBannerNotifier.value = {
        'animationAsset': 'assets/svga/gift_banner_strip.svga',
        'senderPhotoUrl': data['senderPhotoUrl']?.toString(),
        'receiverPhotoUrl': receiverPhoto,
        'defaultImage': data['defaultImage']?.toString(),
        'giftCount': giftCount,
        'userRKey': 'user_r',
        'userLKey': 'user_l',
        'numberKey': 'number',
        'giftKey': 'gift',
      };
      _bannerHideTimer?.cancel();
      _bannerHideTimer = Timer(const Duration(seconds: 8), () {
        _showGiftBanner = false;
        _giftBannerNotifier.value = null;
      });
    }
  }

  void _sendMessage() {
    final t = _chatCtrl.text.trim();
    if (t.isEmpty) return;
    if (_currentRoom?.isChatLocked == true && !_isOwnerOrModerator) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم قفل الدردشة من قبل الإدارة')),
      );
      setState(() => _showChatInput = false);
      return;
    }
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user != null) {
      _firebaseService.sendMessage(
        widget.roomId,
        t,
        user.uid,
        user.name,
        user.photoUrl,
        activeBubble: user.activeBubble,
      );
    }
    _chatCtrl.clear();
    setState(() => _showChatInput = false);
  }

  Future<void> _pickRoomImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (image == null) return;
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.currentUser;
      if (user == null) return;
      final imageUrl = await CloudinaryService().uploadImage(
        File(image.path),
        publicId: 'room_${widget.roomId}_${DateTime.now().millisecondsSinceEpoch}',
      );
      await _firebaseService.sendImageMessage(
        widget.roomId, imageUrl, user.uid, user.name, user.photoUrl,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  // ── Seat tap handler ──────────────────────────────────────────
  void _onSeatTap(int idx) {
    final seat = _seats[idx];
    if (seat.isOccupied && seat.user != null) {
      final user = seat.user!;
      if (_isOwnerOrModerator || user.isAdmin) {
        // Owner/moderator/admin: show action sheet directly
        _showOccupiedDialog(idx, user);
      } else {
        // Regular user: show profile first
        setState(() {
          _selectedSeatIdx = idx;
          _selectedUser = user;
          _showProfile = true;
        });
      }
    } else {
      // Empty or locked seat
      _showEmptyDialog(idx);
    }
  }

  void _showEmptyDialog(int idx) {
    final seat = _seats[idx];
    SeatDialogs.showEmptySeatDialog(
      context,
      seatIndex: idx,
      isOwnerOrModerator: _isOwnerOrModerator,
      isLocked: seat.isLocked,
      isMuted: seat.isMuted,
      onTakeMic: () => _takeMic(idx),
      onInviteToMic: () => _inviteToMic(idx),
      onToggleLock: (locked) => _toggleSeatLock(idx, locked),
      onToggleMic: (muted) => _toggleSeatMute(idx, muted),
    );
  }

  void _showOccupiedDialog(int idx, UserModel user) {
    final seat = _seats[idx];
    SeatDialogs.showOccupiedSeatDialog(
      context,
      user: user,
      isOwner: _isOwner,
      isOwnerOrModerator: _isOwnerOrModerator,
      isMuted: seat.isMuted,
      isAdmin: user.isAdmin,
      isBlacked: user.isBlacked,
      onUserDetail: () => _openProfile(idx, user),
      onKickOffMic: () => _kickOffMic(idx),
      onToggleMicLock: (muted) => _toggleSeatMute(idx, muted),
      onSetAdmin: (admin) => _setAdmin(idx, admin),
      onToggleComments: (enabled) {},
      onToggleBlack: (blacked) => _toggleBlack(idx, blacked),
      onKickOutFromRoom: () => _kickOutFromRoom(idx),
      onPrivateMessage: () => setState(() {
        _closeAllPanels();
        _showChatInput = true;
      }),
      onGift: _openGiftPanel,
    );
  }

  // ── Seat actions ──────────────────────────────────────────────

  bool _takingSeat = false;
  void _takeMic(int idx) {
    if (_takingSeat) return;
    if (_currentUserId == null) return;
    // If already on this seat, skip
    if (idx < _seats.length && _seats[idx].user?.id == _currentUserId) return;
    _takingSeat = true;
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentUser = userProvider.currentUser;
    final name = currentUser?.name ?? 'Me';
    // Remember the previous seat before overwriting local state
    int? previousIdx;
    for (int i = 0; i < _seats.length; i++) {
      if (i != idx && _seats[i].user?.id == _currentUserId) {
        previousIdx = i;
        break;
      }
    }
    // Optimistic UI: place the user on the target seat immediately so the
    // move feels instant; the seats stream reconciles with the server state.
    final optimisticFrame = _resolveFrameAsset(currentUser?.activeFrame);
    setState(() {
      _seats[idx] = SeatModel(
        index: idx,
        state: SeatState.occupied,
        hasFrame: optimisticFrame != null && optimisticFrame.isNotEmpty,
        frameAsset: optimisticFrame,
        carAsset: currentUser?.activeCar,
        user: UserModel(
          name: name,
          avatar: currentUser?.photoUrl ?? '',
          id: _currentUserId!,
          customId: currentUser?.customId,
        ),
      );
      if (previousIdx != null) {
        _seats[previousIdx] = SeatModel(index: previousIdx);
      }
    });
    Future<void> doTake() async {
      await _firebaseService.takeSeat(widget.roomId, idx, app.UserModel(
        uid: _currentUserId!,
        customId: currentUser?.customId ?? '',
        name: name,
        photoUrl: currentUser?.photoUrl ?? '',
        activeFrame: currentUser?.activeFrame,
        activeCar: currentUser?.activeCar,
      ));
      _takingSeat = false;
    }
    if (previousIdx != null) {
      _firebaseService.leaveSeat(widget.roomId, previousIdx).then((_) => doTake());
    } else {
      doTake();
    }
  }

  void _kickOffMic(int idx) {
    final kickedUid = _seats[idx].user?.id;

    setState(() {
      _seats[idx].state = SeatState.empty;
      _seats[idx].user = null;
      _seats[idx].isMuted = false;
    });

    _firebaseService.leaveSeat(widget.roomId, idx);

    if (kickedUid != null) {
      _roomAudio.muteRemoteAudio(kickedUid, widget.roomId, true);
      _roomAudio.stopRemoteStream(kickedUid, widget.roomId);
    }
  }

  void _inviteToMic(int idx) {
    // Open invite UI — stub
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Invited to seat $idx')));
  }

  void _toggleSeatLock(int idx, bool locked) {
    setState(() {
      _seats[idx].isLocked = locked;
      _seats[idx].state = locked ? SeatState.locked : SeatState.empty;
    });
  }

  void _toggleSeatMute(int idx, bool muted) {
    setState(() {
      _seats[idx].isMuted = muted;
      if (_seats[idx].isOccupied) {
        _seats[idx].state = muted ? SeatState.muted : SeatState.occupied;
      }
    });
    _firebaseService.toggleMute(widget.roomId, idx, muted);
  }

  void _kickOutFromRoom(int idx) {
    final user = _seats[idx].user;
    if (user == null) return;
    _showKickDialog(user, idx);
  }

  void _showKickDialog(UserModel user, [int? seatIdx]) {
    bool addToBlacklist = false;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // tv_tips
                    const Text(
                      'تنبيه',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // tv_content
                    Text(
                      'هل أنت متأكد من طرد المستخدم ${user.name} من الغرفة؟',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF565964),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Checkbox cl_join_block
                    GestureDetector(
                      onTap: () {
                        setDialogState(() {
                          addToBlacklist = !addToBlacklist;
                        });
                      },
                      child: Row(
                        children: [
                          Icon(
                            addToBlacklist ? Icons.check_box : Icons.check_box_outline_blank,
                            size: 20,
                            color: addToBlacklist ? const Color(0xFFFFC525) : const Color(0xFF999999),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'إضافة إلى القائمة السوداء لمنع الدخول دائماً',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF16151A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Cancel & Confirm buttons
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: const Color(0xFFF5F7FB),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text(
                                'إلغاء',
                                style: TextStyle(
                                  color: Color(0xFF565964),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: AppColors.giftBtnGradient,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _executeKick(user, seatIdx, addToBlacklist);
                                },
                                child: const Text(
                                  'تأكيد',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _executeKick(UserModel user, int? seatIdx, bool addToBlacklist) {
    if (seatIdx != null && seatIdx < _seats.length) {
      setState(() {
        _seats[seatIdx].state = SeatState.empty;
        _seats[seatIdx].user = null;
        _seats[seatIdx].isMuted = false;
      });
      _firebaseService.leaveSeat(widget.roomId, seatIdx);
    }
    final uid = user.id;
    if (uid != null && _currentUserId != null) {
      _firebaseService.kickUserFromRoom(
        widget.roomId,
        _currentUserId!,
        uid,
        kickerName: _currentUserName ?? '',
        targetName: user.name,
        addToBlacklist: addToBlacklist,
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(addToBlacklist ? 'تم طرد وحظر ${user.name} بنجاح' : 'تم طرد ${user.name} من الغرفة')),
    );
  }

  void _setAdmin(int idx, bool isAdmin) {
    final user = _seats[idx].user;
    if (user == null) return;
    setState(() {
      _seats[idx].user = user.copyWith(isAdmin: isAdmin);
    });
  }

  void _toggleBlack(int idx, bool blacked) {
    final user = _seats[idx].user;
    if (user == null || user.id == null) return;
    setState(() {
      _seats[idx].user = user.copyWith(isBlacked: blacked);
    });
    if (blacked) {
      _kickOffMic(idx);
      if (_currentUserId != null) {
        _firebaseService.blockUserFromRoom(widget.roomId, _currentUserId!, user.id!);
        _firebaseService.leaveRoom(widget.roomId, user.id!);
      }
    } else {
      if (_currentUserId != null) {
        _firebaseService.unblockUserFromRoom(widget.roomId, user.id!);
      }
    }
  }

  void _openProfile(int idx, UserModel user) {
    setState(() {
      _selectedSeatIdx = idx;
      _selectedUser = user;
      _showProfile = true;
    });
  }

  void _openChatUserProfile(String uid, String name, String photoUrl) {
    String? foundCustomId = UserProfile.customIdCache[uid];
    if (foundCustomId == null || foundCustomId.isEmpty) {
      for (final s in _seats) {
        if (s.user?.id == uid && s.user?.customId != null && s.user!.customId!.isNotEmpty) {
          foundCustomId = s.user!.customId;
          break;
        }
      }
    }
    setState(() {
      _selectedSeatIdx = null;
      _selectedUser = UserModel(
        id: uid,
        name: name,
        avatar: photoUrl.isNotEmpty ? photoUrl : null,
        customId: foundCustomId,
      );
      _showProfile = true;
    });
  }

  // ── Function panel actions ────────────────────────────────────

  void _openVolume() {
    _closeAllPanels();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => VolumePanel(initialVolume: 20, onVolumeChanged: (_) {}),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomSettingsScreen(
          roomId: widget.roomId,
          initialName: widget.roomName,
          initialPassword: widget.roomPassword,
          initialTopic: _currentRoom?.announcement.isNotEmpty == true
              ? _currentRoom!.announcement
              : (_currentRoom?.description ?? ''),
          roomAvatarPath: _currentRoom?.roomPhotoUrl.isNotEmpty == true
              ? _currentRoom!.roomPhotoUrl
              : _seats[0].user?.avatar,
          isModerator: !_isOwner && _moderators.contains(_currentUserId),
          onConfirm: (name, pwd, photoUrl, topic) async {
            final updates = <String, dynamic>{
              'name': name,
              'password': pwd,
            };
            if (photoUrl != null && photoUrl.isNotEmpty) updates['room_photo_url'] = photoUrl;
            if (topic != null) {
              updates['announcement'] = topic;
              updates['description'] = topic;
            }
            await _firebaseService.updateRoom(widget.roomId, updates);
            if (_currentUserId != null) {
              await _firebaseService.updateUser(_currentUserId!, {'name': name});
            }
          },
        ),
      ),
    );
  }

  void _openSeatStyle() {
    _closeAllPanels();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SeatStylePanel(
        initialStyle: SeatStyle.values[_roomSeatStyle.index.clamp(0, 2)],
        initialSeatCount: _seats.length,
        onConfirm: (style, count) {
          seat_model.SeatStyle newSeatStyle;
          switch (style) {
            case SeatStyle.game:
              newSeatStyle = seat_model.SeatStyle.circle;
              break;
            case SeatStyle.classic:
              newSeatStyle = seat_model.SeatStyle.classic;
              break;
            case SeatStyle.vip:
              newSeatStyle = seat_model.SeatStyle.heart;
              break;
          }
          _firebaseService.updateRoomSeatStyle(widget.roomId, newSeatStyle.index);
          _firebaseService.updateRoomSeatCount(widget.roomId, count);
          // Clean up removed seats in Firebase
          if (count < _seats.length) {
            for (int i = count; i < _seats.length; i++) {
              _firebaseService.leaveSeat(widget.roomId, i);
            }
          }
          setState(() {
            _roomSeatStyle = newSeatStyle;
            if (count != _seats.length) {
              _seats = List.generate(count, (i) => seat_model.SeatModel(index: i));
            }
          });
        },
      ),
    );
  }

  void _openRoomBackground() {
    _closeAllPanels();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => RoomBackgroundBottomSheet(
        roomId: widget.roomId,
        currentBackground: _currentRoom?.bgImage ?? '',
      ),
    );
  }

  void _openMixer() {
    _closeAllPanels();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MixerPanel(onMixerToggle: (_) {}),
    );
  }

  void _openReport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportRoomScreen(
          roomName: widget.roomName,
          roomAvatar: _currentRoom?.roomPhotoUrl ?? _seats[0].user?.avatar,
        ),
      ),
    );
  }

  void _openPrivateChat(UserModel? user) {
    if (user?.id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          targetUid: user!.id!,
          targetName: user.name,
          targetPhotoUrl: user.avatar,
        ),
      ),
    );
  }

  void _openEffect() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final isAr = Localizations.localeOf(context).languageCode == 'ar';
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xF51D1111),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Text(
                    isAr ? 'إعدادات التأثيرات' : 'Effect Settings',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0x1AFFFFFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isAr ? 'تأثيرات الهدايا' : 'Gift Effects',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Switch(
                        value: _giftEffectsEnabled,
                        activeColor: const Color(0xFFDE880F),
                        activeTrackColor: const Color(0xFFFFC525),
                        onChanged: (val) {
                          setSheetState(() => _giftEffectsEnabled = val);
                          setState(() => _giftEffectsEnabled = val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  isAr
                      ? 'الوصف:\n 1. تشغيل أو إيقاف التأثيرات الخاصة يؤثر عليك فقط ولا يؤثر على الآخرين. لتحسين تجربتك يوصى بإيقافها فقط عند حدوث بطء.\n 2. بعد إيقاف التأثيرات، لن يتم عرض الرسوم المتحركة الكبيرة للهدايا.'
                      : 'Description:\n 1. Turning effects on/off only affects you, not others.\n 2. After disabling, gift full-screen animations will be skipped.',
                  style: const TextStyle(
                    color: Color(0x80FFFFFF),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openCharmSwitch() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isAr = Localizations.localeOf(context).languageCode == 'ar';
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _showCharmValues = !_showCharmValues;
                      });
                      FirebaseService().updateRoom(widget.roomId, {
                        'charm_enabled': _showCharmValues,
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      child: Text(
                        _showCharmValues
                            ? (isAr ? 'إغلاق الكاريزما' : 'Close Charm')
                            : (isAr ? 'فتح الكاريزما' : 'Open Charm'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16151A),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      child: Text(
                        isAr ? 'إلغاء' : 'Cancel',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                          color: Color(0xFF666666),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openMusic() {
    RoomMusicBottomSheet.show(
      context,
      onOpenPlaylist: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MusicScreen()),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final navH = MediaQuery.of(context).padding.bottom;
    final sizeH = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_isMinimized) {
            Navigator.of(context).pop();
            return;
          }
          bool isOnSeat = false;
          for (int i = 0; i < _seats.length; i++) {
            if (_seats[i].user?.id == _currentUserId) {
              isOnSeat = true;
              break;
            }
          }
          if (isOnSeat) {
            _minimizeRoom();
          } else {
            _showExit ? setState(() => _showExit = false) : _exitRoom();
          }
        }
      },
      child: Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.roomBg,
      body: Stack(
          children: [
          // ── Background tap to close ──────────────────────────
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeAllPanels,
              behavior: HitTestBehavior.opaque,
            ),
          ),
          // ── Background ───────────────────────────────────────
          Positioned.fill(
            child: Builder(
              builder: (ctx) {
                final customBg = _currentRoom?.bgImage;
                if (customBg != null && customBg.isNotEmpty) {
                  return Image.network(customBg, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.black));
                }

                final theme = _currentRoom?.category ?? 'themeFriend';
                final bgImageUrl = DynamicConfigService().getRoomBgImage(theme);
                if (bgImageUrl != null && bgImageUrl.isNotEmpty) {
                  return Image(image: R.cachedImage(bgImageUrl), fit: BoxFit.cover);
                }
                
                final gradient = AppColors.themeFriend; // default
                final colors = DynamicConfigService().getRoomGradient(theme);
                final LinearGradient activeGradient = (colors != null && colors.length >= 2) 
                    ? LinearGradient(colors: colors, begin: Alignment.topCenter, end: Alignment.bottomCenter)
                    : (theme == 'themeChat' ? AppColors.themeChat : 
                       theme == 'themeMusic' ? AppColors.themeMusic :
                       theme == 'themeGame' ? AppColors.themeGame :
                       theme == 'themeParty' ? AppColors.themeParty :
                       theme == 'themeHobby' ? AppColors.themeHobby : AppColors.themeFriend);
                
                return Container(
                  decoration: BoxDecoration(gradient: activeGradient),
                );
              },
            ),
          ),

          // ── Main column ──────────────────────────────────────
          Column(
            children: [
              // Header
               RoomHeader(
                roomName: widget.roomName,
                roomId: widget.roomId,
                hostAvatar: _currentRoom?.roomPhotoUrl ?? _seats[0].user?.avatar,
                isLocked: widget.roomPassword.isNotEmpty,
                hotValue: widget.hotValue,
                gameDesc: widget.gameDesc,
                onlineCount: '$_onlineCount',
                isFollowed: _isFollowed,
                onExit: () => setState(() => _showExit = true),
                onMinimize: _minimizeRoom,
                onRank: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => RoomRankBottomSheet(roomId: widget.roomId),
                  );
                },
                onInfoTap: () => setState(() => _showRoomInfo = true),
                onOnlineTap: _showMembersSheet,
                onGameTap: _showGameBottomSheet,
                onFollow: _toggleFollow,
              ),

              const SizedBox(height: 4),

              // SeatArea — 21 seats
              SeatArea(
                seats: _seats,
                onSeatTap: _onSeatTap,
                seatEmojis: _seatEmojis,
                moderators: _moderators,
                hostUid: _currentRoom?.hostUid,
                seatStyle: _roomSeatStyle,
                showCharmValues: _showCharmValues,
                onCharmTap: () => setState(() => _showCharmValues = !_showCharmValues),
              ),

              // Chat area fills remaining
              Expanded(child: _buildChatArea()),

              // Bottom bar
              BottomBar(
                isMicOn: _isMicOn,
                showMic: _currentUserSeat != null,
                msgCount: _msgCount,
                onChat: () {
                  if (_currentRoom?.isChatLocked == true && !_isOwnerOrModerator) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم قفل الدردشة من قبل الإدارة')));
                    return;
                  }
                  final willShow = !_showChatInput;
                  _closeAllPanels();
                  if (willShow) {
                    setState(() => _showChatInput = true);
                  }
                },
                onEmoj: () {
                  final willShow = !_showEmoj;
                  _closeAllPanels();
                  if (willShow) {
                    setState(() => _showEmoj = true);
                  }
                },
                onMic: () async {
                  if (_currentUserSeat == null) return;
                  final newVal = !_isMicOn;
                  setState(() => _isMicOn = newVal);
                  await _roomAudio.toggleMic(newVal);
                  _toggleSeatMute(_currentUserSeat!.index, !newVal);
                },
                onGift: () {
                  if (_showGift) {
                    setState(() => _showGift = false);
                  } else {
                    _openGiftPanel();
                  }
                },
                onMusic: _openMusic,
                onMsg: () {
                  _closeAllPanels();
                  RoomMessageBottomSheet.show(context);
                },
                onFunction: () {
                  final willShow = !_showFunction;
                  _closeAllPanels();
                  if (willShow) {
                    setState(() => _showFunction = true);
                  }
                },
              ),

              SizedBox(height: navH),
            ],
          ),

          // ── Lucky Bag / Red Envelope floating button ─────────
          Positioned(
            bottom: navH + 63 + 17 + 56,
            right: 10,
            child: LuckyBagFloatingWidget(roomId: widget.roomId),
          ),

          // ── صاروخ الغرفة الكريستالي ومستوى الطاقة (Room Rocket) ─────────
          Positioned(
            bottom: navH + 63 + 17 + 56,
            left: 10,
            child: RoomRocketWidget(
              energy: _currentRoom?.totalGifts ?? 0,
              target: 10000,
              onTap: () => RoomRocketWidget.showRocketInfoSheet(
                context,
                _currentRoom?.totalGifts ?? 0,
                10000,
              ),
            ),
          ),

          // ── Game button (room_game_ic) ──────────────────────
          Positioned(
            bottom: navH + 63 + 17,
            right: 14,
            child: GestureDetector(
              onTap: _showGameBottomSheet,
              child: R.image(
                R.roomGameIc,
                width: 44,
                height: 44,
              ),
            ),
          ),

          // ── Bottom sheet panels ───────────────────────────────
          if (_showGift)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showGift = false),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () {},
                      child: GiftPanel(
                        selectedCount: _giftCount,
                        coins: Provider.of<UserProvider>(context).currentUser?.coins ?? 0,
                        roomId: widget.roomId,
                        targetUsers: _seats
                            .where((s) => s.isOccupied && s.user != null)
                            .map((s) => {
                                  'id': s.user!.id ?? '',
                                  'name': s.user!.name,
                                  'photoUrl': s.user!.avatar,
                                })
                            .toList(),
                        receiverId: _selectedSeatIdx != null &&
                                _seats[_selectedSeatIdx!].isOccupied &&
                                _seats[_selectedSeatIdx!].user != null
                            ? _seats[_selectedSeatIdx!].user!.id
                            : null,
                        receiverName: _selectedSeatIdx != null &&
                                _seats[_selectedSeatIdx!].isOccupied &&
                                _seats[_selectedSeatIdx!].user != null
                            ? _seats[_selectedSeatIdx!].user!.name
                            : null,
                        onSend: () {
                          // إبقاء البانل مفتوحاً للاستمرار في الإرسال والكومبو كما في التطبيق الأصلي
                        },
                        onSendGift: (asset) {
                          _giftAnimAsset = asset;
                        },
                        onSendGiftExtended: (data) async {
                          if (data != null) {
                            final iconUrl = data['defaultImage']?.toString() ?? data['animationAsset']?.toString() ?? '';
                            final animAsset = data['animationAsset']?.toString() ?? _giftAnimAsset ?? '';
                            final currUser = Provider.of<UserProvider>(context, listen: false).currentUser;
                            final sName = data['senderName']?.toString() ?? currUser?.name ?? '';
                            final sPhoto = data['senderPhotoUrl']?.toString() ?? currUser?.photoUrl ?? '';
                            final defImg = data['defaultImage']?.toString();
                            final nameKey = data['nameKey']?.toString();
                            final photoKey = data['photoKey']?.toString();
                            final textRepl = _buildTextReplacements(
                              nameKeys: nameKey,
                              receiverNameKeys: data['receiverNameKey']?.toString() ?? data['receiverName']?.toString(),
                              countKeys: data['countKey']?.toString() ?? data['giftCount']?.toString(),
                              senderName: sName,
                              receiverName: data['receiverName']?.toString() ?? '',
                              count: (data['giftCount'] as num?)?.toInt() ?? 1,
                            );
                            final imgRepl = _buildImageReplacements(
                              photoKeys: photoKey,
                              receiverPhotoKeys: data['receiverPhotoKey']?.toString(),
                              senderPhoto: sPhoto,
                              receiverPhoto: data['receiverPhotoUrl']?.toString() ?? '',
                            );

                            // حفظ الإعدادات للأنيميشن الكبير
                            if (mounted) {
                              setState(() {
                                _giftAnimAsset = animAsset;
                                _giftTextReplacement = textRepl;
                                _giftImageReplacement = imgRepl;
                                _giftDefaultImage = defImg;
                              });
                            }

                            // إطلاق أنيميشن الهدية الكبيرة وزر الكومبو فوراً دون أي انتظار
                            if (animAsset.isNotEmpty && mounted) {
                              _triggerGiftAnim(
                                animAsset,
                                textReplacement: textRepl,
                                imageReplacement: imgRepl,
                                defaultImage: defImg,
                              );
                            }
                            _playGiftArrivalSound();

                            _startRoomComboTimer(data);
                            _pendingBannerData = data;
                            _checkGiftBanner(data);

                            // تحميل مسبق في الخلفية دون حظر واجهة المستخدم
                            if (animAsset.isNotEmpty && (animAsset.startsWith('http://') || animAsset.startsWith('https://'))) {
                              unawaited(Future(() async {
                                if (isVideoType(animAsset)) {
                                  await VapPlayer.prefetch(animAsset);
                                } else {
                                  await SvgaPlayer.prefetch(animAsset);
                                }
                              }));
                            }
                            if (sPhoto.isNotEmpty) {
                              unawaited(MediaCacheService().downloadToBytes(sPhoto).catchError((_) => Uint8List(0)));
                            }

                          }
                        },
                        onCountTap: _showGiftCountMenu,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_showFunction)
            Positioned.fill(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => setState(() => _showFunction = false),
                      behavior: HitTestBehavior.opaque,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: FunctionPanel(
                      isOwner: _isOwner,
                      isModerator: _moderators.contains(_currentUserId),
                      onClose: () => setState(() => _showFunction = false),
                      onItemTap: _onFunctionTap,
                    ),
                  ),
                ],
              ),
            ),

          if (_showEmoj) _buildEmojPanel(),
          if (_showChatInput) _buildChatInputBar(),

          // ── Full-screen overlays ──────────────────────────────
          if (_showProfile && _selectedUser != null)
            Positioned.fill(
              child: UserProfile(
                user: _selectedUser!.toMap(),
                showMicControls:
                    _selectedSeatIdx != null &&
                    _seats[_selectedSeatIdx!].isOccupied &&
                    (_isOwnerOrModerator || _selectedUser?.id == _currentUserId),
                isCurrentUser: _selectedUser?.id == _currentUserId,
                isFollowed: _selectedUser?.id != null && _followedUsers.contains(_selectedUser!.id!),
                isModerator: _isOwnerOrModerator,
                isRoomOwner: _isOwner,
                isTargetModerator: _selectedUser?.id != null && _moderators.contains(_selectedUser!.id!),
                isBlocked: _selectedUser?.id != null && _blockedUsers.contains(_selectedUser!.id!),
                currentUserId: _currentUserId,
                onClose: () => setState(() {
                  _showProfile = false;
                  _selectedUser = null;
                  _selectedSeatIdx = null;
                }),
                onViewProfile: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => UserProfileScreen(targetUid: _selectedUser!.id),
                  ));
                },
                onToggleAdmin: () async {
                  final targetUid = _selectedUser?.id;
                  if (targetUid == null) return;
                  final isMod = _moderators.contains(targetUid);
                  try {
                    if (isMod) {
                      await FirebaseFirestore.instance.collection('rooms').doc(widget.roomId).update({
                        'moderators': FieldValue.arrayRemove([targetUid]),
                      });
                      setState(() => _moderators.remove(targetUid));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تم إلغاء إشراف ${_selectedUser?.name}')),
                      );
                    } else {
                      await FirebaseFirestore.instance.collection('rooms').doc(widget.roomId).update({
                        'moderators': FieldValue.arrayUnion([targetUid]),
                      });
                      setState(() => _moderators.add(targetUid));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تم تعيين ${_selectedUser?.name} كمشرف في الغرفة 👑')),
                      );
                    }
                  } catch (e) {
                    debugPrint('Error toggling moderator: $e');
                  }
                  setState(() => _showProfile = false);
                },
                onFollow: () {
                  final userId = _selectedUser?.id;
                  if (userId == null) return;
                  if (_blockedUsers.contains(userId)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Cannot follow this user'), duration: Duration(seconds: 2)),
                    );
                    return;
                  }
                  setState(() {
                    if (_followedUsers.contains(userId)) {
                      _followedUsers.remove(userId);
                      _firebaseService.unfollowUser(_currentUserId!, userId);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Unfollowed ${_selectedUser?.name}')),
                      );
                    } else {
                      _followedUsers.add(userId);
                      _firebaseService.followUser(_currentUserId!, userId);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Followed ${_selectedUser?.name}')),
                      );
                    }
                  });
                },
                onChat: () {
                  final userId = _selectedUser?.id;
                  if (userId != null && _blockedUsers.contains(userId)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Cannot message this user'), duration: Duration(seconds: 2)),
                    );
                    return;
                  }
                  setState(() {
                    _showProfile = false;
                  });
                  // Navigate to private message screen
                  _openPrivateChat(_selectedUser);
                },
                onMention: () {
                  final userId = _selectedUser?.id;
                  if (userId != null && _blockedUsers.contains(userId)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Cannot mention this user'), duration: Duration(seconds: 2)),
                    );
                    return;
                  }
                  setState(() {
                    _showProfile = false;
                    _showChatInput = true;
                    _chatCtrl.text = '@${_selectedUser?.name} ';
                  });
                },
                onGift: _openGiftPanel,
                onMicDown: () {
                  if (_selectedSeatIdx != null) {
                    _kickOffMic(_selectedSeatIdx!);
                  }
                  setState(() => _showProfile = false);
                },
                onMicMute: () {
                  if (_selectedSeatIdx != null) {
                    final idx = _selectedSeatIdx!;
                    _toggleSeatMute(idx, !_seats[idx].isMuted);
                  }
                  setState(() => _showProfile = false);
                },
                onReport: () {
                  final u = _selectedUser;
                  if (u == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReportUserScreen(
                        nickname: u.name,
                        avatar: u.avatar,
                        reportedUid: u.id ?? '',
                      ),
                    ),
                  );
                },
                onBlock: () {
                  final userId = _selectedUser?.id;
                  if (userId == null || _currentUserId == null) return;
                  _firebaseService.blockUser(_currentUserId!, userId);
                  setState(() => _blockedUsers.add(userId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${_selectedUser?.name} has been blocked'), duration: Duration(seconds: 2)),
                  );
                },
                onUnblock: () {
                  final userId = _selectedUser?.id;
                  if (userId == null || _currentUserId == null) return;
                  _firebaseService.unblockUser(_currentUserId!, userId);
                  setState(() => _blockedUsers.remove(userId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${_selectedUser?.name} has been unblocked'), duration: Duration(seconds: 2)),
                  );
                },
                onKick: () {
                  if (_selectedUser != null) {
                    _showKickDialog(_selectedUser!, _selectedSeatIdx);
                  }
                  setState(() => _showProfile = false);
                },
                onMute: () {
                  if (_selectedSeatIdx != null) {
                    final idx = _selectedSeatIdx!;
                    _toggleSeatMute(idx, !_seats[idx].isMuted);
                  }
                  setState(() => _showProfile = false);
                },
              ),
            ),

          if (_showRoomInfo) _buildRoomInfoSheet(sizeH),
          if (_showNotifications) _buildNotificationsSheet(),
          if (_showExit) _buildExitDialog(),
          if (_showShare) _buildShare(),
          // ── أنيميشن gift.svga يملأ الشاشة عند الإرسال مع عزله لمنع إعادة رسم الغرفة ──
          ValueListenableBuilder<Map<String, dynamic>?>(
            valueListenable: _giftAnimNotifier,
            builder: (context, animData, _) {
              if (animData == null) return const SizedBox.shrink();
              final asset = animData['asset']?.toString();
              if (asset == null || asset.isEmpty) return const SizedBox.shrink();
              return Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: RepaintBoundary(
                    child: GiftSvgaOverlay(
                      animationAsset: asset,
                      textReplacement: animData['textReplacement'] as Map<String, String>?,
                      imageReplacement: animData['imageReplacement'] as Map<String, String>?,
                      defaultImageUrl: animData['defaultImage']?.toString(),
                      onFinished: _clearGiftAnim,
                    ),
                  ),
                ),
              );
            },
          ),
          // ── أنيميشن طيران الهدية إلى المقعد المحدد أو جميع المقاعد ──
          if (_showGiftFlight && _giftFlightIconUrl.isNotEmpty && _giftFlightTargets.isNotEmpty)
            Positioned.fill(
              child: GiftSeatFlightOverlay(
                giftIconUrl: _giftFlightIconUrl,
                startOffset: Offset(MediaQuery.of(context).size.width * 0.8, MediaQuery.of(context).size.height - 60),
                targetOffsets: _giftFlightTargets,
                onFinished: () {
                  if (mounted) {
                    setState(() {
                      _showGiftFlight = false;
                      _giftFlightIconUrl = '';
                      _giftFlightTargets = [];
                      // تشغيل الهدية الكبيرة فقط إن لم تكن تعمل بالفعل
                      if (_giftAnimNotifier.value == null && _giftAnimAsset != null && _giftAnimAsset!.isNotEmpty) {
                        _triggerGiftAnim(
                          _giftAnimAsset!,
                          textReplacement: _giftTextReplacement,
                          imageReplacement: _giftImageReplacement,
                          defaultImage: _giftDefaultImage,
                        );
                      }
                    });
                    if (_pendingBannerData != null) {
                      _checkGiftBanner(_pendingBannerData!);
                      _pendingBannerData = null;
                    }
                  }
                },
              ),
            ),
          // ── Gift banner strip (high-value gifts) ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: _giftBannerNotifier,
              builder: (context, bannerData, _) {
                if (bannerData == null) return const SizedBox.shrink();
                return GiftBannerOverlay(
                  animationAsset: bannerData['animationAsset']?.toString(),
                  senderPhotoUrl: bannerData['senderPhotoUrl']?.toString(),
                  receiverPhotoUrl: bannerData['receiverPhotoUrl']?.toString(),
                  giftImageUrl: bannerData['defaultImage']?.toString(),
                  giftCount: (bannerData['giftCount'] as num?)?.toInt() ?? 1,
                  userRKey: bannerData['userRKey']?.toString() ?? 'user_r',
                  userLKey: bannerData['userLKey']?.toString() ?? 'user_l',
                  numberKey: bannerData['numberKey']?.toString() ?? 'number',
                  giftKey: bannerData['giftKey']?.toString() ?? 'gift',
                  onFinished: () {
                    _bannerHideTimer?.cancel();
                    _showGiftBanner = false;
                    _giftBannerNotifier.value = null;
                  },
                );
              },
            ),
          ),
          // ── أنيميشن دخول الغرفة (car effect) ──
          if (_showEntranceAnim && _entranceAnimAsset != null)
            Positioned.fill(
              child: GiftSvgaOverlay(
                animationAsset: _entranceAnimAsset,
                textReplacement: _entranceTextReplacement,
                imageReplacement: _entranceImageReplacement,
                defaultImageUrl: _entranceDefaultImage,
                onFinished: () => setState(() {
                  _stopEntranceSound();
                  _showEntranceAnim = false;
                  _entranceAnimAsset = null;
                  _entranceTextReplacement = null;
                  _entranceImageReplacement = null;
                  _entranceDefaultImage = null;
                }),
              ),
            ),
          // ── أنيميشن دخول (entrance item) يعمل فوق السيارة ──
          if (_showEntranceItemAnim && _entranceItemAnimAsset != null)
            Positioned.fill(
              child: GiftSvgaOverlay(
                animationAsset: _entranceItemAnimAsset,
                textReplacement: _entranceItemTextReplacement,
                imageReplacement: _entranceItemImageReplacement,
                defaultImageUrl: _entranceItemDefaultImage,
                showBackground: false,
                onFinished: () => setState(() {
                  _stopEntranceSound();
                  _showEntranceItemAnim = false;
                  _entranceItemAnimAsset = null;
                  _entranceItemTextReplacement = null;
                  _entranceItemImageReplacement = null;
                  _entranceItemDefaultImage = null;
                }),
              ),
            ),
          // ── زر الكومبو العائم — فوق جميع الرسوم المتحركة لضمان التفاعل التام ──
          ValueListenableBuilder<_ComboState>(
            valueListenable: _comboNotifier,
            builder: (context, combo, _) {
              if (combo.seconds <= 0 || _lastGiftComboData == null) {
                return const SizedBox.shrink();
              }
              return Positioned(
                bottom: 74,
                right: 12,
                child: GestureDetector(
                  onTap: _onRoomComboTap,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 92,
                    height: 92,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.asset(
                          combo.firing ? R.comboFire : R.comboIdle,
                          width: 92,
                          height: 92,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Container(
                            width: 74,
                            height: 74,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
                              ),
                            ),
                            child: const Center(
                              child: Text('COMBO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 12,
                          child: Text(
                            'x${combo.multiplier}',
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // ── Minimized room bubble (room stays functional underneath) ──
          if (_isMinimized)
            Positioned(
              top: navH + 60,
              right: 12,
              child: GestureDetector(
                onTap: () => setState(() => _isMinimized = false),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.cardBg,
                      child: ClipOval(
                        child: SizedBox(
                          width: 52,
                          height: 52,
                          child: R.loadImage(
                            _currentRoom?.roomPhotoUrl ?? R.avaBoy,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: -8,
                      right: -8,
                      child: GestureDetector(
                        onTap: _exitRoom,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Global Marquee Broadcast (view_room_all_banner.xml) ──
          ValueListenableBuilder<Map<String, dynamic>?>(
            valueListenable: _broadcastNotifier,
            builder: (context, broadcast, _) {
              if (broadcast == null) return const SizedBox.shrink();
              return Positioned(
                top: MediaQuery.of(context).padding.top + 46,
                left: 0,
                right: 0,
                child: RoomMarqueeBroadcast(
                  broadcast: broadcast,
                  onDismissed: () {
                    _currentBroadcast = null;
                    _broadcastNotifier.value = null;
                  },
                ),
              );
            },
          ),

          // ── Member Entrance Banner (layout_room_member_enter.xml) ──
          if (_currentEnterMember != null)
            Positioned(
              bottom: navH + 150,
              left: 12,
              child: RoomMemberEnterBanner(
                userName: _currentEnterMember!['name']?.toString() ?? '',
                userPhotoUrl: _currentEnterMember!['photoUrl']?.toString() ?? '',
                userLevel: (_currentEnterMember!['level'] as num?)?.toInt() ?? 1,
                onFinished: () {
                  if (mounted) setState(() => _currentEnterMember = null);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Function panel item tap ───────────────────────────────────
  void _onFunctionTap(String label) {
    setState(() => _showFunction = false);
    switch (label) {
      case 'Volume':
        _openVolume();
        break;
      case 'Settings':
        if (_isOwnerOrModerator) {
          _openSettings();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Localizations.localeOf(context).languageCode == 'ar' ? 'إعدادات الغرفة متاحة للمالك والمشرفين فقط' : 'Room settings available for owner and admins only')),
          );
        }
        break;
      case 'Seat Style':
        if (_isOwnerOrModerator) {
          _openSeatStyle();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Localizations.localeOf(context).languageCode == 'ar' ? 'تغيير شكل المقاعد متاح للمالك والمشرفين فقط' : 'Seat style available for owner and admins only')),
          );
        }
        break;
      case 'Room Background':
        if (_isOwner || _isOwnerOrModerator) {
          _openRoomBackground();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Localizations.localeOf(context).languageCode == 'ar' ? 'تغيير خلفية الغرفة متاح للمالك والمشرفين فقط' : 'Room background available for owner and admins only')),
          );
        }
        break;
      case 'Mixer':
        _openMixer();
        break;
      case 'Report':
        _openReport();
        break;
      case 'Effect':
        _openEffect();
        break;
      case 'Gift Value':
        _openCharmSwitch();
        break;
      case 'Clear Messages':
        if (_isOwnerOrModerator) _clearMessages();
        break;
      case 'Message Settings':
        if (_isOwnerOrModerator) _openMessageSettings();
        break;
      case 'Music':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const MusicScreen()),
        );
        break;
      case 'Notifications':
        setState(() => _showFunction = false);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        );
        break;
      case 'Rankings':
        Navigator.push(
          context,
              MaterialPageRoute(builder: (context) => const RankScreen()),
        );
        break;
      case 'Share':
        setState(() => _showShare = true);
        break;
      case 'Lucky Bag':
        LuckyBagSendDialog.show(context, roomId: widget.roomId);
        break;
      case 'Game':
        _showGameBottomSheet();
        break;
      default:
        break;
    }
  }

  void _showGameBottomSheet() {
    RoomGameBottomSheet.show(
      context,
      roomId: widget.roomId,
      onGameSelect: (gameKey, gameName) {
        if (_isOwner) {
          FirebaseFirestore.instance.collection('rooms').doc(widget.roomId).update({
            'game_desc': gameName,
          }).catchError((_) {});
        }
      },
    );
  }

  // ── Chat area (uses Firebase messages) ──────────────────────
  Widget _buildChatArea() {
    return Padding(
      padding: const EdgeInsets.only(right: 80),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: _chatUpdateNotifier,
              builder: (_, __, ___) {
                if (_chatMessages.isEmpty) return const SizedBox.shrink();
                return ListView.builder(
                  controller: _chatScroll,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  itemCount: _chatMessages.length,
                  itemBuilder: (_, i) {
                    final m = _chatMessages[i];
                    final userProvider = Provider.of<UserProvider>(context, listen: false);
                    final isMe = m.senderUid == userProvider.currentUser?.uid;
                    return _buildChatMsg(m, isMe);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserLevelMedal(String uid) {
    final cached = _cachedUsers[uid];
    final lvl = cached?.wealthLevel ?? 1;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Lv.$lvl',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          height: 1.1,
        ),
      ),
    );
  }

  Widget _buildChatMsg(MessageModel m, bool isMe) {
    final isAr = Localizations.maybeLocaleOf(context)?.languageCode != 'en';

    if (m.type == 'gift') {
      final payload = m.giftPayload;
      final giftName = payload?['gift_name']?.toString() ?? '';
      final receiverName = payload?['receiver_name']?.toString() ?? '';
      final giftIcon = payload?['gift_icon']?.toString() ??
          payload?['image_url']?.toString() ??
          payload?['gift']?['giftIconUrl']?.toString() ??
          payload?['gift']?['giftCoverUrl']?.toString() ??
          payload?['gift']?['iconAsset']?.toString() ??
          payload?['gift']?['default_image']?.toString() ??
          m.imageUrl;
      final count = payload?['count'] ?? 1;

      return Padding(
        padding: const EdgeInsets.only(top: 8, left: 8, right: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sender Avatar (iv_avatar 32×32)
            GestureDetector(
              onTap: () => _openChatUserProfile(m.senderUid, m.senderName, m.senderPhotoUrl),
              child: ClipOval(
                child: m.senderPhotoUrl.isNotEmpty
                    ? Image(
                        image: R.cachedImage(m.senderPhotoUrl),
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _defaultAvatar(),
                      )
                    : _defaultAvatar(),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender name + Level medal (tv_name 13sp white + user_level_medal)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        m.senderName.length > 15 ? m.senderName.substring(0, 15) : m.senderName,
                        style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      _buildUserLevelMedal(m.senderUid),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // cl_msg with room_chat_item_bg (corners 8dp, solid #33000000)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0x33000000),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // tv_send_gift_msg (13sp white)
                        Text(
                          receiverName.isNotEmpty
                              ? 'أرسل إلى $receiverName $giftName'
                              : (m.text.isNotEmpty ? m.text : 'أرسل هدية $giftName'),
                          style: const TextStyle(fontSize: 13, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // iv_gift_icon (40×40)
                            if (giftIcon != null && giftIcon.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: R.loadImage(
                                  giftIcon,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.contain,
                                ),
                              )
                            else
                              const Icon(Icons.card_giftcard, color: Color(0xFFFFEB3B), size: 32),
                            const SizedBox(width: 8),
                            // tv_gift_num (13sp, color #FFEB3B)
                            Text(
                              'x$count',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFFFFEB3B),
                                fontWeight: FontWeight.bold,
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
          ],
        ),
      );
    }

    if (m.type == 'lucky_gift') {
      final payload = m.giftPayload;
      final gift = payload?['gift'];
      final giftName = gift?['giftNameAr'] ?? gift?['giftName'] ?? payload?['gift_name'] ?? 'هدية الحظ';
      final giftIcon = payload?['gift_icon']?.toString() ??
          payload?['image_url']?.toString() ??
          gift?['giftIconUrl']?.toString() ??
          gift?['giftCoverUrl']?.toString() ??
          gift?['iconAsset']?.toString() ??
          gift?['default_image']?.toString() ??
          gift?['gift_icon']?.toString() ??
          payload?['image_url']?.toString() ??
          m.imageUrl;
      final results = payload?['results'];
      final totalWon = (results?['totalWonCoins'] as num?)?.toInt() ?? (payload?['won_coins'] as num?)?.toInt() ?? 0;
      final maxMultiplier = (results?['maxMultiplier'] as num?)?.toInt() ?? (payload?['multiplier'] as num?)?.toInt() ?? 0;
      final receiverName = payload?['receiver_name'] ?? payload?['receiver']?['nickname'] ?? '';
      final count = payload?['count'] ?? 1;

      final senderDisplayName = m.senderName.length > 14 ? m.senderName.substring(0, 14) : m.senderName;
      final hasWon = totalWon > 0 || maxMultiplier > 0;

      return Padding(
        padding: const EdgeInsets.only(top: 8, left: 8, right: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sender Avatar (32×32 circle with gold border if won)
            GestureDetector(
              onTap: () => _openChatUserProfile(m.senderUid, m.senderName, m.senderPhotoUrl),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: hasWon ? Border.all(color: const Color(0xFFFFD700), width: 1.5) : null,
                ),
                child: ClipOval(
                  child: m.senderPhotoUrl.isNotEmpty
                      ? Image(
                          image: R.cachedImage(m.senderPhotoUrl),
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _defaultAvatar(),
                        )
                      : _defaultAvatar(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender name + Level medal + Winner tag
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        senderDisplayName,
                        style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      _buildUserLevelMedal(m.senderUid),
                      if (hasWon) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF8008), Color(0xFFFFC837)],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isAr ? 'فوز حظ' : 'LUCKY WIN',
                            style: const TextStyle(fontSize: 9, color: Colors.black, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  // cl_msg (room_chat_item_bg)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0x33000000), // room_chat_item_bg (corners 8dp, #33000000)
                      borderRadius: BorderRadius.circular(8),
                      border: hasWon ? Border.all(color: const Color(0x66FFD700), width: 1) : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // tv_msg_notice / tv_send_gift_msg
                        Text(
                          hasWon
                              ? (isAr ? 'أرسل هدية الحظ وحصل على مكافأة مضاعفة!' : 'Hit the jackpot with a lucky multiplier!')
                              : (receiverName.toString().isNotEmpty
                                  ? 'أرسل هدية الحظ $giftName إلى $receiverName'
                                  : 'أرسل هدية الحظ $giftName'),
                          style: TextStyle(
                            fontSize: 12,
                            color: hasWon ? const Color(0xFFFFEB3B) : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // iv_gift_icon (40×40)
                            if (giftIcon != null && giftIcon.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: R.loadImage(
                                  giftIcon,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.contain,
                                ),
                              )
                            else
                              const Icon(Icons.stars_rounded, color: Color(0xFFFFD700), size: 32),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      giftName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (maxMultiplier > 0) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
                                          ),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${maxMultiplier}X',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                if (totalWon > 0)
                                  Row(
                                    children: [
                                      Image.asset(
                                        'assets/mipmap-xxhdpi/common_gold_ic_4.webp',
                                        width: 14,
                                        height: 14,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.monetization_on, color: Color(0xFFFFEB3B), size: 13),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '+$totalWon ${isAr ? 'عملة' : 'coins'}',
                                        style: const TextStyle(
                                          color: Color(0xFFFFEB3B),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Text(
                                    'x$count',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFFFEB3B),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                          ],
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

    if (m.type == 'entrance') {
      final isExit = m.text.contains('left') || m.text.contains('غادر');
      return Padding(
        padding: const EdgeInsets.only(top: 6, left: 8, right: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0x33000000), // room_chat_item_bg
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isExit ? Icons.logout : Icons.login,
                  size: 13,
                  color: isExit ? const Color(0xFFFF6B6B) : const Color(0xFF41FE88),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    isExit
                        ? '${m.senderName.isNotEmpty ? m.senderName : m.text} غادر الغرفة'
                        : 'انضم ${m.senderName.isNotEmpty ? m.senderName : m.text} إلى الغرفة',
                    style: TextStyle(
                      fontSize: 12,
                      color: isExit ? const Color(0xFFFF6B6B) : const Color(0xFF41FE88), // color_41FE88
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (m.type == 'system') {
      return Padding(
        padding: const EdgeInsets.only(top: 6, left: 8, right: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0x33000000),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              m.text,
              style: const TextStyle(fontSize: 12, color: Color(0xFF41FE88)),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openChatUserProfile(m.senderUid, m.senderName, m.senderPhotoUrl),
            child: ClipOval(
              child: m.senderPhotoUrl.isNotEmpty
                  ? Image(
                      image: R.cachedImage(m.senderPhotoUrl),
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _defaultAvatar(),
                    )
                  : _defaultAvatar(),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      m.senderName.length > 15
                          ? m.senderName.substring(0, 15)
                          : m.senderName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isMe ? AppColors.goldLight : Colors.white,
                      ),
                    ),
                    _buildUserLevelMedal(m.senderUid),
                  ],
                ),
                const SizedBox(height: 9),
                if (m.type == 'image' && m.imageUrl != null)
                  GestureDetector(
                    onTap: () => _showImagePreview(m.imageUrl!),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image(
                        image: R.cachedImage(m.imageUrl!),
                        width: 180,
                        height: 180,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 180,
                          height: 180,
                          color: const Color(0x33000000),
                          child: const Icon(Icons.broken_image, color: Colors.white54),
                        ),
                      ),
                    ),
                  )
                else
                  _buildChatBubble(
                    text: m.text,
                    isMe: isMe,
                    activeBubble: m.activeBubble,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _defaultAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        color: Color(0xFF2A2A2A),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.person, size: 18, color: Colors.white54),
    );
  }

  Widget _buildChatBubble({
    required String text,
    required bool isMe,
    String? activeBubble,
  }) {
    // In original Android app (adapter_chat_msg_text.xml & room_chat_item_bg.xml):
    // Standard chat bubble is Color(0x33000000) with 8dp radius for all users,
    // with 13sp white text (#FFFFFF).
    const bubbleColor = Color(0x33000000);
    const textColor = Colors.white;
    final borderRadius = BorderRadius.circular(8);

    Widget bubbleContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: textColor, height: 1.3),
      ),
    );

    String? bubbleUrl;
    if (activeBubble != null && activeBubble.isNotEmpty) {
      if (activeBubble.startsWith('http://') || activeBubble.startsWith('https://')) {
        bubbleUrl = activeBubble;
      } else {
        final storeItem = SupabaseService().getStoreItemSync(activeBubble) ??
            FirebaseService().getStoreItemSync(activeBubble);
        bubbleUrl = storeItem?.svgaAsset ?? storeItem?.videoAsset ?? storeItem?.iconAsset;
        if (bubbleUrl == null || bubbleUrl.isEmpty) {
          bubbleUrl = activeBubble;
        }
      }
    }

    if (bubbleUrl != null && bubbleUrl.isNotEmpty) {
      Widget bubbleBg;
      if (detectAssetType(bubbleUrl) == AssetType.svga) {
        bubbleBg = SvgaPlayer(
          assetPath: bubbleUrl,
          fit: BoxFit.fill,
        );
      } else if (bubbleUrl.startsWith('assets/')) {
        bubbleBg = Image.asset(
          bubbleUrl,
          fit: BoxFit.fill,
          errorBuilder: (_, __, ___) => Container(
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: borderRadius,
            ),
          ),
        );
      } else {
        bubbleBg = NinePatchImage(
          imageUrl: bubbleUrl,
          fit: BoxFit.fill,
          errorWidget: (_, url) => Container(
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: borderRadius,
            ),
          ),
        );
      }

      return Container(
        constraints: const BoxConstraints(maxWidth: 240),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
        ),
        child: Stack(
          children: [
            Positioned.fill(child: bubbleBg),
            bubbleContent,
          ],
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: borderRadius,
      ),
      child: bubbleContent,
    );
  }

  void _showImagePreview(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: InteractiveViewer(
            child: Image(image: R.cachedImage(url), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Widget _sheet(Widget child) =>
      Positioned(bottom: 0, left: 0, right: 0, child: child);

  // ── Emoji panel ───────────────────────────────────────────────
  Widget _buildEmojPanel() {
    final navH = MediaQuery.of(context).padding.bottom;
    final staticEmojis = ['😀', '😂', '🥰', '😎', '🤔', '😅', '😊', '🙂',
                   '❤️', '🔥', '💯', '✨', '🎉', '🎁', '👍', '👏',
                   '😢', '😡', '😱', '🤩', '😴', '🤗', '😇', '🤫'];
    
    final config = context.read<DynamicConfigService>();
    final dynamicEmojis = config.appAssets.values
        .where((a) => a.category == 'emoji' && a.isActive && (a.remoteUrl?.isNotEmpty ?? false))
        .map((a) => a.remoteUrl!)
        .toList();
        
    final emojis = [...dynamicEmojis, ...staticEmojis];
    
    // Find current user's seat
    int? currentUserSeat;
    for (int i = 0; i < _seats.length; i++) {
      if (_seats[i].user?.id == _currentUserId) {
        currentUserSeat = i;
        break;
      }
    }
    
    return Positioned(
      bottom: navH + 63,
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          height: 220,
          decoration: const BoxDecoration(
            color: Color(0xF51D1111),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: const [
                    _EmojiTab(label: '😀', selected: true),
                    _EmojiTab(label: '❤️'),
                    _EmojiTab(label: '🎁'),
                    _EmojiTab(label: '🎵'),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 15),
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 8,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: emojis.length,
                    itemBuilder: (_, idx) => GestureDetector(
                      onTap: () {
                        // Show emoji on current user's seat
                        if (currentUserSeat != null) {
                          final seat = currentUserSeat;
                          setState(() {
                            _seatEmojis[seat] = emojis[idx];
                          });
                          // Clear emoji after some time
                          Future.delayed(const Duration(seconds: 3), () {
                            if (mounted) {
                              setState(() {
                                if (_seatEmojis[seat] == emojis[idx]) {
                                  _seatEmojis.remove(seat);
                                }
                              });
                            }
                          });
                        }
                        
                        // Send emoji directly to chat
                        final userProvider = Provider.of<UserProvider>(context, listen: false);
                        final user = userProvider.currentUser;
                        if (user != null) {
                          if (emojis[idx].startsWith('http')) {
                            _firebaseService.sendImageMessage(
                              widget.roomId, emojis[idx], user.uid, user.name, user.photoUrl,
                            );
                          } else {
                            _firebaseService.sendMessage(
                              widget.roomId, emojis[idx], user.uid, user.name, user.photoUrl,
                              activeBubble: user.activeBubble,
                            );
                          }
                        }
                        
                        setState(() => _showEmoj = false);
                      },
                      child: Center(
                        child: emojis[idx].startsWith('http')
                            ? Image.network(emojis[idx], width: 40, height: 40, fit: BoxFit.contain)
                            : Text(emojis[idx], style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Chat input bar ────────────────────────────────────────────
  Widget _buildChatInputBar() {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xF51D1111), // shape_room_chat_bg
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const SizedBox(width: 15),
              GestureDetector(
                onTap: _pickRoomImage,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0x1AFFFFFF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.image, size: 20, color: Colors.white70),
                ),
              ),
              const SizedBox(width: 10),
              // edit_text (shape_room_input_bg)
              Expanded(
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0x33000000), // shape_room_input_bg
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: TextField(
                    controller: _chatCtrl,
                    autofocus: true,
                    style: const TextStyle(fontSize: 15, color: Colors.white), // color_FFFFFF
                    decoration: InputDecoration(
                      hintText: isAr ? 'قل شيئاً...' : 'Say something...',
                      hintStyle: const TextStyle(
                        fontSize: 15,
                        color: Color(0x66FFFFFF), // color_66ffffff
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                    maxLines: 1,
                    maxLength: 100,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // send_btn (shape_room_input_btn_send_bg)
              GestureDetector(
                onTap: _sendMessage,
                child: Container(
                  height: 36,
                  constraints: const BoxConstraints(minWidth: 70),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  margin: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFFFC525), Color(0xFFDE880F)], // shape_room_input_btn_send_bg
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    isAr ? 'إرسال' : 'Send',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Room info sheet — fragment_room_owner_fragment.xml ─────────
  Widget _buildRoomInfoSheet(double sizeH) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final hostUid = _currentRoom?.hostUid.isNotEmpty == true
        ? _currentRoom!.hostUid
        : (_seats.isNotEmpty ? (_seats[0].user?.id ?? '') : '');
    if (_hostCustomId == null || _hostCustomId!.isEmpty) {
      _resolveHostCustomId(hostUid);
    }
    final hostDisplayId = (_hostCustomId != null && _hostCustomId!.isNotEmpty)
        ? _hostCustomId!
        : (UserProfile.customIdCache[hostUid] ??
            (_seats.isNotEmpty && _seats[0].user?.id == hostUid ? _seats[0].user?.customId : null) ??
            '...');

    final totalCoins = _currentRoom?.totalGifts ?? _currentRoom?.hotValue ?? 0;
    final todayCoins = (totalCoins * 0.25).toInt();
    final weekCoins = (totalCoins * 0.65).toInt();
    final monthCoins = totalCoins;
    final roomLevel = max(1, (totalCoins / 1000).floor() + 1);

    final roomBg = _currentRoom?.bgImage.isNotEmpty == true
        ? _currentRoom!.bgImage
        : 'assets/images/room_bg_friend.webp';

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          height: sizeH * 0.80,
          decoration: const BoxDecoration(
            color: Color(0xFF0F0909), // room_info_owner_bg
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Stack(
              children: [
                // iv_room_bg: خلفية الغرفة الأساسية في أعلى النافذة
                Positioned.fill(
                  child: roomBg.startsWith('http')
                      ? Image.network(roomBg, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Image.asset('assets/images/room_bg_friend.webp', fit: BoxFit.cover))
                      : Image.asset(roomBg, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                ),
                // iv_room_mask: قناع التعتيم الأصلي المتدرج
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.98,
                    child: Image.asset(
                      'assets/images/room_owner_info_mask_bg.9.png',
                      fit: BoxFit.fill,
                    ),
                  ),
                ),
                // المحتوى الرئيسي وعلامات التبويب
                DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      // شريط السحب العلوي
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 8, bottom: 4),
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0x33FFFFFF),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // tab_room_info: شريط التبويب الأصلي
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: TabBar(
                                indicatorColor: const Color(0xFFFFFCCE5E),
                                indicatorWeight: 3,
                                indicatorSize: TabBarIndicatorSize.label,
                                labelColor: Colors.white,
                                unselectedLabelColor: const Color(0x80FFFFFF),
                                labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                unselectedLabelStyle: const TextStyle(fontSize: 14),
                                tabs: [
                                  Tab(text: isAr ? 'معلومات الغرفة' : 'Room Info'),
                                  Tab(text: isAr ? 'بيانات الغرفة' : 'Room Data'),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _showRoomInfo = false),
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.close, color: Colors.white70, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(height: 0.5, color: const Color(0x1AFFFFFF)),
                      Expanded(
                        child: TabBarView(
                          children: [
                            // ── Tab 1: Room Card (room_card_info_fragment.xml) ──
                            SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // tv_room_title
                                  Text(
                                    isAr ? 'معلومات الغرفة' : 'Room Info',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // بطاقة الغرفة — room_owner_info_room_bg
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      image: const DecorationImage(
                                        image: AssetImage('assets/images/room_owner_info_room_bg.9.png'),
                                        fit: BoxFit.fill,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        // iv_room_avatar (RoundImageView 72dp)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: SizedBox(
                                            width: 72,
                                            height: 72,
                                            child: _memberAvatar(
                                              _currentRoom?.roomPhotoUrl.isNotEmpty == true
                                                  ? _currentRoom!.roomPhotoUrl
                                                  : _seats[0].user?.avatar,
                                              72,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // tv_room_name + iv_room_country
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      _currentRoom?.name.isNotEmpty == true
                                                          ? _currentRoom!.name
                                                          : widget.roomName,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  if (_currentRoom?.country != null && _currentRoom!.country.isNotEmpty) ...[
                                                    const SizedBox(width: 6),
                                                    Text(_currentRoom!.country, style: const TextStyle(fontSize: 14)),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              // room_id_view
                                              UserIdWidget(
                                                idText: widget.roomId,
                                                showCopy: true,
                                                fontSize: 11,
                                              ),
                                              const SizedBox(height: 6),
                                              // tv_room_type
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFFC525).withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: Text(
                                                  _currentRoom?.category.isNotEmpty == true ? _currentRoom!.category : (widget.gameDesc.isNotEmpty ? widget.gameDesc : (isAr ? 'دردشة' : 'Chat')),
                                                  style: const TextStyle(fontSize: 9, color: Color(0xFFFFC525), fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (_isOwnerOrModerator) ...[
                                          GestureDetector(
                                            onTap: () {
                                              setState(() => _showRoomInfo = false);
                                              _openSettings();
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.08),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.edit, color: Color(0xFFFFC525), size: 20),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        GestureDetector(
                                          onTap: () {
                                            setState(() => _showRoomInfo = false);
                                            _openReport();
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.08),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.flag_outlined, color: Colors.white70, size: 20),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  // room_owner_title
                                  Text(
                                    isAr ? 'صاحب الغرفة' : 'Room Owner',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // بيانات صاحب الغرفة (iv_avatar + user_info_view + user_id_view)
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      ClipOval(
                                        child: SizedBox(
                                          width: 72,
                                          height: 72,
                                          child: _memberAvatar(
                                            _currentRoom?.hostPhotoUrl.isNotEmpty == true
                                                ? _currentRoom!.hostPhotoUrl
                                                : _seats[0].user?.avatar,
                                            72,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _currentRoom?.hostName.isNotEmpty == true
                                                  ? _currentRoom!.hostName
                                                  : widget.hostName,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            // المعرف الرقمي الصريح للمستخدم — أرقام فقط مع زر النسخ الأصلي
                                            UserIdWidget(
                                              idText: hostDisplayId,
                                              showCopy: true,
                                              fontSize: 12,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  // room_owner_notice_title
                                  Text(
                                    isAr ? 'إعلان الغرفة' : 'Room Announcement',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // tv_notice — room_notice_bg
                                  Container(
                                    width: double.infinity,
                                    constraints: const BoxConstraints(minHeight: 105),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0x0FFFFFFF), // room_notice_bg
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _currentRoom?.announcement.isNotEmpty == true
                                          ? _currentRoom!.announcement
                                          : (_currentRoom?.description.isNotEmpty == true
                                              ? _currentRoom!.description
                                              : (isAr ? 'مرحباً بكم في غرفتنا! نتمنى لكم قضاء أجمل الأوقات 🎉' : 'Welcome to our room! Enjoy your time 🎉')),
                                      style: const TextStyle(fontSize: 13, color: Colors.white, height: 1.4),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // ll_follow — btn_shape_confirm_12_bg
                                  GestureDetector(
                                    onTap: _toggleFollow,
                                    child: Container(
                                      width: double.infinity,
                                      height: 50,
                                      margin: const EdgeInsets.only(top: 8, bottom: 12),
                                      decoration: BoxDecoration(
                                        gradient: _isFollowed
                                            ? const LinearGradient(colors: [Color(0xFF555555), Color(0xFF444444)])
                                            : const LinearGradient(
                                                begin: Alignment.bottomCenter,
                                                end: Alignment.topCenter,
                                                colors: [Color(0xFFFCCE5E), Color(0xFFD19C3B)], // btn_shape_confirm_12_bg
                                              ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            _isFollowed ? Icons.favorite : Icons.favorite_border,
                                            color: Colors.white,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _isFollowed ? (isAr ? 'إلغاء المتابعة' : 'Unfollow') : (isAr ? 'متابعة' : 'Follow'),
                                            style: const TextStyle(
                                              fontSize: 15,
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
                            ),

                            // ── Tab 2: Room Data & Levels (room_data_info_fragment.xml) ──
                            SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // room_owner_data_introduce_title
                                  Text(
                                    isAr ? 'بيانات الغرفة' : 'Room Data',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // بطاقة الكوينز الكبرى — room_owner_data_coin_bg
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      image: const DecorationImage(
                                        image: AssetImage('assets/images/room_owner_data_coin_bg.9.png'),
                                        fit: BoxFit.fill,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        // tv_room_coin (20sp bold gold FFFFF5AD + common_gold_ic_5)
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Image.asset(
                                              'assets/images/common_gold_ic_5.webp',
                                              width: 26,
                                              height: 26,
                                              errorBuilder: (_, __, ___) => const Icon(
                                                Icons.monetization_on,
                                                color: Color(0xFFFFD700),
                                                size: 26,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '$totalCoins',
                                              style: const TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFFFFF5AD),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        // room_owner_data_histroy_coin_title
                                        Text(
                                          isAr ? 'إجمالي عملات الغرفة التاريخية' : 'Total Historical Room Coins',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF979797),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // مستوى الغرفة الحالي
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: const Color(0x14FFFFFF),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                gradient: AppColors.giftBtnGradient,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                'Lv.$roomLevel',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              isAr ? 'مستوى الغرفة الحالي' : 'Current Room Level',
                                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                            ),
                                            const Spacer(),
                                            Text(
                                              '${totalCoins % 1000} / 1000',
                                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: ((totalCoins % 1000) / 1000.0).clamp(0.0, 1.0),
                                            minHeight: 7,
                                            backgroundColor: Colors.white12,
                                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFC525)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // adapter_room_owner_data_coin_item
                                  _buildDataCoinRow(isAr ? 'اليوم' : 'Today', todayCoins),
                                  const SizedBox(height: 10),
                                  _buildDataCoinRow(isAr ? 'هذا الأسبوع' : 'This Week', weekCoins),
                                  const SizedBox(height: 10),
                                  _buildDataCoinRow(isAr ? 'هذا الشهر' : 'This Month', monthCoins),
                                  const SizedBox(height: 10),
                                  _buildDataCoinRow(isAr ? 'الكل' : 'All Time', totalCoins),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // adapter_room_owner_data_coin_item.xml
  Widget _buildDataCoinRow(String label, int coins) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF), // room_room_owner_data_item_bg
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // tv_time (12sp #979797)
          Text(
            label,
            style: const TextStyle(color: Color(0xFF979797), fontSize: 12),
          ),
          const SizedBox(height: 10),
          // tv_coin (17sp bold gold #FFFFF5AD + common_gold_ic_5)
          Row(
            children: [
              Image.asset(
                'assets/images/common_gold_ic_5.webp',
                width: 20,
                height: 20,
                errorBuilder: (_, __, ___) => const Icon(Icons.monetization_on, color: Color(0xFFFFD700), size: 20),
              ),
              const SizedBox(width: 6),
              Text(
                '$coins',
                style: const TextStyle(
                  color: Color(0xFFFFF5AD),
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Member list ───────────────────────────────────────────────
  void _showMembersSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final occupiedSeats = _seats.where((s) => s.isOccupied && s.user != null).toList();
        final currentUserId = _currentUserId ?? '';
        final seatedUserIds = occupiedSeats.map((s) => s.user!.id).toSet();

        // Combine seated users and current user if not seated
        final displayUsers = <Map<String, dynamic>>[];
        for (final seat in occupiedSeats) {
          final u = seat.user!;
          displayUsers.add({
            'user': u,
            'isOnMic': true,
            'isMuted': seat.isMuted,
            'seatIndex': seat.index,
          });
        }
        final currentUser = Provider.of<UserProvider>(context, listen: false).currentUser;
        if (currentUser != null && !seatedUserIds.contains(currentUser.uid)) {
          displayUsers.add({
            'user': UserModel(
              id: currentUser.uid,
              name: currentUser.name,
              avatar: currentUser.photoUrl,
              level: currentUser.level,
              customId: currentUser.customId,
            ),
            'isOnMic': false,
            'isMuted': false,
            'seatIndex': -1,
          });
        }

        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // Drag handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 10),
              // idTitleTip
              const Text(
                'المتواجدين',
                style: TextStyle(
                  color: Color(0xFF333333),
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'المتواجدين: $_onlineCount',
                    style: const TextStyle(color: Color(0xFF999999), fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: displayUsers.isEmpty
                    ? const Center(
                        child: Text('لا يوجد مستخدمون متصلون', style: TextStyle(color: Color(0xFF999999), fontSize: 14)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: displayUsers.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0x1A000000)),
                        itemBuilder: (context, index) {
                          final item = displayUsers[index];
                          final u = item['user'] as UserModel;
                          final bool isOnMic = item['isOnMic'] as bool;
                          final bool isMuted = item['isMuted'] as bool;
                          final bool isMale = true; // default

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // iv_avatar (48×48)
                                GestureDetector(
                                  onTap: () {
                                    Navigator.pop(context);
                                    _openChatUserProfile(u.id ?? '', u.name, u.avatar ?? '');
                                  },
                                  child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: ClipOval(
                                      child: _memberAvatar(u.avatar, 48),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // User info column
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              u.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Color(0xFF16151A),
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          if (isOnMic) ...[
                                            const SizedBox(width: 4),
                                            Image.asset(
                                              R.mipmap('room_mic_label_ic'),
                                              width: 19,
                                              height: 16,
                                              errorBuilder: (_, __, ___) => Icon(
                                                isMuted ? Icons.mic_off : Icons.mic,
                                                size: 14,
                                                color: const Color(0xFFDE880F),
                                              ),
                                            ),
                                          ],
                                          const SizedBox(width: 4),
                                          Image.asset(
                                            isMale ? R.mipmap('sex_male_ic') : R.mipmap('sex_female_ic'),
                                            width: 18,
                                            height: 16,
                                            errorBuilder: (_, __, ___) => Icon(
                                              isMale ? Icons.male : Icons.female,
                                              size: 14,
                                              color: const Color(0xFF4A90E2),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      // Level View / Medal
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFFFFC525), Color(0xFFDE880F)],
                                          ),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.star, size: 10, color: Colors.white),
                                            const SizedBox(width: 2),
                                            Text(
                                              'Lv.${u.level}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // tv_kick_out / action button (room_user_kick_out_btn_bg)
                                GestureDetector(
                                  onTap: () {
                                    Navigator.pop(context);
                                    if (!isOnMic) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('تمت دعوة ${u.name} للمايك')),
                                      );
                                    } else {
                                      _openChatUserProfile(u.id ?? '', u.name, u.avatar ?? '');
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: const Color(0xFFDE880F), width: 1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      isOnMic ? 'الملف الشخصي' : 'دعوة للمايك',
                                      style: const TextStyle(
                                        color: Color(0xFFDE880F),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }



  // ── Notifications sheet — layout_adapter_notice_item.xml ──────
  Widget _buildNotificationsSheet() {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final double screenH = MediaQuery.of(context).size.height;
    final giftNotices = _sentGifts.reversed.take(30).toList();

    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showNotifications = false),
        child: Container(
          color: Colors.black54,
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              height: screenH * 0.65,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF1B1A24),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, -4)),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Text(
                            isAr ? 'إشعارات الغرفة والهدايا' : 'Room Notifications',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => setState(() => _showNotifications = false),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(color: Colors.white12, shape: BoxShape.circle),
                              child: const Icon(Icons.close, color: Colors.white70, size: 18),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 1),
                    Expanded(
                      child: giftNotices.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.notifications_none_rounded, size: 48, color: Colors.white24),
                                  const SizedBox(height: 10),
                                  Text(
                                    isAr ? 'لا توجد إشعارات هدايا حالياً' : 'No gift notifications yet',
                                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              itemCount: giftNotices.length,
                              itemBuilder: (ctx, index) {
                                final gift = giftNotices[index];
                                final senderName = gift.senderName.isNotEmpty ? gift.senderName : (isAr ? 'مستخدم' : 'User');
                                final receiverName = gift.receiverName.isNotEmpty ? gift.receiverName : (isAr ? 'الجميع' : 'All');
                                final giftName = gift.giftName;
                                final giftCount = gift.giftCount > 0 ? gift.giftCount : 1;
                                final iconAsset = gift.iconAsset;
                                final defaultImg = gift.defaultImage;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0x22FFFFFF),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0x1AFFFFFF)),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: Colors.white12,
                                        backgroundImage: gift.senderAvatar.isNotEmpty
                                            ? (gift.senderAvatar.startsWith('http')
                                                ? NetworkImage(gift.senderAvatar) as ImageProvider
                                                : AssetImage(gift.senderAvatar))
                                            : null,
                                        child: gift.senderAvatar.isEmpty
                                            ? const Icon(Icons.person, color: Colors.white54, size: 18)
                                            : null,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              senderName,
                                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${isAr ? "أرسل إلى" : "Sent to"} $receiverName: $giftName',
                                              style: const TextStyle(color: Color(0xFFFFA726), fontSize: 12),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (iconAsset.isNotEmpty || defaultImg.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: iconAsset.isNotEmpty
                                              ? R.image(iconAsset, width: 36, height: 36, fit: BoxFit.contain)
                                              : (defaultImg.startsWith('http')
                                                  ? Image.network(defaultImg, width: 36, height: 36, fit: BoxFit.contain)
                                                  : R.image(defaultImg, width: 36, height: 36, fit: BoxFit.contain)),
                                        ),
                                      ],
                                      const SizedBox(width: 8),
                                      Text(
                                        'x$giftCount',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFFFFF456),
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Minimize / Exit ─────────────────────────────────────────
  void _minimizeRoom() {
    setState(() => _showExit = false);
    _isMinimized = true;
    MinimizedRoomService().activate(
      roomId: widget.roomId,
      roomName: widget.roomName,
      hostName: widget.hostName,
      roomPassword: widget.roomPassword.isNotEmpty ? widget.roomPassword : null,
      hotValue: widget.hotValue,
      gameDesc: widget.gameDesc,
      roomPhoto: _currentRoom?.roomPhotoUrl ?? _seats[0].user?.avatar,
    );
    Navigator.of(context).pop();
  }

  Future<void> _leaveRoomSession() async {
    if (_currentUserId == null) return;
    final uid = _currentUserId!;
    final name = _currentUserName;
    final roomId = widget.roomId;

    for (int i = 0; i < _seats.length; i++) {
      if (_seats[i].user?.id == uid) {
        _seats[i].state = SeatState.empty;
        _seats[i].user = null;
        try {
          await _firebaseService.leaveSeat(roomId, i);
        } catch (_) {}
      }
    }

    try {
      await _firebaseService.leaveSeatForUser(roomId, uid);
    } catch (_) {}

    if (name != null && name.isNotEmpty) {
      try {
        await _firebaseService.logExit(roomId, name);
      } catch (_) {}
    }

    try {
      await _firebaseService.leaveRoom(roomId, uid);
    } catch (_) {}
  }

  void _cleanupUserSession() {
    _leaveRoomSession();
  }

  // ────────────────────────────────────────────────────────────
  // PRESENCE PING — نظام كشف وإزالة المستخدمين الصامتين (Zombie users)
  // ────────────────────────────────────────────────────────────

  /// يبدأ ping دوري كل 90 ثانية يحدّث حقل last_ping في Firestore.
  /// إذا توقف الـ ping (انقطع الاتصال / أغلق التطبيق) يُزال المستخدم
  /// تلقائياً بواسطة TTL checker عند دخول أي مستخدم للغرفة.
  void _startPresencePing() {
    _presencePingTimer?.cancel();
    _presencePingTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      _updatePresencePing();
    });
    // أول ping فوري عند الدخول
    _updatePresencePing();
  }

  /// يرسل ping (يحدّث last_ping timestamp) لإثبات أن المستخدم ما زال في الغرفة.
  void _updatePresencePing() {
    if (_currentUserId == null) return;
    final uid = _currentUserId!;
    final roomId = widget.roomId;
    // Fire-and-forget: لا نريد انتظار النتيجة
    FirebaseFirestore.instance
        .collection('room_members')
        .doc('${roomId}_$uid')
        .update({'last_ping': FieldValue.serverTimestamp()})
        .catchError((_) {}); // تجاهل الأخطاء (المستخدم ربما لم يُسجَّل بعد)
  }

  /// يبحث عن أعضاء الغرفة الذين لم يرسلوا ping منذ أكثر من 5 دقائق
  /// ويحذفهم من Firestore — يُستدعى عند كل انضمام جديد.
  Future<void> _cleanupZombieUsers() async {
    try {
      final cutoff = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(minutes: 5)),
      );
      final snap = await FirebaseFirestore.instance
          .collection('room_members')
          .where('room_id', isEqualTo: widget.roomId)
          .get();
      int cleanedCount = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final lastPing = data['last_ping'];
        if (lastPing is Timestamp && lastPing.compareTo(cutoff) < 0) {
          final uid = data['uid'] as String?;
          if (uid == null) continue;
          await doc.reference.delete();
          await _firebaseService.leaveSeatForUser(widget.roomId, uid);
          cleanedCount++;
        }
      }
      if (cleanedCount > 0) {
        debugPrint('Cleaned $cleanedCount zombie user(s) from room ${widget.roomId}');
      }
    } catch (e) {
      debugPrint('_cleanupZombieUsers error (non-fatal): $e');
    }
  }

  void _exitRoom() {
    setState(() => _showExit = false);
    _leaveRoomSession();
    _roomAudio.dispose();
    Navigator.of(context).pop();
  }

  void _checkRoomBan(String uid) {
    _firebaseService.isUserBlockedFromRoom(widget.roomId, uid).then((isBlocked) {
      if (isBlocked && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are banned from this room'), duration: Duration(seconds: 3)),
        );
        Navigator.of(context).pop();
      }
    });
  }

  void _toggleFollow() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user == null) return;
    if (_isFollowed) {
      _firebaseService.unfollowRoom(user.uid, widget.roomId);
    } else {
      _firebaseService.followRoom(user.uid, widget.roomId);
    }
    setState(() => _isFollowed = !_isFollowed);
  }

  Widget _memberAvatar(String? avatar, double size) {
    if (avatar == null || avatar.isEmpty) {
      return R.image(R.avaBoy, width: size, height: size, fit: BoxFit.cover);
    }
    if (avatar.startsWith('http://') || avatar.startsWith('https://')) {
      return Image(
        image: R.cachedImage(avatar),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => R.image(
          R.avaBoy, width: size, height: size, fit: BoxFit.cover,
        ),
      );
    }
    return Image.asset(
      avatar,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Image.asset(
        R.avaBoy, width: size, height: size, fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildExitDialog() {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showExit = false),
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: const Color(0xB3000000),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Minimize Room Button (ll_room_minimize from dialog_room_colose_toip.xml)
                GestureDetector(
                  onTap: () {
                    setState(() => _showExit = false);
                    _minimizeRoom();
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/room_dialog_minimize_ic.webp',
                        width: 88,
                        height: 88,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isAr ? 'تصغير الغرفة' : 'Minimize Room',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                // Exit Room Button (ll_room_exit from dialog_room_colose_toip.xml)
                GestureDetector(
                  onTap: () {
                    setState(() => _showExit = false);
                    _exitRoom();
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/room_dialog_exit_ic.webp',
                        width: 88,
                        height: 88,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isAr ? 'الخروج من الغرفة' : 'Exit Room',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Share dialog ───────────────────────────────────────────────
  Widget _buildShare() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showShare = false),
        child: Container(
          color: Colors.black54,
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF211211),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Share Room',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildShareItem('WhatsApp', Icons.chat, Colors.green),
                        _buildShareItem('Facebook', Icons.facebook, Colors.blue),
                        _buildShareItem('Twitter', Icons.flutter_dash, Colors.lightBlue),
                        _buildShareItem('Copy Link', Icons.link, Colors.grey),
                      ],
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () => setState(() => _showShare = false),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShareItem(String label, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  // ── Gift count popup (adapter_gift_count_item.xml / room_gift_count_bg.xml) ──
  void _showGiftCountMenu() {
    const counts = [1314, 520, 188, 88, 66, 10, 1];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Center(
        child: Container(
          width: 140,
          margin: const EdgeInsets.only(bottom: 50),
          decoration: BoxDecoration(
            color: const Color(0xFF372928), // room_gift_count_bg
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 10, spreadRadius: 2),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < counts.length; i++) ...[
                InkWell(
                  onTap: () {
                    setState(() => _giftCount = counts[i]);
                    Navigator.pop(ctx);
                  },
                  borderRadius: BorderRadius.vertical(
                    top: i == 0 ? const Radius.circular(8) : Radius.zero,
                    bottom: i == counts.length - 1 ? const Radius.circular(8) : Radius.zero,
                  ),
                  child: Container(
                    height: 33, // adapter_gift_count_item tv_item_count height
                    alignment: Alignment.center,
                    child: Text(
                      '${counts[i]}',
                      style: TextStyle(
                        fontSize: 12, // 12sp
                        color: _giftCount == counts[i] ? const Color(0xFFFFD856) : Colors.white,
                        fontWeight: _giftCount == counts[i] ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
                if (i < counts.length - 1)
                  Container(
                    height: 2, // view_line 2dp
                    color: const Color(0xFF211211), // color_211211
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showCustomCountDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF231B2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('أدخل كمية الإرسال', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: InputDecoration(
            hintText: 'مثال: 50, 100, 500, 999...',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD3A350),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final val = int.tryParse(controller.text.trim());
              if (val != null && val > 0) {
                setState(() => _giftCount = val);
              }
              Navigator.pop(dCtx);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }
}

// ── Emoji tab ────────────────────────────────────────────────────
class _EmojiTab extends StatelessWidget {
  final String label;
  final bool selected;
  const _EmojiTab({required this.label, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 22,
          color: selected ? Colors.white : Colors.white54,
        ),
      ),
    );
  }
}



/// حالة زر الكومبو — Immutable لتجنب إعادة رسم شاشة الغرفة كلها
class _ComboState {
  final int seconds;
  final int multiplier;
  final bool firing;
  const _ComboState(this.seconds, this.multiplier, this.firing);
}
