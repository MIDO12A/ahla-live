import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';
import '../models/room_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';

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
      final url = Uri.parse('$_baseUrl/rest/v1/rooms');
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

  Future<RoomModel?> getRoom(String roomId) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/rooms?room_id=eq.$roomId&select=*');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        if (list.isNotEmpty) {
          return RoomModel.fromMap(list.first as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] getRoom error: $e');
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
      final url = Uri.parse('$_baseUrl/rest/v1/room_seats');
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

      final res = await http.post(
        url,
        headers: {
          ..._headers,
          'Prefer': 'resolution=merge-duplicates',
        },
        body: body,
      );

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
      final url = Uri.parse('$_baseUrl/rest/v1/room_seats?room_id=eq.$roomId&seat_index=eq.$seatIndex');
      final res = await http.patch(
        url,
        headers: _headers,
        body: jsonEncode({'is_muted': isMuted}),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] toggleMute error: $e');
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
        return list.map((e) => UserModel.fromMap(e as Map<String, dynamic>)).toList();
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
        'room_id': message.roomId,
        'sender_uid': message.senderUid,
        'sender_name': message.senderName,
        'sender_photo_url': message.senderPhotoUrl,
        'text': message.text,
        'type': message.type,
        'image_url': message.imageUrl ?? '',
        'active_bubble': message.activeBubble,
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
          final m = e as Map<String, dynamic>;
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
      final res = await http.patch(
        url,
        headers: _headers,
        body: jsonEncode(clean),
      );
      debugPrint('[SupabaseDataService] updateUser ($uid) status: ${res.statusCode}');
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[SupabaseDataService] updateUser error: $e');
      return false;
    }
  }

  Future<UserModel?> getUser(String uid) async {
    try {
      final url = Uri.parse('$_baseUrl/rest/v1/users?uid=eq.$uid&select=*');
      final res = await http.get(url, headers: _headers);
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

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      final q = query.trim();
      if (q.isEmpty) return [];
      final encoded = Uri.encodeComponent(q);
      final url = Uri.parse('$_baseUrl/rest/v1/users?or=(custom_id.ilike.*$encoded*,name.ilike.*$encoded*,email.ilike.*$encoded*)&select=*&limit=20');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseDataService] searchUsers error: $e');
    }
    return [];
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
      final url = Uri.parse('$_baseUrl/rest/v1/users?or=(custom_id.eq.$encoded,uid.eq.$encoded)&select=*&limit=1');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        if (list.isNotEmpty) {
          return UserModel.fromMap(Map<String, dynamic>.from(list.first as Map));
        }
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
}

