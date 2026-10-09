import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:async';
import 'dart:developer' as developer;
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'services/dynamic_config_service.dart';
import 'services/error_reporting_service.dart';
import 'services/level_service.dart';
import 'services/firebase_service.dart';
import 'services/media_cache_service.dart'; // ✅ للـ warmup المبكر
import 'services/room_state_service.dart';
import 'services/supabase_auth_service.dart';
import 'services/supabase_service.dart';
import 'providers/user_provider.dart';
import 'providers/locale_provider.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/login/login_screen.dart';
import 'screens/login/setup_profile_screen.dart';
import 'screens/main_screen/main_screen.dart';
import 'screens/room/room_screen.dart';
import 'config/r.dart';
import 'config/app_colors.dart';
import 'core/ui/in_app_toast.dart';
import 'features/host_agency/widgets/agency_notification_handler.dart';
import 'services/global_banner_service.dart';
import 'widgets/global_banner_overlay.dart';


final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Guard against [core/duplicate-app]: on Android the google-services plugin
  // may already have created the [DEFAULT] app before Dart runs.
  try {
    Firebase.app();
  } catch (_) {
    // No default app exists yet — initialize it
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint('Firebase.initializeApp: $e');
    }
  }
  try {
    FirebaseAuth.instance.authStateChanges().listen((data) {
      developer.log('AUTH STATE CHANGE: ${data?.uid ?? 'none'}');
    });
  } catch (_) {}

  await SupabaseAuthService().init();
  FirebaseService().init();
  LevelService().init();
  await DynamicConfigService().init();
  ErrorReportingService().init();

  // ✅ تهيئة كاش الوسائط ← يحمّل فهرس القرص قبل أي طلب هدايا أو SVGA
  // هذا يضمن أن الملفات المُحمَّلة سابقاً تُستخدَم فوراً بدون إعادة تحميل من الإنترنت
  await MediaCacheService().init();

  final localeProvider = LocaleProvider();
  await localeProvider.init();

  GlobalBannerService.instance.init();
  WakelockPlus.enable();
  runApp(ZeroApp(localeProvider: localeProvider));
}

class ZeroApp extends StatefulWidget {
  final LocaleProvider localeProvider;
  const ZeroApp({super.key, required this.localeProvider});

  @override
  State<ZeroApp> createState() => _ZeroAppState();
}

class _ZeroAppState extends State<ZeroApp> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider.value(value: widget.localeProvider),
        ChangeNotifierProvider.value(value: DynamicConfigService()),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, child) {
          return ListenableBuilder(
            listenable: DynamicConfigService(),
            builder: (context, _) {
              final config = DynamicConfigService();
              return AgencyNotificationHandler(
                child: MaterialApp(
                navigatorKey: rootNavigatorKey,
                scaffoldMessengerKey: KayanInAppToast.messengerKey,
                title: config.appName,
                debugShowCheckedModeBanner: false,
                locale: localeProvider.locale,
                supportedLocales: const [
                  Locale('en'),
                  Locale('ar'),
                ],
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder: (context, child) {
                  final isRtl = localeProvider.locale?.languageCode == 'ar';
                  return Directionality(
                    textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                    child: GlobalBannerOverlay(
                      child: GlobalFloatingRoomOverlay(child: child!),
                    ),
                  );
                },
                theme: ThemeData(
                  primarySwatch: Colors.blue,
                  scaffoldBackgroundColor: config.primaryBg,
                  brightness: Brightness.light,
                  fontFamily: 'Roboto',
                  textTheme: TextTheme(
                    bodyLarge: TextStyle(color: config.textPrimary),
                    bodyMedium: TextStyle(color: config.textSecondary),
                  ),
                ),
                home: _showSplash
                    ? SplashScreen(
                        onNavigate: () {
                          setState(() {
                            _showSplash = false;
                          });
                        },
                      )
                    : const _AuthGate(),
              ),
            );  // AgencyNotificationHandler close
            },
          );
        },
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = SupabaseAuthService().currentUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (_uid != null) _loadExistingUser();

    SupabaseAuthService().authStateChanges.listen((uid) {
      if (!mounted) return;
      if (uid != null) {
        _handleNewSignIn(uid);
      } else {
        setState(() => _uid = null);
      }
    });

    try {
      FirebaseAuth.instance.authStateChanges().listen((u) {
        if (!mounted) return;
        if (u != null && _uid == null) {
          _handleNewSignIn(u.uid);
        }
      });
    } catch (_) {}
  }

  Future<void> _loadExistingUser() async {
    final uid = _uid;
    if (uid == null) return;
    final userData = await SupabaseService().getUser(uid);
    if (userData == null && mounted) {
      final supaAuthUser = SupabaseAuthService().currentUser;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => SetupProfileScreen(
            uid: uid,
            email: supaAuthUser?.email ?? FirebaseAuth.instance.currentUser?.email ?? '',
            photoUrl: supaAuthUser?.photoUrl ?? FirebaseAuth.instance.currentUser?.photoURL ?? '',
            phone: supaAuthUser?.phoneNumber ?? '',
          ),
        ),
        (route) => false,
      );
    } else if (mounted) {
      await Provider.of<UserProvider>(context, listen: false).loadUser(uid);
    }
  }

  Future<void> _handleNewSignIn(String uid) async {
    setState(() => _uid = uid);
    final userData = await SupabaseService().getUser(uid);
    if (userData == null && mounted) {
      final supaAuthUser = SupabaseAuthService().currentUser;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => SetupProfileScreen(
            uid: uid,
            email: supaAuthUser?.email ?? FirebaseAuth.instance.currentUser?.email ?? '',
            photoUrl: supaAuthUser?.photoUrl ?? FirebaseAuth.instance.currentUser?.photoURL ?? '',
            phone: supaAuthUser?.phoneNumber ?? '',
          ),
        ),
        (route) => false,
      );
    } else if (mounted) {
      await Provider.of<UserProvider>(context, listen: false).loadUser(uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _uid == null ? const LoginScreen() : const MainScreen();
  }
}

class GlobalFloatingRoomOverlay extends StatefulWidget {
  final Widget child;
  const GlobalFloatingRoomOverlay({super.key, required this.child});

  @override
  State<GlobalFloatingRoomOverlay> createState() => _GlobalFloatingRoomOverlayState();
}

class _GlobalFloatingRoomOverlayState extends State<GlobalFloatingRoomOverlay>
    with SingleTickerProviderStateMixin {
  Offset? _position;
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _onBubbleTap(MinimizedRoomService svc) {
    if (svc.roomId == null) return;
    final roomId = svc.roomId!;
    final roomName = svc.roomName ?? '';
    final hostName = svc.hostName ?? '';
    final roomPassword = svc.roomPassword ?? '';
    final hotValue = svc.hotValue ?? '0';
    final gameDesc = svc.gameDesc ?? '';

    final seatIndex = svc.seatIndex;
    final wasOnSeat = svc.isOnSeat;
    final wasMicMuted = svc.isMicMuted;

    if (!RoomScreen.pushGuard(roomId)) return;

    final navContext = rootNavigatorKey.currentContext;
    if (navContext != null) {
      Navigator.of(navContext).push(
        MaterialPageRoute(
          builder: (_) => RoomScreen(
            roomName: roomName,
            hostName: hostName,
            roomId: roomId,
            roomPassword: roomPassword,
            hotValue: hotValue,
            gameDesc: gameDesc,
            isReentry: true,
            initialSeatIndex: seatIndex,
            wasOnSeat: wasOnSeat,
            wasMicMuted: wasMicMuted,
          ),
        ),
      );
    }
  }

  Future<void> _onBubbleExit(MinimizedRoomService svc) async {
    final navContext = rootNavigatorKey.currentContext;
    String? uid;
    if (navContext != null) {
      try {
        final userProvider = Provider.of<UserProvider>(navContext, listen: false);
        uid = userProvider.currentUser?.uid;
      } catch (_) {}
    }
    uid ??= svc.userId ?? SupabaseAuthService().currentUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await svc.exitRoom(uid);
    } else {
      svc.deactivate();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MinimizedRoomService(),
      builder: (context, _) {
        final svc = MinimizedRoomService();
        if (!svc.isActive) {
          return widget.child;
        }

        final size = MediaQuery.of(context).size;
        final padding = MediaQuery.of(context).padding;

        // Default position: top right
        _position ??= Offset(
          size.width - 76,
          padding.top + 70,
        );

        // Keep inside screen bounds when screen size or orientation changes
        final clampedX = _position!.dx.clamp(8.0, (size.width - 76.0).clamp(8.0, double.infinity));
        final clampedY = _position!.dy.clamp(padding.top + 8.0, (size.height - padding.bottom - 76.0).clamp(padding.top + 8.0, double.infinity));
        final curPos = Offset(clampedX, clampedY);

        return Stack(
          textDirection: TextDirection.ltr,
          children: [
            widget.child,
            Positioned(
              left: curPos.dx,
              top: curPos.dy,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    final newX = (_position!.dx + details.delta.dx)
                        .clamp(8.0, size.width - 76.0);
                    final newY = (_position!.dy + details.delta.dy)
                        .clamp(padding.top + 8.0, size.height - padding.bottom - 76.0);
                    _position = Offset(newX, newY);
                  });
                },
                child: Material(
                  type: MaterialType.transparency,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Pulsing outer glow ring indicating active room audio
                      AnimatedBuilder(
                        animation: _animCtrl,
                        builder: (context, child) {
                          final scale = 1.0 + (_animCtrl.value * 0.08);
                          return Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(0xFF10B981).withValues(alpha: 0.35 + (_animCtrl.value * 0.2)),
                                    const Color(0xFF10B981).withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      // Main room avatar button
                      GestureDetector(
                        onTap: () => _onBubbleTap(svc),
                        child: Container(
                          width: 60,
                          height: 60,
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF10B981),
                              width: 2.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: R.loadImage(
                              svc.roomPhoto ?? R.avaBoy,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      // Close (X) button at top-right
                      Positioned(
                        top: -2,
                        right: -2,
                        child: GestureDetector(
                          onTap: () => _onBubbleExit(svc),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 3,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 13,
                            ),
                          ),
                        ),
                      ),
                      // Mic toggle button at bottom-right (if user is on seat)
                      if (svc.isOnSeat)
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: GestureDetector(
                            onTap: () => svc.toggleMic(),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: svc.isMicMuted ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    blurRadius: 3,
                                  ),
                                ],
                              ),
                              child: Icon(
                                svc.isMicMuted ? Icons.mic_off : Icons.mic,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
