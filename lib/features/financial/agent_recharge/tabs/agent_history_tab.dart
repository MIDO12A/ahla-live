import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/supabase_compat.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../agent_recharge_widgets.dart';

// ══════════════════════════════════════════════════════════════════════
//  History Tab
// ══════════════════════════════════════════════════════════════════════
class AgentHistoryTab extends StatefulWidget {
  const AgentHistoryTab({super.key});
  @override
  State<AgentHistoryTab> createState() => _AgentHistoryTabState();
}

class _AgentHistoryTabState extends State<AgentHistoryTab> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client
          .rpc('agent_recharge_history', params: {'p_limit': 200});
      if (!mounted) return;
      List<Map<String, dynamic>> rows = const [];
      if (res is List) {
        rows = List<Map<String, dynamic>>.from(
            res.map((e) => Map<String, dynamic>.from(e as Map)));
      }
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[history_tab] $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtDate(dynamic ts) {
    if (ts == null) return '';
    final dt = ts is DateTime ? ts : DateTime.tryParse(ts.toString());
    if (dt == null) return '';
    final l = dt.toLocal();
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
    ];
    return '${l.day} ${months[l.month - 1]} ${l.year}  '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFFFB800)));
    }
    if (_rows.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('📋', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 16),
          Text('لا توجد عمليات بعد',
              style: GoogleFonts.tajawal(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.black45)),
        ]),
      );
    }
    return RefreshIndicator(
      color: KayanBrandColors.logoPrimary,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: _rows.length,
        itemBuilder: (_, i) {
          final r = _rows[i];
          final kid = (r['target_custom_id'] ?? r['recipient_kayan_id'] ?? r['target_uid'])?.toString();
          final name = (r['recipient_display_name'] ?? (kid != null ? 'معرّف #$kid' : 'مستخدم')).toString();
          final url = r['recipient_avatar_url']?.toString();
          final gold = ((r['amount_coins'] ?? r['gold_amount']) as num?)?.toInt() ?? 0;
          final ts = r['created_at'];
          final status = r['status']?.toString() ?? 'completed';
          final isWithdraw = r['type'] == 'withdraw';
          final badgeColor = isWithdraw ? Colors.redAccent : KayanBrandColors.logoPrimary;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10),
              ],
            ),
            child: Row(children: [
              AgentAvatar(url: url, size: 50),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(name,
                              style: GoogleFonts.tajawal(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1a1a2e))),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isWithdraw ? 'سحب 📤' : 'شحن 🚀',
                              style: GoogleFonts.tajawal(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: badgeColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (kid != null && kid.isNotEmpty)
                        Text('# $kid',
                            style: GoogleFonts.tajawal(
                                fontSize: 11,
                                color: badgeColor,
                                fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(_fmtDate(ts),
                          style: GoogleFonts.tajawal(
                              fontSize: 11, color: Colors.black38)),
                    ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: badgeColor.withValues(alpha: 0.3)),
                  ),
                  child: Text('${isWithdraw ? "-" : "+"} 🪙 $gold',
                      style: GoogleFonts.tajawal(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: badgeColor)),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: status == 'completed'
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status == 'completed'
                        ? (isWithdraw ? '✓ تم السحب' : '✓ تم الشحن')
                        : status == 'refunded'
                            ? '↩ مُسترد'
                            : status,
                    style: GoogleFonts.tajawal(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: status == 'completed'
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                ),
              ]),
            ]),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  Edit Quick Amounts Bottom Sheet
// ══════════════════════════════════════════════════════════════════════
class AgentEditQuickAmountsSheet extends StatefulWidget {
  const AgentEditQuickAmountsSheet({super.key, required this.current});
  final List<int> current;
  @override
  State<AgentEditQuickAmountsSheet> createState() =>
      _AgentEditQuickAmountsSheetState();
}

class _AgentEditQuickAmountsSheetState
    extends State<AgentEditQuickAmountsSheet> {
  late List<TextEditingController> _ctrls;
  String? _error;

  @override
  void initState() {
    super.initState();
    final base = List<int>.from(widget.current);
    if (base.length < 4) {
      while (base.length < 4) {
        base.add(0);
      }
    }
    _ctrls = base
        .map((v) => TextEditingController(text: v > 0 ? v.toString() : ''))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addField() {
    if (_ctrls.length >= 6) {
      return;
    }
    setState(() => _ctrls.add(TextEditingController()));
  }

  void _removeField(int idx) {
    if (_ctrls.length <= 1) {
      return;
    }
    setState(() {
      _ctrls[idx].dispose();
      _ctrls.removeAt(idx);
    });
  }

  void _save() {
    final amounts = <int>[];
    for (final c in _ctrls) {
      final raw = c.text.trim();
      if (raw.isEmpty) {
        continue;
      }
      final n = int.tryParse(raw);
      if (n == null || n < 1 || n > 1000000) {
        setState(
            () => _error = 'كل مبلغ يجب أن يكون بين 1 و 1,000,000');
        return;
      }
      amounts.add(n);
    }
    if (amounts.isEmpty) {
      setState(() => _error = 'أدخل مبلغاً واحداً على الأقل');
      return;
    }
    final unique = amounts.toSet().toList();
    Navigator.of(context).pop(unique);
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
              color: KayanBrandColors.logoPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.tune_rounded,
                color: KayanBrandColors.logoPrimary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('تخصيص المبالغ السريعة',
                  style: GoogleFonts.tajawal(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF1a1a2e))),
              Text('تظهر كأزرار مباشرة في صفحة الشحن',
                  style: GoogleFonts.tajawal(
                      fontSize: 11, color: Colors.black45)),
            ]),
          ),
          if (_ctrls.length < 6)
            GestureDetector(
              onTap: _addField,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.add_rounded, size: 16, color: Colors.green),
                  const SizedBox(width: 3),
                  Text('إضافة',
                      style: GoogleFonts.tajawal(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.green)),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 20),
        ...List.generate(_ctrls.length, (i) => _buildAmountRow(i)),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded,
                  size: 16, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(_error!,
                      style: GoogleFonts.tajawal(
                          fontSize: 12,
                          color: Colors.red,
                          fontWeight: FontWeight.w700))),
            ]),
          ),
        ],
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                side: BorderSide(
                    color: Colors.black.withValues(alpha: 0.15)),
              ),
              child: Text('إلغاء',
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
                gradient: LinearGradient(
                    colors: [
                      KayanBrandColors.logoPrimary,
                      const Color(0xFFFF6B00)
                    ]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: KayanBrandColors.logoPrimary
                          .withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: TextButton(
                onPressed: _save,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('حفظ ✅',
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

  Widget _buildAmountRow(int idx) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFFFB800).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text('${idx + 1}',
                style: GoogleFonts.tajawal(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFFFFB800))),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Colors.black.withValues(alpha: 0.07)),
            ),
            child: TextField(
              controller: _ctrls[idx],
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textDirection: TextDirection.rtl,
              onChanged: (_) => setState(() => _error = null),
              style: GoogleFonts.tajawal(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1a1a2e)),
              decoration: InputDecoration(
                hintText: 'مثال: 1000',
                hintStyle:
                    GoogleFonts.tajawal(fontSize: 14, color: Colors.black26),
                prefixText: '🪙 ',
                prefixStyle: const TextStyle(fontSize: 16),
                suffixText: 'كوين',
                suffixStyle:
                    GoogleFonts.tajawal(fontSize: 12, color: Colors.black38),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
            ),
          ),
        ),
        if (_ctrls.length > 1) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _removeField(idx),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.remove_rounded,
                  size: 18, color: Colors.red),
            ),
          ),
        ],
      ]),
    );
  }
}
