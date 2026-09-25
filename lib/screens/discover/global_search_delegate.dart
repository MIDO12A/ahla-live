import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zero/screens/user_profile/user_profile_screen.dart';
import 'package:zero/screens/room/room_screen.dart';

class GlobalSearchDelegate extends SearchDelegate<String?> {
  @override
  String get searchFieldLabel => 'ابحث عن مستخدم، غرفة، ID...';

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF1E1E2C),
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18),
        elevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white54),
        border: InputBorder.none,
      ),
      textTheme: theme.textTheme.copyWith(
        titleLarge: const TextStyle(color: Colors.white, fontSize: 18),
      ),
      scaffoldBackgroundColor: const Color(0xFF03030A),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear, color: Colors.white),
          onPressed: () {
            query = '';
          },
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back, color: Colors.white),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _GlobalSearchResults(query: query);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
      return Container(
        color: const Color(0xFF03030A),
        child: const Center(
          child: Text(
            'اكتب اسم المستخدم، اسم الغرفة، أو الـ ID للبحث...',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }
    return _GlobalSearchResults(query: query);
  }
}

class _GlobalSearchResults extends StatefulWidget {
  final String query;
  const _GlobalSearchResults({required this.query});

  @override
  State<_GlobalSearchResults> createState() => _GlobalSearchResultsState();
}

class _GlobalSearchResultsState extends State<_GlobalSearchResults> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _rooms = [];

  @override
  void initState() {
    super.initState();
    _performSearch();
  }

  @override
  void didUpdateWidget(covariant _GlobalSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _performSearch();
    }
  }

  Future<void> _performSearch() async {
    final q = widget.query.trim();
    if (q.isEmpty) {
      if (mounted) {
        setState(() {
          _users = [];
          _rooms = [];
          _isLoading = false;
        });
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
      List<Map<String, dynamic>> usersFound = [];
      List<Map<String, dynamic>> roomsFound = [];

      final isNumeric = int.tryParse(q) != null;

      // 1. Exact match by ID (if numeric)
      if (isNumeric) {
        final uidSnap = await db.collection('users').where('custom_id', isEqualTo: q).limit(5).get();
        for (var doc in uidSnap.docs) {
          final d = doc.data();
          d['docId'] = doc.id;
          usersFound.add(d);
        }

        final ridSnap = await db.collection('rooms').where('room_id', isEqualTo: q).limit(5).get();
        for (var doc in ridSnap.docs) {
          final d = doc.data();
          d['docId'] = doc.id;
          roomsFound.add(d);
        }
      }

      // 2. Prefix match by name (Users)
      final uNameSnap = await db.collection('users')
          .orderBy('name')
          .startAt([q])
          .endAt(['$q\uf8ff'])
          .limit(10)
          .get();
      
      for (var doc in uNameSnap.docs) {
        if (!usersFound.any((u) => u['docId'] == doc.id)) {
          final d = doc.data();
          d['docId'] = doc.id;
          usersFound.add(d);
        }
      }

      // 3. Prefix match by title (Rooms)
      final rNameSnap = await db.collection('rooms')
          .orderBy('title')
          .startAt([q])
          .endAt(['$q\uf8ff'])
          .limit(10)
          .get();
      
      for (var doc in rNameSnap.docs) {
        if (!roomsFound.any((r) => r['docId'] == doc.id)) {
          final d = doc.data();
          d['docId'] = doc.id;
          roomsFound.add(d);
        }
      }

      if (mounted) {
        setState(() {
          _users = usersFound;
          _rooms = roomsFound;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Search error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _enterRoom(Map<String, dynamic> r) {
    final roomId = r['docId'] as String;
    if (!RoomScreen.pushGuard(roomId)) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomScreen(
          roomId: roomId,
          roomName: r['title'] ?? 'Room',
          hostName: r['host_name'] ?? 'Host',
          roomPassword: r['password'] ?? '',
          hotValue: r['hot']?.toString() ?? '0',
          gameDesc: r['game_desc'] ?? '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: const Color(0xFF03030A),
        child: const Center(child: CircularProgressIndicator(color: Color(0xFFD3A350))),
      );
    }

    if (_users.isEmpty && _rooms.isEmpty) {
      return Container(
        color: const Color(0xFF03030A),
        child: const Center(child: Text('لا توجد نتائج', style: TextStyle(color: Colors.white54))),
      );
    }

    return Container(
      color: const Color(0xFF03030A),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_users.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('المستخدمين', style: TextStyle(color: Color(0xFFD3A350), fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ..._users.map((u) {
              final photoUrl = u['photo_url']?.toString() ?? u['photoUrl']?.toString() ?? u['avatar']?.toString() ?? '';
              final uid = u['uid']?.toString() ?? u['id']?.toString() ?? u['docId']?.toString() ?? '';
              
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                leading: Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(shape: BoxShape.circle),
                  clipBehavior: Clip.hardEdge,
                  child: photoUrl.isNotEmpty
                      ? Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white54, size: 30),
                        )
                      : const Icon(Icons.person, color: Colors.white54, size: 30),
                ),
                title: Text(u['name'] ?? u['username'] ?? 'مستخدم', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('ID: ${u['custom_id'] ?? u['customId'] ?? ''}', style: const TextStyle(color: Colors.white54)),
                onTap: () {
                  if (uid.isNotEmpty) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(targetUid: uid)));
                  }
                },
              );
            }),
            const SizedBox(height: 16),
          ],
          
          if (_rooms.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('الغرف', style: TextStyle(color: Color(0xFFD3A350), fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ..._rooms.map((r) {
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                leading: Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: DecorationImage(
                      image: NetworkImage(r['image'] ?? ''),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                title: Text(r['title'] ?? 'بدون اسم', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('ID: ${r['room_id'] ?? ''}', style: const TextStyle(color: Colors.white54)),
                onTap: () => _enterRoom(r),
              );
            }),
          ]
        ],
      ),
    );
  }
}
