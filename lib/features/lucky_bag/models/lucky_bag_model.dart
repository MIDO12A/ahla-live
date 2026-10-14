/// المظروف الأحمر / أكياس الحظ (Red Envelope / Lucky Bag) — نموذج البيانات
class LuckyBagModel {
  final String bagId;
  final String roomId;
  final String ownerId;
  final String ownerName;
  final String ownerAvatar;
  final int ownerVip;
  final int ownerLevel;
  final String type; // 'coins' | 'super' | 'gift' | 'gold'
  final String scope; // 'room' | 'mic'
  final int value;
  final int totalBags;
  final int totalShares;
  final int totalValue;
  final int remainingValue;
  final int claimedShares;
  final String greetingText;
  final bool isSuper;
  final String status;
  final String? luckiestUserId;
  final String? luckiestName;
  final int? luckiestAmount;
  final String? createdAt;
  final String? expiresAt;

  const LuckyBagModel({
    required this.bagId,
    required this.roomId,
    required this.ownerId,
    required this.ownerName,
    required this.ownerAvatar,
    this.ownerVip = 0,
    this.ownerLevel = 1,
    required this.type,
    required this.scope,
    required this.value,
    required this.totalBags,
    this.totalShares = 0,
    required this.totalValue,
    this.remainingValue = 0,
    this.claimedShares = 0,
    this.greetingText = '',
    this.isSuper = false,
    this.status = 'active',
    this.luckiestUserId,
    this.luckiestName,
    this.luckiestAmount,
    this.createdAt,
    this.expiresAt,
  });

  factory LuckyBagModel.fromJson(Map<String, dynamic> json) {
    final total = (json['totalShares'] ?? json['total_shares'] ?? json['totalBags'] ?? json['total_bags'] ?? 0).toInt();
    final totalVal = (json['totalValue'] ?? json['total_value'] ?? 0).toInt();
    final remVal = (json['remainingValue'] ?? json['remaining_value'] ?? totalVal).toInt();
    final claimed = (json['claimedShares'] ?? json['claimed_shares'] ?? json['bagsTaken'] ?? json['bags_taken'] ?? 0).toInt();

    return LuckyBagModel(
      bagId: json['bagId']?.toString() ?? json['id']?.toString() ?? json['bag_id']?.toString() ?? '',
      roomId: json['roomId']?.toString() ?? json['room_id']?.toString() ?? '',
      ownerId: json['ownerId']?.toString() ?? json['owner_id']?.toString() ?? '',
      ownerName: json['ownerName']?.toString() ?? json['owner_name']?.toString() ?? '',
      ownerAvatar: json['ownerAvatar']?.toString() ?? json['owner_photo']?.toString() ?? '',
      ownerVip: (json['ownerVip'] ?? json['owner_vip'] ?? 0).toInt(),
      ownerLevel: (json['ownerLevel'] ?? json['owner_level'] ?? 1).toInt(),
      type: json['type']?.toString() ?? 'coins',
      scope: json['scope']?.toString() ?? 'room',
      value: (json['value'] ?? 0).toInt(),
      totalBags: total,
      totalShares: total,
      totalValue: totalVal,
      remainingValue: remVal,
      claimedShares: claimed,
      greetingText: json['greetingText']?.toString() ?? json['greeting_text']?.toString() ?? '',
      isSuper: json['isSuper'] == true || json['is_super'] == true || json['type'] == 'super',
      status: json['status']?.toString() ?? 'active',
      luckiestUserId: json['luckiestUserId']?.toString() ?? json['luckiest_user_id']?.toString(),
      luckiestName: json['luckiestName']?.toString() ?? json['luckiest_name']?.toString(),
      luckiestAmount: json['luckiestAmount'] != null ? (json['luckiestAmount']).toInt() : (json['luckiest_amount'] != null ? (json['luckiest_amount']).toInt() : null),
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString(),
      expiresAt: json['expiresAt']?.toString() ?? json['expires_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'bagId': bagId,
        'roomId': roomId,
        'ownerId': ownerId,
        'ownerName': ownerName,
        'ownerAvatar': ownerAvatar,
        'ownerVip': ownerVip,
        'ownerLevel': ownerLevel,
        'type': type,
        'scope': scope,
        'value': value,
        'totalBags': totalBags,
        'totalShares': totalShares,
        'totalValue': totalValue,
        'remainingValue': remainingValue,
        'claimedShares': claimedShares,
        'greetingText': greetingText,
        'isSuper': isSuper,
        'status': status,
        'luckiestUserId': luckiestUserId,
        'luckiestName': luckiestName,
        'luckiestAmount': luckiestAmount,
        'createdAt': createdAt,
        'expiresAt': expiresAt,
      };
}

/// نموذج نصيب الفائز من المظروف
class LuckyBagClaim {
  final String id;
  final String claimerId;
  final String claimerName;
  final String claimerAvatar;
  final int amount;
  final bool isLuckiest;
  final String createdAt;

  const LuckyBagClaim({
    required this.id,
    required this.claimerId,
    required this.claimerName,
    required this.claimerAvatar,
    required this.amount,
    this.isLuckiest = false,
    this.createdAt = '',
  });

  factory LuckyBagClaim.fromJson(Map<String, dynamic> json) {
    return LuckyBagClaim(
      id: json['id']?.toString() ?? '',
      claimerId: json['claimerId']?.toString() ?? json['claimer_id']?.toString() ?? '',
      claimerName: json['claimerName']?.toString() ?? json['claimer_name']?.toString() ?? 'عضو',
      claimerAvatar: json['claimerAvatar']?.toString() ?? json['claimer_avatar']?.toString() ?? '',
      amount: (json['amount'] ?? 0).toInt(),
      isLuckiest: json['isLuckiest'] == true || json['is_luckiest'] == true,
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
    );
  }
}

/// نتيجة فتح المظروف الأحمر
class LuckyBagClaimResult {
  final bool success;
  final String claimId;
  final String bagId;
  final int amount;
  final int remaining;
  final bool isDone;
  final bool isLuckiest;
  final String? error;

  const LuckyBagClaimResult({
    required this.success,
    this.claimId = '',
    this.bagId = '',
    this.amount = 0,
    this.remaining = 0,
    this.isDone = false,
    this.isLuckiest = false,
    this.error,
  });

  factory LuckyBagClaimResult.fromJson(Map<String, dynamic> json) {
    return LuckyBagClaimResult(
      success: json['success'] == true,
      claimId: json['claimId']?.toString() ?? '',
      bagId: json['bagId']?.toString() ?? '',
      amount: (json['amount'] ?? 0).toInt(),
      remaining: (json['remaining'] ?? 0).toInt(),
      isDone: json['isDone'] == true,
      isLuckiest: json['isLuckiest'] == true || json['is_luckiest'] == true,
      error: json['error']?.toString(),
    );
  }
}

/// حدث التقاط كيس يُبث لكل الغرفة (type: lucky_bag_claim)
class LuckyBagClaimBroadcast {
  final String bagId;
  final String roomId;
  final String claimerName;
  final String claimerAvatar;
  final int amount;
  final int remaining;
  final bool isLuckiest;
  final bool isDone;

  const LuckyBagClaimBroadcast({
    required this.bagId,
    required this.roomId,
    required this.claimerName,
    required this.claimerAvatar,
    required this.amount,
    required this.remaining,
    this.isLuckiest = false,
    required this.isDone,
  });

  factory LuckyBagClaimBroadcast.fromJson(Map<String, dynamic> json) {
    return LuckyBagClaimBroadcast(
      bagId: json['bagId']?.toString() ?? '',
      roomId: json['roomId']?.toString() ?? json['room_id']?.toString() ?? '',
      claimerName: json['claimerName']?.toString() ?? '',
      claimerAvatar: json['claimerAvatar']?.toString() ?? '',
      amount: (json['amount'] ?? 0).toInt(),
      remaining: (json['remaining'] ?? 0).toInt(),
      isLuckiest: json['isLuckiest'] == true || json['is_luckiest'] == true,
      isDone: json['isDone'] == true,
    );
  }
}