import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../services/supabase_service.dart';
import '../../services/dynamic_config_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/r.dart';
import '../user_profile/user_profile_screen.dart';
import '../room/room_screen.dart';
import 'package:zero/core/dtext.dart';
import '../../widgets/special_name_text.dart';

enum _RankPeriod { daily, weekly, monthly }

class RankScreen extends StatefulWidget {
  /// 0 = الثروة، 1 = الكرزمة/الجاذبية، 2 = الغرف
  final int initialIndex;
  const RankScreen({super.key, this.initialIndex = 0});

  @override
  State<RankScreen> createState() => _RankScreenState();
}

class _RankScreenState extends State<RankScreen> with TickerProviderStateMixin {
  late TabController _mainTabController;
  late TabController _wealthSubTabController;
  late TabController _charmSubTabController;
  late TabController _roomsSubTabController;
  final FirebaseService _api = FirebaseService();
  // ✅ static: النتائج تبقى محفوظة بين فتحات الشاشة —
  //    إعادة الدخول تعرض البيانات فوراً ثم تتحدث بالخلفية
  static final Map<String, List<Map<String, dynamic>>> _cachedRankings =
      {};

  /// ✅ مفتاح حفظ الكاش على القرص — يتيح فتحاً لحظياً حتى بعد
  ///    إعادة تشغيل التطبيق (أول دخول بلا شبكة يعرض آخر بيانات)
  static const String _cachePrefsKey = 'rank_screen_cache_v1';
  static const String _cacheTimeKey = 'rank_screen_cache_time_v1';
  /// الترتيب اليومي يُصفَّر كل 24 ساعة — أي كاش أقدم من ذلك يُهمَل.
  static const Duration _cacheTtl = Duration(hours: 24);
  bool _loading = true;
  int _loadGeneration = 0;
  String _currentType = 'wealth';

  Timer? _countdownTimer;
  Timer? _refreshTimer;
  String _countdownStr = '00h 00m 00s';

  String _getCountdownString() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 3));
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final diff = tomorrow.difference(now);
    final h = diff.inHours.toString().padLeft(2, '0');
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '${h}h ${m}m ${s}s';
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialIndex.clamp(0, 2);
    _mainTabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initial,
    );
    _currentType = ['wealth', 'charm', 'rooms'][initial];
    _mainTabController.addListener(() {
      if (!_mainTabController.indexIsChanging) {
        setState(() {
          _currentType = ['wealth', 'charm', 'rooms'][_mainTabController.index];
        });
      }
    });
    _wealthSubTabController = TabController(length: 3, vsync: this);
    _charmSubTabController = TabController(length: 3, vsync: this);
    _roomsSubTabController = TabController(length: 3, vsync: this);
    // Restore cache first, then refresh, so an async restore
    // cannot overwrite fresh results after the fetch completes.
    _loadInitial();
    // ✅ تحديث تلقائي كل 24 ساعة: تنتهي نافذة اليومي ويُسحب المستخدمون الجدد
    _refreshTimer = Timer.periodic(_cacheTtl, (_) {
      if (mounted) _loadRankings();
    });

    _countdownStr = _getCountdownString();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _countdownStr = _getCountdownString();
        });
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _refreshTimer?.cancel();
    _mainTabController.dispose();
    _wealthSubTabController.dispose();
    _charmSubTabController.dispose();
    _roomsSubTabController.dispose();
    super.dispose();
  }

  /// استعادة آخر نتائج محفوظة على القرص وعرضها فوراً
  Future<void> _restoreCachedRankings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cachePrefsKey);
      if (raw == null || raw.isEmpty) return;
      // ✅ لا نعرض كاش أقدم من 24 ساعة — لازم يتجدد الترتيب اليومي.
      final savedMs = prefs.getInt(_cacheTimeKey) ?? 0;
      if (savedMs == 0 ||
          DateTime.now().difference(
                  DateTime.fromMillisecondsSinceEpoch(savedMs)) >
              _cacheTtl) {
        _cachedRankings.clear();
        await prefs.remove(_cachePrefsKey);
        await prefs.remove(_cacheTimeKey);
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((k, v) {
        if (v is List) {
          _cachedRankings[k.toString()] = v
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      });
      if (mounted && _cachedRankings.length >= 9) {
        setState(() => _loading = false);
      }
    } catch (_) {}
  }


  /// استعادة الكاش أولاً ثم جلب بيانات جديدة — منع سباق يُعيد فيه
  /// الاستعادة كتابة بيانات قديمة بعد اكتمال الجلب.
  Future<void> _loadInitial() async {
    await _restoreCachedRankings();
    if (!mounted) return;
    _loading = _cachedRankings.length < 9;
    await _loadRankings();
  }

  /// حفظ النتائج على القرص لفتح لحظي في المرة القادمة
  Future<void> _persistRankings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cachePrefsKey, jsonEncode(_cachedRankings));
      await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<void> _loadRankings() async {
    final generation = ++_loadGeneration;
    // البيانات المحفوظة تظهر فوراً، والتحديث يجري فترة بفترة دون انتظار
    // استعلام الـ 30 يوماً الأبطأ كما كان يحدث سابقاً.
    if (_cachedRankings.length < 9) {
      setState(() => _loading = true);
    }
    try {
      // الفترات الثلاث تُجلب بالتوازي، لكن كل فترة تُرسم فور اكتمالها.
      await for (final snapshot in _api.rankingGiftSnapshotsStream(
          timeframes: const ['daily', 'weekly', 'monthly'])) {
        final period = snapshot.key;
        final gifts = snapshot.value;
        final periodResults = await Future.wait<dynamic>([
          _api.getGlobalRankings(
              isWealth: true, timeframe: period, gifts: gifts),
          _api.getGlobalRankings(
              isWealth: false, timeframe: period, gifts: gifts),
          _api.getRoomGlobalRanking(timeframe: period, gifts: gifts),
        ]).timeout(const Duration(seconds: 20),
            onTimeout: () => List.filled(3, const <Map<String, dynamic>>[]));
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _cachedRankings['wealth_$period'] =
              List<Map<String, dynamic>>.from(periodResults[0] as List? ?? []);
          _cachedRankings['charm_$period'] =
              List<Map<String, dynamic>>.from(periodResults[1] as List? ?? []);
          _cachedRankings['rooms_$period'] =
              List<Map<String, dynamic>>.from(periodResults[2] as List? ?? []);
          _loading = false;
        });
        unawaited(_persistRankings());
        final w = _cachedRankings['wealth_$period']?.length ?? 0;
        final c = _cachedRankings['charm_$period']?.length ?? 0;
        final r = _cachedRankings['rooms_$period']?.length ?? 0;
        debugPrint('[RankScreen] $period: wealth=$w charm=$c rooms=$r');
      }
    } catch (e, st) {
      debugPrint('[RankScreen] _loadRankings error: $e\n$st');
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  List<Map<String, dynamic>> _getRankingData(_RankPeriod period, String type) {
    final periodKey = period == _RankPeriod.daily ? 'daily' : period == _RankPeriod.weekly ? 'weekly' : 'monthly';
    final key = '${type}_$periodKey';

    if (type == 'rooms') {
      final list = _cachedRankings[key] ?? [];
      final withPoints = list.where((e) {
        final p = (e['points'] as num?)?.toInt() ?? (e['amount'] as num?)?.toInt() ?? (e['total_gifts'] as num?)?.toInt() ?? 0;
        return p > 0;
      }).toList();
      final targetList = withPoints.isNotEmpty ? withPoints : list;
      return targetList.map((e) {
        final photo = (e['photoUrl'] ?? e['photo_url'] ?? e['room_photo_url'] ?? e['cover_image'] ?? e['image'] ?? e['bg_image'] ?? '').toString();
        final roomId = (e['room_id'] ?? e['roomId'] ?? e['user_id'] ?? e['id'] ?? '').toString();
        final pts = (e['points'] as num?)?.toInt() ?? (e['amount'] as num?)?.toInt() ?? (e['total_gifts'] as num?)?.toInt() ?? 0;
        return {
          'uid': e['id'] ?? e['uid'] ?? roomId,
          'name': (e['name'] ?? e['title'] ?? 'Room').toString(),
          'photoUrl': photo,
          'photo_url': photo,
          'points': pts,
          'amount': pts,
          'level': 1,
          'user_id': roomId,
          'room_id': roomId,
          'custom_id': roomId,
          'display_id': roomId,
          'host_name': (e['host_name'] ?? '').toString(),
          'password': (e['password'] ?? '').toString(),
        };
      }).toList();
    }
    
    final data = _cachedRankings[key] ?? [];
    
    return data.where((e) {
      final points = type == 'wealth'
          ? ((e['total_gifts_sent'] as num?)?.toInt() ?? (e['amount'] as num?)?.toInt() ?? (e['points'] as num?)?.toInt() ?? (e['score'] as num?)?.toInt() ?? (e['total_value'] as num?)?.toInt() ?? 0)
          : ((e['total_gifts_received'] as num?)?.toInt() ?? (e['amount'] as num?)?.toInt() ?? (e['points'] as num?)?.toInt() ?? (e['score'] as num?)?.toInt() ?? (e['total_value'] as num?)?.toInt() ?? 0);
      return points > 0;
    }).map((e) {
      final points = type == 'wealth'
          ? ((e['total_gifts_sent'] as num?)?.toInt() ?? (e['amount'] as num?)?.toInt() ?? (e['points'] as num?)?.toInt() ?? (e['score'] as num?)?.toInt() ?? (e['total_value'] as num?)?.toInt() ?? 0)
          : ((e['total_gifts_received'] as num?)?.toInt() ?? (e['amount'] as num?)?.toInt() ?? (e['points'] as num?)?.toInt() ?? (e['score'] as num?)?.toInt() ?? (e['total_value'] as num?)?.toInt() ?? 0);
      final rawCustomId = (e['custom_id'] ?? e['display_id'] ?? '').toString().trim();
      final rawId = (e['id'] ?? e['user_id'] ?? '').toString().trim();
      final realUid = (e['uid'] ?? e['user_id'] ?? e['id'] ?? '').toString().trim();
      // الآيدي المعروض يجب أن يكون رقمياً فقط ومطابقاً للبروفايل، بدون أحرف أو شرطات الـ UUID
      String displayId = '';
      if (rawCustomId.isNotEmpty && !rawCustomId.contains('-')) {
        displayId = rawCustomId;
      } else if (rawId.isNotEmpty && !rawId.contains('-') && RegExp(r'^\d+$').hasMatch(rawId)) {
        displayId = rawId;
      }
      final photo = (e['photo_url'] ?? e['photoUrl'] ?? e['avatar'] ?? '').toString();
      final name = (e['name'] ?? e['user_name'] ?? 'مستخدم').toString();
      return {
        'uid': realUid,
        'name': name.isNotEmpty ? name : 'مستخدم',
        'photoUrl': photo,
        'photo_url': photo,
        'points': points,
        'amount': points,
        'level': e['level'] ?? 1,
        'user_id': realUid,
        'custom_id': displayId,
        'display_id': displayId,
      };
    }).toList();
  }

  Widget _buildDynamicImage(String remoteUrl, String localFallback, {BoxFit fit = BoxFit.cover}) {
    if (remoteUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: remoteUrl,
        fit: fit,
        errorWidget: (context, url, error) => Image.asset(localFallback, fit: fit),
      );
    }
    return Image.asset(localFallback, fit: fit);
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<DynamicConfigService>();
    
    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: _buildDynamicImage(
              config.globalRankBg,
              'assets/mipmap-xxhdpi/global_rank_asset_2.png',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: TabBarView(
                    controller: _mainTabController,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _buildRankPage('wealth', _wealthSubTabController),
                      _buildRankPage('charm', _charmSubTabController),
                      _buildRankPage('rooms', _roomsSubTabController),
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

  Widget _buildHeader() {
    final config = context.watch<DynamicConfigService>();
    final mainBg = config.globalRankMainTabBg;
    final mainIndicator = config.globalRankMainTabIndicator;
    final mainTextColor = config.globalRankMainTabTextColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Container(
                  decoration: mainBg.isNotEmpty
                      ? BoxDecoration(
                          image: DecorationImage(image: R.cachedImage(mainBg), fit: BoxFit.fill),
                        )
                      : null,
                  child: TabBar(
                    controller: _mainTabController,
                    dividerColor: Colors.transparent,
                    indicator: mainIndicator.isNotEmpty
                        ? BoxDecoration(
                            image: DecorationImage(image: R.cachedImage(mainIndicator), fit: BoxFit.fill),
                          )
                        : const UnderlineTabIndicator(borderSide: BorderSide(color: Color(0xFFFFD54F), width: 3)),
                    labelColor: mainTextColor,
                    unselectedLabelColor: Colors.white70,
                    labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    tabs: const [
                      Tab(text: 'الثروة'),
                      Tab(text: 'السحر'),
                      Tab(text: 'الغرف'),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 36),
          ],
        ),
      ),
    );
  }

  Widget _buildRankPage(String type, TabController subTabController) {
    final config = context.watch<DynamicConfigService>();
    final subBg = config.globalRankSubTabBg;
    final subIndicator = config.globalRankSubTabIndicator;
    final subTextColor = config.globalRankSubTabTextColor;

    return Column(
      children: [
        const SizedBox(height: 10),
        // Sub Tabs
        Container(
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 40),
          decoration: subBg.isNotEmpty
              ? BoxDecoration(
                  image: DecorationImage(image: R.cachedImage(subBg), fit: BoxFit.fill),
                  borderRadius: BorderRadius.circular(18),
                )
              : BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFFFD54F).withValues(alpha: 0.3)),
                ),
          child: TabBar(
            controller: subTabController,
            dividerColor: Colors.transparent,
            indicator: subIndicator.isNotEmpty
                ? BoxDecoration(
                    image: DecorationImage(image: R.cachedImage(subIndicator), fit: BoxFit.fill),
                    borderRadius: BorderRadius.circular(18),
                  )
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD54F), Color(0xFFF57F17)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
            labelColor: subTextColor,
            unselectedLabelColor: Colors.white70,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            tabs: const [
              Tab(text: 'يوميا'),
              Tab(text: 'أسبوعيًا'),
              Tab(text: 'شهريا'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        
        // List
        Expanded(
          child: TabBarView(
            controller: subTabController,
            children: [
              _buildRankList(type, _RankPeriod.daily),
              _buildRankList(type, _RankPeriod.weekly),
              _buildRankList(type, _RankPeriod.monthly),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRankList(String type, _RankPeriod period) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFD54F)),
      );
    }

    final data = _getRankingData(period, type);
    if (data.isEmpty) {
      return const Center(
        child: DText(
          'لا توجد بيانات ترتيب حالياً',
          style: TextStyle(fontSize: 14, color: Colors.white70, fontWeight: FontWeight.w500),
        ),
      );
    }

    return Column(
      children: [
        if (data.isNotEmpty)
          Container(
            height: 280,
            padding: const EdgeInsets.only(top: 10),
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                if (data.length >= 2)
                  Positioned(
                    right: 30,
                    bottom: 0,
                    child: _buildTopRankItem(data[1], 2, type),
                  ),
                if (data.length >= 3)
                  Positioned(
                    left: 30,
                    bottom: 0,
                    child: _buildTopRankItem(data[2], 3, type),
                  ),
                if (data.isNotEmpty)
                  Positioned(
                    top: 0,
                    child: _buildTopRankItem(data[0], 1, type),
                  ),
              ],
            ),
          ),
        
        const SizedBox(height: 15),
        
        // Ranks 4+ List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: data.length > 3 ? data.length - 3 : 0,
            itemBuilder: (context, index) {
              return _buildNormalItem(data[index + 3], index + 4, type);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTopRankItem(Map<String, dynamic> item, int rank, String type) {
    final config = context.watch<DynamicConfigService>();
    final isGold = rank == 1;
    
    String remoteBanner = '';
    String localBanner = '';
    String remoteFrame = '';
    String localFrame = '';

    if (rank == 1) {
      remoteBanner = config.globalRank1Banner;
      localBanner = 'assets/mipmap-xxhdpi/global_rank_asset_7.png';
      remoteFrame = config.globalRank1Frame;
      localFrame = 'assets/mipmap-xxhdpi/rank_1_frame.png';
    } else if (rank == 2) {
      remoteBanner = config.globalRank2Banner;
      localBanner = 'assets/mipmap-xxhdpi/global_rank_asset_8.png';
      remoteFrame = config.globalRank2Frame;
      localFrame = 'assets/mipmap-xxhdpi/rank_2_frame.png';
    } else {
      remoteBanner = config.globalRank3Banner;
      localBanner = 'assets/mipmap-xxhdpi/global_rank_asset_1.png';
      remoteFrame = config.globalRank3Frame;
      localFrame = 'assets/mipmap-xxhdpi/global_rank_asset_6.png';
    }

    final double width = isGold ? 130 : 100;
    final double avatarSize = isGold ? 60 : 50;
    // ✅ حجم صريح للإطار — مطابق لباقي شاشات الترتيب/الاستكشاف،
    //    وأكبر شوية من الحجم الطبيعي للصورة عشان ما يطلعش صغير.
    final double frameSize = isGold ? 140 : 116;
    final String photo = (item['photoUrl'] ?? item['photo_url'] ?? '').toString();
    final String rawCid = (item['custom_id'] ?? item['display_id'] ?? '').toString().trim();
    final String rawId = (item['room_id'] ?? item['user_id'] ?? item['id'] ?? '').toString().trim();
    final String displayId = rawCid.isNotEmpty && !rawCid.contains('-') 
        ? rawCid 
        : (type == 'rooms'
            ? (!rawId.contains('-') ? rawId : '')
            : (!rawId.contains('-') && RegExp(r'^\d+$').hasMatch(rawId) ? rawId : ''));

    return GestureDetector(
      onTap: () {
        if (type == 'rooms') {
          final roomId = (item['room_id'] ?? item['id'] ?? item['uid'] ?? '').toString();
          if (roomId.isNotEmpty) {
            navigateToRoom(
              context,
              roomId: roomId,
              roomName: (item['name'] ?? 'Room').toString(),
              hostName: (item['host_name'] ?? 'Host').toString(),
              roomPassword: (item['password'] ?? '').toString(),
            );
          }
        } else {
          final uid = (item['uid'] ?? item['user_id'] ?? item['id'] ?? '').toString();
          if (uid.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(targetUid: uid),
              ),
            );
          }
        }
      },
      child: SizedBox(
        width: width,
        height: isGold ? 260 : 210,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            // Banner
            Positioned(
              top: avatarSize / 2 + 15,
              child: SizedBox(
                width: width - 10,
                height: isGold ? 190 : 150,
                child: _buildDynamicImage(remoteBanner, localBanner, fit: BoxFit.fill),
              ),
            ),
            
            // Name and Details on Banner
            Positioned(
              bottom: isGold ? 90 : 70,
              child: SizedBox(
                width: width - 10,
                child: Column(
                  children: [
                    SpecialNameText(
                      text: item['name']?.toString() ?? '',
                      customId: item['custom_id']?.toString() ?? item['display_id']?.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 1),
                    if (displayId.isNotEmpty)
                      DText(
                        'ID: #$displayId',
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/cp/ic_coin.webp',
                          width: 12,
                          height: 12,
                          errorBuilder: (_, __, ___) => const Icon(Icons.monetization_on, size: 12, color: Color(0xFFFFD54F)),
                        ),
                        const SizedBox(width: 4),
                        DText(
                          _formatPoints(item['points'] ?? 0),
                          style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Avatar and Frame
            Positioned(
              top: 0,
              child: SizedBox(
                width: width,
                height: width,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    ClipOval(
                      child: SizedBox(
                        width: avatarSize,
                        height: avatarSize,
                        child: photo.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: photo,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: Colors.grey.shade900,
                                  child: const Center(
                                    child: SizedBox(
                                      width: 15,
                                      height: 15,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFD54F)),
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Image.asset(
                                  type == 'rooms'
                                      ? R.defaultRoomPhoto
                                      : 'assets/mipmap-xxhdpi/avatar_default.png',
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Image.asset(
                                type == 'rooms'
                                    ? R.defaultRoomPhoto
                                    : 'assets/mipmap-xxhdpi/avatar_default.png',
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                    SizedBox(
                      width: frameSize,
                      height: frameSize,
                      child: _buildDynamicImage(remoteFrame, localFrame, fit: BoxFit.contain),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNormalItem(Map<String, dynamic> item, int rank, String type) {
    final config = context.watch<DynamicConfigService>();
    final remoteBg = config.globalRankListBg;
    final localBg = 'assets/mipmap-xxhdpi/global_rank_list_bg.png';
    final String photo = (item['photoUrl'] ?? item['photo_url'] ?? '').toString();
    final String rawCid = (item['custom_id'] ?? item['display_id'] ?? '').toString().trim();
    final String rawId = (item['room_id'] ?? item['user_id'] ?? item['id'] ?? '').toString().trim();
    final String displayId = rawCid.isNotEmpty && !rawCid.contains('-') 
        ? rawCid 
        : (type == 'rooms'
            ? (!rawId.contains('-') ? rawId : '')
            : (!rawId.contains('-') && RegExp(r'^\d+$').hasMatch(rawId) ? rawId : ''));

    return GestureDetector(
      onTap: () {
        if (type == 'rooms') {
          final roomId = (item['room_id'] ?? item['id'] ?? item['uid'] ?? '').toString();
          if (roomId.isNotEmpty) {
            navigateToRoom(
              context,
              roomId: roomId,
              roomName: (item['name'] ?? 'Room').toString(),
              hostName: (item['host_name'] ?? 'Host').toString(),
              roomPassword: (item['password'] ?? '').toString(),
            );
          }
        } else {
          final uid = (item['uid'] ?? item['user_id'] ?? item['id'] ?? '').toString();
          if (uid.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(targetUid: uid),
              ),
            );
          }
        }
      },
      child: Container(
        height: 75,
        margin: const EdgeInsets.only(bottom: 8),
        child: Stack(
          children: [
            Positioned.fill(
              child: _buildDynamicImage(remoteBg, localBg, fit: BoxFit.fill),
            ),
            Row(
              children: [
                const SizedBox(width: 20),
                SizedBox(
                  width: 30,
                  child: DText(
                    rank < 10 ? '0$rank' : '$rank',
                    style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 16, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 15),
                ClipOval(
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: photo.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: photo,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: Colors.grey.shade900,
                              child: const Center(
                                child: SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFD54F)),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Image.asset(
                              type == 'rooms'
                                  ? R.defaultRoomPhoto
                                  : 'assets/mipmap-xxhdpi/avatar_default.png',
                              fit: BoxFit.cover,
                            ),
                          )
                        : Image.asset(
                            type == 'rooms'
                                ? R.defaultRoomPhoto
                                : 'assets/mipmap-xxhdpi/avatar_default.png',
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SpecialNameText(
                        text: item['name']?.toString() ?? '',
                        customId: item['custom_id']?.toString() ?? item['display_id']?.toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (displayId.isNotEmpty)
                        DText(
                          'ID: #$displayId',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/cp/ic_coin.webp',
                      width: 14,
                      height: 14,
                      errorBuilder: (_, __, ___) => const Icon(Icons.monetization_on, size: 14, color: Color(0xFFFFD54F)),
                    ),
                    const SizedBox(width: 4),
                    DText(
                      '${_formatPoints(item['points'] ?? 0)} ↑',
                      style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(width: 25),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatPoints(int points) {
    if (points >= 1000000) {
      return '${(points / 1000000).toStringAsFixed(1)}M';
    } else if (points >= 1000) {
      return '${(points / 1000).toStringAsFixed(1)}K';
    }
    return points.toString();
  }
}