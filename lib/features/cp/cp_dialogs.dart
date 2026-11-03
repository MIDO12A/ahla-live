import 'package:flutter/material.dart';
import '../../core/cache/encrypted_image_provider.dart';
import '../../config/r.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import 'package:zero/core/dtext.dart';

/// Authentic CP Proposal Dialog matching ic_send_invitation_bg.webp & original flow
Future<Map<String, dynamic>?> showSendRelationshipInvitationDialog(
  BuildContext context, {
  required String receiverName,
  required String receiverAvatar,
  String receiverUid = '',
}) {
  final messageController = TextEditingController();
  int selectedRingIndex = 0;

  final List<Map<String, dynamic>> rings = [
    {
      'id': 'ring_1',
      'name': 'خاتم الفضة',
      'price': 9999,
      'asset': 'assets/cp/cp1.webp',
    },
    {
      'id': 'ring_2',
      'name': 'خاتم الياقوت',
      'price': 19999,
      'asset': 'assets/cp/cp2.webp',
    },
    {
      'id': 'ring_3',
      'name': 'خاتم الماس الملكي',
      'price': 59999,
      'asset': 'assets/cp/cp3.webp',
    },
  ];

  final currentUser = Provider.of<UserProvider>(context, listen: false).currentUser;
  final myAvatar = currentUser?.photoUrl ?? '';
  final myName = currentUser?.name ?? 'أنا';
  final myCoins = currentUser?.coins ?? 0;

  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          final isAr = Localizations.localeOf(context).languageCode == 'ar';
          final selectedRing = rings[selectedRingIndex];

          return Directionality(
            textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.82,
              decoration: const BoxDecoration(
                color: Color(0xFF280B17),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Stack(
                children: [
                  // Top decoration background: ic_send_invitation_bg.webp
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 220,
                    child: Image.asset(
                      'assets/cp/ic_send_invitation_bg.webp',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),

                  // Close button
                  Positioned(
                    top: 14,
                    left: isAr ? null : 16,
                    right: isAr ? 16 : null,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white70, size: 20),
                      ),
                    ),
                  ),

                  // Content
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: Column(
                      children: [
                        DText(
                          isAr ? 'دعوة ارتباط CP' : 'CP Proposal',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 18),

                        // ── Couple Connection: Start Frame + Cord + End Frame ──
                        SizedBox(
                          height: 100,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Love Cord connecting the frames
                              Positioned(
                                left: 60,
                                right: 60,
                                child: Image.asset(
                                  'assets/cp/ic_send_invitation_cord.png',
                                  height: 24,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Container(height: 2, color: Colors.pinkAccent),
                                ),
                              ),

                              // Start User Frame (Current User)
                              Positioned(
                                right: isAr ? 20 : null,
                                left: isAr ? null : 20,
                                child: Column(
                                  children: [
                                    Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        CircleAvatar(
                                          radius: 26,
                                          backgroundColor: Colors.white12,
                                          backgroundImage: myAvatar.isNotEmpty ? EncryptedImageProvider(myAvatar) : null,
                                          child: myAvatar.isEmpty ? const Icon(Icons.person, color: Colors.white54) : null,
                                        ),
                                        Image.asset(
                                          'assets/cp/ic_send_invitation_start_frame.webp',
                                          width: 72,
                                          height: 72,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    DText(
                                      myName,
                                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              ),

                              // End User Frame (Partner/Receiver)
                              Positioned(
                                left: isAr ? 20 : null,
                                right: isAr ? null : 20,
                                child: Column(
                                  children: [
                                    Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        CircleAvatar(
                                          radius: 26,
                                          backgroundColor: Colors.white12,
                                          backgroundImage: receiverAvatar.isNotEmpty ? EncryptedImageProvider(receiverAvatar) : null,
                                          child: receiverAvatar.isEmpty ? const Icon(Icons.person, color: Colors.white54) : null,
                                        ),
                                        Image.asset(
                                          'assets/cp/ic_send_invitation_end_frame.webp',
                                          width: 72,
                                          height: 72,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    DText(
                                      receiverName,
                                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ── Choose Gift Title: ic_send_invitation_choose_gift_title_frame.png ──
                        Image.asset(
                          'assets/cp/ic_send_invitation_choose_gift_title_frame.png',
                          height: 26,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => DText(
                            isAr ? 'اختر رمز وخاتم الحب' : 'Choose Love Token',
                            style: const TextStyle(color: Color(0xFFFFB565), fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // ── Rings Grid / Selector ──
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(rings.length, (idx) {
                            final r = rings[idx];
                            final isSel = selectedRingIndex == idx;
                            return GestureDetector(
                              onTap: () => setState(() => selectedRingIndex = idx),
                              child: Container(
                                width: 96,
                                height: 110,
                                margin: const EdgeInsets.symmetric(horizontal: 6),
                                decoration: BoxDecoration(
                                  image: DecorationImage(
                                    image: AssetImage(
                                      isSel
                                          ? 'assets/cp/ic_send_invitation_gift_bg_selected.webp'
                                          : 'assets/cp/ic_send_invitation_gift_bg_unselected.webp',
                                    ),
                                    fit: BoxFit.fill,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset(
                                      r['asset'],
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.favorite, color: Colors.pink, size: 36),
                                    ),
                                    const SizedBox(height: 4),
                                    DText(
                                      r['name'],
                                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Image.asset('assets/cp/ic_coin.webp', width: 12, height: 12, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                                        const SizedBox(width: 3),
                                        DText(
                                          '${r['price']}',
                                          style: const TextStyle(color: Color(0xFFFFD700), fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),

                        const SizedBox(height: 16),

                        // ── Message Input ──
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0x33FFFFFF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0x33FFB565)),
                          ),
                          child: TextField(
                            controller: messageController,
                            maxLength: 60,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: isAr ? 'أخبره بشيء جميل يعبر عن مشاعرك...' : 'Write your romantic proposal note...',
                              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                              border: InputBorder.none,
                              counterStyle: const TextStyle(color: Colors.white38, fontSize: 10),
                            ),
                          ),
                        ),

                        const Spacer(),

                        // ── Bottom Action Panel: Coins + Send Button ──
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    DText(
                                      isAr ? 'رصيدي:' : 'Balance:',
                                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                                    ),
                                    Row(
                                      children: [
                                        Image.asset('assets/cp/ic_coin.webp', width: 14, height: 14, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                                        const SizedBox(width: 4),
                                        DText(
                                          R.formatCoins(myCoins),
                                          style: const TextStyle(color: Color(0xFFFFD700), fontSize: 15, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () {
                                    final note = messageController.text.trim();
                                    Navigator.pop(ctx, {
                                      'message': note.isNotEmpty ? note : 'هل ترتبط بي كـ CP؟ ❤️',
                                      'gift_id': selectedRing['id'],
                                      'gift_name': selectedRing['name'],
                                      'gift_price': selectedRing['price'],
                                      'gift_asset': selectedRing['asset'],
                                    });
                                  },
                                  child: Image.asset(
                                    'assets/cp/ic_send_invitation_send_btn_bg.webp',
                                    height: 46,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(colors: [Color(0xFFE91E63), Color(0xFFFF4081)]),
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: DText(
                                        isAr ? 'إرسال الدعوة' : 'Send Proposal',
                                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Show dialog to accept/decline CP invitation with authentic layout
Future<bool?> showAcceptCpInvitationDialog(
  BuildContext context, {
  required String senderName,
  required String myAvatar,
  required String senderAvatar,
  String? giftIcon,
  String? message,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final isAr = Localizations.localeOf(context).languageCode == 'ar';
      return Dialog(
        backgroundColor: Colors.transparent,
        child: SizedBox(
          width: 320,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Background card
              Image.asset(
                'assets/cp/ic_accept_cp_invitation_dialog_bg.webp',
                width: 320,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  width: 320,
                  height: 380,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E0D1A),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFF770D2E)),
                  ),
                ),
              ),

              // Content inside card
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Sender avatar
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.white12,
                      backgroundImage: senderAvatar.isNotEmpty ? EncryptedImageProvider(senderAvatar) : null,
                      child: senderAvatar.isEmpty ? const Icon(Icons.person, color: Colors.white54) : null,
                    ),
                    const SizedBox(height: 12),
                    DText(
                      '$senderName ${isAr ? "أرسل لك طلب ارتباط CP" : "sent you a CP proposal"} ❤️',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (message != null && message.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DText(
                          '"$message"',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFFB565), fontSize: 13, fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                    if (giftIcon != null && giftIcon.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Image.asset(giftIcon, width: 48, height: 48, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                    ],
                    const SizedBox(height: 24),
                    // Accept and Reject Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Decline
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx, false),
                          child: Container(
                            width: 100,
                            height: 40,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white30),
                            ),
                            alignment: Alignment.center,
                            child: DText(isAr ? 'رفض' : 'Decline', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Accept with ic_cp_accept_btn.webp
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx, true),
                          child: Image.asset(
                            'assets/cp/ic_cp_accept_btn.webp',
                            height: 40,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Container(
                              width: 100,
                              height: 40,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [Color(0xFFE91E63), Color(0xFFFF4081)]),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              alignment: Alignment.center,
                              child: DText(isAr ? 'قبول' : 'Accept', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Show CP bond result dialog (success/failure)
Future<void> showCpBondResultDialog(
    BuildContext context, {
      required bool success,
      required String myAvatar,
      required String partnerAvatar,
      String? message,
      String? statusIcon,
    }) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/cp/ic_wait_acception_cp_dialog_bg.webp',
                width: 318, height: 288,
                errorBuilder: (_, __, ___) => Container(
                  width: 318, height: 288,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2e0d15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF770d1e)),
                  ),
                )),
            const SizedBox(height: 55),
            DText(success ? '🎉 تم الربط بنجاح!' : '😢 تم رفض الطلب',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(radius: 32,
                    backgroundImage: myAvatar.isNotEmpty ? EncryptedImageProvider(myAvatar) : null,
                    child: const Icon(Icons.person)),
                Container(
                  width: 36, height: 36,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Icon(
                    success ? Icons.check_circle : Icons.cancel,
                    color: success ? Colors.green : Colors.red,
                    size: 36,
                  ),
                ),
                CircleAvatar(radius: 32,
                    backgroundImage: partnerAvatar.isNotEmpty ? EncryptedImageProvider(partnerAvatar) : null,
                    child: const Icon(Icons.person)),
              ],
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 35),
              child: DText(message ?? (success ? 'أصبحتما الآن CP!' : 'يمكنك المحاولة مرة أخرى لاحقاً'),
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  textAlign: TextAlign.center,
                  maxLines: 3),
            ),
            const SizedBox(height: 8),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );
    },
  );
}

/// Show CP level upgrade dialog
Future<void> showCpLvUpgradeDialog(
    BuildContext context, {
      required int newLevel,
      String? levelIconUrl,
      List<Map<String, dynamic>>? rewards,
    }) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Level icon
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFFd99d47).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_upward, color: const Color(0xFFd99d47), size: 44),
            ),
            const SizedBox(height: 8),
            Image.asset('assets/cp/ic_confirm_send_cp_invitation_bg.webp',
                width: 338, height: 338,
                errorBuilder: (_, __, ___) => Container(
                  width: 338,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2e0d15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF770d1e)),
                  ),
                  child: Column(
                    children: [
                      DText('تهانينا! مستوى $newLevel',
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          textAlign: TextAlign.center,
                          maxLines: 4),
                      const SizedBox(height: 12),
                      if (rewards != null && rewards.isNotEmpty)
                        ...rewards.map((r) => ListTile(
                          leading: Icon(Icons.card_giftcard, color: const Color(0xFFd99d47)),
                          title: DText(r['name'] as String? ?? '', style: const TextStyle(color: Colors.white)),
                          subtitle: DText(r['desc'] as String? ?? '', style: const TextStyle(color: Color(0xFF999999))),
                        )),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: 170, height: 40,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFd99d47),
                          ),
                          child: const DText('عرض المزايا الجديدة',
                              style: TextStyle(color: Colors.white, fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 4),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );
    },
  );
}
