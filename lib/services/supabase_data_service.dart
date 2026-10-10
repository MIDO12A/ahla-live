import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../config/supabase_config.dart';
import '../models/room_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../models/banner_config.dart';
import '../models/gift_model.dart' as gm;
import '../models/gift_category_model.dart';
import '../models/gift_banner_config_model.dart';
import '../models/ranking_frame_config.dart';
import '../models/store_item_model.dart';
import '../models/app_asset_model.dart';
import '../models/notification_model.dart';
import '../models/gifted_item_model.dart';
import 'package:uuid/uuid.dart';

class SupabaseDataService {
  static final SupabaseDataService _instance = SupabaseDataService._internal();
  factory SupabaseDataService() => _instance;
  SupabaseDataService._internal();

  static const String _baseUrl = SupabaseConfig.projectUrl;
  static const String _anonKey = SupabaseConfig.anonKey;

  static Map<String, String> get _headers => {
        'apikey': _anonKey,
        'Authorization': 'Bearer $_anonKey',
        'Content-Type': 'application/json',
      };

  // ═══════════════════════════════════════════════════════
  // ROOMS
  // ═══════════════════════════════════════════════════════

  Future<bool> createRoom(RoomModel room) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/rooms?on_conflict=room_id');
      final body = jsonEncode({
        'room_id': room.roomId,
        'name': room.name,
        'description': room.description,
        'room_photo_url': room.roomPhotoUrl,
        'host_uid': room.hostUid,
        'host_name': room.hostName,
        'host_photo_url': room.hostPhotoUrl,
        'member_count': room.memberCount,
        'max_members': room.maxMembers,
        'is_locked': room.isLocked,
        'category': room.category,
        'password': room.password,
        'country': room.country,
        'seat_count': room.seatCount,
        'seat_style': room.seatStyle.index.toString(),
        'seat_color': room.seatColor.index.toString(),
        'total_gifts': room.totalGifts,
        'hot_value': room.hotValue,
        'bg_image': room.bgImage,
        'announcement': room.announcement,
        'is_chat_locked': room.isChatLocked,
        'chat_cleared_at': room.chatClearedAt,
        'moderators': room.moderators,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      final res = await http.post(
        url,
        headers: {
          ..._headers,
          'Prefer': 'resolution=merge-duplicates',
        },
        body: body,
      );

      debugPrint('[SupabaseDataService] createRoom (${room.roomId}) status: ${res.statusCode}');
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] createRoom error: $e');
      return false;
    }
  }

  Future<bool> ensureRoomExists({
    required String roomId,
    String? name,
    String? hostUid,
    String? hostName,
  }) async {
    try {
      // 1. If room already exists, never touch or overwrite its host/data
      final existing = await getRoom(roomId);
      if (existing != null) {
        return true;
      }
      final url = Uri.parse('$_baseUrl/rest/v1/rooms?on_conflict=room_id');
      final body = jsonEncode({
        'room_id': roomId,
        'name': (name != null && name.isNotEmpty) ? name : 'Room',
        'host_uid': hostUid ?? '',
        'host_name': hostName ?? '',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      final res = await http.post(
        url,
        headers: {
          ..._headers,
          'Prefer': 'resolution=ignore-duplicates',
        },
        body: body,
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<RoomModel?> getRoom(String roomId) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/rooms?room_id=eq.$roomId&select=*');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        if (list.isNotEmpty) {
          final m = Map<String, dynamic>.from(list.first as Map);
          return RoomModel.fromMap(m);
        }
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getRoom error: $e');
    }
    return null;
  }

  Future<RoomModel?> getRoomByHostUid(String hostUid) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/rooms?host_uid=eq.$hostUid&select=*&limit=1');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        if (list.isNotEmpty) {
          final m = Map<String, dynamic>.from(list.first as Map);
          return RoomModel.fromMap(m);
        }
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getRoomByHostUid error: $e');
    }
    return null;
  }

  Future<List<RoomModel>> getAllRooms() async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/rooms?select=*&order=total_gifts.desc');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => RoomModel.fromMap(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getAllRooms error: $e');
    }
    return [];
  }

  Future<bool> updateRoom(String roomId, Map<String, dynamic> updates) async {
    try {
      final clean = <String, dynamic>{};
      updates.forEach((k, v) {
        if (v != null) {
          clean[k] = v;
        }
      });
      if (clean.isEmpty) return true;

      final url = Uri.parse('$_baseUrl/rest/v1/rooms?room_id=eq.$roomId');
      final res = await http.patch(
        url,
        headers: _headers,
        body: jsonEncode(clean),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] updateRoom error: $e');
      return false;
    }
  }

  Future<void> incrementRoomGifts(String roomId, int giftValue) async {
    try {
      if (roomId.isEmpty || giftValue <= 0) return;
      final room = await getRoom(roomId);
      if (room != null) {
        final newTotal = room.totalGifts + giftValue;
        final newHot = (room.hotValue > 0 ? room.hotValue : 0) + giftValue;
        await updateRoom(roomId, {
          'total_gifts': newTotal,
          'hot_value': newHot,
        });
      }
    } catch (_) {}
  }

  Future<bool> deleteRoom(String roomId) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/rooms?room_id=eq.$roomId');
      final res = await http.delete(url, headers: _headers);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] deleteRoom error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // ROOM SEATS
  // ═══════════════════════════════════════════════════════

  Future<bool> takeSeat({
    required String roomId,
    required int seatIndex,
    required UserModel user,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/room_seats?on_conflict=room_id,seat_index');
      final body = jsonEncode({
        'room_id': roomId,
        'seat_index': seatIndex,
        'uid': user.uid,
        'name': user.name,
        'photo_url': user.photoUrl,
        'active_frame': user.activeFrame,
        'active_car': user.activeCar,
        'is_muted': false,
        'is_locked': false,
        'taken_at': DateTime.now().toUtc().toIso8601String(),
      });

      var res = await http.post(
        url,
        headers: {
          ..._headers,
          'Prefer': 'resolution=merge-duplicates',
        },
        body: body,
      );

      if (res.statusCode >= 400 && (res.body.contains('foreign key') || res.statusCode == 409 || res.body.contains('room_seats_room_id_fkey'))) {
        await ensureRoomExists(
          roomId: roomId,
          hostUid: '',
          hostName: '',
        );
        res = await http.post(
          url,
          headers: {
            ..._headers,
            'Prefer': 'resolution=merge-duplicates',
          },
          body: body,
        );
      }

      debugPrint('[SupabaseDataService] takeSeat ($roomId, $seatIndex) status: ${res.statusCode}');
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] takeSeat error: $e');
      return false;
    }
  }

  Future<bool> leaveSeat(String roomId, int seatIndex) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/room_seats?room_id=eq.$roomId&seat_index=eq.$seatIndex');
      final res = await http.delete(url, headers: _headers);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] leaveSeat error: $e');
      return false;
    }
  }

  Future<bool> leaveSeatForUser(String roomId, String uid) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/room_seats?room_id=eq.$roomId&uid=eq.$uid');
      final res = await http.delete(url, headers: _headers);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] leaveSeatForUser error: $e');
      return false;
    }
  }

  Future<bool> toggleMute(String roomId, int seatIndex, bool isMuted) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/room_seats?on_conflict=room_id,seat_index');
      final res = await http.post(
        url,
        headers: {
          ..._headers,
          'Prefer': 'resolution=merge-duplicates',
        },
        body: jsonEncode({
          'room_id': roomId,
          'seat_index': seatIndex,
          'is_muted': isMuted,
        }),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return true;
      }
      final patchUrl = Uri.parse('$_baseUrl/rest/v1/room_seats?room_id=eq.$roomId&seat_index=eq.$seatIndex');
      final patchRes = await http.patch(
        patchUrl,
        headers: _headers,
        body: jsonEncode({'is_muted': isMuted}),
      );
      return patchRes.statusCode >= 200 && patchRes.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] toggleMute error: $e');
      return false;
    }
  }

  Future<bool> toggleSeatLock(String roomId, int seatIndex, bool isLocked) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/room_seats?on_conflict=room_id,seat_index');
      final res = await http.post(
        url,
        headers: {
          ..._headers,
          'Prefer': 'resolution=merge-duplicates',
        },
        body: jsonEncode({
          'room_id': roomId,
          'seat_index': seatIndex,
          'is_locked': isLocked,
          if (isLocked) 'uid': null,
        }),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] toggleSeatLock error: $e');
      return false;
    }
  }

  Future<bool> migrateUserRoomId(String hostUid, String newRoomId) async {
    try {
      final existing = await getRoomByHostUid(hostUid);
      if (existing != null && existing.roomId != newRoomId) {
        final oldRoomId = existing.roomId;
        final updatedRoom = RoomModel(
          roomId: newRoomId,
          name: existing.name,
          description: existing.description,
          roomPhotoUrl: existing.roomPhotoUrl,
          hostUid: existing.hostUid,
          hostName: existing.hostName,
          hostPhotoUrl: existing.hostPhotoUrl,
          memberCount: existing.memberCount,
          maxMembers: existing.maxMembers,
          isLocked: existing.isLocked,
          category: existing.category,
          createdAt: existing.createdAt,
          password: existing.password,
          seatCount: existing.seatCount,
          seatStyle: existing.seatStyle,
          seatColor: existing.seatColor,
          totalGifts: existing.totalGifts,
          hotValue: existing.hotValue,
          country: existing.country,
        );
        await createRoom(updatedRoom);

        try {
          await http.patch(
            Uri.parse('$_baseUrl/rest/v1/sent_gifts?room_id=eq.$oldRoomId'),
            headers: _headers,
            body: jsonEncode({'room_id': newRoomId}),
          );
          await http.patch(
            Uri.parse('$_baseUrl/rest/v1/room_seats?room_id=eq.$oldRoomId'),
            headers: _headers,
            body: jsonEncode({'room_id': newRoomId}),
          );
          await http.patch(
            Uri.parse('$_baseUrl/rest/v1/room_members?room_id=eq.$oldRoomId'),
            headers: _headers,
            body: jsonEncode({'room_id': newRoomId}),
          );
          await deleteRoom(oldRoomId);
        } catch (_) {}
      }

      await updateUser(hostUid, {
        'hosted_room_id': newRoomId,
        'custom_id': newRoomId,
      });

      return true;
    } catch (e) {
      debugPrint('[SupabaseDataService] migrateUserRoomId error: $e');
      return false;
    }
  }

  Future<Map<int, Map<String, dynamic>>> getSeats(String roomId) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/room_seats?room_id=eq.$roomId&select=*');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        final map = <int, Map<String, dynamic>>{};
        for (final item in list) {
          final d = Map<String, dynamic>.from(item as Map);
          final idx = (d['seat_index'] as num?)?.toInt() ?? 0;
          map[idx] = d;
        }
        return map;
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getSeats error: $e');
    }
    return {};
  }

  // ═══════════════════════════════════════════════════════
  // ROOM MEMBERS
  // ═══════════════════════════════════════════════════════

  Future<bool> joinRoom(String roomId, UserModel user) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/room_members');
      final body = jsonEncode({
        'room_id': roomId,
        'uid': user.uid,
        'name': user.name,
        'photo_url': user.photoUrl,
        'role': 'member',
        'joined_at': DateTime.now().toUtc().toIso8601String(),
      });

      final res = await http.post(
        url,
        headers: {
          ..._headers,
          'Prefer': 'resolution=merge-duplicates',
        },
        body: body,
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] joinRoom error: $e');
      return false;
    }
  }

  Future<bool> leaveRoom(String roomId, String uid) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/room_members?room_id=eq.$roomId&uid=eq.$uid');
      final res = await http.delete(url, headers: _headers);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] leaveRoom error: $e');
      return false;
    }
  }

  Future<List<UserModel>> getRoomMembers(String roomId) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/room_members?room_id=eq.$roomId&select=*');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return UserModel.fromMap(m);
        }).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getRoomMembers error: $e');
    }
    return [];
  }

  // ═══════════════════════════════════════════════════════
  // ROOM MESSAGES
  // ═══════════════════════════════════════════════════════

  Future<bool> sendMessage(MessageModel message) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/room_messages');
      final body = jsonEncode({
        if (message.msgId.isNotEmpty) 'msg_id': message.msgId,
        'room_id': message.roomId,
        'sender_uid': message.senderUid,
        'sender_name': message.senderName,
        'sender_photo_url': message.senderPhotoUrl,
        'text': message.text,
        'type': message.type,
        'image_url': message.imageUrl ?? '',
        'active_bubble': message.activeBubble,
        'gift_payload': message.giftPayload ?? {},
        'created_at': DateTime.fromMillisecondsSinceEpoch(message.timestamp).toUtc().toIso8601String(),
      });

      final res = await http.post(
        url,
        headers: _headers,
        body: body,
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] sendMessage error: $e');
      return false;
    }
  }

  Future<List<MessageModel>> getRoomMessages(String roomId, {int limit = 60, int? sinceMs}) async {
    try {
      String query = 'room_id=eq.$roomId&select=*&order=created_at.desc&limit=$limit';
      if (sinceMs != null && sinceMs > 0) {
        final iso = DateTime.fromMillisecondsSinceEpoch(sinceMs).toUtc().toIso8601String();
        query += '&created_at=gte.$iso';
      }
      final url = Uri.parse('$_baseUrl/rest/v1/room_messages?$query');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        final messages = list.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          final createdIso = m['created_at']?.toString() ?? '';
          final ts = DateTime.tryParse(createdIso)?.millisecondsSinceEpoch ?? 0;
          return MessageModel(
            msgId: m['msg_id']?.toString() ?? '',
            roomId: m['room_id']?.toString() ?? '',
            senderUid: m['sender_uid']?.toString() ?? '',
            senderName: m['sender_name']?.toString() ?? '',
            senderPhotoUrl: m['sender_photo_url']?.toString() ?? '',
            text: m['text']?.toString() ?? '',
            type: m['type']?.toString() ?? 'text',
            timestamp: ts,
            imageUrl: m['image_url']?.toString(),
            activeBubble: m['active_bubble']?.toString(),
            giftPayload: m['gift_payload'] is Map ? Map<String, dynamic>.from(m['gift_payload'] as Map) : null,
          );
        }).toList();
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        return messages;
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getRoomMessages error: $e');
    }
    return [];
  }

  // ═══════════════════════════════════════════════════════
  // USERS
  // ═══════════════════════════════════════════════════════

  Future<bool> updateUser(String uid, Map<String, dynamic> updates) async {
    try {
      const allowedColumns = {
        'uid', 'custom_id', 'name', 'email', 'photo_url', 'coins', 'diamonds',
        'gender', 'signature', 'country', 'country_code', 'age', 'charm',
        'active_frame', 'active_headwear', 'active_bubble', 'active_entrance',
        'active_car', 'active_cover', 'active_necklace', 'active_mic_wave',
        'profile_bg_url', 'owned_items', 'owned_badges', 'owned_necklaces',
        'owned_level_frames', 'owned_level_badges', 'owned_vip_items', 'album',
        'hosted_room_id', 'followed_rooms', 'total_gifts_sent', 'total_gifts_received',
        'level', 'experience', 'followers', 'following', 'visitors',
        'wealth_level', 'wealth_exp', 'recharge_level', 'recharge_exp',
        'gems_level', 'gems_exp', 'is_recharge_agent', 'recharge_agency_name',
        'recharge_agency_logo', 'whatsapp_number', 'phone', 'banned', 'ban_reason',
        'last_ip', 'updated_at'
      };

      const keyMap = {
        'customId': 'custom_id',
        'photoUrl': 'photo_url',
        'avatar': 'photo_url',
        'avatar_url': 'photo_url',
        'hostedRoomId': 'hosted_room_id',
        'activeFrame': 'active_frame',
        'activeHeadwear': 'active_headwear',
        'activeBubble': 'active_bubble',
        'activeEntrance': 'active_entrance',
        'activeCar': 'active_car',
        'activeCover': 'active_cover',
        'activeNecklace': 'active_necklace',
        'activeMicWave': 'active_mic_wave',
        'profileBgUrl': 'profile_bg_url',
        'ownedItems': 'owned_items',
        'ownedBadges': 'owned_badges',
        'ownedNecklaces': 'owned_necklaces',
        'ownedLevelFrames': 'owned_level_frames',
        'ownedLevelBadges': 'owned_level_badges',
        'ownedVipItems': 'owned_vip_items',
        'albums': 'album',
        'countryCode': 'country_code',
        'wealthLevel': 'wealth_level',
        'wealthExp': 'wealth_exp',
        'rechargeLevel': 'recharge_level',
        'rechargeExp': 'recharge_exp',
        'gemsLevel': 'gems_level',
        'gemsExp': 'gems_exp',
        'isRechargeAgent': 'is_recharge_agent',
        'rechargeAgencyName': 'recharge_agency_name',
        'rechargeAgencyLogo': 'recharge_agency_logo',
        'whatsappNumber': 'whatsapp_number',
        'followedRooms': 'followed_rooms',
        'totalGiftsSent': 'total_gifts_sent',
        'totalGiftsReceived': 'total_gifts_received',
      };

      final clean = <String, dynamic>{};
      updates.forEach((k, v) {
        if (v != null) {
          final mappedKey = keyMap[k] ?? k;
          if (allowedColumns.contains(mappedKey)) {
            clean[mappedKey] = v;
          }
        }
      });
      if (clean.isEmpty) return true;
      clean['updated_at'] = DateTime.now().toUtc().toIso8601String();

      final url = Uri.parse('$_baseUrl/rest/v1/users?uid=eq.$uid');
      var res = await http.patch(
        url,
        headers: _headers,
        body: jsonEncode(clean),
      );
      if (res.statusCode >= 300) {
        final altUrl = Uri.parse('$_baseUrl/rest/v1/users?id=eq.$uid');
        res = await http.patch(
          altUrl,
          headers: _headers,
          body: jsonEncode(clean),
        );
      }
      debugPrint('[SupabaseDataService] updateUser ($uid) status: ${res.statusCode}');
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] updateUser error: $e');
      return false;
    }
  }

  Future<UserModel?> getUser(String uid) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return null;
    try {
      // 1. Try uid=eq
      var url = Uri.parse('$_baseUrl/rest/v1/users?uid=eq.$cleanUid&select=*');
      var res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        if (list.isNotEmpty) {
          return UserModel.fromMap(list.first as Map<String, dynamic>);
        }
      }

      // 2. Try id=eq
      url = Uri.parse('$_baseUrl/rest/v1/users?id=eq.$cleanUid&select=*');
      res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        if (list.isNotEmpty) {
          return UserModel.fromMap(list.first as Map<String, dynamic>);
        }
      }

      // 3. Try custom_id=eq
      url = Uri.parse('$_baseUrl/rest/v1/users?custom_id=eq.$cleanUid&select=*');
      res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        if (list.isNotEmpty) {
          return UserModel.fromMap(list.first as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getUser error: $e');
    }
    return null;
  }

  Future<List<UserModel>> getUsersByCustomId(String customId) async {
    final cleanId = customId.trim();
    if (cleanId.isEmpty) return [];
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/users?custom_id=eq.$cleanId&select=*');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => UserModel.fromMap(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getUsersByCustomId error: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final results = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    void addResult(Map<String, dynamic> item) {
      final id = item['uid']?.toString() ?? item['id']?.toString() ?? '';
      if (id.isNotEmpty && !seenIds.contains(id)) {
        seenIds.add(id);
        results.add(item);
      }
    }

    try {
      final q = query.trim();
      if (q.isEmpty) return [];
      final encoded = Uri.encodeComponent(q);

      // 1. Supabase search
      try {
        final isNum = int.tryParse(q) != null;
        final filter = isNum
            ? 'or=(custom_id.eq.$encoded,id.eq.$encoded,uid.eq.$encoded,name.ilike.*$encoded*)'
            : 'or=(custom_id.ilike.*$encoded*,name.ilike.*$encoded*,email.ilike.*$encoded*)';
        final url = Uri.parse('$_baseUrl/rest/v1/users?$filter&select=*&limit=20');
        final res = await http.get(url, headers: _headers);
        if (res.statusCode == 200) {
          final List list = jsonDecode(res.body);
          for (final e in list) {
            addResult(Map<String, dynamic>.from(e as Map));
          }
        }
      } catch (e) {
        debugPrint('[SupabaseDataService] searchUsers supabase error: $e');
      }

      // 2. Firestore fallback search (خصوصاً للـ IDs المميزة المكونة من رقم واحد مثل 1..9)
      try {
        final fs = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
        final intQ = int.tryParse(q);

        // A. البحث بواسطة custom_id نصي أو رقمي
        var qSnap = await fs.collection('users').where('custom_id', isEqualTo: q).limit(5).get();
        for (final doc in qSnap.docs) {
          addResult({'id': doc.id, 'uid': doc.id, ...doc.data()});
        }
        if (intQ != null) {
          qSnap = await fs.collection('users').where('custom_id', isEqualTo: intQ).limit(5).get();
          for (final doc in qSnap.docs) {
            addResult({'id': doc.id, 'uid': doc.id, ...doc.data()});
          }
        }

        // B. البحث بواسطة customId نصي أو رقمي
        qSnap = await fs.collection('users').where('customId', isEqualTo: q).limit(5).get();
        for (final doc in qSnap.docs) {
          addResult({'id': doc.id, 'uid': doc.id, ...doc.data()});
        }
        if (intQ != null) {
          qSnap = await fs.collection('users').where('customId', isEqualTo: intQ).limit(5).get();
          for (final doc in qSnap.docs) {
            addResult({'id': doc.id, 'uid': doc.id, ...doc.data()});
          }
        }

        // C. البحث بواسطة doc ID
        final directDoc = await fs.collection('users').doc(q).get();
        if (directDoc.exists && directDoc.data() != null) {
          addResult({'id': directDoc.id, 'uid': directDoc.id, ...directDoc.data()!});
        }
      } catch (e) {
        debugPrint('[SupabaseDataService] searchUsers firestore error: $e');
      }

      return results;
    } catch (e) {
      debugPrint('[SupabaseDataService] searchUsers error: $e');
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> searchRooms(String query) async {
    try {
      final q = query.trim();
      if (q.isEmpty) return [];
      final encoded = Uri.encodeComponent(q);
      final url = Uri.parse('$_baseUrl/rest/v1/rooms?or=(room_id.ilike.*$encoded*,name.ilike.*$encoded*,host_name.ilike.*$encoded*)&select=*&limit=20');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] searchRooms error: $e');
    }
    return [];
  }

  Future<UserModel?> findUserByIdOrCustomId(String id) async {
    try {
      final cleanId = id.trim();
      if (cleanId.isEmpty) return null;
      final encoded = Uri.encodeComponent(cleanId);
      final intId = int.tryParse(cleanId);

      // 1. Supabase search (custom_id, uid, id)
      try {
        final url = Uri.parse('$_baseUrl/rest/v1/users?or=(custom_id.eq.$encoded,uid.eq.$encoded,id.eq.$encoded)&select=*&limit=1');
        final res = await http.get(url, headers: _headers);
        if (res.statusCode == 200) {
          final List list = jsonDecode(res.body);
          if (list.isNotEmpty) {
            return UserModel.fromMap(Map<String, dynamic>.from(list.first as Map));
          }
        }
      } catch (_) {}

      // 2. Firestore fallback search (خصوصاً للـ IDs المميزة المكونة من رقم واحد)
      try {
        final fs = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');

        // custom_id كـ String
        var qSnap = await fs.collection('users').where('custom_id', isEqualTo: cleanId).limit(1).get();
        if (qSnap.docs.isNotEmpty) {
          final d = qSnap.docs.first.data();
          d['uid'] ??= qSnap.docs.first.id;
          d['id'] ??= qSnap.docs.first.id;
          return UserModel.fromMap(d);
        }

        // custom_id كـ int
        if (intId != null) {
          qSnap = await fs.collection('users').where('custom_id', isEqualTo: intId).limit(1).get();
          if (qSnap.docs.isNotEmpty) {
            final d = qSnap.docs.first.data();
            d['uid'] ??= qSnap.docs.first.id;
            d['id'] ??= qSnap.docs.first.id;
            return UserModel.fromMap(d);
          }
        }

        // customId كـ String
        qSnap = await fs.collection('users').where('customId', isEqualTo: cleanId).limit(1).get();
        if (qSnap.docs.isNotEmpty) {
          final d = qSnap.docs.first.data();
          d['uid'] ??= qSnap.docs.first.id;
          d['id'] ??= qSnap.docs.first.id;
          return UserModel.fromMap(d);
        }

        // customId كـ int
        if (intId != null) {
          qSnap = await fs.collection('users').where('customId', isEqualTo: intId).limit(1).get();
          if (qSnap.docs.isNotEmpty) {
            final d = qSnap.docs.first.data();
            d['uid'] ??= qSnap.docs.first.id;
            d['id'] ??= qSnap.docs.first.id;
            return UserModel.fromMap(d);
          }
        }

        // Document ID مباشر
        final doc = await fs.collection('users').doc(cleanId).get();
        if (doc.exists && doc.data() != null) {
          final d = doc.data()!;
          d['uid'] ??= doc.id;
          d['id'] ??= doc.id;
          return UserModel.fromMap(d);
        }
      } catch (e) {
        debugPrint('[SupabaseDataService] findUserByIdOrCustomId firestore error: $e');
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] findUserByIdOrCustomId error: $e');
    }
    return null;
  }

  Future<List<UserModel>> getAllUsers({int limit = 50}) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/users?select=*&limit=$limit');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => UserModel.fromMap(Map<String, dynamic>.from(e as Map))).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getAllUsers error: $e');
    }
    return [];
  }

  // ═══════════════════════════════════════════════════════
  // BANNERS, GIFTS, ASSETS & CONFIG
  // ═══════════════════════════════════════════════════════

  Future<List<BannerConfig>> getBanners() async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/banners?select=*&order=sort_order.asc');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list
            .map((e) => BannerConfig.fromMap(Map<String, dynamic>.from(e as Map)))
            .where((b) => b.active && b.imageUrl.isNotEmpty)
            .toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getBanners error: $e');
    }
    return [];
  }

  Future<List<gm.GiftModel>> getGifts() async {
    final Map<String, gm.GiftModel> giftMap = {};

    // 1. Fetch from Supabase
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/gifts?select=*&order=sort_order.asc');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        for (final item in list) {
          try {
            final g = gm.GiftModel.fromMap(Map<String, dynamic>.from(item as Map));
            if (g.id.isNotEmpty) giftMap[g.id] = g;
          } catch (err) {
            debugPrint('[SupabaseDataService] Error parsing gift item: $err');
          }
        }
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getGifts Supabase error: $e');
    }

    final list = giftMap.values.toList();
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  Future<List<GiftCategory>> getGiftCategories() async {
    final Map<String, GiftCategory> catMap = {};

    // 1. Fetch from Supabase
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/gift_categories?select=*&order=sort_order.asc');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        for (final item in list) {
          try {
            final c = GiftCategory.fromMap(Map<String, dynamic>.from(item as Map));
            if (c.id.isNotEmpty) catMap[c.id] = c;
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getGiftCategories Supabase error: $e');
    }

    final list = catMap.values.toList();
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  Future<void> saveGiftCategory(GiftCategory cat) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/gift_categories');
      await http.post(
        url,
        headers: {..._headers, 'Prefer': 'resolution=merge-duplicates'},
        body: jsonEncode(cat.toMap()),
      );
    } catch (e) {
      debugPrint('[SupabaseDataService] saveGiftCategory error: $e');
    }
  }

  Future<void> deleteGiftCategory(String id) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/gift_categories?id=eq.$id');
      await http.delete(url, headers: _headers);
    } catch (e) {
      debugPrint('[SupabaseDataService] deleteGiftCategory error: $e');
    }
  }

  Future<void> saveGift(gm.GiftModel gift) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/gifts');
      await http.post(
        url,
        headers: {..._headers, 'Prefer': 'resolution=merge-duplicates'},
        body: jsonEncode(gift.toMap()),
      );
    } catch (e) {
      debugPrint('[SupabaseDataService] saveGift error: $e');
    }
  }

  Future<void> deleteGift(String id) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/gifts?id=eq.$id');
      await http.delete(url, headers: _headers);
    } catch (e) {
      debugPrint('[SupabaseDataService] deleteGift error: $e');
    }
  }

  Future<List<GiftBannerConfig>> getGiftBannerConfigs() async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/gift_banner_configs?select=*');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list
            .map((e) => GiftBannerConfig.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getGiftBannerConfigs error: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getHostAgencyMembers(String agencyId) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/host_agency_members?agency_id=eq.$agencyId&select=*');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getHostAgencyMembers error: $e');
    }
    return [];
  }

  Future<bool> creditHostAgencyMemberDiamonds(String hostUid, int diamondsToAdd) async {
    if (diamondsToAdd <= 0) return true;
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/host_agency_members?or=(host_uid.eq.$hostUid,user_id.eq.$hostUid)&select=*&limit=1');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        if (list.isNotEmpty) {
          final member = Map<String, dynamic>.from(list.first as Map);
          final memId = member['id'];
          final agencyId = member['agency_id']?.toString() ?? '';
          final currentD = (member['diamonds'] as num?)?.toInt() ?? 0;
          final currentBal = (member['diamonds_balance'] as num?)?.toInt() ?? 0;
          final currentMonthly = (member['diamonds_earned_monthly'] as num?)?.toInt() ?? 0;
          final currentCumul = (member['diamonds_earned_cumulative'] as num?)?.toInt() ?? 0;

          final updateUrl = Uri.parse('$_baseUrl/rest/v1/host_agency_members?id=eq.$memId');
          await http.patch(
            updateUrl,
            headers: _headers,
            body: jsonEncode({
              'diamonds': currentD + diamondsToAdd,
              'diamonds_balance': currentBal + diamondsToAdd,
              'diamonds_earned_monthly': currentMonthly + diamondsToAdd,
              'diamonds_earned_cumulative': currentCumul + diamondsToAdd,
            }),
          );

          if (agencyId.isNotEmpty) {
            final agUrl = Uri.parse('$_baseUrl/rest/v1/host_agencies?id=eq.$agencyId&select=total_diamonds_monthly,total_diamonds_cumulative&limit=1');
            final agRes = await http.get(agUrl, headers: _headers);
            if (agRes.statusCode == 200) {
              final List agList = jsonDecode(agRes.body);
              if (agList.isNotEmpty) {
                final ag = Map<String, dynamic>.from(agList.first as Map);
                final agMonthly = (ag['total_diamonds_monthly'] as num?)?.toInt() ?? 0;
                final agCumul = (ag['total_diamonds_cumulative'] as num?)?.toInt() ?? 0;
                await http.patch(
                  Uri.parse('$_baseUrl/rest/v1/host_agencies?id=eq.$agencyId'),
                  headers: _headers,
                  body: jsonEncode({
                    'total_diamonds_monthly': agMonthly + diamondsToAdd,
                    'total_diamonds_cumulative': agCumul + diamondsToAdd,
                  }),
                );
              }
            }
          }
          return true;
        }
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] creditHostAgencyMemberDiamonds error: $e');
    }
    return false;
  }

  Future<List<StoreItemModel>> getStoreItems() async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/store_items?select=*');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list
            .map((e) => StoreItemModel.fromMap(Map<String, dynamic>.from(e as Map)))
            .where((item) => item.isAvailable && !item.isHidden)
            .toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getStoreItems error: $e');
    }
    return [];
  }

  Future<List<RankingFrameConfig>> getRankingFrames() async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/ranking_frames?select=*');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list
            .map((e) => RankingFrameConfig.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getRankingFrames error: $e');
    }
    return [];
  }

  Future<Map<String, AppAssetModel>> getAppAssets() async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/app_assets?select=*');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        final map = <String, AppAssetModel>{};
        for (final item in list) {
          final row = Map<String, dynamic>.from(item as Map);
          if (row['is_active'] != false) {
            final asset = AppAssetModel.fromJson(row);
            if (asset.key.isNotEmpty) {
              map[asset.key] = asset;
            }
          }
        }
        return map;
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getAppAssets error: $e');
    }
    return {};
  }

  Future<Map<String, dynamic>> getAppConfig() async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/app_config?select=*');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        final map = <String, dynamic>{};
        for (final item in list) {
          final row = Map<String, dynamic>.from(item as Map);
          final k = row['key']?.toString();
          if (k != null && k.isNotEmpty) {
            map[k] = row['value'];
          }
        }
        return map;
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getAppConfig error: $e');
    }
    return {};
  }

  Future<bool> recordSentGift({
    required String roomId,
    required String giftId,
    required String giftName,
    String? animationAsset,
    required String senderId,
    required String senderName,
    String? senderPhotoUrl,
    required String receiverId,
    required String receiverName,
    required int value,
    int count = 1,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/sent_gifts');
      final res = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'room_id': roomId,
          'gift_id': giftId,
          'gift_name': giftName,
          'animation_asset': animationAsset,
          'sender_id': senderId,
          'sender_name': senderName,
          'sender_photo_url': senderPhotoUrl,
          'receiver_id': receiverId,
          'receiver_name': receiverName,
          'value': value,
          'count': count,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] recordSentGift error: $e');
      return false;
    }
  }

  Future<List<gm.SentGiftModel>> getSentGifts(String roomId, {int limit = 50}) async {
    try {
      final roomFilter = roomId.isNotEmpty ? 'room_id=eq.$roomId&' : '';
      final url = Uri.parse('$_baseUrl/rest/v1/sent_gifts?${roomFilter}select=*&order=created_at.desc&limit=$limit');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          m['id'] = m['id']?.toString() ?? '';
          m['gift_id'] = m['gift_id']?.toString() ?? '';
          m['sender_id'] = m['sender_id']?.toString() ?? '';
          m['sender_name'] = m['sender_name']?.toString() ?? '';
          m['receiver_id'] = m['receiver_id']?.toString() ?? '';
          m['receiver_name'] = m['receiver_name']?.toString() ?? '';
          m['room_id'] = m['room_id']?.toString() ?? roomId;
          m['value'] = (m['value'] as num?)?.toInt() ?? 0;
          m['count'] = (m['count'] as num?)?.toInt() ?? 1;
          m['created_at'] = m['created_at']?.toString() ?? DateTime.now().toUtc().toIso8601String();
          return gm.SentGiftModel.fromMap(m);
        }).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getSentGifts error: $e');
    }
    return [];
  }

  Future<List<gm.SentGiftModel>> getReceivedGifts(String receiverId, {int limit = 100}) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/sent_gifts?receiver_id=eq.$receiverId&select=*&order=created_at.desc&limit=$limit');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          m['id'] = m['id']?.toString() ?? '';
          m['gift_id'] = m['gift_id']?.toString() ?? '';
          m['sender_id'] = m['sender_id']?.toString() ?? '';
          m['sender_name'] = m['sender_name']?.toString() ?? '';
          m['sender_photo_url'] = m['sender_photo_url']?.toString() ?? '';
          m['receiver_id'] = m['receiver_id']?.toString() ?? receiverId;
          m['receiver_name'] = m['receiver_name']?.toString() ?? '';
          m['room_id'] = m['room_id']?.toString() ?? '';
          m['value'] = (m['value'] as num?)?.toInt() ?? 0;
          m['count'] = (m['count'] as num?)?.toInt() ?? 1;
          m['created_at'] = m['created_at']?.toString() ?? DateTime.now().toUtc().toIso8601String();
          return gm.SentGiftModel.fromMap(m);
        }).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getReceivedGifts error: $e');
    }
    return [];
  }

  Future<List<gm.SentGiftModel>> getAllSentGifts({int limit = 200, DateTime? after}) async {
    try {
      String query = 'select=*&order=created_at.desc&limit=$limit';
      if (after != null) {
        query += '&created_at=gte.${after.toIso8601String()}';
      }
      final url = Uri.parse('$_baseUrl/rest/v1/sent_gifts?$query');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          m['id'] = m['id']?.toString() ?? '';
          m['gift_id'] = m['gift_id']?.toString() ?? '';
          m['sender_id'] = m['sender_id']?.toString() ?? '';
          m['sender_name'] = m['sender_name']?.toString() ?? '';
          m['sender_photo_url'] = m['sender_photo_url']?.toString() ?? '';
          m['receiver_id'] = m['receiver_id']?.toString() ?? '';
          m['receiver_name'] = m['receiver_name']?.toString() ?? '';
          m['room_id'] = m['room_id']?.toString() ?? '';
          m['value'] = (m['value'] as num?)?.toInt() ?? 0;
          m['count'] = (m['count'] as num?)?.toInt() ?? 1;
          m['created_at'] = m['created_at']?.toString() ?? DateTime.now().toUtc().toIso8601String();
          return gm.SentGiftModel.fromMap(m);
        }).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getAllSentGifts error: $e');
    }
    return [];
  }


  Future<List<NotificationModel>> getNotifications({String? uid}) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/notifications?select=*&order=sent_at.desc&limit=50');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return NotificationModel.fromMap(m);
        }).where((n) {
          final target = (n.data?['target'] ?? n.uid).toString();
          if (uid == null || uid.isEmpty || target == 'all' || target.isEmpty || n.uid == uid || target == uid) {
            return true;
          }
          return false;
        }).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getNotifications error: $e');
    }
    return [];
  }

  Future<bool> sendNotification({
    required String uid,
    required String type,
    String actorUid = '',
    String title = '',
    String body = '',
    Map<String, dynamic>? data,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/notifications');
      final res = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'title': title,
          'body': body,
          'target': uid,
          'type': type,
          'actor_uid': actorUid,
          'data': data,
          'is_read': false,
          'sent_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] sendNotification error: $e');
      return false;
    }
  }

  Future<bool> markAllNotificationsRead(String uid) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/notifications?or=(uid.eq.$uid,target.eq.$uid)');
      final res = await http.patch(
        url,
        headers: _headers,
        body: jsonEncode({'is_read': true}),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] markAllNotificationsRead error: $e');
      return false;
    }
  }

  Future<bool> deleteNotification(String notifId) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/notifications?id=eq.$notifId');
      final res = await http.delete(url, headers: _headers);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] deleteNotification error: $e');
      return false;
    }
  }

  Future<bool> updateUserData(String uid, Map<String, dynamic> data) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/users?uid=eq.$uid');
      final res = await http.patch(url, headers: _headers, body: jsonEncode(data));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] updateUserData error: $e');
      return false;
    }
  }

  Future<bool> upsertHostAgency(Map<String, dynamic> agencyData) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/host_agencies');
      final res = await http.post(
        url,
        headers: {..._headers, 'Prefer': 'resolution=merge-duplicates'},
        body: jsonEncode(agencyData),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] upsertHostAgency error: $e');
      return false;
    }
  }

  Future<bool> upsertHostAgencyMember(Map<String, dynamic> memberData) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/host_agency_members');
      final res = await http.post(
        url,
        headers: {..._headers, 'Prefer': 'resolution=merge-duplicates'},
        body: jsonEncode(memberData),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] upsertHostAgencyMember error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getBadges() async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/badges?select=*');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getBadges error: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getNecklaces() async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/necklaces?select=*&order=sort_order.asc');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getNecklaces error: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getLevelConfigs({String? type}) async {
    try {
      final filter = type != null ? '?type=eq.$type&order=level.asc' : '?order=level.asc';
      final url = Uri.parse('$_baseUrl/rest/v1/level_config$filter');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getLevelConfigs error: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getVipConfigs() async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/vip_config?select=*&order=tier.asc');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getVipConfigs error: $e');
    }
    return [];
  }

  Future<bool> submitReport(Map<String, dynamic> data) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/reports');
      final res = await http.post(url, headers: _headers, body: jsonEncode(data));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] submitReport error: $e');
      return false;
    }
  }

  Future<bool> submitBugReport(Map<String, dynamic> data) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/bug_reports');
      final res = await http.post(url, headers: _headers, body: jsonEncode(data));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] submitBugReport error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getUserRanking({
    required String orderByField,
    int limit = 50,
  }) async {
    try {
      final col = orderByField == 'total_gifts_received' ? 'total_gifts_received' : 'total_gifts_sent';
      final url = Uri.parse('$_baseUrl/rest/v1/users?select=uid,id,custom_id,name,photo_url,avatar,level,total_gifts_sent,total_gifts_received&order=$col.desc&limit=$limit');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) {
          final d = Map<String, dynamic>.from(e as Map);
          final uid = d['uid']?.toString() ?? d['id']?.toString() ?? '';
          final customId = (d['custom_id'] ?? d['customId'] ?? uid).toString();
          final photo = (d['photo_url'] ?? d['avatar'] ?? d['photoUrl'] ?? '').toString();
          final sent = (d['total_gifts_sent'] as num?)?.toInt() ?? 0;
          final received = (d['total_gifts_received'] as num?)?.toInt() ?? 0;
          final pts = orderByField == 'total_gifts_received' ? received : sent;
          return <String, dynamic>{
            'uid': uid,
            'id': customId,
            'custom_id': customId,
            'user_id': customId,
            'display_id': customId,
            'name': (d['name'] ?? 'مستخدم').toString(),
            'photo_url': photo,
            'photoUrl': photo,
            'level': (d['level'] as num?)?.toInt() ?? 1,
            'total_gifts_sent': sent,
            'total_gifts_received': received,
            'points': pts,
            'score': pts,
            'total_value': pts,
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getUserRanking error: $e');
    }
    return [];
  }

  Future<Map<String, UserModel>> getUsersMap(List<String> uids) async {
    final Map<String, UserModel> map = {};
    if (uids.isEmpty) return map;
    try {
      final clean = uids.map((u) => u.trim()).where((u) => u.isNotEmpty).toSet().toList();
      for (final id in clean) {
        final u = await getUser(id);
        if (u != null) {
          map[id] = u;
          if (u.uid.isNotEmpty) map[u.uid] = u;
          if (u.customId.isNotEmpty) map[u.customId] = u;
        }
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getUsersMap error: $e');
    }
    return map;
  }

  Future<List<Map<String, dynamic>>> getStoreCategories() async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/store_categories?select=*&order=sort_order.asc');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getStoreCategories error: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getRoomRanking({int limit = 50}) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/rooms?select=*&order=total_gifts.desc&limit=$limit');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) {
          final d = Map<String, dynamic>.from(e as Map);
          return <String, dynamic>{
            'room_id': (d['room_id'] ?? '').toString(),
            'name': (d['name'] ?? '').toString(),
            'room_photo_url': (d['room_photo_url'] ?? d['bg_image'] ?? '').toString(),
            'host_name': (d['host_name'] ?? '').toString(),
            'total_gifts': (d['total_gifts'] as num?)?.toInt() ?? 0,
            'hot_value': (d['hot_value'] as num?)?.toInt() ?? 0,
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getRoomRanking error: $e');
    }
    return [];
  }

  Future<int?> getGiftCpDurationHours(String giftId) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/gifts?id=eq.$giftId&select=cp_gift_duration_hours');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        if (list.isNotEmpty && list[0]['cp_gift_duration_hours'] != null) {
          final val = (list[0]['cp_gift_duration_hours'] as num).toInt();
          if (val > 0) return val;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getHostAgencyForUser(String uid, {String? agencyId}) async {
    try {
      if (agencyId != null && agencyId.isNotEmpty) {
        final url = Uri.parse('$_baseUrl/rest/v1/host_agencies?id=eq.$agencyId&select=*&limit=1');
        final res = await http.get(url, headers: _headers);
        if (res.statusCode == 200) {
          final List list = jsonDecode(res.body);
          if (list.isNotEmpty) return Map<String, dynamic>.from(list[0] as Map);
        }
      }

      final urlOwner = Uri.parse('$_baseUrl/rest/v1/host_agencies?or=(owner_uid.eq.$uid,owner_id.eq.$uid)&select=*&limit=1');
      final resOwner = await http.get(urlOwner, headers: _headers);
      if (resOwner.statusCode == 200) {
        final List list = jsonDecode(resOwner.body);
        if (list.isNotEmpty) return Map<String, dynamic>.from(list[0] as Map);
      }

      final urlMem = Uri.parse('$_baseUrl/rest/v1/host_agency_members?or=(host_uid.eq.$uid,user_id.eq.$uid)&select=agency_id&limit=1');
      final resMem = await http.get(urlMem, headers: _headers);
      if (resMem.statusCode == 200) {
        final List list = jsonDecode(resMem.body);
        if (list.isNotEmpty && list[0]['agency_id'] != null) {
          final aid = list[0]['agency_id'].toString();
          final urlAg = Uri.parse('$_baseUrl/rest/v1/host_agencies?id=eq.$aid&select=*&limit=1');
          final resAg = await http.get(urlAg, headers: _headers);
          if (resAg.statusCode == 200) {
            final List agList = jsonDecode(resAg.body);
            if (agList.isNotEmpty) return Map<String, dynamic>.from(agList[0] as Map);
          }
        }
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getHostAgencyForUser error: $e');
    }
    return null;
  }

  Future<bool> updateUserCustomId(String uid, String newCustomId) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/users?uid=eq.$uid');
      final res = await http.patch(
        url,
        headers: _headers,
        body: jsonEncode({
          'custom_id': newCustomId,
        }),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] updateUserCustomId error: $e');
      return false;
    }
  }

  Future<bool> markStoreItemSold(String itemId) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/store_items?item_id=eq.$itemId');
      final res = await http.patch(
        url,
        headers: _headers,
        body: jsonEncode({
          'is_available': false,
          'is_sold': true,
        }),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) return true;

      final url2 = Uri.parse('$_baseUrl/rest/v1/store_items?id=eq.$itemId');
      final res2 = await http.patch(
        url2,
        headers: _headers,
        body: jsonEncode({
          'is_available': false,
          'is_sold': true,
        }),
      );
      return res2.statusCode >= 200 && res2.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] markStoreItemSold error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // TASKS
  // ═══════════════════════════════════════════════════════

  Future<Map<String, dynamic>> getUserTasksProgress(String uid, String dateKey) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/user_tasks_progress?uid=eq.$uid&date_key=eq.$dateKey');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        final map = <String, dynamic>{};
        for (final row in list) {
          final tId = row['task_id']?.toString() ?? '';
          if (tId.isNotEmpty) {
            map['${tId}_progress'] = row['progress'] ?? 0;
            map['${tId}_claimed'] = row['is_claimed'] == true;
          }
        }
        return map;
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getUserTasksProgress error: $e');
    }
    return {};
  }

  Future<Map<String, dynamic>> getGrowthTasksProgress(String uid) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/growth_tasks_progress?uid=eq.$uid');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        final map = <String, dynamic>{};
        for (final row in list) {
          final tId = row['task_id']?.toString() ?? '';
          if (tId.isNotEmpty) {
            map['${tId}_progress'] = row['progress'] ?? 0;
            map['${tId}_claimed'] = row['is_claimed'] == true;
          }
        }
        return map;
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getGrowthTasksProgress error: $e');
    }
    return {};
  }

  Future<void> recordTaskAction(String uid, String taskId, {int amount = 1, bool isGrowth = false, required String dateKey}) async {
    try {
      if (isGrowth) {
        final checkUrl = Uri.parse('$_baseUrl/rest/v1/growth_tasks_progress?uid=eq.$uid&task_id=eq.$taskId');
        final res = await http.get(checkUrl, headers: _headers);
        if (res.statusCode == 200) {
          final List list = jsonDecode(res.body);
          if (list.isNotEmpty) {
            final cur = (list.first['progress'] as num?)?.toInt() ?? 0;
            await http.patch(checkUrl, headers: _headers, body: jsonEncode({
              'progress': cur + amount,
              'updated_at': DateTime.now().toIso8601String(),
            }));
            return;
          }
        }
        await http.post(
          Uri.parse('$_baseUrl/rest/v1/growth_tasks_progress'),
          headers: _headers,
          body: jsonEncode({
            'uid': uid,
            'task_id': taskId,
            'progress': amount,
            'is_claimed': false,
          }),
        );
      } else {
        final checkUrl = Uri.parse('$_baseUrl/rest/v1/user_tasks_progress?uid=eq.$uid&task_id=eq.$taskId&date_key=eq.$dateKey');
        final res = await http.get(checkUrl, headers: _headers);
        if (res.statusCode == 200) {
          final List list = jsonDecode(res.body);
          if (list.isNotEmpty) {
            final cur = (list.first['progress'] as num?)?.toInt() ?? 0;
            await http.patch(checkUrl, headers: _headers, body: jsonEncode({
              'progress': cur + amount,
              'updated_at': DateTime.now().toIso8601String(),
            }));
            return;
          }
        }
        await http.post(
          Uri.parse('$_baseUrl/rest/v1/user_tasks_progress'),
          headers: _headers,
          body: jsonEncode({
            'uid': uid,
            'task_id': taskId,
            'date_key': dateKey,
            'progress': amount,
            'is_claimed': false,
          }),
        );
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] recordTaskAction error: $e');
    }
  }

  Future<void> claimTask(String uid, String taskId, {bool isGrowth = false, required String dateKey}) async {
    try {
      if (isGrowth) {
        final url = Uri.parse('$_baseUrl/rest/v1/growth_tasks_progress?uid=eq.$uid&task_id=eq.$taskId');
        await http.patch(url, headers: _headers, body: jsonEncode({
          'is_claimed': true,
          'updated_at': DateTime.now().toIso8601String(),
        }));
      } else {
        final url = Uri.parse('$_baseUrl/rest/v1/user_tasks_progress?uid=eq.$uid&task_id=eq.$taskId&date_key=eq.$dateKey');
        await http.patch(url, headers: _headers, body: jsonEncode({
          'is_claimed': true,
          'updated_at': DateTime.now().toIso8601String(),
        }));
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] claimTask error: $e');
    }
  }

  Future<void> followUser(String followerUid, String followingUid) async {
    if (followerUid.isEmpty || followingUid.isEmpty || followerUid == followingUid) return;
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/follows');
      await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'follower_uid': followerUid,
          'following_uid': followingUid,
          'created_at': DateTime.now().toIso8601String(),
        }),
      );
      final followingCount = await getFollowingCount(followerUid);
      final followersCount = await getFollowersCount(followingUid);
      await updateUser(followerUid, {'following': followingCount});
      await updateUser(followingUid, {'followers': followersCount});
    } catch (e) {
      debugPrint('[SupabaseDataService] followUser error: $e');
    }
  }

  Future<void> unfollowUser(String followerUid, String followingUid) async {
    if (followerUid.isEmpty || followingUid.isEmpty || followerUid == followingUid) return;
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/follows?follower_uid=eq.$followerUid&following_uid=eq.$followingUid');
      await http.delete(url, headers: _headers);
      final followingCount = await getFollowingCount(followerUid);
      final followersCount = await getFollowersCount(followingUid);
      await updateUser(followerUid, {'following': followingCount});
      await updateUser(followingUid, {'followers': followersCount});
    } catch (e) {
      debugPrint('[SupabaseDataService] unfollowUser error: $e');
    }
  }

  Future<bool> isFollowing(String followerUid, String followingUid) async {
    if (followerUid.isEmpty || followingUid.isEmpty) return false;
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/follows?follower_uid=eq.$followerUid&following_uid=eq.$followingUid&select=id&limit=1');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.isNotEmpty;
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] isFollowing error: $e');
    }
    return false;
  }

  Future<int> getFollowingCount(String uid) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/follows?follower_uid=eq.$uid&limit=0');
      final res = await http.get(url, headers: {..._headers, 'Prefer': 'count=exact'});
      final cr = res.headers['content-range'];
      if (cr != null && cr.contains('/')) {
        return int.tryParse(cr.split('/').last) ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  Future<int> getFollowersCount(String uid) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/follows?following_uid=eq.$uid&limit=0');
      final res = await http.get(url, headers: {..._headers, 'Prefer': 'count=exact'});
      final cr = res.headers['content-range'];
      if (cr != null && cr.contains('/')) {
        return int.tryParse(cr.split('/').last) ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  Future<int> getVisitorsCount(String uid) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/profile_visits?visited_uid=eq.$uid&limit=0');
      final res = await http.get(url, headers: {..._headers, 'Prefer': 'count=exact'});
      final cr = res.headers['content-range'];
      if (cr != null && cr.contains('/')) {
        return int.tryParse(cr.split('/').last) ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  Future<void> logProfileVisit(String visitedUid, String visitorUid) async {
    if (visitedUid.isEmpty || visitorUid.isEmpty || visitedUid == visitorUid) return;
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/profile_visits');
      await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'visited_uid': visitedUid,
          'visitor_uid': visitorUid,
          'visited_at': DateTime.now().toIso8601String(),
        }),
      );
      final count = await getVisitorsCount(visitedUid);
      await updateUser(visitedUid, {'visitors': count});
    } catch (e) {
      debugPrint('[SupabaseDataService] logProfileVisit error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getFollowingUsers(String uid) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/follows?follower_uid=eq.$uid&select=following_uid&order=created_at.desc&limit=100');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        final uids = list.map((e) => e['following_uid']?.toString() ?? '').where((id) => id.isNotEmpty).toList();
        if (uids.isEmpty) return [];
        return await _getUsersByIds(uids);
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getFollowingUsers error: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getFollowerUsers(String uid) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/follows?following_uid=eq.$uid&select=follower_uid&order=created_at.desc&limit=100');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        final uids = list.map((e) => e['follower_uid']?.toString() ?? '').where((id) => id.isNotEmpty).toList();
        if (uids.isEmpty) return [];
        return await _getUsersByIds(uids);
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getFollowerUsers error: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getVisitorUsers(String uid) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/profile_visits?visited_uid=eq.$uid&select=visitor_uid,visited_at&order=visited_at.desc&limit=50');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        final uids = list.map((e) => e['visitor_uid']?.toString() ?? '').where((id) => id.isNotEmpty && id != uid).toSet().toList();
        if (uids.isEmpty) return [];
        return await _getUsersByIds(uids);
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getVisitorUsers error: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> _getUsersByIds(List<String> uids) async {
    if (uids.isEmpty) return [];
    try {
      final cleanUids = uids.where((id) => id.isNotEmpty).toSet().toList();
      if (cleanUids.isEmpty) return [];

      // 1. PostgREST REST API batch query
      final filter = cleanUids.join(',');
      var url = Uri.parse('$_baseUrl/rest/v1/users?or=(uid.in.($filter),id.in.($filter))&select=uid,id,name,photo_url,avatar,gender,level,country_idx,custom_id');
      var res = await http.get(url, headers: _headers);
      if (res.statusCode != 200) {
        url = Uri.parse('$_baseUrl/rest/v1/users?id=in.($filter)&select=uid,id,name,photo_url,avatar,gender,level,country_idx,custom_id');
        res = await http.get(url, headers: _headers);
      }
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        if (list.isNotEmpty) {
          return list.map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            final photo = m['photo_url']?.toString() ?? m['avatar']?.toString() ?? '';
            final resolvedUid = m['uid']?.toString() ?? m['id']?.toString() ?? '';
            return {
              'uid': resolvedUid,
              'id': resolvedUid,
              'name': m['name'] ?? 'User',
              'photo_url': photo,
              'avatar': photo,
              'gender': m['gender'] ?? 'male',
              'level': (m['level'] as num?)?.toInt() ?? 1,
              'country_idx': (m['country_idx'] as num?)?.toInt() ?? 0,
              'custom_id': m['custom_id'] ?? '',
            };
          }).toList();
        }
      }

      // 2. Individual getUser lookup fallback
      final results = <Map<String, dynamic>>[];
      for (final uid in cleanUids) {
        final user = await getUser(uid);
        if (user != null) {
          results.add({
            'uid': user.uid,
            'id': user.uid,
            'name': user.name,
            'photo_url': user.photoUrl,
            'avatar': user.photoUrl,
            'gender': user.gender,
            'level': user.level,
            'country_idx': 0,
            'custom_id': user.customId,
          });
        }
      }
      if (results.isNotEmpty) return results;
    } catch (e) {
      debugPrint('[SupabaseDataService] _getUsersByIds error: $e');
    }
    return [];
  }

  Future<void> addInventoryItem({
    required String uid,
    required String itemId,
    String? itemType,
    String? name,
    String? icon,
  }) async {
    if (uid.isEmpty || itemId.isEmpty) return;
    try {
      final user = await getUser(uid);
      if (user != null) {
        final List<String> currentOwned = List<String>.from(user.ownedItems);
        if (!currentOwned.contains(itemId)) {
          currentOwned.add(itemId);
          await updateUser(uid, {'owned_items': currentOwned});
        }
      }
      final url = Uri.parse('$_baseUrl/rest/v1/user_inventory');
      await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'user_id': uid,
          'item_id': itemId,
          'item_type': itemType ?? 'backpack',
          'name': name ?? '',
          'icon': icon ?? '',
          'created_at': DateTime.now().toIso8601String(),
        }),
      );
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════
  // GIFTED ITEMS & BACKPACK (SUPABASE)
  // ═══════════════════════════════════════════════════════

  Future<List<GiftedItemModel>> getGiftedItems(String uid) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/gifted_items?uid=eq.$uid&order=sent_at.desc');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => GiftedItemModel.fromMap(Map<String, dynamic>.from(e as Map), e['id'].toString())).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getGiftedItems error: $e');
    }
    return [];
  }

  Future<List<GiftedItemModel>> getGiftedItemsByCategory(String uid, String category) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/gifted_items?uid=eq.$uid&item_category=eq.$category&order=sent_at.desc');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => GiftedItemModel.fromMap(Map<String, dynamic>.from(e as Map), e['id'].toString())).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getGiftedItemsByCategory error: $e');
    }
    return [];
  }

  Future<bool> removeGiftedItem(String id) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/gifted_items?id=eq.$id');
      final res = await http.delete(url, headers: _headers);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] removeGiftedItem error: $e');
      return false;
    }
  }

  Stream<List<GiftedItemModel>> userGiftedItemsStream(String uid) async* {
    yield await getGiftedItems(uid);
    while (true) {
      await Future.delayed(const Duration(seconds: 15));
      yield await getGiftedItems(uid);
    }
  }

  Future<List<Map<String, dynamic>>> getUserBackpack(String uid) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/user_backpack?user_id=eq.$uid');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> deleteUserBackpackItem(String id) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/user_backpack?id=eq.$id');
      final res = await http.delete(url, headers: _headers);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // AGENT RECHARGE TRANSACTIONS (SUPABASE)
  // ═══════════════════════════════════════════════════════

  Future<bool> recordAgentTransaction({
    required String agentId,
    required String targetUid,
    String? targetCustomId,
    required int amountCoins,
    double amountUsd = 0.0,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/agent_recharge_transactions');
      final res = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'id': 'tx_${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4().substring(0, 6)}',
          'agent_id': agentId,
          'target_uid': targetUid,
          'target_custom_id': targetCustomId,
          'amount_coins': amountCoins,
          'amount_usd': amountUsd,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      debugPrint('[SupabaseDataService] recordAgentTransaction status: ${res.statusCode}');
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] recordAgentTransaction error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getAgentTransactions(String agentId, {int limit = 100}) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/agent_recharge_transactions?agent_id=eq.$agentId&order=created_at.desc&limit=$limit');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getAgentTransactions error: $e');
    }
    return [];
  }

  // ═══════════════════════════════════════════════════════
  // BROADCASTS & GLOBAL ANNOUNCEMENTS (SUPABASE)
  // ═══════════════════════════════════════════════════════

  Future<bool> recordBroadcast({
    required String senderUid,
    required String senderName,
    String? senderPhotoUrl,
    required String roomId,
    String? roomName,
    required String content,
    String? giftIcon,
    int? multiplier,
    String type = 'lucky_gift',
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/broadcasts');
      final res = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'id': const Uuid().v4(),
          'sender_uid': senderUid,
          'sender_name': senderName,
          'sender_photo_url': senderPhotoUrl ?? '',
          'room_id': roomId,
          'room_name': roomName ?? '',
          'content': content,
          'gift_icon': giftIcon,
          'multiplier': multiplier,
          'type': type,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] recordBroadcast error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getRecentBroadcasts({int limit = 10}) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/broadcasts?select=*&order=created_at.desc&limit=$limit');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getRecentBroadcasts error: $e');
    }
    return [];
  }

  Future<bool> recordGlobalAnnouncement({
    required String type,
    required String senderName,
    required String giftName,
    required String roomId,
    required int multiplier,
    required int totalWon,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/global_announcements');
      final res = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'id': const Uuid().v4(),
          'type': type,
          'sender_name': senderName,
          'gift_name': giftName,
          'room_id': roomId,
          'multiplier': multiplier,
          'total_won': totalWon,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] recordGlobalAnnouncement error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getRecentGlobalAnnouncements({int limit = 10}) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/global_announcements?select=*&order=created_at.desc&limit=$limit');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getRecentGlobalAnnouncements error: $e');
    }
    return [];
  }

  Future<bool> sendPresencePing(dynamic roomId, String userId) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/room_members');
      final res = await http.post(
        url,
        headers: {
          ..._headers,
          'Prefer': 'resolution=merge-duplicates',
        },
        body: jsonEncode({
          'room_id': roomId.toString(),
          'uid': userId,
          'joined_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      return false;
    }
  }
}


