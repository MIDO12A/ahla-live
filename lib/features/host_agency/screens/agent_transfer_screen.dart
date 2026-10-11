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
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF333333)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'تحويل الرصيد للمضيفين',
          style: TextStyle(color: Color(0xFF333333), fontSize: 16, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // بطاقة الرصيد
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFDE880F), Color(0xFFF7B733)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: const Color(0xFFDE880F).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('رصيد الكوينز المتاح للتحويل', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      R.formatCoins(currentCoins),
                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.monetization_on, color: Colors.white, size: 24),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // نموذج التحويل
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('معرف المضيف (User ID / No)', style: TextStyle(color: Color(0xFF333333), fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _targetIdCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'أدخل رقم المعرف الخاص بالمضيف',
                    hintStyle: const TextStyle(fontSize: 12, color: Colors.black38),
                    filled: true,
                    fillColor: const Color(0xFFF9F9FB),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('عدد الكوينز المراد تحويلها', style: TextStyle(color: Color(0xFF333333), fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'مثال: 50000',
                    hintStyle: const TextStyle(fontSize: 12, color: Colors.black38),
                    filled: true,
                    fillColor: const Color(0xFFF9F9FB),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 20),
                if (_message != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: _isSuccess ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(_isSuccess ? Icons.check_circle : Icons.error, color: _isSuccess ? Colors.green : Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_message!, style: TextStyle(color: _isSuccess ? Colors.green.shade800 : Colors.red.shade800, fontSize: 12))),
                      ],
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _executeTransfer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDE880F),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('تأكيد التحويل الفوري', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
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
