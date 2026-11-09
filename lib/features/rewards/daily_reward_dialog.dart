import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dtext.dart';
import '../../providers/user_provider.dart';
import '../invite/invite_service.dart';

/// نافذة المكافأة اليومية — تُعرض مرة واحدة يومياً عند فتح التطبيق
/// الإعدادات من app_config.daily_reward_settings (لوحة التحكم)
class DailyRewardDialog extends StatefulWidget {
  final Map<String, dynamic> status;

  const DailyRewardDialog({super.key, required this.status});

  /// تفحص الحالة وتعرض النافذة إذا كانت المكافأة مفعّلة ولم تُستلم اليوم
  static Future<void> showIfNeeded(BuildContext context) async {
    try {
      final uid =
          Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      final status = await InviteService().getDailyRewardStatus(uid);
      if (!context.mounted) return;
      if (status['enabled'] != true || status['claimed'] == true) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => DailyRewardDialog(status: status),
      );
    } catch (_) {}
  }

  @override
  State<DailyRewardDialog> createState() => _DailyRewardDialogState();
}

class _DailyRewardDialogState extends State<DailyRewardDialog> {
  final InviteService _service = InviteService();
  bool _claiming = false;
  String _rewardText = '';
  String _itemName = '';

  Map<String, dynamic> get _reward {
    final r = widget.status['reward'];
    if (r is Map) return Map<String, dynamic>.from(r);
    return const {};
  }

  @override
  void initState() {
    super.initState();
    _resolveRewardText();
  }

  Future<void> _resolveRewardText() async {
    final r = _reward;
    final type = r['type']?.toString() ?? '';
    final amount = (r['amount'] as num?)?.toInt() ?? 0;
    final itemId = r['item_id']?.toString() ?? '';
    String text;
    switch (type) {
      case 'coins':
        text = '$amount كوينز';
        break;
      case 'diamonds':
        text = '$amount ألماس';
        break;
      case 'vip_tier':
        final days = (r['days'] as num?)?.toInt() ?? 0;
        text = 'VIP ${amount.toInt()}${days > 0 ? ' لمدة $days يوم' : ''}';
        break;
      case 'item':
      case 'vip_item':
        _itemName = await _service.getStoreItemName(itemId);
        text = _itemName.isNotEmpty ? _itemName : itemId;
        break;
      default:
        text = '';
    }
    if (mounted) {
      setState(() => _rewardText = text);
    }
  }

  Future<void> _claim() async {
    if (_claiming) return;
    final uid =
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) return;
    setState(() => _claiming = true);
    final res = await _service.claimDailyReward(uid);
    if (!mounted) return;
    setState(() => _claiming = false);
    if (res['ok'] == true) {
      await Provider.of<UserProvider>(context, listen: false).loadUser(uid);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: DText('مكافأة اليوم: ${_rewardText.isNotEmpty ? _rewardText : 'تم الاستلام'}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      // already_claimed أو خطأ — أغلق بهدوء
      Navigator.of(context).pop();
    }
  }

  Map<String, dynamic> get _settings {
    final s = widget.status['settings'];
    if (s is Map) return Map<String, dynamic>.from(s);
    return const {};
  }

  String _cfg(String key, [String fallback = '']) =>
      _settings[key]?.toString().isNotEmpty == true
          ? _settings[key].toString()
          : fallback;

  Color _cfgColor(String key, Color fallback) {
    final hex = _cfg(key).replaceFirst('#', '');
    if (hex.length == 6) {
      final v = int.tryParse(hex, radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    return fallback;
  }

  Widget _cfgImage(String key, Widget fallback, {double? width, double? height, BoxFit fit = BoxFit.contain}) {
    final url = _cfg(key);
    if (url.isEmpty) return fallback;
    final isAsset = !url.startsWith('http');
    return Image(
      image: isAsset ? AssetImage(url) : NetworkImage(url) as ImageProvider,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.status['title']?.toString() ?? '';
    final desc = widget.status['description']?.toString() ?? '';
    final c1 = _cfgColor('color1', const Color(0xFF1DB954));
    final c2 = _cfgColor('color2', const Color(0xFF0B3D2E));
    final btnColor = _cfgColor('button_color', const Color(0xFFFFD700));
    final claimText = _cfg('claim_text', 'استلام');
    final bgImage = _cfg('bg_image');
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c1, c2],
          ),
          image: bgImage.isEmpty
              ? null
              : DecorationImage(
                  image: (bgImage.startsWith('http')
                      ? NetworkImage(bgImage)
                      : AssetImage(bgImage)) as ImageProvider,
                  fit: BoxFit.cover,
                ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _cfgImage('icon_url', const Icon(Icons.card_giftcard, color: Color(0xFFFFD700), size: 56), width: 72, height: 72),
            const SizedBox(height: 10),
            DText(
              title.isNotEmpty ? title : 'مكافأة اليوم',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 6),
            if (_rewardText.isNotEmpty)
              DText(
                _rewardText,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFFFD700)),
              ),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 6),
              DText(desc, style: const TextStyle(fontSize: 12, color: Colors.white70), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: _claiming ? null : _claim,
                style: ElevatedButton.styleFrom(
                  backgroundColor: btnColor,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                ),
                child: _claiming
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : DText(claimText, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
