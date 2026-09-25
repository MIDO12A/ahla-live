import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../services/dynamic_config_service.dart';
import '../../../services/room_audio_service.dart';

// ═══════════════════════════════════════════════════════════════════
// VolumePanel — layout_room_volume.xml + Complete Room Deafen (Mute)
// ═══════════════════════════════════════════════════════════════════

class VolumePanel extends StatefulWidget {
  final double initialVolume;
  final void Function(double volume)? onVolumeChanged;
  final VoidCallback? onClose;

  const VolumePanel({
    super.key,
    this.initialVolume = 100.0,
    this.onVolumeChanged,
    this.onClose,
  });

  @override
  State<VolumePanel> createState() => _VolumePanelState();
}

class _VolumePanelState extends State<VolumePanel> {
  late double _volume;
  final RoomAudioService _audioService = RoomAudioService();

  @override
  void initState() {
    super.initState();
    _volume = _audioService.roomVolume.toDouble().clamp(0.0, 100.0);
    if (_volume <= 0 && widget.initialVolume > 0) {
      _volume = widget.initialVolume.clamp(0.0, 100.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.maybeLocaleOf(context)?.languageCode != 'en';

    return Container(
      decoration: BoxDecoration(
        color: DynamicConfigService().roomVolumePanelBgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title row
          Row(
            children: [
              Expanded(
                child: Text(
                  isAr ? 'صوت الغرفة' : 'Room Volume',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
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
          const SizedBox(height: 20),

          // ── كتم صوت الغرفة بالكامل (Deafen) ──
          ValueListenableBuilder<bool>(
            valueListenable: _audioService.roomDeafenedNotifier,
            builder: (context, isDeafened, _) {
              return Container(
                margin: const EdgeInsets.only(bottom: 18),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isDeafened
                      ? const Color(0x33FF5252)
                      : const Color(0x1AFFFFFF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDeafened ? const Color(0xFFFF5252) : Colors.white12,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isDeafened
                            ? const Color(0xFFFF5252)
                            : const Color(0x22FFFFFF),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isDeafened ? Icons.volume_off : Icons.headset,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr ? 'كتم صوت الغرفة بالكامل' : 'Deafen Room Audio',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDeafened
                                  ? const Color(0xFFFF8A80)
                                  : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isAr
                                ? (isDeafened
                                    ? 'تم كتم أصوات الجميع في الغرفة (هم يسمعون بعض)'
                                    : 'إيقاف سماع أصوات المتحدثين داخل الغرفة')
                                : (isDeafened
                                    ? 'Room muted for you (others hear each other)'
                                    : 'Silence all incoming voices in the room'),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: isDeafened,
                      activeColor: const Color(0xFFFF5252),
                      activeTrackColor: const Color(0x66FF5252),
                      onChanged: (val) async {
                        await _audioService.toggleRoomDeafen(val);
                        setState(() {});
                      },
                    ),
                  ],
                ),
              );
            },
          ),

          // Volume label + slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(Icons.volume_mute, color: Colors.white54, size: 20),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.goldLight,
                    inactiveTrackColor: AppColors.cardBg,
                    thumbColor: AppColors.goldLight,
                    overlayColor: AppColors.goldLight.withValues(alpha: 0.2),
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 10,
                    ),
                  ),
                  child: Slider(
                    value: _volume,
                    min: 0,
                    max: 100,
                    onChanged: (v) {
                      setState(() => _volume = v);
                      _audioService.setRoomVolume(v.round());
                      widget.onVolumeChanged?.call(v);
                    },
                  ),
                ),
              ),
              const Icon(Icons.volume_up, color: Colors.white54, size: 20),
            ],
          ),
          const SizedBox(height: 8),

          // Percentage display
          Text(
            '${_volume.round()}%',
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.goldLight,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
