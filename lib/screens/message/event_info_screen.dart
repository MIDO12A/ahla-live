import 'package:flutter/material.dart';
import '../../services/firebase_service.dart';
import '../../models/banner_config.dart';
import '../../core/widgets/cached_image.dart';
import '../../utils/app_action_navigator.dart';

/// Replicates [ActivityNotificationActivity.java] and [chat_adapter_activity_item.xml]
/// with [chat_event_ic.webp] from the original decompiled app (F:\Medal\New folder\nu).
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

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF16151A),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          isAr ? 'معلومات الحدث' : 'Activity Notifications',
          style: const TextStyle(
            color: Color(0xFF16151A),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: StreamBuilder<List<BannerConfig>>(
        stream: _firebaseService.bannersStream(),
        builder: (context, snapshot) {
          final banners = snapshot.data ?? [];
          final displayList =
              banners.isNotEmpty ? banners : _getDefaultEventBanners(isAr);

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: displayList.length,
            itemBuilder: (context, index) {
              final item = displayList[index];
              return _buildActivityNotificationItem(item, isAr);
            },
          );
        },
      ),
    );
  }

  /// List item matching [chat_adapter_activity_item.xml] with [chat_event_ic.webp]
  Widget _buildActivityNotificationItem(BannerConfig item, bool isAr) {
    final dateStr = _formatTimestamp(item.createdAt);
    final title = item.title?.isNotEmpty == true
        ? item.title!
        : (isAr ? 'حدث جديد في التطبيق' : 'Activity Notice');
    final content = _getEventDescription(item, isAr);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // tv_notification_time: 11sp, color #9BA1B6, paddingTop 16dp
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 10),
            child: Text(
              dateStr,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF9BA1B6),
              ),
            ),
          ),

          // Horizontal layout: iv_system_icon + chat_notification_shape_bg bubble
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // iv_system_icon: 45x45dp, @mipmap/chat_event_ic
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Image.asset(
                  'assets/mipmap-xxhdpi/chat_event_ic.webp',
                  width: 45,
                  height: 45,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 45,
                    height: 45,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF9500),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.celebration_rounded,
                        color: Colors.white, size: 24),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Bubble: chat_notification_shape_bg (White #FFFFFF, radius 16dp, padding 12dp)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    AppActionNavigator.handleAction(
                      context,
                      actionType: item.actionType,
                      actionValue: item.actionValue,
                      rawLink: item.linkUrl,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // tv_title: 15sp, sans-serif-medium, color #16151A
                        if (title.isNotEmpty) ...[
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF16151A),
                            ),
                          ),
                          // view_line: 0.5dp, #FFEDEDED, marginVertical 6dp
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Divider(
                              height: 0.5,
                              thickness: 0.5,
                              color: Color(0xFFEDEDED),
                            ),
                          ),
                        ],

                        // tv_notification_content: 13sp, color #16151A
                        if (content.isNotEmpty)
                          Text(
                            content,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF16151A),
                              height: 1.4,
                            ),
                          ),

                        // iv_notification_img: ratio 262:74, round corner radius 8dp, marginTop 6dp
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AspectRatio(
                              aspectRatio: 262 / 74,
                              child: item.imageUrl.isNotEmpty
                                  ? CachedNetImage(
                                      item.imageUrl,
                                      fit: BoxFit.cover,
                                      error: (_, __, ___) =>
                                          _buildDefaultBannerPlaceholder(),
                                    )
                                  : _buildDefaultBannerPlaceholder(),
                            ),
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
    );
  }

  Widget _buildDefaultBannerPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF8A2387), Color(0xFFE94057), Color(0xFFF27121)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.stars_rounded, color: Colors.white, size: 24),
            SizedBox(width: 8),
            Text(
              'ZORO EVENT',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 1.2,
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
      return '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    }
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  List<BannerConfig> _getDefaultEventBanners(bool isAr) {
    return [
      BannerConfig(
        id: 'event_summer_2026',
        title: isAr
            ? 'مسابقة الصيف الكبرى لعام 2026'
            : 'Grand Summer Championship 2026',
        imageUrl: '',
        actionType: 'screen',
        actionValue: '/recharge_event',
        createdAt: DateTime.now().millisecondsSinceEpoch - 3600000,
      ),
      BannerConfig(
        id: 'event_agency_honor',
        title: isAr
            ? 'دوري الشرف وتكريم الوكلاء المميزين'
            : 'League of Honor: Top Agencies',
        imageUrl: '',
        actionType: 'screen',
        actionValue: '/host_agency',
        createdAt: DateTime.now().millisecondsSinceEpoch - 86400000,
      ),
    ];
  }
}

