// seat_model.dart
// Data models for room seats and users — optimized for fast seat switching
//
// ✅ التعديلات الرئيسية:
// 1) كل الحقول أصبحت final (immutable) — يمنع التعديل المباشر بدون setState.
// 2) إضافة أعلام clear* في copyWith — تسمح بمسح القيم (null) بدل تركها عالقة.
// 3) إضافة operator == و hashCode — تمنع rebuilds غير ضرورية عند تغيير مقعد واحد.

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
  final String country;
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
    this.country = 'EG',
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
    String? country,
    int? level,
    String? following,
    String? fans,
    String? visitors,
    int? giftCount,
    bool? isBlacked,
    int? totalGiftsReceived,
    // ✅ أعلام صريحة للمسح — تحل مشكلة "لا يمكن جعلها null"
    bool clearAvatar = false,
    bool clearFrameAsset = false,
    bool clearActiveMicWave = false,
    bool clearCharm = false,
  }) {
    return UserModel(
      name: name ?? this.name,
      avatar: clearAvatar ? null : (avatar ?? this.avatar),
      charm: clearCharm ? null : (charm ?? this.charm),
      isAdmin: isAdmin ?? this.isAdmin,
      isOwner: isOwner ?? this.isOwner,
      frameAsset: clearFrameAsset ? null : (frameAsset ?? this.frameAsset),
      id: id ?? this.id,
      customId: customId ?? this.customId,
      activeMicWave:
      clearActiveMicWave ? null : (activeMicWave ?? this.activeMicWave),
      gender: gender ?? this.gender,
      country: country ?? this.country,
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
    'country': country,
    'country_code': country.toLowerCase(),
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
    charm: map['charm']?.toString() ?? '0',
    isAdmin: map['isAdmin'] as bool? ?? false,
    isOwner: map['isOwner'] as bool? ?? false,
    frameAsset: map['frameAsset'] as String?,
    id: map['id'] as String?,
    customId: map['custom_id'] as String? ?? map['customId'] as String?,
    activeMicWave: map['active_mic_wave'] as String?,
    gender: map['gender'] as String? ?? 'male',
    country:
    map['country'] as String? ?? map['country_code'] as String? ?? 'EG',
    level: map['level'] as int? ?? 1,
    following: map['following'] as String? ?? '0',
    fans: map['fans'] as String? ?? '0',
    visitors: map['visitors'] as String? ?? '0',
    giftCount: map['giftCount'] as int? ?? 0,
    isBlacked: map['isBlacked'] as bool? ?? false,
    totalGiftsReceived: map['totalGiftsReceived'] as int? ?? 0,
  );

  // ✅ المساواة بالقيمة — تمنع rebuilds غير ضرورية
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is UserModel &&
              runtimeType == other.runtimeType &&
              id == other.id &&
              name == other.name &&
              avatar == other.avatar &&
              charm == other.charm &&
              isAdmin == other.isAdmin &&
              isOwner == other.isOwner &&
              frameAsset == other.frameAsset &&
              customId == other.customId &&
              activeMicWave == other.activeMicWave &&
              gender == other.gender &&
              country == other.country &&
              level == other.level &&
              following == other.following &&
              fans == other.fans &&
              visitors == other.visitors &&
              giftCount == other.giftCount &&
              isBlacked == other.isBlacked &&
              totalGiftsReceived == other.totalGiftsReceived;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    avatar,
    charm,
    isAdmin,
    isOwner,
    frameAsset,
    customId,
    activeMicWave,
    gender,
    country,
    level,
    following,
    fans,
    visitors,
    giftCount,
    isBlacked,
    totalGiftsReceived,
  );
}

class SeatModel {
  final int index;
  final SeatState state;
  final UserModel? user;
  final bool isMuted;
  final bool isLocked;
  final bool hasFrame;
  final String? frameAsset;
  final String? carAsset;
  final SeatColor seatColor;
  final int lastGiftValue;

  const SeatModel({
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
  // ✅ المقعد المكتوم ما زال مشغولاً بصاحبه — لازم يفضل ظاهر في
  //    صندوق الهدايا وقائمة المستلمين بدل ما يختفي بعد الميوت.
  bool get isOccupied =>
      state == SeatState.occupied || state == SeatState.muted;

  SeatModel copyWith({
    SeatState? state,
    UserModel? user,
    bool? isMuted,
    bool? isLocked,
    bool? hasFrame,
    String? frameAsset,
    String? carAsset,
    SeatColor? seatColor,
    int? lastGiftValue,
    // ✅ أعلام صريحة للمسح
    bool clearUser = false,
    bool clearFrameAsset = false,
    bool clearCarAsset = false,
  }) {
    return SeatModel(
      index: index,
      state: state ?? this.state,
      user: clearUser ? null : (user ?? this.user),
      isMuted: isMuted ?? this.isMuted,
      isLocked: isLocked ?? this.isLocked,
      hasFrame: hasFrame ?? this.hasFrame,
      frameAsset: clearFrameAsset ? null : (frameAsset ?? this.frameAsset),
      carAsset: clearCarAsset ? null : (carAsset ?? this.carAsset),
      seatColor: seatColor ?? this.seatColor,
      lastGiftValue: lastGiftValue ?? this.lastGiftValue,
    );
  }

  // ✅ المساواة بالقيمة — تمنع rebuild كل المقاعد عند تغيير مقعد واحد
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is SeatModel &&
              runtimeType == other.runtimeType &&
              index == other.index &&
              state == other.state &&
              user == other.user &&
              isMuted == other.isMuted &&
              isLocked == other.isLocked &&
              hasFrame == other.hasFrame &&
              frameAsset == other.frameAsset &&
              carAsset == other.carAsset &&
              seatColor == other.seatColor &&
              lastGiftValue == other.lastGiftValue;

  @override
  int get hashCode => Object.hash(
    index,
    state,
    user,
    isMuted,
    isLocked,
    hasFrame,
    frameAsset,
    carAsset,
    seatColor,
    lastGiftValue,
  );
}