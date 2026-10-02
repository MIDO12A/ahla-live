import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/cached_image.dart';
import '../../config/r.dart';
import '../../services/dynamic_config_service.dart';
import '../../services/supabase_service.dart';
import '../../models/banner_config.dart';
import '../../models/room_model.dart';
import '../../providers/user_provider.dart';
import 'create_room_screen.dart';
import '../../screens/room/room_screen.dart' show navigateToRoom;
import '../../screens/room/widgets/svga_player.dart';
import '../../screens/room/widgets/vap_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../screens/rank/rank_screen.dart';
import 'package:zero/screens/user_profile/user_profile_screen.dart';
import '../../utils/app_action_navigator.dart';
import 'global_search_delegate.dart';
import '../../widgets/user_id_widget.dart';

class RoomDiscoverScreen extends StatefulWidget {
  const RoomDiscoverScreen({super.key});

  @override
  State<RoomDiscoverScreen> createState() => _RoomDiscoverScreenState();
}

class _RoomDiscoverScreenState extends State<RoomDiscoverScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseService _firebaseService = SupabaseService();
  late final Stream<List<RoomModel>> _roomsStream;
  List<RoomModel>? _cachedRooms;
  late TabController _tabController;
  int _selectedTabIndex = 0;
  String _searchQuery = '';
  String? _selectedCountry;

  @override
  void initState() {
    super.initState();
    _roomsStream = _firebaseService.allRoomsStream();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedTabIndex = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _goToCreateOrMyRoom() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user == null) return;

    String? targetRoomId = user.hostedRoomId;
    if (targetRoomId == null || targetRoomId.isEmpty) {
      if (user.customId.isNotEmpty) {
        final existingRoom = await _firebaseService.getRoom(user.customId);
        if (existingRoom != null) {
          targetRoomId = user.customId;
          await _firebaseService.updateUser(user.uid, {'hosted_room_id': targetRoomId});
        }
      }
    }

    if (targetRoomId != null && targetRoomId.isNotEmpty) {
      final room = await _firebaseService.getRoom(targetRoomId);
      if (room != null) {
        navigateToRoom(
          context,
          roomName: room.name,
          hostName: user.name,
          hostUid: room.hostUid,
          roomId: targetRoomId,
        );
        return;
      } else {
        await _firebaseService.updateUser(user.uid, {'hosted_room_id': null});
        await userProvider.loadUser(user.uid);
      }
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
                  Text(
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
      leading: Text(flag, style: const TextStyle(fontSize: 24)),
      title: Text(name),
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
        body: Column(
          children: [
            _buildHeader(),
            const _BannerCarousel(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDiscoverContent(true, user),
                  _buildDiscoverContent(false, user),
                ],
              ),
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
                    child: R.image(R.tabRankingNor, width: 28, height: 28),
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
          Text(
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

  Widget _buildDiscoverContent(bool isDiscover, dynamic user) {
    return Column(
      children: [
        if (isDiscover) ...[
          _buildCountrySection(),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<List<RoomModel>>(
            stream: _roomsStream,
            initialData: _cachedRooms,
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty) {
                _cachedRooms = snapshot.data;
              }
              if (snapshot.connectionState == ConnectionState.waiting && (_cachedRooms == null || _cachedRooms!.isEmpty)) {
                return const Center(child: CircularProgressIndicator());
              }

              List<RoomModel> rooms = snapshot.data ?? _cachedRooms ?? [];

              if (!isDiscover && user != null) {
                rooms = rooms
                    .where((room) => user.followedRooms.contains(room.roomId))
                    .toList();
              }

              if (_searchQuery.isNotEmpty) {
                rooms = rooms.where((room) {
                  return room.name.toLowerCase().contains(_searchQuery) ||
                      room.hostName.toLowerCase().contains(_searchQuery);
                }).toList();
              }

              if (_selectedCountry != null && _selectedCountry!.isNotEmpty && _selectedCountry != 'الكل') {
                rooms = rooms.where((room) => _roomMatchesCountry(room, _selectedCountry)).toList();
              }

              if (rooms.isEmpty) {
                final isAr = Localizations.maybeLocaleOf(context)?.languageCode != 'en';
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.headset_off, size: 64, color: Colors.black26),
                      const SizedBox(height: 16),
                      Text(
                        isAr
                            ? 'لا توجد غرف حالياً\nابدأ بإنشاء غرفتك الآن!'
                            : 'No rooms yet\nCreate one!',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, color: Colors.black45),
                      ),
                    ],
                  ),
                );
              }

              return SingleChildScrollView(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1,
                        ),
                        itemCount: rooms.length,
                        itemBuilder: (context, index) {
                          final room = rooms[index];
                          final isFollowing =
                              user?.followedRooms.contains(room.roomId) ?? false;
                          final rankIndex = index < 3 ? index : -1;
                          return _buildRoomCard(room, isFollowing, user, rankIndex: rankIndex);
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          ),
        ),
      ],
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

  Widget _buildCountrySection() {
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
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          SizedBox(
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
                        Text(
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
                      final isActive = (isAll && (_selectedCountry == null || _selectedCountry == 'الكل' || _selectedCountry == 'All')) ||
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
                              color: isActive ? const Color(0xFF59370D) : const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  country['flag']!,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  countryName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isActive ? Colors.white : const Color(0xFF59370D),
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
        ],
      ),
    );
  }

  String? _rankBorderPath(int rankIndex) {
    if (rankIndex == 0) return R.roomRankBorder1;
    if (rankIndex == 1) return R.roomRankBorder2;
    if (rankIndex == 2) return R.roomRankBorder3;
    return null;
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
                  if (room.roomPhotoUrl.isNotEmpty)
                    R.loadImage(room.roomPhotoUrl, fit: BoxFit.cover),
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
                          Text(
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
                                room.hostPhotoUrl.isNotEmpty ? room.hostPhotoUrl : R.avaBoy,
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
                          if (room.category.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0x6616151A),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              margin: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                room.category,
                                style: const TextStyle(fontSize: 11, color: Colors.white),
                              ),
                            ),
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: Image.network(
                                  'https://flagcdn.com/w40/${UserIdWidget.resolveCountryCode(room.country)}.png',
                                  width: 18,
                                  height: 12,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Text(
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
                              if (room.hotValue > 0) ...[
                                const SizedBox(width: 2),
                                R.image(R.roomHotLogoIc, width: 12, height: 12),
                                const SizedBox(width: 1),
                                Text(
                                  '${room.hotValue}',
                                  style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
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
                          if (isFollowing) {
                            await _firebaseService.unfollowRoom(user.uid, room.roomId);
                          } else {
                            await _firebaseService.followRoom(user.uid, room.roomId);
                          }
                          if (mounted) {
                            Provider.of<UserProvider>(context, listen: false).loadUser(user.uid);
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

class _BannerCarousel extends StatefulWidget {
  const _BannerCarousel();

  @override
  State<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<_BannerCarousel> {
  final SupabaseService _firebaseService = SupabaseService();
  late PageController _bannerController;
  late Timer _bannerTimer;
  int _currentBannerPage = 0;
  List<BannerConfig> _banners = [];

  @override
  void initState() {
    super.initState();
    _bannerController = PageController(initialPage: 0);
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_bannerController.hasClients && _banners.length > 1) {
        final next = (_currentBannerPage + 1) % _banners.length;
        _bannerController.animateToPage(
          next,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _bannerTimer.cancel();
    _bannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BannerConfig>>(
      stream: _firebaseService.bannersStream(),
      builder: (context, snapshot) {
        _banners = snapshot.data ?? [];
        if (_banners.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            SizedBox(
              height: 160,
              child: PageView.builder(
                controller: _bannerController,
                onPageChanged: (page) {
                  setState(() => _currentBannerPage = page);
                },
                itemCount: _banners.length,
                itemBuilder: (context, index) {
                  final banner = _banners[index];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: GestureDetector(
                        onTap: () {
                          AppActionNavigator.handleAction(
                            context,
                            actionType: banner.actionType,
                            actionValue: banner.actionValue,
                            rawLink: banner.linkUrl,
                          );
                        },
                        child: CachedNetImage(
                          banner.imageUrl,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: const Color(0xFFF0F0F0),
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          error: (context, error, stackTrace) => Container(
                            color: const Color(0xFFF0F0F0),
                            child: const Icon(Icons.broken_image, color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_banners.length, (i) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _currentBannerPage == i ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentBannerPage == i
                        ? const Color(0xFF16151A)
                        : const Color(0x33808080),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ],
        );
      },
    );
  }
}

