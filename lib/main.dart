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
                    child: child!,
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

  void _onBubbleTap() {
    final svc = MinimizedRoomService();
    if (svc.roomId == null) return;
    final roomId = svc.roomId!;
    final roomName = svc.roomName ?? '';
    final hostName = svc.hostName ?? '';
    final roomPassword = svc.roomPassword ?? '';
    final hotValue = svc.hotValue ?? '0';
    final gameDesc = svc.gameDesc ?? '';
    if (!RoomScreen.pushGuard(roomId)) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomScreen(
          roomName: roomName,
          hostName: hostName,
          roomId: roomId,
          roomPassword: roomPassword,
          hotValue: hotValue,
          gameDesc: gameDesc,
          isReentry: true,
        ),
      ),
    );
    svc.deactivate();
  }

  void _onBubbleExit() {
    final svc = MinimizedRoomService();
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;
    if (uid != null) svc.exitRoom(uid);
  }

  @override
  Widget build(BuildContext context) {
    final body = _uid == null ? const LoginScreen() : const MainScreen();
    return ListenableBuilder(
      listenable: MinimizedRoomService(),
      builder: (context, _) {
        final svc = MinimizedRoomService();
        return Stack(
          children: [
            body,
            if (svc.isActive)
              Positioned(
                top: MediaQuery.of(context).padding.top + 60,
                right: 12,
                child: GestureDetector(
                  onTap: _onBubbleTap,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.cardBg,
                        child: ClipOval(
                          child: SizedBox(
                            width: 52,
                            height: 52,
                            child: R.loadImage(
                              svc.roomPhoto ?? R.avaBoy,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: -8,
                        right: -8,
                        child: GestureDetector(
                          onTap: _onBubbleExit,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
