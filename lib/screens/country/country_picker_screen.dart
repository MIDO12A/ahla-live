import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../services/firebase_service.dart';
import '../../services/supabase_data_service.dart';
import '../../core/ui/in_app_toast.dart';

class Country {
  final String name;
  final String nameEn;
  final String code;
  final String flag;
  final String dialCode;

  const Country({
    required this.name,
    required this.nameEn,
    required this.code,
    required this.flag,
    required this.dialCode,
  });
}

class CountryPickerScreen extends StatefulWidget {
  const CountryPickerScreen({super.key});

  @override
  State<CountryPickerScreen> createState() => _CountryPickerScreenState();
}

class _CountryPickerScreenState extends State<CountryPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const List<Country> _allCountries = [
    // الدول العربية (Arabic Countries)
    Country(name: 'مصر', nameEn: 'Egypt', code: 'EG', flag: '🇪🇬', dialCode: '+20'),
    Country(name: 'المملكة العربية السعودية', nameEn: 'Saudi Arabia', code: 'SA', flag: '🇸🇦', dialCode: '+966'),
    Country(name: 'الإمارات العربية المتحدة', nameEn: 'United Arab Emirates', code: 'AE', flag: '🇦🇪', dialCode: '+971'),
    Country(name: 'الكويت', nameEn: 'Kuwait', code: 'KW', flag: '🇰🇼', dialCode: '+965'),
    Country(name: 'قطر', nameEn: 'Qatar', code: 'QA', flag: '🇶🇦', dialCode: '+974'),
    Country(name: 'البحرين', nameEn: 'Bahrain', code: 'BH', flag: '🇧🇭', dialCode: '+973'),
    Country(name: 'عُمان', nameEn: 'Oman', code: 'OM', flag: '🇴🇲', dialCode: '+968'),
    Country(name: 'العراق', nameEn: 'Iraq', code: 'IQ', flag: '🇮🇶', dialCode: '+964'),
    Country(name: 'الأردن', nameEn: 'Jordan', code: 'JO', flag: '🇯🇴', dialCode: '+962'),
    Country(name: 'سوريا', nameEn: 'Syria', code: 'SY', flag: '🇸🇾', dialCode: '+963'),
    Country(name: 'لبنان', nameEn: 'Lebanon', code: 'LB', flag: '🇱🇧', dialCode: '+961'),
    Country(name: 'فلسطين', nameEn: 'Palestine', code: 'PS', flag: '🇵🇸', dialCode: '+970'),
    Country(name: 'اليمن', nameEn: 'Yemen', code: 'YE', flag: '🇾🇪', dialCode: '+967'),
    Country(name: 'السودان', nameEn: 'Sudan', code: 'SD', flag: '🇸🇩', dialCode: '+249'),
    Country(name: 'ليبيا', nameEn: 'Libya', code: 'LY', flag: '🇱🇾', dialCode: '+218'),
    Country(name: 'تونس', nameEn: 'Tunisia', code: 'TN', flag: '🇹🇳', dialCode: '+216'),
    Country(name: 'الجزائر', nameEn: 'Algeria', code: 'DZ', flag: '🇩🇿', dialCode: '+213'),
    Country(name: 'المغرب', nameEn: 'Morocco', code: 'MA', flag: '🇲🇦', dialCode: '+212'),
    Country(name: 'موريتانيا', nameEn: 'Mauritania', code: 'MR', flag: '🇲🇷', dialCode: '+222'),
    Country(name: 'الصومال', nameEn: 'Somalia', code: 'SO', flag: '🇸🇴', dialCode: '+252'),
    Country(name: 'جيبوتي', nameEn: 'Djibouti', code: 'DJ', flag: '🇩🇯', dialCode: '+253'),
    Country(name: 'جزر القمر', nameEn: 'Comoros', code: 'KM', flag: '🇰🇲', dialCode: '+269'),

    // دول إقليمية ودولية (International Countries)
    Country(name: 'تركيا', nameEn: 'Turkey', code: 'TR', flag: '🇹🇷', dialCode: '+90'),
    Country(name: 'الولايات المتحدة الأمريكية', nameEn: 'United States', code: 'US', flag: '🇺🇸', dialCode: '+1'),
    Country(name: 'المملكة المتحدة', nameEn: 'United Kingdom', code: 'GB', flag: '🇬🇧', dialCode: '+44'),
    Country(name: 'ألمانيا', nameEn: 'Germany', code: 'DE', flag: '🇩🇪', dialCode: '+49'),
    Country(name: 'فرنسا', nameEn: 'France', code: 'FR', flag: '🇫🇷', dialCode: '+33'),
    Country(name: 'إيطاليا', nameEn: 'Italy', code: 'IT', flag: '🇮🇹', dialCode: '+39'),
    Country(name: 'إسبانيا', nameEn: 'Spain', code: 'ES', flag: '🇪🇸', dialCode: '+34'),
    Country(name: 'كندا', nameEn: 'Canada', code: 'CA', flag: '🇨🇦', dialCode: '+1'),
    Country(name: 'روسيا', nameEn: 'Russia', code: 'RU', flag: '🇷🇺', dialCode: '+7'),
    Country(name: 'الصين', nameEn: 'China', code: 'CN', flag: '🇨🇳', dialCode: '+86'),
    Country(name: 'الهند', nameEn: 'India', code: 'IN', flag: '🇮🇳', dialCode: '+91'),
    Country(name: 'باكستان', nameEn: 'Pakistan', code: 'PK', flag: '🇵🇰', dialCode: '+92'),
    Country(name: 'إندونيسيا', nameEn: 'Indonesia', code: 'ID', flag: '🇮🇩', dialCode: '+62'),
    Country(name: 'ماليزيا', nameEn: 'Malaysia', code: 'MY', flag: '🇲🇾', dialCode: '+60'),
    Country(name: 'البرازيل', nameEn: 'Brazil', code: 'BR', flag: '🇧🇷', dialCode: '+55'),
    Country(name: 'السويد', nameEn: 'Sweden', code: 'SE', flag: '🇸🇪', dialCode: '+46'),
    Country(name: 'هولندا', nameEn: 'Netherlands', code: 'NL', flag: '🇳🇱', dialCode: '+31'),
    Country(name: 'أستراليا', nameEn: 'Australia', code: 'AU', flag: '🇦🇺', dialCode: '+61'),
  ];

  List<Country> _filteredCountries = [];

  @override
  void initState() {
    super.initState();
    _filteredCountries = _allCountries;
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredCountries = _allCountries;
      } else {
        _filteredCountries = _allCountries.where((c) {
          return c.name.toLowerCase().contains(query) ||
              c.nameEn.toLowerCase().contains(query) ||
              c.code.toLowerCase().contains(query) ||
              c.dialCode.contains(query);
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _selectCountry(Country country) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user != null) {
      final updatedUser = user.copyWith(country: country.code);
      // 1. تحديث الذاكرة المحلية الفوري
      await userProvider.updateUser(updatedUser);
      // 2. تحديث السيرفرات (Firebase & Supabase)
      await FirebaseService().updateUser(user.uid, {
        'country': country.code,
        'country_code': country.code.toLowerCase(),
      });
      await SupabaseDataService().updateUser(user.uid, {
        'country': country.code,
        'country_code': country.code.toLowerCase(),
      });
      KayanInAppToast.success('تم تغيير الدولة بنجاح إلى ${country.name} ${country.flag}');
    }

    if (mounted) {
      Navigator.pop(context, country);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final currentCountryCode = userProvider.currentUser?.country.toUpperCase() ?? 'EG';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: const Text(
          'اختر الدولة / المنطقة',
          style: TextStyle(
            color: Color(0xFF16151A),
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF16151A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'ابحث عن دولة أو رمز...',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF999999), size: 20),
                filled: true,
                fillColor: const Color(0xFFF2F4F8),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              textInputAction: TextInputAction.search,
            ),
          ),
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _filteredCountries.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 64, endIndent: 16),
              itemBuilder: (context, index) {
                final country = _filteredCountries[index];
                final isSelected = country.code.toUpperCase() == currentCountryCode;

                return InkWell(
                  onTap: () => _selectCountry(country),
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Text(country.flag, style: const TextStyle(fontSize: 26)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                country.name,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? const Color(0xFFFF7E40) : const Color(0xFF16151A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${country.nameEn} (${country.code})',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          country.dialCode,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                        ),
                        const SizedBox(width: 8),
                        if (isSelected)
                          const Icon(Icons.check_circle_rounded, color: Color(0xFFFF7E40), size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
