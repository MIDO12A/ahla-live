import 'dart:async';
import 'package:flutter/material.dart';
import '../../../models/banner_config.dart';
import '../../../services/firebase_service.dart';
import '../../../utils/app_action_navigator.dart';
import '../../../core/widgets/cached_image.dart';

/// البنر الدوار المصغر داخل الغرفة المطابق للأصل
/// Layout: act_voice_room.xml (@id/banner)
/// الحجم الأصلي: layout_width=53.0dp layout_height=45.0dp app:banner_auto_loop=true
class RoomBannerWidget extends StatefulWidget {
  const RoomBannerWidget({super.key});

  @override
  State<RoomBannerWidget> createState() => _RoomBannerWidgetState();
}

class _RoomBannerWidgetState extends State<RoomBannerWidget> {
  final FirebaseService _firebaseService = FirebaseService();
  final PageController _pageController = PageController();
  Timer? _autoScrollTimer;
  int _currentPage = 0;
  List<BannerConfig> _banners = [];

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _banners.length <= 1 || !_pageController.hasClients) return;
      final nextPage = (_currentPage + 1) % _banners.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BannerConfig>>(
      stream: _firebaseService.bannersStream(),
      builder: (context, snapshot) {
        final list = snapshot.data ?? [];
        _banners = list;
        if (list.isEmpty) return const SizedBox.shrink();

        // الحجم المصغر الأصلي 53dp x 45dp
        return SizedBox(
          width: 53.0,
          height: 45.0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: PageView.builder(
              controller: _pageController,
              itemCount: list.length,
              onPageChanged: (index) {
                _currentPage = index;
              },
              itemBuilder: (context, index) {
                final banner = list[index];
                return GestureDetector(
                  onTap: () {
                    AppActionNavigator.handleAction(
                      context,
                      actionType: banner.actionType,
                      actionValue: banner.actionValue,
                      rawLink: banner.linkUrl,
                    );
                  },
                  child: CachedNetImage(
                    banner.imageUrl,
                    width: 53.0,
                    height: 45.0,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      width: 53.0,
                      height: 45.0,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.white38,
                          ),
                        ),
                      ),
                    ),
                    error: (_, __, ___) => Container(
                      width: 53.0,
                      height: 45.0,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.campaign_rounded,
                        color: Colors.white54,
                        size: 20,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
