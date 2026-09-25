import 'package:firebase_core/firebase_core.dart';
// lib/features/host_agency/screens/agency_invite_by_id_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// شاشة دعوة عضو عبر Kayan ID
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/agency_chat_repository.dart';
import '../../../core/cache/encrypted_image_provider.dart';

class AgencyInviteByIdScreen extends StatefulWidget {
  const AgencyInviteByIdScreen({
    super.key,
    required this.agencyId,
    required this.agencyName,
  });

  final String agencyId;
  final String agencyName;

  @override
  State<AgencyInviteByIdScreen> createState() => _AgencyInviteByIdScreenState();
}

class _AgencyInviteByIdScreenState extends State<AgencyInviteByIdScreen> {
  final _ctrl    = TextEditingController();
  final _focus   = FocusNode();

  bool   _searching   = false;
  bool   _inviting    = false;
  String _errorMsg    = '';

  // نتيجة البحث
  String? _foundUserId;
  String? _foundName;
  String? _foundAvatar;
  String? _foundKayanId;
  int?    _foundLevel;
  String? _foundCountry;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ── بحث ──────────────────────────────────────────────────────────────────
  Future<void> _search() async {
    final id = _ctrl.text.trim();
    if (id.isEmpty) return;
    _focus.unfocus();
    setState(() {
      _searching   = true;
      _errorMsg    = '';
      _foundUserId = null;
    });

    try {
      // 1. Resolve custom numeric ID to Firebase UID if possible
      String uidToSearch = id;
      try {
        final intId = int.tryParse(id);
        
        // Try string custom_id
        var query = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('users').where('custom_id', isEqualTo: id).limit(1).get();
        
        // Try integer custom_id if string fails
        if (query.docs.isEmpty && intId != null) {
          query = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('users').where('custom_id', isEqualTo: intId).limit(1).get();
        }
        
        if (query.docs.isNotEmpty) {
          uidToSearch = query.docs.first.id;
        } else {
          // Try string customId
          query = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('users').where('customId', isEqualTo: id).limit(1).get();
          // Try int customId
          if (query.docs.isEmpty && intId != null) {
            query = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('users').where('customId', isEqualTo: intId).limit(1).get();
          }
          
          if (query.docs.isNotEmpty) {
            uidToSearch = query.docs.first.id;
          } else {
            // Also try direct document ID
            final doc = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('users').doc(id).get();
            if (doc.exists) {
              uidToSearch = id;
            }
          }
        }
      } catch (_) {}

      // 2. Call Supabase RPC with the resolved UID
      final resp = await AgencyChatRepository.inviteByKayanId(
        agencyId: widget.agencyId,
        kayanId:  uidToSearch,
      );

      if (!mounted) return;
      final status = resp['status']?.toString() ?? 'error';

      if (status == 'invited' || status == 'already_invited') {
        // نجح — المستخدم وُجد (وقد يكون أُرسلت الدعوة فعلاً)
        setState(() {
          _foundUserId  = resp['user_id']?.toString();
          _foundName    = resp['display_name']?.toString() ?? 'مستخدم';
          _foundAvatar  = resp['avatar_url']?.toString();
          _foundKayanId = id; // Show the numeric ID entered by user
          _foundLevel   = (resp['level'] as int?) ?? 1;
          _foundCountry = resp['country']?.toString();

          if (status == 'already_invited') {
            _errorMsg = 'تم إرسال الدعوة مسبقاً';
          }
        });
      } else if (status == 'is_agent') {
        setState(() => _errorMsg = '⚠️ هذا المستخدم وكيل، لا يمكن دعوته كمضيف');
      } else if (status == 'already_member') {
        setState(() => _errorMsg = '⚠️ هذا المستخدم عضو بالفعل في الوكالة');
      } else if (status == 'in_other_agency') {
        setState(() => _errorMsg = '⚠️ هذا المستخدم منضم بالفعل لوكالة أخرى');
      } else if (status == 'not_found') {
        setState(() => _errorMsg = '❌ لم يُعثر على مستخدم بهذا الـ ID');
      } else if (status == 'not_authenticated') {
        setState(() => _errorMsg = '❌ يجب تسجيل الدخول أولاً');
      } else if (status == 'not_authorized') {
        setState(() => _errorMsg = '❌ لا تملك صلاحية إرسال دعوات');
      } else {
        setState(() => _errorMsg = '❌ حدث خطأ غير متوقع ($status)');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMsg = '❌ تعذّر الاتصال بالخادم');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  // ── تأكيد الدعوة ──────────────────────────────────────────────────────────
  Future<void> _confirmInvite() async {
    if (_foundUserId == null) return;
    final confirmed = await _showConfirmDialog();
    if (!confirmed || !mounted) return;

    setState(() => _inviting = true);
    try {
      // الـ RPC أرسل الدعوة أثناء البحث إذا كان status=invited
      // هنا نعرض فقط رسالة النجاح
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      _showSuccessSnack();
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  Future<bool> _showConfirmDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'تأكيد الدعوة',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // أفاتار
            _buildAvatar(_foundAvatar, 64),
            const SizedBox(height: 12),
            Text(
              _foundName ?? 'مستخدم',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Kayan ID: ${_foundKayanId ?? ''}',
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB800).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFB800).withOpacity(0.3)),
              ),
              child: Text(
                'هل تريد دعوة هذا المستخدم للانضمام إلى وكالة "${widget.agencyName}"؟',
                style: const TextStyle(color: Color(0xFFFFB800), fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFB800),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إرسال الدعوة', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showSuccessSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'تم إرسال الدعوة لـ ${_foundName ?? 'المستخدم'} بنجاح ✅',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── بناء الأفاتار ─────────────────────────────────────────────────────────
  Widget _buildAvatar(String? url, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFFFB800), width: 2),
        color: const Color(0xFF2A2A3E),
        image: (url != null && url.isNotEmpty)
            ? DecorationImage(image: EncryptedImageProvider(url), fit: BoxFit.cover)
            : null,
      ),
      child: (url == null || url.isEmpty)
          ? Icon(Icons.person_rounded, color: Colors.white54, size: size * 0.5)
          : null,
    );
  }

  // ── بطاقة المستخدم ────────────────────────────────────────────────────────
  Widget _buildUserCard() {
    if (_foundUserId == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFB800).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB800).withOpacity(0.08),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          _buildAvatar(_foundAvatar, 80),
          const SizedBox(height: 12),
          Text(
            _foundName ?? 'مستخدم',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.tag, color: Color(0xFFFFB800), size: 14),
              const SizedBox(width: 4),
              Text(
                'Kayan ID: ${_foundKayanId ?? ''}',
                style: const TextStyle(color: Color(0xFFFFB800), fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // مستوى
              _InfoChip(
                icon: Icons.military_tech_rounded,
                label: 'المستوى ${_foundLevel ?? 1}',
                color: const Color(0xFF9C6BFF),
              ),
              if (_foundCountry != null && _foundCountry!.isNotEmpty) ...[
                const SizedBox(width: 8),
                _InfoChip(
                  icon: Icons.flag_rounded,
                  label: _foundCountry!.toUpperCase(),
                  color: const Color(0xFF00D4FF),
                ),
              ],
            ],
          ),
          if (_errorMsg.contains('مسبقاً')) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMsg,
                style: TextStyle(color: Colors.orange.shade300, fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB800),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _inviting ? null : _confirmInvite,
              icon: _inviting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.person_add_rounded),
              label: Text(
                _inviting ? 'جاري الإرسال...' : 'إرسال الدعوة',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'دعوة عضو جديد',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Column(
            children: [
              // ── حقل البحث ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFFB800).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      const Icon(Icons.tag, color: Color(0xFFFFB800), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          focusNode: _focus,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          decoration: const InputDecoration(
                            hintText: 'أدخل المعرف الرقمي (ID)...',
                            hintStyle: TextStyle(color: Colors.white38),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _search(),
                        ),
                      ),
                      GestureDetector(
                        onTap: _search,
                        child: Container(
                          margin: const EdgeInsets.all(6),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFB800),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _searching
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(Icons.search_rounded, color: Colors.black, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // ── رسالة خطأ ───────────────────────────────────────────────
              if (_errorMsg.isNotEmpty && _foundUserId == null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMsg,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── بطاقة المستخدم ──────────────────────────────────────────
              if (_foundUserId != null) _buildUserCard(),

              // ── تعليمات ─────────────────────────────────────────────────
              if (_foundUserId == null && _errorMsg.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFB800).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_search_rounded,
                            color: Color(0xFFFFB800),
                            size: 48,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'ابحث بـ Kayan ID',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            'أدخل الـ Kayan ID الخاص بالمستخدم الذي تريد دعوته للانضمام إلى وكالتك',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 32),
                        // تلميحات
                        ..._buildHints(),
                      ],
                    ),
                  ),
                ),

              if (_foundUserId != null) const Spacer(),
            ],
          ),
        ),
    );
  }

  List<Widget> _buildHints() {
    final hints = [
      ('💡', 'الـ Kayan ID رقم فريد من 7 أرقام لكل مستخدم'),
      ('📋', 'يمكن للمستخدم معرفة ID الخاص به من ملفه الشخصي'),
      ('⚡', 'ستصل الدعوة فورياً بعد الإرسال'),
    ];
    return hints.map((h) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
      child: Row(
        children: [
          Text(h.$1, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              h.$2,
              style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13),
            ),
          ),
        ],
      ),
    )).toList();
  }
}

// ── InfoChip ──────────────────────────────────────────────────────────────────
class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String   label;
  final Color    color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
