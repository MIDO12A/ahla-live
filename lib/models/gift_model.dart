// gift_model.dart
// Data model for gifts

class GiftModel {
  final String id;
  final String name;
  final String nameAr;
  final int value;
  final String iconAsset;
  final String? animationAsset;
  final int type; // 1: normal, 2: luxury/VIP, 3: lucky/crystal, 4: backpack, 5: cp
  final bool isVap;
  final bool isLucky;
  final bool isStar;
  final bool isMusic;
  final bool bigEffect;
  final int packageCount;
  final int sortOrder;
  final String? nameKey; // SVGA layer key for sender name
  final String? photoKey; // SVGA layer key for sender photo
  final String? receiverNameKey; // SVGA layer key for receiver name
  final String? receiverPhotoKey; // SVGA layer key for receiver photo
  final String? countKey; // SVGA layer key for gift count
  final String? defaultImage; // fallback image URL
  final int wealthXp; // XP awarded to sender's wealth level
  final int gemsXp; // XP awarded to receiver's gems level
  final String? categoryId;
  final bool isCpGift;
  final int cpGiftDurationHours;
  final String durationType; // 'days' | 'hours'
  final int durationValue; // e.g. 7 for 7d, 24 for 24h
  final int luckyRtp;
  final int luckyMaxMultiplier;
  final bool luckyBurst;
  final String luckyDisplayMode;

  int get giftType {
    if (type > 0) return type;
    if (isCpGift) return 5;
    if (packageCount > 0) return 4;
    if (isLucky) return 3;
    if (isVap || bigEffect || (animationAsset != null && animationAsset!.isNotEmpty)) return 2;
    return 1;
  }

  String get durationBadge {
    if (durationValue > 0) {
      return '$durationValue${durationType == 'hours' ? 'h' : 'd'}';
    }
    if (cpGiftDurationHours > 0) {
      if (cpGiftDurationHours % 24 == 0) {
        return '${cpGiftDurationHours ~/ 24}d';
      }
      return '${cpGiftDurationHours}h';
    }
    return '';
  }

  const GiftModel({
    required this.id,
    required this.name,
    this.nameAr = '',
    required this.value,
    required this.iconAsset,
    this.animationAsset,
    this.type = 1,
    this.isVap = false,
    this.isLucky = false,
    this.isStar = false,
    this.isMusic = false,
    this.bigEffect = false,
    this.packageCount = 0,
    this.sortOrder = 0,
    this.nameKey,
    this.photoKey,
    this.receiverNameKey,
    this.receiverPhotoKey,
    this.countKey,
    this.defaultImage,
    this.wealthXp = 0,
    this.gemsXp = 0,
    this.categoryId,
    this.isCpGift = false,
    this.cpGiftDurationHours = 0,
    this.durationType = 'days',
    this.durationValue = 0,
    this.luckyRtp = 85,
    this.luckyMaxMultiplier = 100,
    this.luckyBurst = true,
    this.luckyDisplayMode = 'cards',
  });

  GiftModel copyWith({
    String? id,
    String? name,
    String? nameAr,
    int? value,
    String? iconAsset,
    String? animationAsset,
    int? type,
    bool? isVap,
    bool? isLucky,
    bool? isStar,
    bool? isMusic,
    bool? bigEffect,
    int? packageCount,
    int? sortOrder,
    String? nameKey,
    String? photoKey,
    String? receiverNameKey,
    String? receiverPhotoKey,
    String? countKey,
    String? defaultImage,
    int? wealthXp,
    int? gemsXp,
    String? categoryId,
    bool? isCpGift,
    int? cpGiftDurationHours,
    String? durationType,
    int? durationValue,
    int? luckyRtp,
    int? luckyMaxMultiplier,
    bool? luckyBurst,
    String? luckyDisplayMode,
  }) {
    return GiftModel(
      id: id ?? this.id,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      value: value ?? this.value,
      iconAsset: iconAsset ?? this.iconAsset,
      animationAsset: animationAsset ?? this.animationAsset,
      type: type ?? this.type,
      isVap: isVap ?? this.isVap,
      isLucky: isLucky ?? this.isLucky,
      isStar: isStar ?? this.isStar,
      isMusic: isMusic ?? this.isMusic,
      bigEffect: bigEffect ?? this.bigEffect,
      packageCount: packageCount ?? this.packageCount,
      sortOrder: sortOrder ?? this.sortOrder,
      nameKey: nameKey ?? this.nameKey,
      photoKey: photoKey ?? this.photoKey,
      receiverNameKey: receiverNameKey ?? this.receiverNameKey,
      receiverPhotoKey: receiverPhotoKey ?? this.receiverPhotoKey,
      countKey: countKey ?? this.countKey,
      defaultImage: defaultImage ?? this.defaultImage,
      wealthXp: wealthXp ?? this.wealthXp,
      gemsXp: gemsXp ?? this.gemsXp,
      categoryId: categoryId ?? this.categoryId,
      isCpGift: isCpGift ?? this.isCpGift,
      cpGiftDurationHours: cpGiftDurationHours ?? this.cpGiftDurationHours,
      durationType: durationType ?? this.durationType,
      durationValue: durationValue ?? this.durationValue,
      luckyRtp: luckyRtp ?? this.luckyRtp,
      luckyMaxMultiplier: luckyMaxMultiplier ?? this.luckyMaxMultiplier,
      luckyBurst: luckyBurst ?? this.luckyBurst,
      luckyDisplayMode: luckyDisplayMode ?? this.luckyDisplayMode,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'name_ar': nameAr,
        'value': value,
        'price': value,
        'type': giftType,
        'icon_asset': iconAsset,
        'icon_url': iconAsset,
        'animation_asset': animationAsset,
        'svga_url': animationAsset,
        'is_vap': isVap,
        'is_lucky': isLucky,
        'is_star': isStar,
        'is_music': isMusic,
        'big_effect': bigEffect ? 1 : 0,
        'package_count': packageCount,
        'sort_order': sortOrder,
        if (nameKey != null) 'name_key': nameKey,
        if (nameKey != null) 'nameKey': nameKey,
        if (photoKey != null) 'photo_key': photoKey,
        if (photoKey != null) 'photoKey': photoKey,
        if (receiverNameKey != null) 'receiver_name_key': receiverNameKey,
        if (receiverNameKey != null) 'receiverNameKey': receiverNameKey,
        if (receiverPhotoKey != null) 'receiver_photo_key': receiverPhotoKey,
        if (receiverPhotoKey != null) 'receiverPhotoKey': receiverPhotoKey,
        if (countKey != null) 'count_key': countKey,
        if (countKey != null) 'countKey': countKey,
        if (defaultImage != null) 'default_image': defaultImage,
        if (defaultImage != null) 'defaultImage': defaultImage,
        'wealth_xp': wealthXp,
        'gems_xp': gemsXp,
        if (categoryId != null) 'category_id': categoryId,
        'is_cp_gift': isCpGift,
        'cp_gift_duration_hours': cpGiftDurationHours,
        'duration_type': durationType,
        'duration_value': durationValue,
        'lucky_rtp': luckyRtp,
        'lucky_max_multiplier': luckyMaxMultiplier,
        'lucky_burst': luckyBurst,
        'lucky_display_mode': luckyDisplayMode,
      };

  factory GiftModel.fromMap(Map<String, dynamic> map) {
    final dType = map['duration_type']?.toString() ??
        (map['duration_hours'] != null || map['cp_gift_duration_hours'] != null && (map['cp_gift_duration_hours'] as num) < 24
            ? 'hours'
            : 'days');
    final dVal = (map['duration_value'] as num?)?.toInt() ??
        (map['duration_days'] as num?)?.toInt() ??
        (map['durationDays'] as num?)?.toInt() ??
        (map['duration_hours'] as num?)?.toInt() ??
        (map['cp_gift_duration_hours'] as num?)?.toInt() ??
        0;

    final rawType = (map['type'] as num?)?.toInt() ?? 0;
    final catId = map['category_id']?.toString() ?? map['categoryId']?.toString() ?? map['category']?.toString();
    final isLuckyVal = rawType == 3 || (map['is_lucky'] == true) || (map['isLucky'] == true) || catId == 'lucky';
    final isCpVal = rawType == 5 || (map['is_cp_gift'] == true) || (map['isCpGift'] == true) || catId == 'cp';
    final isVipVal = rawType == 2 || (map['is_vap'] == true) || (map['isVap'] == true) || (map['big_effect'] == 1) || (map['bigEffect'] == true) || catId == 'vip' || catId == 'luxury';

    return GiftModel(
      id: map['id']?.toString() ?? map['gift_id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      nameAr: map['name_ar']?.toString() ?? map['nameAr']?.toString() ?? map['englist_name']?.toString() ?? '',
      value: (map['value'] ?? map['price'] ?? 0).toInt(),
      iconAsset: map['icon_asset']?.toString() ?? map['iconAsset']?.toString() ?? map['icon_url']?.toString() ?? map['thumb']?.toString() ?? map['photo']?.toString() ?? '',
      animationAsset: map['animation_asset']?.toString() ?? map['animationAsset']?.toString() ?? map['svga_url']?.toString() ?? map['effect']?.toString() ?? map['mp4_url']?.toString(),
      type: rawType > 0 ? rawType : (isCpVal ? 5 : isLuckyVal ? 3 : isVipVal ? 2 : 1),
      isVap: isVipVal || ((map['is_vap'] ?? map['isVap'] ?? false) as bool),
      isLucky: isLuckyVal,
      isStar: (map['is_star'] ?? map['isStar'] ?? false) as bool,
      isMusic: (map['is_music'] ?? map['isMusic'] ?? false) as bool || (map['isMusic'] == 1),
      bigEffect: (map['big_effect'] == 1) || (map['bigEffect'] == true),
      packageCount: (map['package_count'] ?? map['packageCount'] ?? map['gift_number'] ?? map['number'] ?? 0).toInt(),
      sortOrder: (map['sort_order'] ?? map['sortOrder'] ?? map['sort'] ?? 0).toInt(),
      nameKey: map['name_key']?.toString() ?? map['nameKey']?.toString() ?? map['name_keys']?.toString(),
      photoKey: map['photo_key']?.toString() ?? map['photoKey']?.toString() ?? map['photo_keys']?.toString(),
      receiverNameKey: map['receiver_name_key']?.toString() ?? map['receiverNameKey']?.toString(),
      receiverPhotoKey: map['receiver_photo_key']?.toString() ?? map['receiverPhotoKey']?.toString(),
      countKey: map['count_key']?.toString() ?? map['countKey']?.toString(),
      defaultImage: map['default_image']?.toString() ?? map['defaultImage']?.toString(),
      wealthXp: (map['wealth_xp'] ?? map['wealthXp'] ?? 0).toInt(),
      gemsXp: (map['gems_xp'] ?? map['gemsXp'] ?? map['diamond'] != null ? int.tryParse(map['diamond'].toString()) ?? 0 : 0).toInt(),
      categoryId: catId,
      isCpGift: isCpVal,
      cpGiftDurationHours: (map['cp_gift_duration_hours'] ?? map['cpGiftDurationHours'] ?? (dType == 'days' ? dVal * 24 : dVal)).toInt(),
      durationType: dType,
      durationValue: dVal,
      luckyRtp: (map['lucky_rtp'] ?? map['luckyRtp'] ?? map['rtp'] ?? 85).toInt(),
      luckyMaxMultiplier: (map['lucky_max_multiplier'] ?? map['luckyMaxMultiplier'] ?? map['max_multiplier'] ?? 100).toInt(),
      luckyBurst: (map['lucky_burst'] ?? map['luckyBurst'] ?? true) as bool,
      luckyDisplayMode: map['lucky_display_mode']?.toString() ?? map['luckyDisplayMode']?.toString() ?? 'cards',
    );
  }
}

class SentGiftModel {
  final String id;
  final String giftId;
  final String giftName;
  final String? animationAsset;
  final String? iconAsset;
  final String? defaultImage;
  final String senderId;
  final String senderName;
  final String? senderPhotoUrl;
  final String receiverId;
  final String receiverName;
  final String roomId;
  final int value;
  final int count;
  final DateTime timestamp;

  const SentGiftModel({
    required this.id,
    required this.giftId,
    this.giftName = '',
    this.animationAsset,
    this.iconAsset,
    this.defaultImage,
    required this.senderId,
    required this.senderName,
    this.senderPhotoUrl,
    required this.receiverId,
    required this.receiverName,
    required this.roomId,
    required this.value,
    required this.count,
    required this.timestamp,
  });

  int get totalValue => value * count;

  Map<String, dynamic> toMap() => {
        'id': id,
        'gift_id': giftId,
        'gift_name': giftName,
        'animation_asset': animationAsset,
        'icon_asset': iconAsset,
        'default_image': defaultImage,
        'sender_id': senderId,
        'sender_name': senderName,
        'sender_photo_url': senderPhotoUrl,
        'receiver_id': receiverId,
        'receiver_name': receiverName,
        'room_id': roomId,
        'value': value,
        'count': count,
        'created_at': timestamp.toIso8601String(),
      };

  factory SentGiftModel.fromMap(Map<String, dynamic> map) => SentGiftModel(
        id: map['id'] as String,
        giftId: map['gift_id'] as String,
        giftName: map['gift_name']?.toString() ?? '',
        animationAsset: map['animation_asset']?.toString(),
        iconAsset: map['icon_asset']?.toString() ?? map['gift_icon']?.toString(),
        defaultImage: map['default_image']?.toString() ?? map['image_url']?.toString(),
        senderId: map['sender_id'] as String,
        senderName: map['sender_name'] as String,
        senderPhotoUrl: map['sender_photo_url']?.toString(),
        receiverId: map['receiver_id'] as String,
        receiverName: map['receiver_name'] as String,
        roomId: map['room_id'] as String,
        value: (map['value'] as int?) ?? 0,
        count: (map['count'] as int?) ?? 0,
        timestamp: map['created_at'] is int
            ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
            : DateTime.parse(map['created_at'] as String),
      );
}
