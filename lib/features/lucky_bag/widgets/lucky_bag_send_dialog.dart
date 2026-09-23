import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/user_provider.dart';
import '../services/lucky_bag_service.dart';

/// حوار إرسال حقيبة الحظ (Lucky Bag Send Dialog) — مطابق تماماً لتصميم dialog_send_lucky_box.xml و frag_send_coin_lucky_box.xml
class LuckyBagSendDialog extends StatefulWidget {
  final String roomId;

  const LuckyBagSendDialog({super.key, required this.roomId});

  static Future<bool?> show(BuildContext context, {required String roomId}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LuckyBagSendDialog(roomId: roomId),
    );
  }

  @override
  State<LuckyBagSendDialog> createState() => _LuckyBagSendDialogState();
}

class _LuckyBagSendDialogState extends State<LuckyBagSendDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _activeTabIndex = 0; // 0: أكياس العملات, 1: أكياس الهدايا
  String _scope = 'room'; // 'room' (كل الغرفة) أو 'mic' (الميكروفون فقط)
  String _distributionType = 'random'; // 'random' (عشوائي) أو 'equal' (بالتساوي)
  int _selectedAmount = 1000;
  int _sharesCount = 10;
  bool _sending = false;
  bool _showRules = false;

  final TextEditingController _customAmountCtrl = TextEditingController();

  static const _coinPresets = [500, 1000, 2000, 5000, 10000, 20000];
  static const _sharesPresets = [5, 10, 15, 20, 30, 50];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging || _tabController.index != _activeTabIndex) {
        setState(() => _activeTabIndex = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customAmountCtrl.dispose();
    super.dispose();
  }

  int get _totalCoins {
    final custom = int.tryParse(_customAmountCtrl.text.trim());
    if (custom != null && custom > 0) return custom;
    return _selectedAmount;
  }

  Future<void> _handleSend() async {
    if (_sending) return;
    final user = Provider.of<UserProvider>(context, listen: false).currentUser;
    if (user == null) return;

    final cost = _totalCoins;
    if (user.coins < cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('رصيد العملات غير كافٍ!'),
          backgroundColor: Color(0xFFB71C1C),
        ),
      );
      return;
    }

    if (cost < _sharesCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('يجب أن تكون قيمة الحقيبة ($cost) أكبر من عدد الحقائب ($_sharesCount)!'),
          backgroundColor: const Color(0xFFB71C1C),
        ),
      );
      return;
    }

    setState(() => _sending = true);
    final res = await LuckyBagService().sendLuckyBag(
      roomId: widget.roomId,
      type: _activeTabIndex == 1 ? 'super' : 'coins',
      scope: _scope,
      totalCoins: cost,
      count: _sharesCount,
      greetingText: _distributionType == 'random' ? 'حظ سعيد للجميع ✨' : 'توزيع بالتساوي للجميع 🎁',
      isSuper: _activeTabIndex == 1,
    );

    if (!mounted) return;
    setState(() => _sending = false);

    if (res != null) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🧧 تم إرسال حقيبة الحظ بنجاح بمجموع $cost 🪙 ($_sharesCount حقيبة)'),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('فشل الإرسال — تأكد من رصيد العملات أو الاتصال'),
          backgroundColor: Color(0xFFB71C1C),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context).currentUser;
    final coins = user?.coins ?? 0;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF013C1B), // اللون الأساسي الداكن
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Stack(
        children: [
          // 1. الخلفية المكررة ic_send_lucky_box_panel_bg
          Positioned.fill(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: Image.asset(
                'assets/images/ic_send_lucky_box_panel_bg.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),

          // 2. الهيدر العلوي المزخرف topBg: ic_lucky_box_top_bg
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Image.asset(
              'assets/images/ic_lucky_box_top_bg.png',
              fit: BoxFit.fitWidth,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(14, 16, 14, MediaQuery.of(context).viewInsets.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // شريط الرصيد وزر القواعد وزر الإغلاق
                  _buildHeaderBar(coins),

                  const SizedBox(height: 14),

                  if (_showRules) ...[
                    // واجهة عرض القواعد ruleContainer
                    _buildRulesPanel(),
                  ] else ...[
                    // تبويبات أكياس العملات وأكياس الهدايا tabLayoutContainer
                    _buildTabs(),

                    const SizedBox(height: 10),

                    // حاوية الخيارات vpContainer
                    _buildOptionsContainer(),

                    const SizedBox(height: 16),

                    // زر إرسال حقيبة الحظ sendBtn
                    _buildSendButton(),
                  ],

                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// شريط الرصيد coinBtn وزر القواعد ruleBtn
  Widget _buildHeaderBar(int coins) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (_showRules)
          GestureDetector(
            onTap: () => setState(() => _showRules = false),
            child: Image.asset(
              'assets/images/ic_luckybag_back.png',
              width: 32,
              height: 32,
              errorBuilder: (_, __, ___) => const Icon(Icons.arrow_back, color: Color(0xFFFFF295)),
            ),
          )
        else
          // كبسولة الرصيد coinBtn (#0b3a09 مع حد #fff295)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF0B3A09),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFFF295), width: 1.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/ic_min_coins.png',
                  width: 16,
                  height: 16,
                  errorBuilder: (_, __, ___) => const Text('🪙', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 5),
                Text(
                  '$coins',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFF295),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_ios, size: 10, color: Color(0xFFFFF295)),
              ],
            ),
          ),

        // زر القواعد ruleBtn
        if (!_showRules)
          GestureDetector(
            onTap: () => setState(() => _showRules = true),
            child: Image.asset(
              'assets/images/ic_lucky_box_rule_btn.png',
              width: 32,
              height: 32,
              errorBuilder: (_, __, ___) => Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFF0B3A09),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.help_outline, color: Color(0xFFFFF295), size: 18),
              ),
            ),
          ),
      ],
    );
  }

  /// تبويبات أكياس العملات وأكياس الهدايا المطابقة لـ tabLayoutContainer
  Widget _buildTabs() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF003C1B),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFFFF295), width: 1.0),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Opacity(
                opacity: 0.8,
                child: Image.asset(
                  'assets/images/ic_lucky_box_texture.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          Row(
            children: [
              _buildTabItem(0, 'أكياس العملات'),
              _buildTabItem(1, 'أكياس الهدايا'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem(int index, String title) {
    final isSelected = _activeTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          _tabController.animateTo(index);
          setState(() => _activeTabIndex = index);
        },
        child: Container(
          margin: const EdgeInsets.all(3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: isSelected
                ? const LinearGradient(
                    colors: [Color(0xFFFFF295), Color(0xFFFFB606)],
                  )
                : null,
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isSelected ? const Color(0xFF134015) : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  /// حاوية الخيارات vpContainer المطابقة لـ frag_send_coin_lucky_box.xml
  Widget _buildOptionsContainer() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF134015),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFF295), width: 1.0),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Opacity(
                opacity: 0.3,
                child: Image.asset(
                  'assets/images/ic_lucky_box_texture2.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. إجمالي العملات الذهبية totalCoinTitle
              _buildSectionTitle('إجمالي العملات الذهبية'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _coinPresets.map((amt) {
                  final isSelected = _selectedAmount == amt && _customAmountCtrl.text.isEmpty;
                  return GestureDetector(
                    onTap: () {
                      _customAmountCtrl.clear();
                      setState(() => _selectedAmount = amt);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFFFF295) : const Color(0xFF0B2E10),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? const Color(0xFFFFF295) : const Color(0xFF2E6333),
                        ),
                      ),
                      child: Text(
                        '$amt',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? const Color(0xFF134015) : const Color(0xFFFFF295),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 12),

              // 2. عدد حقائب الحظ numberOfLuckyBoxTitle
              _buildSectionTitle('عدد حقائب الحظ'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _sharesPresets.map((cnt) {
                  final isSelected = _sharesCount == cnt;
                  return GestureDetector(
                    onTap: () => setState(() => _sharesCount = cnt),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFFFF295) : const Color(0xFF0B2E10),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? const Color(0xFFFFF295) : const Color(0xFF2E6333),
                        ),
                      ),
                      child: Text(
                        '$cnt حقائب',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? const Color(0xFF134015) : const Color(0xFFFFF295),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 12),

              // 3. نوع حقيبة الحظ typeOfLuckyBoxTitle
              _buildSectionTitle('نوع حقيبة الحظ'),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildOptionButton(
                    title: 'عشوائي (حظ)',
                    isSelected: _distributionType == 'random',
                    onTap: () => setState(() => _distributionType = 'random'),
                  ),
                  const SizedBox(width: 10),
                  _buildOptionButton(
                    title: 'بالتساوي',
                    isSelected: _distributionType == 'equal',
                    onTap: () => setState(() => _distributionType = 'equal'),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // 4. نطاق حقائب الحظ scopeOfLuckyBoxTitle
              _buildSectionTitle('نطاق حقائب الحظ'),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildOptionButton(
                    title: 'كل الغرفة',
                    isSelected: _scope == 'room',
                    onTap: () => setState(() => _scope = 'room'),
                  ),
                  const SizedBox(width: 10),
                  _buildOptionButton(
                    title: 'الميكروفون فقط',
                    isSelected: _scope == 'mic',
                    onTap: () => setState(() => _scope = 'mic'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Image.asset(
          'assets/images/ic_lucky_box_dot.png',
          width: 12,
          height: 12,
          errorBuilder: (_, __, ___) => const Icon(Icons.circle, size: 8, color: Color(0xFFFFFB7B)),
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFFFFFB7B), // #fffb7b
          ),
        ),
      ],
    );
  }

  Widget _buildOptionButton({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFFF295) : const Color(0xFF0B2E10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? const Color(0xFFFFF295) : const Color(0xFF2E6333),
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSelected ? const Color(0xFF134015) : const Color(0xFFFFF295),
            ),
          ),
        ),
      ),
    );
  }

  /// زر الإرسال sendBtn المطابق لـ sendBtn و sendTv
  Widget _buildSendButton() {
    return GestureDetector(
      onTap: _sending ? null : _handleSend,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFF295).withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/images/ic_send_luckybag_btn.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFFFF295), Color(0xFFFFB606)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_sending)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: Color(0xFF134015), strokeWidth: 2),
              )
            else
              const Text(
                'إرسال حقيبة الحظ',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF134015), // #134015 bold 18dp
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// لوحة القواعد ruleContainer
  Widget _buildRulesPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF134015),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFF295), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Center(
            child: Text(
              'قواعد حقيبة الحظ',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFFEF34), // #ffef34
              ),
            ),
          ),
          SizedBox(height: 16),
          Text(
            '1. يمكن لجميع مستخدمي الغرفة أو مستخدمي المايك (حسب النطاق المحدد) فتح حقائب الحظ.\n\n'
            '2. يتم توزيع العملات إما عشوائياً بمضاعفات مختلفة أو بالتساوي حسب اختيار المرسل.\n\n'
            '3. تنتهي صلاحية الحقيبة بعد انتهاء الوقت المحدد أو استلام جميع الحقائب، ويُعاد أي رصيد متبقٍ لحساب المرسل تلقائياً.',
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: Color(0xFFFFFAC3), // #fffac3
            ),
          ),
        ],
      ),
    );
  }
}