import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/r.dart';
import '../../core/dtext.dart';
import '../../providers/user_provider.dart';
import '../../services/dynamic_config_service.dart';
import '../../widgets/user_id_widget.dart';
import 'invite_service.dart';

/// شاشة كود الدعوة — مطابقة 100% لصفحة h5.halopartyvip.com/invite-register
/// الأقسام: القواعد + هيدر البطل + كودي/دعوة الأصدقاء + من دعاني +
/// تبويبات إيرادات (لعبة/شحن) + قائمة الأصدقاء المدعوين + ديالوج القواعد
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final InviteService _service = InviteService();
  bool _loading = true;
  Map<String, dynamic> _summary = {'totalInviteQuantity': 0, 'totalCommission': 0};
  Map<String, dynamic>? _inviter;
  List<Map<String, dynamic>> _invitedUsers = [];
  final TextEditingController _codeController = TextEditingController();
  bool _binding = false;
  bool _claiming = false;
  Map<String, dynamic> _inviteSettings = {};
  final Map<String, String> _rewardLabels = {};

  int _tabIndex = 0; // 0 = إيرادات اللعبة, 1 = إيرادات الشحن
  Map<String, Map<String, double>> _gameStats = {};
  int _visibleCount = 10;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String get _uid =>
      Provider.of<UserProvider>(context, listen: false).currentUser?.uid ?? '';
  String get _myCode {
    final user = Provider.of<UserProvider>(context, listen: false).currentUser;
    final cid = user?.customId.trim() ?? '';
    return cid.isNotEmpty ? cid : (user?.uid ?? '');
  }

  Future<void> _load() async {
    if (_uid.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    final results = await Future.wait([
      _service.getInviteSummary(_uid),
      _service.getInviterOf(_uid),
      _service.getInvitedUsers(_uid),
      _service.getInviteSettings(),
    ]);
    if (!mounted) return;
    final invited = results[2] as List<Map<String, dynamic>>;
    setState(() {
      _summary = results[0] as Map<String, dynamic>;
      _inviter = results[1] as Map<String, dynamic>?;
      _invitedUsers = invited;
      _inviteSettings = results[3] as Map<String, dynamic>;
      _loading = false;
      _visibleCount = _pageSize;
    });
    _resolveRewardLabels();
    // إحصائيات لعب المدعوين (اليوم/أمس)
    final uids = invited
        .map((u) => u['invitee_uid']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
    if (uids.isNotEmpty) {
      final stats = await _service.getInviteesGameStats(uids);
      if (mounted) setState(() => _gameStats = stats);
    }
  }

  Future<String> _rewardLabel(Map<String, dynamic> reward) async {
    if (reward.isEmpty) return '';
    final type = reward['type']?.toString() ?? '';
    final amount = (reward['amount'] as num?)?.toInt() ?? 0;
    final itemId = reward['item_id']?.toString() ?? '';
    switch (type) {
      case 'coins':
        return '$amount كوينز';
      case 'diamonds':
        return '$amount ألماس';
      case 'item':
      case 'vip_item':
        var name = _rewardLabels['item:$itemId'] ?? '';
        if (name.isEmpty) {
          name = await _service.getStoreItemName(itemId);
          if (name.isNotEmpty && mounted) {
            setState(() => _rewardLabels['item:$itemId'] = name);
          }
        }
        return name.isNotEmpty ? name : itemId;
      case 'vip_tier':
        final days = (reward['days'] as num?)?.toInt() ?? 0;
        return 'VIP ${amount.toInt()}${days > 0 ? ' لمدة $days يوم' : ' (دائم)'}';
      default:
        return '';
    }
  }

  Future<void> _resolveRewardLabels() async {
    final r = _inviteSettings['inviter_reward'];
    if (r is Map) await _rewardLabel(Map<String, dynamic>.from(r));
  }

  void _copy(String text) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: DText('تم نسخ الكود بنجاح'), duration: Duration(seconds: 1)),
    );
  }

  void _shareInvite() {
    final code = _myCode;
    if (code.isEmpty) return;
    SharePlus.instance.share(ShareParams(
      text: 'انضم إليّ في التطبيق! كود الدعوة الخاص بي: $code',
      subject: 'دعوة للانضمام',
    ));
  }

  void _showRules() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'rules',
      pageBuilder: (_, __, ___) => const _RulesDialog(),
      transitionBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }

  Future<void> _confirmInviteCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: DText('أدخل كود الدعوة أولاً')),
      );
      return;
    }
    setState(() => _binding = true);
    final res = await _service.bindInviter(_uid, code);
    if (!mounted) return;
    setState(() => _binding = false);
    final ok = res['ok'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: DText(ok
            ? 'تم ربط الكود بنجاح'
            : switch (res['message']) {
                'already_bound' => 'تم ربط كود الدعوة مسبقاً',
                'invalid_code' => 'كود الدعوة غير صحيح',
                _ => 'تعذر ربط الكود، حاول لاحقاً',
              }),
      ),
    );
    if (ok) {
      _codeController.clear();
      final granted = res['invitee_reward']?.toString() ?? '';
      if (granted.isNotEmpty) {
        final parts = granted.split(':');
        String rewardText = granted;
        if (parts.length == 2) {
          if (parts[0] == 'coins') {
            rewardText = '${parts[1]} كوينز';
          } else if (parts[0] == 'diamonds') {
            rewardText = '${parts[1]} ألماس';
          } else if (parts[0] == 'vip_tier') {
            rewardText = 'VIP ${parts[1]}';
          } else {
            rewardText = await _service.getStoreItemName(parts[1]);
            if (rewardText.isEmpty) rewardText = parts[1];
          }
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: DText('تهانينا! حصلت على مكافأة الدعوة: $rewardText')),
          );
        }
        await Provider.of<UserProvider>(context, listen: false)
            .loadUser(_uid);
      }
      _load();
    }
  }

  Future<void> _claimRewards() async {
    setState(() => _claiming = true);
    final res = await _service.claimInviteRewards(_uid);
    if (!mounted) return;
    setState(() => _claiming = false);
    final ok = res['ok'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: DText(ok
            ? 'تم استلام المكافأة بنجاح'
            : switch (res['message']) {
                'no_bonus_configured' => 'لا توجد مكافأة محددة حالياً',
                'nothing_to_claim' => 'لا توجد مكافآت للحصول عليها',
                _ => 'تعذر الاستلام، حاول لاحقاً',
              }),
      ),
    );
    if (ok) {
      final granted = res['reward']?.toString() ?? '';
      await Provider.of<UserProvider>(context, listen: false).loadUser(_uid);
      if (mounted && granted.isNotEmpty) {
        final parts = granted.split(':');
        var rewardText = granted;
        if (parts.length == 2 &&
            (parts[0] == 'item' || parts[0] == 'vip_item')) {
          rewardText = await _service.getStoreItemName(parts[1]);
          if (rewardText.isEmpty) rewardText = parts[1];
        } else if (parts.length == 2 && parts[0] == 'coins') {
          rewardText = '${parts[1]} كوينز';
        } else if (parts.length == 2 && parts[0] == 'diamonds') {
          rewardText = '${parts[1]} ألماس';
        } else if (parts.length == 2 && parts[0] == 'vip_tier') {
          rewardText = 'VIP ${parts[1]}';
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: DText('تم استلام مكافأتك: $rewardText')),
          );
        }
      }
      _load();
    }
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final config = DynamicConfigService();
    final remoteBg = config.inviteScreenBgImage;
    return Scaffold(
      backgroundColor: config.inviteScreenPrimaryColor,
      appBar: AppBar(
        title: DText(config.inviteScreenTitle,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : RefreshIndicator(
              onRefresh: _load,
              child: Stack(
                children: [
                  Positioned.fill(child: _bgImage(remoteBg)),
                  ListView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                    children: [
                      _buildTop(),
                      const SizedBox(height: 10),
                      _buildMyInviteInfo(),
                      const SizedBox(height: 12),
                      _buildContent(),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _bgImage(String remoteBg) {
    if (remoteBg.isNotEmpty) {
      return Image(
        image: R.cachedImage(remoteBg),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _localBg(),
      );
    }
    return _localBg();
  }

  Widget _localBg() {
    return Image.asset(
      'assets/images/invite/page_bg.png',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          Container(color: DynamicConfigService().inviteScreenPrimaryColor),
    );
  }

  /// .top — زر القواعد + صورة البطل
  Widget _buildTop() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _showRules,
          child: SizedBox(
            height: 34,
            child: Image.asset(
              'assets/images/invite/rules_button_bg.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const DText('القواعد',
                    style: TextStyle(fontSize: 12, color: Colors.white)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Image.asset(
            'assets/images/invite/hero_title.png',
            height: 90,
            fit: BoxFit.contain,
          ),
        ),
      ],
    );
  }

  /// .my-invite-info — كودي + دعوة الأصدقاء + قسم "من دعاني"
  Widget _buildMyInviteInfo() {
    return Column(
      children: [
        // كارت الكود
        _cardBackground(
          'assets/images/invite/invite_code_card_bg.png',
          padding: const EdgeInsets.fromLTRB(16, 30, 16, 16),
          child: Column(
            children: [
              const DText('كود الدعوة الخاص بي',
                  style: TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: DText(
                      _myCode.isEmpty ? '-' : _myCode,
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _copy(_myCode),
                    child: const Icon(Icons.copy,
                        color: Color(0xFFFFD700), size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _imageButton(
                'assets/images/invite/invite_button_bg.png',
                'دعوة الأصدقاء',
                onTap: _shareInvite,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // قسم "من دعاني"
        _cardBackground(
          'assets/images/invite/friends_card_bg.png',
          padding: const EdgeInsets.fromLTRB(16, 30, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DText('من دعاني',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 10),
              if (_inviter != null) _buildInviterInfo() else _buildCodeForm(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInviterInfo() {
    final inviter = _inviter!;
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundImage: (inviter['photo_url']?.toString() ?? '').isNotEmpty
              ? R.cachedImage(inviter['photo_url'].toString())
              : null,
          child: (inviter['photo_url']?.toString() ?? '').isEmpty
              ? const Icon(Icons.person, color: Colors.white70)
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DText(
                inviter['name']?.toString() ?? '',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              UserIdWidget(
                idText: inviter['inviter_custom_id']?.toString() ?? '',
                showCopy: false,
                fontSize: 11,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCodeForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DText('أدخل رمز الدعوة',
            style: TextStyle(fontSize: 13, color: Colors.white70)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codeController,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'أدخل رمز الدعوة',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _binding ? null : _confirmInviteCode,
              child: SizedBox(
                height: 40,
                child: _binding
                    ? const Center(
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white)))
                    : Image.asset(
                        'assets/images/invite/confirm_button_bg.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [
                              Color(0xFF1DB954),
                              Color(0xFF0E7A38)
                            ]),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const DText('يتأكد',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const DText(
          'يجب أن يسجل المدعو بعد تسجيل الداعي',
          style: TextStyle(fontSize: 11, color: Colors.white54),
        ),
      ],
    );
  }

  /// .content — تبويبات الإيرادات + كارت الدخل + قائمة الأصدقاء
  Widget _buildContent() {
    return Column(
      children: [
        _buildIncomeTabs(),
        const SizedBox(height: 10),
        _buildIncomeCard(),
        const SizedBox(height: 12),
        _buildInviteList(),
      ],
    );
  }

  Widget _buildIncomeTabs() {
    final tabs = ['إيرادات اللعبة', 'إيرادات الشحن'];
    return Container(
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        image: const DecorationImage(
          image: AssetImage('assets/images/invite/tab_shell_bg.png'),
          fit: BoxFit.fill,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / tabs.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                left: _tabIndex * tabWidth,
                top: 3,
                bottom: 3,
                width: tabWidth,
                child: Image.asset(
                  'assets/images/invite/tab_active_bg.png',
                  fit: BoxFit.fill,
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _tabIndex = i),
                        child: Center(
                          child: DText(
                            tabs[i],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _tabIndex == i
                                  ? Colors.white
                                  : Colors.white70,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildIncomeCard() {
    return _cardBackground(
      'assets/images/invite/income_card_bg.png',
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 16),
      child: _tabIndex == 0 ? _gameIncomeContent() : _rechargeIncomeContent(),
    );
  }

  /// تبويب إيرادات اللعبة: عداد اليوم + مكافأة الأمس + قواعد
  Widget _gameIncomeContent() {
    final total = (_summary['totalInviteQuantity'] as num?)?.toInt() ?? 0;
    final todayPlaying = _invitedUsers.where((u) {
      final uid = u['invitee_uid']?.toString() ?? '';
      return (_gameStats[uid]?['today'] ?? 0) > 0;
    }).length;
    final progress = total > 0 ? (todayPlaying / total).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // progress-panel
        Row(
          children: [
            const Expanded(
              child: DText('لعبة الأصدقاء المدعوين اليوم:',
                  style: TextStyle(fontSize: 12, color: Colors.white70)),
            ),
            DText('$todayPlaying',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Colors.white.withValues(alpha: 0.15),
            valueColor:
                const AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
          ),
        ),
        const SizedBox(height: 14),
        // reward row — جوائز لعبة الأمس
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.emoji_events,
                      color: Color(0xFFFFD700), size: 26),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: DText('جوائز لعبة الأمس:',
                        style: TextStyle(fontSize: 12, color: Colors.white70)),
                  ),
                  _imageButton(
                    'assets/images/invite/claim_button_bg.png',
                    _claiming ? '...' : 'Done',
                    onTap: _claiming ? null : _claimRewards,
                    height: 34,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerRight,
                child: DText(
                  'يمكنك الحصول على جوائز لعبة الأمس كل يوم. يتم التحديث الساعة 00:00.',
                  style: TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// تبويب إيرادات الشحن: ملخص الأصدقاء + إجمالي الإيرادات
  Widget _rechargeIncomeContent() {
    final total = (_summary['totalInviteQuantity'] as num?)?.toInt() ?? 0;
    final commission =
        (_summary['totalCommission'] as num?)?.toInt() ?? 0;
    return Column(
      children: [
        _summaryRow('عدد الأصدقاء المدعوين:', '$total'),
        const SizedBox(height: 10),
        _summaryRow('المجموع الإجمالي للإيرادات:', '$commission'),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      children: [
        const Icon(Icons.monetization_on,
            color: Color(0xFFFFD700), size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: DText(label,
              style: const TextStyle(fontSize: 13, color: Colors.white70)),
        ),
        DText(value,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
      ],
    );
  }

  /// .invite-list — جدول الأصدقاء المدعوين
  Widget _buildInviteList() {
    final shown = _invitedUsers.take(_visibleCount).toList();
    return _cardBackground(
      'assets/images/invite/friends_card_bg.png',
      padding: const EdgeInsets.fromLTRB(14, 26, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DText('الأصدقاء المدعوون',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 10),
          // table head
          const Row(
            children: [
              Expanded(flex: 3, child: _Th('مستخدم')),
              Expanded(flex: 2, child: _Th('لعبة اليوم')),
              Expanded(flex: 2, child: _Th('لعبة الأمس')),
              Expanded(flex: 2, child: _Th('وقت الدعوة')),
            ],
          ),
          const Divider(color: Colors.white24, height: 14),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: DText('لا يوجد مدعوين حتى الآن',
                    style: TextStyle(fontSize: 12, color: Colors.white54)),
              ),
            )
          else
            for (final u in shown) _buildInviteRow(u),
          if (_visibleCount < _invitedUsers.length)
            Center(
              child: TextButton(
                onPressed: () =>
                    setState(() => _visibleCount += _pageSize),
                child: const DText('Load More',
                    style: TextStyle(color: Color(0xFFFFD700))),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInviteRow(Map<String, dynamic> u) {
    final uid = u['invitee_uid']?.toString() ?? '';
    final stats = _gameStats[uid];
    final today = stats?['today'] ?? 0;
    final yesterday = stats?['yesterday'] ?? 0;
    final createdAt = u['created_at']?.toString() ?? '';
    final time = createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;
    final name = u['name']?.toString() ?? 'مستخدم';
    final photo = u['photo_url']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // مستخدم
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundImage:
                      photo.isNotEmpty ? R.cachedImage(photo) : null,
                  child: photo.isEmpty
                      ? const Icon(Icons.person,
                          size: 14, color: Colors.white70)
                      : null,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: DText(name,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          // لعبة اليوم
          Expanded(
            flex: 2,
            child: DText(_fmtBet(today),
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF51FF7F)),
                textAlign: TextAlign.center),
          ),
          // لعبة الأمس
          Expanded(
            flex: 2,
            child: DText(_fmtBet(yesterday),
                style: const TextStyle(
                    fontSize: 11, color: Colors.white70),
                textAlign: TextAlign.center),
          ),
          // وقت الدعوة
          Expanded(
            flex: 2,
            child: DText(time,
                style: const TextStyle(
                    fontSize: 10, color: Colors.white54),
                textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  String _fmtBet(double v) {
    if (v <= 0) return '0';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  }

  // ── Helpers ────────────────────────────────────────────────

  Widget _cardBackground(String asset,
      {required Widget child, EdgeInsets? padding}) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            asset,
            fit: BoxFit.fill,
            errorBuilder: (_, __, ___) => Container(
              decoration: BoxDecoration(
                color: const Color(0xFF005C34),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: const Color(0xFFE5A642), width: 2),
              ),
            ),
          ),
        ),
        Padding(
          padding: padding ?? const EdgeInsets.fromLTRB(14, 26, 14, 14),
          child: child,
        ),
      ],
    );
  }

  Widget _imageButton(String asset, String label,
      {VoidCallback? onTap, double height = 44}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                asset,
                fit: BoxFit.fill,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      Color(0xFF1DB954),
                      Color(0xFF0E7A38)
                    ]),
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
            ),
            Center(
              child: DText(label,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Th extends StatelessWidget {
  final String text;
  const _Th(this.text);

  @override
  Widget build(BuildContext context) {
    return DText(text,
        style: const TextStyle(fontSize: 11, color: Colors.white54),
        textAlign: TextAlign.center);
  }
}

/// ديالوج القواعد — نفس نصوص صفحة الدعوة الأصلية
class _RulesDialog extends StatelessWidget {
  const _RulesDialog();

  static const _rules = [
    '١. ستكون الدعوة ناجحة فقط إذا أدخل المستخدم رمز الدعوة الخاص بك أثناء التسجيل.',
    '٢. يمكن تسجيل حساب واحد فقط لكل جهاز.',
    '٣. تقسم مكافآت الدعوة إلى مكافآت اللعب ومكافآت إعادة الشحن.',
    '٤. قواعد مكافأة إعادة الشحن:',
    '   (١) ستحصل على مكافأة عملات بنسبة 1% عن كل إعادة شحن يقوم بها صديقك.',
    '   (٢) هذه المكافأة صالحة لمدة 30 يومًا من تاريخ بدء الدعوة.',
    '٥. قواعد مكافأة اللعب:',
    '   (١) ستحصل على 0.1% - 0.5% من مبلغ رهان صديقك في كل لعبة. كلما زاد عدد الأصدقاء الذين تدعوهم، ارتفعت نسبة المكافأة.',
    '   (٢) يمكن المطالبة بمكافآت دعوة اللعب يوميًا لمكافآت اليوم السابق، ولا يمكن المطالبة بمكافآت اليوم الحالي إلا في اليوم التالي.',
    '   (٣) لا يوجد حد زمني لهذه المكافأة؛ ستحصل على المكافآت باستمرار طالما أن الأصدقاء الذين دعوتهم يستمرون في لعب الألعاب.',
    'تحتفظ الإدارة بحق تفسير هذا النشاط.',
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 30),
        constraints: const BoxConstraints(maxHeight: 480),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/invite/rules_dialog_bg.png',
                fit: BoxFit.fill,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF005C34),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 30, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const DText('القواعد',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 10),
                  const Divider(color: Color(0xFFE5A642), thickness: 1),
                  const SizedBox(height: 10),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final rule in _rules)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 8),
                              child: DText(rule,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.6,
                                      color: Colors.white),
                                  textAlign: TextAlign.right),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: SizedBox(
                      height: 42,
                      width: 140,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Image.asset(
                              'assets/images/invite/rules_ok_button_bg.png',
                              fit: BoxFit.fill,
                              errorBuilder: (_, __, ___) =>
                                  Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [
                                    Color(0xFF1DB954),
                                    Color(0xFF0E7A38)
                                  ]),
                                  borderRadius:
                                      BorderRadius.circular(21),
                                ),
                              ),
                            ),
                          ),
                          const Center(
                            child: DText('OK',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
