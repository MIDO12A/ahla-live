import '../../../../services/supabase_data_service.dart';
import '../../../../services/supabase_auth_service.dart';
import 'package:provider/provider.dart';
import '../../../../providers/user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../services/firebase_service.dart';
import '../../../../core/supabase_compat.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../agent_recharge_widgets.dart';
import 'agent_history_tab.dart' show AgentEditQuickAmountsSheet;

// ══════════════════════════════════════════════════════════════════════
//  Password Setup Screen — يظهر عند أول استخدام لإعداد كلمة مرور الوكالة
// ══════════════════════════════════════════════════════════════════════
class AgentPinSetupScreen extends StatefulWidget {
  const AgentPinSetupScreen({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  State<AgentPinSetupScreen> createState() => _AgentPinSetupScreenState();
}

typedef AgentPasswordSetupScreen = AgentPinSetupScreen;

class _AgentPinSetupScreenState extends State<AgentPinSetupScreen> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _busy = false;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pass = _passCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (pass.isEmpty || pass.length < 3) {
      _showErr('يرجى إدخال كلمة مرور مكونة من 3 خانات أو أكثر');
      return;
    }
    if (pass != confirm) {
      _showErr('كلمة المرور وتأكيدها غير متطابقين');
      return;
    }

    setState(() => _busy = true);
    try {
      final uid = SupabaseAuthService().currentUser?.uid ??
          Provider.of<UserProvider>(context, listen: false).currentUser?.uid ??
          FirebaseAuth.instance.currentUser?.uid;

      if (uid != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('agent_password_$uid', pass);
          await prefs.setString('agent_pin_$uid', pass);
        } catch (_) {}

        try {
          final fs = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
          await fs.collection('users').doc(uid).set({
            'recharge_password': pass,
            'agent_pin': pass,
          }, SetOptions(merge: true));
          await fs.collection('agent_usd_wallets').doc(uid).set({
            'password': pass,
          }, SetOptions(merge: true));
        } catch (_) {}
      }

      try {
        await Supabase.instance.client.rpc('agent_set_pin', params: {'p_pin': pass, 'uid': uid});
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تثبيت وحفظ كلمة المرور بنجاح ✅',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
      widget.onDone();
    } catch (e) {
      debugPrint('[password_setup] $e');
      if (mounted) {
        setState(() => _busy = false);
        _showErr('حدث خطأ أثناء حفظ كلمة المرور: $e');
      }
    }
  }

  void _showErr(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
          backgroundColor: Colors.red));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF1a0a2e),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          ),
          title: Text('إعداد كلمة مرور الوكالة',
              style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.bold)),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: Column(children: [
              const SizedBox(height: 20),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                    color: KayanBrandColors.logoPrimary.withValues(alpha: 0.15),
                    shape: BoxShape.circle),
                child: const Center(child: Text('🔐', style: TextStyle(fontSize: 40))),
              ),
              const SizedBox(height: 20),
              Text(
                'تعيين كلمة مرور وكالة الشحن',
                style: GoogleFonts.tajawal(
                    fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'كلمة المرور تُطلب لحماية عمليات الشحن والسحب وتُحفظ بشكل دائم',
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(fontSize: 13, color: Colors.white54),
              ),
              const SizedBox(height: 32),
              // حقل كلمة المرور
              TextField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  labelText: 'كلمة المرور الجديدة',
                  labelStyle: GoogleFonts.tajawal(color: const Color(0xFFFFD770)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
                  prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFFFFD770)),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFFFB800), width: 1.5)),
                ),
              ),
              const SizedBox(height: 16),
              // حقل تأكيد كلمة المرور
              TextField(
                controller: _confirmCtrl,
                obscureText: _obscureConfirm,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  labelText: 'تأكيد كلمة المرور',
                  labelStyle: GoogleFonts.tajawal(color: const Color(0xFFFFD770)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
                  prefixIcon: const Icon(Icons.lock_reset, color: Color(0xFFFFD770)),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFFFB800), width: 1.5)),
                ),
              ),
              const SizedBox(height: 36),
              if (_busy)
                const CircularProgressIndicator(color: Color(0xFFFFB800))
              else
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB800),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('تثبيت وحفظ كلمة المرور ✅',
                        style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.w900)),
                  ),
                ),
            ]),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════
//  Password Verify Dialog — يظهر قبل كل عملية شحن أو سحب
// ══════════════════════════════════════════════════════════════════════
class _AgentPinVerifyDialog extends StatefulWidget {
  const _AgentPinVerifyDialog();
  @override
  State<_AgentPinVerifyDialog> createState() => _AgentPinVerifyDialogState();
}

typedef AgentPasswordVerifyDialog = _AgentPinVerifyDialog;

class _AgentPinVerifyDialogState extends State<_AgentPinVerifyDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final entered = _ctrl.text.trim();
    if (entered.isEmpty) {
      setState(() => _error = 'يرجى إدخال كلمة المرور');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final uid = SupabaseAuthService().currentUser?.uid ??
          Provider.of<UserProvider>(context, listen: false).currentUser?.uid ??
          FirebaseAuth.instance.currentUser?.uid;

      // 1. التحقق المحلي السريع من SharedPreferences
      String? savedPass;
      if (uid != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          savedPass = prefs.getString('agent_password_$uid') ?? prefs.getString('agent_pin_$uid');
        } catch (_) {}
      }

      // 2. إذا لم توجد محلياً، التحقق من Firestore
      if ((savedPass == null || savedPass.isEmpty) && uid != null) {
        try {
          final fs = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
          final doc = await fs.collection('users').doc(uid).get();
          savedPass = doc.data()?['recharge_password']?.toString() ?? doc.data()?['agent_pin']?.toString();
          if (savedPass != null && savedPass.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('agent_password_$uid', savedPass);
            await prefs.setString('agent_pin_$uid', savedPass);
          }
        } catch (_) {}
      }

      // 3. التحقق عبر Supabase Compat RPC
      dynamic rpcRes;
      try {
        rpcRes = await Supabase.instance.client
            .rpc('agent_verify_pin', params: {'p_pin': entered, 'p_password': entered, 'uid': uid});
      } catch (_) {}

      final rpcValid = rpcRes == true ||
          (rpcRes is Map && (rpcRes['ok'] == true || rpcRes['valid'] == true));

      final localValid = (savedPass != null && savedPass.isNotEmpty && savedPass == entered);
      final notSet = (savedPass == null || savedPass.isEmpty) &&
          (rpcRes is Map && rpcRes['not_set'] == true);

      if (!mounted) return;

      if (notSet) {
        // لم يتم تعيين كلمة مرور بعد: نفتح نافذة التعيين مباشرة
        final setOk = await AgentResetPinDialog.show(context);
        if (setOk == true && mounted) {
          Navigator.of(context).pop(true);
        } else if (mounted) {
          setState(() => _busy = false);
        }
        return;
      }

      if (localValid || rpcValid) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _busy = false;
          _error = 'كلمة المرور غير صحيحة';
        });
      }
    } catch (e) {
      debugPrint('[password_verify] $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'خطأ أثناء التحقق: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: const Color(0xFF1a0a2e),
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🔐', style: TextStyle(fontSize: 38)),
            const SizedBox(height: 10),
            Text('تأكيد كلمة المرور',
                style: GoogleFonts.tajawal(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
            const SizedBox(height: 4),
            Text('أدخل كلمة المرور لتأكيد العملية',
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(fontSize: 12, color: Colors.white54)),
            const SizedBox(height: 24),
            TextField(
              controller: _ctrl,
              obscureText: _obscure,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _verify(),
              decoration: InputDecoration(
                hintText: 'أدخل كلمة المرور',
                hintStyle: GoogleFonts.tajawal(color: Colors.white38, fontSize: 14),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFFFFB800)),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFFFB800), width: 1.5)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: GoogleFonts.tajawal(
                      fontSize: 13,
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 20),
            if (_busy)
              const CircularProgressIndicator(color: Color(0xFFFFB800))
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('إلغاء',
                          style: GoogleFonts.tajawal(fontSize: 14, color: Colors.white70)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _verify,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFB800),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('تأكيد ✅',
                          style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () async {
                final ok = await AgentResetPinDialog.show(context);
                if (ok == true && context.mounted) {
                  Navigator.of(context).pop(true);
                }
              },
              icon: const Icon(Icons.lock_reset_rounded, size: 18, color: Color(0xFFFFD770)),
              label: Text(
                'إعادة تعيين كلمة المرور',
                style: GoogleFonts.tajawal(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFFFD770),
                ),
              ),
            ),
          ]),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════
//  Agent Reset Password Dialog — نافذة إعادة تعيين / تعيين كلمة المرور
// ══════════════════════════════════════════════════════════════════════
class AgentResetPinDialog extends StatefulWidget {
  const AgentResetPinDialog({super.key, this.onSuccess});
  final VoidCallback? onSuccess;

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const AgentResetPinDialog(),
    );
  }

  @override
  State<AgentResetPinDialog> createState() => _AgentResetPinDialogState();
}

typedef AgentResetPasswordDialog = AgentResetPinDialog;

class _AgentResetPinDialogState extends State<AgentResetPinDialog> {
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pass = _newPassCtrl.text.trim();
    final confirm = _confirmPassCtrl.text.trim();

    if (pass.isEmpty || pass.length < 3) {
      setState(() => _error = 'يرجى إدخال كلمة مرور مكونة من 3 خانات أو أكثر');
      return;
    }
    if (confirm != pass) {
      setState(() => _error = 'تأكيد كلمة المرور غير متطابق مع الكلمة الجديدة');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final uid = SupabaseAuthService().currentUser?.uid ??
          Provider.of<UserProvider>(context, listen: false).currentUser?.uid ??
          FirebaseAuth.instance.currentUser?.uid;

      if (uid != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('agent_password_$uid', pass);
          await prefs.setString('agent_pin_$uid', pass);
        } catch (_) {}

        try {
          final fs = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
          await fs.collection('users').doc(uid).set({
            'recharge_password': pass,
            'agent_pin': pass,
          }, SetOptions(merge: true));
          await fs.collection('agent_usd_wallets').doc(uid).set({
            'password': pass,
          }, SetOptions(merge: true));
        } catch (_) {}
      }

      try {
        await Supabase.instance.client
            .rpc('agent_set_pin', params: {'p_pin': pass, 'p_password': pass, 'uid': uid});
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم حفظ وتثبيت كلمة المرور بنجاح ✅',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
      widget.onSuccess?.call();
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('[reset_password] $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'حدث خطأ أثناء حفظ كلمة المرور: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: const Color(0xFF1a0a2e),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🔑', style: TextStyle(fontSize: 36)),
                const SizedBox(height: 10),
                Text(
                  'تعيين / تغيير كلمة المرور',
                  style: GoogleFonts.tajawal(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'أدخل كلمة المرور الجديدة وثبّتها لاستخدامها في كل مرة',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(fontSize: 12, color: Colors.white54),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _newPassCtrl,
                  obscureText: _obscureNew,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور الجديدة',
                    labelStyle: GoogleFonts.tajawal(color: const Color(0xFFFFD770)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFFFFD770)),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                      onPressed: () => setState(() => _obscureNew = !_obscureNew),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFFB800), width: 1.5)),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _confirmPassCtrl,
                  obscureText: _obscureConfirm,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    labelText: 'تأكيد كلمة المرور الجديدة',
                    labelStyle: GoogleFonts.tajawal(color: const Color(0xFFFFD770)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    prefixIcon: const Icon(Icons.lock_reset, color: Color(0xFFFFD770)),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFFB800), width: 1.5)),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.tajawal(
                      fontSize: 12,
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (_busy)
                  const CircularProgressIndicator(color: Color(0xFFFFB800))
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(
                            'إلغاء',
                            style: GoogleFonts.tajawal(fontSize: 14, color: Colors.white54),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFB800),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                          child: Text(
                            'تثبيت الكلمة ✅',
                            style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.w900),
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

// ══════════════════════════════════════════════════════════════════════
//  Recharge Tab — صفحة البحث عن المستخدم والشحن
// ══════════════════════════════════════════════════════════════════════
class AgentRechargeTab extends StatefulWidget {
  const AgentRechargeTab({
    super.key,
    required this.agencyGold,
    required this.dailyRemaining,
    required this.quickAmounts,
    required this.onSuccess,
    required this.onQuickAmountsChanged,
  });

  final int agencyGold;
  final int dailyRemaining;
  final List<int> quickAmounts;
  final VoidCallback onSuccess;
  final void Function(List<int>) onQuickAmountsChanged;

  @override
  State<AgentRechargeTab> createState() => _AgentRechargeTabState();
}

class _AgentRechargeTabState extends State<AgentRechargeTab> {
  final _searchCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  bool _searching = false;
  List<Map<String, dynamic>> _results = const [];
  Map<String, dynamic>? _selected;
  bool _busy = false;
  bool _isWithdrawMode = false; // false = شحن, true = سحب

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _amountCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    final trimmed = val.trim().replaceFirst('#', '').trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _doSearch(trimmed));
  }

  Future<void> _doSearch(String rawQ) async {
    final q = rawQ.trim().replaceFirst('#', '').trim();
    if (q.isEmpty) {
      setState(() => _searching = false);
      return;
    }
    try {
      final List<Map<String, dynamic>> results = [];
      final Set<String> seenUids = {};

      void addUser(Map<String, dynamic> d) {
        final uid = d['uid']?.toString() ?? d['id']?.toString() ?? '';
        if (uid.isEmpty || seenUids.contains(uid)) return;
        seenUids.add(uid);
        final photo = d['avatar'] ?? d['avatar_url'] ?? d['photo_url'] ?? d['photoUrl'] ?? '';
        results.add({
          'id': uid,
          'uid': uid,
          'display_name': d['name'] ?? d['nickname'] ?? d['display_name'] ?? 'مستخدم',
          'avatar_url': photo,
          'kayan_id': d['custom_id']?.toString() ??
              d['customId']?.toString() ??
              d['display_id']?.toString() ??
              (uid.length > 8 ? uid.substring(0, 8) : uid),
          'coins': (d['coins'] as num?)?.toInt() ?? 0,
          'diamonds': (d['diamonds'] as num?)?.toInt() ?? 0,
        });
      }

      // 1. Direct match by ID / custom_id via Supabase
      final directUser = await SupabaseDataService().findUserByIdOrCustomId(q);
      if (directUser != null) {
        addUser(directUser.toMap());
      }

      // 2. Search users via Supabase
      final searchList = await SupabaseDataService().searchUsers(q);
      for (final u in searchList) {
        addUser(u);
      }

      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (e) {
      debugPrint('[search] $e');
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectUser(Map<String, dynamic> user) {
    setState(() {
      _selected = user;
      _results = const [];
      _searchCtrl.text = user['display_name']?.toString() ?? '';
    });
    _searchFocus.unfocus();
  }

  void _clearSelected() {
    setState(() {
      _selected = null;
      _results = const [];
      _searchCtrl.clear();
      _amountCtrl.clear();
    });
  }

  Future<bool> _showPinDialog() async =>
      await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _AgentPinVerifyDialog()) ??
      false;

  Future<void> _confirmAndSend() async {
    final user = _selected;
    if (user == null) return;
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount < 1) {
      _showSnack('أدخل عدد الكوينز');
      return;
    }
    if (amount > 10000000) {
      _showSnack('الحد الأقصى 10,000,000 كوين');
      return;
    }

    if (!_isWithdrawMode) {
      // وضع الشحن: التحقق من رصيد الوكيل والحد اليومي
      if (amount > widget.agencyGold) {
        _showSnack('رصيد الوكالة غير كافٍ للشحن (رصيدك الحالي: ${widget.agencyGold} كوين)');
        return;
      }
      if (amount > widget.dailyRemaining) {
        _showSnack('يتجاوز الحد اليومي المتبقي (${widget.dailyRemaining} كوين)');
        return;
      }
    } else {
      // وضع سحب الألماس (الراتب): التحقق من رصيد ألماس المستخدم
      final userDiamonds = (user['diamonds'] as num?)?.toInt() ?? 0;
      if (amount > userDiamonds) {
        _showSnack('رصيد ألماس المستخدم غير كافٍ للسحب (رصيده المتاح: $userDiamonds ماسة)');
        return;
      }
    }

    final pinOk = await _showPinDialog();
    if (!pinOk) return;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AgentRechargeConfirmDialog(
            user: user,
            amount: amount,
            isWithdraw: _isWithdrawMode,
          ),
        ) ??
        false;

    if (!confirmed) return;

    if (_isWithdrawMode) {
      await _executeWithdraw(user, amount);
    } else {
      await _executeRecharge(user, amount);
    }
  }

  Future<void> _executeRecharge(Map<String, dynamic> user, int amount) async {
    setState(() => _busy = true);
    final targetUid = user['id']?.toString() ?? user['uid']?.toString() ?? '';
    final agentUid = SupabaseAuthService().currentUser?.uid ??
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid ??
        FirebaseAuth.instance.currentUser?.uid;
    if (agentUid == null || targetUid.isEmpty) {
      setState(() => _busy = false);
      _showSnack('خطأ: تعذر التعرف على بيانات الحساب');
      return;
    }

    try {
      final agentUser = await SupabaseDataService().getUser(agentUid);
      if (agentUser == null || agentUser.coins < amount) {
        if (!mounted) return;
        setState(() => _busy = false);
        _showSnack('فشلت العملية: رصيد الوكيل غير كافٍ');
        return;
      }

      final targetUser = await SupabaseDataService().getUser(targetUid);
      if (targetUser == null) {
        if (!mounted) return;
        setState(() => _busy = false);
        _showSnack('خطأ: لم يتم العثور على حساب المستلم');
        return;
      }

      final agentDeductSuccess = await SupabaseDataService().updateUser(agentUid, {
        'coins': agentUser.coins - amount,
      });

      if (!agentDeductSuccess) {
        if (!mounted) return;
        setState(() => _busy = false);
        _showSnack('فشلت العملية أثناء تحديث رصيد الوكيل');
        return;
      }

      await SupabaseDataService().updateUser(targetUid, {
        'coins': targetUser.coins + amount,
      });

      await SupabaseDataService().recordAgentTransaction(
        agentId: agentUid,
        targetUid: targetUid,
        targetCustomId: user['kayan_id']?.toString() ?? targetUser.customId,
        amountCoins: amount,
      );

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      if (userProvider.currentUser?.uid == agentUid) {
        userProvider.deductCoinsLocally(amount);
      }

      if (!mounted) return;
      setState(() => _busy = false);

      SupabaseDataService().sendNotification(
        uid: targetUid,
        type: 'recharge',
        title: 'شحن رصيد كوينز 🪙',
        body: 'تم شحن $amount كوين لحسابك بنجاح من وكيل الشحن.',
        data: {'amount': amount, 'agent_id': agentUid},
      );

      _showSnack('✅ تم شحن $amount كوين للمستخدم بنجاح');
      _clearSelected();
      widget.onSuccess();
    } catch (e) {
      debugPrint('[recharge] error: $e');
      if (mounted) {
        setState(() => _busy = false);
        _showSnack('حدث خطأ أثناء الشحن: $e');
      }
    }
  }

  Future<void> _executeWithdraw(Map<String, dynamic> user, int amount) async {
    setState(() => _busy = true);
    final targetUid = user['id']?.toString() ?? user['uid']?.toString() ?? '';
    final agentUid = SupabaseAuthService().currentUser?.uid ??
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid ??
        FirebaseAuth.instance.currentUser?.uid;
    if (agentUid == null || targetUid.isEmpty) {
      setState(() => _busy = false);
      _showSnack('خطأ: تعذر التعرف على بيانات الحساب');
      return;
    }

    try {
      final res = await FirebaseService().createAgentDiamondWithdrawalRequest(
        agentUid: agentUid,
        targetUid: targetUid,
        diamondsAmount: amount,
      );

      if (!mounted) return;
      setState(() => _busy = false);

      if (res['success'] == true) {
        _showSnack('✅ تم إرسال طلب سحب $amount ماسة للمستخدم، ولن يتم الخصم إلا بعد موافقته');
        _clearSelected();
        widget.onSuccess();
      } else {
        _showSnack(res['message']?.toString() ?? 'فشلت العملية');
      }
    } catch (e) {
      debugPrint('[withdraw] error: $e');
      if (mounted) {
        setState(() => _busy = false);
        _showSnack('حدث خطأ أثناء إرسال طلب السحب: $e');
      }
    }
  }

  void _showSnack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg,
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1a1a2e),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: _busy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          _buildSearchField(),
          if (_searching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFFFFB800))),
            ),
          if (!_searching && _results.isNotEmpty) _buildResultsList(),
          if (_selected != null) ...[
            const SizedBox(height: 20),
            _buildModeSelector(),
            _buildSelectedCard(),
            const SizedBox(height: 20),
            _buildQuickAmounts(),
            const SizedBox(height: 12),
            _buildAmountField(),
            const SizedBox(height: 16),
            _buildSendButton(),
          ],
          if (_selected == null &&
              !_searching &&
              _results.isEmpty &&
              _searchCtrl.text.isEmpty)
            _buildGuide(),
        ],
      ),
    );
  }

  Widget _buildModeSelector() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isWithdrawMode = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: !_isWithdrawMode
                      ? const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)])
                      : null,
                  color: !_isWithdrawMode ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: !_isWithdrawMode
                      ? [
                          BoxShadow(
                              color: Colors.green.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3)),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    '🟢 شحن رصيد للمستخدم',
                    style: GoogleFonts.tajawal(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: !_isWithdrawMode ? Colors.white : Colors.black54,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isWithdrawMode = true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: _isWithdrawMode
                      ? const LinearGradient(colors: [Color(0xFFC62828), Color(0xFFEF5350)])
                      : null,
                  color: _isWithdrawMode ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _isWithdrawMode
                      ? [
                          BoxShadow(
                              color: Colors.red.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3)),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    '💎 سحب ألماس الراتب',
                    style: GoogleFonts.tajawal(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: _isWithdrawMode ? Colors.white : Colors.black54,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      );

  Widget _buildSearchField() => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          onChanged: _onSearchChanged,
          textDirection: TextDirection.rtl,
          style: GoogleFonts.tajawal(
              fontSize: 15, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'ابحث بالمعرف ID أو الاسم أو رقم الحساب...',
            hintStyle:
                GoogleFonts.tajawal(fontSize: 14, color: Colors.black38),
            prefixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFFFFB800))))
                : const Icon(Icons.search_rounded,
                    color: Color(0xFFFFB800), size: 22),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.black38, size: 20),
                    onPressed: _clearSelected)
                : null,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      );

  Widget _buildResultsList() => Container(
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 16,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Column(
          children: _results.asMap().entries.map((e) {
            final user = e.value;
            final isLast = e.key == _results.length - 1;
            return GestureDetector(
              onTap: () => _selectUser(user),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                    border: isLast
                        ? null
                        : Border(
                            bottom: BorderSide(
                                color: Colors.black
                                    .withValues(alpha: 0.06)))),
                child: Row(children: [
                  AgentAvatar(
                      url: user['avatar_url']?.toString(), size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              user['display_name']?.toString() ??
                                  'مستخدم',
                              style: GoogleFonts.tajawal(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1a1a2e))),
                          if (user['kayan_id'] != null)
                            Text('# ${user['kayan_id']}',
                                style: GoogleFonts.tajawal(
                                    fontSize: 12,
                                    color: KayanBrandColors.logoPrimary,
                                    fontWeight: FontWeight.w700)),
                        ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '🪙 ${_fmtAmt(user['coins'] ?? 0)}',
                      style: GoogleFonts.tajawal(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFB78103),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_left_rounded,
                      color: Colors.black26, size: 20),
                ]),
              ),
            );
          }).toList(),
        ),
      );

  Widget _buildSelectedCard() {
    final user = _selected!;
    final coins = (user['coins'] as num?)?.toInt() ?? 0;
    final diamonds = (user['diamonds'] as num?)?.toInt() ?? 0;
    final primaryColor = _isWithdrawMode ? Colors.redAccent : KayanBrandColors.logoPrimary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primaryColor.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(children: [
            AgentAvatar(url: user['avatar_url']?.toString(), size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_isWithdrawMode ? 'المستخدم المطلوب سحب الألماس منه' : 'المستخدم المطلوب شحن رصيده',
                        style: GoogleFonts.tajawal(
                            fontSize: 11,
                            color: primaryColor,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(user['display_name']?.toString() ?? 'مستخدم',
                        style: GoogleFonts.tajawal(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF1a1a2e))),
                    if (user['kayan_id'] != null)
                      Text('# ${user['kayan_id']}',
                          style: GoogleFonts.tajawal(
                              fontSize: 12,
                              color: primaryColor,
                              fontWeight: FontWeight.w700)),
                  ]),
            ),
            GestureDetector(
              onTap: _clearSelected,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.close_rounded,
                    size: 18, color: Colors.red),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB800).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Text('🪙', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('رصيد الكوينز', style: GoogleFonts.tajawal(fontSize: 10, color: Colors.black45)),
                          Text(_fmtAmt(coins), style: GoogleFonts.tajawal(fontSize: 13, fontWeight: FontWeight.w900, color: const Color(0xFFB78103))),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Text('💎', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('رصيد الماس', style: GoogleFonts.tajawal(fontSize: 10, color: Colors.black45)),
                          Text(_fmtAmt(diamonds), style: GoogleFonts.tajawal(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.blue.shade800)),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAmounts() {
    final amounts = widget.quickAmounts;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('مبالغ سريعة',
            style: GoogleFonts.tajawal(
                fontSize: 12,
                color: Colors.black45,
                fontWeight: FontWeight.w700)),
        const Spacer(),
        GestureDetector(
          onTap: () => _openEditQuickAmounts(amounts),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: KayanBrandColors.logoPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: KayanBrandColors.logoPrimary
                      .withValues(alpha: 0.25)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.tune_rounded,
                  size: 14, color: KayanBrandColors.logoPrimary),
              const SizedBox(width: 4),
              Text('تخصيص',
                  style: GoogleFonts.tajawal(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: KayanBrandColors.logoPrimary)),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(
        children: amounts
            .map((amt) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _amountCtrl.text = amt.toString()),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB800)
                              .withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _amountCtrl.text == amt.toString()
                                ? const Color(0xFFFFB800)
                                : const Color(0xFFFFB800)
                                    .withValues(alpha: 0.3),
                            width:
                                _amountCtrl.text == amt.toString() ? 2 : 1,
                          ),
                        ),
                        child: Column(children: [
                          const Text('🪙',
                              style: TextStyle(fontSize: 16)),
                          Text(_fmtAmt(amt),
                              style: GoogleFonts.tajawal(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFFFFB800))),
                        ]),
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    ]);
  }

  String _fmtAmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
    return n.toString();
  }

  Future<void> _openEditQuickAmounts(List<int> current) async {
    final result = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AgentEditQuickAmountsSheet(current: current),
    );
    if (result != null) {
      try {
        final res = await Supabase.instance.client
            .rpc('agent_set_quick_amounts', params: {'p_amounts': result});
        if (!mounted) return;
        if (res is Map && res['ok'] == true) {
          widget.onQuickAmountsChanged(result);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('✅ تم حفظ المبالغ السريعة',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green.shade700));
        } else {
          _showSnack(res?['error']?.toString() ?? 'خطأ في الحفظ');
        }
      } catch (e) {
        debugPrint('[quick_amounts] $e');
        if (mounted) _showSnack('خطأ في الاتصال');
      }
    }
  }

  Widget _buildAmountField() => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12),
          ],
        ),
        child: TextField(
          controller: _amountCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textDirection: TextDirection.rtl,
          style: GoogleFonts.tajawal(
              fontSize: 18, fontWeight: FontWeight.w800),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: _isWithdrawMode ? 'أدخل عدد الألماس المراد سحبه كراتب' : 'أدخل عدد الكوينز المراد شحنها',
            hintStyle:
                GoogleFonts.tajawal(fontSize: 15, color: Colors.black38),
            prefixIcon: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_isWithdrawMode ? '💎' : '🪙', style: const TextStyle(fontSize: 22))),
            suffixText: _isWithdrawMode ? 'ماسة' : 'كوين',
            suffixStyle: GoogleFonts.tajawal(
                fontSize: 13,
                color: Colors.black45,
                fontWeight: FontWeight.w600),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          ),
        ),
      );

  Widget _buildSendButton() => SizedBox(
        width: double.infinity,
        height: 54,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _busy
                  ? [Colors.grey.shade300, Colors.grey.shade300]
                  : _isWithdrawMode
                      ? [const Color(0xFFC62828), const Color(0xFFEF5350)]
                      : [KayanBrandColors.logoPrimary, const Color(0xFFFF6B00)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: _busy
                ? []
                : [
                    BoxShadow(
                        color: (_isWithdrawMode ? Colors.red : KayanBrandColors.logoPrimary)
                            .withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6)),
                  ],
          ),
          child: TextButton(
            onPressed: _busy ? null : _confirmAndSend,
            style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16))),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : Text(
                    _isWithdrawMode ? 'إرسال طلب سحب الألماس 💎' : 'شحن الكوينز الآن 🚀',
                    style: GoogleFonts.tajawal(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
          ),
        ),
      );

  Widget _buildGuide() => Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🔍', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 16),
          Text('ابحث عن مستخدم بالـ ID أو الاسم',
              style: GoogleFonts.tajawal(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54)),
          const SizedBox(height: 6),
          Text('يمكنك البحث برقم المعرف أو الاسم لشحن أو سحب الكوينز فورياً',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(
                  fontSize: 13, color: Colors.black38)),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: () => AgentResetPinDialog.show(context),
            icon: const Icon(Icons.lock_reset_rounded, size: 20, color: Color(0xFFB78103)),
            label: Text(
              'إعادة تعيين رمز PIN الخاص بك',
              style: GoogleFonts.tajawal(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFB78103),
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFFD770), width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ]),
      );
}
