import 'package:flutter/material.dart';
import '../room/widgets/vap_player.dart';
import '../../config/r.dart';
import 'vip_center_screen.dart';
import 'package:zero/core/dtext.dart';

class VipIntroScreen extends StatefulWidget {
  final String videoUrl;
  const VipIntroScreen({super.key, required this.videoUrl});

  @override
  State<VipIntroScreen> createState() => _VipIntroScreenState();
}

class _VipIntroScreenState extends State<VipIntroScreen> {
  bool _videoEnded = false;

  void _goToVip() {
    if (_videoEnded) return;
    _videoEnded = true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const VipCenterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: _goToVip,
        child: Stack(
          fit: StackFit.expand,
          children: [
            isVideoType(widget.videoUrl)
                ? VapPlayer(
                    url: widget.videoUrl,
                    fit: BoxFit.fill,
                    loops: false,
                    onFinished: _goToVip,
                  )
                : Image(
                    image: R.cachedImage(widget.videoUrl),
                    fit: BoxFit.fill,
                    errorBuilder: (_, __, ___) => const Center(
                      child: DText('Video not available', style: TextStyle(color: Colors.white)),
                    ),
                  ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 12,
              child: GestureDetector(
                onTap: _goToVip,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
            if (!isVideoType(widget.videoUrl))
              Center(
                child: GestureDetector(
                  onTap: _goToVip,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const DText('Tap to enter VIP', style: TextStyle(color: Colors.white, fontSize: 18)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
