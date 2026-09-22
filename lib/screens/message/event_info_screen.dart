import 'package:flutter/material.dart';
import '../../config/r.dart';
import '../../services/dynamic_config_service.dart';
import '../../services/firebase_service.dart';
import '../../models/banner_config.dart';
import '../../core/widgets/cached_image.dart';
import '../../utils/app_action_navigator.dart';

class EventInfoScreen extends StatefulWidget {
  const EventInfoScreen({super.key});

  @override
  State<EventInfoScreen> createState() => _EventInfoScreenState();
}

class _EventInfoScreenState extends State<EventInfoScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final bgImg = DynamicConfigService().eventInfoBackgroundImage;
    final isCustomBg = bgImg.isNotEmpty;
    final textColor = isCustomBg ? Colors.white : const Color(0xFF1E2022);

    return Container(
      decoration: BoxDecoration(
        color: isCustomBg
            ? DynamicConfigService().eventInfoBackgroundColor
            : const Color(0xFFF7F8FA),
        image: isCustomBg
            ? DecorationImage(
                image: R.cachedImage(bgImg),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: isCustomBg ? Colors.transparent : Colors.white,
          elevation: isCustomBg ? 0 : 0.5,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: textColor,
              size: 20,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          centerTitle: true,
          title: Text(
            isAr ? 'معلومات الحدث' : 'Event Information',
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: StreamBuilder<List<BannerConfig>>(
          stream: _firebaseService.bannersStream(),
          builder: (context, snapshot) {
            final banners = snapshot.data ?? [];
            final displayList = banners.isNotEmpty
                ? banners
                : _getDefaultEventBanners(isAr);

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              itemCount: displayList.length,
              itemBuilder: (context, index) {
                final item = displayList[index];
                return _buildOfficialEventItem(item, isAr);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildOfficialEventItem(BannerConfig item, bool isAr) {
    final dateStr = _formatTimestamp(item.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Centered Time Badge (rc_time with rc_item_top_time_bg)
          if (dateStr.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                dateStr,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF8B8B8B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

          // Official Message Card (rc_official_msg_item.xml: officialContent with bg_fff_r8)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  AppActionNavigator.handleAction(
                    context,
                    actionType: item.actionType,
                    actionValue: item.actionValue,
                    rawLink: item.linkUrl,
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Banner Image (topImg with scaleType="centerCrop")
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                      child: item.imageUrl.isNotEmpty
                          ? CachedNetImage(
                              item.imageUrl,
                              height: 160,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                height: 160,
                                color: const Color(0xFFEEEEEE),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFFFD700),
                                  ),
                                ),
                              ),
                              error: (_, __, ___) => _buildDefaultBannerPlaceholder(),
                            )
                          : _buildDefaultBannerPlaceholder(),
                    ),

                    // Title (titleTv: 16dp bold black)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                      child: Text(
                        item.title?.isNotEmpty == true
                            ? item.title!
                            : (isAr ? 'حدث جديد في التطبيق' : 'New Platform Event'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E2022),
                          height: 1.3,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Content / Description (contentTv: 14dp dark grey)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                      child: Text(
                        _getEventDescription(item, isAr),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF4A4A4A),
                          height: 1.45,
                        ),
                      ),
                    ),

                    // Jump Panel (jumpPanel: topLine, jumpTv "اضغط للمعاينة", arrow)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Color(0xFFE6E6E6), width: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              isAr ? 'اضغط للمعاينة' : 'Click to View',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E2022),
                              ),
                            ),
                          ),
                          Image.asset(
                            isAr
                                ? 'assets/mipmap-xxhdpi/ic_gray_left_arrow.png'
                                : 'assets/mipmap-xxhdpi/ic_gray_right_arrow.png',
                            width: 14,
                            height: 14,
                            errorBuilder: (_, __, ___) => Icon(
                              isAr ? Icons.arrow_back_ios_rounded : Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: const Color(0xFF8B8B8B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultBannerPlaceholder() {
    return Container(
      height: 160,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF8A2387), Color(0xFFE94057), Color(0xFFF27121)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.stars_rounded, color: Colors.white, size: 52),
            SizedBox(height: 6),
            Text(
              'ZORO EVENTS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getEventDescription(BannerConfig item, bool isAr) {
    if (item.actionValue != null && item.actionValue!.isNotEmpty) {
      if (item.actionValue!.contains('recharge')) {
        return isAr
            ? 'احصل على مكافآت ذهبية وجواهر إضافية عند شحن رصيدك خلال فترة الفعالية! اغتنم الفرصة الآن وتصدر قائمة الشاحنين.'
            : 'Get exclusive gold rewards and bonus diamonds upon recharging during the event period! Take advantage now and top the leaderboards.';
      }
    }
    return isAr
        ? 'شارك في الفعاليات والأنشطة المميزة واربح هدايا حصرية وجوائز قيمة داخل الغرف الصوتية.'
        : 'Participate in special events and activities to win exclusive gifts and valuable rewards across voice rooms.';
  }

  String _formatTimestamp(int timestamp) {
    if (timestamp <= 0) {
      final now = DateTime.now();
      return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    }
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  List<BannerConfig> _getDefaultEventBanners(bool isAr) {
    return [
      BannerConfig(
        id: 'event_summer_2026',
        title: isAr ? 'مسابقة الصيف الكبرى لعام 2026' : 'Grand Summer Championship 2026',
        imageUrl: '',
        actionType: 'screen',
        actionValue: '/recharge_event',
        createdAt: DateTime.now().millisecondsSinceEpoch - 3600000,
      ),
      BannerConfig(
        id: 'event_agency_honor',
        title: isAr ? 'دوري الشرف وتكريم الوكلاء المميزين' : 'League of Honor: Top Agencies',
        imageUrl: '',
        actionType: 'screen',
        actionValue: '/host_agency',
        createdAt: DateTime.now().millisecondsSinceEpoch - 86400000,
      ),
    ];
  }
}
