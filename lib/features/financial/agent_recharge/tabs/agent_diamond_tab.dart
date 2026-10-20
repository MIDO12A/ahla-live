import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/supabase_compat.dart';
import '../../../../core/cache/encrypted_image_provider.dart';
import '../../../host_agency/data/agency_repository.dart';

import '../../agent_recharge_widgets.dart';

class AgentDiamondWalletTab extends StatefulWidget {
  const AgentDiamondWalletTab({super.key});
  @override
  State<AgentDiamondWalletTab> createState() => _AgentDiamondWalletTabState();
}

class _AgentDiamondWalletTabState extends State<AgentDiamondWalletTab> {
  static const _blue = Color(0xFF3F51B5);
  static const _dBlue = Color(0xFF1A237E);
  static const _cardBg = Color(0xFFF5F7FF);

  bool _loading = true;
  int _balance = 0;
  int _received = 0;
  int _withdrawn = 0;
  List<Map<String, dynamic>> _txns = [];
  List<Map<String, dynamic>> _pendingWithdrawals = [];
  bool _actionLoading = false;

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
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid != null) {
      try {
        final pending = await AgencyRepository.getAgentPendingWithdrawals(uid);
        if (mounted) setState(() => _pendingWithdrawals = pending);
      } catch (e) {
        debugPrint('[DiamondWalletTab] pending withdrawals error: $e');
      }
    }

    try {
      final res =
          await Supabase.instance.client.rpc('agent_get_diamond_wallet');
      if (!mounted) return;
      if (res is Map) {
        final wallet = res['wallet'] as Map? ?? {};
        final txns = (res['transactions'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        setState(() {
          _balance = (wallet['diamond_balance'] as num?)?.toInt() ?? 0;
          _received = (wallet['total_received'] as num?)?.toInt() ?? 0;
          _withdrawn = (wallet['total_withdrawn'] as num?)?.toInt() ?? 0;
          _txns = txns;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('[DiamondWalletTab] load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleWithdrawalAction(String requestId, bool approve) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    if (!approve) {
      final reason = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController(text: 'الرصيد غير متطابق');
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            title: const Text('سبب الرفض', style: TextStyle(color: Colors.white, fontSize: 16)),
            content: TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'اكتب سبب رفض طلب السحب...',
                hintStyle: TextStyle(color: Colors.white30),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('تأكيد الرفض'),
              ),
            ],
          );
        },
      );
      if (reason == null) return;

      setState(() => _actionLoading = true);
      final res = await AgencyRepository.handleAgentWithdrawalAction(
        requestId: requestId,
        agentUid: uid,
        approve: false,
        rejectReason: reason,
      );
      setState(() => _actionLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? '')));
        _load();
      }
      return;
    }

    // تأكيد الموافقة
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('تأكيد قبول طلب السحب', style: TextStyle(color: Colors.white)),
        content: const Text(
          'هل أنت متأكد من قبول الطلب؟ سيتم خصم الألماس من المضيف وتحويله إلى محفظتك بنجاح.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5A0), foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('موافقة وقبول', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _actionLoading = true);
    final res = await AgencyRepository.handleAgentWithdrawalAction(
      requestId: requestId,
      agentUid: uid,
      approve: true,
    );
    setState(() => _actionLoading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? '')));
      _load();
    }
  }

  Future<void> _showExchangeBottomSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ExchangeBottomSheetContent(
        currentBalance: _balance,
        onExchanged: () {
          _load();
        },
      ),
    );
  }

  void _subscribeRealtime() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    _rt = Supabase.instance.client
        .channel('agent_diamond_wallet_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'agent_diamond_transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'agent_id',
            value: uid,
          ),
          callback: (_) => _load(),
        )
        .subscribe();
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}م';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}ك';
    return '$n';
  }

  String _txnLabel(String txnType) {
    switch (txnType) {
      case 'received_from_host':
        return 'استلام من مضيف';
      case 'received_from_agency':
        return 'استلام من وكالة';
      case 'admin_withdrawal':
        return 'سحب إداري';
      case 'exchange_to_coins':
        return 'صرف أرباح إلى كوينز الوكالة';
      default:
        return txnType;
    }
  }

  Color _txnColor(String txnType) {
    if (txnType == 'admin_withdrawal') return Colors.red.shade400;
    if (txnType == 'exchange_to_coins') return const Color(0xFFFF9800);
    return Colors.green.shade600;
  }

  IconData _txnIcon(String txnType) {
    if (txnType == 'admin_withdrawal') return Icons.arrow_upward_rounded;
    if (txnType == 'exchange_to_coins') return Icons.swap_horiz_rounded;
    return Icons.arrow_downward_rounded;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── بطاقة الرصيد الرئيسية ──────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_dBlue, _blue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: _blue.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('💎 محفظة الألماس',
                    style: GoogleFonts.tajawal(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(_fmt(_balance),
                    style: GoogleFonts.tajawal(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w900)),
                Text('ألماس متاح',
                    style: GoogleFonts.tajawal(
                        color: Colors.white60, fontSize: 13)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                      child: AgentStatPill(
                          label: 'إجمالي مستلم',
                          value: _fmt(_received),
                          icon: '⬇️')),
                  const SizedBox(width: 10),
                  Expanded(
                      child: AgentStatPill(
                          label: 'إجمالي مسحوب',
                          value: _fmt(_withdrawn),
                          icon: '⬆️')),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _showExchangeBottomSheet,
                    icon: const Icon(Icons.currency_exchange_rounded, color: Colors.black, size: 22),
                    label: Text(
                      'صرف الألماس إلى كوينز الوكالة 🔄',
                      style: GoogleFonts.tajawal(
                        color: Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      elevation: 4,
                      shadowColor: Colors.black45,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    '⚡ يتم تحويل الألماس فوراً إلى كوينز في محفظة وكالتك لشحن المستخدمين',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.tajawal(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── قسم طلبات السحب المعلقة الواردة من المضيفين ──────────
          if (_pendingWithdrawals.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.mark_email_unread_rounded, color: Color(0xFFFFB800), size: 20),
                const SizedBox(width: 8),
                Text('طلبات سحب الألماس الواردة',
                    style: GoogleFonts.tajawal(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1A1A2E))),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_pendingWithdrawals.length} جديد',
                    style: GoogleFonts.tajawal(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ..._pendingWithdrawals.map((req) => _buildPendingCard(req)),
            const SizedBox(height: 14),
          ],

          Text('سجل العمليات',
              style: GoogleFonts.tajawal(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _dBlue)),
          const SizedBox(height: 10),
          if (_txns.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                  color: _cardBg, borderRadius: BorderRadius.circular(14)),
              child: Center(
                  child: Text('لا توجد عمليات بعد',
                      style: GoogleFonts.tajawal(
                          color: Colors.black38, fontSize: 14))),
            )
          else
            ..._txns.map((t) => _buildTxnRow(t)),
        ],
      ),
    );
  }

  Widget _buildPendingCard(Map<String, dynamic> req) {
    final hostName = req['host_name'] ?? 'مضيف';
    final hostKid = req['host_custom_id'] ?? '';
    final hostAvatar = req['host_avatar']?.toString() ?? '';
    final diamonds = (req['diamonds'] as num?)?.toInt() ?? 0;
    final requestId = req['id']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFB800).withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB800).withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFFB800), width: 1.5),
                  image: hostAvatar.isNotEmpty
                      ? DecorationImage(image: EncryptedImageProvider(hostAvatar), fit: BoxFit.cover)
                      : null,
                ),
                child: hostAvatar.isEmpty ? const Icon(Icons.person, color: Color(0xFFFFB800)) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hostName, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 14)),
                    if (hostKid.isNotEmpty)
                      Text('ID: #$hostKid', style: GoogleFonts.tajawal(color: Colors.black54, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF3F51B5).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF3F51B5).withValues(alpha: 0.3)),
                ),
                child: Text(
                  '💎 $diamonds ماسة',
                  style: GoogleFonts.tajawal(color: const Color(0xFF1A237E), fontWeight: FontWeight.w900, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _actionLoading ? null : () => _handleWithdrawalAction(requestId, false),
                  icon: const Icon(Icons.close_rounded, size: 16, color: Colors.redAccent),
                  label: Text('رفض', style: GoogleFonts.tajawal(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _actionLoading ? null : () => _handleWithdrawalAction(requestId, true),
                  icon: const Icon(Icons.check_rounded, size: 16, color: Colors.black),
                  label: Text('موافقة وقبول', style: GoogleFonts.tajawal(color: Colors.black, fontWeight: FontWeight.w900)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5A0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTxnRow(Map<String, dynamic> t) {
    final txnType = t['txn_type']?.toString() ?? '';
    final amount = (t['diamonds_amount'] as num?)?.toInt() ?? 0;
    final name = t['sender_name']?.toString() ??
        (txnType == 'exchange_to_coins' ? 'صرف أرباح الوكالة' : 'الإدارة');
    final avatar = t['sender_avatar']?.toString();
    final kayanId = t['sender_kayan_id']?.toString();
    final createdAt =
        DateTime.tryParse(t['created_at']?.toString() ?? '') ?? DateTime.now();
    final isIncoming =
        txnType != 'admin_withdrawal' && txnType != 'exchange_to_coins';

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
        Stack(
          clipBehavior: Clip.none,
          children: [
            AgentAvatar(url: avatar, size: 46),
            Positioned(
              bottom: -2,
              right: -4,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: isIncoming
                      ? Colors.green.shade500
                      : Colors.red.shade400,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(_txnIcon(txnType), size: 10, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: GoogleFonts.tajawal(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Colors.black87)),
              if (kayanId != null)
                Text('ID: $kayanId',
                    style: GoogleFonts.tajawal(
                        fontSize: 12, color: Colors.black45)),
              Text(_txnLabel(txnType),
                  style: GoogleFonts.tajawal(
                      fontSize: 12,
                      color: _txnColor(txnType),
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(isIncoming ? '+' : '-',
                style: TextStyle(
                    color: _txnColor(txnType),
                    fontWeight: FontWeight.w900,
                    fontSize: 16)),
            Text(_fmt(amount),
                style: GoogleFonts.tajawal(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: _txnColor(txnType))),
            const SizedBox(width: 4),
            const Text('💎', style: TextStyle(fontSize: 14)),
          ]),
          Text(
            '${createdAt.year}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.day.toString().padLeft(2, '0')} '
            '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
            style:
                GoogleFonts.tajawal(fontSize: 11, color: Colors.black38),
          ),
        ]),
      ]),
    );
  }
}

// ── نافذة باقات صرف الألماس إلى كوينز الوكالة ──────────────────────────────
class _ExchangeBottomSheetContent extends StatefulWidget {
  final int currentBalance;
  final VoidCallback onExchanged;

  const _ExchangeBottomSheetContent({
    required this.currentBalance,
    required this.onExchanged,
  });

  @override
  State<_ExchangeBottomSheetContent> createState() =>
      _ExchangeBottomSheetContentState();
}

class _ExchangeBottomSheetContentState
    extends State<_ExchangeBottomSheetContent> {
  bool _loading = true;
  bool _exchanging = false;
  List<Map<String, dynamic>> _tiers = [];
  int _agencyCoins = 0;

  @override
  void initState() {
    super.initState();
    _fetchTiersAndCoins();
  }

  Future<void> _fetchTiersAndCoins() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    try {
      // 1. Fetch active tiers
      final res = await Supabase.instance.client
          .from('recharge_agency_exchange_tiers')
          .select('*')
          .eq('is_active', true)
          .order('sort_order', ascending: true);

      List<Map<String, dynamic>> list = [];
      if (res is List && res.isNotEmpty) {
        list = (res as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }

      // Default fallback if no tiers configured
      if (list.isEmpty) {
        list = [
          {
            'id': 'default_1',
            'usd_amount': 1.0,
            'diamonds_cost': 15000,
            'coins_received': 1000,
            'title': 'باقة 1 دولار',
            'badge_text': 'أساسي',
          },
          {
            'id': 'default_2',
            'usd_amount': 2.0,
            'diamonds_cost': 30000,
            'coins_received': 30000,
            'title': 'باقة 2 دولار',
            'badge_text': 'شائع',
          },
          {
            'id': 'default_5',
            'usd_amount': 5.0,
            'diamonds_cost': 75000,
            'coins_received': 80000,
            'title': 'باقة 5 دولار',
            'badge_text': 'توفير',
          },
          {
            'id': 'default_10',
            'usd_amount': 10.0,
            'diamonds_cost': 150000,
            'coins_received': 165000,
            'title': 'باقة 10 دولار',
            'badge_text': 'أفضل قيمة',
          },
          {
            'id': 'default_20',
            'usd_amount': 20.0,
            'diamonds_cost': 300000,
            'coins_received': 340000,
            'title': 'باقة 20 دولار',
            'badge_text': 'VIP',
          },
        ];
      }

      // 2. Fetch current agency coins
      int coins = 0;
      if (uid != null) {
        try {
          final aw = await Supabase.instance.client
              .from('agency_wallets')
              .select('gold_balance')
              .eq('agency_profile_id', uid)
              .maybeSingle();
          if (aw != null) {
            coins = (aw['gold_balance'] as num?)?.toInt() ?? 0;
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _tiers = list;
          _agencyCoins = coins;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[ExchangeBottomSheet] error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleExchange(Map<String, dynamic> tier) async {
    final diamondsCost = (tier['diamonds_cost'] as num?)?.toInt() ?? 0;
    final coinsReceived = (tier['coins_received'] as num?)?.toInt() ?? 0;
    final tierId = tier['id']?.toString() ?? '';

    if (widget.currentBalance < diamondsCost) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'عذراً، رصيد الألماس المتاح لديك لا يكفي ($diamondsCost 💎 مطلوب)',
            style: GoogleFonts.tajawal(),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(
          'تأكيد صرف الألماس 🔄',
          style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هل أنت متأكد من صرف $diamondsCost ماسة واستلام $coinsReceived كوينز في محفظة وكالة الشحن؟',
              style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('💎 المطلوب خصمه:', style: GoogleFonts.tajawal(color: Colors.cyanAccent, fontSize: 12)),
                  Text('$diamondsCost 💎', style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('🪙 الكوينز المستلمة:', style: GoogleFonts.tajawal(color: Colors.amber, fontSize: 12)),
                  Text('$coinsReceived 🪙', style: GoogleFonts.tajawal(color: Colors.amber, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء', style: GoogleFonts.tajawal(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('تأكيد الصرف الآن', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _exchanging = true);

    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) throw Exception('المستخدم غير مسجل الدخول');

      // Try calling RPC first
      bool success = false;
      String message = '';
      try {
        final rpcRes = await Supabase.instance.client.rpc(
          'agent_exchange_diamonds_to_coins',
          params: {'p_tier_id': tierId},
        );
        if (rpcRes is Map) {
          success = rpcRes['success'] == true;
          message = rpcRes['message']?.toString() ?? '';
        }
      } catch (rpcErr) {
        debugPrint('[ExchangeBottomSheet] RPC fallback: $rpcErr');
      }

      // Fallback direct execution if RPC failed or not configured yet
      if (!success) {
        final aw = await Supabase.instance.client
            .from('agency_wallets')
            .select('diamond_balance, gold_balance, total_withdrawn')
            .eq('agency_profile_id', uid)
            .maybeSingle();

        if (aw != null) {
          final curDia = (aw['diamond_balance'] as num?)?.toInt() ?? 0;
          final curGold = (aw['gold_balance'] as num?)?.toInt() ?? 0;
          final curWithdrawn = (aw['total_withdrawn'] as num?)?.toInt() ?? 0;

          if (curDia < diamondsCost) {
            throw Exception('رصيد الألماس لا يكفي');
          }

          final newDia = curDia - diamondsCost;
          final newGold = curGold + coinsReceived;
          final newWithdrawn = curWithdrawn + diamondsCost;

          await Supabase.instance.client.from('agency_wallets').update({
            'diamond_balance': newDia,
            'gold_balance': newGold,
            'total_withdrawn': newWithdrawn,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('agency_profile_id', uid);

          try {
            await Supabase.instance.client
                .from('agent_diamond_transactions')
                .insert({
              'agent_id': uid,
              'sender_id': uid,
              'sender_name': 'صرف أرباح الوكالة',
              'txn_type': 'exchange_to_coins',
              'diamonds_amount': diamondsCost,
              'coins_amount': coinsReceived,
              'usd_amount': tier['usd_amount'] ?? 0,
              'balance_after': newDia,
              'notes': 'صرف $diamondsCost ماسة إلى $coinsReceived كوينز للوكالة',
              'created_at': DateTime.now().toIso8601String(),
            });
          } catch (_) {}

          success = true;
          message = 'تم صرف $coinsReceived كوينز وإضافتها لمحفظة الوكالة بنجاح! 🪙';
        } else {
          throw Exception('محفظة الوكالة غير موجودة');
        }
      }

      if (mounted) {
        setState(() => _exchanging = false);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message.isNotEmpty ? message : 'تم صرف الكوينز بنجاح! 🪙',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
            ),
            backgroundColor: const Color(0xFF00C853),
          ),
        );
        widget.onExchanged();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _exchanging = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشلت العملية: $e', style: GoogleFonts.tajawal()),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF12121A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            children: [
              const Icon(Icons.currency_exchange_rounded, color: Color(0xFFFFD700), size: 24),
              const SizedBox(width: 8),
              Text(
                'صرف الألماس إلى كوينز الوكالة',
                style: GoogleFonts.tajawal(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          // Balance Bar
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E2235), Color(0xFF151726)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الألماس المتاح للصرف:', style: GoogleFonts.tajawal(color: Colors.white54, fontSize: 11)),
                      Text('${widget.currentBalance.toString()} 💎',
                          style: GoogleFonts.tajawal(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Container(width: 1, height: 30, color: Colors.white12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('رصيد كوينز الوكالة:', style: GoogleFonts.tajawal(color: Colors.white54, fontSize: 11)),
                      Text('${_agencyCoins.toString()} 🪙',
                          style: GoogleFonts.tajawal(color: const Color(0xFFFFD700), fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_exchanging)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  CircularProgressIndicator(color: Color(0xFFFFD700)),
                  SizedBox(height: 10),
                  Text('جاري إتمام عملية الصرف وتحديث المحفظة...', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            )
          else if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFFFFD700))))
          else
            Expanded(
              child: ListView.separated(
                itemCount: _tiers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final t = _tiers[i];
                  final cost = (t['diamonds_cost'] as num?)?.toInt() ?? 0;
                  final coins = (t['coins_received'] as num?)?.toInt() ?? 0;
                  final title = t['title']?.toString() ?? '';
                  final badge = t['badge_text']?.toString();
                  final usd = t['usd_amount'] != null ? '\$${t['usd_amount']}' : '';
                  final canAfford = widget.currentBalance >= cost;

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1D2A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: canAfford ? const Color(0xFFFFD700).withValues(alpha: 0.3) : Colors.white10,
                      ),
                    ),
                    child: Row(
                      children: [
                        // USD pill
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            usd,
                            style: GoogleFonts.tajawal(
                              color: const Color(0xFFFFD700),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    title,
                                    style: GoogleFonts.tajawal(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (badge != null && badge.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        badge,
                                        style: GoogleFonts.tajawal(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    'خصم: $cost 💎',
                                    style: GoogleFonts.tajawal(color: Colors.cyanAccent, fontSize: 12),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward_rounded, size: 12, color: Colors.white38),
                                  const SizedBox(width: 8),
                                  Text(
                                    'استلام: $coins 🪙',
                                    style: GoogleFonts.tajawal(color: const Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Action button
                        ElevatedButton(
                          onPressed: canAfford ? () => _handleExchange(t) : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: canAfford ? const Color(0xFFFFD700) : Colors.white12,
                            foregroundColor: canAfford ? Colors.black : Colors.white38,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(
                            canAfford ? 'صرف' : 'غير كافٍ',
                            style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

