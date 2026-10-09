import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../services/supabase_service.dart';
import '../../providers/user_provider.dart';
import '../user_profile/user_profile_screen.dart';

class FollowRecentScreen extends StatefulWidget {
  final int initialTab;
  final String? targetUid;
  const FollowRecentScreen({super.key, this.initialTab = 0, this.targetUid});

  @override
  State<FollowRecentScreen> createState() => _FollowRecentScreenState();
}

class _FollowRecentScreenState extends State<FollowRecentScreen>
  with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final supabase = SupabaseService();

  List<Map<String, dynamic>> _following = [];
  List<Map<String, dynamic>> _fans = [];
  List<Map<String, dynamic>> _visitors = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final myUid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
      final uid = widget.targetUid ?? myUid;
      if (uid != null && uid.isNotEmpty) {
        final results = await Future.wait([
          supabase.getFollowing(uid),
          supabase.getFans(uid),
          supabase.getVisitors(uid),
        ]);
        _following = results[0];
        _fans = results[1];
        _visitors = results[2];
      }
    } catch (e) {
      debugPrint('FollowRecentScreen _loadData error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5FC),
      body: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                    child: R.image(R.backIc, width: 24, height: 24),
                  ),
                ),
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    labelColor: const Color(0xFF16151A),
                    unselectedLabelColor: const Color(0xFF9BA1B6),
                    labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    unselectedLabelStyle: const TextStyle(fontSize: 13),
                    indicator: _buildTabIndicator(),
                    indicatorSize: TabBarIndicatorSize.label,
                    tabs: const [
                      Tab(text: 'المتابَعين', height: 44),
                      Tab(text: 'المعجبين', height: 44),
                      Tab(text: 'الزوار', height: 44),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildUserList(_following, isVisitor: false),
                      _buildUserList(_fans, isVisitor: false),
                      _buildUserList(_visitors, isVisitor: true),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Decoration _buildTabIndicator() {
    return const ShapeDecoration(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      color: Color(0xFFDE880F),
    );
  }

  Widget _buildUserList(List<Map<String, dynamic>> items, {bool isVisitor = false}) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.4,
              child: Center(
                child: Text(
                  isVisitor ? 'لا يوجد زوار حتى الآن' : 'لا يوجد مستخدمين حتى الآن',
                  style: const TextStyle(color: Color(0xFF9BA1B6), fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72, color: Color(0xFFF0F0F0)),
        itemBuilder: (context, index) {
          final item = items[index];
          return _buildUserItem(item, isVisitor: isVisitor);
        },
      ),
    );
  }

  Widget _buildUserItem(Map<String, dynamic> item, {bool isVisitor = false}) {
    final name = item['name']?.toString() ?? 'User';
    final id = item['uid']?.toString() ?? item['id']?.toString() ?? '';
    final customId = item['custom_id']?.toString() ?? item['customId']?.toString() ?? item['display_id']?.toString() ?? '';
    final displayId = customId.isNotEmpty ? customId : (id.length > 8 ? id.substring(0, 8) : id);
    final gender = item['gender']?.toString() ?? 'male';
    final level = (item['level'] as num?)?.toInt() ?? 0;
    final photoUrl = item['photo_url']?.toString() ?? item['avatar']?.toString() ?? '';
    final countryIdx = (item['country_idx'] as num?)?.toInt() ?? (item['country'] as num?)?.toInt() ?? 0;
    final isFollowed = item['is_followed'] as bool? ?? false;
    final time = item['time']?.toString() ?? item['last_visit']?.toString() ?? '';

    return GestureDetector(
      onTap: () {
        if (id.isNotEmpty) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => UserProfileScreen(targetUid: id),
          ));
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Stack(
              children: [
                ClipOval(
                  child: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFDE880F), width: 1.5),
                    ),
                    child: photoUrl.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image(image: R.cachedImage(photoUrl), fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 24, color: Colors.grey)),
                          )
                        : const Icon(Icons.person, size: 24, color: Colors.grey),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 20, height: 13,
                        decoration: BoxDecoration(
                          color: [Colors.blue, Colors.red, Colors.green, Colors.orange, Colors.purple][countryIdx % 5],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          name,
                          style: const TextStyle(fontSize: 14, color: Color(0xFF16151A)),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Image.asset(
                        gender == 'male' ? R.sexMaleIc : R.sexFemaleIc,
                        width: 18, height: 16,
                        errorBuilder: (_, __, ___) => Icon(
                          gender == 'male' ? Icons.male : Icons.female,
                          size: 16, color: gender == 'male' ? Colors.blue : Colors.pink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID: $displayId',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF9BA1B6)),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFDE880F), Color(0xFFFFC525)]),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Lv.$level',
                      style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isVisitor)
              Text(
                time,
                style: const TextStyle(fontSize: 10, color: Color(0xFF9BA1B6)),
              )
            else
              GestureDetector(
                onTap: () async {
                  final myUid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
                  if (myUid == null || myUid.isEmpty || id.isEmpty) return;
                  final currentlyFollowed = item['is_followed'] as bool? ?? false;
                  setState(() {
                    item['is_followed'] = !currentlyFollowed;
                  });
                  if (currentlyFollowed) {
                    await supabase.unfollowUser(myUid, id);
                  } else {
                    await supabase.followUser(myUid, id);
                  }
                },
                child: Container(
                  width: 71, height: 31,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isFollowed ? const Color(0xFFDE880F) : const Color(0xFFD4D6E5),
                      width: 1,
                    ),
                    color: isFollowed ? const Color(0xFFDE880F) : Colors.transparent,
                  ),
                  child: Center(
                    child: Text(
                      isFollowed ? 'Following' : 'Follow',
                      style: TextStyle(
                        fontSize: 11,
                        color: isFollowed ? Colors.white : const Color(0xFF303236),
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
}
