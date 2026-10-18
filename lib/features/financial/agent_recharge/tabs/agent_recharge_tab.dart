import '../../../../services/supabase_data_service.dart';
import '../../../../services/supabase_auth_service.dart';
import 'package:provider/provider.dart';
import '../../../../providers/user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../services/supabase_service.dart';
import '../../../../core/supabase_compat.dart';
import '../../../../config/r.dart';
import '../../../../services/dynamic_config_service.dart';

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
          Provider.of<UserProvider>(context, listen: false).currentUser?.uid;

      if (uid != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('agent_password_$uid', pass);
          await prefs.setString('agent_pin_$uid', pass);
        } catch (_) {}

        try {
          await SupabaseDataService().updateUser(uid, {
            'recharge_password': pass,
            'agent_pin': pass,
          });
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
          Provider.of<UserProvider>(context, listen: false).currentUser?.uid;

      // 1. التحقق المحلي السريع من SharedPreferences
      String? savedPass;
      if (uid != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          savedPass = prefs.getString('agent_password_$uid') ?? prefs.getString('agent_pin_$uid');
        } catch (_) {}
      }

      // 2. إذا لم توجد محلياً، التحقق من Supabase
      if ((savedPass == null || savedPass.isEmpty) && uid != null) {
        try {
          final u = await SupabaseDataService().getUser(uid);
          // if saved in prefs or db
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
          Provider.of<UserProvider>(context, listen: false).currentUser?.uid;

      if (uid != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('agent_password_$uid', pass);
          await prefs.setString('agent_pin_$uid', pass);
        } catch (_) {}

        try {
          await SupabaseDataService().updateUser(uid, {
            'recharge_password': pass,
            'agent_pin': pass,
          });
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
  final _confirmAmountCtrl = TextEditingController();
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
    _confirmAmountCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String _fmtAmt(dynamic val) {
    if (val == null) return '0';
    final n = num.tryParse(val.toString()) ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  Future<void> _openEditQuickAmounts(List<int> amounts) async {
    final res = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AgentEditQuickAmountsSheet(
        current: amounts,
      ),
    );
    if (res != null && mounted) {
      widget.onQuickAmountsChanged(res);
    }
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
      _confirmAmountCtrl.clear();
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
    final confirmAmount = int.tryParse(_confirmAmountCtrl.text.trim());
    if (confirmAmount != amount) {
      _showSnack('تأكيد عدد الكوينز غير متطابق مع المبلغ المدخل');
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
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (agentUid == null || targetUid.isEmpty) {
      setState(() => _busy = false);
      _showSnack('خطأ: تعذر التعرف على بيانات الحساب');
      return;
    }

    try {
      // فحص رصيد وكالة الشحن من جدول agency_wallets حصراً (فصل تام عن المحفظة الشخصية)
      final sb = Supabase.instance.client;
      final aw = await sb
          .from('agency_wallets')
          .select('id, gold_balance')
          .eq('agency_profile_id', agentUid)
          .maybeSingle();

      final agencyGold = (aw?['gold_balance'] as num?)?.toInt() ?? 0;
      if (agencyGold < amount) {
        if (!mounted) return;
        setState(() => _busy = false);
        _showSnack('فشلت العملية: رصيد وكالة الشحن غير كافٍ ($agencyGold كوينز)');
        return;
      }

      final targetUser = await SupabaseDataService().getUser(targetUid);
      if (targetUser == null) {
        if (!mounted) return;
        setState(() => _busy = false);
        _showSnack('خطأ: لم يتم العثور على حساب المستلم');
        return;
      }

      // خصم الكوينز من محفظة وكالة الشحن فقط (لا يتم المساس برصيد كوينز حساب المستخدم الشخصي)
      await sb.from('agency_wallets').update({
        'gold_balance': (agencyGold - amount).clamp(0, 999999999),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('agency_profile_id', agentUid);

      await SupabaseDataService().updateUser(targetUid, {
        'coins': targetUser.coins + amount,
      });

      await SupabaseDataService().recordAgentTransaction(
        agentId: agentUid,
        targetUid: targetUid,
        targetCustomId: user['kayan_id']?.toString() ?? targetUser.customId,
        amountCoins: amount,
      );

      if (!mounted) return;
      setState(() => _busy = false);

      SupabaseDataService().sendNotification(
        uid: targetUid,
        type: 'recharge',
        title: 'شحن رصيد كوينز 🪙',
        body: 'تم شحن $amount كوين لحسابك بنجاح من وكيل الشحن.',
        data: {'amount': amount, 'agent_id': agentUid},
      );

      final orderId = 'ORD${DateTime.now().millisecondsSinceEpoch.toString().substring(4)}';
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      AgentRechargeSuccessDialog.show(
        context: context,
        orderId: orderId,
        userId: user['kayan_id']?.toString() ?? targetUser.customId,
        userName: targetUser.name,
        goldNum: amount,
        dateStr: dateStr,
      );

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
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
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
            const SizedBox(height: 16),
            _buildModeSelector(),
            _buildSelectedCard(),
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
    final hasMismatch = _amountCtrl.text.isNotEmpty &&
        _confirmAmountCtrl.text.isNotEmpty &&
        _amountCtrl.text.trim() != _confirmAmountCtrl.text.trim();
    final dc = DynamicConfigService();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dc.agentRechargeCardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: dc.agentRechargeCardBorderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Hayuki Title Image (txt_transfer_title.png) أو من لوحة التحكم ──
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: dc.buildDynamicImage(
                dc.agentRechargeTransferTitleImage,
                defaultAsset: R.hykTxtTransferTitle,
                height: 24,
                fit: BoxFit.contain,
                fallbackWidget: Text(
                  _isWithdrawMode ? 'سحب رصيد الألماس' : 'تحويل كوينز الوكالة',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFEFEFD),
                  ),
                ),
              ),
            ),
          ),

          // ── boxUserInfo (bg_nim_transfer_1_info) أو من لوحة التحكم ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              image: dc.getDecorationImage(
                dc.agentRechargeTransferCardBgImage,
                defaultAsset: R.hykBgNimTransfer1Info,
                fit: BoxFit.fill,
              ),
              color: const Color(0xFF1C2732),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dc.agentRechargeCardBorderColor, width: 1),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF3ED78A), width: 1.5),
                  ),
                  child: AgentAvatar(url: user['avatar_url']?.toString(), size: 44),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user['display_name']?.toString() ?? 'مستخدم',
                        style: GoogleFonts.tajawal(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFFEFEFD),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'ID :',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFFC1EFD3),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0x8C000000),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Text(
                              user['kayan_id']?.toString() ?? user['id']?.toString() ?? '',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFC1EFD3),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _clearSelected,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── bocMiddle: رصيد وكالتك (tvRuuiofkioBalance) ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isWithdrawMode ? 'رصيد ألماس المستخدم المتاح للسحب:' : 'رصيد وكالتك الحالي:',
                style: GoogleFonts.tajawal(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFFEFEFD),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDB442), width: 1),
                ),
                child: Text(
                  _isWithdrawMode ? 'سحب الراتب' : 'تعبئة وشحن',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFCD3E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0x66000000),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x803ED78A), width: 1),
            ),
            child: Row(
              children: [
                Text(
                  _isWithdrawMode ? '💎' : '🪙',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 8),
                Text(
                  _isWithdrawMode ? _fmtAmt(diamonds) : _fmtAmt(widget.agencyGold),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  _isWithdrawMode ? 'ماسة متوفرة' : 'كوين في الوكالة',
                  style: GoogleFonts.tajawal(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Quick Amounts (أزرار مبالغ سريعة بنمط هاكوي) ──
          _buildQuickAmounts(),

          const SizedBox(height: 14),

          // ── textViewRuuiofkio5 + etCoins (حقل إدخال الكوينز الأول) ──
          Text(
            _isWithdrawMode ? 'عدد الماسات المراد سحبها كراتب:' : 'عدد الكوينز المراد شحنها:',
            style: GoogleFonts.tajawal(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: const Color(0xFFFEFEFD),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: const Color(0x66000000),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x803ED78A), width: 1),
            ),
            child: TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: dc.agentRechargeCoinsTextColor,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'أدخل عدد الكوينز',
                hintStyle: TextStyle(fontSize: 13, color: Color(0xFFA1A1A1)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── textViewRuuiofkio6 + etCoins2 (حقل تأكيد عدد الكوينز) ──
          Text(
            _isWithdrawMode ? 'تأكيد عدد الماسات المراد سحبها:' : 'تأكيد عدد الكوينز المراد شحنها:',
            style: GoogleFonts.tajawal(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: const Color(0xFFFEFEFD),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: const Color(0x66000000),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasMismatch ? const Color(0xFFFF5757) : dc.agentRechargeCardBorderColor,
                width: 1,
              ),
            ),
            child: TextField(
              controller: _confirmAmountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: hasMismatch ? const Color(0xFFFF5757) : dc.agentRechargeCoinsTextColor,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'تأكيد عدد الكوينز المدخل',
                hintStyle: TextStyle(fontSize: 13, color: Color(0xFFA1A1A1)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),

          // ── tvNotEnough2: رسالة عدم تطابق المبالغ ──
          if (hasMismatch) ...[
            const SizedBox(height: 5),
            const Text(
              '⚠️ المبالغ غير متطابقة، يرجى كتابة نفس المبلغ للتأكيد',
              style: TextStyle(fontSize: 11, color: Color(0xFFFF5757), fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 18),

          // ── hyk_frame_btn_confirm (زر التأكيد المتطابق مع هاكوي) ──
          _buildSendButton(),
        ],
      ),
    );
  }

  Widget _buildQuickAmounts() {
    final amounts = widget.quickAmounts;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(
          'مبالغ سريعة:',
          style: GoogleFonts.tajawal(
            fontSize: 11,
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => _openEditQuickAmounts(amounts),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF3ED78A).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF3ED78A).withOpacity(0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.tune_rounded, size: 12, color: Color(0xFF3ED78A)),
              const SizedBox(width: 4),
              Text(
                'تخصيص',
                style: GoogleFonts.tajawal(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF3ED78A),
                ),
              ),
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
                      onTap: () {
                        setState(() {
                          _amountCtrl.text = amt.toString();
                          _confirmAmountCtrl.text = amt.toString();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _amountCtrl.text == amt.toString()
                              ? const Color(0x403ED78A)
                              : const Color(0x33000000),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _amountCtrl.text == amt.toString()
                                ? const Color(0xFF3ED78A)
                                : const Color(0x4D3ED78A),
                            width: _amountCtrl.text == amt.toString() ? 1.5 : 1,
                          ),
                        ),
                        child: Column(children: [
                          const Text('🪙', style: TextStyle(fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(
                            _fmtAmt(amt),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFFDE638),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    ]);
  }

  Widget _buildAmountField() => const SizedBox.shrink(); // Integrated into _buildSelectedCard

  Widget _buildSendButton() {
    final dc = DynamicConfigService();
    return SizedBox(
        width: double.infinity,
        height: 48,
        child: DecoratedBox(
          decoration: BoxDecoration(
            image: (!_busy && !_isWithdrawMode)
                ? dc.getDecorationImage(
                    dc.agentRechargeConfirmBtnImage,
                    defaultAsset: R.hykFrameBgTransferSure,
                    fit: BoxFit.fill,
                  )
                : null,
            gradient: _busy
                ? LinearGradient(
                    colors: [Colors.grey.shade600, Colors.grey.shade700],
                  )
                : _isWithdrawMode
                    ? const LinearGradient(
                        colors: [Color(0xFFD32F2F), Color(0xFFEF5350)],
                      )
                    : null,
            borderRadius: BorderRadius.circular(24),
            boxShadow: _busy
                ? []
                : [
                    BoxShadow(
                      color: (_isWithdrawMode ? Colors.red : const Color(0xFF3ED78A))
                          .withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: TextButton(
            onPressed: _busy ? null : _confirmAndSend,
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    _isWithdrawMode ? 'تأكيد سحب الألماس 💎' : dc.agentRechargeConfirmText,
                    style: GoogleFonts.tajawal(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      );
  }

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
