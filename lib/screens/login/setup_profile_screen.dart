import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:math';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../services/supabase_service.dart';
import '../../services/cloudinary_service.dart';
import '../../services/supabase_auth_service.dart';
import '../../providers/user_provider.dart';
import '../../models/user_model.dart';
import '../../core/utils/id_generator.dart';
import '../../services/device_service.dart';
import '../main_screen/main_screen.dart';
import '../country/country_picker_screen.dart';
import 'package:zero/core/dtext.dart';

class SetupProfileScreen extends StatefulWidget {
  final String uid;
  final String email;
  final String photoUrl;
  final String phone;

  const SetupProfileScreen({
    super.key,
    required this.uid,
    required this.email,
    required this.photoUrl,
    this.phone = '',
  });

  @override
  State<SetupProfileScreen> createState() => _SetupProfileScreenState();
}

class _SetupProfileScreenState extends State<SetupProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  String _selectedGender = 'male';
  String _selectedCountry = 'EG';
  File? _selectedImage;
  bool _isLoading = false;

  String _getCountryName(String code) {
    final countries = {
      'EG': 'مصر', 'SA': 'السعودية', 'AE': 'الإمارات', 'KW': 'الكويت',
      'QA': 'قطر', 'BH': 'البحرين', 'OM': 'عُمان', 'IQ': 'العراق',
      'JO': 'الأردن', 'SY': 'سوريا', 'LB': 'لبنان', 'PS': 'فلسطين',
      'YE': 'اليمن', 'SD': 'السودان', 'LY': 'ليبيا', 'TN': 'تونس',
      'DZ': 'الجزائر', 'MA': 'المغرب', 'MR': 'موريتانيا', 'SO': 'الصومال',
      'DJ': 'جيبوتي', 'KM': 'جزر القمر', 'TR': 'تركيا', 'US': 'الولايات المتحدة',
      'GB': 'المملكة المتحدة', 'DE': 'ألمانيا', 'FR': 'فرنسا', 'IT': 'إيطاليا',
      'ES': 'إسبانيا', 'CA': 'كندا', 'RU': 'روسيا', 'CN': 'الصين',
      'IN': 'الهند', 'PK': 'باكستان', 'ID': 'إندونيسيا', 'MY': 'ماليزيا',
      'BR': 'البرازيل', 'SE': 'السويد', 'NL': 'هولندا', 'AU': 'أستراليا',
    };
    return countries[code.toUpperCase()] ?? code;
  }

  String _getFlagEmoji(String code) {
    final flags = {
      'EG': '🇪🇬', 'SA': '🇸🇦', 'AE': '🇦🇪', 'KW': '🇰🇼', 'QA': '🇶🇦',
      'BH': '🇧🇭', 'OM': '🇴🇲', 'IQ': '🇮🇶', 'JO': '🇯🇴', 'SY': '🇸🇾',
      'LB': '🇱🇧', 'PS': '🇵🇸', 'YE': '🇾🇪', 'SD': '🇸🇩', 'LY': '🇱🇾',
      'TN': '🇹🇳', 'DZ': '🇩🇿', 'MA': '🇲🇦', 'MR': '🇲🇷', 'SO': '🇸🇴',
      'DJ': '🇩🇯', 'KM': '🇰🇲', 'TR': '🇹🇷', 'US': '🇺🇸', 'GB': '🇬🇧',
      'DE': '🇩🇪', 'FR': '🇫🇷', 'IT': '🇮🇹', 'ES': '🇪🇸', 'CA': '🇨🇦',
      'RU': '🇷🇺', 'CN': '🇨🇳', 'IN': '🇮🇳', 'PK': '🇵🇰', 'ID': '🇮🇩',
      'MY': '🇲🇾', 'BR': '🇧🇷', 'SE': '🇸🇪', 'NL': '🇳🇱', 'AU': '🇦🇺',
    };
    return flags[code.toUpperCase()] ?? '🏳️';
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: DText('الرجاء إدخال الاسم')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String photoUrl = widget.photoUrl;

      // Generate unique custom ID (6-7 digits)
      String customId;
      try {
        customId = await UserIdGenerator().generateUniqueId(minDigits: 6, maxDigits: 7);
      } catch (_) {
        final rng = Random();
        final is7 = rng.nextBool();
        customId = is7
            ? (1000000 + rng.nextInt(9000000)).toString()
            : (100000 + rng.nextInt(900000)).toString();
      }

      if (_selectedImage != null) {
        photoUrl = await CloudinaryService().uploadImage(
          _selectedImage!,
          publicId: 'user_$customId',
        );
      }

      final deviceInfo = await DeviceService().getDeviceInfo();

      // Create user with custom numeric ID
      final user = UserModel(
        uid: widget.uid,
        customId: customId,
        name: _nameController.text.trim(),
        email: widget.email,
        photoUrl: photoUrl,
        gender: _selectedGender,
        country: _selectedCountry,
        coins: 10000,
        phone: widget.phone,
        deviceId: deviceInfo.deviceId,
        deviceModel: deviceInfo.deviceModel,
        macAddress: deviceInfo.macAddress,
        networkId: deviceInfo.networkId,
        ipAddress: deviceInfo.ipAddress,
        ownedItems: [],
      );

      await SupabaseService().saveUser(user);

      // Sync user profile directly to Supabase public.users
      try {
        await SupabaseAuthService().syncUserToSupabase(
          uid: widget.uid,
          customId: customId,
          name: _nameController.text.trim(),
          email: widget.email,
          photoUrl: photoUrl,
          gender: _selectedGender,
          country: _selectedCountry,
          coins: 10000,
          phone: widget.phone,
        );
        await SupabaseService().updateUser(widget.uid, deviceInfo.toMap());
        await DeviceService().saveDeviceRegistration(widget.uid, email: widget.email, info: deviceInfo);
      } catch (_) {}

      try {
        await SupabaseAuthService().saveSession(
          uid: widget.uid,
          email: widget.email,
          name: _nameController.text.trim(),
          photoUrl: photoUrl,
          phone: widget.phone,
        );
      } catch (_) {}

      if (mounted) {
        await Provider.of<UserProvider>(context, listen: false)
            .loadUser(widget.uid);
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: DText('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F5FC),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                // Avatar
                GestureDetector(
                  onTap: _pickImage,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey[300],
                        ),
                        child: ClipOval(
                          child: _selectedImage != null
                              ? Image.file(
                                  _selectedImage!,
                                  fit: BoxFit.cover,
                                  width: 120,
                                  height: 120,
                                )
                              : widget.photoUrl.isNotEmpty
                                  ? Image(
                                      image: R.cachedImage(widget.photoUrl),
                                      fit: BoxFit.cover,
                                      width: 120,
                                      height: 120,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Image.asset(
                                          R.avaBoy,
                                          fit: BoxFit.cover,
                                        );
                                      },
                                    )
                                  : Image.asset(
                                      R.avaBoy,
                                      fit: BoxFit.cover,
                                    ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Name Field
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _nameController,
                    style: const TextStyle(color: Color(0xFF16151A), fontSize: 15),
                    decoration: const InputDecoration(
                      hintText: 'الاسم',
                      hintStyle: TextStyle(color: Color(0x9916151A)),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Age Field
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Color(0xFF16151A), fontSize: 15),
                    decoration: const InputDecoration(
                      hintText: 'العمر',
                      hintStyle: TextStyle(color: Color(0x9916151A)),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Gender Selection
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const DText(
                          'الجنس',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF16151A),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedGender = 'male';
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _selectedGender == 'male'
                                        ? Colors.blue
                                        : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Image.asset(
                                        'assets/mipmap-xxhdpi/ic_sex_boy.webp',
                                        width: 24,
                                        height: 24,
                                        color: _selectedGender == 'male'
                                            ? Colors.white
                                            : Colors.grey,
                                      ),
                                      const SizedBox(width: 8),
                                      DText(
                                        'ذكر',
                                        style: TextStyle(
                                          color: _selectedGender == 'male'
                                              ? Colors.white
                                              : Colors.black,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedGender = 'female';
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _selectedGender == 'female'
                                        ? Colors.pink
                                        : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Image.asset(
                                        'assets/mipmap-xxhdpi/ic_sex_boy.webp',
                                        width: 24,
                                        height: 24,
                                        color: _selectedGender == 'female'
                                            ? Colors.white
                                            : Colors.grey,
                                      ),
                                      const SizedBox(width: 8),
                                      DText(
                                        'أنثى',
                                        style: TextStyle(
                                          color: _selectedGender == 'female'
                                              ? Colors.white
                                              : Colors.black,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Country Selection
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const DText(
                          'الدولة',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF16151A),
                          ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CountryPickerScreen(),
                              ),
                            );
                            // ✅ CountryPicker يرجّع كائن Country (مش String) —
                            //    كنا بنقارن بـ String فالاختيار اتضاع وفضل العلم EG.
                            if (result is Country) {
                              setState(() {
                                _selectedCountry = result.code;
                              });
                            } else if (result is String && result.isNotEmpty) {
                              setState(() {
                                _selectedCountry = result;
                              });
                            }
                          },
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F6FA),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: Image(
                                    image: R.cachedImage(
                                        'https://flagcdn.com/w40/${_selectedCountry.toLowerCase()}.png'),
                                    width: 24,
                                    height: 16,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => DText(
                                      _getFlagEmoji(_selectedCountry),
                                      style: const TextStyle(fontSize: 20),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                DText(
                                  _getCountryName(_selectedCountry),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF16151A),
                                  ),
                                ),
                                const Spacer(),
                                Image.asset(
                                  'assets/mipmap-xxhdpi/next_2_ic.webp',
                                  width: 16,
                                  height: 16,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 14,
                                    color: Color(0xFF9BA1B6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // Save Button
                _isLoading
                    ? const CircularProgressIndicator()
                    : SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _saveProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFCC80),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          child: const DText(
                            'حفظ',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF894916),
                            ),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}