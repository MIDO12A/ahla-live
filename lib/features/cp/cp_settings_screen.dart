import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../providers/user_provider.dart';
import '../../services/dynamic_config_service.dart';
import 'cp_service.dart';

/// CP Settings screen — matches act_cp_setting.xml
/// Shows: CP panel, love letter card, dissolve button.
class CpSettingsScreen extends StatefulWidget {
  const CpSettingsScreen({super.key});
  @override
  State<CpSettingsScreen> createState() => _CpSettingsScreenState();
}

class _CpSettingsScreenState extends State<CpSettingsScreen> {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  bool _dissolving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final data = await CpService.getMyData();
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final couple = _data['couple'] as Map<String, dynamic>?;
    final hasCp = _data['has_cp'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFF2e0d15),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !hasCp
              ? Center(
                  child: const Text('ليس لديك علاقة CP',
                      style: TextStyle(color: Colors.white54, fontSize: 16)),
                )
              : Stack(
                  children: [
                    // Top background
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 280,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF5a1525), Color(0xFF2e0d15)],
                          ),
                        ),
                      ),
                    ),
                    // Content
                    SingleChildScrollView(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top + 60,
                        bottom: 40,
                      ),
                      child: Column(
                        children: [
                          _buildCpPanel(couple),
                          const SizedBox(height: 23),
                          _buildContentArea(couple),
                        ],
                      ),
                    ),
                    // Top bar
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 12,
                      right: 12,
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
                            ),
                          ),
                          const Spacer(),
                          const Text('إعدادات العلاقة',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          const SizedBox(width: 32),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildCpPanel(Map<String, dynamic>? couple) {
    final partner = couple?['partner'] as Map<String, dynamic>?;
    final user = context.read<UserProvider>().currentUser;
    final myAvatar = user?.photoUrl ?? '';
    final partnerAvatar = partner?['avatar']?.toString() ?? '';
    final daysTogether = couple?['days_together']?.toString() ?? '0';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF4a1020).withValues(alpha: 0.8),
            const Color(0xFF2e0d15).withValues(alpha: 0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF770d1e), width: 1.5),
      ),
      child: Column(
        children: [
          // Avatars
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _avatar(myAvatar, 64),
              const SizedBox(width: 16),
              // Heart
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFd32a43).withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.favorite, color: Color(0xFFff6b9d), size: 24),
              ),
              const SizedBox(width: 16),
              _avatar(partnerAvatar, 64),
            ],
          ),
          const SizedBox(height: 12),
          // Days together
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFd32a43).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFa31b44)),
            ),
            child: Text(
              '$daysTogether يوم معاً',
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String? url, double size) {
    return ClipOval(
      child: R.loadImage(url ?? R.avaBoy, width: size, height: size, fit: BoxFit.cover),
    );
  }

  Widget _buildContentArea(Map<String, dynamic>? couple) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2e0d15),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(22),
          topRight: Radius.circular(22),
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        border: Border.all(color: const Color(0xFF770d1e), width: 1),
      ),
      child: Column(
        children: [
          // Love Letter Card
          _buildLetterCard(),
          const SizedBox(height: 24),
          // Dissolve button
          _buildDissolveButton(),
          const SizedBox(height: 8),
          const Text(
            'حل العلاقة يعني إنهاء الرابطة مع شريكك. لا يمكن التراجع عن هذا الإجراء.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLetterCard() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 44, 16, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF4d9a0d37),
                const Color(0xFF4d9a0d37).withValues(alpha: 0.5),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF770d1e), width: 2),
          ),
          child: Column(
            children: [
              const Text('رسالة الحب',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.mail_outline, color: Colors.white60, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('اكتب رسالة حب لشريكك هنا...',
                          style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  // Navigate to letter record
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7d102b), Color(0xFFd32a43)],
                    ),
                    borderRadius: BorderRadius.circular(35),
                    border: Border.all(color: const Color(0xFFa31b44)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('السجل', style: TextStyle(color: Colors.white, fontSize: 14)),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, color: Colors.white, size: 14),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Floating letter icon
        Positioned(
          top: -32,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFd32a43),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFd32a43).withValues(alpha: 0.4),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: const Icon(Icons.mail, color: Colors.white, size: 32),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDissolveButton() {
    return GestureDetector(
      onTap: _dissolving ? null : _showDissolveConfirm,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(57),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.heart_broken, color: Colors.white.withValues(alpha: 0.7), size: 16),
            const SizedBox(width: 8),
            Text(
              _dissolving ? 'جارٍ الحل...' : 'حل العلاقة',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  void _showDissolveConfirm() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2e0d15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('تأكيد حل العلاقة',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          'هل أنت متأكد من رغبتك في حل العلاقة؟ هذا الإجراء لا يمكن التراجع عنه.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _dissolving = true);
              try {
                await CpService.endCp();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حل العلاقة بنجاح')),
                  );
                  Navigator.pop(context);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('فشل حل العلاقة: $e')),
                  );
                }
              }
              if (mounted) setState(() => _dissolving = false);
            },
            child: const Text('تأكيد الحل', style: TextStyle(color: Color(0xFFff6b9d))),
          ),
        ],
      ),
    );
  }
}
