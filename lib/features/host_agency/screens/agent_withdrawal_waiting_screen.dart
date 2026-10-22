import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/supabase_compat.dart';
import '../../../core/cache/encrypted_image_provider.dart';
import '../../../providers/user_provider.dart';

class AgentWithdrawalWaitingScreen extends StatefulWidget {
  final String requestId;
  final int diamonds;
  final double usdAmount;
  final String agentName;
  final String agentId;
  final String agentAvatar;
  final String agentKayanId;
  final String agencyName;
  final VoidCallback? onSuccess;

  const AgentWithdrawalWaitingScreen({
    super.key,
    required this.requestId,
    required this.diamonds,
    required this.usdAmount,
    required this.agentName,
    required this.agentId,
    this.agentAvatar = '',
    this.agentKayanId = '',
    this.agencyName = '',
    this.onSuccess,
  });

  @override
  State<AgentWithdrawalWaitingScreen> createState() =>
      _AgentWithdrawalWaitingScreenState();
}

class _AgentWithdrawalWaitingScreenState
    extends State<AgentWithdrawalWaitingScreen>
    with SingleTickerProviderStateMixin {
  static const _teal = Color(0xFF00B5B3);
  static const _dark = Color(0xFF0D0D1A);
  static const _card = Color(0xFF161626);

  late final AnimationController _pulseCtrl;
  late final Animation<double> _scaleAnim;

  String _status = 'pending'; // 'pending' | 'approved' | 'rejected' | 'cancelled'
  String? _rejectionReason;
  Timer? _pollTimer;
  RealtimeChannel? _rtChannel;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _scaleAnim = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _startListening();
    _checkStatus();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _pollTimer?.cancel();
    _rtChannel?.unsubscribe();
    super.dispose();
  }

  void _startListening() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (mounted && _status == 'pending') {
        _checkStatus();
      }
    });

    try {
      _rtChannel = Supabase.instance.client
          .channel('agent_wdr_${widget.requestId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'agent_withdrawal_requests',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: widget.requestId,
            ),
            callback: (payload) {
              final newRow = payload.newRecord;
              final st = newRow['status']?.toString();
              if (st != null && mounted) {
                _applyStatusUpdate(
                  status: st,
                  rejectionReason: newRow['rejection_reason']?.toString(),
                );
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('[AgentWithdrawalWaitingScreen] rt subscribe error: $e');
    }
  }

  Future<void> _checkStatus() async {
    try {
      final row = await Supabase.instance.client
          .from('agent_withdrawal_requests')
          .select('*')
          .eq('id', widget.requestId)
          .maybeSingle();

      if (row != null && mounted) {
        final st = row['status']?.toString() ?? 'pending';
        _applyStatusUpdate(
          status: st,
          rejectionReason: row['rejection_reason']?.toString(),
        );
      }
    } catch (e) {
      debugPrint('[AgentWithdrawalWaitingScreen] _checkStatus error: $e');
    }
  }

  void _applyStatusUpdate({required String status, String? rejectionReason}) {
    if (_status == status) return;

    if (status == 'approved') {
      _pollTimer?.cancel();
      _rtChannel?.unsubscribe();
      HapticFeedback.heavyImpact();

      try {
        Provider.of<UserProvider>(context, listen: false)
            .deductDiamondsLocally(widget.diamonds);
      } catch (_) {}

      try {
        widget.onSuccess?.call();
      } catch (_) {}

      setState(() {
        _status = 'approved';
        _rejectionReason = null;
      });
    } else if (status == 'rejected') {
      _pollTimer?.cancel();
      _rtChannel?.unsubscribe();
      HapticFeedback.mediumImpact();

      setState(() {
        _status = 'rejected';
        _rejectionReason = rejectionReason ?? 'اعتذر وكيل الشحن عن قبول الطلب في الوقت الحالي';
      });
    } else if (status == 'cancelled') {
      _pollTimer?.cancel();
      _rtChannel?.unsubscribe();
      setState(() => _status = 'cancelled');
    }
  }

  Future<void> _cancelRequest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('إلغاء طلب الصرف',
            style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
        content: const Text(
          'هل تريد بالتأكيد إلغاء طلب السحب الموجه لوكيل الشحن؟\nلن يتم خصم أو تحويل أي رصيد.',
          style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع', style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، إلغاء الطلب',
                style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _cancelling = true);
    try {
      await Supabase.instance.client
          .from('agent_withdrawal_requests')
          .update({
            'status': 'cancelled',
            'reviewed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.requestId);

      _applyStatusUpdate(status: 'cancelled');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إلغاء طلب الصرف بنجاح', style: TextStyle(fontFamily: 'Tajawal')),
            backgroundColor: Colors.grey,
          ),
        );
        Navigator.pop(context, false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إلغاء الطلب: $e', style: const TextStyle(fontFamily: 'Tajawal')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_status == 'pending') {
          return await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E1E2E),
                  title: const Text('مغادرة شاشة الانتظار؟',
                      style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
                  content: const Text(
                    'الطلب لا يزال قيد الانتظار لموافقة الوكيل في الخلفية.\nيمكنك الرجوع في أي وقت لمتابعة حالته.',
                    style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', height: 1.4),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('البقاء هنا',
                          style: TextStyle(color: _teal, fontFamily: 'Tajawal')),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white12),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('خروج',
                          style: TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
                    ),
                  ],
                ),
              ) ??
              false;
        }
        return true;
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: _dark,
          appBar: AppBar(
            backgroundColor: _card,
            elevation: 0,
            title: const Text(
              'متابعة طلب صرف الراتب',
              style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 16, fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 20),
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 10),
                _buildStatusVisual(),
                const SizedBox(height: 28),
                _buildRequestDetailsCard(),
                const SizedBox(height: 24),
                _buildActionButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusVisual() {
    switch (_status) {
      case 'approved':
        return Column(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00E5A0).withOpacity(0.15),
                border: Border.all(color: const Color(0xFF00E5A0), width: 3),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF00E5A0).withOpacity(0.4), blurRadius: 24),
                ],
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF00E5A0), size: 54),
            ),
            const SizedBox(height: 18),
            const Text(
              '🎉 تمت موافقة الوكيل بنجاح!',
              style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'تم سحب الراتب، وتصفير التارجت والخصم من الرصيد المحقق، وإيداع الرصيد في محفظة وكالة الشحن بنجاح.',
              style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        );

      case 'rejected':
        return Column(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.redAccent.withOpacity(0.15),
                border: Border.all(color: Colors.redAccent, width: 3),
                boxShadow: [
                  BoxShadow(color: Colors.redAccent.withOpacity(0.35), blurRadius: 20),
                ],
              ),
              child: const Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 54),
            ),
            const SizedBox(height: 18),
            const Text(
              'تم رفض طلب الصرف ❌',
              style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _rejectionReason ?? 'اعتذر وكيل الشحن عن قبول الطلب. لم يتم خصم أي رصيد من حسابك.',
              style: const TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        );

      case 'cancelled':
        return Column(
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white10,
                border: Border.all(color: Colors.white30, width: 2),
              ),
              child: const Icon(Icons.remove_circle_outline_rounded, color: Colors.white54, size: 48),
            ),
            const SizedBox(height: 16),
            const Text(
              'تم إلغاء الطلب',
              style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'تم إلغاء طلب السحب بنجاح ولم يتم تحويل أي رصيد.',
              style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal', fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        );

      case 'pending':
      default:
        return Column(
          children: [
            ScaleTransition(
              scale: _scaleAnim,
              child: Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _teal.withOpacity(0.12),
                  border: Border.all(color: _teal, width: 2.5),
                  boxShadow: [
                    BoxShadow(color: _teal.withOpacity(0.3), blurRadius: 24, spreadRadius: 2),
                  ],
                ),
                child: const Center(
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      color: _teal,
                      strokeWidth: 3.5,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'في انتظار موافقة الوكيل ⏳',
              style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'تم إرسال طلب الصرف وإشعار وكيل الشحن فوراً.\nيرجى الانتظار، سيتم الخصم وتصفير التارجت بمجرد قبول الوكيل.',
              style: TextStyle(color: Colors.white60, fontFamily: 'Tajawal', fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        );
    }
  }

  Widget _buildRequestDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _status == 'approved'
              ? const Color(0xFF00E5A0).withOpacity(0.4)
              : _status == 'rejected'
                  ? Colors.redAccent.withOpacity(0.4)
                  : Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'تفاصيل طلب الصرف',
                style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 14, fontWeight: FontWeight.bold),
              ),
              _buildStatusBadge(),
            ],
          ),
          const Divider(color: Colors.white10, height: 24),
          _buildInfoRow('كمية الألماس:', '${widget.diamonds} 💎', valColor: const Color(0xFFFFD700)),
          if (widget.usdAmount > 0)
            _buildInfoRow('القيمة بالدولار:', '\$${widget.usdAmount.toStringAsFixed(2)}', valColor: const Color(0xFF00E5A0)),
          const SizedBox(height: 12),
          const Divider(color: Colors.white10, height: 16),
          const SizedBox(height: 6),
          // بيانات الوكيل
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white12,
                backgroundImage: widget.agentAvatar.isNotEmpty
                    ? EncryptedImageProvider(widget.agentAvatar)
                    : null,
                child: widget.agentAvatar.isEmpty
                    ? const Icon(Icons.person, color: Colors.white54, size: 20)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.agentName,
                      style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 13, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'وكيل شحن معتمد' + (widget.agentKayanId.isNotEmpty ? ' (#${widget.agentKayanId})' : ''),
                      style: const TextStyle(color: _teal, fontFamily: 'Tajawal', fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'رقم الطلب: ${widget.requestId}',
            style: const TextStyle(color: Colors.white30, fontFamily: 'monospace', fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    Color bg;
    Color fg;
    String text;

    switch (_status) {
      case 'approved':
        bg = const Color(0xFF00E5A0).withOpacity(0.15);
        fg = const Color(0xFF00E5A0);
        text = 'مقبول ومكتمل ✅';
        break;
      case 'rejected':
        bg = Colors.redAccent.withOpacity(0.15);
        fg = Colors.redAccent;
        text = 'مرفوض ❌';
        break;
      case 'cancelled':
        bg = Colors.white10;
        fg = Colors.white60;
        text = 'ملغي';
        break;
      case 'pending':
      default:
        bg = Colors.amber.withOpacity(0.15);
        fg = Colors.amber;
        text = 'قيد الانتظار ⏳';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withOpacity(0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontFamily: 'Tajawal', fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontFamily: 'Tajawal', fontSize: 13)),
          Text(
            value,
            style: TextStyle(color: valColor ?? Colors.white, fontFamily: 'Tajawal', fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_status == 'approved') {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5A0),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text(
            'تم وتحديث الرصيد والتارجت ✨',
            style: TextStyle(color: Colors.black, fontFamily: 'Tajawal', fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    if (_status == 'rejected' || _status == 'cancelled') {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white12,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.pop(context, false),
          child: const Text(
            'إغلاق',
            style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 15),
          ),
        ),
      );
    }

    // Pending state buttons
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.refresh_rounded, color: _teal, size: 18),
            label: const Text(
              'تحديث الحالة يدوياً',
              style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 13),
            ),
            onPressed: _checkStatus,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _cancelling ? null : _cancelRequest,
            child: Text(
              _cancelling ? 'جارٍ الإلغاء...' : 'إلغاء طلب الصرف',
              style: const TextStyle(color: Colors.redAccent, fontFamily: 'Tajawal', fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}
