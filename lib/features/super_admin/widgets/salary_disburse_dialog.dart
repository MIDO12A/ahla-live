import 'package:flutter/material.dart';
import '../../../core/supabase_compat.dart';
import '../../../core/ui/in_app_toast.dart';
import '../../../models/user_model.dart';
import '../../../services/supabase_data_service.dart';

class SalaryDisburseDialog extends StatefulWidget {
  final UserModel currentUser;
  final String role; // 'super_admin' | 'admin' | 'bd'
  final double currentSalary;
  final VoidCallback? onDisbursed;

  const SalaryDisburseDialog({
    super.key,
    required this.currentUser,
    required this.role,
    required this.currentSalary,
    this.onDisbursed,
  });

  static Future<void> show(
    BuildContext context, {
    required UserModel currentUser,
    required String role,
    required double currentSalary,
    VoidCallback? onDisbursed,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => SalaryDisburseDialog(
        currentUser: currentUser,
        role: role,
        currentSalary: currentSalary,
        onDisbursed: onDisbursed,
      ),
    );
  }

  @override
  State<SalaryDisburseDialog> createState() => _SalaryDisburseDialogState();
}

class _SalaryDisburseDialogState extends State<SalaryDisburseDialog> {
  final _sb = Supabase.instance.client;
  final _agentIdController = TextEditingController();
  final _amountController = TextEditingController();

  bool _searchingAgent = false;
  Map<String, dynamic>? _selectedAgent;
  String? _agentSearchError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.currentSalary.toInt().toString();
  }

  @override
  void dispose() {
    _agentIdController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _searchAgent() async {
    final query = _agentIdController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _agentSearchError = 'يرجى إدخال معرف وكيل الشحن';
        _selectedAgent = null;
      });
      return;
    }

    setState(() {
      _searchingAgent = true;
      _agentSearchError = null;
    });

    try {
      final res = await _sb
          .from('users')
          .select('uid, id, custom_id, name, photo_url, is_recharge_agent, recharge_agency_name, coins')
          .or('custom_id.eq.$query,uid.eq.$query,id.eq.$query')
          .maybeSingle();

      if (res == null) {
        setState(() {
          _agentSearchError = 'لم يتم العثور على وكيل بهذا المعرف';
          _selectedAgent = null;
        });
      } else if (res['is_recharge_agent'] != true) {
        setState(() {
          _agentSearchError = 'هذا المستخدم ليس وكيلاً معتمداً للشحن';
          _selectedAgent = null;
        });
      } else {
        setState(() {
          _selectedAgent = res;
          _agentSearchError = null;
        });
      }
    } catch (e) {
      setState(() {
        _agentSearchError = 'تعذر البحث عن الوكيل: $e';
        _selectedAgent = null;
      });
    } finally {
      if (mounted) setState(() => _searchingAgent = false);
    }
  }

  Future<void> _submitTransfer() async {
    if (_selectedAgent == null) {
      KayanInAppToast.warning('يرجى التحقق من وكيل الشحن أولاً');
      return;
    }

    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      KayanInAppToast.warning('يرجى إدخال مبلغ صحيح للصرف');
      return;
    }

    if (amount > widget.currentSalary && widget.currentSalary > 0) {
      KayanInAppToast.warning('المبلغ المطلوب أكبر من رصيد الراتب المتاح');
      return;
    }

    setState(() => _submitting = true);

    try {
      final senderUid = widget.currentUser.uid;
      final senderCustomId = widget.currentUser.customId;
      final senderName = widget.currentUser.name;
      final agentUid = _selectedAgent!['uid']?.toString() ?? _selectedAgent!['id']?.toString() ?? '';
      final agentCustomId = _selectedAgent!['custom_id']?.toString() ?? '';

      // 1. Insert into salary_transfer_requests table
      final insertData = {
        'sender_uid': senderUid,
        'sender_custom_id': senderCustomId,
        'sender_name': senderName,
        'sender_role': widget.role,
        'recharge_agent_uid': agentUid,
        'recharge_agent_custom_id': agentCustomId,
        'amount': amount,
        'status': 'pending',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      final inserted = await _sb.from('salary_transfer_requests').insert(insertData).select('id').maybeSingle();
      final transferId = inserted?['id']?.toString() ?? '';

      // 2. Send interactive notification to Recharge Agent
      await SupabaseDataService().sendNotification(
        uid: agentUid,
        type: 'salary_transfer_request',
        actorUid: senderUid,
        title: 'طلب تحويل وصرف راتب 💰',
        body: 'طلب $senderName تحويل راتب بقيمة ${amount.toInt()} ماسة إلى محفظتك ككوينز',
        data: {
          'action': 'salary_transfer_request',
          'transfer_id': transferId,
          'sender_uid': senderUid,
          'sender_name': senderName,
          'sender_custom_id': senderCustomId,
          'sender_role': widget.role,
          'amount': amount,
          'diamonds_amount': amount.toInt(),
        },
      );

      if (mounted) {
        KayanInAppToast.success('تم إرسال طلب صرف الراتب إلى وكيل الشحن بنجاح وفي انتظار موافقته 🎉');
        widget.onDisbursed?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        KayanInAppToast.error('فشل تقديم طلب الصرف: $e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: const Color(0xFF141A32),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFFFB800).withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFFFB800), size: 26),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'صرف الراتب إلى وكيل شحن',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'تحويل رصيد الراتب ككوينز إلى محفظة الوكيل',
                          style: TextStyle(
                            color: Color(0xFF8E9BB0),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // Current Salary Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E1C68), Color(0xFF1A2246)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x336C63FF)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'رصيد الراتب المتاح',
                          style: TextStyle(color: Color(0xFF8E9BB0), fontSize: 12),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'ماس / عملات الإدارة',
                          style: TextStyle(color: Color(0xFF00D4FF), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.diamond_rounded, color: Color(0xFF00D4FF), size: 22),
                        const SizedBox(width: 6),
                        Text(
                          widget.currentSalary.toInt().toString(),
                          style: const TextStyle(
                            color: Color(0xFFFFB800),
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Recharge Agent ID Input
              const Text(
                'معرف وكيل الشحن (ID / Custom ID)',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _agentIdController,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        hintText: 'أدخل رقم ID الخاص بالوكيل',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF0A0E21),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF6C63FF)),
                        ),
                      ),
                      onSubmitted: (_) => _searchAgent(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _searchingAgent ? null : _searchAgent,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    child: _searchingAgent
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('تحقق', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),

              if (_agentSearchError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _agentSearchError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],

              // Verified Agent Info Card
              if (_selectedAgent != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5A0).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF00E5A0).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFF6C63FF),
                        backgroundImage: _selectedAgent!['photo_url'] != null &&
                                _selectedAgent!['photo_url'].toString().isNotEmpty
                            ? NetworkImage(_selectedAgent!['photo_url'])
                            : null,
                        child: _selectedAgent!['photo_url'] == null ||
                                _selectedAgent!['photo_url'].toString().isEmpty
                            ? const Icon(Icons.person, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _selectedAgent!['name'] ?? 'وكيل معتمد',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.verified_rounded, color: Color(0xFF00E5A0), size: 16),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ID: ${_selectedAgent!['custom_id'] ?? _selectedAgent!['uid']} • ${_selectedAgent!['recharge_agency_name'] ?? "وكالة شحن رسمية"}',
                              style: const TextStyle(color: Color(0xFF8E9BB0), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Amount to Disburse Input
              const Text(
                'المبلغ المراد صرفه',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: 'أدخل المبلغ المراد صرفه',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF0A0E21),
                  prefixIcon: const Icon(Icons.diamond_rounded, color: Color(0xFF00D4FF), size: 20),
                  suffixText: 'ماس',
                  suffixStyle: const TextStyle(color: Color(0xFFFFB800), fontWeight: FontWeight.bold),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFFFB800)),
                  ),
                ),
              ),

              const SizedBox(height: 22),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _submitting ? null : () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('إلغاء', style: TextStyle(color: Colors.white60)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submitTransfer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFB800),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 4,
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Text(
                              'إرسال طلب الصرف',
                              style: TextStyle(
                                color: Color(0xFF141A32),
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
