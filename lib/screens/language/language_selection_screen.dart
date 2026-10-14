import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_colors.dart';
import '../../providers/locale_provider.dart';
import '../../l10n/app_localizations.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  late String _selectedLanguage;

  final List<Map<String, String>> _languages = [
    {'code': 'en', 'name': 'English', 'flag': '🇺🇸'},
    {'code': 'ar', 'name': 'العربية', 'flag': '🇸🇦'},
  ];

  @override
  void initState() {
    super.initState();
    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
    _selectedLanguage = localeProvider.locale?.languageCode ?? 'ar';
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
    
    return Scaffold(
      backgroundColor: AppColors.colorF5F7FB,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                itemCount: _languages.length,
                itemBuilder: (context, index) {
                  final lang = _languages[index];
                  final isSelected = _selectedLanguage == lang['code'];
                  return ListTile(
                    leading: Text(
                      lang['flag']!,
                      style: const TextStyle(fontSize: 24),
                    ),
                    title: Text(
                      lang['name']!,
                      style: TextStyle(
                        color: isSelected ? AppColors.colorPrimary : Colors.black,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: AppColors.colorPrimary)
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedLanguage = lang['code']!;
                      });
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () async {
                    await localeProvider.setLocale(Locale(_selectedLanguage));
                    if (mounted) {
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.colorPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context).save,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
