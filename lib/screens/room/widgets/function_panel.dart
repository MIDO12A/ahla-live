import 'package:flutter/material.dart';
import '../../../config/r.dart';
import '../../../services/dynamic_config_service.dart';

class FunctionPanel extends StatelessWidget {
  final VoidCallback? onClose;
  final void Function(String label)? onItemTap;
  final bool isOwner;
  final bool isModerator;

  const FunctionPanel({
    super.key,
    this.onClose,
    this.onItemTap,
    this.isOwner = false,
    this.isModerator = false,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final cfg = DynamicConfigService();

    final functionItems = [
      {
        'key': 'Lucky Bag',
        'label': isAr ? 'حقيبة الحظ' : 'Lucky Bag',
        'asset': 'assets/images/ic_luckybag.png',
      },
      {
        'key': 'Game',
        'label': isAr ? 'الألعاب' : 'Games',
        'asset': R.roomGameIc,
      },
      {
        'key': 'Mixer',
        'label': isAr ? 'الميكسر' : 'Mixer',
        'asset': cfg.roomFuncMixerIcon.isNotEmpty ? cfg.roomFuncMixerIcon : R.roomSetMixerIc,
      },
      {
        'key': 'Settings',
        'label': isAr ? 'إعداد الغرفة' : 'Room Settings',
        'asset': cfg.roomFuncSettingsIcon.isNotEmpty ? cfg.roomFuncSettingsIcon : R.roomSetSetIc,
      },
      {
        'key': 'Seat Style',
        'label': isAr ? 'شكل المقاعد' : 'Seat Style',
        'asset': cfg.roomFuncSeatStyleIcon.isNotEmpty ? cfg.roomFuncSeatStyleIcon : R.roomSetSeatStyle,
      },
      {
        'key': 'Report',
        'label': isAr ? 'إبلاغ' : 'Report',
        'asset': cfg.roomFuncReportIcon.isNotEmpty ? cfg.roomFuncReportIcon : R.roomSetReportIc,
      },
      if (isOwner) ...[
        {
          'key': 'Room Background',
          'label': isAr ? 'خلفية الغرفة' : 'Room Background',
          'asset': cfg.roomFuncBgIcon.isNotEmpty ? cfg.roomFuncBgIcon : R.roomSetSeatStyle,
        },
        {
          'key': 'Clear Messages',
          'label': isAr ? 'مسح المحادثة' : 'Clear Chat',
          'asset': R.commonCloseIc2,
        },
      ],
    ];

    final effectItems = [
      {
        'key': 'Effect',
        'label': isAr ? 'إعدادات التأثيرات' : 'Effect Settings',
        'asset': cfg.roomFuncEffectIcon.isNotEmpty ? cfg.roomFuncEffectIcon : R.roomSetEffectIc,
      },
      {
        'key': 'Volume',
        'label': isAr ? 'صوت الغرفة' : 'Room Volume',
        'asset': cfg.roomFuncVolumeIcon.isNotEmpty ? cfg.roomFuncVolumeIcon : R.roomSetVolumeIc,
      },
      {
        'key': 'Gift Value',
        'label': isAr ? 'قيمة الهدية' : 'Gift Value',
        'asset': cfg.roomFuncGiftValIcon.isNotEmpty ? cfg.roomFuncGiftValIcon : R.roomSetGiftIc,
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: cfg.roomFunctionsPanelBgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.only(top: 20, bottom: 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSection(context, isAr ? 'وظائف الغرفة' : 'Room Functions', functionItems),
            const SizedBox(height: 24),
            _buildSection(context, isAr ? 'إعدادات التأثيرات' : 'Effect Settings', effectItems),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Map<String, String>> items) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            title,
            textAlign: isAr ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 16,
            alignment: isAr ? WrapAlignment.end : WrapAlignment.start,
            children: items.map((item) {
              return SizedBox(
                width: (MediaQuery.of(context).size.width - 48) / 4,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final key = item['key']!;
                    if (key == 'Settings' || key == 'Mixer' || key == 'Volume' || key == 'Seat Style' || key == 'Effect' || key == 'Gift Value' || key == 'Report' || key == 'Room Background' || key == 'Clear Messages' || key == 'Message Settings' || key == 'Lucky Bag' || key == 'Game') {
                      onItemTap?.call(key);
                    } else {
                      final label = item['label']!;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isAr ? '$label قريباً' : '$label coming soon'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _getIconWidget(item['key']!, item['asset']),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          item['label']!,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white70,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _getIconWidget(String labelKey, String? assetPath) {
    if (assetPath != null && assetPath.isNotEmpty) {
      return R.loadAsset(
        assetPath,
        width: 48,
        height: 48,
      );
    }
    return _fallbackIcon(labelKey);
  }

  Widget _fallbackIcon(String labelKey) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.tune, color: Colors.white70, size: 22),
    );
  }
}
