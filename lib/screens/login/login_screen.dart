import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../providers/user_provider.dart';
import '../../models/user_model.dart';
import '../../config/r.dart';
import '../main_screen/main_screen.dart';
import 'setup_profile_screen.dart';
import 'banned_screen.dart';
import 'widgets/phone_login_sheet.dart';
import '../../services/account_switch_service.dart';
import '../../services/supabase_auth_service.dart';
import '../../services/supabase_service.dart';
import '../../services/device_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zero/core/dtext.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  Map<String, dynamic>? _lastAccount;
  String? _bgUrl;
  String _bgType = 'image';
  String _welcomeTitle = 'Welcome';
  String _welcomeSubtitle = 'AHLA LIVE';
  String? _welcomeLogoUrl;
  bool _showWelcome = true;
  VideoPlayerController? _videoController;

  // سياسة الخصوصية
  bool _isPrivacyAgreed = false;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  bool _showPrivacyError = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut));

    _loadSavedAccount();
    _loadLoginConfig();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _triggerPrivacyWarning() {
    setState(() => _showPrivacyError = true);
    _shakeController.forward(from: 0.0);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: DText('يرجى الموافقة على سياسة الخصوصية وشروط الاستخدام أولاً'),
        backgroundColor: Colors.redAccent,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _loadSavedAccount() async {
    try {
      final accounts = await AccountSwitchService.getSavedAccounts();
      if (mounted && accounts.isNotEmpty) {
        setState(() => _lastAccount = accounts.first);
      }
    } catch (_) {}
  }

  Future<void> _loadLoginConfig() async {
    try {
      final doc = await SupabaseService().getDoc('app_config', 'login_screen_config');
      if (doc != null && doc['value'] != null) {
        final val = doc['value'] is Map ? doc['value'] : (doc['value'] is String ? jsonDecode(doc['value']) : null);
        if (val is Map) {
          final url = val['bgUrl']?.toString().trim() ?? '';
          final type = val['bgType']?.toString().trim() ?? 'image';
          final wTitle = val['welcomeTitle']?.toString().trim();
          final wSubtitle = val['welcomeSubtitle']?.toString().trim();
          final wLogo = val['welcomeLogoUrl']?.toString().trim();
          if (wTitle != null && wTitle.isNotEmpty) _welcomeTitle = wTitle;
          if (wSubtitle != null && wSubtitle.isNotEmpty) _welcomeSubtitle = wSubtitle;
          if (wLogo != null && wLogo.isNotEmpty) _welcomeLogoUrl = wLogo;
          if (val['showWelcome'] != null) {
            _showWelcome = val['showWelcome'] == true || val['showWelcome'].toString() == 'true';
          }
          if (url.isNotEmpty) {
            _bgUrl = url;
            _bgType = type;
            if (type == 'video' || url.toLowerCase().endsWith('.mp4')) {
              _initVideo(url);
            }
          }
          if (mounted) setState(() {});
        }
      }
    } catch (_) {}
  }

  void _initVideo(String url) {
    try {
      _videoController?.dispose();
      _videoController = VideoPlayerController.networkUrl(Uri.parse(url))
        ..initialize().then((_) {
          _videoController?.setLooping(true);
          _videoController?.setVolume(0);
          _videoController?.play();
          if (mounted) setState(() {});
        }).catchError((e) {
          debugPrint('Login background video error: $e');
        });
    } catch (_) {}
  }

  Future<void> _handleSignIn(AppAuthUser user) async {
    try {
      // 1. Check ban status if existing user
      if (!user.isNewUser) {
        final userData = await SupabaseService()
            .getUser(user.uid)
            .timeout(const Duration(seconds: 20));
        if (userData != null && userData.banned) {
          // Check if ban duration has expired
          if (userData.bannedUntil != null && DateTime.now().isAfter(userData.bannedUntil!)) {
            // Unban automatically
            try {
              await SupabaseService().updateUser(user.uid, {
                'banned': false,
                'ban_reason': '',
              });
            } catch (_) {}
          } else {
            // Still banned
            if (mounted) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (_) => BannedScreen(
                    reason: userData.banReason,
                    bannedUntil: userData.bannedUntil,
                  ),
                ),
                (route) => false,
              );
            }
            return;
          }
        }
      }

      // 2. Save local persistent session
      await SupabaseAuthService().saveSession(
        uid: user.uid,
        email: user.email,
        name: user.displayName,
        photoUrl: user.photoUrl,
        phone: user.phoneNumber,
      );

      // 3. Update device info on user profile and persistent registries
      //    (best-effort في الخلفية — لا نؤخر الانتقال للشاشة الرئيسية)
      unawaited(() async {
        try {
          final deviceInfo = await DeviceService().getDeviceInfo();
          await SupabaseService().updateUser(user.uid, deviceInfo.toMap());
          await DeviceService().saveDeviceRegistration(user.uid, email: user.email, info: deviceInfo);
        } catch (_) {}
      }());

      // 4. Save account for quick 1-tap re-login (best-effort)
      unawaited(() async {
        try {
          final userData = await SupabaseService().getUser(user.uid);
          await AccountSwitchService.saveAccount(
            uid: user.uid,
            name: userData?.name ?? user.displayName,
            photoUrl: userData?.photoUrl ?? user.photoUrl,
            customId: userData?.customId,
            email: user.email,
            phone: user.phoneNumber,
          );
        } catch (_) {
          await AccountSwitchService.saveAccount(
            uid: user.uid,
            name: user.displayName,
            photoUrl: user.photoUrl,
            email: user.email,
            phone: user.phoneNumber,
          );
        }
      }());

      if (user.isNewUser) {
        // NEW USER: Go to SetupProfileScreen so the user can enter their name, picture, gender and get a custom ID
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => SetupProfileScreen(
                uid: user.uid,
                email: user.email ?? '',
                photoUrl: user.photoUrl ?? '',
                phone: user.phoneNumber ?? '',
              ),
            ),
            (route) => false,
          );
        }
      } else {
        // EXISTING USER: Load user data and go to MainScreen
        try {
          if (user.photoUrl != null && user.photoUrl!.isNotEmpty) {
            await SupabaseAuthService().syncUserToSupabase(
              uid: user.uid,
              photoUrl: user.photoUrl,
            );
          }
        } catch (_) {}

        if (mounted) {
          final up = Provider.of<UserProvider>(context, listen: false);
          up.clearUser();
          try {
            await up.loadUser(user.uid).timeout(const Duration(seconds: 25));
          } catch (_) {}
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const MainScreen()),
              (route) => false,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error signing in: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: DText('تعذر تسجيل الدخول: $e'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  static bool _isGoogleInitialized = false;

  Future<void> _ensureGoogleInitialized() async {
    if (_isGoogleInitialized) return;
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId:
            '183199730954-6sud0ar4r7h3d76dtgdgnd34b7bqb5t6.apps.googleusercontent.com',
      );
      _isGoogleInitialized = true;
    } catch (e) {
      developer.log('GoogleSignIn.initialize: $e');
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!_isPrivacyAgreed) {
      _triggerPrivacyWarning();
      return;
    }
    if (_isLoading) {
      developer.log('_signInWithGoogle: already loading, skipping');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _ensureGoogleInitialized();
      final signIn = GoogleSignIn.instance;

      final account = await signIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw Exception('Google sign-in returned no idToken');
      }

      // 1. Check if user already exists in Supabase by email
      //    (getUserByEmail يرمي استثناءً عند فشل الشبكة — لا نكمل كأن
      //    المستخدم جديد لأن ذلك قد يحجبه بالخطأ "حسابين" أو يكرّر حسابه)
      UserModel? existingUser;
      if (account.email.isNotEmpty) {
        try {
          existingUser = await SupabaseAuthService().getUserByEmail(account.email);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: DText('تعذر التحقق من الحساب. تحقق من اتصالك بالإنترنت'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }
      }

      String uid;
      bool isNewUser = false;
      String? authUid;
      if (existingUser != null) {
        // Existing user found in Supabase! Use their established UID and data
        uid = existingUser.uid;
        isNewUser = false;
        developer.log('[GoogleAuth] Existing user: ${existingUser.name}, uid: $uid, customId: ${existingUser.customId}');
      } else {
        // سجّل الدخول في Supabase Auth أولاً للحصول على uid المصادقة الحقيقي
        final authData = await SupabaseAuthService().signInWithGoogleIdToken(idToken: idToken);
        authUid = (authData?['user']?['id'] as String?)?.toString().trim();
        if (authUid == null || authUid.isEmpty) {
          // في حال واجه خادم Supabase GoTrue خطأ (مثل حذف الحساب مسبقاً وتعلق الهوية في auth.identities)
          // نعتمد على المعرف الثابت الموثوق من جوجل حتى يتمكن المستخدم من الدخول/إعادة التسجيل بسلاسة
          authUid = 'google_${account.id}';
          developer.log('[GoogleAuth] GoTrue token exchange unavailable, fallback to persistent Google UID: $authUid');
        }

        // قد يكون للمستخدم سجل في جدول users بنفس uid المصادقة
        // حتى لو لم يكن بريده الإلكتروني محفوظاً — ابحث عنه قبل اعتباره جديداً
        UserModel? uidUser;
        try {
          uidUser = await SupabaseAuthService().getUserFromSupabase(authUid);
        } catch (_) {}

        if (uidUser != null) {
          existingUser = uidUser;
          uid = uidUser.uid;
          isNewUser = false;
          developer.log('[GoogleAuth] Existing user by auth uid: ${uidUser.name}, uid: $uid');
        } else {
          // مستخدم جديد فعلاً — تحقق من حد الحسابين مع تمرير uid المصادقة
          // حتى لا يُحجب حساب مسجل سابقاً على نفس الجهاز
          final deviceInfo = await DeviceService().getDeviceInfo();
          final canRegister = await DeviceService().canRegisterAccount(
            deviceId: deviceInfo.deviceId,
            currentEmail: account.email,
            currentUid: authUid,
          );

          if (!canRegister) {
            if (mounted) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E1D2A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
                      SizedBox(width: 8),
                      DText('تنبيه الحد الأقصى', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  content: const DText(
                    'عفواً، لا يمكن تسجيل أكثر من حسابين من نفس الهاتف.\nيرجى تسجيل الدخول بأحد الحسابات المسجلة مسبقاً على هذا الجهاز.',
                    style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                  ),
                  actions: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDE880F)),
                      onPressed: () => Navigator.pop(ctx),
                      child: const DText('حسناً', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            }
            return;
          }

          uid = authUid;
          isNewUser = true;
          developer.log('[GoogleAuth] New user with uid: $uid');
        }
      }

      final authUser = AppAuthUser(
        uid: uid,
        email: account.email,
        displayName: existingUser?.name ?? account.displayName,
        photoUrl: (existingUser?.photoUrl.isNotEmpty == true) ? existingUser!.photoUrl : account.photoUrl,
        isNewUser: isNewUser,
      );

      // ✅ إصدار session token لحساب Google — يثبت الهوية على السيرفر
      //    (create_session يتحقق من Supabase JWT) ليتزامن مع حارس
      //    الكتابة على users. أفضل جهد — لا يعطّل الدخول عند الفشل.
      unawaited(SupabaseAuthService().issueGoogleSession(idToken: idToken, uid: authUid ?? uid));

      await _handleSignIn(authUser);
    } on GoogleSignInException catch (e) {
      developer.log('_signInWithGoogle: google error ${e.code} = ${e.description}');
      if (e.code == GoogleSignInExceptionCode.canceled) {
        developer.log('_signInWithGoogle: user canceled');
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: DText(
              'تعذر تسجيل الدخول بجوجل: ${e.description ?? e.code.name}',
            ),
          ),
        );
      }
    } catch (e) {
      developer.log('_signInWithGoogle: error = $e');
      debugPrint('Error signing in with Google: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: DText('تعذر تسجيل الدخول: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Fallback static background
        R.image(
          'assets/mipmap-xxhdpi/bg_login.webp',
          fit: BoxFit.cover,
        ),
        // Dynamic background (video / VAP / GIF / image)
        if (_bgUrl != null && _bgUrl!.isNotEmpty)
          Positioned.fill(
            child: (_bgType == 'video' || _bgUrl!.toLowerCase().endsWith('.mp4'))
                ? (_videoController != null && _videoController!.value.isInitialized
                    ? RepaintBoundary(
                        child: SizedBox.expand(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _videoController!.value.size.width,
                              height: _videoController!.value.size.height,
                              child: VideoPlayer(_videoController!),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink())
                : R.loadImage(
                    _bgUrl!,
                    fit: BoxFit.cover,
                    loops: true,
                  ),
          ),
      ],
    );
  }

  Widget _buildWelcomeHeader() {
    return (_welcomeLogoUrl != null && _welcomeLogoUrl!.isNotEmpty)
        ? CachedNetworkImage(
            imageUrl: _welcomeLogoUrl!,
            height: 65,
            fit: BoxFit.contain,
            placeholder: (_, __) => const SizedBox(height: 65),
            errorWidget: (_, __, ___) => _buildDefaultWelcomeTypography(),
          )
        : _buildDefaultWelcomeTypography();
  }

  Widget _buildDefaultWelcomeTypography() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DText(
          _welcomeTitle.isNotEmpty ? _welcomeTitle : 'Welcome',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w400,
            color: Colors.white.withValues(alpha: 0.92),
            letterSpacing: 2,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.85),
                offset: const Offset(0, 2),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        DText(
          _welcomeSubtitle.isNotEmpty ? _welcomeSubtitle : 'AHLA LIVE',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 3,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.95),
                offset: const Offset(0, 3),
                blurRadius: 14,
              ),
              Shadow(
                color: const Color(0xFFFFB300).withValues(alpha: 0.6),
                offset: const Offset(0, 0),
                blurRadius: 20,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCenteredAppLogo() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 115,
          height: 115,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Image.asset(
              'assets/images/app_logo.png',
              width: 115,
              height: 115,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Image.asset(
                'assets/icon/app_icon.png',
                width: 115,
                height: 115,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        if (_showWelcome) ...[
          const SizedBox(height: 16),
          _buildWelcomeHeader(),
        ],
      ],
    );
  }

  Widget _buildQuickLogin() {
    final photoUrl = _lastAccount?['photoUrl']?.toString();
    return GestureDetector(
      onTap: _isLoading
          ? null
          : () {
              if (!_isPrivacyAgreed) {
                _triggerPrivacyWarning();
                return;
              }
              AccountSwitchService.switchToAccount(context, _lastAccount!);
            },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // فقط صورة المستخدم بدون أي خلفية بيضاء أو سوداء أو معتمة أو ذهبية
          ClipOval(
            child: SizedBox(
              width: 68,
              height: 68,
              child: (photoUrl != null && photoUrl.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: photoUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      errorWidget: (_, __, ___) => Image.asset(R.avaBoy, fit: BoxFit.cover),
                    )
                  : Image.asset(R.avaBoy, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 8),
          // كلمة دخول باللون الأسود وتحتها خلفية بيضاء خاصة بها فقط
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const DText(
              'دخول',
              style: TextStyle(
                color: Colors.black,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _signInWithGoogle,
      child: Container(
        height: 52,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoading)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.black87,
                ),
              )
            else ...[
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Image.asset(
                  'assets/images/google_custom_ic.png',
                  width: 28,
                  height: 28,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Google',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyRow() {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_shakeAnimation.value, 0),
          child: child,
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // زر الصح للموافقة مع اهتزاز وتلوين أحمر عند عدم التحديد
          GestureDetector(
            onTap: () {
              setState(() {
                _isPrivacyAgreed = !_isPrivacyAgreed;
                if (_isPrivacyAgreed) {
                  _showPrivacyError = false;
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                color: _isPrivacyAgreed
                    ? const Color(0xFF22C55E)
                    : (_showPrivacyError ? Colors.red.withValues(alpha: 0.2) : Colors.transparent),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _showPrivacyError
                      ? Colors.redAccent
                      : (_isPrivacyAgreed ? const Color(0xFF22C55E) : Colors.white70),
                  width: _showPrivacyError ? 2.5 : 1.5,
                ),
                boxShadow: _showPrivacyError
                    ? [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.6),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: _isPrivacyAgreed
                  ? const Icon(Icons.check, size: 15, color: Colors.white)
                  : (_showPrivacyError
                      ? const Icon(Icons.priority_high_rounded, size: 14, color: Colors.redAccent)
                      : null),
            ),
          ),
          // رابط ونصوص سياسة الخصوصية وشروط الاستخدام
          Flexible(
            child: GestureDetector(
              onTap: () => _showPrivacyPolicy(context),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 11,
                    color: _showPrivacyError ? Colors.redAccent : const Color(0x99FFFFFF),
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(text: 'بالاستمرار، أنت توافق على '),
                    TextSpan(
                      text: 'سياسة الخصوصية',
                      style: TextStyle(
                        color: _showPrivacyError ? Colors.redAccent : const Color(0xFFFFD700),
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    const TextSpan(text: ' و '),
                    TextSpan(
                      text: 'شروط الخدمة',
                      style: TextStyle(
                        color: _showPrivacyError ? Colors.redAccent : const Color(0xFFFFD700),
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          _buildBackground(),
          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                children: [
                  const Spacer(),
                  // App Logo Centered in Screen
                  _buildCenteredAppLogo(),
                  const Spacer(),
                  // Quick Login (Saved Account)
                  if (_lastAccount != null) ...[
                    _buildQuickLogin(),
                    const SizedBox(height: 24),
                  ],
                  // Google Login Button (White circular shape + custom Google icon + Google text)
                  _buildGoogleButton(),
                  const SizedBox(height: 20),
                  // Privacy & Terms Checkbox
                  _buildPrivacyRow(),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1528),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => FutureBuilder<Map<String, dynamic>?>(
        future: SupabaseService().getDoc('app_config', 'privacy_policy_config'),
        builder: (context, snapshot) {
          String content = 'مرحباً بك في تطبيق أحلى لايف (Ahla Live). نحن نحرص بشدة على حماية خصوصيتك وبياناتك الشخصية وتقديم بيئة آمنة لجميع المستخدمين وفقاً لمعايير Google Play الدولية:\n\n'
              '1. جمع البيانات:\n'
              'نقوم بجمع الحد الأدنى من البيانات الضرورية لتشغيل الحساب (الاسم، البريد الإلكتروني، رقم الهاتف عند التسجيل، ومعرف الجهاز لحماية الحساب من الاحتيال).\n\n'
              '2. أذونات التطبيق:\n'
              'يطلب التطبيق أذونات التسجيل الصوتي والكاميرا فقط عند فتح غرف البث المباشر أو المحادثة الصوتية بموافقتك الصريحة، ولا يتم تسجيل أو مشاركة محادثاتك مع أطراف ثالثة.\n\n'
              '3. حماية البيانات والأمان:\n'
              'يتم تشفير وتأمين جميع الاتصالات والبيانات عبر بروتوكولات SSL/TLS مشفرة بأعلى معايير الأمان.\n\n'
              '4. سلوك المجتمع والمحتوى المحظور:\n'
              'يُحظر تماماً أي محتوى مسيء، خطاب كراهية، مضايقة أو محتوى غير لائق. يحتفظ التطبيق بحق حظر أي حساب يخالف إرشادات المجتمع فوراً.\n\n'
              '5. حذف الحساب والبيانات:\n'
              'يمكنك في أي وقت طلب حذف حسابك وبياناتك بالكامل من خلال إعدادات الحساب داخل التطبيق.';

          final doc = snapshot.data;
          if (doc != null && doc['value'] != null) {
            final val = doc['value'];
            if (val is Map && val['content'] != null && val['content'].toString().trim().isNotEmpty) {
              content = val['content'].toString();
            } else if (val is String && val.trim().isNotEmpty) {
              content = val;
            }
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollCtrl) => Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const DText(
                        'سياسة الخصوصية وشروط الاستخدام',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  Expanded(
                    child: ListView(
                      controller: scrollCtrl,
                      children: [
                        DText(
                          content,
                          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
                        ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse('https://ahla-live-api.vercel.app/privacy');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      icon: const Icon(Icons.open_in_browser, color: Color(0xFF1E1528)),
                      label: const DText(
                        'عرض الصفحة الرسمية على الويب',
                        style: TextStyle(color: Color(0xFF1E1528), fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  ),
);
}
}
