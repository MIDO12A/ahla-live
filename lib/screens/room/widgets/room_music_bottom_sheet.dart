import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../../config/r.dart';
import '../../../services/room_music_player_service.dart';

class RoomMusicBottomSheet extends StatefulWidget {
  final VoidCallback? onOpenPlaylist;

  const RoomMusicBottomSheet({
    super.key,
    this.onOpenPlaylist,
  });

  static Future<void> show(BuildContext context, {VoidCallback? onOpenPlaylist}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xF51D1111), // music_panel_bg
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RoomMusicBottomSheet(onOpenPlaylist: onOpenPlaylist),
    );
  }

  @override
  State<RoomMusicBottomSheet> createState() => _RoomMusicBottomSheetState();
}

class _RoomMusicBottomSheetState extends State<RoomMusicBottomSheet> {
  final RoomMusicPlayerService _musicService = RoomMusicPlayerService();
  double _voiceVolume = 100.0;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _getModeAsset(LoopMode mode) {
    switch (mode) {
      case LoopMode.one:
        return 'assets/mipmap-xxhdpi/music_list_loop_ic.png';
      case LoopMode.off:
        return 'assets/mipmap-xxhdpi/music_order_ic.webp';
      case LoopMode.all:
      default:
        return 'assets/mipmap-xxhdpi/music_randowm_ic.webp';
    }
  }

  Future<void> _pickFiles() async {
    final added = await _musicService.pickLocalAudioFiles();
    if (added > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تمت إضافة $added ملف صوتي من الجهاز'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showPlaylistDialog(BuildContext context) {
    final isAr = Localizations.maybeLocaleOf(context)?.languageCode != 'en';
    final playlist = _musicService.playlist;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1A22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isAr ? 'قائمة الموسيقى (${playlist.length})' : 'Playlist (${playlist.length})',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await _pickFiles();
                          setModalState(() {});
                          if (mounted) setState(() {});
                        },
                        icon: const Icon(Icons.add, color: Color(0xFFD98B2B), size: 18),
                        label: Text(
                          isAr ? 'إضافة ملف' : 'Add File',
                          style: const TextStyle(color: Color(0xFFD98B2B), fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24),
                  if (playlist.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text(
                          isAr ? 'لم تتم إضافة ملفات صوتية بعد' : 'No audio files added yet',
                          style: const TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: playlist.length,
                        itemBuilder: (ctx, idx) {
                          final track = playlist[idx];
                          final isCurrent = _musicService.currentIndex == idx;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              isCurrent ? Icons.equalizer : Icons.music_note,
                              color: isCurrent ? const Color(0xFFD98B2B) : Colors.white54,
                            ),
                            title: Text(
                              track.title,
                              style: TextStyle(
                                color: isCurrent ? const Color(0xFFD98B2B) : Colors.white,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              _musicService.playTrack(idx);
                              Navigator.pop(ctx);
                              if (mounted) setState(() {});
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.maybeLocaleOf(context)?.languageCode != 'en';
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 16),
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
                    color: const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // زر إضافة ملفات صوتية من الهاتف
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: _pickFiles,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFD98B2B), Color(0xFFB36B15)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.folder_open, color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              isAr ? 'ملفات الهاتف الصوتية' : 'Device Audio Files',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.queue_music, color: Colors.white70),
                      onPressed: () => _showPlaylistDialog(context),
                      tooltip: isAr ? 'قائمة التشغيل' : 'Playlist',
                    ),
                  ],
                ),
              ),

              // Song Title (Live notifier)
              ValueListenableBuilder<RoomMusicTrack?>(
                valueListenable: _musicService.currentTrackNotifier,
                builder: (_, track, __) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      track != null
                          ? track.title
                          : (isAr ? 'انقر على "ملفات الهاتف الصوتية" لاختيار موسيقى' : 'Select audio from device'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),

              // Progress bar + Time
              ValueListenableBuilder<Duration>(
                valueListenable: _musicService.durationNotifier,
                builder: (_, totalDuration, __) {
                  return ValueListenableBuilder<Duration>(
                    valueListenable: _musicService.positionNotifier,
                    builder: (_, currentPos, ___) {
                      final totalMs = totalDuration.inMilliseconds.toDouble();
                      final currentMs = currentPos.inMilliseconds.toDouble().clamp(0.0, totalMs > 0 ? totalMs : 1.0);
                      final progress = totalMs > 0 ? (currentMs / totalMs).clamp(0.0, 1.0) : 0.0;

                      return Row(
                        children: [
                          Text(
                            _formatDuration(currentPos),
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                activeTrackColor: const Color(0xFFD98B2B),
                                inactiveTrackColor: const Color(0x33FFFFFF),
                                thumbColor: const Color(0xFFD98B2B),
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              ),
                              child: Slider(
                                value: progress,
                                onChanged: (val) {
                                  if (totalMs > 0) {
                                    final seekMs = (val * totalMs).round();
                                    _musicService.seek(Duration(milliseconds: seekMs));
                                  }
                                },
                              ),
                            ),
                          ),
                          Text(
                            _formatDuration(totalDuration),
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 16),

              // Controls (Mode, Prev, Play/Pause, Next, List)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ValueListenableBuilder<LoopMode>(
                    valueListenable: _musicService.loopModeNotifier,
                    builder: (_, mode, __) {
                      return GestureDetector(
                        onTap: _musicService.toggleLoopMode,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: R.image(_getModeAsset(mode), width: 24, height: 24),
                        ),
                      );
                    },
                  ),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0x1AFFFFFF),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: _musicService.previous,
                          child: R.image('assets/mipmap-xxhdpi/music_previous_ic.png', width: 30, height: 30),
                        ),
                        const SizedBox(width: 20),
                        ValueListenableBuilder<bool>(
                          valueListenable: _musicService.isPlayingNotifier,
                          builder: (_, isPlaying, __) {
                            return GestureDetector(
                              onTap: _musicService.togglePlay,
                              child: R.image(
                                isPlaying
                                    ? 'assets/mipmap-xxhdpi/music_pause_ic.webp'
                                    : 'assets/mipmap-xxhdpi/music_play_ic.png',
                                width: 38,
                                height: 38,
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 20),
                        GestureDetector(
                          onTap: _musicService.next,
                          child: R.image('assets/mipmap-xxhdpi/music_next_ic.png', width: 30, height: 30),
                        ),
                      ],
                    ),
                  ),

                  GestureDetector(
                    onTap: () => _showPlaylistDialog(context),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: R.image('assets/mipmap-xxhdpi/music_list_ic.png', width: 24, height: 24),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Music Volume Slider
              ValueListenableBuilder<double>(
                valueListenable: _musicService.volumeNotifier,
                builder: (_, vol, __) {
                  return Row(
                    children: [
                      SizedBox(
                        width: 54,
                        child: Text(
                          isAr ? 'موسيقى' : 'Music',
                          style: const TextStyle(fontSize: 12, color: Color(0x80FFFFFF)),
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            activeTrackColor: const Color(0xFFD98B2B),
                            inactiveTrackColor: const Color(0x33FFFFFF),
                            thumbColor: const Color(0xFFD98B2B),
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          ),
                          child: Slider(
                            value: (vol * 100).clamp(0.0, 100.0),
                            min: 0,
                            max: 100,
                            onChanged: (val) {
                              _musicService.setVolume(val / 100.0);
                            },
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${(vol * 100).round()}%',
                          style: const TextStyle(fontSize: 12, color: Color(0x80FFFFFF)),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),

              // Voice Volume Slider
              Row(
                children: [
                  SizedBox(
                    width: 54,
                    child: Text(
                      isAr ? 'صوت' : 'Voice',
                      style: const TextStyle(fontSize: 12, color: Color(0x80FFFFFF)),
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        activeTrackColor: const Color(0xFFD98B2B),
                        inactiveTrackColor: const Color(0x33FFFFFF),
                        thumbColor: const Color(0xFFD98B2B),
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      ),
                      child: Slider(
                        value: _voiceVolume,
                        min: 0,
                        max: 100,
                        onChanged: (val) {
                          setState(() {
                            _voiceVolume = val;
                          });
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${_voiceVolume.round()}%',
                      style: const TextStyle(fontSize: 12, color: Color(0x80FFFFFF)),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

