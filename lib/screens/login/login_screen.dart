import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import '../../services/supabase_service.dart';
import '../../providers/user_provider.dart';
import '../../config/r.dart';
import '../main_screen/main_screen.dart';
import 'setup_profile_screen.dart';
import 'widgets/phone_login_sheet.dart';
import '../../services/supabase_auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  Future<void> _handleSignIn(AppAuthUser user) async {
    try {
      // 1. Save local persistent session
      await SupabaseAuthService().saveSession(
        uid: user.uid,
        email: user.email,
        name: user.displayName,
        photoUrl: user.photoUrl,
        phone: user.phoneNumber,
      );

      // 2. Sync user and phone directly into Supabase database
      try {
        await SupabaseAuthService().syncUserToSupabase(
          uid: user.uid,
          email: user.email ?? '',
          name: user.displayName ?? '',
          photoUrl: user.photoUrl ?? '',
          phone: user.phoneNumber ?? '',
        );
      } catch (_) {}

      final existingUser = await SupabaseService().getUser(user.uid);

      if (context.mounted) {
        if (existingUser == null) {
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
        } else {
          await Provider.of<UserProvider>(context, listen: false)
              .loadUser(user.uid);
          if (context.mounted) {
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
      if (context.mounted) {
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

      // Authenticate with Supabase Auth directly using Google ID Token
      final authData = await SupabaseAuthService().signInWithGoogleIdToken(idToken: idToken);
      final uid = (authData?['user']?['id'] as String?) ??
          'google_${account.id}';

      final authUser = AppAuthUser(
        uid: uid,
        email: account.email,
        displayName: account.displayName,
        photoUrl: account.photoUrl,
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
      if (context.mounted) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          R.image(
            'assets/mipmap-xxhdpi/bg_login.webp',
            fit: BoxFit.cover,
          ),
          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Welcome Logo
                  Padding(
                    padding: const EdgeInsets.only(bottom: 65),
                    child: R.loadImage(
                      'assets/mipmap-xxhdpi/login_welcome_ic.webp',
                      fit: BoxFit.contain,
                    ),
                  ),
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
                  const SizedBox(height: 34),
                  // Privacy text
                  const Text(
                    'بالاستمرار، أنت توافق على سياسة الخصوصية وشروط الخدمة',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0x80FFFFFF),
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
}
