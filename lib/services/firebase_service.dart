import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
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
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  void init() {}

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
    final roomId = hostCustomId;
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
    await _db.collection('rooms').doc(roomId).set(room.toMap(), SetOptions(merge: true));
    try {
      await _db.collection('users').doc(hostUid).set({'hosted_room_id': roomId}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('createRoom: users.update failed: $e');
      rethrow;
    }
    return roomId;
  }

  Future<void> followRoom(String uid, String roomId) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return;
    final d = doc.data() ?? {};
    final followed = List<String>.from(d['followed_rooms'] ?? []);
    if (!followed.contains(roomId)) {
      followed.add(roomId);
      await _db.collection('users').doc(uid).update({'followed_rooms': followed});
    }
  }

  Future<void> unfollowRoom(String uid, String roomId) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return;
    final d = doc.data() ?? {};
    final followed = List<String>.from(d['followed_rooms'] ?? []);
    if (followed.contains(roomId)) {
      followed.remove(roomId);
      await _db.collection('users').doc(uid).update({'followed_rooms': followed});
    }
  }

  Stream<RoomModel?> roomStream(String roomId) {
    return _db.collection('rooms').doc(roomId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return RoomModel.fromMap(_data(snap));
    });
  }

  Future<List<RoomModel>> getAllRooms() async {
    final snap = await _db.collection('rooms').get();
    final rooms = snap.docs.map((e) => RoomModel.fromMap(_data(e))).toList();
    rooms.sort((a, b) => b.totalGifts.compareTo(a.totalGifts));
    return rooms;
  }

  Stream<List<RoomModel>> allRoomsStream() {
    return _db.collection('rooms').snapshots().map((snap) {
      final rooms = snap.docs.map((e) => RoomModel.fromMap(_data(e))).toList();
      rooms.sort((a, b) => b.totalGifts.compareTo(a.totalGifts));
      return rooms;
    });
  }

  Future<void> updateRoomMemberCount(String roomId, int count) async {
    await _db.collection('rooms').doc(roomId).update({'member_count': count});
  }

  Future<void> updateRoomName(String roomId, String name) async {
    await _db.collection('rooms').doc(roomId).update({'name': name});
  }

  Future<void> updateRoomSeatStyle(String roomId, int seatStyleIndex) async {
    await _db.collection('rooms').doc(roomId).update({'seat_style': seatStyleIndex});
  }

  Future<void> updateRoomSeatCount(String roomId, int count) async {
    await _db.collection('rooms').doc(roomId).update({'seat_count': count});
  }

  Future<void> updateRoomSeatColor(String roomId, int seatColorIndex) async {
    await _db.collection('rooms').doc(roomId).update({'seat_color': seatColorIndex});
  }

  Future<void> updateRoomBackground(String roomId, String bgUrl) async {
    await _db.collection('rooms').doc(roomId).update({'bgImage': bgUrl});
  }

  Future<RoomModel?> getRoom(String roomId) async {
    final doc = await _db.collection('rooms').doc(roomId).get();
    if (!doc.exists) return null;
    return RoomModel.fromMap(_data(doc));
  }

  Future<void> updateRoom(String roomId, Map<String, dynamic> updates) async {
    await _db.collection('rooms').doc(roomId).update(updates);
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
    await _db.collection('room_members').doc('${roomId}_${user.uid}').set({
      'room_id': roomId,
      'uid': user.uid,
      'name': user.name,
      'photo_url': user.photoUrl,
      'role': 'member',
      'joined_at': _now(),
    });
  }

  Future<void> leaveRoom(String roomId, String uid) async {
    await _db.collection('room_members').doc('${roomId}_$uid').delete();
  }

  Stream<List<UserModel>> roomMembersStream(String roomId) {
    return _db
        .collection('room_members')
        .where('room_id', isEqualTo: roomId)
        .snapshots()
        .map((snap) => snap.docs.map((e) => UserModel.fromMap(_data(e))).toList());
  }

  // ═══════════════════════════════════════════════════════
  // SEATS
  // ═══════════════════════════════════════════════════════

  Future<bool> takeSeat(String roomId, int seatIndex, UserModel user) async {
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
      'is_muted': false,
      'taken_at': _now(),
    };
    try {
      await _db.runTransaction((txn) async {
        final existing = await txn.get(ref);
        if (existing.exists && (existing.data()?['uid'] != user.uid)) {
          throw Exception('seat taken');
        }
        txn.set(ref, seatData);
      });
      return true;
    } catch (e) {
      if (e.toString().contains('seat taken')) return false;
      debugPrint('takeSeat transaction error, using direct set fallback: $e');
      try {
        final snap = await ref.get();
        if (snap.exists && (snap.data()?['uid'] != user.uid)) {
          return false;
        }
        await ref.set(seatData);
        return true;
      } catch (err) {
        debugPrint('takeSeat direct fallback error: $err');
        return false;
      }
    }
  }

  Future<void> leaveSeat(String roomId, int seatIndex) async {
    await _db.collection('room_seats').doc('${roomId}_$seatIndex').delete();
  }

  Future<void> leaveSeatForUser(String roomId, String uid) async {
    try {
      final snap = await _db
          .collection('room_seats')
          .where('room_id', isEqualTo: roomId)
          .where('uid', isEqualTo: uid)
          .get();
      for (final doc in snap.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('leaveSeatForUser error: $e');
    }
  }

  Future<void> toggleMute(String roomId, int seatIndex, bool muted) async {
    try {
      final ref = _db.collection('room_seats').doc('${roomId}_$seatIndex');
      final snap = await ref.get();
      if (snap.exists) {
        await ref.update({'is_muted': muted});
      }
    } catch (e) {
      debugPrint('toggleMute error: $e');
    }
  }

  Stream<Map<int, Map<String, dynamic>>> seatsStream(String roomId) {
    return _db
        .collection('room_seats')
        .where('room_id', isEqualTo: roomId)
        .snapshots()
        .map((snap) {
      final map = <int, Map<String, dynamic>>{};
      for (final e in snap.docs) {
        final d = Map<String, dynamic>.from(e.data());
        map[(d['seat_index'] as int?) ?? 0] = d;
      }
      return map;
    });
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
    await _db.collection('room_messages').doc(msgId).set(msg.toMap());
  }

  Stream<List<MessageModel>> messagesStream(String roomId, {String? since}) {
    return _db
        .collection('room_messages')
        .where('room_id', isEqualTo: roomId)
        .snapshots()
        .map((snap) {
      var msgs = snap.docs.map((e) => MessageModel.fromMap(_data(e))).toList();
      if (since != null) {
        final sinceMs = DateTime.tryParse(since)?.millisecondsSinceEpoch ?? 0;
        msgs = msgs.where((m) => m.timestamp >= sinceMs).toList();
      }
      msgs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (msgs.length > 60) {
        msgs = msgs.sublist(msgs.length - 60);
      }
      return msgs;
    });
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

          // Global broadcast for big gifts
          if (totalCost >= 5000) {
            txn.set(_db.collection('broadcasts').doc(const Uuid().v4()), {
              'sender_uid': senderId,
              'sender_name': senderName,
              'sender_photo_url': senderPhotoUrl,
              'room_id': roomId,
              'room_name': rm['name']?.toString() ?? 'غرفة صوتية',
              'content': 'أرسل هدية كبرى: $giftName x$count!',
              'gift_icon': defaultImage ?? animationAsset ?? '',
              'type': 'big_gift',
              'created_at': DateTime.now().toIso8601String(),
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
      debugPrint('sendGift: transaction failed (insufficient coins?): $e');
      return false;
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
    if (totalCost >= 500) {
      unawaited(Future(() async {
        try {
          await _db.collection('broadcasts').add({
            'sender_uid': senderId,
            'sender_name': senderName,
            'sender_photo_url': senderPhotoUrl,
            'room_id': roomId,
            'room_name': 'غرفة صوتية',
            'content': 'أرسل $giftName x$count بقيمة $totalCost عملة!',
            'gift_icon': animationAsset ?? '',
            'type': 'big_gift',
            'created_at': DateTime.now().toIso8601String(),
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

    return true;
  }

  /// ═══════════════════════════════════════════════════════
  /// LUCKY GIFTS & BURST SYSTEM (FIREBASE FIRESTORE)
  /// ═══════════════════════════════════════════════════════

  List<int> drawLuckyMultipliers(int count) {
    final odds = [
      {'multiplier': 0, 'weight': 650},
      {'multiplier': 1, 'weight': 200},
      {'multiplier': 2, 'weight': 90},
      {'multiplier': 5, 'weight': 40},
      {'multiplier': 10, 'weight': 15},
      {'multiplier': 50, 'weight': 4},
      {'multiplier': 100, 'weight': 1},
      {'multiplier': 500, 'weight': 1},
    ];

    final totalWeight = odds.fold<int>(0, (tot, item) => tot + (item['weight'] as int));
    final random = math.Random.secure();
    final results = <int>[];

    for (int i = 0; i < count; i++) {
      int roll = random.nextInt(totalWeight);
      int accumulated = 0;
      int chosenMultiplier = 0;

      for (final tier in odds) {
        accumulated += tier['weight'] as int;
        if (roll < accumulated) {
          chosenMultiplier = tier['multiplier'] as int;
          break;
        }
      }
      results.add(chosenMultiplier);
    }
    return results;
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
    final cardCount = count < 4 ? 4 : (count > 8 ? 8 : count);
    final multipliers = preDrawnMultipliers ?? drawLuckyMultipliers(cardCount);
    int totalWonCoins = 0;
    for (final m in multipliers) {
      totalWonCoins += (value * m);
    }
    final totalCost = value * count;
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

        // بث الحدث اللحظي للغرفة عبر room_messages
        txn.set(_db.collection('room_messages').doc(const Uuid().v4()), {
          'msg_id': const Uuid().v4(),
          'room_id': roomId,
          'sender_uid': senderId,
          'sender_name': senderName,
          'sender_photo_url': senderPhotoUrl,
          'type': 'lucky_gift',
          'image_url': giftIconUrl,
          'text': '$senderName 🍀 $giftNameAr x$count (فاز بـ $totalWonCoins 🪙)',
          'gift_payload': {
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
          },
          'created_at': DateTime.now().toIso8601String(),
        });

        // خصم التكلفة وإيداع أرباح الحظ في محفظة المرسل ذرّياً
        final sd = senderSnap.data() ?? {};
        final sentTotal = _asInt(sd['total_gifts_sent']);
        txn.update(senderRef, {
          'coins': senderCoins - totalCost + totalWonCoins,
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
              'amount': totalCost,
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

      // بث الفوز الكبير عبر جميع الغرف في التطبيق (Global Big Win Broadcast)
      if (isBigWin || maxMultiplier >= 20) {
        unawaited(Future(() async {
          try {
            await _db.collection('broadcasts').add({
              'sender_uid': senderId,
              'sender_name': senderName,
              'sender_photo_url': senderPhotoUrl,
              'room_id': roomId,
              'room_name': 'غرفة صوتية',
              'content': '🎉 فاز بمضاعف $maxMultiplier X في هدية الحظ $giftNameAr!',
              'gift_icon': giftIconUrl,
              'multiplier': maxMultiplier,
              'type': 'lucky_gift',
              'created_at': DateTime.now().toIso8601String(),
            });
          } catch (err) {
            debugPrint('broadcasts error: $err');
          }

          try {
            await _db.collection('global_announcements').add({
              'type': 'lucky_big_win',
              'sender_name': senderName,
              'gift_name': giftNameAr,
              'room_id': roomId,
              'multiplier': maxMultiplier,
              'total_won': totalWonCoins,
              'created_at': DateTime.now().toIso8601String(),
            });
          } catch (err) {
            debugPrint('global_announcements error: $err');
          }
        }));
      }

      return {
        'success': true,
        'wonCoins': totalWonCoins,
        'multipliers': multipliers,
        'maxMultiplier': maxMultiplier,
        'isBigWin': isBigWin,
      };
    } catch (e) {
      debugPrint('sendLuckyGift error: $e');
      return null;
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

  Stream<List<gm.SentGiftModel>> sentGiftsStream(String roomId) {
    return _db
        .collection('sent_gifts')
        .where('room_id', isEqualTo: roomId)
        .snapshots()
        .map((snap) => snap.docs.map((e) => gm.SentGiftModel.fromMap(_data(e))).toList());
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
    final data = user.toMap();
    data['uid'] = user.uid;
    await _db.collection('users').doc(user.uid).set(_stripNulls(data), SetOptions(merge: true));
  }

  Future<UserModel?> getUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    final m = doc.data() ?? {};
    return UserModel.fromMap({...m, 'uid': uid});
  }

  Stream<UserModel?> userStream(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      if (!snap.exists) return null;
      final m = snap.data() ?? {};
      return UserModel.fromMap({...m, 'uid': uid});
    });
  }

  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).update(_stripNulls(data));
  }

  Future<List<UserModel>> getAllUsers() async {
    final snap = await _db.collection('users').get();
    return snap.docs.map((e) => UserModel.fromMap(_data(e))).toList();
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
    return _db.collection('gifts').snapshots().map((snap) {
      final gifts = snap.docs.map((e) => gm.GiftModel.fromMap(_data(e))).toList();
      gifts.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return gifts;
    });
  }

  Future<Map<String, gm.GiftModel>> getGiftsCatalog() async {
    try {
      final snap = await _db.collection('gifts').get();
      return {for (final e in snap.docs) e.id: gm.GiftModel.fromMap(_data(e))};
    } catch (e) {
      debugPrint('getGiftsCatalog error: $e');
      return {};
    }
  }

  Future<List<gm.GiftModel>> getCpGiftsFromCatalog() async {
    try {
      final snap = await _db
          .collection('gifts')
          .where('is_cp_gift', isEqualTo: true)
          .get();
      final list = snap.docs.map((e) => gm.GiftModel.fromMap(_data(e))).toList();
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return list;
    } catch (e) {
      debugPrint('getCpGiftsFromCatalog error: $e');
      return [];
    }
  }

  Stream<List<GiftCategory>> giftCategoriesStream() {
    return _db.collection('gift_categories').snapshots().map((snap) {
      final cats = snap.docs.map((e) => GiftCategory.fromMap(_data(e))).toList();
      cats.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return cats;
    });
  }

  Future<List<GiftCategory>> getGiftCategories() async {
    try {
      final snap = await _db.collection('gift_categories').get();
      final list = snap.docs.map((e) => GiftCategory.fromMap(_data(e))).toList();
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return list;
    } catch (e) {
      debugPrint('getGiftCategories error: $e');
      return [];
    }
  }

  Future<void> saveGiftCategory(GiftCategory category) async {
    await _db.collection('gift_categories').doc(category.id).set(category.toMap());
  }

  Future<void> deleteGiftCategory(String id) async {
    await _db.collection('gift_categories').doc(id).delete();
  }

  Future<void> saveGift(gm.GiftModel gift) async {
    await _db.collection('gifts').doc(gift.id).set(gift.toMap());
  }

  Future<void> deleteGift(String id) async {
    await _db.collection('gifts').doc(id).delete();
  }

  Stream<List<GiftBannerConfig>> giftBannerConfigsStream() {
    return _db
        .collection('gift_banner_configs')
        .snapshots()
        .map((snap) => snap.docs.map((e) => GiftBannerConfig.fromMap(_data(e))).toList());
  }

  Future<List<GiftBannerConfig>> getGiftBannerConfigs() async {
    try {
      final snap = await _db.collection('gift_banner_configs').get();
      return snap.docs.map((e) => GiftBannerConfig.fromMap(_data(e))).toList();
    } catch (e) {
      debugPrint('getGiftBannerConfigs error: $e');
      return [];
    }
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
    try {
      final snap = await _db.collection('ranking_frames').get();
      return snap.docs.map((e) => RankingFrameConfig.fromMap(_data(e))).toList();
    } catch (e) {
      debugPrint('getRankingFrames error: $e');
      return [];
    }
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
    return _db.collection('store_items').snapshots().map((snap) {
      final items = snap.docs.map((e) => StoreItemModel.fromMap(_data(e))).toList();
      _storeItems = {for (final item in items) item.itemId: item};
      return items;
    });
  }

  Future<List<StoreItemModel>> getStoreItems() async {
    final snap = await _db.collection('store_items').get();
    final items = snap.docs.map((e) => StoreItemModel.fromMap(_data(e))).toList();
    _storeItems = {for (final item in items) item.itemId: item};
    return items;
  }

  StoreItemModel? getStoreItemSync(String itemId) => _storeItems[itemId];

  Stream<List<BannerConfig>> bannersStream() {
    return _db.collection('banners').snapshots().map((snap) {
      final banners = snap.docs
          .map((e) => BannerConfig.fromMap(_data(e)))
          .where((b) => b.active && b.imageUrl.isNotEmpty)
          .toList();
      banners.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return banners;
    });
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
    return _db.collection('store_categories').snapshots().map((snap) {
      final list = snap.docs.map((e) {
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
      }).where((c) => c['is_active'] == true).toList();
      list.sort((a, b) => (a['sort_order'] as num).compareTo(b['sort_order'] as num));
      return list;
    });
  }

  // ═══════════════════════════════════════════════════════
  // BACKPACK & PURCHASES
  // ═══════════════════════════════════════════════════════

  Future<bool> purchaseItem(String uid, StoreItemModel item) async {
    final userRef = _db.collection('users').doc(uid);
    try {
      await _db.runTransaction((txn) async {
        final snap = await txn.get(userRef);
        if (!snap.exists) throw Exception('user missing');
        final d = snap.data() ?? {};
        final coins = (d['coins'] ?? 0) as int;
        final owned = List<String>.from(d['owned_items'] ?? []);
        if (coins < item.price) throw Exception('insufficient coins');
        if (!owned.contains(item.itemId)) owned.add(item.itemId);
        txn.update(userRef, {'coins': coins - item.price, 'owned_items': owned});
      });
      return true;
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
    }
    await _db.collection('users').doc(uid).update(updateMap);
  }

  Future<void> unequipItem(String uid, String category) async {
    final updateMap = <String, dynamic>{};
    switch (category) {
      case 'frame':
        updateMap['active_frame'] = FieldValue.delete();
        break;
      case 'headwear':
        updateMap['active_headwear'] = FieldValue.delete();
        break;
      case 'bubble':
        updateMap['active_bubble'] = FieldValue.delete();
        break;
      case 'entrance':
        updateMap['active_entrance'] = FieldValue.delete();
        break;
      case 'car':
        updateMap['active_car'] = FieldValue.delete();
        break;
      case 'cover':
        updateMap['active_cover'] = FieldValue.delete();
        break;
      case 'necklace':
        updateMap['active_necklace'] = FieldValue.delete();
        break;
    }
    if (updateMap.isNotEmpty) {
      await _db.collection('users').doc(uid).update(updateMap);
    }
  }

  // ═══════════════════════════════════════════════════════
  // GIFTED ITEMS
  // ═══════════════════════════════════════════════════════

  Stream<List<GiftedItemModel>> userGiftedItemsStream(String uid) {
    return _db
        .collection('gifted_items')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs.map((e) => GiftedItemModel.fromMap(_data(e), e.id)).toList());
  }

  Future<List<GiftedItemModel>> getGiftedItems(String uid) async {
    final snap = await _db.collection('gifted_items').where('uid', isEqualTo: uid).get();
    return snap.docs.map((e) => GiftedItemModel.fromMap(_data(e), e.id)).toList();
  }

  Future<List<GiftedItemModel>> getGiftedItemsByCategory(String uid, String category) async {
    try {
      final snap = await _db
          .collection('gifted_items')
          .where('uid', isEqualTo: uid)
          .where('item_category', isEqualTo: category)
          .get();
      return snap.docs.map((e) => GiftedItemModel.fromMap(_data(e), e.id)).toList();
    } catch (e) {
      debugPrint('getGiftedItemsByCategory error: $e');
      return [];
    }
  }

  Future<void> removeGiftedItem(String id) async {
    await _db.collection('gifted_items').doc(id).delete();
  }

  // ═══════════════════════════════════════════════════════
  // IMAGE MESSAGES
  // ═══════════════════════════════════════════════════════

  Future<void> sendImageMessage(String roomId, String imageUrl, String senderUid,
      String senderName, String senderPhotoUrl) async {
    final msgId = const Uuid().v4();
    final msg = MessageModel(
      msgId: msgId,
      senderUid: senderUid,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      text: '',
      imageUrl: imageUrl,
      type: 'image',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    final map = msg.toMap();
    map['room_id'] = roomId;
    await _db.collection('room_messages').doc(msgId).set(map);
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
    // التحقق من الحظر
    final blockDoc = await _db.collection('blocks').doc('${receiverId}_$senderId').get();
    if (blockDoc.exists) {
      throw Exception('لا يمكنك إرسال رسالة لأن هذا المستخدم قام بحظرك.');
    }
    final myBlockDoc = await _db.collection('blocks').doc('${senderId}_$receiverId').get();
    if (myBlockDoc.exists) {
      throw Exception('لقد قمت بحظر هذا المستخدم. يجب إزالة الحظر أولاً.');
    }

    final convId = await _getOrCreateConversationId(senderId, receiverId);
    final msgId = const Uuid().v4();
    final msg = MessageModel(
      msgId: msgId,
      senderUid: senderId,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      text: text,
      imageUrl: imageUrl,
      type: type,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    final data = msg.toMap();
    data['conv_id'] = convId;
    data['id'] = msgId;
    await _db.collection('private_messages').doc(msgId).set(data);

    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    for (final uid in [senderId, receiverId]) {
      final isSender = uid == senderId;
      await _db.collection('conversations').doc('${uid}_$convId').set({
        'uid': uid,
        'conversationId': convId,
        'otherUid': isSender ? receiverId : senderId,
        'otherName': isSender ? receiverName : senderName,
        'otherPhotoUrl': isSender ? receiverPhotoUrl : senderPhotoUrl,
        'lastMessage': type == 'image' ? '[صورة]' : text,
        'lastMessageTime': nowMillis,
        'unreadCount': isSender ? 0 : FieldValue.increment(1),
      }, SetOptions(merge: true));
    }
  }

  Stream<List<Map<String, dynamic>>> conversationsStream(String uid) {
    return _db
        .collection('conversations')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      final convs = snap.docs.map((e) => Map<String, dynamic>.from(e.data())).toList();
      convs.sort((a, b) {
        final at = a['lastMessageTime'] as int? ?? 0;
        final bt = b['lastMessageTime'] as int? ?? 0;
        return bt.compareTo(at);
      });
      return convs;
    });
  }

  Stream<List<MessageModel>> privateMessagesStream(String conversationId) {
    return _db
        .collection('private_messages')
        .where('conv_id', isEqualTo: conversationId)
        .snapshots()
        .map((snap) {
      final msgs = snap.docs.map((e) => MessageModel.fromMap(_data(e))).toList();
      msgs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return msgs;
    });
  }

  Future<void> markConversationRead(String uid, String conversationId) async {
    await _db.collection('conversations').doc('${uid}_$conversationId').update({'unreadCount': 0});
  }

  // ═══════════════════════════════════════════════════════
  // DIAMOND ↔ COIN EXCHANGE
  // ═══════════════════════════════════════════════════════

  Future<({bool success, int coinsReceived, String? error})> exchangeDiamondsToCoins({
    required String uid,
    required int diamonds,
    required int rate,
  }) async {
    if (diamonds < rate) {
      return (success: false, coinsReceived: 0, error: 'الحد الأدنى $rate ألماس');
    }
    final userRef = _db.collection('users').doc(uid);
    try {
      final result = await _db.runTransaction((txn) async {
        final snap = await txn.get(userRef);
        if (!snap.exists) throw Exception('المستخدم غير موجود');
        final d = snap.data() ?? {};
        final bal = (d['diamonds'] ?? 0) as int;
        if (bal < diamonds) throw Exception('رصيد ألماس غير كافٍ');
        final curCoins = (d['coins'] ?? 0) as int;
        final coinsReceived = diamonds ~/ rate;
        txn.update(userRef, {'diamonds': bal - diamonds, 'coins': curCoins + coinsReceived});

        final walletRef = _db.collection('user_wallets').doc(uid);
        final wSnap = await txn.get(walletRef);
        if (wSnap.exists) {
          final wd = wSnap.data() ?? {};
          txn.update(walletRef, {
            'diamond_balance': ((wd['diamond_balance'] ?? 0) as int) - diamonds,
            'gold_balance': ((wd['gold_balance'] ?? 0) as int) + coinsReceived,
          });
        }
        return coinsReceived;
      });
      return (success: true, coinsReceived: result, error: null);
    } catch (e) {
      return (success: false, coinsReceived: 0, error: 'فشل التبادل: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // RECHARGE
  // ═══════════════════════════════════════════════════════

  Future<void> addCoins(String uid, int amount) async {
    final ref = _db.collection('users').doc(uid);
    try {
      await _db.runTransaction((txn) async {
        final snap = await txn.get(ref);
        if (!snap.exists) throw Exception('user missing');
        final d = snap.data() ?? {};
        txn.update(ref, {'coins': ((d['coins'] ?? 0) as int) + amount});
      });
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
      final ref = _db.collection('users').doc(uid);
      return await _db.runTransaction((txn) async {
        final snap = await txn.get(ref);
        if (!snap.exists) return false;
        final d = snap.data()!;
        final curCoins = (d['coins'] ?? 0) as int;
        if (curCoins < amount) return false;
        txn.update(ref, {'coins': curCoins - amount});
        return true;
      });
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
    try {
      await _db.collection('follows').doc('${uid}_$targetUid').set({
        'follower_uid': uid,
        'following_uid': targetUid,
        'created_at': _now(),
      });
      await _incrementCounter('users', uid, 'following', 1);
      await _incrementCounter('users', targetUid, 'followers', 1);
      await _db.collection('notifications').add({
        'id': const Uuid().v4(),
        'uid': targetUid,
        'type': 'follow',
        'actor_uid': uid,
        'title': 'New Follower',
        'body': 'started following you',
        'created_at': _now(),
      });
    } catch (e) {
      debugPrint('followUser error: $e');
    }
  }

  Future<void> unfollowUser(String uid, String targetUid) async {
    if (uid == targetUid) return;
    try {
      await _db.collection('follows').doc('${uid}_$targetUid').delete();
      await _incrementCounter('users', uid, 'following', -1);
      await _incrementCounter('users', targetUid, 'followers', -1);
    } catch (e) {
      debugPrint('unfollowUser error: $e');
    }
  }

  Future<bool> isFollowing(String uid, String targetUid) async {
    if (uid.isEmpty || targetUid.isEmpty) return false;
    try {
      final doc = await _db.collection('follows').doc('${uid}_$targetUid').get();
      return doc.exists;
    } catch (e) {
      debugPrint('isFollowing error: $e');
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

      final countSnap = await _db
          .collection('profile_visits')
          .where('visited_uid', isEqualTo: visitedUid)
          .count()
          .get();
      final int count = countSnap.count ?? 0;
      // V1.2: clients may NOT write to another user's document (users/{uid} is
      // now restricted to self by Firestore rules). The visitor counter is read
      // from profile_visits at display time instead.
      if (!visitedUid.isEmpty) {
        try {
          await _db.collection('user_stats').doc(visitedUid).set(
                {'visitors': count},
                SetOptions(merge: true),
              );
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('recordProfileVisit error: $e');
    }
  }

  Future<int> incrementVisitors(String uid) async {
    try {
      final countSnap = await _db
          .collection('profile_visits')
          .where('visited_uid', isEqualTo: uid)
          .count()
          .get();
      final int count = countSnap.count ?? 0;
      await _db.collection('users').doc(uid).update({'visitors': count});
      return count;
    } catch (e) {
      debugPrint('incrementVisitors error: $e');
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
      final snap = await _db.collection('follows').where('follower_uid', isEqualTo: uid).get();
      final uids = snap.docs
          .map((e) => e.data()['following_uid']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      return await _batchFetchUsers(uids);
    } catch (e) {
      debugPrint('getFollowing error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getFans(String uid) async {
    try {
      final snap = await _db.collection('follows').where('following_uid', isEqualTo: uid).get();
      final uids = snap.docs
          .map((e) => e.data()['follower_uid']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      return await _batchFetchUsers(uids);
    } catch (e) {
      debugPrint('getFans error: $e');
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
      final snap = await _db
          .collection('profile_visits')
          .where('visited_uid', isEqualTo: uid)
          .limit(50)
          .get();
      final items = snap.docs.map((e) => e.data()).toList();
      items.sort((a, b) => (b['visited_at'] ?? '').toString().compareTo((a['visited_at'] ?? '').toString()));
      
      final uids = items
          .map((e) => e['visitor_uid']?.toString() ?? '')
          .where((id) => id.isNotEmpty && id != uid)
          .toSet()
          .toList();

      final userMap = <String, Map<String, dynamic>>{};
      for (final u in await _batchFetchUsers(uids)) {
        userMap[u['uid'].toString()] = u;
      }
      final result = <Map<String, dynamic>>[];
      for (final item in items) {
        final visitorUid = item['visitor_uid']?.toString() ?? '';
        if (visitorUid.isEmpty || visitorUid == uid) continue;
        final user = userMap[visitorUid];
        if (user != null) {
          result.add({...user, 'time': item['visited_at']?.toString() ?? ''});
        } else {
          result.add({
            'uid': visitorUid,
            'id': visitorUid,
            'name': item['visitor_name']?.toString() ?? 'User',
            'photo_url': item['visitor_photo']?.toString() ?? '',
            'avatar': item['visitor_photo']?.toString() ?? '',
            'time': item['visited_at']?.toString() ?? '',
          });
        }
      }
      return result;
    } catch (e) {
      debugPrint('getVisitors error: $e');
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
      final snap = await _db.collection('badges').get();
      return snap.docs.map((e) => Map<String, dynamic>.from(e.data())).toList();
    } catch (e) {
      debugPrint('getBadgesCatalog error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getNecklacesCatalog() async {
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
        ? '$name entered with car'
        : '$name entered the room';

    await _db.collection('room_messages').doc(const Uuid().v4()).set({
      'msg_id': const Uuid().v4(),
      'room_id': roomId,
      'sender_uid': uid,
      'sender_name': name,
      'sender_photo_url': photoUrl,
      'text': text,
      'type': 'entrance',
      'image_url': primaryAsset,
      'created_at': now,
    });
  }

  Future<void> logExit(String roomId, String name) async {
    await _db.collection('room_messages').doc(const Uuid().v4()).set({
      'msg_id': const Uuid().v4(),
      'room_id': roomId,
      'sender_uid': '',
      'sender_name': name,
      'sender_photo_url': '',
      'text': '$name left the room',
      'type': 'entrance',
      'created_at': _now(),
    });
  }

  Stream<List<Map<String, dynamic>>> entrancesStream(String roomId) {
    return _db
        .collection('room_messages')
        .where('room_id', isEqualTo: roomId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((e) => Map<String, dynamic>.from(e.data())).toList();
      list.sort((a, b) {
        final at = a['created_at']?.toString() ?? '';
        final bt = b['created_at']?.toString() ?? '';
        return bt.compareTo(at);
      });
      return list.where((e) => e['type'] == 'entrance').map((e) {
        return {
          'uid': e['sender_uid'],
          'name': e['sender_name'],
          'photoUrl': e['sender_photo_url'],
          'entranceItem': e['image_url']?.toString() ?? '',
          'timestamp': e['created_at'],
        };
      }).toList();
    });
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
    Query<Map<String, dynamic>> query = _db.collection('notifications');
    if (uid != null && uid.isNotEmpty) {
      query = query.where('uid', isEqualTo: uid);
    }
    return query.snapshots().map((snap) {
      final list = snap.docs.map((e) => NotificationModel.fromMap(_data(e))).toList();
      list.sort((a, b) => b.sentAt.compareTo(a.sentAt));
      return list;
    });
  }

  Future<void> sendNotification({
    required String uid,
    required String type,
    String actorUid = '',
    String title = '',
    String body = '',
    Map<String, dynamic>? data,
  }) async {
    await _db.collection('notifications').add({
      'id': const Uuid().v4(),
      'uid': uid,
      'type': type,
      'actor_uid': actorUid,
      'title': title,
      'body': body,
      'data': data,
      'created_at': _now(),
    });
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
      debugPrint('reportUser error: $e');
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
      debugPrint('isUserBlockedFromRoom error: $e');
      return false;
    }
  }

  Stream<List<Map<String, dynamic>>> roomBlocksStream(String roomId) {
    return _db
        .collection('room_blocks')
        .where('room_id', isEqualTo: roomId)
        .snapshots()
        .map((snap) => snap.docs.map((e) => Map<String, dynamic>.from(e.data())).toList());
  }

  Stream<bool> userRoomBanStream(String roomId, String uid) {
    return _db
        .collection('room_blocks')
        .doc('${roomId}_$uid')
        .snapshots()
        .map((snap) => snap.exists);
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
      debugPrint('getBlockedUids error: $e');
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

  /// Fetch Top 10 rankings for a room (Wealth = senders, Magic = receivers)
  Future<List<Map<String, dynamic>>> getRoomRankings({
    required String roomId,
    required bool isWealth,
    required String timeframe,
  }) async {
    // احسب منتصف الليل بتوقيت السعودية/مصر (UTC+3)
    final nowUtc = DateTime.now().toUtc();
    final ksaTime = nowUtc.add(const Duration(hours: 3));
    
    DateTime startDateUtc;
    if (timeframe == 'daily') {
      startDateUtc = DateTime.utc(ksaTime.year, ksaTime.month, ksaTime.day).subtract(const Duration(hours: 3));
    } else if (timeframe == 'weekly') {
      final daysToSubtract = ksaTime.weekday - 1;
      startDateUtc = DateTime.utc(ksaTime.year, ksaTime.month, ksaTime.day).subtract(Duration(days: daysToSubtract, hours: 3));
    } else { // monthly
      startDateUtc = DateTime.utc(ksaTime.year, ksaTime.month, 1).subtract(const Duration(hours: 3));
    }
    
    String startStr = startDateUtc.toIso8601String();

    try {
      final snap = await _db.collection('sent_gifts')
          .where('room_id', isEqualTo: roomId)
          .where('created_at', isGreaterThanOrEqualTo: startStr)
          .get();
      return _processRankings(snap.docs, isWealth);
    } catch (e) {
      // Fallback if composite index is missing
      final snap = await _db.collection('sent_gifts')
          .where('room_id', isEqualTo: roomId)
          .get();
      final filteredDocs = snap.docs.where((doc) {
        final d = doc.data();
        final created = d['created_at'] as String? ?? '';
        return created.compareTo(startStr) >= 0;
      }).toList();
      return _processRankings(filteredDocs, isWealth);
    }
  }

  Future<List<Map<String, dynamic>>> getGlobalRankings({
    required bool isWealth,
    required String timeframe,
  }) async {
    if (timeframe == 'all') {
      return getUserRanking(
        orderByField: isWealth ? 'total_gifts_sent' : 'total_gifts_received',
      );
    }
    final nowUtc = DateTime.now().toUtc();
    final ksaTime = nowUtc.add(const Duration(hours: 3));
    
    DateTime startDateUtc;
    if (timeframe == 'daily') {
      startDateUtc = DateTime.utc(ksaTime.year, ksaTime.month, ksaTime.day).subtract(const Duration(hours: 3));
    } else if (timeframe == 'weekly') {
      final daysToSubtract = ksaTime.weekday - 1;
      startDateUtc = DateTime.utc(ksaTime.year, ksaTime.month, ksaTime.day).subtract(Duration(days: daysToSubtract, hours: 3));
    } else { // monthly
      startDateUtc = DateTime.utc(ksaTime.year, ksaTime.month, 1).subtract(const Duration(hours: 3));
    }
    
    String startStr = startDateUtc.toIso8601String();

    try {
      final snap = await _db.collection('sent_gifts')
          .where('created_at', isGreaterThanOrEqualTo: startStr)
          .get();
      return _processGlobalRankings(snap.docs, isWealth);
    } catch (e) {
      final snap = await _db.collection('sent_gifts').get();
      final filteredDocs = snap.docs.where((doc) {
        final d = doc.data();
        final created = d['created_at'] as String? ?? '';
        return created.compareTo(startStr) >= 0;
      }).toList();
      return _processGlobalRankings(filteredDocs, isWealth);
    }
  }

  Future<List<Map<String, dynamic>>> _processGlobalRankings(List<dynamic> docs, bool isWealth) async {
    final Map<String, int> totals = {};
    for (var doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      final userId = isWealth ? d['sender_id'] : d['receiver_id'];
      final value = _asInt(d['value']) * _asInt(d['count']);
      if (userId == null) continue;
      totals[userId] = (totals[userId] ?? 0) + value;
    }

    final entries = totals.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    final top50 = entries.take(50).toList();

    final List<Map<String, dynamic>> results = [];
    for (var entry in top50) {
      final userSnap = await _db.collection('users').doc(entry.key).get();
      final ud = userSnap.data() ?? {};
      final customId = (ud['custom_id'] ?? ud['customId'] ?? ud['display_id'] ?? ud['id'] ?? '').toString();
      final displayNumericId = customId.isNotEmpty ? customId : entry.key;
      results.add({
        'uid': entry.key,
        'id': displayNumericId,
        'custom_id': displayNumericId,
        'name': (ud['name'] ?? 'Unknown').toString(),
        'photo_url': (ud['photo_url'] ?? ud['photoUrl'] ?? '').toString(),
        'level': ud['level'] ?? 1,
        'total_gifts_sent': isWealth ? entry.value : _asInt(ud['total_gifts_sent']),
        'total_gifts_received': !isWealth ? entry.value : _asInt(ud['total_gifts_received']),
        'user_id': displayNumericId,
      });
    }

    if (results.isEmpty) {
      try {
        final field = isWealth ? 'total_gifts_sent' : 'total_gifts_received';
        final userSnap = await _db.collection('users')
            .orderBy(field, descending: true)
            .limit(50)
            .get();
        for (var doc in userSnap.docs) {
          final ud = doc.data();
          final val = _asInt(ud[field]);
          if (val <= 0) continue;
          final customId = (ud['custom_id'] ?? ud['customId'] ?? ud['display_id'] ?? ud['id'] ?? '').toString();
          final displayNumericId = customId.isNotEmpty ? customId : doc.id;
          results.add({
            'uid': doc.id,
            'id': displayNumericId,
            'custom_id': displayNumericId,
            'name': (ud['name'] ?? 'Unknown').toString(),
            'photo_url': (ud['photo_url'] ?? ud['photoUrl'] ?? '').toString(),
            'level': ud['level'] ?? 1,
            'total_gifts_sent': isWealth ? val : _asInt(ud['total_gifts_sent']),
            'total_gifts_received': !isWealth ? val : _asInt(ud['total_gifts_received']),
            'user_id': displayNumericId,
          });
        }
      } catch (_) {}
    }

    return results;
  }

  Future<List<Map<String, dynamic>>> _processRankings(List<dynamic> docs, bool isWealth) async {
    final Map<String, int> totals = {};
    for (var doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      final userId = isWealth ? d['sender_id'] : d['receiver_id'];
      final value = _asInt(d['value']) * _asInt(d['count']);
      if (userId == null) continue;
      totals[userId] = (totals[userId] ?? 0) + value;
    }

    final entries = totals.entries.toList();
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
        'user_name': ud['name'] ?? 'Unknown',
        'user_photo_url': (ud['photo_url'] ?? ud['photoUrl'] ?? '').toString(),
        'total_value': entry.value,
      });
    }
    return results;
  }
  Future<List<Map<String, dynamic>>> getRoomGlobalRanking({
    int limit = 50,
  }) async {
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _db
            .collection('rooms')
            .orderBy('total_gifts', descending: true)
            .limit(limit)
            .get();
      } catch (e) {
        snap = await _db.collection('rooms').limit(limit).get();
      }
      final list = snap.docs.map((doc) {
        final data = doc.data();
        final photo = (data['room_photo_url'] ?? data['cover_image'] ?? data['photo_url'] ?? data['image'] ?? data['bg_image'] ?? '').toString();
        final name = (data['name'] ?? data['title'] ?? 'Room').toString();
        final roomId = (data['room_id'] ?? data['custom_id'] ?? doc.id).toString();
        return {
          'id': doc.id,
          'room_doc_id': doc.id,
          'name': name,
          'photoUrl': photo,
          'photo_url': photo,
          'user_id': roomId,
          'room_id': roomId,
          'host_name': (data['host_name'] ?? '').toString(),
          'password': (data['password'] ?? '').toString(),
          'points': (data['total_gifts'] as num?)?.toInt() ?? 0,
        };
      }).toList();
      list.sort((a, b) => (b['points'] as int).compareTo(a['points'] as int));
      return list;
    } catch (e) {
      debugPrint('getRoomGlobalRanking error: $e');
      return [];
    }
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
      // 1. البحث عن الوكالة إما بالـ ID أو بالـ Owner UID
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
}



