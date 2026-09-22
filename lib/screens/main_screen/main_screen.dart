import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../providers/user_provider.dart';
import '../../services/dynamic_config_service.dart';
import '../../services/update_service.dart';
import '../../l10n/app_localizations.dart';
import '../discover/room_discover_screen.dart';
import '../message/message_screen.dart';
import '../login/profile_screen.dart';
import '../room/widgets/svga_player.dart';
import '../../widgets/app_update_dialog.dart';
import '../../features/signin/weekly_signin_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  late PageController _pageController;
  int _currentIndex = 0;
  Timer? _updatePoll;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    WidgetsBinding.instance.addObserver(this);
    // Check for updates and daily checkin immediately after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdate();
      WeeklySigninScreen.showIfNeeded(context);
    });
    // Periodic update check while the app is open (splash only checks cold start)
    _updatePoll = Timer.periodic(const Duration(minutes: 15), (_) => _checkUpdate());
  }

  Future<void> _checkUpdate() async {
    if (_checkingUpdate) return;
    _checkingUpdate = true;
    try {
      final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
      final update = await UpdateService.instance.checkForUpdate();
      if (update != null && mounted) {
        await AppUpdateDialog.show(context, update);
        if (uid != null && mounted) {
          await Provider.of<UserProvider>(context, listen: false).loadUser(uid);
        }
      }
    } catch (_) {} finally {
      _checkingUpdate = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkUpdate();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updatePoll?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: DynamicConfigService(),
      builder: (context, _) {
        final pages = <Widget>[
          RoomDiscoverScreen(),
          MessageScreen(),
          ProfileScreen(),
        ];
        return Scaffold(
          backgroundColor: const Color(0xFFFFFFFF),
          body: PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            children: pages,
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      DynamicConfigService().bottomNavGradientStart,
                      DynamicConfigService().bottomNavGradientEnd,
                    ],
                  ),
                  image: DynamicConfigService().bottomNavBgImage.isNotEmpty
                      ? DecorationImage(
                          image: R.cachedImage(DynamicConfigService().bottomNavBgImage),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildNavItem(
                          index: 0,
                          normalIcon: R.tabDiscoverNor,
                          selectedIcon: R.tabDiscoverPre,
                          label: l10n.tabDiscover,
                        ),
                        _buildNavItem(
                          index: 1,
                          normalIcon: R.tabMessageNor,
                          selectedIcon: R.tabMessagePre,
                          label: l10n.tabMessage,
                        ),
                        _buildNavItem(
                          index: 2,
                          normalIcon: R.tabMineNor,
                          selectedIcon: R.tabMinePre,
                          label: l10n.tabProfile,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _navIconWidget(String iconPath) {
    if (iconPath.endsWith('.svga') || iconPath.endsWith('.vap')) {
      return SvgaPlayer(
        assetPath: iconPath,
        width: 48,
        height: 48,
        fit: BoxFit.contain,
      );
    }
    return R.image(iconPath, width: 48, height: 48, fit: BoxFit.contain);
  }

  Widget _buildNavItem({
    required int index,
    required String normalIcon,
    required String selectedIcon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _currentIndex = index);
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      },
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: _navIconWidget(isSelected ? selectedIcon : normalIcon),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
                color: isSelected 
                    ? DynamicConfigService().bottomNavActiveTextColor 
                    : DynamicConfigService().bottomNavInactiveTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
