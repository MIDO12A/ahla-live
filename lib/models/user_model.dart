class UserModel {
  final String uid;
  final String customId; // 8-digit numeric ID for display
  final String name;
  final String email;
  final String photoUrl;
  final int coins;
  final int diamonds;
  final String gender;
  final String? activeFrame;
  final String? activeHeadwear;
  final String? activeBubble;
  final String? activeEntrance;
  final String? activeCar;
  final String? activeCover;
  final String? activeNecklace;
  final String? activeMicWave;
  final String? profileBgUrl;
  final List<String> ownedItems;
  final String? hostedRoomId;
  final List<String> followedRooms;
  final int totalGiftsSent;
  final int totalGiftsReceived;
  final int level;
  final int experience;
  final int followers;
  final int following;
  final int visitors;
  final String signature;
  final String country;
  final int age;
  final int charm;
  final List<String> ownedBadges;
  final int wealthLevel;
  final int wealthExp;
  final int rechargeLevel;
  final int rechargeExp;
  final int gemsLevel;
  final int gemsExp;
  final bool banned;
  final String banReason;
  final List<String> ownedLevelFrames;
  final List<String> ownedLevelBadges;
  final List<String> ownedNecklaces;
  final List<Map<String, String>> ownedVipItems;
  final bool isRechargeAgent;
  final String? rechargeAgencyName;
  final String? rechargeAgencyLogo;
  final String? whatsappNumber;
  final List<String> album;

  UserModel({
    required this.uid,
    this.customId = '',
    this.name = '',
    this.email = '',
    this.photoUrl = '',
    this.coins = 0,
    this.diamonds = 0,
    this.gender = 'male',
    this.activeFrame,
    this.activeHeadwear,
    this.activeBubble,
    this.activeEntrance,
    this.activeCar,
    this.activeCover,
    this.activeNecklace,
    this.activeMicWave,
    this.profileBgUrl,
    this.ownedItems = const [],
    this.ownedBadges = const [],
    this.hostedRoomId,
    this.followedRooms = const [],
    this.totalGiftsSent = 0,
    this.totalGiftsReceived = 0,
    this.level = 1,
    this.experience = 0,
    this.followers = 0,
    this.following = 0,
    this.visitors = 0,
    this.signature = '',
    this.country = 'EG',
    this.age = 18,
    this.charm = 0,
    this.wealthLevel = 1,
    this.wealthExp = 0,
    this.rechargeLevel = 1,
    this.rechargeExp = 0,
    this.gemsLevel = 1,
    this.gemsExp = 0,
    this.banned = false,
    this.banReason = '',
    this.ownedLevelFrames = const [],
    this.ownedLevelBadges = const [],
    this.ownedNecklaces = const [],
    this.ownedVipItems = const [],
    this.isRechargeAgent = false,
    this.album = const [],
    this.rechargeAgencyName,
    this.rechargeAgencyLogo,
    this.whatsappNumber,
  });

  UserModel copyWith({
    String? customId,
    String? name,
    String? email,
    String? photoUrl,
    int? coins,
    int? diamonds,
    String? gender,
    String? activeFrame,
    String? activeHeadwear,
    String? activeBubble,
    String? activeEntrance,
    String? activeCar,
    String? activeCover,
    String? activeNecklace,
    String? activeMicWave,
    String? profileBgUrl,
    List<String>? album,
    List<String>? ownedItems,
    String? hostedRoomId,
    List<String>? followedRooms,
    int? totalGiftsSent,
    int? totalGiftsReceived,
    int? level,
    int? experience,
    int? followers,
    int? following,
    int? visitors,
    String? signature,
    String? country,
    int? age,
    int? charm,
    List<String>? ownedBadges,
    int? wealthLevel,
    int? wealthExp,
    int? rechargeLevel,
    int? rechargeExp,
    int? gemsLevel,
    int? gemsExp,
    bool? banned,
    String? banReason,
    List<String>? ownedLevelFrames,
    List<String>? ownedLevelBadges,
    List<String>? ownedNecklaces,
    List<Map<String, String>>? ownedVipItems,
    bool? isRechargeAgent,
    String? rechargeAgencyName,
    String? rechargeAgencyLogo,
    String? whatsappNumber,
  }) {
    return UserModel(
      uid: uid,
      customId: customId ?? this.customId,
      name: name ?? this.name,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      coins: coins ?? this.coins,
      diamonds: diamonds ?? this.diamonds,
      gender: gender ?? this.gender,
      activeFrame: (activeFrame != null && activeFrame.isEmpty) ? null : (activeFrame ?? this.activeFrame),
      activeHeadwear: (activeHeadwear != null && activeHeadwear.isEmpty) ? null : (activeHeadwear ?? this.activeHeadwear),
      activeBubble: (activeBubble != null && activeBubble.isEmpty) ? null : (activeBubble ?? this.activeBubble),
      activeEntrance: (activeEntrance != null && activeEntrance.isEmpty) ? null : (activeEntrance ?? this.activeEntrance),
      activeCar: (activeCar != null && activeCar.isEmpty) ? null : (activeCar ?? this.activeCar),
      activeCover: (activeCover != null && activeCover.isEmpty) ? null : (activeCover ?? this.activeCover),
      activeNecklace: (activeNecklace != null && activeNecklace.isEmpty) ? null : (activeNecklace ?? this.activeNecklace),
      activeMicWave: (activeMicWave != null && activeMicWave.isEmpty) ? null : (activeMicWave ?? this.activeMicWave),
      profileBgUrl: profileBgUrl ?? this.profileBgUrl,
      album: album ?? this.album,
      ownedItems: ownedItems ?? this.ownedItems,
      hostedRoomId: hostedRoomId ?? this.hostedRoomId,
      followedRooms: followedRooms ?? this.followedRooms,
      totalGiftsSent: totalGiftsSent ?? this.totalGiftsSent,
      totalGiftsReceived: totalGiftsReceived ?? this.totalGiftsReceived,
      level: level ?? this.level,
      experience: experience ?? this.experience,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      visitors: visitors ?? this.visitors,
      signature: signature ?? this.signature,
      country: country ?? this.country,
      age: age ?? this.age,
      charm: charm ?? this.charm,
      ownedBadges: ownedBadges ?? this.ownedBadges,
      wealthLevel: wealthLevel ?? this.wealthLevel,
      wealthExp: wealthExp ?? this.wealthExp,
      rechargeLevel: rechargeLevel ?? this.rechargeLevel,
      rechargeExp: rechargeExp ?? this.rechargeExp,
      gemsLevel: gemsLevel ?? this.gemsLevel,
      gemsExp: gemsExp ?? this.gemsExp,
      banned: banned ?? this.banned,
      banReason: banReason ?? this.banReason,
      ownedLevelFrames: ownedLevelFrames ?? this.ownedLevelFrames,
      ownedLevelBadges: ownedLevelBadges ?? this.ownedLevelBadges,
      ownedNecklaces: ownedNecklaces ?? this.ownedNecklaces,
      ownedVipItems: ownedVipItems ?? this.ownedVipItems,
      isRechargeAgent: isRechargeAgent ?? this.isRechargeAgent,
      rechargeAgencyName: rechargeAgencyName ?? this.rechargeAgencyName,
      rechargeAgencyLogo: rechargeAgencyLogo ?? this.rechargeAgencyLogo,
      whatsappNumber: whatsappNumber ?? this.whatsappNumber,
    );
  }

  // FIX: Helper method to safely extract UID from multiple possible field names
  static String _extractUid(Map map) {
    // Try multiple possible field names for uid with null safety
    final possibleUids = [
      map['uid'],
      map['id'],
      map['user_id'],
      map['userId'],
      map['firebase_uid'],
      map['firebaseUid'],
    ];
    
    for (final candidate in possibleUids) {
      if (candidate != null) {
        final strValue = candidate.toString();
        if (strValue.isNotEmpty && strValue != 'null') {
          return strValue;
        }
      }
    }
    
    // Fallback: generate a temporary ID if none found
    return 'temp_${DateTime.now().millisecondsSinceEpoch}';
  }

  // FIX: Helper method to safely extract custom ID from multiple possible field names
  static String _extractCustomId(Map map) {
    // Try multiple possible field names for custom ID with null safety
    final possibleIds = [
      map['custom_id'],
      map['customId'],
      map['customId'],
      map['display_id'],
      map['displayId'],
      map['user_number'],
      map['userNumber'],
      map['id_number'],
      map['idNumber'],
    ];
    
    for (final candidate in possibleIds) {
      if (candidate != null) {
        final strValue = candidate.toString();
        if (strValue.isNotEmpty && strValue != 'null') {
          // Ensure it's a valid numeric string (6-10 digits)
          if (_isValidNumericId(strValue)) {
            return strValue;
          }
        }
      }
    }
    
    // Fallback: try to extract from uid (take last 8 characters if numeric)
    final uid = _extractUid(map);
    if (uid.length >= 8) {
      final last8 = uid.substring(uid.length - 8);
      if (_isValidNumericId(last8)) {
        return last8;
      }
    }
    
    // Final fallback: empty string (will be handled by display widget)
    return '';
  }

  // FIX: Validate that a string is a valid numeric ID (6-10 digits)
  static bool _isValidNumericId(String value) {
    if (value.isEmpty) return false;
    // Remove any non-numeric characters
    final numericOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
    // Check if it's 6-10 digits
    return numericOnly.length >= 6 && numericOnly.length <= 10;
  }

  // FIX: Robust photo URL extraction supporting various schema field names
  static String _extractPhotoUrl(Map map) {
    final possibleKeys = [
      'photo_url',
      'photoUrl',
      'photoURL',
      'avatar',
      'avatar_url',
      'avatarUrl',
      'profile_image',
      'picture',
      'imageUrl',
      'image_url',
    ];
    for (final key in possibleKeys) {
      final val = map[key];
      if (val != null) {
        final s = val.toString().trim();
        if (s.isNotEmpty && s != 'null') {
          return s;
        }
      }
    }
    return '';
  }

  // FIX: Robust album extraction supporting album, albums, photos
  static List<String> _extractAlbum(Map map) {
    final possibleKeys = ['album', 'albums', 'photos'];
    for (final key in possibleKeys) {
      final list = map[key];
      if (list is List && list.isNotEmpty) {
        return list
            .map((e) => e?.toString() ?? '')
            .where((e) => e.isNotEmpty && e != 'null')
            .toList();
      }
    }
    return const [];
  }

  factory UserModel.fromMap(Map map) {
    // FIX: Robust ID extraction with multiple fallback fields
    // Try multiple possible field names for custom ID to ensure compatibility
    final String extractedCustomId = _extractCustomId(map);
    
    return UserModel(
      uid: _extractUid(map),
      customId: extractedCustomId,
      name: map['name']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      photoUrl: _extractPhotoUrl(map),
      album: _extractAlbum(map),
      coins: (map['coins'] ?? 0).toInt(),
      diamonds: (map['diamonds'] ?? 0).toInt(),
      gender: map['gender']?.toString() ?? 'male',
      activeFrame: map['active_frame']?.toString(),
      activeHeadwear: map['active_headwear']?.toString(),
      activeBubble: map['active_bubble']?.toString(),
      activeEntrance: map['active_entrance']?.toString(),
      activeCar: map['active_car']?.toString(),
      activeCover: map['active_cover']?.toString(),
      activeNecklace: map['active_necklace']?.toString(),
      activeMicWave: map['active_mic_wave']?.toString() ?? map['activeMicWave']?.toString(),
      profileBgUrl: map['profile_bg_url']?.toString() ?? map['profileBgUrl']?.toString(),
      ownedItems: (map['owned_items'] as List?)?.map((e) => e.toString()).toList() ?? [],
      ownedBadges: (map['owned_badges'] as List?)?.map((e) => e.toString()).toList() ?? [],
      hostedRoomId: map['hosted_room_id']?.toString(),
      followedRooms: (map['followed_rooms'] as List?)?.map((e) => e.toString()).toList() ?? [],
      totalGiftsSent: (map['total_gifts_sent'] ?? 0).toInt(),
      totalGiftsReceived: (map['total_gifts_received'] ?? 0).toInt(),
      level: (map['level'] ?? 1).toInt(),
      experience: (map['experience'] ?? 0).toInt(),
      followers: (map['followers'] ?? 0).toInt(),
      following: (map['following'] ?? 0).toInt(),
      visitors: (map['visitors'] ?? 0).toInt(),
      signature: map['signature']?.toString() ?? '',
      country: map['country']?.toString() ?? 'EG',
      age: (map['age'] ?? 18).toInt(),
      charm: (map['charm'] ?? 0).toInt(),
      wealthLevel: (map['wealth_level'] ?? 1).toInt(),
      wealthExp: (map['wealth_exp'] ?? 0).toInt(),
      rechargeLevel: (map['recharge_level'] ?? 1).toInt(),
      rechargeExp: (map['recharge_exp'] ?? 0).toInt(),
      gemsLevel: (map['gems_level'] ?? 1).toInt(),
      gemsExp: (map['gems_exp'] ?? 0).toInt(),
      banned: map['banned'] == true,
      banReason: map['ban_reason']?.toString() ?? '',
      ownedLevelFrames: (map['owned_level_frames'] as List?)?.map((e) => e.toString()).toList() ?? [],
      ownedLevelBadges: (map['owned_level_badges'] as List?)?.map((e) => e.toString()).toList() ?? [],
      ownedNecklaces: (map['owned_necklaces'] as List?)?.map((e) => e.toString()).toList() ?? [],
      ownedVipItems: ((map['owned_vip_items'] as List?) ?? const [])
          .map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')))
          .toList(),
      isRechargeAgent: map['is_recharge_agent'] == true ||
          map['isRechargeAgent'] == true ||
          map['is_agent'] == true ||
          map['role'] == 'agent' ||
          map['role'] == 'recharge_agent',
      rechargeAgencyName: map['recharge_agency_name']?.toString(),
      rechargeAgencyLogo: map['recharge_agency_logo']?.toString(),
      whatsappNumber: map['whatsapp_number']?.toString() ?? map['phone']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'custom_id': customId,
        'name': name,
        'email': email,
        'photo_url': photoUrl,
        'photoUrl': photoUrl,
        'avatar': photoUrl,
        'avatar_url': photoUrl,
        'coins': coins,
        'diamonds': diamonds,
        'gender': gender,
        'active_frame': activeFrame,
        'active_headwear': activeHeadwear,
        'active_bubble': activeBubble,
        'active_entrance': activeEntrance,
        'active_car': activeCar,
        'active_cover': activeCover,
        'active_necklace': activeNecklace,
        'active_mic_wave': activeMicWave,
        'profile_bg_url': profileBgUrl,
        'album': album,
        'albums': album,
        'owned_items': ownedItems,
        'owned_badges': ownedBadges,
        'hosted_room_id': hostedRoomId,
        'followed_rooms': followedRooms,
        'total_gifts_sent': totalGiftsSent,
        'total_gifts_received': totalGiftsReceived,
        'level': level,
        'experience': experience,
        'followers': followers,
        'following': following,
        'visitors': visitors,
        'signature': signature,
        'country': country,
        'age': age,
        'charm': charm,
        'wealth_level': wealthLevel,
        'wealth_exp': wealthExp,
        'recharge_level': rechargeLevel,
        'recharge_exp': rechargeExp,
        'gems_level': gemsLevel,
        'gems_exp': gemsExp,
        'banned': banned,
        'ban_reason': banReason,
        'owned_level_frames': ownedLevelFrames,
        'owned_level_badges': ownedLevelBadges,
        'owned_necklaces': ownedNecklaces,
        'owned_vip_items': ownedVipItems,
        'is_recharge_agent': isRechargeAgent,
        'recharge_agency_name': rechargeAgencyName,
        'recharge_agency_logo': rechargeAgencyLogo,
        'whatsapp_number': whatsappNumber,
      };
}
