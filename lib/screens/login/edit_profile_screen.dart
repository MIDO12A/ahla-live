import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/supabase_service.dart';
import '../../services/cloudinary_service.dart';
import '../../providers/user_provider.dart';
import '../../core/ui/in_app_toast.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _signatureController = TextEditingController();
  String _selectedGender = 'male';
  String _selectedCountry = 'EG';
  File? _selectedImage;
  bool _isLoading = false;
  DateTime? _selectedBirthday;
  final List<String> _albumPhotos = [];

  final List<Map<String, String>> _arabCountries = [
    {'code': 'EG', 'name': 'مصر', 'flag': '🇪🇬'},
    {'code': 'SA', 'name': 'السعودية', 'flag': '🇸🇦'},
    {'code': 'AE', 'name': 'الإمارات', 'flag': '🇦🇪'},
    {'code': 'KW', 'name': 'الكويت', 'flag': '🇰🇼'},
    {'code': 'QA', 'name': 'قطر', 'flag': '🇶🇦'},
    {'code': 'BH', 'name': 'البحرين', 'flag': '🇧🇭'},
    {'code': 'OM', 'name': 'عمان', 'flag': '🇴🇲'},
    {'code': 'IQ', 'name': 'العراق', 'flag': '🇮🇶'},
    {'code': 'SY', 'name': 'سوريا', 'flag': '🇸🇾'},
    {'code': 'LB', 'name': 'لبنان', 'flag': '🇱🇧'},
    {'code': 'JO', 'name': 'الأردن', 'flag': '🇯🇴'},
    {'code': 'PS', 'name': 'فلسطين', 'flag': '🇵🇸'},
    {'code': 'YE', 'name': 'اليمن', 'flag': '🇾🇪'},
    {'code': 'DZ', 'name': 'الجزائر', 'flag': '🇩🇿'},
    {'code': 'MA', 'name': 'المغرب', 'flag': '🇲🇦'},
    {'code': 'TN', 'name': 'تونس', 'flag': '🇹🇳'},
    {'code': 'LY', 'name': 'ليبيا', 'flag': '🇱🇾'},
    {'code': 'SD', 'name': 'السودان', 'flag': '🇸🇩'},
    {'code': 'MR', 'name': 'موريتانيا', 'flag': '🇲🇷'},
    {'code': 'SO', 'name': 'الصومال', 'flag': '🇸🇴'},
    {'code': 'DJ', 'name': 'جيبوتي', 'flag': '🇩🇯'},
    {'code': 'KM', 'name': 'جزر القمر', 'flag': '🇰🇲'},
  ];

  @override
  void initState() {
    super.initState();
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user != null) {
      _nameController.text = user.name;
      _signatureController.text = user.signature;
      _selectedGender = user.gender.isNotEmpty ? user.gender : 'male';
      _selectedCountry = user.country.isNotEmpty ? user.country : 'EG';
      final age = user.age > 0 ? user.age : 20;
      _selectedBirthday = DateTime(DateTime.now().year - age, 1, 1);
      _albumPhotos.addAll(user.album);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  Future<void> _addAlbumPhoto() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (image != null) {
      setState(() {
        _albumPhotos.add(image.path);
      });
    }
  }

  Future<void> _selectBirthday() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedBirthday ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFFF7E40),
              onPrimary: Colors.white,
              onSurface: Color(0xFF16151A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedBirthday = picked;
      });
    }
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'اختر الدولة / المنطقة',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF16151A),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: _arabCountries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) {
                    final country = _arabCountries[index];
                    final isSelected = country['code'] == _selectedCountry;
                    return ListTile(
                      leading: Text(country['flag']!, style: const TextStyle(fontSize: 26)),
                      title: Text(
                        country['name']!,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? const Color(0xFFFF7E40) : const Color(0xFF16151A),
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded, color: Color(0xFFFF7E40), size: 20)
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedCountry = country['code']!;
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      KayanInAppToast.warning('الرجاء إدخال الاسم المستعار');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final currentUser = userProvider.currentUser;
      if (currentUser == null) {
        KayanInAppToast.warning('لم يتم العثور على المستخدم');
        return;
      }

      String photoUrl = currentUser.photoUrl;
      if (photoUrl.isEmpty) {
        final authPhoto = FirebaseAuth.instance.currentUser?.photoURL;
        if (authPhoto != null && authPhoto.isNotEmpty) {
          photoUrl = authPhoto;
        }
      }

      // Upload image if selected
      if (_selectedImage != null) {
        final cid = currentUser.customId.isNotEmpty ? currentUser.customId : currentUser.uid.replaceAll('-', '').substring(0, 7);
        try {
          final uploaded = await CloudinaryService().uploadImage(
            _selectedImage!,
            publicId: 'user_' + cid,
          );
          if (uploaded.isNotEmpty) {
            photoUrl = uploaded;
          }
        } catch (e) {
          debugPrint('Error uploading profile image: $e');
        }
      }

      int computedAge = currentUser.age;
      if (_selectedBirthday != null) {
        computedAge = DateTime.now().year - _selectedBirthday!.year;
        if (computedAge < 1) computedAge = 1;
      }

      // Upload album photos that are local files
      final List<String> finalAlbum = [];
      for (int i = 0; i < _albumPhotos.length; i++) {
        final p = _albumPhotos[i];
        if (p.startsWith('http://') || p.startsWith('https://')) {
          finalAlbum.add(p);
        } else {
          try {
            final cid = currentUser.customId.isNotEmpty ? currentUser.customId : currentUser.uid.replaceAll('-', '').substring(0, 7);
            final uploaded = await CloudinaryService().uploadImage(
              File(p),
              publicId: 'album_${cid}_${i}_${DateTime.now().millisecondsSinceEpoch}',
            );
            if (uploaded.isNotEmpty) {
              finalAlbum.add(uploaded);
            }
          } catch (e) {
            debugPrint('Failed to upload album image $i: $e');
          }
        }
      }

      // Update user
      final updatedUser = currentUser.copyWith(
        album: finalAlbum,
        activeCover: currentUser.activeCover,
        profileBgUrl: currentUser.profileBgUrl,
        name: name,
        photoUrl: photoUrl,
        gender: _selectedGender,
        signature: _signatureController.text.trim(),
        country: _selectedCountry,
        age: computedAge,
      );

      await SupabaseService().saveUser(updatedUser);
      await SupabaseService().updateUser(currentUser.uid, {
        'name': name,
        'photo_url': photoUrl,
        'photoUrl': photoUrl,
        'avatar': photoUrl,
        'avatar_url': photoUrl,
        'gender': _selectedGender,
        'signature': _signatureController.text.trim(),
        'country': _selectedCountry,
        'age': computedAge,
        'album': finalAlbum,
        'albums': finalAlbum,
      });

      if (mounted) {
        await userProvider.loadUser(currentUser.uid);
        KayanInAppToast.success('تم حفظ التعديلات بنجاح');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        KayanInAppToast.warning('خطأ أثناء الحفظ: $e');
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
    final user = Provider.of<UserProvider>(context).currentUser;
    final currentAvatar = (user?.photoUrl != null && user!.photoUrl.isNotEmpty)
        ? user.photoUrl
        : (FirebaseAuth.instance.currentUser?.photoURL ?? '');
    final countryObj = _arabCountries.firstWhere(
      (c) => c['code'] == _selectedCountry,
      orElse: () => _arabCountries.first,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Image.asset(
            'assets/mipmap-xxhdpi/common_back_2.webp',
            width: 24,
            height: 24,
            errorBuilder: (_, __, ___) => const Icon(Icons.arrow_back_ios, color: Color(0xFF16151A), size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'تعديل الملف الشخصي',
          style: TextStyle(
            color: Color(0xFF16151A),
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    // cl_avatar (layout_mineinfo_edit.xml)
                    _buildAvatarSection(currentAvatar),
                    const SizedBox(height: 24),
                    // Nickname label & container
                    _buildSectionTitle('الاسم المستعار'),
                    const SizedBox(height: 10),
                    _buildNicknameInput(),
                    const SizedBox(height: 20),
                    // Gender label & container
                    _buildSectionTitle('الجنس'),
                    const SizedBox(height: 10),
                    _buildGenderSelector(),
                    const SizedBox(height: 20),
                    // Photo album label & container
                    _buildSectionTitle('ألبوم الصور'),
                    const SizedBox(height: 10),
                    _buildAlbumSection(),
                    const SizedBox(height: 20),
                    // Country / Region
                    _buildSectionTitle('البلد / المنطقة'),
                    const SizedBox(height: 10),
                    _buildCountrySelector(countryObj),
                    const SizedBox(height: 20),
                    // Birthday
                    _buildSectionTitle('تاريخ الميلاد'),
                    const SizedBox(height: 10),
                    _buildBirthdaySelector(),
                    const SizedBox(height: 20),
                    // Signature
                    _buildSectionTitle('التوقيع الشخصي'),
                    const SizedBox(height: 10),
                    _buildSignatureInput(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            // Bottom Save Button (tv_sure in layout_mineinfo_edit.xml)
            _buildBottomSaveButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF16151A),
      ),
    );
  }

  Widget _buildAvatarSection(String currentPhotoUrl) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'تعديل الملف الشخصي',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF16151A),
          ),
        ),
        GestureDetector(
          onTap: _pickImage,
          child: Stack(
            children: [
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: const Color(0xFFF5F6FA),
                  border: Border.all(color: const Color(0xFFEEEEEE), width: 1.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: _selectedImage != null
                      ? Image.file(_selectedImage!, fit: BoxFit.cover)
                      : (currentPhotoUrl.isNotEmpty
                          ? Image.network(
                              currentPhotoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 54, color: Colors.grey),
                            )
                          : const Icon(Icons.person, size: 54, color: Colors.grey)),
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Image.asset(
                  'assets/mipmap-xxhdpi/mine_camera_ic.webp',
                  width: 28,
                  height: 28,
                  errorBuilder: (_, __, ___) => Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNicknameInput() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _nameController,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF16151A),
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                hintText: 'أدخل الاسم المستعار',
                hintStyle: TextStyle(color: Color(0xFF9BA1B6), fontSize: 14),
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_nameController.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _nameController.clear();
                setState(() {});
              },
              child: Image.asset(
                'assets/mipmap-xxhdpi/mine_close_ic.webp',
                width: 18,
                height: 18,
                errorBuilder: (_, __, ___) => const Icon(Icons.cancel, size: 18, color: Color(0xFF9BA1B6)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGenderSelector() {
    final isMale = _selectedGender == 'male';
    final isFemale = _selectedGender == 'female';

    return Row(
      children: [
        // Male button (ll_male)
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedGender = 'male'),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: isMale ? const Color(0xFFEBF3FF) : const Color(0xFFF5F6FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isMale ? const Color(0xFF3597FF) : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/mipmap-xxhdpi/sex_male_2_ic.webp',
                    width: 24,
                    height: 24,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.male,
                      color: isMale ? const Color(0xFF3597FF) : const Color(0xFF9BA1B6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ذكر',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isMale ? FontWeight.bold : FontWeight.normal,
                      color: isMale ? const Color(0xFF3597FF) : const Color(0xFF9BA1B6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Female button (ll_female)
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedGender = 'female'),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: isFemale ? const Color(0xFFFFF0F8) : const Color(0xFFF5F6FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isFemale ? const Color(0xFFFE72DC) : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/mipmap-xxhdpi/sex_female_4_ic.webp',
                    width: 24,
                    height: 24,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.female,
                      color: isFemale ? const Color(0xFFFE72DC) : const Color(0xFF9BA1B6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'أنثى',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isFemale ? FontWeight.bold : FontWeight.normal,
                      color: isFemale ? const Color(0xFFFE72DC) : const Color(0xFF9BA1B6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumSection() {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _albumPhotos.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            // Add Photo Button
            return GestureDetector(
              onTap: _addAlbumPhoto,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E4EB), style: BorderStyle.solid),
                ),
                child: Center(
                  child: Image.asset(
                    'assets/mipmap-xxhdpi/mine_photo_add_ic.webp',
                    width: 28,
                    height: 28,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.add_photo_alternate_rounded,
                      size: 28,
                      color: Color(0xFF9BA1B6),
                    ),
                  ),
                ),
              ),
            );
          }
          final photoPath = _albumPhotos[index - 1];
          final isNetwork = photoPath.startsWith('http://') || photoPath.startsWith('https://');
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: isNetwork
                    ? Image.network(
                        photoPath,
                        width: 76,
                        height: 76,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 36, color: Colors.grey),
                      )
                    : Image.file(
                        File(photoPath),
                        width: 76,
                        height: 76,
                        fit: BoxFit.cover,
                      ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _albumPhotos.removeAt(index - 1);
                    });
                  },
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCountrySelector(Map<String, String> countryObj) {
    return GestureDetector(
      onTap: _showCountryPicker,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6FA),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Text(
              countryObj['flag'] ?? '🌍',
              style: const TextStyle(fontSize: 22),
            ),
            const SizedBox(width: 10),
            Text(
              countryObj['name'] ?? 'مصر',
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
    );
  }

  Widget _buildBirthdaySelector() {
    final dateStr = _selectedBirthday != null
        ? '${_selectedBirthday!.year}-${_selectedBirthday!.month.toString().padLeft(2, '0')}-${_selectedBirthday!.day.toString().padLeft(2, '0')}'
        : 'اختر تاريخ الميلاد';

    return GestureDetector(
      onTap: _selectBirthday,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6FA),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Text(
              dateStr,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: _selectedBirthday != null ? const Color(0xFF16151A) : const Color(0xFF9BA1B6),
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
    );
  }

  Widget _buildSignatureInput() {
    return Container(
      constraints: const BoxConstraints(minHeight: 93),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _signatureController,
        maxLength: 200,
        maxLines: 4,
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF16151A),
        ),
        decoration: const InputDecoration(
          hintText: 'اكتب شيئاً عن نفسك...',
          hintStyle: TextStyle(color: Color(0xFF9BA1B6), fontSize: 13),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildBottomSaveButton() {
    return Container(
      width: double.infinity,
      height: 50,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF7E40)))
          : Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF9500), Color(0xFFFF5E3A)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF7E40).withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: const Text(
                  'تأكيد',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
    );
  }
}
