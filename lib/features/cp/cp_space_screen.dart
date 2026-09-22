import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../providers/user_provider.dart';
import '../../screens/room/widgets/svga_frame.dart';
import '../../services/dynamic_config_service.dart';
import 'cp_service.dart';
import 'cp_record_screen.dart';
import 'cp_dialogs.dart';
import 'cp_detail_full_screen.dart';

/// Relationship Space screen — matches act_relationship_space.xml
/// Shows: RS panel (avatars + heartbeat + token), progress bar, daily tasks.
class CpSpaceScreen extends StatefulWidget {
  const CpSpaceScreen({super.key});
  @override
  State<CpSpaceScreen> createState() => _CpSpaceScreenState();
}

class _CpSpaceScreenState extends State<CpSpaceScreen> {
  Map<String, dynamic> _data = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final data = await CpService.getMyData();
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = DynamicConfigService();
    final couple = _data['couple'] as Map<String, dynamic>?;
    final hasCp = _data['has_cp'] == true;
    final bgImg = cfg.cpSpaceBgImage;
    final title = cfg.cpSpaceTitle;

    Widget body = _loading
        ? const Center(child: CircularProgressIndicator())
        : !hasCp
            ? _buildNoCpState(cfg)
            : NestedScrollView(
                headerSliverBuilder: (context, innerBoxScrolled) {
                  return [
                    SliverAppBar(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      leading: IconButton(
                        icon: Image.asset('assets/cp/ic_cp_ranking_back.png', width: 26, height: 26,
                            errorBuilder: (_, __, ___) => const Icon(Icons.arrow_back, color: Colors.white)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      title: Text(title,
                          style: TextStyle(color: cfg.cpSpaceTextColor, fontSize: 16)),
                      centerTitle: true,
                      actions: [
                        IconButton(
                          icon: Image.asset('assets/cp/ic_cp_ranking_entrance.png', width: 26, height: 26,
                              errorBuilder: (_, __, ___) => const Icon(Icons.emoji_events, color: Colors.amber)),
                          tooltip: 'ترتيب CP',
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CPDetailFullScreen())),
                        ),
                      ],
                    ),
                  ];
                },
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (cfg.cpSpaceBannerImage.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: cfg.cpSpaceBannerImage.startsWith('http')
                                ? Image.network(cfg.cpSpaceBannerImage, height: 90, width: double.infinity, fit: BoxFit.cover)
                                : Image.asset(cfg.cpSpaceBannerImage, height: 90, width: double.infinity, fit: BoxFit.cover),
                          ),
                        ),
                      _buildTopSection(cfg, couple),
                      const SizedBox(height: 10),
                      _buildProgressBar(cfg, couple),
                      const SizedBox(height: 16),
                      _buildBorderSection(cfg),
                      const SizedBox(height: 12),
                      _buildTasksSection(cfg),
                    ],
                  ),
                ),
              );

    return Scaffold(
      backgroundColor: const Color(0xFF2e0d15),
      body: bgImg.isNotEmpty
          ? Container(
              decoration: BoxDecoration(
                image: bgImg.startsWith('http')
                    ? DecorationImage(image: NetworkImage(bgImg), fit: BoxFit.cover)
                    : DecorationImage(image: AssetImage(bgImg), fit: BoxFit.cover),
              ),
              child: body,
            )
          : body,
    );
  }

  Widget _buildNoCpState(DynamicConfigService cfg) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final bgImg = cfg.cpSpaceBgImage;
    return Stack(
      children: [
        Positioned.fill(
          child: bgImg.isNotEmpty
              ? (bgImg.startsWith('http')
                  ? Image.network(bgImg, fit: BoxFit.cover)
                  : Image.asset(bgImg, fit: BoxFit.cover))
              : Image.asset(
                  'assets/cp/ic_cp_main_bg_top.webp',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: const Color(0xFF2E0D15)),
                ),
        ),
        SafeArea(
          child: Column(
            children: [
              // Top Bar
              Row(
                children: [
                  IconButton(
                    icon: Image.asset('assets/cp/ic_cp_ranking_back.png', width: 28, height: 28,
                        errorBuilder: (_, __, ___) => const Icon(Icons.arrow_back, color: Colors.white)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Text(
                    cfg.cpSpaceTitle.isNotEmpty ? cfg.cpSpaceTitle : (isAr ? 'مساحة الـ CP' : 'CP Space'),
                    style: TextStyle(color: cfg.cpSpaceTextColor, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Image.asset('assets/cp/ic_cp_ranking_entrance.png', width: 28, height: 28,
                        errorBuilder: (_, __, ___) => const Icon(Icons.emoji_events, color: Colors.amber)),
                    tooltip: 'ترتيب CP',
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CPDetailFullScreen())),
                  ),
                ],
              ),
              const Spacer(),
              // Big Romantic Icon
              Image.asset(
                'assets/cp/ic_cp_love.png',
                width: 140,
                height: 140,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.favorite, color: Colors.pinkAccent, size: 100),
              ),
              const SizedBox(height: 24),
              Text(
                isAr ? 'ليس لديك علاقة CP حالياً' : 'No CP Relationship Yet',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  isAr ? 'ارتبط بشخص مميز وشاركه الهدايا والذكريات والألقاب الخاصة' : 'Find your special partner and share gifts, memories and titles',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
                ),
              ),
              const SizedBox(height: 32),
              // "ربط علاقة" button
              GestureDetector(
                onTap: () => _openPartnerSelector(isAr),
                child: Image.asset(
                  'assets/cp/ic_bind_relationship_btn.webp',
                  height: 48,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFE91E63), Color(0xFFFF4081)]),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      isAr ? 'ربط علاقة' : 'Bind Relationship',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ],
    );
  }

  void _openPartnerSelector(bool isAr) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF280B17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isAr ? 'اختر شريك الـ CP' : 'Select CP Partner',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isAr ? 'أدخل اسم أو معرف (ID) المستخدم الذي ترغب في الارتباط به:' : 'Enter User ID or name to link CP with:',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: textController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: isAr ? 'ID المستخدم' : 'User ID',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isAr ? 'إلغاء' : 'Cancel', style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final target = textController.text.trim();
              if (target.isEmpty) return;
              Navigator.pop(ctx);
              final result = await showSendRelationshipInvitationDialog(
                context,
                receiverName: target,
                receiverAvatar: '',
              );
              if (result != null) {
                try {
                  await CpService.sendRequest(
                    target,
                    giftId: result['gift_id'] ?? 'ring_1',
                    message: result['message'] ?? '',
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(isAr ? 'تم إرسال طلب الارتباط بنجاح! ❤️' : 'Proposal sent successfully! ❤️')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(isAr ? 'تم إرسال الدعوة إلى المستخدم' : 'Invitation sent')),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE91E63)),
            child: Text(isAr ? 'التالي' : 'Next', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSection(DynamicConfigService cfg, Map<String, dynamic>? couple) {
    final partner = couple?['partner'] as Map<String, dynamic>?;
    final user = context.read<UserProvider>().currentUser;
    final myAvatar = user?.photoUrl ?? '';
    final myName = user?.name ?? 'أنا';
    final partnerAvatar = partner?['avatar']?.toString() ?? '';
    final partnerName = partner?['name']?.toString() ?? '';
    final daysTogether = couple?['days_together']?.toString() ?? '0';
    final totalScore = couple?['total_score']?.toString() ?? '0';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        image: cfg.cpSpaceBgImage.isNotEmpty
            ? (cfg.cpSpaceBgImage.startsWith('http')
                ? DecorationImage(image: NetworkImage(cfg.cpSpaceBgImage), fit: BoxFit.cover)
                : DecorationImage(image: AssetImage(cfg.cpSpaceBgImage), fit: BoxFit.cover))
            : const DecorationImage(
                image: AssetImage('assets/cp/ic_cp_main_bg_top.webp'),
                fit: BoxFit.cover,
              ),
      ),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // Top animated SVGA background
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 220,
            child: IgnorePointer(
              child: SvgaFrame(
                svgaPath: 'assets/svga/relationship_act_top_bg.svga',
                size: 220,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Column(
            children: [
              const SizedBox(height: 10),
              // Level frame
              Container(
                width: 72,
                height: 32,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/cp/ic_cp_level_frame.png'),
                    fit: BoxFit.contain,
                  ),
                ),
                alignment: Alignment.center,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    'Lv.${_calcLevel(int.tryParse(totalScore) ?? 0)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // RS Panel: avatars + wings + heartbeat decor
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildAvatarFrame(myAvatar, myName, isMe: true),
                  // Center heart decor
                  SizedBox(
                    width: 70,
                    height: 70,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.asset(
                          'assets/cp/ic_cp_mid_heart_decor.webp',
                          width: 58,
                          height: 58,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                        const SvgaFrame(
                          svgaPath: 'assets/svga/d33.svga',
                          size: 48,
                          fit: BoxFit.contain,
                        ),
                      ],
                    ),
                  ),
                  _buildAvatarFrame(partnerAvatar, partnerName, isMe: false),
                ],
              ),
              const SizedBox(height: 12),
              // Days together badge
              Container(
                width: 120,
                height: 30,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/cp/ic_cp_days_bg.png'),
                    fit: BoxFit.contain,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$daysTogether يوم معاً',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarFrame(String? avatarUrl, String name, {bool isMe = true}) {
    final wingAsset = isMe
        ? 'assets/cp/ic_cp_wing_frame_left.webp'
        : 'assets/cp/ic_cp_wing_frame_right.webp';

    return SizedBox(
      width: 126,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 120,
            height: 104,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Wing Frame background
                Positioned.fill(
                  child: Image.asset(
                    wingAsset,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                // Avatar
                ClipOval(
                  child: R.loadImage(
                    avatarUrl ?? (isMe ? R.avaBoy : R.avaGirl),
                    width: 62,
                    height: 62,
                    fit: BoxFit.cover,
                  ),
                ),
                // SVGA frame overlay
                SvgaFrame(
                  svgaPath: isMe ? 'assets/svga/d28.svga' : 'assets/svga/d29.svga',
                  size: 86,
                  fit: BoxFit.contain,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Name
          Text(
            name.isNotEmpty ? name : (isMe ? 'أنا' : 'شريكي'),
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(DynamicConfigService cfg, Map<String, dynamic>? couple) {
    final totalScore = (couple?['total_score'] as num?)?.toInt() ?? 0;
    final currentLv = _calcLevel(totalScore);
    final nextLv = currentLv + 1;
    final currentLvMin = _lvMinScore(currentLv);
    final nextLvMin = _lvMinScore(nextLv);
    final progress = nextLvMin > currentLvMin
        ? ((totalScore - currentLvMin) / (nextLvMin - currentLvMin)).clamp(0.0, 1.0)
        : 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        children: [
          // Next level tip
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$_nextLvTip',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.help_outline, color: Colors.white54, size: 14),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar
          LayoutBuilder(builder: (context, constraints) {
            return Stack(
              children: [
                // Background
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4a1020),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFF770d1e), width: 1),
                  ),
                ),
                // Fill
                Container(
                  height: 10,
                  width: constraints.maxWidth * progress,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFd32a43), Color(0xFFff6b9d)],
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 4),
          // Level labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Lv.$currentLv',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              Text('Lv.$nextLv',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBorderSection(DynamicConfigService cfg) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF770d1e), width: 1.5),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF4a1020).withValues(alpha: 0.5),
            const Color(0xFF2e0d15).withValues(alpha: 0.3),
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('القربى', '${(_data['couple'] as Map?)?['total_score'] ?? 0}', Icons.favorite),
          _buildStatItem('هذا الأسبوع', '${(_data['couple'] as Map?)?['week_score'] ?? 0}', Icons.star),
          _buildStatItem('هذا الشهر', '${(_data['couple'] as Map?)?['month_score'] ?? 0}', Icons.emoji_events),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFFffb565), size: 24),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ],
    );
  }

  Widget _buildTasksSection(DynamicConfigService cfg) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Header with navigation to record
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'المهام اليومية',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CpRecordScreen()),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('السجل', style: TextStyle(color: Color(0xFFffb565), fontSize: 12)),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_ios, color: Color(0xFFffb565), size: 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'أكمل المهام لزيادة القربى',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 12),
          _buildTaskItem('إرسال هدية CP', '+10 قربى', Icons.card_giftcard, const Color(0xFFff6b9d)),
          _buildTaskItem('الدخول معاً إلى غرفة', '+5 قربى', Icons.meeting_room, const Color(0xFFffb565)),
          _buildTaskItem('إرسال رسالة', '+2 قربى', Icons.chat_bubble, const Color(0xFF64b5f6)),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildTaskItem(String title, String reward, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF4a1020).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF770d1e), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(reward, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  int _calcLevel(int score) {
    if (score >= 1000) return 6;
    if (score >= 500) return 5;
    if (score >= 200) return 4;
    if (score >= 100) return 3;
    if (score >= 30) return 2;
    return 1;
  }

  int _lvMinScore(int lv) {
    return switch (lv) {
      1 => 0,
      2 => 30,
      3 => 100,
      4 => 200,
      5 => 500,
      6 => 1000,
      _ => 0,
    };
  }

  String get _nextLvTip => 'أكمل المهام للوصول للمستوى التالي';
}
