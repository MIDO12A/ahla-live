import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import '../../services/supabase_service.dart';
import '../../providers/user_provider.dart';
import '../../config/r.dart';
import '../main_screen/main_screen.dart';
import 'setup_profile_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  Future<void> _handleSignIn(User user) async {
    try {
      final existingUser = await SupabaseService().getUser(user.uid);

      if (context.mounted) {
        if (existingUser == null) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => SetupProfileScreen(
                uid: user.uid,
                email: user.email ?? '',
                photoUrl: user.photoURL ?? '',
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
          SnackBar(content: Text('Error signing in: $e')),
        );
      }
    }
  }

  Future<void> _signInAnonymously() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final res = await FirebaseAuth.instance.signInAnonymously();
      final user = res.user;
      if (user == null) return;
      await _handleSignIn(user);
    } catch (e) {
      debugPrint('Error signing in anonymously: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing in: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final res = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = res.user;

      if (user == null) {
        throw Exception('لم يتم استرجاع بيانات المستخدم');
      }
      await _handleSignIn(user);
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
                          const SizedBox(width: 8),
                          const Text(
                            'تسجيل الدخول',
                            style: TextStyle(
                              fontSize: 15,
                              color: Color(0xFF894916),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Facebook and Phone login buttons (optional)
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _signInAnonymously,
                          child: Container(
                            height: 50,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF3B5998),
                                  Color(0xFF192F6A),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                R.image(
                                  'assets/mipmap-xxhdpi/login_fb_ic.webp',
                                  width: 24,
                                  height: 24,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Facebook',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: _signInAnonymously,
                          child: Container(
                            height: 50,
                            margin: const EdgeInsets.only(left: 8),
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
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                R.image(
                                  'assets/mipmap-xxhdpi/login_phone_ic.webp',
                                  width: 24,
                                  height: 24,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'الهاتف',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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
