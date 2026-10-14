import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/supabase_auth_service.dart';

class PhoneLoginSheet extends StatefulWidget {
  final Function(AppAuthUser authUser) onSignedIn;

  const PhoneLoginSheet({super.key, required this.onSignedIn});

  static Future<void> show(BuildContext context, {required Function(AppAuthUser authUser) onSignedIn}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PhoneLoginSheet(onSignedIn: onSignedIn),
    );
  }

  @override
  State<PhoneLoginSheet> createState() => _PhoneLoginSheetState();
}

class _PhoneLoginSheetState extends State<PhoneLoginSheet> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  String _countryCode = '+20'; // Default Egypt
  bool _codeSent = false;
  bool _isLoading = false;
  String? _errorMessage;
  String? _infoMessage;
  Timer? _resendTimer;
  int _resendCountdown = 60;

  final List<Map<String, String>> _countries = [
    {'name': 'مصر', 'code': '+20', 'flag': '🇪🇬'},
    {'name': 'السعودية', 'code': '+966', 'flag': '🇸🇦'},
    {'name': 'الإمارات', 'code': '+971', 'flag': '🇦🇪'},
    {'name': 'الكويت', 'code': '+965', 'flag': '🇰🇼'},
    {'name': 'العراق', 'code': '+964', 'flag': '🇮🇶'},
    {'name': 'الأردن', 'code': '+962', 'flag': '🇯🇴'},
    {'name': 'قطر', 'code': '+974', 'flag': '🇶🇦'},
    {'name': 'البحرين', 'code': '+973', 'flag': '🇧🇭'},
    {'name': 'عمان', 'code': '+968', 'flag': '🇴🇲'},
    {'name': 'المغرب', 'code': '+212', 'flag': '🇲🇦'},
    {'name': 'الجزائر', 'code': '+213', 'flag': '🇩🇿'},
    {'name': 'تونس', 'code': '+216', 'flag': '🇹🇳'},
    {'name': 'ليبيا', 'code': '+218', 'flag': '🇱🇾'},
    {'name': 'السودان', 'code': '+249', 'flag': '🇸🇩'},
    {'name': 'اليمن', 'code': '+967', 'flag': '🇾🇪'},
    {'name': 'سوريا', 'code': '+963', 'flag': '🇸🇾'},
    {'name': 'لبنان', 'code': '+961', 'flag': '🇱🇧'},
    {'name': 'فلسطين', 'code': '+970', 'flag': '🇵🇸'},
  ];

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown <= 1) {
        timer.cancel();
        setState(() => _resendCountdown = 0);
      } else {
        setState(() => _resendCountdown--);
      }
    });
  }

  String get _fullPhoneNumber {
    String phone = _phoneController.text.trim();
    if (phone.startsWith('0')) {
      phone = phone.substring(1);
    }
    return '$_countryCode$phone';
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 6) {
      setState(() {
        _errorMessage = 'يرجى إدخال رقم هاتف صحيح';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      final res = await SupabaseAuthService().sendPhoneOtp(_fullPhoneNumber);
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _codeSent = true;
        if (res['debugCode'] != null) {
          _infoMessage = 'تم إنشاء رمز التحقق (OTP): ${res['debugCode']}';
        } else {
          _infoMessage = 'تم إرسال رمز التحقق عبر الرسائل القصيرة (SMS) إلى هاتفك';
        }
      });
      _startResendTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      setState(() {
        _errorMessage = 'يرجى إدخال رمز التحقق (OTP) المكون من 6 أرقام';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authUser = await SupabaseAuthService().verifyPhoneOtpAndSignIn(
        phone: _fullPhoneNumber,
        otp: code,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onSignedIn(authUser);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: bottomInset + 24,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1528),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, -5),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag indicator
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title
          Text(
            _codeSent ? 'رمز التحقق (OTP)' : 'تسجيل الدخول برقم الهاتف',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),

          Text(
            _codeSent
                ? 'أدخل رمز التحقق (OTP) المكون من 6 أرقام لتأكيد حسابك ودخول التطبيق'
                : 'أدخل رقم هاتفك لتلقي رمز التحقق وتفعيل حسابك بأمان',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 20),

          // Info message box (if present)
          if (_infoMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0x3300E676),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00E676), width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Color(0xFF69F0AE), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _infoMessage!,
                      style: const TextStyle(color: Color(0xFFB9F6CA), fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Error box
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0x33FF5252),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFF5252), width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFFF8A80), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (!_codeSent) ...[
            // Phone input row
            Container(
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0x1AFFFFFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  // Country Code dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _countryCode,
                        dropdownColor: const Color(0xFF2A1C3B),
                        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 18),
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        items: _countries.map((c) {
                          return DropdownMenuItem<String>(
                            value: c['code'],
                            child: Row(
                              children: [
                                Text(c['flag'] ?? '', style: const TextStyle(fontSize: 16)),
                                const SizedBox(width: 6),
                                Text(c['code'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _countryCode = val);
                        },
                      ),
                    ),
                  ),
                  Container(width: 1, height: 28, color: Colors.white24),
                  const SizedBox(width: 12),
                  // Phone Number field
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 1),
                      decoration: const InputDecoration(
                        hintText: '10 1234 5678',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 15),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Send OTP Button
            ElevatedButton(
              onPressed: _isLoading ? null : _sendOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text(
                      'إرسال رمز التحقق (OTP)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ] else ...[
            // OTP 6-digit Input field
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0x1AFFFFFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                obscureText: false,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  letterSpacing: 12,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: '------',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 24, letterSpacing: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Verify Button
            ElevatedButton(
              onPressed: _isLoading ? null : _verifyOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text(
                      'تأكيد الرمز والدخول',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(height: 14),

            // Resend & Change Number Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _isLoading ? null : () => setState(() {
                    _codeSent = false;
                    _otpController.clear();
                    _errorMessage = null;
                    _infoMessage = null;
                  }),
                  icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 16),
                  label: const Text('تغيير الرقم', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ),
                TextButton(
                  onPressed: (_isLoading || _resendCountdown > 0) ? null : _sendOtp,
                  child: Text(
                    _resendCountdown > 0
                        ? 'إعادة الإرسال بعد ($_resendCountdown ث)'
                        : 'إعادة إرسال الرمز',
                    style: TextStyle(
                      color: _resendCountdown > 0 ? Colors.white38 : const Color(0xFFFFD700),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
