import 'package:flutter/material.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_strings.dart';
import 'delete_account_step2_screen.dart';
import 'package:zero/core/dtext.dart';

class DeleteAccountStep1Screen extends StatelessWidget {
  const DeleteAccountStep1Screen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const DText(AppStrings.deleteAccount),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [
            const SizedBox(height: 25),
            Expanded(
              child: DText(
                AppStrings.detailDeleteAccount,
                style: const TextStyle(
                  fontSize: 17,
                  color: Color(0xFF16151A),
                ),
              ),
            ),
            const SizedBox(height: 10),
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
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DeleteAccountStep2Screen(),
                    ),
                  );
                },
                child: const DText(
                  AppStrings.continueBtn,
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.color_DE880F,
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
}
