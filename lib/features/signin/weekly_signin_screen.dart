import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../providers/user_provider.dart';
import '../../screens/room/widgets/svga_frame.dart';
import '../../services/dynamic_config_service.dart';
import '../../services/media_prefetch_service.dart';
import 'signin_service.dart';

class WeeklySigninScreen extends StatefulWidget {
  const WeeklySigninScreen({super.key});

  /// إظهار نافذة تسجيل الدخول اليومي تلقائياً إذا لم يستلم المستخدم مكافأته اليوم
  static Future<void> showIfNeeded(BuildContext context) async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;
      if (uid == null) return;
      final hasClaimed = await SigninService.hasClaimedToday(uid);
      if (!hasClaimed && context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (_) => const Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(20)),
              child: SizedBox(
                height: 560,
                child: WeeklySigninScreen(),
              ),
            ),
          ),
        );
      }
    } catch (_) {}
  }

  @override
  State<WeeklySigninScreen> createState() => _WeeklySigninScreenState();
}

class _WeeklySigninScreenState extends State<WeeklySigninScreen> {
  List<Map<String, dynamic>> _rewards = [];
  List<Map<String, dynamic>> _records = [];
  Map<String, dynamic> _weekly = {};
  bool _loading = true;
  bool _signingIn = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final userProvider = context.read<UserProvider>();
      final uid = userProvider.currentUser?.uid;
      if (uid == null) {
        setState(() { _loading = false; _error = 'User not logged in'; });
        return;
      }
      final data = await SigninService.getUserSigninData(uid);
      final rewards = await SigninService.getRewards();
      if (!mounted) return;
      setState(() {
        _rewards = (data['rewards'] as List?)?.cast<Map<String, dynamic>>() ?? rewards;
        _records = (data['records'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _weekly = data['weekly'] is Map ? Map<String, dynamic>.from(data['weekly']) : {};
        _loading = false;
        _error = null;
      });
      MediaPrefetchService().prefetchMaps(_rewards);
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _doSignin() async {
    if (_signingIn) return;
    setState(() => _signingIn = true);
    try {
      final userProvider = context.read<UserProvider>();
      final uid = userProvider.currentUser?.uid;
      if (uid == null) return;
      final result = await SigninService.doSignin(uid);
      if (!mounted) return;
      if (result['success'] == true) {
        _showRewardDialog(result);
        await _loadData();
      } else {
        if (result['error'] == 'already_signed_in') {
          _showAlreadySignedIn();
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _signingIn = false);
  }

  void _showRewardDialog(Map<String, dynamic> result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: _buildRewardDialogContent(result),
      ),
    );
  }

  Widget _buildRewardDialogContent(Map<String, dynamic> result) {
    final cfg = DynamicConfigService();
    final dayNumber = result['day_number'] ?? 1;
    final rewardValue = result['reward_value'] ?? 0;
    final rewardType = result['reward_type'] ?? 'coins';
    final isDouble = result['is_double'] == true;

    final dayReward = _rewards.where((r) => r['day_number'] == dayNumber).toList();
    final iconUrl = dayReward.isNotEmpty ? (dayReward.first['icon_url'] as String? ?? '') : '';
    final svgaUrl = dayReward.isNotEmpty ? (dayReward.first['svga_url'] as String? ?? '') : '';
    final labelAr = dayReward.isNotEmpty ? (dayReward.first['label_ar'] as String? ?? '') : '';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        image: const DecorationImage(
          image: AssetImage(R.bgDialogTask),
          fit: BoxFit.cover,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 40),
          R.loadImage(R.signCoinTop, width: 80, height: 80),
          const SizedBox(height: 8),
          Text(
            labelAr.isNotEmpty ? labelAr : 'اليوم $dayNumber',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: cfg.signinGoldColor,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cfg.signinCardBorderColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                if (svgaUrl.isNotEmpty)
                  SvgaFrame(svgaPath: svgaUrl, size: 64, fit: BoxFit.contain)
                else
                  R.loadImage(
                    iconUrl.isNotEmpty ? iconUrl : R.icSigningOk,
                    width: 48, height: 48,
                  ),
                const SizedBox(height: 12),
                Text(
                  '$rewardValue',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: cfg.signinAccentColor,
                  ),
                ),
                Text(
                  rewardType == 'coins' ? 'عملات' :
                  rewardType == 'diamonds' ? 'ماس' :
                  rewardType == 'xp' ? 'نقاط خبرة' : '',
                  style: TextStyle(
                    fontSize: 16,
                    color: cfg.signinSubTextColor,
                  ),
                ),
                if (isDouble)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cfg.signinButtonGradientStart, cfg.signinButtonGradientEnd],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'مضاعف',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: cfg.signinButtonTextColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 50),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cfg.signinButtonGradientStart, cfg.signinButtonGradientEnd],
                ),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: cfg.signinButtonGradientStart.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                'ممتاز',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cfg.signinButtonTextColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 25),
        ],
      ),
    );
  }

  void _showAlreadySignedIn() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'لقد قمت بالتسجيل اليوم بالفعل',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: DynamicConfigService().signinDayBgColor,
      ),
    );
  }

  int _checkedDays() {
    return _records.length;
  }

  int _consecutiveDays() {
    return (_weekly['consecutive_days'] as num?)?.toInt() ?? _checkedDays();
  }

  bool _isDayChecked(int dayNumber) {
    return _records.any((r) => (r['day_number'] as num?)?.toInt() == dayNumber);
  }

  bool _isTodayDay(int dayNumber) {
    final checkedCount = _checkedDays();
    return dayNumber == checkedCount + 1 && dayNumber <= 7;
  }

  @override
  Widget build(BuildContext context) {
    final cfg = DynamicConfigService();
    return Scaffold(
      backgroundColor: cfg.signinSectionBgColor,
      body: Stack(
        children: [
          _buildBackground(cfg),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(cfg),
                if (_loading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator(color: Color(0xFFFFD700))),
                  )
                else if (_error != null)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off, color: cfg.signinSubTextColor, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            'تعذر تحميل البيانات',
                            style: TextStyle(color: cfg.signinSubTextColor, fontSize: 16),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _loadData,
                            child: Text('إعادة المحاولة', style: TextStyle(color: cfg.signinGoldColor)),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      child: Column(
                        children: [
                          _buildStreakHeader(cfg),
                          const SizedBox(height: 16),
                          _buildRewardGrid(cfg),
                          const SizedBox(height: 20),
                          _buildSigninButton(cfg),
                          const SizedBox(height: 16),
                          _buildStatsRow(cfg),
                          const SizedBox(height: 16),
                          _buildRules(cfg),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(DynamicConfigService cfg) {
    final bg = cfg.signinBackgroundImage;
    if (bg.isNotEmpty) {
      if (bg.startsWith('assets/')) {
        return Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(bg),
              fit: BoxFit.cover,
            ),
          ),
        );
      }
      return Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: R.cachedImage(bg),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF2e0d15),
            Color(0xFF1a080d),
            Color(0xFF0d0408),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(DynamicConfigService cfg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cfg.signinCardBorderColor.withValues(alpha: 0.3)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: cfg.signinTextColor, size: 20),
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
            ),
          ),
          const Spacer(),
          Text(
            'تسجيل الدخول اليومي',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: cfg.signinGoldColor,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildStreakHeader(DynamicConfigService cfg) {
    final consecutive = _consecutiveDays();
    final totalCoins = (_weekly['total_coins'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cfg.signinCardBgColor,
            cfg.signinCardBgColor.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cfg.signinCardBorderColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: cfg.signinGoldColor.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildStreakItem(
            cfg,
            icon: R.icSigningTopBg,
            label: 'أيام متتالية',
            value: '$consecutive',
          ),
          Container(
            width: 1,
            height: 40,
            color: cfg.signinCardBorderColor.withValues(alpha: 0.3),
          ),
          _buildStreakItem(
            cfg,
            icon: R.signCoinTop,
            label: 'إجمالي العملات',
            value: '$totalCoins',
          ),
          Container(
            width: 1,
            height: 40,
            color: cfg.signinCardBorderColor.withValues(alpha: 0.3),
          ),
          _buildStreakItem(
            cfg,
            icon: R.icCheckinGift,
            label: 'الأيام المسجلة',
            value: '${_checkedDays()}/7',
          ),
        ],
      ),
    );
  }

  Widget _buildStreakItem(DynamicConfigService cfg, {
    required String icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Column(
        children: [
          R.loadImage(icon, width: 28, height: 28),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: cfg.signinGoldColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: cfg.signinSubTextColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardGrid(DynamicConfigService cfg) {
    if (_rewards.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Text(
          'لا توجد مكافآت متاحة',
          style: TextStyle(color: cfg.signinSubTextColor),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cfg.signinCardBgColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cfg.signinCardBorderColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cfg.signinButtonGradientStart, cfg.signinButtonGradientEnd],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'مكافآت 7 أيام',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: cfg.signinButtonTextColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: _rewards.map((reward) {
              final dayNumber = (reward['day_number'] as num?)?.toInt() ?? 1;
              return _buildDayCell(cfg, reward, dayNumber);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell(DynamicConfigService cfg, Map<String, dynamic> reward, int dayNumber) {
    final isChecked = _isDayChecked(dayNumber);
    final isToday = _isTodayDay(dayNumber);
    final isLocked = dayNumber > _checkedDays() + 1;
    final iconUrl = reward['icon_url'] as String? ?? '';
    final svgaUrl = reward['svga_url'] as String? ?? '';
    final value = (reward['value'] as num?)?.toInt() ?? 0;
    final isDouble = reward['is_double'] == true;
    final labelAr = reward['label_ar'] as String? ?? 'اليوم $dayNumber';

    Color bgColor;
    Color borderColor;
    if (isChecked) {
      bgColor = cfg.signinDayClaimedColor;
      borderColor = cfg.signinDayClaimedBorderColor;
    } else if (isToday) {
      bgColor = cfg.signinDayActiveColor;
      borderColor = cfg.signinGoldColor;
    } else if (isLocked) {
      bgColor = cfg.signinDayLockedColor;
      borderColor = cfg.signinDayLockedColor;
    } else {
      bgColor = cfg.signinDayBgColor;
      borderColor = cfg.signinDayBorderColor;
    }

    return Container(
      width: 76,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor.withValues(alpha: isChecked ? 0.6 : isToday ? 0.9 : 0.3),
          width: isToday ? 2 : 1.5,
        ),
        boxShadow: isToday ? [
          BoxShadow(
            color: cfg.signinGoldColor.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 0),
          ),
        ] : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isChecked)
            R.loadImage(
              cfg.signinCheckmarkImage.isNotEmpty ? cfg.signinCheckmarkImage : R.icHaveCheckedIn,
              width: 18, height: 18,
            )
          else if (isLocked)
            R.loadImage(
              cfg.signinLockImage.isNotEmpty ? cfg.signinLockImage : R.icHaveNotCheckedIn,
              width: 18, height: 18,
            )
          else
            R.loadImage(R.icSigningClock, width: 18, height: 18),
          const SizedBox(height: 4),
          Text(
            labelAr,
            style: TextStyle(
              fontSize: 10,
              color: isChecked ? cfg.signinDayClaimedBorderColor : cfg.signinTextColor,
              fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          svgaUrl.isNotEmpty
            ? SizedBox(
                width: 36,
                height: 36,
                child: SvgaFrame(svgaPath: svgaUrl, size: 36, fit: BoxFit.contain),
              )
            : R.loadImage(
                iconUrl.isNotEmpty ? iconUrl : R.icSigningOk,
                width: 36, height: 36,
              ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'x$value',
                style: TextStyle(
                  fontSize: 11,
                  color: cfg.signinGoldColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (isDouble)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(Icons.star, color: cfg.signinGoldColor, size: 10),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSigninButton(DynamicConfigService cfg) {
    final allChecked = _checkedDays() >= 7;
    final todayChecked = _checkedDays() > 0 && _isDayChecked(_checkedDays());

    if (allChecked) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: cfg.signinGoldColor, size: 24),
            const SizedBox(width: 8),
            Text(
              'أكملت جميع المكافآت لهذا الأسبوع',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: cfg.signinGoldColor,
              ),
            ),
          ],
        ),
      );
    }

    if (todayChecked) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: cfg.signinCardBorderColor.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            R.loadImage(R.icHaveCheckedIn, width: 24, height: 24),
            const SizedBox(width: 8),
            Text(
              'تم التسجيل اليوم',
              style: TextStyle(
                fontSize: 16,
                color: cfg.signinSubTextColor,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _signingIn ? null : _doSignin,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_signingIn
              ? cfg.signinCardBorderColor
              : cfg.signinButtonGradientStart,
              _signingIn
              ? cfg.signinCardBorderColor
              : cfg.signinButtonGradientEnd,
            ],
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: cfg.signinButtonGradientStart.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_signingIn)
              SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cfg.signinButtonTextColor,
                ),
              )
            else
              R.loadImage(cfg.signinButtonImage.isNotEmpty ? cfg.signinButtonImage : R.icSigningOk,
                  width: 24, height: 24),
            const SizedBox(width: 8),
            Text(
              _signingIn ? 'جاري التسجيل...' : 'تسجيل الدخول اليومي',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: cfg.signinButtonTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(DynamicConfigService cfg) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: cfg.signinCardBgColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cfg.signinCardBorderColor.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatDot(cfg, 'اليوم', _checkedDays().toString(), true),
          _buildStatDot(cfg, 'متبقي', '${7 - _checkedDays()}', false),
          _buildStatDot(cfg, 'السجل', '${_consecutiveDays()} أيام', true),
        ],
      ),
    );
  }

  Widget _buildStatDot(DynamicConfigService cfg, String label, String value, bool isHighlight) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isHighlight ? cfg.signinGoldColor : cfg.signinSubTextColor,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: cfg.signinSubTextColor,
          ),
        ),
      ],
    );
  }

  Widget _buildRules(DynamicConfigService cfg) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cfg.signinCardBorderColor.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: cfg.signinGoldColor, size: 16),
              const SizedBox(width: 6),
              Text(
                'القواعد',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: cfg.signinGoldColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '• سجل دخولك يومياً لجمع المكافآت\n'
            '• المكافآت تتضاعف في اليوم السابع\n'
            '• يحافظ التسجيل المتتالي على سلسلة الأيام\n'
            '• يتم تحديث المكافآت كل أسبوع',
            style: TextStyle(
              fontSize: 12,
              color: cfg.signinSubTextColor,
              height: 1.8,
            ),
          ),
        ],
      ),
    );
  }
}
