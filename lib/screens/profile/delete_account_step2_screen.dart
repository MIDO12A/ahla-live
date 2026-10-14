import 'package:flutter/material.dart';
import '../../services/supabase_auth_service.dart';
import '../../services/supabase_data_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_strings.dart';
import '../../screens/login/login_screen.dart';

class DeleteAccountStep2Screen extends StatefulWidget {
  const DeleteAccountStep2Screen({super.key});

  @override
  State<DeleteAccountStep2Screen> createState() => _DeleteAccountStep2ScreenState();
}

class _DeleteAccountStep2ScreenState extends State<DeleteAccountStep2Screen> {
  bool _isLoading = false;

  Future<void> _deleteAccount() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final uid = SupabaseAuthService().currentUid;
      if (uid == null || uid.isEmpty) {
        if (mounted) _navigateToLogin();
        return;
      }

      await SupabaseDataService().deleteUser(uid);
      await SupabaseAuthService().signOut();
      if (mounted) _navigateToLogin();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(AppStrings.deleteAccount),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 25),
            Text(
              AppStrings.detailDeleteAccount2,
              style: const TextStyle(
                fontSize: 17,
                color: Color(0xFF16151A),
              ),
            ),
            const SizedBox(height: 35),
            _buildItem(
              'assets/mipmap-xxhdpi/img_ask.webp',
              AppStrings.accountBalanceIs0,
              AppStrings.accountBalanceIs0Tip,
            ),
            const SizedBox(height: 35),
            _buildItem(
              'assets/mipmap-xxhdpi/img_ask.webp',
              AppStrings.backpackIsEmpty,
              AppStrings.backpackIsEmptytip,
            ),
            const SizedBox(height: 35),
            _buildItem(
              'assets/mipmap-xxhdpi/img_ask.webp',
              AppStrings.notAgency,
              AppStrings.notAgencyTip,
            ),
            const SizedBox(height: 35),
            _buildItem(
              'assets/mipmap-xxhdpi/img_ask.webp',
              AppStrings.notAdmin,
              AppStrings.notAdminTip,
            ),
            const SizedBox(height: 35),
            Container(
              width: double.infinity,
              height: 45,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                gradient: const LinearGradient(
                  colors: [AppColors.colorPrimary, AppColors.colorPrimary],
                ),
              ),
              child: TextButton(
                onPressed: _isLoading ? null : _deleteAccount,
                child: _isLoading
                    ? const CircularProgressIndicator(color: AppColors.color_894916)
                    : const Text(
                        AppStrings.clickToVerify,
                        style: TextStyle(
                          fontSize: 17,
                          color: AppColors.color_894916,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(String icon, String title, String tip) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            icon,
            width: 24,
            height: 24,
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    color: Color(0xFF16151A),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  tip,
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.color_83879A,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
