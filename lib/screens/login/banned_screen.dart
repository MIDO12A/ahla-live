import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/supabase_auth_service.dart';
import 'login_screen.dart';

class BannedScreen extends StatelessWidget {
  final String reason;
  final DateTime? bannedUntil;

  const BannedScreen({
    super.key,
    required this.reason,
    this.bannedUntil,
  });

  String _formatDuration() {
    if (bannedUntil == null) return 'حظر دائم';
    final diff = bannedUntil!.difference(DateTime.now());
    if (diff.isNegative) return 'انتهت فترة الحظر';
    if (diff.inDays > 0) return '${diff.inDays} يوم (${diff.inHours % 24} ساعة)';
    if (diff.inHours > 0) return '${diff.inHours} ساعة (${diff.inMinutes % 60} دقيقة)';
    return '${diff.inMinutes} دقيقة';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3), width: 2),
                  ),
                  child: const Icon(
                    Icons.block_rounded,
                    size: 70,
                    color: Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'تم إيقاف حسابك',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'تم إيقاف حسابك عن الاستخدام بسبب مخالفة سياسات التطبيق',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B26),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.info_outline, color: Color(0xFFEF4444), size: 18),
                          SizedBox(width: 8),
                          Text(
                            'سبب الحظر:',
                            style: TextStyle(
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        reason.isNotEmpty ? reason : 'مخالفة شروط وسياسات الاستخدام.',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined, color: Color(0xFFF59E0B), size: 18),
                          const SizedBox(width: 8),
                          const Text(
                            'مدة الحظر المتبقية: ',
                            style: TextStyle(
                              color: Color(0xFFF59E0B),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            _formatDuration(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.logout),
                    label: const Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      await SupabaseAuthService().signOut();
                      try { await FirebaseAuth.instance.signOut(); } catch (_) {}
                      if (context.mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
