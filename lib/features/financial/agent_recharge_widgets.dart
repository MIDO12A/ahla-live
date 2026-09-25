import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/cache/encrypted_image_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────

/// شريط عنوان بوابة وكيل الشحن مع رصيد محفظة الوكالة متطابق 100% مع تطبيق الأصل.
import '../../services/dynamic_config_service.dart';

// ─────────────────────────────────────────────────────────────────────────────

/// شريط عنوان بوابة وكيل الشحن مع رصيد محفظة الوكالة متطابق 100% مع تطبيق الأصل.
class AgentRechargeHeader extends StatelessWidget {
  const AgentRechargeHeader({
    super.key,
    required this.agencyGold,
    required this.onBack,
    this.agentPublicId,
    this.onResetPin,
  });

  final int          agencyGold;
  final VoidCallback onBack;
  final String?      agentPublicId;
  final VoidCallback? onResetPin;

  @override
  Widget build(BuildContext context) {
    final dc = DynamicConfigService();
    final headerBg = dc.agentRechargeHeaderBgImage.isNotEmpty
        ? dc.agentRechargeHeaderBgImage
        : 'assets/images/agency/mine_wallet_header_bg.webp';

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
                      'وكالة الشحن',
                      style: GoogleFonts.tajawal(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          'وكيل معتمد',
                          style: GoogleFonts.tajawal(
                            fontSize: 11,
                            color: const Color(0xFFFFD770),
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                      'assets/images/agency/mine_wallet_coin_bag_ic.webp',
                      width: 24,
                      height: 24,
                      errorBuilder: (_, __, ___) => const Text('🏅'),
                    ),
                    const SizedBox(width: 6),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'محفظة الوكالة',
                          style: GoogleFonts.tajawal(
                            fontSize: 9,
                            color: Colors.white70,
                          ),
                        ),
                        Text(
                          _fmt(agencyGold),
                          style: GoogleFonts.tajawal(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFFFD770),
                          ),
                        ),
                      ],
                    ),
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
              child: Text(isWithdraw ? 'إرسال طلب السحب 📤' : 'تأكيد الشحن ✅',
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
