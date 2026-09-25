import 'package:firebase_core/firebase_core.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../screens/room/widgets/svga_player.dart';
import '../../../screens/rank/rank_screen.dart';

/// بيانات المكافأة الفردية داخل مستوى الشحن
class TierRewardItemData {
  final String id;
  final String name;
  final String type; // 'frame', 'entry', 'badge', 'bubble', 'coins', 'gift', 'svga'
  final String icon;
  final String svga;
  final int daysValid;
  final int bonusCoins;

  const TierRewardItemData({
    required this.id,
    required this.name,
    this.type = 'svga',
    required this.icon,
    this.svga = '',
    this.daysValid = 30,
    this.bonusCoins = 0,
  });

  factory TierRewardItemData.fromMap(Map<String, dynamic> map, String fallbackName, String fallbackIcon, String fallbackSvga) {
    return TierRewardItemData(
      id: map['id']?.toString() ?? 'item_${DateTime.now().microsecondsSinceEpoch}',
      name: map['name']?.toString() ?? fallbackName,
      type: map['type']?.toString() ?? 'svga',
      icon: map['icon']?.toString().isNotEmpty == true ? map['icon'].toString() : fallbackIcon,
      svga: map['svga']?.toString().isNotEmpty == true ? map['svga'].toString() : fallbackSvga,
      daysValid: (map['daysValid'] as num?)?.toInt() ?? 30,
      bonusCoins: (map['bonusCoins'] as num?)?.toInt() ?? (map['rewardCoins'] as num?)?.toInt() ?? 0,
    );
  }
}

/// بيانات مستوى الشحن الأسطوري الملكي (المطابق لـ D:40 مع دعم عدد مفتوح من المكافآت)
class RechargeEventTierData {
  final String id;
  final int tier;
  final int targetCoins;
  final String nameAr;
  final String iconAsset;
  final String svgaAsset;
  final String tagText;
  final int durationDays;
  final int bonusCoins;
  final List<TierRewardItemData> rewardsList;

  const RechargeEventTierData({
    required this.id,
    required this.tier,
    required this.targetCoins,
    required this.nameAr,
    required this.iconAsset,
    required this.svgaAsset,
    required this.tagText,
    required this.durationDays,
    required this.bonusCoins,
    this.rewardsList = const [],
  });

  int get totalBonusCoins {
    if (rewardsList.isEmpty) return bonusCoins;
    final sumRewards = rewardsList.fold<int>(0, (acc, item) => acc + item.bonusCoins);
    return sumRewards > 0 ? sumRewards : bonusCoins;
  }

  factory RechargeEventTierData.fromMap(Map<String, dynamic> map, int defaultTier) {
    final t = (map['tier'] as num?)?.toInt() ?? defaultTier;
    final label = map['rewardLabel']?.toString() ?? '${t}00K';
    final icon = map['icon']?.toString().isNotEmpty == true 
        ? map['icon'].toString() 
        : 'assets/recharge_event/$label.png';
    final svga = map['svga']?.toString().isNotEmpty == true 
        ? map['svga'].toString() 
        : '${label.toLowerCase()}.svga';
    final defaultDays = (map['daysValid'] as num?)?.toInt() ?? 30;
    final defaultCoins = (map['rewardCoins'] as num?)?.toInt() ?? 5000;

    List<TierRewardItemData> parsedRewards = [];
    if (map['rewards'] is List && (map['rewards'] as List).isNotEmpty) {
      parsedRewards = (map['rewards'] as List).map((item) {
        return TierRewardItemData.fromMap(Map<String, dynamic>.from(item), label, icon, svga);
      }).toList();
    } else {
      parsedRewards = [
        TierRewardItemData(
          id: 'item_${label}_1',
          name: label,
          type: 'svga',
          icon: icon,
          svga: svga,
          daysValid: defaultDays,
          bonusCoins: defaultCoins,
        ),
      ];
    }

    return RechargeEventTierData(
      id: 'tier_$label',
      tier: t,
      targetCoins: (map['requiredCoins'] as num?)?.toInt() ?? 100000,
      nameAr: label,
      iconAsset: icon,
      svgaAsset: svga,
      tagText: map['tagText']?.toString().isNotEmpty == true ? map['tagText'].toString() : label,
      durationDays: defaultDays,
      bonusCoins: defaultCoins,
      rewardsList: parsedRewards,
    );
  }
}

/// شاشة ونافذة حدث الشحن الملكي الأصلي (D:40 Recharge Event & Dialog)
class RechargeEventScreen extends StatefulWidget {
  final bool isDialog;

  const RechargeEventScreen({super.key, this.isDialog = false});

  /// فتح الحدث كنافذة منبثقة أصلية D:40 (Recharge Remind Dialog)
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      barrierDismissible: true,
      builder: (_) => const Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: RechargeEventScreen(isDialog: true),
      ),
    );
  }

  @override
  State<RechargeEventScreen> createState() => _RechargeEventScreenState();
}

class _RechargeEventScreenState extends State<RechargeEventScreen> {
  // الـ 14 فئة الأصلية الافتراضية المطابقة لـ D:40
  static const List<RechargeEventTierData> _defaultTiers = [
    RechargeEventTierData(id: 'tier_100k', tier: 1, targetCoins: 100000, nameAr: '100K', iconAsset: 'assets/recharge_event/100K.png', svgaAsset: '100k.svga', tagText: 'HOT', durationDays: 7, bonusCoins: 5000),
    RechargeEventTierData(id: 'tier_500k', tier: 2, targetCoins: 500000, nameAr: '500K', iconAsset: 'assets/recharge_event/500K.png', svgaAsset: '500k.svga', tagText: 'VIP', durationDays: 15, bonusCoins: 30000),
    RechargeEventTierData(id: 'tier_1m', tier: 3, targetCoins: 1000000, nameAr: '1M', iconAsset: 'assets/recharge_event/1M.png', svgaAsset: '1M.svga', tagText: '1M', durationDays: 30, bonusCoins: 70000),
    RechargeEventTierData(id: 'tier_5m', tier: 4, targetCoins: 5000000, nameAr: '5M', iconAsset: 'assets/recharge_event/5M.png', svgaAsset: '5M.svga', tagText: '5M', durationDays: 30, bonusCoins: 400000),
    RechargeEventTierData(id: 'tier_10m', tier: 5, targetCoins: 10000000, nameAr: '10M', iconAsset: 'assets/recharge_event/10M.png', svgaAsset: '10M.svga', tagText: '10M', durationDays: 60, bonusCoins: 900000),
    RechargeEventTierData(id: 'tier_20m', tier: 6, targetCoins: 20000000, nameAr: '20M', iconAsset: 'assets/recharge_event/20M.png', svgaAsset: '20m.svga', tagText: '20M', durationDays: 60, bonusCoins: 2000000),
    RechargeEventTierData(id: 'tier_40m', tier: 7, targetCoins: 40000000, nameAr: '40M', iconAsset: 'assets/recharge_event/40M.png', svgaAsset: '40M.svga', tagText: '40M', durationDays: 90, bonusCoins: 4500000),
    RechargeEventTierData(id: 'tier_60m', tier: 8, targetCoins: 60000000, nameAr: '60M', iconAsset: 'assets/recharge_event/60M.png', svgaAsset: '60M.svga', tagText: '60M', durationDays: 90, bonusCoins: 7000000),
    RechargeEventTierData(id: 'tier_80m', tier: 9, targetCoins: 80000000, nameAr: '80M', iconAsset: 'assets/recharge_event/80M.png', svgaAsset: '80M.svga', tagText: '80M', durationDays: 90, bonusCoins: 10000000),
    RechargeEventTierData(id: 'tier_100m', tier: 10, targetCoins: 100000000, nameAr: '100M', iconAsset: 'assets/recharge_event/100M.png', svgaAsset: '100M.svga', tagText: '100M', durationDays: 180, bonusCoins: 14000000),
    RechargeEventTierData(id: 'tier_200m', tier: 11, targetCoins: 200000000, nameAr: '200M', iconAsset: 'assets/recharge_event/200M.png', svgaAsset: '200M.svga', tagText: '200M', durationDays: 180, bonusCoins: 30000000),
    RechargeEventTierData(id: 'tier_300m', tier: 12, targetCoins: 300000000, nameAr: '300M', iconAsset: 'assets/recharge_event/300M.png', svgaAsset: '300M.svga', tagText: '300M', durationDays: 365, bonusCoins: 50000000),
    RechargeEventTierData(id: 'tier_400m', tier: 13, targetCoins: 400000000, nameAr: '400M', iconAsset: 'assets/recharge_event/400M.png', svgaAsset: '400M.svga', tagText: '400M', durationDays: 365, bonusCoins: 75000000),
    RechargeEventTierData(id: 'tier_500m', tier: 14, targetCoins: 500000000, nameAr: '500M', iconAsset: 'assets/recharge_event/500M.png', svgaAsset: '500M.svga', tagText: '500M', durationDays: 365, bonusCoins: 100000000),
  ];

  List<RechargeEventTierData> _tiers = _defaultTiers;
  int _userTotalRecharge = 0;
  List<String> _claimedTiers = [];
  Map<String, int> _claimedCounts = {};

  // إعدادات التصميم والتحكم الديناميكي من اللوحة
  String _titleText = 'اشحن واحصل على مكافآت ملكية فورية';
  Color _titleColor = Colors.white;
  String? _headerTextImage;
  String _dialogBgAsset = 'assets/recharge_event/recharge_remind_dialog_bg.webp';
  String _itemBgAsset = 'assets/recharge_event/recharge_remind_item_bg.webp';
  String _tagAsset = 'assets/recharge_event/recharge_remind_tag_ic.png';
  String _coinsAsset = 'assets/recharge_event/recharge_remind_coins_ic.webp';
  String _btnAsset = 'assets/recharge_event/recharge_remind_btn_ic.webp';
  String _closeBtnAsset = 'assets/recharge_event/recharge_remind_close_ic.png';
  String _btnText = 'اشحن الآن';
  Color _btnTextColor = const Color(0xFF441200);
  Color _tagTextColor = const Color(0xFFFFE957);
  Color _itemLabelColor = const Color(0xFFFFE957);

  Timer? _timer;
  Duration _timeLeft = Duration.zero;

  StreamSubscription? _configSub;
  StreamSubscription? _userSub;
  StreamSubscription? _progressSub;

  @override
  void initState() {
    super.initState();
    _calculateTimeLeft();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _calculateTimeLeft());
    _loadUserProgress();
    _listenToUserProgress();
    _listenToDynamicConfig();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _configSub?.cancel();
    _userSub?.cancel();
    _progressSub?.cancel();
    super.dispose();
  }

  void _calculateTimeLeft() {
    final now = DateTime.now();
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    final diff = endOfMonth.difference(now);
    if (mounted) {
      setState(() {
        _timeLeft = diff.isNegative ? Duration.zero : diff;
      });
    }
  }

  void _listenToDynamicConfig() {
    _configSub = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
        .collection('app_config')
        .doc('general')
        .snapshots()
        .listen((doc) {
      if (!doc.exists) return;
      final data = doc.data();
      if (data == null) return;

      // مستويات الشحن
      if (data['recharge_event_tiers'] is List && (data['recharge_event_tiers'] as List).isNotEmpty) {
        final list = (data['recharge_event_tiers'] as List).asMap().entries.map((e) {
          return RechargeEventTierData.fromMap(Map<String, dynamic>.from(e.value), e.key + 1);
        }).toList();
        if (mounted) setState(() => _tiers = list);
      }

      // إعدادات التصميم والنصوص والألوان
      if (data['recharge_event_settings'] is Map) {
        final s = Map<String, dynamic>.from(data['recharge_event_settings']);
        if (mounted) {
          setState(() {
            if (s['title'] != null) _titleText = s['title'].toString();
            if (s['titleColor'] != null) _titleColor = _parseColor(s['titleColor'], Colors.white);
            _headerTextImage = s['headerTextImage']?.toString().isNotEmpty == true ? s['headerTextImage'].toString() : null;
            if (s['dialogBgImage']?.toString().isNotEmpty == true) _dialogBgAsset = s['dialogBgImage'].toString();
            if (s['itemBgImage']?.toString().isNotEmpty == true) _itemBgAsset = s['itemBgImage'].toString();
            if (s['tagImage']?.toString().isNotEmpty == true) _tagAsset = s['tagImage'].toString();
            if (s['coinsImage']?.toString().isNotEmpty == true) _coinsAsset = s['coinsImage'].toString();
            if (s['btnImage']?.toString().isNotEmpty == true) _btnAsset = s['btnImage'].toString();
            if (s['closeBtnImage']?.toString().isNotEmpty == true) _closeBtnAsset = s['closeBtnImage'].toString();
            if (s['btnText'] != null) _btnText = s['btnText'].toString();
            if (s['btnTextColor'] != null) _btnTextColor = _parseColor(s['btnTextColor'], const Color(0xFF441200));
            if (s['tagTextColor'] != null) _tagTextColor = _parseColor(s['tagTextColor'], const Color(0xFFFFE957));
            if (s['itemLabelColor'] != null) _itemLabelColor = _parseColor(s['itemLabelColor'], const Color(0xFFFFE957));
          });
        }
      }
    }, onError: (_) {});
  }

  Color _parseColor(dynamic hex, Color fallback) {
    if (hex == null) return fallback;
    try {
      String clean = hex.toString().replaceAll('#', '');
      if (clean.length == 6) clean = 'FF$clean';
      return Color(int.parse(clean, radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _loadUserProgress() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final userDoc = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('users').doc(uid).get();
      final rechargedCoins = (userDoc.data()?['recharged_coins'] as num?)?.toInt() ?? 
                            (userDoc.data()?['total_recharge'] as num?)?.toInt() ?? 
                            (userDoc.data()?['total_recharged_coins'] as num?)?.toInt() ?? 0;

      final now = DateTime.now();
      final eventId = 'recharge_${now.year}_${now.month.toString().padLeft(2, '0')}';
      final progressDoc = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
          .collection('recharge_event_progress')
          .doc('${eventId}_$uid')
          .get();

      if (mounted) {
        setState(() {
          _userTotalRecharge = rechargedCoins;
          if (progressDoc.exists) {
            final data = progressDoc.data() ?? {};
            _claimedTiers = List<String>.from(data['claimed_tiers'] ?? []);
            if (data['claimed_counts'] is Map) {
              _claimedCounts = Map<String, int>.from(
                (data['claimed_counts'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
              );
            } else {
              _claimedCounts = {for (final id in _claimedTiers) id: 1};
            }
          }
        });
      }
    } catch (_) {}
  }

  void _listenToUserProgress() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final now = DateTime.now();
    final eventId = 'recharge_${now.year}_${now.month.toString().padLeft(2, '0')}';

    // 1. مراقبة شحن المستخدم المباشر فورياً (عند التحويل من الوكيل أو أداة الإدارة)
    _userSub = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('users').doc(uid).snapshots().listen((doc) {
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      final c1 = (data['recharged_coins'] as num?)?.toInt() ?? 0;
      final c2 = (data['total_recharged_coins'] as num?)?.toInt() ?? 0;
      final c3 = (data['total_recharge'] as num?)?.toInt() ?? 0;
      final maxCoins = [c1, c2, c3, _userTotalRecharge].reduce((curr, next) => curr > next ? curr : next);
      if (mounted && maxCoins != _userTotalRecharge) {
        setState(() => _userTotalRecharge = maxCoins);
      }
    }, onError: (_) {});

    // 2. مراقبة وثيقة تقدم حدث الشحن
    _progressSub = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
        .collection('recharge_event_progress')
        .doc('${eventId}_$uid')
        .snapshots()
        .listen((doc) {
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      final eventCoins = (data['total_recharged_coins'] as num?)?.toInt() ?? 0;
      final claimedList = List<String>.from(data['claimed_tiers'] ?? []);
      Map<String, int> counts = {};
      if (data['claimed_counts'] is Map) {
        counts = Map<String, int>.from(
          (data['claimed_counts'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        );
      } else {
        counts = {for (final id in claimedList) id: 1};
      }

      if (mounted) {
        setState(() {
          if (eventCoins > _userTotalRecharge) {
            _userTotalRecharge = eventCoins;
          }
          _claimedTiers = claimedList;
          _claimedCounts = counts;
        });
      }
    }, onError: (_) {});
  }

  int _getTimesEarned(RechargeEventTierData tier) {
    if (tier.targetCoins <= 0) return 0;
    return _userTotalRecharge ~/ tier.targetCoins;
  }

  int _getTimesClaimed(RechargeEventTierData tier) {
    return _claimedCounts[tier.id] ?? (_claimedTiers.contains(tier.id) ? 1 : 0);
  }

  int _getRemainingClaims(RechargeEventTierData tier) {
    final earned = _getTimesEarned(tier);
    final claimed = _getTimesClaimed(tier);
    final remaining = earned - claimed;
    return remaining > 0 ? remaining : 0;
  }

  Widget _buildImage(String pathOrUrl, {double? width, double? height, BoxFit fit = BoxFit.contain}) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return Image.network(
        pathOrUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => const SizedBox(),
      );
    }
    return Image.asset(
      pathOrUrl,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => const SizedBox(),
    );
  }

  void _previewReward(RechargeEventTierData tier) {
    final remaining = _getRemainingClaims(tier);
    final timesClaimed = _getTimesClaimed(tier);
    final canClaim = remaining > 0;
    final alreadyClaimed = !canClaim && timesClaimed > 0;

    int selectedItemIndex = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141419),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) {
          final currentItem = tier.rewardsList.isNotEmpty && selectedItemIndex < tier.rewardsList.length
              ? tier.rewardsList[selectedItemIndex]
              : TierRewardItemData(
                  id: tier.id,
                  name: tier.nameAr,
                  icon: tier.iconAsset,
                  svga: tier.svgaAsset,
                  daysValid: tier.durationDays,
                  bonusCoins: tier.bonusCoins,
                );

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 18.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 14),

                // Hero Preview (SVGA / Icon)
                SizedBox(
                  width: 135,
                  height: 135,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _buildImage(_itemBgAsset, width: 125, height: 125),
                      if (currentItem.svga.isNotEmpty)
                        SvgaPlayer(
                          key: ValueKey(currentItem.svga),
                          assetPath: currentItem.svga.startsWith('assets/') 
                              ? currentItem.svga 
                              : 'assets/recharge_event/${currentItem.svga}',
                          width: 105,
                          height: 105,
                          fit: BoxFit.contain,
                        )
                      else
                        _buildImage(currentItem.icon, width: 80, height: 80),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                Text(
                  'مستوى ${tier.nameAr}',
                  style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  'تارجت الشحن: ${NumberFormat('#,###').format(tier.targetCoins)} كوينز',
                  style: const TextStyle(color: Color(0xFFFFE957), fontSize: 13, fontWeight: FontWeight.bold),
                ),

                // قائمة الجوائز المتعددة إذا كان المستوى يحتوي أكثر من جائزة
                if (tier.rewardsList.length > 1) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '🎁 باقة الجوائز الملكية (${tier.rewardsList.length} مكافآت):',
                        style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const Text(
                        'اضغط لمعاينة أي جائزة',
                        style: TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 78,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: tier.rewardsList.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, idx) {
                        final item = tier.rewardsList[idx];
                        final isSelected = idx == selectedItemIndex;

                        return GestureDetector(
                          onTap: () {
                            setSheetState(() => selectedItemIndex = idx);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 68,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                                  : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? const Color(0xFFFFD700) : Colors.white12,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: _buildImage(item.icon, width: 32, height: 32),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isSelected ? const Color(0xFFFFD700) : Colors.white70,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${item.daysValid} يوم',
                                  style: const TextStyle(color: Colors.white38, fontSize: 8),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 10),
                // تفاصيل المكافأة المعروضة حالياً
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'الجائزة: ${currentItem.name}',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'الصلاحية: ${currentItem.daysValid} يوم | +${NumberFormat('#,###').format(tier.totalBonusCoins)} كوينز',
                        style: const TextStyle(color: Color(0xFFFFE957), fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),

                if (timesClaimed > 0 || remaining > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'تم الاستلام سابقاً: $timesClaimed مرة | متاح للاستلام الآن: $remaining مرة',
                      style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canClaim 
                          ? Colors.amber 
                          : (alreadyClaimed ? Colors.grey.shade800 : const Color(0xFFFF9800)),
                      foregroundColor: canClaim ? Colors.black : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      if (canClaim) {
                        _claimTierReward(tier);
                      } else if (!alreadyClaimed) {
                        _onGoNow();
                      }
                    },
                    child: Text(
                      canClaim
                          ? (remaining > 1
                              ? 'استلام باقة المكافآت (${tier.rewardsList.length} جوائز - متبقي $remaining) 🎁'
                              : 'استلام باقة المكافآت (${tier.rewardsList.length} جوائز) 🎁')
                          : (alreadyClaimed
                              ? 'تم استلام المكافأة ($timesClaimed مرة)'
                              : 'اشحن للوصول لهذا المستوى'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _claimTierReward(RechargeEventTierData tier) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final remaining = _getRemainingClaims(tier);
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لقد قمت باستلام جميع المكافآت المتاحة لهذا المستوى! اشحن للمزيد.')),
      );
      return;
    }

    final now = DateTime.now();
    final eventId = 'recharge_${now.year}_${now.month.toString().padLeft(2, '0')}';

    try {
      final docRef = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('recharge_event_progress').doc('${eventId}_$uid');
      final currentClaimed = _getTimesClaimed(tier);
      final newCount = currentClaimed + 1;
      final updatedCounts = Map<String, int>.from(_claimedCounts);
      updatedCounts[tier.id] = newCount;
      final newClaimedTiers = Set<String>.from(_claimedTiers)..add(tier.id);

      await docRef.set({
        'user_id': uid,
        'event_id': eventId,
        'total_recharged_coins': _userTotalRecharge,
        'claimed_tiers': newClaimedTiers.toList(),
        'claimed_counts': updatedCounts,
        'updated_at': now.toIso8601String(),
      }, SetOptions(merge: true));

      // إضافة جميع المكافآت في حزمة المستوى إلى حقيبة المستخدم
      final backpack = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('user_backpack');
      for (final item in tier.rewardsList) {
        await backpack.add({
          'user_id': uid,
          'item_id': item.id,
          'name': item.name,
          'type': item.type,
          'icon_url': item.icon,
          'svga_url': item.svga,
          'expires_at': now.add(Duration(days: item.daysValid)).toIso8601String(),
          'created_at': now.toIso8601String(),
          'is_equipped': true,
          'claim_round': newCount,
        });
      }

      // إضافة مجموع الكوينز البونص لهذا المستوى
      final totalBonus = tier.totalBonusCoins;
      if (totalBonus > 0) {
        await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('users').doc(uid).update({
          'coins': FieldValue.increment(totalBonus),
        });
      }

      if (mounted) {
        setState(() {
          _claimedTiers = newClaimedTiers.toList();
          _claimedCounts = updatedCounts;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 تهانينا! تم استلام باقة مكافآت ${tier.nameAr} (${tier.rewardsList.length} جوائز وبونص $totalBonus كوينز) بنجاح!'),
            backgroundColor: Colors.green.shade800,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء الاستلام: $e')),
      );
    }
  }

  void _onGoNow() {
    if (widget.isDialog) {
      Navigator.pop(context);
    }
    Navigator.of(context).pushNamed('/wallet_recharge');
  }

  void _showRankingDialog() {
    final now = DateTime.now();
    final eventId = 'recharge_${now.year}_${now.month.toString().padLeft(2, '0')}';
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14121F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.80,
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          gradient: LinearGradient(
            colors: [Color(0xFF1C172B), Color(0xFF0F0D17)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            // المقبض العلوي
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),

            // الترويسة
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 24),
                      SizedBox(width: 8),
                      Text(
                        'ترتيب كبار شاحني الحدث',
                        style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RankScreen()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.open_in_new, color: Color(0xFFFFD700), size: 14),
                          SizedBox(width: 4),
                          Text(
                            'الترتيب العام',
                            style: TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(color: Colors.white12, height: 1),

            // قائمة المتصدرين الحية
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
                    .collection('recharge_event_progress')
                    .where('event_id', isEqualTo: eventId)
                    .orderBy('total_recharged_coins', descending: true)
                    .limit(30)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)));
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.military_tech_outlined, color: Colors.white24, size: 54),
                          SizedBox(height: 12),
                          Text(
                            'كن أول من يشحن ويتصدر قائمة هذا الشهر!',
                            style: TextStyle(color: Colors.white60, fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final docData = docs[index].data() as Map<String, dynamic>;
                      final targetUid = docData['user_id']?.toString() ?? '';
                      final coins = (docData['total_recharged_coins'] as num?)?.toInt() ?? 0;
                      final isMe = targetUid == currentUid;

                      Color rankColor;
                      IconData? crownIcon;
                      if (index == 0) {
                        rankColor = const Color(0xFFFFD700);
                        crownIcon = Icons.military_tech;
                      } else if (index == 1) {
                        rankColor = const Color(0xFFE0E0E0);
                        crownIcon = Icons.military_tech;
                      } else if (index == 2) {
                        rankColor = const Color(0xFFCD7F32);
                        crownIcon = Icons.military_tech;
                      } else {
                        rankColor = Colors.white54;
                      }

                      return FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('users').doc(targetUid).get(),
                        builder: (context, userSnap) {
                          final userData = userSnap.data?.data() as Map<String, dynamic>?;
                          final name = userData?['name']?.toString() ?? 'مستخدم';
                          final photoUrl = userData?['photo_url']?.toString() ?? userData?['photoUrl']?.toString();
                          final customId = userData?['custom_id']?.toString() ?? userData?['customId']?.toString() ?? '';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? const Color(0xFFFFD700).withValues(alpha: 0.12)
                                  : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isMe
                                    ? const Color(0xFFFFD700).withValues(alpha: 0.6)
                                    : (index < 3 ? rankColor.withValues(alpha: 0.3) : Colors.white10),
                                width: isMe ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                // الرقم / المركز
                                SizedBox(
                                  width: 34,
                                  child: crownIcon != null
                                      ? Icon(crownIcon, color: rankColor, size: 24)
                                      : Text(
                                          '#${index + 1}',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: rankColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 8),

                                // الصورة
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Colors.white12,
                                  backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                                      ? NetworkImage(photoUrl)
                                      : null,
                                  child: photoUrl == null || photoUrl.isEmpty
                                      ? const Icon(Icons.person, color: Colors.white60, size: 22)
                                      : null,
                                ),
                                const SizedBox(width: 12),

                                // الاسم والمعرف
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: isMe ? const Color(0xFFFFD700) : Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          if (isMe) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.amber,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text('أنت', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (customId.isNotEmpty)
                                        Text(
                                          'ID: $customId',
                                          style: const TextStyle(color: Colors.white38, fontSize: 10),
                                        ),
                                    ],
                                  ),
                                ),

                                // مجموع الشحن
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      NumberFormat('#,###').format(coins),
                                      style: const TextStyle(
                                        color: Color(0xFFFFE957),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const Text('🪙 كوينز', style: TextStyle(color: Colors.white54, fontSize: 9)),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRulesDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF181524),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFFFD700), width: 1),
        ),
        title: const Text(
          '📜 قواعد حدث الشحن الملكي',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFFFD700), fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              '1. يتم احتساب جميع عمليات الشحن التراكمية خلال الشهر الحالي.',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
            SizedBox(height: 6),
            Text(
              '2. عند الوصول لتارجت أي مستوى يمكنك المطالبة بالمكافأة وبونص الكوينز فوراً.',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
            SizedBox(height: 6),
            Text(
              '3. مؤثرات الـ SVGA والجوائز الملكية تُضاف مباشرة إلى حقيبة المستخدم وتُفعّل تلقائياً.',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
            SizedBox(height: 6),
            Text(
              '4. يتجدد الحدث في بداية كل شهر ميلادي مع مكافآت جديدة.',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً', style: TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isDialog) {
      return _buildAuthenticDialogView();
    }
    return _buildFullScreenEventView();
  }

  // ══════════════════════════════════════════════════════════════
  // 1. نمط النافذة المنبثقة الأصلية D:40 (Recharge Remind Dialog)
  // ══════════════════════════════════════════════════════════════
  Widget _buildAuthenticDialogView() {
    return Center(
      child: SizedBox(
        width: 312,
        height: 460,
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            // خلفية القوس الملكي
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 385,
              child: _buildImage(_dialogBgAsset, width: 312, height: 385, fit: BoxFit.fill),
            ),

            // زر الترتيب الملكي في النافذة المنبثقة
            Positioned(
              top: 14,
              right: 14,
              child: GestureDetector(
                onTap: _showRankingDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFF8F00)]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.emoji_events, color: Color(0xFF3E1F00), size: 14),
                      SizedBox(width: 3),
                      Text('الترتيب', style: TextStyle(color: Color(0xFF3E1F00), fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),

            // عنوان الحدث أو صورة البانر المصممة
            Positioned(
              top: 96,
              left: 20,
              right: 20,
              child: _headerTextImage != null && _headerTextImage!.isNotEmpty
                  ? _buildImage(_headerTextImage!, height: 32, fit: BoxFit.contain)
                  : Text(
                      _titleText,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _titleColor,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
                        ],
                      ),
                    ),
            ),

            // شبكة الـ 3 أعمدة
            Positioned(
              top: 130,
              left: 14,
              right: 14,
              bottom: 84,
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                physics: const BouncingScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 0.76,
                ),
                itemCount: _tiers.length,
                itemBuilder: (context, index) {
                  final tier = _tiers[index];
                  return _buildTierItemCard(tier);
                },
              ),
            ),

            // كومة الكوينز السفلية
            Positioned(
              bottom: 46,
              left: 6,
              right: 6,
              height: 48,
              child: IgnorePointer(
                child: _buildImage(_coinsAsset, height: 48, fit: BoxFit.contain),
              ),
            ),

            // زر الشحن الذهبي
            Positioned(
              bottom: 24,
              child: GestureDetector(
                onTap: _onGoNow,
                child: SizedBox(
                  width: 142,
                  height: 50,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _buildImage(_btnAsset, width: 142, height: 50, fit: BoxFit.contain),
                      Text(
                        _btnText,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: _btnTextColor,
                          shadows: const [
                            Shadow(color: Color(0x66FFEB3B), blurRadius: 6, offset: Offset(0, 1)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // زر الإغلاق
            Positioned(
              bottom: -22,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 34,
                  height: 34,
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(shape: BoxShape.circle),
                  child: _buildImage(_closeBtnAsset, width: 26, height: 26),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 2. نمط شاشة الحدث الكاملة الفخمة (Full Event Screen)
  // ══════════════════════════════════════════════════════════════
  Widget _buildFullScreenEventView() {
    // حساب المستوى التالي
    RechargeEventTierData? nextTier;
    for (final t in _tiers) {
      if (_userTotalRecharge < t.targetCoins) {
        nextTier = t;
        break;
      }
    }
    final progress = nextTier != null
        ? (_userTotalRecharge / nextTier.targetCoins).clamp(0.0, 1.0)
        : 1.0;

    final days = _timeLeft.inDays;
    final hours = _timeLeft.inHours % 24;
    final minutes = _timeLeft.inMinutes % 60;
    final seconds = _timeLeft.inSeconds % 60;
    final timeStr = '$days يوم ${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: const Color(0xFF0C0A14),
      body: Stack(
        children: [
          // خلفية ملكية بتدرج أرجواني داكن مع ذهبي
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF22170D),
                    Color(0xFF140F22),
                    Color(0xFF090710),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          // المحتوى الرئيسي القابل للتمرير
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // الرأس الملكي للحدث (Header Royal Banner)
              SliverToBoxAdapter(
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    // صورة القوس والتاج الملكي من D:40 ممتدة بعرض الشاشة
                    SizedBox(
                      width: double.infinity,
                      height: 250,
                      child: ShaderMask(
                        shaderCallback: (rect) {
                          return const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black, Colors.black, Colors.transparent],
                            stops: [0.0, 0.75, 1.0],
                          ).createShader(rect);
                        },
                        blendMode: BlendMode.dstIn,
                        child: _buildImage(
                          _dialogBgAsset,
                          width: double.infinity,
                          height: 250,
                          fit: BoxFit.fitWidth,
                        ),
                      ),
                    ),

                    // الترويسة وأزرار التحكم
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                              ),
                            ),
                            _headerTextImage != null && _headerTextImage!.isNotEmpty
                                ? _buildImage(_headerTextImage!, height: 36, fit: BoxFit.contain)
                                : const Text(
                                    '⚡ حدث الشحن الملكي الأسطوري',
                                    style: TextStyle(
                                      color: Color(0xFFFFD700),
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(color: Colors.black, blurRadius: 4),
                                      ],
                                    ),
                                  ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: _showRankingDialog,
                                  child: Container(
                                    height: 38,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFFFFD700), Color(0xFFFF8F00)],
                                      ),
                                      borderRadius: BorderRadius.circular(19),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.emoji_events, color: Color(0xFF3E1F00), size: 18),
                                        SizedBox(width: 4),
                                        Text(
                                          'الترتيب',
                                          style: TextStyle(
                                            color: Color(0xFF3E1F00),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: _showRulesDialog,
                                  child: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white24),
                                    ),
                                    child: const Icon(Icons.info_outline, color: Color(0xFFFFD700), size: 20),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // شارة العداد التنازلي ونبذة الحدث
                    Positioned(
                      top: 100,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.6), width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.timer_outlined, color: Color(0xFFFFD700), size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  'ينتهي خلال: $timeStr',
                                  style: const TextStyle(
                                    color: Color(0xFFFFE957),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _titleText,
                            style: TextStyle(
                              color: _titleColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // كرت تتبع شحن المستخدم (User Progress Card)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 175, 16, 0),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF2C1F10).withValues(alpha: 0.95),
                            const Color(0xFF1B1428).withValues(alpha: 0.95),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.5), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF9800).withValues(alpha: 0.2),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'شحنك التراكمي هذا الشهر:',
                                    style: TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        NumberFormat('#,###').format(_userTotalRecharge),
                                        style: const TextStyle(
                                          color: Color(0xFFFFE957),
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Text('🪙 كوينز', style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ],
                              ),
                              if (nextTier != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'الهدف القادم: ${nextTier.nameAr}',
                                        style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        'متبقي: ${NumberFormat('#,###').format(nextTier.targetCoins - _userTotalRecharge)}',
                                        style: const TextStyle(color: Colors.white60, fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // شريط التقدم الذهبي
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              height: 10,
                              child: LinearProgressIndicator(
                                value: progress,
                                backgroundColor: Colors.white.withValues(alpha: 0.1),
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFB300)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.workspace_premium, color: Color(0xFFFFD700), size: 18),
                      SizedBox(width: 6),
                      Text(
                        'مكافآت مستويات الشحن (14 مستوى ملكي)',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),

              // شبكة الـ 14 فئة الملكية الأصلية (D:40 Grid)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 110),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.64,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final tier = _tiers[index];
                      return _buildTierItemCard(tier, isFullScreen: true);
                    },
                    childCount: _tiers.length,
                  ),
                ),
              ),
            ],
          ),

          // شريط الأزرار السفلي العائم (Floating Bottom Bar)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.95),
                    Colors.black,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // كومة الكوينز الذهبية السفلية
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 52,
                    child: IgnorePointer(
                      child: _buildImage(_coinsAsset, height: 52, fit: BoxFit.contain),
                    ),
                  ),
                  // زر الشحن الذهبي
                  GestureDetector(
                    onTap: _onGoNow,
                    child: SizedBox(
                      width: 175,
                      height: 54,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          _buildImage(_btnAsset, width: 175, height: 54, fit: BoxFit.contain),
                          Text(
                            _btnText,
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: _btnTextColor,
                              shadows: const [
                                Shadow(color: Color(0x66FFEB3B), blurRadius: 6, offset: Offset(0, 1)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// كرت المكافأة الفردي المطابق لـ recharge_remind_list_item.xml
  Widget _buildTierItemCard(RechargeEventTierData tier, {bool isFullScreen = false}) {
    final remaining = _getRemainingClaims(tier);
    final timesClaimed = _getTimesClaimed(tier);
    final canClaim = remaining > 0;
    final claimed = !canClaim && timesClaimed > 0;

    return GestureDetector(
      onTap: () => _previewReward(tier),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // إطار الياقوت الملكي الأصلي من D:40 (recharge_remind_item_bg)
          SizedBox(
            width: isFullScreen ? 100 : 82,
            height: isFullScreen ? 116 : 94,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _buildImage(_itemBgAsset, width: isFullScreen ? 100 : 82, height: isFullScreen ? 116 : 94, fit: BoxFit.fill),

                // شارة التاج الحمراء أعلى اليمين (recharge_remind_tag_ic)
                Positioned(
                  top: isFullScreen ? 10 : 8,
                  right: isFullScreen ? 2 : 1,
                  child: SizedBox(
                    width: isFullScreen ? 40 : 36,
                    height: isFullScreen ? 26 : 24,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _buildImage(_tagAsset, width: isFullScreen ? 40 : 36, height: isFullScreen ? 26 : 24, fit: BoxFit.contain),
                        Padding(
                          padding: const EdgeInsets.only(left: 1),
                          child: Text(
                            tier.tagText,
                            style: TextStyle(
                              fontSize: isFullScreen ? 10 : 9,
                              fontWeight: FontWeight.w900,
                              color: _tagTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // شارة حزمة المكافآت المتعددة أعلى اليسار
                if (tier.rewardsList.length > 1)
                  Positioned(
                    top: isFullScreen ? 10 : 8,
                    left: isFullScreen ? 4 : 3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD700), Color(0xFFFF8F00)],
                        ),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 2)],
                      ),
                      child: Text(
                        'x${tier.rewardsList.length}',
                        style: TextStyle(
                          fontSize: isFullScreen ? 9 : 8,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF3E1F00),
                        ),
                      ),
                    ),
                  ),

                // أيقونة الجائزة داخل الإطار
                Positioned(
                  top: isFullScreen ? 18 : 14,
                  child: _buildImage(
                    tier.iconAsset, 
                    width: isFullScreen ? 64 : 50, 
                    height: isFullScreen ? 52 : 42, 
                    fit: BoxFit.contain,
                  ),
                ),

                // حالة الاستلام (في حال الشاشة الكاملة)
                if (isFullScreen && canClaim)
                  Positioned(
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [BoxShadow(color: Colors.amber, blurRadius: 4)],
                      ),
                      child: Text(
                        remaining > 1 ? 'استلام ($remaining) 🎁' : 'استلام 🎁',
                        style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900),
                      ),
                    ),
                  )
                else if (isFullScreen && claimed)
                  Positioned(
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade800.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        timesClaimed > 1 ? 'تم الاستلام ($timesClaimed) ✓' : 'تم الاستلام ✓',
                        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 2),

          // اسم الفئة في الأسفل بلون الذهب الأصلي (#ffffe957)
          Text(
            tier.nameAr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: isFullScreen ? 12 : 11,
              fontWeight: FontWeight.bold,
              color: _itemLabelColor,
              shadows: const [
                Shadow(color: Colors.black, blurRadius: 2, offset: Offset(0, 1)),
              ],
            ),
          ),

          // التارجت في الشاشة الكاملة
          if (isFullScreen)
            Text(
              '${NumberFormat('#,###').format(tier.targetCoins)} 🪙',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
        ],
      ),
    );
  }
}
