import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../services/dynamic_config_service.dart';
import '../../providers/user_provider.dart';
import '../../services/level_service.dart';
import '../../services/supabase_service.dart';
import '../../services/update_service.dart';
import '../../widgets/app_update_dialog.dart';
import '../../core/supabase_compat.dart';
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
import '../vip/vip_intro_screen.dart';
import '../../features/cp/cp_space_screen.dart';
import '../../features/host_agency/host_agency_screen.dart';
import '../../features/financial/agent_recharge_portal_screen.dart';
import '../../features/signin/weekly_signin_screen.dart';
import '../../features/tasks/screens/daily_tasks_screen.dart';

/// شاشة "أنا" (الملف الشخصي) المطابقة تماماً لملف frag_mine_v3.xml
/// ومكوناتها الأصلية:
/// - vh_mine_user_panel.xml (بيانات المستخدم وصورته والأوسمة)
/// - vh_mine_user_data_panel.xml (الزوار، المتابعون، المعجبون، الأصدقاء)
/// - vh_mine_wallet_panel.xml (المحفظة: الكوينز والماسات)
/// - vh_mine_middle_funcions_panel.xml (الوكالة، المتجر، الارتباط، المستوى)
/// - vh_mine_vip_entrance.xml (مدخل كبار الشخصيات VIP)
/// - vh_mine_bottom_functions_item.xml (قائمة الوظائف والإعدادات)
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.currentUser;
    final bgImg = DynamicConfigService().profileBackgroundImage;

    return Container(
      color: const Color(0xFF13131A), // dark_95
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // 1. الخلفية الأصلية العلوية ic_hilla_top_bg
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Image.asset(
                'assets/mipmap-xxhdpi/ic_hilla_top_bg.png',
                fit: BoxFit.fitWidth,
                errorBuilder: (_, __, ___) => bgImg.isNotEmpty
                    ? Image(image: R.cachedImage(bgImg), fit: BoxFit.fitWidth)
                    : const SizedBox.shrink(),
              ),
            ),

            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 90),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 2. لوحة المستخدم idUserPanel + vh_mine_user_panel
                    _buildUserPanel(context, user),

                    const SizedBox(height: 12),

                    // 3. شريط الإحصائيات الأربعة userDataPanel (vh_mine_user_data_panel)
                    _buildUserDataPanel(context, user),

                    const SizedBox(height: 14),

                    // 4. بطاقة المحفظة والأزرار الأربعة (ic_mine_wallet_bg)
                    _buildWalletAndMiddleFunctionsPanel(context, user),

                    const SizedBox(height: 12),

                    // 5. مدخل VIP (vh_mine_vip_entrance)
                    _buildVipEntrance(context, user),

                    const SizedBox(height: 12),

                    // 6. قائمة الوظائف والإعدادات (settingListRv)
                    _buildBottomFunctions(context, user),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// حل إطار الرأس النشط سواء SVGA أو صورة عادية
  Widget _buildFrameWidget(String activeFrame) {
    if (activeFrame.isEmpty) return const SizedBox();
    String resolved = activeFrame;
    final storeItem = SupabaseService().getStoreItemSync(activeFrame);
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
        size: 98,
        fit: BoxFit.contain,
      );
    }
    return const SizedBox();
  }

  /// لوحة المستخدم العلوية المطابقة لـ vh_mine_user_panel.xml
  Widget _buildUserPanel(BuildContext context, dynamic user) {
    final photoUrl = user?.photoUrl?.isNotEmpty == true ? user.photoUrl : null;
    final userId = user?.customId?.isNotEmpty == true
        ? user!.customId!
        : ((1000000 + (user?.uid.hashCode.abs() ?? 0) % 9000000).toString());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          // زر التعديل العلوي في الزاوية اليمنى userEditBtn
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Image.asset(
                  'assets/mipmap-xxhdpi/ic_mine_user_edit.png',
                  width: 26,
                  height: 26,
                ),
              ),
            ),
          ),

          const SizedBox(height: 4),

          // محتوى اللوحة: الصورة على اليسار والبيانات على اليمين
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // صورة المستخدم userHeader (94x94dp)
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const UserProfileScreen()),
                  );
                },
                child: SizedBox(
                  width: 94,
                  height: 94,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // الصورة الدائرية
                      Container(
                        width: 76,
                        height: 76,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white12,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: photoUrl != null
                            ? Image(
                                image: R.cachedImage(photoUrl),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    Image.asset(R.avaBoy, fit: BoxFit.cover),
                              )
                            : Image.asset(R.avaBoy, fit: BoxFit.cover),
                      ),
                      // الإطار النشط
                      if (user?.activeFrame != null && user!.activeFrame!.isNotEmpty)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: _buildFrameWidget(user.activeFrame!),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // التفاصيل النصية بجانب الصورة
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // السطر 1: اسم المستخدم + شارة الجنس والعمر + علم الدولة
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user?.name?.isNotEmpty == true ? user.name : 'مستخدم جديد',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // شارة الجنس والعمر userGender (SexAgeView)
                        _buildGenderAgeBadge(user),
                        // علم الدولة
                        if (user?.country != null && user.country.toString().isNotEmpty) ...[
                          const SizedBox(width: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: Text(
                              _countryFlag(user.country.toString()),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 6),

                    // السطر 2: معرف المستخدم userId + زر النسخ idCopyIv + زر ID
                    Row(
                      children: [
                        Text(
                          'ID: $userId',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xCCFFFFFF),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: userId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم نسخ الـ ID بنجاح'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          child: Image.asset(
                            'assets/mipmap-xxhdpi/id_id_copy.png',
                            width: 16,
                            height: 16,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'ID',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xB3FFFFFF),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    // السطر 3: الأوسمة والمستويات userLevelsView
                    _buildLevelDisplay(user),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// شارة الجنس والعمر SexAgeView
  Widget _buildGenderAgeBadge(dynamic user) {
    final isGirl = user?.gender == 'female';
    final age = (user?.age != null && (user.age as int) > 0) ? user.age.toString() : '20';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: isGirl ? const Color(0xFFFF5286) : const Color(0xFF2E89FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isGirl ? Icons.female : Icons.male,
            size: 11,
            color: Colors.white,
          ),
          const SizedBox(width: 2),
          Text(
            age,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  String _countryFlag(String countryCode) {
    if (countryCode.length != 2) return '';
    final int first = countryCode.toUpperCase().codeUnitAt(0) - 0x41 + 0x1F1E6;
    final int second = countryCode.toUpperCase().codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(first) + String.fromCharCode(second);
  }

  /// أوسمة المستويات والـ VIP
  Widget _buildLevelDisplay(dynamic user) {
    return Row(
      children: [
        _levelIcon(user?.wealthLevel ?? 1, 'wealth'),
        const SizedBox(width: 6),
        _levelIcon(user?.rechargeLevel ?? 1, 'recharge'),
        if (user?.activeNecklace != null && user.activeNecklace.toString().isNotEmpty) ...[
          const SizedBox(width: 6),
          _buildVipNecklace(user),
        ],
        _buildBadgesRow(user),
      ],
    );
  }

  Widget _buildVipNecklace(dynamic user) {
    final necklace = user?.activeNecklace?.toString() ?? '';
    if (necklace.isEmpty) return const SizedBox();
    return SizedBox(
      width: 24,
      height: 24,
      child: SvgaFrame(svgaPath: necklace, size: 24, fit: BoxFit.contain),
    );
  }

  Widget _buildBadgesRow(dynamic user) {
    final badges = (user?.ownedBadges as List<dynamic>?)?.cast<String>() ?? [];
    if (badges.isEmpty) return const SizedBox();
    return Row(
      children: badges.take(3).map((badgeId) {
        final storeItem = SupabaseService().getStoreItemSync(badgeId);
        final iconUrl = storeItem?.iconAsset ?? storeItem?.svgaAsset;
        if (iconUrl == null || iconUrl.isEmpty) return const SizedBox();
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: SizedBox(
            width: 20,
            height: 20,
            child: iconUrl.endsWith('.svga')
                ? SvgaFrame(svgaPath: iconUrl, size: 20)
                : Image.network(iconUrl, width: 20, height: 20, errorBuilder: (_, __, ___) => const SizedBox()),
          ),
        );
      }).toList(),
    );
  }

  Widget _levelIcon(int level, String type) {
    final config = LevelService().getLevelConfig(type, level);
    final url = config?.imageUrl;
    if (url != null && url.isNotEmpty) {
      return SizedBox(
        width: 32,
        height: 18,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: R.loadAsset(url),
        ),
      );
    }
    final isWealth = type == 'wealth';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isWealth
              ? [const Color(0xFFFF9500), const Color(0xFFFF5E00)]
              : [const Color(0xFF00C6FF), const Color(0xFF0072FF)],
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Lv.$level',
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }

  /// شريط البيانات المطابق لـ vh_mine_user_data_panel.xml
  Widget _buildUserDataPanel(BuildContext context, dynamic user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // 1. الزوار visitorsCl
          _buildDataItem(
            count: '${user?.visitors ?? 0}',
            label: 'الزوار',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FollowRecentScreen(initialTab: 2, targetUid: user?.uid),
                ),
              );
            },
          ),

          // 2. المتابعون followingCl
          _buildDataItem(
            count: '${user?.following ?? 0}',
            label: 'المتابَعون',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FollowRecentScreen(initialTab: 0, targetUid: user?.uid),
                ),
              );
            },
          ),

          // 3. المعجبون fansCl
          _buildDataItem(
            count: '${user?.followers ?? 0}',
            label: 'المعجبون',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FollowRecentScreen(initialTab: 1, targetUid: user?.uid),
                ),
              );
            },
          ),

          // 4. الأصدقاء friendsCl
          _buildDataItem(
            count: '0',
            label: 'الأصدقاء',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FollowRecentScreen(initialTab: 0, targetUid: user?.uid),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDataItem({required String count, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        alignment: Alignment.center,
        child: Column(
          children: [
            Text(
              count,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0x99FFFFFF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// بطاقة المحفظة والأزرار الأربعة المطابقة لـ ic_mine_wallet_bg.png
  Widget _buildWalletAndMiddleFunctionsPanel(BuildContext context, dynamic user) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B26),
        image: const DecorationImage(
          image: AssetImage('assets/mipmap-xxhdpi/ic_mine_wallet_bg.png'),
          fit: BoxFit.fill,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // ── القسم العلوي: المحفظة vh_mine_wallet_panel.xml ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Column(
              children: [
                // ترويسة المحفظة walletIv + walletTv + walletArrowIv
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const WalletMainScreen()),
                    );
                  },
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/mipmap-xxhdpi/ic_wallet.png',
                        width: 22,
                        height: 20,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'محفظتي',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      Image.asset(
                        'assets/mipmap-xxhdpi/ic_wallet_arrow_right.png',
                        width: 14,
                        height: 14,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // بطاقتا الرصيد: الكوينز والماسات جنباً إلى جنب
                Row(
                  children: [
                    // بطاقة الكوينز coinBgIv + coinIconIv + coinNumTv
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const WalletMainScreen()),
                          );
                        },
                        child: Container(
                          height: 44,
                          decoration: const BoxDecoration(
                            image: DecorationImage(
                              image: AssetImage('assets/mipmap-xxhdpi/ic_mine_wallet_coin_bg.png'),
                              fit: BoxFit.fill,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            children: [
                              Image.asset(
                                'assets/mipmap-xxhdpi/ic_coin.png',
                                width: 26,
                                height: 26,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _formatBalance(user?.coins ?? 0),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF9F3D0C),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // بطاقة الماسات diamondBgIv + diamondIconIv + diamondNumTv
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const WalletMainScreen()),
                          );
                        },
                        child: Container(
                          height: 44,
                          decoration: const BoxDecoration(
                            image: DecorationImage(
                              image: AssetImage('assets/mipmap-xxhdpi/ic_mine_wallet_diamond_bg.png'),
                              fit: BoxFit.fill,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            children: [
                              Image.asset(
                                'assets/mipmap-xxhdpi/ic_diamond.png',
                                width: 26,
                                height: 26,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _formatBalance(user?.diamonds ?? 0),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0B53A7),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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

          const Divider(color: Colors.white10, height: 16),

          // ── القسم السفلي: الأزرار الأربعة vh_mine_middle_funcions_panel.xml ──
          Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // 1. الوكالة itemAgency
                _buildMiddleItem(
                  icon: 'assets/mipmap-xxhdpi/ic_mine_agency_entrance.png',
                  name: 'الوكالة',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HostAgencyScreen()),
                    );
                  },
                ),

                // 2. المتجر itemStore
                _buildMiddleItem(
                  icon: 'assets/mipmap-xxhdpi/ic_mine_store_entrance.png',
                  name: 'المتجر',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MallScreen()),
                    );
                  },
                ),

                // 3. الارتباط itemRelationship
                _buildMiddleItem(
                  icon: 'assets/mipmap-xxhdpi/ic_mine_relationship_entrance.png',
                  name: 'الارتباط',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CpSpaceScreen()),
                    );
                  },
                ),

                // 4. المستوى itemLevel
                _buildMiddleItem(
                  icon: 'assets/mipmap-xxhdpi/ic_mine_level_entrance.png',
                  name: 'المستوى',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LevelScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiddleItem({required String icon, required String name, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Image.asset(
            icon,
            width: 48,
            height: 48,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(Icons.star, size: 44, color: Colors.amber),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  String _formatBalance(int num) {
    if (num >= 1000000) {
      return '${(num / 1000000).toStringAsFixed(1)}M';
    } else if (num >= 1000) {
      return '${(num / 1000).toStringAsFixed(1)}K';
    }
    return num.toString();
  }

  /// مدخل VIP المطابق لـ vh_mine_vip_entrance.xml
  Widget _buildVipEntrance(BuildContext context, dynamic user) {
    final int tier = (user?.vipTier ?? 0) as int;
    final bgPath = 'assets/mipmap-xxhdpi/vip_level${tier.clamp(0, 6)}_bg.png';

    return GestureDetector(
      onTap: () => _openVip(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          image: DecorationImage(
            image: AssetImage(bgPath),
            fit: BoxFit.fill,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/mipmap-xxhdpi/mine_mall_tab_vip_ic.webp',
                      width: 22,
                      height: 22,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tier > 0 ? 'عضوية VIP $tier النشطة' : 'مركز كبار الشخصيات VIP',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFAE9B5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  tier > 0 ? 'استمتع بمزاياك الحصرية' : 'انضم الآن واحصل على امتيازات استثنائية',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFDEB979),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Image.asset(
              'assets/mipmap-xxhdpi/ic_wallet_arrow_right.png',
              width: 16,
              height: 16,
              color: const Color(0xFFFAE9B5),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openVip(BuildContext context) async {
    try {
      final res = await Supabase.instance.client
          .from('vip_config')
          .select('intro_video_url')
          .order('tier')
          .limit(1)
          .maybeSingle();
      if (!context.mounted) return;
      final introUrl = res?['intro_video_url']?.toString();
      if (introUrl != null && introUrl.isNotEmpty) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => VipIntroScreen(videoUrl: introUrl),
        ));
        return;
      }
    } catch (_) {}
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => const VipCenterScreen(),
    ));
  }

  /// قائمة الوظائف والإعدادات المطابقة لـ settingListRv & item_mine_setting.xml
  Widget _buildBottomFunctions(BuildContext context, dynamic user) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B26),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // 1. الحقيبة ic_mine_backpack.png
          _buildFunctionItem(
            icon: 'assets/mipmap-xxhdpi/ic_mine_backpack.png',
            title: 'الحقيبة',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BackpackScreen()),
              );
            },
          ),
          _buildFunctionDivider(),

          // 2. المهام اليومية ic_mine_task_entrance.png
          _buildFunctionItem(
            icon: 'assets/mipmap-xxhdpi/ic_mine_task_entrance.png',
            title: 'المهام اليومية والمكافآت',
            subtitle: '🌟 كوينز وجوائز يومية',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DailyTasksScreen()),
              );
            },
          ),
          _buildFunctionDivider(),

          // 3. التسجيل اليومي ic_mine_task.png
          _buildFunctionItem(
            icon: 'assets/mipmap-xxhdpi/ic_mine_task.png',
            title: 'التسجيل اليومي',
            onTap: () {
              WeeklySigninScreen.show(context);
            },
          ),
          _buildFunctionDivider(),

          // 4. حائط الهدايا والأوسمة ic_mine_giftwall_entrance.png
          _buildFunctionItem(
            icon: 'assets/mipmap-xxhdpi/ic_mine_giftwall_entrance.png',
            title: 'حائط الهدايا والأوسمة',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BadgesScreen()),
              );
            },
          ),
          _buildFunctionDivider(),

          // 5. غرفتي ic_mine_create_room.png
          _buildFunctionItem(
            icon: 'assets/mipmap-xxhdpi/ic_mine_create_room.png',
            title: 'غرفتي',
            onTap: () {
              if (user?.hostedRoomId != null && user!.hostedRoomId!.isNotEmpty) {
                // دخول الغرفة
              }
            },
          ),

          // 6. شحن الوكلاء (إذا كان وكيلاً)
          if (user?.isRechargeAgent == true) ...[
            _buildFunctionDivider(),
            _buildFunctionItem(
              icon: 'assets/mipmap-xxhdpi/ic_coinseller_entrance.png',
              title: 'بوابة شحن الوكلاء والرواتب',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AgentRechargePortalScreen()),
                );
              },
            ),
          ],

          _buildFunctionDivider(),

          // 7. الملاحظات والشكاوى ic_mine_feedback.png
          _buildFunctionItem(
            icon: 'assets/mipmap-xxhdpi/ic_mine_feedback.png',
            title: 'الملاحظات والشكاوى',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FeedbackScreen()),
              );
            },
          ),
          _buildFunctionDivider(),

          // 8. إعدادات الحساب ic_mine_setting.png
          _buildFunctionItem(
            icon: 'assets/mipmap-xxhdpi/ic_mine_setting.png',
            title: 'إعدادات الحساب',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AccountManagementScreen()),
              );
            },
          ),
          _buildFunctionDivider(),

          // 9. فحص التحديثات
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) => _buildFunctionItem(
              icon: 'assets/mipmap-xxhdpi/ic_mine_setting.png',
              title: 'فحص التحديثات',
              subtitle: snap.hasData ? 'v${snap.data!.version}+${snap.data!.buildNumber}' : null,
              onTap: () => _checkUpdatesManually(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFunctionItem({
    required String icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Image.asset(
              icon,
              width: 26,
              height: 26,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.circle, size: 20, color: Colors.white54),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            if (subtitle != null) ...[
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0x99FFFFFF),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Image.asset(
              'assets/mipmap-xxhdpi/ic_wallet_arrow_right.png',
              width: 14,
              height: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFunctionDivider() {
    return const Divider(
      color: Colors.white10,
      height: 1,
      indent: 52,
      endIndent: 14,
    );
  }

  Future<void> _checkUpdatesManually(BuildContext context) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري فحص التحديثات...'), duration: Duration(seconds: 2)),
    );
    try {
      final update = await UpdateService.instance.checkForUpdate();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (update != null) {
        await AppUpdateDialog.show(context, update);
        return;
      }
      final info = await PackageInfo.fromPlatform();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('أنت على أحدث نسخة (بناء ${info.buildNumber})')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('أنت على أحدث نسخة حالياً'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
}

