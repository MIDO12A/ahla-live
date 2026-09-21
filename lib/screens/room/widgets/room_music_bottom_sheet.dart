import 'package:flutter/material.dart';
import '../../../config/r.dart';

enum MusicPlayMode {
  loop,
  random,
  order,
}

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
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => RoomMusicBottomSheet(onOpenPlaylist: onOpenPlaylist),
    );
  }

  @override
  State<RoomMusicBottomSheet> createState() => _RoomMusicBottomSheetState();
}

class _RoomMusicBottomSheetState extends State<RoomMusicBottomSheet> {
  bool _isPlaying = false;
  double _progress = 0.25; // 0.0 to 1.0
  double _musicVolume = 80.0;
  double _voiceVolume = 100.0;
  MusicPlayMode _playMode = MusicPlayMode.loop;

  String _songTitle = 'Chill Vibes - Acoustic';
  String _currentTime = '01:12';
  String _totalTime = '03:45';

  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  void _nextTrack() {
    setState(() {
      _songTitle = 'Summer Wind - DJ Wave';
      _currentTime = '00:00';
      _totalTime = '04:12';
      _progress = 0.0;
    });
  }

  void _prevTrack() {
    setState(() {
      _songTitle = 'Night Drive - Synthwave';
      _currentTime = '00:00';
      _totalTime = '05:08';
      _progress = 0.0;
    });
  }

  void _toggleMode() {
    setState(() {
      if (_playMode == MusicPlayMode.loop) {
        _playMode = MusicPlayMode.random;
      } else if (_playMode == MusicPlayMode.random) {
        _playMode = MusicPlayMode.order;
      } else {
        _playMode = MusicPlayMode.loop;
      }
    });
  }

  String get _modeAsset {
    switch (_playMode) {
      case MusicPlayMode.loop:
        return 'assets/mipmap-xxhdpi/music_list_loop_ic.png';
      case MusicPlayMode.random:
        return 'assets/mipmap-xxhdpi/music_randowm_ic.webp';
      case MusicPlayMode.order:
        return 'assets/mipmap-xxhdpi/music_order_ic.webp';
    }
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
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _songTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 18),

              Row(
                children: [
                  Text(
                    _currentTime,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
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
                        value: _progress,
                        onChanged: (val) {
                          setState(() {
                            _progress = val;
                          });
                        },
                      ),
                    ),
                  ),
                  Text(
                    _totalTime,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: _toggleMode,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: R.image(_modeAsset, width: 24, height: 24),
                    ),
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
                          onTap: _prevTrack,
                          child: R.image('assets/mipmap-xxhdpi/music_previous_ic.png', width: 30, height: 30),
                        ),
                        const SizedBox(width: 20),
                        GestureDetector(
                          onTap: _togglePlay,
                          child: R.image(
                            _isPlaying
                                ? 'assets/mipmap-xxhdpi/music_pause_ic.webp'
                                : 'assets/mipmap-xxhdpi/music_play_ic.png',
                            width: 38,
                            height: 38,
                          ),
                        ),
                        const SizedBox(width: 20),
                        GestureDetector(
                          onTap: _nextTrack,
                          child: R.image('assets/mipmap-xxhdpi/music_next_ic.png', width: 30, height: 30),
                        ),
                      ],
                    ),
                  ),

                  GestureDetector(
                    onTap: () {
                      if (widget.onOpenPlaylist != null) {
                        Navigator.pop(context);
                        widget.onOpenPlaylist!();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: R.image('assets/mipmap-xxhdpi/music_list_ic.png', width: 24, height: 24),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      isAr ? 'موسيقى' : 'Music',
                      style: const TextStyle(fontSize: 11, color: Color(0x80FFFFFF)),
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
                        value: _musicVolume,
                        min: 0,
                        max: 100,
                        onChanged: (val) {
                          setState(() {
                            _musicVolume = val;
                          });
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '%',
                      style: const TextStyle(fontSize: 11, color: Color(0x80FFFFFF)),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      isAr ? 'صوت' : 'Voice',
                      style: const TextStyle(fontSize: 11, color: Color(0x80FFFFFF)),
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
                      '%',
                      style: const TextStyle(fontSize: 11, color: Color(0x80FFFFFF)),
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
