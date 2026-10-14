import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/r.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/supabase_service.dart';
import '../data/anchor_agent_model.dart';

/// شاشة تحويل الكوينز والأرباح للمضيفين (AgentActivity)
class AgentTransferScreen extends StatefulWidget {
  final AgentInfoModel? agentInfo;

  const AgentTransferScreen({super.key, this.agentInfo});

  @override
  State<AgentTransferScreen> createState() => _AgentTransferScreenState();
}

class _AgentTransferScreenState extends State<AgentTransferScreen> {
  final TextEditingController _targetIdCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  bool _loading = false;
  String? _message;
  bool _isSuccess = false;

  Future<void> _executeTransfer() async {
    final targetId = _targetIdCtrl.text.trim();
    final amount = int.tryParse(_amountCtrl.text.trim()) ?? 0;

    if (targetId.isEmpty || amount <= 0) {
      setState(() {
        _message = 'يرجى إدخال معرف المضيف والمبلغ بشكل صحيح';
        _isSuccess = false;
      });
      return;
    }

    final currentUser = Provider.of<UserProvider>(context, listen: false).currentUser;
    if (currentUser == null) return;

    if (currentUser.coins < amount) {
      setState(() {
        _message = 'رصيد الكوينز غير كافٍ لإتمام التحويل';
        _isSuccess = false;
      });
      return;
    }

    setState(() => _loading = true);

    try {
      final fb = SupabaseService();
      final ok = await fb.transferCoinsToMember(
        agentUid: currentUser.uid,
        targetUserNoOrId: targetId,
        amount: amount,
      );

      if (mounted) {
        setState(() {
          _loading = false;
          _isSuccess = ok;
          _message = ok ? 'تم تحويل ${R.formatCoins(amount)} كوينز بنجاح إلى المضيف!' : 'فشل إتمام التحويل، تأكد من المعرف';
          if (ok) {
            _amountCtrl.clear();
            _targetIdCtrl.clear();
          }
        });
        if (ok) {
          Provider.of<UserProvider>(context, listen: false).loadUser(currentUser.uid);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _isSuccess = false;
          _message = 'حدث خطأ أثناء تنفيذ المعاملة المالية';
        });
      }
    }
  }

  @override
  void dispose() {
    _targetIdCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context).currentUser;
    final currentCoins = user?.coins ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFF10161D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'تحويل كوينز الوكالة للمضيفين',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── بطاقة رصيد الوكالة (نمط هاكوي الزمردي) ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x66000000),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x803ED78A), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3ED78A).withOpacity(0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3ED78A).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Text('🪙', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'رصيدك المتاح للتحويل:',
                        style: TextStyle(color: Color(0xFFC1EFD3), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        R.formatCoins(currentCoins),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFDB442), width: 1),
                  ),
                  child: const Text(
                    'رصيد كوينز',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFFCD3E)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── نموذج التحويل (مطابق لـ hyk_frame_dialog_trransfer.xml) ──
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF141C24),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x663ED78A), width: 1),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'معرف المضيف المستلم (User ID / No):',
                  style: TextStyle(color: Color(0xFFFEFEFD), fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0x66000000),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x803ED78A), width: 1),
                  ),
                  child: TextField(
                    controller: _targetIdCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      hintText: 'أدخل رقم المعرف ID الخاص بالمضيف',
                      hintStyle: TextStyle(fontSize: 12, color: Color(0xFFA1A1A1)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'عدد الكوينز المراد تحويلها:',
                  style: TextStyle(color: Color(0xFFFEFEFD), fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0x66000000),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x803ED78A), width: 1),
                  ),
                  child: TextField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFDE638), // Hayuki gold yellow
                    ),
                    decoration: const InputDecoration(
                      hintText: 'أدخل عدد الكوينز',
                      hintStyle: TextStyle(fontSize: 13, color: Color(0xFFA1A1A1)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (_message != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: _isSuccess ? const Color(0x223ED78A) : const Color(0x22FF5757),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isSuccess ? const Color(0xFF3ED78A) : const Color(0xFFFF5757),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isSuccess ? Icons.check_circle : Icons.error,
                          color: _isSuccess ? const Color(0xFF3ED78A) : const Color(0xFFFF5757),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _message!,
                            style: TextStyle(
                              color: _isSuccess ? const Color(0xFFC1EFD3) : const Color(0xFFFF8585),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      image: !_loading
                          ? const DecorationImage(
                              image: AssetImage(R.hykFrameBgTransferSure),
                              fit: BoxFit.fill,
                            )
                          : null,
                      gradient: _loading
                          ? LinearGradient(
                              colors: [Colors.grey.shade600, Colors.grey.shade700],
                            )
                          : null,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3ED78A).withOpacity(0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextButton(
                      onPressed: _loading ? null : _executeTransfer,
                      style: TextButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'تأكيد التحويل الفوري 🚀',
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
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
}
