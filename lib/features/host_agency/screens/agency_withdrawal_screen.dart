import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/supabase_compat.dart';

import '../data/agency_models.dart';
import '../data/agency_repository.dart';

import '../../../core/cache/encrypted_image_provider.dart';
import '../../../screens/message/message_reply_detail_screen.dart';

// ═══════════════════════════════════════════════════════════════════
//  AgencyWithdrawalScreen v2 — شاشة السحب المالي الشاملة
//  ✅ جميع الأسعار من قاعدة البيانات (لا ثوابت مشفّرة)
//  ✅ فحص KYC قبل السحب
//  ✅ يعرض الرصيد المتاح (بعد خصم المجمّد)
//  ✅ سجل المعاملات من agency_diamond_ledger
//  Tab 1: تبادل الألماس بكوينز (بمعدل من DB)
//  Tab 2: سحب بالدولار (KYC + رسوم + حد دوري من DB)
//  Tab 3: تحويل إلى وكيل الشحن (بدون رسوم، فوري)
//  Tab 4: سجل المعاملات
// ═══════════════════════════════════════════════════════════════════
class AgencyWithdrawalScreen extends StatefulWidget {
  final int initialTab;
  final int? initialDiamonds;
  const AgencyWithdrawalScreen({
    super.key,
    this.initialTab = 0,
    this.initialDiamonds,
  });

  @override
  State<AgencyWithdrawalScreen> createState() => _AgencyWithdrawalScreenState();
}

class _AgencyWithdrawalScreenState extends State<AgencyWithdrawalScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  bool _loading   = true;
  AgencyMemberInfo?    _member;
  AgencyEngineSettings? _engine;
  bool _isKycVerified = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      final results = await Future.wait([
        AgencyRepository.getHostStats(),
        AgencyRepository.getEngineSettings(),
        if (uid != null)
          Supabase.instance.client
              .from('profiles')
              .select('is_kyc_verified')
              .eq('id', uid)
              .maybeSingle(),
      ]);

      if (!mounted) return;
      final stats  = results[0] as HostAgencyStats?;
      final engine = results[1] as AgencyEngineSettings;
      final profile= uid != null ? results[2] as Map<String, dynamic>? : null;

      setState(() {
        _member         = stats?.member;
        _engine         = engine;
        _isKycVerified  = profile?['is_kyc_verified'] as bool? ?? false;
        _loading        = false;
      });
    } catch (e) {
debugPrint('[agency_withdrawal_screen] error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        foregroundColor: Colors.white,
        title: const Text('المحفظة المالية',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFFD4AF37),
          labelColor: const Color(0xFFD4AF37),
          unselectedLabelColor: Colors.white38,
          isScrollable: true,
          tabs: const [
            Tab(text: '💱 تبادل'),
            Tab(text: '💸 سحب \$'),
            Tab(text: '🔄 وكيل شحن'),
            Tab(text: '📋 السجل'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
          : _member == null
              ? Center(child: Text('لستَ عضواً في وكالة',
                  style: TextStyle(color: Colors.white.withOpacity(0.5))))
              : Column(children: [
                  _WalletHeader(member: _member!, isKycVerified: _isKycVerified),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _ExchangeTab(member: _member!, engine: _engine!, onDone: _loadAll),
                        _WithdrawUsdTab(member: _member!, engine: _engine!, isKycVerified: _isKycVerified, onDone: _loadAll),
                        _TransferRechargeTab(
                          member: _member!,
                          initialDiamonds: widget.initialDiamonds,
                          onDone: _loadAll,
                        ),
                        const _TransactionHistoryTab(),
                      ],
                    ),
                  ),
                ]),
    );
  }
}

// ─── Wallet Header ────────────────────────────────────────────────────────────
class _WalletHeader extends StatelessWidget {
  final AgencyMemberInfo member;
  final bool isKycVerified;
  const _WalletHeader({required this.member, required this.isKycVerified});

  static String _fmtK(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A0A3A), Color(0xFF0D0D1A)],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
        ),
      ),
      child: Column(children: [
        Row(children: [
          _BalanceTile(icon: '♦', label: 'الرصيد الكلي', value: _fmtK(member.diamondsBalance), color: const Color(0xFFB39DDB)),
          const SizedBox(width: 8),
          _BalanceTile(icon: '✅', label: 'المتاح', value: _fmtK(member.diamondsAvailable), color: const Color(0xFF00E5A0)),
          const SizedBox(width: 8),
          _BalanceTile(icon: '🔒', label: 'مجمّد', value: _fmtK(member.diamondsPendingWithdrawal), color: const Color(0xFFFF9800)),
        ]),
        if (member.diamondsPendingWithdrawal > 0) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.lock_rounded, color: Color(0xFFFF9800), size: 12),
            const SizedBox(width: 4),
            Text(
              '${_fmtK(member.diamondsPendingWithdrawal)} ألماس مجمّد بسبب طلب سحب نشط',
              style: const TextStyle(color: Color(0xFFFF9800), fontSize: 11),
            ),
          ]),
        ],
        if (!isKycVerified) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF5252).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.warning_rounded, color: Color(0xFFFF5252), size: 14),
              SizedBox(width: 6),
              Text('يجب إتمام التحقق من الهوية (KYC) للسحب النقدي',
                style: TextStyle(color: Color(0xFFFF5252), fontSize: 11)),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _BalanceTile extends StatelessWidget {
  final String icon, label, value;
  final Color color;
  const _BalanceTile({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Tab 1: تبادل الألماس بكوينز (معدل من DB)
// ═══════════════════════════════════════════════════════════════════
class _ExchangeTab extends StatefulWidget {
  final AgencyMemberInfo    member;
  final AgencyEngineSettings engine;
  final VoidCallback onDone;
  const _ExchangeTab({required this.member, required this.engine, required this.onDone});

  @override
  State<_ExchangeTab> createState() => _ExchangeTabState();
}

class _ExchangeTabState extends State<_ExchangeTab> {
  final _ctrl = TextEditingController();
  bool _processing = false;
  int  _diamonds   = 0;

  /// يستخدم المعدل من قاعدة البيانات (لا ثوابت مشفّرة)
  int get _coinsResult => widget.engine.coinsFromDiamonds(_diamonds);

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _exchange() async {
    if (_diamonds < 100) { _snack('الحد الأدنى للتبادل 100 ألماس'); return; }
    if (_diamonds > widget.member.diamondsAvailable) {
      _snack('الرصيد المتاح غير كافٍ. المتاح: ${widget.member.diamondsAvailable} ♦'); return;
    }
    setState(() => _processing = true);
    try {
      final key = '${widget.member.memberId}_xchg_${DateTime.now().millisecondsSinceEpoch}';
      final result = await AgencyRepository.exchangeDiamonds(
        diamondsAmount: _diamonds,
        idempotencyKey: key,
      );
      if (!mounted) return;
      final coins = (result['coins_received'] as num?)?.toInt() ?? _coinsResult;
      _snack('✅ تم التبادل! حصلت على ${_fmtK(coins)} كوينز');
      _ctrl.clear();
      setState(() => _diamonds = 0);
      widget.onDone();
    } catch (e) {
      if (mounted) _snack('خطأ: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final rate    = widget.engine.diamondToCoinRate;
    final rateStr = rate == rate.truncateToDouble()
        ? rate.toInt().toString()
        : rate.toStringAsFixed(2);
    final limit   = widget.engine.dailyExchangeLimit;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _InfoCard(
          icon: '💱',
          title: 'تبادل الألماس',
          lines: [
            'معدل التبادل: 1 ♦ = $rateStr كوينز',
            'حد يومي: ${_fmtK(limit)} ألماس',
            'الحد الأدنى للعملية: 100 ألماس',
            'يخصم من الرصيد المتاح — لا يؤثر على الهدف الشهري',
            'فوري بدون رسوم',
          ],
        ),
        const SizedBox(height: 24),

        Text('كمية الألماس للتبادل', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          decoration: _deco(hint: '0', suffix: '♦', color: const Color(0xFFB39DDB)),
          onChanged: (v) => setState(() => _diamonds = int.tryParse(v) ?? 0),
        ),

        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [1000, 5000, 10000, 50000].map((v) =>
          ActionChip(
            label: Text('${_fmtK(v)}♦'),
            backgroundColor: const Color(0xFFB39DDB).withOpacity(0.12),
            labelStyle: const TextStyle(color: Color(0xFFB39DDB), fontSize: 12),
            onPressed: () { _ctrl.text = v.toString(); setState(() => _diamonds = v); },
          ),
        ).toList()),

        if (_diamonds >= 100) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37).withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.3)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('تبادل', style: TextStyle(color: Colors.white54, fontSize: 12)),
                Text('${_fmtK(_diamonds)} ♦',
                    style: const TextStyle(color: Color(0xFFB39DDB), fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white38),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                const Text('تحصل على', style: TextStyle(color: Colors.white54, fontSize: 12)),
                Text('${_fmtK(_coinsResult)} كوينز',
                    style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
            ]),
          ),
        ],

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_processing || _diamonds < 100) ? null : _exchange,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB39DDB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _processing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('تأكيد التبادل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Tab 2: سحب بالدولار (جميع الأسعار من DB + KYC)
// ═══════════════════════════════════════════════════════════════════
class _WithdrawUsdTab extends StatefulWidget {
  final AgencyMemberInfo     member;
  final AgencyEngineSettings engine;
  final bool isKycVerified;
  final VoidCallback onDone;
  const _WithdrawUsdTab({
    required this.member, required this.engine,
    required this.isKycVerified, required this.onDone,
  });

  @override
  State<_WithdrawUsdTab> createState() => _WithdrawUsdTabState();
}

class _WithdrawUsdTabState extends State<_WithdrawUsdTab> {
  final _diamondsCtrl    = TextEditingController();
  final _bankNameCtrl    = TextEditingController();
  final _bankIbanCtrl    = TextEditingController();
  final _bankCountryCtrl = TextEditingController(text: 'SA');
  bool _processing = false;
  int  _diamonds   = 0;

  // جميع الحسابات تعتمد على widget.engine (من قاعدة البيانات)
  double get _grossUsd => widget.engine.grossUsdFromDiamonds(_diamonds);
  double get _feeUsd   => _grossUsd * widget.engine.withdrawalFeePct / 100;
  double get _netUsd   => widget.engine.netUsdFromDiamonds(_diamonds);

  @override
  void dispose() {
    _diamondsCtrl.dispose(); _bankNameCtrl.dispose();
    _bankIbanCtrl.dispose(); _bankCountryCtrl.dispose();
    super.dispose();
  }

  Future<void> _withdraw() async {
    if (!widget.isKycVerified) {
      _snack('يجب إتمام التحقق من الهوية (KYC) أولاً'); return;
    }
    if (_diamonds <= 0 || _netUsd < widget.engine.minWithdrawalUsd) {
      _snack('الحد الأدنى للسحب \$${widget.engine.minWithdrawalUsd.toStringAsFixed(0)} صافي'); return;
    }
    if (_bankNameCtrl.text.trim().isEmpty || _bankIbanCtrl.text.trim().isEmpty) {
      _snack('الرجاء إدخال معلومات الحساب البنكي'); return;
    }
    if (_diamonds > widget.member.diamondsAvailable) {
      _snack('الرصيد المتاح غير كافٍ. المتاح: ${widget.member.diamondsAvailable} ♦'); return;
    }
    if (_diamonds < widget.engine.minDiamondsToWithdraw) {
      _snack('الحد الأدنى: ${widget.engine.minDiamondsToWithdraw} ألماس'); return;
    }

    setState(() => _processing = true);
    try {
      final key = '${_diamonds}_wdrw_${DateTime.now().millisecondsSinceEpoch}';
      final result = await AgencyRepository.requestWithdrawal(
        diamondsAmount:  _diamonds,
        paymentMethod:   'bank_transfer',
        paymentDetails:  {
          'bank_name': _bankNameCtrl.text.trim(),
          'iban':      _bankIbanCtrl.text.trim(),
          'country':   _bankCountryCtrl.text.trim(),
        },
        idempotencyKey:  key,
      );
      if (!mounted) return;
      final netUsd = (result['net_usd'] as num?)?.toDouble() ?? _netUsd;
      _snack('✅ طلب السحب \$${netUsd.toStringAsFixed(2)} مُرسَل. ستتم المعالجة خلال 5 أيام عمل.');
      _diamondsCtrl.clear();
      setState(() => _diamonds = 0);
      widget.onDone();
    } catch (e) {
      if (mounted) _snack('خطأ: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final e = widget.engine;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _InfoCard(
          icon: '💸',
          title: 'سحب بالدولار الأمريكي',
          lines: [
            'السعر: ${(1 / e.diamondToUsdRate).round()} ♦ = \$1',
            'رسوم السحب: ${e.withdrawalFeePct.toStringAsFixed(0)}%',
            'الحد الأدنى: \$${e.minWithdrawalUsd.toStringAsFixed(0)} صافي',
            'الحد الأدنى: ${_fmtK(e.minDiamondsToWithdraw)} ألماس',
            'معالجة: 5 أيام عمل عبر Wise / تحويل بنكي',
            'يستلزم التحقق من الهوية (KYC)',
          ],
        ),

        // تحذير KYC
        if (!widget.isKycVerified) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF5252).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.warning_rounded, color: Color(0xFFFF5252)),
              SizedBox(width: 8),
              Expanded(child: Text(
                'حسابك لم يُتحقق منه بعد. اكمل توثيق الهوية (KYC) في الإعدادات لتتمكن من السحب.',
                style: TextStyle(color: Color(0xFFFF5252), fontSize: 12, height: 1.4),
              )),
            ]),
          ),
        ],

        const SizedBox(height: 20),
        Text('كمية الألماس للسحب', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _diamondsCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          decoration: _deco(hint: '0', suffix: '♦', color: const Color(0xFFD4AF37)),
          onChanged: (v) => setState(() => _diamonds = int.tryParse(v) ?? 0),
        ),

        if (_diamonds >= e.minDiamondsToWithdraw) ...[
          const SizedBox(height: 16),
          _InvoicePreview(gross: _grossUsd, fee: _feeUsd, net: _netUsd, feePct: e.withdrawalFeePct),
        ],

        const SizedBox(height: 20),
        const Divider(color: Colors.white12),
        const SizedBox(height: 16),

        Text('معلومات الحساب البنكي', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
        const SizedBox(height: 10),
        TextField(
          controller: _bankNameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: _deco(hint: 'اسم البنك أو Wise Email'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _bankIbanCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: _deco(hint: 'IBAN / رقم الحساب'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _bankCountryCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: _deco(hint: 'كود الدولة (SA / AE / GB...)'),
        ),

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_processing || !widget.isKycVerified ||
                        _netUsd < e.minWithdrawalUsd) ? null : _withdraw,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _processing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : Text('سحب \$${_netUsd.toStringAsFixed(2)} صافي',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ),
      ]),
    );
  }
}

class _InvoicePreview extends StatelessWidget {
  final double gross, fee, net, feePct;
  const _InvoicePreview({required this.gross, required this.fee, required this.net, required this.feePct});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(children: [
        _ILine(label: 'المبلغ الإجمالي', value: '\$${gross.toStringAsFixed(2)}', color: Colors.white70),
        _ILine(label: 'رسوم ${feePct.toStringAsFixed(0)}%', value: '-\$${fee.toStringAsFixed(2)}', color: Colors.redAccent),
        const Divider(color: Colors.white12, height: 20),
        _ILine(label: 'الصافي للتحويل', value: '\$${net.toStringAsFixed(2)}',
            color: const Color(0xFF00E5A0), bold: true),
      ]),
    );
  }
}

class _ILine extends StatelessWidget {
  final String label, value;
  final Color color;
  final bool bold;
  const _ILine({required this.label, required this.value, required this.color, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Text(value, style: TextStyle(color: color,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontSize: bold ? 16 : 13)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Tab 3: تحويل إلى وكيل الشحن
// ═══════════════════════════════════════════════════════════════════
class _TransferRechargeTab extends StatefulWidget {
  final AgencyMemberInfo member;
  final int? initialDiamonds;
  final VoidCallback onDone;
  const _TransferRechargeTab({
    required this.member,
    this.initialDiamonds,
    required this.onDone,
  });

  @override
  State<_TransferRechargeTab> createState() => _TransferRechargeTabState();
}

class _TransferRechargeTabState extends State<_TransferRechargeTab> {
  final _searchCtrl   = TextEditingController();
  final _diamondsCtrl = TextEditingController();
  Map<String, dynamic>? _selectedAgent;
  List<Map<String, dynamic>> _results = [];
  bool _searching   = false;
  bool _processing  = false;
  int  _diamonds    = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialDiamonds != null && widget.initialDiamonds! > 0) {
      _diamonds = widget.initialDiamonds!;
      _diamondsCtrl.text = _diamonds.toString();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose(); _diamondsCtrl.dispose(); _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) { setState(() => _results = []); return; }
    setState(() => _searching = true);
    try {
      final res = await AgencyRepository.searchRechargeAgents(q);
      if (!mounted) return;
      setState(() { _results = res; _searching = false; });
    } catch (e) {
debugPrint('[agency_withdrawal_screen] error: $e');
      if (mounted) setState(() { _searching = false; _results = []; });
    }
  }

  Future<void> _confirmTransfer() async {
    if (_selectedAgent == null || _diamonds <= 0) {
      _snack('اختر وكيل شحن وأدخل الكمية'); return;
    }
    if (_diamonds > widget.member.diamondsAvailable) {
      _snack('الرصيد المتاح غير كافٍ. المتاح: ${widget.member.diamondsAvailable} ♦'); return;
    }

    // Dialog تأكيد مزدوج
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('تأكيد التحويل', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.send_rounded, color: Color(0xFF00D4FF), size: 40),
          const SizedBox(height: 12),
          Text('سيتم تحويل ${_fmtK(_diamonds)} ♦ إلى:',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Text(_selectedAgent!['display_name'] as String? ?? '—',
              style: const TextStyle(color: Color(0xFF00D4FF), fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('العملية فورية ولا يمكن التراجع عنها.',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00D4FF), foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _processing = true);
    try {
      final key = '${widget.member.memberId}_txfr_${DateTime.now().millisecondsSinceEpoch}';
      final res = await AgencyRepository.transferDiamondsToAgentWallet(
        agentId:         _selectedAgent!['id'] as String,
        diamonds:        _diamonds,
        idempotencyKey:  key,
        source:          'host',
      );
      if (res['success'] != true) {
        _snack(res['error']?.toString() ?? 'فشل التحويل');
        setState(() => _processing = false);
        return;
      }
      if (!mounted) return;
      _snack('✅ تم التحويل بنجاح إلى ${_selectedAgent!['display_name']}');
      _diamondsCtrl.clear();
      _searchCtrl.clear();
      setState(() { _diamonds = 0; _selectedAgent = null; _results = []; });
      widget.onDone();
    } catch (e) {
      if (mounted) _snack('خطأ: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _InfoCard(
          icon: '🔄',
          title: 'تحويل إلى وكيل شحن',
          lines: [
            'بدون رسوم — فوري',
            'الألماس يُحوَّل لمحفظة الوكيل مباشرةً',
            'لا تحويل للعملة — ألماس إلى ألماس',
            'يتطلب تأكيداً مزدوجاً',
          ],
        ),
        const SizedBox(height: 20),

        Text('ابحث عن وكيل الشحن', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true, fillColor: Colors.white.withOpacity(0.06),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF00D4FF))),
            hintText: 'ابحث بالاسم أو الـ ID الرقمي للوكيل',
            hintStyle: const TextStyle(color: Colors.white24),
            prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
            suffixIcon: _searching
                ? const Padding(padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38)))
                : null,
          ),
          onChanged: _onSearchChanged,
        ),

        // نتائج البحث
        if (_results.isNotEmpty && _selectedAgent == null)
          ..._results.map((r) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF00D4FF).withOpacity(0.15),
              backgroundImage: r['avatar_url'] != null ? EncryptedImageProvider(r['avatar_url'] as String) : null,
              child: r['avatar_url'] == null ? const Icon(Icons.person, color: Color(0xFF00D4FF)) : null,
            ),
            title: Text(r['display_name'] as String? ?? '—', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: r['kayan_id'] != null
                ? Text('ID: ${r['kayan_id']}', style: const TextStyle(color: Colors.white54, fontSize: 11))
                : null,
            trailing: const Icon(Icons.chevron_left_rounded, color: Colors.white38),
            onTap: () => setState(() {
              _selectedAgent = r;
              _results = [];
              _searchCtrl.text = r['display_name'] as String? ?? '';
            }),
          )),

        // الوكيل المختار
        if (_selectedAgent != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF00D4FF).withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF00D4FF).withOpacity(0.2),
                    backgroundImage: _selectedAgent!['avatar_url'] != null
                        ? EncryptedImageProvider(_selectedAgent!['avatar_url'] as String)
                        : null,
                    child: _selectedAgent!['avatar_url'] == null
                        ? const Icon(Icons.person, color: Color(0xFF00D4FF))
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_selectedAgent!['display_name']}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        Text('معرف الوكيل: ${_selectedAgent!['kayan_id'] ?? _selectedAgent!['id']}',
                            style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 12)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() { _selectedAgent = null; _searchCtrl.clear(); }),
                    child: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
                  ),
                ]),
                const SizedBox(height: 12),
                // زر التواصل المباشر مع الوكيل
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00D4FF),
                      side: const BorderSide(color: Color(0xFF00D4FF)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                    label: const Text('تواصل مع الوكيل لتحويل العملات إليه', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      final agentUid = _selectedAgent!['id']?.toString() ?? _selectedAgent!['user_id']?.toString() ?? '';
                      final myUid = Supabase.instance.client.auth.currentUser?.id ?? '';
                      if (agentUid.isNotEmpty && myUid.isNotEmpty) {
                        final convId = (myUid.compareTo(agentUid) < 0) ? '${myUid}_$agentUid' : '${agentUid}_$myUid';
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MessageReplyDetailScreen(
                              conversationId: convId,
                              otherUid: agentUid,
                              otherName: _selectedAgent!['display_name']?.toString() ?? 'وكيل الشحن',
                              otherPhotoUrl: _selectedAgent!['avatar_url']?.toString() ?? '',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),
        Text('كمية الرصيد / الألماس للتحويل', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _diamondsCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          decoration: _deco(hint: '0', suffix: '♦', color: const Color(0xFF00D4FF)),
          onChanged: (v) => setState(() => _diamonds = int.tryParse(v) ?? 0),
        ),

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_processing || _selectedAgent == null || _diamonds <= 0) ? null : _confirmTransfer,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D4FF),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _processing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('تحويل فوري إلى وكيل الشحن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Tab 4: سجل المعاملات (من agency_diamond_ledger)
// ═══════════════════════════════════════════════════════════════════
class _TransactionHistoryTab extends StatefulWidget {
  const _TransactionHistoryTab();

  @override
  State<_TransactionHistoryTab> createState() => _TransactionHistoryTabState();
}

class _TransactionHistoryTabState extends State<_TransactionHistoryTab> {
  List<AgencyLedgerEntry> _items = [];
  bool _loading = true;
  String? _filterType;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await AgencyRepository.getTransactionHistory(type: _filterType);
      if (!mounted) return;
      setState(() { _items = rows; _loading = false; });
    } catch (e) {
debugPrint('[agency_withdrawal_screen] error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));

    return Column(children: [
      // فلتر
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            _FilterChip(label: 'الكل', active: _filterType == null, onTap: () { setState(() => _filterType = null); _load(); }),
            _FilterChip(label: 'عمولات', active: _filterType == 'gift_commission', onTap: () { setState(() => _filterType = 'gift_commission'); _load(); }),
            _FilterChip(label: 'تبادل', active: _filterType == 'exchange_out', onTap: () { setState(() => _filterType = 'exchange_out'); _load(); }),
            _FilterChip(label: 'سحب', active: _filterType == 'withdrawal_lock', onTap: () { setState(() => _filterType = 'withdrawal_lock'); _load(); }),
            _FilterChip(label: 'تحويل', active: _filterType == 'transfer_out', onTap: () { setState(() => _filterType = 'transfer_out'); _load(); }),
            _FilterChip(label: 'مكافآت', active: _filterType == 'bonus', onTap: () { setState(() => _filterType = 'bonus'); _load(); }),
          ],
        ),
      ),

      if (_items.isEmpty)
        Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('📋', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text('لا توجد معاملات', style: TextStyle(color: Colors.white.withOpacity(0.4))),
        ])))
      else
        Expanded(
          child: RefreshIndicator(
            color: const Color(0xFFD4AF37),
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final e = _items[i];
                final isCredit = e.isCredit;
                final color = isCredit ? const Color(0xFF00E5A0) : const Color(0xFFFF5252);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.15)),
                  ),
                  child: Row(children: [
                    Text(isCredit ? '📈' : '📤', style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.typeLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                      if (e.note != null)
                        Text(e.note!, style: const TextStyle(color: Colors.white38, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(_fmt(e.createdAt), style: const TextStyle(color: Colors.white24, fontSize: 10)),
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${isCredit ? '+' : '-'}${_fmtK(e.amount)} ♦',
                          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                      Text('رصيد: ${_fmtK(e.balanceAfter)} ♦',
                          style: const TextStyle(color: Colors.white24, fontSize: 10)),
                    ]),
                  ]),
                );
              },
            ),
          ),
        ),
    ]);
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFD4AF37) : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? const Color(0xFFD4AF37) : Colors.white12),
          ),
          child: Text(label, style: TextStyle(
            color: active ? Colors.black : Colors.white54,
            fontSize: 12, fontWeight: FontWeight.w600,
          )),
        ),
      ),
    );
  }
}

// ─── Shared Helpers ───────────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final String icon, title;
  final List<String> lines;
  const _InfoCard({required this.icon, required this.title, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
        const SizedBox(height: 10),
        ...lines.map((l) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('• ', style: TextStyle(color: Colors.white.withOpacity(0.4))),
            Expanded(child: Text(l, style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12, height: 1.5))),
          ]),
        )),
      ]),
    );
  }
}

InputDecoration _deco({required String hint, String? suffix, Color? color}) {
  return InputDecoration(
    filled: true, fillColor: Colors.white.withOpacity(0.06),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color ?? const Color(0xFFD4AF37))),
    hintText: hint, hintStyle: const TextStyle(color: Colors.white24),
    suffixText: suffix,
    suffixStyle: TextStyle(color: color ?? const Color(0xFFD4AF37), fontSize: 16),
  );
}

String _fmtK(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}K';
  return n.toString();
}
