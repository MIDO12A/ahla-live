import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/cloudinary_service.dart';
import '../host_agency/data/agency_repository.dart';
import '../../core/supabase_compat.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/cache/encrypted_image_provider.dart';
import '../../services/dynamic_config_service.dart';

// ─────────────────────────────────────────────────────────────────────────────

/// شريط عنوان بوابة وكيل الشحن مع رصيد محفظة الوكالة متطابق 100% مع تطبيق Hayuki.
class AgentRechargeHeader extends StatelessWidget {
  const AgentRechargeHeader({
    super.key,
    required this.agencyGold,
    required this.onBack,
    this.agentPublicId,
    this.onResetPin,
    this.onTopup,
  });

  final int          agencyGold;
  final VoidCallback onBack;
  final String?      agentPublicId;
  final VoidCallback? onResetPin;
  final VoidCallback? onTopup;

  @override
  Widget build(BuildContext context) {
    final dc = DynamicConfigService();
    final headerBg = dc.agentRechargeHeaderBgImage.isNotEmpty
        ? dc.agentRechargeHeaderBgImage
        : 'assets/images/agency/ic_recharge_frag_bg.png';

    return Container(
      decoration: BoxDecoration(
        color: dc.agentRechargeHeaderColor,
        image: headerBg.isNotEmpty
            ? (headerBg.startsWith('http')
                ? DecorationImage(image: NetworkImage(headerBg), fit: BoxFit.cover)
                : DecorationImage(image: AssetImage(headerBg), fit: BoxFit.cover))
            : null,
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 16),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: Image.asset(
                  'assets/images/profile/back_white_2.webp',
                  width: 24,
                  height: 24,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.arrow_back_ios_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dc.agentRechargeTitle,
                      style: GoogleFonts.tajawal(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: dc.agentRechargeTextColor,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          dc.agentRechargeSubtitle,
                          style: GoogleFonts.tajawal(
                            fontSize: 11,
                            color: dc.agentRechargeAccentColor,
                          ),
                        ),
                        if (agentPublicId != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD770).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFFFD770).withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset(
                                  'assets/images/agency/union_id_ic.webp',
                                  width: 12,
                                  height: 12,
                                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'ID: $agentPublicId',
                                  style: GoogleFonts.tajawal(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFFFFD770),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF25252B).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFFFD770).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/agency/wallet_coin_bg.png',
                      width: 22,
                      height: 22,
                      errorBuilder: (_, __, ___) => Image.asset(
                        'assets/images/agency/mine_wallet_coin_bag_ic.webp',
                        width: 22,
                        height: 22,
                        errorBuilder: (_, __, ___) => const Text('🏅'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'رصيد الوكالة',
                          style: GoogleFonts.tajawal(
                            fontSize: 9,
                            color: Colors.white70,
                          ),
                        ),
                        Text(
                          _fmt(agencyGold),
                          style: GoogleFonts.tajawal(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFFFD770),
                          ),
                        ),
                      ],
                    ),
                    if (onTopup != null) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: onTopup,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFB800), Color(0xFFFF8F00)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFFB800).withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            'شحن',
                            style: GoogleFonts.tajawal(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onResetPin != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onResetPin,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25252B).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFFFD770).withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_reset_rounded,
                      color: Color(0xFFFFD770),
                      size: 20,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// زر الإجراء السريع في لوحة التحكم.
class AgentQuickActionBtn extends StatelessWidget {
  const AgentQuickActionBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String       icon;
  final String       label;
  final Color        color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(children: [
          Text(icon, style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 6),
          Text(label, style: GoogleFonts.tajawal(
            fontSize: 12, fontWeight: FontWeight.w800, color: color)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// نافذة تأكيد شحن أو سحب الكوينز.
class AgentRechargeConfirmDialog extends StatelessWidget {
  const AgentRechargeConfirmDialog({
    super.key,
    required this.user,
    required this.amount,
    this.isWithdraw = false,
  });

  final Map<String, dynamic> user;
  final int                  amount;
  final bool                 isWithdraw;

  @override
  Widget build(BuildContext context) {
    final name = user['display_name']?.toString() ?? 'مستخدم';
    final kid  = user['kayan_id']?.toString();
    final url  = user['avatar_url']?.toString();
    final primaryColor = isWithdraw ? Colors.redAccent : KayanBrandColors.logoPrimary;
    final secColor = isWithdraw ? Colors.deepOrange : const Color(0xFFFF6B00);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 60, height: 60,
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            shape: BoxShape.circle),
          child: Center(child: Text(isWithdraw ? '💎' : '🪙', style: const TextStyle(fontSize: 30)))),
        const SizedBox(height: 14),
        Text(isWithdraw ? 'طلب سحب ألماس الراتب' : 'تأكيد شحن كوينز',
          style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.w900,
            color: const Color(0xFF1a1a2e))),
        const SizedBox(height: 4),
        Text(isWithdraw ? 'سيتم إرسال طلب سحب إلى المستخدم، ولن يتم خصم الألماس إلا بعد موافقته' : 'هل أنت متأكد من إرسال الكوينز للمستخدم؟',
          textAlign: TextAlign.center,
          style: GoogleFonts.tajawal(fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 20),
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5FA),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06))),
          child: Row(children: [
            AgentAvatar(url: url, size: 52),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: GoogleFonts.tajawal(
                fontSize: 15, fontWeight: FontWeight.w900,
                color: const Color(0xFF1a1a2e))),
              if (kid != null) Text('# $kid',
                style: GoogleFonts.tajawal(fontSize: 12,
                  color: primaryColor,
                  fontWeight: FontWeight.w700)),
            ])),
          ])),
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryColor, secColor]),
            borderRadius: BorderRadius.circular(40)),
          child: Text(isWithdraw ? '💎  $amount ماسة (طلب سحب)' : '🪙  $amount كوين (شحن)',
            style: GoogleFonts.tajawal(
              fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white))),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              side: BorderSide(color: Colors.black.withValues(alpha: 0.15))),
            child: Text('إلغاء',
              style: GoogleFonts.tajawal(
                fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black54)))),
          const SizedBox(width: 12),
          Expanded(child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryColor, secColor]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                color: primaryColor.withValues(alpha: 0.4),
                blurRadius: 12, offset: const Offset(0, 4))]),
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: Text(
                isWithdraw
                    ? DynamicConfigService().agentRechargeWithdrawText
                    : DynamicConfigService().agentRechargeConfirmText,
                style: GoogleFonts.tajawal(
                  fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white))))),
        ]),
      ])),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// شارة إحصائية بسيطة (label + value + icon).
class AgentStatPill extends StatelessWidget {
  const AgentStatPill({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final String icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$icon $label',
        style: GoogleFonts.tajawal(color: Colors.white60, fontSize: 11)),
      const SizedBox(height: 2),
      Text(value,
        style: GoogleFonts.tajawal(
          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

/// صورة مستخدم دائرية مع fallback أيقونة.
class AgentAvatar extends StatelessWidget {
  const AgentAvatar({super.key, this.url, this.size = 44});

  final String? url;
  final double  size;

  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xFFF0F0F8),
      image: (url != null && url!.isNotEmpty)
          ? DecorationImage(image: EncryptedImageProvider(url!), fit: BoxFit.cover)
          : null,
    ),
    child: (url == null || url!.isEmpty)
        ? Center(child: Icon(Icons.person_rounded,
            size: size * 0.5, color: Colors.black26))
        : null,
  );
}

// ─────────────────────────────────────────────────────────────────────────────

/// نافذة نجاح تحويل الشحن مطابقة 100% مع تطبيق Hayuki الأصل
/// (hyk_frame_dialog_transfer_fiinish.xml)
class AgentRechargeSuccessDialog extends StatelessWidget {
  const AgentRechargeSuccessDialog({
    super.key,
    required this.orderId,
    required this.userId,
    required this.userName,
    required this.goldNum,
    required this.dateStr,
  });

  final String orderId;
  final String userId;
  final String userName;
  final int    goldNum;
  final String dateStr;

  static Future<void> show({
    required BuildContext context,
    required String orderId,
    required String userId,
    required String userName,
    required int goldNum,
    required String dateStr,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AgentRechargeSuccessDialog(
        orderId: orderId,
        userId: userId,
        userName: userName,
        goldNum: goldNum,
        dateStr: dateStr,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: const Color(0xFF141720),
          image: const DecorationImage(
            image: AssetImage('assets/images/agency/bg_nim_transfer.png'),
            fit: BoxFit.fill,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/agency/hyk_frame_ic_suuccess.png',
                width: 58,
                height: 58,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF95FF78),
                  size: 58,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'تم النقل بنجاح',
                style: GoogleFonts.tajawal(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF95FF78),
                ),
              ),
              const SizedBox(height: 16),
              _buildInfoRow('رقم المعاملة', orderId),
              const SizedBox(height: 6),
              _buildInfoRow('ID المستخدم', userId),
              const SizedBox(height: 6),
              _buildInfoRow('اسم المستخدم', userName),
              const SizedBox(height: 6),
              _buildInfoRow('عدد العملات', '$goldNum 🪙'),
              const SizedBox(height: 6),
              _buildInfoRow('التاريخ', dateStr),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 170,
                  height: 44,
                  decoration: BoxDecoration(
                    image: const DecorationImage(
                      image: AssetImage('assets/images/agency/hyk_frame_bg_transfer_sure_enabled.png'),
                      fit: BoxFit.fill,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3ED78A), Color(0xFF22B86E)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3ED78A).withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      'تأكيد',
                      style: GoogleFonts.tajawal(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF3ED78A).withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.tajawal(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFA1A1A1),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.tajawal(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: const Color(0xFFFFFDF8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// نافذة طلب تعبئة رصيد الوكالة (Agency Top-Up Modal)
class AgentTopupDialog extends StatefulWidget {
  const AgentTopupDialog({super.key, required this.onSuccess});
  final VoidCallback onSuccess;

  static Future<void> show(BuildContext context, {required VoidCallback onSuccess}) {
    if (DynamicConfigService().isReviewMode) {
      return Future.value();
    }
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AgentTopupDialog(onSuccess: onSuccess),
    );
  }

  @override
  State<AgentTopupDialog> createState() => _AgentTopupDialogState();
}

class _AgentTopupDialogState extends State<AgentTopupDialog> {
  final _amountCtrl = TextEditingController();
  final _senderNameCtrl = TextEditingController();
  final _senderPhoneCtrl = TextEditingController();
  final _txidCtrl = TextEditingController();

  String _paymentMethod = 'vodafone_cash';
  File? _proofImage;
  bool _uploading = false;
  bool _loadingConfig = true;

  Map<String, dynamic> _gateways = {};

  @override
  void initState() {
    super.initState();
    _loadGateways();
  }

  Future<void> _loadGateways() async {
    try {
      final res = await Supabase.instance.client
          .from('app_config')
          .select('value')
          .eq('key', 'recharge_gateways')
          .maybeSingle();

      if (res != null && res['value'] is Map) {
        setState(() {
          _gateways = Map<String, dynamic>.from(res['value']);
          _loadingConfig = false;
        });
        return;
      }
    } catch (_) {}

    setState(() {
      _gateways = {
        'vodafoneCashNumber': '01000000000',
        'vodafoneCashName': 'الإدارة الرسمية للوكلاء',
        'binanceAddress': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        'binanceId': '84920193',
        'instapayAddress': 'payment@instapay',
      };
      _loadingConfig = false;
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _senderNameCtrl.dispose();
    _senderPhoneCtrl.dispose();
    _txidCtrl.dispose();
    super.dispose();
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم نسخ $label بنجاح ✅', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF2E7D32),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xFile != null) {
      setState(() => _proofImage = File(xFile.path));
    }
  }

  Future<void> _submit() async {
    final amountText = _amountCtrl.text.trim();
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      _snack('يرجى إدخال مبلغ التحويل بشكل صحيح');
      return;
    }
    if (_proofImage == null) {
      _snack('يرجى إرفاق صورة إشعار / إيصال التحويل');
      return;
    }

    setState(() => _uploading = true);
    try {
      // 1. رفع صورة الإشعار
      String proofUrl = '';
      try {
        proofUrl = await CloudinaryService().uploadImage(_proofImage!);
      } catch (e) {
        debugPrint('[AgentTopup] upload proof error: $e');
      }

      if (proofUrl.isEmpty) {
        // Fallback: حاول الرفع عبر Supabase storage
        try {
          final fileName = 'proof_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final bytes = await _proofImage!.readAsBytes();
          await Supabase.instance.client.storage
              .from('receipts')
              .uploadBinary(fileName, bytes);
          proofUrl = Supabase.instance.client.storage.from('receipts').getPublicUrl(fileName);
        } catch (_) {}
      }

      final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
      final userRow = await Supabase.instance.client.from('users').select('name').eq('id', uid).maybeSingle();
      final agentName = userRow?['name']?.toString() ?? 'وكيل شحن';

      // 1 USD = 1000 Coins تقريباً كمعدل افتراضي
      final coinsEst = (amount * 1000).toInt();

      final res = await AgencyRepository.submitAgentTopupRequest(
        agentUid: uid,
        agentName: agentName,
        amountUsd: amount,
        coins: coinsEst,
        paymentMethod: _paymentMethod,
        proofImageUrl: proofUrl,
        txid: _txidCtrl.text.trim(),
        senderName: _senderNameCtrl.text.trim(),
        senderPhone: _senderPhoneCtrl.text.trim(),
      );

      if (!mounted) return;
      setState(() => _uploading = false);

      if (res['success'] == true) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF00E5A0), size: 54),
              const SizedBox(height: 14),
              Text('تم إرسال طلب التعبئة بنجاح! 🚀',
                  style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                'تم استلام طلبك وإرفاق الإيصال للمراجعة.\nسيتم إضافة رصيد الكوينز لمحفظة وكالتك فور تدقيق التحويل من الإدارة.',
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB800),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text('حسناً', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
        );
        widget.onSuccess();
      } else {
        _snack(res['message']?.toString() ?? 'فشل إرسال الطلب');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        _snack('حدث خطأ: $e');
      }
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: GoogleFonts.tajawal())));

  @override
  Widget build(BuildContext context) {
    if (DynamicConfigService().isReviewMode) {
      return const SizedBox.shrink();
    }
    final vfNumber = _gateways['vodafoneCashNumber']?.toString() ?? '01000000000';
    final binanceAddr = _gateways['binanceAddress']?.toString() ?? 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
    final binanceId = _gateways['binanceId']?.toString() ?? '84920193';
    final instapay = _gateways['instapayAddress']?.toString() ?? 'payment@instapay';

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141722),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
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
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFFFB800), size: 24),
                const SizedBox(width: 8),
                Text(
                  'طلب تعبئة رصيد الوكالة',
                  style: GoogleFonts.tajawal(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'حول المبلغ لحساب الإدارة الرسمي ثم ارفع الإيصال لشحن الكوينز فوراً',
              style: GoogleFonts.tajawal(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),

            // بطاقة بيانات التحويل
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFB800).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('حسابات الإدارة الرسمية للإيداع:',
                      style: GoogleFonts.tajawal(color: const Color(0xFFFFB800), fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 10),
                  _buildCopyTile('فودافون كاش / محافظ مصر', vfNumber, Icons.phone_android_rounded),
                  const SizedBox(height: 6),
                  _buildCopyTile('Binance USDT (TRC-20)', binanceAddr, Icons.currency_bitcoin_rounded),
                  const SizedBox(height: 6),
                  _buildCopyTile('Binance Pay ID', binanceId, Icons.badge_rounded),
                  const SizedBox(height: 6),
                  _buildCopyTile('InstaPay إنستاباي', instapay, Icons.send_to_mobile_rounded),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // طريقة الدفع المستخدمة
            Text('طريقة التحويل المستخدمة',
                style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _paymentMethod,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1E2230),
                  items: const [
                    DropdownMenuItem(value: 'vodafone_cash', child: Text('فودافون كاش / محافظ إلكترونية', style: TextStyle(color: Colors.white, fontSize: 13))),
                    DropdownMenuItem(value: 'binance_usdt', child: Text('Binance USDT (TRC-20)', style: TextStyle(color: Colors.white, fontSize: 13))),
                    DropdownMenuItem(value: 'instapay', child: Text('إنستاباي InstaPay', style: TextStyle(color: Colors.white, fontSize: 13))),
                    DropdownMenuItem(value: 'bank_transfer', child: Text('تحويل بنكي / IBAN', style: TextStyle(color: Colors.white, fontSize: 13))),
                  ],
                  onChanged: (v) => setState(() => _paymentMethod = v ?? 'vodafone_cash'),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // المبلغ
            Text('المبلغ المحول (\$ / جنيه)',
                style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                hintText: 'مثال: 50 أو 1000',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),

            // اسم المحول ورقم الهاتف
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _senderNameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    hintText: 'اسم المحوّل',
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _txidCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    hintText: 'رقم العملية / TXID',
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 14),

            // صورة الإشعار
            Text('صورة إشعار / إيصال التحويل',
                style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _proofImage != null ? const Color(0xFF00E5A0) : Colors.white24,
                    style: BorderStyle.solid,
                  ),
                ),
                child: _proofImage != null
                    ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.check_circle_rounded, color: Color(0xFF00E5A0)),
                        const SizedBox(width: 8),
                        Text('تم اختيار الصورة بنجاح (انقر للتغيير)',
                            style: GoogleFonts.tajawal(color: const Color(0xFF00E5A0), fontSize: 12, fontWeight: FontWeight.bold)),
                      ])
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.add_photo_alternate_rounded, color: Color(0xFFFFB800), size: 28),
                        const SizedBox(height: 4),
                        Text('انقر هنا لرفع لقطة الشاشة من المعرض',
                            style: GoogleFonts.tajawal(color: Colors.white54, fontSize: 12)),
                      ]),
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _uploading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB800),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _uploading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : Text('إرسال طلب التعبئة للإدارة 🚀',
                        style: GoogleFonts.tajawal(fontSize: 15, fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCopyTile(String title, String val, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            Text(val, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.copy_rounded, color: Color(0xFFFFB800), size: 18),
          onPressed: () => _copy(val, title),
        ),
      ],
    );
  }
}
