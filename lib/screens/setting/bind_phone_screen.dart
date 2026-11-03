import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/r.dart';
import '../../config/app_colors.dart';
import 'package:zero/core/dtext.dart';

class BindPhoneScreen extends StatefulWidget {
  const BindPhoneScreen({super.key});

  @override
  State<BindPhoneScreen> createState() => _BindPhoneScreenState();
}

class _BindPhoneScreenState extends State<BindPhoneScreen> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    if (_countdown > 0) return;
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_countdown <= 1) {
        _timer?.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown--);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0F0F),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 32),
                    const DText(
                      'ربط الجوال',
                      style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const DText(
                      'سيتم إرسال رمز تحقق إلى رقم جوالك',
                      style: TextStyle(fontSize: 14, color: Colors.white54),
                    ),
                    const SizedBox(height: 32),
                    const DText('رقم الجوال', style: TextStyle(fontSize: 13, color: Color(0xB3FFFFFF))),
                    const SizedBox(height: 8),
                    _buildPhoneField(),
                    const SizedBox(height: 20),
                    const DText('رمز التحقق', style: TextStyle(fontSize: 13, color: Color(0xB3FFFFFF))),
                    const SizedBox(height: 8),
                    _buildCodeField(),
                    const SizedBox(height: 40),
                    _buildSubmitButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: R.image(R.backIc, width: 24, height: 24),
            ),
          ),
          const Spacer(),
          const DText('ربط الجوال', style: TextStyle(fontSize: 17, color: Colors.white, fontWeight: FontWeight.w600)),
          const Spacer(),
          const SizedBox(width: 32),
        ],
      ),
    );
  }

  Widget _buildPhoneField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.cardBg2,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DText('+966', style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500)),
                SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, color: Colors.white54, size: 18),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 15, color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'أدخل رقم الجوال',
                hintStyle: TextStyle(color: Color(0x66FFFFFF)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 15, color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'أدخل رمز التحقق',
                hintStyle: TextStyle(color: Color(0x66FFFFFF)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
                isDense: true,
              ),
            ),
          ),
          GestureDetector(
            onTap: _countdown == 0 ? _startCountdown : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: _countdown == 0 ? AppColors.giftBtnGradient : null,
                color: _countdown > 0 ? AppColors.cardBg : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DText(
                _countdown > 0 ? '$_countdown ثانية' : 'إرسال الرمز',
                style: TextStyle(
                  fontSize: 12,
                  color: _countdown > 0 ? Colors.white54 : Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return GestureDetector(
      onTap: () {},
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          gradient: AppColors.giftBtnGradient,
          borderRadius: BorderRadius.circular(26),
        ),
        alignment: Alignment.center,
        child: const DText(
          'تأكيد',
          style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
