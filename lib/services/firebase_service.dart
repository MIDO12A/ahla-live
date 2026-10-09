import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/room_model.dart';
import '../models/message_model.dart';
import '../models/gift_model.dart' as gm;
import '../models/user_model.dart';
import '../models/store_item_model.dart';
import '../models/banner_config.dart';
import '../models/gifted_item_model.dart';
import '../models/notification_model.dart';
import '../models/ranking_frame_config.dart';
import '../models/gift_category_model.dart';
import '../models/gift_banner_config_model.dart';
import 'level_service.dart';
import 'cloudinary_service.dart';
import 'agency_target_evaluator.dart';
import 'dynamic_config_service.dart';
import 'supabase_auth_service.dart';
import 'supabase_data_service.dart';
import '../core/supabase_compat.dart';

/// Firebase (Firestore) implementation of the app's data layer.
///
/// Collections are named exactly like the original Supabase tables so the
/// whole schema maps 1:1 (see supabase/migrations/*.sql):
///   users, rooms, room_members, room_seats, room_messages, sent_gifts,
///   private_messages, conversations, follows, blocks, room_blocks,
///   notifications, reports, profile_visits, gifted_items, store_items,
///   banners, app_config, gifts, gift_categories, gift_banner_configs,
///   ranking_frames, badges, necklaces, user_wallets, level_config, vip_config
///
/// Auth is handled with Firebase Auth (anonymous + email/password + OAuth).
class FirebaseService {
  static final FirebaseService _instance = FirebaseService._();
  factory FirebaseService() => _instance;
  FirebaseService._();

  late final FirebaseApp _app;

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'default',
      );

  void init() {
    try {
      _db.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 104857600, // 100 MB cache limit
      );
    } catch (e) {
      debugPrint('Firestore settings: $e');
    }
  }

  Future<void> initializeApp() async {
    if (Firebase.apps.isNotEmpty) {
      _app = Firebase.app();
      return;
    }
    _app = await Firebase.initializeApp();
  }

  // ═══════════════════════════════════════════════════════
  // AUTH
  // ═══════════════════════════════════════════════════════

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentAuthUser => _auth.currentUser;

  String get currentUid => _auth.currentUser?.uid ?? '';

  Future<String?> signInAnonymously() async {
    final cred = await _auth.signInAnonymously();
    return cred.user?.uid;
  }

  Future<String?> signInWithEmail(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
    return cred.user?.uid;
  }

  Future<String?> signUpWithEmail(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    return cred.user?.uid;
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> deleteAuthAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.delete();
  }

  Future<String> getIdToken() async => await _auth.currentUser?.getIdToken() ?? '';

  // ═══════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════

  static String _now() => DateTime.now().toIso8601String();

  static Map<String, dynamic> _data(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    if (d == null) return {};
    final m = Map<String, dynamic>.from(d);
    m['id'] = doc.id;
    return m;
  }

  static Map<String, dynamic> _stripNulls(Map<String, dynamic> map) {
    final out = <String, dynamic>{};
    map.forEach((k, v) {
      if (v != null) out[k] = v;
    });
    return out;
  }

  // ═══════════════════════════════════════════════════════
  // ROOMS
  // ═══════════════════════════════════════════════════════

  Future<String> createRoom({
    required String name,
    String description = '',
    String roomPhotoUrl = '',
    required String hostUid,
    required String hostCustomId,
    required String hostName,
    String hostPhotoUrl = '',
    bool isLocked = false,
    String password = '',
    String category = '',
    String country = '',
  }) async {
    String resolvedRoomId = (hostCustomId.trim().isNotEmpty && hostCustomId.trim() != 'null')
        ? hostCustomId.trim()
        : hostUid.trim();

    // Guard against collision with another user's room
    try {
      final existingSb = await SupabaseDataService().getRoom(resolvedRoomId);
      if (existingSb != null && existingSb.hostUid.isNotEmpty && existingSb.hostUid != hostUid) {
        resolvedRoomId = '${resolvedRoomId}_${DateTime.now().millisecondsSinceEpoch % 10000}';
      }
    } catch (_) {}

    final roomId = resolvedRoomId;
    final room = RoomModel(
      roomId: roomId,
      name: name,
      description: description,
      roomPhotoUrl: roomPhotoUrl,
      hostUid: hostUid,
      hostName: hostName,
      hostPhotoUrl: hostPhotoUrl,
      memberCount: 1,
      maxMembers: 10,
      isLocked: isLocked,
      category: category,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      password: password,
      country: country,
    );

    // 1. Sync to Supabase
    try {
      await SupabaseDataService().createRoom(room);
      await SupabaseDataService().updateUser(hostUid, {'hosted_room_id': roomId});
    } catch (e) {
      debugPrint('createRoom Supabase error: $e');
    }

    // 2. Dual-write to Firestore
    try {
      await _db.collection('rooms').doc(roomId).set(room.toMap(), SetOptions(merge: true));
      await _db.collection('users').doc(hostUid).set({'hosted_room_id': roomId}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('createRoom: firestore set error (ignored): $e');
    }
    return roomId;
  }

  Future<void> followRoom(String uid, String roomId) async {
    try {
      try {
        final prefs = await SharedPreferences.getInstance();
        final list = prefs.getStringList('followed_rooms_$uid') ?? [];
        if (!list.contains(roomId)) {
          list.add(roomId);
          await prefs.setStringList('followed_rooms_$uid', list);
        }
      } catch (_) {}
      await _db.collection('users').doc(uid).set({
        'followed_rooms': FieldValue.arrayUnion([roomId]),
      }, SetOptions(merge: true));
      final doc = await _db.collection('users').doc(uid).get();
      final followed = List<String>.from(doc.data()?['followed_rooms'] ?? []);
      unawaited(SupabaseDataService().updateUser(uid, {'followed_rooms': followed}));
    } catch (e) {
      debugPrint('followRoom error: $e');
    }
  }

  Future<void> unfollowRoom(String uid, String roomId) async {
    try {
      try {
        final prefs = await SharedPreferences.getInstance();
        final list = prefs.getStringList('followed_rooms_$uid') ?? [];
        if (list.contains(roomId)) {
          list.remove(roomId);
          await prefs.setStringList('followed_rooms_$uid', list);
        }
      } catch (_) {}
      await _db.collection('users').doc(uid).set({
        'followed_rooms': FieldValue.arrayRemove([roomId]),
      }, SetOptions(merge: true));
      final doc = await _db.collection('users').doc(uid).get();
      final followed = List<String>.from(doc.data()?['followed_rooms'] ?? []);
      unawaited(SupabaseDataService().updateUser(uid, {'followed_rooms': followed}));
    } catch (e) {
      debugPrint('unfollowRoom error: $e');
    }
  }

  Stream<RoomModel?> roomStream(String roomId) {
    final controller = StreamController<RoomModel?>.broadcast();
    Timer? pollTimer;

    void fetchSupabase() async {
      try {
        final r = await SupabaseDataService().getRoom(roomId);
        if (r != null && !controller.isClosed) {
          controller.add(r);
        }
      } catch (_) {}
    }

    fetchSupabase();
    pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => fetchSupabase());

    StreamSubscription? firestoreSub;
    try {
      firestoreSub = _db.collection('rooms').doc(roomId).snapshots().listen((snap) {
        if (snap.exists && !controller.isClosed) {
          controller.add(RoomModel.fromMap(_data(snap)));
        }
      }, onError: (_) {});
    } catch (_) {}

    controller.onCancel = () {
      pollTimer?.cancel();
      firestoreSub?.cancel();
    };

    return controller.stream;
  }

  Future<List<RoomModel>> getAllRooms() async {
    try {
      final supaRooms = await SupabaseDataService().getAllRooms();
      if (supaRooms.isNotEmpty) return supaRooms;
    } catch (e) {
      debugPrint('getAllRooms Supabase error: $e');
    }

    try {
      final snap = await _db.collection('rooms').get();
      final rooms = snap.docs.map((e) => RoomModel.fromMap(_data(e))).toList();
      rooms.sort((a, b) => b.totalGifts.compareTo(a.totalGifts));
      return rooms;
    } catch (e) {
      if (e is! FirebaseException || (e.code != 'permission-denied' && e.code != 'unavailable')) {
        debugPrint('getAllRooms Firestore error: $e');
      }
      return [];
    }
  }

  Stream<List<RoomModel>> allRoomsStream() {
    final controller = StreamController<List<RoomModel>>.broadcast();
    Timer? pollTimer;
    String lastHash = '';

    bool isDifferent(List<RoomModel> newRooms) {
      final newHash = newRooms.map((r) => '${r.roomId}_${r.name}_${r.memberCount}_${r.totalGifts}_${r.hotValue}_${r.country}_${r.bgImage}').join('|');
      if (newHash != lastHash) {
        lastHash = newHash;
        return true;
      }
      return false;
    }

    void fetchSupabase() async {
      try {
        final list = await SupabaseDataService().getAllRooms();
        if (!controller.isClosed) {
          if (isDifferent(list)) {
            controller.add(list);
          }
        }
      } catch (_) {}
    }

    fetchSupabase();
    pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => fetchSupabase());

    controller.onCancel = () {
      pollTimer?.cancel();
    };

    return controller.stream;
  }

  Future<void> updateRoomMemberCount(String roomId, int count) async {
    unawaited(SupabaseDataService().updateRoom(roomId, {'member_count': count}));
    try {
      await _db.collection('rooms').doc(roomId).update({'member_count': count});
    } catch (_) {}
  }

  Future<void> updateRoomName(String roomId, String name) async {
    unawaited(SupabaseDataService().updateRoom(roomId, {'name': name}));
    try {
      await _db.collection('rooms').doc(roomId).update({'name': name});
    } catch (_) {}
  }

  Future<void> updateRoomSeatStyle(String roomId, int seatStyleIndex) async {
    unawaited(SupabaseDataService().updateRoom(roomId, {'seat_style': seatStyleIndex.toString()}));
    try {
      await _db.collection('rooms').doc(roomId).update({'seat_style': seatStyleIndex});
    } catch (_) {}
  }

  Future<void> updateRoomSeatCount(String roomId, int count) async {
    unawaited(SupabaseDataService().updateRoom(roomId, {'seat_count': count}));
    try {
      await _db.collection('rooms').doc(roomId).update({'seat_count': count});
    } catch (_) {}
  }

  Future<void> updateRoomSeatColor(String roomId, int seatColorIndex) async {
    unawaited(SupabaseDataService().updateRoom(roomId, {'seat_color': seatColorIndex.toString()}));
    try {
      await _db.collection('rooms').doc(roomId).update({'seat_color': seatColorIndex});
    } catch (_) {}
  }

  Future<void> updateRoomBackground(String roomId, String bgUrl) async {
    unawaited(SupabaseDataService().updateRoom(roomId, {'bg_image': bgUrl}));
    try {
      await _db.collection('rooms').doc(roomId).update({'bgImage': bgUrl, 'bg_image': bgUrl});
    } catch (_) {}
  }

  Future<RoomModel?> getRoom(String roomId) async {
    try {
      final r = await SupabaseDataService().getRoom(roomId);
      if (r != null) return r;
    } catch (_) {}

    try {
      final doc = await _db.collection('rooms').doc(roomId).get();
      if (!doc.exists) return null;
      return RoomModel.fromMap(_data(doc));
    } catch (_) {
      return null;
    }
  }

  Future<RoomModel?> getRoomByHost(String hostUid, {String? customId}) async {
    // 1. Try Supabase by host_uid
    try {
      final r = await SupabaseDataService().getRoomByHostUid(hostUid);
      if (r != null && r.hostUid == hostUid) return r;
    } catch (_) {}

    // 2. Try Firestore by host_uid
    try {
      final snap = await _db
          .collection('rooms')
          .where('host_uid', isEqualTo: hostUid)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final r = RoomModel.fromMap(_data(snap.docs.first));
        if (r.hostUid == hostUid) return r;
      }
    } catch (_) {}

    return null;
  }

  Future<void> updateRoom(String roomId, Map<String, dynamic> updates) async {
    unawaited(SupabaseDataService().updateRoom(roomId, updates));
    try {
      await _db.collection('rooms').doc(roomId).update(updates);
    } catch (_) {}
  }

  Future<void> addModerator(String roomId, String uid) async {
    final doc = await _db.collection('rooms').doc(roomId).get();
    if (!doc.exists) return;
    final d = doc.data() ?? {};
    final mods = List<String>.from(d['moderators'] ?? d['moderator_uids'] ?? []);
    if (!mods.contains(uid)) {
      mods.add(uid);
      await _db.collection('rooms').doc(roomId).update({
        'moderators': mods,
        'moderator_uids': mods,
      });
    }
  }

  Future<void> removeModerator(String roomId, String uid) async {
    final doc = await _db.collection('rooms').doc(roomId).get();
    if (!doc.exists) return;
    final d = doc.data() ?? {};
    final mods = List<String>.from(d['moderators'] ?? d['moderator_uids'] ?? []);
    mods.remove(uid);
    await _db.collection('rooms').doc(roomId).update({
      'moderators': mods,
      'moderator_uids': mods,
    });
  }

  // ═══════════════════════════════════════════════════════
  // MEMBERS
  // ═══════════════════════════════════════════════════════

  Future<void> joinRoom(String roomId, UserModel user) async {
    unawaited(SupabaseDataService().joinRoom(roomId, user));
    try {
      await _db.collection('room_members').doc('${roomId}_${user.uid}').set({
        'room_id': roomId,
        'uid': user.uid,
        'name': user.name,
        'photo_url': user.photoUrl,
        'role': 'member',
        'joined_at': _now(),
      });
    } catch (_) {}
  }

  Future<void> leaveRoom(String roomId, String uid) async {
    unawaited(SupabaseDataService().leaveRoom(roomId, uid));
    try {
      await _db.collection('room_members').doc('${roomId}_$uid').delete();
    } catch (_) {}
  }

  Stream<List<UserModel>> roomMembersStream(String roomId) {
    final controller = StreamController<List<UserModel>>.broadcast();
    Timer? pollTimer;

    void fetchSupabase() async {
      try {
        final members = await SupabaseDataService().getRoomMembers(roomId);
        if (!controller.isClosed) {
          controller.add(members);
        }
      } catch (_) {}
    }

    fetchSupabase();
    pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => fetchSupabase());

    controller.onCancel = () {
      pollTimer?.cancel();
    };

    return controller.stream;
  }

  // ═══════════════════════════════════════════════════════
  // SEATS
  // ═══════════════════════════════════════════════════════

  Future<bool> takeSeat(String roomId, int seatIndex, UserModel user) async {
    // 1. Sync to Supabase directly and await result
    final supaResult = await SupabaseDataService().takeSeat(
      roomId: roomId,
      seatIndex: seatIndex,
      user: user,
    );

    // 2. Best-effort Firestore write
    try {
      final ref = _db.collection('room_seats').doc('${roomId}_$seatIndex');
      final seatData = {
        'room_id': roomId,
        'seat_index': seatIndex,
        'uid': user.uid,
        'custom_id': user.customId,
        'name': user.name,
        'photo_url': user.photoUrl,
        'active_frame': user.activeFrame,
        'active_car': user.activeCar,
        'active_mic_wave': user.activeMicWave,
        'gender': user.gender,
        'country': user.country,
        'country_code': user.country.toLowerCase(),
        'is_muted': false,
        'taken_at': _now(),
      };
      await ref.set(seatData);
    } catch (_) {}
    return supaResult;
  }

  Future<void> leaveSeat(String roomId, int seatIndex) async {
    await SupabaseDataService().leaveSeat(roomId, seatIndex);
    try {
      await _db.collection('room_seats').doc('${roomId}_$seatIndex').delete();
    } catch (_) {}
  }

  Future<void> leaveSeatForUser(String roomId, String uid) async {
    await SupabaseDataService().leaveSeatForUser(roomId, uid);
    try {
      final snap = await _db
          .collection('room_seats')
          .where('room_id', isEqualTo: roomId)
          .where('uid', isEqualTo: uid)
          .get();
      for (final doc in snap.docs) {
        await doc.reference.delete();
      }
    } catch (_) {}
  }

  Future<void> toggleMute(String roomId, int seatIndex, bool muted) async {
    unawaited(SupabaseDataService().toggleMute(roomId, seatIndex, muted));
    try {
      final ref = _db.collection('room_seats').doc('${roomId}_$seatIndex');
      await ref.set({
        'room_id': roomId,
        'seat_index': seatIndex,
        'is_muted': muted,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('toggleMute error: $e');
    }
  }

  Stream<Map<int, Map<String, dynamic>>> seatsStream(String roomId) {
    final controller = StreamController<Map<int, Map<String, dynamic>>>.broadcast();
    Timer? pollTimer;
    Map<int, Map<String, dynamic>> lastMap = {};
    bool hasEmitted = false;

    bool areMapsEqual(Map<int, Map<String, dynamic>> a, Map<int, Map<String, dynamic>> b) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k)) return false;
        final vA = a[k]!;
        final vB = b[k]!;
        if (vA['uid'] != vB['uid'] ||
            vA['is_muted'] != vB['is_muted'] ||
            vA['is_locked'] != vB['is_locked'] ||
            vA['name'] != vB['name'] ||
            vA['photo_url'] != vB['photo_url'] ||
            vA['active_frame'] != vB['active_frame'] ||
            vA['active_car'] != vB['active_car']) {
          return false;
        }
      }
      return true;
    }

    void fetchSupabase() async {
      try {
        final seats = await SupabaseDataService().getSeats(roomId);
        if (!controller.isClosed) {
          if (!hasEmitted || !areMapsEqual(lastMap, seats)) {
            hasEmitted = true;
            lastMap = Map<int, Map<String, dynamic>>.from(seats);
            controller.add(seats);
          }
        }
      } catch (_) {}
    }

    fetchSupabase();
    pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => fetchSupabase());

    controller.onCancel = () {
      pollTimer?.cancel();
    };

    return controller.stream;
  }

  // ═══════════════════════════════════════════════════════
  // MESSAGES
  // ═══════════════════════════════════════════════════════

  Future<void> sendMessage(String roomId, String text, String senderUid,
      String senderName, String senderPhotoUrl, {String? activeBubble}) async {
    final msgId = const Uuid().v4();
    final msg = MessageModel(
      msgId: msgId,
      roomId: roomId,
      senderUid: senderUid,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      text: text,
      type: 'text',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      activeBubble: activeBubble,
    );
    unawaited(SupabaseDataService().sendMessage(msg));
    try {
      await _db.collection('room_messages').doc(msgId).set(msg.toMap());
    } catch (_) {}
  }

  Stream<List<MessageModel>> messagesStream(String roomId, {String? since}) {
    final controller = StreamController<List<MessageModel>>.broadcast();
    Timer? pollTimer;
    StreamSubscription? firestoreSub;
    final Map<String, MessageModel> msgMap = {};

    void addMessages(List<MessageModel> list) {
      if (controller.isClosed) return;
      bool hasNew = false;
      for (final m in list) {
        final key = m.msgId.isNotEmpty ? m.msgId : '${m.timestamp}_${m.senderUid}';
        if (!msgMap.containsKey(key)) {
          msgMap[key] = m;
          hasNew = true;
        }
      }
      if (hasNew || msgMap.isNotEmpty) {
        final sorted = msgMap.values.toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        controller.add(sorted);
      }
    }

    void fetchSupabase() async {
      try {
        final sinceMs = since != null ? DateTime.tryParse(since)?.millisecondsSinceEpoch : null;
        final list = await SupabaseDataService().getRoomMessages(roomId, limit: 60, sinceMs: sinceMs);
        addMessages(list);
      } catch (_) {}
    }

    // 1. استماع لحظي لـ Firestore room_messages لدعم المزامنة الفورية بين كل مستخدمي الغرفة
    try {
      firestoreSub = _db
          .collection('room_messages')
          .where('room_id', isEqualTo: roomId)
          .limit(60)
          .snapshots()
          .listen((snap) {
        final list = snap.docs.map((doc) {
          final data = doc.data();
          final createdIso = data['created_at']?.toString() ?? '';
          final ts = DateTime.tryParse(createdIso)?.millisecondsSinceEpoch ??
              (data['timestamp'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch;
          return MessageModel(
            msgId: doc.id,
            roomId: data['room_id']?.toString() ?? roomId,
            senderUid: data['sender_uid']?.toString() ?? '',
            senderName: data['sender_name']?.toString() ?? '',
            senderPhotoUrl: data['sender_photo_url']?.toString() ?? '',
            text: data['text']?.toString() ?? '',
            type: data['type']?.toString() ?? 'text',
            timestamp: ts,
            imageUrl: data['image_url']?.toString(),
            activeBubble: data['active_bubble']?.toString(),
            giftPayload: data['gift_payload'] is Map ? Map<String, dynamic>.from(data['gift_payload'] as Map) : null,
          );
        }).toList();
        addMessages(list);
      }, onError: (_) {});
    } catch (_) {}

    fetchSupabase();
    pollTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) => fetchSupabase());

    controller.onCancel = () {
      pollTimer?.cancel();
      firestoreSub?.cancel();
    };

    return controller.stream;
  }

  // ═══════════════════════════════════════════════════════
  // GIFTS
  // ═══════════════════════════════════════════════════════

  /// Safe int conversion – fields may be stored as int, double or string by
  /// different writers (admin dashboard, REST backend, manual console edits).
  /// A strict `as int` cast throws inside the transaction and silently rolls
  /// back the whole gift (no coin deduction).
  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  Future<bool> sendGift({
    required String roomId,
    required String giftId,
    String giftName = '',
    String? animationAsset,
    String? defaultImage,
    required String senderId,
    required String senderName,
    required String senderPhotoUrl,
    required String receiverId,
    required String receiverName,
    required int value,
    int count = 1,
  }) async {
    final id = const Uuid().v4();
    final totalCost = value * count;
    final bool isSelfSend = senderId == receiverId;
    final senderRef = _db.collection('users').doc(senderId);

    // Look up agency membership and agency outside transaction to prevent Firestore transaction query errors & ordering violations
    DocumentReference? agencyMemberRef;
    DocumentReference? agencyRef;
    String? resolvedAgencyId;
    if (!isSelfSend) {
      try {
        final memberQs = await _db
            .collection('host_agency_members')
            .where('user_id', isEqualTo: receiverId)
            .get();

        QueryDocumentSnapshot<Map<String, dynamic>>? activeDoc;
        if (memberQs.docs.isNotEmpty) {
          for (final d in memberQs.docs) {
            final st = d.data()['status']?.toString();
            if (st == 'active') {
              activeDoc = d;
              break;
            }
          }
          activeDoc ??= memberQs.docs.firstWhere(
            (d) {
              final st = d.data()['status']?.toString();
              return st != 'pending' && st != 'rejected' && st != 'left' && st != 'kicked';
            },
            orElse: () => memberQs.docs.first,
          );
        }

        if (activeDoc != null) {
          agencyMemberRef = activeDoc.reference;
          resolvedAgencyId = activeDoc.data()['agency_id']?.toString();
        }

        if (agencyMemberRef == null || resolvedAgencyId == null || resolvedAgencyId.isEmpty) {
          final uSnap = await _db.collection('users').doc(receiverId).get();
          final aid = uSnap.data()?['agency_id']?.toString() ?? uSnap.data()?['agencyId']?.toString();
          if (aid != null && aid.isNotEmpty) {
            resolvedAgencyId = aid;
            final mDocDirect = await _db.collection('host_agency_members').doc('${aid}_$receiverId').get();
            if (mDocDirect.exists) {
              agencyMemberRef = mDocDirect.reference;
            } else {
              final mByAid = await _db
                  .collection('host_agency_members')
                  .where('agency_id', isEqualTo: aid)
                  .where('user_id', isEqualTo: receiverId)
                  .limit(1)
                  .get();
              if (mByAid.docs.isNotEmpty) {
                agencyMemberRef = mByAid.docs.first.reference;
              } else {
                agencyMemberRef = _db.collection('host_agency_members').doc('${aid}_$receiverId');
              }
            }
          }
        }

        if (agencyMemberRef == null || resolvedAgencyId == null || resolvedAgencyId.isEmpty) {
          final ownerSnap = await _db.collection('host_agencies').where('owner_id', isEqualTo: receiverId).limit(1).get();
          if (ownerSnap.docs.isNotEmpty) {
            resolvedAgencyId = ownerSnap.docs.first.id;
            agencyMemberRef = _db.collection('host_agency_members').doc('${resolvedAgencyId}_$receiverId');
          }
        }

        if (resolvedAgencyId != null && resolvedAgencyId.isNotEmpty) {
          agencyRef = _db.collection('host_agencies').doc(resolvedAgencyId);
        }
      } catch (_) {}
    }

    // Pre-sync sender coins if Firestore is lagging behind Supabase
    try {
      final sUser = await SupabaseAuthService().getUserFromSupabase(senderId);
      if (sUser != null && sUser.coins > 0) {
        final sSnap = await senderRef.get();
        final fCoins = _asInt(sSnap.data()?['coins']);
        if (sUser.coins > fCoins) {
          await senderRef.set({'coins': sUser.coins}, SetOptions(merge: true));
        }
      }
    } catch (_) {}

    try {
      await _db.runTransaction((txn) async {
        // ── ALL READS FIRST ──
        final senderSnap = await txn.get(senderRef);
        if (!senderSnap.exists) throw Exception('sender missing');
        final senderCoins = _asInt(senderSnap.data()?['coins']);
        if (senderCoins < totalCost) throw Exception('insufficient coins');

        final receiverRef = _db.collection('users').doc(receiverId);
        final recvSnap = await txn.get(receiverRef);

        final roomRef = _db.collection('rooms').doc(roomId);
        final roomSnap = await txn.get(roomRef);

        final walletRef = _db.collection('user_wallets').doc(receiverId);
        final wSnap = await txn.get(walletRef);

        DocumentSnapshot? agencyMemberSnap;
        if (!isSelfSend && agencyMemberRef != null) {
          agencyMemberSnap = await txn.get(agencyMemberRef);
        }

        DocumentSnapshot? agencySnap;
        if (!isSelfSend && agencyRef != null) {
          agencySnap = await txn.get(agencyRef);
        }

        // ── THEN ALL WRITES ──
        txn.set(_db.collection('sent_gifts').doc(id), {
          'id': id,
          'gift_id': giftId,
          'gift_name': giftName,
          'animation_asset': animationAsset,
          'icon_asset': defaultImage ?? animationAsset ?? '',
          'default_image': defaultImage ?? animationAsset ?? '',
          'sender_id': senderId,
          'sender_name': senderName,
          'sender_photo_url': senderPhotoUrl,
          'receiver_id': receiverId,
          'receiver_name': receiverName,
          'room_id': roomId,
          'value': value,
          'count': count,
          'created_at': DateTime.now().toIso8601String(),
        });

        txn.set(_db.collection('room_messages').doc(const Uuid().v4()), {
          'msg_id': const Uuid().v4(),
          'room_id': roomId,
          'sender_uid': senderId,
          'sender_name': senderName,
          'sender_photo_url': senderPhotoUrl,
          'type': 'gift',
          'text': '$senderName 🎁 $giftName x$count → $receiverName',
          'image_url': defaultImage ?? animationAsset ?? '',
          'gift_payload': {
            'gift_id': giftId,
            'gift_name': giftName,
            'receiver_name': receiverName,
            'receiver_id': receiverId,
            'count': count,
            'gift_icon': defaultImage ?? animationAsset ?? '',
            'coin_value': value,
            'animation_asset': animationAsset,
            'default_image': defaultImage,
            'sender_name': senderName,
            'sender_photo_url': senderPhotoUrl,
          },
          'created_at': DateTime.now().toIso8601String(),
        });

        final String cleanGiftIcon = (defaultImage != null &&
                !defaultImage.endsWith('.svga') &&
                !defaultImage.endsWith('.vap') &&
                !defaultImage.endsWith('.mp4'))
            ? defaultImage
            : '';

        final giftPayloadData = {
          'gift_id': giftId,
          'gift_name': giftName,
          'receiver_name': receiverName,
          'receiver_id': receiverId,
          'count': count,
          'gift_icon': cleanGiftIcon.isNotEmpty ? cleanGiftIcon : (defaultImage ?? ''),
          'coin_value': value,
          'animation_asset': animationAsset,
          'default_image': defaultImage,
          'sender_name': senderName,
          'sender_photo_url': senderPhotoUrl,
        };

        unawaited(SupabaseDataService().sendMessage(MessageModel(
          msgId: const Uuid().v4(),
          roomId: roomId,
          senderUid: senderId,
          senderName: senderName,
          senderPhotoUrl: senderPhotoUrl,
          type: 'gift',
          text: '$senderName 🎁 $giftName x$count → $receiverName',
          imageUrl: cleanGiftIcon.isNotEmpty ? cleanGiftIcon : (defaultImage ?? animationAsset ?? ''),
          giftPayload: giftPayloadData,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        )).catchError((_) => false));

        final sd = senderSnap.data() ?? {};
        final sentTotal = _asInt(sd['total_gifts_sent']);
        txn.update(senderRef, {
          'coins': senderCoins - totalCost,
          'total_gifts_sent': sentTotal + totalCost,
        });

        if (recvSnap.exists) {
          final rd = recvSnap.data() ?? {};
          txn.update(receiverRef, {
            'diamonds': _asInt(rd['diamonds']) + totalCost,
            'total_gifts_received': _asInt(rd['total_gifts_received']) + totalCost,
          });
        }

        if (roomSnap.exists) {
          final rm = roomSnap.data() ?? {};
          final currentRocket = _asInt(rm['rocket_energy']);
          final rocketTarget = _asInt(rm['rocket_target']) > 0 ? _asInt(rm['rocket_target']) : 5000;
          final newRocket = currentRocket + totalCost;
          final isBurst = newRocket >= rocketTarget;
          txn.update(roomRef, {
            'total_gifts': _asInt(rm['total_gifts']) + totalCost,
            'hot_value': _asInt(rm['hot_value']) + totalCost,
            'rocket_energy': isBurst ? 0 : newRocket,
            if (isBurst) 'rocket_burst_active': true,
            if (isBurst) 'rocket_burst_id': const Uuid().v4(),
            if (isBurst) 'rocket_burst_time': DateTime.now().toIso8601String(),
          });

          // Global broadcast for room gifts (لافتة الهدايا العامة لجميع الغرف)
          if (totalCost >= 200) {
            final bId = const Uuid().v4();
            final now = DateTime.now();
            txn.set(_db.collection('broadcasts').doc(bId), {
              'id': bId,
              'sender_uid': senderId,
              'sender_name': senderName,
              'sender_photo_url': senderPhotoUrl,
              'receiver_name': receiverName,
              'room_id': roomId,
              'room_name': rm['name']?.toString() ?? 'غرفة صوتية',
              'content': 'أرسل $giftName x$count بقيمة $totalCost عملة!',
              'gift_name': giftName,
              'gift_icon': defaultImage ?? animationAsset ?? '',
              'count': count,
              'type': 'big_gift',
              'timestamp': now.millisecondsSinceEpoch,
              'created_at': now.toUtc().toIso8601String(),
            });
          }
        }

        if (wSnap.exists) {
          final wd = wSnap.data() ?? {};
          txn.update(walletRef, {'diamond_balance': _asInt(wd['diamond_balance']) + totalCost});
        } else {
          txn.set(walletRef, {'user_id': receiverId, 'diamond_balance': totalCost, 'gold_balance': 0});
        }

        // Only update agency earnings and host agency target if NOT self-sending
        if (!isSelfSend) {
          if (agencyMemberSnap != null && agencyMemberSnap.exists) {
            final md = agencyMemberSnap.data() as Map<String, dynamic>? ?? {};
            txn.update(agencyMemberSnap.reference, {
              'diamonds': _asInt(md['diamonds']) + totalCost,
              'diamonds_balance': _asInt(md['diamonds_balance']) + totalCost,
              'diamonds_available': _asInt(md['diamonds_available']) + totalCost,
              'diamonds_earned_monthly': _asInt(md['diamonds_earned_monthly']) + totalCost,
              'diamonds_earned_cumulative': _asInt(md['diamonds_earned_cumulative']) + totalCost,
            });
          } else if (agencyMemberRef != null && (agencyMemberSnap == null || !agencyMemberSnap.exists) && resolvedAgencyId != null) {
            txn.set(agencyMemberRef, {
              'id': agencyMemberRef.id,
              'agency_id': resolvedAgencyId,
              'user_id': receiverId,
              'status': 'active',
              'role': 'host',
              'diamonds': totalCost,
              'diamonds_balance': totalCost,
              'diamonds_available': totalCost,
              'diamonds_earned_monthly': totalCost,
              'diamonds_earned_cumulative': totalCost,
              'joined_at': DateTime.now().toUtc().toIso8601String(),
            }, SetOptions(merge: true));
          }

          if (agencySnap != null && agencySnap.exists) {
            final ad = agencySnap.data() as Map<String, dynamic>? ?? {};
            txn.update(agencySnap.reference, {
              'total_diamonds_monthly': _asInt(ad['total_diamonds_monthly']) + totalCost,
              'total_diamonds_cumulative': _asInt(ad['total_diamonds_cumulative']) + totalCost,
            });
          }
        }
      });
    } catch (e) {
      debugPrint('sendGift: Firestore transaction failed: $e');
      try {
        final sUser = await SupabaseAuthService().getUserFromSupabase(senderId);
        if (sUser == null || sUser.coins < totalCost) {
          debugPrint('sendGift: insufficient coins in Supabase as well');
          return false;
        }
        // Send Supabase room message even if Firestore failed
        final String cleanGiftIcon = (defaultImage != null &&
                !defaultImage.endsWith('.svga') &&
                !defaultImage.endsWith('.vap') &&
                !defaultImage.endsWith('.mp4'))
            ? defaultImage
            : '';

        final giftPayloadData = {
          'gift_id': giftId,
          'gift_name': giftName,
          'receiver_name': receiverName,
          'receiver_id': receiverId,
          'count': count,
          'gift_icon': cleanGiftIcon.isNotEmpty ? cleanGiftIcon : (defaultImage ?? ''),
          'coin_value': value,
          'animation_asset': animationAsset,
          'default_image': defaultImage,
          'sender_name': senderName,
          'sender_photo_url': senderPhotoUrl,
        };
        unawaited(SupabaseDataService().sendMessage(MessageModel(
          msgId: const Uuid().v4(),
          roomId: roomId,
          senderUid: senderId,
          senderName: senderName,
          senderPhotoUrl: senderPhotoUrl,
          type: 'gift',
          text: '$senderName 🎁 $giftName x$count → $receiverName',
          imageUrl: cleanGiftIcon.isNotEmpty ? cleanGiftIcon : (defaultImage ?? animationAsset ?? ''),
          giftPayload: giftPayloadData,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        )).catchError((_) => false));
      } catch (_) {
        return false;
      }
    }

    // Host target evaluation and ledger update (only for non-self send)
    if (!isSelfSend) {
      unawaited(Future(() async {
        if (resolvedAgencyId != null && resolvedAgencyId.isNotEmpty) {
          try {
            await _db.collection('agency_diamond_ledger').add({
              'agency_id': resolvedAgencyId,
              'user_id': receiverId,
              'sender_id': senderId,
              'sender_name': senderName,
              'gift_id': giftId,
              'gift_name': giftName,
              'amount': totalCost,
              'direction': 1,
              'txn_type': 'gift',
              'created_at': DateTime.now().toUtc().toIso8601String(),
            });
          } catch (e) {
            debugPrint('agency_diamond_ledger error: $e');
          }

          // Sync to Supabase host_agency_members & host_agencies
          try {
            final q = await _db.collection('host_agency_members').where('user_id', isEqualTo: receiverId).limit(1).get();
            if (q.docs.isNotEmpty) {
              final doc = q.docs.first;
              final currentD = (doc.data()['diamonds'] as num?)?.toInt() ?? 0;
              final currentMonthly = (doc.data()['diamonds_earned_monthly'] as num?)?.toInt() ?? 0;
              await doc.reference.update({
                'diamonds': currentD + totalCost,
                'diamonds_balance': currentD + totalCost,
                'diamonds_earned_monthly': currentMonthly + totalCost,
              });
            }
          } catch (_) {}
        }

        try {
          await AgencyTargetEvaluator.evaluateHostTargets(receiverId);
        } catch (_) {}
      }));
    }

    // Real-time notification for the receiver (non-fatal, background)
    unawaited(sendNotification(
      uid: receiverId,
      type: 'gift',
      actorUid: senderId,
      title: '🎁 هدية من $senderName',
      body: '$senderName أرسل لك "$giftName" x$count ($totalCost)',
      data: <String, dynamic>{
        'sender_name': senderName,
        'sender_photo': senderPhotoUrl,
        'gift_id': giftId,
        'gift_name': giftName,
        'gift_image': animationAsset ?? '',
        'value': value,
        'count': count,
        'room_id': roomId,
      },
    ).catchError((_) {}));

    // بث الهدايا الفاخرة للبانر الماركي العام لجميع الغرف (view_room_all_banner.xml)
    if (totalCost >= 200) {
      unawaited(Future(() async {
        try {
          final bId = const Uuid().v4();
          final now = DateTime.now();
          await _db.collection('broadcasts').doc(bId).set({
            'id': bId,
            'sender_uid': senderId,
            'sender_name': senderName,
            'sender_photo_url': senderPhotoUrl,
            'receiver_name': receiverName,
            'room_id': roomId,
            'room_name': 'غرفة صوتية',
            'content': 'أرسل $giftName x$count بقيمة $totalCost عملة!',
            'gift_name': giftName,
            'gift_icon': animationAsset ?? '',
            'count': count,
            'type': 'big_gift',
            'timestamp': now.millisecondsSinceEpoch,
            'created_at': now.toUtc().toIso8601String(),
          });
        } catch (_) {}
      }));
    }

    // XP side-effects (non-fatal, background)
    unawaited(Future(() async {
      try {
        final levelService = LevelService();
        await levelService.loadAllLevels();
        await levelService.addExp(uid: senderId, type: 'wealth', amount: totalCost);
        await levelService.addExp(uid: receiverId, type: 'gems', amount: totalCost);
      } catch (_) {}
    }));

    // Record gift transaction in Supabase
    unawaited(Future(() async {
      try {
        await SupabaseDataService().recordSentGift(
          roomId: roomId,
          giftId: giftId,
          giftName: giftName,
          animationAsset: animationAsset ?? defaultImage,
          senderId: senderId,
          senderName: senderName,
          senderPhotoUrl: senderPhotoUrl,
          receiverId: receiverId,
          receiverName: receiverName,
          value: value,
          count: count,
        );
      } catch (_) {}
    }));

    // Deduct coins & add diamonds in Supabase
    unawaited(Future(() async {
      try {
        final newCoins = (senderCoins - totalCost).clamp(0, 999999999999);
        await SupabaseDataService().updateUser(senderId, {
          'coins': newCoins,
          'total_gifts_sent': sentTotal + totalCost,
        });
        final rUser = await SupabaseAuthService().getUserFromSupabase(receiverId);
        if (rUser != null) {
          await SupabaseDataService().updateUser(receiverId, {
            'diamonds': rUser.diamonds + totalCost,
            'total_gifts_received': rUser.totalGiftsReceived + totalCost,
          });
        }
      } catch (_) {}
    }));

    return true;
  }

  /// ═══════════════════════════════════════════════════════
  /// LUCKY GIFTS & BURST SYSTEM (FIREBASE FIRESTORE)
  /// ═══════════════════════════════════════════════════════

  List<int> drawLuckyMultipliers(int count) {
    final cardCount = count < 4 ? 4 : (count > 8 ? 8 : count);
    final random = math.Random.secure();

    // جدول نسب الفوز والخسارة المعياري العالمي (RTP: 82.5%، نسبة الخسارة: 58.3%)
    // يضمن عدم استمرار الفوز بلا توقف وتوزيع النتائج بدقة هندسية:
    // - خسارة (0X): 58.296% (58,296 / 100,000)
    // - استرداد التكلفة / تعادل (1X): 28.000% (28,000 / 100,000)
    // - ربح مضاعف (2X): 10.000% (10,000 / 100,000)
    // - ربح جيد (5X): 2.500% (2,500 / 100,000)
    // - ربح كبير (10X): 0.800% (800 / 100,000)
    // - ربح فائق (20X): 0.300% (300 / 100,000)
    // - بيج وين (50X): 0.080% (80 / 100,000)
    // - جاكبوت (100X): 0.020% (20 / 100,000)
    // - سوبر جاكبوت (500X): 0.004% (4 / 100,000)
    final effectiveCount = count > 0 ? count : 1;
    final wonMultipliers = <int>[];
    for (int c = 0; c < effectiveCount; c++) {
      final roll = random.nextInt(100000);
      int mult;
      if (roll < 58296) {
        mult = 0;
      } else if (roll < 86296) {
        mult = 1;
      } else if (roll < 96296) {
        mult = 2;
      } else if (roll < 98796) {
        mult = 5;
      } else if (roll < 99596) {
        mult = 10;
      } else if (roll < 99896) {
        mult = 20;
      } else if (roll < 99976) {
        mult = 50;
      } else if (roll < 99996) {
        mult = 100;
      } else {
        mult = 500;
      }
      if (mult > 0) {
        wonMultipliers.add(mult);
      }
    }

    final cards = List<int>.filled(cardCount, 0);
    final indices = List<int>.generate(cardCount, (i) => i)..shuffle(random);
    for (int i = 0; i < wonMultipliers.length && i < cardCount; i++) {
      cards[indices[i]] = wonMultipliers[i];
    }
    for (int i = cardCount; i < wonMultipliers.length; i++) {
      final randomIdx = random.nextInt(cardCount);
      cards[randomIdx] += wonMultipliers[i];
    }

    return cards;
  }

  Future<Map<String, dynamic>?> sendLuckyGift({
    required String roomId,
    required String giftId,
    required String giftName,
    required String giftNameAr,
    required String giftIconUrl,
    required String giftCoverUrl,
    required String giftBgUrl,
    String? svgaAnimUrl,
    required String senderId,
    required String senderName,
    required String senderPhotoUrl,
    required String receiverId,
    required String receiverName,
    required int value,
    int count = 1,
    String? comboId,
    int comboCount = 1,
    List<int>? preDrawnMultipliers,
  }) async {
    final multipliers = preDrawnMultipliers ?? drawLuckyMultipliers(count);
    int totalWonCoins = 0;
    for (final m in multipliers) {
      totalWonCoins += (value * m);
    }
    final totalCost = value * count;
    // حساب نسبة الماس والتارجت التي تدخل للمستلم من هدايا الحظ (افتراضياً 10% أو حسب إعدادات اللوحة)
    final luckyTargetPct = DynamicConfigService().luckyGiftTargetPercentage;
    final int recipientDiamonds = math.max(0, ((totalCost * luckyTargetPct) / 100.0).round());
    final bool isSelfSend = senderId == receiverId;
    final isBigWin = multipliers.any((m) => m >= 50);
    final maxMultiplier = multipliers.isEmpty ? 0 : multipliers.reduce((curr, next) => curr > next ? curr : next);

    final id = const Uuid().v4();
    final senderRef = _db.collection('users').doc(senderId);

    // Look up agency membership and agency outside transaction to prevent Firestore transaction query errors & ordering violations
    DocumentReference? agencyMemberRef;
    DocumentReference? agencyRef;
    String? resolvedAgencyId;
    if (!isSelfSend) {
      try {
        final memberQs = await _db
            .collection('host_agency_members')
            .where('user_id', isEqualTo: receiverId)
            .get();

        QueryDocumentSnapshot<Map<String, dynamic>>? activeDoc;
        if (memberQs.docs.isNotEmpty) {
          for (final d in memberQs.docs) {
            final st = d.data()['status']?.toString();
            if (st == 'active') {
              activeDoc = d;
              break;
            }
          }
          activeDoc ??= memberQs.docs.firstWhere(
            (d) {
              final st = d.data()['status']?.toString();
              return st != 'pending' && st != 'rejected' && st != 'left' && st != 'kicked';
            },
            orElse: () => memberQs.docs.first,
          );
        }

        if (activeDoc != null) {
          agencyMemberRef = activeDoc.reference;
          resolvedAgencyId = activeDoc.data()['agency_id']?.toString();
        }

        if (agencyMemberRef == null || resolvedAgencyId == null || resolvedAgencyId.isEmpty) {
          final uSnap = await _db.collection('users').doc(receiverId).get();
          final aid = uSnap.data()?['agency_id']?.toString();
          if (aid != null && aid.isNotEmpty) {
            resolvedAgencyId = aid;
            final mDocDirect = await _db.collection('host_agency_members').doc('${aid}_$receiverId').get();
            if (mDocDirect.exists) {
              agencyMemberRef = mDocDirect.reference;
            } else {
              final mByAid = await _db
                  .collection('host_agency_members')
                  .where('agency_id', isEqualTo: aid)
                  .where('user_id', isEqualTo: receiverId)
                  .limit(1)
                  .get();
              if (mByAid.docs.isNotEmpty) {
                agencyMemberRef = mByAid.docs.first.reference;
              } else {
                agencyMemberRef = _db.collection('host_agency_members').doc('${aid}_$receiverId');
              }
            }
          }
        }

        if (resolvedAgencyId != null && resolvedAgencyId.isNotEmpty) {
          agencyRef = _db.collection('host_agencies').doc(resolvedAgencyId);
        }
      } catch (_) {}
    }

    try {
      await _db.runTransaction((txn) async {
        final senderSnap = await txn.get(senderRef);
        if (!senderSnap.exists) throw Exception('sender missing');
        final senderCoins = _asInt(senderSnap.data()?['coins']);
        if (senderCoins < totalCost) throw Exception('insufficient coins');

        final receiverRef = _db.collection('users').doc(receiverId);
        final recvSnap = await txn.get(receiverRef);

        final roomRef = _db.collection('rooms').doc(roomId);
        final roomSnap = await txn.get(roomRef);

        final walletRef = _db.collection('user_wallets').doc(receiverId);
        final wSnap = await txn.get(walletRef);

        DocumentSnapshot? agencyMemberSnap;
        if (!isSelfSend && agencyMemberRef != null) {
          agencyMemberSnap = await txn.get(agencyMemberRef);
        }

        DocumentSnapshot? agencySnap;
        if (!isSelfSend && agencyRef != null) {
          agencySnap = await txn.get(agencyRef);
        }

        // تسجيل العملية في sent_lucky_gifts
        txn.set(_db.collection('sent_lucky_gifts').doc(id), {
          'id': id,
          'gift_id': giftId,
          'gift_name': giftName,
          'gift_name_ar': giftNameAr,
          'gift_icon_url': giftIconUrl,
          'sender_id': senderId,
          'sender_name': senderName,
          'sender_photo_url': senderPhotoUrl,
          'receiver_id': receiverId,
          'receiver_name': receiverName,
          'room_id': roomId,
          'value': value,
          'count': count,
          'combo_id': comboId ?? id,
          'combo_count': comboCount,
          'won_coins': totalWonCoins,
          'multipliers': multipliers,
          'is_big_win': isBigWin,
          'created_at': DateTime.now().toIso8601String(),
        });

        // تحضير حمولة هدية الحظ للغرفة ولجميع الحاضرين
        final luckyGiftPayload = {
          'gift_icon': giftIconUrl,
          'image_url': giftIconUrl,
          'gift_name': giftNameAr,
          'count': count,
          'won_coins': totalWonCoins,
          'multiplier': maxMultiplier,
          'receiver_name': receiverName,
          'roomId': roomId,
          'sender': {
            'id': senderId,
            'nickname': senderName,
            'avatar': senderPhotoUrl,
          },
          'receiver': {
            'id': receiverId,
            'nickname': receiverName,
          },
          'gift': {
            'id': giftId,
            'giftName': giftName,
            'giftNameAr': giftNameAr,
            'coinPrice': value,
            'giftIconUrl': giftIconUrl,
            'giftCoverUrl': giftCoverUrl,
            'giftBgUrl': giftBgUrl,
            'svgaAnimUrl': svgaAnimUrl,
          },
          'combo': {
            'comboId': comboId ?? id,
            'comboCount': comboCount,
            'times': count,
          },
          'results': {
            'multipliers': multipliers,
            'cards': List.generate(multipliers.length, (i) => {
              'index': i,
              'multiplier': multipliers[i],
              'wonCoins': value * multipliers[i],
              'giftName': giftNameAr,
              'giftIcon': giftIconUrl,
            }),
            'totalWonCoins': totalWonCoins,
            'maxMultiplier': maxMultiplier,
            'isBigWin': isBigWin,
          },
        };

        // بث الحدث اللحظي للغرفة عبر room_messages في Supabase و Firestore
        final luckyMsgId = const Uuid().v4();
        unawaited(SupabaseDataService().sendMessage(MessageModel(
          msgId: luckyMsgId,
          roomId: roomId,
          senderUid: senderId,
          senderName: senderName,
          senderPhotoUrl: senderPhotoUrl,
          type: 'lucky_gift',
          text: '$senderName 🍀 $giftNameAr x$count (فاز بـ $totalWonCoins 🪙)',
          imageUrl: giftIconUrl,
          giftPayload: luckyGiftPayload,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        )).catchError((_) => false));

        unawaited(SupabaseDataService().recordSentGift(
          roomId: roomId,
          giftId: giftId,
          giftName: giftNameAr,
          animationAsset: svgaAnimUrl ?? giftIconUrl,
          senderId: senderId,
          senderName: senderName,
          senderPhotoUrl: senderPhotoUrl,
          receiverId: receiverId,
          receiverName: receiverName,
          value: value,
          count: count,
        ).catchError((_) => false));

        txn.set(_db.collection('room_messages').doc(luckyMsgId), {
          'msg_id': const Uuid().v4(),
          'room_id': roomId,
          'sender_uid': senderId,
          'sender_name': senderName,
          'sender_photo_url': senderPhotoUrl,
          'type': 'lucky_gift',
          'image_url': giftIconUrl,
          'text': '$senderName 🍀 $giftNameAr x$count (فاز بـ $totalWonCoins 🪙)',
          'gift_payload': luckyGiftPayload,
          'created_at': DateTime.now().toIso8601String(),
        });

        // خصم التكلفة وإيداع أرباح الحظ في محفظة المرسل ذرّياً
        final sd = senderSnap.data() ?? {};
        final sentTotal = _asInt(sd['total_gifts_sent']);
        txn.update(senderRef, {
          'coins': senderCoins - totalCost + totalWonCoins,
          'total_gifts_sent': sentTotal + totalCost,
        });

        // حساب نسبة الماس والتارجت التي تدخل للمستلم من هدايا الحظ (افتراضياً 10% أو حسب إعدادات اللوحة)
        final luckyTargetPct = DynamicConfigService().luckyGiftTargetPercentage;
        final int recipientDiamonds = math.max(0, ((totalCost * luckyTargetPct) / 100.0).round());

        if (recvSnap.exists) {
          final rd = recvSnap.data() ?? {};
          txn.update(receiverRef, {
            'diamonds': _asInt(rd['diamonds']) + recipientDiamonds,
            'total_gifts_received': _asInt(rd['total_gifts_received']) + totalCost,
          });
        }

        if (roomSnap.exists) {
          final rm = roomSnap.data() ?? {};
          final currentRocket = _asInt(rm['rocket_energy']);
          final rocketTarget = _asInt(rm['rocket_target']) > 0 ? _asInt(rm['rocket_target']) : 5000;
          final newRocket = currentRocket + totalCost;
          final isBurst = newRocket >= rocketTarget;
          txn.update(roomRef, {
            'total_gifts': _asInt(rm['total_gifts']) + totalCost,
            'hot_value': _asInt(rm['hot_value']) + totalCost,
            'rocket_energy': isBurst ? 0 : newRocket,
            if (isBurst) 'rocket_burst_active': true,
            if (isBurst) 'rocket_burst_id': const Uuid().v4(),
            if (isBurst) 'rocket_burst_time': DateTime.now().toIso8601String(),
          });
        }

        if (wSnap.exists) {
          final wd = wSnap.data() ?? {};
          txn.update(walletRef, {'diamond_balance': _asInt(wd['diamond_balance']) + recipientDiamonds});
        } else {
          txn.set(walletRef, {'user_id': receiverId, 'diamond_balance': recipientDiamonds, 'gold_balance': 0});
        }

        // Only update agency earnings and host agency target if NOT self-sending
        if (!isSelfSend) {
          if (agencyMemberSnap != null && agencyMemberSnap.exists) {
            final md = agencyMemberSnap.data() as Map<String, dynamic>? ?? {};
            txn.update(agencyMemberSnap.reference, {
              'diamonds': _asInt(md['diamonds']) + recipientDiamonds,
              'diamonds_balance': _asInt(md['diamonds_balance']) + recipientDiamonds,
              'diamonds_available': _asInt(md['diamonds_available']) + recipientDiamonds,
              'diamonds_earned_monthly': _asInt(md['diamonds_earned_monthly']) + recipientDiamonds,
              'diamonds_earned_cumulative': _asInt(md['diamonds_earned_cumulative']) + recipientDiamonds,
            });
          } else if (agencyMemberRef != null && (agencyMemberSnap == null || !agencyMemberSnap.exists) && resolvedAgencyId != null) {
            txn.set(agencyMemberRef, {
              'id': agencyMemberRef.id,
              'agency_id': resolvedAgencyId,
              'user_id': receiverId,
              'status': 'active',
              'role': 'host',
              'diamonds': recipientDiamonds,
              'diamonds_balance': recipientDiamonds,
              'diamonds_available': recipientDiamonds,
              'diamonds_earned_monthly': recipientDiamonds,
              'diamonds_earned_cumulative': recipientDiamonds,
              'joined_at': DateTime.now().toUtc().toIso8601String(),
            }, SetOptions(merge: true));
          }

          if (agencySnap != null && agencySnap.exists) {
            final ad = agencySnap.data() as Map<String, dynamic>? ?? {};
            txn.update(agencySnap.reference, {
              'total_diamonds_monthly': _asInt(ad['total_diamonds_monthly']) + recipientDiamonds,
              'total_diamonds_cumulative': _asInt(ad['total_diamonds_cumulative']) + recipientDiamonds,
            });
          }
        }
      });

      // Host target evaluation and ledger update (only for non-self send)
      if (!isSelfSend && resolvedAgencyId != null && resolvedAgencyId.isNotEmpty) {
        unawaited(Future(() async {
          try {
            await _db.collection('agency_diamond_ledger').add({
              'agency_id': resolvedAgencyId,
              'user_id': receiverId,
              'sender_id': senderId,
              'sender_name': senderName,
              'gift_id': giftId,
              'gift_name': giftNameAr,
              'amount': recipientDiamonds,
              'direction': 1,
              'txn_type': 'gift',
              'created_at': DateTime.now().toUtc().toIso8601String(),
            });
          } catch (e) {
            debugPrint('agency_diamond_ledger error: $e');
          }

          try {
            await AgencyTargetEvaluator.evaluateHostTargets(receiverId);
          } catch (_) {}
        }));
      }

      // بث الفوز بمضاعفات الحظ عبر جميع الغرف في التطبيق (Global Lucky Broadcast)
      if (maxMultiplier >= 5 || isBigWin || totalWonCoins > 0) {
        unawaited(Future(() async {
          final now = DateTime.now();
          final bId = const Uuid().v4();
          try {
            await _db.collection('broadcasts').doc(bId).set({
              'id': bId,
              'sender_uid': senderId,
              'sender_name': senderName,
              'sender_photo_url': senderPhotoUrl,
              'receiver_name': receiverName,
              'room_id': roomId,
              'room_name': 'غرفة صوتية',
              'content': maxMultiplier > 1
                  ? '🎉 فاز بمضاعف ${maxMultiplier}X في هدية الحظ $giftNameAr (كسب $totalWonCoins 🪙)!'
                  : 'أرسل هدية الحظ $giftNameAr x$count',
              'gift_name': giftNameAr,
              'gift_icon': giftIconUrl,
              'multiplier': maxMultiplier,
              'count': count,
              'won_coins': totalWonCoins,
              'coins': totalWonCoins,
              'is_lucky': true,
              'type': 'lucky_gift',
              'timestamp': now.millisecondsSinceEpoch,
              'created_at': now.toUtc().toIso8601String(),
            });
          } catch (err) {
            debugPrint('broadcasts error: $err');
          }

          if (isBigWin || maxMultiplier >= 50) {
            try {
              await _db.collection('global_announcements').add({
                'type': 'lucky_big_win',
                'sender_name': senderName,
                'gift_name': giftNameAr,
                'room_id': roomId,
                'multiplier': maxMultiplier,
                'total_won': totalWonCoins,
                'timestamp': now.millisecondsSinceEpoch,
                'created_at': now.toUtc().toIso8601String(),
              });
            } catch (err) {
              debugPrint('global_announcements error: $err');
            }
          }
        }));
      }

      // Deduct coins & add diamonds in Supabase
      unawaited(Future(() async {
        try {
          final newCoins = (senderCoins - totalCost + totalWonCoins).clamp(0, 999999999999);
          await SupabaseDataService().updateUser(senderId, {
            'coins': newCoins,
            'total_gifts_sent': sentTotal + totalCost,
          });
          final rUser = await SupabaseAuthService().getUserFromSupabase(receiverId);
          if (rUser != null) {
            await SupabaseDataService().updateUser(receiverId, {
              'diamonds': rUser.diamonds + recipientDiamonds,
              'total_gifts_received': rUser.totalGiftsReceived + totalCost,
            });
          }
        } catch (_) {}
      }));

      return {
        'success': true,
        'wonCoins': totalWonCoins,
        'multipliers': multipliers,
        'maxMultiplier': maxMultiplier,
        'isBigWin': isBigWin,
      };
    } catch (e) {
      debugPrint('sendLuckyGift Firestore error, attempting Supabase fallback: $e');
      try {
        final sUser = await SupabaseAuthService().getUserFromSupabase(senderId);
        final currentCoins = sUser?.coins ?? 0;
        if (currentCoins < totalCost) {
          return null;
        }

        final luckyMsgId = const Uuid().v4();
        final luckyGiftPayload = {
          'gift_icon': giftIconUrl,
          'image_url': giftIconUrl,
          'gift_name': giftNameAr,
          'count': count,
          'won_coins': totalWonCoins,
          'multiplier': maxMultiplier,
          'receiver_name': receiverName,
          'roomId': roomId,
          'sender': {
            'id': senderId,
            'nickname': senderName,
            'avatar': senderPhotoUrl,
          },
          'receiver': {
            'id': receiverId,
            'nickname': receiverName,
          },
          'gift': {
            'id': giftId,
            'giftName': giftName,
            'giftNameAr': giftNameAr,
            'coinPrice': value,
            'giftIconUrl': giftIconUrl,
            'giftCoverUrl': giftCoverUrl,
            'giftBgUrl': giftBgUrl,
            'svgaAnimUrl': svgaAnimUrl,
          },
          'combo': {
            'comboId': comboId ?? id,
            'comboCount': comboCount,
            'times': count,
          },
          'results': {
            'multipliers': multipliers,
            'cards': List.generate(multipliers.length, (i) => {
              'index': i,
              'multiplier': multipliers[i],
              'wonCoins': value * multipliers[i],
              'giftName': giftNameAr,
              'giftIcon': giftIconUrl,
            }),
            'totalWonCoins': totalWonCoins,
            'maxMultiplier': maxMultiplier,
            'isBigWin': isBigWin,
          },
        };

        await SupabaseDataService().sendMessage(MessageModel(
          msgId: luckyMsgId,
          roomId: roomId,
          senderUid: senderId,
          senderName: senderName,
          senderPhotoUrl: senderPhotoUrl,
          type: 'lucky_gift',
          text: '$senderName 🍀 $giftNameAr x$count (فاز بـ $totalWonCoins 🪙)',
          imageUrl: giftIconUrl,
          giftPayload: luckyGiftPayload,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ));

        await SupabaseDataService().recordSentGift(
          roomId: roomId,
          giftId: giftId,
          giftName: giftNameAr,
          animationAsset: svgaAnimUrl ?? giftIconUrl,
          senderId: senderId,
          senderName: senderName,
          senderPhotoUrl: senderPhotoUrl,
          receiverId: receiverId,
          receiverName: receiverName,
          value: value,
          count: count,
        );

        try {
          await _db.collection('room_messages').doc(luckyMsgId).set({
            'msg_id': luckyMsgId,
            'room_id': roomId,
            'sender_uid': senderId,
            'sender_name': senderName,
            'sender_photo_url': senderPhotoUrl,
            'type': 'lucky_gift',
            'image_url': giftIconUrl,
            'text': '$senderName 🍀 $giftNameAr x$count (فاز بـ $totalWonCoins 🪙)',
            'gift_payload': luckyGiftPayload,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        } catch (_) {}

        if (maxMultiplier >= 5 || isBigWin || totalWonCoins > 0) {
          unawaited(Future(() async {
            try {
              final now = DateTime.now();
              final bId = const Uuid().v4();
              await _db.collection('broadcasts').doc(bId).set({
                'id': bId,
                'sender_uid': senderId,
                'sender_name': senderName,
                'sender_photo_url': senderPhotoUrl,
                'receiver_name': receiverName,
                'room_id': roomId,
                'room_name': 'غرفة صوتية',
                'content': maxMultiplier > 1
                    ? '🎉 فاز بمضاعف ${maxMultiplier}X في هدية الحظ $giftNameAr (كسب $totalWonCoins 🪙)!'
                    : 'أرسل هدية الحظ $giftNameAr x$count',
                'gift_name': giftNameAr,
                'gift_icon': giftIconUrl,
                'multiplier': maxMultiplier,
                'count': count,
                'won_coins': totalWonCoins,
                'coins': totalWonCoins,
                'is_lucky': true,
                'type': 'lucky_gift',
                'timestamp': now.millisecondsSinceEpoch,
                'created_at': now.toUtc().toIso8601String(),
              });
            } catch (_) {}
          }));
        }

        final newCoins = (currentCoins - totalCost + totalWonCoins).clamp(0, 999999999999);
        await SupabaseDataService().updateUser(senderId, {
          'coins': newCoins,
          'total_gifts_sent': (sUser?.totalGiftsSent ?? 0) + totalCost,
        });

        final fallbackLuckyPct = DynamicConfigService().luckyGiftTargetPercentage;
        final int fallbackRecipientDiamonds = math.max(0, ((totalCost * fallbackLuckyPct) / 100.0).round());

        final rUser = await SupabaseAuthService().getUserFromSupabase(receiverId);
        if (rUser != null) {
          await SupabaseDataService().updateUser(receiverId, {
            'diamonds': rUser.diamonds + fallbackRecipientDiamonds,
            'total_gifts_received': rUser.totalGiftsReceived + totalCost,
          });
        }

        return {
          'success': true,
          'wonCoins': totalWonCoins,
          'multipliers': multipliers,
          'maxMultiplier': maxMultiplier,
          'isBigWin': isBigWin,
        };
      } catch (fallbackErr) {
        debugPrint('sendLuckyGift fallback error: $fallbackErr');
        return null;
      }
    }
  }

  /// استماع للبث العام للفوز الكبير عبر كافة الغرف
  Stream<Map<String, dynamic>> globalBigWinStream() {
    return _db
        .collection('global_announcements')
        .where('type', isEqualTo: 'lucky_big_win')
        .limit(5)
        .snapshots()
        .where((snap) => snap.docs.isNotEmpty)
        .map((snap) => snap.docs.first.data());
  }

  Stream<List<gm.SentGiftModel>> sentGiftsStream(String roomId) async* {
    while (true) {
      try {
        final gifts = await SupabaseDataService().getSentGifts(roomId);
        if (gifts.isNotEmpty) {
          yield gifts;
        } else {
          try {
            final snap = await _db
                .collection('sent_gifts')
                .where('room_id', isEqualTo: roomId)
                .get();
            final list = snap.docs.map((e) => gm.SentGiftModel.fromMap(_data(e))).toList();
            yield list;
          } catch (_) {
            yield [];
          }
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 1500));
    }
  }

  Stream<List<gm.SentGiftModel>> userReceivedGiftsStream(String uid) {
    return _db
        .collection('sent_gifts')
        .where('receiver_id', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs.map((e) => gm.SentGiftModel.fromMap(_data(e))).toList());
  }

  Future<List<gm.SentGiftModel>> getReceivedGifts(String uid) async {
    try {
      final supaGifts = await SupabaseDataService().getReceivedGifts(uid, limit: 100);
      if (supaGifts.isNotEmpty) {
        return supaGifts;
      }
    } catch (_) {}
    try {
      final snap = await _db
          .collection('sent_gifts')
          .where('receiver_id', isEqualTo: uid)
          .limit(50)
          .get();
      final list = snap.docs.map((e) => gm.SentGiftModel.fromMap(_data(e))).toList();
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list;
    } catch (e) {
      debugPrint('getReceivedGifts error: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════
  // USERS
  // ═══════════════════════════════════════════════════════

  Future<void> saveUser(UserModel user) async {
    // 1. Save directly to Supabase public.users
    try {
      await SupabaseAuthService().saveUserToSupabase(user);
    } catch (e) {
      debugPrint('saveUser Supabase error: $e');
    }

    // 2. Try Firestore silently without crashing if permission-denied
    try {
      final data = user.toMap();
      data['uid'] = user.uid;
      await _db.collection('users').doc(user.uid).set(_stripNulls(data), SetOptions(merge: true));
    } catch (e) {
      debugPrint('saveUser Firestore error (ignored): $e');
    }
  }

  Future<UserModel?> getUser(String uid) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return null;

    // 1. Try Supabase first (uid, id, custom_id)
    try {
      final supabaseUser = await SupabaseAuthService().getUserFromSupabase(cleanUid);
      if (supabaseUser != null) {
        return supabaseUser;
      }
    } catch (e) {
      debugPrint('getUser Supabase error: $e');
    }

    // 2. Fall back to Firestore with doc ID
    try {
      final doc = await _db.collection('users').doc(cleanUid).get();
      if (doc.exists) {
        final m = doc.data() ?? {};
        return UserModel.fromMap({...m, 'uid': cleanUid});
      }
    } on FirebaseException catch (e) {
      debugPrint('getUser FirebaseException ($cleanUid): $e');
      if (e.code == 'resource-exhausted' || e.code == 'unavailable') {
        try {
          final cachedDoc = await _db.collection('users').doc(cleanUid).get(const GetOptions(source: Source.cache));
          if (cachedDoc.exists) {
            return UserModel.fromMap({...cachedDoc.data() ?? {}, 'uid': cleanUid});
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('getUser doc error ($cleanUid): $e');
    }

    // 3. Fall back to Firestore query by custom_id
    try {
      final snap = await _db.collection('users').where('custom_id', isEqualTo: cleanUid).limit(1).get();
      if (snap.docs.isNotEmpty) {
        final doc = snap.docs.first;
        return UserModel.fromMap({...doc.data(), 'uid': doc.id});
      }
    } catch (_) {}

    // 4. Fall back to Firestore query by uid field
    try {
      final snap = await _db.collection('users').where('uid', isEqualTo: cleanUid).limit(1).get();
      if (snap.docs.isNotEmpty) {
        final doc = snap.docs.first;
        return UserModel.fromMap({...doc.data(), 'uid': doc.id});
      }
    } catch (_) {}

    // 5. Final fallback to SupabaseDataService search
    try {
      final results = await SupabaseDataService().searchUsers(cleanUid);
      if (results.isNotEmpty) {
        return UserModel.fromMap(results.first);
      }
    } catch (_) {}

    return null;
  }

  Stream<UserModel?> userStream(String uid) {
    final controller = StreamController<UserModel?>.broadcast();
    Timer? pollTimer;
    UserModel? latestUser;

    void fetchSupabase() async {
      try {
        var u = await SupabaseAuthService().getUserFromSupabase(uid);
        if (u != null && !controller.isClosed) {
          // Preserve followed_rooms if Supabase returned empty
          List<String> followed = u.followedRooms;
          if (followed.isEmpty) {
            try {
              final prefs = await SharedPreferences.getInstance();
              followed = prefs.getStringList('followed_rooms_$uid') ?? [];
            } catch (_) {}
            if (followed.isEmpty && latestUser != null) {
              followed = latestUser!.followedRooms;
            }
            if (followed.isNotEmpty) {
              u = u.copyWith(followedRooms: followed);
            }
          }
          if (latestUser == null) {
            latestUser = u;
            controller.add(u);
            try {
              _db.collection('users').doc(uid).set({
                'coins': u.coins,
                'diamonds': u.diamonds,
                'custom_id': u.customId,
                'owned_items': u.ownedItems,
              }, SetOptions(merge: true));
            } catch (_) {}
          } else {
            // Keep real-time coins & diamonds from Firestore transactions to prevent balance bounce
            final mergedCoins = (latestUser!.coins >= 0) ? latestUser!.coins : u.coins;
            final mergedDiamonds = (latestUser!.diamonds >= 0) ? latestUser!.diamonds : u.diamonds;
            final merged = u.copyWith(coins: mergedCoins, diamonds: mergedDiamonds);
            latestUser = merged;
            controller.add(merged);
            try {
              _db.collection('users').doc(uid).set({
                'custom_id': u.customId,
                'owned_items': u.ownedItems,
              }, SetOptions(merge: true));
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    fetchSupabase();
    pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => fetchSupabase());

    StreamSubscription? firestoreSub;
    try {
      firestoreSub = _db.collection('users').doc(uid).snapshots().listen((snap) {
        if (!controller.isClosed && snap.exists) {
          final m = snap.data() ?? {};
          var fireUser = UserModel.fromMap({...m, 'uid': uid});
          final fRooms = fireUser.followedRooms.isNotEmpty
              ? fireUser.followedRooms
              : (latestUser?.followedRooms ?? []);
          final hasCoins = m.containsKey('coins');
          final resolvedCoins = hasCoins ? (m['coins'] as num).toInt() : (latestUser?.coins ?? fireUser.coins);
          final hasDiamonds = m.containsKey('diamonds');
          final resolvedDiamonds = hasDiamonds ? (m['diamonds'] as num).toInt() : (latestUser?.diamonds ?? fireUser.diamonds);
          if (latestUser != null) {
            fireUser = fireUser.copyWith(
              coins: resolvedCoins,
              diamonds: resolvedDiamonds,
              photoUrl: fireUser.photoUrl.isNotEmpty ? fireUser.photoUrl : latestUser!.photoUrl,
              name: fireUser.name.isNotEmpty ? fireUser.name : latestUser!.name,
              customId: fireUser.customId.isNotEmpty ? fireUser.customId : latestUser!.customId,
              email: fireUser.email.isNotEmpty ? fireUser.email : latestUser!.email,
              gender: fireUser.gender.isNotEmpty ? fireUser.gender : latestUser!.gender,
              ownedItems: fireUser.ownedItems.isNotEmpty ? fireUser.ownedItems : latestUser!.ownedItems,
              followedRooms: fRooms,
              isRechargeAgent: fireUser.isRechargeAgent || latestUser!.isRechargeAgent,
              rechargeAgencyName: fireUser.rechargeAgencyName?.isNotEmpty == true
                  ? fireUser.rechargeAgencyName
                  : latestUser!.rechargeAgencyName,
              rechargeAgencyLogo: fireUser.rechargeAgencyLogo?.isNotEmpty == true
                  ? fireUser.rechargeAgencyLogo
                  : latestUser!.rechargeAgencyLogo,
              whatsappNumber: fireUser.whatsappNumber?.isNotEmpty == true
                  ? fireUser.whatsappNumber
                  : latestUser!.whatsappNumber,
            );
          } else if (fRooms.isNotEmpty) {
            fireUser = fireUser.copyWith(followedRooms: fRooms);
          }
          latestUser = fireUser;
          controller.add(fireUser);
        }
      }, onError: (_) {});
    } catch (_) {}

    controller.onCancel = () {
      pollTimer?.cancel();
      firestoreSub?.cancel();
    };

    return controller.stream;
  }

  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    // 1. Sync update to Supabase via SupabaseAuthService & SupabaseDataService
    try {
      await SupabaseAuthService().syncUserToSupabase(
        uid: uid,
        customId: data['custom_id']?.toString() ?? data['customId']?.toString(),
        name: data['name']?.toString(),
        email: data['email']?.toString(),
        photoUrl: data['photo_url']?.toString() ?? data['photoUrl']?.toString(),
        phone: data['phone']?.toString(),
        gender: data['gender']?.toString(),
        coins: (data['coins'] as num?)?.toInt(),
        country: data['country']?.toString(),
      );

      final supaUpdates = <String, dynamic>{};
      data.forEach((k, v) {
        if (v != null) {
          if (k == 'hostedRoomId' || k == 'hosted_room_id') {
            supaUpdates['hosted_room_id'] = v;
          } else if (k == 'photoUrl') {
            supaUpdates['photo_url'] = v;
          } else if (k == 'customId') {
            supaUpdates['custom_id'] = v;
          } else if (k == 'activeFrame') {
            supaUpdates['active_frame'] = v;
          } else if (k == 'activeCar') {
            supaUpdates['active_car'] = v;
          } else if (k == 'activeBubble') {
            supaUpdates['active_bubble'] = v;
          } else if (k == 'activeHeadwear') {
            supaUpdates['active_headwear'] = v;
          } else if (k == 'activeEntrance') {
            supaUpdates['active_entrance'] = v;
          } else if (k == 'activeCover') {
            supaUpdates['active_cover'] = v;
          } else if (k == 'activeNecklace') {
            supaUpdates['active_necklace'] = v;
          } else if (k == 'activeMicWave') {
            supaUpdates['active_mic_wave'] = v;
          } else {
            supaUpdates[k] = v;
          }
        }
      });
      if (supaUpdates.isNotEmpty) {
        await SupabaseDataService().updateUser(uid, supaUpdates);
      }
    } catch (e) {
      debugPrint('updateUser Supabase error: $e');
    }

    // 2. Try Firestore silently without crashing if permission-denied
    try {
      await _db.collection('users').doc(uid).update(_stripNulls(data));
    } catch (e) {
      debugPrint('updateUser Firestore error (ignored): $e');
    }
  }

  Future<List<UserModel>> getAllUsers() async {
    try {
      final supaUsers = await SupabaseDataService().getAllUsers();
      if (supaUsers.isNotEmpty) return supaUsers;
    } catch (e) {
      debugPrint('getAllUsers Supabase error: $e');
    }

    try {
      final snap = await _db.collection('users').get();
      return snap.docs.map((e) => UserModel.fromMap(_data(e))).toList();
    } catch (_) {
      return [];
    }
  }


  Stream<List<UserModel>> allUsersStream() {
    return _db
        .collection('users')
        .snapshots()
        .map((snap) => snap.docs.map((e) => UserModel.fromMap(_data(e))).toList());
  }

  /// ترتيب المستخدمين حسب حقل عدّاد (total_gifts_sent / total_gifts_received).
  Future<List<Map<String, dynamic>>> getUserRanking({
    required String orderByField,
    int limit = 50,
  }) async {
    try {
      final sbRank = await SupabaseDataService().getUserRanking(
        orderByField: orderByField,
        limit: limit,
      );
      if (sbRank.isNotEmpty) {
        return sbRank;
      }
    } catch (_) {}

    try {
      final snap = await _db
          .collection('users')
          .orderBy(orderByField, descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((e) {
        final d = e.data();
        return <String, dynamic>{
          'uid': e.id,
          'id': (d['customId'] ?? d['id'] ?? '').toString(),
          'name': (d['name'] ?? '').toString(),
          'photo_url': (d['photo_url'] ?? d['photoUrl'] ?? '').toString(),
          'level': d['level'] ?? 1,
          'total_gifts_sent': _asInt(d['total_gifts_sent']),
          'total_gifts_received': _asInt(d['total_gifts_received']),
        };
      }).toList();
    } catch (e) {
      debugPrint('getUserRanking($orderByField) failed: $e');
      return const [];
    }
  }

  /// ترتيب الغرف حسب إجمالي الهدايا.
  Future<List<Map<String, dynamic>>> getRoomRanking({int limit = 50}) async {
    try {
      final sbRooms = await SupabaseDataService().getRoomRanking(limit: limit);
      if (sbRooms.isNotEmpty) {
        return sbRooms.map((d) => <String, dynamic>{
          'uid': d['room_id'] ?? '',
          'name': d['name'] ?? '',
          'hostName': d['host_name'] ?? '',
          'photo_url': d['room_photo_url'] ?? '',
          'points': d['total_gifts'] ?? 0,
        }).toList();
      }
    } catch (_) {}

    try {
      final snap = await _db
          .collection('rooms')
          .orderBy('total_gifts', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((e) {
        final d = e.data();
        return <String, dynamic>{
          'uid': e.id,
          'name': (d['name'] ?? '').toString(),
          'hostName': (d['host_name'] ?? '').toString(),
          'photo_url': (d['cover_image'] ?? d['room_photo_url'] ?? '').toString(),
          'points': _asInt(d['total_gifts']),
        };
      }).toList();
    } catch (e) {
      debugPrint('getRoomRanking failed: $e');
      return const [];
    }
  }

  Future<void> saveAppConfig(String key, dynamic value) async {
    await _db.collection('app_config').doc(key).set({'key': key, 'value': value});
  }

  Future<dynamic> getAppConfig(String key) async {
    final doc = await _db.collection('app_config').doc(key).get();
    return doc.data()?['value'];
  }

  Stream<Map<String, dynamic>> appConfigStream() {
    return _db.collection('app_config').snapshots().map((snap) {
      return {for (final e in snap.docs) e.id: e.data()['value']};
    });
  }

  // ═══════════════════════════════════════════════════════
  // GIFT CATALOG + CATEGORIES + BANNERS
  // ═══════════════════════════════════════════════════════

  Stream<List<gm.GiftModel>> giftsStream() {
    final controller = StreamController<List<gm.GiftModel>>.broadcast();

    void fetch() async {
      try {
        final list = await SupabaseDataService().getGifts();
        if (!controller.isClosed) {
          controller.add(list);
        }
      } catch (_) {}
    }

    fetch();
    final timer = Timer.periodic(const Duration(seconds: 3), (_) => fetch());

    controller.onCancel = () {
      timer.cancel();
    };

    return controller.stream;
  }

  Future<Map<String, gm.GiftModel>> getGiftsCatalog() async {
    final Map<String, gm.GiftModel> map = {};
    try {
      final sbGifts = await SupabaseDataService().getGifts();
      for (final g in sbGifts) {
        map[g.id] = g;
      }
    } catch (e) {
      debugPrint('getGiftsCatalog supabase error: $e');
    }
    return map;
  }

  Future<List<gm.GiftModel>> getCpGiftsFromCatalog() async {
    final catalog = await getGiftsCatalog();
    final list = catalog.values.where((g) => g.isCpGift).toList();
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  Stream<List<GiftCategory>> giftCategoriesStream() {
    final controller = StreamController<List<GiftCategory>>.broadcast();

    void fetch() async {
      try {
        final list = await SupabaseDataService().getGiftCategories();
        if (!controller.isClosed) {
          controller.add(list);
        }
      } catch (_) {}
    }

    fetch();
    final timer = Timer.periodic(const Duration(seconds: 3), (_) => fetch());

    controller.onCancel = () {
      timer.cancel();
    };

    return controller.stream;
  }

  Future<List<GiftCategory>> getGiftCategories() async {
    try {
      return await SupabaseDataService().getGiftCategories();
    } catch (e) {
      debugPrint('getGiftCategories supabase error: $e');
      return [];
    }
  }

  Future<void> saveGiftCategory(GiftCategory category) async {
    await SupabaseDataService().saveGiftCategory(category);
    try {
      await _db.collection('gift_categories').doc(category.id).set(category.toMap());
    } catch (_) {}
  }

  Future<void> deleteGiftCategory(String id) async {
    await SupabaseDataService().deleteGiftCategory(id);
    try {
      await _db.collection('gift_categories').doc(id).delete();
    } catch (_) {}
  }

  Future<void> saveGift(gm.GiftModel gift) async {
    await SupabaseDataService().saveGift(gift);
    try {
      await _db.collection('gifts').doc(gift.id).set(gift.toMap());
    } catch (_) {}
  }

  Future<void> deleteGift(String id) async {
    await SupabaseDataService().deleteGift(id);
    try {
      await _db.collection('gifts').doc(id).delete();
    } catch (_) {}
  }

  Stream<List<GiftBannerConfig>> giftBannerConfigsStream() {
    final controller = StreamController<List<GiftBannerConfig>>.broadcast();
    List<GiftBannerConfig> sbConfigs = [];
    List<GiftBannerConfig> fsConfigs = [];

    void emitMerged() {
      if (controller.isClosed) return;
      final map = <String, GiftBannerConfig>{};
      for (final c in sbConfigs) {
        map[c.id] = c;
      }
      for (final c in fsConfigs) {
        map.putIfAbsent(c.id, () => c);
      }
      controller.add(map.values.toList());
    }

    SupabaseDataService().getGiftBannerConfigs().then((list) {
      sbConfigs = list;
      emitMerged();
    }).catchError((_) {});

    final timer = Timer.periodic(const Duration(seconds: 45), (_) {
      SupabaseDataService().getGiftBannerConfigs().then((list) {
        sbConfigs = list;
        emitMerged();
      }).catchError((_) {});
    });

    final sub = _db.collection('gift_banner_configs').snapshots().listen((snap) {
      fsConfigs = snap.docs.map((e) => GiftBannerConfig.fromMap(_data(e))).toList();
      emitMerged();
    }, onError: (_) {});

    controller.onCancel = () {
      timer.cancel();
      sub.cancel();
    };

    return controller.stream;
  }

  Future<List<GiftBannerConfig>> getGiftBannerConfigs() async {
    final Map<String, GiftBannerConfig> map = {};
    try {
      final sbConfigs = await SupabaseDataService().getGiftBannerConfigs();
      for (final c in sbConfigs) {
        map[c.id] = c;
      }
    } catch (e) {
      debugPrint('getGiftBannerConfigs supabase error: $e');
    }
    try {
      final snap = await _db.collection('gift_banner_configs').get();
      for (final e in snap.docs) {
        final c = GiftBannerConfig.fromMap(_data(e));
        map.putIfAbsent(c.id, () => c);
      }
    } catch (e) {
      debugPrint('getGiftBannerConfigs firestore error: $e');
    }
    return map.values.toList();
  }

  Future<void> saveGiftBannerConfig(GiftBannerConfig config) async {
    await _db.collection('gift_banner_configs').doc(config.id).set(config.toMap());
  }

  Future<void> deleteGiftBannerConfig(String id) async {
    await _db.collection('gift_banner_configs').doc(id).delete();
  }

  Future<String> uploadGiftBannerSvga(String filePath, String fileName) async {
    try {
      final path = filePath.startsWith('file://') ? Uri.parse(filePath).toFilePath() : filePath;
      final url = await CloudinaryService().upload(
        File(path),
        publicId: 'admin-uploads/$fileName',
        type: CloudinaryResourceType.raw,
      );
      return url;
    } catch (e) {
      debugPrint('uploadGiftBannerSvga error: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════
  // RANKING FRAMES
  // ═══════════════════════════════════════════════════════

  Future<List<RankingFrameConfig>> getRankingFrames() async {
    final Map<String, RankingFrameConfig> map = {};
    try {
      final sbFrames = await SupabaseDataService().getRankingFrames();
      for (final f in sbFrames) {
        final k = f.id.isNotEmpty ? f.id : '${f.category}_${f.rank}';
        map[k] = f;
      }
    } catch (e) {
      debugPrint('getRankingFrames supabase error: $e');
    }
    try {
      final snap = await _db.collection('ranking_frames').get();
      for (final e in snap.docs) {
        final f = RankingFrameConfig.fromMap(_data(e));
        final k = f.id.isNotEmpty ? f.id : '${f.category}_${f.rank}';
        map.putIfAbsent(k, () => f);
      }
    } catch (e) {
      debugPrint('getRankingFrames firestore error: $e');
    }
    return map.values.toList();
  }

  Future<void> saveRankingFrame(RankingFrameConfig config) async {
    final map = config.toMap();
    final id = map['id']?.toString() ?? '${map['category']}_${map['rank']}';
    await _db.collection('ranking_frames').doc(id).set(map);
  }

  Future<void> deleteRankingFrame(String id) async {
    await _db.collection('ranking_frames').doc(id).delete();
  }

  // ═══════════════════════════════════════════════════════
  // STORE
  // ═══════════════════════════════════════════════════════

  Map<String, StoreItemModel> _storeItems = {};

  Stream<List<StoreItemModel>> storeItemsStream() {
    final controller = StreamController<List<StoreItemModel>>.broadcast();
    List<StoreItemModel> sbItems = [];
    List<StoreItemModel> fsItems = [];

    void emitMerged() {
      if (controller.isClosed) return;
      final map = <String, StoreItemModel>{};
      for (final item in sbItems) {
        map[item.itemId] = item;
      }
      for (final item in fsItems) {
        map.putIfAbsent(item.itemId, () => item);
      }
      final list = map.values.toList();
      _storeItems = {for (final item in list) item.itemId: item};
      controller.add(list);
    }

    SupabaseDataService().getStoreItems().then((list) {
      sbItems = list;
      emitMerged();
    }).catchError((_) {});

    final timer = Timer.periodic(const Duration(seconds: 5), (_) {
      SupabaseDataService().getStoreItems().then((list) {
        sbItems = list;
        emitMerged();
      }).catchError((_) {});
    });

    final sub = _db.collection('store_items').snapshots().listen((snap) {
      fsItems = snap.docs.map((e) => StoreItemModel.fromMap(_data(e))).toList();
      emitMerged();
    }, onError: (_) {});

    controller.onCancel = () {
      timer.cancel();
      sub.cancel();
    };

    return controller.stream;
  }

  Future<List<StoreItemModel>> getStoreItems() async {
    final Map<String, StoreItemModel> map = {};
    try {
      final sbItems = await SupabaseDataService().getStoreItems();
      for (final item in sbItems) {
        map[item.itemId] = item;
      }
    } catch (e) {
      debugPrint('getStoreItems supabase error: $e');
    }
    try {
      final snap = await _db.collection('store_items').get();
      for (final e in snap.docs) {
        final item = StoreItemModel.fromMap(_data(e));
        map.putIfAbsent(item.itemId, () => item);
      }
    } catch (e) {
      debugPrint('getStoreItems firestore error: $e');
    }
    final items = map.values.toList();
    _storeItems = {for (final item in items) item.itemId: item};
    return items;
  }

  StoreItemModel? getStoreItemSync(String itemId) => _storeItems[itemId];

  Stream<List<BannerConfig>> bannersStream() {
    final controller = StreamController<List<BannerConfig>>.broadcast();
    List<BannerConfig> sbBanners = [];
    List<BannerConfig> fsBanners = [];

    void emitMerged() {
      if (controller.isClosed) return;
      final map = <String, BannerConfig>{};
      for (final b in sbBanners) {
        if (b.active && b.imageUrl.isNotEmpty) map[b.id] = b;
      }
      for (final b in fsBanners) {
        if (b.active && b.imageUrl.isNotEmpty) {
          map.putIfAbsent(b.id, () => b);
        }
      }
      final list = map.values.toList();
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      controller.add(list);
    }

    SupabaseDataService().getBanners().then((list) {
      sbBanners = list;
      emitMerged();
    }).catchError((_) {});

    final timer = Timer.periodic(const Duration(seconds: 45), (_) {
      SupabaseDataService().getBanners().then((list) {
        sbBanners = list;
        emitMerged();
      }).catchError((_) {});
    });

    final sub = _db.collection('banners').snapshots().listen((snap) {
      fsBanners = snap.docs
          .map((e) => BannerConfig.fromMap(_data(e)))
          .where((b) => b.active && b.imageUrl.isNotEmpty)
          .toList();
      emitMerged();
    }, onError: (_) {});

    controller.onCancel = () {
      timer.cancel();
      sub.cancel();
    };

    return controller.stream;
  }

  Future<void> addStoreItem(StoreItemModel item) async {
    await _db.collection('store_items').doc(item.itemId).set(item.toMap());
  }

  Future<StoreItemModel?> getStoreItem(String itemId) async {
    final doc = await _db.collection('store_items').doc(itemId).get();
    if (!doc.exists) return null;
    return StoreItemModel.fromMap(_data(doc));
  }

  Stream<List<Map<String, dynamic>>> storeCategoriesStream() {
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
    List<Map<String, dynamic>> sbCats = [];
    List<Map<String, dynamic>> fsCats = [];

    void emitMerged() {
      if (controller.isClosed) return;
      final map = <String, Map<String, dynamic>>{};
      for (final c in sbCats) {
        final k = c['key']?.toString() ?? c['id']?.toString() ?? '';
        if (k.isNotEmpty) map[k] = c;
      }
      for (final c in fsCats) {
        final k = c['key']?.toString() ?? c['id']?.toString() ?? '';
        if (k.isNotEmpty) map.putIfAbsent(k, () => c);
      }
      final list = map.values.where((c) => c['is_active'] != false).toList();
      list.sort((a, b) => ((a['sort_order'] ?? 0) as num).compareTo((b['sort_order'] ?? 0) as num));
      controller.add(list);
    }

    void fetchSupabase() async {
      try {
        final list = await SupabaseDataService().getStoreCategories();
        sbCats = list.map((d) => {
          'id': d['id']?.toString() ?? '',
          'key': d['key']?.toString() ?? d['id']?.toString() ?? '',
          'name': d['name']?.toString() ?? '',
          'icon_asset': d['icon_asset']?.toString() ?? d['iconAsset']?.toString() ?? '',
          'selected_icon_asset': d['selected_icon_asset']?.toString() ?? d['selectedIconAsset']?.toString() ?? '',
          'sort_order': (d['sort_order'] ?? d['sortOrder'] ?? 0) as num,
          'is_active': d['is_active'] ?? d['isActive'] ?? true,
        }).toList();
        emitMerged();
      } catch (_) {}
    }

    fetchSupabase();
    final timer = Timer.periodic(const Duration(seconds: 5), (_) => fetchSupabase());

    final sub = _db.collection('store_categories').snapshots().listen((snap) {
      fsCats = snap.docs.map((e) {
        final d = _data(e);
        return {
          'id': d['id']?.toString() ?? e.id,
          'key': d['key']?.toString() ?? d['id']?.toString() ?? e.id,
          'name': d['name']?.toString() ?? '',
          'icon_asset': d['icon_asset']?.toString() ?? d['iconAsset']?.toString() ?? '',
          'selected_icon_asset': d['selected_icon_asset']?.toString() ?? d['selectedIconAsset']?.toString() ?? '',
          'sort_order': (d['sort_order'] ?? d['sortOrder'] ?? 0) as num,
          'is_active': d['is_active'] ?? d['isActive'] ?? true,
        };
      }).toList();
      emitMerged();
    }, onError: (_) {});

    controller.onCancel = () {
      timer.cancel();
      sub.cancel();
    };

    return controller.stream;
  }

  // ═══════════════════════════════════════════════════════
  // BACKPACK & PURCHASES
  // ═══════════════════════════════════════════════════════

  Future<bool> purchaseItem(String uid, StoreItemModel item) async {
    final userRef = _db.collection('users').doc(uid);
    final isSpecialId = item.category == 'special_id';
    final specialIdVal = (item.customId != null && item.customId!.isNotEmpty)
        ? item.customId!
        : item.name.replaceAll(RegExp(r'[^0-9]'), '');

    try {
      // 1. Get user from Supabase or Firestore to check coins
      UserModel? user = await SupabaseAuthService().getUserFromSupabase(uid);
      user ??= await SupabaseDataService().getUser(uid);

      int userCoins = user?.coins ?? 0;
      List<String> userOwned = List<String>.from(user?.ownedItems ?? []);

      // If Firestore has higher coins, fall back to max
      try {
        final snap = await userRef.get();
        if (snap.exists) {
          final d = snap.data() ?? {};
          final fc = (d['coins'] as num?)?.toInt() ?? 0;
          if (fc > userCoins) userCoins = fc;
          final fo = List<String>.from(d['owned_items'] ?? []);
          for (final o in fo) {
            if (!userOwned.contains(o)) userOwned.add(o);
          }
        }
      } catch (_) {}

      if (userCoins < item.price) {
        debugPrint('purchaseItem failed: insufficient coins ($userCoins < ${item.price})');
        return false;
      }

      final newCoins = userCoins - item.price;
      if (!userOwned.contains(item.itemId)) {
        userOwned.add(item.itemId);
      }

      // 2. Update Supabase first
      final supaUpdates = <String, dynamic>{
        'coins': newCoins,
        'owned_items': userOwned,
      };

      if (isSpecialId && specialIdVal.isNotEmpty) {
        supaUpdates['custom_id'] = specialIdVal;
        supaUpdates['hosted_room_id'] = specialIdVal;
      }

      final supaSuccess = await SupabaseDataService().updateUser(uid, supaUpdates);

      if (isSpecialId && specialIdVal.isNotEmpty) {
        await SupabaseDataService().updateUserCustomId(uid, specialIdVal);
        await SupabaseDataService().markStoreItemSold(item.itemId);
      }

      // 3. Sync to Firestore (non-fatal)
      try {
        final updateData = <String, dynamic>{
          'coins': newCoins,
          'owned_items': userOwned,
        };
        if (isSpecialId && specialIdVal.isNotEmpty) {
          updateData['custom_id'] = specialIdVal;
          updateData['customId'] = specialIdVal;
          updateData['hosted_room_id'] = specialIdVal;
        }
        await userRef.set(updateData, SetOptions(merge: true));

        if (isSpecialId) {
          await _db.collection('store_items').doc(item.itemId).set({
            'is_available': false,
            'is_sold': true,
          }, SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint('purchaseItem firestore sync non-fatal error: $e');
      }

      return supaSuccess || true;
    } catch (e) {
      debugPrint('purchaseItem error: $e');
      return false;
    }
  }

  Future<void> equipItem(String uid, String itemId, String category) async {
    final updateMap = <String, dynamic>{};
    switch (category) {
      case 'frame':
        updateMap['active_frame'] = itemId;
        break;
      case 'headwear':
        updateMap['active_headwear'] = itemId;
        break;
      case 'bubble':
        final storeItem = getStoreItemSync(itemId);
        updateMap['active_bubble'] = storeItem?.svgaAsset ?? storeItem?.iconAsset ?? '';
        break;
      case 'entrance':
        updateMap['active_entrance'] = itemId;
        break;
      case 'car':
        updateMap['active_car'] = itemId;
        break;
      case 'cover':
        updateMap['active_cover'] = itemId;
        break;
      case 'necklace':
        updateMap['active_necklace'] = itemId;
        break;
      case 'mic_wave':
        final storeItem = getStoreItemSync(itemId);
        updateMap['active_mic_wave'] = storeItem?.svgaAsset ?? storeItem?.iconAsset ?? itemId;
        break;
    }

    if (updateMap.isNotEmpty) {
      await SupabaseDataService().updateUser(uid, updateMap);
      try {
        await _db.collection('users').doc(uid).set(updateMap, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  Future<void> unequipItem(String uid, String category) async {
    final updateMap = <String, dynamic>{};
    final supaMap = <String, dynamic>{};
    switch (category) {
      case 'frame':
        updateMap['active_frame'] = FieldValue.delete();
        supaMap['active_frame'] = '';
        break;
      case 'headwear':
        updateMap['active_headwear'] = FieldValue.delete();
        supaMap['active_headwear'] = '';
        break;
      case 'bubble':
        updateMap['active_bubble'] = FieldValue.delete();
        supaMap['active_bubble'] = '';
        break;
      case 'entrance':
        updateMap['active_entrance'] = FieldValue.delete();
        supaMap['active_entrance'] = '';
        break;
      case 'car':
        updateMap['active_car'] = FieldValue.delete();
        supaMap['active_car'] = '';
        break;
      case 'cover':
        updateMap['active_cover'] = FieldValue.delete();
        supaMap['active_cover'] = '';
        break;
      case 'necklace':
        updateMap['active_necklace'] = FieldValue.delete();
        supaMap['active_necklace'] = '';
        break;
      case 'mic_wave':
        updateMap['active_mic_wave'] = FieldValue.delete();
        supaMap['active_mic_wave'] = '';
        break;
    }
    if (supaMap.isNotEmpty) {
      await SupabaseDataService().updateUser(uid, supaMap);
    }
    if (updateMap.isNotEmpty) {
      try {
        await _db.collection('users').doc(uid).update(updateMap);
      } catch (_) {}
    }
  }

  // ═══════════════════════════════════════════════════════
  // GIFTED ITEMS
  // ═══════════════════════════════════════════════════════

  Stream<List<GiftedItemModel>> userGiftedItemsStream(String uid) {
    return SupabaseDataService().userGiftedItemsStream(uid);
  }

  Future<List<GiftedItemModel>> getGiftedItems(String uid) async {
    return SupabaseDataService().getGiftedItems(uid);
  }

  Future<List<GiftedItemModel>> getGiftedItemsByCategory(String uid, String category) async {
    return SupabaseDataService().getGiftedItemsByCategory(uid, category);
  }

  Future<void> removeGiftedItem(String id) async {
    await SupabaseDataService().removeGiftedItem(id);
    try {
      await _db.collection('gifted_items').doc(id).delete();
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════
  // IMAGE MESSAGES
  // ═══════════════════════════════════════════════════════

  Future<void> sendImageMessage(String roomId, String imageUrl, String senderUid,
      String senderName, String senderPhotoUrl) async {
    final msgId = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final msg = MessageModel(
      msgId: msgId,
      roomId: roomId,
      senderUid: senderUid,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      text: imageUrl,
      imageUrl: imageUrl,
      type: 'image',
      timestamp: now,
    );
    final map = msg.toMap();
    map['room_id'] = roomId;
    map['image_url'] = imageUrl;
    map['imageUrl'] = imageUrl;
    map['timestamp'] = now;
    map['created_at'] = DateTime.fromMillisecondsSinceEpoch(now).toIso8601String();
    unawaited(SupabaseDataService().sendMessage(msg));
    try {
      await _db.collection('room_messages').doc(msgId).set(map);
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════
  // PRIVATE MESSAGING
  // ═══════════════════════════════════════════════════════

  Future<String> _getOrCreateConversationId(String uid1, String uid2) async {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  Future<void> sendPrivateMessage({
    required String senderId,
    required String senderName,
    required String senderPhotoUrl,
    required String receiverId,
    required String receiverName,
    required String receiverPhotoUrl,
    required String text,
    String? imageUrl,
    String type = 'text',
  }) async {
    // 0. Ensure Firebase anonymous auth is active so Firestore rules never reject
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (e) {
      debugPrint('[sendPrivateMessage] FirebaseAuth signInAnonymously: $e');
    }

    // 0.1 Resolve numeric customId to canonical auth UID if applicable
    String resolvedSenderId = senderId.trim();
    String resolvedReceiverId = receiverId.trim();

    if (RegExp(r'^\d+$').hasMatch(resolvedReceiverId)) {
      try {
        final snap = await _db.collection('users').where('custom_id', isEqualTo: resolvedReceiverId).limit(1).get();
        if (snap.docs.isNotEmpty) {
          resolvedReceiverId = snap.docs.first.id;
        } else {
          final sUser = await SupabaseDataService().findUserByIdOrCustomId(resolvedReceiverId);
          if (sUser != null && sUser.uid.isNotEmpty) {
            resolvedReceiverId = sUser.uid;
          }
        }
      } catch (_) {}
    }

    if (RegExp(r'^\d+$').hasMatch(resolvedSenderId)) {
      try {
        final snap = await _db.collection('users').where('custom_id', isEqualTo: resolvedSenderId).limit(1).get();
        if (snap.docs.isNotEmpty) {
          resolvedSenderId = snap.docs.first.id;
        }
      } catch (_) {}
    }

    // 1. Block checks
    try {
      final blockDoc = await _db.collection('blocks').doc('${resolvedReceiverId}_$resolvedSenderId').get();
      if (blockDoc.exists) {
        throw Exception('لا يمكنك إرسال رسالة لأن هذا المستخدم قام بحظرك.');
      }
      final myBlockDoc = await _db.collection('blocks').doc('${resolvedSenderId}_$resolvedReceiverId').get();
      if (myBlockDoc.exists) {
        throw Exception('لقد قمت بحظر هذا المستخدم. يجب إزالة الحظر أولاً.');
      }
    } catch (e) {
      if (e is Exception && e.toString().contains('بحظر')) rethrow;
      debugPrint('[sendPrivateMessage] block check ignored: $e');
    }

    final convId = await _getOrCreateConversationId(resolvedSenderId, resolvedReceiverId);
    final msgId = const Uuid().v4();
    final sName = senderName.isNotEmpty ? senderName : 'مستخدم';
    final rName = receiverName.isNotEmpty ? receiverName : 'مستخدم';
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    final isoDate = DateTime.fromMillisecondsSinceEpoch(nowMillis).toUtc().toIso8601String();

    final msg = MessageModel(
      msgId: msgId,
      senderUid: resolvedSenderId,
      senderName: sName,
      senderPhotoUrl: senderPhotoUrl,
      text: text,
      imageUrl: imageUrl,
      type: type,
      timestamp: nowMillis,
    );
    final data = msg.toMap();
    data['conv_id'] = convId;
    data['id'] = msgId;
    data['timestamp'] = nowMillis;
    data['created_at'] = isoDate;

    // 2. Write to Firestore private_messages
    try {
      await _db.collection('private_messages').doc(msgId).set(data);
    } catch (e) {
      debugPrint('[sendPrivateMessage] Firestore private_messages error: $e');
    }

    // 2.1 Sync to Supabase private_messages
    try {
      await Supabase.instance.client.from('private_messages').insert({
        'id': msgId,
        'conv_id': convId,
        'sender_uid': resolvedSenderId,
        'sender_name': sName,
        'sender_photo_url': senderPhotoUrl,
        'text': text,
        'image_url': imageUrl,
        'created_at': isoDate,
      });
    } catch (e) {
      debugPrint('[sendPrivateMessage] Supabase private_messages insert error: $e');
    }

    // 3. Sender conversation in Firestore
    try {
      await _db.collection('conversations').doc('${resolvedSenderId}_$convId').set({
        'uid': resolvedSenderId,
        'conversationId': convId,
        'otherUid': resolvedReceiverId,
        'otherName': rName,
        'otherPhotoUrl': receiverPhotoUrl,
        'lastMessage': type == 'image' ? '[صورة]' : text,
        'lastMessageTime': nowMillis,
        'unreadCount': 0,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[sendPrivateMessage] sender conversation error: $e');
    }

    // 4. Receiver conversation in Firestore
    try {
      await _db.collection('conversations').doc('${resolvedReceiverId}_$convId').set({
        'uid': resolvedReceiverId,
        'conversationId': convId,
        'otherUid': resolvedSenderId,
        'otherName': sName,
        'otherPhotoUrl': senderPhotoUrl,
        'lastMessage': type == 'image' ? '[صورة]' : text,
        'lastMessageTime': nowMillis,
        'unreadCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[sendPrivateMessage] receiver conversation error: $e');
    }

    // 4.1 Sync to Supabase conversations table
    try {
      await Supabase.instance.client.from('conversations').upsert([
        {
          'uid': resolvedSenderId,
          'conv_id': convId,
          'last_message': type == 'image' ? '[صورة]' : text,
          'last_sender_uid': resolvedSenderId,
          'last_timestamp': isoDate,
          'unread_count': 0,
        },
        {
          'uid': resolvedReceiverId,
          'conv_id': convId,
          'last_message': type == 'image' ? '[صورة]' : text,
          'last_sender_uid': resolvedSenderId,
          'last_timestamp': isoDate,
          'unread_count': 1,
        }
      ]);
    } catch (e) {
      debugPrint('[sendPrivateMessage] Supabase conversations upsert error: $e');
    }
  }

  Stream<List<Map<String, dynamic>>> conversationsStream(String uid) {
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
    final Map<String, Map<String, dynamic>> convsMap = {};

    void emitMerged() {
      if (controller.isClosed) return;
      final list = convsMap.values.toList();
      list.sort((a, b) {
        final at = a['lastMessageTime'] as int? ?? 0;
        final bt = b['lastMessageTime'] as int? ?? 0;
        return bt.compareTo(at);
      });
      controller.add(list);
    }

    // 1. Fetch from Supabase conversations
    Future<void> fetchSupabase() async {
      try {
        final rows = await Supabase.instance.client
            .from('conversations')
            .select('*')
            .eq('uid', uid);
        for (final r in rows) {
          final cId = r['conv_id']?.toString() ?? '';
          if (cId.isEmpty) continue;
          final parts = cId.split('_');
          final otherUid = parts.firstWhere((p) => p != uid, orElse: () => '');
          int timeMillis = 0;
          if (r['last_timestamp'] != null) {
            timeMillis = DateTime.tryParse(r['last_timestamp'].toString())?.millisecondsSinceEpoch ?? 0;
          }
          final key = '${uid}_$cId';
          if (!convsMap.containsKey(key) || (timeMillis > (convsMap[key]?['lastMessageTime'] as int? ?? 0))) {
            convsMap[key] = {
              'uid': uid,
              'conversationId': cId,
              'otherUid': otherUid,
              'otherName': 'مستخدم',
              'otherPhotoUrl': '',
              'lastMessage': r['last_message']?.toString() ?? '',
              'lastMessageTime': timeMillis,
              'unreadCount': r['unread_count'] as int? ?? 0,
            };
          }
        }
        emitMerged();
      } catch (_) {}
    }

    fetchSupabase();
    final pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => fetchSupabase());

    // 2. Ensure Firebase anonymous auth before listening to Firestore
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        FirebaseAuth.instance.signInAnonymously().catchError((_) => null as dynamic);
      }
    } catch (_) {}

    // 3. Listen to Firestore conversations
    StreamSubscription? firestoreSub;
    try {
      firestoreSub = _db
          .collection('conversations')
          .where('uid', isEqualTo: uid)
          .snapshots()
          .listen((snap) {
        for (final doc in snap.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          final cId = data['conversationId']?.toString() ?? doc.id;
          final key = '${uid}_$cId';
          convsMap[key] = data;
        }
        emitMerged();
      }, onError: (err) {
        debugPrint('[conversationsStream] Firestore error: $err');
      });
    } catch (e) {
      debugPrint('[conversationsStream] Firestore subscribe error: $e');
    }

    controller.onCancel = () {
      pollTimer.cancel();
      firestoreSub?.cancel();
    };

    return controller.stream;
  }

  Stream<List<MessageModel>> privateMessagesStream(String conversationId) {
    final controller = StreamController<List<MessageModel>>.broadcast();
    final Map<String, MessageModel> msgMap = {};

    void emitMerged() {
      if (controller.isClosed) return;
      final list = msgMap.values.toList();
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      controller.add(list);
    }

    // 1. Fetch from Supabase
    Future<void> fetchSupabase() async {
      try {
        final rows = await Supabase.instance.client
            .from('private_messages')
            .select('*')
            .eq('conv_id', conversationId);
        for (final r in rows) {
          final m = MessageModel(
            msgId: r['id']?.toString() ?? '',
            senderUid: r['sender_uid']?.toString() ?? '',
            senderName: r['sender_name']?.toString() ?? '',
            senderPhotoUrl: r['sender_photo_url']?.toString() ?? '',
            text: r['text']?.toString() ?? '',
            imageUrl: r['image_url']?.toString(),
            type: (r['image_url'] != null && r['image_url'].toString().isNotEmpty) ? 'image' : 'text',
            timestamp: r['created_at'] != null
                ? (DateTime.tryParse(r['created_at'].toString())?.millisecondsSinceEpoch ?? 0)
                : 0,
          );
          if (m.msgId.isNotEmpty) {
            msgMap[m.msgId] = m;
          }
        }
        emitMerged();
      } catch (_) {}
    }

    fetchSupabase();
    final pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => fetchSupabase());

    // 2. Ensure Firebase anonymous auth before listening to Firestore
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        FirebaseAuth.instance.signInAnonymously().catchError((_) => null as dynamic);
      }
    } catch (_) {}

    // 3. Listen to Firestore
    StreamSubscription? firestoreSub;
    try {
      firestoreSub = _db
          .collection('private_messages')
          .where('conv_id', isEqualTo: conversationId)
          .snapshots()
          .listen((snap) {
        for (final doc in snap.docs) {
          final m = MessageModel.fromMap(_data(doc));
          final key = m.msgId.isNotEmpty ? m.msgId : doc.id;
          msgMap[key] = m;
        }
        emitMerged();
      }, onError: (err) {
        debugPrint('[privateMessagesStream] Firestore error: $err');
      });
    } catch (e) {
      debugPrint('[privateMessagesStream] Firestore error: $e');
    }

    controller.onCancel = () {
      pollTimer.cancel();
      firestoreSub?.cancel();
    };

    return controller.stream;
  }

  Future<void> markConversationRead(String uid, String conversationId) async {
    try {
      await _db.collection('conversations').doc('${uid}_$conversationId').update({'unreadCount': 0});
    } catch (_) {}
    try {
      await Supabase.instance.client
          .from('conversations')
          .update({'unread_count': 0})
          .eq('uid', uid)
          .eq('conv_id', conversationId);
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════
  // DIAMOND ↔ COIN EXCHANGE
  // ═══════════════════════════════════════════════════════

  Future<({bool success, int coinsReceived, String? error})> exchangeDiamondsToCoins({
    required String uid,
    required int diamonds,
    required int rate,
  }) async {
    final effectiveRate = rate <= 0 ? 2 : rate;
    if (diamonds < 1) {
      return (success: false, coinsReceived: 0, error: 'يرجى إدخال كمية ألماس صحيحة');
    }
    if (diamonds < effectiveRate) {
      return (success: false, coinsReceived: 0, error: 'الحد الأدنى للتبديل هو $effectiveRate ألماس');
    }
    try {
      // 1. Fetch current balances from Supabase and Firestore
      int currentDiamonds = 0;
      int currentCoins = 0;

      try {
        UserModel? supaUser = await SupabaseAuthService().getUserFromSupabase(uid);
        supaUser ??= await SupabaseDataService().getUser(uid);
        if (supaUser != null) {
          if (supaUser.diamonds > currentDiamonds) currentDiamonds = supaUser.diamonds;
          if (supaUser.coins > currentCoins) currentCoins = supaUser.coins;
        }
      } catch (_) {}

      final userRef = _db.collection('users').doc(uid);
      final walletRef = _db.collection('user_wallets').doc(uid);

      try {
        final snap = await userRef.get();
        if (snap.exists) {
          final d = snap.data() ?? {};
          final fd = (d['diamonds'] as num?)?.toInt() ?? 0;
          final fc = (d['coins'] as num?)?.toInt() ?? 0;
          if (fd > currentDiamonds) currentDiamonds = fd;
          if (fc > currentCoins) currentCoins = fc;
        }
      } catch (_) {}

      try {
        final wSnap = await walletRef.get();
        if (wSnap.exists) {
          final wd = wSnap.data() ?? {};
          final fwd = (wd['diamond_balance'] as num?)?.toInt() ?? 0;
          final fwc = (wd['gold_balance'] as num?)?.toInt() ?? (wd['coin_balance'] as num?)?.toInt() ?? 0;
          if (fwd > currentDiamonds) currentDiamonds = fwd;
          if (fwc > currentCoins) currentCoins = fwc;
        }
      } catch (_) {}

      if (currentDiamonds < diamonds) {
        return (success: false, coinsReceived: 0, error: 'رصيد ألماس غير كافٍ (رصيدك الحالي: $currentDiamonds)');
      }

      final coinsReceived = diamonds ~/ effectiveRate;
      if (coinsReceived < 1) {
        return (success: false, coinsReceived: 0, error: 'الحد الأدنى للتبديل هو $effectiveRate ألماس');
      }

      final newDiamonds = currentDiamonds - diamonds;
      final newCoins = currentCoins + coinsReceived;

      // 2. Update Supabase safely
      try {
        await SupabaseDataService().updateUser(uid, {
          'diamonds': newDiamonds,
          'coins': newCoins,
        });
      } catch (se) {
        debugPrint('[exchangeDiamondsToCoins] Supabase update non-fatal: $se');
      }

      // 3. Update Firestore
      try {
        await userRef.set({
          'diamonds': newDiamonds,
          'coins': newCoins,
        }, SetOptions(merge: true));

        await walletRef.set({
          'diamond_balance': newDiamonds,
          'gold_balance': newCoins,
        }, SetOptions(merge: true));
      } catch (fe) {
        debugPrint('Firestore exchange update non-fatal error: $fe');
      }

      // 4. Log transaction
      try {
        await _db.collection('diamond_exchanges').add({
          'uid': uid,
          'diamonds_exchanged': diamonds,
          'coins_received': coinsReceived,
          'rate': effectiveRate,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (_) {}

      return (success: true, coinsReceived: coinsReceived, error: null);
    } catch (e) {
      return (success: false, coinsReceived: 0, error: 'فشل التبادل: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // RECHARGE
  // ═══════════════════════════════════════════════════════

  Future<void> addCoins(String uid, int amount) async {
    if (amount <= 0) return;
    try {
      UserModel? user = await SupabaseAuthService().getUserFromSupabase(uid);
      user ??= await SupabaseDataService().getUser(uid);
      int curCoins = user?.coins ?? 0;

      try {
        final snap = await _db.collection('users').doc(uid).get();
        if (snap.exists) {
          final fc = (snap.data()?['coins'] as num?)?.toInt() ?? 0;
          if (fc > curCoins) curCoins = fc;
        }
      } catch (_) {}

      final newCoins = curCoins + amount;
      await SupabaseDataService().updateUser(uid, {'coins': newCoins});

      try {
        await _db.collection('users').doc(uid).set({'coins': newCoins}, SetOptions(merge: true));
      } catch (_) {}
    } catch (e) {
      debugPrint('addCoins error: $e');
    }
    try {
      final levelService = LevelService();
      await levelService.loadAllLevels();
      await levelService.addExp(uid: uid, type: 'recharge', amount: amount);
    } catch (e) {
      debugPrint('addCoins: recharge XP error: $e');
    }
  }

  Future<bool> deductCoins(String uid, int amount, String reason) async {
    if (amount <= 0) return true;
    try {
      UserModel? user = await SupabaseAuthService().getUserFromSupabase(uid);
      user ??= await SupabaseDataService().getUser(uid);
      int curCoins = user?.coins ?? 0;

      try {
        final snap = await _db.collection('users').doc(uid).get();
        if (snap.exists) {
          final fc = (snap.data()?['coins'] as num?)?.toInt() ?? 0;
          if (fc > curCoins) curCoins = fc;
        }
      } catch (_) {}

      if (curCoins < amount) {
        debugPrint('deductCoins: insufficient coins ($curCoins < $amount)');
        return false;
      }

      final newCoins = curCoins - amount;
      await SupabaseDataService().updateUser(uid, {'coins': newCoins});

      try {
        await _db.collection('users').doc(uid).set({'coins': newCoins}, SetOptions(merge: true));
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint('deductCoins error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // USER FOLLOW
  // ═══════════════════════════════════════════════════════

  Future<void> followUser(String uid, String targetUid) async {
    if (uid == targetUid) return;
    await SupabaseDataService().followUser(uid, targetUid);
    try {
      await _db.collection('follows').doc('${uid}_$targetUid').set({
        'follower_uid': uid,
        'following_uid': targetUid,
        'created_at': _now(),
      });
      await _incrementCounter('users', uid, 'following', 1);
      await _incrementCounter('users', targetUid, 'followers', 1);
    } catch (_) {}
  }

  Future<void> unfollowUser(String uid, String targetUid) async {
    if (uid == targetUid) return;
    await SupabaseDataService().unfollowUser(uid, targetUid);
    try {
      await _db.collection('follows').doc('${uid}_$targetUid').delete();
      await _incrementCounter('users', uid, 'following', -1);
      await _incrementCounter('users', targetUid, 'followers', -1);
    } catch (_) {}
  }

  Future<bool> isFollowing(String uid, String targetUid) async {
    if (uid.isEmpty || targetUid.isEmpty) return false;
    final supaResult = await SupabaseDataService().isFollowing(uid, targetUid);
    if (supaResult) return true;
    try {
      final doc = await _db.collection('follows').doc('${uid}_$targetUid').get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  Future<void> recordProfileVisit({
    required String visitedUid,
    required String visitorUid,
    String? visitorName,
    String? visitorPhoto,
  }) async {
    if (visitedUid.isEmpty || visitorUid.isEmpty || visitedUid == visitorUid) {
      return;
    }
    await SupabaseDataService().logProfileVisit(visitedUid, visitorUid);
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final visitDocId = '${visitedUid}_$visitorUid';
      await _db.collection('profile_visits').doc(visitDocId).set({
        'visited_uid': visitedUid,
        'visitor_uid': visitorUid,
        'visitor_name': visitorName ?? '',
        'visitor_photo': visitorPhoto ?? '',
        'visited_at': now,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<int> incrementVisitors(String uid) async {
    try {
      return await SupabaseDataService().getVisitorsCount(uid);
    } catch (e) {
      return 0;
    }
  }

  Future<void> _incrementCounter(String coll, String docId, String field, int delta) async {
    try {
      final ref = _db.collection(coll).doc(docId);
      final snap = await ref.get();
      if (!snap.exists) return;
      await ref.update({field: ((snap.data()?[field] ?? 0) as int) + delta});
    } catch (e) {
      debugPrint('_incrementCounter error: $e');
    }
  }

  Future<String?> getUserCurrentRoomId(String uid) async {
    try {
      final snap = await _db.collection('room_members').where('uid', isEqualTo: uid).limit(1).get();
      if (snap.docs.isEmpty) return null;
      return snap.docs.first.data()['room_id']?.toString();
    } catch (e) {
      debugPrint('getUserCurrentRoomId error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getFollowing(String uid) async {
    try {
      final list = await SupabaseDataService().getFollowingUsers(uid);
      if (list.isNotEmpty) return list;
    } catch (_) {}
    try {
      final snap = await _db.collection('follows').where('follower_uid', isEqualTo: uid).get();
      final uids = snap.docs
          .map((e) => e.data()['following_uid']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      return await _batchFetchUsers(uids);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getFans(String uid) async {
    try {
      final list = await SupabaseDataService().getFollowerUsers(uid);
      if (list.isNotEmpty) return list;
    } catch (_) {}
    try {
      final snap = await _db.collection('follows').where('following_uid', isEqualTo: uid).get();
      final uids = snap.docs
          .map((e) => e.data()['follower_uid']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      return await _batchFetchUsers(uids);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _batchFetchUsers(List<String> uids) async {
    final users = <Map<String, dynamic>>[];
    for (final uid in uids) {
      try {
        final doc = await _db.collection('users').doc(uid).get();
        if (!doc.exists) continue;
        final d = doc.data() ?? {};
        final photo = d['photoUrl']?.toString() ?? d['photo_url']?.toString() ?? d['avatar']?.toString() ?? '';
        final name = d['name']?.toString() ?? 'User';
        users.add({
          'uid': uid,
          'id': uid,
          'name': name,
          'photo_url': photo,
          'avatar': photo,
          'gender': d['gender']?.toString() ?? 'male',
          'level': (d['level'] as num?)?.toInt() ?? 1,
          'country_idx': (d['country_idx'] as num?)?.toInt() ?? 0,
          'custom_id': d['custom_id']?.toString() ?? d['customId']?.toString() ?? '',
        });
      } catch (_) {}
    }
    return users;
  }

  Future<List<Map<String, dynamic>>> getVisitors(String uid) async {
    if (uid.isEmpty) return [];
    try {
      final list = await SupabaseDataService().getVisitorUsers(uid);
      if (list.isNotEmpty) return list;
    } catch (_) {}
    try {
      final snap = await _db.collection('profile_visits').where('visited_uid', isEqualTo: uid).get();
      final uids = snap.docs
          .map((e) => e.data()['visitor_uid']?.toString() ?? '')
          .where((id) => id.isNotEmpty && id != uid)
          .toSet()
          .toList();
      return await _batchFetchUsers(uids);
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, int>> getVisitorHistoryDays(String uid) async {
    try {
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      final snap = await _db
          .collection('profile_visits')
          .where('visited_uid', isEqualTo: uid)
          .get();
      final dayCounts = <String, int>{};
      for (int i = 6; i >= 0; i--) {
        final d = now.subtract(Duration(days: i));
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        dayCounts[key] = 0;
      }
      for (final e in snap.docs) {
        final ts = e.data()['visited_at']?.toString() ?? '';
        final dt = DateTime.tryParse(ts);
        if (dt != null && !dt.isBefore(sevenDaysAgo)) {
          final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
          if (dayCounts.containsKey(key)) {
            dayCounts[key] = (dayCounts[key] ?? 0) + 1;
          }
        }
      }
      return dayCounts;
    } catch (e) {
      debugPrint('getVisitorHistoryDays error: $e');
      return {};
    }
  }

  // ═══════════════════════════════════════════════════════
  // BADGES & NECKLACES
  // ═══════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getBadgesCatalog() async {
    try {
      final sbBadges = await SupabaseDataService().getBadges();
      if (sbBadges.isNotEmpty) {
        return sbBadges;
      }
    } catch (_) {}
    try {
      final snap = await _db.collection('badges').get();
      return snap.docs.map((e) => Map<String, dynamic>.from(e.data())).toList();
    } catch (e) {
      debugPrint('getBadgesCatalog error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getNecklacesCatalog() async {
    try {
      final sbNecklaces = await SupabaseDataService().getNecklaces();
      if (sbNecklaces.isNotEmpty) {
        return sbNecklaces;
      }
    } catch (_) {}
    try {
      final snap = await _db.collection('necklaces').get();
      final list = snap.docs.map((e) => Map<String, dynamic>.from(e.data())).toList();
      list.sort((a, b) => ((a['sort_order'] ?? 0) as int).compareTo((b['sort_order'] ?? 0) as int));
      return list;
    } catch (e) {
      debugPrint('getNecklacesCatalog error: $e');
      return [];
    }
  }

  Future<List<String>> awardRechargeNecklaces(String uid, int rechargeLevel) async {
    try {
      final cat = await getNecklacesCatalog();
      final eligible = <Map<String, dynamic>>[];
      for (final n in cat) {
        if (n['type']?.toString() == 'recharge') {
          final req = (n['required_recharge_level'] ?? 0).toInt();
          if (req > 0 && req <= rechargeLevel) {
            eligible.add(n);
          }
        }
      }
      if (eligible.isEmpty) return [];

      final userDoc = await _db.collection('users').doc(uid).get();
      final current = List<String>.from(userDoc.data()?['owned_necklaces'] ?? []);
      final toAdd = eligible
          .map((n) => n['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty && !current.contains(id))
          .toList();
      if (toAdd.isEmpty) return [];

      final updated = [...current, ...toAdd];
      await updateUser(uid, {'owned_necklaces': updated});
      return toAdd;
    } catch (e) {
      debugPrint('awardRechargeNecklaces error: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════
  // ENTRANCE EFFECTS
  // ═══════════════════════════════════════════════════════

  Future<void> logEntrance(String roomId, String uid, String name, String photoUrl,
      String? entranceItem, {String? carItem}) async {
    final now = _now();
    final primaryAsset = (carItem != null && carItem.isNotEmpty)
        ? carItem
        : ((entranceItem != null && entranceItem.isNotEmpty) ? entranceItem : '');
    final text = (carItem != null && carItem.isNotEmpty)
        ? 'انضم $name إلى الغرفة بسيارة'
        : 'انضم $name إلى الغرفة';

    final msg = MessageModel(
      msgId: const Uuid().v4(),
      roomId: roomId,
      senderUid: uid,
      senderName: name,
      senderPhotoUrl: photoUrl,
      text: text,
      type: 'entrance',
      imageUrl: primaryAsset,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    unawaited(SupabaseDataService().sendMessage(msg));

    try {
      await _db.collection('room_messages').doc(msg.msgId).set({
        'msg_id': msg.msgId,
        'room_id': roomId,
        'sender_uid': uid,
        'sender_name': name,
        'sender_photo_url': photoUrl,
        'text': text,
        'type': 'entrance',
        'image_url': primaryAsset,
        'created_at': now,
      });
    } catch (_) {}
  }

  Future<void> logExit(String roomId, String name) async {
    final now = _now();
    final text = '$name غادر الغرفة';
    final msg = MessageModel(
      msgId: const Uuid().v4(),
      roomId: roomId,
      senderUid: '',
      senderName: name,
      senderPhotoUrl: '',
      text: text,
      type: 'entrance',
      imageUrl: '',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    unawaited(SupabaseDataService().sendMessage(msg));

    try {
      await _db.collection('room_messages').doc(msg.msgId).set({
        'msg_id': msg.msgId,
        'room_id': roomId,
        'sender_uid': '',
        'sender_name': name,
        'sender_photo_url': '',
        'text': text,
        'type': 'entrance',
        'created_at': now,
      });
    } catch (_) {}
  }

  Stream<List<Map<String, dynamic>>> entrancesStream(String roomId) async* {
    while (true) {
      try {
        final messages = await SupabaseDataService().getRoomMessages(roomId, limit: 30);
        final entranceMessages = messages.where((m) => m.type == 'entrance').toList();
        final list = entranceMessages.map((m) {
          final tsStr = DateTime.fromMillisecondsSinceEpoch(m.timestamp).toIso8601String();
          return {
            'uid': m.senderUid,
            'name': m.senderName,
            'photoUrl': m.senderPhotoUrl,
            'entranceItem': m.imageUrl ?? '',
            'timestamp': tsStr,
          };
        }).toList();
        yield list;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 1500));
    }
  }

  // ═══════════════════════════════════════════════════════
  // GLOBAL BROADCASTS & ROOM ROCKET (CRYSTAL BURST)
  // ═══════════════════════════════════════════════════════

  Stream<List<Map<String, dynamic>>> globalBroadcastStream() {
    return _db
        .collection('broadcasts')
        .orderBy('created_at', descending: true)
        .limit(10)
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Future<void> sendGlobalBroadcast({
    required String senderUid,
    required String senderName,
    required String senderPhotoUrl,
    required String roomId,
    required String roomName,
    required String content,
    String? giftIcon,
    int? multiplier,
    String type = 'lucky_gift', // 'lucky_gift', 'big_gift', 'admin_notice', 'crystal_rocket'
  }) async {
    await _db.collection('broadcasts').add({
      'sender_uid': senderUid,
      'sender_name': senderName,
      'sender_photo_url': senderPhotoUrl,
      'room_id': roomId,
      'room_name': roomName,
      'content': content,
      'gift_icon': giftIcon,
      'multiplier': multiplier,
      'type': type,
      'created_at': _now(),
    });
  }

  Stream<Map<String, dynamic>> roomRocketStream(String roomId) {
    return _db.collection('rooms').doc(roomId).snapshots().map((snap) {
      final data = snap.data() ?? {};
      final energy = (data['rocket_energy'] as num?)?.toInt() ?? 0;
      final target = (data['rocket_target'] as num?)?.toInt() ?? 5000;
      final burstActive = data['rocket_burst_active'] == true;
      final burstId = data['rocket_burst_id']?.toString() ?? '';
      return {
        'energy': energy,
        'target': target,
        'burst_active': burstActive,
        'burst_id': burstId,
      };
    });
  }

  Future<void> addRocketEnergy(String roomId, int coins) async {
    final ref = _db.collection('rooms').doc(roomId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      final current = (data['rocket_energy'] as num?)?.toInt() ?? 0;
      final target = (data['rocket_target'] as num?)?.toInt() ?? 5000;
      final newEnergy = current + coins;
      if (newEnergy >= target) {
        final burstId = const Uuid().v4();
        tx.update(ref, {
          'rocket_energy': 0,
          'rocket_burst_active': true,
          'rocket_burst_id': burstId,
          'rocket_burst_time': _now(),
        });
      } else {
        tx.update(ref, {'rocket_energy': newEnergy});
      }
    });
  }

  Future<void> endRocketBurst(String roomId) async {
    await _db.collection('rooms').doc(roomId).update({
      'rocket_burst_active': false,
    });
  }

  Stream<Map<String, dynamic>> luckyGiftRatesStream() {
    return _db.collection('app_config').doc('lucky_gift_rates').snapshots().map((snap) {
      return snap.data() ?? {
        'multipliers': [5, 10, 20, 50, 100, 250, 500, 1000],
        'default_rates': {
          '5': 0.30,
          '10': 0.15,
          '20': 0.05,
          '50': 0.02,
          '100': 0.008,
          '250': 0.003,
          '500': 0.001,
          '1000': 0.0005,
        }
      };
    });
  }

  // ═══════════════════════════════════════════════════════
  // NOTIFICATIONS
  // ═══════════════════════════════════════════════════════

  Stream<List<NotificationModel>> notificationsStream({String? uid}) {
    final controller = StreamController<List<NotificationModel>>.broadcast();
    List<NotificationModel> sbList = [];
    List<NotificationModel> fsList = [];

    void emitMerged() {
      if (controller.isClosed) return;
      final map = <String, NotificationModel>{};
      for (final n in sbList) {
        map[n.id] = n;
      }
      for (final n in fsList) {
        map[n.id] = n;
      }
      final list = map.values.toList();
      list.sort((a, b) => b.sentAt.compareTo(a.sentAt));
      controller.add(list);
    }

    // 1. Immediately fetch from Supabase
    SupabaseDataService().getNotifications(uid: uid).then((list) {
      sbList = list;
      emitMerged();
    }).catchError((_) {
      if (sbList.isEmpty && fsList.isEmpty && !controller.isClosed) {
        controller.add(<NotificationModel>[]);
      }
    });

    // 2. Poll Supabase every 5 seconds
    final timer = Timer.periodic(const Duration(seconds: 5), (_) {
      SupabaseDataService().getNotifications(uid: uid).then((list) {
        sbList = list;
        emitMerged();
      }).catchError((_) {});
    });

    // 3. Listen to Firestore without blocking
    StreamSubscription? fsSub;
    try {
      Query<Map<String, dynamic>> query = _db.collection('notifications');
      if (uid != null && uid.isNotEmpty) {
        query = query.where('uid', isEqualTo: uid);
      }
      fsSub = query.snapshots().listen((snap) {
        fsList = snap.docs.map((e) => NotificationModel.fromMap(_data(e))).toList();
        emitMerged();
      }, onError: (_) {});
    } catch (_) {}

    controller.onCancel = () {
      timer.cancel();
      fsSub?.cancel();
    };

    return controller.stream;
  }

  Future<void> sendNotification({
    required String uid,
    required String type,
    String actorUid = '',
    String title = '',
    String body = '',
    Map<String, dynamic>? data,
  }) async {
    final notifId = const Uuid().v4();
    final nowStr = _now();
    try {
      await _db.collection('notifications').doc(notifId).set({
        'id': notifId,
        'uid': uid,
        'type': type,
        'actor_uid': actorUid,
        'title': title,
        'body': body,
        'data': data,
        'created_at': nowStr,
      });
    } catch (_) {}

    try {
      await SupabaseDataService().sendNotification(
        uid: uid,
        type: type,
        actorUid: actorUid,
        title: title,
        body: body,
        data: data,
      );
    } catch (_) {}
  }

  Future<void> markNotificationRead(String id) async {
    await _db.collection('notifications').doc(id).update({'read': true});
  }

  Future<void> deleteNotification(String id) async {
    await _db.collection('notifications').doc(id).delete();
  }

  // ═══════════════════════════════════════════════════════
  // REPORTS
  // ═══════════════════════════════════════════════════════

  Future<void> reportUser({
    required String reporterUid,
    required String reportedUid,
    required String reason,
    String? description,
  }) async {
    try {
      await _db.collection('reports').add({
        'id': const Uuid().v4(),
        'reporter_uid': reporterUid,
        'reported_uid': reportedUid,
        'reason': reason,
        'description': description ?? '',
        'status': 'pending',
        'created_at': _now(),
      });
    } catch (e) {
      debugPrint('reportUser firestore error: $e');
    }

    try {
      await SupabaseDataService().submitReport({
        'reporter_uid': reporterUid,
        'reported_uid': reportedUid,
        'reason': reason,
        'description': description ?? '',
        'status': 'pending',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('reportUser supabase error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getReports() async {
    try {
      final snap = await _db.collection('reports').get();
      final list = snap.docs.map((e) {
        final d = Map<String, dynamic>.from(e.data());
        d['id'] = e.id;
        return d;
      }).toList();
      list.sort((a, b) {
        final at = a['created_at']?.toString() ?? '';
        final bt = b['created_at']?.toString() ?? '';
        return bt.compareTo(at);
      });
      return list;
    } catch (e) {
      debugPrint('getReports error: $e');
      return [];
    }
  }

  Future<void> resolveReport(String reportId) async {
    try {
      await _db.collection('reports').doc(reportId).update({
        'status': 'resolved',
        'resolved_at': _now(),
      });
    } catch (e) {
      debugPrint('resolveReport error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // ROOM BLOCKS (BAN FROM ROOM)
  // ═══════════════════════════════════════════════════════

  Future<void> blockUserFromRoom(String roomId, String blockerUid, String blockedUid,
      {String reason = ''}) async {
    if (blockerUid == blockedUid) return;
    try {
      await _db.collection('room_blocks').doc('${roomId}_$blockedUid').set({
        'room_id': roomId,
        'blocker_uid': blockerUid,
        'blocked_uid': blockedUid,
        'reason': reason,
        'created_at': _now(),
      });
    } catch (e) {
      debugPrint('blockUserFromRoom error: $e');
    }
  }

  Future<void> unblockUserFromRoom(String roomId, String blockedUid) async {
    try {
      await _db.collection('room_blocks').doc('${roomId}_$blockedUid').delete();
    } catch (e) {
      debugPrint('unblockUserFromRoom error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getRoomBlockedUsers(String roomId) async {
    try {
      final snap = await _db.collection('room_blocks').where('room_id', isEqualTo: roomId).get();
      return snap.docs.map((e) => Map<String, dynamic>.from(e.data())).toList();
    } catch (e) {
      debugPrint('getRoomBlockedUsers error: $e');
      return [];
    }
  }

  Future<List<String>> getRoomBlockedUids(String roomId) async {
    try {
      final snap = await _db.collection('room_blocks').where('room_id', isEqualTo: roomId).get();
      return snap.docs
          .map((e) => e.data()['blocked_uid']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('getRoomBlockedUids error: $e');
      return [];
    }
  }

  Future<bool> isUserBlockedFromRoom(String roomId, String uid) async {
    if (roomId.isEmpty || uid.isEmpty) return false;
    try {
      final doc = await _db.collection('room_blocks').doc('${roomId}_$uid').get();
      return doc.exists;
    } catch (e) {
      if (e is! FirebaseException || (e.code != 'permission-denied' && e.code != 'unavailable')) {
        debugPrint('isUserBlockedFromRoom error: $e');
      }
      return false;
    }
  }

  Stream<List<Map<String, dynamic>>> roomBlocksStream(String roomId) {
    return _db
        .collection('room_blocks')
        .where('room_id', isEqualTo: roomId)
        .snapshots()
        .map((snap) => snap.docs.map((e) => Map<String, dynamic>.from(e.data())).toList())
        .handleError((_) => <Map<String, dynamic>>[]);
  }

  Stream<bool> userRoomBanStream(String roomId, String uid) {
    return _db
        .collection('room_blocks')
        .doc('${roomId}_$uid')
        .snapshots()
        .map((snap) => snap.exists)
        .handleError((_) => false);
  }

  Future<void> kickUserFromRoom(String roomId, String kickerUid, String targetUid, {
    String kickerName = '',
    String targetName = '',
    bool addToBlacklist = false,
    String reason = 'Kicked by administrator',
  }) async {
    try {
      // 1. If addToBlacklist is checked, save to room_blocks
      if (addToBlacklist) {
        await blockUserFromRoom(roomId, kickerUid, targetUid, reason: reason);
      }
      // 2. Remove user from seats
      for (int i = 0; i < 20; i++) {
        final seatDoc = await _db.collection('room_seats').doc('${roomId}_$i').get();
        if (seatDoc.exists && seatDoc.data()?['uid'] == targetUid) {
          await leaveSeat(roomId, i);
        }
      }
      // 3. Remove user presence
      await leaveRoom(roomId, targetUid);
      // 4. Send a kick signal message to room_messages so the client can listen & auto-exit
      final msgId = const Uuid().v4();
      final kickMsg = MessageModel(
        msgId: msgId,
        roomId: roomId,
        senderUid: kickerUid,
        senderName: kickerName.isNotEmpty ? kickerName : 'Admin',
        senderPhotoUrl: '',
        text: '$targetName تم طرده من الغرفة بواسطة $kickerName',
        type: 'room_kick',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        giftPayload: {
          'kickedUid': targetUid,
          'targetName': targetName,
          'isBlacklisted': addToBlacklist,
          'reason': reason,
        },
      );
      await _db.collection('room_messages').doc(msgId).set(kickMsg.toMap());
    } catch (e) {
      debugPrint('kickUserFromRoom error: $e');
    }
  }

  Future<void> sendSeatInvite(String roomId, {
    required String inviterUid,
    required String inviterName,
    required String targetUid,
    required String targetName,
    required int seatIndex,
  }) async {
    try {
      final msgId = const Uuid().v4();
      final inviteMsg = MessageModel(
        msgId: msgId,
        roomId: roomId,
        senderUid: inviterUid,
        senderName: inviterName,
        senderPhotoUrl: '',
        text: 'دعاك للصعود على المايك',
        type: 'seat_invite',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        giftPayload: {
          'targetUid': targetUid,
          'targetName': targetName,
          'seatIndex': seatIndex,
          'inviterName': inviterName,
          'inviterUid': inviterUid,
        },
      );
      await _db.collection('room_messages').doc(msgId).set(inviteMsg.toMap());
    } catch (e) {
      debugPrint('sendSeatInvite error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // BLOCKS
  // ═══════════════════════════════════════════════════════

  Future<void> blockUser(String blockerUid, String blockedUid) async {
    if (blockerUid == blockedUid) return;
    try {
      await _db.collection('blocks').doc('${blockerUid}_$blockedUid').set({
        'blocker_uid': blockerUid,
        'blocked_uid': blockedUid,
        'created_at': _now(),
      });
    } catch (e) {
      debugPrint('blockUser error: $e');
    }
  }

  Future<void> unblockUser(String blockerUid, String blockedUid) async {
    try {
      await _db.collection('blocks').doc('${blockerUid}_$blockedUid').delete();
    } catch (e) {
      debugPrint('unblockUser error: $e');
    }
  }

  Future<List<String>> getBlockedUids(String uid) async {
    try {
      final snap = await _db.collection('blocks').where('blocker_uid', isEqualTo: uid).get();
      return snap.docs
          .map((e) => e.data()['blocked_uid']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (e) {
      if (e is! FirebaseException || (e.code != 'permission-denied' && e.code != 'unavailable')) {
        debugPrint('getBlockedUids error: $e');
      }
      return [];
    }
  }

  Future<bool> isBlocked(String uid, String targetUid) async {
    if (uid.isEmpty || targetUid.isEmpty) return false;
    try {
      final d1 = await _db.collection('blocks').doc('${uid}_$targetUid').get();
      if (d1.exists) return true;
      final d2 = await _db.collection('blocks').doc('${targetUid}_$uid').get();
      return d2.exists;
    } catch (e) {
      debugPrint('isBlocked error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // GENERIC (for admin / other modules)
  // ═══════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getAllDocs(String collection) async {
    final snap = await _db.collection(collection).get();
    return snap.docs.map((e) {
      final d = Map<String, dynamic>.from(e.data());
      d['id'] = e.id;
      return d;
    }).toList();
  }

  Future<void> setDoc(String collection, String docId, Map<String, dynamic> data) async {
    await _db.collection(collection).doc(docId).set(data, SetOptions(merge: true));
  }

  Future<void> deleteDoc(String collection, String docId) async {
    await _db.collection(collection).doc(docId).delete();
  }

  DateTime _getRankingStartDateUtc(String timeframe) {
    final nowUtc = DateTime.now().toUtc();
    final ksaTime = nowUtc.add(const Duration(hours: 3));

    if (timeframe == 'daily') {
      // يومي: 24 ساعة يبدأ عند منتصف الليل بتوقيت السعودية/مصر (UTC+3)
      return DateTime.utc(ksaTime.year, ksaTime.month, ksaTime.day).subtract(const Duration(hours: 3));
    } else if (timeframe == 'weekly') {
      // أسبوعي: 7 أيام يبدأ من يوم الأحد ويتم تصفيره
      final daysSinceSunday = ksaTime.weekday % 7;
      return DateTime.utc(ksaTime.year, ksaTime.month, ksaTime.day).subtract(Duration(days: daysSinceSunday, hours: 3));
    } else {
      // شهري: يبدأ من يوم 1 إلى يوم 30 أو 31 حسب الشهر ويتم تصفيره
      return DateTime.utc(ksaTime.year, ksaTime.month, 1).subtract(const Duration(hours: 3));
    }
  }

  /// Fetch Top rankings for a room (Wealth = senders, Magic = receivers)
  /// Returns only real room gifts; if empty, returns [] so an empty state is shown.
  Future<List<Map<String, dynamic>>> getRoomRankings({
    required String roomId,
    required bool isWealth,
    required String timeframe,
  }) async {
    final startDateUtc = _getRankingStartDateUtc(timeframe);
    final startStr = startDateUtc.toIso8601String();

    // 1. Fetch from Supabase sent_gifts for real room-specific leaderboard data
    try {
      final gifts = await SupabaseDataService().getSentGifts(roomId, limit: 300);
      if (gifts.isNotEmpty) {
        final Map<String, int> roomTotals = {};
        final Map<String, Map<String, dynamic>> userDetails = {};
        for (final g in gifts) {
          // Check timeframe filter
          if (g.timestamp.isBefore(startDateUtc)) {
            continue;
          }
          final userId = isWealth ? g.senderId : g.receiverId;
          final name = isWealth ? g.senderName : g.receiverName;
          final photo = isWealth ? (g.senderPhotoUrl ?? '') : '';
          if (userId.isEmpty) continue;
          final val = g.totalValue.toInt();
          if (val <= 0) continue;
          roomTotals[userId] = (roomTotals[userId] ?? 0) + val;
          if (!userDetails.containsKey(userId)) {
            userDetails[userId] = {
              'name': name,
              'photo': photo,
            };
          }
        }
        if (roomTotals.isNotEmpty) {
          final sorted = roomTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          final top = sorted.take(20).toList();
          final userMap = await SupabaseDataService().getUsersMap(top.map((e) => e.key).toList());
          return top.map((e) {
            final info = userDetails[e.key] ?? {};
            final u = userMap[e.key];
            final resolvedCustomId = (u?.customId.isNotEmpty ?? false) ? u!.customId : '';
            final displayId = resolvedCustomId.isNotEmpty ? resolvedCustomId : e.key;
            final resolvedName = (u?.name.isNotEmpty ?? false) ? u!.name : (info['name'] ?? 'مستخدم');
            final resolvedPhoto = (u?.photoUrl.isNotEmpty ?? false) ? u!.photoUrl : (info['photo'] ?? '');
            final resolvedLevel = u?.level ?? 1;
            return {
              'uid': e.key,
              'user_id': displayId,
              'id': displayId,
              'custom_id': displayId,
              'display_id': displayId,
              'name': resolvedName,
              'user_name': resolvedName,
              'photoUrl': resolvedPhoto,
              'photo_url': resolvedPhoto,
              'user_photo_url': resolvedPhoto,
              'points': e.value,
              'score': e.value,
              'total_value': e.value,
              'level': resolvedLevel,
              'gender': u?.gender ?? 'male',
            };
          }).toList();
        }
      }
    } catch (_) {}

    // 2. Fetch from Firestore sent_gifts for room-specific gifts
    try {
      final snap = await _db.collection('sent_gifts')
          .where('room_id', isEqualTo: roomId)
          .where('created_at', isGreaterThanOrEqualTo: startStr)
          .get();
      return await _processRankings(snap.docs, isWealth);
    } catch (e) {
      try {
        final snap = await _db.collection('sent_gifts')
            .where('room_id', isEqualTo: roomId)
            .get();
        final filteredDocs = snap.docs.where((doc) {
          final d = doc.data();
          final created = d['created_at'] as String? ?? '';
          return created.compareTo(startStr) >= 0;
        }).toList();
        return await _processRankings(filteredDocs, isWealth);
      } catch (_) {
        return [];
      }
    }
  }

  Future<List<Map<String, dynamic>>> getGlobalRankings({
    required bool isWealth,
    required String timeframe,
  }) async {
    final field = isWealth ? 'total_gifts_sent' : 'total_gifts_received';
    if (timeframe == 'all') {
      final allUsers = await getUserRanking(orderByField: field);
      return allUsers.where((u) => ((u['points'] as num?)?.toInt() ?? (u['score'] as num?)?.toInt() ?? (u[field] as num?)?.toInt() ?? 0) > 0).toList();
    }

    final startDateUtc = _getRankingStartDateUtc(timeframe);

    // 1. Fetch from Supabase sent_gifts for real gifts within timeframe
    try {
      final sbGifts = await SupabaseDataService().getAllSentGifts(limit: 500, after: startDateUtc);
      if (sbGifts.isNotEmpty) {
        final Map<String, int> totals = {};
        for (final g in sbGifts) {
          final userId = isWealth ? g.senderId : g.receiverId;
          if (userId.isEmpty) continue;
          final val = g.totalValue.toInt();
          if (val <= 0) continue;
          totals[userId] = (totals[userId] ?? 0) + val;
        }
        if (totals.isNotEmpty) {
          final sorted = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          final top = sorted.take(50).toList();
          final userMap = await SupabaseDataService().getUsersMap(top.map((e) => e.key).toList());
          return top.map((entry) {
            final u = userMap[entry.key];
            final resolvedCustomId = (u?.customId.isNotEmpty ?? false) ? u!.customId : '';
            final displayId = resolvedCustomId.isNotEmpty ? resolvedCustomId : entry.key;
            final resolvedName = (u?.name.isNotEmpty ?? false) ? u!.name : 'مستخدم';
            final resolvedPhoto = (u?.photoUrl.isNotEmpty ?? false) ? u!.photoUrl : '';
            final resolvedLevel = u?.level ?? 1;
            return {
              'uid': entry.key,
              'id': displayId,
              'custom_id': displayId,
              'user_id': displayId,
              'display_id': displayId,
              'name': resolvedName,
              'photo_url': resolvedPhoto,
              'photoUrl': resolvedPhoto,
              'level': resolvedLevel,
              'points': entry.value,
              'score': entry.value,
              'total_value': entry.value,
              'total_gifts_sent': isWealth ? entry.value : (u?.totalGiftsSent ?? 0),
              'total_gifts_received': !isWealth ? entry.value : (u?.totalGiftsReceived ?? 0),
            };
          }).toList();
        }
      }
    } catch (e) {
      debugPrint('[FirebaseService] getGlobalRankings Supabase sent_gifts error: $e');
    }

    // 2. Fall back to Firestore sent_gifts
    final startStr = startDateUtc.toIso8601String();
    try {
      final snap = await _db.collection('sent_gifts')
          .where('created_at', isGreaterThanOrEqualTo: startStr)
          .get();
      return await _processGlobalRankings(snap.docs, isWealth);
    } catch (e) {
      try {
        final snap = await _db.collection('sent_gifts').get();
        final filteredDocs = snap.docs.where((doc) {
          final d = doc.data();
          final created = d['created_at'] as String? ?? '';
          return created.compareTo(startStr) >= 0;
        }).toList();
        return await _processGlobalRankings(filteredDocs, isWealth);
      } catch (_) {
        return [];
      }
    }
  }

  Future<List<Map<String, dynamic>>> _processGlobalRankings(List<dynamic> docs, bool isWealth) async {
    final Map<String, int> totals = {};
    for (var doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      final userId = isWealth ? d['sender_id'] : d['receiver_id'];
      final value = _asInt(d['value']) * _asInt(d['count']);
      if (userId == null || value <= 0) continue;
      totals[userId] = (totals[userId] ?? 0) + value;
    }

    final entries = totals.entries.where((e) => e.value > 0).toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    final top50 = entries.take(50).toList();

    final List<Map<String, dynamic>> results = [];
    final userMap = await SupabaseDataService().getUsersMap(top50.map((e) => e.key).toList());
    for (var entry in top50) {
      final u = userMap[entry.key];
      final customId = (u?.customId.isNotEmpty ?? false) ? u!.customId : '';
      final displayNumericId = customId.isNotEmpty ? customId : entry.key;
      results.add({
        'uid': entry.key,
        'id': displayNumericId,
        'custom_id': displayNumericId,
        'user_id': displayNumericId,
        'display_id': displayNumericId,
        'name': (u?.name.isNotEmpty ?? false) ? u!.name : 'مستخدم',
        'photo_url': (u?.photoUrl.isNotEmpty ?? false) ? u!.photoUrl : '',
        'photoUrl': (u?.photoUrl.isNotEmpty ?? false) ? u!.photoUrl : '',
        'level': u?.level ?? 1,
        'points': entry.value,
        'score': entry.value,
        'total_value': entry.value,
        'total_gifts_sent': isWealth ? entry.value : (u?.totalGiftsSent ?? 0),
        'total_gifts_received': !isWealth ? entry.value : (u?.totalGiftsReceived ?? 0),
      });
    }

    return results;
  }

  Future<List<Map<String, dynamic>>> _processRankings(List<dynamic> docs, bool isWealth) async {
    final Map<String, int> totals = {};
    for (var doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      final userId = isWealth ? d['sender_id'] : d['receiver_id'];
      final value = _asInt(d['value']) * _asInt(d['count']);
      if (userId == null || value <= 0) continue;
      totals[userId] = (totals[userId] ?? 0) + value;
    }

    final entries = totals.entries.where((e) => e.value > 0).toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    final top10 = entries.take(10).toList();

    final List<Map<String, dynamic>> results = [];
    for (var entry in top10) {
      final userSnap = await _db.collection('users').doc(entry.key).get();
      final ud = userSnap.data() ?? {};
      final customId = (ud['custom_id'] ?? ud['customId'] ?? ud['display_id'] ?? ud['id'] ?? '').toString();
      final displayNumericId = customId.isNotEmpty ? customId : entry.key;
      results.add({
        'user_id': displayNumericId,
        'custom_id': displayNumericId,
        'uid': entry.key,
        'id': entry.key,
        'name': ud['name'] ?? 'مستخدم',
        'user_name': ud['name'] ?? 'مستخدم',
        'photoUrl': (ud['photo_url'] ?? ud['photoUrl'] ?? '').toString(),
        'photo_url': (ud['photo_url'] ?? ud['photoUrl'] ?? '').toString(),
        'user_photo_url': (ud['photo_url'] ?? ud['photoUrl'] ?? '').toString(),
        'total_value': entry.value,
        'points': entry.value,
        'score': entry.value,
        'level': (ud['level'] as num?)?.toInt() ?? 1,
      });
    }

    return results;
  }

  Future<List<Map<String, dynamic>>> getRoomGlobalRanking({
    String timeframe = 'daily',
    int limit = 50,
  }) async {
    try {
      final startDateUtc = _getRankingStartDateUtc(timeframe);
      final startStr = startDateUtc.toIso8601String();
      final Map<String, int> roomGiftsTotal = {};

      // 1. Calculate gift points per room from Supabase sent_gifts within timeframe
      try {
        final sbGifts = await SupabaseDataService().getAllSentGifts(limit: 500, after: startDateUtc);
        for (final g in sbGifts) {
          if (g.roomId.isNotEmpty && g.totalValue > 0) {
            roomGiftsTotal[g.roomId] = (roomGiftsTotal[g.roomId] ?? 0) + g.totalValue.toInt();
          }
        }
      } catch (_) {}

      // 2. Also check Firestore sent_gifts within timeframe
      try {
        final fsGifts = await _db.collection('sent_gifts')
            .where('created_at', isGreaterThanOrEqualTo: startStr)
            .limit(300)
            .get();
        for (final doc in fsGifts.docs) {
          final d = doc.data();
          final rId = (d['room_id'] ?? '').toString();
          if (rId.isNotEmpty) {
            final val = _asInt(d['value']) * _asInt(d['count'] ?? 1);
            if (val > 0) {
              roomGiftsTotal[rId] = (roomGiftsTotal[rId] ?? 0) + val;
            }
          }
        }
      } catch (_) {}

      // If no rooms have received gifts in this timeframe, return empty list
      if (roomGiftsTotal.isEmpty) {
        return [];
      }

      final Map<String, Map<String, dynamic>> roomsMap = {};

      // 3. Fetch rooms from Supabase for only rooms that have points
      try {
        final sbRooms = await SupabaseDataService().getAllRooms();
        for (final data in sbRooms) {
          final roomId = data.roomId;
          if (roomId.isEmpty || !roomGiftsTotal.containsKey(roomId)) continue;
          final totalPts = roomGiftsTotal[roomId] ?? 0;
          if (totalPts <= 0) continue;
          roomsMap[roomId] = {
            'id': roomId,
            'room_id': roomId,
            'custom_id': roomId,
            'display_id': roomId,
            'room_doc_id': roomId,
            'name': data.name.isNotEmpty ? data.name : 'غرفة',
            'photoUrl': data.roomPhotoUrl,
            'photo_url': data.roomPhotoUrl,
            'user_id': roomId,
            'host_name': data.hostName,
            'points': totalPts,
            'score': totalPts,
          };
        }
      } catch (_) {}

      // 4. Fetch missing rooms from Firestore
      for (final entry in roomGiftsTotal.entries) {
        if (!roomsMap.containsKey(entry.key) && entry.value > 0) {
          try {
            final doc = await _db.collection('rooms').doc(entry.key).get();
            if (doc.exists) {
              final data = doc.data() ?? {};
              final photo = (data['room_photo_url'] ?? data['cover_image'] ?? data['photo_url'] ?? data['image'] ?? data['bg_image'] ?? '').toString();
              final name = (data['name'] ?? data['title'] ?? 'غرفة #${entry.key}').toString();
              roomsMap[entry.key] = {
                'id': doc.id,
                'room_id': entry.key,
                'custom_id': entry.key,
                'display_id': entry.key,
                'room_doc_id': doc.id,
                'name': name.isNotEmpty ? name : 'غرفة #${entry.key}',
                'photoUrl': photo,
                'photo_url': photo,
                'user_id': entry.key,
                'host_name': (data['host_name'] ?? '').toString(),
                'points': entry.value,
                'score': entry.value,
              };
            } else {
              roomsMap[entry.key] = {
                'id': entry.key,
                'room_id': entry.key,
                'custom_id': entry.key,
                'display_id': entry.key,
                'room_doc_id': entry.key,
                'name': 'غرفة #${entry.key}',
                'photoUrl': '',
                'photo_url': '',
                'user_id': entry.key,
                'host_name': '',
                'points': entry.value,
                'score': entry.value,
              };
            }
          } catch (_) {
            roomsMap[entry.key] = {
              'id': entry.key,
              'room_id': entry.key,
              'custom_id': entry.key,
              'display_id': entry.key,
              'room_doc_id': entry.key,
              'name': 'غرفة #${entry.key}',
              'photoUrl': '',
              'photo_url': '',
              'user_id': entry.key,
              'host_name': '',
              'points': entry.value,
              'score': entry.value,
            };
          }
        }
      }

      final list = roomsMap.values.where((r) => (r['points'] as int) > 0).toList();
      list.sort((a, b) => (b['points'] as int).compareTo(a['points'] as int));
      return list.take(limit).toList();
    } catch (e) {
      debugPrint('getRoomGlobalRanking error: $e');
      return [];
    }
  }

  Future<bool> toggleSeatLock(String roomId, int seatIndex, bool isLocked) async {
    final ok = await SupabaseDataService().toggleSeatLock(roomId, seatIndex, isLocked);
    try {
      await _db.collection('rooms').doc(roomId).collection('seats').doc(seatIndex.toString()).set({
        'is_locked': isLocked,
      }, SetOptions(merge: true));
    } catch (_) {}
    return ok;
  }

  Future<bool> migrateUserRoomId(String hostUid, String newRoomId) async {
    final ok = await SupabaseDataService().migrateUserRoomId(hostUid, newRoomId);
    try {
      await _db.collection('users').doc(hostUid).set({
        'hosted_room_id': newRoomId,
        'custom_id': newRoomId,
        'customId': newRoomId,
      }, SetOptions(merge: true));
    } catch (_) {}
    return ok;
  }

  Future<List<Map<String, dynamic>>> getTopMonthlyFans(String uid) async {
    try {
      final nowUtc = DateTime.now().toUtc();
      final ksaTime = nowUtc.add(const Duration(hours: 3));
      final startDateUtc = DateTime.utc(ksaTime.year, ksaTime.month, 1).subtract(const Duration(hours: 3));
      final startStr = startDateUtc.toIso8601String();

      final snap = await _db.collection('sent_gifts')
          .where('receiver_id', isEqualTo: uid)
          .where('created_at', isGreaterThanOrEqualTo: startStr)
          .get();

      return _processRankings(snap.docs, false);
    } catch (e) {
      debugPrint('getTopMonthlyFans error: ');
      // Fallback
      try {
        final snap = await _db.collection('sent_gifts')
            .where('receiver_id', isEqualTo: uid)
            .get();
        final nowUtc = DateTime.now().toUtc();
        final ksaTime = nowUtc.add(const Duration(hours: 3));
        final startDateUtc = DateTime.utc(ksaTime.year, ksaTime.month, 1).subtract(const Duration(hours: 3));
        final startStr = startDateUtc.toIso8601String();
        
        final filteredDocs = snap.docs.where((doc) {
          final d = doc.data();
          final created = d['created_at'] as String? ?? '';
          return created.compareTo(startStr) >= 0;
        }).toList();
        return _processRankings(filteredDocs, false);
      } catch (innerE) {
        debugPrint('getTopMonthlyFans fallback error: ');
        return [];
      }
    }
  }

  /// بث المظاريف وأكياس الحظ النشطة داخل الغرفة لحظياً
  Stream<List<Map<String, dynamic>>> activeLuckyBagsStream(String roomId) {
    return _db
        .collection('lucky_bags')
        .where('room_id', isEqualTo: roomId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snap) {
          final now = DateTime.now();
          return snap.docs
              .map((d) => d.data())
              .where((d) {
                final rem = _asInt(d['remaining_value']);
                final expStr = d['expires_at']?.toString();
                final exp = expStr != null ? DateTime.tryParse(expStr) : null;
                final notExpired = exp == null || exp.isAfter(now);
                return rem > 0 && notExpired;
              })
              .toList();
        });
  }

  /// جلب بيانات وكيل المضيفين والمذيعين التابعين للوكالة (Anchor Agent Data)
  Future<Map<String, dynamic>> getAnchorAgencyData({String? agencyId, required String agentUid}) async {
    try {
      // 0. البحث المباشر في Supabase host_agencies و host_agency_members (الأسرع والأدق)
      try {
        final sbAg = await SupabaseDataService().getHostAgencyForUser(agentUid, agencyId: agencyId);
        if (sbAg != null && sbAg['id'] != null) {
          final aid = sbAg['id'].toString();
          return await _buildAgencyDataPayload(aid, sbAg, agentUid);
        }
      } catch (e) {
        debugPrint('[getAnchorAgencyData] supabase check error: $e');
      }

      // 1. البحث عن الوكالة إما بالـ ID أو بالـ Owner UID في Firestore
      if (agencyId != null && agencyId.isNotEmpty) {
        final doc = await _db.collection('host_agencies').doc(agencyId).get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          data['id'] = doc.id;
          return await _buildAgencyDataPayload(doc.id, data, agentUid);
        }
      }
      final agencySnap = await _db.collection('host_agencies').where('owner_id', isEqualTo: agentUid).limit(1).get();
      if (agencySnap.docs.isNotEmpty) {
        final doc = agencySnap.docs.first;
        final data = doc.data() as Map<String, dynamic>? ?? {};
        data['id'] = doc.id;
        return await _buildAgencyDataPayload(doc.id, data, agentUid);
      }

      // 2. البحث عن طريق users/{agentUid}.agency_id
      final userSnap = await _db.collection('users').doc(agentUid).get();
      final userAgencyId = userSnap.data()?['agency_id'] as String?;
      if (userAgencyId != null && userAgencyId.isNotEmpty) {
        final doc = await _db.collection('host_agencies').doc(userAgencyId).get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          data['id'] = doc.id;
          return await _buildAgencyDataPayload(doc.id, data, agentUid);
        }
      }

      // 3. البحث في host_agency_members
      final memberSnap = await _db.collection('host_agency_members').where('user_id', isEqualTo: agentUid).limit(1).get();
      if (memberSnap.docs.isNotEmpty) {
        final aid = memberSnap.docs.first.data()['agency_id'] as String?;
        if (aid != null && aid.isNotEmpty) {
          final doc = await _db.collection('host_agencies').doc(aid).get();
          if (doc.exists) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            data['id'] = doc.id;
            return await _buildAgencyDataPayload(doc.id, data, agentUid);
          }
        }
      }

      // 4. البحث في agency_applications وإنشاء الوكالة تلقائياً إن وجدت
      final appSnap = await _db.collection('agency_applications').where('user_id', isEqualTo: agentUid).limit(1).get();
      if (appSnap.docs.isNotEmpty) {
        final appData = appSnap.docs.first.data();
        final aid = 'agency_$agentUid';
        final newAgency = {
          'id': aid,
          'name': appData['agency_name'] ?? 'وكالة المضيفين',
          'owner_id': agentUid,
          'description': appData['description'] ?? 'وكالة معتمدة',
          'country': appData['country'] ?? 'عالمي',
          'commission_rate': 0.10,
          'tier': 'bronze',
          'is_active': true,
          'member_count': 1,
          'total_diamonds_monthly': 0,
          'created_at': DateTime.now().toIso8601String(),
        };
        await _db.collection('host_agencies').doc(aid).set(newAgency);
        await _db.collection('host_agency_members').doc('${aid}_$agentUid').set({
          'agency_id': aid,
          'user_id': agentUid,
          'role': 'owner',
          'status': 'active',
          'joined_at': DateTime.now().toIso8601String(),
        });
        await _db.collection('users').doc(agentUid).update({'agency_id': aid, 'is_host_agent': true});
        return await _buildAgencyDataPayload(aid, newAgency, agentUid);
      }

      // إذا لم يكن لديه وكالة مسجلة
      return {
        'info': null,
        'anchors': <Map<String, dynamic>>[],
      };
    } catch (e) {
      debugPrint('getAnchorAgencyData error: $e');
      return {
        'info': null,
        'anchors': <Map<String, dynamic>>[],
      };
    }
  }

  Future<Map<String, dynamic>> _buildAgencyDataPayload(String agencyDocId, Map<String, dynamic> agencyData, String agentUid) async {
    // جلب بيانات الأعضاء والمضيفين
    final membersSnap = await _db
        .collection('host_agency_members')
        .where('agency_id', isEqualTo: agencyDocId)
        .get();

    final anchors = <Map<String, dynamic>>[];
    int totalDiamonds = 0;

    for (final mDoc in membersSnap.docs) {
      final mData = mDoc.data() as Map<String, dynamic>? ?? {};
      final st = mData['status']?.toString();
      if (st == 'pending' || st == 'rejected' || st == 'kicked' || st == 'left') continue;

      final mUid = mData['user_id']?.toString() ?? mDoc.id;
      final uSnap = await _db.collection('users').doc(mUid).get();
      final uData = uSnap.exists ? ((uSnap.data() as Map<String, dynamic>?) ?? {}) : {};

      final d1 = _asInt(mData['diamonds']);
      final d2 = _asInt(mData['diamonds_earned_monthly']);
      final d3 = _asInt(mData['diamonds_balance']);
      final mDiamonds = [d1, d2, d3].reduce((curr, next) => curr > next ? curr : next);
      final uDiamonds = _asInt(uData['diamonds']);
      final int diamonds = mDiamonds > uDiamonds ? mDiamonds : uDiamonds;
      totalDiamonds += diamonds;

      anchors.add({
        'user_id': _asInt(uData['custom_id'] ?? mData['user_id'] ?? 0),
        'user_no': _asInt(uData['custom_id'] ?? 0),
        'uid': mUid,
        'role': mData['role']?.toString() ?? 'host',
        'nickname': uData['name'] ?? mData['user_name'] ?? 'مضيف',
        'headImage': uData['photo_url'] ?? uData['avatar'] ?? '',
        'country': _asInt(uData['country'] ?? 0),
        'country_flag_url': uData['country_flag_url'] ?? '',
        'days': _asInt(mData['active_days'] ?? mData['days'] ?? 1),
        'minute': (mData['on_mic_minutes'] as num?)?.toDouble() ?? (mData['minute'] as num?)?.toDouble() ?? 120.0,
        'diamonds': diamonds.toString(),
        'experience': _asInt(uData['wealth_xp'] ?? 0),
        'level': _asInt(uData['level'] ?? 1),
        'recg_level': _asInt(uData['wealth_level'] ?? 0),
        'recharge_value': _asInt(uData['recharge_coins'] ?? 0),
        'sex': _asInt(uData['gender'] ?? 1),
        'vip': _asInt(uData['vip_level'] ?? 0),
        'target_diamonds': _asInt(mData['target_diamonds'] ?? 100000),
      });
    }

    final agentUserSnap = await _db.collection('users').doc(agentUid).get();
    final agentUserData = agentUserSnap.exists ? ((agentUserSnap.data() as Map<String, dynamic>?) ?? {}) : {};

    // جلب مراحل وتارجت الوكالة من host_milestones
    final milestonesSnap = await _db.collection('host_milestones')
        .where('is_active', isEqualTo: true)
        .get();

    final milestonesList = <Map<String, dynamic>>[];
    for (final mDoc in milestonesSnap.docs) {
      final md = mDoc.data();
      md['id'] = mDoc.id;
      milestonesList.add(md);
    }
    // Sort milestones by target_diamonds ascending
    milestonesList.sort((a, b) {
      final ta = (a['target_diamonds'] as num?)?.toInt() ?? 0;
      final tb = (b['target_diamonds'] as num?)?.toInt() ?? 0;
      return ta.compareTo(tb);
    });

    // Find current or next milestone
    Map<String, dynamic>? activeMilestone;
    for (final m in milestonesList) {
      final td = (m['target_diamonds'] as num?)?.toInt() ?? 0;
      if (totalDiamonds < td) {
        activeMilestone = m;
        break;
      }
    }
    if (activeMilestone == null && milestonesList.isNotEmpty) {
      activeMilestone = milestonesList.last;
    }

    final targetDiamonds = (activeMilestone?['target_diamonds'] as num?)?.toInt() ?? 1000000;
    final commissionRate = (agencyData['commission_rate'] as num?)?.toDouble() ??
        (activeMilestone?['agent_commission_rate'] as num?)?.toDouble() ?? 0.10;
    final salaryUsd = (activeMilestone?['reward_value'] as num?)?.toDouble() ?? 0.0;
    final rewardType = activeMilestone?['reward_type']?.toString() ?? 'salary_usd';
    final rewardValue = (activeMilestone?['reward_value'] as num?)?.toDouble() ?? 0.0;
    final periodType = activeMilestone?['period_type']?.toString() ?? 'monthly';
    final notice = agencyData['notice']?.toString() ?? agencyData['description']?.toString() ?? 'أهلاً بكم في الوكالة الرسمية!';
    final tier = agencyData['tier']?.toString() ?? 'bronze';

    return {
      'info': {
        'user_id': _asInt(agentUserData['custom_id'] ?? 0),
        'agency_id': agencyDocId,
        'agency_name': agencyData['name'] ?? 'وكالة النجوم المعتمدة',
        'avatar_url': agentUserData['photo_url'] ?? '',
        'country_flag_url': agentUserData['country_flag_url'] ?? '',
        'agent_bean': _asInt(agentUserData['coins'] ?? 0),
        'transfer_money': totalDiamonds,
        'transfer_dollar': (totalDiamonds / 1000).toInt(),
        'transfer_number': membersSnap.docs.length,
        'commission_rate': commissionRate,
        'tier': tier,
        'notice': notice,
        'target_diamonds': targetDiamonds,
        'salary_usd': salaryUsd,
        'reward_type': rewardType,
        'reward_value': rewardValue,
        'period_type': periodType,
        'milestones': milestonesList,
      },
      'anchors': anchors,
    };
  }

  /// تحديث إعلان الوكالة
  Future<bool> updateAgencyNotice({required String agencyId, required String notice}) async {
    try {
      await _db.collection('host_agencies').doc(agencyId).update({
        'notice': notice,
        'description': notice,
        'updated_at': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('updateAgencyNotice error: $e');
      return false;
    }
  }

  /// إزالة عضو من الوكالة
  Future<bool> removeAgencyMember({required String agencyId, required String memberUid}) async {
    try {
      // Find member doc in host_agency_members
      final snap = await _db.collection('host_agency_members')
          .where('agency_id', isEqualTo: agencyId)
          .where('user_id', isEqualTo: memberUid)
          .get();
      for (final d in snap.docs) {
        await d.reference.delete();
      }
      // Clear agency_id on user doc
      await _db.collection('users').doc(memberUid).update({
        'agency_id': FieldValue.delete(),
        'agency_name': FieldValue.delete(),
        'host_agency_id': FieldValue.delete(),
        'host_agency_name': FieldValue.delete(),
        'is_agency_member': false,
        'agency_status': FieldValue.delete(),
        'agency_role': FieldValue.delete(),
      });
      // Delete achieved milestones/targets for this user in this agency
      final achSnap = await _db.collection('agency_achieved_targets')
          .where('agency_id', isEqualTo: agencyId)
          .where('user_id', isEqualTo: memberUid)
          .get();
      for (final doc in achSnap.docs) {
        await doc.reference.delete();
      }
      // Decrement member count
      await _db.collection('host_agencies').doc(agencyId).update({
        'member_count': FieldValue.increment(-1),
      });
      return true;
    } catch (e) {
      debugPrint('removeAgencyMember error: $e');
      return false;
    }
  }

  /// خروج العضو (المضيف) من الوكالة وتصفير مراحله وإلغاء ارتباطه بالوكالة
  Future<bool> exitAgencyAsMember({required String agencyId, required String userId}) async {
    try {
      String resolvedAgencyId = agencyId;
      if (resolvedAgencyId.isEmpty) {
        final userDoc = await _db.collection('users').doc(userId).get();
        resolvedAgencyId = userDoc.data()?['agency_id']?.toString() ??
            userDoc.data()?['host_agency_id']?.toString() ?? '';
      }

      // 1. حذف العضو من host_agency_members
      final memberSnap = await _db.collection('host_agency_members')
          .where('user_id', isEqualTo: userId)
          .get();
      for (final doc in memberSnap.docs) {
        await doc.reference.delete();
      }

      // 2. حذف مراحل وأهداف التارجت المحققة الخاصة بالعضو في الوكالة
      final achSnap = await _db.collection('agency_achieved_targets')
          .where('user_id', isEqualTo: userId)
          .get();
      for (final doc in achSnap.docs) {
        await doc.reference.delete();
      }

      // 3. مسح بيانات الوكالة من وثيقة المستخدم في users
      await _db.collection('users').doc(userId).update({
        'agency_id': FieldValue.delete(),
        'agency_name': FieldValue.delete(),
        'host_agency_id': FieldValue.delete(),
        'host_agency_name': FieldValue.delete(),
        'is_agency_member': false,
        'agency_status': FieldValue.delete(),
        'agency_role': FieldValue.delete(),
        'agency_joined_at': FieldValue.delete(),
        'agency_agent_id': FieldValue.delete(),
      });

      // 4. تقليل عدد أعضاء الوكالة
      if (resolvedAgencyId.isNotEmpty) {
        try {
          await _db.collection('host_agencies').doc(resolvedAgencyId).update({
            'member_count': FieldValue.increment(-1),
          });
        } catch (_) {}
      }

      // 5. منح وضع وكيل حر لمدة 7 أيام
      final freeUntil = DateTime.now().toUtc().add(const Duration(days: 7));
      await _db.collection('agency_free_agents').doc(userId).set({
        'user_id': userId,
        'free_until': freeUntil.toIso8601String(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      return true;
    } catch (e) {
      debugPrint('exitAgencyAsMember error: $e');
      return false;
    }
  }

  /// خروج الوكيل وحذف الوكالة نهائياً وتصفير مراحل جميع المستخدمين وفك ارتباطهم
  Future<bool> deleteAndExitAgencyByOwner({required String agencyId, required String ownerUid}) async {
    try {
      String resolvedAgencyId = agencyId;
      if (resolvedAgencyId.isEmpty) {
        final agSnap = await _db.collection('host_agencies').where('owner_id', isEqualTo: ownerUid).limit(1).get();
        if (agSnap.docs.isNotEmpty) {
          resolvedAgencyId = agSnap.docs.first.id;
        } else {
          final uDoc = await _db.collection('users').doc(ownerUid).get();
          resolvedAgencyId = uDoc.data()?['agency_id']?.toString() ??
              uDoc.data()?['host_agency_id']?.toString() ?? '';
        }
      }

      // 1. حصر جميع معرفات الأعضاء التابعين للوكالة
      final memberUids = <String>{ownerUid};

      if (resolvedAgencyId.isNotEmpty) {
        // أ) من host_agency_members
        final mSnap = await _db.collection('host_agency_members')
            .where('agency_id', isEqualTo: resolvedAgencyId)
            .get();
        for (final d in mSnap.docs) {
          final u = d.data()['user_id']?.toString();
          if (u != null && u.isNotEmpty) memberUids.add(u);
        }

        // ب) من users حيث agency_id
        final uSnap1 = await _db.collection('users')
            .where('agency_id', isEqualTo: resolvedAgencyId)
            .get();
        for (final d in uSnap1.docs) {
          memberUids.add(d.id);
        }

        // ج) من users حيث host_agency_id
        final uSnap2 = await _db.collection('users')
            .where('host_agency_id', isEqualTo: resolvedAgencyId)
            .get();
        for (final d in uSnap2.docs) {
          memberUids.add(d.id);
        }
      }

      // 2. تحديث كل مستخدم: فك ارتباط الوكالة، وحذف مراحل التارجت، ومنحه وضع وكيل حر
      for (final uid in memberUids) {
        try {
          await _db.collection('users').doc(uid).update({
            'agency_id': FieldValue.delete(),
            'agency_name': FieldValue.delete(),
            'host_agency_id': FieldValue.delete(),
            'host_agency_name': FieldValue.delete(),
            'is_host_agent': false,
            'is_agency_member': false,
            'agency_status': FieldValue.delete(),
            'agency_role': FieldValue.delete(),
            'agency_joined_at': FieldValue.delete(),
            'agency_agent_id': FieldValue.delete(),
          });
        } catch (e) {
          debugPrint('Error updating user $uid on agency delete: $e');
        }

        // حذف مراحل وتارجت هذا العضو من agency_achieved_targets
        try {
          final achSnap = await _db.collection('agency_achieved_targets')
              .where('user_id', isEqualTo: uid)
              .get();
          for (final doc in achSnap.docs) {
            await doc.reference.delete();
          }
        } catch (e) {
          debugPrint('Error deleting achieved targets for user $uid: $e');
        }

        // حذف عضويته من host_agency_members
        try {
          final mbSnap = await _db.collection('host_agency_members')
              .where('user_id', isEqualTo: uid)
              .get();
          for (final doc in mbSnap.docs) {
            await doc.reference.delete();
          }
        } catch (e) {
          debugPrint('Error deleting membership doc for user $uid: $e');
        }

        // منح وضع وكيل حر
        try {
          final freeUntil = DateTime.now().toUtc().add(const Duration(days: 7));
          await _db.collection('agency_free_agents').doc(uid).set({
            'user_id': uid,
            'free_until': freeUntil.toIso8601String(),
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        } catch (_) {}
      }

      // 3. حذف أهداف ومراحل الوكالة بالكامل من agency_achieved_targets
      if (resolvedAgencyId.isNotEmpty) {
        try {
          final agAchSnap = await _db.collection('agency_achieved_targets')
              .where('agency_id', isEqualTo: resolvedAgencyId)
              .get();
          for (final doc in agAchSnap.docs) {
            await doc.reference.delete();
          }
        } catch (e) {
          debugPrint('Error deleting agency achieved targets: $e');
        }

        // 4. حذف سجلات host_agency_members المتبقية للوكالة
        try {
          final allMb = await _db.collection('host_agency_members')
              .where('agency_id', isEqualTo: resolvedAgencyId)
              .get();
          for (final doc in allMb.docs) {
            await doc.reference.delete();
          }
        } catch (e) {
          debugPrint('Error deleting all agency members: $e');
        }

        // 5. حذف وثيقة الوكالة من host_agencies
        try {
          await _db.collection('host_agencies').doc(resolvedAgencyId).delete();
        } catch (e) {
          debugPrint('Error deleting host_agencies doc: $e');
        }

        // 6. حذف محفظة الوكالة
        try {
          await _db.collection('agency_wallets').doc(resolvedAgencyId).delete();
        } catch (_) {}

        // 7. حذف طلبات الانضمام والدعوات
        try {
          final reqSnap = await _db.collection('agency_join_requests')
              .where('agency_id', isEqualTo: resolvedAgencyId)
              .get();
          for (final doc in reqSnap.docs) {
            await doc.reference.delete();
          }
        } catch (_) {}

        // 8. حذف رسائل شات الوكالة
        try {
          final chatSnap = await _db.collection('agency_chat_messages')
              .where('agency_id', isEqualTo: resolvedAgencyId)
              .get();
          for (final doc in chatSnap.docs) {
            await doc.reference.delete();
          }
        } catch (_) {}

        // 9. حذف طلبات إنشاء الوكالة التابعة لنفس الوكالة حتى لا تعيد إنشاءها
        try {
          final appSnap = await _db.collection('agency_applications')
              .where('agency_id', isEqualTo: resolvedAgencyId)
              .get();
          for (final doc in appSnap.docs) {
            await doc.reference.delete();
          }
        } catch (_) {}
      }

      // 10. حذف طلبات إنشاء الوكالة الخاصة بالوكيل (user_id == ownerUid)
      try {
        final appSnap2 = await _db.collection('agency_applications')
            .where('user_id', isEqualTo: ownerUid)
            .get();
        for (final doc in appSnap2.docs) {
          await doc.reference.delete();
        }
      } catch (_) {}

      // 11. حذف أي وكالة متبقية بالـ owner_id
      try {
        final ownerAgencies = await _db.collection('host_agencies')
            .where('owner_id', isEqualTo: ownerUid)
            .get();
        for (final doc in ownerAgencies.docs) {
          await doc.reference.delete();
        }
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint('deleteAndExitAgencyByOwner error: $e');
      return false;
    }
  }

  /// ترقية أو تنزيل رتبة العضو في الوكالة (مشرف / مضيف)
  Future<bool> updateAgencyMemberRole({required String agencyId, required String memberUid, required String newRole}) async {
    try {
      final snap = await _db.collection('host_agency_members')
          .where('agency_id', isEqualTo: agencyId)
          .where('user_id', isEqualTo: memberUid)
          .get();
      for (final d in snap.docs) {
        await d.reference.update({'role': newRole});
      }
      return true;
    } catch (e) {
      debugPrint('updateAgencyMemberRole error: $e');
      return false;
    }
  }

  /// تحويل كوينز من الوكيل إلى أحد مضيفي الوكالة (Agent Coin Transfer)
  Future<bool> transferCoinsToMember({
    required String agentUid,
    required String targetUserNoOrId,
    required int coinsAmount,
  }) async {
    try {
      final agentRef = _db.collection('users').doc(agentUid);
      
      // البحث عن المضيف بالـ customId أو بالـ UID
      final targetSnap = await _db.collection('users').where('custom_id', isEqualTo: targetUserNoOrId).limit(1).get();
      DocumentReference targetRef;
      if (targetSnap.docs.isNotEmpty) {
        targetRef = targetSnap.docs.first.reference;
      } else {
        final byIdDoc = await _db.collection('users').doc(targetUserNoOrId).get();
        if (byIdDoc.exists) {
          targetRef = byIdDoc.reference;
        } else {
          return false;
        }
      }

      return await _db.runTransaction((txn) async {
        final agentDoc = await txn.get(agentRef);
        final targetDoc = await txn.get(targetRef);

        if (!agentDoc.exists || !targetDoc.exists) return false;

        final agentData = agentDoc.data() as Map<String, dynamic>?;
        final targetData = targetDoc.data() as Map<String, dynamic>?;

        final agentCoins = _asInt(agentData?['coins'] ?? 0);
        if (agentCoins < coinsAmount) return false;

        final targetCoins = _asInt(targetData?['coins'] ?? 0);

        txn.update(agentRef, {'coins': agentCoins - coinsAmount});
        txn.update(targetRef, {
          'coins': targetCoins + coinsAmount,
          'recharged_coins': FieldValue.increment(coinsAmount),
          'total_recharge': FieldValue.increment(coinsAmount),
        });

        // تحديث تقدم حدث الشحن للمستخدم المستلم
        final now = DateTime.now();
        final eventId = 'recharge_${now.year}_${now.month.toString().padLeft(2, '0')}';
        final progressRef = _db.collection('recharge_event_progress').doc('${eventId}_${targetRef.id}');
        txn.set(progressRef, {
          'event_id': eventId,
          'user_id': targetRef.id,
          'total_recharged_coins': FieldValue.increment(coinsAmount),
          'updated_at': now.toIso8601String(),
        }, SetOptions(merge: true));

        // تسجيل العملية في السجلات المالية
        final transferRef = _db.collection('agency_transfers').doc();
        txn.set(transferRef, {
          'agent_id': agentUid,
          'target_id': targetRef.id,
          'target_custom_id': targetUserNoOrId,
          'amount': coinsAmount,
          'created_at': FieldValue.serverTimestamp(),
          'status': 'completed',
        });

        return true;
      });
    } catch (e) {
      debugPrint('transferCoinsToMember error: $e');
      return false;
    }
  }

  /// إنشاء طلب سحب ألماس الراتب من مستخدم بواسطة وكيل شحن
  Future<Map<String, dynamic>> createAgentDiamondWithdrawalRequest({
    required String agentUid,
    required String targetUid,
    required int diamondsAmount,
  }) async {
    try {
      if (diamondsAmount <= 0) {
        return {'success': false, 'message': 'يرجى إدخال كمية ألماس صحيحة أكبر من 0'};
      }

      // جلب بيانات الوكيل والمستهدف من Supabase أولاً كمصدر أساسي
      final sbData = SupabaseDataService();
      var sbAgent = await sbData.getUser(agentUid);
      var sbTarget = await sbData.getUser(targetUid);

      // إذا لم يتم العثور على المستخدم بالـ UID، نفحص إذا كان المدخل هو المعرف الرقمي (custom_id)
      if (sbTarget == null) {
        try {
          final usersByCustomId = await sbData.getUsersByCustomId(targetUid);
          if (usersByCustomId.isNotEmpty) {
            sbTarget = usersByCustomId.first;
          }
        } catch (_) {}
      }

      // محاولة فحص Firestore أيضاً بشكل احتياطي دون أن يتسبب خطأ الصلاحيات في فشل العملية
      Map<String, dynamic>? fsAgentData;
      Map<String, dynamic>? fsTargetData;
      try {
        if (FirebaseAuth.instance.currentUser == null) {
          await FirebaseAuth.instance.signInAnonymously();
        }
        final aDoc = await _db.collection('users').doc(agentUid).get();
        if (aDoc.exists) fsAgentData = aDoc.data();
      } catch (_) {}

      try {
        final tDoc = await _db.collection('users').doc(targetUid).get();
        if (tDoc.exists) fsTargetData = tDoc.data();
      } catch (_) {}

      if (sbAgent == null && fsAgentData == null) {
        return {'success': false, 'message': 'بيانات وكيل الشحن غير موجودة'};
      }
      if (sbTarget == null && fsTargetData == null) {
        return {'success': false, 'message': 'لم يتم العثور على حساب المستخدم'};
      }

      final resolvedTargetUid = sbTarget?.uid ?? targetUid;
      final targetDiamonds = math.max(
        sbTarget?.diamonds ?? 0,
        _asInt(fsTargetData?['diamonds'] ?? 0),
      );

      if (targetDiamonds < diamondsAmount) {
        return {
          'success': false,
          'message': 'رصيد المستخدم غير كافٍ. الألماس المتاح لديه: $targetDiamonds ماسة'
        };
      }

      final agentName = (sbAgent != null && sbAgent.name.trim().isNotEmpty)
          ? sbAgent.name
          : (fsAgentData?['name'] ?? fsAgentData?['display_name'] ?? 'وكيل الشحن').toString();

      final targetName = (sbTarget != null && sbTarget.name.trim().isNotEmpty)
          ? sbTarget.name
          : (fsTargetData?['name'] ?? fsTargetData?['display_name'] ?? 'المستخدم').toString();

      final targetCustomId = (sbTarget != null && sbTarget.customId.trim().isNotEmpty)
          ? sbTarget.customId
          : (fsTargetData?['custom_id'] ?? '').toString();

      final requestId = 'wd_${DateTime.now().millisecondsSinceEpoch}_$resolvedTargetUid';
      final now = DateTime.now().toUtc();

      // حفظ الطلب في Firestore احتياطياً داخل try/catch لتجنب مشكلة permission-denied
      try {
        await _db.collection('agent_withdrawal_requests').doc(requestId).set({
          'request_id': requestId,
          'agent_id': agentUid,
          'agent_name': agentName,
          'target_uid': resolvedTargetUid,
          'target_name': targetName,
          'target_custom_id': targetCustomId,
          'diamonds_amount': diamondsAmount,
          'status': 'pending',
          'created_at': now.toIso8601String(),
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (fsErr) {
        debugPrint('[createAgentDiamondWithdrawalRequest] Firestore save skipped: $fsErr');
      }

      // إرسال إشعار فوري للمستخدم للموافقة أو الرفض عبر Supabase و Firebase
      await sendNotification(
        uid: resolvedTargetUid,
        type: 'agent_withdrawal_request',
        title: 'طلب سحب راتب 💎',
        body: 'يطلب وكيل الشحن ($agentName) سحب $diamondsAmount ماسة من رصيد ألماسك كراتب. هل توافق على السحب؟',
        data: {
          'action': 'agent_withdrawal_request',
          'request_id': requestId,
          'agent_id': agentUid,
          'agent_name': agentName,
          'diamonds_amount': diamondsAmount,
        },
      );

      return {'success': true, 'request_id': requestId};
    } catch (e) {
      debugPrint('createAgentDiamondWithdrawalRequest error: $e');
      return {'success': false, 'message': 'حدث خطأ أثناء إرسال طلب السحب: $e'};
    }
  }

  /// معالجة رد المستخدم (الموافقة أو الرفض) على طلب سحب الألماس
  Future<Map<String, dynamic>> respondToAgentWithdrawalRequest({
    required String requestId,
    required String userUid,
    required bool approved,
    String? agentId,
    int? diamondsAmount,
    String? targetName,
  }) async {
    try {
      Map<String, dynamic>? reqData;
      try {
        if (FirebaseAuth.instance.currentUser == null) {
          await FirebaseAuth.instance.signInAnonymously();
        }
        final reqSnap = await _db.collection('agent_withdrawal_requests').doc(requestId).get();
        if (reqSnap.exists) {
          reqData = reqSnap.data();
        }
      } catch (_) {}

      final resolvedAgentId = (reqData?['agent_id'] ?? agentId ?? '').toString();
      final resolvedDiamonds = _asInt(reqData?['diamonds_amount'] ?? diamondsAmount ?? 0);
      final resolvedTargetName = (reqData?['target_name'] ?? targetName ?? 'المستخدم').toString();

      if (!approved) {
        // رفض الطلب: لا يتم خصم أي ماسة
        try {
          await _db.collection('agent_withdrawal_requests').doc(requestId).update({
            'status': 'rejected',
            'rejected_at': DateTime.now().toUtc().toIso8601String(),
          });
        } catch (_) {}

        // إشعار الوكيل بالرفض
        if (resolvedAgentId.isNotEmpty) {
          await sendNotification(
            uid: resolvedAgentId,
            type: 'agent_withdrawal_rejected',
            title: 'تم رفض طلب السحب ❌',
            body: 'قام المستخدم $resolvedTargetName برفض طلب سحب $resolvedDiamonds ماسة.',
            data: {
              'request_id': requestId,
              'target_uid': userUid,
              'diamonds_amount': resolvedDiamonds,
            },
          );
        }

        return {'success': true, 'action': 'rejected'};
      }

      // موافقة المستخدم: فحص الرصيد والخصم في Supabase كأصل رئيسي
      final sbData = SupabaseDataService();
      final sbTarget = await sbData.getUser(userUid);
      final currentDiamonds = sbTarget?.diamonds ?? 0;

      if (currentDiamonds < resolvedDiamonds) {
        return {
          'success': false,
          'message': 'رصيد الألماس لديك غير كافٍ لإتمام السحب (المتاح: $currentDiamonds ماسة)'
        };
      }

      // 1. خصم الألماس من المستخدم في Supabase
      final newTargetDiamonds = math.max(0, currentDiamonds - resolvedDiamonds);
      await sbData.updateUser(userUid, {'diamonds': newTargetDiamonds});

      // 2. إضافة الألماس لحساب الوكيل في Supabase
      if (resolvedAgentId.isNotEmpty) {
        final sbAgent = await sbData.getUser(resolvedAgentId);
        if (sbAgent != null) {
          final newAgentDiamonds = sbAgent.diamonds + resolvedDiamonds;
          await sbData.updateUser(resolvedAgentId, {'diamonds': newAgentDiamonds});
        }
      }

      // 3. مزامنة Firestore أيضاً إن أمكن
      try {
        await _db.collection('agent_withdrawal_requests').doc(requestId).update({
          'status': 'approved',
          'approved_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (_) {}

      try {
        await _db.collection('users').doc(userUid).update({
          'diamonds': FieldValue.increment(-resolvedDiamonds),
          'total_diamonds_withdrawn': FieldValue.increment(resolvedDiamonds),
        });
      } catch (_) {}

      try {
        if (resolvedAgentId.isNotEmpty) {
          await _db.collection('users').doc(resolvedAgentId).update({
            'diamonds': FieldValue.increment(resolvedDiamonds),
          });

          await _db.collection('agent_usd_wallets').doc(resolvedAgentId).set({
            'user_id': resolvedAgentId,
            'diamond_balance': FieldValue.increment(resolvedDiamonds),
            'total_received': FieldValue.increment(resolvedDiamonds),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, SetOptions(merge: true));

          await _db.collection('agent_recharge_transactions').add({
            'agent_id': resolvedAgentId,
            'type': 'withdraw_diamonds',
            'recipient_uid': userUid,
            'recipient_display_name': resolvedTargetName,
            'diamonds_amount': resolvedDiamonds,
            'status': 'completed',
            'request_id': requestId,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      } catch (_) {}

      // 4. إشعار الوكيل بنجاح العملية
      if (resolvedAgentId.isNotEmpty) {
        await sendNotification(
          uid: resolvedAgentId,
          type: 'agent_withdrawal_approved',
          title: 'تمت الموافقة على سحب الألماس ✅',
          body: 'وافق المستخدم $resolvedTargetName على طلب سحب $resolvedDiamonds ماسة، وتم تحويلها لمحفظتك بنجاح.',
          data: {
            'request_id': requestId,
            'target_uid': userUid,
            'diamonds_amount': resolvedDiamonds,
          },
        );
      }

      return {'success': true, 'action': 'approved'};
    } catch (e) {
      debugPrint('respondToAgentWithdrawalRequest error: $e');
      return {'success': false, 'message': 'حدث خطأ أثناء معالجة الطلب: $e'};
    }
  }
}



