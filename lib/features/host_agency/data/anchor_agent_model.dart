/// نموذج بيانات وكيل المضيفين (AgentInfoBean)
class AgentInfoModel {
  final int userId;
  final int agentBean;
  final int agentGold;
  final int beanNumber;
  final int transferBean;
  final int transferBeanDollar;
  final int transferDollar;
  final int transferMoney;
  final int transferNumber;
  final String agencyName;
  final String avatarUrl;
  final String countryFlagUrl;

  final String agencyId;
  final String? agencyPublicId;
  final double commissionRate;
  final String tier;
  final String notice;
  final int targetDiamonds;
  final double salaryUsd;
  final String rewardType;
  final double rewardValue;
  final String periodType;
  final List<Map<String, dynamic>> milestones;

  const AgentInfoModel({
    this.userId = 0,
    this.agentBean = 0,
    this.agentGold = 0,
    this.beanNumber = 0,
    this.transferBean = 0,
    this.transferBeanDollar = 0,
    this.transferDollar = 0,
    this.transferMoney = 0,
    this.transferNumber = 0,
    this.agencyName = '',
    this.avatarUrl = '',
    this.countryFlagUrl = '',
    this.agencyId = '',
    this.agencyPublicId,
    this.commissionRate = 0.10,
    this.tier = 'bronze',
    this.notice = 'أهلاً بكم في الوكالة الرسمية!',
    this.targetDiamonds = 1000000,
    this.salaryUsd = 0.0,
    this.rewardType = 'salary_usd',
    this.rewardValue = 0.0,
    this.periodType = 'monthly',
    this.milestones = const [],
  });

  factory AgentInfoModel.fromJson(Map<String, dynamic> json) {
    final pubCode = json['agency_code']?.toString() ??
        json['agency_public_id']?.toString() ??
        json['code']?.toString() ??
        json['custom_id']?.toString();
    return AgentInfoModel(
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      agentBean: (json['agent_bean'] as num?)?.toInt() ?? 0,
      agentGold: (json['agent_gold'] as num?)?.toInt() ?? 0,
      beanNumber: (json['bean_number'] as num?)?.toInt() ?? 0,
      transferBean: (json['transfer_bean'] as num?)?.toInt() ?? 0,
      transferBeanDollar: (json['transfer_bean_dollar'] as num?)?.toInt() ?? 0,
      transferDollar: (json['transfer_dollar'] as num?)?.toInt() ?? 0,
      transferMoney: (json['transfer_money'] as num?)?.toInt() ?? (json['total_diamonds_monthly'] as num?)?.toInt() ?? (json['monthly_diamonds'] as num?)?.toInt() ?? 0,
      transferNumber: (json['transfer_number'] as num?)?.toInt() ?? 0,
      agencyName: json['agency_name']?.toString() ?? json['name']?.toString() ?? json['nickname']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString() ?? json['photo_url']?.toString() ?? json['photoUrl']?.toString() ?? json['headImage']?.toString() ?? json['logo_url']?.toString() ?? '',
      countryFlagUrl: json['country_flag_url']?.toString() ?? json['flag_url']?.toString() ?? '',
      agencyId: json['agency_id']?.toString() ?? json['id']?.toString() ?? '',
      agencyPublicId: pubCode,
      commissionRate: (json['commission_rate'] as num?)?.toDouble() ?? 0.10,
      tier: json['tier']?.toString() ?? 'bronze',
      notice: json['notice']?.toString() ?? json['description']?.toString() ?? json['announcement']?.toString() ?? 'أهلاً بكم في الوكالة الرسمية!',
      targetDiamonds: (json['target_diamonds'] as num?)?.toInt() ?? (json['monthly_target'] as num?)?.toInt() ?? 1000000,
      salaryUsd: (json['salary_usd'] as num?)?.toDouble() ?? 0.0,
      rewardType: json['reward_type']?.toString() ?? 'salary_usd',
      rewardValue: (json['reward_value'] as num?)?.toDouble() ?? 0.0,
      periodType: json['period_type']?.toString() ?? 'monthly',
      milestones: (json['milestones'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'agent_bean': agentBean,
        'agent_gold': agentGold,
        'bean_number': beanNumber,
        'transfer_bean': transferBean,
        'transfer_bean_dollar': transferBeanDollar,
        'transfer_dollar': transferDollar,
        'transfer_money': transferMoney,
        'transfer_number': transferNumber,
        'agency_name': agencyName,
        'avatar_url': avatarUrl,
        'country_flag_url': countryFlagUrl,
        'agency_id': agencyId,
        'commission_rate': commissionRate,
        'tier': tier,
        'notice': notice,
        'target_diamonds': targetDiamonds,
        'salary_usd': salaryUsd,
        'reward_type': rewardType,
        'reward_value': rewardValue,
        'period_type': periodType,
        'milestones': milestones,
      };
}

/// نموذج معلومات المضيف التابع للوكالة (AnchorAgentUserInfoDataBean)
class AnchorAgentUserInfoDataModel {
  final int userId;
  final int userNo;
  final String uid;
  final String role;
  final String nickname;
  final String headImage;
  final int country;
  final String countryFlagUrl;
  final int days;
  final double minute;
  final String diamonds;
  final int experience;
  final int level;
  final int recgLevel;
  final int rechargeValue;
  final int sex;
  final int vip;
  final int targetDiamonds;

  const AnchorAgentUserInfoDataModel({
    this.userId = 0,
    this.userNo = 0,
    this.uid = '',
    this.role = 'host',
    this.nickname = '',
    this.headImage = '',
    this.country = 0,
    this.countryFlagUrl = '',
    this.days = 0,
    this.minute = 0.0,
    this.diamonds = '0',
    this.experience = 0,
    this.level = 1,
    this.recgLevel = 0,
    this.rechargeValue = 0,
    this.sex = 1,
    this.vip = 0,
    this.targetDiamonds = 100000,
  });

  String get formattedTime {
    final totalHours = (minute / 60).toStringAsFixed(1);
    return '$days أيام / $totalHours ساعة';
  }

  String get avatarUrl => headImage;
  String get totalDiamond => diamonds;

  double get targetProgress {
    final current = double.tryParse(diamonds) ?? 0.0;
    if (targetDiamonds <= 0) return 0.0;
    return (current / targetDiamonds).clamp(0.0, 1.0);
  }

  factory AnchorAgentUserInfoDataModel.fromJson(Map<String, dynamic> json) {
    return AnchorAgentUserInfoDataModel(
      userId: (json['user_id'] as num?)?.toInt() ?? (json['uid'] != null ? int.tryParse(json['uid'].toString()) ?? 0 : 0),
      userNo: (json['user_no'] as num?)?.toInt() ?? (json['custom_id'] != null ? int.tryParse(json['custom_id'].toString()) ?? 0 : 0),
      uid: json['uid']?.toString() ?? '',
      role: json['role']?.toString() ?? 'host',
      nickname: json['nickname']?.toString() ?? json['name']?.toString() ?? '',
      headImage: json['headImage']?.toString() ?? json['photo_url']?.toString() ?? json['avatar']?.toString() ?? '',
      country: (json['country'] as num?)?.toInt() ?? 0,
      countryFlagUrl: json['country_flag_url']?.toString() ?? '',
      days: (json['days'] as num?)?.toInt() ?? 0,
      minute: (json['minute'] as num?)?.toDouble() ?? 0.0,
      diamonds: json['diamonds']?.toString() ?? json['earnings']?.toString() ?? '0',
      experience: (json['experience'] as num?)?.toInt() ?? 0,
      level: (json['level'] as num?)?.toInt() ?? 1,
      recgLevel: (json['recg_level'] as num?)?.toInt() ?? 0,
      rechargeValue: (json['recharge_value'] as num?)?.toInt() ?? 0,
      sex: (json['sex'] as num?)?.toInt() ?? 1,
      vip: (json['vip'] as num?)?.toInt() ?? 0,
      targetDiamonds: (json['target_diamonds'] as num?)?.toInt() ?? 100000,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'user_no': userNo,
        'nickname': nickname,
        'headImage': headImage,
        'country': country,
        'country_flag_url': countryFlagUrl,
        'days': days,
        'minute': minute,
        'diamonds': diamonds,
        'experience': experience,
        'level': level,
        'recg_level': recgLevel,
        'recharge_value': rechargeValue,
        'sex': sex,
        'vip': vip,
        'target_diamonds': targetDiamonds,
      };
}
