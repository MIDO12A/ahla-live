// seat_model.dart
// Data models for room seats and users

enum SeatState { empty, occupied, locked, muted }
enum SeatStyle { classic, circle, heart, square }
enum SeatColor { silver, gold }

class UserModel {
  final String name;
  final String? avatar;
  final String? charm;
  final bool isAdmin;
  final bool isOwner;
  final String? frameAsset;
  final String? id; // uid
  final String? customId; // 8-digit display ID
  final int level;
  final String following;
  final String fans;
  final String visitors;
  final int giftCount;
  final bool isBlacked;
  final String? activeMicWave;
  final String gender;
  final int totalGiftsReceived;

  const UserModel({
    required this.name,
    this.avatar,
    this.charm,
    this.isAdmin = false,
    this.isOwner = false,
    this.frameAsset,
    this.id,
    this.customId,
    this.activeMicWave,
    this.gender = 'male',
    this.level = 1,
    this.following = '0',
    this.fans = '0',
    this.visitors = '0',
    this.giftCount = 0,
    this.isBlacked = false,
    this.totalGiftsReceived = 0,
  });

  UserModel copyWith({
    String? name,
    String? avatar,
    String? charm,
    bool? isAdmin,
    bool? isOwner,
    String? frameAsset,
    String? id,
    String? customId,
    String? activeMicWave,
    String? gender,
    int? level,
    String? following,
    String? fans,
    String? visitors,
    int? giftCount,
    bool? isBlacked,
    int? totalGiftsReceived,
  }) {
    return UserModel(
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      charm: charm ?? this.charm,
      isAdmin: isAdmin ?? this.isAdmin,
      isOwner: isOwner ?? this.isOwner,
      frameAsset: frameAsset ?? this.frameAsset,
      id: id ?? this.id,
      customId: customId ?? this.customId,
      activeMicWave: activeMicWave ?? this.activeMicWave,
      gender: gender ?? this.gender,
      level: level ?? this.level,
      following: following ?? this.following,
      fans: fans ?? this.fans,
      visitors: visitors ?? this.visitors,
      giftCount: giftCount ?? this.giftCount,
      isBlacked: isBlacked ?? this.isBlacked,
      totalGiftsReceived: totalGiftsReceived ?? this.totalGiftsReceived,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'avatar': avatar,
    'charm': charm,
    'isAdmin': isAdmin,
    'isOwner': isOwner,
    'id': id,
    'custom_id': customId,
    'active_mic_wave': activeMicWave,
    'gender': gender,
    'level': level,
    'following': following,
    'fans': fans,
    'visitors': visitors,
    'giftCount': giftCount,
    'isBlacked': isBlacked,
    'totalGiftsReceived': totalGiftsReceived,
  };

  factory UserModel.fromMap(Map<String, dynamic> map) => UserModel(
    name: map['name'] as String? ?? '',
    avatar: map['avatar'] as String?,
    charm: map['charm'] as String?,
    isAdmin: map['isAdmin'] as bool? ?? false,
    isOwner: map['isOwner'] as bool? ?? false,
    frameAsset: map['frameAsset'] as String?,
    id: map['id'] as String?,
    customId: map['custom_id'] as String? ?? map['customId'] as String?,
    activeMicWave: map['active_mic_wave'] as String?,
    gender: map['gender'] as String? ?? 'male',
    level: map['level'] as int? ?? 1,
    following: map['following'] as String? ?? '0',
    fans: map['fans'] as String? ?? '0',
    visitors: map['visitors'] as String? ?? '0',
    giftCount: map['giftCount'] as int? ?? 0,
    isBlacked: map['isBlacked'] as bool? ?? false,
    totalGiftsReceived: map['totalGiftsReceived'] as int? ?? 0,
  );
}

class SeatModel {
  final int index;
  SeatState state;
  UserModel? user;
  bool isMuted;
  bool isLocked;
  bool hasFrame;
  String? frameAsset;
  String? carAsset;
  SeatColor seatColor;
  int lastGiftValue;

  SeatModel({
    required this.index,
    this.state = SeatState.empty,
    this.user,
    this.isMuted = false,
    this.isLocked = false,
    this.hasFrame = false,
    this.frameAsset,
    this.carAsset,
    this.seatColor = SeatColor.silver,
    this.lastGiftValue = 0,
  });

  bool get isEmpty => state == SeatState.empty;
  bool get isOccupied => state == SeatState.occupied;

  SeatModel copyWith({
    SeatState? state,
    UserModel? user,
    bool? isMuted,
    bool? isLocked,
    bool? hasFrame,
    String? frameAsset,
    String? carAsset,
    bool clearUser = false,
    SeatColor? seatColor,
    int? lastGiftValue,
  }) {
    return SeatModel(
      index: index,
      state: state ?? this.state,
      user: clearUser ? null : (user ?? this.user),
      isMuted: isMuted ?? this.isMuted,
      isLocked: isLocked ?? this.isLocked,
      hasFrame: hasFrame ?? this.hasFrame,
      frameAsset: frameAsset ?? this.frameAsset,
      carAsset: carAsset ?? this.carAsset,
      seatColor: seatColor ?? this.seatColor,
      lastGiftValue: lastGiftValue ?? this.lastGiftValue,
    );
  }
}
