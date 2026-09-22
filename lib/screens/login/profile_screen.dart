import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../config/r.dart';
import '../../services/dynamic_config_service.dart';
import '../../providers/user_provider.dart';
import '../../services/level_service.dart';
import '../../services/supabase_service.dart';
import '../../services/update_service.dart';
import '../../widgets/app_update_dialog.dart';
import '../../widgets/user_id_widget.dart';
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


class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.currentUser;
    final bgImg = DynamicConfigService().profileBackgroundImage;

    return Container(
      decoration: BoxDecoration(
        color: DynamicConfigService().profileBackgroundColor,
        image: bgImg.isNotEmpty
            ? DecorationImage(
                image: R.cachedImage(bgImg),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 80),
            child: Column(
              children: [
                _buildInfoSection(context, user),
                _buildDataSection(context),
                _buildWalletSection(context, user),
                _buildVipSection(context),
                _buildSettingsSection(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
        size: 122,
        fit: BoxFit.contain,
      );
    }
    return const SizedBox();
  }

  Widget _buildInfoSection(BuildContext context, dynamic user) {
    return Stack(
      children: [
        R.image(R.mineTopBg,
          width: double.infinity,
          fit: BoxFit.fitWidth,
        ),
        Column(
          children: [
            const SizedBox(height: 56),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const EditProfileScreen(),
                        ),
                      );
                    },
                    child: R.image(R.mineBtnEditIc,
                      width: 24,
                      height: 24,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const UserProfileScreen(),
                  ),
                );
              },
              child: SizedBox(
                width: 122,
                height: 122,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    R.image(R.mineAvatarIc,
                      width: 122,
                      height: 122,
                    ),
                    Container(
                      width: 92,
                      height: 92,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(BorderSide.none),
                      ),
                      child: ClipOval(
                        child: (user?.photoUrl != null && user?.photoUrl != '')
                            ? Image(
                                image: R.cachedImage(user.photoUrl),
                                fit: BoxFit.cover,
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
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  user?.name ?? 'اسم المستخدم',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF16151A),
                  ),
                ),
                const SizedBox(width: 2),
                R.image(
                  (user?.gender == 'female')
                      ? R.icSexGirl
                      : R.icSexBoy,
                  width: 18,
                  height: 16,
                ),
              ],
            ),
            const SizedBox(height: 7),
            UserIdWidget(
              idText: user?.customId?.isNotEmpty == true
                  ? user!.customId
                  : ((1000000 + (user?.uid.hashCode.abs() ?? 0) % 9000000).toString()),
              countryCode: user?.country,
            ),
            const SizedBox(height: 8),
            _buildLevelDisplay(user),
          ],
        ),
      ],
    );
  }

  Widget _buildLevelDisplay(dynamic user) {
    final hasVip = (user?.ownedVipItems != null && (user.ownedVipItems as List).isNotEmpty) ||
        (user?.activeNecklace != null && user.activeNecklace.toString().isNotEmpty) ||
        (user?.rechargeLevel != null && (user.rechargeLevel as int) > 1) ||
        (user?.rechargeExp != null && (user.rechargeExp as int) > 0);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (hasVip) ...[
                _buildVipNecklace(user),
                const SizedBox(width: 8),
              ],
              _levelIcon(user?.wealthLevel ?? 1, 'wealth'),
              const SizedBox(width: 8),
              _levelIcon(user?.rechargeLevel ?? 1, 'recharge'),
            ],
          ),
        ),
        _buildBadgesRow(user),
      ],
    );
  }

  Widget _buildVipNecklace(dynamic user) {
    String necklace = user?.activeNecklace?.toString() ?? '';
    if (necklace.isEmpty) {
      final lvl = ((user?.rechargeLevel ?? 1) as int).clamp(1, 5);
      necklace = 'assets/svga/v${lvl}_left_bottom.svga';
    }
    return SizedBox(
      width: 28,
      height: 28,
      child: SvgaFrame(
        svgaPath: necklace,
        size: 28,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildBadgesRow(dynamic user) {
    final badges = (user?.ownedBadges as List<String>?) ?? [];
    if (badges.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        alignment: WrapAlignment.center,
        children: badges.take(4).map((badgeId) {
          final storeItem = SupabaseService().getStoreItemSync(badgeId);
          final iconUrl = storeItem?.iconAsset ?? storeItem?.svgaAsset;
          if (iconUrl == null || iconUrl.isEmpty) return const SizedBox();
          return SizedBox(
            width: 22,
            height: 22,
            child: iconUrl.endsWith('.svga')
                ? SvgaFrame(svgaPath: iconUrl, size: 22)
                : Image.network(iconUrl, width: 22, height: 22, errorBuilder: (_, __, ___) => const SizedBox()),
          );
        }).toList(),
      ),
    );
  }

  Widget _levelIcon(int level, String type) {
    final config = LevelService().getLevelConfig(type, level);
    final url = config?.imageUrl;
    if (url != null) {
      return SizedBox(
        width: 48,
        height: 48,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: R.loadAsset(url),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFD700), width: 1),
      ),
      child: Text(
        'Lv.$level',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF16151A)),
      ),
    );
  }


  Widget _buildDataSection(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.currentUser;
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildDataItem('${user?.following ?? 0}', 'المتابَعين', () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FollowRecentScreen(
                    initialTab: 0,
                    targetUid: user?.uid,
                  ),
                ),
              );
            }),
          ),
          Expanded(
            child: _buildDataItem('${user?.followers ?? 0}', 'المعجبين', () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FollowRecentScreen(
                    initialTab: 1,
                    targetUid: user?.uid,
                  ),
                ),
              );
            }),
          ),
          Expanded(
            child: _buildDataItem('${user?.visitors ?? 0}', 'الزائرين', () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FollowRecentScreen(
                    initialTab: 2,
                    targetUid: user?.uid,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildDataItem(String count, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              count,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF16151A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF9BA1B6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletSection(BuildContext context, dynamic user) {
    return Container(
      margin: const EdgeInsets.only(top: 16, left: 16, right: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildMenuItem(
            R.mineWalletIc,
            'الحقيبة',
            'اشحن الآن',
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const WalletMainScreen(),
                ),
              );
            },
          ),
          Container(
            height: 1,
            color: Colors.grey[200],
            margin: const EdgeInsets.symmetric(horizontal: 16),
          ),
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
              R.image(R.commonGoldIc3,
                width: 24,
                height: 24,
              ),
                const SizedBox(width: 8),
                Text(
                  user?.coins?.toString() ?? '1,234,567',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF16151A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVipSection(BuildContext context) {
    return GestureDetector(
      onTap: () => _openVip(context),
      child: Container(
        margin: const EdgeInsets.only(top: 12, left: 16, right: 16),
        width: double.infinity,
        height: 64,
        child: Stack(
          children: [
            SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: R.image(R.mineVipCenterBg,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              left: 20,
              top: 0,
              bottom: 0,
              child: Row(
                children: [
                  R.image(R.mineMallTabVipIc,
                    width: 24,
                    height: 24,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'VIP Center',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFAE9B5),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Row(
                children: [
                  R.image(R.mineVipLabelIc,
                    width: 56,
                    height: 56,
                  ),
                  const SizedBox(width: 4),
                  R.image(R.mineVipGo,
                    width: 16,
                    height: 16,
                  ),
                ],
              ),
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
      final introUrl = res?['intro_video_url']?.toString();
      if (introUrl != null && introUrl.isNotEmpty) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => VipIntroScreen(videoUrl: introUrl),
        ));
        return;
      }
    } catch (_) {}
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => const VipCenterScreen(),
    ));
  }

  Widget _buildSettingsSection(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.currentUser;
    return Container(
      margin: const EdgeInsets.only(top: 12, left: 16, right: 16),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildMenuItem(
            'assets/images/tasks/ic_me_menu_task_center.png',
            'مركز المهام والمكافآت',
            '🌟 كوينز وجوائز يومية',
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DailyTasksScreen()),
              );
            },
          ),
          _buildDivider(),
          _buildMenuItem(
            R.mineCpIc,
            'علاقات CP',
            null,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CpSpaceScreen()),
              );
            },
          ),
          _buildDivider(),
          _buildMenuItem(
            R.mineUnionIc,
            'وكالة المضيفين (إدارة الوكالة)',
            null,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HostAgencyScreen()),
              );
            },
          ),
          if (user?.isRechargeAgent == true) ...[
            _buildDivider(),
            _buildMenuItem(
              R.mineUnionIc,
              'وكالة الشحن والرواتب',
              null,
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AgentRechargePortalScreen()),
                );
              },
            ),
          ],
          _buildDivider(),
          _buildMenuItem(
            R.mineLevelIc,
            'المستوى',
            'Lv.${user?.level ?? 1}',
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LevelScreen()),
              );
            },
          ),
          _buildDivider(),
          _buildMenuItem(
            R.mineLevelIc,
            'الشارات',
            null,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const BadgesScreen()),
              );
            },
          ),
          _buildMenuItem(
            R.mineMallIc,
            'المتجر',
            null,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MallScreen()),
              );
            },
          ),
          _buildDivider(),
          _buildMenuItem(
            R.icSigningOk,
            'المكافآت اليومية',
            null,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const WeeklySigninScreen()),
              );
            },
          ),
          _buildDivider(),
          _buildMenuItem(
            R.mineBackpackIc,
            'الحقيبة',
            null,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const BackpackScreen()),
              );
            },
          ),
          _buildDivider(),
          _buildMenuItem(
            R.mineFeedbackIc,
            'الشكوى والاقتراحات',
            null,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FeedbackScreen()),
              );
            },
          ),
          _buildDivider(),
          _buildMenuItem(
            R.mineSettingIc,
            'الإعدادات',
            null,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AccountManagementScreen(),
                ),
              );
            },
          ),
          _buildDivider(),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) => _buildMenuItem(
              R.mineFeedbackIc,
              'فحص التحديثات',
              snap.hasData ? 'v${snap.data!.version}+${snap.data!.buildNumber}' : null,
              () => _checkUpdatesManually(context),
            ),
          ),
          _buildDivider(),
          FutureBuilder<DocumentSnapshot>(
            future: user != null
                ? FirebaseFirestore.instance.collection('admin_users').doc(user.uid).get()
                : Future.value(null),
            builder: (context, snap) {
              final isAdmin = snap.data?.exists ?? false;
              return const SizedBox.shrink();
            },
          ),

        ],
      ),
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

  Widget _buildMenuItem(
    String iconPath,
    String title,
    String? subtitle,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            R.image(iconPath, width: 44, height: 44),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF16151A),
              ),
            ),
            const Spacer(),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9BA1B6),
                  ),
                ),
              ),
            R.image(R.commonNext4Ic, width: 16, height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 1,
      color: Colors.grey[200],
      margin: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}
