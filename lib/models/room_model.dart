import 'dart:convert';
import '../screens/room/models/seat_model.dart';

class RoomModel {
  final String roomId;
  final String name;
  final String description;
  final String roomPhotoUrl;
  final String hostUid;
  final String hostName;
  final String hostPhotoUrl;
  final int memberCount;
  final int maxMembers;
  final bool isLocked;
  final String category;
  final int createdAt;
  final String password;
  final int seatCount;
  final SeatStyle seatStyle;
  final SeatColor seatColor;
  final int totalGifts;
  final int hotValue;
  final List<String> moderators;
  final String country;
  final String bgImage;
  final int chatClearedAt;
  final bool isChatLocked;
  final String announcement;

  RoomModel({
    required this.roomId,
    this.name = '',
    this.description = '',
    this.roomPhotoUrl = '',
    this.hostUid = '',
    this.hostName = '',
    this.hostPhotoUrl = '',
    this.memberCount = 0,
    this.maxMembers = 10,
    this.isLocked = false,
    this.category = '',
    this.createdAt = 0,
    this.password = '',
    this.seatCount = 10,
    this.seatStyle = SeatStyle.circle,
    this.seatColor = SeatColor.silver,
    this.totalGifts = 0,
    this.hotValue = 0,
    this.moderators = const [],
    this.country = '',
    this.bgImage = '',
    this.chatClearedAt = 0,
    this.isChatLocked = false,
    this.announcement = '',
  });

  RoomModel copyWith({
    String? roomId,
    String? name,
    String? description,
    String? roomPhotoUrl,
    String? hostUid,
    String? hostName,
    String? hostPhotoUrl,
    int? memberCount,
    int? maxMembers,
    bool? isLocked,
    String? category,
    int? createdAt,
    String? password,
    int? seatCount,
    SeatStyle? seatStyle,
    SeatColor? seatColor,
    int? totalGifts,
    int? hotValue,
    List<String>? moderators,
    String? country,
    String? bgImage,
    int? chatClearedAt,
    bool? isChatLocked,
    String? announcement,
  }) {
    return RoomModel(
      roomId: roomId ?? this.roomId,
      name: name ?? this.name,
      description: description ?? this.description,
      roomPhotoUrl: roomPhotoUrl ?? this.roomPhotoUrl,
      hostUid: hostUid ?? this.hostUid,
      hostName: hostName ?? this.hostName,
      hostPhotoUrl: hostPhotoUrl ?? this.hostPhotoUrl,
      memberCount: memberCount ?? this.memberCount,
      maxMembers: maxMembers ?? this.maxMembers,
      isLocked: isLocked ?? this.isLocked,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      password: password ?? this.password,
      seatCount: seatCount ?? this.seatCount,
      seatStyle: seatStyle ?? this.seatStyle,
      seatColor: seatColor ?? this.seatColor,
      totalGifts: totalGifts ?? this.totalGifts,
      hotValue: hotValue ?? this.hotValue,
      moderators: moderators ?? this.moderators,
      country: country ?? this.country,
      bgImage: bgImage ?? this.bgImage,
      chatClearedAt: chatClearedAt ?? this.chatClearedAt,
      isChatLocked: isChatLocked ?? this.isChatLocked,
      announcement: announcement ?? this.announcement,
    );
  }

  factory RoomModel.fromMap(Map map) {
    return RoomModel(
      roomId: map['room_id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      roomPhotoUrl: map['room_photo_url']?.toString() ?? '',
      hostUid: map['host_uid']?.toString() ?? '',
      hostName: map['host_name']?.toString() ?? '',
      hostPhotoUrl: map['host_photo_url']?.toString() ?? '',
      memberCount: (map['member_count'] ?? 0).toInt(),
      maxMembers: (map['max_members'] ?? 10).toInt(),
      isLocked: map['is_locked'] == true,
      category: map['category']?.toString() ?? '',
      createdAt: map['created_at'] is int
          ? (map['created_at'] as int)
          : DateTime.tryParse(map['created_at']?.toString() ?? '')
                  ?.millisecondsSinceEpoch ?? 0,
      password: map['password']?.toString() ?? '',
      seatCount: (map['seat_count'] ?? 10).toInt(),
      seatStyle: SeatStyle.values[
        (map['seat_style'] is int
            ? map['seat_style'] as int
            : int.tryParse(map['seat_style']?.toString() ?? '') ?? SeatStyle.circle.index)
      ],
      seatColor: SeatColor.values[
        (map['seat_color'] is int
            ? map['seat_color'] as int
            : int.tryParse(map['seat_color']?.toString() ?? '') ?? SeatColor.silver.index)
      ],
      totalGifts: (map['total_gifts'] ?? 0).toInt(),
      hotValue: (map['hot_value'] ?? 0).toInt(),
      moderators: () {
        final m = map['moderators'];
        if (m is List) return m.map((e) => e.toString()).toList();
        if (m is String && m.isNotEmpty) {
          try {
            final decoded = jsonDecode(m);
            if (decoded is List) return decoded.map((e) => e.toString()).toList();
          } catch (_) {}
        }
        return <String>[];
      }(),
      country: map['country']?.toString() ?? '',
      bgImage: map['bgImage']?.toString() ?? map['bg_image']?.toString() ?? '',
      chatClearedAt: (map['chat_cleared_at'] as num?)?.toInt() ?? 0,
      isChatLocked: map['is_chat_locked'] == true,
      announcement: map['announcement']?.toString() ?? map['description']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'room_id': roomId,
        'name': name,
        'description': description,
        'room_photo_url': roomPhotoUrl,
        'host_uid': hostUid,
        'host_name': hostName,
        'host_photo_url': hostPhotoUrl,
        'member_count': memberCount,
        'max_members': maxMembers,
        'is_locked': isLocked,
        'category': category,
        'created_at': createdAt > 0
            ? DateTime.fromMillisecondsSinceEpoch(createdAt).toIso8601String()
            : null,
        'password': password,
        'seat_count': seatCount,
        'seat_style': seatStyle.index.toString(),
        'seat_color': seatColor.index.toString(),
        'total_gifts': totalGifts,
        'hot_value': hotValue,
        'moderators': moderators,
        'country': country,
        'bg_image': bgImage,
        'chat_cleared_at': chatClearedAt,
        'is_chat_locked': isChatLocked,
        'announcement': announcement,
      };
}
