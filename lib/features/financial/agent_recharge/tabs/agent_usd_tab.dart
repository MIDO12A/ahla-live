/// ═══════════════════════════════════════════════════════════════
///  agent_usd_tab.dart — تبويب محفظة الدولار لوكيل الشحن
/// ═══════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/supabase_compat.dart';

import '../../agent_recharge_widgets.dart';
import 'package:zero/core/dtext.dart';

// ══════════════════════════════════════════════════════════════════════
//  Withdraw Request Bottom Sheet
// ══════════════════════════════════════════════════════════════════════
class _WithdrawRequestSheet extends StatefulWidget {
  const _WithdrawRequestSheet({required this.onSubmit});
  final Future<String?> Function(
      double amount, Map<String, String> bankDetails) onSubmit;
  @override
  State<_WithdrawRequestSheet> createState() => _WithdrawRequestSheetState();
}

class _WithdrawRequestSheetState extends State<_WithdrawRequestSheet> {
  final _amountCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _ibanCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _bankCtrl.dispose();
    _ibanCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amtStr = _amountCtrl.text.trim();
    final bank = _bankCtrl.text.trim();
    final iban = _ibanCtrl.text.trim();
    final name = _nameCtrl.text.trim();

    final amt = double.tryParse(amtStr);
    if (amt == null || amt < 10) {
      setState(() => _error = 'الحد الأدنى للسحب \$10');
      return;
    }
    if (bank.isEmpty || iban.isEmpty || name.isEmpty) {
      setState(() => _error = 'يرجى ملء جميع بيانات البنك');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onSubmit(
        amt, {'bank_name': bank, 'iban': iban, 'account_holder': name});
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
              color: Colors.black12, borderRadius: BorderRadius.circular(4)),
        ),
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.account_balance_rounded,
                color: Colors.green, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DText('طلب سحب دولار',
                  style: GoogleFonts.tajawal(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF1B5E20))),
              DText('سيتم مراجعة طلبك من قِبل الإدارة',
                  style: GoogleFonts.tajawal(
                      fontSize: 11, color: Colors.black45)),
            ]),
          ),
        ]),
        const SizedBox(height: 20),
        _buildField(
            ctrl: _amountCtrl,
            label: 'المبلغ المطلوب (USD)',
            hint: 'مثال: 100.00',
            prefix: '\$',
            keyboard: TextInputType.numberWithOptions(decimal: true)),
        const SizedBox(height: 12),
        _buildField(
            ctrl: _bankCtrl,
            label: 'اسم البنك',
            hint: 'مثال: Riyad Bank'),
        const SizedBox(height: 12),
        _buildField(
            ctrl: _ibanCtrl,
            label: 'رقم IBAN / الحساب',
            hint: 'SA03 8000 0000 6080 1016 7519'),
        const SizedBox(height: 12),
        _buildField(
            ctrl: _nameCtrl,
            label: 'اسم صاحب الحساب',
            hint: 'كما هو في البنك'),
        const SizedBox(height: 12),
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.red, size: 16),
              const SizedBox(width: 8),
              Expanded(
                  child: DText(_error!,
                      style: GoogleFonts.tajawal(
                          color: Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w700))),
            ]),
          ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                side: BorderSide(
                    color: Colors.black.withValues(alpha: 0.15)),
              ),
              child: DText('إلغاء',
                  style: GoogleFonts.tajawal(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.black54)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF43A047)]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: TextButton(
                onPressed: _busy ? null : _submit,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : DText('إرسال الطلب ✅',
                        style: GoogleFonts.tajawal(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _buildField({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    String prefix = '',
    TextInputType keyboard = TextInputType.text,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DText(label,
          style: GoogleFonts.tajawal(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black54)),
      const SizedBox(height: 5),
      Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
        ),
        child: TextField(
          controller: ctrl,
          keyboardType: keyboard,
          textDirection: TextDirection.ltr,
          style: GoogleFonts.tajawal(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1a1a2e)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                GoogleFonts.tajawal(fontSize: 13, color: Colors.black26),
            prefixText: prefix.isNotEmpty ? prefix : null,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════
//  USD Wallet Tab
// ══════════════════════════════════════════════════════════════════════
class AgentUsdWalletTab extends StatefulWidget {
  const AgentUsdWalletTab({super.key});
  @override
  State<AgentUsdWalletTab> createState() => _AgentUsdWalletTabState();
}

class _AgentUsdWalletTabState extends State<AgentUsdWalletTab> {
  static const _green = Color(0xFF1B5E20);
  static const _lGreen = Color(0xFF2E7D32);

  bool _loading = true;
  double _balance = 0.0;
  double _received = 0.0;
  double _withdrawn = 0.0;
  List<Map<String, dynamic>> _txns = [];
  List<Map<String, dynamic>> _requests = [];

  RealtimeChannel? _rt;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _rt?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res =
          await Supabase.instance.client.rpc('agent_get_usd_wallet');
      if (!mounted) return;
      if (res is Map) {
        final wallet = res['wallet'] as Map? ?? {};
        final txnList = res['transactions'] as List? ?? [];
        final reqList = res['withdrawal_requests'] as List? ?? [];
        setState(() {
          _balance =
              (wallet['usd_balance'] as num?)?.toDouble() ?? 0.0;
          _received =
              (wallet['total_received'] as num?)?.toDouble() ?? 0.0;
          _withdrawn =
              (wallet['total_withdrawn'] as num?)?.toDouble() ?? 0.0;
          _txns = txnList
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _requests = reqList
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('[UsdWalletTab] load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribeRealtime() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    _rt = Supabase.instance.client
        .channel('agent_usd_wallet_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'agent_usd_transactions',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'agent_id',
              value: uid),
          callback: (_) => _load(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'agent_usd_withdrawal_requests',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'agent_id',
              value: uid),
          callback: (_) => _load(),
        )
        .subscribe();
  }

  String _fmtUsd(double v) => '\$${v.toStringAsFixed(2)}';

  Color _statusColor(String s) {
    switch (s) {
      case 'approved':
        return Colors.green.shade600;
      case 'rejected':
        return Colors.red.shade600;
      default:
        return Colors.orange.shade700;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'approved':
        return '✓ مُوافق عليه';
      case 'rejected':
        return '✗ مرفوض';
      default:
        return '⏳ قيد المراجعة';
    }
  }

  String _txnLabel(String t) {
    switch (t) {
      case 'settlement_from_host':
        return 'تسوية من مضيف';
      case 'settlement_from_agency':
        return 'تسوية من وكالة';
      case 'withdrawal_approved':
        return 'سحب موافق عليه';
      case 'admin_credit':
        return 'إيداع إداري';
      default:
        return t;
    }
  }

  bool _isCredit(String t) => t != 'withdrawal_approved';

  String _fmtDate(dynamic ts) {
    if (ts == null) return '';
    final dt = ts is DateTime ? ts : DateTime.tryParse(ts.toString());
    if (dt == null) return '';
    final l = dt.toLocal();
    return '${l.year}/${l.month.toString().padLeft(2, '0')}/${l.day.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openWithdrawDialog() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WithdrawRequestSheet(
        onSubmit: (amt, bankDetails) async {
          try {
            final idempotencyKey =
                'wd_${DateTime.now().millisecondsSinceEpoch}_${(math.Random().nextDouble() * 1e9).toInt()}';
            final res = await Supabase.instance.client
                .rpc('agent_request_usd_withdrawal', params: {
              'p_amount_usd': amt,
              'p_bank_details': bankDetails,
              'p_idempotency_key': idempotencyKey,
            });
            if (res is Map && res['ok'] == true) return null;
            return (res as Map?)?['error']?.toString() ?? 'خطأ غير معروف';
          } catch (e) {
            debugPrint('[usd_withdraw] $e');
            return e.toString();
          }
        },
      ),
    );
    if (result == true) {
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: DText('✅ تم إرسال طلب السحب بنجاح',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF2E7D32)));
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF2E7D32),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── بطاقة الرصيد الرئيسية ──────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_green, _lGreen],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                    color: _lGreen.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              DText('💵 محفظة الدولار',
                  style: GoogleFonts.tajawal(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DText(_fmtUsd(_balance),
                  style: GoogleFonts.tajawal(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w900)),
              DText('رصيد متاح',
                  style: GoogleFonts.tajawal(
                      color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: AgentStatPill(
                        label: 'إجمالي مستلم',
                        value: _fmtUsd(_received),
                        icon: '⬇️')),
                const SizedBox(width: 10),
                Expanded(
                    child: AgentStatPill(
                        label: 'إجمالي مسحوب',
                        value: _fmtUsd(_withdrawn),
                        icon: '⬆️')),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      _balance >= 10 ? _openWithdrawDialog : null,
                  icon: const Icon(Icons.account_balance_rounded, size: 18),
                  label: DText(
                      _balance >= 10
                          ? 'طلب سحب'
                          : 'الحد الأدنى \$10',
                      style: GoogleFonts.tajawal(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _lGreen,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 20),

          // ── طلبات السحب ─────────────────────────────────────────
          if (_requests.isNotEmpty) ...[
            DText('طلبات السحب',
                style: GoogleFonts.tajawal(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _green)),
            const SizedBox(height: 10),
            ..._requests.map((r) => _buildRequestCard(r)),
            const SizedBox(height: 20),
          ],

          // ── سجل معاملات USD ──────────────────────────────────
          DText('سجل معاملات الدولار',
              style: GoogleFonts.tajawal(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _green)),
          const SizedBox(height: 10),
          if (_txns.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                  color: const Color(0xFFF1F8F2),
                  borderRadius: BorderRadius.circular(14)),
              child: Center(
                  child: DText('لا توجد معاملات بعد',
                      style: GoogleFonts.tajawal(
                          color: Colors.black38, fontSize: 14))),
            )
          else
            ..._txns.map((t) => _buildTxnCard(t)),
        ],
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> r) {
    final status = r['status']?.toString() ?? 'pending';
    final amountUsd = (r['amount_usd'] as num?)?.toDouble() ?? 0.0;
    final adminNote = r['admin_note']?.toString();
    final createdAt = r['created_at'];
    final bankDetails = r['bank_details'] as Map? ?? {};

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: _statusColor(status).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          DText(_fmtUsd(amountUsd),
              style: GoogleFonts.tajawal(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _lGreen)),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColor(status).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: _statusColor(status).withValues(alpha: 0.4)),
            ),
            child: DText(_statusLabel(status),
                style: GoogleFonts.tajawal(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _statusColor(status))),
          ),
        ]),
        if (bankDetails.isNotEmpty) ...[
          const SizedBox(height: 8),
          DText(
              'البيانات المصرفية: ${bankDetails['bank_name'] ?? bankDetails.toString()}',
              style: GoogleFonts.tajawal(
                  fontSize: 11, color: Colors.black45)),
        ],
        if (adminNote != null && adminNote.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.comment_outlined,
                  size: 14, color: Colors.orange),
              const SizedBox(width: 6),
              Expanded(
                  child: DText('ملاحظة الإدارة: $adminNote',
                      style: GoogleFonts.tajawal(
                          fontSize: 11,
                          color: Colors.orange.shade800))),
            ]),
          ),
        ],
        const SizedBox(height: 6),
        DText(_fmtDate(createdAt),
            style:
                GoogleFonts.tajawal(fontSize: 10, color: Colors.black38)),
      ]),
    );
  }

  Widget _buildTxnCard(Map<String, dynamic> t) {
    final txnType = t['txn_type']?.toString() ?? '';
    final amountUsd = (t['amount_usd'] as num?)?.toDouble() ?? 0.0;
    final note = t['note']?.toString();
    final senderType = t['sender_type']?.toString();
    final isCredit = _isCredit(txnType);
    final color =
        isCredit ? Colors.green.shade600 : Colors.red.shade500;
    final createdAt = t['created_at'];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
              isCredit
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              color: color,
              size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            DText(_txnLabel(txnType),
                style: GoogleFonts.tajawal(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87)),
            if (senderType != null)
              DText('المصدر: $senderType',
                  style: GoogleFonts.tajawal(
                      fontSize: 11, color: Colors.black38)),
            if (note != null && note.isNotEmpty)
              DText(note,
                  style: GoogleFonts.tajawal(
                      fontSize: 11, color: Colors.black45)),
            DText(_fmtDate(createdAt),
                style: GoogleFonts.tajawal(
                    fontSize: 10, color: Colors.black38)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            DText(isCredit ? '+' : '-',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 16)),
            DText(_fmtUsd(amountUsd),
                style: GoogleFonts.tajawal(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: color)),
          ]),
        ]),
      ]),
    );
  }
}
