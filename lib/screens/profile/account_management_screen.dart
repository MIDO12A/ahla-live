import 'package:flutter/material.dart';
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
import '../../services/account_switch_service.dart';

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
                          // Switch Account
                          _buildSimpleItem(
                            title: 'تبديل الحساب',
                            trailingWidget: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.switch_account_rounded, color: Color(0xFFDE880F), size: 20),
                              ],
                            ),
                            onTap: () => _showAccountSwitchSheet(context),
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
          if (context.mounted) {
            Provider.of<UserProvider>(context, listen: false).clearUser();
          }
          await SupabaseAuthService().signOut();
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

  void _showAccountSwitchSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1D2A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final currentUid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid ?? '';

            return FutureBuilder<List<Map<String, dynamic>>>(
              future: AccountSwitchService.getSavedAccounts(),
              builder: (context, snapshot) {
                final accounts = snapshot.data ?? [];

                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          Icon(Icons.switch_account_rounded, color: Color(0xFFFFD700), size: 24),
                          SizedBox(width: 10),
                          Text(
                            'تبديل الحساب',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (accounts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            'لا توجد حسابات أخرى محفوظة على هذا الجهاز',
                            style: TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        )
                      else
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: accounts.length,
                            separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                            itemBuilder: (context, index) {
                              final acc = accounts[index];
                              final uid = acc['uid'] as String? ?? '';
                              final isCurrent = uid == currentUid;
                              final name = (acc['name'] as String?)?.isNotEmpty == true ? acc['name'] as String : 'مستخدم';
                              final photo = acc['photoUrl'] as String? ?? '';
                              final customId = acc['customId'] as String? ?? '';
                              final email = acc['email'] as String? ?? '';
                              final phone = acc['phone'] as String? ?? '';
                              final sub = customId.isNotEmpty
                                  ? 'ID: $customId'
                                  : (phone.isNotEmpty ? phone : email);

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  radius: 22,
                                  backgroundColor: const Color(0xFF33333F),
                                  backgroundImage: photo.isNotEmpty && photo.startsWith('http')
                                      ? NetworkImage(photo)
                                      : null,
                                  child: photo.isEmpty || !photo.startsWith('http')
                                      ? const Icon(Icons.person, color: Colors.white54)
                                      : null,
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isCurrent)
                                      Container(
                                        margin: const EdgeInsets.only(left: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0x3300E5A0),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFF00E5A0)),
                                        ),
                                        child: const Text(
                                          'الحالي',
                                          style: TextStyle(color: Color(0xFF00E5A0), fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: sub.isNotEmpty
                                    ? Text(
                                        sub,
                                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!isCurrent) ...[
                                      ElevatedButton(
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          AccountSwitchService.switchToAccount(context, acc);
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFFFD700),
                                          foregroundColor: const Color(0xFF1A1A1A),
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                          minimumSize: Size.zero,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        ),
                                        child: const Text('تبديل', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                                        onPressed: () async {
                                          await AccountSwitchService.removeAccount(uid);
                                          setSheetState(() {});
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const LoginScreen()),
                            );
                          },
                          icon: const Icon(Icons.add, color: Color(0xFFFFD700)),
                          label: const Text(
                            'تسجيل الدخول بحساب آخر',
                            style: TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFFFD700)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
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
