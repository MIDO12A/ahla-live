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
//  PIN Setup Screen — يظهر عند أول استخدام قبل إعداد PIN
// ══════════════════════════════════════════════════════════════════════
class AgentPinSetupScreen extends StatefulWidget {
  const AgentPinSetupScreen({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  State<AgentPinSetupScreen> createState() => _AgentPinSetupScreenState();
}

class _AgentPinSetupScreenState extends State<AgentPinSetupScreen> {
  final List<TextEditingController> _ctrls =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(4, (_) => FocusNode());
  bool _busy = false;
  bool _confirm = false;
  String _firstPin = '';

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _pin => _ctrls.map((c) => c.text).join();

  void _onDigit(int idx, String val) {
    if (val.isNotEmpty && idx < 3) {
      _nodes[idx + 1].requestFocus();
    }
    setState(() {});
    if (_pin.length == 4) {
      _onPinComplete();
    }
  }

  void _onPinComplete() {
    final pin = _pin;
    if (!_confirm) {
      setState(() {
        _firstPin = pin;
        _confirm = true;
      });
      for (final c in _ctrls) {
        c.clear();
      }
      _nodes[0].requestFocus();
    } else {
      if (pin == _firstPin) {
        _savePin(pin);
      } else {
        for (final c in _ctrls) {
          c.clear();
        }
        _nodes[0].requestFocus();
        setState(() {
          _confirm = false;
          _firstPin = '';
        });
        _showErr('PIN غير متطابق، حاول مجدداً');
      }
    }
  }

  Future<void> _savePin(String pin) async {
    setState(() => _busy = true);
    try {
      final res = await Supabase.instance.client
          .rpc('agent_set_pin', params: {'p_pin': pin});
      if (!mounted) return;
      if (res is Map && res['ok'] == true) {
        widget.onDone();
      } else {
        _showErr(res?['error']?.toString() ?? 'خطأ في حفظ PIN');
        setState(() {
          _busy = false;
          _confirm = false;
          _firstPin = '';
        });
        for (final c in _ctrls) {
          c.clear();
        }
      }
    } catch (e) {
      debugPrint('[pin_setup] $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showErr(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg,
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
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
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(children: [
              const Spacer(),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                    color: KayanBrandColors.logoPrimary.withValues(alpha: 0.15),
                    shape: BoxShape.circle),
                child:
                    const Center(child: Text('🔐', style: TextStyle(fontSize: 40))),
              ),
              const SizedBox(height: 24),
              Text(
                _confirm ? 'أكّد رمز PIN' : 'أنشئ رمز PIN',
                style: GoogleFonts.tajawal(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                _confirm
                    ? 'أعد إدخال رمز PIN للتأكيد'
                    : 'رمز 4 أرقام يُطلب قبل كل شحن',
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(fontSize: 13, color: Colors.white54),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  4,
                  (i) => Container(
                    width: 56,
                    height: 64,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: _nodes[i].hasFocus
                              ? KayanBrandColors.logoPrimary
                              : Colors.white24,
                          width: 1.5),
                    ),
                    child: TextField(
                      controller: _ctrls[i],
                      focusNode: _nodes[i],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 1,
                      obscureText: true,
                      obscuringCharacter: '●',
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: GoogleFonts.tajawal(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white),
                      decoration: const InputDecoration(
                          counterText: '', border: InputBorder.none),
                      onChanged: (v) => _onDigit(i, v),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (_busy)
                const CircularProgressIndicator(color: Color(0xFFFFB800))
              else
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _pin.length == 4 ? _onPinComplete : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KayanBrandColors.logoPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('متابعة',
                        style: GoogleFonts.tajawal(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                  ),
                ),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════
//  PIN Verify Dialog — يظهر قبل كل عملية شحن
// ══════════════════════════════════════════════════════════════════════
class _AgentPinVerifyDialog extends StatefulWidget {
  const _AgentPinVerifyDialog();
  @override
  State<_AgentPinVerifyDialog> createState() => _AgentPinVerifyDialogState();
}

class _AgentPinVerifyDialogState extends State<_AgentPinVerifyDialog> {
  final List<TextEditingController> _ctrls =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(4, (_) => FocusNode());
  bool _busy = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _nodes[0].requestFocus());
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _pin => _ctrls.map((c) => c.text).join();

  void _onDigit(int idx, String val) {
    setState(() => _error = false);
    if (val.isNotEmpty && idx < 3) {
      _nodes[idx + 1].requestFocus();
    }
    if (_pin.length == 4) {
      _verify();
    }
  }

  Future<void> _verify() async {
    setState(() => _busy = true);
    try {
      final ok = await Supabase.instance.client
          .rpc('agent_verify_pin', params: {'p_pin': _pin});
      if (!mounted) return;
      if (ok == true) {
        Navigator.of(context).pop(true);
      } else {
        for (final c in _ctrls) {
          c.clear();
        }
        _nodes[0].requestFocus();
        setState(() {
          _busy = false;
          _error = true;
        });
      }
    } catch (e) {
      debugPrint('[pin_verify] $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: const Color(0xFF1a0a2e),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🔐', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text('أدخل رمز PIN',
                style: GoogleFonts.tajawal(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
            const SizedBox(height: 6),
            Text('يُطلب قبل كل عملية شحن',
                textAlign: TextAlign.center,
                style:
                    GoogleFonts.tajawal(fontSize: 12, color: Colors.white54)),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                4,
                (i) => Container(
                  width: 52,
                  height: 60,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _error
                            ? Colors.red
                            : _nodes[i].hasFocus
                                ? KayanBrandColors.logoPrimary
                                : Colors.white24,
                        width: 1.5),
                  ),
                  child: TextField(
                    controller: _ctrls[i],
                    focusNode: _nodes[i],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    obscureText: true,
                    obscuringCharacter: '●',
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: GoogleFonts.tajawal(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white),
                    decoration: const InputDecoration(
                        counterText: '', border: InputBorder.none),
                    onChanged: (v) => _onDigit(i, v),
                  ),
                ),
              ),
            ),
            if (_error) ...[
              const SizedBox(height: 12),
              Text('رمز PIN خاطئ',
                  style: GoogleFonts.tajawal(
                      fontSize: 13,
                      color: Colors.red,
                      fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 16),
            if (_busy)
              const CircularProgressIndicator(color: Color(0xFFFFB800))
            else ...[
              TextButton.icon(
                onPressed: () async {
                  final ok = await AgentResetPinDialog.show(context);
                  if (ok == true && context.mounted) {
                    Navigator.of(context).pop(true);
                  }
                },
                icon: const Icon(Icons.lock_reset_rounded, size: 18, color: Color(0xFFFFB800)),
                label: Text(
                  'إعادة تعيين رمز PIN',
                  style: GoogleFonts.tajawal(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFFFB800),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('إلغاء',
                    style: GoogleFonts.tajawal(
                        fontSize: 14, color: Colors.white54)),
              ),
            ],
          ]),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════
//  Agent Reset PIN Dialog — نافذة إعادة تعيين رمز PIN
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

class _AgentResetPinDialogState extends State<AgentResetPinDialog> {
  final List<TextEditingController> _newPinCtrls =
      List.generate(4, (_) => TextEditingController());
  final List<TextEditingController> _confirmPinCtrls =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _newPinNodes = List.generate(4, (_) => FocusNode());
  final List<FocusNode> _confirmPinNodes = List.generate(4, (_) => FocusNode());
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _newPinNodes[0].requestFocus());
  }

  @override
  void dispose() {
    for (final c in _newPinCtrls) {
      c.dispose();
    }
    for (final c in _confirmPinCtrls) {
      c.dispose();
    }
    for (final n in _newPinNodes) {
      n.dispose();
    }
    for (final n in _confirmPinNodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _newPin => _newPinCtrls.map((c) => c.text).join();
  String get _confirmPin => _confirmPinCtrls.map((c) => c.text).join();

  void _onDigit(int idx, String val, bool isConfirm) {
    setState(() => _error = null);
    final nodes = isConfirm ? _confirmPinNodes : _newPinNodes;
    if (val.isNotEmpty && idx < 3) {
      nodes[idx + 1].requestFocus();
    } else if (val.isNotEmpty && idx == 3 && !isConfirm) {
      _confirmPinNodes[0].requestFocus();
    }
  }

  Future<void> _submit() async {
    final pin = _newPin;
    final confirm = _confirmPin;
    if (pin.length != 4) {
      setState(() => _error = 'يرجى إدخال رمز PIN المكون من 4 أرقام');
      return;
    }
    if (confirm != pin) {
      setState(() => _error = 'رمز التأكيد غير متطابق مع الرمز الجديد');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final res = await Supabase.instance.client
          .rpc('agent_set_pin', params: {'p_pin': pin});
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('users').doc(uid).set(
          {'agent_pin': pin},
          SetOptions(merge: true),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تعيين رمز PIN الجديد بنجاح ✅',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
      widget.onSuccess?.call();
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('[reset_pin] $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'حدث خطأ أثناء حفظ الرمز: $e';
        });
      }
    }
  }

  Widget _buildPinRow(List<TextEditingController> ctrls, List<FocusNode> nodes, bool isConfirm) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        4,
        (i) => Container(
          width: 48,
          height: 54,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: nodes[i].hasFocus
                  ? const Color(0xFFFFB800)
                  : Colors.white24,
              width: 1.5,
            ),
          ),
          child: TextField(
            controller: ctrls[i],
            focusNode: nodes[i],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 1,
            obscureText: true,
            obscuringCharacter: '●',
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: GoogleFonts.tajawal(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
            decoration: const InputDecoration(counterText: '', border: InputBorder.none),
            onChanged: (v) => _onDigit(i, v, isConfirm),
          ),
        ),
      ),
    );
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
                  'إعادة تعيين رمز PIN',
                  style: GoogleFonts.tajawal(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'أدخل رمز PIN الجديد المكون من 4 أرقام',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(fontSize: 12, color: Colors.white54),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'رمز PIN الجديد:',
                    style: GoogleFonts.tajawal(fontSize: 12, color: const Color(0xFFFFD770), fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                _buildPinRow(_newPinCtrls, _newPinNodes, false),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'تأكيد رمز PIN الجديد:',
                    style: GoogleFonts.tajawal(fontSize: 12, color: const Color(0xFFFFD770), fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                _buildPinRow(_confirmPinCtrls, _confirmPinNodes, true),
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
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: Text(
                            'حفظ الرمز',
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
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
      final intId = int.tryParse(q);
      final List<Map<String, dynamic>> results = [];
      final Set<String> seenUids = {};

      void addDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
        if (!doc.exists || doc.data() == null) return;
        final uid = doc.id;
        if (seenUids.contains(uid)) return;
        seenUids.add(uid);
        final d = doc.data()!;
        results.add({
          'id': uid,
          'uid': uid,
          'display_name': d['name'] ?? d['nickname'] ?? d['display_name'] ?? 'مستخدم',
          'avatar_url': d['avatar'] ?? d['avatar_url'] ?? d['photo_url'] ?? d['photoUrl'] ?? '',
          'kayan_id': d['custom_id']?.toString() ??
              d['customId']?.toString() ??
              d['display_id']?.toString() ??
              (uid.length > 8 ? uid.substring(0, 8) : uid),
          'coins': (d['coins'] as num?)?.toInt() ?? 0,
          'diamonds': (d['diamonds'] as num?)?.toInt() ?? 0,
        });
      }

      // 1. Check exact custom_id (string)
      try {
        final snap1 = await db.collection('users').where('custom_id', isEqualTo: q).limit(5).get();
        for (final doc in snap1.docs) {
          addDoc(doc);
        }
      } catch (_) {}

      // 2. Check exact custom_id (int)
      if (intId != null && results.isEmpty) {
        try {
          final snap1Int = await db.collection('users').where('custom_id', isEqualTo: intId).limit(5).get();
          for (final doc in snap1Int.docs) {
            addDoc(doc);
          }
        } catch (_) {}
      }

      // 3. Check customId (camelCase)
      if (results.isEmpty) {
        try {
          final snap2 = await db.collection('users').where('customId', isEqualTo: q).limit(5).get();
          for (final doc in snap2.docs) {
            addDoc(doc);
          }
        } catch (_) {}
      }
      if (intId != null && results.isEmpty) {
        try {
          final snap2Int = await db.collection('users').where('customId', isEqualTo: intId).limit(5).get();
          for (final doc in snap2Int.docs) {
            addDoc(doc);
          }
        } catch (_) {}
      }

      // 4. Check display_id
      if (results.isEmpty) {
        try {
          final snap3 = await db.collection('users').where('display_id', isEqualTo: q).limit(5).get();
          for (final doc in snap3.docs) {
            addDoc(doc);
          }
        } catch (_) {}
      }

      // 5. Direct doc lookup by UID
      if (results.isEmpty) {
        try {
          final doc = await db.collection('users').doc(q).get();
          if (doc.exists) {
            addDoc(doc);
          }
        } catch (_) {}
      }

      // 6. Name / Nickname search prefix
      if (results.isEmpty && q.length >= 2) {
        try {
          final nameSnap = await db.collection('users')
              .where('name', isGreaterThanOrEqualTo: q)
              .where('name', isLessThanOrEqualTo: '$q\uf8ff')
              .limit(5)
              .get();
          for (final doc in nameSnap.docs) {
            addDoc(doc);
          }
        } catch (_) {}

        if (results.isEmpty) {
          try {
            final nickSnap = await db.collection('users')
                .where('nickname', isGreaterThanOrEqualTo: q)
                .where('nickname', isLessThanOrEqualTo: '$q\uf8ff')
                .limit(5)
                .get();
            for (final doc in nickSnap.docs) {
              addDoc(doc);
            }
          } catch (_) {}
        }
      }

      // 7. General search fallback: scan recent users in memory
      if (results.isEmpty) {
        try {
          final allSnap = await db.collection('users').limit(60).get();
          final lowerQ = q.toLowerCase();
          for (final doc in allSnap.docs) {
            final d = doc.data();
            final cid = (d['custom_id'] ?? d['customId'] ?? d['display_id'] ?? '').toString().toLowerCase();
            final uid = doc.id.toLowerCase();
            final name = (d['name'] ?? d['nickname'] ?? d['display_name'] ?? '').toString().toLowerCase();
            if (cid.contains(lowerQ) || uid.contains(lowerQ) || name.contains(lowerQ)) {
              addDoc(doc);
              if (results.length >= 5) break;
            }
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (e) {
      debugPrint('[recharge_tab] search error: $e');
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
      // وضع السحب: التحقق من رصيد المستخدم
      final userCoins = (user['coins'] as num?)?.toInt() ?? 0;
      if (amount > userCoins) {
        _showSnack('رصيد المستخدم غير كافٍ للسحب (رصيده الحالي: $userCoins كوين)');
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
    final agentUid = FirebaseAuth.instance.currentUser?.uid;
    if (agentUid == null || targetUid.isEmpty) {
      setState(() => _busy = false);
      _showSnack('خطأ: تعذر التعرف على بيانات الحساب');
      return;
    }

    try {
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
      final agentRef = db.collection('users').doc(agentUid);
      final targetRef = db.collection('users').doc(targetUid);

      final success = await db.runTransaction<bool>((txn) async {
        final agentSnap = await txn.get(agentRef);
        final targetSnap = await txn.get(targetRef);
        if (!agentSnap.exists || !targetSnap.exists) return false;

        final agentCoins = (agentSnap.data()?['coins'] as num?)?.toInt() ?? 0;
        if (agentCoins < amount) return false;

        final targetCoins = (targetSnap.data()?['coins'] as num?)?.toInt() ?? 0;

        txn.update(agentRef, {'coins': agentCoins - amount});
        txn.update(targetRef, {'coins': targetCoins + amount});

        final txRef = db.collection('agent_recharge_transactions').doc();
        txn.set(txRef, {
          'agent_id': agentUid,
          'type': 'recharge',
          'recipient_uid': targetUid,
          'recipient_display_name': user['display_name'] ?? 'مستخدم',
          'recipient_avatar_url': user['avatar_url'] ?? '',
          'recipient_kayan_id': user['kayan_id'] ?? '',
          'gold_amount': amount,
          'status': 'completed',
          'created_at': DateTime.now().toIso8601String(),
          'timestamp': FieldValue.serverTimestamp(),
        });

        return true;
      });

      if (!mounted) return;
      setState(() => _busy = false);

      if (success) {
        FirebaseService().sendNotification(
          uid: targetUid,
          type: 'recharge',
          title: 'شحن رصيد كوينز 🪙',
          body: 'تم شحن $amount كوين لحسابك بنجاح من وكيل الشحن.',
          data: {'amount': amount, 'agent_id': agentUid},
        );

        _showSnack('✅ تم شحن $amount كوين للمستخدم بنجاح');
        _clearSelected();
        widget.onSuccess();
      } else {
        _showSnack('فشلت العملية: رصيد الوكيل غير كافٍ');
      }
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
    final agentUid = FirebaseAuth.instance.currentUser?.uid;
    if (agentUid == null || targetUid.isEmpty) {
      setState(() => _busy = false);
      _showSnack('خطأ: تعذر التعرف على بيانات الحساب');
      return;
    }

    try {
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
      final agentRef = db.collection('users').doc(agentUid);
      final targetRef = db.collection('users').doc(targetUid);

      final success = await db.runTransaction<bool>((txn) async {
        final agentSnap = await txn.get(agentRef);
        final targetSnap = await txn.get(targetRef);
        if (!agentSnap.exists || !targetSnap.exists) return false;

        final targetCoins = (targetSnap.data()?['coins'] as num?)?.toInt() ?? 0;
        if (targetCoins < amount) return false;

        final agentCoins = (agentSnap.data()?['coins'] as num?)?.toInt() ?? 0;

        txn.update(targetRef, {'coins': targetCoins - amount});
        txn.update(agentRef, {'coins': agentCoins + amount});

        final txRef = db.collection('agent_recharge_transactions').doc();
        txn.set(txRef, {
          'agent_id': agentUid,
          'type': 'withdraw',
          'recipient_uid': targetUid,
          'recipient_display_name': user['display_name'] ?? 'مستخدم',
          'recipient_avatar_url': user['avatar_url'] ?? '',
          'recipient_kayan_id': user['kayan_id'] ?? '',
          'gold_amount': amount,
          'status': 'completed',
          'created_at': DateTime.now().toIso8601String(),
          'timestamp': FieldValue.serverTimestamp(),
        });

        return true;
      });

      if (!mounted) return;
      setState(() => _busy = false);

      if (success) {
        FirebaseService().sendNotification(
          uid: targetUid,
          type: 'withdraw',
          title: 'سحب كوينز 🪙',
          body: 'قام وكيل الشحن بسحب $amount كوين من رصيدك.',
          data: {'amount': amount, 'agent_id': agentUid},
        );

        _showSnack('✅ تم سحب $amount كوين من المستخدم بنجاح');
        _clearSelected();
        widget.onSuccess();
      } else {
        _showSnack('فشلت العملية: رصيد المستخدم غير كافٍ');
      }
    } catch (e) {
      debugPrint('[withdraw] error: $e');
      if (mounted) {
        setState(() => _busy = false);
        _showSnack('حدث خطأ أثناء السحب: $e');
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
                    '🔴 سحب كوينز من المستخدم',
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
                    Text(_isWithdrawMode ? 'المستخدم المطلوب سحب الكوينز منه' : 'المستخدم المطلوب شحن رصيده',
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
            hintText: _isWithdrawMode ? 'أدخل عدد الكوينز المراد سحبها' : 'أدخل عدد الكوينز المراد شحنها',
            hintStyle:
                GoogleFonts.tajawal(fontSize: 15, color: Colors.black38),
            prefixIcon: const Padding(
                padding: EdgeInsets.all(14),
                child: Text('🪙', style: TextStyle(fontSize: 22))),
            suffixText: 'كوين',
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
                    _isWithdrawMode ? 'سحب الكوينز الآن 📤' : 'شحن الكوينز الآن 🚀',
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
