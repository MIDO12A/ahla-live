import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../screens/room/widgets/svga_player.dart';

/// بيانات مستوى الشحن الأسطوري الملكي (المطابق لـ D:40)
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
  });

  factory RechargeEventTierData.fromMap(Map<String, dynamic> map, int defaultTier) {
    final t = (map['tier'] as num?)?.toInt() ?? defaultTier;
    final label = map['rewardLabel']?.toString() ?? '${t}00K';
    return RechargeEventTierData(
      id: 'tier_$label',
      tier: t,
      targetCoins: (map['requiredCoins'] as num?)?.toInt() ?? 100000,
      nameAr: label,
      iconAsset: map['icon']?.toString().isNotEmpty == true 
          ? map['icon'].toString() 
          : 'assets/recharge_event/$label.png',
      svgaAsset: map['svga']?.toString().isNotEmpty == true 
          ? map['svga'].toString() 
          : '${label.toLowerCase()}.svga',
      tagText: map['tagText']?.toString().isNotEmpty == true ? map['tagText'].toString() : label,
      durationDays: (map['daysValid'] as num?)?.toInt() ?? 30,
      bonusCoins: (map['rewardCoins'] as num?)?.toInt() ?? 5000,
    );
  }
}

/// الشاشة والنافذة الملكية لحدث الشحن (D:40 Recharge Remind Dialog)
class RechargeEventScreen extends StatefulWidget {
  final bool isDialog;

  const RechargeEventScreen({super.key, this.isDialog = false});

  /// دالة مساعدة لفتح الحدث كنافذة منبثقة أصلية كما في D:40
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

  // إعدادات التصميم والتحكم من اللوحة
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

  StreamSubscription? _configSub;

  @override
  void initState() {
    super.initState();
    _loadUserProgress();
    _listenToDynamicConfig();
  }

  @override
  void dispose() {
    _configSub?.cancel();
    super.dispose();
  }

  void _listenToDynamicConfig() {
    _configSub = FirebaseFirestore.instance
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
      // إجمالي شحن المستخدم
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final rechargedCoins = (userDoc.data()?['recharged_coins'] as num?)?.toInt() ?? 
                            (userDoc.data()?['total_recharge'] as num?)?.toInt() ?? 0;

      final now = DateTime.now();
      final eventId = 'recharge_${now.year}_${now.month.toString().padLeft(2, '0')}';
      final progressDoc = await FirebaseFirestore.instance
          .collection('recharge_event_progress')
          .doc('${eventId}_$uid')
          .get();

      if (mounted) {
        setState(() {
          _userTotalRecharge = rechargedCoins;
          if (progressDoc.exists) {
            _claimedTiers = List<String>.from(progressDoc.data()?['claimed_tiers'] ?? []);
          }
        });
      }
    } catch (_) {}
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
    final canClaim = _userTotalRecharge >= tier.targetCoins && !_claimedTiers.contains(tier.id);
    final alreadyClaimed = _claimedTiers.contains(tier.id);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141419),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            // SVGA Player or Icon
            SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _buildImage(_itemBgAsset, width: 130, height: 130),
                  if (tier.svgaAsset.isNotEmpty)
                    SvgaPlayer(
                      assetPath: tier.svgaAsset.startsWith('assets/') 
                          ? tier.svgaAsset 
                          : 'assets/recharge_event/${tier.svgaAsset}',
                      width: 110,
                      height: 110,
                      fit: BoxFit.contain,
                    )
                  else
                    _buildImage(tier.iconAsset, width: 85, height: 85),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'مستوى ${tier.nameAr}',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'تارجت الشحن: ${NumberFormat('#,###').format(tier.targetCoins)} كوينز',
              style: const TextStyle(color: Color(0xFFFFE957), fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'بونص إضافي: +${NumberFormat('#,###').format(tier.bonusCoins)} كوينز | الصلاحية: ${tier.durationDays} يوم',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 20),
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
                  alreadyClaimed
                      ? 'تم الاستلام مسبقاً'
                      : canClaim
                          ? 'استلام الجائزة الملكية 🎁'
                          : 'اشحن للوصول لهذا المستوى',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _claimTierReward(RechargeEventTierData tier) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final now = DateTime.now();
    final eventId = 'recharge_${now.year}_${now.month.toString().padLeft(2, '0')}';

    try {
      final docRef = FirebaseFirestore.instance.collection('recharge_event_progress').doc('${eventId}_$uid');
      final newClaimed = [..._claimedTiers, tier.id];

      await docRef.set({
        'user_id': uid,
        'event_id': eventId,
        'claimed_tiers': newClaimed,
        'updated_at': now.toIso8601String(),
      }, SetOptions(merge: true));

      // إضافة المكافأة لحقيبة المستخدم
      await FirebaseFirestore.instance.collection('user_backpack').add({
        'user_id': uid,
        'item_id': tier.id,
        'name': tier.nameAr,
        'icon_url': tier.iconAsset,
        'svga_url': tier.svgaAsset,
        'expires_at': now.add(Duration(days: tier.durationDays)).toIso8601String(),
        'created_at': now.toIso8601String(),
        'is_equipped': true,
      });

      // إضافة الكوينز البونص
      if (tier.bonusCoins > 0) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'coins': FieldValue.increment(tier.bonusCoins),
        });
      }

      setState(() => _claimedTiers = newClaimed);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 تهانينا! تم استلام مكافأة ${tier.nameAr} وبونص ${tier.bonusCoins} كوينز بنجاح!'),
          backgroundColor: Colors.green.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء الاستلام: $e')),
      );
    }
  }

  void _onGoNow() {
    // إغلاق النافذة المنبثقة إذا كانت مفتوحة والانتقال لصفحة الشحن
    if (widget.isDialog) {
      Navigator.pop(context);
    }
    // فتح متجر شحن الكوينز
    Navigator.of(context).pushNamed('/wallet_recharge');
  }

  @override
  Widget build(BuildContext context) {
    // التصميم الأصلي يحاكي أبعاد recharge_remind_dialog.xml (Width 302dp, Height 440dp)
    final dialogWidget = Center(
      child: SizedBox(
        width: 312,
        height: 460,
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            // 1. خلفية القوس الملكي مع التاج والمسجد الذهبي (recharge_remind_dialog_bg)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 385,
              child: _buildImage(_dialogBgAsset, width: 312, height: 385, fit: BoxFit.fill),
            ),

            // 2. Guideline بنسبة 25% من الأعلى: عنوان الحدث أو صورة البانر المصممة (Text-to-Image)
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

            // 3. شبكة الـ 3 أعمدة الأصلية (recharge_remind_dialog_rv, spanCount="3")
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
                  return _buildTierItem(tier);
                },
              ),
            ),

            // 4. كومة الكوينز الذهبية السفلية (recharge_remind_coins_ic)
            Positioned(
              bottom: 46,
              left: 6,
              right: 6,
              height: 48,
              child: IgnorePointer(
                child: _buildImage(_coinsAsset, height: 48, fit: BoxFit.contain),
              ),
            ),

            // 5. زر الشحن الذهبي الملكي (recharge_remind_btn_ic مع نص "اشحن الآن")
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

            // 6. زر الإغلاق الدائري الأصلي (recharge_remind_close_ic)
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

    if (widget.isDialog) {
      return dialogWidget;
    }

    // عند فتح الصفحة بشكل كامل (Full Screen)
    return Scaffold(
      backgroundColor: const Color(0xEE090910),
      body: Stack(
        children: [
          // خلفية معتمة فخمة مع لمسات نجوم
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.8,
                  colors: [
                    Color(0xFF1E1710),
                    Color(0xFF0C0A0E),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: dialogWidget,
          ),
        ],
      ),
    );
  }

  /// كرت المكافأة الفردي المطابق لـ recharge_remind_list_item.xml
  Widget _buildTierItem(RechargeEventTierData tier) {
    return GestureDetector(
      onTap: () => _previewReward(tier),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // إطار الياقوت الملكي (recharge_remind_item_bg)
          SizedBox(
            width: 82,
            height: 94,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // صورة الإطار الذهبي مع فصوص الياقوت
                _buildImage(_itemBgAsset, width: 82, height: 94, fit: BoxFit.fill),

                // شارة التاج الحمراء أعلى اليمين (recharge_remind_tag_ic)
                Positioned(
                  top: 8,
                  right: 1,
                  child: SizedBox(
                    width: 36,
                    height: 24,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _buildImage(_tagAsset, width: 36, height: 24, fit: BoxFit.contain),
                        Padding(
                          padding: const EdgeInsets.only(left: 1),
                          child: Text(
                            tier.tagText,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: _tagTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // أيقونة الجائزة داخل الإطار (55x42dp)
                Positioned(
                  top: 14,
                  child: _buildImage(tier.iconAsset, width: 50, height: 42, fit: BoxFit.contain),
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
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _itemLabelColor,
              shadows: const [
                Shadow(color: Colors.black, blurRadius: 2, offset: Offset(0, 1)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
