import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../providers/user_provider.dart';
import '../tasks/screens/daily_tasks_screen.dart';
import 'signin_service.dart';

/// الشاشة والنافذة المنبثقة لتسجيل الوصول اليومي
/// مطابقة بالكامل لتصميم التطبيق الأصلي:
/// - dialog_signin_coins.xml
/// - item_sign_coin.xml
/// - item_sign_coin2.xml
/// - dialog_task_coin.xml
class WeeklySigninScreen extends StatelessWidget {
  const WeeklySigninScreen({super.key});

  /// إظهار نافذة تسجيل الوصول اليومي تلقائياً إذا لم يستلم المستخدم مكافأته لليوم
  static Future<void> showIfNeeded(BuildContext context) async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;
      if (uid == null) return;
      final hasClaimed = await SigninService.hasClaimedToday(uid);
      if (!hasClaimed && context.mounted) {
        show(context);
      }
    } catch (_) {}
  }

  /// فتح نافذة تسجيل الوصول اليومي كـ Dialog أصلي مطابق
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => const Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        elevation: 0,
        child: WeeklySigninDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // في حال فتحها كشاشة كاملة عبر Navigator.push
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.6),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),
        child: Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {}, // منع الإغلاق عند النقر داخل النافذة
            child: const SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: WeeklySigninDialog(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// نافذة تسجيل الوصول اليومي المطابقة لـ dialog_signin_coins.xml
class WeeklySigninDialog extends StatefulWidget {
  const WeeklySigninDialog({super.key});

  @override
  State<WeeklySigninDialog> createState() => _WeeklySigninDialogState();
}

class _WeeklySigninDialogState extends State<WeeklySigninDialog> {
  List<Map<String, dynamic>> _rewards = [];
  List<Map<String, dynamic>> _records = [];
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
        setState(() {
          _loading = false;
          _error = 'User not logged in';
        });
        return;
      }
      final data = await SigninService.getUserSigninData(uid);
      final rewards = await SigninService.getRewards();
      if (!mounted) return;
      setState(() {
        _rewards = (data['rewards'] as List?)?.cast<Map<String, dynamic>>() ?? rewards;
        _records = (data['records'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  bool _isDayChecked(int dayNumber) {
    return _records.any((r) => (r['day_number'] as num?)?.toInt() == dayNumber);
  }

  bool _hasClaimedToday() {
    final checkedCount = _records.length;
    if (checkedCount >= 7) return true;
    final userProvider = context.read<UserProvider>();
    final uid = userProvider.currentUser?.uid;
    if (uid == null) return false;
    final now = DateTime.now().toUtc();
    final todayStr = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return _records.any((r) => (r['claimed_date'] ?? r['claim_date'] ?? r['date']) == todayStr);
  }

  int _todayDayNumber() {
    return (_records.length + 1).clamp(1, 7);
  }

  Future<void> _doSignin() async {
    if (_signingIn || _hasClaimedToday()) return;
    setState(() => _signingIn = true);
    try {
      final userProvider = context.read<UserProvider>();
      final uid = userProvider.currentUser?.uid;
      if (uid == null) return;
      final result = await SigninService.doSignin(uid);
      if (!mounted) return;
      if (result['success'] == true) {
        await _loadData();
        if (mounted) {
          _showRewardSuccessDialog(result);
        }
      } else {
        if (result['error'] == 'already_signed_in') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لقد قمت بتسجيل الوصول اليوم بالفعل', textAlign: TextAlign.center),
              backgroundColor: Color(0xFFFEB606),
            ),
          );
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _signingIn = false);
  }

  /// نافذة التأكيد والتهنئة المطابقة لـ dialog_task_coin.xml
  void _showRewardSuccessDialog(Map<String, dynamic> result) {
    final rewardValue = result['reward_value'] ?? 50;
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        elevation: 0,
        child: _buildTaskCoinDialogContent(ctx, rewardValue),
      ),
    );
  }

  Widget _buildTaskCoinDialogContent(BuildContext ctx, dynamic rewardValue) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // خلفية نافذة المكافأة bg_get_task_coin
          Image.asset(
            R.bgGetTaskCoin,
            fit: BoxFit.fill,
            width: double.infinity,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 60),
              // تهانينا (congratulations)
              const Text(
                'تهانينا',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFD6BF),
                  shadows: [
                    Shadow(
                      color: Color(0xFF944307),
                      offset: Offset(0, 1),
                      blurRadius: 3,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // قيمة المكافأة مع أيقونة mini_coins
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    R.miniCoins,
                    width: 34,
                    height: 34,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '+$rewardValue',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFECB15),
                      shadows: [
                        Shadow(
                          color: Color(0xFF614C00),
                          offset: Offset(0, 2),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              // زر التأكيد (confirm)
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: Container(
                  height: 48,
                  margin: const EdgeInsets.symmetric(horizontal: 45),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDE301),
                    borderRadius: BorderRadius.circular(60),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFDE301).withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'تأكيد',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // البطاقة البيضاء الأساسية بزوايا 18dp (ShapeConstraintLayout)
          Container(
            margin: const EdgeInsets.only(top: 36),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // رأس البطاقة bg_dialog_task
                _buildHeader(),

                // شبكة الأيام والمكافآت
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: CircularProgressIndicator(color: Color(0xFFFEB606)),
                    ),
                  )
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
                    child: Column(
                      children: [
                        Text(_error!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _loadData,
                          child: const Text('إعادة المحاولة', style: TextStyle(color: Color(0xFFFEB606))),
                        ),
                      ],
                    ),
                  )
                else ...[
                  // شبكة 7 أيام (item_sign_coin & item_sign_coin2)
                  _buildDaysGrid(),

                  // الأيقونة الكبيرة وإجمالي كويزات اليوم
                  _buildCoinsRow(),

                  // زر تسجيل الوصول tvCheckIn
                  _buildCheckInButton(),

                  // شريط المزيد من المهام llMoreTask
                  _buildMoreTasksBar(),
                ],
              ],
            ),
          ),

          // الميدالية الذهبية العائمة في الأعلى sign_coin_top (80x80dp)
          Positioned(
            top: 0,
            child: Image.asset(
              R.signCoinTop,
              width: 76,
              height: 76,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }

  /// ترويسة النافذة (خلفية bg_dialog_task + العنوان + زر الإغلاق)
  Widget _buildHeader() {
    return Stack(
      children: [
        // صورة الترويسة العليا bg_dialog_task
        ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
          ),
          child: Image.asset(
            R.bgDialogTask,
            width: double.infinity,
            height: 72,
            fit: BoxFit.fill,
          ),
        ),

        // العنوان "تسجيل الوصول اليومي"
        const Positioned(
          left: 0,
          right: 0,
          bottom: 10,
          child: Text(
            'تسجيل الوصول اليومي',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: Color(0xFFA54800),
            ),
          ),
        ),

        // زر الإغلاق imgClose
        Positioned(
          top: 10,
          right: 10,
          child: GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 18,
                color: Color(0xFFC46200),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// شبكة الأيام الـ 7 (السطر الأول: أيام 1-4، السطر الثاني: أيام 5-6 ويوم 7 مضاعف العرض)
  Widget _buildDaysGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        children: [
          // الصف الأول: الأيام 1 إلى 4
          Row(
            children: List.generate(4, (index) {
              final dayNum = index + 1;
              final reward = _getRewardForDay(dayNum);
              return Expanded(
                child: _buildStandardDayCard(dayNum, reward),
              );
            }),
          ),
          const SizedBox(height: 6),
          // الصف الثاني: الأيام 5 و 6 (1 flex لكل منهما) واليوم 7 (2 flex مضاعف)
          Row(
            children: [
              Expanded(
                flex: 1,
                child: _buildStandardDayCard(5, _getRewardForDay(5)),
              ),
              Expanded(
                flex: 1,
                child: _buildStandardDayCard(6, _getRewardForDay(6)),
              ),
              Expanded(
                flex: 2,
                child: _buildDay7Card(_getRewardForDay(7)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getRewardForDay(int dayNum) {
    final match = _rewards.where((r) => (r['day_number'] as num?)?.toInt() == dayNum).toList();
    if (match.isNotEmpty) return match.first;
    // قيم افتراضية متطابقة مع التطبيق الأصلي
    final defaultValues = [50, 100, 150, 200, 300, 400, 500];
    return {
      'day_number': dayNum,
      'value': defaultValues[(dayNum - 1).clamp(0, 6)],
    };
  }

  /// بطاقة الأيام العادية (1-6) مطابقة لـ item_sign_coin.xml
  Widget _buildStandardDayCard(int dayNum, Map<String, dynamic> reward) {
    final isChecked = _isDayChecked(dayNum);
    final value = reward['value'] ?? (dayNum * 50);
    final isToday = !_hasClaimedToday() && dayNum == _todayDayNumber();

    return Container(
      margin: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(8),
        border: isToday
            ? Border.all(color: const Color(0xFFFEB606), width: 1.5)
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // عنوان اليوم (tvTitle)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Day $dayNum',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
              ),
            ),
          ),
          // فاصل أبيض
          Container(
            height: 1,
            color: Colors.white,
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
          // محتوى المكافأة بارتفاع 54dp
          SizedBox(
            height: 54,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      R.miniCoins,
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'X$value',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF6953),
                      ),
                    ),
                  ],
                ),
                // أيقونة تم التسجيل (has_signed)
                if (isChecked)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFFEB606), width: 1.5),
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 16,
                          color: Color(0xFFFEB606),
                        ),
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

  /// بطاقة اليوم السابع المميزة (item_sign_coin2.xml)
  Widget _buildDay7Card(Map<String, dynamic> reward) {
    final isChecked = _isDayChecked(7);
    final value = reward['value'] ?? 500;
    final isToday = !_hasClaimedToday() && _todayDayNumber() == 7;

    return Container(
      margin: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(8),
        border: isToday
            ? Border.all(color: const Color(0xFFFEB606), width: 1.5)
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // عنوان اليوم السابع
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Day 7',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
              ),
            ),
          ),
          // فاصل أبيض
          Container(
            height: 1,
            color: Colors.white,
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
          // محتوى بارتفاع 54dp مع رسمة كومة الكويزات في الخلفية sign_coin_bg_coin
          SizedBox(
            height: 54,
            child: Stack(
              children: [
                // صورة الكويزات الجانبية sign_coin_bg_coin
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Image.asset(
                    R.signCoinBgCoin,
                    width: 50,
                    height: 48,
                    fit: BoxFit.contain,
                  ),
                ),
                // أيقونة dialog_coins والقيمة
                Padding(
                  padding: const EdgeInsets.only(left: 10, top: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.asset(
                        R.dialogCoins,
                        width: 24,
                        height: 24,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'X$value',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF6953),
                        ),
                      ),
                    ],
                  ),
                ),
                // أيقونة تم التسجيل
                if (isChecked)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFFEB606), width: 1.5),
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 16,
                          color: Color(0xFFFEB606),
                        ),
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

  /// قسم عرض الكويزات الكبيرة لليوم الحالي (give_coin_icon + llCoins)
  Widget _buildCoinsRow() {
    final todayDay = _todayDayNumber();
    final todayReward = _getRewardForDay(todayDay);
    final value = todayReward['value'] ?? 50;

    return Column(
      children: [
        const SizedBox(height: 8),
        Image.asset(
          R.giveCoinIcon,
          width: 80,
          height: 48,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF6953),
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              'كويزات',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// زر تسجيل الوصول (tvCheckIn)
  Widget _buildCheckInButton() {
    final claimed = _hasClaimedToday();

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 14, 40, 18),
      child: GestureDetector(
        onTap: (_signingIn || claimed) ? null : _doSignin,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: claimed
                ? const LinearGradient(
                    colors: [Color(0xFFD6D6D6), Color(0xFFB0B0B0)],
                  )
                : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFEB606), Color(0xFFFF6953)],
                  ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: claimed
                ? null
                : [
                    BoxShadow(
                      color: const Color(0xFFFF6953).withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: _signingIn
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  claimed ? 'تم تسجيل الوصول اليوم' : 'تسجيل الوصول',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }

  /// شريط المزيد من المهام السفلي (llMoreTask)
  Widget _buildMoreTasksBar() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).maybePop();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DailyTasksScreen()),
        );
      },
      child: Container(
        height: 46,
        decoration: const BoxDecoration(
          color: Color(0xFFE0F6F4),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'المزيد من المهام',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF00D9C5),
              ),
            ),
            SizedBox(width: 4),
            Icon(
              Icons.arrow_forward_ios,
              size: 13,
              color: Color(0xFF00D9C5),
            ),
          ],
        ),
      ),
    );
  }
}
