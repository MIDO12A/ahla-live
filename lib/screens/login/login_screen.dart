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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  Map<String, dynamic>? _lastAccount;
  String? _bgUrl;
  String _bgType = 'image';
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    _loadSavedAccount();
    _loadLoginConfig();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
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
          if (url.isNotEmpty) {
            _bgUrl = url;
            _bgType = type;
            if (type == 'video' || url.toLowerCase().endsWith('.mp4')) {
              _initVideo(url);
            }
            if (mounted) setState(() {});
          }
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
        final userData = await SupabaseService().getUser(user.uid);
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
      try {
        final deviceInfo = await DeviceService().getDeviceInfo();
        await SupabaseService().updateUser(user.uid, deviceInfo.toMap());
        await DeviceService().saveDeviceRegistration(user.uid, email: user.email, info: deviceInfo);
      } catch (_) {}

      // 4. Save account for quick 1-tap re-login
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
          await up.loadUser(user.uid);
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
            content: Text('تعذر تسجيل الدخول: $e'),
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
      UserModel? existingUser;
      if (account.email.isNotEmpty) {
        existingUser = await SupabaseAuthService().getUserByEmail(account.email);
      }

      String uid;
      bool isNewUser = false;
      if (existingUser != null) {
        // Existing user found in Supabase! Use their established UID and data
        uid = existingUser.uid;
        isNewUser = false;
        developer.log('[GoogleAuth] Existing user: ${existingUser.name}, uid: $uid, customId: ${existingUser.customId}');
      } else {
        // Enforce maximum 2 accounts per phone before registering new user
        final deviceInfo = await DeviceService().getDeviceInfo();
        final canRegister = await DeviceService().canRegisterAccount(
          deviceId: deviceInfo.deviceId,
          currentEmail: account.email,
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
                    Text('تنبيه الحد الأقصى', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                content: const Text(
                  'عفواً، لا يمكن تسجيل أكثر من حسابين من نفس الهاتف.\nيرجى تسجيل الدخول بأحد الحسابات المسجلة مسبقاً على هذا الجهاز.',
                  style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                ),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDE880F)),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('حسناً', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }
          return;
        }

        // Brand new user! Authenticate with Supabase Auth
        final authData = await SupabaseAuthService().signInWithGoogleIdToken(idToken: idToken);
        uid = (authData?['user']?['id'] as String?) ?? 'google_${account.id}';
        isNewUser = true;
        developer.log('[GoogleAuth] New user with uid: $uid');
      }

      final authUser = AppAuthUser(
        uid: uid,
        email: account.email,
        displayName: existingUser?.name ?? account.displayName,
        photoUrl: (existingUser?.photoUrl.isNotEmpty == true) ? existingUser!.photoUrl : account.photoUrl,
        isNewUser: isNewUser,
      );

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
            content: Text(
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
            content: Text('تعذر تسجيل الدخول: $e'),
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
                    ? SizedBox.expand(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _videoController!.value.size.width,
                            height: _videoController!.value.size.height,
                            child: VideoPlayer(_videoController!),
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
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Welcome Logo
                  Padding(
                    padding: const EdgeInsets.only(bottom: 50),
                    child: R.loadImage(
                      'assets/mipmap-xxhdpi/login_welcome_ic.webp',
                      fit: BoxFit.contain,
                    ),
                  ),
                  // Quick Login Card for Saved Account
                  if (_lastAccount != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFFFCC80).withOpacity(0.7),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: (_lastAccount!['photoUrl'] != null &&
                                      _lastAccount!['photoUrl'].toString().isNotEmpty)
                                  ? CachedNetworkImage(
                                      imageUrl: _lastAccount!['photoUrl'],
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => const CircularProgressIndicator(strokeWidth: 2),
                                      errorWidget: (_, __, ___) => Image.asset(R.avaBoy, fit: BoxFit.cover),
                                    )
                                  : Image.asset(R.avaBoy, fit: BoxFit.cover),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  (_lastAccount!['name']?.toString().isNotEmpty == true)
                                      ? _lastAccount!['name']
                                      : 'مستخدم',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'ID: ${_lastAccount!['customId'] ?? _lastAccount!['uid'] ?? ''}',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFCC80),
                              foregroundColor: const Color(0xFF894916),
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: const Icon(Icons.bolt_rounded, size: 16),
                            label: const Text(
                              'دخول مباشر',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            onPressed: _isLoading
                                ? null
                                : () => AccountSwitchService.switchToAccount(context, _lastAccount!),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Google Login Button
                  GestureDetector(
                    onTap: _isLoading ? null : _signInWithGoogle,
                    child: Container(
                      height: 50,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFCC80),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isLoading)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF894916),
                              ),
                            )
                          else
                            R.image(
                              'assets/mipmap-xxhdpi/login_google_ic.webp',
                              width: 24,
                              height: 24,
                            ),
                          const SizedBox(width: 10),
                          const Text(
                            'تسجيل الدخول بحساب Google',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF894916),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Phone Login Button
                  GestureDetector(
                    onTap: _isLoading
                        ? null
                        : () {
                            PhoneLoginSheet.show(
                              context,
                              onSignedIn: (user) => _handleSignIn(user),
                            );
                          },
                    child: Container(
                      height: 50,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFFF5722),
                            Color(0xFFFF9800),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          R.image(
                            'assets/mipmap-xxhdpi/login_phone_ic.webp',
                            width: 24,
                            height: 24,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'تسجيل الدخول برقم الهاتف',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Privacy text & Terms
                  InkWell(
                    onTap: () => _showPrivacyPolicy(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: const TextSpan(
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0x99FFFFFF),
                            height: 1.5,
                          ),
                          children: [
                            TextSpan(text: 'بالاستمرار، أنت توافق على '),
                            TextSpan(
                              text: 'سياسة الخصوصية',
                              style: TextStyle(
                                color: Color(0xFFFFD700),
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                            TextSpan(text: ' و '),
                            TextSpan(
                              text: 'شروط الخدمة',
                              style: TextStyle(
                                color: Color(0xFFFFD700),
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
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
                      const Text(
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
                        Text(
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
                      label: const Text(
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
