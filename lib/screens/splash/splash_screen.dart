import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../services/supabase_service.dart';
import '../../services/dynamic_config_service.dart';
import '../../services/update_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/app_update_dialog.dart';
import '../../utils/app_action_navigator.dart';
import '../room/widgets/svga_frame.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onNavigate});

  final VoidCallback onNavigate;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isBanned = false;
  String _banReason = 'تم حظر حسابك من قبل الإدارة لمخالفة الشروط والأحكام.';

  bool _showingAd = false;
  int _adCountdown = 3;
  Timer? _adTimer;

  @override
  void dispose() {
    _adTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _checkStatusAndNavigate();
  }

  Future<void> _checkStatusAndNavigate() async {
    // Wait briefly to show app logo
    await Future.delayed(const Duration(milliseconds: 500));

    // Check if user is logged in and check ban status
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userData = await SupabaseService().getUser(user.uid);
        if (userData != null && userData.banned) {
          setState(() {
            _isBanned = true;
            _banReason = userData.banReason.isNotEmpty ? userData.banReason : _banReason;
          });
          return; // Stop here, don't navigate to app
        }
      } catch (e) {
        debugPrint('Error checking user ban status: $e');
      }
      // Load user data into provider
      if (mounted) {
        try {
          await Provider.of<UserProvider>(context, listen: false).loadUser(user.uid);
        } catch (e) {
          debugPrint('Error loading user data: $e');
        }
      }
    }

    // Check for a published app update before entering the app
    try {
      final update = await UpdateService.instance.checkForUpdate();
      if (update != null && mounted) {
        if (update.forceUpdate) {
          await AppUpdateDialog.show(context, update);
          return;
        }
        unawaited(AppUpdateDialog.show(context, update));
        if (mounted) widget.onNavigate();
        return;
      }
    } catch (e) {
      debugPrint('Update flow error: $e');
    }

    // Phase 1: عرض لوجو التطبيق واسمه باللون الغامق أولاً لمدة 1800ms
    await Future.delayed(const Duration(milliseconds: 1800));

    final config = DynamicConfigService();
    final hasCustomSplash = config.splashEnabled &&
        (config.splashSvgaUrl.isNotEmpty || config.splashImageUrl.isNotEmpty || config.splashUrl.isNotEmpty);

    // Phase 2: بعد ذلك فتح شاشة السبلاش المخصصة المحددة من لوحة التحكم إذا كانت مفعلة
    if (hasCustomSplash) {
      if (mounted) {
        setState(() {
          _showingAd = true;
          _adCountdown = config.splashDurationSeconds > 0 ? config.splashDurationSeconds : 3;
        });
        _adTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          setState(() {
            _adCountdown--;
          });
          if (_adCountdown <= 0) {
            timer.cancel();
            widget.onNavigate();
          }
        });
      }
      return;
    }

    if (mounted) {
      widget.onNavigate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = DynamicConfigService();

    if (_isBanned) {
      return Scaffold(
        backgroundColor: const Color(0xFF0C101D),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.gavel_rounded,
                    size: 80,
                    color: Color(0xFFEF4444),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'تنبيه الحظر الشامل',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Text(
                      _banReason,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF9BA1B6),
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'إذا كنت تعتقد أن هذا خطأ، يرجى التواصل مع الإدارة الدعم الفني.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_showingAd) {
      final svgaUrl = config.splashSvgaUrl.isNotEmpty
          ? config.splashSvgaUrl
          : (config.splashUrl.toLowerCase().endsWith('.svga') ? config.splashUrl : '');
      final imageUrl = config.splashImageUrl.isNotEmpty
          ? config.splashImageUrl
          : config.splashUrl;

      void triggerSplashAction() {
        if (config.splashActionValue.isNotEmpty) {
          _adTimer?.cancel();
          widget.onNavigate();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              AppActionNavigator.handleAction(
                context,
                actionType: config.splashActionType,
                actionValue: config.splashActionValue,
              );
            }
          });
        }
      }

      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: triggerSplashAction,
                onTap: () {
                  // If action configured, allow tap/double-tap to trigger
                  if (config.splashActionValue.isNotEmpty) {
                    triggerSplashAction();
                  }
                },
                child: svgaUrl.isNotEmpty
                    ? SvgaFrame(
                        svgaPath: svgaUrl,
                        size: double.infinity,
                        fit: BoxFit.cover,
                      )
                    : Image(
                        image: R.cachedImage(imageUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => Center(
                          child: Text(
                            config.appName,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: GestureDetector(
                    onTap: () {
                      _adTimer?.cancel();
                      widget.onNavigate();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'تخطي $_adCountdown',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Phase 1: عرض لوجو التطبيق الرسمي واسمه بوضوح
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Official Ahla Live App Logo
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(
                  'assets/images/app_logo.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Image.asset(
                    'assets/icon/app_icon.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              config.appName.isNotEmpty ? config.appName : 'Ahla Live',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: config.splashNameColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

