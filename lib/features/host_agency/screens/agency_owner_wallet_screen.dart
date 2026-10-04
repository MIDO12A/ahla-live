import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/supabase_compat.dart';

import '../../../core/utils/server_time_service.dart';
import '../data/agency_models.dart';
import '../data/agency_repository.dart';
import '../../../core/cache/encrypted_image_provider.dart';

// ═══════════════════════════════════════════════════════════════════
//  AgencyOwnerWalletScreen — محفظة مالك الوكالة
//
//  Tab 1: نظرة عامة (الرصيد + المتاح + المجمّد + الكلي)
//  Tab 2: تبادل الألماس بكوينز (بمعدل من DB)
//  Tab 3: سحب نقدي بالدولار (KYC مطلوب + رسوم من DB)
//  Tab 4: سجل حركات دفتر الوكالة
//
//  ✅ جميع الأسعار من قاعدة البيانات — لا ثوابت مشفّرة
//  ✅ Realtime على agency_owner_ledger
//  ✅ idempotency_key فريد يمنع التكرار
// ═══════════════════════════════════════════════════════════════════

class AgencyOwnerWalletScreen extends StatefulWidget {
  final String agencyId;
  const AgencyOwnerWalletScreen({super.key, required this.agencyId});

  @override
  State<AgencyOwnerWalletScreen> createState() =>
      _AgencyOwnerWalletScreenState();
}

class _AgencyOwnerWalletScreenState extends State<AgencyOwnerWalletScreen>
    with SingleTickerProviderStateMixin {
  // ── حالة ─────────────────────────────────────────────────────────
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  AgencyOwnerDashboard? _dash;

  // ── Realtime ──────────────────────────────────────────────────────
  RealtimeChannel? _rtChannel;

  // ── حقول التبادل ─────────────────────────────────────────────────
  final _exchangeCtrl = TextEditingController();
  bool _exchangeBusy  = false;

  // ── حقول السحب ───────────────────────────────────────────────────
  final _withdrawCtrl       = TextEditingController();
  final _payMethodCtrl      = TextEditingController(text: 'bank_transfer');
  final _payDetailCtrl      = TextEditingController();
  bool _withdrawBusy        = false;

  // ── ثوابت لون ────────────────────────────────────────────────────
  static const _gold  = Color(0xFFD4A843);
  static const _dark  = Color(0xFF0E0E1A);
  static const _card  = Color(0xFF1A1A2E);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _exchangeCtrl.dispose();
    _withdrawCtrl.dispose();
    _payMethodCtrl.dispose();
    _payDetailCtrl.dispose();
    _rtChannel?.unsubscribe();
    super.dispose();
  }

  // ─── تحميل البيانات ───────────────────────────────────────────────
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await AgencyRepository.getOwnerDashboard(widget.agencyId);
      setState(() { _dash = d; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ─── Realtime ─────────────────────────────────────────────────────
  void _subscribeRealtime() {
    _rtChannel = Supabase.instance.client
        .channel('owner_ledger_${widget.agencyId}')
        .onPostgresChanges(
          event:  PostgresChangeEvent.insert,
          schema: 'public',
          table:  'agency_owner_ledger',
          filter: PostgresChangeFilter(
            type:  PostgresChangeFilterType.eq,
            column: 'agency_id',
            value:  widget.agencyId,
          ),
          callback: (_) => _load(),
        )
        .subscribe();
  }

  // ─── تبادل ألماس → كوينز ─────────────────────────────────────────
  Future<void> _doExchange() async {
    final amount = int.tryParse(_exchangeCtrl.text.trim()) ?? 0;
    if (amount <= 0) { _show('أدخل مبلغاً صحيحاً'); return; }
    final wallet  = _dash?.wallet;
    if (wallet == null || wallet.available < amount) {
      _show('الرصيد المتاح غير كافٍ (${_fmt(wallet?.available ?? 0)} ألماس)');
      return;
    }
    final idempKey = 'owner_ex_${ServerTimeService.instance.now().millisecondsSinceEpoch}';
    setState(() => _exchangeBusy = true);
    try {
      final res = await AgencyRepository.ownerExchangeDiamonds(
        agencyId:       widget.agencyId,
        diamondsAmount: amount,
        idempotencyKey: idempKey,
      );
      if (mounted) {
        final coins = res['coins'] ?? 0;
        _show('✅ تم التبادل: ${_fmt(amount)} ألماس → ${_fmt(coins)} كوينز', ok: true);
        _exchangeCtrl.clear();
        await _load();
      }
    } catch (e) {
      if (mounted) _show('فشل التبادل: $e');
    } finally {
      if (mounted) setState(() => _exchangeBusy = false);
    }
  }

  // ─── طلب سحب نقدي ────────────────────────────────────────────────
  Future<void> _doWithdrawal() async {
    final amount  = int.tryParse(_withdrawCtrl.text.trim()) ?? 0;
    final method  = _payMethodCtrl.text.trim();
    final details = _payDetailCtrl.text.trim();
    if (amount <= 0) { _show('أدخل مبلغاً صحيحاً'); return; }
    if (method.isEmpty) { _show('اختر طريقة الدفع'); return; }

    final minD = _dash?.rates.minDiamondsToWithdraw ?? 100000;
    if (amount < minD) {
      _show('الحد الأدنى للسحب: ${_fmt(minD)} ألماس');
      return;
    }

    final wallet = _dash?.wallet;
    if (wallet == null || wallet.available < amount) {
      _show('الرصيد المتاح غير كافٍ (${_fmt(wallet?.available ?? 0)} ألماس)');
      return;
    }

    final confirmed = await _confirmDialog(amount);
    if (!confirmed) return;

    setState(() => _withdrawBusy = true);
    try {
      await AgencyRepository.ownerRequestWithdrawal(
        agencyId:       widget.agencyId,
        diamondsAmount: amount,
        paymentMethod:  method,
        paymentDetails: details.isEmpty ? {} : {'details': details},
      );
      if (mounted) {
        final net = _dash!.rates.netUsdFromDiamonds(amount);
        _show('✅ طلب السحب أُرسل — صافي ≈ \$${net.toStringAsFixed(2)}', ok: true);
        _withdrawCtrl.clear();
        _payDetailCtrl.clear();
        await _load();
      }
    } catch (e) {
      if (mounted) _show('فشل طلب السحب: $e');
    } finally {
      if (mounted) setState(() => _withdrawBusy = false);
    }
  }

  Future<bool> _confirmDialog(int amount) async {
    final rates  = _dash!.rates;
    final gross  = rates.grossUsdFromDiamonds(amount);
    final net    = rates.netUsdFromDiamonds(amount);
    final fee    = gross - net;
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: const Text('تأكيد طلب السحب',
            style: TextStyle(color: _gold, fontFamily: 'Tajawal')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dRow('الألماس',   '${_fmt(amount)} 💎'),
            _dRow('الإجمالي',  '\$${gross.toStringAsFixed(2)}'),
            _dRow('الرسوم ${rates.withdrawalFeePct.toStringAsFixed(0)}%',
                  '-\$${fee.toStringAsFixed(2)}'),
            const Divider(color: Colors.white24),
            _dRow('الصافي',    '\$${net.toStringAsFixed(2)}',
                  bold: true, color: _gold),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء', style: TextStyle(color: Colors.white70))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _gold),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    ) ?? false;
  }

  // ─── مساعدات ─────────────────────────────────────────────────────
  void _show(String msg, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Tajawal')),
      backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
    ));
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(2)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  Widget _dRow(String label, String val,
      {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal',
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(val,
              style: TextStyle(
                  color: color ?? Colors.white,
                  fontFamily: 'Tajawal',
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  UI
  // ════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: _dark,
        elevation: 0,
        title: const Text('محفظة الوكالة',
            style: TextStyle(color: _gold, fontFamily: 'Tajawal',
                fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: _gold),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: _gold),
            onPressed: _load,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _gold,
          labelColor: _gold,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontFamily: 'Tajawal', fontSize: 12),
          tabs: const [
            Tab(text: 'نظرة عامة'),
            Tab(text: 'تبادل'),
            Tab(text: 'سحب'),
            Tab(text: '🔄 وكيل'),
            Tab(text: 'السجل'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : _error != null
              ? _buildError()
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildOverview(),
                    _buildExchange(),
                    _buildWithdrawal(),
                    _OwnerTransferToAgentTab(agencyId: widget.agencyId, onDone: _load),
                    _buildLedger(),
                  ],
                ),
    );
  }

  // ── تبويب 1: نظرة عامة ──────────────────────────────────────────
  Widget _buildOverview() {
    final w = _dash?.wallet ?? AgencyOwnerWallet.empty();
    final r = _dash?.rates;
    return RefreshIndicator(
      onRefresh: _load,
      color: _gold,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // بطاقة الألماس الرئيسية
          _walletCard(
            title: 'إجمالي الألماس',
            value: '${_fmt(w.balance)} 💎',
            sub: 'المتاح: ${_fmt(w.available)} | مجمّد: ${_fmt(w.pending)}',
          ),
          const SizedBox(height: 12),
          // بطاقة الكلي المكتسب
          _walletCard(
            title: 'إجمالي مكتسب (كل الوقت)',
            value: '${_fmt(w.earnedTotal)} 💎',
            color: Colors.purple.shade700,
          ),
          const SizedBox(height: 20),

          if (r != null) ...[
            const Text('معدلات المحرك الحالية',
                style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal',
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _rateRow('ألماس → كوينز',
                '1 ألماس = ${r.diamondToCoinRate} كوينز'),
            _rateRow('ألماس → دولار',
                '1000 ألماس = \$${(r.diamondToUsdRate * 1000).toStringAsFixed(2)}'),
            _rateRow('رسوم السحب', '${r.withdrawalFeePct.toStringAsFixed(0)}%'),
            _rateRow('الحد الأدنى للسحب', '${_fmt(r.minDiamondsToWithdraw)} ألماس'),
            _rateRow('حصتك من الهدايا', '${r.agencySharePct}% (وكالة) + ${r.hostSharePct}% (مضيف)'),
          ],

          const SizedBox(height: 20),
          // أزرار سريعة
          Row(children: [
            Expanded(child: _quickBtn('تبادل بكوينز', Icons.currency_exchange,
                () => _tabs.animateTo(1))),
            const SizedBox(width: 10),
            Expanded(child: _quickBtn('سحب بالدولار', Icons.account_balance,
                () => _tabs.animateTo(2))),
          ]),
        ],
      ),
    );
  }

  Widget _walletCard({
    required String title,
    required String value,
    String? sub,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: color != null
              ? [color, color.withOpacity(0.7)]
              : [const Color(0xFF2A2040), const Color(0xFF1A1030)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(color: Colors.white70,
                  fontFamily: 'Tajawal', fontSize: 13)),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(color: _gold, fontFamily: 'Tajawal',
                  fontSize: 24, fontWeight: FontWeight.bold)),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub,
                style: const TextStyle(color: Colors.white54,
                    fontFamily: 'Tajawal', fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _rateRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white60,
                  fontFamily: 'Tajawal')),
          Text(val,
              style: const TextStyle(color: _gold,
                  fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _quickBtn(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _gold.withOpacity(0.4)),
        ),
        child: Column(children: [
          Icon(icon, color: _gold, size: 22),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(color: Colors.white,
                  fontFamily: 'Tajawal', fontSize: 12)),
        ]),
      ),
    );
  }

  // ── تبويب 2: تبادل ──────────────────────────────────────────────
  Widget _buildExchange() {
    final w = _dash?.wallet;
    final r = _dash?.rates;
    final available = w?.available ?? 0;
    final rate      = r?.diamondToCoinRate ?? 0.5;

    int preview() {
      final d = int.tryParse(_exchangeCtrl.text.trim()) ?? 0;
      return (d * rate).floor();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // رصيد متاح
        _infoBox('الرصيد المتاح', '${_fmt(available)} 💎'),
        const SizedBox(height: 16),

        // حقل الكمية
        _label('عدد الألماس للتبادل'),
        const SizedBox(height: 8),
        _inputField(_exchangeCtrl, 'مثال: 50000',
            suffix: 'ألماس', onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),

        // معاينة الكوينز
        StatefulBuilder(builder: (_, st) {
          final coins = preview();
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade800),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('ستحصل على:', style: TextStyle(color: Colors.white70,
                    fontFamily: 'Tajawal')),
                Text('${_fmt(coins)} 🪙',
                    style: const TextStyle(color: Colors.amber,
                        fontFamily: 'Tajawal', fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          );
        }),

        const SizedBox(height: 8),
        Text('المعدل: 1 ألماس = $rate كوينز',
            style: const TextStyle(color: Colors.white38,
                fontFamily: 'Tajawal', fontSize: 12),
            textAlign: TextAlign.center),

        const SizedBox(height: 20),
        _actionBtn('تبادل الآن 🔄', _exchangeBusy, _doExchange),
      ],
    );
  }

  // ── تبويب 3: سحب نقدي ───────────────────────────────────────────
  Widget _buildWithdrawal() {
    final w    = _dash?.wallet;
    final r    = _dash?.rates;
    final avail= w?.available ?? 0;
    final minD = r?.minDiamondsToWithdraw ?? 100000;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // تحذير KYC
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade900.withOpacity(0.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade700),
          ),
          child: const Row(children: [
            Icon(Icons.warning_amber, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(child: Text(
              'يتطلب السحب إكمال التحقق من الهوية (KYC) مسبقاً.',
              style: TextStyle(color: Colors.orange,
                  fontFamily: 'Tajawal', fontSize: 12),
            )),
          ]),
        ),
        const SizedBox(height: 14),

        _infoBox('الرصيد المتاح', '${_fmt(avail)} 💎'),
        const SizedBox(height: 4),
        Text('الحد الأدنى: ${_fmt(minD)} ألماس',
            style: const TextStyle(color: Colors.white38,
                fontFamily: 'Tajawal', fontSize: 12)),
        const SizedBox(height: 14),

        _label('عدد الألماس للسحب'),
        const SizedBox(height: 8),
        _inputField(_withdrawCtrl, 'مثال: 100000',
            suffix: 'ألماس', onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),

        // معاينة الدولار
        Builder(builder: (_) {
          final d     = int.tryParse(_withdrawCtrl.text.trim()) ?? 0;
          final gross = (r?.grossUsdFromDiamonds(d) ?? 0);
          final net   = (r?.netUsdFromDiamonds(d) ?? 0);
          final fee   = gross - net;
          if (d <= 0) return const SizedBox.shrink();
          return Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade800),
            ),
            child: Column(children: [
              _dRow('الإجمالي', '\$${gross.toStringAsFixed(2)}'),
              _dRow('الرسوم', '-\$${fee.toStringAsFixed(2)}'),
              const Divider(color: Colors.white12),
              _dRow('الصافي', '\$${net.toStringAsFixed(2)}',
                  bold: true, color: Colors.greenAccent),
            ]),
          );
        }),

        _label('طريقة الدفع'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _payMethodCtrl.text,
              dropdownColor: _card,
              style: const TextStyle(color: Colors.white,
                  fontFamily: 'Tajawal'),
              items: const [
                DropdownMenuItem(value: 'bank_transfer',
                    child: Text('تحويل بنكي (رسوم حد أقصى \$25)')),
                DropdownMenuItem(value: 'payoneer',
                    child: Text('Payoneer')),
                DropdownMenuItem(value: 'usdt',
                    child: Text('USDT (TRC20)')),
                DropdownMenuItem(value: 'paypal',
                    child: Text('PayPal')),
                DropdownMenuItem(value: 'wise',
                    child: Text('Wise')),
              ],
              onChanged: (v) => setState(() =>
                  _payMethodCtrl.text = v ?? 'bank_transfer'),
            ),
          ),
        ),
        const SizedBox(height: 10),

        _label('تفاصيل الدفع (اختياري)'),
        const SizedBox(height: 8),
        _inputField(_payDetailCtrl, 'رقم الحساب / البريد الإلكتروني...',
            maxLines: 2),
        const SizedBox(height: 20),
        _actionBtn('طلب السحب 💵', _withdrawBusy, _doWithdrawal,
            color: Colors.green.shade700),
      ],
    );
  }

  // ── تبويب 4: السجل ───────────────────────────────────────────────
  Widget _buildLedger() {
    final entries = _dash?.ledger ?? [];
    if (entries.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.receipt_long, color: Colors.white24, size: 48),
          const SizedBox(height: 12),
          const Text('لا توجد حركات بعد',
              style: TextStyle(color: Colors.white38, fontFamily: 'Tajawal')),
          TextButton(onPressed: _load,
              child: const Text('تحديث', style: TextStyle(color: _gold))),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _gold,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const Divider(color: Colors.white12),
        itemBuilder: (_, i) => _ledgerTile(entries[i]),
      ),
    );
  }

  Widget _ledgerTile(AgencyOwnerLedgerEntry e) {
    final isIn  = e.isCredit;
    final color = isIn ? Colors.greenAccent : Colors.redAccent;
    final sign  = isIn ? '+' : '−';
    final dt    = e.createdAt.toLocal();
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isIn ? Icons.arrow_downward : Icons.arrow_upward,
          color: color, size: 18,
        ),
      ),
      title: Text(e.typeLabel,
          style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal',
              fontSize: 13)),
      subtitle: Text(
        e.note ?? '',
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white38, fontFamily: 'Tajawal',
            fontSize: 11),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('$sign${_fmt(e.amount)} 💎',
              style: TextStyle(color: color, fontFamily: 'Tajawal',
                  fontWeight: FontWeight.bold, fontSize: 13)),
          Text(
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}',
            style: const TextStyle(color: Colors.white38, fontSize: 10,
                fontFamily: 'Tajawal'),
          ),
        ],
      ),
    );
  }

  // ─── مكونات مشتركة ────────────────────────────────────────────────
  Widget _buildError() {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
        const SizedBox(height: 12),
        Text(_error ?? 'خطأ غير معروف',
            style: const TextStyle(color: Colors.white70,
                fontFamily: 'Tajawal'),
            textAlign: TextAlign.center),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: _gold),
          onPressed: _load,
          icon: const Icon(Icons.refresh, color: Colors.black),
          label: const Text('إعادة المحاولة',
              style: TextStyle(color: Colors.black, fontFamily: 'Tajawal')),
        ),
      ],
    ));
  }

  Widget _infoBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70,
              fontFamily: 'Tajawal')),
          Text(value, style: const TextStyle(color: _gold,
              fontFamily: 'Tajawal', fontWeight: FontWeight.bold,
              fontSize: 18)),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Text(text, style: const TextStyle(color: Colors.white70,
        fontFamily: 'Tajawal', fontSize: 13));
  }

  Widget _inputField(
    TextEditingController ctrl,
    String hint, {
    String? suffix,
    int maxLines = 1,
    void Function(String)? onChanged,
  }) {
    return TextField(
      controller:   ctrl,
      keyboardType: maxLines == 1 ? TextInputType.number : TextInputType.text,
      maxLines:     maxLines,
      inputFormatters: maxLines == 1
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      onChanged:    onChanged,
      style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal'),
      decoration: InputDecoration(
        hintText:      hint,
        hintStyle:     const TextStyle(color: Colors.white24),
        suffixText:    suffix,
        suffixStyle:   const TextStyle(color: Colors.white38),
        filled:        true,
        fillColor:     _card,
        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                           borderSide: BorderSide(color: Colors.white12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                           borderSide: const BorderSide(color: Colors.white12)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                           borderSide: const BorderSide(color: _gold)),
      ),
    );
  }

  Widget _actionBtn(String label, bool busy, VoidCallback onTap,
      {Color? color}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? _gold,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: busy ? null : onTap,
        child: busy
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.black))
            : Text(label,
                style: const TextStyle(color: Colors.black,
                    fontFamily: 'Tajawal', fontWeight: FontWeight.bold,
                    fontSize: 15)),
      ),
    );
  }
}

// ════════════════════════���══════════════════════���═══════════════════
//  _OwnerTransferToAgentTab — مالك الوكالة يحوّل لوكيل شحن
// ══════════════════════════════════════════════���════════════════════
class _OwnerTransferToAgentTab extends StatefulWidget {
  final String agencyId;
  final VoidCallback onDone;
  const _OwnerTransferToAgentTab({required this.agencyId, required this.onDone});
  @override
  State<_OwnerTransferToAgentTab> createState() => _OwnerTransferToAgentTabState();
}

class _OwnerTransferToAgentTabState extends State<_OwnerTransferToAgentTab> {
  static const _gold = Color(0xFFD4A843);
  static const _dark = Color(0xFF0E0E1A);
  static const _card = Color(0xFF1A1A2E);

  final _searchCtrl   = TextEditingController();
  final _diamondsCtrl = TextEditingController();

  Map<String, dynamic>? _selectedAgent;
  List<Map<String, dynamic>> _results = [];
  bool _searching  = false;
  bool _processing = false;
  int  _diamonds   = 0;
  Timer? _debounce;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _diamondsCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String q) {
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
      debugPrint('[owner_transfer] search error: $e');
      if (mounted) setState(() { _searching = false; _results = []; });
    }
  }

  String _fmtK(int n) {
    if (n >= 1000000) return '${(n/1000000).toStringAsFixed(1)}م';
    if (n >= 1000)    return '${(n/1000).toStringAsFixed(1)}ك';
    return '$n';
  }

  Future<void> _confirm() async {
    if (_selectedAgent == null || _diamonds <= 0) {
      _snack('اختر وكيل شحن وأدخل الكمية'); return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: const Text('تأكيد تحويل الألماس',
            style: TextStyle(color: _gold, fontFamily: 'Tajawal')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.diamond_rounded, color: _gold, size: 40),
          const SizedBox(height: 12),
          Text('سيتم تحويل ${_fmtK(_diamonds)} ♦ من محفظة الوكالة إلى:',
              style: const TextStyle(color: Colors.white70, fontSize: 13,
                  fontFamily: 'Tajawal'), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(_selectedAgent!['display_name'] as String? ?? '—',
              style: const TextStyle(color: _gold, fontWeight: FontWeight.bold,
                  fontSize: 16, fontFamily: 'Tajawal')),
          const SizedBox(height: 8),
          const Text('العملية فورية ولا يمكن التراجع عنها.',
              style: TextStyle(color: Colors.white38, fontSize: 11,
                  fontFamily: 'Tajawal')),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء',
                style: TextStyle(color: Colors.white38, fontFamily: 'Tajawal'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _gold),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد التحويل',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold,
                    fontFamily: 'Tajawal'))),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _processing = true);
    try {
      final key = 'owner_txfr_${widget.agencyId}_${DateTime.now().millisecondsSinceEpoch}';
      final res = await AgencyRepository.transferDiamondsToAgentWallet(
        agentId:        _selectedAgent!['id'] as String,
        diamonds:       _diamonds,
        idempotencyKey: key,
        source:         'agency_owner',
      );
      if (!mounted) return;
      if (res['success'] == true) {
        _snack('✅ تم التحويل بنجاح إلى ${_selectedAgent!['display_name']}');
        _diamondsCtrl.clear();
        _searchCtrl.clear();
        setState(() { _diamonds = 0; _selectedAgent = null; _results = []; });
        widget.onDone();
      } else {
        _snack(res['error']?.toString() ?? 'فشل التحويل');
      }
    } catch (e) {
      debugPrint('[owner_transfer] confirm error: $e');
      if (mounted) _snack('خطأ: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Tajawal'))));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ─── شرح ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _gold.withValues(alpha: 0.3)),
          ),
          child: const Text(
            '💡 يمكنك تحويل الألماس من محفظة وكالتك مباشرةً لوكيل شحن. '
            'سيستلمه في محفظة الألماس الخاصة به ويقدر يسحبه عبر الإدارة.',
            style: TextStyle(color: _gold, fontSize: 13,
                fontFamily: 'Tajawal', height: 1.5),
          ),
        ),
        const SizedBox(height: 20),

        // ─── بحث عن وكيل ──────────────────────────────────────────
        const Text('ابحث عن وكيل الشحن',
            style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal',
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: _card, borderRadius: BorderRadius.circular(12)),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal'),
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(
              hintText: 'الاسم أو Kayan ID',
              hintStyle: TextStyle(color: Colors.white38, fontFamily: 'Tajawal'),
              prefixIcon: Icon(Icons.search, color: Colors.white38),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            onChanged: _onSearch,
          ),
        ),

        // نتائج البحث
        if (_searching)
          const Padding(padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(color: _gold))),
        if (!_searching && _results.isNotEmpty)
          ...(_results.map((a) => _AgentResultTile(
            agent: a,
            selected: _selectedAgent?['id'] == a['id'],
            onTap: () => setState(() {
              _selectedAgent = a;
              _searchCtrl.text = a['display_name'] as String? ?? '';
              _results = [];
            }),
          ))),

        // الوكيل المختار
        if (_selectedAgent != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _gold.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _card,
                backgroundImage: (_selectedAgent!['avatar_url'] as String?)?.isNotEmpty == true
                    ? EncryptedImageProvider(_selectedAgent!['avatar_url'] as String)
                    : null,
                child: (_selectedAgent!['avatar_url'] as String?)?.isNotEmpty != true
                    ? const Icon(Icons.person_rounded, color: _gold, size: 22)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_selectedAgent!['display_name'] as String? ?? '—',
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold, fontFamily: 'Tajawal')),
                  if (_selectedAgent!['kayan_id'] != null)
                    Text('ID: ${_selectedAgent!['kayan_id']}',
                        style: const TextStyle(color: Colors.white54,
                            fontSize: 12, fontFamily: 'Tajawal')),
                ],
              )),
              GestureDetector(
                onTap: () => setState(() {
                  _selectedAgent = null; _searchCtrl.clear();
                }),
                child: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 20),

        // ─── حقل المبلغ ──────────────────────────────���─────────────
        const Text('مبلغ الألماس',
            style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal',
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: _card, borderRadius: BorderRadius.circular(12)),
          child: TextField(
            controller: _diamondsCtrl,
            style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal',
                fontSize: 18, fontWeight: FontWeight.bold),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              hintText: '0',
              hintStyle: TextStyle(color: Colors.white24),
              suffixText: '♦',
              suffixStyle: TextStyle(color: _gold, fontSize: 18),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 16),
            ),
            onChanged: (v) => setState(() => _diamonds = int.tryParse(v) ?? 0),
          ),
        ),

        const SizedBox(height: 24),

        // ─── زر التحويل ─────────────────────────────���─────────────
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedAgent != null && _diamonds > 0
                  ? _gold : Colors.white12,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _selectedAgent != null && _diamonds > 0 && !_processing
                ? _confirm : null,
            child: _processing
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('تأكيد التحويل لوكيل الشحن',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold,
                        fontSize: 15, fontFamily: 'Tajawal')),
          ),
        ),
      ],
    );
  }
}

// ─── بطاقة نتيجة وكيل ────────────────────���───────────────────────────────────
class _AgentResultTile extends StatelessWidget {
  final Map<String, dynamic> agent;
  final bool selected;
  final VoidCallback onTap;
  const _AgentResultTile({required this.agent, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFD4A843).withValues(alpha: 0.15)
            : const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? const Color(0xFFD4A843) : Colors.transparent),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFF0E0E1A),
          backgroundImage: (agent['avatar_url'] as String?)?.isNotEmpty == true
              ? EncryptedImageProvider(agent['avatar_url'] as String) : null,
          child: (agent['avatar_url'] as String?)?.isNotEmpty != true
              ? const Icon(Icons.person_rounded, color: Colors.white38, size: 18) : null,
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(agent['display_name'] as String? ?? '—',
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w600, fontFamily: 'Tajawal')),
            if (agent['kayan_id'] != null)
              Text('ID: ${agent['kayan_id']}',
                  style: const TextStyle(color: Colors.white38,
                      fontSize: 11, fontFamily: 'Tajawal')),
          ],
        )),
        if (selected)
          const Icon(Icons.check_circle_rounded,
              color: Color(0xFFD4A843), size: 20),
      ]),
    ),
  );
}

