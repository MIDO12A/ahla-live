import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../providers/user_provider.dart';
import '../../models/user_model.dart';
import '../../services/firebase_service.dart';
import '../../services/update_service.dart';
import '../../widgets/app_update_dialog.dart';
import '../../screens/room/widgets/svga_frame.dart';
import '../follow/follow_recent_screen.dart';
import '../profile/account_management_screen.dart';
import '../wallet/wallet_main_screen.dart';
import '../mall/mall_screen.dart';
import '../user_profile/user_profile_screen.dart';
import '../level/level_screen.dart';
import '../badges/badges_screen.dart';
import '../backpack/backpack_screen.dart';
import 'edit_profile_screen.dart';
import '../setting/feedback_screen.dart';
import '../vip/vip_center_screen.dart';
import '../../features/host_agency/host_agency_screen.dart';
import '../../features/financial/agent_recharge_portal_screen.dart';

/// شاشة "أنا" (الملف الشخصي) المطابقة تماماً لملف fragment_mine.xml
/// وكود MineFragment.java من المشروع الأصلي (F:\Medal\New folder\nu):
/// - الخلفية بلون #F2F5FC مع صورة الغلاف العلوية mine_top_bg.webp
/// - الصورة الشخصية المركزية (iv_avatar) بقطر 92dp وحدود بيضاء 4dp داخل إطار mine_avatar_ic.webp (122dp)
/// - زر تعديل البيانات mine_btn_edit_ic.webp في الزاوية العلوية (marginTop: 56dp, marginEnd: 12dp)
/// - الاسم والجنس (sex_male_ic / sex_female_ic) ومعرف المستخدم (ID) وأزرار النسخ والأوسمة في المنتصف
/// - إحصائيات المتابعة الثلاثية: المتابَعون (cl_following)، المعجبون (cl_followers)، الزوار (cl_visitor)
/// - بطاقة المحفظة البيضاء (ll_wallet_info): mine_wallet_ic + common_gold_ic_3 + رصيد الكوينز والماسات
/// - بطاقة VIP الفاخرة (cl_vip): mine_vip_center_bg + mine_mall_tab_vip_ic + mine_vip_label_ic + mine_vip_go
/// - قائمة الوظائف البيضاء (ll_set): الوكالة، المستوى، المتجر، الحقيبة، بوابة الوكلاء، الشكاوى، الإعدادات، التحديثات
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.currentUser;
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      color: const Color(0xFFF2F5FC), // color_F2F5FC
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // 1. الخلفية العلوية mine_top_bg.webp الممتدة بعرض الشاشة
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Image.asset(
                'assets/mipmap-xxhdpi/mine_top_bg.webp',
                fit: BoxFit.fitWidth,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),

            SingleChildScrollView(
              padding: EdgeInsets.only(
                top: topPadding,
                bottom: 90,
              ),
              child: Column(
                children: [
                  // 2. لوحة المستخدم المركزية (cl_info)
                  _buildUserInfoPanel(context, user),

                  const SizedBox(height: 24),

                  // 3. شريط الإحصائيات الثلاثي (cl_data_info)
                  _buildStatsRow(context, user),

                  const SizedBox(height: 16),

                  // 4. بطاقة المحفظة (ll_wallet_info)
                  _buildWalletCard(context, user),

                  const SizedBox(height: 12),

                  // 5. بطاقة مركز VIP (cl_vip)
                  _buildVipBanner(context, user),

                  const SizedBox(height: 12),

                  // 6. قائمة الوظائف والإعدادات (ll_set)
                  _buildSettingsList(context, user),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// حل إطار الرأس النشط سواء SVGA أو صورة عادية
  Widget _buildFrameWidget(String activeFrame) {
    if (activeFrame.isEmpty) return const SizedBox.shrink();
    String resolved = activeFrame;
    final storeItem = FirebaseService().getStoreItemSync(activeFrame);
    if (storeItem != null) {
      final anim = (storeItem.svgaAsset != null && storeItem.svgaAsset!.isNotEmpty)
          ? storeItem.svgaAsset!
          : (storeItem.videoAsset != null && storeItem.videoAsset!.isNotEmpty)
              ? storeItem.videoAsset!
              : (storeItem.animationUrl != null && storeItem.animationUrl!.isNotEmpty)
                  ? storeItem.animationUrl!
                  : storeItem.iconAsset;
      if (anim.isNotEmpty) resolved = anim;
    }
    if (resolved.toLowerCase().endsWith('.svga') ||
        resolved.toLowerCase().endsWith('.vap') ||
        resolved.toLowerCase().endsWith('.mp4') ||
        resolved.startsWith('http') ||
        resolved.startsWith('assets/')) {
      return SvgaFrame(
        svgaPath: resolved,
        size: 122,
        fit: BoxFit.contain,
      );
    }
    return const SizedBox.shrink();
  }

  /// لوحة المستخدم العلوية المركزية cl_info المطابقة تماماً لـ fragment_mine.xml
  Widget _buildUserInfoPanel(BuildContext context, UserModel? user) {
    final photoUrl = (user?.photoUrl != null && user!.photoUrl.isNotEmpty) ? user.photoUrl : null;
    final userId = (user?.customId != null && user!.customId.isNotEmpty)
        ? user.customId
        : ((1000000 + (user?.uid.hashCode.abs() ?? 0) % 9000000).toString());
    final isMale = user?.gender != 'female';
    final hasFrame = user?.activeFrame != null && user!.activeFrame!.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // زر التعديل العلوي iv_edit_info (mine_btn_edit_ic)
          PositionedDirectional(
            top: 16,
            end: 16,
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                );
              },
              child: Image.asset(
                'assets/mipmap-xxhdpi/mine_btn_edit_ic.webp',
                width: 36,
                height: 28,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.edit, size: 24, color: Colors.black87),
              ),
            ),
          ),

          // المحتوى المركزي: الصورة الشخصية، الاسم، المعرف، والمستوى
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // الصورة المركزية (iv_avatar) 92dp داخل إطار 122dp
                Center(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const UserProfileScreen()),
                      );
                    },
                    child: SizedBox(
                      width: 122,
                      height: 122,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // الصورة الدائرية iv_avatar (92x92) بحدود بيضاء 4dp
                          Container(
                            width: 92,
                            height: 92,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: photoUrl != null
                                ? Image(
                                    image: R.cachedImage(photoUrl),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Image.asset(
                                      isMale ? R.avaBoy : R.avaGirl,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Image.asset(
                                    isMale ? R.avaBoy : R.avaGirl,
                                    fit: BoxFit.cover,
                                  ),
                          ),

                          // الإطار الخارجي: إطار SVGA النشط أو mine_avatar_ic.webp
                          if (hasFrame)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: _buildFrameWidget(user.activeFrame!),
                              ),
                            )
                          else
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Image.asset(
                                  'assets/mipmap-xxhdpi/mine_avatar_ic.webp',
                                  width: 122,
                                  height: 122,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // اسم المستخدم + أيقونة الجنس (ll_name)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        (user?.name != null && user!.name.isNotEmpty) ? user.name : 'مستخدم جديد',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16151A), // color_16151A
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Image.asset(
                      isMale
                          ? 'assets/mipmap-xxhdpi/sex_male_ic.webp'
                          : 'assets/mipmap-xxhdpi/sex_female_ic.webp',
                      width: 18,
                      height: 16,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(
                        isMale ? Icons.male : Icons.female,
                        size: 16,
                        color: isMale ? Colors.blue : Colors.pink,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 7),

                // معرف المستخدم + زر النسخ (user_id_view)
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: userId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم نسخ المعرّف بنجاح!', textAlign: TextAlign.center),
                        duration: Duration(seconds: 1),
                        backgroundColor: Color(0xFF16151A),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ID:$userId',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF9BA1B6),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Image.asset(
                          'assets/mipmap-xxhdpi/mine_copy_ic_2.webp',
                          width: 13,
                          height: 13,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(Icons.copy, size: 13, color: Color(0xFF9BA1B6)),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // صف الأوسمة والمستوى (level_view)
                _buildRankLevelView(context, user),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// شارات المستوى والـ VIP (level_view)
  Widget _buildRankLevelView(BuildContext context, UserModel? user) {
    final wealthLevel = user?.wealthLevel ?? 1;
    final rechargeLevel = user?.rechargeLevel ?? 1;
    final vipLevel = _getUserVipTier(user);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BadgesScreen()),
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // شارة الثروة (50x18dp)
          Container(
            width: 50,
            height: 18,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFB038), Color(0xFFFF7A00)],
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star, size: 10, color: Colors.white),
                const SizedBox(width: 2),
                Text(
                  'Lv.$wealthLevel',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),

          // شارة الشحن / الجاذبية (50x18dp)
          Container(
            width: 50,
            height: 18,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF5C9E), Color(0xFFD61877)],
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.favorite, size: 10, color: Colors.white),
                const SizedBox(width: 2),
                Text(
                  'Lv.$rechargeLevel',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),

          if (vipLevel > 0) ...[
            const SizedBox(width: 4),
            Container(
              width: 50,
              height: 18,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFB8860B)],
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Text(
                'VIP $vipLevel',
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _getUserVipTier(UserModel? user) {
    if (user == null) return 0;
    if (user.ownedVipItems.isNotEmpty) {
      for (final item in user.ownedVipItems) {
        final name = item['name'] ?? item['title'] ?? '';
        final match = RegExp(r'VIP\s*(\d+)', caseSensitive: false).firstMatch(name);
        if (match != null) {
          return (int.tryParse(match.group(1) ?? '1') ?? 1).clamp(1, 6);
        }
      }
      return 1;
    }
    if (user.rechargeLevel > 1) {
      return (user.rechargeLevel ~/ 2).clamp(1, 6);
    }
    return 0;
  }

  /// شريط الإحصائيات الثلاثي cl_data_info المطابق لـ fragment_mine.xml:
  /// cl_following (المتابَعون) | cl_followers (المعجبون) | cl_visitor (الزوار)
  Widget _buildStatsRow(BuildContext context, UserModel? user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // 1. المتابَعون cl_following
          Expanded(
            child: _buildStatItem(
              context: context,
              count: user?.following ?? 0,
              label: 'المتابَعون',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => FollowRecentScreen(initialTab: 0, targetUid: user?.uid)),
                );
              },
            ),
          ),
          // 2. المعجبون cl_followers
          Expanded(
            child: _buildStatItem(
              context: context,
              count: user?.followers ?? 0,
              label: 'المتابعون',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => FollowRecentScreen(initialTab: 1, targetUid: user?.uid)),
                );
              },
            ),
          ),
          // 3. الزوار cl_visitor
          Expanded(
            child: _buildStatItem(
              context: context,
              count: user?.visitors ?? 0,
              label: 'الزوار',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => FollowRecentScreen(initialTab: 2, targetUid: user?.uid)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required BuildContext context,
    required int count,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFF16151A), // color_16151A
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF9BA1B6), // color_9BA1B6
            ),
          ),
        ],
      ),
    );
  }

  /// بطاقة المحفظة البيضاء ll_wallet_info المطابقة لـ fragment_mine.xml
  Widget _buildWalletCard(BuildContext context, UserModel? user) {
    final coins = user?.coins ?? 0;
    final diamonds = user?.diamonds ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14), // mine_item_shape_bg_12
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1E284B).withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            // السطر 1: عنوان المحفظة ورابط الشحن (cl_recharge)
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WalletMainScreen()),
                );
              },
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/mipmap-xxhdpi/mine_wallet_ic.webp',
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'المحفظة',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF000000),
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'إعادة شحن العملات الذهبية',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9BA1B6),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Image.asset(
                      'assets/mipmap-xxhdpi/common_next_4_ic.webp',
                      width: 16,
                      height: 16,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(Icons.chevron_left, size: 16, color: Color(0xFF9BA1B6)),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: Color(0xFFF4F5F8), indent: 16, endIndent: 16),

            // السطر 2: الرصيد بالعملات الذهبية والماسات (cl_coin)
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WalletMainScreen()),
                );
              },
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/mipmap-xxhdpi/common_gold_ic_3.webp',
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$coins',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF000000),
                      ),
                    ),
                    if (diamonds > 0) ...[
                      const Spacer(),
                      Image.asset(
                        'assets/mipmap-xxhdpi/common_diamond_ic.webp',
                        width: 20,
                        height: 20,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.diamond, size: 18, color: Colors.blueAccent),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$diamonds',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF000000),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// بطاقة مركز VIP الفاخرة cl_vip المطابقة لـ fragment_mine.xml
  Widget _buildVipBanner(BuildContext context, UserModel? user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VipCenterScreen()),
          );
        },
        child: SizedBox(
          height: 64,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // خلفية كارت VIP mine_vip_center_bg.webp
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    'assets/mipmap-xxhdpi/mine_vip_center_bg.webp',
                    fit: BoxFit.fill,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // أيقونة mine_mall_tab_vip_ic
                    Image.asset(
                      'assets/mipmap-xxhdpi/mine_mall_tab_vip_ic.webp',
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'مركز VIP',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFAE9B5), // color_FFFAE9B5
                      ),
                    ),
                    const Spacer(),
                    // ملصق تاج VIP mine_vip_label_ic
                    Image.asset(
                      'assets/mipmap-xxhdpi/mine_vip_label_ic.webp',
                      width: 52,
                      height: 52,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 8),
                    // سهم التخطي mine_vip_go
                    Image.asset(
                      'assets/mipmap-xxhdpi/mine_vip_go.webp',
                      width: 16,
                      height: 16,
                      fit: BoxFit.contain,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// قائمة الوظائف والإعدادات البيضاء ll_set المطابقة لـ fragment_mine.xml
  Widget _buildSettingsList(BuildContext context, UserModel? user) {
    final isAgent = user?.isRechargeAgent == true;
    final wealthLevel = user?.wealthLevel ?? 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14), // mine_item_shape_bg_12
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1E284B).withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            // 1. الوكالة (cl_union)
            _buildFunctionItem(
              icon: 'assets/mipmap-xxhdpi/mine_union_ic.webp',
              title: 'الوكالة',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HostAgencyScreen()),
                );
              },
            ),

            // 2. المستوى (cl_level) مع إظهار Lv.X
            _buildFunctionItem(
              icon: 'assets/mipmap-xxhdpi/mine_level_ic.webp',
              title: 'المستوى',
              trailingText: 'Lv.$wealthLevel',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LevelScreen()),
                );
              },
            ),

            // 3. المتجر (cl_mall)
            _buildFunctionItem(
              icon: 'assets/mipmap-xxhdpi/mine_mall_ic.webp',
              title: 'المتجر',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MallScreen()),
                );
              },
            ),

            // 4. الحقيبة (cl_package)
            _buildFunctionItem(
              icon: 'assets/mipmap-xxhdpi/mine_backpack_ic.webp',
              title: 'الحقيبة',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BackpackScreen()),
                );
              },
            ),

            // 5. بوابة شحن الوكلاء والرواتب (خاص بالوكلاء المعتمدين)
            if (isAgent)
              _buildFunctionItem(
                icon: 'assets/images/profile/ic_coinseller_entrance.png',
                title: 'بوابة شحن الوكلاء والرواتب',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AgentRechargePortalScreen()),
                  );
                },
              ),

            // 6. الشكاوى والاقتراحات (cl_feedback)
            _buildFunctionItem(
              icon: 'assets/mipmap-xxhdpi/mine_feedback_ic.webp',
              title: 'الشكاوى والاقتراحات',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FeedbackScreen()),
                );
              },
            ),

            // 7. الإعدادات (cl_setting)
            _buildFunctionItem(
              icon: 'assets/mipmap-xxhdpi/mine_setting_ic.webp',
              title: 'الإعدادات',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountManagementScreen()),
                );
              },
            ),

            // 8. التحقق من التحديثات
            _buildFunctionItem(
              icon: 'assets/mipmap-xxhdpi/mine_set_increase_version_ic.webp',
              title: 'التحقق من التحديثات',
              onTap: () => _handleCheckUpdates(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFunctionItem({
    required String icon,
    required String title,
    String? trailingText,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Image.asset(
              icon,
              width: 44,
              height: 44,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.circle, size: 30, color: Colors.blueAccent),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF000000),
              ),
            ),
            const Spacer(),
            if (trailingText != null) ...[
              Text(
                trailingText,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF16151A),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Image.asset(
              'assets/mipmap-xxhdpi/next_black_ic.webp',
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.chevron_left, size: 24, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }

  void _handleCheckUpdates(BuildContext context) async {
    final updateService = UpdateService.instance;
    final updateInfo = await updateService.checkForUpdate();
    final info = await PackageInfo.fromPlatform();
    final currentVer = '${info.version}+${info.buildNumber}';

    if (!context.mounted) return;

    if (updateInfo != null) {
      await AppUpdateDialog.show(context, updateInfo);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'أنت تستخدم أحدث إصدار ($currentVer) ✅',
            textAlign: TextAlign.center,
          ),
          backgroundColor: const Color(0xFF2E7D32),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
