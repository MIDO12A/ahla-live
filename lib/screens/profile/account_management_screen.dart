import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/supabase_auth_service.dart';
import '../../config/r.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_strings.dart';
import '../../utils/app_dimensions.dart';
import '../language/language_selection_screen.dart';
import '../country/country_picker_screen.dart';
import '../setting/bind_phone_screen.dart';
import '../setting/about_screen.dart';
import '../login/login_screen.dart';
import 'delete_account_step1_screen.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../widgets/user_id_widget.dart';

class AccountManagementScreen extends StatelessWidget {
  const AccountManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.colorF5F7FB,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Container(
              color: AppColors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.dp12,
                vertical: AppDimensions.dp8,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                    },
                    child: R.image(
                      R.backIc,
                      width: AppDimensions.dp28,
                      height: AppDimensions.dp28,
                    ),
                  ),
                  const SizedBox(width: AppDimensions.dp8),
                  const Expanded(
                    child: Text(
                      AppStrings.accountManagement,
                      style: TextStyle(
                        fontSize: AppDimensions.textSizeLg,
                        fontWeight: FontWeight.bold,
                        color: AppColors.color16151A,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppDimensions.dp16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMd),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: AppDimensions.dp8),
                      child: Column(
                        children: [
                          // Google
                          _buildListItem(
                            icon: R.mineGoogleIc,
                            title: AppStrings.google,
                            subtitle: AppStrings.notLinked,
                            onTap: () {},
                          ),
                          // Facebook
                          _buildListItem(
                            icon: R.mineFacebookIc,
                            title: AppStrings.facebook,
                            subtitle: AppStrings.notLinked,
                            onTap: () {},
                          ),
                          // Phone
                          _buildListItem(
                            icon: R.minePhoneIc,
                            title: AppStrings.phone,
                            subtitle: AppStrings.notLinked,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const BindPhoneScreen()),
                              );
                            },
                          ),
                          // Change Password
                          _buildSimpleItem(
                            title: AppStrings.changePassword,
                            onTap: () {},
                          ),
                          // Language
                          _buildSimpleItem(
                            title: "Language",
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const LanguageSelectionScreen(),
                                ),
                              );
                            },
                          ),
                          // Country
                          Builder(
                            builder: (context) {
                              final user = Provider.of<UserProvider>(context).currentUser;
                              final countryCode = user?.country.isNotEmpty == true ? user!.country : 'EG';
                              final cleanCode = UserIdWidget.resolveCountryCode(countryCode);
                              final flagEmoji = UserIdWidget.countryCodeToEmoji(cleanCode);

                              return _buildSimpleItem(
                                title: "الدولة / المنطقة",
                                trailingWidget: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(3),
                                      child: Image.network(
                                        'https://flagcdn.com/w40/$cleanCode.png',
                                        width: 22,
                                        height: 15,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Text(flagEmoji, style: const TextStyle(fontSize: 16)),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      countryCode.toUpperCase(),
                                      style: const TextStyle(fontSize: 13, color: Color(0xFF888888), fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const CountryPickerScreen(),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                          // About Us
                          _buildSimpleItem(
                            title: 'عن التطبيق',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const AboutScreen()),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    // Logout
                    const SizedBox(height: 24),
                    _buildLogoutButton(context),
                    const SizedBox(height: 40),
                    const Text(
                      AppStrings.securityTips,
                      style: TextStyle(
                        fontSize: AppDimensions.textSizeSm,
                        fontWeight: FontWeight.w500,
                        color: AppColors.color16151A,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.dp16),
                    const Text(
                      AppStrings.securityTipsDescription,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.color565964,
                      ),
                    ),
                    const SizedBox(height: 32),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DeleteAccountStep1Screen(),
                          ),
                        );
                      },
                      child: Text(
                        AppStrings.deleteAccount,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.red,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListItem({
    required String icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.dp8,
          vertical: 3,
        ),
        height: 66,
        child: Row(
          children: [
            Image.asset(
              icon,
              width: AppDimensions.dp44,
              height: AppDimensions.dp44,
            ),
            const SizedBox(width: AppDimensions.dp12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: AppDimensions.textSizeSm,
                      fontWeight: FontWeight.w500,
                      color: AppColors.color16151A,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.color16151A,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            R.image(
              R.nextBlackIc,
              width: AppDimensions.dp24,
              height: AppDimensions.dp24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(AppStrings.logout),
            content: const Text('هل أنت متأكد أنك تريد تسجيل الخروج؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(AppStrings.languageCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('تأكيد', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await SupabaseAuthService().signOut();
          try {
            await FirebaseAuth.instance.signOut();
          } catch (_) {}
          if (context.mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          }
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMd),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout, color: Colors.red, size: 22),
            SizedBox(width: 8),
            Text(
              'تسجيل الخروج',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleItem({
    required String title,
    required VoidCallback onTap,
    Widget? trailingWidget,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.dp8,
          vertical: 3,
        ),
        height: 66,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: AppDimensions.textSizeSm,
                  fontWeight: FontWeight.w500,
                  color: AppColors.color16151A,
                ),
              ),
            ),
            if (trailingWidget != null) ...[
              trailingWidget,
              const SizedBox(width: 8),
            ],
            R.image(
              R.nextBlackIc,
              width: AppDimensions.dp24,
              height: AppDimensions.dp24,
            ),
          ],
        ),
      ),
    );
  }
}
