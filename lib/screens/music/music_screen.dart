import 'package:flutter/material.dart';
import '../../config/r.dart';
import '../../config/app_colors.dart';
import 'package:zero/core/dtext.dart';

class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _requestedSongs = {};

  final List<Map<String, String>> _songs = [
    {'title': 'نظر عيني', 'artist': 'محمد عبده'},
    {'title': 'أما براوة', 'artist': 'أصالة'},
    {'title': 'إنتي', 'artist': 'كاظم الساهر'},
    {'title': 'سامحني', 'artist': 'عبد المجيد عبد الله'},
    {'title': 'حبيبي يا ناسي', 'artist': 'راشد الماجد'},
    {'title': 'كل القصايد', 'artist': 'ماجد المهندس'},
    {'title': 'يا سيدي', 'artist': 'مشعل العبدلي'},
    {'title': 'أهل العشق', 'artist': 'نجوى كرم'},
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.roomBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: R.image(R.backIc, width: 28, height: 28),
                  ),
                  const SizedBox(width: 8),
                  const DText(
                    'طلب أغنية',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _searchController,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'ابحث عن أغنية...',
                  hintStyle: const TextStyle(color: AppColors.textTertiary),
                  hintTextDirection: TextDirection.rtl,
                  prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 22),
                  filled: true,
                  fillColor: AppColors.cardBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _songs.length,
                separatorBuilder: (_, __) => const Divider(
                  color: AppColors.divider,
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  final song = _songs[index];
                  final isRequested = _requestedSongs.contains(index);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primaryBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.music_note,
                            color: AppColors.goldLight,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              DText(
                                song['title']!,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              DText(
                                song['artist']!,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: isRequested
                              ? null
                              : () {
                                  setState(() => _requestedSongs.add(index));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: DText('تم طلب "${song['title']}"'),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isRequested
                                  ? AppColors.cardBg
                                  : AppColors.goldLight,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: DText(
                              isRequested ? 'تم الطلب' : 'طلب',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isRequested
                                    ? AppColors.textTertiary
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
