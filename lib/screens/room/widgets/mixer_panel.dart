import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../services/dynamic_config_service.dart';

// ═══════════════════════════════════════════════════════════════════
// MixerPanel — fragment_room_music_mixer.xml
//
// Title "Mixer"
// Checkbox "Open Microphone Mixer" with switch icon
// Description text below
// ═══════════════════════════════════════════════════════════════════

class MixerPanel extends StatefulWidget {
  final bool initialMixerEnabled;
  final void Function(bool enabled)? onMixerToggle;
  final VoidCallback? onClose;

  const MixerPanel({
    super.key,
    this.initialMixerEnabled = false,
    this.onMixerToggle,
    this.onClose,
  });

  @override
  State<MixerPanel> createState() => _MixerPanelState();
}

class _MixerPanelState extends State<MixerPanel> {
  late bool _mixerEnabled;

  @override
  void initState() {
    super.initState();
    _mixerEnabled = widget.initialMixerEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    return Container(
      decoration: BoxDecoration(
        color: DynamicConfigService().roomVolumePanelBgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              Expanded(
                child: Text(
                  isAr ? 'الميكسر' : 'Mixer',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              GestureDetector(
                onTap: widget.onClose ?? () => Navigator.pop(context),
                child: const Icon(Icons.close, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 0.5, color: const Color(0x1AFFFFFF)),
          const SizedBox(height: 16),

          // "Open Microphone Mixer" checkbox row
          GestureDetector(
            onTap: () {
              setState(() => _mixerEnabled = !_mixerEnabled);
              widget.onMixerToggle?.call(_mixerEnabled);
            },
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                // Switch icon (checkbox look)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    color: _mixerEnabled
                        ? AppColors.goldLight
                        : const Color(0x33FFFFFF),
                  ),
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 200),
                        left: _mixerEnabled ? 20 : 2,
                        top: 2,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isAr ? 'ميكسر الميكروفون' : 'Open Microphone Mixer',
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Description text
          Text(
            _mixerEnabled
                ? (isAr
                    ? 'تم تفعيل ميكسر الميكروفون. سيتم دمج صوتك مع الموسيقى والمؤثرات للحصول على تجربة استماع احترافية.'
                    : 'Microphone mixer is enabled. Your voice will be mixed with background music for a better listening experience.')
                : (isAr
                    ? 'قم بتفعيل ميكسر الميكروفون لدمج صوتك مع موسيقى الخلفية والمؤثرات الصوتية داخل الغرفة.'
                    : 'Enable the microphone mixer to mix your voice with background music for a richer audio experience in the room.'),
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xB3FFFFFF),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),

          // EQ sliders (shown when mixer is enabled)
          if (_mixerEnabled) ...[
            _buildEqRow(isAr ? 'العالي' : 'Treble', 0.6),
            const SizedBox(height: 8),
            _buildEqRow(isAr ? 'المتوسط' : 'Mid', 0.5),
            const SizedBox(height: 8),
            _buildEqRow(isAr ? 'المنخفض' : 'Bass', 0.4),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildEqRow(String label, double initialValue) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.goldLight,
              inactiveTrackColor: AppColors.cardBg,
              thumbColor: AppColors.goldLight,
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(value: initialValue, onChanged: (_) {}),
          ),
        ),
      ],
    );
  }
}
