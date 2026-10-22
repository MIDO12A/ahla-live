import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../config/r.dart';
import '../../services/supabase_service.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _title = 'أحلى لايف - Ahla Live';
  String _description = 'تطبيق أحلى لايف هو منصة تواصل اجتماعي تتيح لك التعرف على أصدقاء جدد، وإنشاء غرف صوتية، والمشاركة في الفعاليات المختلفة. استمتع بتجربة تواصل فريدة وآمنة.';
  String _copyright = 'جميع الحقوق محفوظة © 2026';
  String _version = 'الإصدار 1.0.0';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = 'الإصدار ${pkg.version}+${pkg.buildNumber}');
    } catch (_) {}

    try {
      final doc = await SupabaseService().getDoc('app_config', 'about_app_config');
      if (doc != null && doc['value'] != null) {
        final val = doc['value'] is Map ? doc['value'] : (doc['value'] is String ? jsonDecode(doc['value']) : null);
        if (val is Map) {
          if (mounted) {
            setState(() {
              if (val['title'] != null && val['title'].toString().isNotEmpty) _title = val['title'].toString();
              if (val['description'] != null && val['description'].toString().isNotEmpty) _description = val['description'].toString();
              if (val['copyright'] != null && val['copyright'].toString().isNotEmpty) _copyright = val['copyright'].toString();
            });
          }
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    R.image(R.splashImgLogo, width: 80, height: 80),
                    const SizedBox(height: 16),
                    Text(
                      _title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF16151A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _version,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF9BA1B6),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildSocialRow(),
                    const SizedBox(height: 24),
                    Text(
                      _description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFF0F0F0)),
                ),
              ),
              child: Text(
                _copyright,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9BA1B6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: R.image(R.backIc, width: 24, height: 24),
            ),
          ),
          const Spacer(),
          const Text('عن التطبيق', style: TextStyle(fontSize: 17, color: Color(0xFF16151A), fontWeight: FontWeight.w500)),
          const Spacer(),
          const SizedBox(width: 32),
        ],
      ),
    );
  }

  Widget _buildSocialRow() {
    final socialItems = [
      ('تلغرام', Icons.telegram, const Color(0xFF0088CC)),
      ('انستغرام', Icons.camera_alt_outlined, const Color(0xFFE4405F)),
      ('تويتر', Icons.alternate_email, const Color(0xFF1DA1F2)),
      ('فيسبوك', Icons.facebook, const Color(0xFF1877F2)),
      ('تيك توك', Icons.music_note, const Color(0xFF000000)),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: socialItems.map((item) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: item.$3.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(item.$2, color: item.$3, size: 22),
            ),
          ),
        );
      }).toList(),
    );
  }
}
