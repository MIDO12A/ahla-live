import 'package:flutter/material.dart';
import '../../config/r.dart';
import '../../screens/room/widgets/svga_frame.dart';
import '../../services/dynamic_config_service.dart';
import 'cp_service.dart';
import 'package:zero/core/dtext.dart';

/// Relationship Display screen — matches act_relationship_display.xml
/// Shows available CP themes/displays and lets the couple select active one.
class CpDisplayScreen extends StatefulWidget {
  const CpDisplayScreen({super.key});

  @override
  State<CpDisplayScreen> createState() => _CpDisplayScreenState();
}

class _CpDisplayScreenState extends State<CpDisplayScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _themes = [];
  String? _activeThemeId;
  String? _applyingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        CpService.getThemes(),
        CpService.getMyData(),
      ]);
      final themes = (results[0] as List).cast<Map<String, dynamic>>();
      final my = results[1] as Map<String, dynamic>;
      final couple = my['couple'] as Map<String, dynamic>?;
      final activeTheme = my['active_theme'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _themes = themes;
        _activeThemeId = couple?['active_theme_id']?.toString() ?? activeTheme?['id']?.toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _apply(Map<String, dynamic> theme) async {
    final id = theme['id']?.toString();
    if (id == null || id.isEmpty || _applyingId != null) return;
    setState(() => _applyingId = id);
    final ok = await CpService.setTheme(id);
    if (!mounted) return;
    setState(() => _applyingId = null);
    if (ok) {
      setState(() => _activeThemeId = id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: DText('تم تطبيق المظهر بنجاح')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: DText('تعذّر تطبيق المظهر')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = DynamicConfigService();
    final bg = cfg.cpDisplayBgImage.isNotEmpty ? cfg.cpDisplayBgImage : cfg.cpSpaceBgImage;

    Widget body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white54, size: 48),
                    const SizedBox(height: 12),
                    const DText('تعذّر تحميل المظاهر', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _load, child: const DText('إعادة المحاولة', style: TextStyle(color: Color(0xFFFFB565)))),
                  ],
                ),
              )
            : _themes.isEmpty
                ? const Center(child: DText('لا توجد مظاهر متاحة حالياً', style: TextStyle(color: Colors.white54, fontSize: 16)))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: _themes.length,
                      itemBuilder: (_, i) => _buildThemeCard(cfg, _themes[i]),
                    ),
                  );

    return Scaffold(
      backgroundColor: const Color(0xFF2e0d15),
      body: Container(
        decoration: bg.isNotEmpty
            ? BoxDecoration(
                image: bg.startsWith('http')
                    ? DecorationImage(image: R.cachedImage(bg), fit: BoxFit.cover)
                    : DecorationImage(image: AssetImage(bg), fit: BoxFit.cover),
              )
            : const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF4a1020), Color(0xFF2e0d15)],
                ),
              ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(cfg),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(DynamicConfigService cfg) {
    final title = cfg.cpDisplayTitle.isNotEmpty ? cfg.cpDisplayTitle : 'عرض العلاقة';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: DText(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(color: cfg.cpSpaceTextColor, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildThemeCard(DynamicConfigService cfg, Map<String, dynamic> theme) {
    final id = theme['id']?.toString() ?? '';
    final name = (theme['name_ar'] ?? theme['name'] ?? 'مظهر').toString();
    final preview = (theme['preview_url'] ?? theme['image_url'] ?? theme['icon'] ?? theme['thumbnail'] ?? '').toString();
    final svga = (theme['svga_url'] ?? '').toString();
    final active = id.isNotEmpty && id == _activeThemeId;
    final applying = id.isNotEmpty && id == _applyingId;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF4a1020).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? cfg.cpGold : const Color(0xFF770d1e),
          width: active ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (svga.isNotEmpty)
                    SvgaFrame(svgaPath: svga, size: 200, fit: BoxFit.cover)
                  else if (preview.isNotEmpty)
                    (preview.startsWith('http')
                        ? Image(image: R.cachedImage(preview), fit: BoxFit.cover)
                        : Image.asset(preview, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholder()))
                  else
                    _placeholder(),
                  if (active)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cfg.cpGold,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const DText('مفعّل', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DText(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: ElevatedButton(
                    onPressed: (active || applying) ? null : () => _apply(theme),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: active ? Colors.white24 : const Color(0xFFd32a43),
                      disabledBackgroundColor: active ? Colors.white24 : Colors.white12,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: EdgeInsets.zero,
                      elevation: 0,
                    ),
                    child: applying
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : DText(
                            active ? 'مفعّل' : 'تطبيق',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFF2e0d15),
      child: const Center(child: Icon(Icons.auto_awesome, color: Color(0xFFffb565), size: 36)),
    );
  }
}
