import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/widgets/cached_image.dart';
import '../../config/r.dart';
import '../../services/dynamic_config_service.dart';
import '../../services/media_prefetch_service.dart';
import '../../services/supabase_service.dart';
import '../../services/supabase_data_service.dart';
import '../../models/room_model.dart';
import '../../providers/user_provider.dart';
import 'create_room_screen.dart';
import '../../services/room_state_service.dart';
import '../../screens/room/room_screen.dart' show navigateToRoom;
import '../../screens/room/widgets/svga_player.dart';
import '../../screens/room/widgets/vap_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../screens/rank/rank_screen.dart';
import 'global_search_delegate.dart';
import 'package:zero/core/dtext.dart';
import '../../widgets/user_id_widget.dart';
import '../../widgets/banner_carousel.dart';
import '../../features/signin/weekly_signin_screen.dart';
import '../../features/signin/signin_service.dart';

class RoomDiscoverScreen extends StatefulWidget {
  const RoomDiscoverScreen({super.key});

  @override
  State<RoomDiscoverScreen> createState() => _RoomDiscoverScreenState();
}

class _AudioWaveIndicator extends StatefulWidget {
  const _AudioWaveIndicator();
  @override
  State<_AudioWaveIndicator> createState() => _AudioWaveIndicatorState();
}

class _AudioWaveIndicatorState extends State<_AudioWaveIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final v = _ctrl.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(width: 2.5, height: 4 + (v * 8), decoration: BoxDecoration(color: const Color(0xFFFFD700), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 2),
            Container(width: 2.5, height: 12 - (v * 8), decoration: BoxDecoration(color: const Color(0xFFFFD700), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 2),
            Container(width: 2.5, height: 6 + (v * 6), decoration: BoxDecoration(color: const Color(0xFFFFD700), borderRadius: BorderRadius.circular(2))),
          ],
        );
      },
    );
  }
}

class _DailySigninFloatingBadge extends StatefulWidget {
  const _DailySigninFloatingBadge();

  @override
  State<_DailySigninFloatingBadge> createState() => _DailySigninFloatingBadgeState();
}

class _DailySigninFloatingBadgeState extends State<_DailySigninFloatingBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _scaleAnim;
  bool _hasClaimed = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _scaleAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _checkStatus();
  }

  Future<void> _checkStatus() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;
      if (uid != null) {
        final claimed = await SigninService.hasClaimedToday(uid);
        if (mounted) setState(() => _hasClaimed = claimed);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await WeeklySigninScreen.show(context);
        _checkStatus();
      },
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) => Transform.scale(
          scale: _hasClaimed ? 1.0 : _scaleAnim.value,
          child: child,
        ),
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7B1FA2).withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipOval(
                child: Image.asset(
                  // بعد تسجيل الوصول اليومي تتحول الأيقونة للصورة المميزة
                  _hasClaimed
                      ? 'assets/images/ic_daily_signin_claimed.png'
                      : 'assets/images/ic_daily_signin_badge.png',
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                ),
              ),
              if (!_hasClaimed)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF1744),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomDiscoverScreenState extends State<RoomDiscoverScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseService _firebaseService = SupabaseService();
  late Stream<List<RoomModel>> _roomsStream;
  List<RoomModel>? _cachedRooms;
  RoomModel? _myRoom;
  late TabController _tabController;
  int _selectedTabIndex = 1;
  final String _searchQuery = '';
  String? _selectedCountry;
  String _lastRoomsSignature = '';
  static const String _roomsCachePrefsKey = 'discover_rooms_cache_v1';

  /// أول 3 مراكز في تصنيفات المتصدرين اليومي (ثروة/كرزمة/غرف)
  /// تُعرض داخل بطاقات التصنيفات أسفل شريط الدول
  Map<String, List<Map<String, dynamic>>> _topDailyRankings = {};

  @override
  void initState() {
    super.initState();
    _roomsStream = _firebaseService.allRoomsStream().asBroadcastStream();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 1);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedTabIndex = _tabController.index);
      }
    });
    unawaited(_restoreCachedRooms());

    // ✅ تحميل «غرفتي» فوراً (مهم للمستخدم)، وتأجيل الترتيب الثقيل
    //    حتى تظهر الغرف أولاً — يقلّل الضغط على الشبكة عند فتح الشاشة.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadMyRoom());
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) unawaited(_loadTopDailyRankings());
      });
    });
  }

  /// يجلب **المتصدر الأول** في الترتيب اليومي لكل تصنيف
  /// (الثروة، الكرزمة/الجاذبية، الغرف) لعرضه في بطاقات الاستكشاف.
  ///
  /// عند فشل الجلب (شبكة بطيئة عند فتح التطبيق) تُعاد المحاولة تلقائياً
  /// في الخلفية — وإلا بقيت البطاقات بلا صور المتصدرين حتى إعادة تشغيل
  /// التطبيق، لأن الشاشة تبقى حيّة داخل IndexedStack.
  bool _rankingsLoading = false;
  bool _rankingsReady = false;
  int _rankingsAttempts = 0;
  Timer? _rankingsRetry;

  Future<void> _loadTopDailyRankings({bool force = false}) async {
    if (_rankingsLoading) return;
    if (!force && _rankingsReady) return;
    _rankingsLoading = true;
    if (force) _rankingsAttempts = 0;
    _rankingsRetry?.cancel();

    Map<String, List<Map<String, dynamic>>> result = const {};

    // 1) المصدر الأول: نفس Views شاشة الترتيب — مهلة أقصر (8s بدل 15s)
    //    حتى لا ينتظر المستخدم طويلاً قبل الانتقال للاحتياطي.
    try {
      final views = await _firebaseService
          .getDailyTopRankingsFromViews()
          .timeout(const Duration(seconds: 8), onTimeout: () => const {});
      if (views.values.any((l) => l.isNotEmpty)) result = views;
    } catch (_) {}

    // 2) احتياطي: حساب الترتيب من جدول الهدايا مباشرةً — مهل أقصر
    //    (20s/25s بدل 30s/40s) لأن الجلب أصبح مُرقّماً ويتجاوز سقف PostgREST.
    if (result.isEmpty) {
      try {
        final snapshots = await _firebaseService
            .getRankingGiftSnapshots(timeframes: ['daily'])
            .timeout(const Duration(seconds: 20), onTimeout: () => const {});
        final gifts = snapshots['daily'];
        final results = await Future.wait<List<Map<String, dynamic>>>([
          _firebaseService.getGlobalRankings(
              isWealth: true, timeframe: 'daily', gifts: gifts),
          _firebaseService.getGlobalRankings(
              isWealth: false, timeframe: 'daily', gifts: gifts),
          _firebaseService.getRoomGlobalRanking(
              timeframe: 'daily', gifts: gifts),
        ]).timeout(const Duration(seconds: 25),
            onTimeout: () => <List<Map<String, dynamic>>>[[], [], []]);
        result = {
          'wealth': results[0],
          'charm': results[1],
          'rooms': results[2],
        };
      } catch (_) {}
    }

    _rankingsLoading = false;
    if (!mounted) return;

    const keys = ['wealth', 'charm', 'rooms'];
    final anyData = keys.any((k) => (result[k] ?? const []).isNotEmpty);
    final allData = keys.every((k) => (result[k] ?? const []).isNotEmpty);

    if (anyData) {
      setState(() {
        _topDailyRankings = {
          'wealth': (result['wealth'] ?? const []).take(1).toList(),
          'charm': (result['charm'] ?? const []).take(1).toList(),
          'rooms': (result['rooms'] ?? const []).take(1).toList(),
        };
      });
    }

    if (allData) {
      _rankingsReady = true;
      return;
    }

    // بيانات ناقصة (شبكة/تصنيف فارغ) — إعادة محاولة صامتة في الخلفية
    _rankingsAttempts++;
    final maxAttempts = anyData ? 5 : 20;
    if (_rankingsAttempts < maxAttempts) {
      _rankingsRetry = Timer(const Duration(seconds: 15), () {
        unawaited(_loadTopDailyRankings());
      });
    }
  }

  /// آخر قائمة غرف محفوظة محلياً — تُعرض فوراً عند فتح الاستكشاف
  /// قبل وصول بيانات السيرفر، فلا تبقى الشاشة فارغة أثناء التحميل
  Future<void> _restoreCachedRooms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_roomsCachePrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final rooms = decoded
          .whereType<Map>()
          .map((e) => RoomModel.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      if (rooms.isNotEmpty && mounted) {
        setState(() => _cachedRooms = rooms);
      }
    } catch (_) {}
  }

  /// يُستدعى عند وصول قائمة الغرف: يحمّل الصور في الخلفية ويحفظ
  /// النسخة المحلية لعرضها فوراً في المرة القادمة.
  ///
  /// ✅ prefetchUrls نُقلت داخل حماية البصمة — كانت تعمل في كل rebuild
  ///    للـ StreamBuilder، ما يستهلك الشبكة بلا داعٍ.
  void _onRoomsData(List<RoomModel> rooms) {
    final signature = rooms
        .map((r) =>
    '${r.roomId}:${r.memberCount}:${r.monthlyCoins}:${r.totalGifts}')
        .join('|');
    if (signature == _lastRoomsSignature) return;
    _lastRoomsSignature = signature;

    // نسخ المصغّرات هي ما تعرضه البطاقات فعلاً — تحميلها مسبقاً
    // يجعل صور الغرف جاهزة قبل بناء الشبكة.
    MediaPrefetchService().prefetchUrls(rooms.expand((r) => <String>[
      _cloudinaryThumb(r.roomPhotoUrl, width: 800),
      _cloudinaryThumb(
          r.hostPhotoUrl.isNotEmpty ? r.hostPhotoUrl : R.avaBoy,
          width: 96),
      // خلفية الغرفة تُعرض بملء الشاشة عند الدخول — تحميلها مسبقاً
      // يجعل انتقال المستخدم من البطاقة إلى الغرفة فورياً.
      if (r.bgImage.isNotEmpty) r.bgImage,
    ]));

    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _roomsCachePrefsKey,
          jsonEncode(rooms.map((r) => r.toMap()).toList()),
        );
      } catch (_) {}
    }());
  }

  /// نسخة مصغّرة من صور Cloudinary للعرض داخل شبكة الاستكشاف —
  /// تحميل أخف بكثير من الصورة الأصلية فيظهر الغرف بشكل أسرع
  static String _cloudinaryThumb(String url, {required int width}) {
    const marker = '/image/upload/';
    final i = url.indexOf(marker);
    if (i < 0) return url;
    final rest = url.substring(i + marker.length);
    if (rest.startsWith('w_') ||
        rest.startsWith('c_') ||
        rest.startsWith('q_') ||
        rest.startsWith('f_') ||
        rest.startsWith('e_')) {
      return url;
    }
    return '${url.substring(0, i + marker.length)}w_$width,c_limit,q_auto,f_auto/$rest';
  }

  /// ✅ توازي بدل تسلسل: كانت 4 رحلات متتالية (~2-4 ثوانٍ على الشبكات
  ///    البطيئة). الآن: 1 جرّب hostedRoomId، ثم 3 مصادر بالتوازي.
  Future<void> _loadMyRoom() async {
    final user = Provider.of<UserProvider>(context, listen: false).currentUser;
    if (user == null) return;
    try {
      RoomModel? room;

      // 1) جرّب hostedRoomId أولاً — الأسرع والأكثر دقة.
      final hostedId = user.hostedRoomId;
      if (hostedId != null && hostedId.isNotEmpty && hostedId != 'null') {
        room = await _firebaseService.getRoom(hostedId);
      }

      // 2) إذا فشل، جرّب المصادر الثلاثة **بالتوازي** بدل التسلسل
      if (room == null) {
        final futures = <Future<RoomModel?>>[
          _firebaseService.getRoomByHost(user.uid),
          if (user.customId.isNotEmpty)
            _firebaseService.getRoomByHost(user.customId),
          SupabaseDataService().getRoomByHostUid(user.uid),
        ];
        final results = await Future.wait<RoomModel?>(futures)
            .catchError((_) => <RoomModel?>[null, null, null]);
        room = results.firstWhere((r) => r != null, orElse: () => null);
      }

      if (mounted && room != null) {
        setState(() => _myRoom = room);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _rankingsRetry?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _goToCreateOrMyRoom() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user == null) return;

    RoomModel? room;
    // 1. Check hostedRoomId if valid AND strictly owned by this user
    final targetRoomId = user.hostedRoomId;
    if (targetRoomId != null && targetRoomId.isNotEmpty && targetRoomId != 'null') {
      final candidate = await _firebaseService.getRoom(targetRoomId);
      if (candidate != null && (candidate.hostUid == user.uid || (user.customId.isNotEmpty && candidate.hostUid == user.customId))) {
        room = candidate;
      }
    }

    // 2. If not found or not owned, lookup strictly by host uid
    if (room == null) {
      final candidate = await _firebaseService.getRoomByHost(user.uid);
      if (candidate != null && (candidate.hostUid == user.uid || (user.customId.isNotEmpty && candidate.hostUid == user.customId))) {
        room = candidate;
        await _firebaseService.updateUser(user.uid, {'hosted_room_id': room.roomId});
        await userProvider.loadUser(user.uid);
      }
    }

    // 3. Lookup by customId if available
    if (room == null && user.customId.isNotEmpty) {
      final candidate = await _firebaseService.getRoomByHost(user.customId);
      if (candidate != null && (candidate.hostUid == user.uid || candidate.hostUid == user.customId)) {
        room = candidate;
        await _firebaseService.updateUser(user.uid, {'hosted_room_id': room.roomId});
        await userProvider.loadUser(user.uid);
      }
    }

    // 4. Supabase direct fallback lookup (strictly verify host ownership)
    if (room == null) {
      try {
        final sbRoom = await SupabaseDataService().getRoomByHostUid(user.uid);
        if (sbRoom != null && (sbRoom.hostUid == user.uid || (user.customId.isNotEmpty && sbRoom.hostUid == user.customId))) {
          room = sbRoom;
          await _firebaseService.updateUser(user.uid, {'hosted_room_id': sbRoom.roomId});
          await userProvider.loadUser(user.uid);
        }
      } catch (_) {}
    }

    final minSvc = MinimizedRoomService();

    // 3. If own room found, directly enter it without exiting if it's already minimized!
    if (room != null && mounted) {
      if (minSvc.isActive && minSvc.roomId != room.roomId) {
        await minSvc.exitRoom(user.uid);
      }
      navigateToRoom(
        context,
        roomName: room.name,
        hostName: user.name,
        hostUid: room.hostUid,
        roomId: room.roomId,
      );
      return;
    }

    // 4. Otherwise, exit old room and open create room screen
    if (minSvc.isActive) {
      await minSvc.exitRoom(user.uid);
    }
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CreateRoomScreen()),
      );
    }
  }

  void _onSearch() {
    showSearch(
      context: context,
      delegate: GlobalSearchDelegate(),
    );
  }

  void _openCountryPicker() {
    final isAr = Localizations.maybeLocaleOf(context)?.languageCode != 'en';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SizedBox(
        height: 400,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Spacer(),
                  DText(
                    isAr ? 'اختر الدولة' : 'Select Country',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  _countryItem('🌍', isAr ? 'الكل' : 'All'),
                  _countryItem('🇪🇬', isAr ? 'مصر' : 'Egypt'),
                  _countryItem('🇸🇦', isAr ? 'السعودية' : 'Saudi Arabia'),
                  _countryItem('🇦🇪', isAr ? 'الإمارات' : 'UAE'),
                  _countryItem('🇰🇼', isAr ? 'الكويت' : 'Kuwait'),
                  _countryItem('🇶🇦', isAr ? 'قطر' : 'Qatar'),
                  _countryItem('🇧🇭', isAr ? 'البحرين' : 'Bahrain'),
                  _countryItem('🇴🇲', isAr ? 'عمان' : 'Oman'),
                  _countryItem('🇯🇴', isAr ? 'الأردن' : 'Jordan'),
                  _countryItem('🇱🇧', isAr ? 'لبنان' : 'Lebanon'),
                  _countryItem('🇮🇶', isAr ? 'العراق' : 'Iraq'),
                  _countryItem('🇲🇦', isAr ? 'المغرب' : 'Morocco'),
                  _countryItem('🇩🇿', isAr ? 'الجزائر' : 'Algeria'),
                  _countryItem('🇹🇳', isAr ? 'تونس' : 'Tunisia'),
                  _countryItem('🇸🇩', isAr ? 'السودان' : 'Sudan'),
                  _countryItem('🇾🇪', isAr ? 'اليمن' : 'Yemen'),
                  _countryItem('🇸🇾', isAr ? 'سوريا' : 'Syria'),
                  _countryItem('🇵🇸', isAr ? 'فلسطين' : 'Palestine'),
                  _countryItem('🇱🇾', isAr ? 'ليبيا' : 'Libya'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countryItem(String flag, String name) {
    return ListTile(
      leading: DText(flag, style: const TextStyle(fontSize: 24)),
      title: DText(name),
      onTap: () {
        Navigator.pop(context);
        setState(() {
          if (name == 'الكل' || name == 'All' || _selectedCountry == name) {
            _selectedCountry = null;
          } else {
            _selectedCountry = name;
          }
        });
      },
    );
  }

  static String _categoryBg(String category) {
    switch (category.toLowerCase()) {
      case 'chat':
        return R.discoverItemChatBg;
      case 'music':
        return R.discoverItemMusicBg;
      case 'game':
        return R.discoverItemGameBg;
      case 'hobby':
        return R.discoverItemHobbyBg;
      case 'party':
        return R.discoverItemPartyBg;
      case 'friend':
        return R.discoverItemFriendBg;
      default:
        return R.discoverGameTeamingIc;
    }
  }

  static String _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'chat':
        return R.discoverRoomChatIc;
      case 'music':
        return R.discoverRoomMusicIc;
      case 'game':
        return R.discoverRoomGameTeamIc;
      case 'hobby':
        return R.discoverRoomHobbyIc;
      case 'party':
        return R.discoverRoomPartyIc;
      default:
        return R.discoverGameTeamingIc;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.currentUser;
    final bgImg = DynamicConfigService().discoverBackgroundImage;

    return Container(
      decoration: BoxDecoration(
        color: DynamicConfigService().discoverBackgroundColor,
        image: bgImg.isNotEmpty
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
            Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildDiscoverContent(isFollowTab: true, user: user),
                      _buildDiscoverContent(isFollowTab: false, user: user),
                    ],
                  ),
                ),
              ],
            ),
            // أيقونة تسجيل الوصول اليومي فكسد على اليسار فوق حسابي
            const Positioned(
              left: 14,
              bottom: 16,
              child: _DailySigninFloatingBadge(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Stack(
      children: [
        R.image(
          R.discoverHeaderBg,
          width: double.infinity,
          fit: BoxFit.fitWidth,
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _onSearch,
                    child: R.image(R.discoverSearchIc, width: 28, height: 28),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final isAr = Localizations.maybeLocaleOf(context)?.languageCode != 'en';
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildCustomTab(
                              iconPath: R.discoverTabFollowIc,
                              label: isAr ? 'متابعة' : 'Follow',
                              index: 0,
                            ),
                            const SizedBox(width: 24),
                            _buildCustomTab(
                              iconPath: R.discoverTabRecentIc,
                              label: isAr ? 'الأحدث' : 'Recent',
                              index: 1,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RankScreen()),
                    ),
                    child: R.loadAsset(
                      DynamicConfigService.instance.getAssetUrl('room_rank_icon') ??
                          DynamicConfigService.instance.getAssetUrl('rank_icon') ??
                          'assets/images/ic_rank_cup_gold.png',
                      width: 28,
                      height: 28,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _goToCreateOrMyRoom,
                    child: R.image(R.discoverRoomIc, width: 28, height: 28),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomTab({
    required String iconPath,
    required String label,
    required int index,
  }) {
    final isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () => _tabController.animateTo(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          R.image(iconPath, width: 20, height: 20),
          const SizedBox(height: 2),
          DText(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isSelected
                  ? const Color(0xFF16151A)
                  : const Color(0x8016151A),
            ),
          ),
          if (isSelected)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: R.image(R.discoverTabIndicatorIc, width: 16, height: 4),
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildMyRoomCard(dynamic user) {
    final isAr = Localizations.maybeLocaleOf(context)?.languageCode != 'en';
    final cfg = DynamicConfigService();

    final Color btnColor = cfg.discoverFollowCardBtnColor;
    final String bgImage = cfg.discoverFollowCardBgImage;

    final room = _myRoom;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.5), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // خلفية الكرت باستخدام الصورة الذهبية بدلاً من الخلفية الرمادي
          Positioned.fill(
            child: bgImage.isNotEmpty
                ? CachedNetImage(
                    bgImage,
                    fit: BoxFit.cover,
                    error: (_, __, ___) => Image.asset(
                      'assets/images/discover_create_room_card.png',
                      fit: BoxFit.cover,
                    ),
                  )
                : Image.asset(
                    'assets/images/discover_create_room_card.png',
                    fit: BoxFit.cover,
                  ),
          ),
          // طبقة تظليل خفيفة لإبراز النصوص البيضاء بوضوح عالي
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.black.withValues(alpha: 0.2),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: room != null
                ? Row(
                    children: [
                      // 1. Room Photo with Sound Wave Animation
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: btnColor, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: btnColor.withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: room.roomPhotoUrl.isNotEmpty
                                  ? CachedNetImage(
                                      _cloudinaryThumb(room.roomPhotoUrl, width: 128),
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                      error: (_, __, ___) => Image.asset(_roomDefaultAsset, width: 50, height: 50, fit: BoxFit.cover),
                                    )
                                  : Image.asset(_roomDefaultAsset, width: 50, height: 50, fit: BoxFit.cover),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const _AudioWaveIndicator(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      // 2. Room Name and Room ID
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: DText(
                                    room.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: btnColor.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: btnColor.withValues(alpha: 0.8), width: 0.5),
                                  ),
                                  child: DText(
                                    isAr ? 'غرفتي' : 'My Room',
                                    style: TextStyle(
                                      color: btnColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            DText(
                              'ID: ${room.roomId}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                shadows: [
                                  Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 3. "Enter" (دخول) Button with custom card style and white text
                      GestureDetector(
                        onTap: () {
                          navigateToRoom(
                            context,
                            roomName: room.name,
                            hostName: room.hostName,
                            hostUid: room.hostUid,
                            roomId: room.roomId,
                            roomPassword: room.password,
                          );
                        },
                        child: Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                            image: const DecorationImage(
                              image: AssetImage('assets/images/discover_create_room_card.png'),
                              fit: BoxFit.fill,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: DText(
                            isAr ? 'دخول' : 'Enter',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  color: Colors.black87,
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : GestureDetector(
                    onTap: _goToCreateOrMyRoom,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFFFD700).withValues(alpha: 0.6),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(Icons.add_home_work_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DText(
                                isAr ? 'ليس لديك غرفة بعد' : 'No Room Created Yet',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 2),
                              DText(
                                isAr ? 'ابدأ الآن بإنشاء غرفتك الخاصة وتحدث مع أصدقائك' : 'Create your room and start chatting',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  shadows: const [
                                    Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // زر إنشاء روم باستخدام نفس تصميم الكارت والخط الأبيض
                        GestureDetector(
                          onTap: _goToCreateOrMyRoom,
                          child: Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                              image: const DecorationImage(
                                image: AssetImage('assets/images/discover_create_room_card.png'),
                                fit: BoxFit.fill,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: DText(
                              isAr ? 'إنشاء روم' : 'Create Room',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Colors.black87,
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
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
    );
  }

  Widget _buildDiscoverContent({required bool isFollowTab, dynamic user}) {
    final bgColor = DynamicConfigService().discoverBackgroundColor;
    return RefreshIndicator(
      color: const Color(0xFFFF9D3E),
      onRefresh: () async {
        setState(() {
          _roomsStream =
              _firebaseService.allRoomsStream().asBroadcastStream();
        });
        await Future.wait<void>([
          _loadMyRoom(),
          _loadTopDailyRankings(force: true),
        ]);
      },
      child: StreamBuilder<List<RoomModel>>(
        stream: _roomsStream,
        initialData: _cachedRooms,
        builder: (context, snapshot) {
          if (snapshot.hasData &&
              snapshot.data != null &&
              snapshot.data!.isNotEmpty) {
            _cachedRooms = snapshot.data;
            _onRoomsData(snapshot.data!);
          }

          List<RoomModel> rooms = snapshot.data ?? _cachedRooms ?? [];

          if (isFollowTab) {
            final List<String> followedList =
                (user?.followedRooms as List<String>?) ?? [];
            rooms = rooms
                .where((room) => followedList.contains(room.roomId))
                .toList();
          }

          if (_searchQuery.isNotEmpty) {
            rooms = rooms.where((room) {
              return room.name.toLowerCase().contains(_searchQuery) ||
                  room.hostName.toLowerCase().contains(_searchQuery);
            }).toList();
          }

          if (_selectedCountry != null &&
              _selectedCountry!.isNotEmpty &&
              _selectedCountry != 'الكل') {
            rooms = rooms
                .where((room) => _roomMatchesCountry(room, _selectedCountry))
                .toList();
          }

          final isLoading = snapshot.connectionState ==
              ConnectionState.waiting &&
              (_cachedRooms == null || _cachedRooms!.isEmpty);

          // ✅ كل ما فوق الغرف (البانر الدوّار/غرفتي + شريط الهاشتاجات)
          //    أصبح داخل نفس الـ ScrollView: البانر يُرفع مع التمرير،
          //    وشريط الهاشتاجات يثبت (pinned) تحت الشريط العلوي،
          //    والغرف تتكرّر تحت الثابت — تماماً كما في تطبيقات البث.
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: isFollowTab
                    ? _buildMyRoomCard(user)
                    : const BannerCarousel(),
              ),
              // شريط الهاشتاجات/الدول — يثبت أعلى القائمة أثناء التمرير
              SliverPersistentHeader(
                pinned: true,
                delegate: _DiscoverChipsHeader(
                  backgroundColor: bgColor,
                  child: _buildCountryChips(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _buildTopRankingCards(),
                ),
              ),
              if (isLoading)
                const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (rooms.isEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 280,
                    child: _buildEmptyRooms(isFollowTab),
                  ),
                )
              else
              // ✅ شبكة الغرف كـ Sliver — تُبنى بشكل كسول (lazy) أثناء
              //    التمرير بدل بناء كل البطاقات دفعة واحدة.
                SliverPadding(
                  padding: const EdgeInsets.only(left: 8, right: 8, top: 4, bottom: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1,
                    ),
                    delegate: SliverChildBuilderDelegate(
                          (context, index) {
                        final room = rooms[index];
                        final isFollowing =
                            user?.followedRooms.contains(room.roomId) ?? false;
                        final rankIndex = index < 3 ? index : -1;
                        return _buildRoomCard(room, isFollowing, user,
                            rankIndex: rankIndex);
                      },
                      childCount: rooms.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// حالة «لا توجد غرف» — داخل SliverFillRemaining حتى يعمل السحب للتحديث
  Widget _buildEmptyRooms(bool isFollowTab) {
    final isAr = Localizations.maybeLocaleOf(context)?.languageCode != 'en';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.headset_off, size: 64, color: Colors.black26),
          const SizedBox(height: 16),
          DText(
            isFollowTab
                ? (isAr
                ? 'لم تتابع أي غرفة بعد\nاستكشف الغرف وتابع غرفك المفضلة!'
                : 'No followed rooms yet\nDiscover and follow rooms!')
                : (isAr
                ? 'لا توجد غرف حالياً\nابدأ بإنشاء غرفتك الآن!'
                : 'No rooms yet\nCreate one!'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  bool _roomMatchesCountry(RoomModel room, String? selectedCountry) {
    if (selectedCountry == null ||
        selectedCountry.isEmpty ||
        selectedCountry == 'الكل' ||
        selectedCountry.toLowerCase() == 'all') {
      return true;
    }
    final sel = selectedCountry.trim().toLowerCase();
    String rCountry = room.country.trim().toLowerCase();
    if (rCountry.isEmpty) {
      rCountry = 'eg';
    }

    if (rCountry == sel) return true;

    const countryAliases = <String, List<String>>{
      'eg': ['مصر', 'egypt', 'eg', 'egp', 'جمهورية مصر العربية'],
      'sa': ['السعودية', 'saudi', 'saudi arabia', 'sa', 'ksa', 'المملكة العربية السعودية'],
      'ae': ['الإمارات', 'الامارات', 'uae', 'ae', 'united arab emirates', 'الإمارات العربية المتحدة'],
      'kw': ['الكويت', 'kuwait', 'kw', 'kwt', 'دولة الكويت'],
      'qa': ['قطر', 'qatar', 'qa', 'qat', 'دولة قطر'],
      'bh': ['البحرين', 'bahrain', 'bh', 'bhr', 'مملكة البحرين'],
      'om': ['عمان', 'عُمان', 'oman', 'om', 'omn', 'سلطنة عمان'],
      'iq': ['العراق', 'iraq', 'iq', 'irq', 'جمهورية العراق'],
      'jo': ['الأردن', 'الاردن', 'jordan', 'jo', 'jor', 'المملكة الأردنية الهاشمية'],
      'sy': ['سوريا', 'syria', 'sy', 'syr'],
      'lb': ['لبنان', 'lebanon', 'lb', 'lbn', 'الجمهورية اللبنانية'],
      'ye': ['اليمن', 'yemen', 'ye', 'yem'],
      'ps': ['فلسطين', 'palestine', 'ps', 'pse'],
      'sd': ['السودان', 'sudan', 'sd', 'sdn'],
      'ly': ['ليبيا', 'libya', 'ly', 'lby'],
      'tn': ['تونس', 'tunisia', 'tn', 'tun'],
      'dz': ['الجزائر', 'algeria', 'dz', 'dza'],
      'ma': ['المغرب', 'morocco', 'ma', 'mar'],
      'us': ['امريكا', 'أمريكا', 'us', 'usa', 'united states', 'الولايات المتحدة الأمريكية'],
      'gb': ['بريطانيا', 'gb', 'uk', 'united kingdom', 'المملكة المتحدة'],
      'tr': ['تركيا', 'turkey', 'tr', 'tur'],
    };

    for (final entry in countryAliases.entries) {
      final code = entry.key;
      final aliases = entry.value;
      final matchesSelected = sel == code || aliases.any((a) => a == sel || sel.contains(a));
      if (matchesSelected) {
        if (rCountry == code) return true;
        if (aliases.any((a) => a == rCountry || (rCountry.isNotEmpty && rCountry.contains(a)))) return true;
      }
    }

    if (rCountry.isNotEmpty && (rCountry.contains(sel) || sel.contains(rCountry))) {
      return true;
    }

    return false;
  }

  /// شريط الدول/الهاشتاجات الأفقي — يُستخدم كعنوان ثابت (pinned header)
  /// أعلى قائمة الغرف أثناء التمرير.
  Widget _buildCountryChips() {
    final isAr = Localizations.maybeLocaleOf(context)?.languageCode != 'en';
    final countries = [
      {'name': isAr ? 'الكل' : 'All', 'flag': '🌍'},
      {'name': isAr ? 'مصر' : 'Egypt', 'flag': '🇪🇬'},
      {'name': isAr ? 'السعودية' : 'Saudi Arabia', 'flag': '🇸🇦'},
      {'name': isAr ? 'الإمارات' : 'UAE', 'flag': '🇦🇪'},
      {'name': isAr ? 'الكويت' : 'Kuwait', 'flag': '🇰🇼'},
      {'name': isAr ? 'العراق' : 'Iraq', 'flag': '🇮🇶'},
      {'name': isAr ? 'قطر' : 'Qatar', 'flag': '🇶🇦'},
      {'name': isAr ? 'عمان' : 'Oman', 'flag': '🇴🇲'},
      {'name': isAr ? 'الأردن' : 'Jordan', 'flag': '🇯🇴'},
      {'name': isAr ? 'المغرب' : 'Morocco', 'flag': '🇲🇦'},
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            GestureDetector(
              onTap: _openCountryPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    R.image(
                      R.discoverCountryMoreIc,
                      width: 24,
                      height: 24,
                    ),
                    const SizedBox(width: 2),
                    DText(
                      isAr ? 'المزيد' : 'More',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF59370D),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: countries.length,
                itemBuilder: (context, index) {
                  final country = countries[index];
                  final countryName = country['name']!;
                  final isAll = countryName == 'الكل' || countryName == 'All';
                  final isActive = (isAll &&
                      (_selectedCountry == null ||
                          _selectedCountry == 'الكل' ||
                          _selectedCountry == 'All')) ||
                      (!isAll && _selectedCountry == countryName);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isAll) {
                            _selectedCountry = null;
                          } else {
                            _selectedCountry = countryName;
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFF59370D)
                              : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            DText(
                              country['flag']!,
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(width: 2),
                            DText(
                              countryName,
                              style: TextStyle(
                                fontSize: 11,
                                color: isActive
                                    ? Colors.white
                                    : const Color(0xFF59370D),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// بطاقات المتصدرين (ثروة / كرزمة / غرف) أسفل شريط الدول.
  /// البطاقات الثلاث تعرض **المتصدر الأول فقط** (topCount=1) — كما في
  /// شاشة الترتيب اليومي، وتأخذ الصورة الحقيقية من نفس مصدرها.
  Widget _buildTopRankingCards() {
    // (مفتاح البيانات، صورة البطاقة، تبويب RankScreen المقابل، إزاحة
    //  دوائر المتصدرين أفقياً/رأسياً لكل بطاقة، عدد المراكز المعروضة)
    // (مفتاح البيانات، صورة البطاقة، تبويب RankScreen،
    //  avatarDx، avatarDy = إزاحة الصورة لأسفل 4dp، عدد المراكز المعروضة)
    final cards = [
      ('rooms', R.discoverRankRooms, 2, 0.0, 6.0, 1),
      ('charm', R.discoverRankCharm, 1, 0.0, 6.0, 1),
      ('wealth', R.discoverRankWealth, 0, 0.0, 6.0, 1),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          for (final (key, bg, tabIndex, avatarDx, avatarDy, topCount) in cards)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _rankingCard(
                    key, bg, tabIndex, avatarDx, avatarDy, topCount),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rankingCard(String key, String bgImage, int rankTabIndex,
      double avatarDx, double avatarDy, int topCount) {
    final top = _topDailyRankings[key] ?? const <Map<String, dynamic>>[];
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RankScreen(initialIndex: rankTabIndex)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 1.35,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ✅ الصورة أولاً (في الخلف)
              Image.asset(bgImage, fit: BoxFit.cover),
              // ✅ الدوائر فوق الصورة — كانت خلفها فكان إطار الصورة يقصّها
              //    فتظهر المتصدرون ناقصين أو مخفيين تماماً.
              Align(
                alignment: const Alignment(0, 0.58),
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Transform.translate(
                    offset: Offset(avatarDx, avatarDy),
                    child: topCount == 1
                        ? _top1Avatar(top, isRoom: key == 'rooms')
                        : _top3AvatarCluster(top),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// صورة الغرفة الافتراضية — نفس البديل الذي تستخدمه شاشة الترتيب
  /// لتصنيف الغرف عند عدم وجود صورة للغرفة.
  static const String _roomDefaultAsset = R.defaultRoomPhoto;

  /// يستخرج رابط الصورة من صف ترتيب مهما اختلف اسم العمود القادم من
  /// الـ View (`photo_url` / `photoUrl` / `avatar` / `room_photo_url` …).
  static String _rowPhoto(Map<String, dynamic>? row) {
    if (row == null) return '';
    const keys = <String>[
      'photoUrl',
      'photo_url',
      'avatar',
      'avatar_url',
      'user_avatar',
      'room_photo_url',
      'room_photo',
      'cover_image',
      'cover',
      'image',
      'bg_image',
    ];
    for (final key in keys) {
      final v = (row[key] ?? '').toString().trim();
      if (v.isNotEmpty && v != 'null') return v;
    }
    return '';
  }

  /// دائرة المتصدر الأول فقط (لبطاقات الثروة/السحر/الغرف).
  /// [isRoom] يجعل البديل صورة غرفة افتراضية بدل صورة المستخدم الافتراضية.
  Widget _top1Avatar(List<Map<String, dynamic>> top, {bool isRoom = false}) {
    final photo = top.isEmpty ? '' : _rowPhoto(top.first);
    return _avatarCircle(photo, 44,
        fallbackAsset: isRoom ? _roomDefaultAsset : R.avaBoy, framed: true);
  }

  /// ثلاث دوائر لمراكز المتصدرين — الترتيب من اليسار لليمين:
  /// المركز 3، المركز 1 (الأكبر بالنص)، المركز 2 — مع فواصل ذهبية
  /// وشارات مربعة مرقّمة 1/2/3 أسفل كل دائرة.
  Widget _top3AvatarCluster(List<Map<String, dynamic>> top3) {
    return SizedBox(
      width: 85,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 10, top: 1, child: _rankAvatar(top3, 2, 50)),
          Positioned(left: 32, top: 0, child: _rankAvatar(top3, 0, 50)),
          Positioned(left: 60, top: 1, child: _rankAvatar(top3, 1, 50)),
        ],
      ),
    );
  }

  Widget _rankAvatar(List<Map<String, dynamic>> top3, int rank, double size) {
    final entry = rank < top3.length ? top3[rank] : null;
    final photo = _rowPhoto(entry);
    return _avatarCircle(photo, size,
        fallbackAsset: R.avaBoy, framed: rank == 0);
  }

  /// إطار دائري يوضع فوق صورة المتصدر الأول في بطاقات
  /// الثروة / السحر / الغرف داخل شاشة الاستكشاف.
  static const String _top1FrameAsset = 'assets/icon/rank_top1_frame.png';

  /// الملف 168px لكن المحتوى الظاهر منه 156px (هوامش شفافة 6px يمين/يسار).
  /// النسبة الحالية 203/125 تكبّر الإطار المعروض (~1.62x) — أكبر بكتير من
  /// صورة المستخدم (44dp)، فالإطار بيقترب من حدود البطاقة السفلية.
  /// لو احتاجنا نزّل الصورة أكتر لازم نزود ارتفاع البطاقة (aspectRatio أقل)
  /// عشان الـ ClipRRect ما يقصّش الإطار من تحت.
  static const double _top1FrameScale = 203 / 125;

  /// رفع صورة الإطار وحدها 4dp لأعلى دون تحريك صورة المستخدم.
  /// القيمة سالبة لأن محور Y في Flutter يتجه لأسفل.
  /// زدها (مثلاً -8) إذا أردت رفعاً أكبر.
  static const double _top1FrameDy = -4.0;

  /// دائرة متصدر واحدة — تُستخدم في بطاقة «الأول فقط» وفي مجموعة الثلاثة.
  /// [framed] يضيف إطار الصورة الدائري (png شفاف من المنتصف) فوق الصورة.
  Widget _avatarCircle(String photo, double size,
      {required String fallbackAsset, bool framed = false}) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        // ✅ incluso السماح للإطار بالخروج حدود الدائرة 44dp حتى لا يُقصّ
        //    عند رفعه 4dp لأعلى.
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF221A2E),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 4),
              ],
            ),
            child: ClipOval(
              child: photo.isNotEmpty
                  ? CachedNetImage(
                photo,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    Container(color: const Color(0xFF221A2E)),
                error: (_, __, ___) =>
                    Image.asset(fallbackAsset, fit: BoxFit.cover),
              )
                  : Image.asset(fallbackAsset, fit: BoxFit.cover),
            ),
          ),
          // الإطار الدائري فوق الصورة (منتصفه شفاف).
          // التكبير يعوّض الهوامش الشفافة في الـ PNG عشان يطابق مقاس الصورة.
          if (framed)
            Center(
              child: Transform.translate(
                offset: Offset(0, _top1FrameDy),
                child: Transform.scale(
                  scale: _top1FrameScale,
                  child: Image.asset(
                    _top1FrameAsset,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRoomCard(RoomModel room, bool isFollowing, dynamic user, {int rankIndex = -1}) {
    final categoryBg = _categoryBg(room.category);
    final categoryIcon = _categoryIcon(room.category);

    return GestureDetector(
      onTap: () {
        navigateToRoom(
          context,
          roomName: room.name,
          hostName: room.hostName,
          hostUid: room.hostUid,
          roomId: room.roomId,
          roomPassword: room.password,
        );
      },
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox.expand(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  R.image(categoryBg, fit: BoxFit.cover),
                  R.image(R.discoverRoomItem1, fit: BoxFit.contain),
                  // صورة الغرفة — وعند عدم وجود صورة تُعرض الصورة الافتراضية
                  R.loadImage(
                    _cloudinaryThumb(
                      room.roomPhotoUrl.isNotEmpty ? room.roomPhotoUrl : _roomDefaultAsset,
                      width: 800,
                    ),
                    fit: BoxFit.cover,
                  ),
                  // Top-right online badge
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0x6616151A),
                        borderRadius: BorderRadius.circular(128),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6, height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4CAF50),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 3),
                          SizedBox(
                            width: 12, height: 12,
                            child: R.image(categoryIcon, fit: BoxFit.contain),
                          ),
                          const SizedBox(width: 2),
                          DText(
                            '${room.memberCount}',
                            style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold,
                              color: Color(0xFFFFE76C),
                            ),
                          ),
                          const SizedBox(width: 2),
                          ClipOval(
                            child: SizedBox(
                              width: 12, height: 12,
                              child: R.loadImage(
                                _cloudinaryThumb(
                                  room.hostPhotoUrl.isNotEmpty ? room.hostPhotoUrl : R.avaBoy,
                                  width: 96,
                                ),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Bottom info bar
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: SizedBox(
                      height: kToolbarHeight,
                      child: R.image(R.discoverRoomItemInfoBg, fit: BoxFit.fill),
                    ),
                  ),
                  // Room info content
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (room.hasLuckyBag)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF2442), Color(0xFFFF7A00)],
                                ),
                                borderRadius: BorderRadius.circular(5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withValues(alpha: 0.5),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              margin: const EdgeInsets.only(bottom: 3),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  DText('🧧', style: TextStyle(fontSize: 10)),
                                  SizedBox(width: 3),
                                  DText(
                                    'حقيبة الحظ',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (room.category.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0x6616151A),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              margin: const EdgeInsets.only(bottom: 2),
                              child: DText(
                                room.category,
                                style: const TextStyle(fontSize: 11, color: Colors.white),
                              ),
                            ),
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: Image(
                                  image: R.cachedImage(
                                    'https://flagcdn.com/w40/${UserIdWidget.resolveCountryCode(room.country)}.png',
                                  ),
                                  width: 18,
                                  height: 12,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => DText(
                                    UserIdWidget.countryCodeToEmoji(UserIdWidget.resolveCountryCode(room.country)),
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: SpecialTextWidget(
                                  text: room.name,
                                  isSpecial: UserIdWidget.isSpecialId(room.roomId),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(
                                Icons.group_rounded,
                                size: 12,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 1),
                              DText(
                                '${room.memberCount}',
                                style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Follow button (top-left)
                  if (user != null)
                    Positioned(
                      top: 6, left: 6,
                      child: GestureDetector(
                        onTap: () async {
                          final willFollow = !isFollowing;
                          if (context.mounted) {
                            Provider.of<UserProvider>(context, listen: false).toggleFollowedRoom(room.roomId, willFollow);
                          }
                          if (willFollow) {
                            await _firebaseService.followRoom(user.uid, room.roomId);
                          } else {
                            await _firebaseService.unfollowRoom(user.uid, room.roomId);
                          }
                        },
                        child: Icon(
                          isFollowing ? Icons.favorite : Icons.favorite_border,
                          color: isFollowing ? Colors.red : Colors.white70,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Top-rank border overlay (supports SVGA, VAP, MP4, PNG, WEBP dynamically in real-time)
          if (rankIndex >= 0)
            Positioned(
              left: -4, top: -4, right: -4, bottom: -4,
              child: RoomRankBorderWidget(rankIndex: rankIndex),
            ),
        ],
      ),
    );
  }
}

/// عنوان ثابت (pinned) لشريط الدول/الهاشتاجات في شاشة الاستكشاف.
/// يبقى ملتصقاً أسفل الشريط العلوي أثناء تمرير الغرف، ويعود لمكانه
/// الأصلي عند الرجوع للأعلى.
class _DiscoverChipsHeader extends SliverPersistentHeaderDelegate {
  final Widget child;
  final Color backgroundColor;

  const _DiscoverChipsHeader({
    required this.child,
    required this.backgroundColor,
  });

  static const double _height = 48;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        boxShadow: overlapsContent
            ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ]
            : null,
      ),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _DiscoverChipsHeader oldDelegate) {
    return oldDelegate.child != child ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

class RoomRankBorderWidget extends StatelessWidget {
  final int rankIndex;
  const RoomRankBorderWidget({super.key, required this.rankIndex});

  @override
  Widget build(BuildContext context) {
    if (rankIndex < 0 || rankIndex > 2) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: DynamicConfigService.instance,
      builder: (context, _) {
        final localPath = rankIndex == 0
            ? R.roomRankBorder1
            : (rankIndex == 1 ? R.roomRankBorder2 : R.roomRankBorder3);
        final overrideUrl = DynamicConfigService.instance.getAssetOverride(localPath);
        final path = (overrideUrl != null && overrideUrl.isNotEmpty) ? overrideUrl : localPath;
        final type = detectAssetType(path);

        Widget child;
        if (type == AssetType.svga) {
          child = SvgaPlayer(
            assetPath: path,
            fit: BoxFit.fill,
            loops: true,
          );
        } else if (type == AssetType.vap || type == AssetType.mp4) {
          child = VapPlayer(
            url: path,
            fit: BoxFit.fill,
          );
        } else {
          // PNG, WEBP, GIF, JPG or any image format
          if (path.startsWith('http://') || path.startsWith('https://')) {
            child = CachedNetworkImage(
              imageUrl: path,
              fit: BoxFit.fill,
              errorWidget: (_, __, ___) => SvgaPlayer(
                assetPath: localPath,
                fit: BoxFit.fill,
                loops: true,
              ),
            );
          } else {
            child = Image.asset(
              path,
              fit: BoxFit.fill,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            );
          }
        }

        return IgnorePointer(child: child);
      },
    );
  }
}
