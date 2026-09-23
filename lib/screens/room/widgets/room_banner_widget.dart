import 'dart:async';
import 'package:flutter/material.dart';
import '../../../models/banner_config.dart';
import '../../../services/firebase_service.dart';
import '../../../core/navigation/app_action_navigator.dart';
import '../../../widgets/cached_net_image.dart';

/// ويدجت بنرات الغرفة المطابقة للتطبيق الأصلي
/// Layout: vh_room_banner.xml (ConflictBanner, aspect ratio 351:101)
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

        return LayoutBuilder(
          builder: (context, constraints) {
            final double bannerWidth = constraints.maxWidth > 0
                ? constraints.maxWidth - 24
                : 351.0;
            final double bannerHeight = (bannerWidth / (351.0 / 101.0)).clamp(70.0, 105.0);

            return Container(
              width: bannerWidth,
              height: bannerHeight,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: list.length,
                      onPageChanged: (index) {
                        setState(() => _currentPage = index);
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
                            width: bannerWidth,
                            height: bannerHeight,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: Colors.black26,
                              child: const Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFFFD700),
                                  ),
                                ),
                              ),
                            ),
                            error: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        );
                      },
                    ),
                  ),

                  // Indicator dots at bottom center
                  if (list.length > 1)
                    Positioned(
                      bottom: 4,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(list.length, (i) {
                          final isActive = _currentPage == i;
                          return Container(
                            width: isActive ? 12 : 5,
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFFFFD700)
                                  : Colors.white.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        }),
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
}
